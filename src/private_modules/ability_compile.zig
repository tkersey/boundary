const compile_api = @import("ability_compile_api");
const shared = @import("ability_shared");

/// Retained internal explicit compile-time IR surface.
pub const effect_ir = shared.ir;
/// Retained internal lowering and source-provenance surface.
pub const lowering_api = shared.lowering;
/// Retained internal compile helper from explicit lowering inputs to the runtime-owned plan bridge.
pub const lower = shared.lower;
/// Retained internal ArtifactV1 encoding and decoding helpers used by internal compile paths.
pub const artifact = shared.artifact;
/// Compile-time options for ArtifactV1 emission.
pub const CompileOptionsV1 = compile_api.CompileOptionsV1;
/// Compile one runtime-owned ProgramPlan into a typed execution and ArtifactV1 surface.
pub const CompilePlan = compile_api.CompilePlan;
/// ProgramPlan-first compile entrypoint.
pub const compile = compile_api.compile;

test {
    _ = CompileOptionsV1;
    _ = CompilePlan;
    _ = compile;
    _ = artifact;
    _ = effect_ir;
    _ = lowering_api;
    _ = lower;
}
