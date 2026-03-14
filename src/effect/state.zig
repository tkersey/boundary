const kernel = @import("kernel.zig");
const raw = @import("../raw.zig");
const shift = @import("../root.zig");
const std = @import("std");

fn InstanceTypeFromPtr(comptime InstancePtrType: type) type {
    return switch (@typeInfo(InstancePtrType)) {
        .pointer => |pointer| pointer.child,
        else => @compileError("expected a pointer to shift.effect.state.Instance(...)"),
    };
}

fn InstanceStateType(comptime InstancePtrType: type) type {
    return InstanceTypeFromPtr(InstancePtrType).State;
}

fn InstanceErrorSetType(comptime InstancePtrType: type) type {
    return InstanceTypeFromPtr(InstancePtrType).ErrorSet;
}

fn Context(comptime Cap: type, comptime State: type, comptime Answer: type, comptime ErrorSet: type) type {
    return struct {
        /// Unique capability witness type for this private context.
        pub const capability = Cap;
        /// State type threaded through this private context.
        pub const StateType = State;
        /// Answer type produced by this private context.
        pub const AnswerType = Answer;
        /// Error set propagated by this private context.
        pub const ErrorSetType = ErrorSet;

        _cap: *const Cap,
    };
}

fn ContextTypeFromPtr(comptime ContextPtrType: type) type {
    return switch (@typeInfo(ContextPtrType)) {
        .pointer => |pointer| pointer.child,
        else => @compileError("expected a pointer to a shift.effect.state context"),
    };
}

fn hasDeclSafe(comptime T: type, comptime name: []const u8) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, name),
        else => false,
    };
}

fn assertContextType(comptime Cap: type, comptime ContextPtrType: type) void {
    const ContextType = ContextTypeFromPtr(ContextPtrType);
    if (!hasDeclSafe(ContextType, "capability") or !hasDeclSafe(ContextType, "StateType") or !hasDeclSafe(ContextType, "AnswerType") or !hasDeclSafe(ContextType, "ErrorSetType")) {
        @compileError("expected a shift.effect.state context");
    }
    if (ContextType.capability != Cap) {
        @compileError("context capability does not match supplied capability");
    }
    const ExpectedContext = Context(Cap, ContextType.StateType, ContextType.AnswerType, ContextType.ErrorSetType);
    if (ContextType != ExpectedContext) {
        @compileError("expected exact shift.effect.state context type");
    }
}

fn ContextStateType(comptime ContextPtrType: type) type {
    return ContextTypeFromPtr(ContextPtrType).StateType;
}

fn ContextErrorSetType(comptime ContextPtrType: type) type {
    return ContextTypeFromPtr(ContextPtrType).ErrorSetType;
}

/// Prompt-backed effect instance for a state family.
pub fn Instance(comptime StateType: type, comptime ErrorSetType: type) type {
    const PromptShell = raw.Prompt(.resume_then_transform, void, void, ErrorSetType);
    return struct {
        /// State value threaded through this effect family.
        pub const State = StateType;
        /// Error set propagated by this effect family.
        pub const ErrorSet = ErrorSetType;

        prompt: PromptShell,

        /// Create a fresh state-effect instance with its own prompt identity.
        pub fn init() @This() {
            return .{ .prompt = PromptShell.init() };
        }
    };
}

/// Final state plus body answer returned from a handled state program.
pub fn HandleResult(comptime State: type, comptime Value: type) type {
    return struct {
        state: State,
        value: Value,
    };
}

/// Read the current state value for the supplied capability and handled context.
pub inline fn get(
    comptime Cap: type,
    ctx: anytype,
) shift.ResetError(ContextErrorSetType(@TypeOf(ctx)))!ContextStateType(@TypeOf(ctx)) {
    comptime assertContextType(Cap, @TypeOf(ctx));
    const ContextType = ContextTypeFromPtr(@TypeOf(ctx));
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
    value: ContextStateType(@TypeOf(ctx)),
) shift.ResetError(ContextErrorSetType(@TypeOf(ctx)))!void {
    comptime assertContextType(Cap, @TypeOf(ctx));
    const ContextType = ContextTypeFromPtr(@TypeOf(ctx));
    const family_impl = kernel.Family(ContextType.StateType, ContextType.AnswerType, ContextType.ErrorSetType);
    _ = ctx._cap;
    family_impl.active_frame.?.state = value;
    return try raw.shiftLocalIdentity(void, family_impl.Prompt, &family_impl.active_frame.?.prompt, {});
}

/// Run a state effect body and return the final state plus the body answer.
pub fn handle(
    comptime Answer: type,
    runtime: *shift.Runtime,
    instance: anytype,
    initial_state: InstanceStateType(@TypeOf(instance)),
    comptime Body: type,
) shift.ResetError(InstanceErrorSetType(@TypeOf(instance)))!HandleResult(
    InstanceStateType(@TypeOf(instance)),
    Answer,
) {
    const State = InstanceStateType(@TypeOf(instance));
    const ErrorSet = InstanceErrorSetType(@TypeOf(instance));
    const family_impl = kernel.Family(State, Answer, ErrorSet);
    const ResultType = HandleResult(State, Answer);

    const seal = struct {};
    const Cap = struct {
        _seal: seal,
        /// Body type that minted this capability witness.
        pub const BodyType = Body;
    };
    const ContextType = Context(Cap, State, Answer, ErrorSet);

    var frame = family_impl.Frame{
        .prompt = .{ .token = instance.prompt.token },
        .state = initial_state,
    };
    var cap_token = Cap{ ._seal = .{} };
    var context = ContextType{ ._cap = &cap_token };

    const invoker = struct {
        threadlocal var active_context: ?*ContextType = null;

        fn invoke() shift.ResetError(ErrorSet)!Answer {
            return try Body.body(Cap, active_context.?);
        }
    };

    const previous_family_frame = family_impl.active_frame;
    const previous_context = invoker.active_context;
    family_impl.active_frame = &frame;
    invoker.active_context = &context;
    defer {
        family_impl.active_frame = previous_family_frame;
        invoker.active_context = previous_context;
    }

    const value = try raw.reset(family_impl.Prompt, runtime, &frame.prompt, invoker.invoke);
    return ResultType{ .state = frame.state, .value = value };
}

test "state instance shell stays prompt-sized" {
    const NoError = error{};
    const StateInstance = Instance(i32, NoError);
    const PromptShell = raw.Prompt(.resume_then_transform, void, void, NoError);
    try std.testing.expectEqual(@sizeOf(PromptShell), @sizeOf(StateInstance));
}

test "state private context stays pointer-sized" {
    const NoError = error{};
    const StateContext = Context(struct {}, i32, i32, NoError);
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
