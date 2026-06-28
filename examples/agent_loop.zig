// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions no_swallow_error
const boundary = @import("boundary");
const std = @import("std");

const BoundaryAgent = boundary.Agent;

const Action = union(enum) {
    final: []const u8,
    malformed_action: void,
    tool: []const u8,
    unknown_tool: void,
};

const BoundaryTools = BoundaryAgent.ClosedToolSet(&.{ "actuate", "read_file", "write_file" });
const boundary_tool_ids = [_]BoundaryAgent.ToolId{
    BoundaryTools.id(0),
    BoundaryTools.id(1),
    BoundaryTools.id(2),
};
const boundary_agent_config = BoundaryAgent.Config{
    .max_iterations = 5,
    .max_model_calls = 5,
    .max_tool_calls = 4,
    .max_observation_bytes = 1024,
    .max_action_bytes = 512,
    .max_tool_result_bytes = 1024,
    .max_trace_entries = 8,
};

const AgentHandlers = struct {
    initial_remaining: usize,
    initial_observation: []const u8,
};

const AgentSchemas = boundary.ir.schema.Registry(.{Action});

const AgentProtocol = boundary.ir.schema.Protocol(.{
    .label = "agent",
    .ops = .{
        boundary.ir.schema.transform("decide", []const u8, Action),
    },
});

const ToolProtocol = boundary.ir.schema.Protocol(.{
    .label = "tool",
    .ops = .{
        boundary.ir.schema.transform("call", []const u8, []const u8),
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

const agent_requirements = [_]boundary.ir.plan.Requirement{
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
    final_text: []u8,
    run_record: RunRecord,
    recorded_response_count: usize,

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.final_text);
        self.final_text = &.{};
    }
};

const Scenario = enum {
    budget_exhaustion,
    fixture,
    malformed_action,
    skeleton,
    unknown_tool,
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

const fixture_dir = "zig-cache/boundary-agent-loop-fixtures";
const fixture_input_path = fixture_dir ++ "/input.txt";
const fixture_output_path = fixture_dir ++ "/output.txt";
const fixture_input_contents = "rewrite this file through the agent loop\n";
const fixture_observation = "rewrite this file through the agent loop";
const fixture_write_contents = "actuate updated the fixture";
const fixture_read_command = "read:" ++ fixture_input_path;
const fixture_write_payload = fixture_output_path ++ "=" ++ fixture_write_contents;
const fixture_write_command = "write:" ++ fixture_write_payload;

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
        .budget_exhaustion,
        .malformed_action,
        .unknown_tool,
        => "goal=invoke",
        .skeleton => "goal=invoke",
        .fixture => "goal=fixture",
    };
}

fn expectedFinalText(scenario: Scenario) []const u8 {
    return switch (scenario) {
        .budget_exhaustion, .malformed_action, .unknown_tool => "",
        .skeleton => "final=actuate skeleton complete",
        .fixture => "final=fixture updated",
    };
}

fn expectedRecordedResponseCount(scenario: Scenario) usize {
    return switch (scenario) {
        .budget_exhaustion => 2,
        .malformed_action, .unknown_tool => 1,
        .skeleton => 3,
        .fixture => 5,
    };
}

fn decideAction(scenario: Scenario, observation: []const u8) Action {
    return switch (scenario) {
        .budget_exhaustion => Action{ .tool = @as([]const u8, "actuate") },
        .malformed_action => Action{ .malformed_action = {} },
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
        .unknown_tool => Action{ .unknown_tool = {} },
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
        .budget_exhaustion, .skeleton => return if (std.mem.eql(u8, command, "actuate")) "actuate" else "tool=unsupported",
        .malformed_action, .unknown_tool => return error.UnexpectedToolCall,
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
    const semantic = boundary.ir.builder.semantic;
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
                semantic.local("is_malformed_action", bool),
                semantic.local("is_unknown_tool", bool),
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
                    .terminator = semantic.branchIf("is_final", .{ .then = "final", .@"else" = "check_malformed_action" }),
                },
                .{
                    .name = "final",
                    .instructions = .{
                        semantic.sumExtractPayload("answer", "action", 0),
                    },
                    .terminator = semantic.returnValue("answer"),
                },
                .{
                    .name = "check_malformed_action",
                    .instructions = .{
                        semantic.sumVariantIs("is_malformed_action", "action", 1),
                    },
                    .terminator = semantic.branchIf("is_malformed_action", .{ .then = "malformed_action", .@"else" = "check_unknown_tool" }),
                },
                .{
                    .name = "malformed_action",
                    .instructions = .{},
                    .terminator = semantic.returnError("MalformedAgentAction"),
                },
                .{
                    .name = "check_unknown_tool",
                    .instructions = .{
                        semantic.sumVariantIs("is_unknown_tool", "action", 3),
                    },
                    .terminator = semantic.branchIf("is_unknown_tool", .{ .then = "unknown_tool", .@"else" = "tool" }),
                },
                .{
                    .name = "unknown_tool",
                    .instructions = .{},
                    .terminator = semantic.returnError("UnknownToolId"),
                },
                .{
                    .name = "tool",
                    .instructions = .{
                        semantic.sumExtractPayload("tool_name", "action", 2),
                        semantic.call(Tool, .{ .dst = "observation", .payload = "tool_name", .label = "agent.tool" }),
                        semantic.subOne("remaining", "remaining"),
                    },
                    .terminator = semantic.jump("entry"),
                },
                .{
                    .name = "exhausted",
                    .instructions = .{},
                    .terminator = semantic.returnError("AgentBudgetExhausted"),
                },
            },
        }},
    };
};

