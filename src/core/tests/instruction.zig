const std = @import("std");

const Cpu = @import("../cpu.zig").Cpu;

const Register16 = @import("../cpu/register.zig").Register16;
const Register8 = @import("../cpu/register.zig").Register8;

const OPCODES = @import("../cpu/instruction.zig").OPCODES;
const OPCODES_EXT = @import("../cpu/instructionExt.zig").OPCODES_EXT;

test "opcode NOP" {
    var cpu: Cpu = .{};

    const opcode = OPCODES[0x00];
    const cycles = opcode.execute(&cpu);
    try std.testing.expect(cycles == 1);
}

test "opcode unimplemented" {
    const logLevel = std.testing.log_level;
    defer std.testing.log_level = logLevel;
    std.testing.log_level = .err; // Avoid spamming

    var cpu: Cpu = .{};

    const opcode = OPCODES[0xD3]; // This should stays unimplemented
    const cycles = opcode.execute(&cpu);
    try std.testing.expect(cycles == 0);

    try std.testing.expectEqualStrings(opcode.metadata.name, "UNIMPLEMENTED(0xD3)");
}

test "opcode INC16" {
    var cpu: Cpu = .{};
    cpu.reg.set16(.bc, 0xFFFF);

    const opcode = OPCODES[0x03]; // INC BC
    const cycles = opcode.execute(&cpu);
    try std.testing.expect(cycles == 2);

    try std.testing.expect(cpu.reg.get16(.bc) == 0x0000);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == false);
    try std.testing.expect(cpu.reg.single.f.c == false);
}

test "opcode INC Memory" {
    var cpu: Cpu = .{};

    const addr: u16 = 0x2000;

    cpu.reg.set16(.hl, addr);
    cpu.mem.writeByte(addr, 0xFE);

    const inc_opcode = OPCODES[0x34]; // INC (HL)
    const dec_opcode = OPCODES[0x35]; // DEC (HL)

    const cycles1 = inc_opcode.execute(&cpu);
    try std.testing.expect(cycles1 == 3);
    try std.testing.expect(cpu.mem.readByte(addr) == 0xFF);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == false);
    try std.testing.expect(cpu.reg.single.f.c == false);

    const cycles2 = inc_opcode.execute(&cpu);
    try std.testing.expect(cycles2 == 3);
    try std.testing.expect(cpu.mem.readByte(addr) == 0x00);
    try std.testing.expect(cpu.reg.single.f.z == true);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == true);
    try std.testing.expect(cpu.reg.single.f.c == false);

    const cycles3 = dec_opcode.execute(&cpu);
    try std.testing.expect(cycles3 == 3);
    try std.testing.expect(cpu.mem.readByte(addr) == 0xFF);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == true);
    try std.testing.expect(cpu.reg.single.f.h == true);
    try std.testing.expect(cpu.reg.single.f.c == false);

    const cycles4 = dec_opcode.execute(&cpu);
    try std.testing.expect(cycles4 == 3);
    try std.testing.expect(cpu.mem.readByte(addr) == 0xFE);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == true);
    try std.testing.expect(cpu.reg.single.f.h == false);
    try std.testing.expect(cpu.reg.single.f.c == false);
}

test "load" {
    var cpu = Cpu.init();

    cpu.reg.set8(Register8.a, 0x12);
    cpu.reg.set8(Register8.b, 0x00);

    const op_a_b = OPCODES[0x47]; // LD B, A
    const cycles1 = op_a_b.execute(&cpu);
    try std.testing.expect(cycles1 == 1);

    try std.testing.expect(cpu.reg.get8(Register8.b) == 0x12);

    const op_b_hl = OPCODES[0x70]; // LD (HL), B
    const test_addr: u16 = 0x3000;
    cpu.reg.set16(Register16.hl, test_addr);

    const cycles2 = op_b_hl.execute(&cpu);
    try std.testing.expect(cycles2 == 2);

    try std.testing.expect(cpu.mem.readByte(test_addr) == 0x12);

    const op_hl_a = OPCODES[0x7E]; // LD A, (HL)
    const cycles3 = op_hl_a.execute(&cpu);
    try std.testing.expect(cycles3 == 2);

    try std.testing.expect(cpu.reg.single.a == 0x12);
}

test "load inc dec" {
    var cpu = Cpu.init();

    var test_addr: u16 = 0x4000;

    cpu.mem.writeByte(test_addr, 0x1A);
    cpu.mem.writeByte(test_addr + 1, 0x1B);
    cpu.reg.pair.hl = test_addr;

    const op_ld_hl_inc_a = OPCODES[0x2A]; // LD A, (HL+)
    const cycles1 = op_ld_hl_inc_a.execute(&cpu);
    try std.testing.expect(cycles1 == 2);
    test_addr += 1;

    try std.testing.expect(cpu.reg.single.a == 0x1A);
    try std.testing.expect(cpu.reg.get16(Register16.hl) == test_addr);

    const op_ld_hl_dec_a = OPCODES[0x3A]; // LD A, (HL-)
    const cycles2 = op_ld_hl_dec_a.execute(&cpu);
    try std.testing.expect(cycles2 == 2);
    test_addr -= 1;

    try std.testing.expect(cpu.reg.single.a == 0x1B);
    try std.testing.expect(cpu.reg.get16(Register16.hl) == test_addr);
}

test "opcode INC8 - all registers" {
    var cpu = Cpu.init();

    // Test INC B (0x04)
    cpu.reg.set8(.b, 0x0F);
    var cycles = OPCODES[0x04].execute(&cpu);
    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.b) == 0x10);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == true); // Half carry from 0x0F to 0x10

    // Test INC C (0x0C)
    cpu.reg.set8(.c, 0xFF);
    cycles = OPCODES[0x0C].execute(&cpu);
    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.c) == 0x00);
    try std.testing.expect(cpu.reg.single.f.z == true);
    try std.testing.expect(cpu.reg.single.f.h == true);

    // Test INC D (0x14)
    cpu.reg.set8(.d, 0x42);
    cycles = OPCODES[0x14].execute(&cpu);
    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.d) == 0x43);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.h == false);

    // Test INC E (0x1C)
    cpu.reg.set8(.e, 0x1F);
    cycles = OPCODES[0x1C].execute(&cpu);
    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.e) == 0x20);
    try std.testing.expect(cpu.reg.single.f.h == true);

    // Test INC H (0x24)
    cpu.reg.set8(.h, 0x00);
    cycles = OPCODES[0x24].execute(&cpu);
    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.h) == 0x01);
    try std.testing.expect(cpu.reg.single.f.z == false);

    // Test INC L (0x2C)
    cpu.reg.set8(.l, 0xFE);
    cycles = OPCODES[0x2C].execute(&cpu);
    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.l) == 0xFF);

    // Test INC A (0x3C)
    cpu.reg.set8(.a, 0x7F);
    cycles = OPCODES[0x3C].execute(&cpu);
    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.a) == 0x80);
}

test "opcode DEC8 - all registers" {
    var cpu = Cpu.init();

    // Test DEC B (0x05)
    cpu.reg.set8(.b, 0x01);
    var cycles = OPCODES[0x05].execute(&cpu);

    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.b) == 0x00);
    try std.testing.expect(cpu.reg.single.f.z == true);
    try std.testing.expect(cpu.reg.single.f.n == true);
    try std.testing.expect(cpu.reg.single.f.h == false);

    // Test DEC C (0x0D) - underflow
    cpu.reg.set8(.c, 0x00);
    cycles = OPCODES[0x0D].execute(&cpu);

    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.c) == 0xFF);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.h == true);

    // Test DEC D (0x15) - half borrow
    cpu.reg.set8(.d, 0x10);
    cycles = OPCODES[0x15].execute(&cpu);

    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.d) == 0x0F);
    try std.testing.expect(cpu.reg.single.f.h == true);

    // Test DEC E (0x1D)
    cpu.reg.set8(.e, 0x42);
    cycles = OPCODES[0x1D].execute(&cpu);

    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.e) == 0x41);
    try std.testing.expect(cpu.reg.single.f.h == false);

    // Test DEC H (0x25)
    cpu.reg.set8(.h, 0x80);
    cycles = OPCODES[0x25].execute(&cpu);
    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.h) == 0x7F);

    // Test DEC L (0x2D)
    cpu.reg.set8(.l, 0x20);
    cycles = OPCODES[0x2D].execute(&cpu);

    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.l) == 0x1F);

    // Test DEC A (0x3D)
    cpu.reg.set8(.a, 0x01);
    cycles = OPCODES[0x3D].execute(&cpu);

    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.a) == 0x00);
    try std.testing.expect(cpu.reg.single.f.z == true);
}

test "opcode INC16 - all registers" {
    var cpu = Cpu.init();

    // Test INC BC (0x03)
    cpu.reg.set16(.bc, 0x1234);
    var cycles = OPCODES[0x03].execute(&cpu);

    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get16(.bc) == 0x1235);

    // Test INC DE (0x13)
    cpu.reg.set16(.de, 0xFFFF);
    cycles = OPCODES[0x13].execute(&cpu);

    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get16(.de) == 0x0000);

    // Test INC HL (0x23)
    cpu.reg.set16(.hl, 0x00FF);
    cycles = OPCODES[0x23].execute(&cpu);

    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get16(.hl) == 0x0100);

    // Test INC SP (0x33)
    cpu.reg.set16(.sp, 0xFFFE);
    cycles = OPCODES[0x33].execute(&cpu);

    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get16(.sp) == 0xFFFF);
}

test "opcode DEC16 - all registers" {
    var cpu = Cpu.init();

    // Test DEC BC (0x0B)
    cpu.reg.set16(.bc, 0x1000);
    var cycles = OPCODES[0x0B].execute(&cpu);

    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get16(.bc) == 0x0FFF);

    // Test DEC DE (0x1B)
    cpu.reg.set16(.de, 0x0000);
    cycles = OPCODES[0x1B].execute(&cpu);

    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get16(.de) == 0xFFFF);

    // Test DEC HL (0x2B)
    cpu.reg.set16(.hl, 0x0100);
    cycles = OPCODES[0x2B].execute(&cpu);

    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get16(.hl) == 0x00FF);

    // Test DEC SP (0x3B)
    cpu.reg.set16(.sp, 0x0001);
    cycles = OPCODES[0x3B].execute(&cpu);

    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get16(.sp) == 0x0000);
}

