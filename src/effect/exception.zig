const cleanup = @import("cleanup.zig");
const family = @import("family.zig");
const raw = @import("../raw.zig");
const shift = @import("../root.zig");
const std = @import("std");

/// Prompt-backed effect instance for an exception family.
pub fn Instance(comptime PayloadType: type, comptime ErrorSetType: type) type {
    return family.InstanceWithMode(.direct_return, PayloadType, ErrorSetType);
}

fn assertCatchType(comptime PayloadType: type, comptime AnswerType: type, comptime ErrorSetType: type, comptime CatchType: type) void {
    if (!family.hasDeclSafe(CatchType, "directReturn")) {
        @compileError("exception catch policy must declare directReturn");
    }
    const DirectReturnFn = @TypeOf(CatchType.directReturn);
    if (DirectReturnFn != fn (PayloadType) AnswerType and DirectReturnFn != fn (PayloadType) shift.ResetError(ErrorSetType)!AnswerType) {
        @compileError("exception catch policy directReturn must have type fn (Payload) Answer or fn (Payload) ResetError(ErrorSet)!Answer");
    }
}

fn Kernel(comptime PayloadType: type, comptime AnswerType: type, comptime ErrorSetType: type, comptime CatchType: type) type {
    const PromptType = raw.Prompt(.direct_return, AnswerType, AnswerType, ErrorSetType);
    return struct {
        const Prompt = PromptType;
        const Frame = struct {
            prompt: PromptType,
            payload: ?PayloadType = null,
        };

        var active_frame: ?*Frame = null;
        var active_cleanup_marker: ?*cleanup.Frame = null;

        fn callDirectReturn(payload: PayloadType) shift.ResetError(ErrorSetType)!AnswerType {
            const DirectReturnFn = @TypeOf(CatchType.directReturn);
            if (DirectReturnFn == fn (PayloadType) AnswerType) return CatchType.directReturn(payload);
            return try CatchType.directReturn(payload);
        }

        fn throw(payload: PayloadType) shift.ResetError(ErrorSetType)!noreturn {
            const frame = active_frame.?;
            frame.payload = payload;
            const handler = struct {
                /// Convert the thrown payload into the enclosing answer.
                pub fn directReturn() shift.ResetError(ErrorSetType)!AnswerType {
                    cleanup.unwindTo(active_cleanup_marker) catch |err| return @errorCast(err);
                    return try callDirectReturn(active_frame.?.payload.?);
                }
            };

            _ = try raw.shift(void, PromptType, &frame.prompt, handler);
            unreachable;
        }
    };
}

/// Throw one payload through the supplied capability and handled context.
pub inline fn throw(
    comptime Cap: type,
    ctx: anytype,
    payload: family.ContextStateType(@TypeOf(ctx)),
) shift.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!noreturn {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    const ContextType = family.ContextTypeFromPtr(@TypeOf(ctx));
    comptime {
        if (!family.hasDeclSafe(ContextType.capability, "CatchType")) {
            @compileError("exception capability does not carry a catch type");
        }
    }
    const CatchType = ContextType.capability.CatchType();
    comptime assertCatchType(ContextType.StateType, ContextType.AnswerType, ContextType.ErrorSetType, CatchType);
    const exception_impl = Kernel(ContextType.StateType, ContextType.AnswerType, ContextType.ErrorSetType, CatchType);
    _ = ctx._cap;
    return try exception_impl.throw(payload);
}

/// Run an exception effect body and return the final caught or normal answer.
pub fn handle(
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Catch: type,
    comptime Body: type,
) shift.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!AnswerType {
    const PayloadType = family.InstanceStateType(@TypeOf(instance));
    const ErrorSetType = family.InstanceErrorSetType(@TypeOf(instance));
    comptime assertCatchType(PayloadType, AnswerType, ErrorSetType, Catch);
    const exception_impl = Kernel(PayloadType, AnswerType, ErrorSetType, Catch);
    const Cap = struct {
        _seal: struct {},
        const body_tag = Body;

        /// Catch type used by this exception capability.
        pub fn CatchType() type {
            return Catch;
        }
    };
    const ContextType = family.Context(Cap, PayloadType, AnswerType, ErrorSetType);

    var frame = exception_impl.Frame{
        .prompt = .{ .token = instance.prompt.token },
    };
    var cap_token = Cap{ ._seal = .{} };
    var context = ContextType{ ._cap = &cap_token };

    const invoker = struct {
        threadlocal var active_context: ?*ContextType = null;

        fn invoke() shift.ResetError(ErrorSetType)!AnswerType {
            return try Body.body(Cap, active_context.?);
        }
    };

    const previous_frame = exception_impl.active_frame;
    const previous_context = invoker.active_context;
    const previous_cleanup_marker = exception_impl.active_cleanup_marker;
    exception_impl.active_frame = &frame;
    invoker.active_context = &context;
    exception_impl.active_cleanup_marker = cleanup.checkpoint();
    defer {
        exception_impl.active_frame = previous_frame;
        invoker.active_context = previous_context;
        exception_impl.active_cleanup_marker = previous_cleanup_marker;
    }

    return try raw.reset(exception_impl.Prompt, runtime, &frame.prompt, invoker.invoke);
}

test "exception instance shell stays prompt-sized" {
    const NoError = error{};
    const ExceptionInstance = Instance(i32, NoError);
    const PromptShell = raw.Prompt(.direct_return, void, void, NoError);
    try std.testing.expectEqual(@sizeOf(PromptShell), @sizeOf(ExceptionInstance));
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
        pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)![]const u8 {
            try throw(Cap, ctx, "result=early");
            after_throw = true;
            return "result=late";
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator, .{});
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
                pub fn body(comptime InnerCap: type, _: anytype) shift.ResetError(NoError)!i32 {
                    comptime if (OuterCap == InnerCap) {
                        @compileError("nested exception handles must receive distinct capability types");
                    };
                    return 0;
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    var outer_instance = ExceptionInstance.init();
    var inner_instance = ExceptionInstance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    const result = try handle(i32, &runtime, &outer_instance, catcher, struct {
        /// Enter the outer exception handle and hand its capability inward.
        pub fn body(comptime OuterCap: type, ctx: anytype) shift.ResetError(NoError)!i32 {
            return try demo.outer(OuterCap, ctx);
        }
    });
    try std.testing.expectEqual(@as(i32, 0), result);
}