const agent_loop_compiled = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk boundary.ir.builder.semantic.finish(agent_loop_semantic_spec) catch |err|
        @compileError("invalid agent loop semantic plan: " ++ @errorName(err));
};

const AgentBody = struct {
    pub const Error = error{
        AgentBudgetExhausted,
        MalformedAgentAction,
        UnknownToolId,
    };
    pub const value_schema_types = AgentSchemas.value_schema_types;
    pub const site_metadata = agent_loop_compiled.site_metadata;
    pub const compiled_plan = agent_loop_compiled.plan;

    pub fn encodeArgs(handlers: AgentHandlers) struct { usize, []const u8 } {
        return .{ handlers.initial_remaining, handlers.initial_observation };
    }
};

pub const Program = boundary.program("agent-loop-session", AgentHandlers, AgentBody);
pub const AgentDecision = Program.protocol.operationSite("agent", "decide", 0);
pub const ToolboxCall = Program.protocol.operationSite("tool", "call", 0);

fn worldPortForSite(comptime label: []const u8, comptime port_label: []const u8, comptime Site: anytype) Program.BoundaryClosure.WorldPort {
    const Closure = Program.BoundaryClosure;
    @setEvalBranchQuota(2_000_000);
    const source_shape = Closure.EffectShape.init(.{
        .program_label = Program.contract.label,
        .plan_hash = Program.compiled_plan.hash(),
        .kind = .operation,
        .site_index = Site.index,
        .protocol_label = label,
        .protocol_op_fingerprint = Site.fingerprint,
        .semantic_label = Site.semantic_label,
        .name = Site.op_name,
        .mode = "transform",
        .value_ref = Program.Evidence.BoundaryValueRef.fromValueRef(Site.payload_ref),
        .expected_resume_ref = Program.Evidence.BoundaryValueRef.fromValueRef(Site.resume_ref),
        .result_ref = Program.Evidence.BoundaryValueRef.fromValueRef(Site.result_ref),
    });
    return Closure.WorldPort.init(.{
        .label = port_label,
        .kind = .test_fixture,
        .effect_shape_ref = source_shape.evidenceRef(),
        .effect_shape_witness = source_shape,
        .supported_protocol_labels = &.{label},
        .supported_site_indexes = &.{Site.index},
        .supported_protocol_op_fingerprints = &.{Site.fingerprint},
    });
}

const agent_source_ref = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk Program.Evidence.refFor(
        Program.Evidence.domains.program_plan,
        Program.compiled_plan.hash(),
        .{ .label = Program.contract.label },
    );
};
const model_world_port = worldPortForSite("agent", "agent-model-decision-port", AgentDecision);
const toolbox_world_port = worldPortForSite("tool", "agent-toolbox-call-port", ToolboxCall);
const agent_closure_graph = Program.BoundaryClosure.Graph.init("agent-root-module-graph", &.{}, &.{}, &.{});
const agent_closure_report = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk Program.BoundaryClosure.Report.init(.{
        .graph_fingerprint = agent_closure_graph.fingerprint,
        .root_program_refs = &.{agent_source_ref},
        .effect_shape_count = 2,
        .world_port_refs = &.{ model_world_port.evidenceRef(), toolbox_world_port.evidenceRef() },
        .open_world_port_count = 2,
    });
};
const agent_closure_certificate = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk Program.BoundaryClosure.Certificate.init(
        agent_closure_report,
        agent_closure_graph,
        Program.BoundaryClosure.Policy.auditOnly(),
        &.{},
    );
};
const agent_elaboration_input = Program.BoundaryClosure.Elaboration.Input{
    .closure_graph = agent_closure_graph,
    .closure_report = agent_closure_report,
    .closure_certificate = agent_closure_certificate,
    .source_program_ref = agent_source_ref,
    .world_ports = &.{ model_world_port, toolbox_world_port },
    .policy = Program.BoundaryClosure.Elaboration.Policy.auditOnly(),
};

pub const RootTarget = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk Program.BoundaryClosure.Elaboration.Target.compileComptime(.{
        .label = "agent-root-module-target",
        .input = agent_elaboration_input,
        .residual_program = Program,
        .policy = Program.BoundaryClosure.Elaboration.Target.Policy.auditOnly(),
    });
};

const ToolboxHandlers = struct {
    tool_index: usize,
};

const FileProtocol = boundary.ir.schema.Protocol(.{
    .label = "file",
    .ops = .{
        boundary.ir.schema.transform("read", []const u8, []const u8),
        boundary.ir.schema.transform("write", []const u8, []const u8),
    },
});
const FileRows = FileProtocol.Rows(ToolboxHandlers, .{
    .requirement_index = 0,
    .first_op = 0,
    .schema_refs = AgentSchemas.schema_refs,
});
const file_requirements = [_]boundary.ir.plan.Requirement{FileRows.requirement};
const file_ops = FileRows.ops;

