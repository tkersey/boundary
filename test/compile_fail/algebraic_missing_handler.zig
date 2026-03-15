const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const ping = shift.algebraic.TransformOp("ping", void, i32);
const demo = shift.algebraic.Program(i32, NoError, .{ping});

const configured = demo.handlers(.{});

const body = struct {
    /// Provide the compile-fail missing-handler witness body.
    pub fn body(_: *@TypeOf(configured).Context) shift.ResetError(NoError)!i32 {
        return 0;
    }
};

/// Trigger the compile-fail missing-handler witness.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    _ = try configured.run(&runtime, body);
}
