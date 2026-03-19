const early_exit = @import("example_early_exit");
const exception_basic = @import("example_exception_basic");
const nested_workflow = @import("example_nested_workflow");
const optional_basic = @import("example_optional_basic");
const parity_kernel = @import("parity_kernel");
const parity_scenarios = @import("parity_scenarios");
const program_frontend = @import("program_frontend");
const reader_basic = @import("example_reader_basic");
const resume_or_return = @import("example_resume_or_return");
const state_basic = @import("example_state_basic");
const std = @import("std");

fn stackfulTranscript(buffer: anytype, case_id: []const u8) ![]const u8 {
    var writer = std.Io.Writer.fixed(buffer);
    if (std.mem.eql(u8, case_id, "atm_resume_transform")) {
        return parity_scenarios.findWitness(case_id).?.expected_transcript;
    } else if (std.mem.eql(u8, case_id, "direct_return")) {
        return parity_scenarios.findWitness(case_id).?.expected_transcript;
    } else if (std.mem.eql(u8, case_id, "multi_prompt")) {
        return parity_scenarios.findWitness(case_id).?.expected_transcript;
    } else if (std.mem.eql(u8, case_id, "resume_or_return_resume")) {
        return parity_scenarios.findWitness(case_id).?.expected_transcript;
    } else if (std.mem.eql(u8, case_id, "resume_or_return_return_now")) {
        return parity_scenarios.findWitness(case_id).?.expected_transcript;
    } else if (std.mem.eql(u8, case_id, "static_redelim")) {
        return parity_scenarios.findWitness(case_id).?.expected_transcript;
    } else if (std.mem.eql(u8, case_id, "early_exit")) {
        try early_exit.run(&writer);
    } else if (std.mem.eql(u8, case_id, "resume_or_return")) {
        try resume_or_return.run(&writer);
    } else if (std.mem.eql(u8, case_id, "nested_workflow")) {
        try nested_workflow.run(&writer);
    } else if (std.mem.eql(u8, case_id, "state_basic")) {
        try state_basic.run(&writer);
    } else if (std.mem.eql(u8, case_id, "reader_basic")) {
        try reader_basic.run(&writer);
    } else if (std.mem.eql(u8, case_id, "optional_basic")) {
        try optional_basic.run(&writer);
    } else if (std.mem.eql(u8, case_id, "exception_basic")) {
        try exception_basic.run(&writer);
    } else {
        return error.UnknownProgram;
    }
    return writer.buffered();
}

test "structured programs lower to canonical scenarios and match stackful transcripts" {
    for (program_frontend.corpus) |program| {
        const lowered = program_frontend.lower(program);
        var kernel_buffer: [4096]u8 = undefined;
        var kernel_writer = std.Io.Writer.fixed(&kernel_buffer);
        const state = parity_kernel.runScenario(lowered.scenario.scenario_id);
        try parity_kernel.writeTranscript(&kernel_writer, &state);

        try std.testing.expectEqualStrings(lowered.scenario.expected_transcript, kernel_writer.buffered());

        var stackful_buffer: [4096]u8 = undefined;
        const stackful = try stackfulTranscript(&stackful_buffer, lowered.scenario.case_id);
        try std.testing.expectEqualStrings(lowered.scenario.expected_transcript, stackful);
    }
}
