const builtin = @import("builtin");
const std = @import("std");

const memory = @import("./memory.zig");

const STACK_START: u16 = memory.Memory.STACK_START;
pub const PROGRAM_START: u16 = memory.Memory.PROGRAM_START;

comptime {
    // Sanity: Flags must be exactly one byte
    if (@sizeOf(Flags) != 1) @compileError("Flags must be 1 byte.");
}

pub const Flags = packed struct {
    // Flags is initialized to 0b10110000 (0xB0)

    const __unusedLEType = if (builtin.target.cpu.arch.endian() == .little) u4 else void;
    const __unusedBEType = if (builtin.target.cpu.arch.endian() == .big) u4 else void;

    __unusedLE: __unusedLEType = if (__unusedLEType == void) {} else 0,

    c: bool = true, // Carry Flag
    h: bool = true, // Half Carry Flag
    n: bool = false, // Subtract Flag
    z: bool = true, // Zero Flag

    __unusedBE: __unusedBEType = if (__unusedBEType == void) {} else 0,

    pub inline fn init() Flags {
        return Flags{};
    }

    pub inline fn zeroed() Flags {
        return Flags{
            .z = false,
            .n = false,
            .h = false,
            .c = false,
        };
    }
};

const Pairs = packed struct {
    af: u16 = 0,
    bc: u16 = 0,
    de: u16 = 0,
    hl: u16 = 0,

    sp: u16 = STACK_START,
    pc: u16 = 0,
};

/// 16-bit registers
pub const Register16 = enum(usize) {
    af = 0,
    bc = 1,
    de = 2,
    hl = 3,
    sp = 4,
    pc = 5,
};

/// 16-bit registers that can be used to access memory indirectly
pub const Register16Memory = enum(usize) {
    bc = @intFromEnum(Register16.bc),
    de = @intFromEnum(Register16.de),
    hl = @intFromEnum(Register16.hl),

    pub fn asReg16(self: Register16Memory) Register16 {
        const value = @intFromEnum(self);
        const reg: Register16 = @enumFromInt(value);
        return reg;
    }
};

const SingleLE = packed struct {
    f: Flags = .{},
    a: u8 = 0,

    c: u8 = 0,
    b: u8 = 0,

    e: u8 = 0,
    d: u8 = 0,

    l: u8 = 0,
    h: u8 = 0,

    __unused: std.meta.Int(.unsigned, 16 * 2) = 0, // PC and SP are not part of 8-bit registers
};

pub const Register8Le = enum(usize) {
    f = 0,
    a = 1,

    c = 2,
    b = 3,

    e = 4,
    d = 5,

    l = 6,
    h = 7,
};

const SingleBE = packed struct {
    a: u8 = 0,
    f: Flags = .{},

    b: u8 = 0,
    c: u8 = 0,

    d: u8 = 0,
    e: u8 = 0,

    h: u8 = 0,
    l: u8 = 0,

    __unused: u32 = 0, // PC and SP are not part of 8-bit registers
};

pub const Register8Be = enum(usize) {
    a = 0,
    f = 1,

    b = 2,
    c = 3,

    d = 4,
    e = 5,

    h = 6,
    l = 7,
};

pub fn asText(comptime reg: anytype) []const u8 {
    comptime {
        const regType = @TypeOf(reg);

        if (regType == Register8) {
            switch (reg) {
                .a => return "A",
                .b => return "B",
                .c => return "C",
                .d => return "D",
                .e => return "E",
                .f => return "F",
                .h => return "H",
                .l => return "L",
            }
        } else if (regType == Register16) {
            switch (reg) {
                .af => return "AF",
                .bc => return "BC",
                .de => return "DE",
                .hl => return "HL",
                .sp => return "SP",
                .pc => return "PC",
            }
        } else if (regType == Register16Memory) {
            switch (reg) {
                .bc => return "(BC)",
                .de => return "(DE)",
                .hl => return "(HL)",
            }
        } else {
            @compileError("Unsupported register type");
        }
    }
}

// Select the correct endianess for the Single representation
const Single = if (builtin.target.cpu.arch.endian() == .little) SingleLE else SingleBE;
pub const Register8 = if (builtin.target.cpu.arch.endian() == .little) Register8Le else Register8Be;

comptime {
    // Sanity: Ensure Single and Pairs have the same size
    if (@sizeOf(Single) != @sizeOf(Pairs)) {
        @compileError("Single and Pairs size mismatch");
    }
}

/// Cpu registers
pub const Registers = packed union {

    // Access to 16-bit registers
    pair: Pairs,

    // Access to 8-bit registers
    single: Single,

    pub inline fn init() Registers {
        var regs: Registers = undefined;

        regs.pair.pc = PROGRAM_START;
        regs.pair.sp = STACK_START;

        regs.single.a = 0x01;
        regs.single.b = 0x00;
        regs.single.c = 0x13;
        regs.single.d = 0x00;
        regs.single.e = 0xD8;
        regs.single.f = Flags.init(); // Flags init to 0xB0
        regs.single.h = 0x01;
        regs.single.l = 0x4D;

        return regs;
    }

    const _rawSingle = [@bitSizeOf(Registers) / @bitSizeOf(u8)]u8;

    inline fn asRawSingle(self: *Registers) *_rawSingle {
        return @as(*_rawSingle, @ptrCast(self));
    }

    inline fn asRawSingleConst(self: *const Registers) *const _rawSingle {
        return @as(*const _rawSingle, @ptrCast(self));
    }

    pub inline fn get8(self: *const Registers, reg: Register8) u8 {
        const raw = self.asRawSingleConst();
        return raw[@intFromEnum(reg)];
    }

    pub inline fn set8(self: *Registers, reg: Register8, value: u8) void {
        const raw = self.asRawSingle();
        raw[@intFromEnum(reg)] = value;
    }

    const _rawPairs = [@bitSizeOf(Registers) / @bitSizeOf(u16)]u16;
    inline fn asRawPairs(self: *Registers) *_rawPairs {
        return @as(*_rawPairs, @ptrCast(self));
    }
    inline fn asRawPairsConst(self: *const Registers) *const _rawPairs {
        return @as(*const _rawPairs, @ptrCast(self));
    }

    pub inline fn get16(self: *const Registers, reg: Register16) u16 {
        const raw = self.asRawPairsConst();
        return raw[@intFromEnum(reg)];
    }

    pub inline fn set16(self: *Registers, reg: Register16, value: u16) void {
        const raw = self.asRawPairs();
        raw[@intFromEnum(reg)] = value;
    }
};
