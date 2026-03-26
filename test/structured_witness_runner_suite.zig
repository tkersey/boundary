const lexical_witness_runners = @import("lexical_witness_runners");
const parity_kernel = @import("parity_kernel");
const program_frontend = @import("program_frontend");
const std = @import("std");

const WitnessCase = struct {
    case_id: []const u8,
    program: program_frontend.Program,
    Runner: type,
};

const atm_runner = struct {
    /// Run this public entrypoint.
    pub fn run(writer: anytype) !void {
        try lexical_witness_runners.runAtmResumeTransform(writer);
    }
};

const direct_return_runner = struct {
    /// Run this public entrypoint.
    pub fn run(writer: anytype) !void {
        try lexical_witness_runners.runDirectReturn(writer);
    }
};

const multi_prompt_runner = struct {
    /// Run this public entrypoint.
    pub fn run(writer: anytype) !void {
        try lexical_witness_runners.runMultiPrompt(writer);
    }
};

const resume_runner = struct {
    /// Run this public entrypoint.
    pub fn run(writer: anytype) !void {
        try lexical_witness_runners.runResumeOrReturnResume(writer);
    }
};

const return_now_runner = struct {
    /// Run this public entrypoint.
    pub fn run(writer: anytype) !void {
        try lexical_witness_runners.runResumeOrReturnReturnNow(writer);
    }
};

const static_redelim_runner = struct {
    /// Run this public entrypoint.
    pub fn run(writer: anytype) !void {
        try lexical_witness_runners.runStaticRedelim(writer);
    }
};

fn expectWitnessCase(comptime witness: WitnessCase) !void {
    const lowered = program_frontend.lower(witness.program);

    var kernel_buffer: [1024]u8 = undefined;
    var kernel_writer = std.Io.Writer.fixed(&kernel_buffer);
    const state = parity_kernel.runScenario(lowered.scenario.scenario_id);
    try parity_kernel.writeTranscript(&kernel_writer, &state);
    try std.testing.expectEqualStrings(lowered.scenario.expected_transcript, kernel_writer.buffered());

    var stackful_buffer: [1024]u8 = undefined;
    var stackful_writer = std.Io.Writer.fixed(&stackful_buffer);
    try witness.Runner.run(&stackful_writer);

    try std.testing.expectEqualStrings(lowered.scenario.case_id, witness.case_id);
    try std.testing.expectEqualStrings(lowered.scenario.expected_transcript, stackful_writer.buffered());
}

test "structured witness programs still match the canonical lexical witness runners" {
    try expectWitnessCase(.{
        .case_id = "atm_resume_transform",
        .program = program_frontend.witnesses.atmResumeTransform(),
        .Runner = atm_runner,
    });
    try expectWitnessCase(.{
        .case_id = "direct_return",
        .program = program_frontend.witnesses.directReturn(),
        .Runner = direct_return_runner,
    });
    try expectWitnessCase(.{
        .case_id = "multi_prompt",
        .program = program_frontend.witnesses.multiPrompt(),
        .Runner = multi_prompt_runner,
    });
    try expectWitnessCase(.{
        .case_id = "resume_or_return_resume",
        .program = program_frontend.witnesses.resumeOrReturnResume(),
        .Runner = resume_runner,
    });
    try expectWitnessCase(.{
        .case_id = "resume_or_return_return_now",
        .program = program_frontend.witnesses.resumeOrReturnReturnNow(),
        .Runner = return_now_runner,
    });
    try expectWitnessCase(.{
        .case_id = "static_redelim",
        .program = program_frontend.witnesses.staticRedelim(),
        .Runner = static_redelim_runner,
    });
}
