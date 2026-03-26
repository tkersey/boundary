const shift = @import("shift");
const std = @import("std");

const bad_manager = struct {
    /// Public `release` helper.
    pub fn release(_: []const u8) void {
        // Intentionally empty for this compile-fail fixture.
    }
};

const Demo = shift.Program(.{
    .resource = shift.Decl.resource([]const u8, bad_manager),
}, struct {
    /// Execute this public body hook.
    pub fn body(eff: anytype) !usize {
        const item = try eff.resource.acquire();
        return item.len;
    }
});

/// Run this public entrypoint.
pub fn main() !void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    _ = try shift.run(&runtime, Demo, .{});
}
