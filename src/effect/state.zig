const algebraic = @import("algebraic.zig");
const family = @import("family.zig");
const lexical_with = @import("../with_api.zig");
const lowered_machine = @import("lowered_machine");
const shift = @import("../root.zig");
const std = @import("std");

/// Prompt-backed effect instance for a state family.
pub fn Instance(comptime StateType: type) type {
    return family.Instance(StateType, error{});
}

/// Final state plus body answer returned from a handled state program.
pub const HandleResult = family.HandleResult;

/// Lexical state handle used by `shift.with(...)`.
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

/// Descriptor value used by `shift.with(...)` for the built-in state family.
pub fn LexicalDescriptor(comptime StateType: type, comptime ErrorSetType: type) type {
    return struct {
        /// Shared error set carried by the lexical state descriptor.
        pub const ErrorSet = ErrorSetType;
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

        /// Run one lexical state descriptor through the existing state family.
        pub fn run(self: @This(), comptime AnswerType: type, runtime: *shift.Runtime, comptime Body: type) lowered_machine.ResetError(ErrorSetType)!lexical_with.DescriptorResult(Output, AnswerType) {
            var instance = family.Instance(StateType, ErrorSetType).init();
            const result = try handle(AnswerType, runtime, &instance, self.initial_state, Body);
            return .{
                .output = result.state,
                .value = result.value,
            };
        }
    };
}

/// Create one lexical state descriptor for `shift.with(...)`.
pub fn use(initial_state: anytype) LexicalDescriptor(@TypeOf(initial_state), error{}) {
    return .{ .initial_state = initial_state };
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
    return try algebraic.handleState(AnswerType, runtime, instance, initial_state, Body);
}

test "state instance shell stays prompt-sized" {
    const StateInstance = Instance(i32);
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(StateInstance));
}

test "state private context stays pointer-sized" {
    const NoError = error{};
    const StateContext = family.Context(struct {}, i32, i32, NoError);
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(StateContext));
}

test "state handle threads value and final state" {
    const NoError = error{};
    const StateInstance = Instance(i32);

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
    const result = try handle(i32, &runtime, &instance, 5, demo);
    try std.testing.expectEqual(@as(i32, 6), result.state);
    try std.testing.expectEqual(@as(i32, 6), result.value);
}

test "nested same-shaped state handles get distinct capability types" {
    const NoError = error{};
    const StateInstance = Instance(i32);
    const demo = struct {
        var runtime_ptr: ?*shift.Runtime = null;
        var inner_ptr: ?*const StateInstance = null;

        /// Open an inner handle and prove its capability type differs from the outer one.
        pub fn outer(comptime OuterCap: type, _: anytype) lowered_machine.ResetError(NoError)!i32 {
            const result = try handle(i32, runtime_ptr.?, inner_ptr.?, 0, struct {
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
    const result = try handle(i32, &runtime, &outer_instance, 0, struct {
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
