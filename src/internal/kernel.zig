const scenarios = @import("parity_scenarios");
const std = @import("std");

/// Stable scenario ids re-exported from the canonical scenario registry.
pub const ScenarioId = scenarios.ScenarioId;
/// Stable prompt ids re-exported from the canonical scenario registry.
pub const PromptId = scenarios.PromptId;
/// Pending continuation kinds re-exported from the canonical scenario registry.
pub const PendingKind = scenarios.PendingKind;
/// Typed proof values re-exported from the canonical scenario registry.
pub const Value = scenarios.Value;
/// Narrow typed program values used by the explicit canonical program path.
pub const ProgramValue = union(enum) {
    bool: bool,
    i32: i32,
    none,
    string: []const u8,
    usize: usize,
};
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

/// Full typed execution state for one kernel execution.
pub const State = struct {
    active_prompt: ?PromptId = null,
    checkpoints: [16]TraceCheckpoint = [_]TraceCheckpoint{empty_checkpoint} ** 16,
    checkpoint_len: usize = 0,
    events: [16]Event = [_]Event{empty_event} ** 16,
    event_len: usize = 0,
    final_result: Value = .none,
    pending: [8]PendingFrame = [_]PendingFrame{empty_pending} ** 8,
    pending_len: usize = 0,

    fn appendCheckpoint(self: *State, tag: CheckpointTag) void {
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

    fn appendEvent(self: *State, event: Event) void {
        self.events[self.event_len] = event;
        self.event_len += 1;
    }

    fn popPending(self: *State) void {
        self.pending_len -= 1;
    }

    fn pushPending(self: *State, frame: PendingFrame) void {
        self.pending[self.pending_len] = frame;
        self.pending_len += 1;
    }
};

/// Execute one sequence of kernel steps to completion.
pub fn runSteps(steps: []const Step) State {
    var state = State{};
    for (steps) |step| applyStep(&state, step);
    return state;
}

/// Return the captured checkpoints for one kernel execution.
pub fn checkpoints(state: *const State) []const TraceCheckpoint {
    return state.checkpoints[0..state.checkpoint_len];
}

/// Return the transcript-projection events for one kernel execution.
pub fn events(state: *const State) []const Event {
    return state.events[0..state.event_len];
}

/// Render the exact-output transcript for one kernel execution.
pub fn writeTranscript(writer: anytype, state: *const State) anyerror!void {
    for (events(state)) |event| switch (event) {
        .note => |line| try writer.print("{s}\n", .{line}),
        .final_i32 => |value| try writer.print("final={d}\n", .{value}),
        .final_string => |value| try writer.print("final={s}\n", .{value}),
    };
}

fn applyStep(state: *State, step: Step) void {
    switch (step) {
        .checkpoint => |tag| state.appendCheckpoint(tag),
        .emit => |event| state.appendEvent(event),
        .pop_pending => state.popPending(),
        .push_pending => |frame| state.pushPending(frame),
        .set_active_prompt => |prompt| state.active_prompt = prompt,
        .set_final => |value| state.final_result = value,
    }
}

test "runSteps records checkpoints and transcript events without host runtime state" {
    const state = runSteps(&.{
        .{ .set_active_prompt = .primary },
        .{ .push_pending = .{ .kind = .resume_then_transform, .prompt = .primary, .resume_value = .{ .i32 = 41 } } },
        .{ .checkpoint = .atm_resume_prepared },
        .{ .emit = .{ .note = "handler-enter" } },
        .{ .set_final = .{ .i32 = 42 } },
    });

    try std.testing.expectEqual(@as(usize, 1), checkpoints(&state).len);
    try std.testing.expectEqual(@as(usize, 1), events(&state).len);
    try std.testing.expectEqual(@as(?PromptId, .primary), state.active_prompt);
    try std.testing.expectEqual(@as(usize, 1), state.pending_len);
}
