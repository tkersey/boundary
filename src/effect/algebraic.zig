const cleanup = @import("cleanup.zig");
const family = @import("family.zig");
const kernel = @import("kernel.zig");
const raw = @import("../raw.zig");
const shift = @import("../root.zig");
const std = @import("std");

/// Read the current prompt-local state cell for a transform family.
pub inline fn readTransformState(
    comptime Cap: type,
    ctx: anytype,
) shift.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!family.ContextStateType(@TypeOf(ctx)) {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    const ContextType = family.ContextTypeFromPtr(@TypeOf(ctx));
    const family_impl = kernel.Family(ContextType.StateType, ContextType.AnswerType, ContextType.ErrorSetType);
    _ = ctx._cap;
    return family_impl.active_frame.?.state;
}

/// Replace the current prompt-local state cell for a transform family.
pub inline fn writeTransformState(
    comptime Cap: type,
    ctx: anytype,
    value: family.ContextStateType(@TypeOf(ctx)),
) shift.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!void {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    const ContextType = family.ContextTypeFromPtr(@TypeOf(ctx));
    const family_impl = kernel.Family(ContextType.StateType, ContextType.AnswerType, ContextType.ErrorSetType);
    _ = ctx._cap;
    family_impl.active_frame.?.state = value;
    return;
}

/// Apply one in-place mutation to a transform-family state cell and resume with its result.
pub inline fn mutateTransformState(
    comptime Cap: type,
    ctx: anytype,
    payload: anytype,
    comptime Mutation: type,
) shift.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!Mutation.Result {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    const ContextType = family.ContextTypeFromPtr(@TypeOf(ctx));
    const family_impl = kernel.Family(ContextType.StateType, ContextType.AnswerType, ContextType.ErrorSetType);
    _ = ctx._cap;
    return try Mutation.apply(&family_impl.active_frame.?.state, payload);
}

/// Assert the handler policy shape required by an optional family.
pub fn assertOptionalPolicyType(comptime ResumeType: type, comptime AnswerType: type, comptime ErrorSetType: type, comptime PolicyType: type) void {
    const DecisionType = shift.ResumeOrReturn(ResumeType, AnswerType);
    if (!family.hasDeclSafe(PolicyType, "resumeOrReturn")) {
        @compileError("optional policy must declare resumeOrReturn");
    }
    if (!family.hasDeclSafe(PolicyType, "afterResume")) {
        @compileError("optional policy must declare afterResume");
    }

    const ResumeOrReturnFn = @TypeOf(PolicyType.resumeOrReturn);
    if (ResumeOrReturnFn != fn () DecisionType and ResumeOrReturnFn != fn () shift.ResetError(ErrorSetType)!DecisionType) {
        @compileError("optional policy resumeOrReturn must have type fn () ResumeOrReturn or fn () ResetError(ErrorSet)!ResumeOrReturn");
    }

    const AfterResumeFn = @TypeOf(PolicyType.afterResume);
    if (AfterResumeFn != fn (ResumeType) AnswerType and AfterResumeFn != fn (ResumeType) shift.ResetError(ErrorSetType)!AnswerType) {
        @compileError("optional policy afterResume must have type fn (Resume) Answer or fn (Resume) ResetError(ErrorSet)!Answer");
    }
}

