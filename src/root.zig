const lowered_machine = @import("lowered_machine");
const error_witness = @import("error_witness");
const program_api = @import("program_api.zig");
const with_api = @import("with_api.zig");

/// Canonical lowered-first runtime handle.
pub const Runtime = lowered_machine.Runtime;
/// Public runtime misuse and semantic-contract errors surfaced by `shift`.
pub const RuntimeError = lowered_machine.RuntimeError;
/// Stable public error-witness schema.
pub const ErrorWitnessV1 = error_witness.ErrorWitnessV1;
/// Root-level choice-decision helper for the front-door API.
pub const Decision = program_api.Decision;
/// Unified declaration namespace for the front-door API.
pub const Decl = program_api.Decl;
/// Unified op-descriptor namespace for the front-door API.
pub const Op = program_api.Op;
/// Compatibility namespace for legacy root lanes.
pub const compat = @import("compat/root.zig");
/// Root-first authored program surface.
pub const Program = program_api.Program;
/// Generalized algebraic-effect builders over the core shift/reset runtime.
pub const algebraic = @import("algebraic.zig");
/// Additive algebraic-effect families built on top of the core shift/reset runtime.
pub const effect = @import("effect/root.zig");
/// Canonical source-backed lowering surface for the repo-owned ordinary corpus.
pub const ordinary = @import("ordinary/root.zig");

/// Canonical lexical product returned from `shift.with(...)`.
pub fn With(comptime HandlersType: type, comptime Body: type) type {
    return with_api.With(HandlersType, Body);
}

/// Run one ordinary Zig body against a lexical effect-handle bundle.
pub fn with(
    runtime: *Runtime,
    handlers: anytype,
    comptime Body: type,
) with_api.WithFnReturnType(@TypeOf(handlers), Body) {
    return with_api.with(runtime, handlers, Body);
}

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
    _ = With;
    _ = effect;
    _ = algebraic;
    _ = compat;
    _ = ordinary;
    _ = run;
    _ = with;
}
