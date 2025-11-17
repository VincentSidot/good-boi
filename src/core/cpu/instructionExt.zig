const std = @import("std");
const utils = @import("../../utils.zig");
const cpuZig = @import("../cpu.zig");
const math = @import("math.zig");
const register = @import("./register.zig");
const memory = @import("./memory.zig");
const i = @import("./instruction.zig");

const Cpu = cpuZig.Cpu;

const Registers = register.Registers;
const Register8 = register.Register8;
const Register16 = register.Register16;
const Register16Memory = register.Register16Memory;
const Flags = register.Flags;
const Instruction = i.Instruction;

const Memory = memory.Memory;

const R8 = i.R8;
const RM = i.RM;

const TR = union(enum) {
    reg8: R8,
    reg16m: RM,
};

const FlagsOperation = enum {
    set,
    clear,
    depends,
    ignore,
};

const TargetFlag = enum {
    z,
    n,
    h,
    c,

    inline fn get(flag: TargetFlag, cpu: *Cpu) bool {
        const flagBits = cpu.reg.single.f;
        switch (flag) {
            .z => return flagBits.z,
            .n => return flagBits.n,
            .h => return flagBits.h,
            .c => return flagBits.c,
        }
    }

    inline fn set(flag: TargetFlag, cpu: *Cpu, value: bool) void {
        switch (flag) {
            .z => cpu.reg.single.f.z = value,
            .n => cpu.reg.single.f.n = value,
            .h => cpu.reg.single.f.h = value,
            .c => cpu.reg.single.f.c = value,
        }
    }
};

const FlagEffect = struct {
    flag: TargetFlag,
    operation: FlagsOperation,

    pub inline fn handle(self: FlagEffect, cpu: *Cpu, zero: bool, carry: bool) void {
        switch (self.operation) {
            .set => TargetFlag.set(self.flag, cpu, true),
            .clear => TargetFlag.set(self.flag, cpu, false),
            .depends => {
                switch (self.flag) {
                    .z => {
                        TargetFlag.set(self.flag, cpu, zero);
                    },
                    .c => {
                        TargetFlag.set(self.flag, cpu, carry);
                    },
                    else => @panic("Unhandled flag dependency"),
                }
            },
            .ignore => {},
        }
    }
};

