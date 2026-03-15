const scenarios = @import("parity_scenarios");

/// Stable scenario ids re-exported from the canonical scenario registry.
pub const ScenarioId = scenarios.ScenarioId;
/// Stable prompt ids re-exported from the canonical scenario registry.
pub const PromptId = scenarios.PromptId;
/// Pending continuation kinds re-exported from the canonical scenario registry.
pub const PendingKind = scenarios.PendingKind;
/// Typed proof values re-exported from the canonical scenario registry.
pub const Value = scenarios.Value;
/// Transcript events re-exported from the canonical scenario registry.
pub const Event = scenarios.Event;
/// Checkpoint tags re-exported from the canonical scenario registry.
pub const CheckpointTag = scenarios.CheckpointTag;
/// Pending frames re-exported from the canonical scenario registry.
pub const PendingFrame = scenarios.PendingFrame;
/// Trace checkpoints re-exported from the canonical scenario registry.
pub const TraceCheckpoint = scenarios.TraceCheckpoint;
/// Lowered proof steps re-exported from the canonical scenario registry.
pub const Step = scenarios.Step;

const empty_checkpoint = TraceCheckpoint{
    .tag = .atm_resume_prepared,
    .active_prompt = null,
    .pending_depth = 0,
    .top_pending_kind = null,
    .top_pending_prompt = null,
    .top_resume_value = .none,
    .final_result = .none,
};

const empty_event = Event{ .note = "" };

const empty_pending = PendingFrame{
    .kind = .resume_then_transform,
    .prompt = .primary,
    .resume_value = .none,
};

/// Full typed execution state for one canonical proof scenario.
pub const MachineState = struct {
    active_prompt: ?PromptId = null,
    checkpoints: [16]TraceCheckpoint = [_]TraceCheckpoint{empty_checkpoint} ** 16,
    checkpoint_len: usize = 0,
    events: [16]Event = [_]Event{empty_event} ** 16,
    event_len: usize = 0,
    final_result: Value = .none,
    pending: [8]PendingFrame = [_]PendingFrame{empty_pending} ** 8,
    pending_len: usize = 0,

    fn appendCheckpoint(self: *MachineState, tag: CheckpointTag) void {
        const top_pending = if (self.pending_len == 0) null else self.pending[self.pending_len - 1];
        self.checkpoints[self.checkpoint_len] = .{
            .tag = tag,
            .active_prompt = self.active_prompt,
            .pending_depth = self.pending_len,
            .top_pending_kind = if (top_pending) |frame| frame.kind else null,
            .top_pending_prompt = if (top_pending) |frame| frame.prompt else null,
            .top_resume_value = if (top_pending) |frame| frame.resume_value else .none,
            .final_result = self.final_result,
        };
        self.checkpoint_len += 1;
    }

    fn appendEvent(self: *MachineState, event: Event) void {
        self.events[self.event_len] = event;
        self.event_len += 1;
    }

    fn popPending(self: *MachineState) void {
        self.pending_len -= 1;
    }

    fn pushPending(self: *MachineState, frame: PendingFrame) void {
        self.pending[self.pending_len] = frame;
        self.pending_len += 1;
    }
};

/// Return the captured checkpoints for one scenario execution.
pub fn checkpoints(state: *const MachineState) []const TraceCheckpoint {
    return state.checkpoints[0..state.checkpoint_len];
}

/// Return the transcript-projection events for one scenario execution.
pub fn events(state: *const MachineState) []const Event {
    return state.events[0..state.event_len];
}

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
    var state = MachineState{};
    for (scenario.steps) |step| applyStep(&state, step);
    return state;
}

/// Render the exact-output transcript for one scenario execution.
pub fn writeTranscript(writer: anytype, state: *const MachineState) anyerror!void {
    for (events(state)) |event| switch (event) {
        .note => |line| try writer.print("{s}\n", .{line}),
        .final_i32 => |value| try writer.print("final={d}\n", .{value}),
        .final_string => |value| try writer.print("final={s}\n", .{value}),
    };
}

fn applyStep(state: *MachineState, step: Step) void {
    switch (step) {
        .checkpoint => |tag| state.appendCheckpoint(tag),
        .emit => |event| state.appendEvent(event),
        .pop_pending => state.popPending(),
        .push_pending => |frame| state.pushPending(frame),
        .set_active_prompt => |prompt| state.active_prompt = prompt,
        .set_final => |value| state.final_result = value,
    }
}
