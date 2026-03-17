const choice = @import("choice.zig");
const cleanup = @import("cleanup.zig");
const family = @import("family.zig");
const frontend = @import("frontend_support");
const internal = @import("../internal/algebraic_engine.zig");
const lowered_machine = @import("lowered_machine");
const prompt_contract = @import("prompt_contract_support");
const shift = @import("../root.zig");
const std = @import("std");

fn activeEngineContext(comptime Cap: type, ctx: anytype) *Cap.EngineContextType() {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    const ContextType = family.ContextTypeFromPtr(@TypeOf(ctx));
    const EngineContextType = Cap.EngineContextType();
    const shim = family.EngineShim(ContextType, EngineContextType);
    _ = ctx._cap;
    return shim.active_engine.?;
}

fn computeProgramForPrompt(
    comptime Cap: type,
    ctx: anytype,
    comptime PromptType: type,
    thunk: anytype,
) frontend.Program(PromptType) {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    const ContextType = family.ContextTypeFromPtr(@TypeOf(ctx));
    const shim = family.ProgramShimFor(ContextType);
    const ThunkType = @TypeOf(thunk);
    _ = ctx._cap;
    return frontend.computeProgram(PromptType, struct {
        fn invoke() lowered_machine.ResetError(ContextType.ErrorSetType)!ContextType.AnswerType {
            switch (@typeInfo(ThunkType)) {
                .@"fn" => {
                    const params = @typeInfo(ThunkType).@"fn".params;
                    const ReturnType = @typeInfo(ThunkType).@"fn".return_type.?;
                    if (params.len == 0) {
                        if (@typeInfo(ReturnType) != .error_union) return thunk();
                        return try thunk();
                    }
                    if (@typeInfo(ReturnType) != .error_union) return thunk(Cap, shim.active_context.?);
                    return try thunk(Cap, shim.active_context.?);
                },
                .pointer => |pointer| {
                    if (@typeInfo(pointer.child) == .@"fn") {
                        const params = @typeInfo(pointer.child).@"fn".params;
                        const ReturnType = @typeInfo(pointer.child).@"fn".return_type.?;
                        if (params.len == 0) {
                            if (@typeInfo(ReturnType) != .error_union) return thunk();
                            return try thunk();
                        }
                        if (@typeInfo(ReturnType) != .error_union) return thunk(Cap, shim.active_context.?);
                        return try thunk(Cap, shim.active_context.?);
                    }
                },
                else => {},
            }

            const RunFn = @TypeOf(thunk.run);
            const params = @typeInfo(RunFn).@"fn".params;
            const ReturnType = @typeInfo(RunFn).@"fn".return_type.?;
            if (params.len == 0) {
                if (@typeInfo(ReturnType) != .error_union) return thunk.run();
                return try thunk.run();
            }
            if (@typeInfo(ReturnType) != .error_union) return thunk.run(Cap, shim.active_context.?);
            return try thunk.run(Cap, shim.active_context.?);
        }
    }.invoke);
}

fn runWithSealedEngine(
    comptime EngineContract: type,
    config: anytype,
    comptime Body: type,
) lowered_machine.ResetError(EngineContract.ErrorSetTypeV)!EngineContract.AnswerTypeV {
    const PromptType = EngineContract.PromptTypeV;
    const StateType = EngineContract.StateTypeV;
    const AnswerType = EngineContract.AnswerTypeV;
    const ErrorSetType = EngineContract.ErrorSetTypeV;
    const capability_decls = EngineContract.capability_decls;
    const EnginePtrType = @TypeOf(config.engine_ctx);
    const EngineContextType = switch (@typeInfo(EnginePtrType)) {
        .pointer => |pointer| pointer.child,
        else => @compileError("expected engine context pointer"),
    };

    const runner = struct {
        threadlocal var active_runtime: ?*shift.Runtime = null;
        threadlocal var active_prompt_token: prompt_contract.PromptToken = 0;
        threadlocal var active_engine_ctx: ?*EngineContextType = null;

        /// Run one sealed effect body with both exact context and shared engine context installed.
        pub fn run(comptime Cap: type, ctx: anytype) lowered_machine.ResetError(ErrorSetType)!AnswerType {
            const ContextType = family.ContextTypeFromPtr(@TypeOf(ctx));
            const context_shim = family.ProgramShimFor(ContextType);
            const engine_shim = family.EngineShim(ContextType, EngineContextType);
            var prompt = PromptType{ .token = active_prompt_token };

            const previous_context = context_shim.active_context;
            const previous_engine = engine_shim.active_engine;
            context_shim.active_context = ctx;
            engine_shim.active_engine = active_engine_ctx;
            defer {
                context_shim.active_context = previous_context;
                engine_shim.active_engine = previous_engine;
            }

            if (comptime family.hasDeclSafe(Body, "program")) {
                return try frontend.run(active_runtime.?, &prompt, Body.program(Cap, ctx));
            }
            if (comptime family.hasDeclSafe(Body, "body")) {
                return try frontend.run(active_runtime.?, &prompt, computeProgramForPrompt(Cap, ctx, PromptType, Body.body));
            }
            @compileError("effect body must declare program or body");
        }
    };

    const previous_runtime = runner.active_runtime;
    const previous_prompt_token = runner.active_prompt_token;
    const previous_engine_ctx = runner.active_engine_ctx;
    runner.active_runtime = config.runtime;
    runner.active_prompt_token = config.prompt_token;
    runner.active_engine_ctx = config.engine_ctx;
    defer runner.active_runtime = previous_runtime;
    defer runner.active_prompt_token = previous_prompt_token;
    defer runner.active_engine_ctx = previous_engine_ctx;

    return try family.withCapability(family.ContextSpec(StateType, AnswerType, ErrorSetType), capability_decls, AnswerType, runner);
}

