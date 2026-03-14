const cleanup = @import("cleanup.zig");
const family = @import("family.zig");
const raw = @import("../raw.zig");
const shift = @import("../root.zig");
const std = @import("std");

/// Prompt-backed effect instance for a bracketed resource family.
pub fn Instance(comptime ResourceType: type, comptime ErrorSetType: type) type {
    return family.InstanceWithMode(.resume_then_transform, ResourceType, ErrorSetType);
}

fn assertManagerType(comptime ResourceType: type, comptime ErrorSetType: type, comptime ManagerType: type) void {
    if (!family.hasDeclSafe(ManagerType, "acquire")) {
        @compileError("resource manager must declare acquire");
    }
    if (!family.hasDeclSafe(ManagerType, "release")) {
        @compileError("resource manager must declare release");
    }

    const AcquireFn = @TypeOf(ManagerType.acquire);
    if (AcquireFn != fn () ResourceType and AcquireFn != fn () shift.ResetError(ErrorSetType)!ResourceType) {
        @compileError("resource manager acquire must have type fn () Resource or fn () ResetError(ErrorSet)!Resource");
    }

    const ReleaseFn = @TypeOf(ManagerType.release);
    if (ReleaseFn != fn (ResourceType) void and ReleaseFn != fn (ResourceType) shift.ResetError(ErrorSetType)!void) {
        @compileError("resource manager release must have type fn (Resource) void or fn (Resource) ResetError(ErrorSet)!void");
    }
}

fn Kernel(comptime ResourceType: type, comptime AnswerType: type, comptime ErrorSetType: type, comptime ManagerType: type) type {
    const PromptType = raw.Prompt(.resume_then_transform, AnswerType, AnswerType, ErrorSetType);
    return struct {
        const Prompt = PromptType;
        const ResourceList = std.ArrayList(ResourceType);
        const Frame = struct {
            prompt: PromptType,
            allocator: std.mem.Allocator,
            resources: ResourceList = .empty,
            cleaned: bool = false,
            cleanup_frame: cleanup.Frame = .{
                .cleanupFn = cleanupResources,
            },

            fn deinit(self: *Frame) void {
                if (self.cleaned) return;
                self.cleaned = true;
                self.resources.deinit(self.allocator);
            }

            fn cleanupResources(base: *cleanup.Frame) anyerror!void {
                const self: *Frame = @fieldParentPtr("cleanup_frame", base);
                var first_error: ?shift.ResetError(ErrorSetType) = null;

                while (self.resources.items.len != 0) {
                    const resource = self.resources.items[self.resources.items.len - 1];
                    self.resources.items.len -= 1;
                    releaseOne(resource) catch |err| {
                        if (first_error == null) first_error = err;
                    };
                }

                self.deinit();
                if (first_error) |err| return err;
            }
        };

        var active_frame: ?*Frame = null;

        fn acquireOne() shift.ResetError(ErrorSetType)!ResourceType {
            const AcquireFn = @TypeOf(ManagerType.acquire);
            if (AcquireFn == fn () ResourceType) return ManagerType.acquire();
            return try ManagerType.acquire();
        }

        fn releaseOne(resource: ResourceType) shift.ResetError(ErrorSetType)!void {
            const ReleaseFn = @TypeOf(ManagerType.release);
            if (ReleaseFn == fn (ResourceType) void) return ManagerType.release(resource);
            return try ManagerType.release(resource);
        }

        fn acquire() shift.ResetError(ErrorSetType)!ResourceType {
            const handler = struct {
                /// Acquire one resource before resuming the body.
                pub fn resumeValue() shift.ResetError(ErrorSetType)!ResourceType {
                    const frame = active_frame.?;
                    const resource = try acquireOne();
                    try frame.resources.append(frame.allocator, resource);
                    return resource;
                }

                /// Preserve the resumed answer after the acquire point.
                pub fn afterResume(answer: AnswerType) AnswerType {
                    return answer;
                }
            };

            return try raw.shift(ResourceType, PromptType, &active_frame.?.prompt, handler);
        }
    };
}

/// Acquire one resource under the supplied capability and handled context.
pub inline fn acquire(
    comptime Cap: type,
    ctx: anytype,
) shift.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!family.ContextStateType(@TypeOf(ctx)) {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    const ContextType = family.ContextTypeFromPtr(@TypeOf(ctx));
    comptime {
        if (!family.hasDeclSafe(ContextType.capability, "ManagerType")) {
            @compileError("resource capability does not carry a manager type");
        }
    }
    const ManagerType = ContextType.capability.ManagerType();
    comptime assertManagerType(ContextType.StateType, ContextType.ErrorSetType, ManagerType);
    const resource_impl = Kernel(ContextType.StateType, ContextType.AnswerType, ContextType.ErrorSetType, ManagerType);
    _ = ctx._cap;
    return try resource_impl.acquire();
}

