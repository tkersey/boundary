const shift = @import("shift");
const std = @import("std");

const bad_catch = struct {};

const Demo = shift.Program(.{
    .exception = shift.Decl.exception([]const u8, bad_catch),
}, struct {
    /// Execute this public body hook.
    pub fn body(eff: anytype) ![]const u8 {
        try eff.exception.throw("boom");
    }
});

/// Run this public entrypoint.
pub fn main() !void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    _ = try shift.run(&runtime, Demo, .{});
}
