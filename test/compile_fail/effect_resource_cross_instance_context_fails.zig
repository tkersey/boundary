const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const ResourceInstance = shift.effect.resource.Instance(i32, NoError);
const manager = struct {
    /// Acquire one dummy resource for the cross-instance resource fixture.
    pub fn acquire() i32 {
        return 0;
    }

    /// Release the dummy resource for the cross-instance resource fixture.
    pub fn release(_: i32) void {
        // Intentionally empty for this fixture.
    }
};

const demo = struct {
    var runtime_ptr: ?*shift.Runtime = null;
    var inner_ptr: ?*const ResourceInstance = null;

    /// Start a nested handle and try to treat its context as the outer one.
    pub fn outer(comptime OuterCap: type, _: anytype) shift.ResetError(NoError)!i32 {
        return try shift.effect.resource.handle(i32, runtime_ptr.?, inner_ptr.?, manager, struct {
            /// Attempt to acquire with the wrong capability type.
            pub fn body(comptime InnerCap: type, inner_ctx: anytype) shift.ResetError(NoError)!i32 {
                _ = InnerCap;
                _ = try shift.effect.resource.acquire(OuterCap, inner_ctx);
                return 0;
            }
        });
    }
};

/// Attempt to treat one resource capability as though it belonged to another.
pub fn main() anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var outer_instance = ResourceInstance.init();
    var inner_instance = ResourceInstance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    _ = try shift.effect.resource.handle(i32, &runtime, &outer_instance, manager, struct {
        /// Invoke the outer body with the fresh outer capability.
        pub fn body(comptime OuterCap: type, ctx: anytype) shift.ResetError(NoError)!i32 {
            return try demo.outer(OuterCap, ctx);
        }
    });
}
