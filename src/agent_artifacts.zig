// zlinter-disable declaration_naming no_inferred_error_unions require_doc_comment require_errdefer_dealloc
const Agent = @import("agent.zig");
const std = @import("std");

const corpus_dir = "conformance/v0/agent";
const corpus_manifest_path = corpus_dir ++ "/corpus.boundary-agent.txt";

const Tools = Agent.ClosedToolSet(&.{ "actuate", "read_file", "write_file" });
const tool_ids = [_]Agent.ToolId{ Tools.id(0), Tools.id(1), Tools.id(2) };

const config = Agent.Config{
    .max_iterations = 5,
    .max_model_calls = 5,
    .max_tool_calls = 4,
    .max_observation_bytes = 1024,
    .max_action_bytes = 256,
    .max_tool_result_bytes = 1024,
    .max_trace_entries = 8,
};

const Scenario = struct {
    scenario_id: []const u8,
    kind: []const u8,
    initial_observation: []const u8,
    expected_terminal_status: ?Agent.TerminalStatus,
    expected_final: []const u8 = "",
    expected_failure: []const u8 = "",
    expected_rejection: []const u8 = "",
    expected_model_calls: ?u32,
    expected_tool_calls: ?u32,
    run_config: Agent.Config = config,
    replay: []const u8,
};

const scenarios = [_]Scenario{
    .{
        .scenario_id = "skeleton-one-tool",
        .kind = "positive",
        .initial_observation = "goal=invoke",
        .expected_terminal_status = .completed,
        .expected_final = "final=actuate skeleton complete",
        .expected_model_calls = 2,
        .expected_tool_calls = 1,
        .replay = "zig build check-boundary-agent-conformance-corpus -- --test-filter 'skeleton one-tool'",
    },
    .{
        .scenario_id = "fixture-read-write",
        .kind = "positive",
        .initial_observation = "goal=fixture",
        .expected_terminal_status = .completed,
        .expected_final = "final=fixture updated",
        .expected_model_calls = 3,
        .expected_tool_calls = 2,
        .replay = "zig build check-boundary-agent-conformance-corpus -- --test-filter 'fixture read write'",
    },
    .{
        .scenario_id = "budget-exhaustion",
        .kind = "negative",
        .initial_observation = "goal=invoke",
        .expected_terminal_status = .failed,
        .expected_failure = "AgentBudgetExhausted",
        .expected_model_calls = 1,
        .expected_tool_calls = 1,
        .run_config = .{
            .max_iterations = 1,
            .max_model_calls = 1,
            .max_tool_calls = 1,
            .max_observation_bytes = config.max_observation_bytes,
            .max_action_bytes = config.max_action_bytes,
            .max_tool_result_bytes = config.max_tool_result_bytes,
            .max_trace_entries = config.max_trace_entries,
        },
        .replay = "zig build check-boundary-agent-conformance-corpus -- --test-filter 'budget exhaustion'",
    },
    .{
        .scenario_id = "malformed-action",
        .kind = "negative",
        .initial_observation = "goal=invoke",
        .expected_terminal_status = .failed,
        .expected_failure = "MalformedAgentAction",
        .expected_model_calls = 1,
        .expected_tool_calls = 0,
        .replay = "zig build check-boundary-agent-conformance-corpus -- --test-filter 'malformed action'",
    },
    .{
        .scenario_id = "unknown-tool-id",
        .kind = "negative",
        .initial_observation = "goal=invoke",
        .expected_terminal_status = .failed,
        .expected_failure = "UnknownToolId",
        .expected_model_calls = 1,
        .expected_tool_calls = 0,
        .replay = "zig build check-boundary-agent-conformance-corpus -- --test-filter 'unknown tool id'",
    },
    .{
        .scenario_id = "generated-loaded-parity",
        .kind = "parity",
        .initial_observation = "agent-module-manifest",
        .expected_terminal_status = .completed,
        .expected_final = "approved:7",
        .expected_model_calls = 0,
        .expected_tool_calls = 0,
        .replay = "zig build check-boundary-agent-generated-loaded-parity",
    },
    .{
        .scenario_id = "agent-root-generated-loaded-skeleton",
        .kind = "parity",
        .initial_observation = "goal=invoke",
        .expected_terminal_status = .completed,
        .expected_final = "final=actuate skeleton complete",
        .expected_model_calls = 2,
        .expected_tool_calls = 1,
        .replay = "zig build check-boundary-agent-generated-loaded-parity -- --test-filter 'agent root generated-loaded parity skeleton'",
    },
    .{
        .scenario_id = "agent-root-generated-loaded-fixture",
        .kind = "parity",
        .initial_observation = "goal=fixture",
        .expected_terminal_status = .completed,
        .expected_final = "final=fixture updated",
        .expected_model_calls = 3,
        .expected_tool_calls = 2,
        .replay = "zig build check-boundary-agent-generated-loaded-parity -- --test-filter 'agent root generated-loaded parity fixture'",
    },
    .{
        .scenario_id = "agent-root-generated-loaded-budget-exhaustion",
        .kind = "parity",
        .initial_observation = "goal=invoke",
        .expected_terminal_status = .failed,
        .expected_failure = "AgentBudgetExhausted",
        .expected_model_calls = 1,
        .expected_tool_calls = 1,
        .run_config = .{
            .max_iterations = 1,
            .max_model_calls = 1,
            .max_tool_calls = 1,
            .max_observation_bytes = config.max_observation_bytes,
            .max_action_bytes = config.max_action_bytes,
            .max_tool_result_bytes = config.max_tool_result_bytes,
            .max_trace_entries = config.max_trace_entries,
        },
        .replay = "zig build check-boundary-agent-generated-loaded-parity -- --test-filter 'agent root generated-loaded parity budget exhaustion'",
    },
    .{
        .scenario_id = "agent-root-generated-loaded-malformed-action",
        .kind = "parity",
        .initial_observation = "goal=invoke",
        .expected_terminal_status = null,
        .expected_rejection = "generated=ProgramContractViolation loaded=InvalidResume before_tool_dispatch=true",
        .expected_model_calls = null,
        .expected_tool_calls = null,
        .replay = "zig build check-boundary-agent-generated-loaded-parity -- --test-filter 'agent root generated-loaded parity malformed action'",
    },
    .{
        .scenario_id = "agent-root-generated-loaded-unknown-tool",
        .kind = "parity",
        .initial_observation = "goal=invoke",
        .expected_terminal_status = .failed,
        .expected_failure = "UnknownToolId",
        .expected_model_calls = 1,
        .expected_tool_calls = 0,
        .replay = "zig build check-boundary-agent-generated-loaded-parity -- --test-filter 'agent root generated-loaded parity unknown tool'",
    },
    .{
        .scenario_id = "agent-toolbox-generated-loaded-actuate",
        .kind = "parity",
        .initial_observation = "tool_index=0",
        .expected_terminal_status = .completed,
        .expected_final = "actuate",
        .expected_model_calls = 0,
        .expected_tool_calls = 1,
        .replay = "zig build check-boundary-agent-generated-loaded-parity -- --test-filter 'agent toolbox generated-loaded parity actuate'",
    },
    .{
        .scenario_id = "agent-toolbox-generated-loaded-read-file",
        .kind = "parity",
        .initial_observation = "tool_index=1",
        .expected_terminal_status = .completed,
        .expected_final = "rewrite this file through the agent loop",
        .expected_model_calls = 0,
        .expected_tool_calls = 1,
        .replay = "zig build check-boundary-agent-generated-loaded-parity -- --test-filter 'agent toolbox generated-loaded parity read'",
    },
    .{
        .scenario_id = "agent-toolbox-generated-loaded-write-file",
        .kind = "parity",
        .initial_observation = "tool_index=2",
        .expected_terminal_status = .completed,
        .expected_final = "write=ok",
        .expected_model_calls = 0,
        .expected_tool_calls = 1,
        .replay = "zig build check-boundary-agent-generated-loaded-parity -- --test-filter 'agent toolbox generated-loaded parity write'",
    },
};

