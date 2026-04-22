const artifact_api = @import("artifact_api");
const effect_root = @import("effect/root.zig");
const error_witness = @import("error_witness");
const interpreter_api = @import("interpreter");
const ir_api = @import("ir_api");
const lowered_machine = @import("lowered_machine");
const lowering_api = @import("lowering_api");
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
/// Public `with(...)` helper retained at the root surface.
pub const with = with_api.with;

/// Interpreter namespace retained for compatibility surfaces.
pub const interpreter = interpreter_api;
/// Public semantic-error witness surface.
pub const ErrorWitnessV1 = error_witness.ErrorWitnessV1;

/// Retained explicit IR compatibility surface shared by `shift` and `shift_compile`.
// zlinter-disable-next-line declaration_naming - retained public API contract is shift.ir
pub const ir = ir_api;
/// Public lowering namespace retained for shared build wiring.
pub const lowering = lowering_api;
/// Public lowering entrypoint retained for shared build wiring.
pub const lower = lowering_api.lower;
/// Internal lowered runtime surface re-exported for sibling wrapper modules.
pub const lowered_machine_internal = lowered_machine;
/// Internal program-plan surface re-exported for sibling wrapper modules.
pub const internal_program_plan = @import("internal_program_plan");
