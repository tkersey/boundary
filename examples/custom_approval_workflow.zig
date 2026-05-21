// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions
const boundary = @import("boundary");
const std = @import("std");

pub const Transcript = struct {
    lookups: usize = 0,
    choices: usize = 0,
    continuations: usize = 0,
    aborts: usize = 0,
    last_lookup: []const u8 = "",
    last_choice: []const u8 = "",
    last_abort: []const u8 = "",
};

const transcript = struct {
    threadlocal var current: Transcript = .{};
};

fn resetTranscript() void {
    transcript.current = .{};
}

fn currentTranscript() Transcript {
    return transcript.current;
}

const DirectoryHandler = struct {
    exists_value: bool,

    pub fn dispatch(self: *const @This(), payload: []const u8) !i32 {
        transcript.current.lookups += 1;
        transcript.current.last_lookup = payload;
        return if (self.exists_value) 1 else 0;
    }
};

const ApprovalBranch = enum { approve, deny };

const ApprovalHandler = struct {
    branch: ApprovalBranch,

    pub fn dispatch(self: *const @This(), payload: []const u8) !boundary.effect.choice.Decision(i32, []const u8) {
        transcript.current.choices += 1;
        transcript.current.last_choice = payload;
        return switch (self.branch) {
            .approve => boundary.effect.choice.Decision(i32, []const u8).resumeWith(1),
            .deny => boundary.effect.choice.Decision(i32, []const u8).returnNow("denied"),
        };
    }

    pub fn afterDispatch(_: *const @This(), answer: []const u8) ![]const u8 {
        transcript.current.continuations += 1;
        return answer;
    }
};

const GuardHandler = struct {
    pub fn dispatch(_: *const @This(), payload: []const u8) ![]const u8 {
        transcript.current.aborts += 1;
        transcript.current.last_abort = payload;
        return "invalid:missing";
    }
};

pub const RunResult = struct {
    value: []const u8,
    transcript: Transcript,
};

const DirectoryState = enum { missing, present };

const WorkflowHandlers = struct {
    workflow: struct {
        exists: DirectoryHandler,
        request: ApprovalHandler,
        invalid: GuardHandler,
    },
};

pub const WorkflowProtocol = boundary.ir.schema.Protocol(.{
    .label = "workflow",
    .ops = .{
        boundary.ir.schema.transform("exists", []const u8, i32),
        boundary.ir.schema.choiceAfter("request", []const u8, i32),
        boundary.ir.schema.abort("invalid", []const u8),
    },
});

pub const WorkflowSchemas = boundary.ir.schema.Registry(.{ []const u8, i32 });

pub const WorkflowRows = WorkflowProtocol.Rows(WorkflowHandlers, .{
    .requirement_index = 0,
    .first_op = 0,
    .schema_refs = WorkflowSchemas.schema_refs,
});

const workflow_semantic_spec = blk: {
    const semantic = boundary.ir.builder.semantic;
    const Exists = WorkflowRows.op("exists");
    const Request = WorkflowRows.op("request");
    const Invalid = WorkflowRows.op("invalid");

    break :blk .{
        .label = "custom-approval",
        .ir_hash = 11,
        .entry = "run",
        .schemas = WorkflowSchemas,
        .requirements = &.{WorkflowRows.requirement},
        .ops = &WorkflowRows.ops,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = semantic.span(0, 1),
            .params = .{},
            .locals = .{
                semantic.local("request_payload", []const u8),
                semantic.local("exists_value", i32),
                semantic.local("approval_resume", i32),
                semantic.local("publish_payload", []const u8),
                semantic.local("final_value", []const u8),
                semantic.local("invalid_payload", []const u8),
                semantic.local("missing_value", bool),
            },
            .result = []const u8,
            .blocks = .{
                .{
                    .name = "entry",
                    .instructions = .{
                        semantic.constString("request_payload", "request-7"),
                        semantic.call(Exists, .{ .dst = "exists_value", .payload = "request_payload", .label = "approval.exists.initial" }),
                        semantic.compareEqZero("missing_value", "exists_value"),
                    },
                    .terminator = semantic.branchIf("missing_value", .{ .then = "invalid", .@"else" = "request" }),
                },
                .{
                    .name = "invalid",
                    .instructions = .{
                        semantic.constString("invalid_payload", "missing"),
                        semantic.call(Invalid, .{ .payload = "invalid_payload", .label = "approval.invalid" }),
                    },
                    .terminator = semantic.returnValue("invalid_payload"),
                },
                .{
                    .name = "request",
                    .instructions = .{
                        semantic.call(Request, .{ .dst = "approval_resume", .payload = "request_payload", .label = "approval.request" }),
                        semantic.constString("publish_payload", "publish-7"),
                        semantic.call(Exists, .{ .dst = "exists_value", .payload = "publish_payload", .label = "approval.exists.publish" }),
                        semantic.constString("final_value", "published:approved"),
                    },
                    .terminator = semantic.returnValue("final_value"),
                },
            },
        }},
    };
};

