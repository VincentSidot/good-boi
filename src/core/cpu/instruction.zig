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

    fn Output(comptime T: type) type {
        return struct {
            value: T,
            carry: bool,
            halfCarry: bool,
        };
    }

    fn OutputFn(comptime T: type) type {
        return fn (a: T, b: T, carry: bool) callconv(.@"inline") ArithmeticOperation.Output(T);
    }

    inline fn _add(comptime T: type) ArithmeticOperation.OutputFn(T) {
        const _inline = struct {
            inline fn _add(a: T, b: T, _: bool) ArithmeticOperation.Output(T) {
                const res = math.checkCarryAdd(T, a, b);

                return .{
                    .value = res.value,
                    .carry = res.carry,
                    .halfCarry = res.halfCarry,
                };
            }
        };

        return _inline._add;
    }

    inline fn _sub(comptime T: type) ArithmeticOperation.OutputFn(T) {
        const _inline = struct {
            inline fn _sub(a: T, b: T, _: bool) ArithmeticOperation.Output(T) {
                const res = math.checkBorrowSub(T, a, b);

                return .{
                    .value = res.value,
                    .carry = res.borrow,
                    .halfCarry = res.halfBorrow,
                };
            }
        };

        return _inline._sub;
    }

    inline fn _adc(comptime T: type) ArithmeticOperation.OutputFn(T) {
        const _inline = struct {
            inline fn _adc(a: T, b: T, carry: bool) ArithmeticOperation.Output(T) {
                const carryVal: T = if (carry) 1 else 0;
                const res1 = math.checkCarryAdd(T, a, b);
                const res2 = math.checkCarryAdd(T, res1.value, carryVal);

                const resCarry = res1.carry or res2.carry;
                const resHalfCarry = res1.halfCarry or res2.halfCarry;

                return .{
                    .value = res2.value,
                    .carry = resCarry,
                    .halfCarry = resHalfCarry,
                };
            }
        };

        return _inline._adc;
    }

    inline fn _sbc(comptime T: type) ArithmeticOperation.OutputFn(T) {
        const _inline = struct {
            inline fn _sbc(a: T, b: T, carry: bool) ArithmeticOperation.Output(T) {
                const carryVal: T = if (carry) 1 else 0;
                const res1 = math.checkBorrowSub(T, a, b);
                const res2 = math.checkBorrowSub(T, res1.value, carryVal);

                const resCarry = res1.borrow or res2.borrow;
                const resHalfCarry = res1.halfBorrow or res2.halfBorrow;

                return .{
                    .value = res2.value,
                    .carry = resCarry,
                    .halfCarry = resHalfCarry,
                };
            }
        };

        return _inline._sbc;
    }

    fn asFn(comptime self: ArithmeticOperation, comptime T: type) ArithmeticOperation.OutputFn(T) {
        switch (self) {
            .ADD => return ArithmeticOperation._add(T),
            .SUB => return ArithmeticOperation._sub(T),
            .ADC => return ArithmeticOperation._adc(T),
            .SBC => return ArithmeticOperation._sbc(T),
            .CP => return ArithmeticOperation._sub(T),
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
    fn nop_00(cpu: *Cpu) void {
        _ = cpu; // unused
    }

    fn ld_e0(cpu: *Cpu) void {
        const offset = cpu.fetch();
        const addr = 0xFF00 + @as(u16, offset);

        const value = cpu.reg.single.a;
        cpu.ram.writeByte(addr, value);
    }

    fn ld_f0(cpu: *Cpu) void {
        const offset = cpu.fetch();
        const addr = 0xFF00 + @as(u16, offset);

        const value = cpu.ram.readByte(addr);
        cpu.reg.single.a = value;
    }

    fn ld_08(cpu: *Cpu) void {
        const addr = cpu.fetch16();
        const valueSplit = math.splitBytes(cpu.reg.pair.sp);

        cpu.ram.writeByte(addr, valueSplit.low);
        cpu.ram.writeByte(addr + 1, valueSplit.high);
    }

    fn ld_e2(cpu: *Cpu) void {
        const addr = 0xFF00 + @as(u16, cpu.reg.single.c);
        const value = cpu.reg.single.a;

        cpu.ram.writeByte(addr, value);
    }

    fn ld_f2(cpu: *Cpu) void {
        const addr = 0xFF00 + @as(u16, cpu.reg.single.c);
        const value = cpu.ram.readByte(addr);

        cpu.reg.single.a = value;
    }

    fn add_e8(cpu: *Cpu) void {

        // Treat immediate values as i8
        var offset: u16 = @intCast(cpu.fetch());
        // Sign extend to 16 bits if negative
        if (offset & 0x00_80 != 0) {
            offset = 0xFF_00 | offset;
        }

        const sp = cpu.reg.pair.sp;

        const value = math.checkCarryAdd(u16, sp, offset);

        // Flags: 00HC
        var flags = cpu.reg.single.f;
        flags.z = false;
        flags.n = false;
        flags.h = value.halfCarry;
        flags.c = value.carry;
        cpu.reg.single.f = flags;

        // Set registers
        cpu.reg.pair.sp = value.value;
    }

    fn ld_f8(cpu: *Cpu) void {

        // Treat immediate values as i8
        var offset: u16 = @intCast(cpu.fetch());
        // Sign extend to 16 bits if negative
        if (offset & 0x00_80 != 0) {
            offset = 0xFF_00 | offset;
        }

        const sp = cpu.reg.pair.sp;

        const value = math.checkCarryAdd(u16, sp, offset);

        // Flags: 00HC
        var flags = cpu.reg.single.f;
        flags.z = false;
        flags.n = false;
        flags.h = value.halfCarry;
        flags.c = value.carry;

        // Set registers
        cpu.reg.pair.hl = value.value;
    }

    fn ld_ea(cpu: *Cpu) void {
        const addr = cpu.fetch16();
        const value = cpu.reg.single.a;

        cpu.ram.writeByte(addr, value);
    }

    fn ld_fa(cpu: *Cpu) void {
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
            fn execute(cpu: *Cpu) void {
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

    fn arithmetic(comptime ops: ArithmeticOperation, comptime dest: anytype, comptime source: anytype) Instruction {
        const TD = @TypeOf(dest);
        const TS = @TypeOf(source);

        const getDst, const setDst, const editZ, const bitTypeDst = comptime blkD: {
            switch (TD) {
                R8 => break :blkD .{ getReg8, setReg8, true, u8 },
                R16 => break :blkD .{ getReg16, setReg16, false, u16 },
                else => @compileError("dest must be of type R8, or R16"),
            }
        };

        const getSrc, const cycles, const bitTypeSrc = comptime blkS: {
            switch (TS) {
                R8 => break :blkS .{ getReg8, 1, u8 },
                R16 => break :blkS .{ getReg16, 2, u16 },
                RM => break :blkS .{ getMemory(RegisterMemoryOperation._nop), 2, u8 },
                IM8 => break :blkS .{ getIm8, 2, u8 },
                else => @compileError("source must be of type R8, R16, RM or IM8"),
            }
        };

        const bitType = comptime blkT: {
            if (bitTypeDst != bitTypeSrc) {
                @compileError("dest and source must be of the same bit type");
            } else {
                break :blkT bitTypeDst;
            }
        };

        const _inline = struct {
            fn execute(cpu: *Cpu) void {
                const destValue = getDst(cpu, dest);
                const sourceValue = getSrc(cpu, source);

                const res = ops.asFn(bitType)(destValue, sourceValue, cpu.reg.single.f.c);

                // Flags ZxHC => x depends on ops (on non 16bit-ops)
                // Flags -xHC => x depends on ops (on 16bit-ops)
                var flags = cpu.reg.single.f;
                if (editZ) flags.z = res.value == 0;
                flags.n = ops.setNFlags();
                flags.h = res.halfCarry;
                flags.c = res.carry;
                cpu.reg.single.f = flags;

                if (ops != .CP) setDst(cpu, dest, res.value); // Do not store result if CP
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

const _ADD_09: Instruction = op.arithmetic(.ADD, R16.hl, R16.bc);
const _ADD_19: Instruction = op.arithmetic(.ADD, R16.hl, R16.de);
const _ADD_29: Instruction = op.arithmetic(.ADD, R16.hl, R16.hl);
const _ADD_39: Instruction = op.arithmetic(.ADD, R16.hl, R16.sp);

const _ADD_80: Instruction = op.arithmetic(.ADD, R8.a, R8.b);
const _ADD_81: Instruction = op.arithmetic(.ADD, R8.a, R8.c);
const _ADD_82: Instruction = op.arithmetic(.ADD, R8.a, R8.d);
const _ADD_83: Instruction = op.arithmetic(.ADD, R8.a, R8.e);
const _ADD_84: Instruction = op.arithmetic(.ADD, R8.a, R8.h);
const _ADD_85: Instruction = op.arithmetic(.ADD, R8.a, R8.l);
const _ADD_86: Instruction = op.arithmetic(.ADD, R8.a, RM.hl);
const _ADD_C6: Instruction = op.arithmetic(.ADD, R8.a, IM8{});
const _ADD_87: Instruction = op.arithmetic(.ADD, R8.a, R8.a);

const _ADD_E8: Instruction = .{
    .execute = op.add_e8,
    .metadata = .{
        .name = "ADD SP, i8",
        .cycles = 4,
    },
};

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
const __OR_B6: Instruction = op.bits(.OR, R8.a, RM.hl);
const __OR_F6: Instruction = op.bits(.OR, R8.a, IM8{});
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
pub const OPCODES: [256]Instruction = .{
    //0x00,  0x01,    0x02,    0x03,    0x04,    0x05,    0x06,    0x07,    0x08,    0x09,    0x0A,    0x0B,    0x0C,    0x0D,    0x0E,    0x0F,
    _NOP_00, __LD_01, __LD_02, _INC_03, _INC_04, _DEC_05, __LD_06, U(0x07), __LD_08, _ADD_09, __LD_0A, _DEC_0B, _INC_0C, _DEC_0D, __LD_0E, U(0x0F), // 0x00
    U(0x10), __LD_11, __LD_12, _INC_13, _INC_14, _DEC_15, __LD_16, U(0x17), U(0x18), _ADD_19, __LD_1A, _DEC_1B, _INC_1C, _DEC_1D, __LD_1E, U(0x1F), // 0x10
    U(0x20), __LD_21, __LD_22, _INC_23, _INC_24, _DEC_25, __LD_26, U(0x27), U(0x28), _ADD_29, __LD_2A, _DEC_2B, _INC_2C, _DEC_2D, __LD_2E, U(0x2F), // 0x20
    U(0x30), __LD_31, __LD_32, _INC_33, _INC_34, _DEC_35, __LD_36, U(0x37), U(0x38), _ADD_39, __LD_3A, _DEC_3B, _INC_3C, _DEC_3D, __LD_3E, U(0x3F), // 0x30
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
    __LD_E0, U(0xE1), __LD_E2, U(0xE3), U(0xE4), U(0xE5), _AND_E6, U(0xE7), _ADD_E8, U(0xE9), __LD_EA, U(0xEB), U(0xEC), U(0xED), _XOR_EE, U(0xEF), // 0xE0
    __LD_F0, U(0xF1), __LD_F2, U(0xF3), U(0xF4), U(0xF5), __OR_F6, U(0xF7), __LD_F8, __LD_F9, __LD_FA, U(0xFB), U(0xFC), U(0xFD), __CP_FE, U(0xFF), // 0xF0
};
