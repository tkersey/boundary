// zlinter-disable declaration_naming no_inferred_error_unions require_doc_comment
const boundary = @import("boundary");
const std = @import("std");

const Agent = boundary.Agent;
const Tools = Agent.ClosedToolSet(&.{ "actuate", "read_file", "write_file" });

const config = Agent.Config{
    .max_iterations = 5,
    .max_model_calls = 5,
    .max_tool_calls = 4,
    .max_observation_bytes = 1024,
    .max_action_bytes = 256,
    .max_tool_result_bytes = 1024,
    .max_trace_entries = 8,
};

const skeleton_final = "final=actuate skeleton complete";
const fixture_input = "rewrite this file through the agent loop\n";
const fixture_observation = "rewrite this file through the agent loop";
const fixture_output = "actuate updated the fixture";
const fixture_final = "final=fixture updated";

const Scenario = enum {
    budget_exhaustion,
    fixture,
    malformed_action,
    skeleton,
    unknown_tool,
};

const Outcome = struct {
    final_text: []const u8 = "",
    failure_reason: []const u8 = "",
    model_calls: u32 = 0,
    tool_calls: u32 = 0,
    terminal_status: Agent.TerminalStatus,
};

fn modelDecision(scenario: Scenario, observation: []const u8) !Agent.Action {
    return switch (scenario) {
        .skeleton => if (std.mem.eql(u8, observation, "goal=invoke"))
            .{ .tool = .{ .tool_id = Tools.id(0), .payload = "" } }
        else if (std.mem.eql(u8, observation, "actuate"))
            .{ .final = skeleton_final }
        else
            .{ .fail = "unexpected skeleton observation" },
        .fixture => if (std.mem.eql(u8, observation, "goal=fixture"))
            .{ .tool = .{ .tool_id = Tools.id(1), .payload = "input.txt" } }
        else if (std.mem.eql(u8, observation, fixture_observation))
            .{ .tool = .{ .tool_id = Tools.id(2), .payload = "output.txt=actuate updated the fixture" } }
        else if (std.mem.eql(u8, observation, "write=ok"))
            .{ .final = fixture_final }
        else
            .{ .fail = "unexpected fixture observation" },
        .budget_exhaustion => .{ .tool = .{ .tool_id = Tools.id(0), .payload = "" } },
        .unknown_tool => .{ .tool = .{ .tool_id = .{ .index = 99, .label = "shell" }, .payload = "" } },
        .malformed_action => {
            _ = try Agent.decodeActionTag(99);
            return error.ExpectedMalformedAction;
        },
    };
}

fn callTool(request: Agent.ToolRequest) !Agent.ToolResult {
    _ = try Tools.label(request.tool_id);
    return switch (request.tool_id.index) {
        0 => .{ .tool_id = request.tool_id, .bytes = "actuate" },
        1 => .{ .tool_id = request.tool_id, .bytes = fixture_observation },
        2 => .{ .tool_id = request.tool_id, .bytes = "write=ok" },
        else => error.UnknownToolId,
    };
}

