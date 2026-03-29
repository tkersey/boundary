const algebraic = @import("algebraic.zig");
const family = @import("family.zig");
const lexical_with = @import("../with_api.zig");
const lowered_machine = @import("lowered_machine");
const shift = @import("../root.zig");
const std = @import("std");

/// Prompt-backed effect instance for a reader family.
pub const Instance = family.Instance;

/// Lexical reader handle used by `shift.with(...)`.
pub fn LexicalHandle(comptime Cap: type, comptime ContextPtrType: type) type {
    return struct {
        ctx: ?ContextPtrType,

        /// Read the current environment through the lexical handle.
        pub fn ask(self: @This()) lowered_machine.ResetError(family.ContextErrorSetType(ContextPtrType))!family.ContextStateType(ContextPtrType) {
            return try algebraic.readerAsk(Cap, self.ctx.?);
        }
    };
}

/// Descriptor value used by `shift.with(...)` for the built-in reader family.
pub fn LexicalDescriptor(comptime StateType: type, comptime ErrorSetType: type) type {
    return struct {
        /// Shared error set carried by the lexical reader descriptor.
        pub const ErrorSet = ErrorSetType;
        /// Environment type threaded through the lexical reader context.
        pub const State = StateType;
        /// Reader lexical descriptors do not surface an extra output value.
        pub const Output = void;

        environment: StateType,

        /// Resolve the lexical reader handle type for one exact context.
        pub fn HandleType(comptime Cap: type, comptime ContextPtrType: type) type {
            return LexicalHandle(Cap, ContextPtrType);
        }

        /// Bind one lexical reader handle to the active exact context.
        pub fn bindLexical(self: @This(), comptime Cap: type, ctx: anytype) HandleType(Cap, @TypeOf(ctx)) {
            _ = self;
            return .{ .ctx = ctx };
        }

        /// Run one lexical reader descriptor through the existing reader family.
        pub fn run(self: @This(), comptime AnswerType: type, comptime RunErrorSetType: type, runtime: *shift.Runtime, lexical_state: anytype, comptime Body: type) lowered_machine.ResetError(RunErrorSetType)!lexical_with.DescriptorResult(Output, AnswerType) {
            var instance = family.Instance(StateType, ErrorSetType).init();
            const result = try algebraic.handleReaderWithErrorSetLexical(AnswerType, RunErrorSetType, .{
                .runtime = runtime,
                .instance = &instance,
                .environment = self.environment,
                .lexical_state = @constCast(lexical_state),
            }, Body);
            return .{
                .output = {},
                .value = result,
            };
        }
    };
}

/// Create one lexical reader descriptor for `shift.with(...)`.
pub fn use(environment: anytype) LexicalDescriptor(@TypeOf(environment), error{}) {
    return .{ .environment = environment };
}

/// Read the current environment value for the supplied capability and handled context.
pub inline fn ask(
    comptime Cap: type,
    ctx: anytype,
) lowered_machine.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!family.ContextStateType(@TypeOf(ctx)) {
    return try algebraic.readerAsk(Cap, ctx);
}

/// Build one explicit reader body program with no prompt operation.
pub inline fn computeProgram(
    comptime Cap: type,
    ctx: anytype,
    comptime Thunk: type,
) @TypeOf(family.computeProgram(Cap, ctx, Thunk)) {
    return family.computeProgram(Cap, ctx, Thunk);
}

/// Run a reader effect body and return the body answer.
pub fn handle(
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    environment: family.InstanceStateType(@TypeOf(instance)),
    comptime Body: type,
) lowered_machine.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!AnswerType {
    return try algebraic.handleReader(AnswerType, runtime, instance, environment, Body);
}

/// Public `handleWithErrorSet` helper.
pub fn handleWithErrorSet(
    comptime AnswerType: type,
    comptime RunErrorSetType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    environment: family.InstanceStateType(@TypeOf(instance)),
    comptime Body: type,
) lowered_machine.ResetError(RunErrorSetType)!AnswerType {
    return try algebraic.handleReaderWithErrorSet(AnswerType, RunErrorSetType, runtime, instance, environment, Body);
}

test "reader instance shell stays prompt-sized" {
    const ReaderInstance = Instance(i32, error{});
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(ReaderInstance));
}

test "reader handle threads environment into the body" {
    const NoError = error{};
    const ReaderInstance = Instance(i32, NoError);
    const demo = struct {
        /// Execute the reader body by asking for the environment once.
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(family.computeProgram(Cap, ctx, struct {
            /// Read the active reader environment once.
            pub fn run(comptime ProgramCap: type, program_ctx: anytype) lowered_machine.ResetError(NoError)!i32 {
                return try ask(ProgramCap, program_ctx);
            }
        })) {
            return family.computeProgram(Cap, ctx, struct {
                /// Read the active reader environment once.
                pub fn run(comptime ProgramCap: type, program_ctx: anytype) lowered_machine.ResetError(NoError)!i32 {
                    return try ask(ProgramCap, program_ctx);
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = ReaderInstance.init();
    const result = try handle(i32, &runtime, &instance, 21, demo);
    try std.testing.expectEqual(@as(i32, 21), result);
}

test "nested same-shaped reader handles get distinct capability types" {
    const NoError = error{};
    const ReaderInstance = Instance(i32, NoError);
    const demo = struct {
        var runtime_ptr: ?*shift.Runtime = null;
        var inner_ptr: ?*const ReaderInstance = null;

        /// Open an inner reader handle and prove its capability type differs from the outer one.
        pub fn outer(comptime OuterCap: type, _: anytype) lowered_machine.ResetError(NoError)!i32 {
            return try handle(i32, runtime_ptr.?, inner_ptr.?, 0, struct {
                /// Reject capability-type collapse inside the nested reader handle.
                pub fn program(comptime InnerCap: type, inner_ctx: anytype) @TypeOf(family.computeProgram(InnerCap, inner_ctx, struct {
                    /// Return a neutral value from the nested reader body.
                    pub fn run(_: type, _: anytype) i32 {
                        return 0;
                    }
                })) {
                    comptime if (OuterCap == InnerCap) {
                        @compileError("nested reader handles must receive distinct capability types");
                    };
                    return family.computeProgram(InnerCap, inner_ctx, struct {
                        /// Return a neutral value from the nested reader body.
                        pub fn run(_: type, _: anytype) i32 {
                            return 0;
                        }
                    });
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var outer_instance = ReaderInstance.init();
    var inner_instance = ReaderInstance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    const result = try handle(i32, &runtime, &outer_instance, 0, struct {
        /// Enter the outer reader handle and hand its capability to the nested check.
        pub fn program(comptime OuterCap: type, ctx: anytype) @TypeOf(family.computeProgram(OuterCap, ctx, struct {
            /// Re-enter the nested reader witness through the outer capability.
            pub fn run(_: type, _: anytype) lowered_machine.ResetError(NoError)!i32 {
                return try demo.outer(OuterCap, {});
            }
        })) {
            return family.computeProgram(OuterCap, ctx, struct {
                /// Re-enter the nested reader witness through the outer capability.
                pub fn run(_: type, _: anytype) lowered_machine.ResetError(NoError)!i32 {
                    return try demo.outer(OuterCap, {});
                }
            });
        }
    });
    try std.testing.expectEqual(@as(i32, 0), result);
}
