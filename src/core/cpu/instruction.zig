const std = @import("std");
const utils = @import("../../utils.zig");
const cpuZig = @import("../cpu.zig");
const math = @import("math.zig");
const register = @import("./register.zig");
const ram = @import("./ram.zig");

const Cpu = cpuZig.Cpu;

const Registers = register.Registers;
const Register8 = register.Register8;
const Register16 = register.Register16;
const Register16Memory = register.Register16Memory;

const Memory = ram.Memory;

const InstructionMetadata = struct {
    name: []const u8, // Name of the instruction
    cycles: u8, // Number of cycles the instruction takes
};

const Instruction = struct {
    execute: *const fn (cpu: *Cpu) void,
    metadata: InstructionMetadata,
};

fn Unimplemented(comptime code: u8) Instruction {
    @setEvalBranchQuota(200_000);
    const logFmt = std.fmt.comptimePrint("Unimplemented instruction executed: 0x{X:02}", .{code});
    const nameFmt = std.fmt.comptimePrint("UNIMPLEMENTED(0x{X:02})", .{code});

    const inner = struct {
        fn logger(_: *Cpu) void {
            utils.log.warn(logFmt, .{});
        }
    };

    return .{
        .execute = inner.logger,
        .metadata = InstructionMetadata{
            .name = nameFmt,
            .cycles = 0,
        },
    };
}

inline fn getReg8(cpu: *const Cpu, reg: Register8) u8 {
    return cpu.reg.get8(reg);
}

inline fn getReg16(cpu: *const Cpu, reg: Register16) u16 {
    return cpu.reg.get16(reg);
}

fn getMemory(comptime postOp: fn (u16) callconv(.@"inline") u16) fn (*Cpu, Register16Memory) callconv(.@"inline") u8 {
    const _inner = struct {
        inline fn execute(cpu: *const Cpu, reg: Register16Memory) u8 {
            const address = cpu.reg.get16(reg.asReg16());
            defer {
                const new_address = postOp(address);
                cpu.reg.set16(reg.asReg16(), new_address);
            }

            return cpu.ram.readByte(address);
        }
    };

    return _inner.execute;
}

inline fn setReg8(cpu: *Cpu, reg: Register8, value: u8) void {
    cpu.reg.set8(reg, value);
}

inline fn setReg16(cpu: *Cpu, reg: Register16, value: u16) void {
    cpu.reg.set16(reg, value);
}

fn setMemory(comptime postOp: fn (u16) callconv(.@"inline") u16) fn (*Cpu, Register16Memory, u8) callconv(.@"inline") void {
    const _inner = struct {
        inline fn execute(cpu: *Cpu, reg: Register16Memory, value: u8) void {
            const address = cpu.reg.get16(reg.asReg16());
            defer {
                const new_address = postOp(address);
                cpu.reg.set16(reg.asReg16(), new_address);
            }
            cpu.ram.writeByte(address, value);
        }
    };

    return _inner.execute;
}

const RegisterMemoryOperation = enum {
    inc,
    dec,

    inline fn asPostOp(self: RegisterMemoryOperation) fn (value: u16) callconv(.@"inline") u16 {
        switch (self) {
            .inc => return _inc,
            .dec => return _dec,
        }
    }

    fn asText(self: RegisterMemoryOperation, reg: RM) []const u8 {
        const op_char = comptime blk: {
            switch (self) {
                .inc => break :blk "+",
                .dec => break :blk "-",
            }
        };
        comptime {
            const reg16 = reg.asReg16();
            return std.fmt.comptimePrint("({s}{s})", .{
                reg16.asText(),
                op_char,
            });
        }
    }

    inline fn _inc(value: u16) u16 {
        return value + 1;
    }

    inline fn _dec(value: u16) u16 {
        return value - 1;
    }

    inline fn _nop(value: u16) u16 {
        return value;
    }
};

const R8 = Register8;
const R16 = Register16;
const RM = Register16Memory;
const RMO = struct {
    reg: Register16Memory,
    op: RegisterMemoryOperation,

    const hl_inc = RMO{
        .reg = RM.hl,
        .op = .inc,
    };

    const hl_dec = RMO{
        .reg = RM.hl,
        .op = .dec,
    };
};

fn regAsText(reg: anytype) []const u8 {
    comptime {
        const regType = @TypeOf(reg);

        switch (regType) {
            R8 or R16 or RM => {
                return reg.asText();
            },
            RMO => {
                return reg.op.asText(reg.reg);
            },
            else => {
                @compileError("Unsupported register type");
            },
        }
    }
}

