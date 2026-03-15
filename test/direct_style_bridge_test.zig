const atm = @import("direct_style_bridge_atm");
const direct_return = @import("direct_style_bridge_direct_return");
const early_exit = @import("direct_style_bridge_early_exit");
const exception_basic = @import("direct_style_bridge_exception_basic");
const multi_prompt = @import("direct_style_bridge_multi_prompt");
const optional_basic = @import("direct_style_bridge_optional_basic");
const parity_kernel = @import("parity_kernel");
const program_bridge = @import("program_bridge");
const reader_basic = @import("direct_style_bridge_reader_basic");
const resume_or_return = @import("direct_style_bridge_resume_or_return");
const resume_or_return_resume = @import("direct_style_bridge_resume_or_return_resume");
const resume_or_return_return_now = @import("direct_style_bridge_resume_or_return_return_now");
const state_basic = @import("direct_style_bridge_state_basic");
const static_redelim = @import("direct_style_bridge_static_redelim");
const std = @import("std");

fn parityTranscript(buffer: anytype, lowered: anytype) ![]const u8 {
    var writer = std.Io.Writer.fixed(buffer);
    const state = parity_kernel.runScenario(lowered.scenario.scenario_id);
    try parity_kernel.writeTranscript(&writer, &state);
    return writer.buffered();
}

fn expectBridgeParity(comptime Fixture: type, expected_label: []const u8) !void {
    const lowered = try program_bridge.lowerFixture(Fixture);
    var stackful_buffer: [1024]u8 = undefined;
    var stackful_writer = std.Io.Writer.fixed(&stackful_buffer);
    try Fixture.run(&stackful_writer);

    var parity_buffer: [1024]u8 = undefined;
    const parity = try parityTranscript(&parity_buffer, lowered);

    try std.testing.expectEqualStrings(expected_label, lowered.label);
    try std.testing.expectEqualStrings(stackful_writer.buffered(), parity);
}

test "direct-style bridge lowers the supported unchanged-body corpus" {
    try expectBridgeParity(atm, "bridge.atm_resume_transform");
    try expectBridgeParity(direct_return, "bridge.direct_return");
    try expectBridgeParity(multi_prompt, "bridge.multi_prompt");
    try expectBridgeParity(resume_or_return_resume, "bridge.resume_or_return_resume");
    try expectBridgeParity(resume_or_return_return_now, "bridge.resume_or_return_return_now");
    try expectBridgeParity(static_redelim, "bridge.static_redelim");
    try expectBridgeParity(early_exit, "bridge.early_exit");
    try expectBridgeParity(resume_or_return, "bridge.resume_or_return");
    try expectBridgeParity(state_basic, "bridge.state_basic");
    try expectBridgeParity(reader_basic, "bridge.reader_basic");
    try expectBridgeParity(optional_basic, "bridge.optional_basic");
    try expectBridgeParity(exception_basic, "bridge.exception_basic");
}
