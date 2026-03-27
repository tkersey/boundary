const error_witness = @import("error_witness");
const lowered_machine = @import("lowered_machine");
const open_row_api = @import("open_row_api.zig");
const open_row_handlers = @import("open_row_handlers.zig");
const program_api = @import("program_api.zig");

/// Canonical lowered-first runtime handle.
pub const Runtime = lowered_machine.Runtime;
/// Public runtime misuse and semantic-contract errors surfaced by `shift`.
pub const RuntimeError = lowered_machine.RuntimeError;
/// Stable public error-witness schema.
pub const ErrorWitnessV1 = error_witness.ErrorWitnessV1;
/// Open-row transform descriptor.
pub const Transform = open_row_api.Transform;
/// Open-row choice descriptor.
pub const Choice = open_row_api.Choice;
/// Open-row abort descriptor.
pub const Abort = open_row_api.Abort;
/// Open-row run result wrapper.
pub const RunResult = open_row_api.RunResult;
/// Canonical open-row row builder.
pub const Row = open_row_api.Row;
/// Canonical open-row row merge helper.
pub const mergeRows = open_row_api.mergeRows;
/// Canonical builtin open-row fragments.
pub const effects = open_row_api.effects;
/// Canonical builtin handler bridge constructors.
pub const handlers = open_row_handlers;
/// Open-row capability-bundle carrier.
pub const Uses = open_row_api.Uses;
/// Canonical partial discharge helper.
pub const handle = open_row_api.handle;
/// Canonical full bind helper.
pub const bind = open_row_api.bind;
/// Root-level choice-decision helper for the front-door API.
pub const Decision = program_api.Decision;
/// Run one closed root with explicit runtime ownership.
pub fn run(runtime: *Runtime, closed_root: anytype) @TypeOf(open_row_api.runBound(runtime, closed_root)) {
    return open_row_api.runBound(runtime, closed_root);
}

test {
    _ = Decision;
    _ = ErrorWitnessV1;
    _ = Row;
    _ = Runtime;
    _ = RuntimeError;
    _ = bind;
    _ = handle;
    _ = mergeRows;
    _ = run;
}
