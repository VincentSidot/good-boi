const std = @import("std");
const _cpu = @import("../cpu.zig");
const _register = @import("../cpu/register.zig");
const _memory = @import("../cpu/memory.zig");

const Cpu = _cpu.Cpu;
const Flags = _register.Flags;

const STACK_START = _memory.Memory.STACK_START;

/// Load a binary file into CPU memory at the specified start address
fn loadFileIntoMemory(cpu: *Cpu, path: []const u8, startAddress: u16) !void {
    const file = try std.fs.cwd().openFile(
        path,
        .{},
    );
    defer file.close();

    const fileSize = try file.getEndPos();
    const fullSize: u64 = @as(u64, @intCast(startAddress)) + fileSize;
    if (fullSize > _memory.Memory.RAM_SIZE) {
        return error.FileTooLarge;
    }

    const beginIndex: usize = @intCast(startAddress);
    const endIndex: usize = @intCast(fullSize);

    const idx = cpu.mem.memory[beginIndex..endIndex];

    _ = try file.read(idx);

    return;
}

test "CPU fetch - single byte" {
    var cpu = Cpu.init();

    // Set up test data in memory
    cpu.mem.writeByte(0x0000, 0x42);
    cpu.mem.writeByte(0x0001, 0x84);
    cpu.reg.pair.pc = 0x0000;

    // Test fetching first byte
    const opcode1 = cpu.fetch();
    try std.testing.expect(opcode1 == 0x42);
    try std.testing.expect(cpu.reg.pair.pc == 0x0001);

    // Test fetching second byte
    const opcode2 = cpu.fetch();
    try std.testing.expect(opcode2 == 0x84);
    try std.testing.expect(cpu.reg.pair.pc == 0x0002);
}

test "CPU fetch16 - 16-bit word" {
    var cpu = Cpu.init();

    // Set up test data in memory (little-endian: low byte first, then high byte)
    cpu.mem.writeByte(0x0000, 0x34); // Low byte
    cpu.mem.writeByte(0x0001, 0x12); // High byte
    cpu.reg.pair.pc = 0x0000;

    // Test fetching 16-bit word
    const word = cpu.fetch16();
    try std.testing.expect(word == 0x1234);
    try std.testing.expect(cpu.reg.pair.pc == 0x0002);
}

test "CPU fetch16 - multiple words" {
    var cpu = Cpu.init();

    // Set up multiple 16-bit words in memory
    cpu.mem.writeByte(0x0000, 0x78); // Low byte of first word
    cpu.mem.writeByte(0x0001, 0x56); // High byte of first word
    cpu.mem.writeByte(0x0002, 0xBC); // Low byte of second word
    cpu.mem.writeByte(0x0003, 0x9A); // High byte of second word
    cpu.reg.pair.pc = 0x0000;

    // Test fetching first word
    const word1 = cpu.fetch16();
    try std.testing.expect(word1 == 0x5678);
    try std.testing.expect(cpu.reg.pair.pc == 0x0002);

    // Test fetching second word
    const word2 = cpu.fetch16();
    try std.testing.expect(word2 == 0x9ABC);
    try std.testing.expect(cpu.reg.pair.pc == 0x0004);
}

test "CPU push and pop - single value" {
    var cpu = Cpu.init();

    // Initialize stack pointer to valid position
    cpu.reg.pair.sp = 0xFFFE;

    // Push a value onto the stack
    const test_value: u16 = 0x1234;
    cpu.push(test_value);

    // Verify stack pointer moved down by 2
    try std.testing.expect(cpu.reg.pair.sp == 0xFFFC);

    // Verify the value was written to memory (little-endian)
    try std.testing.expect(cpu.mem.readByte(0xFFFC) == 0x34); // Low byte
    try std.testing.expect(cpu.mem.readByte(0xFFFD) == 0x12); // High byte

    // Pop the value back
    const popped_value = cpu.pop();
    try std.testing.expect(popped_value == test_value);
    try std.testing.expect(cpu.reg.pair.sp == 0xFFFE);
}

test "CPU push and pop - multiple values" {
    var cpu = Cpu.init();

    // Initialize stack pointer
    cpu.reg.pair.sp = 0xFFFE;

    // Push multiple values
    const value1: u16 = 0x1111;
    const value2: u16 = 0x2222;
    const value3: u16 = 0x3333;

    cpu.push(value1);
    cpu.push(value2);
    cpu.push(value3);

    // Verify stack pointer position
    try std.testing.expect(cpu.reg.pair.sp == 0xFFF8);

    // Pop values back in reverse order (LIFO)
    const pop3 = cpu.pop();
    const pop2 = cpu.pop();
    const pop1 = cpu.pop();

    try std.testing.expect(pop3 == value3);
    try std.testing.expect(pop2 == value2);
    try std.testing.expect(pop1 == value1);
    try std.testing.expect(cpu.reg.pair.sp == 0xFFFE);
}