test "opcode LD - register to register combinations" {
    var cpu = Cpu.init();

    // Set initial values
    cpu.reg.set8(.a, 0xAA);
    cpu.reg.set8(.b, 0xBB);
    cpu.reg.set8(.c, 0xCC);
    cpu.reg.set8(.d, 0xDD);
    cpu.reg.set8(.e, 0xEE);
    cpu.reg.set8(.h, 0x11);
    cpu.reg.set8(.l, 0x22);

    // Test LD B, C (0x41)
    var cycles = OPCODES[0x41].execute(&cpu);

    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.b) == 0xCC);

    // Test LD D, E (0x53)
    cycles = OPCODES[0x53].execute(&cpu);

    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.d) == 0xEE);

    // Test LD H, A (0x67)
    cycles = OPCODES[0x67].execute(&cpu);

    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.h) == 0xAA);

    // Test LD A, L (0x7D)
    cycles = OPCODES[0x7D].execute(&cpu);

    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.a) == 0x22);

    // Test LD C, H (0x4C)
    cycles = OPCODES[0x4C].execute(&cpu);

    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.c) == 0xAA);
}

test "opcode LD - memory operations" {
    var cpu = Cpu.init();

    const addr: u16 = 0x5000;

    // Test LD (BC), A (0x02)
    cpu.reg.set16(.bc, addr);
    cpu.reg.set8(.a, 0x12);
    var cycles = OPCODES[0x02].execute(&cpu);

    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.mem.readByte(addr) == 0x12);

    // Test LD A, (BC) (0x0A)
    cpu.reg.set8(.a, 0x00);
    cycles = OPCODES[0x0A].execute(&cpu);

    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.a) == 0x12);

    // Test LD (DE), A (0x12)
    cpu.reg.set16(.de, addr + 1);
    cpu.reg.set8(.a, 0x34);
    cycles = OPCODES[0x12].execute(&cpu);

    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.mem.readByte(addr + 1) == 0x34);

    // Test LD A, (DE) (0x1A)
    cpu.reg.set8(.a, 0x00);
    cycles = OPCODES[0x1A].execute(&cpu);

    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.a) == 0x34);

    // Test LD (HL), various registers
    cpu.reg.set16(.hl, addr + 2);
    cpu.reg.set8(.b, 0x56);
    cycles = OPCODES[0x70].execute(&cpu); // LD (HL), B

    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.mem.readByte(addr + 2) == 0x56);

    cpu.reg.set8(.c, 0x78);
    cycles = OPCODES[0x71].execute(&cpu); // LD (HL), C

    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.mem.readByte(addr + 2) == 0x78);

    // Test LD various registers, (HL)
    cpu.mem.writeByte(addr + 3, 0x9A);
    cpu.reg.set16(.hl, addr + 3);

    cycles = OPCODES[0x46].execute(&cpu); // LD B, (HL)

    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.b) == 0x9A);

    cycles = OPCODES[0x4E].execute(&cpu); // LD C, (HL)

    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.c) == 0x9A);

    cycles = OPCODES[0x56].execute(&cpu); // LD D, (HL)

    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.d) == 0x9A);
}

test "opcode LD - increment/decrement operations" {
    var cpu = Cpu.init();

    const base_addr: u16 = 0x6000;

    // Setup memory
    cpu.mem.writeByte(base_addr, 0x11);
    cpu.mem.writeByte(base_addr + 1, 0x22);
    cpu.mem.writeByte(base_addr + 2, 0x33);
    cpu.mem.writeByte(base_addr - 1, 0x00);

    // Test LD (HL+), A (0x22)
    cpu.reg.set16(.hl, base_addr);
    cpu.reg.set8(.a, 0xAA);
    var cycles = OPCODES[0x22].execute(&cpu);

    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.mem.readByte(base_addr) == 0xAA);
    try std.testing.expect(cpu.reg.get16(.hl) == base_addr + 1);

    // Test LD A, (HL+) (0x2A)
    cpu.reg.set16(.hl, base_addr + 1);
    cycles = OPCODES[0x2A].execute(&cpu);

    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.a) == 0x22);
    try std.testing.expect(cpu.reg.get16(.hl) == base_addr + 2);

    // Test LD (HL-), A (0x32)
    cpu.reg.set8(.a, 0xBB);
    cycles = OPCODES[0x32].execute(&cpu);

    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.mem.readByte(base_addr + 2) == 0xBB);
    try std.testing.expect(cpu.reg.get16(.hl) == base_addr + 1);

    // Test LD A, (HL-) (0x3A)
    cycles = OPCODES[0x3A].execute(&cpu);

    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.a) == 0x22);
    try std.testing.expect(cpu.reg.get16(.hl) == base_addr);
}

test "opcode cycles execution" {
    var cpu = Cpu.init();

    // Verify cycle counts are returned correctly by execute
    var cycles = OPCODES[0x00].execute(&cpu); // NOP

    try std.testing.expect(cycles == 1);

    cpu.reg.set8(.b, 0x42);
    cycles = OPCODES[0x04].execute(&cpu); // INC B

    try std.testing.expect(cycles == 1);

    cpu.reg.set16(.bc, 0x1234);
    cycles = OPCODES[0x03].execute(&cpu); // INC BC

    try std.testing.expect(cycles == 2);

    const addr: u16 = 0x8000;
    cpu.reg.set16(.hl, addr);
    cpu.mem.writeByte(addr, 0x42);
    cycles = OPCODES[0x34].execute(&cpu); // INC (HL)

    try std.testing.expect(cycles == 3);

    cpu.reg.set8(.a, 0x12);
    cycles = OPCODES[0x47].execute(&cpu); // LD B, A

    try std.testing.expect(cycles == 1);

    cycles = OPCODES[0x46].execute(&cpu); // LD B, (HL)

    try std.testing.expect(cycles == 2);

    cycles = OPCODES[0x70].execute(&cpu); // LD (HL), B

    try std.testing.expect(cycles == 2);

    cycles = OPCODES[0x2A].execute(&cpu); // LD A, (HL+)

    try std.testing.expect(cycles == 2);

    cycles = OPCODES[0x22].execute(&cpu); // LD (HL+), A

    try std.testing.expect(cycles == 2);

    cpu.mem.writeByte(0x0000, 0x42); // immediate value
    cpu.reg.set16(.pc, 0x0000);
    cycles = OPCODES[0x36].execute(&cpu); // LD (HL), d8

    try std.testing.expect(cycles == 3);

    cpu.mem.writeByte(0x0001, 0x34);
    cpu.mem.writeByte(0x0002, 0x12);
    cpu.reg.set16(.pc, 0x0001);
    cycles = OPCODES[0x31].execute(&cpu); // LD SP, d16

    try std.testing.expect(cycles == 3);

    cpu.mem.writeByte(0x0003, 0x00);
    cpu.mem.writeByte(0x0004, 0x80);
    cpu.reg.set16(.pc, 0x0003);
    cycles = OPCODES[0x08].execute(&cpu); // LD (d16), SP

    try std.testing.expect(cycles == 5);
}

test "opcode flags - zero flag" {
    var cpu = Cpu.init();

    // INC setting zero flag
    cpu.reg.set8(.b, 0xFF);
    var cycles = OPCODES[0x04].execute(&cpu); // INC B

    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.single.f.z == true);

    // INC clearing zero flag
    cycles = OPCODES[0x04].execute(&cpu); // INC B again

    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.single.f.z == false);

    // DEC setting zero flag
    cpu.reg.set8(.c, 0x01);
    cycles = OPCODES[0x0D].execute(&cpu); // DEC C

    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.single.f.z == true);

    // DEC clearing zero flag
    cycles = OPCODES[0x0D].execute(&cpu); // DEC C again

    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.single.f.z == false);
}

test "opcode flags - half carry/borrow" {
    var cpu = Cpu.init();

    // INC half carry tests
    cpu.reg.set8(.b, 0x0F);
    var cycles = OPCODES[0x04].execute(&cpu); // INC B

    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.single.f.h == true);

    cpu.reg.set8(.b, 0x10);
    cycles = OPCODES[0x04].execute(&cpu); // INC B

    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.single.f.h == false);

    cpu.reg.set8(.b, 0xFF);
    cycles = OPCODES[0x04].execute(&cpu); // INC B

    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.single.f.h == true);

    // DEC half borrow tests
    cpu.reg.set8(.c, 0x10);
    cycles = OPCODES[0x0D].execute(&cpu); // DEC C

    try std.testing.expect(cpu.reg.single.f.h == true);

    cpu.reg.set8(.c, 0x0F);
    cycles = OPCODES[0x0D].execute(&cpu); // DEC C

    try std.testing.expect(cpu.reg.single.f.h == false);

    cpu.reg.set8(.c, 0x00);
    cycles = OPCODES[0x0D].execute(&cpu); // DEC C

    try std.testing.expect(cpu.reg.single.f.h == true);
}

test "opcode flags - N flag" {
    var cpu = Cpu.init();

    // INC should clear N flag
    cpu.reg.set8(.b, 0x42);
    cpu.reg.single.f.n = true;
    var cycles = OPCODES[0x04].execute(&cpu); // INC B

    try std.testing.expect(cpu.reg.single.f.n == false);

    // DEC should set N flag
    cpu.reg.set8(.c, 0x42);
    cycles = OPCODES[0x0D].execute(&cpu); // DEC C

    try std.testing.expect(cpu.reg.single.f.n == true);
}

test "opcode F8 - LD HL, SP + i8" {
    var cpu = Cpu.init();

    cpu.reg.set16(.sp, 0xFFF8);
    cpu.mem.writeByte(0x0000, 0x08); // i8 = 8
    cpu.reg.set16(.pc, 0x0000);

    var cycles = OPCODES[0xF8].execute(&cpu); // LD HL, SP + i8

    try std.testing.expect(cpu.reg.pair.hl == 0x0000); // 0xFFF8 + 8 = 0x0000 (wrap around)

    // => Now test with negative offset
    // -8 =>

    cpu.mem.writeByte(0x0001, 0xF8); // i8 = -8
    cpu.reg.pair.sp = 0x00_FF; // 255

    try std.testing.expect(cpu.reg.pair.pc == 0x0001);
    cycles = OPCODES[0xF8].execute(&cpu); // LD HL, SP + i8

    try std.testing.expect(cpu.reg.pair.hl == 0x00_F7); // 0x00_FF - 0x00_08 = 0x00_F7 => no carry, no half carry

    // Check flags
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == false);
    try std.testing.expect(cpu.reg.single.f.c == false);

    cpu.mem.writeByte(0x0002, 0xF8); // i8 = -8
    cpu.reg.pair.sp = 0x0F_00;

    try std.testing.expect(cpu.reg.pair.pc == 0x0002);
    cycles = OPCODES[0xF8].execute(&cpu); // LD HL, SP + i8

    try std.testing.expect(cpu.reg.pair.hl == 0x0E_F8); // 0x0F_00 - 0x00_08 = 0x0E_F8

    // Check flags
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == false);
    try std.testing.expect(cpu.reg.single.f.c == false);
}

// ============================================================================
// ARITHMETIC OPERATIONS TESTS
// ============================================================================

