const scenarios = @import("parity_scenarios");
const std = @import("std");

/// Runtime errors surfaced by the lowered-machine-backed canonical runtime.
pub const Error = error{
    CrossThread,
    FrontendSuspend,
    MissingPrompt,
    NonDiagonalComplete,
    ProgramContractViolation,
    RuntimeBusy,
    RuntimeDestroyed,
};

/// Runtime-visible error union for user-provided errors.
pub fn ControlError(comptime ErrorSet: type) type {
    return Error || ErrorSet;
}

/// Allocation failure that can still arise on the lowered runtime path.
pub const SetupError = error{OutOfMemory};

/// Reset-time error union for user-provided errors on the lowered runtime path.
pub fn ResetError(comptime ErrorSet: type) type {
    return ControlError(ErrorSet) || SetupError;
}

/// Canonical thread-affine runtime backed by the lowered execution backend.
pub const Runtime = struct {
    allocator: std.mem.Allocator,
    thread_id: std.Thread.Id,
    state: enum {
        alive,
        destroyed,
    } = .alive,
    active_reset_count: usize = 0,

    /// Initialize a runtime on the current thread.
    pub fn init(allocator: std.mem.Allocator) Runtime {
        return .{
            .allocator = allocator,
            .thread_id = std.Thread.getCurrentId(),
        };
    }

    /// Release runtime resources.
    pub fn deinit(self: *Runtime) void {
        self.deinitChecked() catch |err| switch (err) {
            error.CrossThread, error.RuntimeBusy => unreachable,
            else => unreachable,
        };
    }

    /// Release runtime resources, returning an error on misuse.
    pub fn deinitChecked(self: *Runtime) Error!void {
        try self.ensureThread();
        if (self.active_reset_count != 0) return error.RuntimeBusy;
        self.state = .destroyed;
    }

    /// Confirm the runtime is live and accessed from the owning thread.
    pub fn ensureThread(self: *Runtime) Error!void {
        if (self.thread_id != std.Thread.getCurrentId()) return error.CrossThread;
        if (self.state == .destroyed) return error.RuntimeDestroyed;
    }
};

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

/// Full typed execution state for one lowered-machine execution.
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

/// Execute one sequence of lowered machine steps to completion.
pub fn runSteps(steps: []const Step) MachineState {
    var state = MachineState{};
    for (steps) |step| applyStep(&state, step);
    return state;
}

/// Return the captured checkpoints for one machine execution.
pub fn checkpoints(state: *const MachineState) []const TraceCheckpoint {
    return state.checkpoints[0..state.checkpoint_len];
}

/// Return the transcript-projection events for one machine execution.
pub fn events(state: *const MachineState) []const Event {
    return state.events[0..state.event_len];
}

/// Render the exact-output transcript for one machine execution.
pub fn writeTranscript(writer: anytype, state: *const MachineState) anyerror!void {
    for (events(state)) |event| switch (event) {
        .note => |line| try writer.print("{s}\n", .{line}),
        .final_i32 => |value| try writer.print("final={d}\n", .{value}),
        .final_string => |value| try writer.print("final={s}\n", .{value}),
    };
}

/// Execute one explicit typed-value pure program to completion.
pub fn runExplicitPure(
    comptime PromptType: type,
    value: PromptType.InAnswer,
) anyerror!PromptType.OutAnswer {
    if (comptime PromptType.InAnswer == PromptType.OutAnswer) return value;
    return error.NonDiagonalComplete;
}

/// Execute one explicit typed-value transform program to completion.
pub fn runExplicitTransform(
    comptime PromptType: type,
    node: anytype,
) anyerror!PromptType.OutAnswer {
    const resume_value = try node.resumeValueFn();
    const in_answer = try node.continueFn(resume_value);
    return try node.afterResumeFn(in_answer);
}

/// Execute one explicit typed-value choice program to completion.
pub fn runExplicitChoice(
    comptime PromptType: type,
    node: anytype,
) anyerror!PromptType.OutAnswer {
    const decision = try node.decisionFn();
    return switch (decision) {
        .resume_with => |resume_value| blk: {
            const in_answer = try node.continueFn(resume_value);
            break :blk try node.afterResumeFn(in_answer);
        },
        .return_now => |answer| answer,
    };
}

/// Execute one explicit typed-value abortive program to completion.
pub fn runExplicitAbort(
    comptime PromptType: type,
    node: anytype,
) anyerror!PromptType.OutAnswer {
    return try node.directReturnFn();
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
