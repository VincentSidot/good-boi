/// A utility function to perform addition with carry check.
pub inline fn checkCarryAdd(comptime T: type, a: T, b: T) struct {
    /// The result of the addition.
    value: T,
    /// Whether a carry occurred during the addition.
    carry: bool,
    /// Whether a half-carry occurred during the addition. (A carry from bit bits/2 to bits/2-1)
    halfCarry: bool,
} {
    const halfPartCheck, const halfMask = comptime blk: {
        const Tinfo = @typeInfo(T);

        switch (Tinfo) {
            .int => |int_info| {
                if (int_info.signedness == .unsigned) {
                    switch (int_info.bits) {
                        8 => break :blk .{ 1 << 4, (1 << 4) - 1 }, // Half-carry bit is bit 4
                        16 => break :blk .{ 1 << 12, (1 << 12) - 1 }, // Half-carry bit is bit 12 (I do not know why, but it is)
                        else => {},
                    }
                }
            },
            else => {},
        }

        @compileError("Expecting u16 or u8");
    };

    const value: T, const carry: u1 = @addWithOverflow(a, b);

    const halfCarry = ((a & halfMask) + (b & halfMask)) & halfPartCheck != 0;

    return .{
        .value = value,
        .carry = carry != 0,
        .halfCarry = halfCarry,
    };
}

pub inline fn checkBorrowSub(comptime T: type, a: T, b: T) struct {
    /// The result of the subtraction.
    value: T,
    /// Whether a borrow occurred during the subtraction.
    borrow: bool,
    /// Whether a half-borrow occurred during the subtraction. (A borrow from bit bits/2 to bits/2-1)
    halfBorrow: bool,
} {
    const halfMask = comptime blk: {
        const Tinfo = @typeInfo(T);

        switch (Tinfo) {
            .int => |int_info| {
                if (int_info.signedness == .unsigned) {
                    switch (int_info.bits) {
                        8 => break :blk (1 << 4) - 1, // Half-carry bit is bit 4
                        16 => break :blk (1 << 12) - 1, // Half-carry bit is bit 12 (I do not know why, but it is)
                        else => {},
                    }
                }
            },
            else => {},
        }

        @compileError("Expecting u16 or u8");
    };

    const value: T, const borrow: u1 = @subWithOverflow(a, b);

    const halfBorrow = ((a & halfMask) < (b & halfMask));

    return .{
        .value = value,
        .borrow = borrow != 0,
        .halfBorrow = halfBorrow,
    };
}

pub inline fn mergeBytes(low: u8, high: u8) u16 {
    return @as(u16, low) | (@as(u16, high) << 8);
}

pub inline fn splitBytes(value: u16) struct {
    low: u8,
    high: u8,
} {
    return .{
        .low = @as(u8, @intCast(value & 0x00FF)),
        .high = @as(u8, @intCast((value >> 8) & 0x00FF)),
    };
}

test "mergeBytes - basic combinations" {
    const std = @import("std");

    // Test merging 0x00 and 0x00
    const result1 = mergeBytes(0x00, 0x00);
    try std.testing.expect(result1 == 0x0000);

    // Test merging 0xFF and 0x00
    const result2 = mergeBytes(0xFF, 0x00);
    try std.testing.expect(result2 == 0x00FF);

    // Test merging 0x00 and 0xFF
    const result3 = mergeBytes(0x00, 0xFF);
    try std.testing.expect(result3 == 0xFF00);

    // Test merging 0xFF and 0xFF
    const result4 = mergeBytes(0xFF, 0xFF);
    try std.testing.expect(result4 == 0xFFFF);
}

