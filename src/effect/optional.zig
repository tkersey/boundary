const algebraic = @import("algebraic.zig");
const effect_schema = @import("../effect_schema.zig");
const family = @import("family.zig");
const frontend = @import("frontend_support");
const lexical_with = @import("../internal/lexical_support.zig");
const lowered_machine = @import("lowered_machine");
const prompt_contract = @import("prompt_contract_support");
const ability = lowered_machine;
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

/// Handler optional handle used by `ability.effect handlers`.
pub fn LexicalHandle(
    comptime Cap: type,
    comptime ContextPtrType: type,
    comptime HandlersType: type,
    comptime PreviousEffType: type,
    comptime index: usize,
) type {
    const binder_index = index;
    return struct {
        /// Caller source location preserved across optional handler continuation re-entry.
        pub const caller_source = family.contextCallerSource(ContextPtrType);
        ctx: ?ContextPtrType,
        runtime: ?*ability.Runtime,
        handlers_ptr: ?*HandlersType,
        previous_eff: PreviousEffType,
        outputs_ptr: ?*lexical_with.OutputBundleType(HandlersType),

        /// Request the optional policy decision through the handler handle and resume through an explicit handler continuation.
        pub fn request(self: @This(), comptime Continuation: anytype) lowered_machine.ResetError(lexical_with.ChoiceFailureSet(family.ContextErrorSetType(ContextPtrType), Continuation, family.ContextStateType(ContextPtrType), lexical_with.ContinuationEffType(HandlersType, binder_index, PreviousEffType, @This())))!lexical_with.ChoiceAnswerTypeFor(Continuation, family.ContextStateType(ContextPtrType), lexical_with.ContinuationEffType(HandlersType, binder_index, PreviousEffType, @This())) {
            const Handle = @This();
            const ResumeType = family.ContextStateType(ContextPtrType);
            const ContinuationEff = lexical_with.ContinuationEffType(HandlersType, binder_index, PreviousEffType, Handle);
            const AnswerType = lexical_with.ChoiceAnswerTypeFor(Continuation, ResumeType, ContinuationEff);
            const ChoiceFailure = lexical_with.ChoiceFailureSet(family.ContextErrorSetType(ContextPtrType), Continuation, ResumeType, ContinuationEff);

            const request_state = struct {
                /// Caller source location preserved for the resumed optional continuation frame.
                pub const caller_source = Handle.caller_source;
                /// Re-enter the handler continuation after one optional resume.
                pub fn apply(current_handle: *Handle, value: ResumeType) lowered_machine.ResetError(ChoiceFailure)!AnswerType {
                    const frame = struct {
                        /// Caller source location forwarded into the rebuilt continuation chain.
                        pub const caller_source = Handle.caller_source;
                        runtime: *ability.Runtime,
                        handlers_ptr: *HandlersType,
                        previous_eff: PreviousEffType,
                        current_handle: Handle,
                        outputs_ptr: *lexical_with.OutputBundleType(HandlersType),
                    }{
                        .runtime = current_handle.runtime.?,
                        .handlers_ptr = current_handle.handlers_ptr.?,
                        .previous_eff = current_handle.previous_eff,
                        .current_handle = current_handle.*,
                        .outputs_ptr = current_handle.outputs_ptr.?,
                    };
                    return try lexical_with.continueChoice(
                        HandlersType,
                        binder_index,
                        frame,
                        Continuation,
                        value,
                    );
                }
            };

            var current_handle = self;
            var authored = algebraic.activeEngineContext(Cap, self.ctx.?).performProgramWithContext(Cap.RequestOp(), {}, &current_handle, request_state);
            if (comptime !(@hasDecl(@TypeOf(authored), "has_compiled_plan") and @TypeOf(authored).has_compiled_plan)) {
                @compileError("optional handler choice continuations must compile to supported direct execution; interpreted frontend fallback is unsupported");
            }
            return try authored.runCompiled(self.runtime.?);
        }
    };
}

