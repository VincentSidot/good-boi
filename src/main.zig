const std = @import("std");

const Window = @import("gui/window.zig").Window;

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
    var window = Window.init(800, 600, "Good Boi Emulator");

    window.run();
}
