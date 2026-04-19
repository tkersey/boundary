const algebraic = @import("algebraic.zig");
const effect_schema = @import("../effect_schema.zig");
const family = @import("family.zig");
const lexical_with = @import("../with_api.zig");
const lowered_machine = @import("lowered_machine");
const shift = lowered_machine;
const std = @import("std");

/// Prompt-backed effect instance for a state family.
pub const Instance = family.Instance;

/// Final state plus body answer returned from a handled state program.
pub const HandleResult = family.HandleResult;

/// Lexical state handle used by `shift.withAt(@src(), ...)`.
pub fn LexicalHandle(comptime Cap: type, comptime ContextPtrType: type) type {
    return struct {
        ctx: ?ContextPtrType,

        /// Read the current state value through the lexical handle.
        pub fn get(self: @This()) lowered_machine.ResetError(family.ContextErrorSetType(ContextPtrType))!family.ContextStateType(ContextPtrType) {
            return try algebraic.stateGet(Cap, self.ctx.?);
        }

        /// Replace the current state value through the lexical handle.
        pub fn set(self: @This(), value: family.ContextStateType(ContextPtrType)) lowered_machine.ResetError(family.ContextErrorSetType(ContextPtrType))!void {
            try algebraic.stateSet(Cap, self.ctx.?, value);
        }
    };
}

/// Descriptor value used by `shift.withAt(@src(), ...)` for the built-in state family.
pub fn LexicalDescriptor(comptime StateType: type, comptime ErrorSetType: type) type {
    return struct {
        /// Shared error set carried by the lexical state descriptor.
        pub const ErrorSet = ErrorSetType;
        /// State type threaded through the lexical state context.
        pub const State = StateType;
        /// Final state output produced by the lexical state descriptor.
        pub const Output = StateType;

        initial_state: StateType,

        /// Resolve the lexical state handle type for one exact context.
        pub fn HandleType(comptime Cap: type, comptime ContextPtrType: type) type {
            return LexicalHandle(Cap, ContextPtrType);
        }

        /// Bind one lexical state handle to the active exact context.
        pub fn bindLexical(self: @This(), comptime Cap: type, ctx: anytype) HandleType(Cap, @TypeOf(ctx)) {
            _ = self;
            return .{ .ctx = ctx };
        }

        /// Return the shared binding schema for this lexical descriptor under one requirement label.
        pub fn BindingSchema(comptime requirement_label: [:0]const u8) type {
            return effect_schema.Binding(requirement_label, Schema(StateType, ErrorSetType), struct {});
        }

        /// Run one lexical state descriptor through the existing state family.
        pub fn run(self: @This(), comptime AnswerType: type, comptime RunErrorSetType: type, run_ctx: anytype, comptime Body: type) lowered_machine.ResetError(RunErrorSetType)!lexical_with.DescriptorResult(Output, AnswerType) {
            var instance = family.Instance(StateType, ErrorSetType).init();
            const result = try algebraic.handleStateWithErrorSetLexicalAt(AnswerType, RunErrorSetType, @TypeOf(run_ctx).caller_source, .{
                .runtime = run_ctx.runtime,
                .instance = &instance,
                .initial_state = self.initial_state,
                .lexical_state = @constCast(run_ctx.lexical_state),
            }, Body);
            return .{
                .output = result.state,
                .value = result.value,
            };
        }
    };
}

/// Create one lexical state descriptor for `shift.withAt(@src(), ...)`.
pub fn use(initial_state: anytype) LexicalDescriptor(@TypeOf(initial_state), error{}) {
    return .{ .initial_state = initial_state };
}

/// Shared effect schema for the built-in state family.
pub fn Schema(comptime StateType: type, comptime ErrorSetType: type) type {
    return effect_schema.state_cell(StateType, ErrorSetType);
}

/// Read the current state value for the supplied capability and handled context.
pub inline fn get(
    comptime Cap: type,
    ctx: anytype,
) lowered_machine.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!family.ContextStateType(@TypeOf(ctx)) {
    return try algebraic.stateGet(Cap, ctx);
}

/// Replace the current state value for the supplied capability and handled context.
pub inline fn set(
    comptime Cap: type,
    ctx: anytype,
    value: family.ContextStateType(@TypeOf(ctx)),
) lowered_machine.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!void {
    return try algebraic.stateSet(Cap, ctx, value);
}

/// Build one explicit state body program with no prompt operation.
pub inline fn computeProgram(
    comptime Cap: type,
    ctx: anytype,
    comptime Thunk: type,
) @TypeOf(family.computeProgram(Cap, ctx, Thunk)) {
    return family.computeProgram(Cap, ctx, Thunk);
}

/// Run a state effect body and return the final state plus the body answer.
pub fn handle(
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    initial_state: family.InstanceStateType(@TypeOf(instance)),
    comptime Body: type,
) lowered_machine.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!HandleResult(
    family.InstanceStateType(@TypeOf(instance)),
    AnswerType,
) {
    return try algebraic.handleState(null, AnswerType, runtime, instance, initial_state, Body);
}