fn runScenario(scenario: Scenario, initial_observation: []const u8, run_config: Agent.Config) !Outcome {
    var state = try Agent.State.init(initial_observation, initial_observation, run_config);
    while (state.terminal_status == .running) {
        state.beginModelDecision() catch |err| {
            state.fail();
            return .{
                .failure_reason = @errorName(err),
                .model_calls = state.model_call_count,
                .tool_calls = state.tool_call_count,
                .terminal_status = state.terminal_status,
            };
        };
        state.trace_summary.record(run_config.max_trace_entries, "model=prompted", state.iteration_index) catch |err| {
            state.fail();
            return .{
                .failure_reason = @errorName(err),
                .model_calls = state.model_call_count,
                .tool_calls = state.tool_call_count,
                .terminal_status = state.terminal_status,
            };
        };

        const action = modelDecision(scenario, state.current_observation) catch |err| {
            state.fail();
            return .{
                .failure_reason = @errorName(err),
                .model_calls = state.model_call_count,
                .tool_calls = state.tool_call_count,
                .terminal_status = state.terminal_status,
            };
        };
        Agent.validateAction(Tools, run_config, action) catch |err| {
            state.fail();
            return .{
                .failure_reason = @errorName(err),
                .model_calls = state.model_call_count,
                .tool_calls = state.tool_call_count,
                .terminal_status = state.terminal_status,
            };
        };

        switch (action) {
            .final => |text| {
                state.complete();
                return .{
                    .final_text = text,
                    .model_calls = state.model_call_count,
                    .tool_calls = state.tool_call_count,
                    .terminal_status = state.terminal_status,
                };
            },
            .fail => |reason| {
                state.fail();
                return .{
                    .failure_reason = reason,
                    .model_calls = state.model_call_count,
                    .tool_calls = state.tool_call_count,
                    .terminal_status = state.terminal_status,
                };
            },
            .tool => |request| {
                state.beginToolCall() catch |err| {
                    state.fail();
                    return .{
                        .failure_reason = @errorName(err),
                        .model_calls = state.model_call_count,
                        .tool_calls = state.tool_call_count,
                        .terminal_status = state.terminal_status,
                    };
                };
                const result = callTool(request) catch |err| {
                    state.fail();
                    return .{
                        .failure_reason = @errorName(err),
                        .model_calls = state.model_call_count,
                        .tool_calls = state.tool_call_count,
                        .terminal_status = state.terminal_status,
                    };
                };
                try Agent.observeToolResult(run_config, &state, result);
            },
        }
    }
    return error.UnreachableTerminalState;
}

fn expectCompleted(outcome: Outcome, expected: []const u8, expected_tool_calls: u32) !void {
    try std.testing.expectEqual(Agent.TerminalStatus.completed, outcome.terminal_status);
    try std.testing.expectEqualStrings(expected, outcome.final_text);
    try std.testing.expectEqual(expected_tool_calls, outcome.tool_calls);
}

test "Agent Profile conformance skeleton one-tool flow" {
    const outcome = try runScenario(.skeleton, "goal=invoke", config);
    try expectCompleted(outcome, skeleton_final, 1);
}

test "Agent Profile conformance fixture read write flow" {
    _ = fixture_input;
    _ = fixture_output;
    const outcome = try runScenario(.fixture, "goal=fixture", config);
    try expectCompleted(outcome, fixture_final, 2);
}

test "Agent Profile conformance budget exhaustion fails deterministically" {
    var exhausted = config;
    exhausted.max_iterations = 1;
    exhausted.max_model_calls = 1;
    exhausted.max_tool_calls = 1;
    const outcome = try runScenario(.budget_exhaustion, "goal=invoke", exhausted);
    try std.testing.expectEqual(Agent.TerminalStatus.failed, outcome.terminal_status);
    try std.testing.expectEqualStrings("AgentBudgetExhausted", outcome.failure_reason);
}

test "Agent Profile conformance malformed action fails before tool call" {
    const outcome = try runScenario(.malformed_action, "goal=invoke", config);
    try std.testing.expectEqual(Agent.TerminalStatus.failed, outcome.terminal_status);
    try std.testing.expectEqualStrings("MalformedAgentAction", outcome.failure_reason);
    try std.testing.expectEqual(@as(u32, 0), outcome.tool_calls);
}

test "Agent Profile conformance unknown tool id fails closed" {
    const outcome = try runScenario(.unknown_tool, "goal=invoke", config);
    try std.testing.expectEqual(Agent.TerminalStatus.failed, outcome.terminal_status);
    try std.testing.expectEqualStrings("UnknownToolId", outcome.failure_reason);
    try std.testing.expectEqual(@as(u32, 0), outcome.tool_calls);
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    const skeleton = try runScenario(.skeleton, "goal=invoke", config);
    const fixture = try runScenario(.fixture, "goal=fixture", config);
    try stdout.print("skeleton_final={s}\n", .{skeleton.final_text});
    try stdout.print("fixture_final={s}\n", .{fixture.final_text});
    try stdout.flush();
}
