const bridge_manifest = @import("direct_style_bridge_manifest");
const early_exit = @import("direct_style_bridge_early_exit");
const exception_basic = @import("direct_style_bridge_exception_basic");
const nested_workflow = @import("direct_style_bridge_nested_workflow");
const open_row_abortive_validation = @import("direct_style_bridge_open_row_abortive_validation");
const open_row_artifact_search = @import("direct_style_bridge_open_row_artifact_search");
const open_row_generator = @import("direct_style_bridge_open_row_generator");
const optional_basic = @import("direct_style_bridge_optional_basic");
const private_lowered_runtime = @import("private_lowered_runtime");
const program_bridge = @import("program_bridge");
const reader_basic = @import("direct_style_bridge_reader_basic");
const resource_basic = @import("direct_style_bridge_resource_basic");
const resume_or_return = @import("direct_style_bridge_resume_or_return");
const state_basic = @import("direct_style_bridge_state_basic");
const std = @import("std");
const writer_basic = @import("direct_style_bridge_writer_basic");

fn expectInternalFixtureParity(comptime Fixture: type) !void {
    const case = bridge_manifest.find(Fixture.bridge_case_id).?;
    try std.testing.expect(case.status == .supported);

    var lowered = try program_bridge.lowerFixture(std.testing.allocator, Fixture);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.status == .canonical);
    try std.testing.expect(lowered.surface_kind == .bridge);
    try std.testing.expectEqual(case.scenario_id, lowered.canonical_scenario_id.?);
    try std.testing.expectEqualStrings(case.fixture_module, lowered.source_path);
    try std.testing.expectEqualStrings(case.label, lowered.label);
    try std.testing.expect(std.mem.startsWith(u8, case.fixture_module, "test/direct_style_bridge/"));

    var stackful_buffer: [1024]u8 = undefined;
    var stackful_writer = std.Io.Writer.fixed(&stackful_buffer);
    try Fixture.run(&stackful_writer);

    var lowered_buffer: [1024]u8 = undefined;
    var lowered_writer = std.Io.Writer.fixed(&lowered_buffer);
    const execution = try private_lowered_runtime.runBridgeFixture(Fixture, &lowered_writer);

    try std.testing.expectEqualStrings(case.label, execution.label);
    try std.testing.expectEqualStrings(case.case_id, execution.scenario.case_id);
    try std.testing.expectEqualStrings(stackful_writer.buffered(), lowered_writer.buffered());
}

test "internal proof fixtures still lower through the private seam" {
    try expectInternalFixtureParity(open_row_abortive_validation);
    try expectInternalFixtureParity(open_row_artifact_search);
    try expectInternalFixtureParity(early_exit);
    try expectInternalFixtureParity(open_row_generator);
    try expectInternalFixtureParity(resume_or_return);
    try expectInternalFixtureParity(nested_workflow);
    try expectInternalFixtureParity(state_basic);
    try expectInternalFixtureParity(reader_basic);
    try expectInternalFixtureParity(optional_basic);
    try expectInternalFixtureParity(exception_basic);
    try expectInternalFixtureParity(resource_basic);
    try expectInternalFixtureParity(writer_basic);
}

test "private lowered runtime seam reports supported internal fixture case ids" {
    try std.testing.expect(private_lowered_runtime.supportsCaseId("nested_workflow"));
    try std.testing.expect(!private_lowered_runtime.supportsCaseId("missing_case"));
    var buffer: [1]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(error.UnsupportedBridgeCase, private_lowered_runtime.runCaseId(&writer, "missing_case"));
}
