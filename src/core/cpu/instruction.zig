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

inline fn getMemory(cpu: *const Cpu, reg: Register16Memory) u8 {
    const address = cpu.reg.get16(reg.asReg16());
    return cpu.ram.readByte(address);
}

inline fn setReg8(cpu: *Cpu, reg: Register8, value: u8) void {
    cpu.reg.set8(reg, value);
}

inline fn setReg16(cpu: *Cpu, reg: Register16, value: u16) void {
    cpu.reg.set16(reg, value);
}

inline fn setMemory(cpu: *Cpu, reg: Register16Memory, value: u8) void {
    const address = cpu.reg.get16(reg.asReg16());
    cpu.ram.writeByte(address, value);
}

const RegisterMemoryOperation = enum {
    inc,
    dec,
};

const R8 = Register8;
const R16 = Register16;
const RM = Register16Memory;
const RMO = struct {
    reg: Register16Memory,
    op: RegisterMemoryOperation,
};

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
                break :blk .{ u8, true, getMemory, setMemory, 3 };
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
                break :blk .{ u8, true, getMemory, setMemory, 3 };
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

    fn load(comptime source: anytype, comptime dest: anytype) Instruction {
        const TS = @TypeOf(source);
        const TD = @TypeOf(dest);

        const getSrc, const cycleSrc = comptime blkS: {
            switch (TS) {
                Register8 => break :blkS .{ getReg8, 1 },
                Register16 => break :blkS .{ getReg16, 1 },
                Register16Memory => break :blkS .{ getMemory, 2 },
                else => @compileError("source must be of type Register8, Register16, or Register16Memory"),
            }
        };

        const setDst, const cycleDst = comptime blkD: {
            switch (TD) {
                Register8 => break :blkD .{ setReg8, 1 },
                Register16 => break :blkD .{ setReg16, 1 },
                Register16Memory => break :blkD .{ setMemory, 2 },
                else => @compileError("dest must be of type Register8, Register16, or Register16Memory"),
            }
        };

        const cycle = cycleSrc * cycleDst; // Tiny hack because cycles are 1 or 2.

        const _inline = struct {
            fn execute(cpu: *Cpu) void {
                const value = getSrc(cpu, source);
                setDst(cpu, dest, value);

                // Flags ----

            }
        };

        return .{
            .execute = _inline.execute,
            .metadata = .{
                .cycles = cycle,
                .name = std.fmt.comptimePrint(
                    "LD {s}, {s}",
                    .{ register.asText(dest), register.asText(source) },
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
    _NOP_00, U(0x01), U(0x02), _INC_03, _INC_04, _DEC_05, U(0x06), U(0x07), U(0x08), U(0x09), U(0x0A), _DEC_0B, _INC_0C, _DEC_0D, U(0x0E), U(0x0F), // 0x00
    U(0x10), U(0x11), U(0x12), _INC_13, _INC_14, _DEC_15, U(0x16), U(0x17), U(0x18), U(0x19), U(0x1A), _DEC_1B, _INC_1C, _DEC_1D, U(0x1E), U(0x1F), // 0x10
    U(0x20), U(0x21), U(0x22), _INC_23, _INC_24, _DEC_25, U(0x26), U(0x27), U(0x28), U(0x29), U(0x2A), _DEC_2B, _INC_2C, _DEC_2D, U(0x2E), U(0x2F), // 0x20
    U(0x30), U(0x31), U(0x32), _INC_33, _INC_34, _DEC_35, U(0x36), U(0x37), U(0x38), U(0x39), U(0x3A), _DEC_3B, _INC_3C, _DEC_3D, U(0x3E), U(0x3F), // 0x30
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
