const frontend = @import("frontend_support");
const lowered_machine = @import("lowered_machine");
const prompt_contract = @import("prompt_contract_support");

/// Resolve an effect instance type from a pointer passed into a family handler.
pub fn InstanceTypeFromPtr(comptime InstancePtrType: type) type {
    return switch (@typeInfo(InstancePtrType)) {
        .pointer => |pointer| pointer.child,
        else => @compileError("expected a pointer to boundary.effect family instance"),
    };
}

/// Extract the family state type from an instance pointer.
pub fn InstanceStateType(comptime InstancePtrType: type) type {
    return InstanceTypeFromPtr(InstancePtrType).State;
}

/// Extract the family error set from an instance pointer.
pub fn InstanceErrorSetType(comptime InstancePtrType: type) type {
    return InstanceTypeFromPtr(InstancePtrType).ErrorSet;
}

/// Build a prompt-backed family instance shell for the selected prompt mode.
pub fn InstanceWithMode(comptime mode: prompt_contract.PromptMode, comptime StateType: type, comptime ErrorSetType: type) type {
    const PromptShell = prompt_contract.Prompt(mode, void, void, ErrorSetType);
    return struct {
        /// Prompt mode used internally by this family instance.
        pub const prompt_mode = mode;
        /// State value threaded through this effect family.
        pub const State = StateType;
        /// Error set propagated by this effect family.
        pub const ErrorSet = ErrorSetType;

        prompt: PromptShell,

        /// Create a fresh family instance with its own prompt identity.
        pub fn init() @This() {
            return .{ .prompt = PromptShell.init() };
        }
    };
}

/// Build a prompt-backed family instance shell for a value-threading family.
pub fn Instance(comptime StateType: type, comptime ErrorSetType: type) type {
    return InstanceWithMode(.resume_then_transform, StateType, ErrorSetType);
}

/// Final family state plus body answer returned from a handled effect program.
pub fn HandleResult(comptime StateType: type, comptime ValueType: type) type {
    return struct {
        state: StateType,
        value: ValueType,
    };
}

/// Build the private exact context type for one family capability.
pub fn Context(comptime Cap: type, comptime StateTypeParam: type, comptime AnswerTypeParam: type, comptime ErrorSetTypeParam: type) type {
    return struct {
        /// Unique capability witness type for this private context.
        pub const capability = Cap;
        /// Caller source location carried through lexical continuation re-entry when available.
        pub const caller_source = if (hasDeclSafe(Cap, "caller_source")) Cap.caller_source else null;
        /// State type threaded through this private context.
        pub const StateType = StateTypeParam;
        /// Answer type produced by this private context.
        pub const AnswerType = AnswerTypeParam;
        /// Error set propagated by this private context.
        pub const ErrorSetType = ErrorSetTypeParam;

        _cap: *const Cap,
    };
}

/// Resolve the private exact context type from a pointer.
pub fn ContextTypeFromPtr(comptime ContextPtrType: type) type {
    return switch (@typeInfo(ContextPtrType)) {
        .pointer => |pointer| pointer.child,
        else => @compileError("expected a pointer to an boundary.effect context"),
    };
}

/// Safely check whether a type declares a comptime field.
pub fn hasDeclSafe(comptime T: type, comptime name: []const u8) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, name),
        else => false,
    };
}

/// Assert that the supplied context pointer exactly matches the expected capability-parameterized private context type.
pub fn assertContextType(comptime Cap: type, comptime ContextPtrType: type) void {
    const ContextType = ContextTypeFromPtr(ContextPtrType);
    if (!hasDeclSafe(ContextType, "capability") or !hasDeclSafe(ContextType, "StateType") or !hasDeclSafe(ContextType, "AnswerType") or !hasDeclSafe(ContextType, "ErrorSetType")) {
        @compileError("expected an boundary.effect context");
    }
    if (ContextType.capability != Cap) {
        @compileError("context capability does not match supplied capability");
    }
    const ExpectedContext = Context(Cap, ContextType.StateType, ContextType.AnswerType, ContextType.ErrorSetType);
    if (ContextType != ExpectedContext) {
        @compileError("expected exact boundary.effect context type");
    }
}

/// Extract the family state type from a checked context pointer.
pub fn ContextStateType(comptime ContextPtrType: type) type {
    return ContextTypeFromPtr(ContextPtrType).StateType;
}

/// Extract the family answer type from a checked context pointer.
pub fn ContextAnswerType(comptime ContextPtrType: type) type {
    return ContextTypeFromPtr(ContextPtrType).AnswerType;
}

/// Extract the family error set from a checked context pointer.
pub fn ContextErrorSetType(comptime ContextPtrType: type) type {
    return ContextTypeFromPtr(ContextPtrType).ErrorSetType;
}

/// Return the caller provenance carried by one checked context pointer.
pub fn contextCallerSource(comptime ContextPtrType: type) @TypeOf(ContextTypeFromPtr(ContextPtrType).caller_source) {
    return ContextTypeFromPtr(ContextPtrType).caller_source;
}

/// Package the three family types used to build an exact private context.
pub fn ContextSpec(comptime StateType: type, comptime AnswerType: type, comptime ErrorSetType: type) type {
    return struct {
        /// State type carried by the family context.
        pub const state_type = StateType;
        /// Enclosing answer type produced by the family context.
        pub const answer_type = AnswerType;
        /// Error set propagated by the family context.
        pub const error_set_type = ErrorSetType;
    };
}