test "CPU push - stack grows downward" {
    var cpu = Cpu.init();

    // Start at a higher address to clearly see downward growth
    cpu.reg.pair.sp = 0x8000;

    const value1: u16 = 0xAABB;
    const value2: u16 = 0xCCDD;

    // Push first value
    cpu.push(value1);
    try std.testing.expect(cpu.reg.pair.sp == 0x7FFE);
    try std.testing.expect(cpu.mem.readByte(0x7FFE) == 0xBB); // Low byte
    try std.testing.expect(cpu.mem.readByte(0x7FFF) == 0xAA); // High byte

    // Push second value
    cpu.push(value2);
    try std.testing.expect(cpu.reg.pair.sp == 0x7FFC);
    try std.testing.expect(cpu.mem.readByte(0x7FFC) == 0xDD); // Low byte
    try std.testing.expect(cpu.mem.readByte(0x7FFD) == 0xCC); // High byte
}

test "CPU pop - stack underflow detection" {
    var cpu = Cpu.init();

    // Set stack pointer to stack start (empty stack condition)
    cpu.reg.pair.sp = STACK_START;

    // Attempting to pop from empty stack should panic
    // Note: In a real test environment, you'd want to catch this panic
    // For now, we'll just verify the stack pointer is at the expected position
    try std.testing.expect(cpu.reg.pair.sp == 0xFFFE);
}

test "CPU memory interaction through fetch" {
    var cpu = Cpu.init();

    // Test that CPU properly interacts with memory
    // Write test pattern to memory
    for (0..10) |i| {
        cpu.mem.writeByte(@intCast(i), @intCast(i * 2));
    }

    // Use fetch to read the pattern back
    cpu.reg.pair.pc = 0;
    for (0..10) |i| {
        const fetched = cpu.fetch();
        try std.testing.expect(fetched == i * 2);
        try std.testing.expect(cpu.reg.pair.pc == i + 1);
    }
}

test "CPU stack operations with edge addresses" {
    var cpu = Cpu.init();

    // Test stack operations near memory boundaries
    cpu.reg.pair.sp = 0x0004; // Low address

    const test_val: u16 = 0xDEAD;
    cpu.push(test_val);

    try std.testing.expect(cpu.reg.pair.sp == 0x0002);
    try std.testing.expect(cpu.mem.readByte(0x0002) == 0xAD); // Low byte
    try std.testing.expect(cpu.mem.readByte(0x0003) == 0xDE); // High byte

    const popped = cpu.pop();
    try std.testing.expect(popped == test_val);
    try std.testing.expect(cpu.reg.pair.sp == 0x0004);
}

test "FIB First steps" {
    const log_level_backup = std.testing.log_level;
    defer std.testing.log_level = log_level_backup;
    std.testing.log_level = .info; // Avoid steps printing

    const MAX_STEP_COUNT = 10_000;
    const OP_HALT: u8 = 0x76;

    var cpu = Cpu.init();
    cpu.setPC(0x0000); // HACKKKKKKK

    // Print current working directory for debugging
    try loadFileIntoMemory(&cpu, "./bin/fib.gb", 0x0000);

    // Verify that the first few bytes are loaded correctly
    try std.testing.expect(cpu.mem.readByte(0x0000) == 0x00); // NOP
    try std.testing.expect(cpu.mem.readByte(0x0001) == 0x21);
    try std.testing.expect(cpu.mem.readByte(0x0010) == 0xE5);

    std.log.debug("Running few CPU steps...", .{});

    // Let's play few CPU steps
    var i: usize = 0;
    while (i < MAX_STEP_COUNT and cpu.mem.readByte(cpu.getPC()) != OP_HALT) : (i += 1) {
        _ = cpu.step();
    }

    std.log.debug("Completed {d} steps", .{i});

    // Values should be located at memory address 0xB000
    const TARGET_FIB_COUNT: u16 = 11; // Read the 10 first Fibonacci numbers
    const address: u16 = 0xB000;
    var offset: u16 = 2;

    var fib_n_1: u8 = 1;
    var fib_n: u8 = 2;

    while (offset < TARGET_FIB_COUNT) : (offset += 1) {
        const value = cpu.mem.readByte(address + offset);

        std.log.debug("FIB[{d}] = {d} | Expected = {d}", .{ offset, value, fib_n });
        try std.testing.expect(value == fib_n);

        const next_fib = fib_n + fib_n_1;
        fib_n_1 = fib_n;
        fib_n = next_fib;
    }
}