const op = struct {
    fn nop_00(cpu: *Cpu) void {
        utils.log.debug("NOP executed", .{});
        _ = cpu; // unused
    }

    fn inc(comptime reg: anytype) Instruction {
        const T = @TypeOf(reg);

        const targetInt, const handleFlags, const getFn, const setFn, const cycles = comptime blk: {
            if (T == R8) {
                break :blk .{ u8, true, getReg8, setReg8, 1 };
            } else if (T == R16) {
                break :blk .{ u16, false, getReg16, setReg16, 2 };
            } else if (T == RM) {
                break :blk .{ u8, true, getMemory(RegisterMemoryOperation._nop), setMemory(RegisterMemoryOperation._nop), 3 };
            } else {
                @compileError("reg must be of type Register8 or Register16");
            }
        };

        const _inline = struct {
            fn execute(cpu: *Cpu) void {
                const value = getFn(cpu, reg);

                const result = math.checkCarryAdd(targetInt, value, 1);

                if (handleFlags) {
                    // Flags Z0H-
                    var flags = cpu.reg.single.f;
                    flags.z = result.value == 0;
                    flags.n = false;
                    flags.h = result.halfCarry;
                    cpu.reg.single.f = flags;
                } else {
                    // Flags ----
                }

                setFn(cpu, reg, result.value);
            }
        };

        return .{ .execute = _inline.execute, .metadata = .{
            .cycles = cycles,
            .name = std.fmt.comptimePrint("INC {s}", .{register.asText(reg)}),
        } };
    }

    fn dec(comptime reg: anytype) Instruction {
        const T = @TypeOf(reg);

        const targetInt, const handleFlags, const getFn, const setFn, const cycles = comptime blk: {
            if (T == R8) {
                break :blk .{ u8, true, getReg8, setReg8, 1 };
            } else if (T == R16) {
                break :blk .{ u16, false, getReg16, setReg16, 2 };
            } else if (T == RM) {
                break :blk .{ u8, true, getMemory(RegisterMemoryOperation._nop), setMemory(RegisterMemoryOperation._nop), 3 };
            } else {
                @compileError("reg must be of type Register8 or Register16");
            }
        };

        const _inline = struct {
            fn execute(cpu: *Cpu) void {
                const value = getFn(cpu, reg);

                const result = math.checkBorrowSub(targetInt, value, 1);

                if (handleFlags) {
                    // Flags Z0H-
                    var flags = cpu.reg.single.f;
                    flags.z = result.value == 0;
                    flags.n = true;
                    flags.h = result.halfBorrow;
                    cpu.reg.single.f = flags;
                } else {
                    // Flags ----
                }

                setFn(cpu, reg, result.value);
            }
        };

        return .{ .execute = _inline.execute, .metadata = .{
            .cycles = cycles,
            .name = std.fmt.comptimePrint("DEC {s}", .{register.asText(reg)}),
        } };
    }

    fn load(comptime dest: anytype, comptime source: anytype) Instruction {
        const TS = @TypeOf(source);
        const TD = @TypeOf(dest);

        const getSrc, const sourceReg, const cycleSrc = comptime blkS: {
            switch (TS) {
                R8 => break :blkS .{ getReg8, source, 1 },
                R16 => break :blkS .{ getReg16, source, 1 },
                RM => break :blkS .{ getMemory(RegisterMemoryOperation._nop), source, 2 },
                RMO => break :blkS .{ getMemory(source.op.asPostOp()), source.reg, 2 },
                else => @compileError("source must be of type R8, R16, RM, or RMO"),
            }
        };

        const setDst, const destReg, const cycleDst = comptime blkD: {
            switch (TD) {
                R8 => break :blkD .{ setReg8, dest, 1 },
                R16 => break :blkD .{ setReg16, dest, 1 },
                RM => break :blkD .{ setMemory(RegisterMemoryOperation._nop), dest, 2 },
                RMO => break :blkD .{ setMemory(dest.op.asPostOp()), dest.reg, 2 },
                else => @compileError("dest must be of type R8, R16, RM, or RMO"),
            }
        };

        const cycle = cycleSrc * cycleDst; // Tiny hack because cycles are 1 or 2.

        const _inline = struct {
            fn execute(cpu: *Cpu) void {
                const value = getSrc(cpu, sourceReg);
                setDst(cpu, destReg, value);

                // Flags ----

            }
        };

        return .{
            .execute = _inline.execute,
            .metadata = .{
                .cycles = cycle,
                .name = std.fmt.comptimePrint(
                    "LD {s}, {s}",
                    .{ register.asText(destReg), register.asText(sourceReg) },
                ),
            },
        };
    }
};

const _NOP_00: Instruction = .{
    .execute = op.nop_00,
    .metadata = InstructionMetadata{
        .name = "NOP",
        .cycles = 1,
    },
};

const _LD_02_: Instruction = op.load(RM.bc, R8.a);
const _LD_12_: Instruction = op.load(RM.de, R8.a);
const _LD_22_: Instruction = op.load(RMO.hl_inc, R8.a);
const _LD_32_: Instruction = op.load(RMO.hl_dec, R8.a);

