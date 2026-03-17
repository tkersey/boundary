/// Stable ordinary-Zig case id.
pub const ordinary_case_id = "ordinary.cross_module_typed_error_try";

const support_mod = @import("cross_module_typed_error_support.zig");

/// Run the cross-module typed-error case with ordinary Zig control flow.
pub fn run(writer: anytype) anyerror!void {
    try writer.writeAll("branch=ok\n");
    const value = try support_mod.succeed();
    try writer.print("value={d}\n", .{value});

    try writer.writeAll("branch=err\n");
    _ = support_mod.fail() catch |err| switch (err) {
        error.Boom => {
            try writer.writeAll("error=boom\n");
            try writer.writeAll("final=error=boom\n");
            return;
        },
    };
    unreachable;
}
