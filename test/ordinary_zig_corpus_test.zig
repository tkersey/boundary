const lowered_machine = @import("lowered_machine");
const ordinary = @import("ordinary_zig_registry");
const ordinary_zig_lowering = @import("ordinary_zig_lowering");
const std = @import("std");

const branch_resume = @import("ordinary_fixture_branch_resume");
const cross_module_helper_chain_resume = @import("ordinary_fixture_cross_module_helper_chain_resume");
const cross_module_helper_resume = @import("ordinary_fixture_cross_module_helper_resume");
const cross_module_typed_error_try = @import("ordinary_fixture_cross_module_typed_error_try");
const defer_resume = @import("ordinary_fixture_defer_resume");
const errdefer_error = @import("ordinary_fixture_errdefer_error");
const helper_call_resume = @import("ordinary_fixture_helper_call_resume");
const local_mutation_resume = @import("ordinary_fixture_local_mutation_resume");
const loop_resume = @import("ordinary_fixture_loop_resume");
const nested_prompt_static_redelim = @import("ordinary_fixture_nested_prompt_static_redelim");
const typed_error_try = @import("ordinary_fixture_typed_error_try");

fn expectCase(comptime Fixture: type) !void {
    const case = ordinary.find(Fixture.ordinary_case_id).?;
    const lowered = try ordinary_zig_lowering.lowerFixture(Fixture);

    var source_buffer: [1024]u8 = undefined;
    var source_writer = std.Io.Writer.fixed(&source_buffer);
    try Fixture.run(&source_writer);

    var lowered_buffer: [1024]u8 = undefined;
    var lowered_writer = std.Io.Writer.fixed(&lowered_buffer);
    const lowered_state = lowered_machine.runSteps(lowered.scenario.steps);
    try lowered_machine.writeTranscript(&lowered_writer, &lowered_state);

    try std.testing.expectEqualStrings(lowered.scenario.expected_transcript, source_writer.buffered());
    try std.testing.expectEqualStrings(lowered.scenario.expected_transcript, lowered_writer.buffered());

    if (case.forbidden_transcript) |forbidden| {
        try std.testing.expect(!std.mem.eql(u8, forbidden, source_writer.buffered()));
        try std.testing.expect(!std.mem.eql(u8, forbidden, lowered_writer.buffered()));
    }
}

test "ordinary Zig corpus stays green across direct source fixtures and lowered scenarios" {
    try expectCase(local_mutation_resume);
    try expectCase(branch_resume);
    try expectCase(loop_resume);
    try expectCase(helper_call_resume);
    try expectCase(cross_module_helper_resume);
    try expectCase(cross_module_helper_chain_resume);
    try expectCase(nested_prompt_static_redelim);
    try expectCase(typed_error_try);
    try expectCase(cross_module_typed_error_try);
    try expectCase(defer_resume);
    try expectCase(errdefer_error);
}