/// Read the current state value through the shared algebraic engine.
pub inline fn stateGet(
    comptime Cap: type,
    ctx: anytype,
) lowered_machine.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!family.ContextStateType(@TypeOf(ctx)) {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    return try activeEngineContext(Cap, ctx).perform(Cap.GetOp(), {});
}

/// Replace the current state value through the shared algebraic engine.
pub inline fn stateSet(
    comptime Cap: type,
    ctx: anytype,
    value: family.ContextStateType(@TypeOf(ctx)),
) lowered_machine.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!void {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    return try activeEngineContext(Cap, ctx).perform(Cap.SetOp(), value);
}

/// Run a state family through the shared algebraic engine.
pub fn handleState(
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    initial_state: family.InstanceStateType(@TypeOf(instance)),
    comptime Body: type,
) lowered_machine.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!family.HandleResult(
    family.InstanceStateType(@TypeOf(instance)),
    AnswerType,
) {
    const StateType = family.InstanceStateType(@TypeOf(instance));
    const ErrorSetType = family.InstanceErrorSetType(@TypeOf(instance));
    const get_state_op = internal.TransformOp("__effect_state_get", void, StateType);
    const set_state_op = internal.TransformOp("__effect_state_set", StateType, void);
    const hidden_program = internal.Program(AnswerType, AnswerType, ErrorSetType, .{ get_state_op, set_state_op });

    var state_cell = initial_state;
    const specs = .{
        internal.handleDirectTransform(get_state_op, &state_cell, struct {
            /// Read the current state cell into the resumed path.
            pub fn resumeValue(state_ptr: *StateType, _: void) StateType {
                return state_ptr.*;
            }

            /// Preserve the enclosing answer unchanged after a state read.
            pub fn afterResume(_: *StateType, answer: AnswerType) AnswerType {
                return answer;
            }
        }),
        internal.handleDirectTransform(set_state_op, &state_cell, struct {
            /// Replace the current state cell from the payload.
            pub fn resumeValue(state_ptr: *StateType, payload: StateType) void {
                state_ptr.* = payload;
            }

            /// Preserve the enclosing answer unchanged after a state write.
            pub fn afterResume(_: *StateType, answer: AnswerType) AnswerType {
                return answer;
            }
        }),
    };
    const configured = hidden_program.handlers(specs);
    const GeneratedEngineContextType = @TypeOf(configured).Context;
    const BindingsType = internal.BindingChainFor(@TypeOf(specs), AnswerType, AnswerType, ErrorSetType);
    var bindings = BindingsType.initWithToken(specs, instance.prompt.token);
    var engine_ctx = GeneratedEngineContextType{ .bindings = &bindings };

    const capability_meta = struct {
        const body_tag = Body;

        /// Shared engine context type used by the exact state context.
        pub fn EngineContextType() type {
            return GeneratedEngineContextType;
        }

        /// Hidden read op used by the exact state context.
        pub fn GetOp() type {
            return get_state_op;
        }

        /// Hidden write op used by the exact state context.
        pub fn SetOp() type {
            return set_state_op;
        }
    };

    const contract = struct {
        const PromptTypeV = prompt_contract.Prompt(.resume_then_transform, AnswerType, AnswerType, ErrorSetType);
        const StateTypeV = StateType;
        const AnswerTypeV = AnswerType;
        const ErrorSetTypeV = ErrorSetType;
        const capability_decls = capability_meta;
    };
    const value = try runWithSealedEngine(contract, .{ .runtime = runtime, .prompt_token = instance.prompt.token, .engine_ctx = &engine_ctx }, Body);
    return .{ .state = state_cell, .value = value };
}

/// Read the current environment value through the shared algebraic engine.
pub inline fn readerAsk(
    comptime Cap: type,
    ctx: anytype,
) lowered_machine.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!family.ContextStateType(@TypeOf(ctx)) {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    return try activeEngineContext(Cap, ctx).perform(Cap.AskOp(), {});
}

