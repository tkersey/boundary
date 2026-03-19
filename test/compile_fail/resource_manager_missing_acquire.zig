const shift = @import("shift");
const std = @import("std");

const bad_manager = struct {
    pub fn release(_: []const u8) void {}
};

const Demo = shift.Program(.{
    .resource = shift.Decl.resource([]const u8, bad_manager),
}, struct {
    pub fn body(eff: anytype) !usize {
        const item = try eff.resource.acquire();
        return item.len;
    }
});

pub fn main() !void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    _ = try shift.run(&runtime, Demo, .{});
}
