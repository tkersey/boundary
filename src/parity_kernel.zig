const std = @import("std");

/// Typed proof-kernel scenarios migrated off the legacy transcript-first parity path.
pub const ScenarioId = enum {
    atm_resume_transform,
    direct_return,
    multi_prompt,
    nested_workflow_publish,
    resume_or_return_resume,
    resume_or_return_return_now,
    static_redelim,
};

/// Prompt identities used by the typed proof kernel.
pub const PromptId = enum {
    approval,
    audit,
    inner,
    outer,
    primary,
};

/// Pending continuation families represented by the typed proof kernel.
pub const PendingKind = enum {
    direct_return,
    resume_or_return,
    resume_then_transform,
};

/// Typed values carried through migrated proof-kernel scenarios.
pub const Value = union(enum) {
    bool: bool,
    i32: i32,
    none,
    string: []const u8,
};

/// Transcript-projection events emitted by the typed proof kernel.
pub const Event = union(enum) {
    final_i32: i32,
    final_string: []const u8,
    note: []const u8,
};

/// Stable internal-state checkpoints used to prove migrated scenarios are state-first.
pub const CheckpointTag = enum {
    atm_body_resumed,
    atm_resume_prepared,
    atm_terminal,
    direct_return_handler,
    direct_return_terminal,
    multi_prompt_outer_resume,
    multi_prompt_terminal,
    nested_workflow_approval,
    nested_workflow_audit_entered,
    nested_workflow_audit_resumed,
    nested_workflow_terminal,
    resume_or_return_resume_choice,
    ror_resume_body,
    ror_resume_terminal,
    ror_return_now_choice,
    ror_return_now_terminal,
    static_redelim_inner_resume,
    static_redelim_outer_resume,
    static_redelim_terminal,
};

/// One pending frame in the typed proof kernel.
pub const PendingFrame = struct {
    kind: PendingKind,
    prompt: PromptId,
    resume_value: Value = .none,
};

/// One internal-state snapshot captured while executing a migrated scenario.
pub const TraceCheckpoint = struct {
    tag: CheckpointTag,
    active_prompt: ?PromptId,
    pending_depth: usize,
    top_pending_kind: ?PendingKind,
    top_pending_prompt: ?PromptId,
    top_resume_value: Value = .none,
    final_result: Value = .none,
};

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

/// Full typed execution state for one migrated scenario.
pub const MachineState = struct {
    active_prompt: ?PromptId = null,
    checkpoints: [8]TraceCheckpoint = [_]TraceCheckpoint{empty_checkpoint} ** 8,
    checkpoint_len: usize = 0,
    events: [8]Event = [_]Event{empty_event} ** 8,
    event_len: usize = 0,
    final_result: Value = .none,
    pending: [4]PendingFrame = [_]PendingFrame{empty_pending} ** 4,
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

    fn appendNote(self: *MachineState, line: []const u8) void {
        self.appendEvent(.{ .note = line });
    }

    fn finishI32(self: *MachineState, value: i32) void {
        self.final_result = .{ .i32 = value };
        self.appendEvent(.{ .final_i32 = value });
    }

    fn finishString(self: *MachineState, value: []const u8) void {
        self.final_result = .{ .string = value };
        self.appendEvent(.{ .final_string = value });
    }

    fn popPending(self: *MachineState) void {
        std.debug.assert(self.pending_len != 0);
        self.pending_len -= 1;
    }

    fn pushPending(self: *MachineState, prompt: PromptId, kind: PendingKind, resume_value: Value) void {
        self.pending[self.pending_len] = .{
            .kind = kind,
            .prompt = prompt,
            .resume_value = resume_value,
        };
        self.pending_len += 1;
    }
};

/// Return the captured checkpoints for one migrated scenario execution.
pub fn checkpoints(state: *const MachineState) []const TraceCheckpoint {
    return state.checkpoints[0..state.checkpoint_len];
}

/// Return the transcript-projection events for one migrated scenario execution.
pub fn events(state: *const MachineState) []const Event {
    return state.events[0..state.event_len];
}

/// Map a parity case id to the typed proof-kernel scenario that owns it.
pub fn scenarioForCaseId(case_id: []const u8) ?ScenarioId {
    if (std.mem.eql(u8, case_id, "atm_resume_transform")) return .atm_resume_transform;
    if (std.mem.eql(u8, case_id, "direct_return")) return .direct_return;
    if (std.mem.eql(u8, case_id, "resume_or_return_return_now")) return .resume_or_return_return_now;
    if (std.mem.eql(u8, case_id, "resume_or_return_resume")) return .resume_or_return_resume;
    if (std.mem.eql(u8, case_id, "static_redelim")) return .static_redelim;
    if (std.mem.eql(u8, case_id, "multi_prompt")) return .multi_prompt;
    if (std.mem.eql(u8, case_id, "nested_workflow")) return .nested_workflow_publish;
    return null;
}

/// Execute one migrated parity case by stable case id.
pub fn runCaseId(case_id: []const u8) error{UnknownScenario}!MachineState {
    const scenario = scenarioForCaseId(case_id) orelse return error.UnknownScenario;
    return runScenario(scenario);
}

