const std = @import("std");

const asm_ = @import("../asm.zig");
const inst = @import("../../core/cpu/instruction.zig");

fn assembleAt(src: []const u8, out: []u8) ![]const u8 {
    var diag = asm_.Diag{};
    const res = asm_.assembleBuf(src, out, &diag) catch |e| {
        std.debug.print("asm error line {d}: {s}\n", .{ diag.line, diag.msg() });
        return e;
    };
    return out[0..res.len];
}

fn expectBytes(src: []const u8, expected: []const u8) !void {
    var buf: [512]u8 = undefined;
    const got = try assembleAt(src, &buf);
    try std.testing.expectEqualSlices(u8, expected, got);
}

test "asm - single byte instructions" {
    try expectBytes("NOP", &.{0x00});
    try expectBytes("HALT", &.{0x76});
    try expectBytes("RET", &.{0xC9});
    try expectBytes("DI\nEI", &.{ 0xF3, 0xFB });
}

test "asm - LD r, r' covers the 0x40 block" {
    try expectBytes("LD B, B", &.{0x40});
    try expectBytes("LD A, A", &.{0x7F});
    try expectBytes("LD A, E", &.{0x7B});
    try expectBytes("LD (HL), A", &.{0x77});
    try expectBytes("LD A, (HL)", &.{0x7E});
}

test "asm - immediates" {
    try expectBytes("LD B, 5", &.{ 0x06, 0x05 });
    try expectBytes("LD HL, $1234", &.{ 0x21, 0x34, 0x12 });
    try expectBytes("LD HL, 0x1234", &.{ 0x21, 0x34, 0x12 });
    try expectBytes("LD SP, $FFFE", &.{ 0x31, 0xFE, 0xFF });
    try expectBytes("ADD A, 1", &.{ 0xC6, 0x01 });
    try expectBytes("CP A, 11", &.{ 0xFE, 0x0B });
}

test "asm - alu with and without explicit A" {
    try expectBytes("ADD A, B", &.{0x80});
    try expectBytes("ADD B", &.{0x80});
    try expectBytes("XOR A", &.{0xAF});
    try expectBytes("CP C", &.{0xB9});
}

test "asm - memory operand spellings" {
    try expectBytes("LD (HL+), A", &.{0x22});
    try expectBytes("LD [HL+], A", &.{0x22});
    try expectBytes("LD A, (0xB000)", &.{ 0xFA, 0x00, 0xB0 });
    try expectBytes("LD (0xB000), A", &.{ 0xEA, 0x00, 0xB0 });
    try expectBytes("LD (0xFF00), SP", &.{ 0x08, 0x00, 0xFF });
}

test "asm - CB page" {
    try expectBytes("RLC B", &.{ 0xCB, 0x00 });
    try expectBytes("SRL A", &.{ 0xCB, 0x3F });
    try expectBytes("BIT 7, (HL)", &.{ 0xCB, 0x7E });
    try expectBytes("RES 0, B", &.{ 0xCB, 0x80 });
    try expectBytes("SET 7, A", &.{ 0xCB, 0xFF });
}

test "asm - labels resolve for absolute jumps" {
    try expectBytes(
        \\.org $0000
        \\start:
        \\  NOP
        \\  JP start
    , &.{ 0x00, 0xC3, 0x00, 0x00 });

    // Forward reference.
    try expectBytes(
        \\.org $0000
        \\  JP done
        \\  NOP
        \\done:
        \\  HALT
    , &.{ 0xC3, 0x04, 0x00, 0x00, 0x76 });
}

test "asm - labels honour .org" {
    try expectBytes(
        \\.org $8000
        \\start:
        \\  JP start
    , &.{ 0xC3, 0x00, 0x80 });
}

test "asm - relative jumps compute offsets" {
    // JR to itself: target - (pc + 2) = -2
    try expectBytes(
        \\.org $0000
        \\here:
        \\  JR here
    , &.{ 0x18, 0xFE });

    try expectBytes(
        \\.org $0000
        \\  JR NZ, fwd
        \\  NOP
        \\fwd:
        \\  HALT
    , &.{ 0x20, 0x01, 0x00, 0x76 });
}

test "asm - relative jump out of range is an error" {
    var buf: [1024]u8 = undefined;
    var diag = asm_.Diag{};
    const src =
        \\.org $0000
        \\  JR far
        \\  ds 200
        \\far:
        \\  HALT
    ;
    try std.testing.expectError(
        asm_.Error.JumpOutOfRange,
        asm_.assembleBuf(src, &buf, &diag),
    );
}

