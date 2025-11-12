const register = @import("./cpu/register.zig");
const instruction = @import("./cpu/instruction.zig");
const math = @import("./cpu/math.zig");
const ram = @import("./cpu/ram.zig");

const Registers = register.Registers;
const Memory = ram.Memory;

pub const Cpu = struct {
    reg: Registers = Registers.zeroed(),
    ram: Memory = Memory.init(),
};

test {
    const std = @import("std");

    std.testing.refAllDecls(register);
    std.testing.refAllDecls(instruction);
    std.testing.refAllDecls(math);
    std.testing.refAllDecls(ram);
}