/// Run a reader family through the shared algebraic engine.
pub fn handleReader(
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    environment: family.InstanceStateType(@TypeOf(instance)),
    comptime Body: type,
) lowered_machine.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!AnswerType {
    const StateType = family.InstanceStateType(@TypeOf(instance));
    const ErrorSetType = family.InstanceErrorSetType(@TypeOf(instance));
    const reader_ask_op = internal.TransformOp("__effect_reader_ask", void, StateType);
    const hidden_program = internal.Program(AnswerType, AnswerType, ErrorSetType, .{reader_ask_op});

    var env_value = environment;
    const specs = .{
        internal.handleDirectTransform(reader_ask_op, &env_value, struct {
            /// Read the current reader environment into the resumed path.
            pub fn resumeValue(env_ptr: *StateType, _: void) StateType {
                return env_ptr.*;
            }

            /// Preserve the enclosing answer unchanged after a reader ask.
            pub fn afterResume(_: *StateType, answer: AnswerType) AnswerType {
                return answer;
            }
        }),
    };
    const configured = hidden_program.handlers(specs);
    const GeneratedEngineContextType = @TypeOf(configured).Context;
    const BindingsType = internal.BindingChainFor(@TypeOf(specs), AnswerType, AnswerType, ErrorSetType);
    var bindings = BindingsType.initWithToken(specs, instance.prompt.token);
    var engine_ctx = GeneratedEngineContextType{ .bindings = &bindings };

    const capability_meta = struct {
        const body_tag = Body;

        /// Shared engine context type used by the exact reader context.
        pub fn EngineContextType() type {
            return GeneratedEngineContextType;
        }

        /// Hidden ask op used by the exact reader context.
        pub fn AskOp() type {
            return reader_ask_op;
        }
    };

    const contract = struct {
        const PromptTypeV = prompt_contract.Prompt(.resume_then_transform, AnswerType, AnswerType, ErrorSetType);
        const StateTypeV = StateType;
        const AnswerTypeV = AnswerType;
        const ErrorSetTypeV = ErrorSetType;
        const capability_decls = capability_meta;
    };
    return try runWithSealedEngine(contract, .{ .runtime = runtime, .prompt_token = instance.prompt.token, .engine_ctx = &engine_ctx }, Body);
}

/// Append one item through the shared algebraic engine.
pub inline fn writerTell(
    comptime Cap: type,
    ctx: anytype,
    item: anytype,
) lowered_machine.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!void {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    return try activeEngineContext(Cap, ctx).perform(Cap.TellOp(), item);
}

/// Run a writer family through the shared algebraic engine.
pub fn handleWriter(
    comptime WriterContract: type,
    runtime: *shift.Runtime,
    instance: anytype,
    allocator: std.mem.Allocator,
    comptime Body: type,
) lowered_machine.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!struct {
    items: []WriterContract.Item,
    value: WriterContract.Answer,
} {
    const ItemType = WriterContract.Item;
    const AnswerType = WriterContract.Answer;
    const WriterStateType = WriterContract.WriterStateType;
    const ErrorSetType = family.InstanceErrorSetType(@TypeOf(instance));
    const writer_tell_op = internal.TransformOp("__effect_writer_tell", ItemType, void);
    const hidden_program = internal.Program(AnswerType, AnswerType, ErrorSetType, .{writer_tell_op});

    var writer_state = WriterStateType.init(allocator);
    errdefer writer_state.deinit();
    const specs = .{
        internal.handleDirectTransform(writer_tell_op, &writer_state, struct {
            /// Append one writer item into the active writer state.
            pub fn resumeValue(state_ptr: *WriterStateType, payload: ItemType) lowered_machine.ResetError(ErrorSetType)!void {
                try state_ptr.append(payload);
            }

            /// Preserve the enclosing answer unchanged after a writer append.
            pub fn afterResume(_: *WriterStateType, answer: AnswerType) AnswerType {
                return answer;
            }
        }),
    };
    const configured = hidden_program.handlers(specs);
    const GeneratedEngineContextType = @TypeOf(configured).Context;
    const BindingsType = internal.BindingChainFor(@TypeOf(specs), AnswerType, AnswerType, ErrorSetType);
    var bindings = BindingsType.initWithToken(specs, instance.prompt.token);
    var engine_ctx = GeneratedEngineContextType{ .bindings = &bindings };

    const capability_meta = struct {
        const body_tag = Body;

        /// Shared engine context type used by the exact writer context.
        pub fn EngineContextType() type {
            return GeneratedEngineContextType;
        }

        /// Hidden tell op used by the exact writer context.
        pub fn TellOp() type {
            return writer_tell_op;
        }
    };

    const contract = struct {
        const PromptTypeV = prompt_contract.Prompt(.resume_then_transform, AnswerType, AnswerType, ErrorSetType);
        const StateTypeV = WriterStateType;
        const AnswerTypeV = AnswerType;
        const ErrorSetTypeV = ErrorSetType;
        const capability_decls = capability_meta;
    };
    const value = try runWithSealedEngine(contract, .{ .runtime = runtime, .prompt_token = instance.prompt.token, .engine_ctx = &engine_ctx }, Body);
    const items = try writer_state.intoOwnedSlice();
    return .{ .items = items, .value = value };
}

