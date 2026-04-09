const compile_api = @import("shift_compile_api.zig");
const shared = @import("shift_shared");

/// Public explicit compile-time IR surface.
pub const ir = shared.ir;
/// Public lowering and source-provenance surface.
pub const lowering = shared.lowering;
/// Public compile helper from explicit lowering inputs to the runtime-owned plan bridge.
pub const lower = shared.lower;
/// ArtifactV1 encoding and decoding helpers shared with `shift_vm`.
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
    _ = ir;
    _ = lowering;
    _ = lower;
}