test "opcode ADD - register to register" {
    var cpu = Cpu.init();

    // Test ADD A, B (0x80)
    cpu.reg.set8(.a, 0x10);
    cpu.reg.set8(.b, 0x05);
    var cycles = OPCODES[0x80].execute(&cpu);

    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.a) == 0x15);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == false);
    try std.testing.expect(cpu.reg.single.f.c == false);

    // Test ADD A, C (0x81) with half carry
    cpu.reg.set8(.a, 0x0F);
    cpu.reg.set8(.c, 0x01);
    cycles = OPCODES[0x81].execute(&cpu);

    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.a) == 0x10);
    try std.testing.expect(cpu.reg.single.f.h == true);

    // Test ADD A, D (0x82) with carry
    cpu.reg.set8(.a, 0xFF);
    cpu.reg.set8(.d, 0x01);
    cycles = OPCODES[0x82].execute(&cpu);

    try std.testing.expect(cycles == 1);
    try std.testing.expect(cpu.reg.get8(.a) == 0x00);
    try std.testing.expect(cpu.reg.single.f.z == true);
    try std.testing.expect(cpu.reg.single.f.c == true);
    try std.testing.expect(cpu.reg.single.f.h == true);

    // Test ADD A, A (0x87)
    cpu.reg.set8(.a, 0x80);
    cycles = OPCODES[0x87].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x00);
    try std.testing.expect(cpu.reg.single.f.z == true);
    try std.testing.expect(cpu.reg.single.f.c == true);
}

test "opcode ADD - memory and immediate" {
    var cpu = Cpu.init();

    const addr: u16 = 0x8000;

    // Test ADD A, (HL) (0x86)
    cpu.reg.set16(.hl, addr);
    cpu.mem.writeByte(addr, 0x12);
    cpu.reg.set8(.a, 0x34);
    var cycles = OPCODES[0x86].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x46);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == false);
    try std.testing.expect(cpu.reg.single.f.c == false);

    // Test ADD A, d8 (0xC6)
    cpu.reg.set8(.a, 0xF0);
    cpu.mem.writeByte(0x0000, 0x0F); // immediate value
    cpu.reg.set16(.pc, 0x0000);
    cycles = OPCODES[0xC6].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0xFF);
    try std.testing.expect(cpu.reg.single.f.h == false); // 0xF0 + 0x0F = 0xFF no half carry
}

test "opcode ADC - add with carry" {
    var cpu = Cpu.init();

    // Test ADC A, B (0x88) without carry
    cpu.reg.set8(.a, 0x10);
    cpu.reg.set8(.b, 0x05);
    cpu.reg.single.f.c = false;
    var cycles = OPCODES[0x88].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x15);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.c == false);

    // Test ADC A, C (0x89) with carry
    cpu.reg.set8(.a, 0x10);
    cpu.reg.set8(.c, 0x05);
    cpu.reg.single.f.c = true;
    cycles = OPCODES[0x89].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x16); // 0x10 + 0x05 + 1 = 0x16
    try std.testing.expect(cpu.reg.single.f.c == false);

    // Test ADC A, D (0x8A) with double carry
    cpu.reg.set8(.a, 0xFF);
    cpu.reg.set8(.d, 0x00);
    cpu.reg.single.f.c = true;
    cycles = OPCODES[0x8A].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x00); // 0xFF + 0x00 + 1 = 0x00 (carry)
    try std.testing.expect(cpu.reg.single.f.z == true);
    try std.testing.expect(cpu.reg.single.f.c == true);

    // Test ADC A, immediate (0xCE)
    cpu.reg.set8(.a, 0x0E);
    cpu.mem.writeByte(0x0001, 0x01);
    cpu.reg.set16(.pc, 0x0001);
    cpu.reg.single.f.c = true;
    cycles = OPCODES[0xCE].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x10); // 0x0E + 0x01 + 1 = 0x10
    try std.testing.expect(cpu.reg.single.f.h == true);
}

test "opcode SUB - subtract" {
    var cpu = Cpu.init();

    // Test SUB A, B (0x90)
    cpu.reg.set8(.a, 0x20);
    cpu.reg.set8(.b, 0x10);
    var cycles = OPCODES[0x90].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x10);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == true);
    try std.testing.expect(cpu.reg.single.f.h == false);
    try std.testing.expect(cpu.reg.single.f.c == false);

    // Test SUB A, C (0x91) with zero result
    cpu.reg.set8(.a, 0x42);
    cpu.reg.set8(.c, 0x42);
    cycles = OPCODES[0x91].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x00);
    try std.testing.expect(cpu.reg.single.f.z == true);
    try std.testing.expect(cpu.reg.single.f.n == true);

    // Test SUB A, D (0x92) with borrow
    cpu.reg.set8(.a, 0x00);
    cpu.reg.set8(.d, 0x01);
    cycles = OPCODES[0x92].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0xFF);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == true);
    try std.testing.expect(cpu.reg.single.f.c == true);
    try std.testing.expect(cpu.reg.single.f.h == true);

    // Test SUB A, immediate (0xD6)
    cpu.reg.set8(.a, 0x10);
    cpu.mem.writeByte(0x0002, 0x01);
    cpu.reg.set16(.pc, 0x0002);
    cycles = OPCODES[0xD6].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x0F);
    try std.testing.expect(cpu.reg.single.f.h == true);
}

test "opcode SBC - subtract with carry" {
    var cpu = Cpu.init();

    // Test SBC A, B (0x98) without carry
    cpu.reg.set8(.a, 0x20);
    cpu.reg.set8(.b, 0x10);
    cpu.reg.single.f.c = false;
    var cycles = OPCODES[0x98].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x10);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == true);
    try std.testing.expect(cpu.reg.single.f.c == false);

    // Test SBC A, C (0x99) with carry
    cpu.reg.set8(.a, 0x20);
    cpu.reg.set8(.c, 0x10);
    cpu.reg.single.f.c = true;
    cycles = OPCODES[0x99].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x0F); // 0x20 - 0x10 - 1 = 0x0F
    try std.testing.expect(cpu.reg.single.f.n == true);
    try std.testing.expect(cpu.reg.single.f.c == false);

    // Test SBC A, D (0x9A) with double borrow
    cpu.reg.set8(.a, 0x00);
    cpu.reg.set8(.d, 0x00);
    cpu.reg.single.f.c = true;
    cycles = OPCODES[0x9A].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0xFF); // 0x00 - 0x00 - 1 = 0xFF
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.c == true);
}

test "opcode CP - compare" {
    var cpu = Cpu.init();

    // Test CP A, B (0xB8) - equal values
    cpu.reg.set8(.a, 0x42);
    cpu.reg.set8(.b, 0x42);
    var cycles = OPCODES[0xB8].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x42); // A should not change
    try std.testing.expect(cpu.reg.single.f.z == true);
    try std.testing.expect(cpu.reg.single.f.n == true);
    try std.testing.expect(cpu.reg.single.f.c == false);

    // Test CP A, C (0xB9) - A > C
    cpu.reg.set8(.a, 0x50);
    cpu.reg.set8(.c, 0x30);
    cycles = OPCODES[0xB9].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x50); // A should not change
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == true);
    try std.testing.expect(cpu.reg.single.f.c == false);

    // Test CP A, D (0xBA) - A < D (borrow)
    cpu.reg.set8(.a, 0x10);
    cpu.reg.set8(.d, 0x20);
    cycles = OPCODES[0xBA].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x10); // A should not change
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == true);
    try std.testing.expect(cpu.reg.single.f.c == true);

    // Test CP A, immediate (0xFE)
    cpu.reg.set8(.a, 0x10);
    cpu.mem.writeByte(0x0003, 0x0F);
    cpu.reg.set16(.pc, 0x0003);
    cycles = OPCODES[0xFE].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x10); // A should not change
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.h == true); // A - Im = 0x10 - 0x0F
}

// ============================================================================
// BITWISE OPERATIONS TESTS
// ============================================================================

test "opcode AND - bitwise and" {
    var cpu = Cpu.init();

    // Test AND A, B (0xA0)
    cpu.reg.set8(.a, 0xFF);
    cpu.reg.set8(.b, 0x0F);
    var cycles = OPCODES[0xA0].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x0F);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == true); // AND always sets H flag
    try std.testing.expect(cpu.reg.single.f.c == false);

    // Test AND A, C (0xA1) with zero result
    cpu.reg.set8(.a, 0xAA);
    cpu.reg.set8(.c, 0x55);
    cycles = OPCODES[0xA1].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x00);
    try std.testing.expect(cpu.reg.single.f.z == true);
    try std.testing.expect(cpu.reg.single.f.h == true);

    // Test AND A, (HL) (0xA6)
    const addr: u16 = 0x9000;
    cpu.reg.set16(.hl, addr);
    cpu.mem.writeByte(addr, 0xF0);
    cpu.reg.set8(.a, 0x33);
    cycles = OPCODES[0xA6].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x30);
    try std.testing.expect(cpu.reg.single.f.h == true);

    // Test AND A, immediate (0xE6)
    cpu.reg.set8(.a, 0xFF);
    cpu.mem.writeByte(0x0004, 0x80);
    cpu.reg.set16(.pc, 0x0004);
    cycles = OPCODES[0xE6].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x80);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.h == true);
}

test "opcode OR - bitwise or" {
    var cpu = Cpu.init();

    // Test OR A, B (0xB0)
    cpu.reg.set8(.a, 0x0F);
    cpu.reg.set8(.b, 0xF0);
    var cycles = OPCODES[0xB0].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0xFF);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == false); // OR clears H flag
    try std.testing.expect(cpu.reg.single.f.c == false);

    // Test OR A, C (0xB1) with zero result
    cpu.reg.set8(.a, 0x00);
    cpu.reg.set8(.c, 0x00);
    cycles = OPCODES[0xB1].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x00);
    try std.testing.expect(cpu.reg.single.f.z == true);
    try std.testing.expect(cpu.reg.single.f.h == false);

    // Test OR A, A (0xB7) - common way to test A register
    cpu.reg.set8(.a, 0x42);
    cycles = OPCODES[0xB7].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x42);
    try std.testing.expect(cpu.reg.single.f.z == false);

    // Test OR A, (HL) (0xB6)
    const addr2: u16 = 0xB000;
    cpu.reg.set16(.hl, addr2);
    cpu.mem.writeByte(addr2, 0xF0);
    cpu.reg.set8(.a, 0x0A);
    cycles = OPCODES[0xB6].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0xFA);
    try std.testing.expect(cpu.reg.single.f.z == false);

    // Test OR A, immediate (0xF6)
    cpu.reg.set8(.a, 0x0A);
    cpu.mem.writeByte(0x0005, 0x05);
    cpu.reg.set16(.pc, 0x0005);
    cycles = OPCODES[0xF6].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x0F);
}

