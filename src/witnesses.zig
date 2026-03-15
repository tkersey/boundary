const lowered_runtime = @import("private_lowered_runtime");
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

fn runLowered(writer: anytype, case_id: []const u8) anyerror!void {
    _ = try lowered_runtime.runCaseId(writer, case_id);
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

/// Run the ATM resume-then-transform witness.
pub fn runAtmResumeTransform(writer: anytype) anyerror!void {
    try runLowered(writer, "atm_resume_transform");
}

/// Run the generator witness.
pub fn runGenerator(writer: anytype) anyerror!void {
    try runLowered(writer, "generator");
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

/// Run the direct-return witness.
pub fn runDirectReturn(writer: anytype) anyerror!void {
    try runLowered(writer, "direct_return");
}

/// Run the return-now witness for resume-or-return prompts.
pub fn runResumeOrReturnReturnNow(writer: anytype) anyerror!void {
    try runLowered(writer, "resume_or_return_return_now");
}

/// Run the single-resume witness for resume-or-return prompts.
pub fn runResumeOrReturnResume(writer: anytype) anyerror!void {
    try runLowered(writer, "resume_or_return_resume");
}

/// Run the static re-delimitation witness.
pub fn runStaticRedelim(writer: anytype) anyerror!void {
    try runLowered(writer, "static_redelim");
}

/// Run the prompt-separation witness.
pub fn runMultiPrompt(writer: anytype) anyerror!void {
    try runLowered(writer, "multi_prompt");
}
