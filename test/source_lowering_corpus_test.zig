const parity_scenarios = @import("parity_scenarios");
const source_lowering = @import("source_lowering");
const source_lowering_registry = @import("source_lowering_registry");
const std = @import("std");

const branch_resume = @import("source_fixture_branch_resume");
const defer_resume = @import("source_fixture_defer_resume");
const errdefer_error = @import("source_fixture_errdefer_error");
const helper_call_resume = @import("source_fixture_helper_call_resume");
const local_mutation_resume = @import("source_fixture_local_mutation_resume");
const loop_resume = @import("source_fixture_loop_resume");
const nested_prompt_static_redelim = @import("source_fixture_nested_prompt_static_redelim");
const typed_error_try = @import("source_fixture_typed_error_try");

fn expectCase(comptime Fixture: type) !void {
    const case = source_lowering_registry.find(Fixture.source_case_id).?;
    var lowered = try source_lowering.lowerFixture(std.testing.allocator, Fixture);
    defer lowered.deinit(std.testing.allocator);

    var source_buffer: [1024]u8 = undefined;
    var source_writer = std.Io.Writer.fixed(&source_buffer);
    try Fixture.run(&source_writer);

    var lowered_buffer: [1024]u8 = undefined;
    var lowered_writer = std.Io.Writer.fixed(&lowered_buffer);
    try std.testing.expect(lowered.isAccepted());
    try source_lowering.runLowered(&lowered_writer, &lowered);

    const scenario = parity_scenarios.byId(case.scenario_id);
    try std.testing.expectEqualStrings(scenario.expected_transcript, source_writer.buffered());
    try std.testing.expectEqualStrings(scenario.expected_transcript, lowered_writer.buffered());
    try std.testing.expectEqual(case.scenario_id, lowered.canonical_scenario_id.?);
    try std.testing.expectEqual(@as(usize, scenario.steps.len), lowered.steps.len);
    try std.testing.expect(lowered.status == .canonical);

    if (case.forbidden_transcript) |forbidden| {
        try std.testing.expect(!std.mem.eql(u8, forbidden, source_writer.buffered()));
        try std.testing.expect(!std.mem.eql(u8, forbidden, lowered_writer.buffered()));
    }
}

test "source-lowering corpus local_mutation_resume stays green across direct source fixtures and lowered scenarios" {
    try expectCase(local_mutation_resume);
}

test "source-lowering corpus branch_resume stays green across direct source fixtures and lowered scenarios" {
    try expectCase(branch_resume);
}

test "source-lowering corpus loop_resume stays green across direct source fixtures and lowered scenarios" {
    try expectCase(loop_resume);
}

test "source-lowering corpus helper_call_resume stays green across direct source fixtures and lowered scenarios" {
    try expectCase(helper_call_resume);
}

test "source-lowering corpus nested_prompt_static_redelim stays green across direct source fixtures and lowered scenarios" {
    try expectCase(nested_prompt_static_redelim);
}

test "source-lowering corpus typed_error_try stays green across direct source fixtures and lowered scenarios" {
    try expectCase(typed_error_try);
}

test "source-lowering corpus defer_resume stays green across direct source fixtures and lowered scenarios" {
    try expectCase(defer_resume);
}

test "source-lowering corpus errdefer_error stays green across direct source fixtures and lowered scenarios" {
    try expectCase(errdefer_error);
}
