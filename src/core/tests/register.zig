const std = @import("std");

const register = @import("../cpu/register.zig");

const Registers = register.Registers;
const Register8 = register.Register8;
const Register16 = register.Register16;

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