const toolbox_semantic_spec = blk: {
    const semantic = boundary.ir.builder.semantic;
    const ReadOp = FileRows.op("read");
    const WriteOp = FileRows.op("write");

    break :blk .{
        .label = "agent-toolbox-provider",
        .ir_hash = 102,
        .entry = "toolbox",
        .schemas = AgentSchemas,
        .requirements = &file_requirements,
        .ops = &file_ops,
        .functions = .{.{
            .symbol_name = "toolbox",
            .requirements = semantic.span(0, file_requirements.len),
            .params = .{
                semantic.param("tool_index", usize),
            },
            .locals = .{
                semantic.local("is_actuate", bool),
                semantic.local("is_read", bool),
                semantic.local("is_write", bool),
                semantic.local("selector", usize),
                semantic.local("payload", []const u8),
                semantic.local("result", []const u8),
            },
            .result = []const u8,
            .blocks = .{
                .{
                    .name = "entry",
                    .instructions = .{
                        semantic.compareEqZero("is_actuate", "tool_index"),
                    },
                    .terminator = semantic.branchIf("is_actuate", .{ .then = "actuate", .@"else" = "check_read" }),
                },
                .{
                    .name = "check_read",
                    .instructions = .{
                        semantic.subOne("selector", "tool_index"),
                        semantic.compareEqZero("is_read", "selector"),
                    },
                    .terminator = semantic.branchIf("is_read", .{ .then = "read_file", .@"else" = "check_write" }),
                },
                .{
                    .name = "check_write",
                    .instructions = .{
                        semantic.subOne("selector", "selector"),
                        semantic.compareEqZero("is_write", "selector"),
                    },
                    .terminator = semantic.branchIf("is_write", .{ .then = "write_file", .@"else" = "unsupported" }),
                },
                .{
                    .name = "actuate",
                    .instructions = .{
                        semantic.constString("result", "actuate"),
                    },
                    .terminator = semantic.returnValue("result"),
                },
                .{
                    .name = "read_file",
                    .instructions = .{
                        semantic.constString("payload", fixture_input_path),
                        semantic.call(ReadOp, .{ .dst = "result", .payload = "payload", .label = "toolbox.file.read" }),
                    },
                    .terminator = semantic.returnValue("result"),
                },
                .{
                    .name = "write_file",
                    .instructions = .{
                        semantic.constString("payload", fixture_write_payload),
                        semantic.call(WriteOp, .{ .dst = "result", .payload = "payload", .label = "toolbox.file.write" }),
                    },
                    .terminator = semantic.returnValue("result"),
                },
                .{
                    .name = "unsupported",
                    .instructions = .{
                        semantic.constString("result", "tool=unsupported"),
                    },
                    .terminator = semantic.returnValue("result"),
                },
            },
        }},
    };
};

const toolbox_compiled = boundary.ir.builder.semantic.finish(toolbox_semantic_spec) catch |err|
    @compileError("invalid agent toolbox semantic plan: " ++ @errorName(err));

const ToolboxBody = struct {
    pub const value_schema_types = AgentSchemas.value_schema_types;
    pub const site_metadata = toolbox_compiled.site_metadata;
    pub const compiled_plan = toolbox_compiled.plan;

    pub fn encodeArgs(handlers: ToolboxHandlers) struct { usize } {
        return .{handlers.tool_index};
    }
};

pub const ToolboxProgram = boundary.program("agent-toolbox-provider", ToolboxHandlers, ToolboxBody);
pub const FileRead = ToolboxProgram.protocol.operationSite("file", "read", 0);
pub const FileWrite = ToolboxProgram.protocol.operationSite("file", "write", 0);

fn toolboxWorldPortForSite(comptime label: []const u8, comptime port_label: []const u8, comptime Site: anytype) ToolboxProgram.BoundaryClosure.WorldPort {
    const Closure = ToolboxProgram.BoundaryClosure;
    @setEvalBranchQuota(2_000_000);
    const source_shape = Closure.EffectShape.init(.{
        .program_label = ToolboxProgram.contract.label,
        .plan_hash = ToolboxProgram.compiled_plan.hash(),
        .kind = .operation,
        .site_index = Site.index,
        .protocol_label = label,
        .protocol_op_fingerprint = Site.fingerprint,
        .semantic_label = Site.semantic_label,
        .name = Site.op_name,
        .mode = "transform",
        .value_ref = ToolboxProgram.Evidence.BoundaryValueRef.fromValueRef(Site.payload_ref),
        .expected_resume_ref = ToolboxProgram.Evidence.BoundaryValueRef.fromValueRef(Site.resume_ref),
        .result_ref = ToolboxProgram.Evidence.BoundaryValueRef.fromValueRef(Site.result_ref),
    });
    return Closure.WorldPort.init(.{
        .label = port_label,
        .kind = .test_fixture,
        .effect_shape_ref = source_shape.evidenceRef(),
        .effect_shape_witness = source_shape,
        .supported_protocol_labels = &.{label},
        .supported_site_indexes = &.{Site.index},
        .supported_protocol_op_fingerprints = &.{Site.fingerprint},
    });
}