test "asm - data directives" {
    try expectBytes("db 1, 2, $ff", &.{ 0x01, 0x02, 0xFF });
    try expectBytes("dw $1234, $abcd", &.{ 0x34, 0x12, 0xCD, 0xAB });
    try expectBytes("ds 3", &.{ 0x00, 0x00, 0x00 });
    try expectBytes("db 1\nds 2\ndb 2", &.{ 0x01, 0x00, 0x00, 0x02 });
}

test "asm - equ and expressions" {
    try expectBytes(
        \\base equ $B000
        \\  LD HL, base
        \\  LD HL, base + 2
    , &.{ 0x21, 0x00, 0xB0, 0x21, 0x02, 0xB0 });
}

test "asm - .org pads forward" {
    try expectBytes(
        \\.org $0000
        \\  NOP
        \\.org $0004
        \\  HALT
    , &.{ 0x00, 0x00, 0x00, 0x00, 0x76 });
}

test "asm - unknown instruction is an error" {
    var buf: [64]u8 = undefined;
    var diag = asm_.Diag{};
    try std.testing.expectError(
        asm_.Error.UnknownInstruction,
        asm_.assembleBuf("FROBNICATE A", &buf, &diag),
    );
}

test "asm - comptime assembly" {
    const prog = comptime asm_.assemble(
        \\.org $0100
        \\start:
        \\  LD HL, $0002
        \\  JP start
    );
    try std.testing.expectEqualSlices(u8, &.{ 0x21, 0x02, 0x00, 0xC3, 0x00, 0x01 }, prog);
    try std.testing.expectEqual(@as(u16, 0x0100), comptime asm_.assembleOrigin(".org $0100\nNOP"));
}

// Guards against the assembler and the emulator drifting apart.
//
// The names in `metadata` are written for logging, not parsing (0xFA reads
// "LD A. (u16)", 0xEA uses "a16"), so this compares operand *width* and
// coverage rather than exact spelling.
test "asm - cross-check operand widths against the emulator table" {
    var mismatches: u32 = 0;

    for (0..256) |i| {
        const op: u8 = @intCast(i);
        const name = inst.getOpcode(op).metadata.name;
        if (std.mem.startsWith(u8, name, "INVALID")) continue;
        if (std.mem.eql(u8, name, "PREFIX CB")) continue;

        const expected: usize = if (std.mem.indexOf(u8, name, "u16") != null or
            std.mem.indexOf(u8, name, "a16") != null)
            2
        else if (std.mem.indexOf(u8, name, "u8") != null or
            std.mem.indexOf(u8, name, "i8") != null)
            1
        else
            0;

        const actual = asm_.immWidthForOpcode(op) orelse {
            std.debug.print("opcode 0x{X:0>2} ({s}) missing from assembler table\n", .{ op, name });
            mismatches += 1;
            continue;
        };

        if (actual != expected) {
            std.debug.print(
                "opcode 0x{X:0>2} ({s}): emulator says {d} immediate byte(s), assembler says {d}\n",
                .{ op, name, expected, actual },
            );
            mismatches += 1;
        }
    }

    try std.testing.expectEqual(@as(u32, 0), mismatches);
}

test "asm - every non-CB opcode is reachable from some mnemonic" {
    var covered = [_]bool{false} ** 256;
    for (asm_.TABLE) |e| {
        if (!e.cb) covered[e.op] = true;
    }

    var missing: u32 = 0;
    for (0..256) |i| {
        const name = inst.getOpcode(@intCast(i)).metadata.name;
        if (std.mem.startsWith(u8, name, "INVALID")) continue;
        if (std.mem.eql(u8, name, "PREFIX CB")) continue;
        if (!covered[i]) {
            std.debug.print("opcode 0x{X:0>2} ({s}) has no assembler form\n", .{ i, name });
            missing += 1;
        }
    }
    try std.testing.expectEqual(@as(u32, 0), missing);
}

test "asm - fib.s reproduces bin/fib.gb byte for byte" {
    const io = std.testing.io;

    const src = std.Io.Dir.cwd().readFileAlloc(
        io,
        "progs/fib.s",
        std.testing.allocator,
        .limited(64 * 1024),
    ) catch return error.SkipZigTest;
    defer std.testing.allocator.free(src);

    const expected = std.Io.Dir.cwd().readFileAlloc(
        io,
        "bin/fib.gb",
        std.testing.allocator,
        .limited(64 * 1024),
    ) catch return error.SkipZigTest;
    defer std.testing.allocator.free(expected);

    var buf: [4096]u8 = undefined;
    const got = try assembleAt(src, &buf);

    try std.testing.expectEqualSlices(u8, expected, got);
}
