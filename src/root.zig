const error_witness = @import("error_witness");
const lowered_machine = @import("lowered_machine");
const program_api = @import("program_api.zig");

/// Canonical lowered-first runtime handle.
pub const Runtime = lowered_machine.Runtime;
/// Public runtime misuse and semantic-contract errors surfaced by `shift`.
pub const RuntimeError = lowered_machine.RuntimeError;
/// Stable public error-witness schema.
pub const ErrorWitnessV1 = error_witness.ErrorWitnessV1;
/// Root-level choice-decision helper for the front-door API.
pub const Decision = program_api.Decision;
/// Unified declaration namespace for the front-door API.
pub const Decl = @import("root_decl_api.zig").Decl;
/// Unified op-descriptor namespace for the front-door API.
pub const Op = @import("root_op_api.zig").Op;
/// Root-first authored program surface.
pub const Program = program_api.Program;

/// Run one front-door authored program with explicit runtime ownership.
pub fn run(runtime: *Runtime, comptime ProgramType: type, bindings: ProgramType.Bindings) program_api.RunReturnType(ProgramType) {
    return program_api.run(runtime, ProgramType, bindings);
}

test {
    _ = Decl;
    _ = Decision;
    _ = ErrorWitnessV1;
    _ = Op;
    _ = Program;
    _ = Runtime;
    _ = RuntimeError;
    _ = run;
}
