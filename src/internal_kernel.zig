const inner = @import("./internal/kernel.zig");

/// Re-exported checkpoint tag.
pub const CheckpointTag = inner.CheckpointTag;
/// Re-exported event type.
pub const Event = inner.Event;
/// Re-exported pending frame descriptor.
pub const PendingFrame = inner.PendingFrame;
/// Re-exported pending kind.
pub const PendingKind = inner.PendingKind;
/// Re-exported program value type.
pub const ProgramValue = inner.ProgramValue;
/// Re-exported prompt identifier.
pub const PromptId = inner.PromptId;
/// Re-exported scenario identifier.
pub const ScenarioId = inner.ScenarioId;
/// Re-exported machine state.
pub const State = inner.State;
/// Re-exported proof step.
pub const Step = inner.Step;
/// Re-exported trace checkpoint payload.
pub const TraceCheckpoint = inner.TraceCheckpoint;
/// Re-exported semantic value type.
pub const Value = inner.Value;
/// Re-exported checkpoint iterator.
pub const checkpoints = inner.checkpoints;
/// Re-exported event iterator.
pub const events = inner.events;
/// Re-exported step runner.
pub const runSteps = inner.runSteps;
/// Re-exported transcript writer.
pub const writeTranscript = inner.writeTranscript;