test "opcode XOR - bitwise xor" {
    var cpu = Cpu.init();

    // Test XOR A, B (0xA8)
    cpu.reg.set8(.a, 0xFF);
    cpu.reg.set8(.b, 0xAA);
    var cycles = OPCODES[0xA8].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x55);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == false); // XOR clears H flag
    try std.testing.expect(cpu.reg.single.f.c == false);

    // Test XOR A, C (0xA9) with zero result (same values)
    cpu.reg.set8(.a, 0x42);
    cpu.reg.set8(.c, 0x42);
    cycles = OPCODES[0xA9].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x00);
    try std.testing.expect(cpu.reg.single.f.z == true);
    try std.testing.expect(cpu.reg.single.f.h == false);

    // Test XOR A, A (0xAF) - common way to clear A register
    cpu.reg.set8(.a, 0xFF);
    cycles = OPCODES[0xAF].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0x00);
    try std.testing.expect(cpu.reg.single.f.z == true);

    // Test XOR A, (HL) (0xAE)
    const addr: u16 = 0xA000;
    cpu.reg.set16(.hl, addr);
    cpu.mem.writeByte(addr, 0x55);
    cpu.reg.set8(.a, 0xAA);
    cycles = OPCODES[0xAE].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0xFF);
    try std.testing.expect(cpu.reg.single.f.z == false);

    // Test XOR A, immediate (0xEE)
    cpu.reg.set8(.a, 0xF0);
    cpu.mem.writeByte(0x0006, 0x0F);
    cpu.reg.set16(.pc, 0x0006);
    cycles = OPCODES[0xEE].execute(&cpu);

    try std.testing.expect(cpu.reg.get8(.a) == 0xFF);
    try std.testing.expect(cpu.reg.single.f.z == false);
}

test "arithmetic operations - flag combinations" {
    var cpu = Cpu.init();

    // Test half carry in addition (lower nibble overflow)
    cpu.reg.set8(.a, 0x08);
    cpu.reg.set8(.b, 0x08);
    var cycles = OPCODES[0x80].execute(&cpu); // ADD A, B

    try std.testing.expect(cpu.reg.get8(.a) == 0x10);
    try std.testing.expect(cpu.reg.single.f.h == true);
    try std.testing.expect(cpu.reg.single.f.c == false);

    // Test both carry and half carry
    cpu.reg.set8(.a, 0xFF);
    cpu.reg.set8(.c, 0x01);
    cycles = OPCODES[0x81].execute(&cpu); // ADD A, C

    try std.testing.expect(cpu.reg.get8(.a) == 0x00);
    try std.testing.expect(cpu.reg.single.f.z == true);
    try std.testing.expect(cpu.reg.single.f.h == true);
    try std.testing.expect(cpu.reg.single.f.c == true);

    // Test half borrow in subtraction
    cpu.reg.set8(.a, 0x10);
    cpu.reg.set8(.d, 0x01);
    cycles = OPCODES[0x92].execute(&cpu); // SUB A, D

    try std.testing.expect(cpu.reg.get8(.a) == 0x0F);
    try std.testing.expect(cpu.reg.single.f.h == true);
    try std.testing.expect(cpu.reg.single.f.c == false);
}

test "bitwise operations - flag behavior" {
    var cpu = Cpu.init();

    // Test that bitwise operations clear N and C flags
    cpu.reg.single.f.n = true;
    cpu.reg.single.f.c = true;

    cpu.reg.set8(.a, 0xFF);
    cpu.reg.set8(.b, 0xFF);
    var cycles = OPCODES[0xA0].execute(&cpu); // AND A, B

    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.c == false);
    try std.testing.expect(cpu.reg.single.f.h == true); // AND sets H

    cpu.reg.single.f.n = true;
    cpu.reg.single.f.c = true;

    cpu.reg.set8(.a, 0xFF);
    cpu.reg.set8(.c, 0xFF);
    cycles = OPCODES[0xB1].execute(&cpu); // OR A, C

    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.c == false);
    try std.testing.expect(cpu.reg.single.f.h == false); // OR clears H

    cpu.reg.single.f.n = true;
    cpu.reg.single.f.c = true;

    cpu.reg.set8(.a, 0xFF);
    cpu.reg.set8(.d, 0xFF);
    cycles = OPCODES[0xAA].execute(&cpu); // XOR A, D

    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.c == false);
    try std.testing.expect(cpu.reg.single.f.h == false); // XOR clears H
}

test "arithmetic and bitwise operations - cycle counts" {
    // Verify that the cycle counts are correct for all operations
    var cpu = Cpu.init();

    // Arithmetic operations (register to register = 1 cycle)
    try std.testing.expect(OPCODES[0x80].execute(&cpu) == 1); // ADD A, B
    try std.testing.expect(OPCODES[0x88].execute(&cpu) == 1); // ADC A, B
    try std.testing.expect(OPCODES[0x90].execute(&cpu) == 1); // SUB A, B
    try std.testing.expect(OPCODES[0x98].execute(&cpu) == 1); // SBC A, B
    try std.testing.expect(OPCODES[0xB8].execute(&cpu) == 1); // CP A, B

    // Arithmetic operations (memory = 2 cycles)
    try std.testing.expect(OPCODES[0x86].execute(&cpu) == 2); // ADD A, (HL)
    try std.testing.expect(OPCODES[0x8E].execute(&cpu) == 2); // ADC A, (HL)
    try std.testing.expect(OPCODES[0x96].execute(&cpu) == 2); // SUB A, (HL)
    try std.testing.expect(OPCODES[0x9E].execute(&cpu) == 2); // SBC A, (HL)
    try std.testing.expect(OPCODES[0xBE].execute(&cpu) == 2); // CP A, (HL)

    // Arithmetic operations (immediate = 2 cycles)
    try std.testing.expect(OPCODES[0xC6].execute(&cpu) == 2); // ADD A, d8
    try std.testing.expect(OPCODES[0xCE].execute(&cpu) == 2); // ADC A, d8
    try std.testing.expect(OPCODES[0xD6].execute(&cpu) == 2); // SUB A, d8
    try std.testing.expect(OPCODES[0xDE].execute(&cpu) == 2); // SBC A, d8
    try std.testing.expect(OPCODES[0xFE].execute(&cpu) == 2); // CP A, d8

    // Bitwise operations (register to register = 1 cycle)
    try std.testing.expect(OPCODES[0xA0].execute(&cpu) == 1); // AND A, B
    try std.testing.expect(OPCODES[0xA8].execute(&cpu) == 1); // XOR A, B
    try std.testing.expect(OPCODES[0xB0].execute(&cpu) == 1); // OR A, B

    // Bitwise operations (memory = 2 cycles)
    try std.testing.expect(OPCODES[0xA6].execute(&cpu) == 2); // AND A, (HL)
    try std.testing.expect(OPCODES[0xAE].execute(&cpu) == 2); // XOR A, (HL)
    try std.testing.expect(OPCODES[0xB6].execute(&cpu) == 2); // OR A, (HL)

    // Bitwise operations (immediate = 2 cycles)
    try std.testing.expect(OPCODES[0xE6].execute(&cpu) == 2); // AND A, d8
    try std.testing.expect(OPCODES[0xEE].execute(&cpu) == 2); // XOR A, d8
    try std.testing.expect(OPCODES[0xF6].execute(&cpu) == 2); // OR A, d8
}

test "arithmetic operations - comprehensive edge cases" {
    var cpu = Cpu.init();

    // Test edge cases for all registers with ADD
    const registers = [_]Register8{ .b, .c, .d, .e, .h, .l };
    const add_opcodes = [_]u8{ 0x80, 0x81, 0x82, 0x83, 0x84, 0x85 };
    var cycles: u8 = undefined;

    for (registers, add_opcodes) |reg, opcode| {
        // Test adding zero
        cpu.reg.set8(.a, 0x42);
        cpu.reg.set8(reg, 0x00);
        cycles = OPCODES[opcode].execute(&cpu);
        try std.testing.expect(cpu.reg.get8(.a) == 0x42);
        try std.testing.expect(cpu.reg.single.f.z == false);
        try std.testing.expect(cpu.reg.single.f.n == false);
        try std.testing.expect(cpu.reg.single.f.c == false);
    }

    // Test SUB edge case: subtracting from zero
    cpu.reg.set8(.a, 0x00);
    cpu.reg.set8(.b, 0x01);
    cycles = OPCODES[0x90].execute(&cpu); // SUB A, B
    try std.testing.expect(cpu.reg.get8(.a) == 0xFF);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == true);
    try std.testing.expect(cpu.reg.single.f.c == true);
    try std.testing.expect(cpu.reg.single.f.h == true);

    // Test ADC with maximum values
    cpu.reg.set8(.a, 0xFF);
    cpu.reg.set8(.c, 0xFF);
    cpu.reg.single.f.c = true;
    cycles = OPCODES[0x89].execute(&cpu); // ADC A, C

    try std.testing.expect(cpu.reg.get8(.a) == 0xFF); // 0xFF + 0xFF + 1 = 0x1FF -> 0xFF with carry
    try std.testing.expect(cpu.reg.single.f.c == true);

    // Test SBC underflow
    cpu.reg.set8(.a, 0x00);
    cpu.reg.set8(.d, 0xFF);
    cpu.reg.single.f.c = true;
    cycles = OPCODES[0x9A].execute(&cpu); // SBC A, D

    try std.testing.expect(cpu.reg.get8(.a) == 0x00); // 0x00 - 0xFF - 1 = 0x00 with borrow
    try std.testing.expect(cpu.reg.single.f.c == true);
}

