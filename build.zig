const std = @import("std");

const raylib_dir = "raylib-5.5";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("good_boi", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "good_boi",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true, // Who needs libc anyway?
            .imports = &.{
                .{ .name = "good_boi", .module = mod },
            },
        }),
    });

    // raylib is vendored as a prebuilt static library.
    exe.root_module.addIncludePath(b.path(raylib_dir ++ "/include"));
    exe.root_module.addObjectFile(b.path(raylib_dir ++ "/lib/libraylib.a"));

    if (target.result.os.tag == .macos) {
        // Frameworks raylib depends on for windowing and input.
        exe.root_module.linkFramework("IOKit", .{});
        exe.root_module.linkFramework("OpenGL", .{});
        exe.root_module.linkFramework("Cocoa", .{});
    }

    b.installArtifact(exe);

    // Assembler CLI: `zig build asm -- progs/fib.s bin/fib.gb`.
    // Shares its core with the comptime assembler the tests use.
    const asm_mod = b.addModule("gbasm", .{
        .root_source_file = b.path("src/tools/asm.zig"),
        .target = target,
    });

    const asm_exe = b.addExecutable(.{
        .name = "gbasm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("utils/asm_cli.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "gbasm", .module = asm_mod },
            },
        }),
    });
    b.installArtifact(asm_exe);

    const asm_run = b.addRunArtifact(asm_exe);
    if (b.args) |args| {
        asm_run.addArgs(args);
    } else {
        asm_run.addArgs(&.{ "progs/fib.s", "bin/fib.gb" });
    }
    const asm_step = b.step("asm", "Assemble a .s file (defaults to progs/fib.s)");
    asm_step.dependOn(&asm_run.step);

    // `zig build run [-- args...]`, running from the install prefix.
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // A test executable covers a single module, so the library and the
    // executable each need their own.
    const run_mod_tests = b.addRunArtifact(b.addTest(.{
        .root_module = mod,
    }));
    const run_exe_tests = b.addRunArtifact(b.addTest(.{
        .root_module = exe.root_module,
    }));

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