/// Assert the handler policy shape required by an optional family.
pub fn assertOptionalPolicyType(comptime ResumeType: type, comptime AnswerType: type, comptime ErrorSetType: type, comptime PolicyType: type) void {
    const DecisionType = choice.Decision(ResumeType, AnswerType);
    if (!family.hasDeclSafe(PolicyType, "resumeOrReturn")) {
        @compileError("optional policy must declare resumeOrReturn");
    }
    if (!family.hasDeclSafe(PolicyType, "afterResume")) {
        @compileError("optional policy must declare afterResume");
    }

    const ResumeOrReturnFn = @TypeOf(PolicyType.resumeOrReturn);
    if (ResumeOrReturnFn != fn () DecisionType and ResumeOrReturnFn != fn () lowered_machine.ResetError(ErrorSetType)!DecisionType) {
        @compileError("optional policy resumeOrReturn must have type fn () effect.choice.Decision or fn () ResetError(ErrorSet)!effect.choice.Decision");
    }

    const AfterResumeFn = @TypeOf(PolicyType.afterResume);
    if (AfterResumeFn != fn (ResumeType) AnswerType and AfterResumeFn != fn (ResumeType) lowered_machine.ResetError(ErrorSetType)!AnswerType) {
        @compileError("optional policy afterResume must have type fn (Resume) Answer or fn (Resume) ResetError(ErrorSet)!Answer");
    }
}

/// Assert the lexical policy shape required by a continuation-taking optional family.
pub fn assertOptionalLexicalPolicyType(comptime ResumeType: type, comptime AnswerType: type, comptime ErrorSetType: type, comptime PolicyType: type) void {
    const DecisionType = choice.Decision(ResumeType, AnswerType);
    if (!family.hasDeclSafe(PolicyType, "resumeOrReturn")) {
        @compileError("lexical optional policy must declare resumeOrReturn");
    }
    if (!family.hasDeclSafe(PolicyType, "afterResume")) {
        @compileError("lexical optional policy must declare afterResume");
    }

    const ResumeOrReturnFn = @TypeOf(PolicyType.resumeOrReturn);
    if (ResumeOrReturnFn != fn () DecisionType and ResumeOrReturnFn != fn () lowered_machine.ResetError(ErrorSetType)!DecisionType) {
        @compileError("lexical optional policy resumeOrReturn must have type fn () effect.choice.Decision or fn () ResetError(ErrorSet)!effect.choice.Decision");
    }

    const AfterFn = @TypeOf(PolicyType.afterResume);
    if (AfterFn != fn (AnswerType) AnswerType and AfterFn != fn (AnswerType) lowered_machine.ResetError(ErrorSetType)!AnswerType) {
        @compileError("lexical optional policy afterResume must have type fn (Answer) Answer or fn (Answer) ResetError(ErrorSet)!Answer");
    }
}

/// Perform the public `optional.request` operation through the shared algebraic engine.
pub inline fn optionalRequest(
    comptime Cap: type,
    ctx: anytype,
) lowered_machine.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!family.ContextStateType(@TypeOf(ctx)) {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    return try activeEngineContext(Cap, ctx).perform(Cap.RequestOp(), {});
}

/// Build one explicit optional request program for the supplied capability and continuation.
pub inline fn optionalRequestProgram(
    comptime Cap: type,
    ctx: anytype,
    comptime Continuation: type,
) frontend.Program(prompt_contract.Prompt(
    .resume_or_return,
    family.ContextStateType(@TypeOf(ctx)),
    family.ContextAnswerType(@TypeOf(ctx)),
    family.ContextErrorSetType(@TypeOf(ctx)),
)) {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    return activeEngineContext(Cap, ctx).bindings.bindingPtr(0).directProgram({}, Continuation);
}

/// Build one bound optional request program for the supplied capability and continuation.
pub inline fn optionalRequestBoundProgram(
    comptime Cap: type,
    ctx: anytype,
    comptime Continuation: type,
) @TypeOf(activeEngineContext(Cap, ctx).performProgram(Cap.RequestOp(), {}, Continuation)) {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    return activeEngineContext(Cap, ctx).performProgram(Cap.RequestOp(), {}, Continuation);
}