fn OptionalKernel(comptime ResumeType: type, comptime AnswerType: type, comptime ErrorSetType: type, comptime PolicyType: type) type {
    const PromptType = raw.Prompt(.resume_or_return, ResumeType, AnswerType, ErrorSetType);
    const DecisionType = shift.ResumeOrReturn(ResumeType, AnswerType);
    return struct {
        const Prompt = PromptType;
        var active_prompt: ?*const PromptType = null;
        var active_cleanup_marker: ?*cleanup.Frame = null;

        fn callResumeOrReturn() shift.ResetError(ErrorSetType)!DecisionType {
            const ResumeOrReturnFn = @TypeOf(PolicyType.resumeOrReturn);
            if (ResumeOrReturnFn == fn () DecisionType) return PolicyType.resumeOrReturn();
            return try PolicyType.resumeOrReturn();
        }

        fn callAfterResume(value: ResumeType) shift.ResetError(ErrorSetType)!AnswerType {
            const AfterResumeFn = @TypeOf(PolicyType.afterResume);
            if (AfterResumeFn == fn (ResumeType) AnswerType) return PolicyType.afterResume(value);
            return try PolicyType.afterResume(value);
        }

        fn request() shift.ResetError(ErrorSetType)!ResumeType {
            const handler = struct {
                /// Forward the policy decision into the raw optional-resumption protocol.
                pub fn resumeOrReturn() shift.ResetError(ErrorSetType)!DecisionType {
                    const decision = try callResumeOrReturn();
                    switch (decision) {
                        .return_now => |_| cleanup.unwindTo(active_cleanup_marker) catch |err| return @errorCast(err),
                        .resume_with => {},
                    }
                    return decision;
                }

                /// Complete the enclosing answer after one resumptive branch.
                pub fn afterResume(value: ResumeType) shift.ResetError(ErrorSetType)!AnswerType {
                    return try callAfterResume(value);
                }
            };

            return try raw.shift(ResumeType, PromptType, active_prompt.?, handler);
        }
    };
}

/// Perform the public `optional.request` operation through the generalized substrate.
pub inline fn optionalRequest(
    comptime Cap: type,
    ctx: anytype,
) shift.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!family.ContextStateType(@TypeOf(ctx)) {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    const ContextType = family.ContextTypeFromPtr(@TypeOf(ctx));
    comptime {
        if (!family.hasDeclSafe(ContextType.capability, "PolicyType")) {
            @compileError("optional capability does not carry a policy type");
        }
    }
    const PolicyType = ContextType.capability.PolicyType();
    comptime assertOptionalPolicyType(ContextType.StateType, ContextType.AnswerType, ContextType.ErrorSetType, PolicyType);
    const optional_impl = OptionalKernel(ContextType.StateType, ContextType.AnswerType, ContextType.ErrorSetType, PolicyType);
    _ = ctx._cap;
    return try optional_impl.request();
}

/// Run an optional family through the generalized substrate.
pub fn handleOptional(
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Policy: type,
    comptime Body: type,
) shift.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!AnswerType {
    const ResumeType = family.InstanceStateType(@TypeOf(instance));
    const ErrorSetType = family.InstanceErrorSetType(@TypeOf(instance));
    comptime assertOptionalPolicyType(ResumeType, AnswerType, ErrorSetType, Policy);
    const optional_impl = OptionalKernel(ResumeType, AnswerType, ErrorSetType, Policy);
    const capability_decls = struct {
        const body_tag = Body;

        /// Policy type used by this optional-resumption capability.
        pub fn PolicyType() type {
            return Policy;
        }
    };
    const runner = struct {
        threadlocal var active_prompt_token: usize = 0;
        threadlocal var active_runtime: ?*shift.Runtime = null;
        threadlocal var cleanup_marker: ?*cleanup.Frame = null;

        /// Run the body with a fresh exact context and the active optional prompt.
        pub fn run(comptime Cap: type, ctx: anytype) shift.ResetError(ErrorSetType)!AnswerType {
            const ContextType = family.ContextTypeFromPtr(@TypeOf(ctx));
            var prompt = optional_impl.Prompt{ .token = active_prompt_token };
            const invoker = struct {
                threadlocal var active_context: ?*ContextType = null;

                fn invoke() shift.ResetError(ErrorSetType)!ResumeType {
                    return try Body.body(Cap, active_context.?);
                }
            };

            const previous_prompt = optional_impl.active_prompt;
            const previous_context = invoker.active_context;
            optional_impl.active_prompt = &prompt;
            invoker.active_context = ctx;
            defer {
                optional_impl.active_prompt = previous_prompt;
                invoker.active_context = previous_context;
            }

            return try raw.reset(optional_impl.Prompt, active_runtime.?, &prompt, invoker.invoke);
        }
    };

    const previous_prompt_token = runner.active_prompt_token;
    const previous_runtime = runner.active_runtime;
    const previous_cleanup_marker = runner.cleanup_marker;
    const previous_opt_cleanup = optional_impl.active_cleanup_marker;
    runner.active_prompt_token = instance.prompt.token;
    runner.active_runtime = runtime;
    runner.cleanup_marker = cleanup.checkpoint();
    defer runner.active_prompt_token = previous_prompt_token;
    defer runner.active_runtime = previous_runtime;
    defer runner.cleanup_marker = previous_cleanup_marker;
    optional_impl.active_cleanup_marker = runner.cleanup_marker;
    defer optional_impl.active_cleanup_marker = previous_opt_cleanup;

    return try family.withCapability(family.ContextSpec(ResumeType, AnswerType, ErrorSetType), capability_decls, AnswerType, runner);
}

