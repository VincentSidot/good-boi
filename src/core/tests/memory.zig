const std = @import("std");

const _memory = @import("../cpu/memory.zig");

const Memory = _memory.Memory;

test "RAW MEM read/write" {
    var memory = Memory.init();

    memory.writeByte(0x1234, 0xAB);
    const value = memory.readByte(0x1234);

    try std.testing.expect(value == 0xAB);
}
