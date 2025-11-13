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
    execute: fn (cpu: *Cpu) callconv(.@"inline") void,
    metadata: InstructionMetadata,
};

fn Unimplemented(comptime code: u8) Instruction {
    @setEvalBranchQuota(200_000);
    const logFmt = std.fmt.comptimePrint("Unimplemented instruction executed: 0x{X:02}", .{code});
    const nameFmt = std.fmt.comptimePrint("UNIMPLEMENTED(0x{X:02})", .{code});

    const inner = struct {
        inline fn logger(_: *Cpu) void {
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

inline fn getIm8(cpu: *Cpu, _: IM8) u8 {
    const value = cpu.fetch();
    return value;
}

inline fn getIm16(cpu: *Cpu, _: IM16) u16 {
    const value = cpu.fetch16();
    return value;
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

const BitsOperation = enum {
    OR,
    AND,
    XOR,

    inline fn _or(a: u8, b: u8) u8 {
        return a | b;
    }

    inline fn _and(a: u8, b: u8) u8 {
        return a & b;
    }

    inline fn _xor(a: u8, b: u8) u8 {
        return a ^ b;
    }

    inline fn asFn(comptime self: BitsOperation) fn (a: u8, b: u8) callconv(.@"inline") u8 {
        switch (self) {
            .OR => return _or,
            .AND => return _and,
            .XOR => return _xor,
        }
    }

    fn asText(comptime self: BitsOperation) []const u8 {
        switch (self) {
            .OR => return "OR",
            .AND => return "AND",
            .XOR => return "XOR",
        }
    }

    fn setHFlag(comptime self: BitsOperation) bool {
        switch (self) {
            .OR, .XOR => return false,
            .AND => return true,
        }
    }
};

const ArithmeticOperation = enum {
    ADD,
    SUB,
    ADC,
    SBC,
    CP,

    const Output = struct {
        value: u8,
        carry: bool,
        halfCarry: bool,
    };

    inline fn _add(a: u8, b: u8, _: bool) ArithmeticOperation.Output {
        const res = math.checkCarryAdd(u8, a, b);

        return .{
            .value = res.value,
            .carry = res.carry,
            .halfCarry = res.halfCarry,
        };
    }

    inline fn _sub(a: u8, b: u8, _: bool) ArithmeticOperation.Output {
        const res = math.checkBorrowSub(u8, a, b);

        return .{
            .value = res.value,
            .carry = res.borrow,
            .halfCarry = res.halfBorrow,
        };
    }

    inline fn _adc(a: u8, b: u8, carry: bool) ArithmeticOperation.Output {
        const carryVal: u8 = if (carry) 1 else 0;
        const res1 = math.checkCarryAdd(u8, a, b);
        const res2 = math.checkCarryAdd(u8, res1.value, carryVal);

        const resCarry = res1.carry or res2.carry;
        const resHalfCarry = res1.halfCarry or res2.halfCarry;

        return .{
            .value = res2.value,
            .carry = resCarry,
            .halfCarry = resHalfCarry,
        };
    }

    inline fn _sbc(a: u8, b: u8, carry: bool) ArithmeticOperation.Output {
        const carryVal: u8 = if (carry) 1 else 0;
        const res1 = math.checkBorrowSub(u8, a, b);
        const res2 = math.checkBorrowSub(u8, res1.value, carryVal);

        const resCarry = res1.borrow or res2.borrow;
        const resHalfCarry = res1.halfBorrow or res2.halfBorrow;

        return .{
            .value = res2.value,
            .carry = resCarry,
            .halfCarry = resHalfCarry,
        };
    }

    inline fn _cp(a: u8, b: u8, _: bool) ArithmeticOperation.Output {
        const res = math.checkBorrowSub(u8, a, b);

        return .{
            .value = a, // Tiny hack to not modify the first register (I hope compiler optimizes this out)
            .carry = res.borrow,
            .halfCarry = res.halfBorrow,
        };
    }

    fn asFn(comptime self: ArithmeticOperation) fn (u8, u8, bool) ArithmeticOperation.Output {
        switch (self) {
            .ADD => return _add,
            .SUB => return _sub,
            .ADC => return _adc,
            .SBC => return _sbc,
            .CP => return _cp,
        }
    }

    fn asText(comptime self: ArithmeticOperation) []const u8 {
        switch (self) {
            .ADD => return "ADD",
            .SUB => return "SUB",
            .ADC => return "ADC",
            .SBC => return "SBC",
            .CP => return "CP",
        }
    }

    fn setNFlags(comptime self: ArithmeticOperation) bool {
        switch (self) {
            .ADD, .ADC => return false,
            .SUB, .SBC, .CP => return true,
        }
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
const IM8 = struct {};
const IM16 = struct {};

fn regAsText(reg: anytype) []const u8 {
    comptime {
        const regType = @TypeOf(reg);

        switch (regType) {
            R8, R16, RM => {
                return register.asText(reg);
            },
            RMO => {
                return reg.op.asText(reg.reg);
            },
            IM8 => {
                return "u8";
            },
            IM16 => {
                return "u16";
            },
            else => {
                @compileError("Unsupported register type");
            },
        }
    }
}

const op = struct {
    inline fn nop_00(cpu: *Cpu) void {
        _ = cpu; // unused
    }

    inline fn ld_e0(cpu: *Cpu) void {
        const offset = cpu.fetch();
        const addr = 0xFF00 + @as(u16, offset);

        const value = cpu.reg.single.a;
        cpu.ram.writeByte(addr, value);
    }

    inline fn ld_f0(cpu: *Cpu) void {
        const offset = cpu.fetch();
        const addr = 0xFF00 + @as(u16, offset);

        const value = cpu.ram.readByte(addr);
        cpu.reg.single.a = value;
    }

    inline fn ld_08(cpu: *Cpu) void {
        const addr = cpu.fetch16();
        const valueSplit = math.splitBytes(cpu.reg.pair.sp);

        cpu.ram.writeByte(addr, valueSplit.low);
        cpu.ram.writeByte(addr + 1, valueSplit.high);
    }

    inline fn ld_e2(cpu: *Cpu) void {
        const addr = 0xFF00 + @as(u16, cpu.reg.single.c);
        const value = cpu.reg.single.a;

        cpu.ram.writeByte(addr, value);
    }

    inline fn ld_f2(cpu: *Cpu) void {
        const addr = 0xFF00 + @as(u16, cpu.reg.single.c);
        const value = cpu.ram.readByte(addr);

        cpu.reg.single.a = value;
    }

    inline fn ld_f8(cpu: *Cpu) void {

        // Treat immediate values as i8
        var offset: u16 = @intCast(cpu.fetch());
        // Sign extend to 16 bits if negative
        if (offset & 0x0080 != 0) {
            offset = 0xFF_00 | offset;
        }

        const sp = cpu.reg.pair.sp;

        const value = math.checkCarryAdd(u16, sp, offset);

        // Flags: 00HC
        var flags = cpu.reg.single.f;
        flags.z = false;
        flags.n = false;
        flags.c = value.carry;
        flags.h = value.halfCarry;

        // Set registers
        cpu.reg.pair.hl = value.value;
    }

    inline fn ld_ea(cpu: *Cpu) void {
        const addr = cpu.fetch16();
        const value = cpu.reg.single.a;

        cpu.ram.writeByte(addr, value);
    }

    inline fn ld_fa(cpu: *Cpu) void {
        const addr = cpu.fetch16();
        const value = cpu.ram.readByte(addr);

        cpu.reg.single.a = value;
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
                @compileError("reg must be of type R8 or R16");
            }
        };

        const _inline = struct {
            inline fn execute(cpu: *Cpu) void {
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
            .name = std.fmt.comptimePrint("INC {s}", .{regAsText(reg)}),
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
                @compileError("reg must be of type R8 or R16");
            }
        };

        const _inline = struct {
            inline fn execute(cpu: *Cpu) void {
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
            .name = std.fmt.comptimePrint("DEC {s}", .{regAsText(reg)}),
        } };
    }

    fn load(comptime dest: anytype, comptime source: anytype) Instruction {
        const TD = @TypeOf(dest);
        const TS = @TypeOf(source);

        const setDst, const destReg, const cycleDst = comptime blkD: {
            switch (TD) {
                R8 => break :blkD .{ setReg8, dest, 0 },
                R16 => break :blkD .{ setReg16, dest, 0 },
                RM => break :blkD .{ setMemory(RegisterMemoryOperation._nop), dest, 1 },
                RMO => break :blkD .{ setMemory(dest.op.asPostOp()), dest.reg, 1 },
                else => @compileError("dest must be of type R8, R16, RM, or RMO"),
            }
        };

        const getSrc, const sourceReg, const cycleSrc = comptime blkS: {
            switch (TS) {
                R8 => break :blkS .{ getReg8, source, 1 },
                R16 => break :blkS .{ getReg16, source, 1 },
                RM => break :blkS .{ getMemory(RegisterMemoryOperation._nop), source, 2 },
                RMO => break :blkS .{ getMemory(source.op.asPostOp()), source.reg, 2 },
                IM8 => break :blkS .{ getIm8, source, 2 },
                IM16 => break :blkS .{ getIm16, source, 3 },
                else => @compileError("source must be of type R8, R16, RM, RMO, IM8, or IM16"),
            }
        };

        const cycle = cycleSrc + cycleDst; // Tiny hack because cycles are 1 or 2.

        const _inline = struct {
            inline fn execute(cpu: *Cpu) void {
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
                    .{ regAsText(destReg), regAsText(sourceReg) },
                ),
            },
        };
    }

    fn bits(comptime ops: BitsOperation, comptime dest: R8, comptime source: anytype) Instruction {
        const TS = @TypeOf(source);

        const getSrc, const cycles = comptime blkS: {
            switch (TS) {
                R8 => break :blkS .{ getReg8, 1 },
                RM => break :blkS .{ getMemory(RegisterMemoryOperation._nop), 2 },
                IM8 => break :blkS .{ getIm8, 2 },
                else => @compileError("source must be of type R8, RM or IM8"),
            }
        };

        const _inline = struct {
            inline fn execute(cpu: *Cpu) void {
                const destValue = cpu.reg.get8(dest);
                const sourceValue = getSrc(cpu, source);

                const result = ops.asFn()(destValue, sourceValue);

                // Flags Z0x0 => x depends on ops
                var flags = cpu.reg.single.f;
                flags.z = result == 0;
                flags.n = false;
                flags.h = ops.setHFlag();
                flags.c = false;
                cpu.reg.single.f = flags;

                cpu.reg.set8(dest, result);
            }
        };

        return .{
            .execute = _inline.execute,
            .metadata = .{
                .cycles = cycles,
                .name = std.fmt.comptimePrint(
                    "{s} {s}, {s}",
                    .{ ops.asText(), regAsText(dest), regAsText(source) },
                ),
            },
        };
    }

    fn arithmetic(comptime ops: ArithmeticOperation, comptime dest: R8, comptime source: anytype) Instruction {
        const TS = @TypeOf(source);

        const getSrc, const cycles = comptime blkS: {
            switch (TS) {
                R8 => break :blkS .{ getReg8, 1 },
                RM => break :blkS .{ getMemory(RegisterMemoryOperation._nop), 2 },
                IM8 => break :blkS .{ getIm8, 2 },
                else => @compileError("source must be of type R8, RM or IM8"),
            }
        };

        const _inline = struct {
            inline fn execute(cpu: *Cpu) void {
                const destValue = cpu.reg.get8(dest);
                const sourceValue = getSrc(cpu, source);

                const res = ops.asFn()(destValue, sourceValue, cpu.reg.single.f.c);

                // Flags ZxHC => x depends on ops
                var flags = cpu.reg.single.f;
                flags.z = res.value == 0;
                flags.n = ops.setNFlags();
                flags.h = res.halfCarry;
                flags.c = res.carry;
                cpu.reg.single.f = flags;

                cpu.reg.set8(dest, res.value);
            }
        };

        return .{
            .execute = _inline.execute,
            .metadata = .{
                .cycles = cycles,
                .name = std.fmt.comptimePrint(
                    "{s} {s}, {s}",
                    .{ ops.asText(), regAsText(dest), regAsText(source) },
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

const __LD_E0: Instruction = .{
    .execute = op.ld_e0,
    .metadata = .{ .name = "LDH (FF00 + u8), A", .cycles = 3 },
};
const __LD_F0: Instruction = .{
    .execute = op.ld_f0,
    .metadata = .{ .name = "LDH A, (FF00 + u8)", .cycles = 3 },
};

const __LD_01: Instruction = op.load(R16.bc, IM16{});
const __LD_11: Instruction = op.load(R16.de, IM16{});
const __LD_21: Instruction = op.load(R16.hl, IM16{});
const __LD_31: Instruction = op.load(R16.sp, IM16{});

const __LD_02: Instruction = op.load(RM.bc, R8.a);
const __LD_12: Instruction = op.load(RM.de, R8.a);
const __LD_22: Instruction = op.load(RMO.hl_inc, R8.a);
const __LD_32: Instruction = op.load(RMO.hl_dec, R8.a);

const __LD_E2: Instruction = .{
    .execute = op.ld_e2,
    .metadata = .{ .name = "LD (FF00 + C), A", .cycles = 2 },
};
const __LD_F2: Instruction = .{
    .execute = op.ld_f2,
    .metadata = .{ .name = "LD A, (FF00 + C)", .cycles = 2 },
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

const __LD_06: Instruction = op.load(R8.b, IM8{});
const __LD_16: Instruction = op.load(R8.d, IM8{});
const __LD_26: Instruction = op.load(R8.h, IM8{});
const __LD_36: Instruction = op.load(RM.hl, IM8{});

// const __LD_08: Instruction = op.load(IMM16{}, R16.sp);
const __LD_08: Instruction = .{
    .execute = op.ld_08,
    .metadata = .{
        .name = "LD (u16), SP",
        .cycles = 5,
    },
};

const __LD_0A: Instruction = op.load(R8.a, RM.bc);
const __LD_1A: Instruction = op.load(R8.a, RM.de);
const __LD_2A: Instruction = op.load(R8.a, RMO.hl_inc);
const __LD_3A: Instruction = op.load(R8.a, RMO.hl_dec);

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

const __LD_0E: Instruction = op.load(R8.c, IM8{});
const __LD_1E: Instruction = op.load(R8.e, IM8{});
const __LD_2E: Instruction = op.load(R8.l, IM8{});
const __LD_3E: Instruction = op.load(R8.a, IM8{});

const __LD_40: Instruction = op.load(R8.b, R8.b);
const __LD_50: Instruction = op.load(R8.d, R8.b);
const __LD_60: Instruction = op.load(R8.h, R8.b);
const __LD_70: Instruction = op.load(RM.hl, R8.b);

const __LD_41: Instruction = op.load(R8.b, R8.c);
const __LD_51: Instruction = op.load(R8.d, R8.c);
const __LD_61: Instruction = op.load(R8.h, R8.c);
const __LD_71: Instruction = op.load(RM.hl, R8.c);

const __LD_42: Instruction = op.load(R8.b, R8.d);
const __LD_52: Instruction = op.load(R8.d, R8.d);
const __LD_62: Instruction = op.load(R8.h, R8.d);
const __LD_72: Instruction = op.load(RM.hl, R8.d);

const __LD_43: Instruction = op.load(R8.b, R8.e);
const __LD_53: Instruction = op.load(R8.d, R8.e);
const __LD_63: Instruction = op.load(R8.h, R8.e);
const __LD_73: Instruction = op.load(RM.hl, R8.e);

const __LD_44: Instruction = op.load(R8.b, R8.h);
const __LD_54: Instruction = op.load(R8.d, R8.h);
const __LD_64: Instruction = op.load(R8.h, R8.h);
const __LD_74: Instruction = op.load(RM.hl, R8.h);

const __LD_45: Instruction = op.load(R8.b, R8.l);
const __LD_55: Instruction = op.load(R8.d, R8.l);
const __LD_65: Instruction = op.load(R8.h, R8.l);
const __LD_75: Instruction = op.load(RM.hl, R8.l);

const __LD_46: Instruction = op.load(R8.b, RM.hl);
const __LD_56: Instruction = op.load(R8.d, RM.hl);
const __LD_66: Instruction = op.load(R8.h, RM.hl);
// const __LD_76: Instruction = op.halt; // HALT instruction

const __LD_47: Instruction = op.load(R8.b, R8.a);
const __LD_57: Instruction = op.load(R8.d, R8.a);
const __LD_67: Instruction = op.load(R8.h, R8.a);
const __LD_77: Instruction = op.load(RM.hl, R8.a);

const __LD_48: Instruction = op.load(R8.c, R8.b);
const __LD_58: Instruction = op.load(R8.e, R8.b);
const __LD_68: Instruction = op.load(R8.l, R8.b);
const __LD_78: Instruction = op.load(R8.a, R8.b);

const __LD_F8: Instruction = .{
    .execute = op.ld_f8,
    .metadata = .{ .name = "LD HL, SP + i8", .cycles = 3 },
};

const __LD_49: Instruction = op.load(R8.c, R8.c);
const __LD_59: Instruction = op.load(R8.e, R8.c);
const __LD_69: Instruction = op.load(R8.l, R8.c);
const __LD_79: Instruction = op.load(R8.a, R8.c);

const __LD_F9: Instruction = op.load(R16.sp, R16.hl);

const __LD_4A: Instruction = op.load(R8.c, R8.d);
const __LD_5A: Instruction = op.load(R8.e, R8.d);
const __LD_6A: Instruction = op.load(R8.l, R8.d);
const __LD_7A: Instruction = op.load(R8.a, R8.d);

const __LD_EA: Instruction = .{
    .execute = op.ld_ea,
    .metadata = .{ .name = "LD (a16), A", .cycles = 4 },
};
const __LD_FA: Instruction = .{
    .execute = op.ld_fa,
    .metadata = .{ .name = "LD A. (u16)", .cycles = 4 },
};

const __LD_4B: Instruction = op.load(R8.c, R8.e);
const __LD_5B: Instruction = op.load(R8.e, R8.e);
const __LD_6B: Instruction = op.load(R8.l, R8.e);
const __LD_7B: Instruction = op.load(R8.a, R8.e);

const __LD_4C: Instruction = op.load(R8.c, R8.h);
const __LD_5C: Instruction = op.load(R8.e, R8.h);
const __LD_6C: Instruction = op.load(R8.l, R8.h);
const __LD_7C: Instruction = op.load(R8.a, R8.h);

const __LD_4D: Instruction = op.load(R8.c, R8.l);
const __LD_5D: Instruction = op.load(R8.e, R8.l);
const __LD_6D: Instruction = op.load(R8.l, R8.l);
const __LD_7D: Instruction = op.load(R8.a, R8.l);

const __LD_4E: Instruction = op.load(R8.c, RM.hl);
const __LD_5E: Instruction = op.load(R8.e, RM.hl);
const __LD_6E: Instruction = op.load(R8.l, RM.hl);
const __LD_7E: Instruction = op.load(R8.a, RM.hl);

const __LD_4F: Instruction = op.load(R8.c, R8.a);
const __LD_5F: Instruction = op.load(R8.e, R8.a);
const __LD_6F: Instruction = op.load(R8.l, R8.a);
const __LD_7F: Instruction = op.load(R8.a, R8.a);

const _ADD_80: Instruction = op.arithmetic(.ADD, R8.a, R8.b);
const _ADD_81: Instruction = op.arithmetic(.ADD, R8.a, R8.c);
const _ADD_82: Instruction = op.arithmetic(.ADD, R8.a, R8.d);
const _ADD_83: Instruction = op.arithmetic(.ADD, R8.a, R8.e);
const _ADD_84: Instruction = op.arithmetic(.ADD, R8.a, R8.h);
const _ADD_85: Instruction = op.arithmetic(.ADD, R8.a, R8.l);
const _ADD_86: Instruction = op.arithmetic(.ADD, R8.a, RM.hl);
const _ADD_C6: Instruction = op.arithmetic(.ADD, R8.a, IM8{});
const _ADD_87: Instruction = op.arithmetic(.ADD, R8.a, R8.a);

const _ADC_88: Instruction = op.arithmetic(.ADC, R8.a, R8.b);
const _ADC_89: Instruction = op.arithmetic(.ADC, R8.a, R8.c);
const _ADC_8A: Instruction = op.arithmetic(.ADC, R8.a, R8.d);
const _ADC_8B: Instruction = op.arithmetic(.ADC, R8.a, R8.e);
const _ADC_8C: Instruction = op.arithmetic(.ADC, R8.a, R8.h);
const _ADC_8D: Instruction = op.arithmetic(.ADC, R8.a, R8.l);
const _ADC_8E: Instruction = op.arithmetic(.ADC, R8.a, RM.hl);
const _ADC_CE: Instruction = op.arithmetic(.ADC, R8.a, IM8{});
const _ADC_8F: Instruction = op.arithmetic(.ADC, R8.a, R8.a);

const _SUB_90: Instruction = op.arithmetic(.SUB, R8.a, R8.b);
const _SUB_91: Instruction = op.arithmetic(.SUB, R8.a, R8.c);
const _SUB_92: Instruction = op.arithmetic(.SUB, R8.a, R8.d);
const _SUB_93: Instruction = op.arithmetic(.SUB, R8.a, R8.e);
const _SUB_94: Instruction = op.arithmetic(.SUB, R8.a, R8.h);
const _SUB_95: Instruction = op.arithmetic(.SUB, R8.a, R8.l);
const _SUB_96: Instruction = op.arithmetic(.SUB, R8.a, RM.hl);
const _SUB_D6: Instruction = op.arithmetic(.SUB, R8.a, IM8{});
const _SUB_97: Instruction = op.arithmetic(.SUB, R8.a, R8.a);

const _SBC_98: Instruction = op.arithmetic(.SBC, R8.a, R8.b);
const _SBC_99: Instruction = op.arithmetic(.SBC, R8.a, R8.c);
const _SBC_9A: Instruction = op.arithmetic(.SBC, R8.a, R8.d);
const _SBC_9B: Instruction = op.arithmetic(.SBC, R8.a, R8.e);
const _SBC_9C: Instruction = op.arithmetic(.SBC, R8.a, R8.h);
const _SBC_9D: Instruction = op.arithmetic(.SBC, R8.a, R8.l);
const _SBC_9E: Instruction = op.arithmetic(.SBC, R8.a, RM.hl);
const _SBC_DE: Instruction = op.arithmetic(.SBC, R8.a, IM8{});
const _SBC_9F: Instruction = op.arithmetic(.SBC, R8.a, R8.a);

const _AND_A0: Instruction = op.bits(.AND, R8.a, R8.b);
const _AND_A1: Instruction = op.bits(.AND, R8.a, R8.c);
const _AND_A2: Instruction = op.bits(.AND, R8.a, R8.d);
const _AND_A3: Instruction = op.bits(.AND, R8.a, R8.e);
const _AND_A4: Instruction = op.bits(.AND, R8.a, R8.h);
const _AND_A5: Instruction = op.bits(.AND, R8.a, R8.l);
const _AND_A6: Instruction = op.bits(.AND, R8.a, RM.hl);
const _AND_E6: Instruction = op.bits(.AND, R8.a, IM8{});
const _AND_A7: Instruction = op.bits(.AND, R8.a, R8.a);

const _XOR_A8: Instruction = op.bits(.XOR, R8.a, R8.b);
const _XOR_A9: Instruction = op.bits(.XOR, R8.a, R8.c);
const _XOR_AA: Instruction = op.bits(.XOR, R8.a, R8.d);
const _XOR_AB: Instruction = op.bits(.XOR, R8.a, R8.e);
const _XOR_AC: Instruction = op.bits(.XOR, R8.a, R8.h);
const _XOR_AD: Instruction = op.bits(.XOR, R8.a, R8.l);
const _XOR_AE: Instruction = op.bits(.XOR, R8.a, RM.hl);
const _XOR_EE: Instruction = op.bits(.XOR, R8.a, IM8{});
const _XOR_AF: Instruction = op.bits(.XOR, R8.a, R8.a);

const __OR_B0: Instruction = op.bits(.OR, R8.a, R8.b);
const __OR_B1: Instruction = op.bits(.OR, R8.a, R8.c);
const __OR_B2: Instruction = op.bits(.OR, R8.a, R8.d);
const __OR_B3: Instruction = op.bits(.OR, R8.a, R8.e);
const __OR_B4: Instruction = op.bits(.OR, R8.a, R8.h);
const __OR_B5: Instruction = op.bits(.OR, R8.a, R8.l);
const __OR_F6: Instruction = op.bits(.OR, R8.a, RM.hl);
const __OR_B6: Instruction = op.bits(.OR, R8.a, IM8{});
const __OR_B7: Instruction = op.bits(.OR, R8.a, R8.a);

const __CP_B8: Instruction = op.arithmetic(.CP, R8.a, R8.b);
const __CP_B9: Instruction = op.arithmetic(.CP, R8.a, R8.c);
const __CP_BA: Instruction = op.arithmetic(.CP, R8.a, R8.d);
const __CP_BB: Instruction = op.arithmetic(.CP, R8.a, R8.e);
const __CP_BC: Instruction = op.arithmetic(.CP, R8.a, R8.h);
const __CP_BD: Instruction = op.arithmetic(.CP, R8.a, R8.l);
const __CP_BE: Instruction = op.arithmetic(.CP, R8.a, RM.hl);
const __CP_FE: Instruction = op.arithmetic(.CP, R8.a, IM8{});
const __CP_BF: Instruction = op.arithmetic(.CP, R8.a, R8.a);

const U = Unimplemented;

// From https://izik1.github.io/gbops/
const OPCODES: [256]Instruction = .{
    //0x00,  0x01,    0x02,    0x03,    0x04,    0x05,    0x06,    0x07,    0x08,    0x09,    0x0A,    0x0B,    0x0C,    0x0D,    0x0E,    0x0F,
    _NOP_00, __LD_01, __LD_02, _INC_03, _INC_04, _DEC_05, __LD_06, U(0x07), __LD_08, U(0x09), __LD_0A, _DEC_0B, _INC_0C, _DEC_0D, __LD_0E, U(0x0F), // 0x00
    U(0x10), __LD_11, __LD_12, _INC_13, _INC_14, _DEC_15, __LD_16, U(0x17), U(0x18), U(0x19), __LD_1A, _DEC_1B, _INC_1C, _DEC_1D, __LD_1E, U(0x1F), // 0x10
    U(0x20), __LD_21, __LD_22, _INC_23, _INC_24, _DEC_25, __LD_26, U(0x27), U(0x28), U(0x29), __LD_2A, _DEC_2B, _INC_2C, _DEC_2D, __LD_2E, U(0x2F), // 0x20
    U(0x30), __LD_31, __LD_32, _INC_33, _INC_34, _DEC_35, __LD_36, U(0x37), U(0x38), U(0x39), __LD_3A, _DEC_3B, _INC_3C, _DEC_3D, __LD_3E, U(0x3F), // 0x30
    __LD_40, __LD_41, __LD_42, __LD_43, __LD_44, __LD_45, __LD_46, __LD_47, __LD_48, __LD_49, __LD_4A, __LD_4B, __LD_4C, __LD_4D, __LD_4E, __LD_4F, // 0x40
    __LD_50, __LD_51, __LD_52, __LD_53, __LD_54, __LD_55, __LD_56, __LD_57, __LD_58, __LD_59, __LD_5A, __LD_5B, __LD_5C, __LD_5D, __LD_5E, __LD_5F, // 0x50
    __LD_60, __LD_61, __LD_62, __LD_63, __LD_64, __LD_65, __LD_66, __LD_67, __LD_68, __LD_69, __LD_6A, __LD_6B, __LD_6C, __LD_6D, __LD_6E, __LD_6F, // 0x60
    __LD_70, __LD_71, __LD_72, __LD_73, __LD_74, __LD_75, U(0x76), __LD_77, __LD_78, __LD_79, __LD_7A, __LD_7B, __LD_7C, __LD_7D, __LD_7E, __LD_7F, // 0x70
    _ADD_80, _ADD_81, _ADD_82, _ADD_83, _ADD_84, _ADD_85, _ADD_86, _ADD_87, _ADC_88, _ADC_89, _ADC_8A, _ADC_8B, _ADC_8C, _ADC_8D, _ADC_8E, _ADC_8F, // 0x80
    _SUB_90, _SUB_91, _SUB_92, _SUB_93, _SUB_94, _SUB_95, _SUB_96, _SUB_97, _SBC_98, _SBC_99, _SBC_9A, _SBC_9B, _SBC_9C, _SBC_9D, _SBC_9E, _SBC_9F, // 0x90
    _AND_A0, _AND_A1, _AND_A2, _AND_A3, _AND_A4, _AND_A5, _AND_A6, _AND_A7, _XOR_A8, _XOR_A9, _XOR_AA, _XOR_AB, _XOR_AC, _XOR_AD, _XOR_AE, _XOR_AF, // 0xA0
    __OR_B0, __OR_B1, __OR_B2, __OR_B3, __OR_B4, __OR_B5, __OR_B6, __OR_B7, __CP_B8, __CP_B9, __CP_BA, __CP_BB, __CP_BC, __CP_BD, __CP_BE, __CP_BF, // 0xB0
    U(0xC0), U(0xC1), U(0xC2), U(0xC3), U(0xC4), U(0xC5), _ADD_C6, U(0xC7), U(0xC8), U(0xC9), U(0xCA), U(0xCB), U(0xCC), U(0xCD), _ADC_CE, U(0xCF), // 0xC0
    U(0xD0), U(0xD1), U(0xD2), U(0xD3), U(0xD4), U(0xD5), _SUB_D6, U(0xD7), U(0xD8), U(0xD9), U(0xDA), U(0xDB), U(0xDC), U(0xDD), _SBC_DE, U(0xDF), // 0xD0
    __LD_E0, U(0xE1), __LD_E2, U(0xE3), U(0xE4), U(0xE5), _AND_E6, U(0xE7), U(0xE8), U(0xE9), __LD_EA, U(0xEB), U(0xEC), U(0xED), _XOR_EE, U(0xEF), // 0xE0
    __LD_F0, U(0xF1), __LD_F2, U(0xF3), U(0xF4), U(0xF5), __OR_F6, U(0xF7), __LD_F8, __LD_F9, __LD_FA, U(0xFB), U(0xFC), U(0xFD), __CP_BE, U(0xFF), // 0xF0
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
    try std.testing.expect(OPCODES[0x36].metadata.cycles == 3); // LD (HL), d8
    try std.testing.expect(OPCODES[0x31].metadata.cycles == 3); // LD SP, d16
    try std.testing.expect(OPCODES[0x08].metadata.cycles == 5); // LD (d16), SP

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

test "opcode F8 - LD HL, SP + i8" {
    var cpu = Cpu.init();

    cpu.reg.set16(.sp, 0xFFF8);
    cpu.ram.writeByte(0x0000, 0x08); // i8 = 8
    cpu.reg.set16(.pc, 0x0000);

    OPCODES[0xF8].execute(&cpu); // LD HL, SP + i8

    try std.testing.expect(cpu.reg.pair.hl == 0x0000); // 0xFFF8 + 8 = 0x0000 (wrap around)

    // => Now test with negative offset
    // -8 =>

    cpu.ram.writeByte(0x0001, 0xF8); // i8 = -8
    cpu.reg.pair.sp = 0x00_FF; // 255

    try std.testing.expect(cpu.reg.pair.pc == 0x0001);
    OPCODES[0xF8].execute(&cpu); // LD HL, SP + i8

    try std.testing.expect(cpu.reg.pair.hl == 0x00_F7); // 0x00_FF - 0x00_08 = 0x00_F7 => no carry, no half carry

    // Check flags
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == false);
    try std.testing.expect(cpu.reg.single.f.c == false);

    cpu.ram.writeByte(0x0002, 0xF8); // i8 = -8
    cpu.reg.pair.sp = 0x0F_00;

    try std.testing.expect(cpu.reg.pair.pc == 0x0002);
    OPCODES[0xF8].execute(&cpu); // LD HL, SP + i8

    try std.testing.expect(cpu.reg.pair.hl == 0x0E_F8); // 0x0F_00 - 0x00_08 = 0x0E_F8

    // Check flags
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == false);
    try std.testing.expect(cpu.reg.single.f.c == false);
}