pub const ExtendedOp = union(enum) {
    const OPTS = buildOptsTable();

    // Extended operations
    rlc: void,
    rrc: void,
    rl: void,
    rr: void,
    sla: void,
    sra: void,
    swap: void,
    srl: void,
    bit: u3,
    res: u3,
    set: u3,

    // NonExtended rotate operations
    rlca: void,
    rla: void,
    rrca: void,
    rra: void,

    fn buildOptsTable() [32]ExtendedOp {
        var table: [32]ExtendedOp = undefined;

        table[0] = .rlc;
        table[1] = .rrc;
        table[2] = .rl;
        table[3] = .rr;
        table[4] = .sla;
        table[5] = .sra;
        table[6] = .swap;
        table[7] = .srl;

        var index: usize = 8;

        for (0..8) |bitPos| {
            table[index] = .{ .bit = @as(u3, bitPos) };
            index += 1;
        }

        for (0..8) |bitPos| {
            table[index] = .{ .res = @as(u3, bitPos) };
            index += 1;
        }

        for (0..8) |bitPos| {
            table[index] = .{ .set = @as(u3, bitPos) };
            index += 1;
        }

        if (index != table.len) {
            @panic("ExtendedOp buildOptsTable logic error");
        }

        return table;
    }

    pub fn asText(comptime self: ExtendedOp) []const u8 {
        switch (self) {
            .rlc => return "RLC",
            .rrc => return "RRC",
            .rl => return "RL",
            .rr => return "RR",
            .sla => return "SLA",
            .sra => return "SRA",
            .swap => return "SWAP",
            .srl => return "SRL",
            .bit => |bitPos| {
                return std.fmt.comptimePrint("BIT {d},", .{bitPos});
            },
            .res => |bitPos| {
                return std.fmt.comptimePrint("RES {d},", .{bitPos});
            },
            .set => |bitPos| {
                return std.fmt.comptimePrint("SET {d},", .{bitPos});
            },
            .rlca => return "RLCA",
            .rla => return "RLA",
            .rrca => return "RRCA",
            .rra => return "RRA",
        }
    }

    pub fn getOperation(comptime self: ExtendedOp) fn (u8, Flags) callconv(.@"inline") OperationResult {
        const _inline = struct {
            inline fn swap(value: u8, _: Flags) OperationResult {
                const res = (value << 4) | (value >> 4);
                return .{
                    .value = res,
                    .zero = res == 0,
                };
            }
        };

        switch (self) {
            .rlc, .rlca => return rotateFactory(true, true),
            .rrc, .rrca => return rotateFactory(false, true),
            .rl, .rla => return rotateFactory(true, false),
            .rr, .rra => return rotateFactory(false, false),
            .sla => return shiftFactory(true, false), // no arithmetic for left shift
            .sra => return shiftFactory(false, true),
            .swap => return _inline.swap,
            .srl => return shiftFactory(false, false),
            .bit => |bitPos| {
                return testBitFactory(bitPos);
            },
            .res => |bitPos| {
                return writeBitFactory(bitPos, false);
            },
            .set => |bitPos| {
                return writeBitFactory(bitPos, true);
            },
        }
    }

    fn valueCouldBeUpdated(comptime self: ExtendedOp) bool {
        switch (self) {
            .bit => return false,
            else => return true,
        }
    }

    pub fn getFlagEffect(comptime self: ExtendedOp) [4]FlagEffect {
        switch (self) {
            .rlc,
            .rrc,
            .rl,
            .rr,
            .sla,
            .sra,
            .srl,
            => return .{
                .{ .flag = .z, .operation = .depends },
                .{ .flag = .n, .operation = .clear },
                .{ .flag = .h, .operation = .clear },
                .{ .flag = .c, .operation = .depends },
            },
            .swap => return .{
                .{ .flag = .z, .operation = .depends },
                .{ .flag = .n, .operation = .clear },
                .{ .flag = .h, .operation = .clear },
                .{ .flag = .c, .operation = .clear },
            },
            .bit => return .{
                .{ .flag = .z, .operation = .depends },
                .{ .flag = .n, .operation = .clear },
                .{ .flag = .h, .operation = .set },
                .{ .flag = .c, .operation = .ignore },
            },
            .res, .set => return .{
                .{ .flag = .z, .operation = .ignore },
                .{ .flag = .n, .operation = .ignore },
                .{ .flag = .h, .operation = .ignore },
                .{ .flag = .c, .operation = .ignore },
            },
            .rlca, .rla, .rrca, .rra => return .{
                .{ .flag = .z, .operation = .clear },
                .{ .flag = .n, .operation = .clear },
                .{ .flag = .h, .operation = .clear },
                .{ .flag = .c, .operation = .depends },
            },
        }
    }

    const OperationResult = struct {
        value: u8,
        carry: bool = undefined,
        zero: bool = undefined,
    };

    const OperationFn = fn (u8, Flags) callconv(.@"inline") OperationResult;

    fn rotateFactory(comptime left: bool, comptime addCarry: bool) OperationFn {
        const _inline = struct {
            inline fn execute(value: u8, flags: Flags) OperationResult {
                const _fn = comptime blkFn: {
                    if (left) {
                        break :blkFn std.math.rotl;
                    } else {
                        break :blkFn std.math.rotr;
                    }
                };

                const carryOut: bool = if (left) value & 0x80 != 0 else value & 0x01 != 0; // Look the msb/lsb of original value

                var res: u8 = _fn(u8, value, 1);

                if (addCarry) {
                    const carryIn: bool = flags.c;

                    const mask: u8 = if (left) 0xFE else 0x7F;
                    const setBit: u8 = if (left) 0x01 else 0x80;

                    if (carryIn) {
                        res = res & mask | setBit;
                    } else {
                        res = res & mask;
                    }
                }

                return .{
                    .value = res,
                    .carry = carryOut,
                    .zero = res == 0,
                };
            }
        };

        return _inline.execute;
    }

    fn shiftFactory(comptime left: bool, arith: bool) OperationFn {
        if (left and arith) {
            @compileError("Shift left is not compatible with arithmetic flag");
        }

        const _inline = struct {
            inline fn execute(value: u8, _: Flags) OperationResult {
                const carryOut: bool = if (left) value & 0x80 != 0 else value & 0x01 != 0; // Look the msb/lsb of original value
                var res: u8 = if (left) value << 1 else value >> 1;
                if (arith) {
                    const msb = value & 0x80;
                    res = res | msb;
                }

                return .{
                    .value = res,
                    .carry = carryOut,
                    .zero = res == 0,
                };
            }
        };

        return _inline.execute;
    }

    fn testBitFactory(comptime bitPos: comptime_int) OperationFn {
        const _inline = struct {
            inline fn execute(value: u8, _: Flags) OperationResult {
                const bitMask: u8 = 1 << bitPos;
                const bitSet = (value & bitMask) != 0;

                return .{
                    .value = value, // Value is unchanged
                    .zero = !bitSet,
                };
            }
        };

        return _inline.execute;
    }

    fn writeBitFactory(comptime bitPos: comptime_int, bitValue: bool) OperationFn {
        const _inline = struct {
            inline fn execute(value: u8, _: Flags) OperationResult {
                const bitMask: u8 = 1 << bitPos;
                const res: u8 = if (bitValue) value | bitMask else value & ~bitMask;

                return .{
                    .value = res,
                };
            }
        };

        return _inline.execute;
    }
};

