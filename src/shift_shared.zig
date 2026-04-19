const artifact_api = @import("artifact_api");
const compat_api = @import("compat.zig");
const effect_root = @import("effect/root.zig");
const error_witness = @import("error_witness");
const interpreter_api = @import("interpreter");
const lowered_machine = @import("lowered_machine");
const public_ir = @import("public_ir");
const public_lowering = @import("public_lowering");
const with_api = @import("with_api.zig");

/// Shared ArtifactV1 codec and helpers used by the retained public roots.
pub const artifact = artifact_api;
/// Public effect family and handler constructors retained at the root surface.
pub const effect = effect_root;
/// Canonical lowered runtime retained at the root surface.
pub const Runtime = lowered_machine.Runtime;
/// Public runtime misuse and semantic-contract errors retained at the root surface.
pub const RuntimeError = lowered_machine.RuntimeError;
/// Public `With` helper retained at the root surface.
pub const With = with_api.With;
/// Canonical named lexical body helper retained at the root surface.
pub const NamedBody = with_api.NamedBody;
/// Explicit caller-owned source witness retained for `withOwnedSource(...)`.
pub const OwnedSourceWitness = with_api.OwnedSourceWitness;
/// Public `with(...)` helper retained at the root surface.
pub const with = with_api.with;
/// Public `withAt(...)` helper retained for explicit caller provenance.
pub const withAt = with_api.withAt;
/// Public `withOwnedSource(...)` helper retained for explicit caller-owned lexical compilation witnesses.
pub const withOwnedSource = with_api.withOwnedSource;

/// Compatibility API namespace retained for existing `shift.compat.*` users.
pub const compat = compat_api;
/// Interpreter namespace retained for compatibility surfaces.
pub const interpreter = interpreter_api;
/// Public semantic-error witness surface.
pub const ErrorWitnessV1 = error_witness.ErrorWitnessV1;
/// Retained compatibility declaration vocabulary.
pub const Decl = compat_api.Decl;
/// Retained compatibility operation vocabulary.
pub const Op = compat_api.Op;
/// Retained compatibility decision vocabulary.
pub const Decision = compat_api.Decision;
/// Retained compatibility program vocabulary.
pub const Program = compat_api.Program;
/// Retained compatibility execution helper.
pub const run = compat_api.run;

/// Retained explicit IR compatibility surface shared by `shift` and `shift_compile`.
// zlinter-disable-next-line declaration_naming - retained public API contract is shift.ir
pub const ir = public_ir;
/// Public lowering namespace retained for shared build wiring.
pub const lowering = public_lowering;
/// Public lowering entrypoint retained for shared build wiring.
pub const lower = public_lowering.lower;
/// Internal lowered runtime surface re-exported for sibling wrapper modules.
pub const lowered_machine_internal = lowered_machine;
/// Internal program-plan surface re-exported for sibling wrapper modules.
pub const internal_program_plan = @import("internal_program_plan");
