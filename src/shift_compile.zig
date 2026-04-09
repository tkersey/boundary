const shared = @import("shift_shared");
const compile_api = @import("shift_compile_api.zig");

/// Public explicit compile-time IR surface.
pub const ir = shared.ir;
/// Public lowering and source-provenance surface.
pub const lowering = shared.lowering;
/// Public compile helper from explicit lowering inputs to the runtime-owned plan bridge.
pub const lower = shared.lower;
pub const artifact = shared.artifact;
pub const CompileOptionsV1 = compile_api.CompileOptionsV1;
pub const compileSource = compile_api.compileSource;
pub const compileAndEncode = compile_api.compileAndEncode;

test {
    _ = CompileOptionsV1;
    _ = artifact;
    _ = compileAndEncode;
    _ = compileSource;
    _ = ir;
    _ = lowering;
    _ = lower;
}