/// Assert the catch policy shape required by an exception family.
pub fn assertCatchType(comptime PayloadType: type, comptime AnswerType: type, comptime ErrorSetType: type, comptime CatchType: type) void {
    if (!family.hasDeclSafe(CatchType, "directReturn")) {
        @compileError("exception catch policy must declare directReturn");
    }
    const DirectReturnFn = @TypeOf(CatchType.directReturn);
    if (DirectReturnFn != fn (PayloadType) AnswerType and DirectReturnFn != fn (PayloadType) shift.ResetError(ErrorSetType)!AnswerType) {
        @compileError("exception catch policy directReturn must have type fn (Payload) Answer or fn (Payload) ResetError(ErrorSet)!Answer");
    }
}

fn ExceptionKernel(comptime PayloadType: type, comptime AnswerType: type, comptime ErrorSetType: type, comptime CatchType: type) type {
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

/// Throw one payload through the generalized direct-return substrate.
pub inline fn throwException(
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
    const exception_impl = ExceptionKernel(ContextType.StateType, ContextType.AnswerType, ContextType.ErrorSetType, CatchType);
    _ = ctx._cap;
    return try exception_impl.throw(payload);
}

/// Run an exception family through the generalized substrate.
pub fn handleException(
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Catch: type,
    comptime Body: type,
) shift.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!AnswerType {
    const PayloadType = family.InstanceStateType(@TypeOf(instance));
    const ErrorSetType = family.InstanceErrorSetType(@TypeOf(instance));
    comptime assertCatchType(PayloadType, AnswerType, ErrorSetType, Catch);
    const exception_impl = ExceptionKernel(PayloadType, AnswerType, ErrorSetType, Catch);
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

/// Assert the manager shape required by a bracketed resource family.
pub fn assertManagerType(comptime ResourceType: type, comptime ErrorSetType: type, comptime ManagerType: type) void {
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

fn ResourceKernel(comptime ResourceType: type, comptime AnswerType: type, comptime ErrorSetType: type, comptime ManagerType: type) type {
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
    };
}

/// Acquire one resource through the generalized bracketed resource substrate.
pub inline fn acquireResource(
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
    const resource_impl = ResourceKernel(ContextType.StateType, ContextType.AnswerType, ContextType.ErrorSetType, ManagerType);
    _ = ctx._cap;
    const frame = resource_impl.active_frame.?;
    const resource = try resource_impl.acquireOne();
    try frame.resources.append(frame.allocator, resource);
    return resource;
}

/// Run a resource family through the generalized substrate.
pub fn handleResource(
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Manager: type,
    comptime Body: type,
) shift.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!AnswerType {
    const ResourceType = family.InstanceStateType(@TypeOf(instance));
    const ErrorSetType = family.InstanceErrorSetType(@TypeOf(instance));
    comptime assertManagerType(ResourceType, ErrorSetType, Manager);
    const resource_impl = ResourceKernel(ResourceType, AnswerType, ErrorSetType, Manager);
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
    answer = invoker.invoke() catch |err| blk: {
        body_error = err;
        break :blk null;
    };

    const cleanup_marker = frame.cleanup_frame.previous;
    var cleanup_error: ?shift.ResetError(ErrorSetType) = null;
    cleanup.unwindTo(cleanup_marker) catch |err| {
        cleanup_error = @errorCast(err);
    };

    if (body_error) |err| return err;
    if (cleanup_error) |err| return err;
    return answer.?;
}