const toolbox_source_ref = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk ToolboxProgram.Evidence.refFor(
        ToolboxProgram.Evidence.domains.program_plan,
        ToolboxProgram.compiled_plan.hash(),
        .{ .label = ToolboxProgram.contract.label },
    );
};
const file_read_world_port = toolboxWorldPortForSite("file", "agent-toolbox-file-read-port", FileRead);
const file_write_world_port = toolboxWorldPortForSite("file", "agent-toolbox-file-write-port", FileWrite);
const toolbox_closure_graph = ToolboxProgram.BoundaryClosure.Graph.init("agent-toolbox-module-graph", &.{}, &.{}, &.{});
const toolbox_closure_report = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk ToolboxProgram.BoundaryClosure.Report.init(.{
        .graph_fingerprint = toolbox_closure_graph.fingerprint,
        .root_program_refs = &.{toolbox_source_ref},
        .effect_shape_count = 2,
        .world_port_refs = &.{ file_read_world_port.evidenceRef(), file_write_world_port.evidenceRef() },
        .open_world_port_count = 2,
    });
};
const toolbox_closure_certificate = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk ToolboxProgram.BoundaryClosure.Certificate.init(
        toolbox_closure_report,
        toolbox_closure_graph,
        ToolboxProgram.BoundaryClosure.Policy.auditOnly(),
        &.{},
    );
};
const toolbox_elaboration_input = ToolboxProgram.BoundaryClosure.Elaboration.Input{
    .closure_graph = toolbox_closure_graph,
    .closure_report = toolbox_closure_report,
    .closure_certificate = toolbox_closure_certificate,
    .source_program_ref = toolbox_source_ref,
    .world_ports = &.{ file_read_world_port, file_write_world_port },
    .policy = ToolboxProgram.BoundaryClosure.Elaboration.Policy.auditOnly(),
};

pub const ToolboxTarget = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk ToolboxProgram.BoundaryClosure.Elaboration.Target.compileComptime(.{
        .label = "agent-toolbox-module-target",
        .input = toolbox_elaboration_input,
        .residual_program = ToolboxProgram,
        .policy = ToolboxProgram.BoundaryClosure.Elaboration.Target.Policy.auditOnly(),
    });
};

const host_between_turns_semantic_spec = .{
    .label = "agent-loop-host-between-turns",
    .ir_hash = 101,
    .entry = "host_check",
    .functions = .{.{
        .symbol_name = "host_check",
        .params = .{},
        .locals = .{
            boundary.ir.builder.semantic.local("value", []const u8),
        },
        .result = []const u8,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{
                boundary.ir.builder.semantic.constString("value", "parked"),
            },
            .terminator = boundary.ir.builder.semantic.returnValue("value"),
        }},
    }},
};

const host_between_turns_compiled = boundary.ir.builder.semantic.finish(host_between_turns_semantic_spec) catch |err|
    @compileError("invalid host-between-turns semantic plan: " ++ @errorName(err));

const HostBetweenTurnsBody = struct {
    pub const compiled_plan = host_between_turns_compiled.plan;
};

fn boundaryAgentProfile() BoundaryAgent.Profile {
    return BoundaryAgent.Profile.fromConfig(
        boundary_agent_config,
        &boundary_tool_ids,
        BoundaryAgent.canonicalValueSchemaFingerprints(),
        "agent-root-module",
    );
}

fn loadedSchemaSet() RootTarget.Module.LoadedValueSchemaSet {
    return .{
        .schemas = RootTarget.Program.compiled_plan.value_schemas,
        .fields = RootTarget.Program.compiled_plan.value_fields,
        .variants = RootTarget.Program.compiled_plan.value_variants,
    };
}

fn toolboxLoadedSchemaSet() ToolboxTarget.Module.LoadedValueSchemaSet {
    return .{
        .schemas = ToolboxTarget.Program.compiled_plan.value_schemas,
        .fields = ToolboxTarget.Program.compiled_plan.value_fields,
        .variants = ToolboxTarget.Program.compiled_plan.value_variants,
    };
}

fn encodeLoadedString(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return RootTarget.Module.LoadedExecution.encodeLoadedValueImageBytes(
        allocator,
        loadedSchemaSet(),
        .{ .codec = .string },
        .{ .bytes = text },
        .{},
    );
}

fn encodeLoadedAction(allocator: std.mem.Allocator, action: Action) ![]u8 {
    const action_ref = AgentSchemas.valueRef(Action).?;
    return switch (action) {
        .final => |text| blk: {
            const payload = RootTarget.Module.LoadedValue{ .bytes = text };
            const sum = RootTarget.Module.LoadedValue{ .sum = .{
                .variant_index = 0,
                .payload = &payload,
            } };
            break :blk try RootTarget.Module.LoadedExecution.encodeLoadedValueImageBytes(
                allocator,
                loadedSchemaSet(),
                .{ .codec = .sum, .schema_index = action_ref.schema_index },
                sum,
                .{},
            );
        },
        .malformed_action => blk: {
            const sum = RootTarget.Module.LoadedValue{ .sum = .{
                .variant_index = 1,
            } };
            break :blk try RootTarget.Module.LoadedExecution.encodeLoadedValueImageBytes(
                allocator,
                loadedSchemaSet(),
                .{ .codec = .sum, .schema_index = action_ref.schema_index },
                sum,
                .{},
            );
        },
        .tool => |text| blk: {
            const payload = RootTarget.Module.LoadedValue{ .bytes = text };
            const sum = RootTarget.Module.LoadedValue{ .sum = .{
                .variant_index = 2,
                .payload = &payload,
            } };
            break :blk try RootTarget.Module.LoadedExecution.encodeLoadedValueImageBytes(
                allocator,
                loadedSchemaSet(),
                .{ .codec = .sum, .schema_index = action_ref.schema_index },
                sum,
                .{},
            );
        },
        .unknown_tool => blk: {
            const sum = RootTarget.Module.LoadedValue{ .sum = .{
                .variant_index = 3,
            } };
            break :blk try RootTarget.Module.LoadedExecution.encodeLoadedValueImageBytes(
                allocator,
                loadedSchemaSet(),
                .{ .codec = .sum, .schema_index = action_ref.schema_index },
                sum,
                .{},
            );
        },
    };
}

