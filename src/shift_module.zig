const root = @import("root.zig");

/// Root-level choice decision helper.
pub const Decision = root.Decision;
/// Unified declaration namespace.
pub const Decl = root.Decl;
/// Legacy unified op descriptor namespace.
pub const Op = root.Op;
/// Unified op descriptor namespace.
pub const Ops = root.Ops;
/// Root-first authored program surface.
pub const Program = root.Program;
/// Canonical runtime handle.
pub const Runtime = root.Runtime;
/// Public runtime error surface.
pub const RuntimeError = root.RuntimeError;
/// Stable public error-witness schema.
pub const ErrorWitnessV1 = root.ErrorWitnessV1;
/// Canonical lexical execution entrypoint.
pub const run = root.run;

test {
    _ = root;
}
