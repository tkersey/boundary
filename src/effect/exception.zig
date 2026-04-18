const algebraic = @import("algebraic.zig");
const effect_schema = @import("../effect_schema.zig");
const family = @import("family.zig");
const frontend = @import("frontend_support");
const lexical_with = @import("../with_api.zig");
const lowered_machine = @import("lowered_machine");
const prompt_contract = @import("prompt_contract_support");
const shift = lowered_machine;
const std = @import("std");

fn ReturnTypeErrorSet(comptime ReturnType: type) type {
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.error_set,
        else => error{},
    };
}

fn CatchErrorSet(comptime Catch: type) type {
    return ReturnTypeErrorSet(@typeInfo(@TypeOf(Catch.directReturn)).@"fn".return_type.?);
}

/// Prompt-backed effect instance for an exception family.
pub fn Instance(comptime PayloadType: type, comptime ErrorSetType: type) type {
    return family.InstanceWithMode(.direct_return, PayloadType, ErrorSetType);
}

/// Lexical exception handle used by `shift.withAt(@src(), ...)`.
pub fn LexicalHandle(comptime Cap: type, comptime ContextPtrType: type) type {
    return struct {
        ctx: ?ContextPtrType,

        /// Throw one payload through the lexical exception handle.
        pub fn throw(self: @This(), payload: family.ContextStateType(ContextPtrType)) lowered_machine.ResetError(family.ContextErrorSetType(ContextPtrType))!noreturn {
            return try algebraic.throwException(Cap, self.ctx.?, payload);
        }
    };
}

/// Descriptor value used by `shift.withAt(@src(), ...)` for the built-in exception family.
pub fn LexicalDescriptor(comptime PayloadType: type, comptime ErrorSetType: type, comptime Catch: type) type {
    return struct {
        /// Shared error set carried by the lexical exception descriptor.
        pub const ErrorSet = ErrorSetType;
        /// Payload type threaded through the lexical exception context.
        pub const State = PayloadType;
        /// Exception lexical descriptors do not surface an extra output value.
        pub const Output = void;

        /// Resolve the lexical exception handle type for one exact context.
        pub fn HandleType(comptime Cap: type, comptime ContextPtrType: type) type {
            return LexicalHandle(Cap, ContextPtrType);
        }

        /// Bind one lexical exception handle to the active exact context.
        pub fn bindLexical(self: @This(), comptime Cap: type, ctx: anytype) HandleType(Cap, @TypeOf(ctx)) {
            _ = self;
            return .{ .ctx = ctx };
        }

        /// Return the shared binding schema for this lexical descriptor under one requirement label.
        pub fn BindingSchema(comptime requirement_label: [:0]const u8) type {
            return effect_schema.Binding(requirement_label, Schema(PayloadType, ErrorSetType, Catch), struct {});
        }

        /// Run one lexical exception descriptor through the existing exception family.
        pub fn run(self: @This(), comptime AnswerType: type, comptime RunErrorSetType: type, run_ctx: anytype, comptime Body: type) lowered_machine.ResetError(RunErrorSetType)!lexical_with.DescriptorResult(Output, AnswerType) {
            _ = self;
            var instance = family.InstanceWithMode(.direct_return, PayloadType, ErrorSetType).init();
            const result = try algebraic.handleExceptionWithErrorSetLexicalAt(AnswerType, RunErrorSetType, @TypeOf(run_ctx).caller_source, .{
                .runtime = run_ctx.runtime,
                .instance = &instance,
                .lexical_state = @constCast(run_ctx.lexical_state),
            }, Catch, Body);
            return .{
                .output = {},
                .value = result,
            };
        }
    };
}

/// Create one lexical exception descriptor for `shift.withAt(@src(), ...)`.
pub fn use(comptime PayloadType: type, comptime Catch: type) LexicalDescriptor(PayloadType, CatchErrorSet(Catch), Catch) {
    return .{};
}

/// Shared effect schema for the built-in exception family.
pub fn Schema(comptime PayloadType: type, comptime ErrorSetType: type, comptime Catch: type) type {
    return effect_schema.abort_catch(PayloadType, ErrorSetType, Catch);
}

/// Throw one payload through the supplied capability and handled context.
pub inline fn throw(
    comptime Cap: type,
    ctx: anytype,
    payload: family.ContextStateType(@TypeOf(ctx)),
) lowered_machine.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!noreturn {
    return try algebraic.throwException(Cap, ctx, payload);
}

/// Build one explicit exception throw program for the supplied payload.
pub inline fn throwProgram(
    comptime Cap: type,
    ctx: anytype,
    payload: family.ContextStateType(@TypeOf(ctx)),
) @TypeOf(algebraic.throwExceptionProgram(Cap, ctx, payload)) {
    return algebraic.throwExceptionProgram(Cap, ctx, payload);
}

/// Build one bound exception throw program for the supplied payload.
pub inline fn throwBoundProgram(
    comptime Cap: type,
    ctx: anytype,
    payload: family.ContextStateType(@TypeOf(ctx)),
) @TypeOf(algebraic.throwExceptionBoundProgram(Cap, ctx, payload)) {
    return algebraic.throwExceptionBoundProgram(Cap, ctx, payload);
}

