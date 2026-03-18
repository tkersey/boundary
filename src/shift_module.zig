const root = @import("root.zig");

/// Generalized algebraic-effect builders over the canonical shift root.
pub const algebraic = root.algebraic;
/// Additive algebraic-effect families over the canonical shift root.
pub const effect = root.effect;
/// Canonical ordinary-Zig lowering metadata and execution helpers.
pub const ordinary = root.ordinary;
/// Canonical runtime handle.
pub const Runtime = root.Runtime;
/// Public runtime error surface.
pub const RuntimeError = root.RuntimeError;
/// Stable public error-witness schema.
pub const ErrorWitnessV1 = root.ErrorWitnessV1;
/// Canonical lexical companion type returned from `shift.with(...)`.
pub const With = root.With;
/// Canonical lexical execution entrypoint.
pub const with = root.with;

test {
    _ = root;
}
