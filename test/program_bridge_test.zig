const bridge_fixture_multi_prompt = @import("direct_style_bridge/multi_prompt.zig");
const bridge_fixture_static_redelim = @import("direct_style_bridge/static_redelim.zig");
const bridge_manifest = @import("direct_style_bridge_manifest");
const lowered_machine = @import("lowered_machine");
const parity_scenarios = @import("parity_scenarios");
const program_bridge = @import("program_bridge");
const std = @import("std");

fn expectCanonicalBridgeCase(case: *const bridge_manifest.Case) !void {
    var lowered = try program_bridge.lowerCaseId(std.testing.allocator, case.case_id);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.status == .canonical);
    try std.testing.expectEqual(case.scenario_id, lowered.canonical_scenario_id.?);
    try std.testing.expectEqualStrings(case.source_module, lowered.source_path);

    const scenario = parity_scenarios.byId(case.scenario_id);
    const state = lowered_machine.runSteps(lowered.steps);

    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try lowered_machine.writeTranscript(&writer, &state);

    try std.testing.expectEqualStrings(scenario.expected_transcript, writer.buffered());
}

fn expectFixtureBridgeCase(
    comptime Fixture: type,
    expected_source_path: []const u8,
    expected_scenario_id: parity_scenarios.ScenarioId,
) !void {
    var lowered = try program_bridge.lowerFixture(std.testing.allocator, Fixture);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.status == .canonical);
    try std.testing.expectEqual(expected_scenario_id, lowered.canonical_scenario_id.?);
    try std.testing.expectEqualStrings(expected_source_path, lowered.source_path);

    const scenario = parity_scenarios.byId(expected_scenario_id);
    const state = lowered_machine.runSteps(lowered.steps);

    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try lowered_machine.writeTranscript(&writer, &state);

    try std.testing.expectEqualStrings(scenario.expected_transcript, writer.buffered());
}

test "program bridge lowers each supported case id from its canonical source module" {
    for (bridge_manifest.cases) |case| {
        if (case.status == .blocked) continue;
        try expectCanonicalBridgeCase(&case);
    }
}

test "program bridge lowers the static redelim fixture wrapper through the fixture seam" {
    try expectFixtureBridgeCase(
        bridge_fixture_static_redelim,
        "test/direct_style_bridge/static_redelim.zig",
        .static_redelim,
    );
}

test "program bridge lowers the multi-prompt fixture wrapper through the fixture seam" {
    try expectFixtureBridgeCase(
        bridge_fixture_multi_prompt,
        "test/direct_style_bridge/multi_prompt.zig",
        .multi_prompt,
    );
}
