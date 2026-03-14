const kernel = @import("kernel.zig");
const raw = @import("../raw.zig");
const shift = @import("../root.zig");

/// Resolve an effect instance type from a pointer passed into a family handler.
pub fn InstanceTypeFromPtr(comptime InstancePtrType: type) type {
    return switch (@typeInfo(InstancePtrType)) {
        .pointer => |pointer| pointer.child,
        else => @compileError("expected a pointer to shift.effect family instance"),
    };
}

/// Extract the family state type from an instance pointer.
pub fn InstanceStateType(comptime InstancePtrType: type) type {
    return InstanceTypeFromPtr(InstancePtrType).State;
}

/// Extract the family error set from an instance pointer.
pub fn InstanceErrorSetType(comptime InstancePtrType: type) type {
    return InstanceTypeFromPtr(InstancePtrType).ErrorSet;
}

/// Build a prompt-backed family instance shell.
pub fn Instance(comptime StateType: type, comptime ErrorSetType: type) type {
    const PromptShell = raw.Prompt(.resume_then_transform, void, void, ErrorSetType);
    return struct {
        /// State value threaded through this effect family.
        pub const State = StateType;
        /// Error set propagated by this effect family.
        pub const ErrorSet = ErrorSetType;

        prompt: PromptShell,

        /// Create a fresh family instance with its own prompt identity.
        pub fn init() @This() {
            return .{ .prompt = PromptShell.init() };
        }
    };
}

/// Final family state plus body answer returned from a handled effect program.
pub fn HandleResult(comptime StateType: type, comptime ValueType: type) type {
    return struct {
        state: StateType,
        value: ValueType,
    };
}

/// Build the private exact context type for one family capability.
pub fn Context(comptime Cap: type, comptime StateTypeParam: type, comptime AnswerTypeParam: type, comptime ErrorSetTypeParam: type) type {
    return struct {
        /// Unique capability witness type for this private context.
        pub const capability = Cap;
        /// State type threaded through this private context.
        pub const StateType = StateTypeParam;
        /// Answer type produced by this private context.
        pub const AnswerType = AnswerTypeParam;
        /// Error set propagated by this private context.
        pub const ErrorSetType = ErrorSetTypeParam;

        _cap: *const Cap,
    };
}

/// Resolve the private exact context type from a pointer.
pub fn ContextTypeFromPtr(comptime ContextPtrType: type) type {
    return switch (@typeInfo(ContextPtrType)) {
        .pointer => |pointer| pointer.child,
        else => @compileError("expected a pointer to a shift.effect context"),
    };
}

/// Safely check whether a type declares a comptime field.
pub fn hasDeclSafe(comptime T: type, comptime name: []const u8) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, name),
        else => false,
    };
}

/// Assert that the supplied context pointer exactly matches the expected capability-parameterized private context type.
pub fn assertContextType(comptime Cap: type, comptime ContextPtrType: type) void {
    const ContextType = ContextTypeFromPtr(ContextPtrType);
    if (!hasDeclSafe(ContextType, "capability") or !hasDeclSafe(ContextType, "StateType") or !hasDeclSafe(ContextType, "AnswerType") or !hasDeclSafe(ContextType, "ErrorSetType")) {
        @compileError("expected a shift.effect context");
    }
    if (ContextType.capability != Cap) {
        @compileError("context capability does not match supplied capability");
    }
    const ExpectedContext = Context(Cap, ContextType.StateType, ContextType.AnswerType, ContextType.ErrorSetType);
    if (ContextType != ExpectedContext) {
        @compileError("expected exact shift.effect context type");
    }
}

/// Extract the family state type from a checked context pointer.
pub fn ContextStateType(comptime ContextPtrType: type) type {
    return ContextTypeFromPtr(ContextPtrType).StateType;
}

/// Extract the family answer type from a checked context pointer.
pub fn ContextAnswerType(comptime ContextPtrType: type) type {
    return ContextTypeFromPtr(ContextPtrType).AnswerType;
}

/// Extract the family error set from a checked context pointer.
pub fn ContextErrorSetType(comptime ContextPtrType: type) type {
    return ContextTypeFromPtr(ContextPtrType).ErrorSetType;
}

/// Run a family body under a fresh capability witness and return the final family state plus answer.
pub fn handle(
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    initial_state: InstanceStateType(@TypeOf(instance)),
    comptime Body: type,
) shift.ResetError(InstanceErrorSetType(@TypeOf(instance)))!HandleResult(
    InstanceStateType(@TypeOf(instance)),
    AnswerType,
) {
    const StateType = InstanceStateType(@TypeOf(instance));
    const ErrorSetType = InstanceErrorSetType(@TypeOf(instance));
    const family_impl = kernel.Family(StateType, AnswerType, ErrorSetType);
    const ResultType = HandleResult(StateType, AnswerType);

    const seal = struct {};
    const Cap = struct {
        _seal: seal,
        /// Body type that minted this capability witness.
        pub const BodyType = Body;
    };
    const ContextType = Context(Cap, StateType, AnswerType, ErrorSetType);

    var frame = family_impl.Frame{
        .prompt = .{ .token = instance.prompt.token },
        .state = initial_state,
    };
    var cap_token = Cap{ ._seal = .{} };
    var context = ContextType{ ._cap = &cap_token };

    const invoker = struct {
        threadlocal var active_context: ?*ContextType = null;

        fn invoke() shift.ResetError(ErrorSetType)!AnswerType {
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
