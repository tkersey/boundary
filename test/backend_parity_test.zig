const algebraic_abortive_validation = @import("example_algebraic_abortive_validation");
const algebraic_artifact_search = @import("example_algebraic_artifact_search");
const backend_manifest = @import("backend_parity_manifest");
const early_exit = @import("example_early_exit");
const exception_basic = @import("example_exception_basic");
const generator = @import("example_generator");
const nested_workflow = @import("example_nested_workflow");
const optional_basic = @import("example_optional_basic");
const parity_kernel = @import("parity_kernel");
const parity_machine = @import("parity_machine");
const reader_basic = @import("example_reader_basic");
const resource_basic = @import("example_resource_basic");
const resume_or_return = @import("example_resume_or_return");
const resume_transform_smoke = @import("survey_resume_transform_executes");
const state_basic = @import("example_state_basic");
const std = @import("std");
const witnesses = @import("witnesses_src");
const writer_basic = @import("example_writer_basic");

fn stackfulTranscript(buffer: anytype, case_id: []const u8) ![]const u8 {
    var writer = std.Io.Writer.fixed(buffer);
    if (std.mem.eql(u8, case_id, "atm_resume_transform")) {
        try witnesses.runWitness(&writer, case_id);
    } else if (std.mem.eql(u8, case_id, "direct_return")) {
        try witnesses.runWitness(&writer, case_id);
    } else if (std.mem.eql(u8, case_id, "resume_or_return_return_now")) {
        try witnesses.runWitness(&writer, case_id);
    } else if (std.mem.eql(u8, case_id, "resume_or_return_resume")) {
        try witnesses.runWitness(&writer, case_id);
    } else if (std.mem.eql(u8, case_id, "static_redelim")) {
        try witnesses.runWitness(&writer, case_id);
    } else if (std.mem.eql(u8, case_id, "multi_prompt")) {
        try witnesses.runWitness(&writer, case_id);
    } else if (std.mem.eql(u8, case_id, "generator")) {
        try generator.run(&writer);
    } else if (std.mem.eql(u8, case_id, "early_exit")) {
        try early_exit.run(&writer);
    } else if (std.mem.eql(u8, case_id, "resume_or_return")) {
        try resume_or_return.run(&writer);
    } else if (std.mem.eql(u8, case_id, "nested_workflow")) {
        try nested_workflow.run(&writer);
    } else if (std.mem.eql(u8, case_id, "reader_basic")) {
        try reader_basic.run(&writer);
    } else if (std.mem.eql(u8, case_id, "exception_basic")) {
        try exception_basic.run(&writer);
    } else if (std.mem.eql(u8, case_id, "optional_basic")) {
        try optional_basic.run(&writer);
    } else if (std.mem.eql(u8, case_id, "resource_basic")) {
        try resource_basic.run(&writer);
    } else if (std.mem.eql(u8, case_id, "writer_basic")) {
        try writer_basic.run(&writer);
    } else if (std.mem.eql(u8, case_id, "state_basic")) {
        try state_basic.run(&writer);
    } else if (std.mem.eql(u8, case_id, "algebraic_abortive_validation")) {
        try algebraic_abortive_validation.run(&writer);
    } else if (std.mem.eql(u8, case_id, "algebraic_artifact_search")) {
        try algebraic_artifact_search.run(&writer);
    } else {
        return error.UnknownParityCase;
    }
    return writer.buffered();
}

fn parityTranscript(buffer: anytype, case_id: []const u8) ![]const u8 {
    var writer = std.Io.Writer.fixed(buffer);
    try parity_machine.runCase(&writer, case_id);
    return writer.buffered();
}

fn expectStateTrace(case_id: []const u8, expected: []const backend_manifest.TraceCheckpoint) !void {
    const state = try parity_kernel.runCaseId(case_id);
    const actual = parity_kernel.checkpoints(&state);
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |expected_checkpoint, actual_checkpoint| {
        try std.testing.expect(std.meta.eql(expected_checkpoint, actual_checkpoint));
    }
}

test "backend parity transcripts stay locked across stackful runtime and parity machine" {
    for (backend_manifest.transcript_cases) |case| {
        var stackful_buffer: [4096]u8 = undefined;
        const stackful = try stackfulTranscript(&stackful_buffer, case.case_id);

        var parity_buffer: [4096]u8 = undefined;
        const parity = try parityTranscript(&parity_buffer, case.case_id);

        try std.testing.expectEqualStrings(case.expected, stackful);
        try std.testing.expectEqualStrings(case.expected, parity);
        if (case.state_trace_expected.len != 0) {
            try expectStateTrace(case.case_id, case.state_trace_expected);
        }
    }
}

test "runtime-positive survey parity cases succeed" {
    for (backend_manifest.runtime_cases) |case| {
        if (std.mem.eql(u8, case.case_id, "protocol_resume_transform_runtime")) {
            try resume_transform_smoke.main();
            try parity_machine.runRuntimeCase(case.case_id);
        } else {
            return error.UnknownParityCase;
        }
    }
}
