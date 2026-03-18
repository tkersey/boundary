const algebraic = @import("algebraic.zig");
const family = @import("family.zig");
const frontend = @import("frontend_support");
const lexical_with = @import("../with_api.zig");
const lowered_machine = @import("lowered_machine");
const prompt_contract = @import("prompt_contract_support");
const shift = @import("../root.zig");
const std = @import("std");

fn ReturnTypeErrorSet(comptime ReturnType: type) type {
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.error_set,
        else => error{},
    };
}

fn PolicyErrorSet(comptime Policy: type) type {
    return ReturnTypeErrorSet(@typeInfo(@TypeOf(Policy.resumeOrReturn)).@"fn".return_type.?) ||
        ReturnTypeErrorSet(@typeInfo(@TypeOf(Policy.afterResume)).@"fn".return_type.?);
}

/// Prompt-backed effect instance for an optional-resumption family.
pub fn Instance(comptime ResumeType: type, comptime ErrorSetType: type) type {
    return family.InstanceWithMode(.resume_or_return, ResumeType, ErrorSetType);
}

/// Lexical optional handle used by `shift.with(...)`.
pub fn LexicalHandle(
    comptime Cap: type,
    comptime ContextPtrType: type,
    comptime HandlersType: type,
    comptime PreviousEffType: type,
    comptime index: usize,
) type {
    const binder_index = index;
    return struct {
        ctx: ?ContextPtrType,
        runtime: ?*shift.Runtime,
        handlers_ptr: ?*HandlersType,
        previous_eff: PreviousEffType,
        outputs_ptr: ?*lexical_with.OutputBundleType(HandlersType),

        /// Request the optional policy decision through the lexical handle and resume through an explicit lexical continuation.
        pub fn request(self: @This(), comptime Continuation: type) lowered_machine.ResetError(lexical_with.ChoiceExecutionErrorSet(family.ContextErrorSetType(ContextPtrType), Continuation, family.ContextStateType(ContextPtrType), lexical_with.ContinuationEffType(HandlersType, binder_index, PreviousEffType, @This())))!lexical_with.ChoiceAnswerTypeFor(Continuation, family.ContextStateType(ContextPtrType), lexical_with.ContinuationEffType(HandlersType, binder_index, PreviousEffType, @This())) {
            const Handle = @This();
            const ResumeType = family.ContextStateType(ContextPtrType);
            const ContinuationEff = lexical_with.ContinuationEffType(HandlersType, binder_index, PreviousEffType, Handle);
            const AnswerType = lexical_with.ChoiceAnswerTypeFor(Continuation, ResumeType, ContinuationEff);
            const ExecutionError = lexical_with.ChoiceExecutionErrorSet(family.ContextErrorSetType(ContextPtrType), Continuation, ResumeType, ContinuationEff);

            const request_state = struct {
                threadlocal var active_handle: ?Handle = null;

                /// Re-enter the lexical continuation after one optional resume.
                pub fn apply(value: ResumeType) lowered_machine.ResetError(ExecutionError)!AnswerType {
                    const current_handle = active_handle.?;
                    return try lexical_with.continueChoice(
                        HandlersType,
                        binder_index,
                        .{
                            .runtime = current_handle.runtime.?,
                            .handlers_ptr = current_handle.handlers_ptr.?,
                            .previous_eff = current_handle.previous_eff,
                            .current_handle = current_handle,
                            .outputs_ptr = current_handle.outputs_ptr.?,
                        },
                        Continuation,
                        value,
                    );
                }
            };

            const previous_handle = request_state.active_handle;
            request_state.active_handle = self;
            defer request_state.active_handle = previous_handle;

            const authored = algebraic.optionalRequestBoundProgram(Cap, self.ctx.?, request_state);
            authored.activate();
            defer authored.deactivate();
            return try frontend.run(self.runtime.?, authored.prompt, authored.program);
        }
    };
}