/// Build one explicit family body program with no prompt operation.
pub inline fn computeProgram(
    comptime Cap: type,
    ctx: anytype,
    comptime Thunk: type,
) frontend.Program(prompt_contract.Prompt(.resume_then_transform, ContextAnswerType(@TypeOf(ctx)), ContextAnswerType(@TypeOf(ctx)), ContextErrorSetType(@TypeOf(ctx)))) {
    comptime assertContextType(Cap, @TypeOf(ctx));
    const ContextType = ContextTypeFromPtr(@TypeOf(ctx));
    const PromptType = prompt_contract.Prompt(.resume_then_transform, ContextType.AnswerType, ContextType.AnswerType, ContextType.ErrorSetType);
    _ = ctx._cap;
    return frontend.computeProgramWithContext(PromptType, ctx, struct {
        fn invoke(program_ctx: @TypeOf(ctx)) lowered_machine.ResetError(ContextType.ErrorSetType)!ContextType.AnswerType {
            const RunFn = @TypeOf(Thunk.run);
            const ReturnType = @typeInfo(RunFn).@"fn".return_type.?;
            if (@typeInfo(ReturnType) != .error_union) return Thunk.run(Cap, program_ctx);
            return try Thunk.run(Cap, program_ctx);
        }
    }.invoke);
}

/// Mint a fresh capability witness and exact private context, then hand both to `Runner.run`.
pub fn withCapability(
    comptime context_spec: type,
    comptime capability_decls: type,
    runner_state: anytype,
    comptime ResultType: type,
    comptime Runner: type,
) lowered_machine.ResetError(context_spec.error_set_type)!ResultType {
    const seal = struct {};
    const Cap = struct {
        _seal: seal,
        engine_ctx: ?*anyopaque = null,
        lexical_state: ?*anyopaque = null,
        const capability_tag = capability_decls;
        /// Caller source location forwarded through exact-capability execution when supplied by the caller.
        pub const caller_source = if (hasDeclSafe(@TypeOf(runner_state), "caller_source")) @TypeOf(runner_state).caller_source else null;

        /// Opaque metadata bundle for effect-family-specific internal wiring.
        pub fn CapabilityTag() type {
            return capability_tag;
        }

        /// Optional engine context metadata attached to this capability witness.
        pub fn EngineContextType() type {
            if (hasDeclSafe(capability_decls, "EngineContextType")) return capability_decls.EngineContextType();
            return void;
        }

        /// Optional hidden transform-op metadata attached to this capability witness.
        pub fn GetOp() type {
            if (hasDeclSafe(capability_decls, "GetOp")) return capability_decls.GetOp();
            return void;
        }

        /// Optional hidden transform-op metadata attached to this capability witness.
        pub fn SetOp() type {
            if (hasDeclSafe(capability_decls, "SetOp")) return capability_decls.SetOp();
            return void;
        }

        /// Optional hidden transform-op metadata attached to this capability witness.
        pub fn AskOp() type {
            if (hasDeclSafe(capability_decls, "AskOp")) return capability_decls.AskOp();
            return void;
        }

        /// Optional hidden transform-op metadata attached to this capability witness.
        pub fn TellOp() type {
            if (hasDeclSafe(capability_decls, "TellOp")) return capability_decls.TellOp();
            return void;
        }

        /// Optional hidden choice-op metadata attached to this capability witness.
        pub fn RequestOp() type {
            if (hasDeclSafe(capability_decls, "RequestOp")) return capability_decls.RequestOp();
            return void;
        }

        /// Optional hidden abort-op metadata attached to this capability witness.
        pub fn ThrowOp() type {
            if (hasDeclSafe(capability_decls, "ThrowOp")) return capability_decls.ThrowOp();
            return void;
        }

        /// Optional hidden transform-op metadata attached to this capability witness.
        pub fn AcquireOp() type {
            if (hasDeclSafe(capability_decls, "AcquireOp")) return capability_decls.AcquireOp();
            return void;
        }

        /// Optional policy metadata attached to this capability witness.
        pub fn PolicyType() type {
            if (hasDeclSafe(capability_decls, "PolicyType")) return capability_decls.PolicyType();
            return void;
        }

        /// Optional catch metadata attached to this capability witness.
        pub fn CatchType() type {
            if (hasDeclSafe(capability_decls, "CatchType")) return capability_decls.CatchType();
            return void;
        }

        /// Optional manager metadata attached to this capability witness.
        pub fn ManagerType() type {
            if (hasDeclSafe(capability_decls, "ManagerType")) return capability_decls.ManagerType();
            return void;
        }
    };
    const ContextType = Context(Cap, context_spec.state_type, context_spec.answer_type, context_spec.error_set_type);

    var cap_token = Cap{ ._seal = .{} };
    if (@hasField(@TypeOf(runner_state), "engine_ctx")) {
        cap_token.engine_ctx = @ptrCast(runner_state.engine_ctx);
    }
    if (@hasField(@TypeOf(runner_state), "lexical_state")) {
        cap_token.lexical_state = @ptrCast(runner_state.lexical_state);
    }
    var context = ContextType{ ._cap = &cap_token };
    return try Runner.run(runner_state, Cap, &context);
}
