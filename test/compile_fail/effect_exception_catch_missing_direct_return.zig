const shift = @import("shift");
const shift_internal = @import("shift_internal");
const std = @import("std");

const NoError = error{};
const ExceptionInstance = shift.effect.exception.Instance(i32, NoError);
const bad_catch = struct {};

/// Attempt to handle an exception effect with a malformed catch policy.
pub fn main() anyerror!void {
    var runtime = shift_internal.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    var instance = ExceptionInstance.init();
    _ = try shift.effect.exception.handle(i32, &runtime, &instance, bad_catch, struct {
        /// Force the handler to instantiate the malformed catch policy.
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(shift.effect.exception.throwProgram(Cap, ctx, 1)) {
            return shift.effect.exception.throwProgram(Cap, ctx, 1);
        }
    });
}
