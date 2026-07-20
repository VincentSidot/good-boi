//! CLI wrapper around the assembler in src/tools/asm.zig.
//!
//!     gbasm <input.s> <output.gb>
//!
//! The core is shared with the comptime path the tests use, so a program that
//! assembles here assembles identically when embedded inline in a test.

const std = @import("std");
const asm_ = @import("gbasm");

const MAX_SOURCE = 1 << 20;
const MAX_OUTPUT = 1 << 16;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, gpa);
    defer args.deinit();

    _ = args.skip(); // argv[0]
    const in_path = args.next() orelse return usage();
    const out_path = args.next() orelse return usage();

    const src = std.Io.Dir.cwd().readFileAlloc(io, in_path, gpa, .limited(MAX_SOURCE)) catch |e| {
        report("cannot read {s}: {s}", .{ in_path, @errorName(e) });
        return error.ReadFailed;
    };
    defer gpa.free(src);

    const out = try gpa.alloc(u8, MAX_OUTPUT);
    defer gpa.free(out);

    var diag = asm_.Diag{};
    const res = asm_.assembleBuf(src, out, &diag) catch |e| {
        report("{s}:{d}: {s} ({s})", .{ in_path, diag.line, diag.msg(), @errorName(e) });
        return error.AssembleFailed;
    };

    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = out_path,
        .data = out[0..res.len],
    });

    report("{s} -> {s}  (origin ${X:0>4}, {d} bytes)", .{ in_path, out_path, res.origin, res.len });
}

fn usage() error{BadUsage} {
    report("usage: gbasm <input.s> <output.gb>", .{});
    return error.BadUsage;
}

fn report(comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const stderr = std.debug.lockStderr(&buf).terminal();
    defer std.debug.unlockStderr();
    stderr.writer.print(fmt ++ "\n", args) catch return;
}