fn decodeLoadedString(allocator: std.mem.Allocator, arena: *RootTarget.Module.LoadedValueArena, image: []const u8) ![]const u8 {
    const value = try RootTarget.Module.LoadedExecution.decodeLoadedValueImage(
        allocator,
        arena,
        loadedSchemaSet(),
        .{ .codec = .string },
        image,
        .{},
    );
    return value.bytes;
}

fn encodeToolboxLoadedString(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    return ToolboxTarget.Module.LoadedExecution.encodeLoadedValueImageBytes(
        allocator,
        toolboxLoadedSchemaSet(),
        .{ .codec = .string },
        .{ .bytes = text },
        .{},
    );
}

fn decodeToolboxLoadedString(allocator: std.mem.Allocator, arena: *ToolboxTarget.Module.LoadedValueArena, image: []const u8) ![]const u8 {
    const value = try ToolboxTarget.Module.LoadedExecution.decodeLoadedValueImage(
        allocator,
        arena,
        toolboxLoadedSchemaSet(),
        .{ .codec = .string },
        image,
        .{},
    );
    return value.bytes;
}

fn runToolboxProviderParityScenario(
    allocator: std.mem.Allocator,
    tool_index: usize,
    payload_text: []const u8,
    expected_final: []const u8,
) ![]u8 {
    const full = try ToolboxTarget.Module.fullImage(allocator);
    defer allocator.free(full);
    var loaded = try ToolboxTarget.Module.decode(allocator, full);
    defer loaded.deinit();

    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var generated_session = try ToolboxProgram.Session.start(&runtime, .{ .tool_index = tool_index });
    defer generated_session.deinit();

    var entry_args = [_]ToolboxTarget.Module.LoadedValue{
        .{ .word_u64 = tool_index },
    };
    var loaded_session = try ToolboxTarget.Module.LoadedModule.Session.startExecutableWithArgs(
        allocator,
        &loaded,
        ToolboxTarget.Module.LoadedExecutionProfile.portableV2(),
        entry_args[0..],
    );
    defer loaded_session.deinit();

    const read_response_text = try allocator.dupe(u8, fixture_observation);
    defer allocator.free(read_response_text);
    const read_response_const: []const u8 = read_response_text;
    const write_response_text = try allocator.dupe(u8, "write=ok");
    defer allocator.free(write_response_text);
    const write_response_const: []const u8 = write_response_text;

    while (true) {
        const generated_next = try generated_session.next();
        const loaded_next = loaded_session.next();
        switch (generated_next) {
            .after => return error.UnexpectedAfter,
            .request => |generated_request| {
                const loaded_request = switch (loaded_next) {
                    .request => |request| request,
                    .done => return error.UnexpectedLoadedDone,
                    .failed => return error.UnexpectedLoadedFailure,
                };
                try std.testing.expectEqual(
                    ToolboxTarget.WorldDispatchTable.lookup(generated_request.operation_site_index).?,
                    loaded_request.world_port_id,
                );
                try std.testing.expectEqual(generated_request.operation_site_index, loaded_request.residual_site_index);
                try std.testing.expectEqual(generated_request.operation_site_fingerprint, loaded_request.residual_site_fingerprint);

                var payload_arena = ToolboxTarget.Module.LoadedValueArena.init(allocator);
                defer payload_arena.deinit();
                const loaded_payload = try decodeToolboxLoadedString(allocator, &payload_arena, loaded_request.canonical_payload_image);

                if (generated_request.matches(FileRead)) {
                    const typed = try generated_request.as(FileRead);
                    const path: FileRead.Payload = try typed.payload();
                    try std.testing.expectEqualStrings(path, loaded_payload);
                    try std.testing.expectEqualStrings(payload_text, path);
                    const loaded_response = try encodeToolboxLoadedString(allocator, read_response_const);
                    defer allocator.free(loaded_response);
                    try generated_session.resumeTyped(typed, read_response_const);
                    try loaded_session.@"resume"(loaded_request, loaded_response);
                } else if (generated_request.matches(FileWrite)) {
                    const typed = try generated_request.as(FileWrite);
                    const payload: FileWrite.Payload = try typed.payload();
                    try std.testing.expectEqualStrings(payload, loaded_payload);
                    try std.testing.expectEqualStrings(payload_text, payload);
                    const loaded_response = try encodeToolboxLoadedString(allocator, write_response_const);
                    defer allocator.free(loaded_response);
                    try generated_session.resumeTyped(typed, write_response_const);
                    try loaded_session.@"resume"(loaded_request, loaded_response);
                } else {
                    return error.UnknownToolboxRequest;
                }
            },
            .done => |done| {
                var generated_done = done;
                defer generated_done.deinit();
                const loaded_done = switch (loaded_next) {
                    .done => |value| value,
                    .request => return error.UnexpectedLoadedRequest,
                    .failed => return error.UnexpectedLoadedFailure,
                };
                var result_arena = ToolboxTarget.Module.LoadedValueArena.init(allocator);
                defer result_arena.deinit();
                const loaded_result = try decodeToolboxLoadedString(allocator, &result_arena, loaded_done.canonical_result_image);
                try std.testing.expectEqualStrings(generated_done.value, loaded_result);
                try std.testing.expectEqualStrings(expected_final, loaded_result);
                return allocator.dupe(u8, loaded_result);
            },
        }
    }
}

