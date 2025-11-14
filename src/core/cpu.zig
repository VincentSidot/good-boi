const utils = @import("../utils.zig");

const register = @import("./cpu/register.zig");
const instruction = @import("./cpu/instruction.zig");
const math = @import("./cpu/math.zig");
const memory = @import("./cpu/memory.zig");

const Registers = register.Registers;
const Memory = memory.Memory;

pub const Cpu = struct {
    reg: Registers = Registers.zeroed(),
    mem: Memory = Memory.init(),

    pub fn init() Cpu {
        return Cpu{};
    }

    pub fn fetch(self: *Cpu) u8 {
        if (self.reg.pair.pc == Memory.RAM_SIZE - 1) {
            @panic("Program counter out of bounds");
        }

        const opcode = self.mem.readByte(self.reg.pair.pc);
        self.reg.pair.pc += 1;

        return opcode;
    }

    pub fn fetch16(self: *Cpu) u16 {
        const low = self.fetch();
        const high = self.fetch();

        const value: u16 = math.mergeBytes(low, high);
        return value;
    }

    pub fn pop(self: *Cpu) u16 {
        if (self.reg.pair.sp == Memory.STACK_START) {
            @panic("Stack underflow");
        } else if (self.reg.pair.sp + 1 >= Memory.STACK_START) {
            @panic("Stack overflow");
        }
        defer {
            self.reg.pair.sp += 2;
        }

        const low = self.mem.readByte(self.reg.pair.sp);
        const high = self.mem.readByte(self.reg.pair.sp + 1);

        return math.mergeBytes(low, high);
    }

    pub fn push(self: *Cpu, value: u16) void {
        self.reg.pair.sp -= 2;

        const valueSplit = math.splitBytes(value);

        self.mem.writeByte(self.reg.pair.sp, valueSplit.low);
        self.mem.writeByte(self.reg.pair.sp + 1, valueSplit.high);
    }

    pub fn getPC(self: *const Cpu) u16 {
        return self.reg.pair.pc;
    }

    pub fn setPC(self: *Cpu, address: u16) void {
        self.reg.pair.pc = address;
    }

    /// Executes a single CPU step and returns the number of cycles taken.
    pub fn step(self: *Cpu) u8 {
        const opcode = self.fetch();
        const inst = instruction.getOpcode(opcode);
        utils.log.debug("0x{X:4}: {s}", .{ self.reg.pair.pc - 1, inst.metadata.name });
        return inst.execute(self);
    }
};

test {
    const std = @import("std");

    const registerTest = @import("tests/register.zig");
    const instructionTest = @import("tests/instruction.zig");
    const mathTest = @import("tests/math.zig");
    const memoryTest = @import("tests/memory.zig");
    const cpuTest = @import("tests/cpu.zig");

    std.testing.refAllDecls(registerTest);
    std.testing.refAllDecls(instructionTest);
    std.testing.refAllDecls(mathTest);
    std.testing.refAllDecls(memoryTest);
    std.testing.refAllDecls(cpuTest);
}