const workflow_compiled = boundary.ir.builder.semantic.finish(workflow_semantic_spec) catch |err|
    @compileError("invalid custom-approval semantic plan: " ++ @errorName(err));

pub const WorkflowBody = struct {
    pub const value_schema_types = WorkflowSchemas.value_schema_types;
    pub const site_metadata = workflow_compiled.site_metadata;
    pub const compiled_plan = workflow_compiled.plan;
};

pub const WorkflowProgram = boundary.program("custom-approval", WorkflowHandlers, WorkflowBody);

fn runCase(
    runtime: *boundary.Runtime,
    state: DirectoryState,
    branch: ApprovalBranch,
) !RunResult {
    resetTranscript();
    var result = try WorkflowProgram.run(runtime, .{
        .workflow = .{
            .exists = .{ .exists_value = state == .present },
            .request = .{ .branch = branch },
            .invalid = .{},
        },
    });
    defer result.deinit();
    return .{ .value = result.value, .transcript = currentTranscript() };
}

pub fn runApprove(runtime: *boundary.Runtime) !RunResult {
    return runCase(runtime, .present, .approve);
}

pub fn runDeny(runtime: *boundary.Runtime) !RunResult {
    return runCase(runtime, .present, .deny);
}

pub fn runInvalid(runtime: *boundary.Runtime) !RunResult {
    return runCase(runtime, .missing, .approve);
}

const TraceMode = enum { record, replay };

const SessionTraceEntry = struct {
    request_fingerprint: u64,
    response_fingerprint: u64,
};

const SessionTraceRecording = struct {
    entries: [8]SessionTraceEntry = [_]SessionTraceEntry{.{
        .request_fingerprint = 0,
        .response_fingerprint = 0,
    }} ** 8,
    len: usize = 0,

    fn append(self: *@This(), entry: SessionTraceEntry) !void {
        if (self.len >= self.entries.len) return error.TraceRecordingOverflow;
        self.entries[self.len] = entry;
        self.len += 1;
    }

    fn at(self: *const @This(), index: usize) !SessionTraceEntry {
        if (index >= self.len) return error.TraceReplayUnderflow;
        return self.entries[index];
    }
};

pub const SessionRunResult = struct {
    value: []const u8,
    transcript: Transcript,
    trace_entries: usize,
    deterministic_replay: bool,
    _result: ?WorkflowProgram.Result = null,

    pub fn deinit(self: *@This()) void {
        if (self._result) |*result| result.deinit();
        self._result = null;
    }
};

fn workflowHandlers(state: DirectoryState, branch: ApprovalBranch) WorkflowHandlers {
    return .{
        .workflow = .{
            .exists = .{ .exists_value = state == .present },
            .request = .{ .branch = branch },
            .invalid = .{},
        },
    };
}

fn checkSessionTrace(
    mode: TraceMode,
    recording: *SessionTraceRecording,
    replay_index: *usize,
    request_fingerprint: u64,
    response_fingerprint: u64,
) !void {
    switch (mode) {
        .record => try recording.append(.{
            .request_fingerprint = request_fingerprint,
            .response_fingerprint = response_fingerprint,
        }),
        .replay => {
            const recorded = try recording.at(replay_index.*);
            if (recorded.request_fingerprint != request_fingerprint) return error.TraceReplayRequestFingerprintMismatch;
            if (recorded.response_fingerprint != response_fingerprint) return error.TraceReplayResponseFingerprintMismatch;
        },
    }
    replay_index.* += 1;
}