test "bitwise operations - comprehensive patterns" {
    var cpu = Cpu.init();
    var cycles: u8 = undefined;

    // Test AND with various bit patterns
    const test_patterns = [_]struct { a: u8, b: u8, result: u8 }{
        .{ .a = 0b11110000, .b = 0b00001111, .result = 0b00000000 },
        .{ .a = 0b10101010, .b = 0b01010101, .result = 0b00000000 },
        .{ .a = 0b11111111, .b = 0b10000001, .result = 0b10000001 },
        .{ .a = 0b01010101, .b = 0b01010101, .result = 0b01010101 },
    };

    for (test_patterns) |pattern| {
        cpu.reg.set8(.a, pattern.a);
        cpu.reg.set8(.b, pattern.b);
        cycles = OPCODES[0xA0].execute(&cpu); // AND A, B

        try std.testing.expect(cpu.reg.get8(.a) == pattern.result);
        try std.testing.expect(cpu.reg.single.f.z == (pattern.result == 0));
        try std.testing.expect(cpu.reg.single.f.h == true); // AND always sets H
    }

    // Test OR with various bit patterns
    const or_patterns = [_]struct { a: u8, b: u8, result: u8 }{
        .{ .a = 0b11110000, .b = 0b00001111, .result = 0b11111111 },
        .{ .a = 0b10101010, .b = 0b01010101, .result = 0b11111111 },
        .{ .a = 0b00000000, .b = 0b00000000, .result = 0b00000000 },
        .{ .a = 0b11000011, .b = 0b00111100, .result = 0b11111111 },
    };

    for (or_patterns) |pattern| {
        cpu.reg.set8(.a, pattern.a);
        cpu.reg.set8(.c, pattern.b);
        cycles = OPCODES[0xB1].execute(&cpu); // OR A, C

        try std.testing.expect(cpu.reg.get8(.a) == pattern.result);
        try std.testing.expect(cpu.reg.single.f.z == (pattern.result == 0));
        try std.testing.expect(cpu.reg.single.f.h == false); // OR clears H
    }

    // Test XOR with various bit patterns
    const xor_patterns = [_]struct { a: u8, b: u8, result: u8 }{
        .{ .a = 0b11110000, .b = 0b00001111, .result = 0b11111111 },
        .{ .a = 0b10101010, .b = 0b01010101, .result = 0b11111111 },
        .{ .a = 0b11111111, .b = 0b11111111, .result = 0b00000000 },
        .{ .a = 0b11000011, .b = 0b00110011, .result = 0b11110000 },
    };

    for (xor_patterns) |pattern| {
        cpu.reg.set8(.a, pattern.a);
        cpu.reg.set8(.d, pattern.b);
        cycles = OPCODES[0xAA].execute(&cpu); // XOR A, D

        try std.testing.expect(cpu.reg.get8(.a) == pattern.result);
        try std.testing.expect(cpu.reg.single.f.z == (pattern.result == 0));
        try std.testing.expect(cpu.reg.single.f.h == false); // XOR clears H
    }
}

test "add operations - 16bit alu" {
    var cpu = Cpu.init();

    // Test ADD HL, BC (0x09)
    cpu.reg.pair.hl = 0x1234;
    cpu.reg.pair.bc = 0x1111;
    var cycles = OPCODES[0x09].execute(&cpu); // ADD HL, BC

    try std.testing.expect(cpu.reg.pair.hl == 0x2345);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == false);
    try std.testing.expect(cpu.reg.single.f.c == false);

    // Test ADD HL, DE (0x19) with carry
    cpu.reg.pair.hl = 0xFFFF;
    cpu.reg.pair.de = 0x0001;
    cycles = OPCODES[0x19].execute(&cpu); // ADD HL, DE

    try std.testing.expect(cpu.reg.pair.hl == 0x0000);
    try std.testing.expect(cpu.reg.single.f.c == true);

    // Test ADD HL, SP (0x39) with half carry
    cpu.reg.pair.hl = 0x0FFF;
    cpu.reg.pair.sp = 0x0001;
    cycles = OPCODES[0x39].execute(&cpu); // ADD HL, SP

    try std.testing.expect(cpu.reg.pair.hl == 0x1000);
    try std.testing.expect(cpu.reg.single.f.h == true);
}

// Branching Instructions Tests

test "jump relative - unconditional JR" {
    var cpu = Cpu.init();

    // Set up memory with jump instruction and offset
    cpu.setPC(0x1001);
    cpu.mem.writeByte(0x1000, 0x18); // JR instruction
    cpu.mem.writeByte(0x1001, 0x05); // Jump forward 5 bytes

    const cycles = OPCODES[0x18].execute(&cpu); // JR 5

    // PC should be at 0x1002 (after fetching offset) + 5 = 0x1007
    try std.testing.expect(cpu.getPC() == 0x1007);
    try std.testing.expect(cycles == 3);
}

test "jump relative - conditional JR with flags" {
    var cpu = Cpu.init();

    // Test JR NZ when Z flag is clear (should jump)
    cpu.setPC(0x1001);
    cpu.mem.writeByte(0x1000, 0x20); // JR NZ instruction
    cpu.mem.writeByte(0x1001, 0x10); // Jump forward 16 bytes
    cpu.reg.single.f.z = false;

    var cycles = OPCODES[0x20].execute(&cpu); // JR NZ, 16

    try std.testing.expect(cpu.getPC() == 0x1012); // 0x1002 + 16
    try std.testing.expect(cycles == 3);

    // Test JR NZ when Z flag is set (should not jump)
    cpu.setPC(0x2001);
    cpu.mem.writeByte(0x2000, 0x20); // JR NZ instruction
    cpu.mem.writeByte(0x2001, 0x10); // Jump forward 16 bytes
    cpu.reg.single.f.z = true;

    cycles = OPCODES[0x20].execute(&cpu); // JR NZ, 16

    try std.testing.expect(cpu.getPC() == 0x2002); // Should not jump
    try std.testing.expect(cycles == 2); // Faster when not jumping

    // Test JR Z when Z flag is set (should jump)
    cpu.setPC(0x3001);
    cpu.mem.writeByte(0x3000, 0x28); // JR Z instruction
    cpu.mem.writeByte(0x3001, 0x08); // Jump forward 8 bytes
    cpu.reg.single.f.z = true;

    cycles = OPCODES[0x28].execute(&cpu); // JR Z, 8

    try std.testing.expect(cpu.getPC() == 0x300A); // 0x3002 + 8
    try std.testing.expect(cycles == 3);

    // Test JR NC when C flag is clear (should jump)
    cpu.setPC(0x4001);
    cpu.mem.writeByte(0x4000, 0x30); // JR NC instruction
    cpu.mem.writeByte(0x4001, 0x04); // Jump forward 4 bytes
    cpu.reg.single.f.c = false;

    cycles = OPCODES[0x30].execute(&cpu); // JR NC, 4

    try std.testing.expect(cpu.getPC() == 0x4006); // 0x4002 + 4
    try std.testing.expect(cycles == 3);

    // Test JR C when C flag is set (should jump)
    cpu.setPC(0x5001);
    cpu.mem.writeByte(0x5000, 0x38); // JR C instruction
    cpu.mem.writeByte(0x5001, 0x02); // Jump forward 2 bytes
    cpu.reg.single.f.c = true;

    cycles = OPCODES[0x38].execute(&cpu); // JR C, 2

    try std.testing.expect(cpu.getPC() == 0x5004); // 0x5002 + 2
    try std.testing.expect(cycles == 3);
}

test "jump relative - negative offsets" {
    var cpu = Cpu.init();

    // Test JR with negative offset (backward jump)
    cpu.setPC(0x1011);
    cpu.mem.writeByte(0x1010, 0x18); // JR instruction
    cpu.mem.writeByte(0x1011, 0xF0); // Jump backward 16 bytes (-16 in two's complement)

    const cycles = OPCODES[0x18].execute(&cpu); // JR -16

    // PC should be at 0x1012 (after fetching offset) - 16 = 0x1002
    try std.testing.expect(cpu.getPC() == 0x1002);
    try std.testing.expect(cycles == 3);
}

test "jump absolute - unconditional JP" {
    var cpu = Cpu.init();

    // Test JP a16 (0xC3)
    cpu.setPC(0x1001);
    cpu.mem.writeByte(0x1000, 0xC3); // JP instruction
    cpu.mem.writeByte(0x1001, 0x34); // Low byte of address
    cpu.mem.writeByte(0x1002, 0x12); // High byte of address

    const cycles = OPCODES[0xC3].execute(&cpu); // JP 0x1234

    try std.testing.expect(cpu.getPC() == 0x1234);
    try std.testing.expect(cycles == 4);
}

test "jump absolute - conditional JP with flags" {
    var cpu = Cpu.init();

    // Test JP NZ when Z flag is clear (should jump)
    cpu.setPC(0x2001);
    cpu.mem.writeByte(0x2000, 0xC2); // JP NZ instruction
    cpu.mem.writeByte(0x2001, 0x78); // Low byte
    cpu.mem.writeByte(0x2002, 0x56); // High byte
    cpu.reg.single.f.z = false;

    var cycles = OPCODES[0xC2].execute(&cpu); // JP NZ, 0x5678

    try std.testing.expect(cpu.getPC() == 0x5678);
    try std.testing.expect(cycles == 4);

    // Test JP NZ when Z flag is set (should not jump)
    cpu.setPC(0x3001);
    cpu.mem.writeByte(0x3000, 0xC2); // JP NZ instruction
    cpu.mem.writeByte(0x3001, 0x78); // Low byte
    cpu.mem.writeByte(0x3002, 0x56); // High byte
    cpu.reg.single.f.z = true;

    cycles = OPCODES[0xC2].execute(&cpu); // JP NZ, 0x5678

    try std.testing.expect(cpu.getPC() == 0x3003); // Should not jump
    try std.testing.expect(cycles == 3); // Faster when not jumping

    // Test all conditional JP variants
    const jp_conditions = [_]struct { opcode: u8, flag_set: bool, should_jump: bool }{
        .{ .opcode = 0xC2, .flag_set = false, .should_jump = true }, // JP NZ with Z=0
        .{ .opcode = 0xC2, .flag_set = true, .should_jump = false }, // JP NZ with Z=1
        .{ .opcode = 0xCA, .flag_set = true, .should_jump = true }, // JP Z with Z=1
        .{ .opcode = 0xCA, .flag_set = false, .should_jump = false }, // JP Z with Z=0
        .{ .opcode = 0xD2, .flag_set = false, .should_jump = true }, // JP NC with C=0
        .{ .opcode = 0xD2, .flag_set = true, .should_jump = false }, // JP NC with C=1
        .{ .opcode = 0xDA, .flag_set = true, .should_jump = true }, // JP C with C=1
        .{ .opcode = 0xDA, .flag_set = false, .should_jump = false }, // JP C with C=0
    };

    for (jp_conditions) |condition| {
        cpu.setPC(0x4001);
        cpu.mem.writeByte(0x4000, condition.opcode);
        cpu.mem.writeByte(0x4001, 0xBC); // Low byte
        cpu.mem.writeByte(0x4002, 0x9A); // High byte

        // Set appropriate flag
        if (condition.opcode == 0xC2 or condition.opcode == 0xCA) {
            cpu.reg.single.f.z = condition.flag_set;
        } else {
            cpu.reg.single.f.c = condition.flag_set;
        }

        cycles = OPCODES[condition.opcode].execute(&cpu);

        if (condition.should_jump) {
            try std.testing.expect(cpu.getPC() == 0x9ABC);
            try std.testing.expect(cycles == 4);
        } else {
            try std.testing.expect(cpu.getPC() == 0x4003);
            try std.testing.expect(cycles == 3);
        }
    }
}

