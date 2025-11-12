/// A utility function to perform addition with carry check.
pub inline fn checkCarryAdd(comptime T: type, a: T, b: T) struct {
    /// The result of the addition.
    value: T,
    /// Whether a carry occurred during the addition.
    carry: bool,
    /// Whether a half-carry occurred during the addition. (A carry from bit bits/2 to bits/2-1)
    halfCarry: bool,
} {
    comptime {
        if (@typeInfo(T) == .comptime_int) {
            @compileError("T cannot be a comptime_int because we are perfoming operation related to T size and comptime_int has a size of 0");
        } else if (@typeInfo(T) != .int) {
            @compileError("T must be an integer type");
        }
    }

    const value: T, const carry: u1 = @addWithOverflow(a, b);

    const halfBits = @bitSizeOf(T) / 2; // Compute half the number of bits in T;
    const halfMask = (1 << halfBits) - 1;

    const halfCarry = ((a & halfMask) + (b & halfMask)) > halfMask;

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
    comptime {
        if (@typeInfo(T) != .int) {
            @compileError("T must be an integer type");
        }
    }

    const value: T, const borrow: u1 = @subWithOverflow(a, b);

    const halfBits = @bitSizeOf(T) / 2; // Compute half the number of bits in T;
    const halfMask = (1 << halfBits) - 1;

    const halfBorrow = (a & halfMask) < (b & halfMask);

    return .{
        .value = value,
        .borrow = borrow != 0,
        .halfBorrow = halfBorrow,
    };
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

    // Test u16: 255 + 1 = 256, no carry, but half-carry (0x00FF + 0x0001 = 0x0100)
    const result_u16 = checkCarryAdd(u16, 255, 1);
    try std.testing.expect(result_u16.value == 256);
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
}

test "checkCarryAdd - different integer types" {
    const std = @import("std");

    // Test u32
    const result_u32 = checkCarryAdd(u32, 0x0000_FFFF, 1);
    try std.testing.expect(result_u32.value == 0x0001_0000);
    try std.testing.expect(result_u32.carry == false);
    try std.testing.expect(result_u32.halfCarry == true); // Carry from bit 15 to 16 (half of 32 bits)

    // Test u64
    const result_u64 = checkCarryAdd(u64, 0x0000_0000_FFFF_FFFF, 1);
    try std.testing.expect(result_u64.value == 0x0000_0001_0000_0000);
    try std.testing.expect(result_u64.carry == false);
    try std.testing.expect(result_u64.halfCarry == true); // Carry from bit 31 to 32 (half of 64 bits)
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

    // Test u16: 256 - 1 = 255, no borrow, but half-borrow (0x0100 - 0x0001 = 0x00FF)
    const result_u16 = checkBorrowSub(u16, 256, 1);
    try std.testing.expect(result_u16.value == 255);
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
}

test "checkBorrowSub - different integer types" {
    const std = @import("std");

    // Test u32: half-borrow from bit 15 to 16
    const result_u32 = checkBorrowSub(u32, 0x0001_0000, 1);
    try std.testing.expect(result_u32.value == 0x0000_FFFF);
    try std.testing.expect(result_u32.borrow == false);
    try std.testing.expect(result_u32.halfBorrow == true); // Borrow from bit 16 to 15 (half of 32 bits)

    // Test u64: half-borrow from bit 31 to 32
    const result_u64 = checkBorrowSub(u64, 0x0000_0001_0000_0000, 1);
    try std.testing.expect(result_u64.value == 0x0000_0000_FFFF_FFFF);
    try std.testing.expect(result_u64.borrow == false);
    try std.testing.expect(result_u64.halfBorrow == true); // Borrow from bit 32 to 31 (half of 64 bits)
}
