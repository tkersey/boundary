const kernel = @import("internal_kernel");

/// Stable scenario ids re-exported from the internal kernel.
pub const ScenarioId = kernel.ScenarioId;
/// Stable prompt ids re-exported from the internal kernel.
pub const PromptId = kernel.PromptId;
/// Pending continuation kinds re-exported from the internal kernel.
pub const PendingKind = kernel.PendingKind;
/// Typed proof values re-exported from the internal kernel.
pub const Value = kernel.Value;
/// Narrow typed program values used by the explicit canonical program path.
pub const ProgramValue = kernel.ProgramValue;
/// Transcript events re-exported from the internal kernel.
pub const Event = kernel.Event;
/// Checkpoint tags re-exported from the internal kernel.
pub const CheckpointTag = kernel.CheckpointTag;
/// Pending frames re-exported from the internal kernel.
pub const PendingFrame = kernel.PendingFrame;
/// Trace checkpoints re-exported from the internal kernel.
pub const TraceCheckpoint = kernel.TraceCheckpoint;
/// Lowered proof steps re-exported from the internal kernel.
pub const Step = kernel.Step;
/// Full typed execution state for one interpreter execution.
pub const State = kernel.State;
/// Back-compat alias while callers migrate off `MachineState`.
pub const MachineState = kernel.State;
/// Execute one sequence of interpreter steps to completion.
pub const runSteps = kernel.runSteps;
/// Return the captured checkpoints for one interpreter execution.
pub const checkpoints = kernel.checkpoints;
/// Return the transcript-projection events for one interpreter execution.
pub const events = kernel.events;
/// Render the exact-output transcript for one interpreter execution.
pub const writeTranscript = kernel.writeTranscript;
