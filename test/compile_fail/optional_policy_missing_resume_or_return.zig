const shift = @import("shift");
const std = @import("std");

const bad_policy = struct {
    pub fn afterResume(answer: i32) i32 {
        return answer;
    }
};

const Demo = shift.Program(.{
    .optional = shift.Decl.optional(i32, bad_policy),
}, struct {
    pub fn body(eff: anytype) !i32 {
        return try eff.optional.request(struct {
            pub fn apply(value: i32, _: anytype) !i32 {
                return value;
            }
        });
    }
});

pub fn main() !void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    _ = try shift.run(&runtime, Demo, .{});
}