fn runLoadedFailureParityScenario(
    allocator: std.mem.Allocator,
    scenario: Scenario,
    initial_remaining: usize,
    expected_error: []const u8,
) !void {
    const full = try RootTarget.Module.fullImage(allocator);
    defer allocator.free(full);
    var loaded = try RootTarget.Module.decode(allocator, full);
    defer loaded.deinit();

    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var generated_session = try Program.Session.start(&runtime, .{
        .initial_remaining = initial_remaining,
        .initial_observation = initialObservation(scenario),
    });
    defer generated_session.deinit();

    var entry_args = [_]RootTarget.Module.LoadedValue{
        .{ .word_u64 = initial_remaining },
        .{ .bytes = initialObservation(scenario) },
    };
    var loaded_session = try RootTarget.Module.LoadedModule.Session.startExecutableWithArgs(
        allocator,
        &loaded,
        RootTarget.Module.LoadedExecutionProfile.portableV2(),
        entry_args[0..],
    );
    defer loaded_session.deinit();

    while (true) {
        const generated_next = generated_session.next() catch |err| {
            const loaded_failure = switch (loaded_session.next()) {
                .failed => |failure| failure,
                .request => return error.UnexpectedLoadedRequest,
                .done => return error.UnexpectedLoadedDone,
            };
            try std.testing.expectEqualStrings(expected_error, @errorName(err));
            try std.testing.expectEqual(RootTarget.Module.LoadedExecution.ExecutionFailureKind.declared_error, loaded_failure.kind);
            try std.testing.expectEqual(RootTarget.Module.LoadedExecution.loadedDeclaredErrorRef(expected_error), loaded_failure.declared_error_ref.?);
            try std.testing.expectEqualStrings(expected_error, loaded_failure.diagnostic_summary);
            return;
        };
        const loaded_next = loaded_session.next();
        switch (generated_next) {
            .after => return error.UnexpectedAfter,
            .request => |generated_request| {
                const loaded_request = switch (loaded_next) {
                    .request => |request| request,
                    .done => return error.UnexpectedLoadedDone,
                    .failed => return error.UnexpectedLoadedFailure,
                };
                try std.testing.expectEqual(
                    RootTarget.WorldDispatchTable.lookup(generated_request.operation_site_index).?,
                    loaded_request.world_port_id,
                );
                try std.testing.expectEqual(generated_request.operation_site_index, loaded_request.residual_site_index);
                try std.testing.expectEqual(generated_request.operation_site_fingerprint, loaded_request.residual_site_fingerprint);

                if (generated_request.matches(AgentDecision)) {
                    var payload_arena = RootTarget.Module.LoadedValueArena.init(allocator);
                    defer payload_arena.deinit();
                    const loaded_payload = try decodeLoadedString(allocator, &payload_arena, loaded_request.canonical_payload_image);
                    const typed = try generated_request.as(AgentDecision);
                    const observation: AgentDecision.Payload = try typed.payload();
                    try std.testing.expectEqualStrings(observation, loaded_payload);
                    const action = decideAction(scenario, observation);
                    const loaded_response = try encodeLoadedAction(allocator, action);
                    defer allocator.free(loaded_response);
                    try generated_session.resumeTyped(typed, action);
                    try loaded_session.@"resume"(loaded_request, loaded_response);
                } else if (generated_request.matches(ToolboxCall)) {
                    var payload_arena = RootTarget.Module.LoadedValueArena.init(allocator);
                    defer payload_arena.deinit();
                    const typed = try generated_request.as(ToolboxCall);
                    const command: ToolboxCall.Payload = try typed.payload();
                    const loaded_payload = try decodeLoadedString(allocator, &payload_arena, loaded_request.canonical_payload_image);
                    try std.testing.expectEqualStrings(command, loaded_payload);
                    const text = try callTool(allocator, scenario, command);
                    const loaded_response = try encodeLoadedString(allocator, text);
                    defer allocator.free(loaded_response);
                    try generated_session.resumeTyped(typed, text);
                    try loaded_session.@"resume"(loaded_request, loaded_response);
                } else {
                    return error.UnknownAgentRequest;
                }
            },
            .done => return error.UnexpectedGeneratedDone,
        }
    }
}

