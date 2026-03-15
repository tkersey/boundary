const lowered_machine = @import("lowered_machine");
const scenarios = @import("parity_scenarios");

/// Stable scenario ids re-exported from the shared lowered machine.
pub const ScenarioId = lowered_machine.ScenarioId;
/// Stable prompt ids re-exported from the shared lowered machine.
pub const PromptId = lowered_machine.PromptId;
/// Pending continuation kinds re-exported from the shared lowered machine.
pub const PendingKind = lowered_machine.PendingKind;
/// Typed proof values re-exported from the shared lowered machine.
pub const Value = lowered_machine.Value;
/// Transcript events re-exported from the shared lowered machine.
pub const Event = lowered_machine.Event;
/// Checkpoint tags re-exported from the shared lowered machine.
pub const CheckpointTag = lowered_machine.CheckpointTag;
/// Pending frames re-exported from the shared lowered machine.
pub const PendingFrame = lowered_machine.PendingFrame;
/// Trace checkpoints re-exported from the shared lowered machine.
pub const TraceCheckpoint = lowered_machine.TraceCheckpoint;
/// Lowered proof steps re-exported from the shared lowered machine.
pub const Step = lowered_machine.Step;
/// Full typed execution state re-exported from the shared lowered machine.
pub const MachineState = lowered_machine.MachineState;

/// Return the captured checkpoints for one lowered machine execution.
pub const checkpoints = lowered_machine.checkpoints;
/// Return the transcript-projection events for one lowered machine execution.
pub const events = lowered_machine.events;
/// Render the exact-output transcript for one lowered machine execution.
pub const writeTranscript = lowered_machine.writeTranscript;

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
    return lowered_machine.runSteps(scenario.steps);
}