fn profile() Agent.Profile {
    return Agent.Profile.fromConfig(config, &tool_ids, Agent.canonicalValueSchemaFingerprints(), "agent-conformance-corpus-v0");
}

pub fn main(init: std.process.Init) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const allocator = arena_state.allocator();
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const command = args.next() orelse return error.InvalidArguments;
    if (std.mem.eql(u8, command, "update-corpus")) return updateCorpus(init, allocator);
    if (std.mem.eql(u8, command, "check-corpus")) return checkCorpus(init, allocator);
    return error.InvalidArguments;
}

fn updateCorpus(init: std.process.Init, allocator: std.mem.Allocator) !void {
    const corpus = try corpusManifestAlloc(allocator);
    try std.Io.Dir.cwd().createDirPath(init.io, corpus_dir);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = corpus_manifest_path, .data = corpus });
}

fn checkCorpus(init: std.process.Init, allocator: std.mem.Allocator) !void {
    const expected = try corpusManifestAlloc(allocator);
    const actual = try std.Io.Dir.cwd().readFileAlloc(init.io, corpus_manifest_path, allocator, .limited(256 * 1024));
    if (!std.mem.eql(u8, expected, actual)) return error.AgentConformanceCorpusDrift;
}

fn corpusManifestAlloc(allocator: std.mem.Allocator) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    const p = profile();
    try p.validate();

    try appendFmt(&out, allocator,
        \\Boundary Agent Profile v0 conformance corpus
        \\format: boundary-agent-conformance-corpus-v0
        \\profile_format_version: {d}
        \\profile_fingerprint_version: {d}
        \\profile_fingerprint: 0x{x:0>16}
        \\max_iterations: {d}
        \\max_model_calls: {d}
        \\max_tool_calls: {d}
        \\max_observation_bytes: {d}
        \\max_action_bytes: {d}
        \\max_tool_result_bytes: {d}
        \\max_trace_entries: {d}
        \\
    , .{
        p.format_version,
        p.fingerprint_version,
        p.profile_fingerprint,
        p.max_iterations,
        p.max_model_calls,
        p.max_tool_calls,
        p.max_observation_bytes,
        p.max_action_bytes,
        p.max_tool_result_bytes,
        p.max_trace_entries,
    });

    try appendLine(&out, allocator, "tool_variants:");
    for (tool_ids) |tool_id| {
        try appendFmt(&out, allocator, "- index: {d}\n  label: {s}\n", .{ tool_id.index, tool_id.diagnostic_label });
    }
    try appendLine(&out, allocator, "");
    try appendLine(&out, allocator, "value_schemas:");
    for (Agent.canonical_value_schemas) |value_schema| {
        try appendFmt(&out, allocator,
            \\- name: {s}
            \\  codec: {s}
            \\  fingerprint: 0x{x:0>16}
            \\
        , .{ value_schema.name, value_schema.codec, value_schema.fingerprint });
    }
    try appendLine(&out, allocator, "");
    try appendLine(&out, allocator, "scenarios:");
    for (scenarios) |scenario| try appendScenario(&out, allocator, scenario);
    try appendLine(&out, allocator, "");
    try appendLine(&out, allocator, "validation:");
    try appendLine(&out, allocator, "- check-boundary-agent-conformance-corpus compares this catalog and executes the scenario tests");
    try appendLine(&out, allocator, "- check-boundary-agent-generated-loaded-parity covers Agent module transfer plus positive and negative root-agent parity and toolbox-provider parity");
    try appendLine(&out, allocator, "- model and tools are deterministic fixtures; no network, credentials, host registry, or real LLM is used");
    return out.toOwnedSlice(allocator);
}