/// Descriptor value used by `ability.effect handlers` for the built-in optional family.
pub fn LexicalDescriptor(comptime ResumeType: type, comptime ErrorSetType: type, comptime Policy: type) type {
    return struct {
        /// Shared error set carried by the handler optional descriptor.
        pub const ErrorSet = ErrorSetType;
        /// Resume value threaded through the handler optional context.
        pub const State = ResumeType;
        /// Optional handler descriptors do not surface an extra output value.
        pub const Output = void;

        /// Resolve the handler optional handle type for one exact context.
        pub fn HandleType(
            comptime Cap: type,
            comptime ContextPtrType: type,
            comptime HandlersType: type,
            comptime PreviousEffType: type,
            comptime index: usize,
        ) type {
            return LexicalHandle(Cap, ContextPtrType, HandlersType, PreviousEffType, index);
        }

        /// Bind one handler optional handle to the active exact context.
        pub fn bindLexical(
            self: @This(),
            comptime Cap: type,
            ctx: anytype,
            comptime HandlersType: type,
            comptime PreviousEffType: type,
            comptime index: usize,
        ) HandleType(Cap, @TypeOf(ctx), HandlersType, PreviousEffType, index) {
            _ = self;
            const lexical_state = lexical_with.activeLexicalState(ctx, HandlersType, PreviousEffType);
            return .{
                .ctx = ctx,
                .runtime = lexical_state.runtime,
                .handlers_ptr = lexical_state.handlers_ptr,
                .previous_eff = lexical_state.eff_value,
                .outputs_ptr = lexical_state.outputs_ptr,
            };
        }

        /// Return the shared binding schema for this handler descriptor under one requirement label.
        pub fn BindingSchema(comptime requirement_label: [:0]const u8) type {
            const policy_binding_handler = struct {
                /// Finalize the resumed optional answer through the policy after-hook.
                pub fn afterRequest(_: *@This(), answer: anytype) @TypeOf(Policy.afterResume(answer)) {
                    return Policy.afterResume(answer);
                }
            };
            return effect_schema.Binding(requirement_label, Schema(ResumeType, ErrorSetType, Policy), policy_binding_handler);
        }

        /// Run one handler optional descriptor through the continuation-taking handler optional family.
        pub fn run(self: @This(), comptime AnswerType: type, comptime RunErrorSetType: type, run_ctx: anytype, comptime Body: type) lowered_machine.ResetError(RunErrorSetType)!lexical_with.DescriptorResult(Output, AnswerType) {
            _ = self;
            var instance = family.InstanceWithMode(.resume_or_return, ResumeType, ErrorSetType).init();
            const result = try algebraic.handleOptionalLexicalWithErrorSet(AnswerType, RunErrorSetType, .{
                .runtime = run_ctx.runtime,
                .instance = &instance,
                .lexical_state = @constCast(run_ctx.lexical_state),
            }, Policy, Body);
            return .{
                .output = {},
                .value = result,
            };
        }
    };
}

/// Create one handler optional descriptor for `ability.effect handlers`.
pub fn use(comptime ResumeType: type, comptime Policy: type) LexicalDescriptor(ResumeType, PolicyErrorSet(Policy), Policy) {
    return .{};
}

/// Shared effect schema for the built-in optional family.
pub fn Schema(comptime ResumeType: type, comptime ErrorSetType: type, comptime Policy: type) type {
    return effect_schema.choice_policy(ResumeType, ErrorSetType, Policy);
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
    comptime Continuation: anytype,
) @TypeOf(algebraic.optionalRequestProgram(Cap, ctx, Continuation)) {
    return algebraic.optionalRequestProgram(Cap, ctx, Continuation);
}

/// Build one bound optional request program for the supplied continuation.
pub inline fn requestBoundProgram(
    comptime Cap: type,
    ctx: anytype,
    comptime Continuation: anytype,
) @TypeOf(algebraic.optionalRequestBoundProgram(Cap, ctx, Continuation)) {
    return algebraic.optionalRequestBoundProgram(Cap, ctx, Continuation);
}

/// Build one bound optional request program with one runtime continuation context.
pub inline fn requestBoundProgramWithContext(
    comptime Cap: type,
    ctx: anytype,
    continuation_ctx: anytype,
    comptime Continuation: type,
) @TypeOf(algebraic.optionalRequestBoundProgramWithContext(Cap, ctx, continuation_ctx, Continuation)) {
    return algebraic.optionalRequestBoundProgramWithContext(Cap, ctx, continuation_ctx, Continuation);
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
    runtime: *ability.Runtime,
    instance: anytype,
    comptime Policy: type,
    comptime Body: type,
) lowered_machine.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!AnswerType {
    return try algebraic.handleOptional(AnswerType, runtime, instance, Policy, Body);
}

/// Public `handleWithErrorSet` helper.
// zlinter-disable max_positional_args - public caller provenance and optional policy inputs stay explicit at this compatibility wrapper.
pub fn handleWithErrorSet(
    comptime AnswerType: type,
    comptime RunErrorSetType: type,
    runtime: *ability.Runtime,
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
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(requestBoundProgram(Cap, ctx, struct {
            /// Mark that the request continuation resumed unexpectedly.
            pub fn apply(_: i32) i32 {
                after_request = true;
                return 0;
            }
        })) {
            return requestBoundProgram(Cap, ctx, struct {
                /// Mark that the request continuation resumed unexpectedly.
                pub fn apply(_: i32) i32 {
                    after_request = true;
                    return 0;
                }
            });
        }
    };

    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = OptionalInstance.init();
    demo.after_request = false;
    const result = try handle([]const u8, &runtime, &instance, policy, demo);
    try std.testing.expectEqualStrings("result=early", result);
    try std.testing.expect(!demo.after_request);
}

