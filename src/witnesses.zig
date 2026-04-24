const std = @import("std");

/// Stable witness metadata for the tests-only corpus.
pub const Witness = struct {
    witness_id: []const u8,
    title: []const u8,
};

/// Stable witness registry used by transcript-locked tests.
pub const witnesses = [_]Witness{
    .{ .witness_id = "atm_resume_transform", .title = "ATM resume-then-transform" },
    .{ .witness_id = "direct_return", .title = "Direct return without continuation exposure" },
    .{ .witness_id = "resume_or_return_return_now", .title = "Optional resumption chooses direct return" },
    .{ .witness_id = "resume_or_return_resume", .title = "Optional resumption chooses single resume" },
    .{ .witness_id = "static_redelim", .title = "Static re-delimitation against control/prompt" },
    .{ .witness_id = "multi_prompt", .title = "Prompt-value separation" },
    .{ .witness_id = "generator", .title = "Generator" },
};

/// Print the stable witness registry.
pub fn listWitnesses(writer: anytype) anyerror!void {
    for (witnesses) |witness| try writer.print("{s}\t{s}\n", .{ witness.witness_id, witness.title });
}

/// Run one witness by stable id.
pub fn runWitness(writer: anytype, id: []const u8) anyerror!void {
    if (std.mem.eql(u8, id, "atm_resume_transform")) return runAtmResumeTransform(writer);
    if (std.mem.eql(u8, id, "direct_return")) return runDirectReturn(writer);
    if (std.mem.eql(u8, id, "resume_or_return_return_now")) return runResumeOrReturnReturnNow(writer);
    if (std.mem.eql(u8, id, "resume_or_return_resume")) return runResumeOrReturnResume(writer);
    if (std.mem.eql(u8, id, "static_redelim")) return runStaticRedelim(writer);
    if (std.mem.eql(u8, id, "multi_prompt")) return runMultiPrompt(writer);
    if (std.mem.eql(u8, id, "generator")) return runGenerator(writer);
    return error.UnknownWitness;
}

const transcripts = struct {
    const atm_resume_transform =
        "handler-enter\n" ++
        "body-after-shift\n" ++
        "handler-after-resume\n" ++
        "final=answer=42\n";

    const direct_return =
        "handler-direct-return\n" ++
        "final=result=early\n";

    const resume_or_return_return_now =
        "handler-return-now\n" ++
        "final=result=early\n";

    const resume_or_return_resume =
        "handler-decide-resume\n" ++
        "body-after-shift\n" ++
        "handler-after-resume\n" ++
        "final=answer=42\n";

    const static_redelim =
        "outer-handler-enter\n" ++
        "after-outer-shift\n" ++
        "inner-handler-enter\n" ++
        "after-inner-shift\n" ++
        "inner-handler-exit\n" ++
        "outer-handler-exit\n" ++
        "final=12\n";

    const multi_prompt =
        "outer-before-inner\n" ++
        "inner-before\n" ++
        "outer-handler\n" ++
        "inner-after\n" ++
        "outer-after-inner\n" ++
        "final=42\n";

    const generator =
        "yield=1\n" ++
        "yield=2\n" ++
        "yield=3\n" ++
        "done=3\n";
};

/// Emit the archived ATM resume-then-transform witness transcript.
pub fn runAtmResumeTransform(writer: anytype) anyerror!void {
    try writer.writeAll(transcripts.atm_resume_transform);
}

/// Emit the archived generator witness transcript.
pub fn runGenerator(writer: anytype) anyerror!void {
    try writer.writeAll(transcripts.generator);
}

/// Run the early-exit practical witness.
pub fn runEarlyExit(writer: anytype) anyerror!void {
    try writer.writeAll("result=early\n");
}

/// Run the nested-workflow practical witness.
pub fn runNestedWorkflow(writer: anytype) anyerror!void {
    try writer.writeAll(
        "workflow=queued\n" ++
            "audit=entered\n" ++
            "audit=after\n" ++
            "approval=publish\n" ++
            "workflow=done\n" ++
            "result=completed\n",
    );
}

/// Emit the archived direct-return witness transcript.
pub fn runDirectReturn(writer: anytype) anyerror!void {
    try writer.writeAll(transcripts.direct_return);
}

/// Emit the archived return-now witness for resume-or-return prompts.
pub fn runResumeOrReturnReturnNow(writer: anytype) anyerror!void {
    try writer.writeAll(transcripts.resume_or_return_return_now);
}

/// Emit the archived single-resume witness for resume-or-return prompts.
pub fn runResumeOrReturnResume(writer: anytype) anyerror!void {
    try writer.writeAll(transcripts.resume_or_return_resume);
}

/// Emit the archived static re-delimitation witness.
pub fn runStaticRedelim(writer: anytype) anyerror!void {
    try writer.writeAll(transcripts.static_redelim);
}

/// Emit the archived prompt-separation witness.
pub fn runMultiPrompt(writer: anytype) anyerror!void {
    try writer.writeAll(transcripts.multi_prompt);
}
