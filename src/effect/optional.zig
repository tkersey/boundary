const cleanup = @import("cleanup.zig");
const family = @import("family.zig");
const raw = @import("../raw.zig");
const shift = @import("../root.zig");
const std = @import("std");

/// Prompt-backed effect instance for an optional-resumption family.
pub fn Instance(comptime ResumeType: type, comptime ErrorSetType: type) type {
    return family.InstanceWithMode(.resume_or_return, ResumeType, ErrorSetType);
}

fn assertPolicyType(comptime ResumeType: type, comptime AnswerType: type, comptime ErrorSetType: type, comptime PolicyType: type) void {
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

fn Kernel(comptime ResumeType: type, comptime AnswerType: type, comptime ErrorSetType: type, comptime PolicyType: type) type {
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

/// Request a policy decision for the supplied capability and handled context.
pub inline fn request(
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
    comptime assertPolicyType(ContextType.StateType, ContextType.AnswerType, ContextType.ErrorSetType, PolicyType);
    const optional_impl = Kernel(ContextType.StateType, ContextType.AnswerType, ContextType.ErrorSetType, PolicyType);
    _ = ctx._cap;
    return try optional_impl.request();
}

/// Run an optional-resumption effect body and return the final handler answer.
pub fn handle(
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Policy: type,
    comptime Body: type,
) shift.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!AnswerType {
    const ResumeType = family.InstanceStateType(@TypeOf(instance));
    const ErrorSetType = family.InstanceErrorSetType(@TypeOf(instance));
    comptime assertPolicyType(ResumeType, AnswerType, ErrorSetType, Policy);
    const optional_impl = Kernel(ResumeType, AnswerType, ErrorSetType, Policy);
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

test "optional instance shell stays prompt-sized" {
    const NoError = error{};
    const OptionalInstance = Instance(i32, NoError);
    const PromptShell = raw.Prompt(.resume_or_return, void, void, NoError);
    try std.testing.expectEqual(@sizeOf(PromptShell), @sizeOf(OptionalInstance));
}

test "optional handle can return now without resuming the body tail" {
    const NoError = error{};
    const OptionalInstance = Instance(i32, NoError);
    const policy = struct {
        /// Choose the direct-return branch for this optional-family test.
        pub fn resumeOrReturn() shift.ResumeOrReturn(i32, []const u8) {
            return shift.ResumeOrReturn(i32, []const u8).returnNow("result=early");
        }

        /// Preserve the late answer if this branch were ever resumed.
        pub fn afterResume(_: i32) []const u8 {
            return "result=late";
        }
    };
    const demo = struct {
        var after_request: bool = false;

        /// Attempt one optional request and prove the body tail never runs.
        pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)!i32 {
            _ = try request(Cap, ctx);
            after_request = true;
            return 0;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    var instance = OptionalInstance.init();
    demo.after_request = false;
    const result = try handle([]const u8, &runtime, &instance, policy, demo);
    try std.testing.expectEqualStrings("result=early", result);
    try std.testing.expect(!demo.after_request);
}

test "optional handle can resume and transform the resumed answer" {
    const NoError = error{};
    const OptionalInstance = Instance(i32, NoError);
    const policy = struct {
        /// Resume the optional request with a known value.
        pub fn resumeOrReturn() shift.ResumeOrReturn(i32, []const u8) {
            return shift.ResumeOrReturn(i32, []const u8).resumeWith(41);
        }

        /// Convert the resumed answer into the enclosing result.
        pub fn afterResume(value: i32) []const u8 {
            if (value != 42) unreachable;
            return "answer=42";
        }
    };
    const demo = struct {
        /// Request once and increment the resumed answer.
        pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)!i32 {
            const current = try request(Cap, ctx);
            return current + 1;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    var instance = OptionalInstance.init();
    const result = try handle([]const u8, &runtime, &instance, policy, demo);
    try std.testing.expectEqualStrings("answer=42", result);
}

test "nested same-shaped optional handles get distinct capability types" {
    const NoError = error{};
    const OptionalInstance = Instance(i32, NoError);
    const policy = struct {
        /// Resume the nested optional test with a neutral value.
        pub fn resumeOrReturn() shift.ResumeOrReturn(i32, i32) {
            return shift.ResumeOrReturn(i32, i32).resumeWith(0);
        }

        /// Preserve the resumed answer in the nested optional test.
        pub fn afterResume(value: i32) i32 {
            return value;
        }
    };
    const demo = struct {
        var runtime_ptr: ?*shift.Runtime = null;
        var inner_ptr: ?*const OptionalInstance = null;

        /// Open an inner optional handle and compare its capability type.
        pub fn outer(comptime OuterCap: type, _: anytype) shift.ResetError(NoError)!i32 {
            return try handle(i32, runtime_ptr.?, inner_ptr.?, policy, struct {
                /// Reject capability-type collapse inside the nested handle.
                pub fn body(comptime InnerCap: type, _: anytype) shift.ResetError(NoError)!i32 {
                    comptime if (OuterCap == InnerCap) {
                        @compileError("nested optional handles must receive distinct capability types");
                    };
                    return 0;
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator, .{});
    defer runtime.deinit();
    var outer_instance = OptionalInstance.init();
    var inner_instance = OptionalInstance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    const result = try handle(i32, &runtime, &outer_instance, policy, struct {
        /// Enter the outer optional handle and hand its capability inward.
        pub fn body(comptime OuterCap: type, ctx: anytype) shift.ResetError(NoError)!i32 {
            return try demo.outer(OuterCap, ctx);
        }
    });
    try std.testing.expectEqual(@as(i32, 0), result);
}
