const family = @import("../effect/family.zig");
const frontend = @import("frontend_support");
const lowered_machine = @import("lowered_machine");

pub fn computeProgramForPrompt(
    comptime Cap: type,
    ctx: anytype,
    comptime PromptType: type,
    thunk: anytype,
) frontend.Program(PromptType) {
    comptime family.assertContextType(Cap, @TypeOf(ctx));
    const ContextType = family.ContextTypeFromPtr(@TypeOf(ctx));
    const ThunkType = @TypeOf(thunk);
    _ = ctx._cap;
    return frontend.computeProgramWithContext(PromptType, ctx, struct {
        fn invoke(program_ctx: @TypeOf(ctx)) lowered_machine.ResetError(ContextType.ErrorSetType)!ContextType.AnswerType {
            switch (@typeInfo(ThunkType)) {
                .@"fn" => {
                    const params = @typeInfo(ThunkType).@"fn".params;
                    const ReturnType = @typeInfo(ThunkType).@"fn".return_type.?;
                    if (params.len == 0) {
                        if (@typeInfo(ReturnType) != .error_union) return thunk();
                        return try thunk();
                    }
                    if (@typeInfo(ReturnType) != .error_union) return thunk(Cap, program_ctx);
                    return try thunk(Cap, program_ctx);
                },
                .pointer => |pointer| {
                    if (@typeInfo(pointer.child) == .@"fn") {
                        const params = @typeInfo(pointer.child).@"fn".params;
                        const ReturnType = @typeInfo(pointer.child).@"fn".return_type.?;
                        if (params.len == 0) {
                            if (@typeInfo(ReturnType) != .error_union) return thunk();
                            return try thunk();
                        }
                        if (@typeInfo(ReturnType) != .error_union) return thunk(Cap, program_ctx);
                        return try thunk(Cap, program_ctx);
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
            if (@typeInfo(ReturnType) != .error_union) return thunk.run(Cap, program_ctx);
            return try thunk.run(Cap, program_ctx);
        }
    }.invoke);
}

/// Execute one exact-capability body through the shared sealed-engine adapter.
pub fn runWithSealedEngine(
    comptime PromptType: type,
    comptime StateType: type,
    comptime AnswerType: type,
    comptime ErrorSetType: type,
    comptime capability_decls: type,
    config: anytype,
    comptime Body: type,
) lowered_machine.ResetError(ErrorSetType)!AnswerType {
    const EnginePtrType = @TypeOf(config.engine_ctx);
    const EngineContextType = switch (@typeInfo(EnginePtrType)) {
        .pointer => |pointer| pointer.child,
        else => @compileError("expected engine context pointer"),
    };

    const RunnerState = struct {
        runtime: *lowered_machine.Runtime,
        prompt_identity: *const anyopaque,
        engine_ctx: *EngineContextType,
        lexical_state: ?*anyopaque = null,
    };
    const runner_state = RunnerState{
        .runtime = config.runtime,
        .prompt_identity = config.prompt_identity,
        .engine_ctx = config.engine_ctx,
        .lexical_state = if (@hasField(@TypeOf(config), "lexical_state")) config.lexical_state else null,
    };

    const runner = struct {
        pub fn run(state: RunnerState, comptime Cap: type, ctx: anytype) lowered_machine.ResetError(ErrorSetType)!AnswerType {
            const prompt: *const PromptType = @ptrCast(@alignCast(state.prompt_identity));
            if (comptime family.hasDeclSafe(Body, "program")) {
                const AuthoredType = @TypeOf(Body.program(Cap, ctx));
                if (@typeInfo(AuthoredType) == .@"struct") {
                    var authored = Body.program(Cap, ctx);
                    authored.activate();
                    defer authored.deactivate();
                    return try frontend.run(state.runtime, authored.prompt, authored.program);
                }
                return try frontend.run(state.runtime, prompt, Body.program(Cap, ctx));
            }
            if (comptime family.hasDeclSafe(Body, "body")) {
                return try frontend.run(state.runtime, prompt, computeProgramForPrompt(Cap, ctx, PromptType, Body.body));
            }
            @compileError("effect body must declare program or body");
        }
    };

    return try family.withCapability(
        family.ContextSpec(StateType, AnswerType, ErrorSetType),
        capability_decls,
        runner_state,
        AnswerType,
        runner,
    );
}
