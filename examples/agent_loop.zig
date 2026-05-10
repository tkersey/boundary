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

fn mustPlan(result: anyerror!ability.ir.ProgramPlan) ability.ir.ProgramPlan {
    return result catch |err| @compileError("invalid agent loop plan: " ++ @errorName(err));
}

fn agentLoopPlan() ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const remaining = ability.ir.builder.local(root, 0);
    const observation = ability.ir.builder.local(root, 1);
    const budget_empty = ability.ir.builder.local(root, 2);
    const action = ability.ir.builder.local(root, 3);
    const is_final = ability.ir.builder.local(root, 4);
    const answer = ability.ir.builder.local(root, 5);
    const tool_name = ability.ir.builder.local(root, 6);

    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .compare_eq_zero, .dst = budget_empty.index, .operand = remaining.index },
        ability.ir.builder.callOp(root, action, ability.ir.builder.op(root, 0), observation) catch unreachable,
        .{ .kind = .sum_variant_is, .dst = is_final.index, .operand = action.index, .aux = 0 },
        .{ .kind = .sum_extract_payload, .dst = answer.index, .operand = action.index, .aux = 0 },
        ability.ir.builder.returnValue(root, answer) catch unreachable,
        .{ .kind = .sum_extract_payload, .dst = tool_name.index, .operand = action.index, .aux = 1 },
        ability.ir.builder.callOp(root, observation, ability.ir.builder.op(root, 1), tool_name) catch unreachable,
        .{ .kind = .sub_one, .dst = remaining.index, .operand = remaining.index },
        .{ .kind = .const_string, .dst = answer.index, .string_literal = "budget exhausted" },
        ability.ir.builder.returnValue(root, answer) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "agent",
        .value_codec = .string,
        .result_codec = .string,
        .parameter_count = 2,
        .first_requirement = 0,
        .requirement_count = 2,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 7,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 5,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{
        .{ .label = "agent", .first_op = 0, .op_count = 1 },
        .{ .label = "tool", .first_op = 1, .op_count = 1 },
    };
    const ops = [_]ability.ir.plan.Op{
        .{
            .requirement_index = 0,
            .op_name = "decide",
            .mode = .transform,
            .payload_codec = .string,
            .resume_codec = .sum,
            .resume_schema_index = 0,
        },
        .{
            .requirement_index = 1,
            .op_name = "call",
            .mode = .transform,
            .payload_codec = .string,
            .resume_codec = .string,
        },
    };
    const action_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Action),
        .codec = .sum,
        .first_variant = 0,
        .variant_count = 2,
    }};
    const action_variants = [_]ability.ir.ValueVariantPlan{
        .{ .name = "final", .codec = .string },
        .{ .name = "tool", .codec = .string },
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 2, .terminator_index = 1 },
        .{ .first_instruction = 3, .instruction_count = 2, .terminator_index = 2 },
        .{ .first_instruction = 5, .instruction_count = 3, .terminator_index = 3 },
        .{ .first_instruction = 8, .instruction_count = 2, .terminator_index = 4 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 4, .secondary = 1 },
        .{ .kind = .branch_if, .primary = 2, .secondary = 3 },
        .{ .kind = .return_value },
        .{ .kind = .jump, .primary = 0 },
        .{ .kind = .return_value },
    };

    return mustPlan(ability.ir.builder.finish(.{
        .label = "agent-loop-session",
        .ir_hash = 100,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &action_schemas,
        .value_fields = &.{},
        .value_variants = &action_variants,
        .locals = &.{
            .{ .codec = .usize },
            .{ .codec = .string },
            .{ .codec = .bool },
            .{ .codec = .sum, .schema_index = 0 },
            .{ .codec = .bool },
            .{ .codec = .string },
            .{ .codec = .string },
        },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }));
}

const AgentBody = struct {
    pub const value_schema_types = .{Action};
    pub const compiled_plan = agentLoopPlan();

    pub fn encodeArgs(handlers: AgentHandlers) struct { usize, []const u8 } {
        return .{ handlers.initial_remaining, @as([]const u8, "start") };
    }
};

fn hostBetweenTurnsPlan() ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const value = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_string, .dst = value.index, .string_literal = "parked" },
        ability.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "host_check",
        .value_codec = .string,
        .result_codec = .string,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 1,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return mustPlan(ability.ir.builder.finish(.{
        .label = "agent-loop-host-between-turns",
        .ir_hash = 101,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &.{},
        .value_fields = &.{},
        .value_variants = &.{},
        .locals = &.{.{ .codec = .string }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }));
}

const HostBetweenTurnsBody = struct {
    pub const compiled_plan = hostBetweenTurnsPlan();
};

fn runSession(writer: anytype, mode: TraceMode, recording: *TraceRecording) ![]const u8 {
    var runtime = ability.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    const Program = ability.program("agent-loop-session", AgentHandlers, AgentBody);
    const HostBetweenTurns = ability.program("agent-loop-host-between-turns", struct {}, HostBetweenTurnsBody);
    var session = try Program.Session.start(&runtime, .{ .initial_remaining = 3 });
    defer session.deinit();

    var replay_index: usize = 0;
    const phase = @tagName(mode);

    while (true) {
        switch (try session.next()) {
            .after => return error.UnexpectedAfter,
            .request => |request| {
                const trace = request.trace();
                try writer.print("{s} turn={d} kind={s} op={s} request={x}\n", .{
                    phase,
                    trace.turn_index,
                    @tagName(trace.kind),
                    trace.op_name,
                    trace.fingerprint,
                });

                var host_check = try HostBetweenTurns.run(&runtime, .{});
                defer host_check.deinit();
                try writer.print("{s} between_turns={s}\n", .{ phase, host_check.value });

                if (std.mem.eql(u8, request.op_name, "decide")) {
                    const action = switch (mode) {
                        .record => action: {
                            const observation = try request.payload([]const u8);
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
                    const response_trace = try request.responseTrace(.@"resume", action);
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
                    try session.@"resume"(request, action);
                } else if (std.mem.eql(u8, request.op_name, "call")) {
                    const text = switch (mode) {
                        .record => text: {
                            const tool_name = try request.payload([]const u8);
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
                    const response_trace = try request.responseTrace(.@"resume", text);
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
                    try session.@"resume"(request, text);
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
