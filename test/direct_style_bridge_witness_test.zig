const bridge_manifest = @import("direct_style_bridge_manifest");
const lexical_witness_runners = @import("lexical_witness_runners");
const private_lowered_runtime = @import("private_lowered_runtime");
const std = @import("std");

const WitnessCase = struct {
    case_id: []const u8,
    Runner: type,
};

const atm_runner = struct {
    /// Run this public entrypoint.
    pub fn run(writer: anytype) anyerror!void {
        try lexical_witness_runners.runAtmResumeTransform(writer);
    }
};

const direct_return_runner = struct {
    /// Run this public entrypoint.
    pub fn run(writer: anytype) anyerror!void {
        try lexical_witness_runners.runDirectReturn(writer);
    }
};

const multi_prompt_runner = struct {
    /// Run this public entrypoint.
    pub fn run(writer: anytype) anyerror!void {
        try lexical_witness_runners.runMultiPrompt(writer);
    }
};

const resume_runner = struct {
    /// Run this public entrypoint.
    pub fn run(writer: anytype) anyerror!void {
        try lexical_witness_runners.runResumeOrReturnResume(writer);
    }
};

const return_now_runner = struct {
    /// Run this public entrypoint.
    pub fn run(writer: anytype) anyerror!void {
        try lexical_witness_runners.runResumeOrReturnReturnNow(writer);
    }
};

const static_redelim_runner = struct {
    /// Run this public entrypoint.
    pub fn run(writer: anytype) anyerror!void {
        try lexical_witness_runners.runStaticRedelim(writer);
    }
};

fn expectWitnessBridgeParity(comptime witness: WitnessCase) anyerror!void {
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
    try expectWitnessBridgeParity(.{ .case_id = "atm_resume_transform", .Runner = atm_runner });
    try expectWitnessBridgeParity(.{ .case_id = "direct_return", .Runner = direct_return_runner });
    try expectWitnessBridgeParity(.{ .case_id = "multi_prompt", .Runner = multi_prompt_runner });
    try expectWitnessBridgeParity(.{ .case_id = "resume_or_return_resume", .Runner = resume_runner });
    try expectWitnessBridgeParity(.{ .case_id = "resume_or_return_return_now", .Runner = return_now_runner });
    try expectWitnessBridgeParity(.{ .case_id = "static_redelim", .Runner = static_redelim_runner });
}
