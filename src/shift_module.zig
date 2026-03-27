const root = @import("root.zig");

/// Root-level choice decision helper.
pub const Decision = root.Decision;
/// Open-row transform descriptor.
pub const Transform = root.Transform;
/// Open-row choice descriptor.
pub const Choice = root.Choice;
/// Open-row abort descriptor.
pub const Abort = root.Abort;
/// Open-row result wrapper.
pub const RunResult = root.RunResult;
/// Canonical open-row row builder.
pub const Row = root.Row;
/// Canonical open-row row merge helper.
pub const mergeRows = root.mergeRows;
/// Canonical builtin open-row fragments.
pub const effects = root.effects;
/// Canonical builtin handler bridge constructors.
pub const handlers = root.handlers;
/// Open-row capability-bundle carrier.
pub const Uses = root.Uses;
/// Canonical partial discharge helper.
pub const handle = root.handle;
/// Canonical full bind helper.
pub const bind = root.bind;
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
