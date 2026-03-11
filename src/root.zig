const raw = @import("raw.zig");
const std = @import("std");

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

fn PromptTypeFromPtr(comptime PromptPtrType: type) type {
    return switch (@typeInfo(PromptPtrType)) {
        .pointer => |pointer| pointer.child,
        else => @compileError("expected a pointer to shift.Prompt(...)"),
    };
}

fn PromptAnswerType(comptime PromptPtrType: type) type {
    return PromptTypeFromPtr(PromptPtrType).Answer;
}

fn PromptErrorSetType(comptime PromptPtrType: type) type {
    return PromptTypeFromPtr(PromptPtrType).ErrorSet;
}

/// First-class delimiter value for one-shot `shift/reset`.
pub fn Prompt(comptime Answer: type, comptime ErrorSet: type) type {
    return raw.Prompt(Answer, ErrorSet);
}

/// Run `body` under a fresh dynamic delimiter identified by `prompt`.
pub fn reset(
    runtime: *Runtime,
    prompt: anytype,
    body: *const fn () ResetError(PromptErrorSetType(@TypeOf(prompt)))!PromptAnswerType(@TypeOf(prompt)),
) ResetError(PromptErrorSetType(@TypeOf(prompt)))!PromptAnswerType(@TypeOf(prompt)) {
    return raw.reset(PromptTypeFromPtr(@TypeOf(prompt)), runtime, prompt, body);
}

/// Capture the computation up to the nearest active `reset(..., prompt, ...)`.
pub fn shift(
    comptime Resume: type,
    prompt: anytype,
    handler: *const fn (*raw.Continuation(Resume, PromptTypeFromPtr(@TypeOf(prompt)))) ResetError(PromptErrorSetType(@TypeOf(prompt)))!PromptAnswerType(@TypeOf(prompt)),
) ControlError(PromptErrorSetType(@TypeOf(prompt)))!Resume {
    return raw.shift(Resume, PromptTypeFromPtr(@TypeOf(prompt)), prompt, handler);
}

/// One-shot continuation handle for `shift`.
pub fn Continuation(comptime Resume: type, comptime PromptType: type) type {
    return raw.Continuation(Resume, PromptType);
}

test {
    _ = Prompt;
    _ = Runtime;
    _ = std;
}