fn runSessionCase(
    runtime: *boundary.Runtime,
    state: DirectoryState,
    branch: ApprovalBranch,
    mode: TraceMode,
    recording: *SessionTraceRecording,
) !SessionRunResult {
    resetTranscript();
    const ExistsInitial = WorkflowProgram.protocol.operationSite("workflow", "exists", 0);
    const Request = WorkflowProgram.protocol.operationSite("workflow", "request", 0);
    const Invalid = WorkflowProgram.protocol.operationSite("workflow", "invalid", 0);
    const ExistsPublish = WorkflowProgram.protocol.operationSite("workflow", "exists", 1);
    const RequestAfter = WorkflowProgram.protocol.afterSite("workflow", "request", 0);
    comptime {
        WorkflowProgram.protocol.assertOperationSitesCovered(.{ ExistsInitial, Request, Invalid, ExistsPublish });
        WorkflowProgram.protocol.assertAfterSitesCovered(.{RequestAfter});
        WorkflowProgram.protocol.assertAllSitesCovered(.{ ExistsInitial, Request, Invalid, ExistsPublish, RequestAfter });
    }

    var session = try WorkflowProgram.Session.start(runtime, workflowHandlers(state, branch));
    defer session.deinit();
    var replay_index: usize = 0;

    while (true) {
        switch (try session.next()) {
            .request => |request| {
                const trace = request.trace();
                if (request.matches(ExistsInitial)) {
                    const typed_request = try request.as(ExistsInitial);
                    const payload: ExistsInitial.Payload = try typed_request.payload();
                    transcript.current.lookups += 1;
                    transcript.current.last_lookup = payload;
                    const exists_result: ExistsInitial.Resume = if (state == .present) 1 else 0;
                    const response_trace = try typed_request.responseTrace(.@"resume", exists_result);
                    try checkSessionTrace(mode, recording, &replay_index, trace.fingerprint, response_trace.fingerprint);
                    try session.resumeTyped(typed_request, exists_result);
                } else if (request.matches(Request)) {
                    const typed_request = try request.as(Request);
                    const payload: Request.Payload = try typed_request.payload();
                    transcript.current.choices += 1;
                    transcript.current.last_choice = payload;
                    switch (branch) {
                        .approve => {
                            const response_trace = try typed_request.responseTrace(.@"resume", @as(Request.Resume, 1));
                            try checkSessionTrace(mode, recording, &replay_index, trace.fingerprint, response_trace.fingerprint);
                            try session.resumeTyped(typed_request, @as(Request.Resume, 1));
                        },
                        .deny => {
                            const response_trace = try typed_request.responseTrace(.return_now, @as(Request.Result, "denied"));
                            try checkSessionTrace(mode, recording, &replay_index, trace.fingerprint, response_trace.fingerprint);
                            try session.returnNowTyped(typed_request, @as(Request.Result, "denied"));
                        },
                    }
                } else if (request.matches(Invalid)) {
                    const typed_request = try request.as(Invalid);
                    const payload: Invalid.Payload = try typed_request.payload();
                    transcript.current.aborts += 1;
                    transcript.current.last_abort = payload;
                    const response_trace = try typed_request.responseTrace(.return_now, @as(Invalid.Result, "invalid:missing"));
                    try checkSessionTrace(mode, recording, &replay_index, trace.fingerprint, response_trace.fingerprint);
                    try session.returnNowTyped(typed_request, @as(Invalid.Result, "invalid:missing"));
                } else if (request.matches(ExistsPublish)) {
                    const typed_request = try request.as(ExistsPublish);
                    const payload: ExistsPublish.Payload = try typed_request.payload();
                    transcript.current.lookups += 1;
                    transcript.current.last_lookup = payload;
                    const response_trace = try typed_request.responseTrace(.@"resume", @as(ExistsPublish.Resume, 1));
                    try checkSessionTrace(mode, recording, &replay_index, trace.fingerprint, response_trace.fingerprint);
                    try session.resumeTyped(typed_request, @as(ExistsPublish.Resume, 1));
                } else {
                    return error.UnknownWorkflowRequest;
                }
            },
            .after => |after| {
                const trace = after.trace();
                if (!after.matches(RequestAfter)) return error.UnknownWorkflowAfterRequest;
                const typed_after = try after.as(RequestAfter);
                const current: RequestAfter.Input = try typed_after.value();
                transcript.current.continuations += 1;
                const response_trace = try typed_after.responseTrace(current);
                try checkSessionTrace(mode, recording, &replay_index, trace.fingerprint, response_trace.fingerprint);
                try session.resumeAfterTyped(typed_after, current);
            },
            .done => |done| {
                var result = done;
                errdefer result.deinit();
                if (mode == .replay and replay_index != recording.len) return error.TraceReplayLengthMismatch;
                return .{
                    .value = result.value,
                    .transcript = currentTranscript(),
                    .trace_entries = replay_index,
                    .deterministic_replay = mode == .replay,
                    ._result = result,
                };
            },
        }
    }
}