/// Run a resource effect body and guarantee LIFO cleanup of acquired resources.
pub fn handle(
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Manager: type,
    comptime Body: type,
) shift.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!AnswerType {
    const ResourceType = family.InstanceStateType(@TypeOf(instance));
    const ErrorSetType = family.InstanceErrorSetType(@TypeOf(instance));
    comptime assertManagerType(ResourceType, ErrorSetType, Manager);
    const resource_impl = Kernel(ResourceType, AnswerType, ErrorSetType, Manager);
    const Cap = struct {
        _seal: struct {},
        const body_tag = Body;

        /// Manager type used by this resource capability.
        pub fn ManagerType() type {
            return Manager;
        }
    };
    const ContextType = family.Context(Cap, ResourceType, AnswerType, ErrorSetType);

    var frame = resource_impl.Frame{
        .prompt = .{ .token = instance.prompt.token },
        .allocator = runtime.allocator,
    };
    defer frame.deinit();
    var cap_token = Cap{ ._seal = .{} };
    var context = ContextType{ ._cap = &cap_token };

    const invoker = struct {
        threadlocal var active_context: ?*ContextType = null;

        fn invoke() shift.ResetError(ErrorSetType)!AnswerType {
            return try Body.body(Cap, active_context.?);
        }
    };

    const previous_frame = resource_impl.active_frame;
    const previous_context = invoker.active_context;
    resource_impl.active_frame = &frame;
    invoker.active_context = &context;
    cleanup.push(&frame.cleanup_frame);
    defer {
        resource_impl.active_frame = previous_frame;
        invoker.active_context = previous_context;
    }

    var body_error: ?shift.ResetError(ErrorSetType) = null;
    var answer: ?AnswerType = null;
    answer = raw.reset(resource_impl.Prompt, runtime, &frame.prompt, invoker.invoke) catch |err| blk: {
        body_error = err;
        break :blk null;
    };

    const cleanup_marker = frame.cleanup_frame.previous;
    var cleanup_error: ?shift.ResetError(ErrorSetType) = null;
    cleanup.unwindTo(cleanup_marker) catch |err| {
        cleanup_error = @errorCast(err);
    };

    if (body_error) |err| {
        return err;
    }
    if (cleanup_error) |err| return err;
    return answer.?;
}

test "resource instance shell stays prompt-sized" {
    const NoError = error{};
    const ResourceInstance = Instance(i32, NoError);
    const PromptShell = raw.Prompt(.resume_then_transform, void, void, NoError);
    try std.testing.expectEqual(@sizeOf(PromptShell), @sizeOf(ResourceInstance));
}