test "jump indirect - JP (HL)" {
    var cpu = Cpu.init();

    // Test JP (HL) - 0xE9
    cpu.reg.pair.hl = 0x8000;
    cpu.setPC(0x1000);

    const cycles = OPCODES[0xE9].execute(&cpu); // JP (HL)

    try std.testing.expect(cpu.getPC() == 0x8000);
    try std.testing.expect(cycles == 1);
}

test "call instructions - unconditional and conditional" {
    var cpu = Cpu.init();

    // Test CALL a16 (0xCD) - unconditional call
    cpu.setPC(0x1001); // Ignore opcode fetch
    cpu.reg.pair.sp = 0xFFFE; // Initialize stack
    cpu.mem.writeByte(0x1000, 0xCD); // CALL instruction
    cpu.mem.writeByte(0x1001, 0x34); // Low byte of address
    cpu.mem.writeByte(0x1002, 0x12); // High byte of address

    var cycles = OPCODES[0xCD].execute(&cpu); // CALL 0x1234

    // Check that PC was pushed to stack
    const return_addr = cpu.pop();
    try std.testing.expect(return_addr == 0x1003); // Address after CALL instruction
    try std.testing.expect(cpu.getPC() == 0x1234); // Jumped to call target
    try std.testing.expect(cycles == 6); // 4 base + 2 for call

    // Test conditional CALL when condition is true
    cpu.setPC(0x2001);
    cpu.reg.pair.sp = 0xFFFE;
    cpu.mem.writeByte(0x2000, 0xCC); // CALL Z instruction
    cpu.mem.writeByte(0x2001, 0x78); // Low byte
    cpu.mem.writeByte(0x2002, 0x56); // High byte
    cpu.reg.single.f.z = true;

    cycles = OPCODES[0xCC].execute(&cpu); // CALL Z, 0x5678

    const return_addr2 = cpu.pop();
    try std.testing.expect(return_addr2 == 0x2003);
    try std.testing.expect(cpu.getPC() == 0x5678);
    try std.testing.expect(cycles == 6);

    // Test conditional CALL when condition is false
    cpu.setPC(0x3001);
    cpu.reg.pair.sp = 0xFFFE;
    cpu.mem.writeByte(0x3000, 0xCC); // CALL Z instruction
    cpu.mem.writeByte(0x3001, 0x78); // Low byte
    cpu.mem.writeByte(0x3002, 0x56); // High byte
    cpu.reg.single.f.z = false;

    cycles = OPCODES[0xCC].execute(&cpu); // CALL Z, 0x5678

    try std.testing.expect(cpu.getPC() == 0x3003); // Should not call
    try std.testing.expect(cycles == 3); // Faster when not calling
}

test "return instructions - unconditional and conditional" {
    var cpu = Cpu.init();

    // Test RET (0xC9) - unconditional return
    cpu.reg.pair.sp = 0xFFFC;
    cpu.mem.writeByte(0xFFFC, 0x34); // Return address low byte
    cpu.mem.writeByte(0xFFFD, 0x12); // Return address high byte
    cpu.setPC(0x5000); // Current PC (will be overwritten)

    var cycles = OPCODES[0xC9].execute(&cpu); // RET

    try std.testing.expect(cpu.getPC() == 0x1234);
    try std.testing.expect(cpu.reg.pair.sp == 0xFFFE); // Stack pointer restored
    try std.testing.expect(cycles == 4); // 3 base + 1 for return

    // Test conditional RET when condition is true
    cpu.reg.pair.sp = 0xFFFC;
    cpu.mem.writeByte(0xFFFC, 0x78); // Return address low byte
    cpu.mem.writeByte(0xFFFD, 0x56); // Return address high byte
    cpu.reg.single.f.z = true;
    cpu.setPC(0x6000);

    cycles = OPCODES[0xC8].execute(&cpu); // RET Z

    try std.testing.expect(cpu.getPC() == 0x5678);
    try std.testing.expect(cpu.reg.pair.sp == 0xFFFE);
    try std.testing.expect(cycles == 5); // 3 base + 2 for conditional return

    // Test conditional RET when condition is false
    cpu.reg.pair.sp = 0xFFFC;
    cpu.mem.writeByte(0xFFFC, 0x78); // Return address (shouldn't be used)
    cpu.mem.writeByte(0xFFFD, 0x56);
    cpu.reg.single.f.z = false;
    cpu.setPC(0x7000);

    cycles = OPCODES[0xC8].execute(&cpu); // RET Z

    try std.testing.expect(cpu.getPC() == 0x7000); // Should not return
    try std.testing.expect(cpu.reg.pair.sp == 0xFFFC); // Stack unchanged
    try std.testing.expect(cycles == 2); // Faster when not returning
}

test "restart instructions - RST" {
    var cpu = Cpu.init();

    // Test all RST instructions
    const rst_instructions = [_]struct { opcode: u8, address: u16 }{
        .{ .opcode = 0xC7, .address = 0x00 }, // RST 00h
        .{ .opcode = 0xCF, .address = 0x08 }, // RST 08h
        .{ .opcode = 0xD7, .address = 0x10 }, // RST 10h
        .{ .opcode = 0xDF, .address = 0x18 }, // RST 18h
        .{ .opcode = 0xE7, .address = 0x20 }, // RST 20h
        .{ .opcode = 0xEF, .address = 0x28 }, // RST 28h
        .{ .opcode = 0xF7, .address = 0x30 }, // RST 30h
        .{ .opcode = 0xFF, .address = 0x38 }, // RST 38h
    };

    for (rst_instructions) |rst| {
        cpu.setPC(0x2000);
        cpu.reg.pair.sp = 0xFFFE;

        const cycles = OPCODES[rst.opcode].execute(&cpu);

        // Check that PC was pushed to stack
        const return_addr = cpu.pop();
        try std.testing.expect(return_addr == 0x2000); // Current PC should be pushed
        try std.testing.expect(cpu.getPC() == rst.address); // Jumped to RST vector
        try std.testing.expect(cycles == 4);
    }
}

test "branching instructions - cycle counts verification" {
    var cpu = Cpu.init();

    // Prepare memory and stack for tests
    cpu.mem.writeByte(0x1000, 0x10); // Relative offset
    cpu.mem.writeByte(0x1001, 0x34); // Address low byte
    cpu.mem.writeByte(0x1002, 0x12); // Address high byte
    cpu.reg.pair.sp = 0xFFFC;
    cpu.mem.writeByte(0xFFFC, 0x00); // Return address low
    cpu.mem.writeByte(0xFFFD, 0x10); // Return address high

    // Test cycle counts for various branching instructions
    cpu.setPC(0x1000);
    cpu.reg.single.f.z = false;
    try std.testing.expect(OPCODES[0x18].execute(&cpu) == 3); // JR (unconditional)

    cpu.setPC(0x1000);
    cpu.reg.single.f.z = false;
    try std.testing.expect(OPCODES[0x20].execute(&cpu) == 3); // JR NZ (taken)

    cpu.setPC(0x1000);
    cpu.reg.single.f.z = true;
    try std.testing.expect(OPCODES[0x20].execute(&cpu) == 2); // JR NZ (not taken)

    cpu.setPC(0x1000);
    try std.testing.expect(OPCODES[0xC3].execute(&cpu) == 4); // JP (unconditional)

    cpu.setPC(0x1000);
    cpu.reg.single.f.z = false;
    try std.testing.expect(OPCODES[0xC2].execute(&cpu) == 4); // JP NZ (taken)

    cpu.setPC(0x1000);
    cpu.reg.single.f.z = true;
    try std.testing.expect(OPCODES[0xC2].execute(&cpu) == 3); // JP NZ (not taken)

    cpu.reg.pair.hl = 0x1000;
    try std.testing.expect(OPCODES[0xE9].execute(&cpu) == 1); // JP (HL)

    cpu.setPC(0x1000);
    cpu.reg.pair.sp = 0xFFFE;
    try std.testing.expect(OPCODES[0xCD].execute(&cpu) == 6); // CALL (unconditional)

    cpu.setPC(0x1000);
    cpu.reg.pair.sp = 0xFFFE;
    cpu.reg.single.f.z = true;
    try std.testing.expect(OPCODES[0xCC].execute(&cpu) == 6); // CALL Z (taken)

    cpu.setPC(0x1000);
    cpu.reg.pair.sp = 0xFFFE;
    cpu.reg.single.f.z = false;
    try std.testing.expect(OPCODES[0xCC].execute(&cpu) == 3); // CALL Z (not taken)

    cpu.reg.pair.sp = 0xFFFC;
    try std.testing.expect(OPCODES[0xC9].execute(&cpu) == 4); // RET (unconditional)

    cpu.reg.pair.sp = 0xFFFC;
    cpu.reg.single.f.z = true;
    try std.testing.expect(OPCODES[0xC8].execute(&cpu) == 5); // RET Z (taken)

    cpu.reg.pair.sp = 0xFFFC;
    cpu.reg.single.f.z = false;
    try std.testing.expect(OPCODES[0xC8].execute(&cpu) == 2); // RET Z (not taken)

    cpu.setPC(0x1000);
    cpu.reg.pair.sp = 0xFFFE;
    try std.testing.expect(OPCODES[0xC7].execute(&cpu) == 4); // RST 00h
}

test "branching instructions - flag independence" {
    var cpu = Cpu.init();

    // Test that branching instructions don't modify flags
    cpu.setPC(0x1001);
    cpu.mem.writeByte(0x1000, 0x10); // Jump offset
    cpu.mem.writeByte(0x1001, 0x34); // Address low
    cpu.mem.writeByte(0x1002, 0x12); // Address high

    // Set all flags to known values
    cpu.reg.single.f.z = true;
    cpu.reg.single.f.n = true;
    cpu.reg.single.f.h = true;
    cpu.reg.single.f.c = true;

    const original_flags = cpu.reg.single.f;

    // Test various branching instructions
    _ = OPCODES[0x18].execute(&cpu); // JR
    try std.testing.expect(std.meta.eql(cpu.reg.single.f, original_flags));

    cpu.setPC(0x1001);
    _ = OPCODES[0xC3].execute(&cpu); // JP
    try std.testing.expect(std.meta.eql(cpu.reg.single.f, original_flags));

    cpu.reg.pair.hl = 0x2000;
    _ = OPCODES[0xE9].execute(&cpu); // JP (HL)
    try std.testing.expect(std.meta.eql(cpu.reg.single.f, original_flags));

    cpu.setPC(0x1001);
    cpu.reg.pair.sp = 0xFFFE;
    _ = OPCODES[0xCD].execute(&cpu); // CALL
    try std.testing.expect(std.meta.eql(cpu.reg.single.f, original_flags));

    cpu.reg.pair.sp = 0xFFFC;
    cpu.mem.writeByte(0xFFFC, 0x00);
    cpu.mem.writeByte(0xFFFD, 0x20);
    _ = OPCODES[0xC9].execute(&cpu); // RET
    try std.testing.expect(std.meta.eql(cpu.reg.single.f, original_flags));

    cpu.setPC(0x1001);
    cpu.reg.pair.sp = 0xFFFE;
    _ = OPCODES[0xC7].execute(&cpu); // RST 00h
    try std.testing.expect(std.meta.eql(cpu.reg.single.f, original_flags));
}

