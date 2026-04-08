const program_plan = @import("internal_program_plan");
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
/// Runtime-owned executable plan re-export.
pub const ProgramPlan = program_plan.ProgramPlan;
/// Runtime-owned function descriptor re-export.
pub const FunctionPlan = program_plan.FunctionPlan;
/// Runtime-owned requirement descriptor re-export.
pub const RequirementPlan = program_plan.RequirementPlan;
/// Runtime-owned op descriptor re-export.
pub const OpPlan = program_plan.OpPlan;
/// Runtime-owned output descriptor re-export.
pub const OutputPlan = program_plan.OutputPlan;
/// Runtime-owned local descriptor re-export.
pub const LocalPlan = program_plan.LocalPlan;
/// Runtime-owned block descriptor re-export.
pub const BlockPlan = program_plan.BlockPlan;
/// Runtime-owned terminator descriptor re-export.
pub const Terminator = program_plan.Terminator;
/// Runtime-owned instruction descriptor re-export.
pub const Instruction = program_plan.Instruction;
/// Runtime-owned instruction-tag descriptor re-export.
pub const InstructionKind = program_plan.InstructionKind;
/// Runtime-owned terminator-tag descriptor re-export.
pub const TerminatorKind = program_plan.TerminatorKind;
/// Runtime-owned value codec re-export.
pub const ValueCodec = program_plan.ValueCodec;
/// Runtime-owned control-mode tag re-export.
pub const PlanControlMode = program_plan.ControlMode;
/// Runtime-owned plan validation error re-export.
pub const ProgramPlanValidationError = program_plan.ValidationError;
/// Runtime-owned plan compiler re-export.
pub const planFromProgram = program_plan.planFromProgram;
/// Runtime-owned legacy plan schema upgrader re-export.
pub const upgradeLegacyProgramPlan = program_plan.upgradeLegacyProgramPlan;
/// Runtime-owned full-program identity hash helper re-export.
pub const irHashForProgram = program_plan.irHashForProgram;
/// Value codec helper re-export.
pub const codecForType = program_plan.codecForType;
/// Value codec payload helper re-export.
pub const hasPlanPayload = program_plan.hasPayload;

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

const max_checkpoints = 16;
const max_events = 16;
const max_pending_frames = 8;

/// Validation errors for fixed-capacity kernel transcript replay.
pub const StepValidationError = error{
    PendingFrameUnderflow,
    TooManyCheckpoints,
    TooManyEvents,
    TooManyPendingFrames,
};

/// Full typed execution state for one kernel execution.
pub const State = struct {
    active_prompt: ?PromptId = null,
    checkpoints: [max_checkpoints]TraceCheckpoint = [_]TraceCheckpoint{empty_checkpoint} ** max_checkpoints,
    checkpoint_len: usize = 0,
    events: [max_events]Event = [_]Event{empty_event} ** max_events,
    event_len: usize = 0,
    final_result: Value = .none,
    pending: [max_pending_frames]PendingFrame = [_]PendingFrame{empty_pending} ** max_pending_frames,
    pending_len: usize = 0,

    fn appendCheckpoint(self: *State, tag: CheckpointTag) void {
        std.debug.assert(self.checkpoint_len < self.checkpoints.len);
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
        std.debug.assert(self.event_len < self.events.len);
        self.events[self.event_len] = event;
        self.event_len += 1;
    }

    fn popPending(self: *State) void {
        std.debug.assert(self.pending_len != 0);
        self.pending_len -= 1;
    }

    fn pushPending(self: *State, frame: PendingFrame) void {
        std.debug.assert(self.pending_len < self.pending.len);
        self.pending[self.pending_len] = frame;
        self.pending_len += 1;
    }
};

/// Reject one step transcript that would overflow the fixed-capacity replay state.
pub fn validateStepCapacity(steps: []const Step) StepValidationError!void {
    var checkpoint_len: usize = 0;
    var event_len: usize = 0;
    var pending_len: usize = 0;

    for (steps) |step| switch (step) {
        .checkpoint => {
            if (checkpoint_len >= max_checkpoints) return error.TooManyCheckpoints;
            checkpoint_len += 1;
        },
        .emit => {
            if (event_len >= max_events) return error.TooManyEvents;
            event_len += 1;
        },
        .push_pending => {
            if (pending_len >= max_pending_frames) return error.TooManyPendingFrames;
            pending_len += 1;
        },
        .pop_pending => {
            if (pending_len == 0) return error.PendingFrameUnderflow;
            pending_len -= 1;
        },
        else => {},
    };
}

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

test "validateStepCapacity rejects oversized transcripts before replay" {
    var too_many_checkpoints: [max_checkpoints + 1]Step = undefined;
    for (&too_many_checkpoints) |*step| step.* = .{ .checkpoint = .atm_resume_prepared };
    try std.testing.expectError(error.TooManyCheckpoints, validateStepCapacity(&too_many_checkpoints));

    var too_many_events: [max_events + 1]Step = undefined;
    for (&too_many_events) |*step| step.* = .{ .emit = .{ .note = "queued" } };
    try std.testing.expectError(error.TooManyEvents, validateStepCapacity(&too_many_events));

    var too_many_pending: [max_pending_frames + 1]Step = undefined;
    for (&too_many_pending) |*step| step.* = .{ .push_pending = .{
        .kind = .resume_then_transform,
        .prompt = .primary,
        .resume_value = .none,
    } };
    try std.testing.expectError(error.TooManyPendingFrames, validateStepCapacity(&too_many_pending));

    try std.testing.expectError(error.PendingFrameUnderflow, validateStepCapacity(&.{.pop_pending}));
}
