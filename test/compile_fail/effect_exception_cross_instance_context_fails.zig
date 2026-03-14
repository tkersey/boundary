const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const ExceptionInstance = shift.effect.exception.Instance(i32, NoError);
const catcher = struct {
    /// Preserve the thrown payload for the cross-instance exception fixture.
    pub fn directReturn(payload: i32) i32 {
        return payload;
    }
};

const demo = struct {
    var runtime_ptr: ?*shift.Runtime = null;
    var inner_ptr: ?*const ExceptionInstance = null;

    /// Start a nested handle and try to treat its context as the outer one.
    pub fn outer(comptime OuterCap: type, _: anytype) shift.ResetError(NoError)!i32 {
        return try shift.effect.exception.handle(i32, runtime_ptr.?, inner_ptr.?, catcher, struct {
            /// Attempt to throw with the wrong capability type.
            pub fn body(comptime InnerCap: type, inner_ctx: anytype) shift.ResetError(NoError)!i32 {
                _ = InnerCap;
                try shift.effect.exception.throw(OuterCap, inner_ctx, 1);
            }
        });
    }
};

/// Attempt to treat one exception capability as though it belonged to another.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var outer_instance = ExceptionInstance.init();
    var inner_instance = ExceptionInstance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    _ = try shift.effect.exception.handle(i32, &runtime, &outer_instance, catcher, struct {
        /// Invoke the outer body with the fresh outer capability.
        pub fn body(comptime OuterCap: type, ctx: anytype) shift.ResetError(NoError)!i32 {
            return try demo.outer(OuterCap, ctx);
        }
    });
}
