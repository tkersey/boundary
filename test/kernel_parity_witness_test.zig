const backend_manifest = @import("backend_parity_manifest");
const parity_kernel = @import("parity_kernel");
const parity_machine = @import("parity_machine");
const std = @import("std");
const witnesses = @import("witnesses_src");

fn isWitnessCase(case_id: []const u8) bool {
    return std.mem.eql(u8, case_id, "atm_resume_transform") or
        std.mem.eql(u8, case_id, "direct_return") or
        std.mem.eql(u8, case_id, "resume_or_return_return_now") or
        std.mem.eql(u8, case_id, "resume_or_return_resume") or
        std.mem.eql(u8, case_id, "static_redelim") or
        std.mem.eql(u8, case_id, "multi_prompt");
}

fn stackfulTranscript(buffer: anytype, case_id: []const u8) ![]const u8 {
    var writer = std.Io.Writer.fixed(buffer);
    try witnesses.runWitness(&writer, case_id);
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

test "kernel parity keeps lexical witness transcripts locked" {
    for (backend_manifest.transcript_cases) |case| {
        if (!isWitnessCase(case.case_id)) continue;

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
