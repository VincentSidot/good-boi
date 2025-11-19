const utils = @import("../utils.zig");

const register = @import("./cpu/register.zig");
const instruction = @import("./cpu/instruction.zig");
const math = @import("./cpu/math.zig");
const memory = @import("./cpu/memory.zig");

const Registers = register.Registers;
const Memory = memory.Memory;

pub const Cpu = struct {
    const Self = @This();

    /// CPU Registers
    reg: Registers = Registers.init(),
    /// CPU Memory
    mem: Memory = Memory.init(),
    /// Interrupts enabled flag
    irqEnabled: bool,
    /// CPU halted flag
    halted: bool = false,
    /// Total CPU cycles executed
    cycles: u64 = 0,

    pub fn init() Self {
        return Self{
            .reg = Registers.init(),
            .mem = Memory.init(),

            .irqEnabled = false,
            .halted = false,
            .cycles = 0,
        };
    }

    pub fn fetch(self: *Self) u8 {
        if (self.reg.pair.pc == Memory.RAM_SIZE - 1) {
            @panic("Program counter out of bounds");
        }

        const opcode = self.mem.read(self.reg.pair.pc);
        self.reg.pair.pc += 1;

        return opcode;
    }

    pub fn fetch16(self: *Self) u16 {
        const low = self.fetch();
        const high = self.fetch();

        const value: u16 = math.mergeBytes(low, high);
        return value;
    }

    pub fn pop(self: *Self) u16 {
        if (self.reg.pair.sp == Memory.STACK_START) {
            @panic("Stack underflow");
        } else if (self.reg.pair.sp + 1 >= Memory.STACK_START) {
            @panic("Stack overflow");
        }
        defer {
            self.reg.pair.sp += 2;
        }

        const low = self.mem.read(self.reg.pair.sp);
        const high = self.mem.read(self.reg.pair.sp + 1);

        return math.mergeBytes(low, high);
    }

    pub fn push(self: *Self, value: u16) void {
        self.reg.pair.sp -= 2;

        const valueSplit = math.splitBytes(value);

        self.mem.write(self.reg.pair.sp, valueSplit.low);
        self.mem.write(self.reg.pair.sp + 1, valueSplit.high);
    }

    pub fn getPC(self: *const Self) u16 {
        return self.reg.pair.pc;
    }

    pub fn setPC(self: *Self, address: u16) void {
        self.reg.pair.pc = address;
    }

    pub fn setIRQ(self: *Self, enabled: bool) void {
        self.irqEnabled = enabled;
    }

    pub fn setHalted(self: *Self, halted: bool) void {
        self.halted = halted;
    }

    /// Executes a single CPU step and returns the number of cycles taken.
    pub fn step(self: *Self) u8 {
        if (self.halted) {
            @branchHint(.cold); // Halted state is uncommon during normal execution
            return 1; // No cycles consumed when halted
        }

        const opcode = self.fetch();
        const inst = instruction.getOpcode(opcode);
        utils.log.debug("0x{X:04}: {s}", .{ self.reg.pair.pc - 1, inst.metadata.name });
        const cycle = inst.execute(self);
        self.cycles += @intCast(cycle);

        return cycle;
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