/// Build one explicit exception body program with no throw operation.
pub inline fn computeProgram(
    comptime Cap: type,
    ctx: anytype,
    thunk: anytype,
) @TypeOf(algebraic.exceptionComputeProgram(Cap, ctx, thunk)) {
    return algebraic.exceptionComputeProgram(Cap, ctx, thunk);
}

/// Run an exception effect body and return the final caught or normal answer.
pub fn handle(
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Catch: type,
    comptime Body: type,
) lowered_machine.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!AnswerType {
    return try algebraic.handleException(null, AnswerType, runtime, instance, Catch, Body);
}

/// Run an exception effect body with explicit caller provenance and return the final caught or normal answer.
pub fn handleAt(
    comptime caller_source: std.builtin.SourceLocation,
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Catch: type,
    comptime Body: type,
) lowered_machine.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!AnswerType {
    return try algebraic.handleException(caller_source, AnswerType, runtime, instance, Catch, Body);
}

/// Public `handleWithErrorSet` helper.
// zlinter-disable max_positional_args - public caller provenance and catch inputs stay explicit at this compatibility wrapper.
pub fn handleWithErrorSet(
    comptime AnswerType: type,
    comptime RunErrorSetType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Catch: type,
    comptime Body: type,
) lowered_machine.ResetError(RunErrorSetType)!AnswerType {
    return try algebraic.handleExceptionWithErrorSet(null, AnswerType, RunErrorSetType, runtime, instance, Catch, Body);
}

/// Public `handleWithErrorSetAt` helper.
// zlinter-disable max_positional_args - public caller provenance and catch inputs stay explicit at this compatibility wrapper.
pub fn handleWithErrorSetAt(
    comptime caller_source: std.builtin.SourceLocation,
    comptime AnswerType: type,
    comptime RunErrorSetType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Catch: type,
    comptime Body: type,
) lowered_machine.ResetError(RunErrorSetType)!AnswerType {
    return try algebraic.handleExceptionWithErrorSet(caller_source, AnswerType, RunErrorSetType, runtime, instance, Catch, Body);
}

test "exception instance shell stays prompt-sized" {
    const ExceptionInstance = Instance(i32, error{});
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(ExceptionInstance));
}