test "mergeBytes - specific values" {
    const std = @import("std");

    // Test merging 0x34 and 0x12 -> 0x1234
    const result1 = mergeBytes(0x34, 0x12);
    try std.testing.expect(result1 == 0x1234);

    // Test merging 0xCD and 0xAB -> 0xABCD
    const result2 = mergeBytes(0xCD, 0xAB);
    try std.testing.expect(result2 == 0xABCD);

    // Test merging 0x00 and 0x80 -> 0x8000
    const result3 = mergeBytes(0x00, 0x80);
    try std.testing.expect(result3 == 0x8000);

    // Test merging 0x01 and 0x00 -> 0x0001
    const result4 = mergeBytes(0x01, 0x00);
    try std.testing.expect(result4 == 0x0001);
}

test "splitBytes - basic values" {
    const std = @import("std");

    // Test splitting 0x0000
    const result1 = splitBytes(0x0000);
    try std.testing.expect(result1.low == 0x00);
    try std.testing.expect(result1.high == 0x00);

    // Test splitting 0x00FF
    const result2 = splitBytes(0x00FF);
    try std.testing.expect(result2.low == 0xFF);
    try std.testing.expect(result2.high == 0x00);

    // Test splitting 0xFF00
    const result3 = splitBytes(0xFF00);
    try std.testing.expect(result3.low == 0x00);
    try std.testing.expect(result3.high == 0xFF);

    // Test splitting 0xFFFF
    const result4 = splitBytes(0xFFFF);
    try std.testing.expect(result4.low == 0xFF);
    try std.testing.expect(result4.high == 0xFF);
}

test "splitBytes - specific values" {
    const std = @import("std");

    // Test splitting 0x1234 -> low: 0x34, high: 0x12
    const result1 = splitBytes(0x1234);
    try std.testing.expect(result1.low == 0x34);
    try std.testing.expect(result1.high == 0x12);

    // Test splitting 0xABCD -> low: 0xCD, high: 0xAB
    const result2 = splitBytes(0xABCD);
    try std.testing.expect(result2.low == 0xCD);
    try std.testing.expect(result2.high == 0xAB);

    // Test splitting 0x8000 -> low: 0x00, high: 0x80
    const result3 = splitBytes(0x8000);
    try std.testing.expect(result3.low == 0x00);
    try std.testing.expect(result3.high == 0x80);

    // Test splitting 0x0001 -> low: 0x01, high: 0x00
    const result4 = splitBytes(0x0001);
    try std.testing.expect(result4.low == 0x01);
    try std.testing.expect(result4.high == 0x00);
}

test "mergeBytes and splitBytes - roundtrip" {
    const std = @import("std");

    // Test that splitting and merging gives back the original value
    const original1: u16 = 0x1234;
    const split1 = splitBytes(original1);
    const merged1 = mergeBytes(split1.low, split1.high);
    try std.testing.expect(merged1 == original1);

    const original2: u16 = 0xABCD;
    const split2 = splitBytes(original2);
    const merged2 = mergeBytes(split2.low, split2.high);
    try std.testing.expect(merged2 == original2);

    const original3: u16 = 0x0000;
    const split3 = splitBytes(original3);
    const merged3 = mergeBytes(split3.low, split3.high);
    try std.testing.expect(merged3 == original3);

    const original4: u16 = 0xFFFF;
    const split4 = splitBytes(original4);
    const merged4 = mergeBytes(split4.low, split4.high);
    try std.testing.expect(merged4 == original4);

    // Test with all possible byte combinations (comprehensive check)
    var low: u8 = 0;
    while (true) {
        var high: u8 = 0;
        while (true) {
            const merged = mergeBytes(low, high);
            const split = splitBytes(merged);
            try std.testing.expect(split.low == low);
            try std.testing.expect(split.high == high);

            if (high == 255) break;
            high += 1;
        }
        if (low == 255) break;
        low += 1;
    }
}

