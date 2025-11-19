const std = @import("std");

const _memory = @import("../cpu/memory.zig");

const Memory = _memory.Memory;

test "RAW MEM read/write" {
    var memory = Memory.init();

    const addr = Memory.RAM_START + 0x0012;

    memory.write(addr, 0xAB);
    const value = memory.read(addr);

    try std.testing.expect(value == 0xAB);
}