const _INC_03: Instruction = op.inc(R16.bc);
const _INC_13: Instruction = op.inc(R16.de);
const _INC_23: Instruction = op.inc(R16.hl);
const _INC_33: Instruction = op.inc(R16.sp);

const _INC_04: Instruction = op.inc(R8.b);
const _INC_14: Instruction = op.inc(R8.d);
const _INC_24: Instruction = op.inc(R8.h);
const _INC_34: Instruction = op.inc(RM.hl);

const _DEC_05: Instruction = op.dec(R8.b);
const _DEC_15: Instruction = op.dec(R8.d);
const _DEC_25: Instruction = op.dec(R8.h);
const _DEC_35: Instruction = op.dec(RM.hl);

const _LD_0A_: Instruction = op.load(R8.a, RM.bc);
const _LD_1A_: Instruction = op.load(R8.a, RM.de);
const _LD_2A_: Instruction = op.load(R8.a, RMO.hl_inc);
const _LD_3A_: Instruction = op.load(R8.a, RMO.hl_dec);

const _DEC_0B: Instruction = op.dec(R16.bc);
const _DEC_1B: Instruction = op.dec(R16.de);
const _DEC_2B: Instruction = op.dec(R16.hl);
const _DEC_3B: Instruction = op.dec(R16.sp);

const _INC_0C: Instruction = op.inc(R8.c);
const _INC_1C: Instruction = op.inc(R8.e);
const _INC_2C: Instruction = op.inc(R8.l);
const _INC_3C: Instruction = op.inc(R8.a);

const _DEC_0D: Instruction = op.dec(R8.c);
const _DEC_1D: Instruction = op.dec(R8.e);
const _DEC_2D: Instruction = op.dec(R8.l);
const _DEC_3D: Instruction = op.dec(R8.a);

const _LD_40_: Instruction = op.load(R8.b, R8.b);
const _LD_50_: Instruction = op.load(R8.d, R8.b);
const _LD_60_: Instruction = op.load(R8.h, R8.b);
const _LD_70_: Instruction = op.load(RM.hl, R8.b);

const _LD_41_: Instruction = op.load(R8.b, R8.c);
const _LD_51_: Instruction = op.load(R8.d, R8.c);
const _LD_61_: Instruction = op.load(R8.h, R8.c);
const _LD_71_: Instruction = op.load(RM.hl, R8.c);

const _LD_42_: Instruction = op.load(R8.b, R8.d);
const _LD_52_: Instruction = op.load(R8.d, R8.d);
const _LD_62_: Instruction = op.load(R8.h, R8.d);
const _LD_72_: Instruction = op.load(RM.hl, R8.d);

const _LD_43_: Instruction = op.load(R8.b, R8.e);
const _LD_53_: Instruction = op.load(R8.d, R8.e);
const _LD_63_: Instruction = op.load(R8.h, R8.e);
const _LD_73_: Instruction = op.load(RM.hl, R8.e);

const _LD_44_: Instruction = op.load(R8.b, R8.h);
const _LD_54_: Instruction = op.load(R8.d, R8.h);
const _LD_64_: Instruction = op.load(R8.h, R8.h);
const _LD_74_: Instruction = op.load(RM.hl, R8.h);

const _LD_45_: Instruction = op.load(R8.b, R8.l);
const _LD_55_: Instruction = op.load(R8.d, R8.l);
const _LD_65_: Instruction = op.load(R8.h, R8.l);
const _LD_75_: Instruction = op.load(RM.hl, R8.l);

const _LD_46_: Instruction = op.load(R8.b, RM.hl);
const _LD_56_: Instruction = op.load(R8.d, RM.hl);
const _LD_66_: Instruction = op.load(R8.h, RM.hl);
// const _LD_76_: Instruction = op.halt; // HALT instruction

const _LD_47_: Instruction = op.load(R8.b, R8.a);
const _LD_57_: Instruction = op.load(R8.d, R8.a);
const _LD_67_: Instruction = op.load(R8.h, R8.a);
const _LD_77_: Instruction = op.load(RM.hl, R8.a);

const _LD_48_: Instruction = op.load(R8.c, R8.b);
const _LD_58_: Instruction = op.load(R8.e, R8.b);
const _LD_68_: Instruction = op.load(R8.l, R8.b);
const _LD_78_: Instruction = op.load(R8.a, R8.b);

const _LD_49_: Instruction = op.load(R8.c, R8.c);
const _LD_59_: Instruction = op.load(R8.e, R8.c);
const _LD_69_: Instruction = op.load(R8.l, R8.c);
const _LD_79_: Instruction = op.load(R8.a, R8.c);

