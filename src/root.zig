//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

test {
    std.testing.refAllDecls(@import("./core/cpu/register.zig"));
}