test "mergeBytes and splitBytes - edge cases" {
    const std = @import("std");

    // Test byte ordering is little-endian (low byte first)
    const result1 = mergeBytes(0x78, 0x56);
    try std.testing.expect(result1 == 0x5678);

    // Verify that low byte is in bits 0-7
    const result2 = mergeBytes(0x12, 0x00);
    try std.testing.expect((result2 & 0x00FF) == 0x12);

    // Verify that high byte is in bits 8-15
    const result3 = mergeBytes(0x00, 0x34);
    try std.testing.expect((result3 >> 8) == 0x34);

    // Test split maintains byte positions
    const split1 = splitBytes(0x9ABC);
    try std.testing.expect(split1.low == 0xBC);
    try std.testing.expect(split1.high == 0x9A);
}

test "checkCarryAdd - basic addition without carry" {
    const std = @import("std");

    // Test u8: 5 + 3 = 8, no carry, no half-carry
    const result_u8 = checkCarryAdd(u8, 5, 3);
    try std.testing.expect(result_u8.value == 8);
    try std.testing.expect(result_u8.carry == false);
    try std.testing.expect(result_u8.halfCarry == false);

    // Test u16: 100 + 50 = 150, no carry, no half-carry
    const result_u16 = checkCarryAdd(u16, 100, 50);
    try std.testing.expect(result_u16.value == 150);
    try std.testing.expect(result_u16.carry == false);
    try std.testing.expect(result_u16.halfCarry == false);
}

test "checkCarryAdd - addition with carry" {
    const std = @import("std");

    // Test u8: 255 + 1 = 0 (with carry)
    const result_u8 = checkCarryAdd(u8, 255, 1);
    try std.testing.expect(result_u8.value == 0);
    try std.testing.expect(result_u8.carry == true);
    try std.testing.expect(result_u8.halfCarry == true); // 0xF + 0x1 = 0x10 (half-carry from bit 3 to 4)

    // Test u16: 65535 + 1 = 0 (with carry)
    const result_u16 = checkCarryAdd(u16, 65535, 1);
    try std.testing.expect(result_u16.value == 0);
    try std.testing.expect(result_u16.carry == true);
    try std.testing.expect(result_u16.halfCarry == true);
}

test "checkCarryAdd - addition with half-carry only" {
    const std = @import("std");

    // Test u8: 15 + 1 = 16, no carry, but half-carry (0x0F + 0x01 = 0x10)
    const result_u8 = checkCarryAdd(u8, 15, 1);
    try std.testing.expect(result_u8.value == 16);
    try std.testing.expect(result_u8.carry == false);
    try std.testing.expect(result_u8.halfCarry == true);

    // Test u16: 4095 + 1 = 4096, no carry, but half-carry (0x0FFF + 0x0001 = 0x1000)
    const result_u16 = checkCarryAdd(u16, 4095, 1);
    try std.testing.expect(result_u16.value == 4096);
    try std.testing.expect(result_u16.carry == false);
    try std.testing.expect(result_u16.halfCarry == true);
}

test "checkCarryAdd - edge cases with zero" {
    const std = @import("std");

    // Test adding zero
    const result_zero = checkCarryAdd(u8, 42, 0);
    try std.testing.expect(result_zero.value == 42);
    try std.testing.expect(result_zero.carry == false);
    try std.testing.expect(result_zero.halfCarry == false);

    // Test zero + zero
    const result_zero_zero = checkCarryAdd(u8, 0, 0);
    try std.testing.expect(result_zero_zero.value == 0);
    try std.testing.expect(result_zero_zero.carry == false);
    try std.testing.expect(result_zero_zero.halfCarry == false);
}

test "checkCarryAdd - maximum values" {
    const std = @import("std");

    // Test u8 max + max
    const result_max_u8 = checkCarryAdd(u8, 255, 255);
    try std.testing.expect(result_max_u8.value == 254); // 255 + 255 = 510 = 0x1FE, wraps to 0xFE = 254
    try std.testing.expect(result_max_u8.carry == true);
    try std.testing.expect(result_max_u8.halfCarry == true);

    // Test u16 max + max
    const result_max_u16 = checkCarryAdd(u16, 65535, 65535);
    try std.testing.expect(result_max_u16.value == 65534);
    try std.testing.expect(result_max_u16.carry == true);
    try std.testing.expect(result_max_u16.halfCarry == true);
}