const _LD_4A_: Instruction = op.load(R8.c, R8.d);
const _LD_5A_: Instruction = op.load(R8.e, R8.d);
const _LD_6A_: Instruction = op.load(R8.l, R8.d);
const _LD_7A_: Instruction = op.load(R8.a, R8.d);

const _LD_4B_: Instruction = op.load(R8.c, R8.e);
const _LD_5B_: Instruction = op.load(R8.e, R8.e);
const _LD_6B_: Instruction = op.load(R8.l, R8.e);
const _LD_7B_: Instruction = op.load(R8.a, R8.e);

const _LD_4C_: Instruction = op.load(R8.c, R8.h);
const _LD_5C_: Instruction = op.load(R8.e, R8.h);
const _LD_6C_: Instruction = op.load(R8.l, R8.h);
const _LD_7C_: Instruction = op.load(R8.a, R8.h);

const _LD_4D_: Instruction = op.load(R8.c, R8.l);
const _LD_5D_: Instruction = op.load(R8.e, R8.l);
const _LD_6D_: Instruction = op.load(R8.l, R8.l);
const _LD_7D_: Instruction = op.load(R8.a, R8.l);

const _LD_4E_: Instruction = op.load(R8.c, RM.hl);
const _LD_5E_: Instruction = op.load(R8.e, RM.hl);
const _LD_6E_: Instruction = op.load(R8.l, RM.hl);
const _LD_7E_: Instruction = op.load(R8.a, RM.hl);

const _LD_4F_: Instruction = op.load(R8.c, R8.a);
const _LD_5F_: Instruction = op.load(R8.e, R8.a);
const _LD_6F_: Instruction = op.load(R8.l, R8.a);
const _LD_7F_: Instruction = op.load(R8.a, R8.a);

const U = Unimplemented;
const OPCODES: [256]Instruction = .{
    //0x00,  0x01,    0x02,    0x03,    0x04,    0x05,    0x06,    0x07,    0x08,    0x09,    0x0A,    0x0B,    0x0C,    0x0D,    0x0E,    0x0F,
    _NOP_00, U(0x01), _LD_02_, _INC_03, _INC_04, _DEC_05, U(0x06), U(0x07), U(0x08), U(0x09), _LD_0A_, _DEC_0B, _INC_0C, _DEC_0D, U(0x0E), U(0x0F), // 0x00
    U(0x10), U(0x11), _LD_12_, _INC_13, _INC_14, _DEC_15, U(0x16), U(0x17), U(0x18), U(0x19), _LD_1A_, _DEC_1B, _INC_1C, _DEC_1D, U(0x1E), U(0x1F), // 0x10
    U(0x20), U(0x21), _LD_22_, _INC_23, _INC_24, _DEC_25, U(0x26), U(0x27), U(0x28), U(0x29), _LD_2A_, _DEC_2B, _INC_2C, _DEC_2D, U(0x2E), U(0x2F), // 0x20
    U(0x30), U(0x31), _LD_32_, _INC_33, _INC_34, _DEC_35, U(0x36), U(0x37), U(0x38), U(0x39), _LD_3A_, _DEC_3B, _INC_3C, _DEC_3D, U(0x3E), U(0x3F), // 0x30
    _LD_40_, _LD_41_, _LD_42_, _LD_43_, _LD_44_, _LD_45_, _LD_46_, _LD_47_, _LD_48_, _LD_49_, _LD_4A_, _LD_4B_, _LD_4C_, _LD_4D_, _LD_4E_, _LD_4F_, // 0x40
    _LD_50_, _LD_51_, _LD_52_, _LD_53_, _LD_54_, _LD_55_, _LD_56_, _LD_57_, _LD_58_, _LD_59_, _LD_5A_, _LD_5B_, _LD_5C_, _LD_5D_, _LD_5E_, _LD_5F_, // 0x50
    _LD_60_, _LD_61_, _LD_62_, _LD_63_, _LD_64_, _LD_65_, _LD_66_, _LD_67_, _LD_68_, _LD_69_, _LD_6A_, _LD_6B_, _LD_6C_, _LD_6D_, _LD_6E_, _LD_6F_, // 0x60
    _LD_70_, _LD_71_, _LD_72_, _LD_73_, _LD_74_, _LD_75_, U(0x76), _LD_77_, _LD_78_, _LD_79_, _LD_7A_, _LD_7B_, _LD_7C_, _LD_7D_, _LD_7E_, _LD_7F_, // 0x70
    U(0x80), U(0x81), U(0x82), U(0x83), U(0x84), U(0x85), U(0x86), U(0x87), U(0x88), U(0x89), U(0x8A), U(0x8B), U(0x8C), U(0x8D), U(0x8E), U(0x8F), // 0x80
    U(0x90), U(0x91), U(0x92), U(0x93), U(0x94), U(0x95), U(0x96), U(0x97), U(0x98), U(0x99), U(0x9A), U(0x9B), U(0x9C), U(0x9D), U(0x9E), U(0x9F), // 0x90
    U(0xA0), U(0xA1), U(0xA2), U(0xA3), U(0xA4), U(0xA5), U(0xA6), U(0xA7), U(0xA8), U(0xA9), U(0xAA), U(0xAB), U(0xAC), U(0xAD), U(0xAE), U(0xAF), // 0xA0
    U(0xB0), U(0xB1), U(0xB2), U(0xB3), U(0xB4), U(0xB5), U(0xB6), U(0xB7), U(0xB8), U(0xB9), U(0xBA), U(0xBB), U(0xBC), U(0xBD), U(0xBE), U(0xBF), // 0xB0
    U(0xC0), U(0xC1), U(0xC2), U(0xC3), U(0xC4), U(0xC5), U(0xC6), U(0xC7), U(0xC8), U(0xC9), U(0xCA), U(0xCB), U(0xCC), U(0xCD), U(0xCE), U(0xCF), // 0xC0
    U(0xD0), U(0xD1), U(0xD2), U(0xD3), U(0xD4), U(0xD5), U(0xD6), U(0xD7), U(0xD8), U(0xD9), U(0xDA), U(0xDB), U(0xDC), U(0xDD), U(0xDE), U(0xDF), // 0xD0
    U(0xE0), U(0xE1), U(0xE2), U(0xE3), U(0xE4), U(0xE5), U(0xE6), U(0xE7), U(0xE8), U(0xE9), U(0xEA), U(0xEB), U(0xEC), U(0xED), U(0xEE), U(0xEF), // 0xE0
    U(0xF0), U(0xF1), U(0xF2), U(0xF3), U(0xF4), U(0xF5), U(0xF6), U(0xF7), U(0xF8), U(0xF9), U(0xFA), U(0xFB), U(0xFC), U(0xFD), U(0xFE), U(0xFF), // 0xF0
};

