const bridge_manifest = @import("direct_style_bridge_manifest");
const lexical_witness_runners = @import("lexical_witness_runners");
const private_lowered_runtime = @import("private_lowered_runtime");
const std = @import("std");

const WitnessCase = struct {
    case_id: []const u8,
    Runner: type,
};

const AtmRunner = struct {
    pub fn run(writer: anytype) !void {
        try lexical_witness_runners.runAtmResumeTransform(writer);
    }
};

const DirectReturnRunner = struct {
    pub fn run(writer: anytype) !void {
        try lexical_witness_runners.runDirectReturn(writer);
    }
};

const MultiPromptRunner = struct {
    pub fn run(writer: anytype) !void {
        try lexical_witness_runners.runMultiPrompt(writer);
    }
};

const ResumeRunner = struct {
    pub fn run(writer: anytype) !void {
        try lexical_witness_runners.runResumeOrReturnResume(writer);
    }
};

const ReturnNowRunner = struct {
    pub fn run(writer: anytype) !void {
        try lexical_witness_runners.runResumeOrReturnReturnNow(writer);
    }
};

const StaticRedelimRunner = struct {
    pub fn run(writer: anytype) !void {
        try lexical_witness_runners.runStaticRedelim(writer);
    }
};

fn expectWitnessBridgeParity(comptime witness: WitnessCase) !void {
    const case = bridge_manifest.find(witness.case_id).?;
    try std.testing.expect(case.status == .supported);

    var stackful_buffer: [1024]u8 = undefined;
    var stackful_writer = std.Io.Writer.fixed(&stackful_buffer);
    try witness.Runner.run(&stackful_writer);

    var lowered_buffer: [1024]u8 = undefined;
    var lowered_writer = std.Io.Writer.fixed(&lowered_buffer);
    const execution = try private_lowered_runtime.runCaseId(&lowered_writer, witness.case_id);

    try std.testing.expectEqualStrings(case.label, execution.label);
    try std.testing.expectEqualStrings(case.case_id, execution.scenario.case_id);
    try std.testing.expectEqualStrings(stackful_writer.buffered(), lowered_writer.buffered());
}

test "direct-style bridge witness cases still match the lexical witness runners" {
    try expectWitnessBridgeParity(.{ .case_id = "atm_resume_transform", .Runner = AtmRunner });
    try expectWitnessBridgeParity(.{ .case_id = "direct_return", .Runner = DirectReturnRunner });
    try expectWitnessBridgeParity(.{ .case_id = "multi_prompt", .Runner = MultiPromptRunner });
    try expectWitnessBridgeParity(.{ .case_id = "resume_or_return_resume", .Runner = ResumeRunner });
    try expectWitnessBridgeParity(.{ .case_id = "resume_or_return_return_now", .Runner = ReturnNowRunner });
    try expectWitnessBridgeParity(.{ .case_id = "static_redelim", .Runner = StaticRedelimRunner });
}
