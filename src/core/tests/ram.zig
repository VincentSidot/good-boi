const std = @import("std");

const ram = @import("../cpu/ram.zig");

const Memory = ram.Memory;

test "RAW RAM read/write" {
    var _ram = Memory.init();

    _ram.writeByte(0x1234, 0xAB);
    const value = _ram.readByte(0x1234);

    try std.testing.expect(value == 0xAB);
}
