/// Generalized algebraic-effect builders over the core shift/reset runtime.
pub const algebraic = @import("algebraic.zig");
/// Additive algebraic-effect families built on top of the core shift/reset runtime.
pub const effect = @import("effect/root.zig");
/// Canonical authored-body layer over the raw runtime substrate.
pub const frontend = @import("frontend.zig");
const prompt_contract = @import("prompt_contract.zig");
const raw = @import("raw.zig");
const std = @import("std");

/// Comptime-selected handler protocol for a prompt value.
pub const PromptMode = prompt_contract.PromptMode;

/// Canonical lowered-first runtime handle.
pub const Runtime = struct {
    allocator: std.mem.Allocator,
    inner: raw.Runtime,

    /// Initialize a canonical runtime on the current thread.
    pub fn init(allocator: std.mem.Allocator) Runtime {
        return .{
            .allocator = allocator,
            .inner = raw.Runtime.init(allocator, .{}),
        };
    }

    /// Release resources owned by the canonical runtime.
    pub fn deinit(self: *Runtime) void {
        self.inner.deinit();
    }

    /// Release resources owned by the canonical runtime, returning an error on misuse.
    pub fn deinitChecked(self: *Runtime) raw.Error!void {
        return self.inner.deinitChecked();
    }
};
/// Public runtime errors surfaced by `shift`.
pub const Error = raw.Error;

/// Runtime error union for a user-provided error set.
pub fn ControlError(comptime ErrorSet: type) type {
    return raw.ControlError(ErrorSet);
}

/// Reset-time error union for a user-provided error set.
pub fn ResetError(comptime ErrorSet: type) type {
    return raw.ResetError(ErrorSet);
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
    body_or_program: anytype,
) ResetError(PromptErrorSetType(@TypeOf(prompt)))!PromptOutAnswerType(@TypeOf(prompt)) {
    return frontend.run(runtime, prompt, body_or_program);
}

/// Capture the computation up to the nearest active `reset(..., prompt, ...)`.
pub fn shift(
    comptime Resume: type,
    prompt: anytype,
    comptime Handler: type,
) ControlError(PromptErrorSetType(@TypeOf(prompt)))!Resume {
    return frontend.perform(Resume, prompt, Handler);
}

test {
    _ = Prompt;
    _ = PromptMode;
    _ = ResumeOrReturn;
    _ = Runtime;
    _ = effect;
    _ = algebraic;
    _ = frontend;
    _ = std;
}
