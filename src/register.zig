const builtin = @import("builtin");

comptime {
    // Sanity: Flags must be exactly one byte
    if (@sizeOf(Flags) != 1) @compileError("Flags must be 1 byte.");
}

pub const Flags = packed struct {
    __unused: u4 = 0,

    c: bool = false, // Carry Flag
    h: bool = false, // Half Carry Flag
    n: bool = false, // Subtract Flag
    z: bool = false, // Zero Flag

    pub inline fn zeroed() Flags {
        return Flags{};
    }
};

const Pairs = packed struct {
    af: u16 = 0,
    bc: u16 = 0,
    de: u16 = 0,
    hl: u16 = 0,

    sp: u16 = 0,
    pc: u16 = 0,
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

    __unused: u32 = 0, // PC and SP are not part of 8-bit registers
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

// Select the correct endianess for the Single representation
const Single = if (builtin.target.cpu.arch.endian() == .little) SingleLE else SingleBE;

/// Cpu registers
pub const Registers = packed union {

    // Access to 16-bit registers
    pair: Pairs,

    // Access to 8-bit registers
    single: Single,

    pub inline fn zeroed() Registers {
        return Registers{ .pair = .{} };
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
    const std = @import("std");

    var reg: Registers = .{ .single = .{
        .b = 0x12,
        .c = 0x34,
    } };

    try std.testing.expect(getBC(&reg) == reg.pair.bc);
}

test "regsiter" {
    const std = @import("std");
    var reg: Registers = .{ .pair = .{ .af = 0xAEB0 } };

    std.debug.print("Reg: {any}\n", .{reg});

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

    std.debug.print("Reg2: {any}\n", .{reg2});

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
