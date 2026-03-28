const bridge_manifest = @import("direct_style_bridge_manifest");
const early_exit = @import("direct_style_bridge_early_exit");
const exception_basic = @import("direct_style_bridge_exception_basic");
const nested_workflow = @import("direct_style_bridge_nested_workflow");
const open_row_abortive_validation = @import("direct_style_bridge_open_row_abortive_validation");
const open_row_artifact_search = @import("direct_style_bridge_open_row_artifact_search");
const open_row_generator = @import("direct_style_bridge_open_row_generator");
const optional_basic = @import("direct_style_bridge_optional_basic");
const private_lowered_runtime = @import("private_lowered_runtime");
const reader_basic = @import("direct_style_bridge_reader_basic");
const resource_basic = @import("direct_style_bridge_resource_basic");
const resume_or_return = @import("direct_style_bridge_resume_or_return");
const state_basic = @import("direct_style_bridge_state_basic");
const std = @import("std");
const writer_basic = @import("direct_style_bridge_writer_basic");

fn expectBridgeParity(comptime Fixture: type) !void {
    const case = bridge_manifest.find(Fixture.bridge_case_id).?;
    try std.testing.expect(case.status == .supported);
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

test "direct-style bridge lowers the supported unchanged-body corpus" {
    try expectBridgeParity(open_row_abortive_validation);
    try expectBridgeParity(open_row_artifact_search);
    try expectBridgeParity(early_exit);
    try expectBridgeParity(open_row_generator);
    try expectBridgeParity(resume_or_return);
    try expectBridgeParity(nested_workflow);
    try expectBridgeParity(state_basic);
    try expectBridgeParity(reader_basic);
    try expectBridgeParity(optional_basic);
    try expectBridgeParity(exception_basic);
    try expectBridgeParity(resource_basic);
    try expectBridgeParity(writer_basic);
}

test "private lowered runtime seam reports supported cases" {
    try std.testing.expect(private_lowered_runtime.supportsCaseId("nested_workflow"));
    try std.testing.expect(!private_lowered_runtime.supportsCaseId("missing_case"));
    var buffer: [1]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(error.UnsupportedBridgeCase, private_lowered_runtime.runCaseId(&writer, "missing_case"));
}