fn appendScenario(out: *std.ArrayList(u8), allocator: std.mem.Allocator, scenario: Scenario) !void {
    try appendFmt(out, allocator,
        \\- id: {s}
        \\  kind: {s}
        \\  initial_observation: {s}
        \\  scenario_max_iterations: {d}
        \\  scenario_max_model_calls: {d}
        \\  scenario_max_tool_calls: {d}
        \\  scenario_max_observation_bytes: {d}
        \\  scenario_max_action_bytes: {d}
        \\  scenario_max_tool_result_bytes: {d}
        \\  scenario_max_trace_entries: {d}
        \\
    , .{
        scenario.scenario_id,
        scenario.kind,
        scenario.initial_observation,
        scenario.run_config.max_iterations,
        scenario.run_config.max_model_calls,
        scenario.run_config.max_tool_calls,
        scenario.run_config.max_observation_bytes,
        scenario.run_config.max_action_bytes,
        scenario.run_config.max_tool_result_bytes,
        scenario.run_config.max_trace_entries,
    });
    if (scenario.expected_terminal_status) |terminal_status| {
        try appendFmt(out, allocator, "  expected_terminal_status: {s}\n", .{@tagName(terminal_status)});
    }
    if (scenario.expected_model_calls) |model_calls| {
        try appendFmt(out, allocator, "  expected_model_calls: {d}\n", .{model_calls});
    }
    if (scenario.expected_tool_calls) |tool_calls| {
        try appendFmt(out, allocator, "  expected_tool_calls: {d}\n", .{tool_calls});
    }
    if (scenario.expected_final.len != 0) {
        try appendFmt(out, allocator,
            \\  expected_final: {s}
            \\  expected_final_fingerprint: 0x{x:0>16}
            \\
        , .{ scenario.expected_final, Agent.fingerprintBytes(scenario.expected_final) });
    }
    if (scenario.expected_failure.len != 0) {
        try appendFmt(out, allocator,
            \\  expected_failure: {s}
            \\  expected_failure_fingerprint: 0x{x:0>16}
            \\
        , .{ scenario.expected_failure, Agent.fingerprintBytes(scenario.expected_failure) });
    }
    if (scenario.expected_rejection.len != 0) {
        try appendFmt(out, allocator, "  expected_rejection: {s}\n", .{scenario.expected_rejection});
    }
    try appendFmt(out, allocator, "  replay: {s}\n", .{scenario.replay});
}

fn appendLine(out: *std.ArrayList(u8), allocator: std.mem.Allocator, line: []const u8) !void {
    try out.appendSlice(allocator, line);
    try out.append(allocator, '\n');
}

fn appendFmt(out: *std.ArrayList(u8), allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

test "Agent conformance corpus generator is deterministic" {
    const allocator = std.testing.allocator;
    const first = try corpusManifestAlloc(allocator);
    defer allocator.free(first);
    const second = try corpusManifestAlloc(allocator);
    defer allocator.free(second);
    try std.testing.expectEqualSlices(u8, first, second);
    try std.testing.expect(std.mem.find(u8, first, "skeleton-one-tool") != null);
    try std.testing.expect(std.mem.find(u8, first, "generated-loaded-parity") != null);
}