fn runLoadedParityScenario(allocator: std.mem.Allocator, scenario: Scenario) ![]u8 {
    if (scenario == .fixture) try prepareFixtureWorkspace();

    const full = try RootTarget.Module.fullImage(allocator);
    defer allocator.free(full);
    var loaded = try RootTarget.Module.decode(allocator, full);
    defer loaded.deinit();

    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var generated_session = try Program.Session.start(&runtime, .{
        .initial_remaining = 3,
        .initial_observation = initialObservation(scenario),
    });
    defer generated_session.deinit();

    var entry_args = [_]RootTarget.Module.LoadedValue{
        .{ .word_u64 = 3 },
        .{ .bytes = initialObservation(scenario) },
    };
    var loaded_session = try RootTarget.Module.LoadedModule.Session.startExecutableWithArgs(
        allocator,
        &loaded,
        RootTarget.Module.LoadedExecutionProfile.portableV2(),
        entry_args[0..],
    );
    defer loaded_session.deinit();

    while (true) {
        const generated_next = try generated_session.next();
        const loaded_next = loaded_session.next();
        switch (generated_next) {
            .after => return error.UnexpectedAfter,
            .request => |generated_request| {
                const loaded_request = switch (loaded_next) {
                    .request => |request| request,
                    .done => return error.UnexpectedLoadedDone,
                    .failed => return error.UnexpectedLoadedFailure,
                };
                try std.testing.expectEqual(
                    RootTarget.WorldDispatchTable.lookup(generated_request.operation_site_index).?,
                    loaded_request.world_port_id,
                );
                try std.testing.expectEqual(generated_request.operation_site_index, loaded_request.residual_site_index);
                try std.testing.expectEqual(generated_request.operation_site_fingerprint, loaded_request.residual_site_fingerprint);

                if (generated_request.matches(AgentDecision)) {
                    var payload_arena = RootTarget.Module.LoadedValueArena.init(allocator);
                    defer payload_arena.deinit();
                    const loaded_payload = try decodeLoadedString(allocator, &payload_arena, loaded_request.canonical_payload_image);
                    const typed = try generated_request.as(AgentDecision);
                    const observation: AgentDecision.Payload = try typed.payload();
                    try std.testing.expectEqualStrings(observation, loaded_payload);
                    const action = decideAction(scenario, observation);
                    const loaded_response = try encodeLoadedAction(allocator, action);
                    defer allocator.free(loaded_response);
                    try generated_session.resumeTyped(typed, action);
                    try loaded_session.@"resume"(loaded_request, loaded_response);
                } else if (generated_request.matches(ToolboxCall)) {
                    var payload_arena = RootTarget.Module.LoadedValueArena.init(allocator);
                    defer payload_arena.deinit();
                    const typed = try generated_request.as(ToolboxCall);
                    const command: ToolboxCall.Payload = try typed.payload();
                    const loaded_payload = try decodeLoadedString(allocator, &payload_arena, loaded_request.canonical_payload_image);
                    try std.testing.expectEqualStrings(command, loaded_payload);
                    const text = try callTool(allocator, scenario, command);
                    const loaded_response = try encodeLoadedString(allocator, text);
                    defer allocator.free(loaded_response);
                    try generated_session.resumeTyped(typed, text);
                    try loaded_session.@"resume"(loaded_request, loaded_response);
                } else {
                    return error.UnknownAgentRequest;
                }
            },
            .done => |done| {
                var generated_done = done;
                defer generated_done.deinit();
                const loaded_done = switch (loaded_next) {
                    .done => |value| value,
                    .request => return error.UnexpectedLoadedRequest,
                    .failed => return error.UnexpectedLoadedFailure,
                };
                var result_arena = RootTarget.Module.LoadedValueArena.init(allocator);
                defer result_arena.deinit();
                const loaded_result = try decodeLoadedString(allocator, &result_arena, loaded_done.canonical_result_image);
                try std.testing.expectEqualStrings(generated_done.value, loaded_result);
                return allocator.dupe(u8, loaded_result);
            },
        }
    }
}

