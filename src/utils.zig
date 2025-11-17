const std = @import("std");

pub const CRASH_ON_INVALID = true;

pub const log = std.log;

pub fn unimplemented(comptime msg: []const u8) noreturn {
    @panic("Unimplemtented: " ++ msg);
}