fn setVoid(_: *Cpu, _: anytype, _: anytype) void {}

const op = struct {
    fn getOp(eop: ExtendedOp, input: TR) Instruction {
        const reg, const getValue, const setValue, const cycles = comptime blk: {
            switch (input) {
                .reg8 => |reg| {
                    break :blk .{
                        reg,
                        i.getReg8,
                        if (eop.valueCouldBeUpdated()) i.setReg8 else setVoid,
                        2, // 2 cycles for register operations
                    };
                },
                .reg16m => |reg| {
                    break :blk .{
                        reg,
                        i.getMemory(i.RegisterMemoryOperation._nop),
                        if (eop.valueCouldBeUpdated()) i.setMemory(i.RegisterMemoryOperation._nop) else setVoid,
                        4, // 4 cycles for memory operations
                    };
                },
            }
        };

        const operation = eop.getOperation();
        const flagEffect = eop.getFlagEffect();

        const _inline = struct {
            fn execute(cpu: *Cpu) u8 {
                const value = getValue(cpu, reg);

                const res = operation(value, cpu.reg.single.f);

                for (flagEffect) |fe| {
                    fe.handle(
                        cpu,
                        res.zero,
                        res.carry,
                    );
                }

                setValue(
                    cpu,
                    reg,
                    res.value,
                );

                return cycles;
            }
        };

        return Instruction{
            .execute = _inline.execute,
            .metadata = .{
                .name = std.fmt.comptimePrint(
                    "{s} {s}",
                    .{ eop.asText(), i.regAsText(reg) },
                ),
            },
        };
    }
};

fn makeExtendedOpcodeTable() [256]Instruction {
    @setEvalBranchQuota(200_000);
    var table: [256]Instruction = undefined;

    const REGISTER_ORDER = [_]TR{
        .{ .reg8 = R8.b },
        .{ .reg8 = R8.c },
        .{ .reg8 = R8.d },
        .{ .reg8 = R8.e },
        .{ .reg8 = R8.h },
        .{ .reg8 = R8.l },
        .{ .reg16m = RM.hl },
        .{ .reg8 = R8.a },
    };

    var start_index: usize = 0;

    for (ExtendedOp.OPTS) |eop| {
        for (REGISTER_ORDER) |reg| {
            const instr = op.getOp(eop, reg);
            table[start_index] = instr;
            start_index += 1;
        }
    }

    return table;
}

pub const OPCODES_EXT: [256]Instruction = makeExtendedOpcodeTable();