fn runSession(
    writer: anytype,
    allocator: std.mem.Allocator,
    scenario: Scenario,
    mode: TraceMode,
    recording: *TraceRecording,
) !InvokeOutcome {
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();

    const HostBetweenTurns = boundary.program("agent-loop-host-between-turns", struct {}, HostBetweenTurnsBody);
    const Decide = AgentDecision;
    const Tool = ToolboxCall;
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
                            const command: Tool.Payload = try typed_request.payload();
                            try writer.print("{s} tool name={s}\n", .{ phase, command });
                            break :text try callTool(allocator, scenario, command);
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
                const final_text = try allocator.dupe(u8, result.value);
                return .{
                    .final_text = final_text,
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
    var record_outcome = try runSession(writer, allocator, scenario, .record, &recording);
    errdefer record_outcome.deinit(allocator);
    var replay_outcome = try runSession(writer, allocator, scenario, .replay, &recording);
    defer replay_outcome.deinit(allocator);
    if (!std.mem.eql(u8, record_outcome.final_text, replay_outcome.final_text)) return error.TraceReplayAnswerMismatch;
    if (!runRecordsEqual(record_outcome.run_record, replay_outcome.run_record)) return error.TraceReplayRunRecordMismatch;
    if (!std.mem.eql(u8, record_outcome.final_text, expectedFinalText(scenario))) return error.UnexpectedFinalText;
    if (recording.count != expectedRecordedResponseCount(scenario)) return error.UnexpectedTraceResponseCount;
    if (replay_outcome.recorded_response_count != recording.count) return error.TraceReplayResponseCountMismatch;
    return record_outcome;
}

pub fn run(writer: anytype, allocator: std.mem.Allocator) !void {
    var skeleton = try runScenario(writer, allocator, .skeleton);
    defer skeleton.deinit(allocator);
    try writer.print("skeleton final={s} events={d} tool_calls={d} responses={d}\n", .{
        skeleton.final_text,
        skeleton.run_record.event_count,
        skeleton.run_record.tool_calls,
        skeleton.recorded_response_count,
    });

    var fixture = try runScenario(writer, allocator, .fixture);
    defer fixture.deinit(allocator);
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
    try run(stdout, std.heap.page_allocator);
    try stdout.flush();
}

test "agent loop skeleton scenario mirrors actuate skeleton coverage" {
    var output = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer output.deinit();

    var outcome = try runScenario(&output.writer, std.testing.allocator, .skeleton);
    defer outcome.deinit(std.testing.allocator);
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

    var outcome = try runScenario(&output.writer, std.testing.allocator, .fixture);
    defer outcome.deinit(std.testing.allocator);
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

test "agent root module full image binds model and toolbox residual ports" {
    const allocator = std.testing.allocator;
    var built = try BoundaryAgent.buildRootModule(RootTarget, allocator, boundaryAgentProfile());
    defer built.deinit(allocator);
    try built.artifact.validate(RootTarget, .{
        .allocator = allocator,
        .profile = boundaryAgentProfile(),
        .expected_role = .root,
        .bytes = built.bytes,
    });
    try std.testing.expectEqual(BoundaryAgent.ModuleRole.root, built.artifact.role);
    try std.testing.expectEqual(@as(u32, 2), built.artifact.import_count);

    var loaded = try RootTarget.Module.decode(allocator, built.bytes);
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 2), loaded.imports().len);
    try std.testing.expectEqual(@as(u32, 0), loaded.worldPortForSite(AgentDecision.index).?);
    try std.testing.expectEqual(@as(u32, 1), loaded.worldPortForSite(ToolboxCall.index).?);
}

test "agent toolbox module full image binds file residual ports" {
    const allocator = std.testing.allocator;
    var built = try BoundaryAgent.buildToolboxModule(ToolboxTarget, allocator, boundaryAgentProfile());
    defer built.deinit(allocator);
    try built.artifact.validate(ToolboxTarget, .{
        .allocator = allocator,
        .profile = boundaryAgentProfile(),
        .expected_role = .toolbox,
        .bytes = built.bytes,
    });
    try std.testing.expectEqual(BoundaryAgent.ModuleRole.toolbox, built.artifact.role);
    try std.testing.expectEqual(@as(u32, 2), built.artifact.import_count);

    var loaded = try ToolboxTarget.Module.decode(allocator, built.bytes);
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 2), loaded.imports().len);
    try std.testing.expectEqual(@as(u32, 0), loaded.worldPortForSite(FileRead.index).?);
    try std.testing.expectEqual(@as(u32, 1), loaded.worldPortForSite(FileWrite.index).?);
}

test "agent root generated-loaded parity skeleton one-tool flow" {
    const final_text = try runLoadedParityScenario(std.testing.allocator, .skeleton);
    defer std.testing.allocator.free(final_text);
    try std.testing.expectEqualStrings("final=actuate skeleton complete", final_text);
}

test "agent root generated-loaded parity fixture read write flow" {
    const final_text = try runLoadedParityScenario(std.testing.allocator, .fixture);
    defer std.testing.allocator.free(final_text);
    try std.testing.expectEqualStrings("final=fixture updated", final_text);

    const io = std.Io.Threaded.global_single_threaded.io();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, fixture_output_path, std.testing.allocator, .limited(1024));
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("actuate updated the fixture", bytes);
}

test "agent root generated-loaded parity budget exhaustion failure" {
    try runLoadedFailureParityScenario(std.testing.allocator, .budget_exhaustion, 1, "AgentBudgetExhausted");
}

test "agent root generated-loaded parity malformed action failure" {
    try runLoadedFailureParityScenario(std.testing.allocator, .malformed_action, 3, "MalformedAgentAction");
}

test "agent root generated-loaded parity unknown tool failure" {
    try runLoadedFailureParityScenario(std.testing.allocator, .unknown_tool, 3, "UnknownToolId");
}

test "agent toolbox generated-loaded parity actuate pure helper" {
    const result = try runToolboxProviderParityScenario(std.testing.allocator, 0, "", "actuate");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("actuate", result);
}

test "agent toolbox generated-loaded parity read file residual" {
    const result = try runToolboxProviderParityScenario(std.testing.allocator, 1, fixture_input_path, fixture_observation);
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings(fixture_observation, result);
}

test "agent toolbox generated-loaded parity write file residual" {
    const result = try runToolboxProviderParityScenario(std.testing.allocator, 2, fixture_write_payload, "write=ok");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("write=ok", result);
}