test "exception handle can throw directly to the catch policy" {
    const ExceptionInstance = Instance([]const u8, error{});
    const catcher = struct {
        /// Recover the thrown payload into the final answer.
        pub fn directReturn(payload: []const u8) []const u8 {
            return payload;
        }
    };
    const demo = struct {
        var after_throw: bool = false;

        /// Throw once and prove the body tail never resumes.
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(throwBoundProgram(Cap, ctx, "result=early")) {
            return throwBoundProgram(Cap, ctx, "result=early");
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = ExceptionInstance.init();
    demo.after_throw = false;
    const result = try handleAt(@src(), []const u8, &runtime, &instance, catcher, demo);
    try std.testing.expectEqualStrings("result=early", result);
    try std.testing.expect(!demo.after_throw);
}

test "exception throwProgram stays on the explicit frontend.Program surface" {
    const ExceptionInstance = Instance([]const u8, error{});
    const catcher = struct {
        /// Recover the explicit-program regression payload unchanged.
        pub fn directReturn(payload: []const u8) []const u8 {
            return payload;
        }
    };
    const demo = struct {
        /// Store the exception throw program on the explicit frontend.Program surface.
        pub fn program(comptime Cap: type, ctx: anytype) frontend.Program(prompt_contract.Prompt(
            .direct_return,
            family.ContextAnswerType(@TypeOf(ctx)),
            family.ContextAnswerType(@TypeOf(ctx)),
            family.ContextErrorSetType(@TypeOf(ctx)),
        )) {
            const explicit_program: frontend.Program(prompt_contract.Prompt(
                .direct_return,
                family.ContextAnswerType(@TypeOf(ctx)),
                family.ContextAnswerType(@TypeOf(ctx)),
                family.ContextErrorSetType(@TypeOf(ctx)),
            )) = throwProgram(Cap, ctx, "result=early");
            return explicit_program;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = ExceptionInstance.init();
    const result = try handleAt(@src(), []const u8, &runtime, &instance, catcher, demo);
    try std.testing.expectEqualStrings("result=early", result);
}

test "exception throwProgram keeps direct explicit-program state thread-local across concurrent handles" {
    const ExceptionInstance = Instance([]const u8, error{});
    const catcher = struct {
        /// Preserve the thrown payload so concurrent explicit-program runs can assert thread isolation.
        pub fn directReturn(payload: []const u8) []const u8 {
            return payload;
        }
    };
    const Shared = struct {
        stage: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
        first_result: []const u8 = "",
        second_result: []const u8 = "",
    };
    const waitForStage = struct {
        fn until(stage: *std.atomic.Value(u8), expected: u8) void {
            while (stage.load(.acquire) < expected) {
                std.Thread.yield() catch {};
            }
        }
    }.until;

    var shared = Shared{};

    const first = try std.Thread.spawn(.{}, struct {
        fn run(state: *Shared) void {
            const demo = struct {
                var shared_ptr: *Shared = undefined;

                /// Build the first explicit throw program, then wait for the second thread to overwrite shared direct state.
                pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(throwBoundProgram(Cap, ctx, "first")) {
                    const explicit_program = throwBoundProgram(Cap, ctx, "first");
                    shared_ptr.stage.store(1, .release);
                    waitForStage(&shared_ptr.stage, 2);
                    return explicit_program;
                }
            };

            demo.shared_ptr = state;
            var runtime = shift.Runtime.init(std.testing.allocator);
            defer runtime.deinit();
            var instance = ExceptionInstance.init();
            state.first_result = handleAt(@src(), []const u8, &runtime, &instance, catcher, demo) catch unreachable;
        }
    }.run, .{&shared});

    const second = try std.Thread.spawn(.{}, struct {
        fn run(state: *Shared) void {
            waitForStage(&state.stage, 1);

            const demo = struct {
                var shared_ptr: *Shared = undefined;

                /// Build the second explicit throw program after the first thread has published its pending direct state.
                pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(throwBoundProgram(Cap, ctx, "second")) {
                    const explicit_program = throwBoundProgram(Cap, ctx, "second");
                    shared_ptr.stage.store(2, .release);
                    return explicit_program;
                }
            };

            demo.shared_ptr = state;
            var runtime = shift.Runtime.init(std.testing.allocator);
            defer runtime.deinit();
            var instance = ExceptionInstance.init();
            state.second_result = handleAt(@src(), []const u8, &runtime, &instance, catcher, demo) catch unreachable;
        }
    }.run, .{&shared});

    first.join();
    second.join();

    try std.testing.expectEqualStrings("first", shared.first_result);
    try std.testing.expectEqualStrings("second", shared.second_result);
}

test "public exception handleWithErrorSet preserves caller provenance" {
    const NoError = error{};
    const ExceptionInstance = Instance([]const u8, NoError);
    const catcher = struct {
        /// Preserve the normal body answer for provenance verification.
        pub fn directReturn(payload: []const u8) []const u8 {
            return payload;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = ExceptionInstance.init();

    const result = try handleWithErrorSet([]const u8, NoError, &runtime, &instance, catcher, struct {
        /// Return the exact caller-owned source file observed through the public exception wrapper.
        pub fn body(comptime Cap: type, ctx: anytype) lowered_machine.ResetError(NoError)![]const u8 {
            _ = Cap;
            return @TypeOf(ctx.*).caller_source.?.file;
        }
    });

    try std.testing.expectEqualStrings(@src().file, result);
}

test "nested same-shaped exception handles get distinct capability types" {
    const NoError = error{};
    const ExceptionInstance = Instance(i32, NoError);
    const catcher = struct {
        /// Preserve the thrown payload unchanged for the nested exception test.
        pub fn directReturn(payload: i32) i32 {
            return payload;
        }
    };
    const demo = struct {
        var runtime_ptr: ?*shift.Runtime = null;
        var inner_ptr: ?*const ExceptionInstance = null;

        /// Open an inner exception handle and prove its capability differs from the outer one.
        pub fn outer(comptime OuterCap: type, _: anytype) lowered_machine.ResetError(NoError)!i32 {
            return try handleAt(@src(), i32, runtime_ptr.?, inner_ptr.?, catcher, struct {
                /// Reject capability-type collapse inside the nested exception handle.
                pub fn program(comptime InnerCap: type, inner_ctx: anytype) @TypeOf(computeProgram(InnerCap, inner_ctx, struct {
                    /// Return a neutral value from the nested exception body.
                    pub fn run() i32 {
                        return 0;
                    }
                }.run)) {
                    comptime if (OuterCap == InnerCap) {
                        @compileError("nested exception handles must receive distinct capability types");
                    };
                    return computeProgram(InnerCap, inner_ctx, struct {
                        /// Return a neutral value from the nested exception body.
                        pub fn run() i32 {
                            return 0;
                        }
                    }.run);
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var outer_instance = ExceptionInstance.init();
    var inner_instance = ExceptionInstance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    const result = try handleAt(@src(), i32, &runtime, &outer_instance, catcher, struct {
        /// Enter the outer exception handle and hand its capability inward.
        pub fn program(comptime OuterCap: type, ctx: anytype) @TypeOf(computeProgram(OuterCap, ctx, struct {
            /// Re-enter the nested exception witness through the outer capability.
            pub fn run() lowered_machine.ResetError(NoError)!i32 {
                return try demo.outer(OuterCap, {});
            }
        }.run)) {
            return computeProgram(OuterCap, ctx, struct {
                /// Re-enter the nested exception witness through the outer capability.
                pub fn run() lowered_machine.ResetError(NoError)!i32 {
                    return try demo.outer(OuterCap, {});
                }
            }.run);
        }
    });
    try std.testing.expectEqual(@as(i32, 0), result);
}
