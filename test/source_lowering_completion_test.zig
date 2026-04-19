const parity_scenarios = @import("parity_scenarios");
const source_lowering = @import("source_lowering");
const std = @import("std");

const example_resource_basic = @import("example_resource_basic");
const example_writer_basic = @import("example_writer_basic");

const PublicCompletionCase = struct {
    case_id: []const u8,
    source_path: []const u8,
    surface_kind: source_lowering.SurfaceKind,
    entry_symbol: []const u8 = "run",
    scenario_id: parity_scenarios.ScenarioId,
    Runner: type,
};

fn expectPublicCompletionCase(comptime public_example: PublicCompletionCase) !void {
    var direct_buffer: [2048]u8 = undefined;
    var direct_writer = std.Io.Writer.fixed(&direct_buffer);
    try public_example.Runner.run(&direct_writer);

    try std.testing.expect(std.mem.startsWith(u8, public_example.source_path, "examples/"));

    var lowered = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = public_example.case_id,
        .source_path = public_example.source_path,
        .entry_symbol = public_example.entry_symbol,
        .surface_kind = public_example.surface_kind,
    });
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.isAccepted());
    try std.testing.expect(lowered.status == .canonical);
    try std.testing.expect(lowered.surface_kind == .example);
    try std.testing.expectEqual(public_example.scenario_id, lowered.canonical_scenario_id.?);

    var lowered_buffer: [2048]u8 = undefined;
    var lowered_writer = std.Io.Writer.fixed(&lowered_buffer);
    try source_lowering.runLowered(&lowered_writer, &lowered);

    const scenario = parity_scenarios.byId(public_example.scenario_id);
    try std.testing.expectEqualStrings(scenario.expected_transcript, direct_writer.buffered());
    try std.testing.expectEqualStrings(scenario.expected_transcript, lowered_writer.buffered());
}

test "public example completion row resource_basic stays source-backed and canonical" {
    try expectPublicCompletionCase(.{
        .case_id = "example.resource_basic",
        .source_path = "examples/resource_basic.zig",
        .surface_kind = .example,
        .scenario_id = .resource_basic,
        .Runner = example_resource_basic,
    });
}

test "public example completion row writer_basic stays source-backed and canonical" {
    try expectPublicCompletionCase(.{
        .case_id = "example.writer_basic",
        .source_path = "examples/writer_basic.zig",
        .surface_kind = .example,
        .scenario_id = .writer_basic,
        .Runner = example_writer_basic,
    });
}
