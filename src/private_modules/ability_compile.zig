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
/// Compile one repo-owned source path into a typed ArtifactV1 emission surface.
pub const CompileSource = compile_api.CompileSource;
/// Compile one repo-owned source path and emit ArtifactV1 bytes immediately.
pub const compileAndEncode = compile_api.compileAndEncode;

test {
    _ = CompileOptionsV1;
    _ = CompileSource;
    _ = artifact;
    _ = compileAndEncode;
    _ = effect_ir;
    _ = lowering_api;
    _ = lower;
}
