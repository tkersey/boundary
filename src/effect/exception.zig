const algebraic = @import("algebraic.zig");
const family = @import("family.zig");
const lexical_with = @import("../with_api.zig");
const shift = @import("../root.zig");
const std = @import("std");

/// Prompt-backed effect instance for an exception family.
pub fn Instance(comptime PayloadType: type, comptime ErrorSetType: type) type {
    return family.InstanceWithMode(.direct_return, PayloadType, ErrorSetType);
}

/// Lexical exception handle used by `shift.with(...)`.
pub fn LexicalHandle(comptime Cap: type, comptime ContextPtrType: type) type {
    return struct {
        ctx: ?ContextPtrType,

        /// Throw one payload through the lexical exception handle.
        pub fn throw(self: @This(), payload: family.ContextStateType(ContextPtrType)) shift.ResetError(family.ContextErrorSetType(ContextPtrType))!noreturn {
            return try algebraic.throwException(Cap, self.ctx.?, payload);
        }
    };
}

/// Descriptor value used by `shift.with(...)` for the built-in exception family.
pub fn LexicalDescriptor(comptime PayloadType: type, comptime ErrorSetType: type, comptime Catch: type) type {
    return struct {
        /// Shared error set carried by the lexical exception descriptor.
        pub const ErrorSet = ErrorSetType;
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
        pub fn run(self: @This(), comptime AnswerType: type, runtime: *shift.Runtime, comptime Body: type) shift.ResetError(ErrorSetType)!lexical_with.DescriptorResult(Output, AnswerType) {
            _ = self;
            var instance = Instance(PayloadType, ErrorSetType).init();
            const result = try handle(AnswerType, runtime, &instance, Catch, Body);
            return .{
                .output = {},
                .value = result,
            };
        }
    };
}

/// Create one lexical exception descriptor for `shift.with(...)`.
pub fn use(comptime PayloadType: type, comptime ErrorSetType: type, comptime Catch: type) LexicalDescriptor(PayloadType, ErrorSetType, Catch) {
    return .{};
}

/// Throw one payload through the supplied capability and handled context.
pub inline fn throw(
    comptime Cap: type,
    ctx: anytype,
    payload: family.ContextStateType(@TypeOf(ctx)),
) shift.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!noreturn {
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
) shift.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!AnswerType {
    return try algebraic.handleException(AnswerType, runtime, instance, Catch, Body);
}

test "exception instance shell stays prompt-sized" {
    const NoError = error{};
    const ExceptionInstance = Instance(i32, NoError);
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(ExceptionInstance));
}

test "exception handle can throw directly to the catch policy" {
    const NoError = error{};
    const ExceptionInstance = Instance([]const u8, NoError);
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
        pub fn outer(comptime OuterCap: type, _: anytype) shift.ResetError(NoError)!i32 {
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
            pub fn run() shift.ResetError(NoError)!i32 {
                return try demo.outer(OuterCap, {});
            }
        }.run)) {
            return computeProgram(OuterCap, ctx, struct {
                /// Re-enter the nested exception witness through the outer capability.
                pub fn run() shift.ResetError(NoError)!i32 {
                    return try demo.outer(OuterCap, {});
                }
            }.run);
        }
    });
    try std.testing.expectEqual(@as(i32, 0), result);
}
