const lowered_machine = @import("lowered_machine");
const parity_scenarios = @import("parity_scenarios");
const program_bridge = @import("program_bridge");
const std = @import("std");

fn expectBridgeCase(case_id: []const u8) !void {
    var lowered = try program_bridge.lowerCaseId(std.testing.allocator, case_id);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.status == .canonical);
    try std.testing.expect(lowered.canonical_scenario_id != null);

    const scenario = parity_scenarios.byId(lowered.canonical_scenario_id.?);
    const state = lowered_machine.runSteps(lowered.steps);

    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try lowered_machine.writeTranscript(&writer, &state);

    try std.testing.expectEqualStrings(scenario.expected_transcript, writer.buffered());
}

test "program bridge lowers static redelim witness source to the canonical scenario" {
    try expectBridgeCase("static_redelim");
}

test "program bridge lowers multi-prompt witness source to the canonical scenario" {
    try expectBridgeCase("multi_prompt");
}