/// Run a state effect body with explicit caller provenance and return the final state plus the body answer.
pub fn handleAt(
    comptime caller_source: std.builtin.SourceLocation,
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    initial_state: family.InstanceStateType(@TypeOf(instance)),
    comptime Body: type,
) lowered_machine.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!HandleResult(
    family.InstanceStateType(@TypeOf(instance)),
    AnswerType,
) {
    return try algebraic.handleState(caller_source, AnswerType, runtime, instance, initial_state, Body);
}

/// Public `handleWithErrorSet` helper.
// zlinter-disable max_positional_args - public caller provenance and state inputs stay explicit at this compatibility wrapper.
pub fn handleWithErrorSet(
    comptime AnswerType: type,
    comptime RunErrorSetType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    initial_state: family.InstanceStateType(@TypeOf(instance)),
    comptime Body: type,
) lowered_machine.ResetError(RunErrorSetType)!HandleResult(
    family.InstanceStateType(@TypeOf(instance)),
    AnswerType,
) {
    return try algebraic.handleStateWithErrorSet(null, AnswerType, RunErrorSetType, runtime, instance, initial_state, Body);
}

/// Public `handleWithErrorSetAt` helper.
// zlinter-disable max_positional_args - public caller provenance and state inputs stay explicit at this compatibility wrapper.
pub fn handleWithErrorSetAt(
    comptime caller_source: std.builtin.SourceLocation,
    comptime AnswerType: type,
    comptime RunErrorSetType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    initial_state: family.InstanceStateType(@TypeOf(instance)),
    comptime Body: type,
) lowered_machine.ResetError(RunErrorSetType)!HandleResult(
    family.InstanceStateType(@TypeOf(instance)),
    AnswerType,
) {
    return try algebraic.handleStateWithErrorSet(caller_source, AnswerType, RunErrorSetType, runtime, instance, initial_state, Body);
}

test "state instance shell stays prompt-sized" {
    const StateInstance = Instance(i32, error{});
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(StateInstance));
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
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(family.computeProgram(Cap, ctx, struct {
            /// Read, update, and read the state cell once.
            pub fn run(comptime ProgramCap: type, program_ctx: anytype) lowered_machine.ResetError(NoError)!i32 {
                const before = try get(ProgramCap, program_ctx);
                try set(ProgramCap, program_ctx, before + 1);
                return try get(ProgramCap, program_ctx);
            }
        })) {
            return family.computeProgram(Cap, ctx, struct {
                /// Read, update, and read the state cell once.
                pub fn run(comptime ProgramCap: type, program_ctx: anytype) lowered_machine.ResetError(NoError)!i32 {
                    const before = try get(ProgramCap, program_ctx);
                    try set(ProgramCap, program_ctx, before + 1);
                    return try get(ProgramCap, program_ctx);
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = StateInstance.init();
    const result = try handleAt(@src(), i32, &runtime, &instance, 5, demo);
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
        pub fn outer(comptime OuterCap: type, _: anytype) lowered_machine.ResetError(NoError)!i32 {
            const result = try handleAt(@src(), i32, runtime_ptr.?, inner_ptr.?, 0, struct {
                /// Reject capability-type collapse inside the nested handle.
                pub fn program(comptime InnerCap: type, inner_ctx: anytype) @TypeOf(family.computeProgram(InnerCap, inner_ctx, struct {
                    /// Return a neutral value from the nested state body.
                    pub fn run(_: type, _: anytype) i32 {
                        return 0;
                    }
                })) {
                    comptime if (OuterCap == InnerCap) {
                        @compileError("nested state handles must receive distinct capability types");
                    };
                    return family.computeProgram(InnerCap, inner_ctx, struct {
                        /// Return a neutral value from the nested state body.
                        pub fn run(_: type, _: anytype) i32 {
                            return 0;
                        }
                    });
                }
            });
            return result.value;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var outer_instance = StateInstance.init();
    var inner_instance = StateInstance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    const result = try handleAt(@src(), i32, &runtime, &outer_instance, 0, struct {
        /// Enter the outer handle and hand its capability to the nested check.
        pub fn program(comptime OuterCap: type, ctx: anytype) @TypeOf(family.computeProgram(OuterCap, ctx, struct {
            /// Re-enter the nested state witness through the outer capability.
            pub fn run(_: type, _: anytype) lowered_machine.ResetError(NoError)!i32 {
                return try demo.outer(OuterCap, {});
            }
        })) {
            return family.computeProgram(OuterCap, ctx, struct {
                /// Re-enter the nested state witness through the outer capability.
                pub fn run(_: type, _: anytype) lowered_machine.ResetError(NoError)!i32 {
                    return try demo.outer(OuterCap, {});
                }
            });
        }
    });
    try std.testing.expectEqual(@as(i32, 0), result.value);
}

test "public state handleWithErrorSet leaves caller provenance absent by default" {
    const NoError = error{};
    const StateInstance = Instance(i32, NoError);

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = StateInstance.init();

    const result = try handleWithErrorSet([]const u8, NoError, &runtime, &instance, @as(i32, 0), struct {
        /// Report whether the source-compatible state wrapper leaves caller provenance absent.
        pub fn body(comptime Cap: type, ctx: anytype) lowered_machine.ResetError(NoError)![]const u8 {
            _ = Cap;
            return if (@TypeOf(ctx.*).caller_source == null) "absent" else "present";
        }
    });

    try std.testing.expectEqualStrings("absent", result.value);
}
