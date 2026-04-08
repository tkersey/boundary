const kernel = @import("internal_kernel");
const scenarios = @import("parity_scenarios");

/// Stable scenario ids re-exported from the shared lowered machine.
pub const ScenarioId = kernel.ScenarioId;
/// Stable prompt ids re-exported from the shared lowered machine.
pub const PromptId = kernel.PromptId;
/// Pending continuation kinds re-exported from the shared lowered machine.
pub const PendingKind = kernel.PendingKind;
/// Typed proof values re-exported from the shared lowered machine.
pub const Value = kernel.Value;
/// Transcript events re-exported from the shared lowered machine.
pub const Event = kernel.Event;
/// Checkpoint tags re-exported from the shared lowered machine.
pub const CheckpointTag = kernel.CheckpointTag;
/// Pending frames re-exported from the shared lowered machine.
pub const PendingFrame = kernel.PendingFrame;
/// Trace checkpoints re-exported from the shared lowered machine.
pub const TraceCheckpoint = kernel.TraceCheckpoint;
/// Lowered proof steps re-exported from the shared lowered machine.
pub const Step = kernel.Step;
/// Full typed execution state re-exported from the shared lowered machine.
pub const MachineState = kernel.State;

/// Return the captured checkpoints for one lowered machine execution.
pub const checkpoints = kernel.checkpoints;
/// Return the transcript-projection events for one lowered machine execution.
pub const events = kernel.events;
/// Render the exact-output transcript for one lowered machine execution.
pub const writeTranscript = kernel.writeTranscript;

/// Map a parity case id to the scenario id that owns it.
pub fn scenarioForCaseId(case_id: []const u8) ?ScenarioId {
    if (scenarios.find(case_id)) |scenario| return scenario.scenario_id;
    return null;
}

/// Execute one canonical proof scenario by stable case id.
pub fn runCaseId(case_id: []const u8) error{UnknownScenario}!MachineState {
    const scenario = scenarios.find(case_id) orelse return error.UnknownScenario;
    return runScenario(scenario.scenario_id);
}

/// Execute one canonical proof scenario to completion.
pub fn runScenario(id: ScenarioId) MachineState {
    const scenario = scenarios.byId(id);
    return kernel.runSteps(scenario.steps);
}
