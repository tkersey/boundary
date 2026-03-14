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

/// Pointer-sized context that grants access to one handled state family.
pub fn Context(comptime State: type, comptime Answer: type, comptime ErrorSet: type) type {
    const family_impl = kernel.Family(State, Answer, ErrorSet);
    return struct {
        const get_handler = struct {
            /// Return the current state value to the resumed body.
            pub fn resumeValue() State {
                return family_impl.active_frame.?.state;
            }

            /// Preserve the resumed answer unchanged for `get`.
            pub fn afterResume(answer: Answer) Answer {
                return answer;
            }
        };

        const set_handler = struct {
            /// Resume the body after the state cell has been updated.
            pub fn resumeValue() void {
                // Intentionally empty: `set` resumes after mutating the state cell.
            }

            /// Preserve the resumed answer unchanged for `set`.
            pub fn afterResume(answer: Answer) Answer {
                return answer;
            }
        };

        /// Read the current state value from this handled state family.
        pub inline fn get(self: *@This()) shift.ResetError(ErrorSet)!State {
            _ = self;
            return try raw.shiftLocalIdentity(State, family_impl.Prompt, &family_impl.active_frame.?.prompt, family_impl.active_frame.?.state);
        }

        /// Replace the current state value for this handled state family.
        pub inline fn set(self: *@This(), value: State) shift.ResetError(ErrorSet)!void {
            _ = self;
            family_impl.active_frame.?.state = value;
            return try raw.shiftLocalIdentity(void, family_impl.Prompt, &family_impl.active_frame.?.prompt, {});
        }
    };
}

/// Run a state effect body and return the final state plus the body answer.
pub fn handle(
    comptime Answer: type,
    runtime: *shift.Runtime,
    instance: anytype,
    initial_state: InstanceStateType(@TypeOf(instance)),
    comptime body: *const fn (*Context(
        InstanceStateType(@TypeOf(instance)),
        Answer,
        InstanceErrorSetType(@TypeOf(instance)),
    )) shift.ResetError(InstanceErrorSetType(@TypeOf(instance)))!Answer,
) shift.ResetError(InstanceErrorSetType(@TypeOf(instance)))!HandleResult(
    InstanceStateType(@TypeOf(instance)),
    Answer,
) {
    const State = InstanceStateType(@TypeOf(instance));
    const ErrorSet = InstanceErrorSetType(@TypeOf(instance));
    const family_impl = kernel.Family(State, Answer, ErrorSet);
    const ResultType = HandleResult(State, Answer);
    const context_type = Context(State, Answer, ErrorSet);

    var frame = family_impl.Frame{
        .prompt = .{ .token = instance.prompt.token },
        .state = initial_state,
    };
    const context_singleton = context_type{};

    const invoker = struct {
        fn invoke() shift.ResetError(ErrorSet)!Answer {
            return try body(@constCast(&context_singleton));
        }
    };

    const previous_family_frame = family_impl.active_frame;
    family_impl.active_frame = &frame;
    defer {
        family_impl.active_frame = previous_family_frame;
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

test "state context stays pointer-sized" {
    const NoError = error{};
    const state_context = Context(i32, i32, NoError);
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(state_context));
}

test "state handle threads value and final state" {
    const NoError = error{};
    const StateInstance = Instance(i32, NoError);
    const state_context = Context(i32, i32, NoError);

    const demo = struct {
        fn body(ctx: *state_context) shift.ResetError(NoError)!i32 {
            const before = try ctx.get();
            try ctx.set(before + 1);
            return try ctx.get();
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    var instance = StateInstance.init();
    const result = try handle(i32, &runtime, &instance, 5, demo.body);
    try std.testing.expectEqual(@as(i32, 6), result.state);
    try std.testing.expectEqual(@as(i32, 6), result.value);
}
