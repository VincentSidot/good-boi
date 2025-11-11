const std = @import("std");

fn logFn(comptime message_level: std.log.Level, comptime scope: anytype, comptime format: []const u8, args: anytype) void {
    _ = scope; // unused
    const level_txt = comptime message_level.asText();

    var buffer: [255]u8 = undefined;

    const stderr = std.debug.lockStderrWriter(&buffer);
    defer std.debug.unlockStderrWriter();

    nosuspend stderr.print(level_txt ++ "| " ++ format ++ "\n", args) catch return;
}

pub const std_options: std.Options = .{
    .log_level = .info,
    .logFn = logFn,
};

pub fn main() !void {
    std.log.info("Info log", .{});
    std.log.warn("Warning log", .{});
    std.log.err("Error log", .{});
    std.log.debug("Debug log", .{});
}
