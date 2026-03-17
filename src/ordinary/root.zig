const lowering = @import("ordinary_zig_lowering");

/// Canonical source-backed lowering surface for the repo-owned ordinary corpus.
pub const GeneratedProgram = lowering.GeneratedProgram;
/// Status for one source-backed ordinary lowering attempt.
pub const LowerStatus = lowering.LowerStatus;
/// Source classification for one ordinary lowering request.
pub const SurfaceKind = lowering.SurfaceKind;
/// Input specification for one ordinary lowering request.
pub const Spec = lowering.Spec;
/// Diagnostic emitted by the ordinary lowerer.
pub const Diagnostic = lowering.Diagnostic;
/// One lowered-machine step exposed through the public ordinary surface.
pub const Step = lowering.Step;
/// Lower one restricted ordinary-Zig source file.
pub const inspectSource = lowering.inspectSource;
/// Execute one generated lowered program and render its transcript.
pub const runLowered = lowering.runLowered;

test {
    _ = lowering;
}