pub fn runSessionReplay(
    runtime: *boundary.Runtime,
    state: DirectoryState,
    branch: ApprovalBranch,
) !SessionRunResult {
    var recording: SessionTraceRecording = .{};
    var recorded = try runSessionCase(runtime, state, branch, .record, &recording);
    errdefer recorded.deinit();
    var replayed = try runSessionCase(runtime, state, branch, .replay, &recording);
    defer replayed.deinit();
    if (!std.mem.eql(u8, recorded.value, replayed.value)) return error.TraceReplayValueMismatch;
    if (recorded.trace_entries != replayed.trace_entries) return error.TraceReplayLengthMismatch;
    recorded.deterministic_replay = true;
    return recorded;
}

pub fn runApproveSession(runtime: *boundary.Runtime) !SessionRunResult {
    return runSessionReplay(runtime, .present, .approve);
}

pub fn runInvalidSession(runtime: *boundary.Runtime) !SessionRunResult {
    return runSessionReplay(runtime, .missing, .approve);
}

pub fn run(writer: anytype) !void {
    var runtime = boundary.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const approved = try runApprove(&runtime);
    try writer.print("approve={s} lookups={d} choices={d} continuations={d} aborts={d}\n", .{
        approved.value,
        approved.transcript.lookups,
        approved.transcript.choices,
        approved.transcript.continuations,
        approved.transcript.aborts,
    });

    const denied = try runDeny(&runtime);
    try writer.print("deny={s} lookups={d} choices={d} continuations={d} aborts={d}\n", .{
        denied.value,
        denied.transcript.lookups,
        denied.transcript.choices,
        denied.transcript.continuations,
        denied.transcript.aborts,
    });

    const invalid = try runInvalid(&runtime);
    try writer.print("invalid={s} lookups={d} choices={d} continuations={d} aborts={d}\n", .{
        invalid.value,
        invalid.transcript.lookups,
        invalid.transcript.choices,
        invalid.transcript.continuations,
        invalid.transcript.aborts,
    });

    var session_approved = try runApproveSession(&runtime);
    defer session_approved.deinit();
    try writer.print("session-approve={s} lookups={d} choices={d} continuations={d} aborts={d} traces={d} replay={any}\n", .{
        session_approved.value,
        session_approved.transcript.lookups,
        session_approved.transcript.choices,
        session_approved.transcript.continuations,
        session_approved.transcript.aborts,
        session_approved.trace_entries,
        session_approved.deterministic_replay,
    });

    var session_invalid = try runInvalidSession(&runtime);
    defer session_invalid.deinit();
    try writer.print("session-invalid={s} lookups={d} choices={d} continuations={d} aborts={d} traces={d} replay={any}\n", .{
        session_invalid.value,
        session_invalid.transcript.lookups,
        session_invalid.transcript.choices,
        session_invalid.transcript.continuations,
        session_invalid.transcript.aborts,
        session_invalid.trace_entries,
        session_invalid.deterministic_replay,
    });
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
