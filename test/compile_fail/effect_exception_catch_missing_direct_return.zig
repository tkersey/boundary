const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const ExceptionInstance = shift.effect.exception.Instance(i32, NoError);
const bad_catch = struct {};

/// Attempt to handle an exception effect with a malformed catch policy.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var instance = ExceptionInstance.init();
    _ = try shift.effect.exception.handle(i32, &runtime, &instance, bad_catch, struct {
        /// Force the handler to instantiate the malformed catch policy.
        pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)!i32 {
            try shift.effect.exception.throw(Cap, ctx, 1);
        }
    });
}
