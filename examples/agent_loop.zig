// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions no_swallow_error
const ability = @import("ability");
const std = @import("std");

const Action = union(enum) {
    final: []const u8,
    tool: []const u8,
};

const AgentHandlers = struct {
    initial_remaining: usize,
};

const AgentSchemas = ability.ir.schema.Registry(.{Action});

const AgentProtocol = ability.ir.schema.Protocol(.{
    .label = "agent",
    .ops = .{
        ability.ir.schema.transform("decide", []const u8, Action),
    },
});

const ToolProtocol = ability.ir.schema.Protocol(.{
    .label = "tool",
    .ops = .{
        ability.ir.schema.transform("call", []const u8, []const u8),
    },
});

const AgentRows = AgentProtocol.Rows(AgentHandlers, .{
    .requirement_index = 0,
    .first_op = 0,
    .schema_refs = AgentSchemas.schema_refs,
});

const ToolRows = ToolProtocol.Rows(AgentHandlers, .{
    .requirement_index = 1,
    .first_op = AgentRows.op_count,
    .schema_refs = AgentSchemas.schema_refs,
});

const agent_requirements = [_]ability.ir.plan.Requirement{
    AgentRows.requirement,
    ToolRows.requirement,
};
const agent_ops = AgentRows.ops ++ ToolRows.ops;

const TraceMode = enum {
    record,
    replay,
};

const RecordedResponse = struct {
    request_fingerprint: u64,
    response_fingerprint: u64,
    response: union(enum) {
        action: Action,
        text: []const u8,
    },
};

const TraceRecording = struct {
    responses: [8]RecordedResponse = [_]RecordedResponse{.{
        .request_fingerprint = 0,
        .response_fingerprint = 0,
        .response = .{ .text = "" },
    }} ** 8,
    count: usize = 0,

    fn append(self: *@This(), record: RecordedResponse) !void {
        if (self.count >= self.responses.len) return error.TraceRecordingFull;
        self.responses[self.count] = record;
        self.count += 1;
    }

    fn at(self: *const @This(), index: usize) !RecordedResponse {
        if (index >= self.count) return error.TraceReplayMissingResponse;
        return self.responses[index];
    }
};

const agent_loop_semantic_spec = blk: {
    const semantic = ability.ir.builder.semantic;
    const Decide = AgentRows.op("decide");
    const Tool = ToolRows.op("call");

    break :blk .{
        .label = "agent-loop-session",
        .ir_hash = 100,
        .entry = "agent",
        .schemas = AgentSchemas,
        .requirements = &agent_requirements,
        .ops = &agent_ops,
        .functions = .{.{
            .symbol_name = "agent",
            .requirements = semantic.span(0, agent_requirements.len),
            .params = .{
                semantic.param("remaining", usize),
                semantic.param("observation", []const u8),
            },
            .locals = .{
                semantic.local("budget_empty", bool),
                semantic.local("action", Action),
                semantic.local("is_final", bool),
                semantic.local("answer", []const u8),
                semantic.local("tool_name", []const u8),
            },
            .result = []const u8,
            .blocks = .{
                .{
                    .name = "entry",
                    .instructions = .{
                        semantic.compareEqZero("budget_empty", "remaining"),
                    },
                    .terminator = semantic.branchIf("budget_empty", .{ .then = "exhausted", .@"else" = "decide" }),
                },
                .{
                    .name = "decide",
                    .instructions = .{
                        semantic.call(Decide, .{ .dst = "action", .payload = "observation", .label = "agent.decide" }),
                        semantic.sumVariantIs("is_final", "action", 0),
                    },
                    .terminator = semantic.branchIf("is_final", .{ .then = "final", .@"else" = "tool" }),
                },
                .{
                    .name = "final",
                    .instructions = .{
                        semantic.sumExtractPayload("answer", "action", 0),
                    },
                    .terminator = semantic.returnValue("answer"),
                },
                .{
                    .name = "tool",
                    .instructions = .{
                        semantic.sumExtractPayload("tool_name", "action", 1),
                        semantic.call(Tool, .{ .dst = "observation", .payload = "tool_name", .label = "agent.tool" }),
                        semantic.subOne("remaining", "remaining"),
                    },
                    .terminator = semantic.jump("entry"),
                },
                .{
                    .name = "exhausted",
                    .instructions = .{
                        semantic.constString("answer", "budget exhausted"),
                    },
                    .terminator = semantic.returnValue("answer"),
                },
            },
        }},
    };
};

const agent_loop_compiled = ability.ir.builder.semantic.finish(agent_loop_semantic_spec) catch |err|
    @compileError("invalid agent loop semantic plan: " ++ @errorName(err));

const AgentBody = struct {
    pub const value_schema_types = AgentSchemas.value_schema_types;
    pub const site_metadata = agent_loop_compiled.site_metadata;
    pub const compiled_plan = agent_loop_compiled.plan;

    pub fn encodeArgs(handlers: AgentHandlers) struct { usize, []const u8 } {
        return .{ handlers.initial_remaining, @as([]const u8, "start") };
    }
};

const host_between_turns_semantic_spec = .{
    .label = "agent-loop-host-between-turns",
    .ir_hash = 101,
    .entry = "host_check",
    .functions = .{.{
        .symbol_name = "host_check",
        .params = .{},
        .locals = .{
            ability.ir.builder.semantic.local("value", []const u8),
        },
        .result = []const u8,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{
                ability.ir.builder.semantic.constString("value", "parked"),
            },
            .terminator = ability.ir.builder.semantic.returnValue("value"),
        }},
    }},
};

