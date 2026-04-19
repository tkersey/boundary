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

test "program bridge lowers case atm_resume_transform from its canonical source module" {
    try expectCanonicalBridgeCase(bridge_manifest.find("atm_resume_transform").?);
}

test "program bridge lowers case direct_return from its canonical source module" {
    try expectCanonicalBridgeCase(bridge_manifest.find("direct_return").?);
}

test "program bridge lowers case multi_prompt from its canonical source module" {
    try expectCanonicalBridgeCase(bridge_manifest.find("multi_prompt").?);
}

test "program bridge lowers case resume_or_return_resume from its canonical source module" {
    try expectCanonicalBridgeCase(bridge_manifest.find("resume_or_return_resume").?);
}

test "program bridge lowers case resume_or_return_return_now from its canonical source module" {
    try expectCanonicalBridgeCase(bridge_manifest.find("resume_or_return_return_now").?);
}

test "program bridge lowers case static_redelim from its canonical source module" {
    try expectCanonicalBridgeCase(bridge_manifest.find("static_redelim").?);
}

test "program bridge lowers case early_exit from its canonical source module" {
    try expectCanonicalBridgeCase(bridge_manifest.find("early_exit").?);
}

test "program bridge lowers case resume_or_return from its canonical source module" {
    try expectCanonicalBridgeCase(bridge_manifest.find("resume_or_return").?);
}

test "program bridge lowers case nested_workflow from its canonical source module" {
    try expectCanonicalBridgeCase(bridge_manifest.find("nested_workflow").?);
}

test "program bridge lowers case open_row_generator from its canonical source module" {
    try expectCanonicalBridgeCase(bridge_manifest.find("open_row_generator").?);
}

test "program bridge lowers case state_basic from its canonical source module" {
    try expectCanonicalBridgeCase(bridge_manifest.find("state_basic").?);
}

test "program bridge lowers case reader_basic from its canonical source module" {
    try expectCanonicalBridgeCase(bridge_manifest.find("reader_basic").?);
}

test "program bridge lowers case optional_basic from its canonical source module" {
    try expectCanonicalBridgeCase(bridge_manifest.find("optional_basic").?);
}

test "program bridge lowers case exception_basic from its canonical source module" {
    try expectCanonicalBridgeCase(bridge_manifest.find("exception_basic").?);
}

test "program bridge lowers case resource_basic from its canonical source module" {
    try expectCanonicalBridgeCase(bridge_manifest.find("resource_basic").?);
}

test "program bridge lowers case writer_basic from its canonical source module" {
    try expectCanonicalBridgeCase(bridge_manifest.find("writer_basic").?);
}

test "program bridge lowers case open_row_abortive_validation from its canonical source module" {
    try expectCanonicalBridgeCase(bridge_manifest.find("open_row_abortive_validation").?);
}

test "program bridge lowers case open_row_artifact_search from its canonical source module" {
    try expectCanonicalBridgeCase(bridge_manifest.find("open_row_artifact_search").?);
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
