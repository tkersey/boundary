const parity_scenarios = @import("parity_scenarios");
const source_lowering = @import("source_lowering");
const std = @import("std");

/// One canonical source-lowering case plus the direct baseline runner that should match it.
pub const CanonicalSourceCase = struct {
    case_id: []const u8,
    source_path: []const u8,
    surface_kind: source_lowering.SurfaceKind,
    entry_symbol: []const u8 = "run",
    scenario_id: parity_scenarios.ScenarioId,
};

/// Prove the lowered canonical case matches the expected transcript and canonical metadata.
pub fn expectCanonicalSourceCase(comptime canonical_case: CanonicalSourceCase) anyerror!void {
    try std.testing.expect(std.mem.startsWith(u8, canonical_case.source_path, "examples/"));

    var lowered = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = canonical_case.case_id,
        .source_path = canonical_case.source_path,
        .entry_symbol = canonical_case.entry_symbol,
        .surface_kind = canonical_case.surface_kind,
    });
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.isAccepted());
    try std.testing.expect(lowered.status == .canonical);
    try std.testing.expectEqual(canonical_case.surface_kind, lowered.surface_kind);
    try std.testing.expectEqual(canonical_case.scenario_id, lowered.canonical_scenario_id.?);

    var lowered_buffer: [2048]u8 = undefined;
    var lowered_writer = std.Io.Writer.fixed(&lowered_buffer);
    try source_lowering.runLowered(&lowered_writer, &lowered);

    const scenario = parity_scenarios.byId(canonical_case.scenario_id);
    try std.testing.expectEqualStrings(scenario.expected_transcript, lowered_writer.buffered());
}