/// Build one explicit optional body program with no request operation.
pub inline fn optionalComputeProgram(
    comptime Cap: type,
    ctx: anytype,
    thunk: anytype,
) frontend.Program(prompt_contract.Prompt(
    .resume_or_return,
    family.ContextStateType(@TypeOf(ctx)),
    family.ContextAnswerType(@TypeOf(ctx)),
    family.ContextErrorSetType(@TypeOf(ctx)),
)) {
    const ContextType = family.ContextTypeFromPtr(@TypeOf(ctx));
    const PromptType = prompt_contract.Prompt(.resume_or_return, ContextType.StateType, ContextType.AnswerType, ContextType.ErrorSetType);
    return computeProgramForPrompt(Cap, ctx, PromptType, thunk);
}

/// Run an optional family through the shared algebraic engine.
pub fn handleOptional(
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Policy: type,
    comptime Body: type,
) lowered_machine.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!AnswerType {
    const ResumeType = family.InstanceStateType(@TypeOf(instance));
    const ErrorSetType = family.InstanceErrorSetType(@TypeOf(instance));
    comptime assertOptionalPolicyType(ResumeType, AnswerType, ErrorSetType, Policy);

    const optional_request_op = internal.ChoiceOp("__effect_optional_request", void, ResumeType);
    const hidden_program = internal.Program(ResumeType, AnswerType, ErrorSetType, .{optional_request_op});
    const OptionalState = struct {
        cleanup_marker: ?*cleanup.Frame,
    };
    const cleanup_marker = cleanup.checkpoint();
    const specs = .{
        internal.handleChoice(optional_request_op, OptionalState{ .cleanup_marker = cleanup_marker }, struct {
            /// Choose whether the optional request resumes or returns now.
            pub fn resumeOrReturn(_: OptionalState, _: void) lowered_machine.ResetError(ErrorSetType)!choice.Decision(ResumeType, AnswerType) {
                const DecisionFn = @TypeOf(Policy.resumeOrReturn);
                if (DecisionFn == fn () choice.Decision(ResumeType, AnswerType)) return Policy.resumeOrReturn();
                return try Policy.resumeOrReturn();
            }

            /// Finish the optional request by applying cleanup and the policy's after-resume path.
            pub fn afterResume(state: OptionalState, value: ResumeType) lowered_machine.ResetError(ErrorSetType)!AnswerType {
                if (cleanup.checkpoint() != state.cleanup_marker) {
                    cleanup.unwindTo(state.cleanup_marker) catch |err| return @errorCast(err);
                }
                const AfterFn = @TypeOf(Policy.afterResume);
                if (AfterFn == fn (ResumeType) AnswerType) return Policy.afterResume(value);
                return try Policy.afterResume(value);
            }
        }),
    };
    const configured = hidden_program.handlers(specs);
    const GeneratedEngineContextType = @TypeOf(configured).Context;
    const BindingsType = internal.BindingChainFor(@TypeOf(specs), ResumeType, AnswerType, ErrorSetType);
    var bindings = BindingsType.initWithToken(specs, instance.prompt.token);
    var engine_ctx = GeneratedEngineContextType{ .bindings = &bindings };

    const capability_meta = struct {
        const body_tag = Body;

        /// Hidden policy metadata used by the exact optional context.
        pub fn PolicyType() type {
            return Policy;
        }

        /// Shared engine context type used by the exact optional context.
        pub fn EngineContextType() type {
            return GeneratedEngineContextType;
        }

        /// Hidden request op used by the exact optional context.
        pub fn RequestOp() type {
            return optional_request_op;
        }
    };

    const contract = struct {
        const PromptTypeV = prompt_contract.Prompt(.resume_or_return, ResumeType, AnswerType, ErrorSetType);
        const StateTypeV = ResumeType;
        const AnswerTypeV = AnswerType;
        const ErrorSetTypeV = ErrorSetType;
        const capability_decls = capability_meta;
    };
    return try runWithSealedEngine(contract, .{ .runtime = runtime, .prompt_token = instance.prompt.token, .engine_ctx = &engine_ctx }, Body);
}