/// Descriptor value used by `shift.with(...)` for the built-in optional family.
pub fn LexicalDescriptor(comptime ResumeType: type, comptime ErrorSetType: type, comptime Policy: type) type {
    return struct {
        /// Shared error set carried by the lexical optional descriptor.
        pub const ErrorSet = ErrorSetType;
        /// Resume value threaded through the lexical optional context.
        pub const State = ResumeType;
        /// Optional lexical descriptors do not surface an extra output value.
        pub const Output = void;

        /// Resolve the lexical optional handle type for one exact context.
        pub fn HandleType(
            comptime Cap: type,
            comptime ContextPtrType: type,
            comptime HandlersType: type,
            comptime PreviousEffType: type,
            comptime index: usize,
        ) type {
            return LexicalHandle(Cap, ContextPtrType, HandlersType, PreviousEffType, index);
        }

        /// Bind one lexical optional handle to the active exact context.
        pub fn bindLexical(
            self: @This(),
            comptime Cap: type,
            ctx: anytype,
            runtime: *shift.Runtime,
            handlers_ptr: anytype,
            previous_eff: anytype,
            outputs_ptr: anytype,
            comptime index: usize,
        ) HandleType(Cap, @TypeOf(ctx), @TypeOf(handlers_ptr.*), @TypeOf(previous_eff), index) {
            _ = self;
            return .{
                .ctx = ctx,
                .runtime = runtime,
                .handlers_ptr = handlers_ptr,
                .previous_eff = previous_eff,
                .outputs_ptr = outputs_ptr,
            };
        }

        /// Run one lexical optional descriptor through the continuation-taking lexical optional family.
        pub fn run(self: @This(), comptime AnswerType: type, comptime RunErrorSetType: type, runtime: *shift.Runtime, comptime Body: type) lowered_machine.ResetError(RunErrorSetType)!lexical_with.DescriptorResult(Output, AnswerType) {
            _ = self;
            var instance = family.InstanceWithMode(.resume_or_return, ResumeType, ErrorSetType).init();
            const result = try algebraic.handleOptionalLexicalWithErrorSet(AnswerType, RunErrorSetType, runtime, &instance, Policy, Body);
            return .{
                .output = {},
                .value = result,
            };
        }
    };
}

/// Create one lexical optional descriptor for `shift.with(...)`.
pub fn use(comptime ResumeType: type, comptime Policy: type) LexicalDescriptor(ResumeType, PolicyErrorSet(Policy), Policy) {
    return .{};
}

/// Request a policy decision for the supplied capability and handled context.
pub inline fn request(
    comptime Cap: type,
    ctx: anytype,
) lowered_machine.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!family.ContextStateType(@TypeOf(ctx)) {
    return try algebraic.optionalRequest(Cap, ctx);
}

/// Build one explicit optional request program for the supplied continuation.
pub inline fn requestProgram(
    comptime Cap: type,
    ctx: anytype,
    comptime Continuation: type,
) @TypeOf(algebraic.optionalRequestProgram(Cap, ctx, Continuation)) {
    return algebraic.optionalRequestProgram(Cap, ctx, Continuation);
}

/// Build one explicit optional body program with no request operation.
pub inline fn computeProgram(
    comptime Cap: type,
    ctx: anytype,
    thunk: anytype,
) @TypeOf(algebraic.optionalComputeProgram(Cap, ctx, thunk)) {
    return algebraic.optionalComputeProgram(Cap, ctx, thunk);
}

/// Run an optional-resumption effect body and return the final handler answer.
pub fn handle(
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Policy: type,
    comptime Body: type,
) lowered_machine.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!AnswerType {
    return try algebraic.handleOptional(AnswerType, runtime, instance, Policy, Body);
}

pub fn handleWithErrorSet(
    comptime AnswerType: type,
    comptime RunErrorSetType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Policy: type,
    comptime Body: type,
) lowered_machine.ResetError(RunErrorSetType)!AnswerType {
    return try algebraic.handleOptionalWithErrorSet(AnswerType, RunErrorSetType, runtime, instance, Policy, Body);
}

test "optional instance shell stays prompt-sized" {
    const OptionalInstance = Instance(i32, error{});
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(OptionalInstance));
}

