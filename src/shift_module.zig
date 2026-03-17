const root = @import("root.zig");

/// Generalized algebraic-effect builders over the canonical shift root.
pub const algebraic = root.algebraic;
/// Additive algebraic-effect families over the canonical shift root.
pub const effect = root.effect;
/// Canonical runtime handle.
pub const Runtime = root.Runtime;
/// Public runtime error surface.
pub const Error = root.Error;
/// Runtime error union for a user-provided error set.
pub const ControlError = root.ControlError;
/// Reset-time error union for a user-provided error set.
pub const ResetError = root.ResetError;
/// Canonical lexical result type returned from `shift.with(...)`.
pub const WithResult = root.WithResult;
/// Canonical lexical execution entrypoint.
pub const with = root.with;

test {
    _ = root;
}
