// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions no_swallow_error
const ability = @import("ability");
const std = @import("std");

const Action = union(enum) {
    final: []const u8,
    tool: []const u8,
};

const AgentHandlers = struct {
    initial_remaining: usize,
    initial_observation: []const u8,
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

const SessionEvent = enum {
    model_prompted,
    model_replied,
    run_completed,
    run_started,
    tool_called,
    tool_returned,
};

const TerminalStatus = enum {
    completed,
    running,
};

const RunRecord = struct {
    event_count: usize = 0,
    tool_calls: usize = 0,
    last_status: TerminalStatus = .running,
    last_note: []const u8 = "",
};

const InvokeOutcome = struct {
    final_text: []const u8,
    run_record: RunRecord,
    recorded_response_count: usize,
};

const Scenario = enum {
    fixture,
    skeleton,
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

const fixture_dir = "zig-cache/ability-agent-loop-fixtures";
const fixture_input_path = fixture_dir ++ "/input.txt";
const fixture_output_path = fixture_dir ++ "/output.txt";
const fixture_input_contents = "rewrite this file through the agent loop\n";
const fixture_observation = "rewrite this file through the agent loop";
const fixture_write_contents = "actuate updated the fixture";
const fixture_read_command = "read:" ++ fixture_input_path;
const fixture_write_command = "write:" ++ fixture_output_path ++ "=" ++ fixture_write_contents;

fn recordEvent(record: *RunRecord, event: SessionEvent) void {
    record.event_count += 1;
    switch (event) {
        .run_started => record.last_note = "session=started",
        .model_prompted => record.last_note = "model=prompted",
        .model_replied => record.last_note = "model=replied",
        .tool_called => {
            record.tool_calls += 1;
            record.last_note = "tool=called";
        },
        .tool_returned => record.last_note = "tool=returned",
        .run_completed => {
            record.last_status = .completed;
            record.last_note = "session=completed";
        },
    }
}

fn runRecordsEqual(a: RunRecord, b: RunRecord) bool {
    return a.event_count == b.event_count and
        a.tool_calls == b.tool_calls and
        a.last_status == b.last_status and
        std.mem.eql(u8, a.last_note, b.last_note);
}

fn initialObservation(scenario: Scenario) []const u8 {
    return switch (scenario) {
        .skeleton => "goal=invoke",
        .fixture => "goal=fixture",
    };
}

fn expectedFinalText(scenario: Scenario) []const u8 {
    return switch (scenario) {
        .skeleton => "final=actuate skeleton complete",
        .fixture => "final=fixture updated",
    };
}

fn expectedRecordedResponseCount(scenario: Scenario) usize {
    return switch (scenario) {
        .skeleton => 3,
        .fixture => 5,
    };
}

fn decideAction(scenario: Scenario, observation: []const u8) Action {
    return switch (scenario) {
        .skeleton => if (std.mem.eql(u8, observation, "goal=invoke"))
            Action{ .tool = @as([]const u8, "actuate") }
        else if (std.mem.eql(u8, observation, "actuate"))
            Action{ .final = @as([]const u8, "final=actuate skeleton complete") }
        else
            Action{ .final = @as([]const u8, "final=unexpected-tool-output") },
        .fixture => if (std.mem.eql(u8, observation, "goal=fixture"))
            Action{ .tool = @as([]const u8, fixture_read_command) }
        else if (std.mem.eql(u8, observation, fixture_observation))
            Action{ .tool = @as([]const u8, fixture_write_command) }
        else if (std.mem.eql(u8, observation, "write=ok"))
            Action{ .final = @as([]const u8, "final=fixture updated") }
        else
            Action{ .final = @as([]const u8, "final=fixture update failed") },
    };
}

fn prepareFixtureWorkspace() !void {
    const io = std.Io.Threaded.global_single_threaded.io();
    try std.Io.Dir.cwd().createDirPath(io, fixture_dir);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = fixture_input_path,
        .data = fixture_input_contents,
    });
    std.Io.Dir.cwd().deleteFile(io, fixture_output_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
}

fn callTool(allocator: std.mem.Allocator, scenario: Scenario, command: []const u8) ![]const u8 {
    switch (scenario) {
        .skeleton => return if (std.mem.eql(u8, command, "actuate")) "actuate" else "tool=unsupported",
        .fixture => {
            const io = std.Io.Threaded.global_single_threaded.io();
            if (std.mem.startsWith(u8, command, "read:")) {
                const path = command["read:".len..];
                const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024));
                defer allocator.free(bytes);
                const trimmed = std.mem.trim(u8, bytes, "\r\n");
                if (!std.mem.eql(u8, trimmed, fixture_observation)) return error.UnexpectedFixtureInput;
                return fixture_observation;
            }
            if (std.mem.startsWith(u8, command, "write:")) {
                const payload = command["write:".len..];
                const split = std.mem.findScalar(u8, payload, '=') orelse return "write=invalid";
                try std.Io.Dir.cwd().writeFile(io, .{
                    .sub_path = payload[0..split],
                    .data = payload[split + 1 ..],
                });
                return "write=ok";
            }
            return "tool=unsupported";
        },
    }
}

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
        return .{ handlers.initial_remaining, handlers.initial_observation };
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

