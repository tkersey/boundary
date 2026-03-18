const source_lowering = @import("source_lowering");
const parity_scenarios = @import("parity_scenarios");
const std = @import("std");

const example_early_exit = @import("promoted_example_early_exit");
const example_exception_basic = @import("promoted_example_exception_basic");
const example_front_door_workflow = @import("promoted_example_front_door_workflow");
const example_nested_workflow = @import("promoted_example_nested_workflow");
const example_optional_basic = @import("promoted_example_optional_basic");
const example_reader_basic = @import("promoted_example_reader_basic");
const example_resume_or_return = @import("promoted_example_resume_or_return");
const example_state_basic = @import("promoted_example_state_basic");

const PromotedCase = struct {
    case_id: []const u8,
    source_path: []const u8,
    surface_kind: source_lowering.SurfaceKind,
    entry_symbol: []const u8 = "run",
    scenario_id: parity_scenarios.ScenarioId,
    Runner: type,
};

fn expectPromotedCase(comptime promoted: PromotedCase) !void {
    var direct_buffer: [2048]u8 = undefined;
    var direct_writer = std.Io.Writer.fixed(&direct_buffer);
    try promoted.Runner.run(&direct_writer);

    var lowered = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = promoted.case_id,
        .source_path = promoted.source_path,
        .entry_symbol = promoted.entry_symbol,
        .surface_kind = promoted.surface_kind,
    });
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.isAccepted());
    try std.testing.expect(lowered.status == .canonical);
    try std.testing.expectEqual(promoted.scenario_id, lowered.canonical_scenario_id.?);

    var lowered_buffer: [2048]u8 = undefined;
    var lowered_writer = std.Io.Writer.fixed(&lowered_buffer);
    try source_lowering.runLowered(&lowered_writer, &lowered);

    const scenario = parity_scenarios.byId(promoted.scenario_id);
    try std.testing.expectEqualStrings(scenario.expected_transcript, direct_writer.buffered());
    try std.testing.expectEqualStrings(scenario.expected_transcript, lowered_writer.buffered());
}

test "promoted source-lowering example and effect cohort stays source-backed and canonical" {
    try expectPromotedCase(.{
        .case_id = "example.early_exit",
        .source_path = "examples/early_exit.zig",
        .surface_kind = .example,
        .scenario_id = .early_exit,
        .Runner = example_early_exit,
    });
    try expectPromotedCase(.{
        .case_id = "example.resume_or_return",
        .source_path = "examples/resume_or_return.zig",
        .surface_kind = .example,
        .scenario_id = .resume_or_return,
        .Runner = example_resume_or_return,
    });
    try expectPromotedCase(.{
        .case_id = "example.front_door_workflow",
        .source_path = "examples/front_door_workflow.zig",
        .surface_kind = .example,
        .scenario_id = .front_door_workflow,
        .Runner = example_front_door_workflow,
    });
    try expectPromotedCase(.{
        .case_id = "example.nested_workflow",
        .source_path = "examples/nested_workflow.zig",
        .surface_kind = .example,
        .scenario_id = .nested_workflow_publish,
        .Runner = example_nested_workflow,
    });
    try expectPromotedCase(.{
        .case_id = "example.state_basic",
        .source_path = "examples/state_basic.zig",
        .surface_kind = .example,
        .scenario_id = .state_basic,
        .Runner = example_state_basic,
    });
    try expectPromotedCase(.{
        .case_id = "example.reader_basic",
        .source_path = "examples/reader_basic.zig",
        .surface_kind = .example,
        .scenario_id = .reader_basic,
        .Runner = example_reader_basic,
    });
    try expectPromotedCase(.{
        .case_id = "example.optional_basic",
        .source_path = "examples/optional_basic.zig",
        .surface_kind = .example,
        .scenario_id = .optional_basic,
        .Runner = example_optional_basic,
    });
    try expectPromotedCase(.{
        .case_id = "example.exception_basic",
        .source_path = "examples/exception_basic.zig",
        .surface_kind = .example,
        .scenario_id = .exception_basic,
        .Runner = example_exception_basic,
    });
    try expectPromotedCase(.{
        .case_id = "effect.state_basic",
        .source_path = "examples/state_basic.zig",
        .surface_kind = .effect,
        .scenario_id = .state_basic,
        .Runner = example_state_basic,
    });
    try expectPromotedCase(.{
        .case_id = "effect.reader_basic",
        .source_path = "examples/reader_basic.zig",
        .surface_kind = .effect,
        .scenario_id = .reader_basic,
        .Runner = example_reader_basic,
    });
    try expectPromotedCase(.{
        .case_id = "effect.optional_basic",
        .source_path = "examples/optional_basic.zig",
        .surface_kind = .effect,
        .scenario_id = .optional_basic,
        .Runner = example_optional_basic,
    });
    try expectPromotedCase(.{
        .case_id = "effect.exception_basic",
        .source_path = "examples/exception_basic.zig",
        .surface_kind = .effect,
        .scenario_id = .exception_basic,
        .Runner = example_exception_basic,
    });
}