/// Run a continuation-taking lexical optional family through the shared algebraic engine.
pub fn handleOptionalLexical(
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Policy: type,
    comptime Body: type,
) lowered_machine.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!AnswerType {
    const ResumeType = family.InstanceStateType(@TypeOf(instance));
    const ErrorSetType = family.InstanceErrorSetType(@TypeOf(instance));
    comptime assertOptionalLexicalPolicyType(ResumeType, AnswerType, ErrorSetType, Policy);

    const optional_request_op = internal.ChoiceOp("__effect_optional_request", void, ResumeType);
    const hidden_program = internal.Program(AnswerType, AnswerType, ErrorSetType, .{optional_request_op});
    const OptionalState = struct {
        cleanup_marker: ?*cleanup.Frame,
    };
    const cleanup_marker = cleanup.checkpoint();
    const specs = .{
        internal.handleChoice(optional_request_op, OptionalState{ .cleanup_marker = cleanup_marker }, struct {
            /// Choose whether the lexical optional request resumes or returns now.
            pub fn resumeOrReturn(_: OptionalState, _: void) lowered_machine.ResetError(ErrorSetType)!choice.Decision(ResumeType, AnswerType) {
                const DecisionFn = @TypeOf(Policy.resumeOrReturn);
                if (DecisionFn == fn () choice.Decision(ResumeType, AnswerType)) return Policy.resumeOrReturn();
                return try Policy.resumeOrReturn();
            }

            /// Finish one resumed lexical optional answer by applying cleanup and the policy's final answer transform.
            pub fn afterResume(state: OptionalState, answer: AnswerType) lowered_machine.ResetError(ErrorSetType)!AnswerType {
                if (cleanup.checkpoint() != state.cleanup_marker) {
                    cleanup.unwindTo(state.cleanup_marker) catch |err| return @errorCast(err);
                }
                const AfterFn = @TypeOf(Policy.afterResume);
                if (AfterFn == fn (AnswerType) AnswerType) return Policy.afterResume(answer);
                return try Policy.afterResume(answer);
            }
        }),
    };
    const configured = hidden_program.handlers(specs);
    const GeneratedEngineContextType = @TypeOf(configured).Context;
    const BindingsType = internal.BindingChainFor(@TypeOf(specs), AnswerType, AnswerType, ErrorSetType);
    var bindings = BindingsType.initWithToken(specs, instance.prompt.token);
    var engine_ctx = GeneratedEngineContextType{ .bindings = &bindings };

    const capability_meta = struct {
        const body_tag = Body;

        /// Hidden lexical optional policy metadata carried by the exact context.
        pub fn PolicyType() type {
            return Policy;
        }

        /// Shared engine context type used by the lexical optional exact context.
        pub fn EngineContextType() type {
            return GeneratedEngineContextType;
        }

        /// Hidden choice op used by the lexical optional exact context.
        pub fn RequestOp() type {
            return optional_request_op;
        }
    };

    const contract = struct {
        const PromptTypeV = prompt_contract.Prompt(.resume_or_return, AnswerType, AnswerType, ErrorSetType);
        const StateTypeV = ResumeType;
        const AnswerTypeV = AnswerType;
        const ErrorSetTypeV = ErrorSetType;
        const capability_decls = capability_meta;
    };
    return try runWithSealedEngine(contract, .{ .runtime = runtime, .prompt_token = instance.prompt.token, .engine_ctx = &engine_ctx }, Body);
}

/// Assert the catch policy shape required by an exception family.
pub fn assertCatchType(comptime PayloadType: type, comptime AnswerType: type, comptime ErrorSetType: type, comptime CatchType: type) void {
    if (!family.hasDeclSafe(CatchType, "directReturn")) {
        @compileError("exception catch policy must declare directReturn");
    }
    const DirectReturnFn = @TypeOf(CatchType.directReturn);
    if (DirectReturnFn != fn (PayloadType) AnswerType and DirectReturnFn != fn (PayloadType) lowered_machine.ResetError(ErrorSetType)!AnswerType) {
        @compileError("exception catch policy directReturn must have type fn (Payload) Answer or fn (Payload) ResetError(ErrorSet)!Answer");
    }
}

/// Throw one payload through the shared algebraic engine.
pub inline fn throwException(
    comptime Cap: type,
    ctx: anytype,
    payload: family.ContextStateType(@TypeOf(ctx)),
) lowered_machine.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!noreturn {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    return try activeEngineContext(Cap, ctx).perform(Cap.ThrowOp(), payload);
}

/// Build one explicit exception throw program for the supplied capability and payload.
pub inline fn throwExceptionProgram(
    comptime Cap: type,
    ctx: anytype,
    payload: family.ContextStateType(@TypeOf(ctx)),
) frontend.Program(prompt_contract.Prompt(
    .direct_return,
    family.ContextAnswerType(@TypeOf(ctx)),
    family.ContextAnswerType(@TypeOf(ctx)),
    family.ContextErrorSetType(@TypeOf(ctx)),
)) {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    const ContextType = family.ContextTypeFromPtr(@TypeOf(ctx));
    return activeEngineContext(Cap, ctx).bindings.bindingPtr(0).directProgram(payload, struct {
        /// Unreachable continuation placeholder for direct-return effect programs.
        pub fn apply(_: noreturn) ContextType.AnswerType {
            unreachable;
        }
    });
}

