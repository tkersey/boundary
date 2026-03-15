/// Generalized algebraic-effect builders over the core shift/reset runtime.
pub const algebraic = @import("algebraic.zig");
/// Additive algebraic-effect families built on top of the core shift/reset runtime.
pub const effect = @import("effect/root.zig");
/// Canonical authored-body layer over the lowered runtime substrate.
pub const frontend = @import("frontend.zig");
const lowered_machine = @import("lowered_machine");
const prompt_contract = @import("prompt_contract.zig");

/// Comptime-selected handler protocol for a prompt value.
pub const PromptMode = prompt_contract.PromptMode;

/// Canonical lowered-first runtime handle.
pub const Runtime = lowered_machine.Runtime;
/// Public runtime errors surfaced by `shift`.
pub const Error = lowered_machine.Error;

/// Runtime error union for a user-provided error set.
pub fn ControlError(comptime ErrorSet: type) type {
    return lowered_machine.ControlError(ErrorSet);
}

/// Reset-time error union for a user-provided error set.
pub fn ResetError(comptime ErrorSet: type) type {
    return lowered_machine.ResetError(ErrorSet);
}

/// Handler decision for zero-or-one-resume prompt modes.
pub const ResumeOrReturn = prompt_contract.ResumeOrReturn;

fn PromptTypeFromPtr(comptime PromptPtrType: type) type {
    return switch (@typeInfo(PromptPtrType)) {
        .pointer => |pointer| pointer.child,
        else => @compileError("expected a pointer to shift.Prompt(...)"),
    };
}

fn PromptOutAnswerType(comptime PromptPtrType: type) type {
    return PromptTypeFromPtr(PromptPtrType).OutAnswer;
}

fn PromptErrorSetType(comptime PromptPtrType: type) type {
    return PromptTypeFromPtr(PromptPtrType).ErrorSet;
}

/// First-class delimiter value for one-shot `shift/reset`.
pub fn Prompt(
    comptime mode: PromptMode,
    comptime InAnswer: type,
    comptime OutAnswer: type,
    comptime ErrorSet: type,
) type {
    return prompt_contract.Prompt(mode, InAnswer, OutAnswer, ErrorSet);
}

/// Run `body` under a fresh dynamic delimiter identified by `prompt`.
pub fn reset(
    runtime: *Runtime,
    prompt: anytype,
    program: frontend.Program(PromptTypeFromPtr(@TypeOf(prompt))),
) ResetError(PromptErrorSetType(@TypeOf(prompt)))!PromptOutAnswerType(@TypeOf(prompt)) {
    return frontend.run(runtime, prompt, program);
}

/// Capture the computation up to the nearest active `reset(..., prompt, ...)`.
pub fn shift(
    comptime _Resume: type,
    _prompt: anytype,
    comptime _: type,
) ControlError(PromptErrorSetType(@TypeOf(_prompt)))!_Resume {
    @compileError("canonical shift.shift is no longer executable; use shift.frontend.build(...) plus shift.frontend.perform/transform/choice/abort.");
}

test {
    _ = Prompt;
    _ = PromptMode;
    _ = ResumeOrReturn;
    _ = Runtime;
    _ = effect;
    _ = algebraic;
    _ = frontend;
}
