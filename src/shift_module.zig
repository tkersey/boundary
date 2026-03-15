const root = @import("root.zig");

/// Generalized algebraic-effect builders over the canonical shift root.
pub const algebraic = root.algebraic;
/// Additive algebraic-effect families over the canonical shift root.
pub const effect = root.effect;
/// Canonical authored-body layer over the shift runtime.
pub const frontend = root.frontend;
/// Comptime-selected handler protocol for a prompt value.
pub const PromptMode = root.PromptMode;
/// Canonical runtime handle.
pub const Runtime = root.Runtime;
/// Public runtime error surface.
pub const Error = root.Error;
/// Runtime error union for a user-provided error set.
pub const ControlError = root.ControlError;
/// Reset-time error union for a user-provided error set.
pub const ResetError = root.ResetError;
/// Handler decision for zero-or-one-resume prompt modes.
pub const ResumeOrReturn = root.ResumeOrReturn;
/// First-class delimiter value for one-shot shift/reset.
pub const Prompt = root.Prompt;
/// Canonical reset entrypoint.
pub const reset = root.reset;

test {
    _ = root;
}
