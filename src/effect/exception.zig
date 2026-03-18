const algebraic = @import("algebraic.zig");
const family = @import("family.zig");
const lexical_with = @import("../with_api.zig");
const lowered_machine = @import("lowered_machine");
const shift = @import("../root.zig");
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
pub fn Instance(comptime PayloadType: type) type {
    return family.InstanceWithMode(.direct_return, PayloadType, error{});
}

/// Lexical exception handle used by `shift.with(...)`.
pub fn LexicalHandle(comptime Cap: type, comptime ContextPtrType: type) type {
    return struct {
        ctx: ?ContextPtrType,

        /// Throw one payload through the lexical exception handle.
        pub fn throw(self: @This(), payload: family.ContextStateType(ContextPtrType)) lowered_machine.ResetError(family.ContextErrorSetType(ContextPtrType))!noreturn {
            return try algebraic.throwException(Cap, self.ctx.?, payload);
        }
    };
}

/// Descriptor value used by `shift.with(...)` for the built-in exception family.
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

        /// Run one lexical exception descriptor through the existing exception family.
        pub fn run(self: @This(), comptime AnswerType: type, comptime RunErrorSetType: type, runtime: *shift.Runtime, comptime Body: type) lowered_machine.ResetError(RunErrorSetType)!lexical_with.DescriptorResult(Output, AnswerType) {
            _ = self;
            var instance = family.InstanceWithMode(.direct_return, PayloadType, ErrorSetType).init();
            const result = try handleWithErrorSet(AnswerType, RunErrorSetType, runtime, &instance, Catch, Body);
            return .{
                .output = {},
                .value = result,
            };
        }
    };
}

/// Create one lexical exception descriptor for `shift.with(...)`.
pub fn use(comptime PayloadType: type, comptime Catch: type) LexicalDescriptor(PayloadType, CatchErrorSet(Catch), Catch) {
    return .{};
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
    return try algebraic.handleException(AnswerType, runtime, instance, Catch, Body);
}

pub fn handleWithErrorSet(
    comptime AnswerType: type,
    comptime RunErrorSetType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Catch: type,
    comptime Body: type,
) lowered_machine.ResetError(RunErrorSetType)!AnswerType {
    return try algebraic.handleExceptionWithErrorSet(AnswerType, RunErrorSetType, runtime, instance, Catch, Body);
}

test "exception instance shell stays prompt-sized" {
    const ExceptionInstance = Instance(i32);
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(ExceptionInstance));
}

test "exception handle can throw directly to the catch policy" {
    const ExceptionInstance = Instance([]const u8);
    const catcher = struct {
        /// Recover the thrown payload into the final answer.
        pub fn directReturn(payload: []const u8) []const u8 {
            return payload;
        }
    };
    const demo = struct {
        var after_throw: bool = false;

        /// Throw once and prove the body tail never resumes.
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(throwProgram(Cap, ctx, "result=early")) {
            return throwProgram(Cap, ctx, "result=early");
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = ExceptionInstance.init();
    demo.after_throw = false;
    const result = try handle([]const u8, &runtime, &instance, catcher, demo);
    try std.testing.expectEqualStrings("result=early", result);
    try std.testing.expect(!demo.after_throw);
}

test "nested same-shaped exception handles get distinct capability types" {
    const NoError = error{};
    const ExceptionInstance = Instance(i32);
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
            return try handle(i32, runtime_ptr.?, inner_ptr.?, catcher, struct {
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
    const result = try handle(i32, &runtime, &outer_instance, catcher, struct {
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
