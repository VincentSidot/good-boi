const register = @import("./cpu/register.zig");
const instruction = @import("./cpu/instruction.zig");
const math = @import("./cpu/math.zig");
const ram = @import("./cpu/ram.zig");

const Registers = register.Registers;
const Memory = ram.Memory;

pub const Cpu = struct {
    reg: Registers = Registers.zeroed(),
    ram: Memory = Memory.init(),

    pub fn init() Cpu {
        return Cpu{};
    }

    pub fn fetch(self: *Cpu) u8 {
        const opcode = self.ram.readByte(self.reg.pair.pc);
        self.reg.pair.pc += 1;

        return opcode;
    }

    pub fn fetch16(self: *Cpu) u16 {
        const low = self.fetch();
        const high = self.fetch();

        const value: u16 = math.mergeBytes(low, high);
        return value;
    }
};

test {
    const std = @import("std");

    const registerTest = @import("tests/register.zig");
    const instructionTest = @import("tests/instruction.zig");
    const mathTest = @import("tests/math.zig");
    const ramTest = @import("tests/ram.zig");

    std.testing.refAllDecls(registerTest);
    std.testing.refAllDecls(instructionTest);
    std.testing.refAllDecls(mathTest);
    std.testing.refAllDecls(ramTest);
}
