const shared = @import("shift_shared");

/// Public lexical effect namespace.
pub const effect = shared.effect;
/// Canonical runtime handle for lexical execution.
pub const Runtime = shared.Runtime;
/// Public runtime misuse and semantic-contract errors surfaced by `shift`.
pub const RuntimeError = shared.RuntimeError;
/// Run the public lexical handler entrypoint.
pub const with = shared.with;

test {
    _ = Runtime;
    _ = RuntimeError;
    _ = effect;
    _ = with;
}

test "retained public_ir/public_lowering imports stay source-compatible" {
    const public_ir = @import("public_ir");
    const public_lowering = @import("public_lowering");
    const std = @import("std");

    try std.testing.expect(public_ir.Program == shared.ir.Program);
    try std.testing.expect(public_lowering.ProgramPlan == shared.lowering.ProgramPlan);
    try std.testing.expect(@hasDecl(public_ir, "compile"));
    try std.testing.expect(@hasDecl(public_lowering, "lowerAt"));
}