const host_between_turns_compiled = ability.ir.builder.semantic.finish(host_between_turns_semantic_spec) catch |err|
    @compileError("invalid host-between-turns semantic plan: " ++ @errorName(err));

const HostBetweenTurnsBody = struct {
    pub const compiled_plan = host_between_turns_compiled.plan;
};

fn runSession(writer: anytype, mode: TraceMode, recording: *TraceRecording) ![]const u8 {
    var runtime = ability.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const Program = ability.program("agent-loop-session", AgentHandlers, AgentBody);
    const HostBetweenTurns = ability.program("agent-loop-host-between-turns", struct {}, HostBetweenTurnsBody);
    const Decide = Program.protocol.operationSite("agent", "decide", 0);
    const Tool = Program.protocol.operationSite("tool", "call", 0);
    comptime {
        Program.protocol.assertOperationSitesCovered(.{ Decide, Tool });
        Program.protocol.assertAfterSitesCovered(.{});
    }
    var session = try Program.Session.start(&runtime, .{ .initial_remaining = 3 });
    defer session.deinit();

    var replay_index: usize = 0;
    const phase = @tagName(mode);

    while (true) {
        switch (try session.next()) {
            .after => return error.UnexpectedAfter,
            .request => |request| {
                const trace = request.trace();
                try writer.print("{s} turn={d} site={d} label={s} kind={s} op={s} request={x}\n", .{
                    phase,
                    trace.turn_index,
                    trace.operation_site_index,
                    trace.semantic_label orelse "",
                    @tagName(trace.kind),
                    trace.op_name,
                    trace.fingerprint,
                });

                var host_check = try HostBetweenTurns.run(&runtime, .{});
                defer host_check.deinit();
                try writer.print("{s} between_turns={s}\n", .{ phase, host_check.value });

                if (request.matches(Decide)) {
                    const typed_request = try request.as(Decide);
                    const action = switch (mode) {
                        .record => action: {
                            const observation: Decide.Payload = try typed_request.payload();
                            try writer.print("{s} decide observation={s}\n", .{ phase, observation });
                            break :action if (std.mem.eql(u8, observation, "start"))
                                Action{ .tool = @as([]const u8, "lookup") }
                            else
                                Action{ .final = @as([]const u8, "answer: lookup=42") };
                        },
                        .replay => action: {
                            const recorded = try recording.at(replay_index);
                            try request.expectFingerprint(recorded.request_fingerprint);
                            break :action switch (recorded.response) {
                                .action => |action| action,
                                .text => return error.TraceReplayResponseKindMismatch,
                            };
                        },
                    };
                    const response_trace = try typed_request.responseTrace(.@"resume", action);
                    switch (mode) {
                        .record => try recording.append(.{
                            .request_fingerprint = trace.fingerprint,
                            .response_fingerprint = response_trace.fingerprint,
                            .response = .{ .action = action },
                        }),
                        .replay => {
                            const recorded = try recording.at(replay_index);
                            if (response_trace.fingerprint != recorded.response_fingerprint) return error.TraceReplayResponseFingerprintMismatch;
                        },
                    }
                    try writer.print("{s} response kind={s} response={x}\n", .{
                        phase,
                        @tagName(response_trace.kind),
                        response_trace.fingerprint,
                    });
                    replay_index += 1;
                    try session.resumeTyped(typed_request, action);
                } else if (request.matches(Tool)) {
                    const typed_request = try request.as(Tool);
                    const text = switch (mode) {
                        .record => text: {
                            const tool_name: Tool.Payload = try typed_request.payload();
                            try writer.print("{s} tool name={s}\n", .{ phase, tool_name });
                            break :text @as([]const u8, "lookup=42");
                        },
                        .replay => text: {
                            const recorded = try recording.at(replay_index);
                            try request.expectFingerprint(recorded.request_fingerprint);
                            break :text switch (recorded.response) {
                                .text => |text| text,
                                .action => return error.TraceReplayResponseKindMismatch,
                            };
                        },
                    };
                    const response_trace = try typed_request.responseTrace(.@"resume", text);
                    switch (mode) {
                        .record => try recording.append(.{
                            .request_fingerprint = trace.fingerprint,
                            .response_fingerprint = response_trace.fingerprint,
                            .response = .{ .text = text },
                        }),
                        .replay => {
                            const recorded = try recording.at(replay_index);
                            if (response_trace.fingerprint != recorded.response_fingerprint) return error.TraceReplayResponseFingerprintMismatch;
                        },
                    }
                    try writer.print("{s} response kind={s} response={x}\n", .{
                        phase,
                        @tagName(response_trace.kind),
                        response_trace.fingerprint,
                    });
                    replay_index += 1;
                    try session.resumeTyped(typed_request, text);
                } else {
                    return error.UnknownAgentRequest;
                }
            },
            .done => |done| {
                var result = done;
                defer result.deinit();
                try writer.print("{s} answer={s}\n", .{ phase, result.value });
                if (mode == .replay and replay_index != recording.count) return error.TraceReplayUnusedResponse;
                return result.value;
            },
        }
    }
}

pub fn run(writer: anytype) !void {
    var recording: TraceRecording = .{};
    const first_answer = try runSession(writer, .record, &recording);
    const replay_answer = try runSession(writer, .replay, &recording);
    if (!std.mem.eql(u8, first_answer, replay_answer)) return error.TraceReplayAnswerMismatch;
    try writer.print("replay verified responses={d} answer={s}\n", .{ recording.count, replay_answer });
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