test "optional handle can return now without resuming the body tail" {
    const OptionalInstance = Instance(i32, error{});
    const policy = struct {
        /// Choose the direct-return branch for this optional-family test.
        pub fn resumeOrReturn() prompt_contract.ResumeOrReturn(i32, []const u8) {
            return prompt_contract.ResumeOrReturn(i32, []const u8).returnNow("result=early");
        }

        /// Preserve the late answer if this branch were ever resumed.
        pub fn afterResume(_: i32) []const u8 {
            return "result=late";
        }
    };
    const demo = struct {
        var after_request: bool = false;

        /// Attempt one optional request and prove the body tail never runs.
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(requestProgram(Cap, ctx, struct {
            /// Mark that the request continuation resumed unexpectedly.
            pub fn apply(_: i32) i32 {
                after_request = true;
                return 0;
            }
        })) {
            return requestProgram(Cap, ctx, struct {
                /// Mark that the request continuation resumed unexpectedly.
                pub fn apply(_: i32) i32 {
                    after_request = true;
                    return 0;
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = OptionalInstance.init();
    demo.after_request = false;
    const result = try handle([]const u8, &runtime, &instance, policy, demo);
    try std.testing.expectEqualStrings("result=early", result);
    try std.testing.expect(!demo.after_request);
}

test "optional handle can resume and transform the resumed answer" {
    const OptionalInstance = Instance(i32, error{});
    const policy = struct {
        /// Resume the optional request with a known value.
        pub fn resumeOrReturn() prompt_contract.ResumeOrReturn(i32, []const u8) {
            return prompt_contract.ResumeOrReturn(i32, []const u8).resumeWith(41);
        }

        /// Convert the resumed answer into the enclosing result.
        pub fn afterResume(value: i32) []const u8 {
            if (value != 42) unreachable;
            return "answer=42";
        }
    };
    const demo = struct {
        /// Request once and increment the resumed answer.
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(requestProgram(Cap, ctx, struct {
            /// Increment the resumed optional answer.
            pub fn apply(current: i32) i32 {
                return current + 1;
            }
        })) {
            return requestProgram(Cap, ctx, struct {
                /// Increment the resumed optional answer.
                pub fn apply(current: i32) i32 {
                    return current + 1;
                }
            });
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
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
        pub fn resumeOrReturn() prompt_contract.ResumeOrReturn(i32, i32) {
            return prompt_contract.ResumeOrReturn(i32, i32).resumeWith(0);
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
        pub fn outer(comptime OuterCap: type, _: anytype) lowered_machine.ResetError(NoError)!i32 {
            return try handle(i32, runtime_ptr.?, inner_ptr.?, policy, struct {
                /// Reject capability-type collapse inside the nested handle.
                pub fn program(comptime InnerCap: type, inner_ctx: anytype) @TypeOf(computeProgram(InnerCap, inner_ctx, struct {
                    /// Return a neutral value from the nested optional body.
                    pub fn run() i32 {
                        return 0;
                    }
                }.run)) {
                    comptime if (OuterCap == InnerCap) {
                        @compileError("nested optional handles must receive distinct capability types");
                    };
                    return computeProgram(InnerCap, inner_ctx, struct {
                        /// Return a neutral value from the nested optional body.
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
    var outer_instance = OptionalInstance.init();
    var inner_instance = OptionalInstance.init();
    demo.runtime_ptr = &runtime;
    demo.inner_ptr = &inner_instance;
    const result = try handle(i32, &runtime, &outer_instance, policy, struct {
        /// Enter the outer optional handle and hand its capability inward.
        pub fn program(comptime OuterCap: type, ctx: anytype) @TypeOf(computeProgram(OuterCap, ctx, struct {
            /// Re-enter the nested optional witness through the outer capability.
            pub fn run() lowered_machine.ResetError(NoError)!i32 {
                return try demo.outer(OuterCap, {});
            }
        }.run)) {
            return computeProgram(OuterCap, ctx, struct {
                /// Re-enter the nested optional witness through the outer capability.
                pub fn run() lowered_machine.ResetError(NoError)!i32 {
                    return try demo.outer(OuterCap, {});
                }
            }.run);
        }
    });
    try std.testing.expectEqual(@as(i32, 0), result);
}