test "opcode NOP" {
    var cpu: Cpu = .{};

    const opcode = OPCODES[0x00];
    opcode.execute(&cpu);
}

test "opcode unimplemented" {
    var cpu: Cpu = .{};

    const opcode = OPCODES[0xC3]; // This should stays unimplemented
    opcode.execute(&cpu);

    std.debug.print("Opcode name: {s}\n", .{opcode.metadata.name});

    try std.testing.expectEqualStrings(opcode.metadata.name, "UNIMPLEMENTED(0xC3)");
}

test "opcode INC16" {
    var cpu: Cpu = .{};
    cpu.reg.set16(.bc, 0xFFFF);

    const opcode = OPCODES[0x03]; // INC BC
    opcode.execute(&cpu);

    try std.testing.expect(cpu.reg.get16(.bc) == 0x0000);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == false);
    try std.testing.expect(cpu.reg.single.f.c == false);
}

test "opcode INC Memory" {
    var cpu: Cpu = .{};

    const addr: u16 = 0x2000;

    cpu.reg.set16(.hl, addr);
    cpu.ram.writeByte(addr, 0xFE);

    const inc_opcode = OPCODES[0x34]; // INC (HL)
    const dec_opcode = OPCODES[0x35]; // DEC (HL)

    inc_opcode.execute(&cpu);
    try std.testing.expect(cpu.ram.readByte(addr) == 0xFF);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == false);
    try std.testing.expect(cpu.reg.single.f.c == false);

    inc_opcode.execute(&cpu);
    try std.testing.expect(cpu.ram.readByte(addr) == 0x00);
    try std.testing.expect(cpu.reg.single.f.z == true);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == true);
    try std.testing.expect(cpu.reg.single.f.c == false);

    dec_opcode.execute(&cpu);
    try std.testing.expect(cpu.ram.readByte(addr) == 0xFF);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == true);
    try std.testing.expect(cpu.reg.single.f.h == true);
    try std.testing.expect(cpu.reg.single.f.c == false);

    dec_opcode.execute(&cpu);
    try std.testing.expect(cpu.ram.readByte(addr) == 0xFE);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == true);
    try std.testing.expect(cpu.reg.single.f.h == false);
    try std.testing.expect(cpu.reg.single.f.c == false);
}

test "load" {
    var cpu = Cpu.init();

    cpu.reg.set8(Register8.a, 0x12);
    cpu.reg.set8(Register8.b, 0x00);

    const op_a_b = OPCODES[0x47]; // LD B, A
    op_a_b.execute(&cpu);

    try std.testing.expect(cpu.reg.get8(Register8.b) == 0x12);

    const op_b_hl = OPCODES[0x70]; // LD (HL), B
    const test_addr: u16 = 0x3000;
    cpu.reg.set16(Register16.hl, test_addr);

    op_b_hl.execute(&cpu);

    try std.testing.expect(cpu.ram.readByte(test_addr) == 0x12);

    const op_hl_a = OPCODES[0x7E]; // LD A, (HL)
    op_hl_a.execute(&cpu);

    try std.testing.expect(cpu.reg.single.a == 0x12);
}