test "optional requestProgram stays on the explicit frontend.Program surface" {
    const OptionalInstance = Instance(i32, error{});
    const policy = struct {
        /// Resume the explicit-program regression test with a known value.
        pub fn resumeOrReturn() prompt_contract.ResumeOrReturn(i32, []const u8) {
            return prompt_contract.ResumeOrReturn(i32, []const u8).resumeWith(41);
        }

        /// Convert the resumed explicit-program answer into the enclosing result.
        pub fn afterResume(value: i32) []const u8 {
            if (value != 42) unreachable;
            return "answer=42";
        }
    };
    const demo = struct {
        /// Store the optional request program on the explicit frontend.Program surface.
        pub fn program(comptime Cap: type, ctx: anytype) frontend.Program(prompt_contract.Prompt(
            .resume_or_return,
            family.ContextStateType(@TypeOf(ctx)),
            family.ContextAnswerType(@TypeOf(ctx)),
            family.ContextErrorSetType(@TypeOf(ctx)),
        )) {
            const explicit_program: frontend.Program(prompt_contract.Prompt(
                .resume_or_return,
                family.ContextStateType(@TypeOf(ctx)),
                family.ContextAnswerType(@TypeOf(ctx)),
                family.ContextErrorSetType(@TypeOf(ctx)),
            )) = requestProgram(Cap, ctx, struct {
                /// Increment the resumed optional answer through the explicit frontend.Program path.
                pub fn apply(current: i32) i32 {
                    return current + 1;
                }
            });
            return explicit_program;
        }
    };

    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = OptionalInstance.init();
    const result = try handle([]const u8, &runtime, &instance, policy, demo);
    try std.testing.expectEqualStrings("answer=42", result);
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
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(requestBoundProgram(Cap, ctx, struct {
            /// Increment the resumed optional answer.
            pub fn apply(current: i32) i32 {
                return current + 1;
            }
        })) {
            const ProgramType = @TypeOf(requestBoundProgram(Cap, ctx, struct {
                /// Increment the resumed optional answer through the compiled bound-program proof path.
                pub fn apply(current: i32) i32 {
                    return current + 1;
                }
            }));
            comptime {
                if (!ProgramType.has_compiled_plan) @compileError("optional bound program should expose supported compiled execution");
                const compiled_plan = ProgramType.compiledPlan().?;
                if (compiled_plan.functions[compiled_plan.entry_index].value_codec != .i32) {
                    @compileError("optional bound program should preserve the continuation resume codec in compiled execution");
                }
                if (compiled_plan.functions[compiled_plan.entry_index].result_codec.? != .string) {
                    @compileError("optional bound program should preserve the final answer codec separately in compiled execution");
                }
            }
            return requestBoundProgram(Cap, ctx, struct {
                /// Increment the resumed optional answer through the compiled bound-program path.
                pub fn apply(current: i32) i32 {
                    return current + 1;
                }
            });
        }
    };

    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = OptionalInstance.init();
    const result = try handle([]const u8, &runtime, &instance, policy, demo);
    try std.testing.expectEqualStrings("answer=42", result);
}

test "optional descriptor run uses the lexical backing handler" {
    const policy = struct {
        /// Resume the descriptor-backed optional request with a known value.
        pub fn resumeOrReturn() prompt_contract.ResumeOrReturn(i32, []const u8) {
            return prompt_contract.ResumeOrReturn(i32, []const u8).resumeWith(41);
        }

        /// Convert the resumed answer into the enclosing descriptor result.
        pub fn afterResume(value: i32) []const u8 {
            if (value != 42) unreachable;
            return "answer=42";
        }
    };
    const demo = struct {
        /// Request once and increment the resumed answer.
        pub fn program(comptime Cap: type, ctx: anytype) @TypeOf(requestBoundProgram(Cap, ctx, struct {
            /// Increment the resumed optional answer.
            pub fn apply(current: i32) i32 {
                return current + 1;
            }
        })) {
            return requestBoundProgram(Cap, ctx, struct {
                /// Increment the resumed optional answer.
                pub fn apply(current: i32) i32 {
                    return current + 1;
                }
            });
        }
    };

    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const descriptor = use(i32, policy);
    const result = try descriptor.run([]const u8, error{}, .{
        .runtime = &runtime,
        .lexical_state = @as(?*anyopaque, null),
    }, demo);
    try std.testing.expectEqual({}, result.output);
    try std.testing.expectEqualStrings("answer=42", result.value);
}

test "public optional handleWithErrorSet leaves caller provenance absent by default" {
    const NoError = error{};
    const OptionalInstance = Instance(i32, NoError);
    const policy = struct {
        /// Return early so the body can observe the public wrapper context directly.
        pub fn resumeOrReturn() prompt_contract.ResumeOrReturn(i32, []const u8) {
            return prompt_contract.ResumeOrReturn(i32, []const u8).returnNow("unused");
        }

        /// Preserve a placeholder resumed answer for shape completeness.
        pub fn afterResume(value: i32) []const u8 {
            _ = value;
            return "unused";
        }
    };

    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var instance = OptionalInstance.init();

    const result = try handleWithErrorSet([]const u8, NoError, &runtime, &instance, policy, struct {
        /// Report whether the source-compatible optional wrapper leaves caller provenance absent.
        pub fn body(comptime Cap: type, ctx: anytype) lowered_machine.ResetError(NoError)![]const u8 {
            _ = Cap;
            return if (@TypeOf(ctx.*).caller_source == null) "absent" else "present";
        }
    });

    try std.testing.expectEqualStrings("absent", result);
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
        var runtime_ptr: ?*ability.Runtime = null;
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

    var runtime = ability.Runtime.init(std.testing.allocator);
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
