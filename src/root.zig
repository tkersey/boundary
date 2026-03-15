/// Generalized algebraic-effect builders over the core shift/reset runtime.
pub const algebraic = @import("algebraic.zig");
/// Additive algebraic-effect families built on top of the core shift/reset runtime.
pub const effect = @import("effect/root.zig");
/// Explicit compatibility namespace for the current stackful raw runtime.
pub const compat = struct {
    /// Legacy raw prompt/runtime surface retained outside the planned lowered-first root cut.
    pub const raw = @import("compat/raw.zig");
};
const raw = @import("raw.zig");
const std = @import("std");

/// Comptime-selected handler protocol for a prompt value.
pub const PromptMode = raw.PromptMode;

/// Runtime owner for fiber-backed one-shot `shift/reset`.
pub const Runtime = raw.Runtime;
/// Public runtime errors surfaced by `shift`.
pub const Error = raw.Error;
/// Internal runtime/setup failures that can appear before user code runs.
pub const SetupError = raw.SetupError;

/// Runtime error union for a user-provided error set.
pub fn ControlError(comptime ErrorSet: type) type {
    return raw.ControlError(ErrorSet);
}

/// Reset-time error union for a user-provided error set.
pub fn ResetError(comptime ErrorSet: type) type {
    return raw.ResetError(ErrorSet);
}

/// Handler decision for zero-or-one-resume prompt modes.
pub fn ResumeOrReturn(
    comptime Resume: type,
    comptime OutAnswer: type,
) type {
    return raw.ResumeOrReturn(Resume, OutAnswer);
}

fn PromptTypeFromPtr(comptime PromptPtrType: type) type {
    return switch (@typeInfo(PromptPtrType)) {
        .pointer => |pointer| pointer.child,
        else => @compileError("expected a pointer to shift.Prompt(...)"),
    };
}

fn PromptInAnswerType(comptime PromptPtrType: type) type {
    return PromptTypeFromPtr(PromptPtrType).InAnswer;
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
    return raw.Prompt(mode, InAnswer, OutAnswer, ErrorSet);
}

/// Run `body` under a fresh dynamic delimiter identified by `prompt`.
pub fn reset(
    runtime: *Runtime,
    prompt: anytype,
    body: *const fn () ResetError(PromptErrorSetType(@TypeOf(prompt)))!PromptInAnswerType(@TypeOf(prompt)),
) ResetError(PromptErrorSetType(@TypeOf(prompt)))!PromptOutAnswerType(@TypeOf(prompt)) {
    return raw.reset(PromptTypeFromPtr(@TypeOf(prompt)), runtime, prompt, body);
}

/// Capture the computation up to the nearest active `reset(..., prompt, ...)`.
pub fn shift(
    comptime Resume: type,
    prompt: anytype,
    comptime Handler: type,
) ControlError(PromptErrorSetType(@TypeOf(prompt)))!Resume {
    return raw.shift(Resume, PromptTypeFromPtr(@TypeOf(prompt)), prompt, Handler);
}

test {
    _ = Prompt;
    _ = PromptMode;
    _ = ResumeOrReturn;
    _ = Runtime;
    _ = compat;
    _ = effect;
    _ = algebraic;
    _ = std;
}