test "checkCarryAdd - half-carry boundary conditions" {
    const std = @import("std");

    // Test u8: boundary around bit 3-4 (half-carry boundary for u8)
    const result1 = checkCarryAdd(u8, 0x0F, 0x01); // 15 + 1 = 16, half-carry
    try std.testing.expect(result1.value == 16);
    try std.testing.expect(result1.carry == false);
    try std.testing.expect(result1.halfCarry == true);

    const result2 = checkCarryAdd(u8, 0x0E, 0x01); // 14 + 1 = 15, no half-carry
    try std.testing.expect(result2.value == 15);
    try std.testing.expect(result2.carry == false);
    try std.testing.expect(result2.halfCarry == false);

    const result3 = checkCarryAdd(u8, 0x08, 0x08); // 8 + 8 = 16, half-carry
    try std.testing.expect(result3.value == 16);
    try std.testing.expect(result3.carry == false);
    try std.testing.expect(result3.halfCarry == true);

    // Test u16: boundary around bit 11-12 (half-carry boundary for u16)
    const result4 = checkCarryAdd(u16, 0x0FFF, 0x0001); // 4095 + 1 = 4096, half-carry
    try std.testing.expect(result4.value == 4096);
    try std.testing.expect(result4.carry == false);
    try std.testing.expect(result4.halfCarry == true);

    const result5 = checkCarryAdd(u16, 0x0800, 0x0800); // 2048 + 2048 = 4096, half-carry
    try std.testing.expect(result5.value == 4096);
    try std.testing.expect(result5.carry == false);
    try std.testing.expect(result5.halfCarry == true);
}

test "checkBorrowSub - basic subtraction without borrow" {
    const std = @import("std");

    // Test u8: 10 - 3 = 7, no borrow, no half-borrow
    const result_u8 = checkBorrowSub(u8, 10, 3);
    try std.testing.expect(result_u8.value == 7);
    try std.testing.expect(result_u8.borrow == false);
    try std.testing.expect(result_u8.halfBorrow == false);

    // Test u16: 200 - 50 = 150, no borrow, no half-borrow
    const result_u16 = checkBorrowSub(u16, 200, 50);
    try std.testing.expect(result_u16.value == 150);
    try std.testing.expect(result_u16.borrow == false);
    try std.testing.expect(result_u16.halfBorrow == false);
}

test "checkBorrowSub - subtraction with borrow" {
    const std = @import("std");

    // Test u8: 0 - 1 = 255 (with borrow)
    const result_u8 = checkBorrowSub(u8, 0, 1);
    try std.testing.expect(result_u8.value == 255);
    try std.testing.expect(result_u8.borrow == true);
    try std.testing.expect(result_u8.halfBorrow == true); // 0x0 - 0x1 requires borrow

    // Test u16: 0 - 1 = 65535 (with borrow)
    const result_u16 = checkBorrowSub(u16, 0, 1);
    try std.testing.expect(result_u16.value == 65535);
    try std.testing.expect(result_u16.borrow == true);
    try std.testing.expect(result_u16.halfBorrow == true);
}

test "checkBorrowSub - subtraction with half-borrow only" {
    const std = @import("std");

    // Test u8: 16 - 1 = 15, no borrow, but half-borrow (0x10 - 0x01 = 0x0F)
    const result_u8 = checkBorrowSub(u8, 16, 1);
    try std.testing.expect(result_u8.value == 15);
    try std.testing.expect(result_u8.borrow == false);
    try std.testing.expect(result_u8.halfBorrow == true);

    // Test u16: 4096 - 1 = 4095, no borrow, but half-borrow (0x1000 - 0x0001 = 0x0FFF)
    const result_u16 = checkBorrowSub(u16, 4096, 1);
    try std.testing.expect(result_u16.value == 4095);
    try std.testing.expect(result_u16.borrow == false);
    try std.testing.expect(result_u16.halfBorrow == true);
}