test "load inc dec" {
    var cpu = Cpu.init();

    var test_addr: u16 = 0x4000;

    cpu.ram.writeByte(test_addr, 0x1A);
    cpu.ram.writeByte(test_addr + 1, 0x1B);
    cpu.reg.pair.hl = test_addr;

    const op_ld_hl_inc_a = OPCODES[0x2A]; // LD A, (HL+)
    op_ld_hl_inc_a.execute(&cpu);
    test_addr += 1;

    try std.testing.expect(cpu.reg.single.a == 0x1A);
    try std.testing.expect(cpu.reg.get16(Register16.hl) == test_addr);

    const op_ld_hl_dec_a = OPCODES[0x3A]; // LD A, (HL-)
    op_ld_hl_dec_a.execute(&cpu);
    test_addr -= 1;

    try std.testing.expect(cpu.reg.single.a == 0x1B);
    try std.testing.expect(cpu.reg.get16(Register16.hl) == test_addr);
}

test "opcode INC8 - all registers" {
    var cpu = Cpu.init();

    // Test INC B (0x04)
    cpu.reg.set8(.b, 0x0F);
    OPCODES[0x04].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.b) == 0x10);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == true); // Half carry from 0x0F to 0x10

    // Test INC C (0x0C)
    cpu.reg.set8(.c, 0xFF);
    OPCODES[0x0C].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.c) == 0x00);
    try std.testing.expect(cpu.reg.single.f.z == true);
    try std.testing.expect(cpu.reg.single.f.h == true);

    // Test INC D (0x14)
    cpu.reg.set8(.d, 0x42);
    OPCODES[0x14].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.d) == 0x43);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.h == false);

    // Test INC E (0x1C)
    cpu.reg.set8(.e, 0x1F);
    OPCODES[0x1C].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.e) == 0x20);
    try std.testing.expect(cpu.reg.single.f.h == true);

    // Test INC H (0x24)
    cpu.reg.set8(.h, 0x00);
    OPCODES[0x24].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.h) == 0x01);
    try std.testing.expect(cpu.reg.single.f.z == false);

    // Test INC L (0x2C)
    cpu.reg.set8(.l, 0xFE);
    OPCODES[0x2C].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.l) == 0xFF);

    // Test INC A (0x3C)
    cpu.reg.set8(.a, 0x7F);
    OPCODES[0x3C].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.a) == 0x80);
}

test "opcode DEC8 - all registers" {
    var cpu = Cpu.init();

    // Test DEC B (0x05)
    cpu.reg.set8(.b, 0x01);
    OPCODES[0x05].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.b) == 0x00);
    try std.testing.expect(cpu.reg.single.f.z == true);
    try std.testing.expect(cpu.reg.single.f.n == true);
    try std.testing.expect(cpu.reg.single.f.h == false);

    // Test DEC C (0x0D) - underflow
    cpu.reg.set8(.c, 0x00);
    OPCODES[0x0D].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.c) == 0xFF);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.h == true);

    // Test DEC D (0x15) - half borrow
    cpu.reg.set8(.d, 0x10);
    OPCODES[0x15].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.d) == 0x0F);
    try std.testing.expect(cpu.reg.single.f.h == true);

    // Test DEC E (0x1D)
    cpu.reg.set8(.e, 0x42);
    OPCODES[0x1D].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.e) == 0x41);
    try std.testing.expect(cpu.reg.single.f.h == false);

    // Test DEC H (0x25)
    cpu.reg.set8(.h, 0x80);
    OPCODES[0x25].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.h) == 0x7F);

    // Test DEC L (0x2D)
    cpu.reg.set8(.l, 0x20);
    OPCODES[0x2D].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.l) == 0x1F);

    // Test DEC A (0x3D)
    cpu.reg.set8(.a, 0x01);
    OPCODES[0x3D].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.a) == 0x00);
    try std.testing.expect(cpu.reg.single.f.z == true);
}

test "opcode INC16 - all registers" {
    var cpu = Cpu.init();

    // Test INC BC (0x03)
    cpu.reg.set16(.bc, 0x1234);
    OPCODES[0x03].execute(&cpu);
    try std.testing.expect(cpu.reg.get16(.bc) == 0x1235);

    // Test INC DE (0x13)
    cpu.reg.set16(.de, 0xFFFF);
    OPCODES[0x13].execute(&cpu);
    try std.testing.expect(cpu.reg.get16(.de) == 0x0000);

    // Test INC HL (0x23)
    cpu.reg.set16(.hl, 0x00FF);
    OPCODES[0x23].execute(&cpu);
    try std.testing.expect(cpu.reg.get16(.hl) == 0x0100);

    // Test INC SP (0x33)
    cpu.reg.set16(.sp, 0xFFFE);
    OPCODES[0x33].execute(&cpu);
    try std.testing.expect(cpu.reg.get16(.sp) == 0xFFFF);
}

