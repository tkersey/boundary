const family = @import("family.zig");
const kernel = @import("kernel.zig");
const raw = @import("../raw.zig");
const shift = @import("../root.zig");
const std = @import("std");

/// Prompt-backed effect instance for a state family.
pub const Instance = family.Instance;

/// Final state plus body answer returned from a handled state program.
pub const HandleResult = family.HandleResult;

/// Read the current state value for the supplied capability and handled context.
pub inline fn get(
    comptime Cap: type,
    ctx: anytype,
) shift.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!family.ContextStateType(@TypeOf(ctx)) {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    const ContextType = family.ContextTypeFromPtr(@TypeOf(ctx));
    const family_impl = kernel.Family(ContextType.StateType, ContextType.AnswerType, ContextType.ErrorSetType);
    _ = ctx._cap;
    return try raw.shiftLocalIdentity(
        ContextType.StateType,
        family_impl.Prompt,
        &family_impl.active_frame.?.prompt,
        family_impl.active_frame.?.state,
    );
}

/// Replace the current state value for the supplied capability and handled context.
pub inline fn set(
    comptime Cap: type,
    ctx: anytype,
    value: family.ContextStateType(@TypeOf(ctx)),
) shift.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!void {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    const ContextType = family.ContextTypeFromPtr(@TypeOf(ctx));
    const family_impl = kernel.Family(ContextType.StateType, ContextType.AnswerType, ContextType.ErrorSetType);
    _ = ctx._cap;
    family_impl.active_frame.?.state = value;
    return try raw.shiftLocalIdentity(void, family_impl.Prompt, &family_impl.active_frame.?.prompt, {});
}

/// Run a state effect body and return the final state plus the body answer.
pub fn handle(
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    initial_state: family.InstanceStateType(@TypeOf(instance)),
    comptime Body: type,
) shift.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!HandleResult(
    family.InstanceStateType(@TypeOf(instance)),
    AnswerType,
) {
    return try family.handle(AnswerType, runtime, instance, initial_state, Body);
}

test "state instance shell stays prompt-sized" {
    const NoError = error{};
    const StateInstance = Instance(i32, NoError);
    const PromptShell = raw.Prompt(.resume_then_transform, void, void, NoError);
    try std.testing.expectEqual(@sizeOf(PromptShell), @sizeOf(StateInstance));
}

test "state private context stays pointer-sized" {
    const NoError = error{};
    const StateContext = family.Context(struct {}, i32, i32, NoError);
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(StateContext));
}

test "state handle threads value and final state" {
    const NoError = error{};
    const StateInstance = Instance(i32, NoError);

    const demo = struct {
        /// Execute the strict-affinity state-effect test body.
        pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)!i32 {
            const before = try get(Cap, ctx);
            try set(Cap, ctx, before + 1);
            return try get(Cap, ctx);
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    var instance = StateInstance.init();
    const result = try handle(i32, &runtime, &instance, 5, demo);
    try std.testing.expectEqual(@as(i32, 6), result.state);
    try std.testing.expectEqual(@as(i32, 6), result.value);
}

test "nested same-shaped state handles get distinct capability types" {
    const NoError = error{};
    const StateInstance = Instance(i32, NoError);
    const demo = struct {
        var runtime_ptr: ?*shift.Runtime = null;
        var inner_ptr: ?*const StateInstance = null;

        /// Open an inner handle and prove its capability type differs from the outer one.
        pub fn outer(comptime OuterCap: type, _: anytype) shift.ResetError(NoError)!i32 {
            const result = try handle(i32, runtime_ptr.?, inner_ptr.?, 0, struct {
                /// Reject capability-type collapse inside the nested handle.
                pub fn body(comptime InnerCap: type, _: anytype) shift.ResetError(NoError)!i32 {
                    comptime if (OuterCap == InnerCap) {
                        @compileError("nested state handles must receive distinct capability types");
                    };
                    return 0;
                }
            });
            return result.value;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    var outer_instance = StateInstance.init();
    var inner_instance = StateInstance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    const result = try handle(i32, &runtime, &outer_instance, 0, struct {
        /// Enter the outer handle and hand its capability to the nested check.
        pub fn body(comptime OuterCap: type, ctx: anytype) shift.ResetError(NoError)!i32 {
            return try demo.outer(OuterCap, ctx);
        }
    });
    try std.testing.expectEqual(@as(i32, 0), result.value);
}