/// Build one explicit exception body program with no throw operation.
pub inline fn exceptionComputeProgram(
    comptime Cap: type,
    ctx: anytype,
    thunk: anytype,
) frontend.Program(prompt_contract.Prompt(
    .direct_return,
    family.ContextAnswerType(@TypeOf(ctx)),
    family.ContextAnswerType(@TypeOf(ctx)),
    family.ContextErrorSetType(@TypeOf(ctx)),
)) {
    const ContextType = family.ContextTypeFromPtr(@TypeOf(ctx));
    const PromptType = prompt_contract.Prompt(.direct_return, ContextType.AnswerType, ContextType.AnswerType, ContextType.ErrorSetType);
    return computeProgramForPrompt(Cap, ctx, PromptType, thunk);
}

/// Run an exception family through the shared algebraic engine.
pub fn handleException(
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Catch: type,
    comptime Body: type,
) lowered_machine.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!AnswerType {
    const PayloadType = family.InstanceStateType(@TypeOf(instance));
    const ErrorSetType = family.InstanceErrorSetType(@TypeOf(instance));
    comptime assertCatchType(PayloadType, AnswerType, ErrorSetType, Catch);

    const exception_throw_op = internal.AbortOp("__effect_exception_throw", PayloadType);
    const hidden_program = internal.Program(AnswerType, AnswerType, ErrorSetType, .{exception_throw_op});
    const ExceptionState = struct {
        cleanup_marker: ?*cleanup.Frame,
    };
    const cleanup_marker = cleanup.checkpoint();
    const specs = .{
        internal.handleAbort(exception_throw_op, ExceptionState{ .cleanup_marker = cleanup_marker }, struct {
            /// Convert one thrown payload into the caught answer while unwinding cleanup.
            pub fn directReturn(state: ExceptionState, payload: PayloadType) lowered_machine.ResetError(ErrorSetType)!AnswerType {
                cleanup.unwindTo(state.cleanup_marker) catch |err| return @errorCast(err);
                const DirectFn = @TypeOf(Catch.directReturn);
                if (DirectFn == fn (PayloadType) AnswerType) return Catch.directReturn(payload);
                return try Catch.directReturn(payload);
            }
        }),
    };
    const configured = hidden_program.handlers(specs);
    const GeneratedEngineContextType = @TypeOf(configured).Context;
    const BindingsType = internal.BindingChainFor(@TypeOf(specs), AnswerType, AnswerType, ErrorSetType);
    var bindings = BindingsType.initWithToken(specs, instance.prompt.token);
    var engine_ctx = GeneratedEngineContextType{ .bindings = &bindings };

    const capability_meta = struct {
        const body_tag = Body;

        /// Hidden catch metadata used by the exact exception context.
        pub fn CatchType() type {
            return Catch;
        }

        /// Shared engine context type used by the exact exception context.
        pub fn EngineContextType() type {
            return GeneratedEngineContextType;
        }

        /// Hidden throw op used by the exact exception context.
        pub fn ThrowOp() type {
            return exception_throw_op;
        }
    };

    const contract = struct {
        const PromptTypeV = prompt_contract.Prompt(.direct_return, AnswerType, AnswerType, ErrorSetType);
        const StateTypeV = PayloadType;
        const AnswerTypeV = AnswerType;
        const ErrorSetTypeV = ErrorSetType;
        const capability_decls = capability_meta;
    };
    return try runWithSealedEngine(contract, .{ .runtime = runtime, .prompt_token = instance.prompt.token, .engine_ctx = &engine_ctx }, Body);
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
    if (AcquireFn != fn () ResourceType and AcquireFn != fn () lowered_machine.ResetError(ErrorSetType)!ResourceType) {
        @compileError("resource manager acquire must have type fn () Resource or fn () ResetError(ErrorSet)!Resource");
    }

    const ReleaseFn = @TypeOf(ManagerType.release);
    if (ReleaseFn != fn (ResourceType) void and ReleaseFn != fn (ResourceType) lowered_machine.ResetError(ErrorSetType)!void) {
        @compileError("resource manager release must have type fn (Resource) void or fn (Resource) ResetError(ErrorSet)!void");
    }
}

/// Acquire one resource through the shared algebraic engine.
pub inline fn acquireResource(
    comptime Cap: type,
    ctx: anytype,
) lowered_machine.ResetError(family.ContextErrorSetType(@TypeOf(ctx)))!family.ContextStateType(@TypeOf(ctx)) {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    return try activeEngineContext(Cap, ctx).perform(Cap.AcquireOp(), {});
}

/// Build one explicit resource body program with no prompt operation.
pub inline fn resourceComputeProgram(
    comptime Cap: type,
    ctx: anytype,
    comptime Thunk: type,
) frontend.Program(prompt_contract.Prompt(
    .resume_then_transform,
    family.ContextAnswerType(@TypeOf(ctx)),
    family.ContextAnswerType(@TypeOf(ctx)),
    family.ContextErrorSetType(@TypeOf(ctx)),
)) {
    const ContextType = family.ContextTypeFromPtr(@TypeOf(ctx));
    const PromptType = prompt_contract.Prompt(.resume_then_transform, ContextType.AnswerType, ContextType.AnswerType, ContextType.ErrorSetType);
    return computeProgramForPrompt(Cap, ctx, PromptType, Thunk);
}