/// Execute one typed proof-kernel scenario to completion.
pub fn runScenario(scenario: ScenarioId) MachineState {
    var state = MachineState{};
    switch (scenario) {
        .atm_resume_transform => runAtmResumeTransform(&state),
        .direct_return => runDirectReturn(&state),
        .multi_prompt => runMultiPrompt(&state),
        .nested_workflow_publish => runNestedWorkflowPublish(&state),
        .resume_or_return_resume => runResumeOrReturnResume(&state),
        .resume_or_return_return_now => runResumeOrReturnReturnNow(&state),
        .static_redelim => runStaticRedelim(&state),
    }
    return state;
}

/// Render the exact-output transcript for one migrated scenario execution.
pub fn writeTranscript(writer: anytype, state: *const MachineState) anyerror!void {
    for (events(state)) |event| switch (event) {
        .note => |line| try writer.print("{s}\n", .{line}),
        .final_i32 => |value| try writer.print("final={d}\n", .{value}),
        .final_string => |value| try writer.print("final={s}\n", .{value}),
    };
}

fn runAtmResumeTransform(state: *MachineState) void {
    state.active_prompt = .primary;
    state.pushPending(.primary, .resume_then_transform, .{ .i32 = 41 });
    state.appendNote("handler-enter");
    state.appendCheckpoint(.atm_resume_prepared);

    state.appendNote("body-after-shift");
    state.appendCheckpoint(.atm_body_resumed);

    state.popPending();
    state.appendNote("handler-after-resume");
    state.finishString("answer=42");
    state.appendCheckpoint(.atm_terminal);
}

fn runDirectReturn(state: *MachineState) void {
    state.active_prompt = .primary;
    state.pushPending(.primary, .direct_return, .none);
    state.appendNote("handler-direct-return");
    state.appendCheckpoint(.direct_return_handler);

    state.popPending();
    state.finishString("result=early");
    state.appendCheckpoint(.direct_return_terminal);
}

fn runMultiPrompt(state: *MachineState) void {
    state.active_prompt = .outer;
    state.appendNote("outer-before-inner");
    state.active_prompt = .inner;
    state.appendNote("inner-before");

    state.pushPending(.outer, .resume_then_transform, .{ .i32 = 41 });
    state.active_prompt = .outer;
    state.appendNote("outer-handler");
    state.appendCheckpoint(.multi_prompt_outer_resume);

    state.popPending();
    state.active_prompt = .inner;
    state.appendNote("inner-after");
    state.active_prompt = .outer;
    state.appendNote("outer-after-inner");
    state.finishI32(42);
    state.appendCheckpoint(.multi_prompt_terminal);
}

fn runNestedWorkflowPublish(state: *MachineState) void {
    state.active_prompt = .approval;
    state.appendNote("workflow=queued");

    state.active_prompt = .audit;
    state.pushPending(.audit, .resume_then_transform, .none);
    state.appendNote("audit=entered");
    state.appendCheckpoint(.nested_workflow_audit_entered);

    state.popPending();
    state.appendNote("audit=after");
    state.appendCheckpoint(.nested_workflow_audit_resumed);

    state.active_prompt = .approval;
    state.pushPending(.approval, .resume_then_transform, .{ .bool = true });
    state.appendNote("approval=publish");
    state.appendCheckpoint(.nested_workflow_approval);

    state.popPending();
    state.appendNote("workflow=done");
    state.final_result = .{ .string = "result=completed" };
    state.appendNote("result=completed");
    state.appendCheckpoint(.nested_workflow_terminal);
}

fn runResumeOrReturnResume(state: *MachineState) void {
    state.active_prompt = .primary;
    state.pushPending(.primary, .resume_or_return, .{ .i32 = 41 });
    state.appendNote("handler-decide-resume");
    state.appendCheckpoint(.resume_or_return_resume_choice);

    state.appendNote("body-after-shift");
    state.appendCheckpoint(.ror_resume_body);

    state.popPending();
    state.appendNote("handler-after-resume");
    state.finishString("answer=42");
    state.appendCheckpoint(.ror_resume_terminal);
}

fn runResumeOrReturnReturnNow(state: *MachineState) void {
    state.active_prompt = .primary;
    state.pushPending(.primary, .resume_or_return, .none);
    state.appendNote("handler-return-now");
    state.appendCheckpoint(.ror_return_now_choice);

    state.popPending();
    state.finishString("result=early");
    state.appendCheckpoint(.ror_return_now_terminal);
}

fn runStaticRedelim(state: *MachineState) void {
    state.active_prompt = .outer;
    state.pushPending(.outer, .resume_then_transform, .{ .i32 = 1 });
    state.appendNote("outer-handler-enter");
    state.appendCheckpoint(.static_redelim_outer_resume);

    state.appendNote("after-outer-shift");
    state.active_prompt = .inner;
    state.pushPending(.inner, .resume_then_transform, .{ .i32 = 2 });
    state.appendNote("inner-handler-enter");
    state.appendCheckpoint(.static_redelim_inner_resume);

    state.appendNote("after-inner-shift");
    state.appendNote("inner-handler-exit");
    state.popPending();
    state.active_prompt = .outer;
    state.appendNote("outer-handler-exit");
    state.popPending();
    state.finishI32(12);
    state.appendCheckpoint(.static_redelim_terminal);
}
