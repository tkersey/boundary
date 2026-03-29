const root = @import("root.zig");

/// Root-level choice decision helper.
pub const Decision = root.Decision;
/// Public declaration namespace.
pub const Decl = root.Decl;
/// Public op-descriptor namespace.
pub const Op = root.Op;
/// Canonical runtime handle.
pub const Runtime = root.Runtime;
/// Public runtime error surface.
pub const RuntimeError = root.RuntimeError;
/// Stable public error-witness schema.
pub const ErrorWitnessV1 = root.ErrorWitnessV1;
/// Public program builder.
pub const Program = root.Program;
/// Canonical lexical execution entrypoint.
pub const run = root.run;

test {
    _ = root;
}
