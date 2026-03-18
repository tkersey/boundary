const shift = @import("shift");
const std = @import("std");

const bad_catch = struct {
    pub fn directReturn(_: []const u8) i32 {
        return 1;
    }
};

const Demo = shift.Program(.{
    .exception = shift.Decl.exception([]const u8, bad_catch),
}, struct {
    pub fn body(eff: anytype) ![]const u8 {
        try eff.exception.throw("boom");
    }
});

pub fn main() !void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    _ = try shift.run(&runtime, Demo, .{});
}