test "checkBorrowSub - edge cases with zero" {
    const std = @import("std");

    // Test subtracting zero
    const result_zero = checkBorrowSub(u8, 42, 0);
    try std.testing.expect(result_zero.value == 42);
    try std.testing.expect(result_zero.borrow == false);
    try std.testing.expect(result_zero.halfBorrow == false);

    // Test zero - zero
    const result_zero_zero = checkBorrowSub(u8, 0, 0);
    try std.testing.expect(result_zero_zero.value == 0);
    try std.testing.expect(result_zero_zero.borrow == false);
    try std.testing.expect(result_zero_zero.halfBorrow == false);

    // Test same values
    const result_same = checkBorrowSub(u8, 100, 100);
    try std.testing.expect(result_same.value == 0);
    try std.testing.expect(result_same.borrow == false);
    try std.testing.expect(result_same.halfBorrow == false);
}

test "checkBorrowSub - maximum values" {
    const std = @import("std");

    // Test u8: 255 - 255 = 0, no borrow
    const result_max_u8 = checkBorrowSub(u8, 255, 255);
    try std.testing.expect(result_max_u8.value == 0);
    try std.testing.expect(result_max_u8.borrow == false);
    try std.testing.expect(result_max_u8.halfBorrow == false);

    // Test u8: 1 - 255 = 2 (with borrow, wraps around)
    const result_wrap_u8 = checkBorrowSub(u8, 1, 255);
    try std.testing.expect(result_wrap_u8.value == 2); // 1 - 255 = -254, wraps to 2
    try std.testing.expect(result_wrap_u8.borrow == true);
    try std.testing.expect(result_wrap_u8.halfBorrow == true);

    // Test u16 similar case
    const result_wrap_u16 = checkBorrowSub(u16, 1, 65535);
    try std.testing.expect(result_wrap_u16.value == 2);
    try std.testing.expect(result_wrap_u16.borrow == true);
    try std.testing.expect(result_wrap_u16.halfBorrow == true);
}

test "checkBorrowSub - half-borrow boundary conditions" {
    const std = @import("std");

    // Test u8: boundary around bit 3-4 (half-borrow boundary for u8)
    const result1 = checkBorrowSub(u8, 0x10, 0x01); // 16 - 1 = 15, half-borrow
    try std.testing.expect(result1.value == 15);
    try std.testing.expect(result1.borrow == false);
    try std.testing.expect(result1.halfBorrow == true);

    const result2 = checkBorrowSub(u8, 0x11, 0x01); // 17 - 1 = 16, no half-borrow
    try std.testing.expect(result2.value == 16);
    try std.testing.expect(result2.borrow == false);
    try std.testing.expect(result2.halfBorrow == false);

    const result3 = checkBorrowSub(u8, 0x00, 0x01); // 0 - 1 = 255, both borrow and half-borrow
    try std.testing.expect(result3.value == 255);
    try std.testing.expect(result3.borrow == true);
    try std.testing.expect(result3.halfBorrow == true);

    const result4 = checkBorrowSub(u8, 0x08, 0x09); // 8 - 9 = 255, both borrow and half-borrow
    try std.testing.expect(result4.value == 255);
    try std.testing.expect(result4.borrow == true);
    try std.testing.expect(result4.halfBorrow == true);

    // Test u16: boundary around bit 11-12 (half-borrow boundary for u16)
    const result5 = checkBorrowSub(u16, 0x1000, 0x0001); // 4096 - 1 = 4095, half-borrow
    try std.testing.expect(result5.value == 4095);
    try std.testing.expect(result5.borrow == false);
    try std.testing.expect(result5.halfBorrow == true);

    const result6 = checkBorrowSub(u16, 0x1001, 0x0001); // 4097 - 1 = 4096, no half-borrow
    try std.testing.expect(result6.value == 4096);
    try std.testing.expect(result6.borrow == false);
    try std.testing.expect(result6.halfBorrow == false);
}