test "resource handle releases in LIFO order after normal completion" {
    const NoError = error{};
    const ResourceInstance = Instance([]const u8, NoError);
    const manager = struct {
        var next_index: usize = 0;
        var transcript = [_][]const u8{ "", "", "", "", "", "" };
        var transcript_len: usize = 0;
        const resources = [_][]const u8{ "a", "b" };

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        /// Hand out resources in a fixed order for the normal resource test.
        pub fn acquire() []const u8 {
            const resource = resources[next_index];
            next_index += 1;
            note(resource);
            return resource;
        }

        /// Record release order for the normal resource test.
        pub fn release(resource: []const u8) void {
            note(resource);
        }
    };
    const demo = struct {
        /// Acquire two resources in order and return normally.
        pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)![]const u8 {
            const first = try acquire(Cap, ctx);
            manager.note(first);
            const second = try acquire(Cap, ctx);
            manager.note(second);
            return "done";
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    var instance = ResourceInstance.init();
    manager.next_index = 0;
    manager.transcript_len = 0;
    const result = try handle([]const u8, &runtime, &instance, manager, demo);
    try std.testing.expectEqualStrings("done", result);
    try std.testing.expectEqualStrings("a", manager.transcript[0]);
    try std.testing.expectEqualStrings("a", manager.transcript[1]);
    try std.testing.expectEqualStrings("b", manager.transcript[2]);
    try std.testing.expectEqualStrings("b", manager.transcript[3]);
    try std.testing.expectEqualStrings("b", manager.transcript[4]);
    try std.testing.expectEqualStrings("a", manager.transcript[5]);
}

test "resource handle releases before outer exception catch returns" {
    const NoError = error{};
    const ResourceInstance = Instance([]const u8, NoError);
    const ExceptionInstance = @import("exception.zig").Instance([]const u8, NoError);

    const manager = struct {
        var transcript = [_][]const u8{ "", "", "", "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        /// Acquire one named resource for the abortive cleanup test.
        pub fn acquire() []const u8 {
            note("acquire=r");
            return "r";
        }

        /// Release the named resource before the outer catch runs.
        pub fn release(resource: []const u8) void {
            _ = resource;
            note("release=r");
        }
    };

    const catcher = struct {
        /// Record the catch after resource cleanup has already happened.
        pub fn directReturn(payload: []const u8) []const u8 {
            _ = payload;
            manager.note("catch=boom");
            return "handled=boom";
        }
    };

    const scenario = struct {
        var runtime_ptr: ?*shift.Runtime = null;
        var resource_ptr: ?*const ResourceInstance = null;

        /// Open a resource handle and throw through the outer exception capability.
        pub fn outer(comptime ExceptionCap: type, exception_ctx: anytype) shift.ResetError(NoError)![]const u8 {
            const ExceptionCtxType = @TypeOf(exception_ctx);
            const inner = struct {
                threadlocal var active_exception_ctx: ?ExceptionCtxType = null;

                /// Acquire once, then abort through the outer exception handler.
                pub fn body(comptime ResourceCap: type, resource_ctx: anytype) shift.ResetError(NoError)![]const u8 {
                    const resource = try acquire(ResourceCap, resource_ctx);
                    _ = resource;
                    manager.note("use=r");
                    try @import("exception.zig").throw(ExceptionCap, active_exception_ctx.?, "boom");
                }
            };

            const previous_exception_ctx = inner.active_exception_ctx;
            inner.active_exception_ctx = exception_ctx;
            defer inner.active_exception_ctx = previous_exception_ctx;
            return try handle([]const u8, runtime_ptr.?, resource_ptr.?, manager, inner);
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    var exception_instance = ExceptionInstance.init();
    var resource_instance = ResourceInstance.init();
    scenario.runtime_ptr = &runtime;
    scenario.resource_ptr = &resource_instance;
    manager.transcript_len = 0;
    const result = try @import("exception.zig").handle([]const u8, &runtime, &exception_instance, catcher, struct {
        /// Enter the outer exception handle and hand its capability to the inner resource scope.
        pub fn body(comptime ExceptionCap: type, exception_ctx: anytype) shift.ResetError(NoError)![]const u8 {
            return try scenario.outer(ExceptionCap, exception_ctx);
        }
    });
    try std.testing.expectEqualStrings("handled=boom", result);
    try std.testing.expectEqualStrings("acquire=r", manager.transcript[0]);
    try std.testing.expectEqualStrings("use=r", manager.transcript[1]);
    try std.testing.expectEqualStrings("release=r", manager.transcript[2]);
    try std.testing.expectEqualStrings("catch=boom", manager.transcript[3]);
}

test "resource handle releases before outer optional return-now completes" {
    const NoError = error{};
    const ResourceInstance = Instance([]const u8, NoError);
    const OptionalInstance = @import("optional.zig").Instance([]const u8, NoError);

    const manager = struct {
        var transcript = [_][]const u8{ "", "", "", "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        /// Acquire one named resource for the optional-return cleanup test.
        pub fn acquire() []const u8 {
            note("acquire=r");
            return "r";
        }

        /// Release the named resource before the outer optional answer completes.
        pub fn release(resource: []const u8) void {
            _ = resource;
            note("release=r");
        }
    };

    const policy = struct {
        /// Return the enclosing optional answer after resource cleanup has run.
        pub fn resumeOrReturn() shift.ResumeOrReturn([]const u8, []const u8) {
            manager.note("policy-return-now");
            return shift.ResumeOrReturn([]const u8, []const u8).returnNow("result=early");
        }

        /// Preserve the resumed answer if this branch were ever resumed.
        pub fn afterResume(value: []const u8) []const u8 {
            return value;
        }
    };

    const scenario = struct {
        var runtime_ptr: ?*shift.Runtime = null;
        var resource_ptr: ?*const ResourceInstance = null;

        /// Open a resource handle and trigger the outer optional return-now branch.
        pub fn outer(comptime OptionalCap: type, optional_ctx: anytype) shift.ResetError(NoError)![]const u8 {
            const OptionalCtxType = @TypeOf(optional_ctx);
            const inner = struct {
                threadlocal var active_optional_ctx: ?OptionalCtxType = null;

                /// Acquire once, then early-return through the outer optional handler.
                pub fn body(comptime ResourceCap: type, resource_ctx: anytype) shift.ResetError(NoError)![]const u8 {
                    const resource = try acquire(ResourceCap, resource_ctx);
                    _ = resource;
                    manager.note("use=r");
                    _ = try @import("optional.zig").request(OptionalCap, active_optional_ctx.?);
                    return "result=late";
                }
            };

            const previous_optional_ctx = inner.active_optional_ctx;
            inner.active_optional_ctx = optional_ctx;
            defer inner.active_optional_ctx = previous_optional_ctx;
            return try handle([]const u8, runtime_ptr.?, resource_ptr.?, manager, inner);
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    var optional_instance = OptionalInstance.init();
    var resource_instance = ResourceInstance.init();
    scenario.runtime_ptr = &runtime;
    scenario.resource_ptr = &resource_instance;
    manager.transcript_len = 0;
    const result = try @import("optional.zig").handle([]const u8, &runtime, &optional_instance, policy, struct {
        /// Enter the outer optional handle and hand its capability to the inner resource scope.
        pub fn body(comptime OptionalCap: type, optional_ctx: anytype) shift.ResetError(NoError)![]const u8 {
            return try scenario.outer(OptionalCap, optional_ctx);
        }
    });
    try std.testing.expectEqualStrings("result=early", result);
    try std.testing.expectEqualStrings("acquire=r", manager.transcript[0]);
    try std.testing.expectEqualStrings("use=r", manager.transcript[1]);
    try std.testing.expectEqualStrings("policy-return-now", manager.transcript[2]);
    try std.testing.expectEqualStrings("release=r", manager.transcript[3]);
}

test "resource release error wins after a successful body" {
    const DemoError = error{ReleaseFailed};
    const ResourceInstance = Instance(i32, DemoError);

    const manager = struct {
        /// Hand out one resource for the release-error precedence test.
        pub fn acquire() i32 {
            return 1;
        }

        /// Fail release to prove cleanup errors become the public result after success.
        pub fn release(_: i32) shift.ResetError(DemoError)!void {
            return error.ReleaseFailed;
        }
    };

    const demo = struct {
        /// Acquire one resource and otherwise complete successfully.
        pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(DemoError)![]const u8 {
            _ = try acquire(Cap, ctx);
            return "done";
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    var instance = ResourceInstance.init();
    try std.testing.expectError(error.ReleaseFailed, handle([]const u8, &runtime, &instance, manager, demo));
}

test "resource body error wins over release error" {
    const DemoError = error{BodyFailed, ReleaseFailed};
    const ResourceInstance = Instance(i32, DemoError);

    const manager = struct {
        /// Hand out one resource for the body-error precedence test.
        pub fn acquire() i32 {
            return 1;
        }

        /// Also fail release, but the body error must remain public.
        pub fn release(_: i32) shift.ResetError(DemoError)!void {
            return error.ReleaseFailed;
        }
    };

    const demo = struct {
        /// Acquire one resource and then fail the body.
        pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(DemoError)![]const u8 {
            _ = try acquire(Cap, ctx);
            return error.BodyFailed;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    var instance = ResourceInstance.init();
    try std.testing.expectError(error.BodyFailed, handle([]const u8, &runtime, &instance, manager, demo));
}

test "nested same-shaped resource handles get distinct capability types" {
    const NoError = error{};
    const ResourceInstance = Instance(i32, NoError);
    const manager = struct {
        /// Acquire one dummy resource for the nested resource test.
        pub fn acquire() i32 {
            return 0;
        }

        /// Release the dummy resource for the nested resource test.
        pub fn release(_: i32) void {
            // Intentionally empty for this type-only test.
        }
    };
    const demo = struct {
        var runtime_ptr: ?*shift.Runtime = null;
        var inner_ptr: ?*const ResourceInstance = null;

        /// Open an inner resource handle and prove its capability differs from the outer one.
        pub fn outer(comptime OuterCap: type, _: anytype) shift.ResetError(NoError)!i32 {
            return try handle(i32, runtime_ptr.?, inner_ptr.?, manager, struct {
                /// Reject capability-type collapse inside the nested resource handle.
                pub fn body(comptime InnerCap: type, _: anytype) shift.ResetError(NoError)!i32 {
                    comptime if (OuterCap == InnerCap) {
                        @compileError("nested resource handles must receive distinct capability types");
                    };
                    return 0;
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    var outer_instance = ResourceInstance.init();
    var inner_instance = ResourceInstance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    const result = try handle(i32, &runtime, &outer_instance, manager, struct {
        /// Enter the outer resource handle and hand its capability inward.
        pub fn body(comptime OuterCap: type, ctx: anytype) shift.ResetError(NoError)!i32 {
            return try demo.outer(OuterCap, ctx);
        }
    });
    try std.testing.expectEqual(@as(i32, 0), result);
}