/// Run a resource family through the shared algebraic engine.
pub fn handleResource(
    comptime AnswerType: type,
    runtime: *shift.Runtime,
    instance: anytype,
    comptime Manager: type,
    comptime Body: type,
) lowered_machine.ResetError(family.InstanceErrorSetType(@TypeOf(instance)))!AnswerType {
    const ResourceType = family.InstanceStateType(@TypeOf(instance));
    const ErrorSetType = family.InstanceErrorSetType(@TypeOf(instance));
    comptime assertManagerType(ResourceType, ErrorSetType, Manager);

    const resource_acquire_op = internal.TransformOp("__effect_resource_acquire", void, ResourceType);
    const hidden_program = internal.Program(AnswerType, AnswerType, ErrorSetType, .{resource_acquire_op});
    const Frame = struct {
        allocator: std.mem.Allocator,
        resources: std.ArrayList(ResourceType) = .empty,
        cleanup_frame: cleanup.Frame = .{ .cleanupFn = cleanupResources },
        cleaned: bool = false,

        fn cleanupResources(base: *cleanup.Frame) anyerror!void {
            const self: *@This() = @fieldParentPtr("cleanup_frame", base);
            var first_error: ?lowered_machine.ResetError(ErrorSetType) = null;
            while (self.resources.items.len != 0) {
                const resource = self.resources.items[self.resources.items.len - 1];
                self.resources.items.len -= 1;
                const ReleaseFn = @TypeOf(Manager.release);
                if (ReleaseFn == fn (ResourceType) void) {
                    Manager.release(resource);
                } else {
                    Manager.release(resource) catch |err| {
                        if (first_error == null) first_error = err;
                    };
                }
            }
            self.deinit();
            if (first_error) |err| return err;
        }

        fn deinit(self: *@This()) void {
            if (self.cleaned) return;
            self.cleaned = true;
            self.resources.deinit(self.allocator);
        }
    };

    var frame = Frame{ .allocator = runtime.allocator };
    defer frame.deinit();
    const specs = .{
        internal.handleDirectTransform(resource_acquire_op, &frame, struct {
            /// Acquire one resource and record it for later cleanup.
            pub fn resumeValue(frame_ptr: *Frame, _: void) lowered_machine.ResetError(ErrorSetType)!ResourceType {
                const AcquireFn = @TypeOf(Manager.acquire);
                const resource = if (AcquireFn == fn () ResourceType) Manager.acquire() else try Manager.acquire();
                try frame_ptr.resources.append(frame_ptr.allocator, resource);
                return resource;
            }

            /// Preserve the enclosing answer unchanged after a resource acquire.
            pub fn afterResume(_: *Frame, answer: AnswerType) AnswerType {
                return answer;
            }
        }),
    };
    const configured = hidden_program.handlers(specs);
    const GeneratedEngineContextType = @TypeOf(configured).Context;
    const BindingsType = internal.BindingChainFor(@TypeOf(specs), AnswerType, AnswerType, ErrorSetType);
    var bindings = BindingsType.initWithToken(specs, instance.prompt.token);
    var engine_ctx = GeneratedEngineContextType{ .bindings = &bindings };

    const capability_meta = struct {
        const body_tag = Body;

        /// Hidden manager metadata used by the exact resource context.
        pub fn ManagerType() type {
            return Manager;
        }

        /// Shared engine context type used by the exact resource context.
        pub fn EngineContextType() type {
            return GeneratedEngineContextType;
        }

        /// Hidden acquire op used by the exact resource context.
        pub fn AcquireOp() type {
            return resource_acquire_op;
        }
    };

    cleanup.push(&frame.cleanup_frame);
    var body_error: ?lowered_machine.ResetError(ErrorSetType) = null;
    const contract = struct {
        const PromptTypeV = prompt_contract.Prompt(.resume_then_transform, AnswerType, AnswerType, ErrorSetType);
        const StateTypeV = ResourceType;
        const AnswerTypeV = AnswerType;
        const ErrorSetTypeV = ErrorSetType;
        const capability_decls = capability_meta;
    };
    const answer = runWithSealedEngine(contract, .{ .runtime = runtime, .prompt_token = instance.prompt.token, .engine_ctx = &engine_ctx }, Body) catch |err| blk: {
        body_error = err;
        break :blk null;
    };

    const cleanup_marker = frame.cleanup_frame.previous;
    var cleanup_error: ?lowered_machine.ResetError(ErrorSetType) = null;
    cleanup.unwindTo(cleanup_marker) catch |err| {
        cleanup_error = @errorCast(err);
    };

    if (body_error) |err| return err;
    if (cleanup_error) |err| return err;
    return answer.?;
}
