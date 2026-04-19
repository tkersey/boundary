const parity_scenarios = @import("parity_scenarios");
const source_lowering = @import("source_lowering");
const std = @import("std");

const CompletionCase = struct {
    case_id: []const u8,
    source_path: []const u8,
    entry_symbol: []const u8,
    scenario_id: parity_scenarios.ScenarioId,
};

fn expectWitnessCase(comptime completion: CompletionCase) !void {
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
    try std.testing.expectEqualStrings(scenario.expected_transcript, lowered_writer.buffered());
}

test "admitted source-lowering witness rows stay source-backed and canonical" {
    try expectWitnessCase(.{
        .case_id = "witness.atm_resume_transform",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runAtmResumeTransform",
        .scenario_id = .atm_resume_transform,
    });
    try expectWitnessCase(.{
        .case_id = "witness.direct_return",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runDirectReturn",
        .scenario_id = .direct_return,
    });
    try expectWitnessCase(.{
        .case_id = "witness.multi_prompt",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runMultiPrompt",
        .scenario_id = .multi_prompt,
    });
    try expectWitnessCase(.{
        .case_id = "witness.resume_or_return_return_now",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runResumeOrReturnReturnNow",
        .scenario_id = .resume_or_return_return_now,
    });
    try expectWitnessCase(.{
        .case_id = "witness.resume_or_return_resume",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runResumeOrReturnResume",
        .scenario_id = .resume_or_return_resume,
    });
    try expectWitnessCase(.{
        .case_id = "witness.static_redelim",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runStaticRedelim",
        .scenario_id = .static_redelim,
    });
    try expectWitnessCase(.{
        .case_id = "witness.generator",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runGenerator",
        .scenario_id = .generator,
    });
}
