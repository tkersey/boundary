const shift = @import("shift");
const std = @import("std");

const bad_manager = struct {
    pub fn acquire() []const u8 {
        return "resource";
    }

    pub fn release(_: []const u8) i32 {
        return 1;
    }
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
