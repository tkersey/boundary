const source_lowering = @import("source_lowering");
const parity_scenarios = @import("parity_scenarios");
const std = @import("std");
const witness_sources = @import("witness_sources");

const CompletionCase = struct {
    case_id: []const u8,
    source_path: []const u8,
    entry_symbol: []const u8,
    scenario_id: parity_scenarios.ScenarioId,
    Runner: type,
};

fn expectWitnessCase(comptime completion: CompletionCase) !void {
    var direct_buffer: [2048]u8 = undefined;
    var direct_writer = std.Io.Writer.fixed(&direct_buffer);
    try completion.Runner.run(&direct_writer);

    var lowered = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = completion.case_id,
        .source_path = completion.source_path,
        .entry_symbol = completion.entry_symbol,
        .surface_kind = .witness,
    });
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.isAccepted());
    try std.testing.expect(lowered.status == .canonical);
    try std.testing.expectEqual(completion.scenario_id, lowered.canonical_scenario_id.?);

    var lowered_buffer: [2048]u8 = undefined;
    var lowered_writer = std.Io.Writer.fixed(&lowered_buffer);
    try source_lowering.runLowered(&lowered_writer, &lowered);

    const scenario = parity_scenarios.byId(completion.scenario_id);
    try std.testing.expectEqualStrings(scenario.expected_transcript, direct_writer.buffered());
    try std.testing.expectEqualStrings(scenario.expected_transcript, lowered_writer.buffered());
}

const witness_atm_runner = struct {
    /// Run this public entrypoint.
    pub fn run(writer: anytype) anyerror!void {
        try witness_sources.runAtmResumeTransform(writer);
    }
};
const witness_direct_runner = struct {
    /// Run this public entrypoint.
    pub fn run(writer: anytype) anyerror!void {
        try witness_sources.runDirectReturn(writer);
    }
};
const witness_ror_return_runner = struct {
    /// Run this public entrypoint.
    pub fn run(writer: anytype) anyerror!void {
        try witness_sources.runResumeOrReturnReturnNow(writer);
    }
};
const witness_ror_resume_runner = struct {
    /// Run this public entrypoint.
    pub fn run(writer: anytype) anyerror!void {
        try witness_sources.runResumeOrReturnResume(writer);
    }
};
const witness_static_runner = struct {
    /// Run this public entrypoint.
    pub fn run(writer: anytype) anyerror!void {
        try witness_sources.runStaticRedelim(writer);
    }
};
const witness_multi_runner = struct {
    /// Run this public entrypoint.
    pub fn run(writer: anytype) anyerror!void {
        try witness_sources.runMultiPrompt(writer);
    }
};
const witness_generator_runner = struct {
    /// Run this public entrypoint.
    pub fn run(writer: anytype) anyerror!void {
        try witness_sources.runGenerator(writer);
    }
};

test "source-lowering witness rows stay source-backed and canonical" {
    try expectWitnessCase(.{
        .case_id = "witness.atm_resume_transform",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runAtmResumeTransform",
        .scenario_id = .atm_resume_transform,
        .Runner = witness_atm_runner,
    });
    try expectWitnessCase(.{
        .case_id = "witness.direct_return",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runDirectReturn",
        .scenario_id = .direct_return,
        .Runner = witness_direct_runner,
    });
    try expectWitnessCase(.{
        .case_id = "witness.resume_or_return_return_now",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runResumeOrReturnReturnNow",
        .scenario_id = .resume_or_return_return_now,
        .Runner = witness_ror_return_runner,
    });
    try expectWitnessCase(.{
        .case_id = "witness.resume_or_return_resume",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runResumeOrReturnResume",
        .scenario_id = .resume_or_return_resume,
        .Runner = witness_ror_resume_runner,
    });
    try expectWitnessCase(.{
        .case_id = "witness.static_redelim",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runStaticRedelim",
        .scenario_id = .static_redelim,
        .Runner = witness_static_runner,
    });
    try expectWitnessCase(.{
        .case_id = "witness.multi_prompt",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runMultiPrompt",
        .scenario_id = .multi_prompt,
        .Runner = witness_multi_runner,
    });
    try expectWitnessCase(.{
        .case_id = "witness.generator",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runGenerator",
        .scenario_id = .generator,
        .Runner = witness_generator_runner,
    });
}