test "opcode DEC16 - all registers" {
    var cpu = Cpu.init();

    // Test DEC BC (0x0B)
    cpu.reg.set16(.bc, 0x1000);
    OPCODES[0x0B].execute(&cpu);
    try std.testing.expect(cpu.reg.get16(.bc) == 0x0FFF);

    // Test DEC DE (0x1B)
    cpu.reg.set16(.de, 0x0000);
    OPCODES[0x1B].execute(&cpu);
    try std.testing.expect(cpu.reg.get16(.de) == 0xFFFF);

    // Test DEC HL (0x2B)
    cpu.reg.set16(.hl, 0x0100);
    OPCODES[0x2B].execute(&cpu);
    try std.testing.expect(cpu.reg.get16(.hl) == 0x00FF);

    // Test DEC SP (0x3B)
    cpu.reg.set16(.sp, 0x0001);
    OPCODES[0x3B].execute(&cpu);
    try std.testing.expect(cpu.reg.get16(.sp) == 0x0000);
}

test "opcode LD - register to register combinations" {
    var cpu = Cpu.init();

    // Set initial values
    cpu.reg.set8(.a, 0xAA);
    cpu.reg.set8(.b, 0xBB);
    cpu.reg.set8(.c, 0xCC);
    cpu.reg.set8(.d, 0xDD);
    cpu.reg.set8(.e, 0xEE);
    cpu.reg.set8(.h, 0x11);
    cpu.reg.set8(.l, 0x22);

    // Test LD B, C (0x41)
    OPCODES[0x41].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.b) == 0xCC);

    // Test LD D, E (0x53)
    OPCODES[0x53].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.d) == 0xEE);

    // Test LD H, A (0x67)
    OPCODES[0x67].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.h) == 0xAA);

    // Test LD A, L (0x7D)
    OPCODES[0x7D].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.a) == 0x22);

    // Test LD C, H (0x4C)
    OPCODES[0x4C].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.c) == 0xAA);
}

test "opcode LD - memory operations" {
    var cpu = Cpu.init();

    const addr: u16 = 0x5000;

    // Test LD (BC), A (0x02)
    cpu.reg.set16(.bc, addr);
    cpu.reg.set8(.a, 0x12);
    OPCODES[0x02].execute(&cpu);
    try std.testing.expect(cpu.ram.readByte(addr) == 0x12);

    // Test LD A, (BC) (0x0A)
    cpu.reg.set8(.a, 0x00);
    OPCODES[0x0A].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.a) == 0x12);

    // Test LD (DE), A (0x12)
    cpu.reg.set16(.de, addr + 1);
    cpu.reg.set8(.a, 0x34);
    OPCODES[0x12].execute(&cpu);
    try std.testing.expect(cpu.ram.readByte(addr + 1) == 0x34);

    // Test LD A, (DE) (0x1A)
    cpu.reg.set8(.a, 0x00);
    OPCODES[0x1A].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.a) == 0x34);

    // Test LD (HL), various registers
    cpu.reg.set16(.hl, addr + 2);
    cpu.reg.set8(.b, 0x56);
    OPCODES[0x70].execute(&cpu); // LD (HL), B
    try std.testing.expect(cpu.ram.readByte(addr + 2) == 0x56);

    cpu.reg.set8(.c, 0x78);
    OPCODES[0x71].execute(&cpu); // LD (HL), C
    try std.testing.expect(cpu.ram.readByte(addr + 2) == 0x78);

    // Test LD various registers, (HL)
    cpu.ram.writeByte(addr + 3, 0x9A);
    cpu.reg.set16(.hl, addr + 3);

    OPCODES[0x46].execute(&cpu); // LD B, (HL)
    try std.testing.expect(cpu.reg.get8(.b) == 0x9A);

    OPCODES[0x4E].execute(&cpu); // LD C, (HL)
    try std.testing.expect(cpu.reg.get8(.c) == 0x9A);

    OPCODES[0x56].execute(&cpu); // LD D, (HL)
    try std.testing.expect(cpu.reg.get8(.d) == 0x9A);
}

