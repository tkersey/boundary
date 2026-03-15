const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const OptionalInstance = shift.effect.optional.Instance(i32, NoError);
const policy = struct {
    /// Resume the optional request with a neutral value.
    pub fn resumeOrReturn() shift.ResumeOrReturn(i32, i32) {
        return shift.ResumeOrReturn(i32, i32).resumeWith(0);
    }

    /// Preserve the resumed answer for the optional mismatch fixture.
    pub fn afterResume(value: i32) i32 {
        return value;
    }
};

const demo = struct {
    var runtime_ptr: ?*shift.Runtime = null;
    var inner_ptr: ?*const OptionalInstance = null;

    /// Start a nested handle and try to treat its context as the outer one.
    pub fn outer(comptime OuterCap: type, _: anytype) shift.ResetError(NoError)!i32 {
        return try shift.effect.optional.handle(i32, runtime_ptr.?, inner_ptr.?, policy, struct {
            /// Attempt to request with the wrong capability type.
            pub fn body(comptime InnerCap: type, inner_ctx: anytype) shift.ResetError(NoError)!i32 {
                _ = InnerCap;
                return try shift.effect.optional.request(OuterCap, inner_ctx);
            }
        });
    }
};

/// Attempt to treat one optional capability as though it belonged to another.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    var outer_instance = OptionalInstance.init();
    var inner_instance = OptionalInstance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    _ = try shift.effect.optional.handle(i32, &runtime, &outer_instance, policy, struct {
        /// Invoke the outer body with the fresh outer capability.
        pub fn body(comptime OuterCap: type, ctx: anytype) shift.ResetError(NoError)!i32 {
            return try demo.outer(OuterCap, ctx);
        }
    });
}