// Extended Instructions Tests (CB-prefixed opcodes)

test "extended instructions - rotate left carry (RLC)" {
    var cpu = Cpu.init();

    // Test RLC B (0x00)
    cpu.reg.set8(.b, 0b10000001);
    var cycles = OPCODES_EXT[0x10].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.b) == 0b00000011); // Rotated left with carry
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == false);
    try std.testing.expect(cpu.reg.single.f.c == true); // MSB was 1

    // Test RLC C (0x01) with zero result
    cpu.reg.set8(.c, 0b00000000);
    cycles = OPCODES_EXT[0x11].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.c) == 0b00000000);
    try std.testing.expect(cpu.reg.single.f.z == true);
    try std.testing.expect(cpu.reg.single.f.c == false);

    // Test RLC D (0x02)
    cpu.reg.set8(.d, 0b01010101);
    cycles = OPCODES_EXT[0x12].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.d) == 0b10101010);
    try std.testing.expect(cpu.reg.single.f.c == false); // MSB was 0

    // Test RLC (HL) (0x06) - memory operation
    const addr: u16 = 0x8000;
    cpu.reg.set16(.hl, addr);
    cpu.mem.writeByte(addr, 0b11000000);
    cycles = OPCODES_EXT[0x16].execute(&cpu);
    try std.testing.expect(cycles == 4);
    try std.testing.expect(cpu.mem.readByte(addr) == 0b10000001);
    try std.testing.expect(cpu.reg.single.f.c == true);

    // Test RLC A (0x07)
    cpu.reg.set8(.a, 0xFF);
    cycles = OPCODES_EXT[0x17].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.a) == 0xFF);
    try std.testing.expect(cpu.reg.single.f.c == true);
}

test "extended instructions - rotate right carry (RRC)" {
    var cpu = Cpu.init();

    // Test RRC B (0x08)
    cpu.reg.set8(.b, 0b10000001);
    var cycles = OPCODES_EXT[0x18].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.b) == 0b11000000); // Rotated right with carry
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == false);
    try std.testing.expect(cpu.reg.single.f.c == true); // LSB was 1

    // Test RRC C (0x09)
    cpu.reg.set8(.c, 0b01010100);
    cycles = OPCODES_EXT[0x19].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.c) == 0b00101010);
    try std.testing.expect(cpu.reg.single.f.c == false); // LSB was 0

    // Test RRC (HL) (0x0E) - memory operation
    const addr: u16 = 0x8000;
    cpu.reg.set16(.hl, addr);
    cpu.mem.writeByte(addr, 0b00000011);
    cycles = OPCODES_EXT[0x1E].execute(&cpu);
    try std.testing.expect(cycles == 4);
    try std.testing.expect(cpu.mem.readByte(addr) == 0b10000001);
    try std.testing.expect(cpu.reg.single.f.c == true);
}

test "extended instructions - rotate left through carry (RL)" {
    var cpu = Cpu.init();

    // Test RL B (0x10) with carry flag clear
    cpu.reg.set8(.b, 0b10000001);
    cpu.reg.single.f.c = false;
    var cycles = OPCODES_EXT[0x00].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.b) == 0b00000010); // Rotated left, carry in = 0
    try std.testing.expect(cpu.reg.single.f.c == true); // MSB was 1

    // Test RL C (0x11) with carry flag set
    cpu.reg.set8(.c, 0b01000000);
    cpu.reg.single.f.c = true;
    cycles = OPCODES_EXT[0x01].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.c) == 0b10000001); // Rotated left, carry in = 1
    try std.testing.expect(cpu.reg.single.f.c == false); // MSB was 0

    // Test RL D (0x12) zero result
    cpu.reg.set8(.d, 0b00000000);
    cpu.reg.single.f.c = false;
    cycles = OPCODES_EXT[0x02].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.d) == 0b00000000);
    try std.testing.expect(cpu.reg.single.f.z == true);
    try std.testing.expect(cpu.reg.single.f.c == false);
}

test "extended instructions - rotate right through carry (RR)" {
    var cpu = Cpu.init();

    // Test RR B (0x18) with carry flag clear
    cpu.reg.set8(.b, 0b10000001);
    cpu.reg.single.f.c = false;
    var cycles = OPCODES_EXT[0x08].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.b) == 0b01000000); // Rotated right, carry in = 0
    try std.testing.expect(cpu.reg.single.f.c == true); // LSB was 1

    // Test RR C (0x19) with carry flag set
    cpu.reg.set8(.c, 0b00000010);
    cpu.reg.single.f.c = true;
    cycles = OPCODES_EXT[0x09].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.c) == 0b10000001); // Rotated right, carry in = 1
    try std.testing.expect(cpu.reg.single.f.c == false); // LSB was 0
}

test "extended instructions - shift left arithmetic (SLA)" {
    var cpu = Cpu.init();

    // Test SLA B (0x20)
    cpu.reg.set8(.b, 0b01000001);
    var cycles = OPCODES_EXT[0x20].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.b) == 0b10000010); // Shifted left, LSB = 0
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == false);
    try std.testing.expect(cpu.reg.single.f.c == false); // MSB was 0

    // Test SLA C (0x21) with carry
    cpu.reg.set8(.c, 0b10000000);
    cycles = OPCODES_EXT[0x21].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.c) == 0b00000000);
    try std.testing.expect(cpu.reg.single.f.z == true);
    try std.testing.expect(cpu.reg.single.f.c == true); // MSB was 1

    // Test SLA (HL) (0x26)
    const addr: u16 = 0x8000;
    cpu.reg.set16(.hl, addr);
    cpu.mem.writeByte(addr, 0b11110000);
    cycles = OPCODES_EXT[0x26].execute(&cpu);
    try std.testing.expect(cycles == 4);
    try std.testing.expect(cpu.mem.readByte(addr) == 0b11100000);
    try std.testing.expect(cpu.reg.single.f.c == true);
}

test "extended instructions - shift right arithmetic (SRA)" {
    var cpu = Cpu.init();

    // Test SRA B (0x28) - positive number
    cpu.reg.set8(.b, 0b01000010);
    var cycles = OPCODES_EXT[0x28].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.b) == 0b00100001); // Shifted right, MSB = 0 (preserved)
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.c == false); // LSB was 0

    // Test SRA C (0x29) - negative number
    cpu.reg.set8(.c, 0b10000011);
    cycles = OPCODES_EXT[0x29].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.c) == 0b11000001); // Shifted right, MSB = 1 (preserved)
    try std.testing.expect(cpu.reg.single.f.c == true); // LSB was 1

    // Test SRA D (0x2A) - zero result
    cpu.reg.set8(.d, 0b00000001);
    cycles = OPCODES_EXT[0x2A].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.d) == 0b00000000);
    try std.testing.expect(cpu.reg.single.f.z == true);
    try std.testing.expect(cpu.reg.single.f.c == true);
}

test "extended instructions - swap nibbles (SWAP)" {
    var cpu = Cpu.init();

    // Test SWAP B (0x30)
    cpu.reg.set8(.b, 0xAB);
    var cycles = OPCODES_EXT[0x30].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.b) == 0xBA);
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == false);
    try std.testing.expect(cpu.reg.single.f.c == false); // SWAP always clears carry

    // Test SWAP C (0x31) with zero result
    cpu.reg.set8(.c, 0x00);
    cycles = OPCODES_EXT[0x31].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.c) == 0x00);
    try std.testing.expect(cpu.reg.single.f.z == true);

    // Test SWAP D (0x32)
    cpu.reg.set8(.d, 0xF0);
    cycles = OPCODES_EXT[0x32].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.d) == 0x0F);

    // Test SWAP (HL) (0x36)
    const addr: u16 = 0x8000;
    cpu.reg.set16(.hl, addr);
    cpu.mem.writeByte(addr, 0x12);
    cycles = OPCODES_EXT[0x36].execute(&cpu);
    try std.testing.expect(cycles == 4);
    try std.testing.expect(cpu.mem.readByte(addr) == 0x21);
}

test "extended instructions - shift right logical (SRL)" {
    var cpu = Cpu.init();

    // Test SRL B (0x38)
    cpu.reg.set8(.b, 0b10000001);
    var cycles = OPCODES_EXT[0x38].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.b) == 0b01000000); // Shifted right, MSB = 0
    try std.testing.expect(cpu.reg.single.f.z == false);
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == false);
    try std.testing.expect(cpu.reg.single.f.c == true); // LSB was 1

    // Test SRL C (0x39) with zero result
    cpu.reg.set8(.c, 0b00000001);
    cycles = OPCODES_EXT[0x39].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.c) == 0b00000000);
    try std.testing.expect(cpu.reg.single.f.z == true);
    try std.testing.expect(cpu.reg.single.f.c == true);

    // Test SRL D (0x3A)
    cpu.reg.set8(.d, 0b11111110);
    cycles = OPCODES_EXT[0x3A].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.d) == 0b01111111);
    try std.testing.expect(cpu.reg.single.f.c == false); // LSB was 0
}

test "extended instructions - bit test (BIT)" {
    var cpu = Cpu.init();

    // Test BIT 0, B (0x40)
    cpu.reg.set8(.b, 0b00000001);
    var cycles = OPCODES_EXT[0x40].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.b) == 0b00000001); // Value unchanged
    try std.testing.expect(cpu.reg.single.f.z == false); // Bit 0 is set
    try std.testing.expect(cpu.reg.single.f.n == false);
    try std.testing.expect(cpu.reg.single.f.h == true); // BIT always sets H

    // Test BIT 0, C (0x41) - bit not set
    cpu.reg.set8(.c, 0b11111110);
    cycles = OPCODES_EXT[0x41].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.c) == 0b11111110); // Value unchanged
    try std.testing.expect(cpu.reg.single.f.z == true); // Bit 0 is not set

    // Test BIT 7, A (0x7F)
    cpu.reg.set8(.a, 0b10000000);
    cycles = OPCODES_EXT[0x7F].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.single.f.z == false); // Bit 7 is set

    // Test BIT 7, A (0x7F) - bit not set
    cpu.reg.set8(.a, 0b01111111);
    cycles = OPCODES_EXT[0x7F].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.single.f.z == true); // Bit 7 is not set

    // Test BIT 3, (HL) (0x5E)
    const addr: u16 = 0x8000;
    cpu.reg.set16(.hl, addr);
    cpu.mem.writeByte(addr, 0b00001000);
    cycles = OPCODES_EXT[0x5E].execute(&cpu);
    try std.testing.expect(cycles == 4);
    try std.testing.expect(cpu.mem.readByte(addr) == 0b00001000); // Memory unchanged
    try std.testing.expect(cpu.reg.single.f.z == false); // Bit 3 is set
}