test "opcode LD - increment/decrement operations" {
    var cpu = Cpu.init();

    const base_addr: u16 = 0x6000;

    // Setup memory
    cpu.ram.writeByte(base_addr, 0x11);
    cpu.ram.writeByte(base_addr + 1, 0x22);
    cpu.ram.writeByte(base_addr + 2, 0x33);
    cpu.ram.writeByte(base_addr - 1, 0x00);

    // Test LD (HL+), A (0x22)
    cpu.reg.set16(.hl, base_addr);
    cpu.reg.set8(.a, 0xAA);
    OPCODES[0x22].execute(&cpu);
    try std.testing.expect(cpu.ram.readByte(base_addr) == 0xAA);
    try std.testing.expect(cpu.reg.get16(.hl) == base_addr + 1);

    // Test LD A, (HL+) (0x2A)
    cpu.reg.set16(.hl, base_addr + 1);
    OPCODES[0x2A].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.a) == 0x22);
    try std.testing.expect(cpu.reg.get16(.hl) == base_addr + 2);

    // Test LD (HL-), A (0x32)
    cpu.reg.set8(.a, 0xBB);
    OPCODES[0x32].execute(&cpu);
    try std.testing.expect(cpu.ram.readByte(base_addr + 2) == 0xBB);
    try std.testing.expect(cpu.reg.get16(.hl) == base_addr + 1);

    // Test LD A, (HL-) (0x3A)
    OPCODES[0x3A].execute(&cpu);
    try std.testing.expect(cpu.reg.get8(.a) == 0x22);
    try std.testing.expect(cpu.reg.get16(.hl) == base_addr);
}

test "opcode cycles metadata" {
    // Verify cycle counts are correct
    try std.testing.expect(OPCODES[0x00].metadata.cycles == 1); // NOP
    try std.testing.expect(OPCODES[0x04].metadata.cycles == 1); // INC B
    try std.testing.expect(OPCODES[0x03].metadata.cycles == 2); // INC BC
    try std.testing.expect(OPCODES[0x34].metadata.cycles == 3); // INC (HL)
    try std.testing.expect(OPCODES[0x47].metadata.cycles == 1); // LD B, A
    try std.testing.expect(OPCODES[0x46].metadata.cycles == 2); // LD B, (HL)
    try std.testing.expect(OPCODES[0x70].metadata.cycles == 2); // LD (HL), B
    try std.testing.expect(OPCODES[0x2A].metadata.cycles == 2); // LD A, (HL+)
    try std.testing.expect(OPCODES[0x22].metadata.cycles == 2); // LD (HL+), A
}

test "opcode flags - zero flag" {
    var cpu = Cpu.init();

    // INC setting zero flag
    cpu.reg.set8(.b, 0xFF);
    OPCODES[0x04].execute(&cpu); // INC B
    try std.testing.expect(cpu.reg.single.f.z == true);

    // INC clearing zero flag
    OPCODES[0x04].execute(&cpu); // INC B again
    try std.testing.expect(cpu.reg.single.f.z == false);

    // DEC setting zero flag
    cpu.reg.set8(.c, 0x01);
    OPCODES[0x0D].execute(&cpu); // DEC C
    try std.testing.expect(cpu.reg.single.f.z == true);

    // DEC clearing zero flag
    OPCODES[0x0D].execute(&cpu); // DEC C again
    try std.testing.expect(cpu.reg.single.f.z == false);
}

test "opcode flags - half carry/borrow" {
    var cpu = Cpu.init();

    // INC half carry tests
    cpu.reg.set8(.b, 0x0F);
    OPCODES[0x04].execute(&cpu); // INC B
    try std.testing.expect(cpu.reg.single.f.h == true);

    cpu.reg.set8(.b, 0x10);
    OPCODES[0x04].execute(&cpu); // INC B
    try std.testing.expect(cpu.reg.single.f.h == false);

    cpu.reg.set8(.b, 0xFF);
    OPCODES[0x04].execute(&cpu); // INC B
    try std.testing.expect(cpu.reg.single.f.h == true);

    // DEC half borrow tests
    cpu.reg.set8(.c, 0x10);
    OPCODES[0x0D].execute(&cpu); // DEC C
    try std.testing.expect(cpu.reg.single.f.h == true);

    cpu.reg.set8(.c, 0x0F);
    OPCODES[0x0D].execute(&cpu); // DEC C
    try std.testing.expect(cpu.reg.single.f.h == false);

    cpu.reg.set8(.c, 0x00);
    OPCODES[0x0D].execute(&cpu); // DEC C
    try std.testing.expect(cpu.reg.single.f.h == true);
}

test "opcode flags - N flag" {
    var cpu = Cpu.init();

    // INC should clear N flag
    cpu.reg.set8(.b, 0x42);
    cpu.reg.single.f.n = true;
    OPCODES[0x04].execute(&cpu); // INC B
    try std.testing.expect(cpu.reg.single.f.n == false);

    // DEC should set N flag
    cpu.reg.set8(.c, 0x42);
    OPCODES[0x0D].execute(&cpu); // DEC C
    try std.testing.expect(cpu.reg.single.f.n == true);
}
