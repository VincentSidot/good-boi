const builtin = @import("builtin");
const std = @import("std");

comptime {
    // Sanity: Flags must be exactly one byte
    if (@sizeOf(Flags) != 1) @compileError("Flags must be 1 byte.");
}

pub const FlagsLe = packed struct {
    __unused: u4 = 0,

    c: bool = false, // Carry Flag
    h: bool = false, // Half Carry Flag
    n: bool = false, // Subtract Flag
    z: bool = false, // Zero Flag

    pub inline fn zeroed() FlagsLe {
        return FlagsLe{};
    }
};

pub const FlagsBe = packed struct {
    z: bool = false, // Zero Flag
    n: bool = false, // Subtract Flag
    h: bool = false, // Half Carry Flag
    c: bool = false, // Carry Flag

    __unused: u4 = 0,

    pub inline fn zeroed() FlagsBe {
        return FlagsBe{};
    }
};

pub const Flags = if (builtin.target.cpu.arch.endian() == .little) FlagsLe else FlagsBe;

const Pairs = packed struct {
    af: u16 = 0,
    bc: u16 = 0,
    de: u16 = 0,
    hl: u16 = 0,

    sp: u16 = 0,
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

    pub inline fn zeroed() Registers {
        return Registers{ .pair = .{} };
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

fn getBC(reg: *const Registers) u16 {
    const b: u16 = @intCast(reg.single.b);
    const c: u16 = @intCast(reg.single.c);

    return (b << 8) | c;

    // (self.b as u16) << 8
    // | self.c as u16
}

test "endianess" {
    var reg: Registers = .{ .single = .{
        .b = 0x12,
        .c = 0x34,
    } };

    try std.testing.expect(getBC(&reg) == reg.pair.bc);
}

test "regsiter" {
    var reg: Registers = .{ .pair = .{ .af = 0xAEB0 } };

    // std.debug.print("Reg: {any}\n", .{reg});

    try std.testing.expect(reg.single.a == 0xAE);

    try std.testing.expect(reg.single.f.z == true);
    try std.testing.expect(reg.single.f.n == false);
    try std.testing.expect(reg.single.f.h == true);
    try std.testing.expect(reg.single.f.c == true);

    reg.single.a = 0xF0;
    try std.testing.expect(reg.pair.af == 0xF0B0);

    var reg2 = Registers.zeroed();

    reg2.pair.af = 0xDEAD;
    reg2.pair.bc = 0xBEEF;
    reg2.pair.de = 0xCAFE;
    reg2.pair.hl = 0xBABE;

    // std.debug.print("Reg2: {any}\n", .{reg2});

    try std.testing.expect(reg2.single.a == 0xDE);
    try std.testing.expect(reg2.single.f.z == true);
    try std.testing.expect(reg2.single.f.n == false);
    try std.testing.expect(reg2.single.f.h == true);
    try std.testing.expect(reg2.single.f.c == false);

    try std.testing.expect(reg2.single.b == 0xBE);
    try std.testing.expect(reg2.single.c == 0xEF);

    try std.testing.expect(reg2.single.d == 0xCA);
    try std.testing.expect(reg2.single.e == 0xFE);

    try std.testing.expect(reg2.single.h == 0xBA);
    try std.testing.expect(reg2.single.l == 0xBE);
}

test "raw access" {
    var reg = Registers.zeroed();

    reg.set8(Register8.a, 0x12);
    reg.set16(Register16.bc, 0xDEAD);

    try std.testing.expect(reg.get16(Register16.af) == 0x1200);
    try std.testing.expect(reg.get8(Register8.b) == 0xde);
    try std.testing.expect(reg.get8(Register8.c) == 0xad);
}
