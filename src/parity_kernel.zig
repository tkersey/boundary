const interpreter = @import("interpreter");
const scenarios = @import("parity_scenarios");

/// Stable scenario ids re-exported from the shared lowered machine.
pub const ScenarioId = interpreter.ScenarioId;
/// Stable prompt ids re-exported from the shared lowered machine.
pub const PromptId = interpreter.PromptId;
/// Pending continuation kinds re-exported from the shared lowered machine.
pub const PendingKind = interpreter.PendingKind;
/// Typed proof values re-exported from the shared lowered machine.
pub const Value = interpreter.Value;
/// Transcript events re-exported from the shared lowered machine.
pub const Event = interpreter.Event;
/// Checkpoint tags re-exported from the shared lowered machine.
pub const CheckpointTag = interpreter.CheckpointTag;
/// Pending frames re-exported from the shared lowered machine.
pub const PendingFrame = interpreter.PendingFrame;
/// Trace checkpoints re-exported from the shared lowered machine.
pub const TraceCheckpoint = interpreter.TraceCheckpoint;
/// Lowered proof steps re-exported from the shared lowered machine.
pub const Step = interpreter.Step;
/// Full typed execution state re-exported from the shared lowered machine.
pub const MachineState = interpreter.MachineState;

/// Return the captured checkpoints for one lowered machine execution.
pub const checkpoints = interpreter.checkpoints;
/// Return the transcript-projection events for one lowered machine execution.
pub const events = interpreter.events;
/// Render the exact-output transcript for one lowered machine execution.
pub const writeTranscript = interpreter.writeTranscript;

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
    return interpreter.runSteps(scenario.steps);
}