fn runSession(
    writer: anytype,
    allocator: std.mem.Allocator,
    scenario: Scenario,
    mode: TraceMode,
    recording: *TraceRecording,
) !InvokeOutcome {
    var runtime = ability.Runtime.init(allocator);
    defer runtime.deinit();

    const Program = ability.program("agent-loop-session", AgentHandlers, AgentBody);
    const HostBetweenTurns = ability.program("agent-loop-host-between-turns", struct {}, HostBetweenTurnsBody);
    const Decide = Program.protocol.operationSite("agent", "decide", 0);
    const Tool = Program.protocol.operationSite("tool", "call", 0);
    comptime {
        Program.protocol.assertOperationSitesCovered(.{ Decide, Tool });
        Program.protocol.assertAfterSitesCovered(.{});
    }
    var session = try Program.Session.start(&runtime, .{
        .initial_remaining = 3,
        .initial_observation = initialObservation(scenario),
    });
    defer session.deinit();

    var replay_index: usize = 0;
    var run_record = RunRecord{};
    recordEvent(&run_record, .run_started);
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
                            break :action decideAction(scenario, observation);
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
                    if (action == .tool) {
                        recordEvent(&run_record, .model_prompted);
                        recordEvent(&run_record, .model_replied);
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
                            break :text try callTool(allocator, scenario, tool_name);
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
                    recordEvent(&run_record, .tool_called);
                    recordEvent(&run_record, .tool_returned);
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
                recordEvent(&run_record, .run_completed);
                return .{
                    .final_text = result.value,
                    .run_record = run_record,
                    .recorded_response_count = recording.count,
                };
            },
        }
    }
}

fn runScenario(writer: anytype, allocator: std.mem.Allocator, scenario: Scenario) !InvokeOutcome {
    if (scenario == .fixture) try prepareFixtureWorkspace();

    var recording: TraceRecording = .{};
    const record_outcome = try runSession(writer, allocator, scenario, .record, &recording);
    const replay_outcome = try runSession(writer, allocator, scenario, .replay, &recording);
    if (!std.mem.eql(u8, record_outcome.final_text, replay_outcome.final_text)) return error.TraceReplayAnswerMismatch;
    if (!runRecordsEqual(record_outcome.run_record, replay_outcome.run_record)) return error.TraceReplayRunRecordMismatch;
    if (!std.mem.eql(u8, record_outcome.final_text, expectedFinalText(scenario))) return error.UnexpectedFinalText;
    if (recording.count != expectedRecordedResponseCount(scenario)) return error.UnexpectedTraceResponseCount;
    if (replay_outcome.recorded_response_count != recording.count) return error.TraceReplayResponseCountMismatch;
    return record_outcome;
}

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    const skeleton = try runScenario(writer, allocator, .skeleton);
    try writer.print("skeleton final={s} events={d} tool_calls={d} responses={d}\n", .{
        skeleton.final_text,
        skeleton.run_record.event_count,
        skeleton.run_record.tool_calls,
        skeleton.recorded_response_count,
    });

    const fixture = try runScenario(writer, allocator, .fixture);
    const io = std.Io.Threaded.global_single_threaded.io();
    var output_buffer: [1024]u8 = undefined;
    const bytes = try std.Io.Dir.cwd().readFile(io, fixture_output_path, &output_buffer);
    try writer.print("fixture final={s} events={d} tool_calls={d} responses={d}\n", .{
        fixture.final_text,
        fixture.run_record.event_count,
        fixture.run_record.tool_calls,
        fixture.recorded_response_count,
    });
    try writer.print("fixture output={s} content={s}\n", .{ fixture_output_path, bytes });
    try writer.print("replay verified skeleton=true fixture=true\n", .{});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}

test "agent loop skeleton scenario mirrors actuate skeleton coverage" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();

    const outcome = try runScenario(&output.writer, std.testing.allocator, .skeleton);
    try std.testing.expectEqualStrings("final=actuate skeleton complete", outcome.final_text);
    try std.testing.expectEqual(@as(usize, 6), outcome.run_record.event_count);
    try std.testing.expectEqual(@as(usize, 1), outcome.run_record.tool_calls);
    try std.testing.expectEqual(TerminalStatus.completed, outcome.run_record.last_status);
    try std.testing.expectEqualStrings("session=completed", outcome.run_record.last_note);
    try std.testing.expectEqual(@as(usize, 3), outcome.recorded_response_count);
}

test "agent loop fixture scenario mirrors actuate fixture coverage" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();

    const outcome = try runScenario(&output.writer, std.testing.allocator, .fixture);
    try std.testing.expectEqualStrings("final=fixture updated", outcome.final_text);
    try std.testing.expectEqual(@as(usize, 10), outcome.run_record.event_count);
    try std.testing.expectEqual(@as(usize, 2), outcome.run_record.tool_calls);
    try std.testing.expectEqual(TerminalStatus.completed, outcome.run_record.last_status);
    try std.testing.expectEqual(@as(usize, 5), outcome.recorded_response_count);

    const io = std.Io.Threaded.global_single_threaded.io();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, fixture_output_path, std.testing.allocator, .limited(1024));
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("actuate updated the fixture", bytes);
}
