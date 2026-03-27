const shift = @import("shift");
const std = @import("std");

const bad_policy = struct {
    /// Finish this public resumed path.
    pub fn afterResume(answer: i32) i32 {
        return answer;
    }
};

const Demo = shift.Program(.{
    .optional = shift.Decl.optional(i32, bad_policy),
}, struct {
    /// Execute this public body hook.
    pub fn body(eff: anytype) anyerror!i32 {
        return try eff.optional.request(struct {
            /// Apply this public continuation hook.
            pub fn apply(value: i32, _: anytype) anyerror!i32 {
                return value;
            }
        });
    }
});

/// Run this public entrypoint.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    _ = try shift.run(&runtime, Demo, .{});
}
