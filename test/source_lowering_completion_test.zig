const parity_scenarios = @import("parity_scenarios");
const source_lowering = @import("source_lowering");
const std = @import("std");

const example_algebraic_abortive_validation = @import("example_algebraic_abortive_validation");
const example_algebraic_artifact_search = @import("example_algebraic_artifact_search");
const example_define_abort_basic = @import("example_define_abort_basic");
const example_define_basic = @import("example_define_basic");
const example_define_choice_basic = @import("example_define_choice_basic");
const example_resource_basic = @import("example_resource_basic");
const example_writer_basic = @import("example_writer_basic");

const CompletionCase = struct {
    case_id: []const u8,
    source_path: []const u8,
    surface_kind: source_lowering.SurfaceKind,
    entry_symbol: []const u8 = "run",
    scenario_id: parity_scenarios.ScenarioId,
    Runner: type,
};

fn expectCompletionCase(comptime completion: CompletionCase) !void {
    var direct_buffer: [2048]u8 = undefined;
    var direct_writer = std.Io.Writer.fixed(&direct_buffer);
    try completion.Runner.run(&direct_writer);

    var lowered = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = completion.case_id,
        .source_path = completion.source_path,
        .entry_symbol = completion.entry_symbol,
        .surface_kind = completion.surface_kind,
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

test "remaining source-lowering completion rows stay source-backed and canonical" {
    try expectCompletionCase(.{
        .case_id = "example.define_basic",
        .source_path = "examples/define_basic.zig",
        .surface_kind = .example,
        .scenario_id = .define_basic,
        .Runner = example_define_basic,
    });
    try expectCompletionCase(.{
        .case_id = "example.define_choice_basic",
        .source_path = "examples/define_choice_basic.zig",
        .surface_kind = .example,
        .scenario_id = .define_choice_basic,
        .Runner = example_define_choice_basic,
    });
    try expectCompletionCase(.{
        .case_id = "example.define_abort_basic",
        .source_path = "examples/define_abort_basic.zig",
        .surface_kind = .example,
        .scenario_id = .define_abort_basic,
        .Runner = example_define_abort_basic,
    });
    try expectCompletionCase(.{
        .case_id = "example.algebraic_abortive_validation",
        .source_path = "examples/algebraic_abortive_validation.zig",
        .surface_kind = .example,
        .scenario_id = .algebraic_abortive_validation,
        .Runner = example_algebraic_abortive_validation,
    });
    try expectCompletionCase(.{
        .case_id = "example.algebraic_artifact_search",
        .source_path = "examples/algebraic_artifact_search.zig",
        .surface_kind = .example,
        .scenario_id = .algebraic_artifact_search,
        .Runner = example_algebraic_artifact_search,
    });
    try expectCompletionCase(.{
        .case_id = "example.resource_basic",
        .source_path = "examples/resource_basic.zig",
        .surface_kind = .example,
        .scenario_id = .resource_basic,
        .Runner = example_resource_basic,
    });
    try expectCompletionCase(.{
        .case_id = "example.writer_basic",
        .source_path = "examples/writer_basic.zig",
        .surface_kind = .example,
        .scenario_id = .writer_basic,
        .Runner = example_writer_basic,
    });
    try expectCompletionCase(.{
        .case_id = "effect.resource_basic",
        .source_path = "examples/resource_basic.zig",
        .surface_kind = .effect,
        .scenario_id = .resource_basic,
        .Runner = example_resource_basic,
    });
    try expectCompletionCase(.{
        .case_id = "effect.writer_basic",
        .source_path = "examples/writer_basic.zig",
        .surface_kind = .effect,
        .scenario_id = .writer_basic,
        .Runner = example_writer_basic,
    });
    try expectCompletionCase(.{
        .case_id = "user_defined.transform",
        .source_path = "examples/define_basic.zig",
        .surface_kind = .user_defined_effect,
        .scenario_id = .define_basic,
        .Runner = example_define_basic,
    });
    try expectCompletionCase(.{
        .case_id = "user_defined.choice",
        .source_path = "examples/define_choice_basic.zig",
        .surface_kind = .user_defined_effect,
        .scenario_id = .define_choice_basic,
        .Runner = example_define_choice_basic,
    });
    try expectCompletionCase(.{
        .case_id = "user_defined.abort",
        .source_path = "examples/define_abort_basic.zig",
        .surface_kind = .user_defined_effect,
        .scenario_id = .define_abort_basic,
        .Runner = example_define_abort_basic,
    });
}