test "extended instructions - reset bit (RES)" {
    var cpu = Cpu.init();

    // Test RES 0, B (0x80)
    cpu.reg.set8(.b, 0b11111111);
    var cycles = OPCODES_EXT[0x80].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.b) == 0b11111110); // Bit 0 cleared

    // Test RES 0, C (0x81) - bit already clear
    cpu.reg.set8(.c, 0b11111110);
    cycles = OPCODES_EXT[0x81].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.c) == 0b11111110); // No change

    // Test RES 7, A (0xBF)
    cpu.reg.set8(.a, 0b10101010);
    cycles = OPCODES_EXT[0xBF].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.a) == 0b00101010); // Bit 7 cleared

    // Test RES 4, (HL) (0xA6)
    const addr: u16 = 0x8000;
    cpu.reg.set16(.hl, addr);
    cpu.mem.writeByte(addr, 0b11111111);
    cycles = OPCODES_EXT[0xA6].execute(&cpu);
    try std.testing.expect(cycles == 4);
    try std.testing.expect(cpu.mem.readByte(addr) == 0b11101111); // Bit 4 cleared

    // Verify RES doesn't affect flags (except for memory operations)
    const original_flags = cpu.reg.single.f;
    cpu.reg.set8(.d, 0xFF);
    _ = OPCODES_EXT[0x92].execute(&cpu); // RES 2, D
    try std.testing.expect(std.meta.eql(cpu.reg.single.f, original_flags));
}

test "extended instructions - set bit (SET)" {
    var cpu = Cpu.init();

    // Test SET 0, B (0xC0)
    cpu.reg.set8(.b, 0b00000000);
    var cycles = OPCODES_EXT[0xC0].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.b) == 0b00000001); // Bit 0 set

    // Test SET 0, C (0xC1) - bit already set
    cpu.reg.set8(.c, 0b00000001);
    cycles = OPCODES_EXT[0xC1].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.c) == 0b00000001); // No change

    // Test SET 7, A (0xFF)
    cpu.reg.set8(.a, 0b01010101);
    cycles = OPCODES_EXT[0xFF].execute(&cpu);
    try std.testing.expect(cycles == 2);
    try std.testing.expect(cpu.reg.get8(.a) == 0b11010101); // Bit 7 set

    // Test SET 3, (HL) (0xDE)
    const addr: u16 = 0x8000;
    cpu.reg.set16(.hl, addr);
    cpu.mem.writeByte(addr, 0b00000000);
    cycles = OPCODES_EXT[0xDE].execute(&cpu);
    try std.testing.expect(cycles == 4);
    try std.testing.expect(cpu.mem.readByte(addr) == 0b00001000); // Bit 3 set

    // Verify SET doesn't affect flags
    const original_flags = cpu.reg.single.f;
    cpu.reg.set8(.e, 0x00);
    _ = OPCODES_EXT[0xD3].execute(&cpu); // SET 2, E
    try std.testing.expect(std.meta.eql(cpu.reg.single.f, original_flags));
}

test "extended instructions - comprehensive bit operations" {
    var cpu = Cpu.init();

    // Test all bit positions for BIT operations
    for (0..8) |bit_pos| {
        const bit_val: u8 = @intCast(@as(u8, 1) << @as(u3, @intCast(bit_pos)));

        // Test BIT n, B
        const bit_opcode: u8 = @intCast(0x40 + (bit_pos * 8)); // BIT n, B opcodes
        cpu.reg.set8(.b, bit_val);
        _ = OPCODES_EXT[bit_opcode].execute(&cpu);
        try std.testing.expect(cpu.reg.single.f.z == false); // Bit is set

        cpu.reg.set8(.b, ~bit_val);
        _ = OPCODES_EXT[bit_opcode].execute(&cpu);
        try std.testing.expect(cpu.reg.single.f.z == true); // Bit is not set

        // Test RES n, C
        const res_opcode: u8 = @intCast(0x81 + (bit_pos * 8)); // RES n, C opcodes
        cpu.reg.set8(.c, 0xFF);
        _ = OPCODES_EXT[res_opcode].execute(&cpu);
        try std.testing.expect(cpu.reg.get8(.c) == (0xFF & ~bit_val)); // Bit cleared

        // Test SET n, D
        const set_opcode: u8 = @intCast(0xC2 + (bit_pos * 8)); // SET n, D opcodes
        cpu.reg.set8(.d, 0x00);
        _ = OPCODES_EXT[set_opcode].execute(&cpu);
        try std.testing.expect(cpu.reg.get8(.d) == bit_val); // Bit set
    }
}

test "extended instructions - register ordering verification" {
    var cpu = Cpu.init();

    // Verify the register order matches expected pattern: B, C, D, E, H, L, (HL), A
    const test_value: u8 = 0b10101010; // => 170d

    cpu.reg.set8(.b, test_value);
    cpu.reg.set8(.c, test_value);
    cpu.reg.set8(.d, test_value);
    cpu.reg.set8(.e, test_value);
    cpu.reg.set8(.h, test_value);
    cpu.reg.set8(.l, test_value);
    cpu.reg.set8(.a, test_value);

    // Test RLC for all registers to verify ordering
    _ = OPCODES_EXT[0x00].execute(&cpu); // RLC B
    _ = OPCODES_EXT[0x01].execute(&cpu); // RLC C
    _ = OPCODES_EXT[0x02].execute(&cpu); // RLC D
    _ = OPCODES_EXT[0x03].execute(&cpu); // RLC E
    _ = OPCODES_EXT[0x04].execute(&cpu); // RLC H
    _ = OPCODES_EXT[0x05].execute(&cpu); // RLC L
    _ = OPCODES_EXT[0x07].execute(&cpu); // RLC A

    const expected: u8 = 0b01010101; // After rotating left => 85d
    try std.testing.expect(cpu.reg.get8(.b) == expected - 1); // On first RLC, C is false to bits 0 is 0
    try std.testing.expect(cpu.reg.get8(.c) == expected);
    try std.testing.expect(cpu.reg.get8(.d) == expected);
    try std.testing.expect(cpu.reg.get8(.e) == expected);
    try std.testing.expect(cpu.reg.get8(.h) == expected);
    try std.testing.expect(cpu.reg.get8(.l) == expected);
    try std.testing.expect(cpu.reg.get8(.a) == expected);

    const addr: u16 = 0x8000;
    cpu.reg.set16(.hl, addr);
    cpu.mem.writeByte(addr, test_value);
    _ = OPCODES_EXT[0x06].execute(&cpu); // RLC (HL)

    // All should have the same result after RLC
    try std.testing.expect(cpu.mem.readByte(addr) == expected);
}

test "extended instructions - cycle counts verification" {
    var cpu = Cpu.init();

    const addr: u16 = 0x8000;
    cpu.reg.set16(.hl, addr);
    cpu.mem.writeByte(addr, 0x42);

    // All register operations should take 2 cycles
    try std.testing.expect(OPCODES_EXT[0x00].execute(&cpu) == 2); // RLC B
    try std.testing.expect(OPCODES_EXT[0x08].execute(&cpu) == 2); // RRC B
    try std.testing.expect(OPCODES_EXT[0x10].execute(&cpu) == 2); // RL B
    try std.testing.expect(OPCODES_EXT[0x18].execute(&cpu) == 2); // RR B
    try std.testing.expect(OPCODES_EXT[0x20].execute(&cpu) == 2); // SLA B
    try std.testing.expect(OPCODES_EXT[0x28].execute(&cpu) == 2); // SRA B
    try std.testing.expect(OPCODES_EXT[0x30].execute(&cpu) == 2); // SWAP B
    try std.testing.expect(OPCODES_EXT[0x38].execute(&cpu) == 2); // SRL B
    try std.testing.expect(OPCODES_EXT[0x40].execute(&cpu) == 2); // BIT 0, B
    try std.testing.expect(OPCODES_EXT[0x80].execute(&cpu) == 2); // RES 0, B
    try std.testing.expect(OPCODES_EXT[0xC0].execute(&cpu) == 2); // SET 0, B

    // All memory operations should take 4 cycles
    try std.testing.expect(OPCODES_EXT[0x06].execute(&cpu) == 4); // RLC (HL)
    try std.testing.expect(OPCODES_EXT[0x0E].execute(&cpu) == 4); // RRC (HL)
    try std.testing.expect(OPCODES_EXT[0x16].execute(&cpu) == 4); // RL (HL)
    try std.testing.expect(OPCODES_EXT[0x1E].execute(&cpu) == 4); // RR (HL)
    try std.testing.expect(OPCODES_EXT[0x26].execute(&cpu) == 4); // SLA (HL)
    try std.testing.expect(OPCODES_EXT[0x2E].execute(&cpu) == 4); // SRA (HL)
    try std.testing.expect(OPCODES_EXT[0x36].execute(&cpu) == 4); // SWAP (HL)
    try std.testing.expect(OPCODES_EXT[0x3E].execute(&cpu) == 4); // SRL (HL)
    try std.testing.expect(OPCODES_EXT[0x46].execute(&cpu) == 4); // BIT 0, (HL)
    try std.testing.expect(OPCODES_EXT[0x86].execute(&cpu) == 4); // RES 0, (HL)
    try std.testing.expect(OPCODES_EXT[0xC6].execute(&cpu) == 4); // SET 0, (HL)
}

test "extended instructions - flag preservation for bit operations" {
    var cpu = Cpu.init();

    // Set all flags to known values
    cpu.reg.single.f.z = true;
    cpu.reg.single.f.n = true;
    cpu.reg.single.f.h = true;
    cpu.reg.single.f.c = true;
    const original_flags = cpu.reg.single.f;

    // RES and SET should not affect any flags
    cpu.reg.set8(.b, 0xFF);
    _ = OPCODES_EXT[0x80].execute(&cpu); // RES 0, B
    try std.testing.expect(std.meta.eql(cpu.reg.single.f, original_flags));

    _ = OPCODES_EXT[0xC0].execute(&cpu); // SET 0, B
    try std.testing.expect(std.meta.eql(cpu.reg.single.f, original_flags));

    // BIT should only affect Z, N, H flags (C is preserved)
    _ = OPCODES_EXT[0x40].execute(&cpu); // BIT 0, B
    try std.testing.expect(cpu.reg.single.f.z == false); // Bit 0 is set
    try std.testing.expect(cpu.reg.single.f.n == false); // BIT clears N
    try std.testing.expect(cpu.reg.single.f.h == true); // BIT sets H
    try std.testing.expect(cpu.reg.single.f.c == true); // C preserved
}
