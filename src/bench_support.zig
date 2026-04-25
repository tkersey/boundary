/// Private benchmark-only runtime facade that preserves the historical
/// benchmark call surface without widening the public root API.
const effect_root = @import("effect/root.zig");
const internal_algebraic = @import("internal/algebraic_engine.zig");
const lowered_machine = @import("lowered_machine");
const lowering_api = @import("lowering_api");
const prompt_support = @import("internal/prompt_support.zig");
const std = @import("std");

/// Benchmark-visible runtime shell.
pub const Runtime = lowered_machine.Runtime;
/// Benchmark-visible runtime error surface.
pub const RuntimeError = lowered_machine.RuntimeError;
/// Benchmark-visible lexical effect namespace.
pub const effect = effect_root;

/// Benchmark-visible explicit frontend helpers.
pub const frontend = prompt_support.frontend;
/// Benchmark-visible prompt mode enum.
pub const PromptMode = prompt_support.PromptMode;
/// Benchmark-visible prompt constructor.
pub const Prompt = prompt_support.Prompt;
/// Benchmark-visible zero-or-one-resume decision type.
pub const ResumeOrReturn = prompt_support.ResumeOrReturn;
/// Benchmark-visible explicit program type.
pub const Program = prompt_support.Program;
/// Benchmark-visible pure explicit program constructor.
pub const pureProgram = prompt_support.pureProgram;
/// Benchmark-visible transform explicit program constructor.
pub const transformProgram = prompt_support.transformProgram;
/// Benchmark-visible choice explicit program constructor.
pub const choiceProgram = prompt_support.choiceProgram;
/// Benchmark-visible abort explicit program constructor.
pub const abortProgram = prompt_support.abortProgram;
/// Benchmark-visible explicit perform helper.
pub const perform = prompt_support.perform;
/// Benchmark-visible explicit run helper.
pub const reset = prompt_support.run;

/// Preserve benchmark values across optimizer passes without changing the value.
pub fn preserveValue(value: anytype) @TypeOf(value) {
    const preserved = value;
    std.mem.doNotOptimizeAway(preserved);
    return preserved;
}

/// Benchmark-visible reset error helper.
pub fn ResetError(comptime ErrorSetType: type) type {
    return lowered_machine.ResetError(ErrorSetType);
}

/// Benchmark-visible algebraic engine compatibility facade.
pub const algebraic = struct {
    /// Benchmark-visible lowering namespace used by retained algebraic micro-benches.
    pub const lowering = lowering_api;
    /// Benchmark-visible transform op constructor.
    pub const TransformOp = internal_algebraic.TransformOp;
    /// Benchmark-visible choice op constructor.
    pub const ChoiceOp = internal_algebraic.ChoiceOp;
    /// Benchmark-visible abort op constructor.
    pub const AbortOp = internal_algebraic.AbortOp;
    /// Benchmark-visible transform handler builder.
    pub const handleTransform = internal_algebraic.handleTransform;
    /// Benchmark-visible choice handler builder.
    pub const handleChoice = internal_algebraic.handleChoice;
    /// Benchmark-visible abort handler builder.
    pub const handleAbort = internal_algebraic.handleAbort;

    /// Benchmark-visible closed-world algebraic program constructor.
    pub fn Program(
        comptime AnswerType: type,
        comptime ErrorSetType: type,
        comptime ops: anytype,
    ) type {
        return internal_algebraic.Program(AnswerType, AnswerType, ErrorSetType, ops);
    }
};
