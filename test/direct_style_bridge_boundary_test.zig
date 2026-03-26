const bridge_manifest = @import("direct_style_bridge_manifest");
const early_exit = @import("direct_style_bridge_early_exit");
const private_lowered_runtime = @import("private_lowered_runtime");
const program_bridge = @import("program_bridge");
const std = @import("std");
const witness_admission = @import("witness_admission_registry");

test "direct-style bridge manifest stays aligned with witness admission truth" {
    for (witness_admission.entries) |entry| {
        const case = bridge_manifest.find(entry.witness_id).?;
        const expected_supported = entry.bridge_status == .supported;
        try std.testing.expectEqual(expected_supported, case.status == .supported);
        if (!expected_supported) {
            try std.testing.expect(case.blocked_reason != null);
        }
    }
}

test "blocked bridge witness cases fail closed through the lowered seam" {
    for (bridge_manifest.cases) |case| {
        if (case.status != .blocked) continue;
        try std.testing.expect(case.blocked_reason != null);
        var buffer: [1]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        try std.testing.expectError(error.UnsupportedBridgeCase, private_lowered_runtime.runCaseId(&writer, case.case_id));
    }
}

test "bridge fixtures still execute when callers chdir outside the repo root" {
    const original_cwd = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(original_cwd);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);

    try std.posix.chdir(tmp_path);
    defer std.posix.chdir(original_cwd) catch unreachable;

    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const execution = try private_lowered_runtime.runBridgeFixture(early_exit, &writer);
    try std.testing.expectEqualStrings("bridge.early_exit", execution.label);
    try std.testing.expectEqualStrings("early_exit", execution.scenario.case_id);
}

test "bridge case ids still execute through the lowered runtime seam" {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const execution = try private_lowered_runtime.runCaseId(&writer, "early_exit");
    try std.testing.expectEqualStrings("bridge.early_exit", execution.label);
    try std.testing.expectEqualStrings("early_exit", execution.scenario.case_id);
}

test "bridge case-id admission rejects drifted canonical sources" {
    const drifted =
        \\const shift = @import("shift");
        \\
        \\pub const bridge_case_id = "early_exit";
        \\
        \\pub fn run(writer: anytype) !void {
        \\    _ = shift;
        \\    try writer.writeAll("status=late\\n");
        \\}
    ;

    var lowered = try program_bridge.inspectCaseIdSourceText(std.testing.allocator, "early_exit", drifted);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.status == .rejected);
    try std.testing.expectEqualStrings("structural_mismatch", lowered.diagnostics[0].code);
    try std.testing.expect(lowered.diagnostics[0].line > 1);
}

test "bridge witness case-id admission rejects drifted wrapper sources" {
    const drifted =
        \\const sources = @import("witness_sources.zig");
        \\const std = @import("std");
        \\
        \\/// Stable witness metadata for the tests-only corpus.
        \\pub const Witness = struct {
        \\    witness_id: []const u8,
        \\    title: []const u8,
        \\};
        \\
        \\/// Stable witness registry used by transcript-locked tests.
        \\pub const witnesses = [_]Witness{
        \\    .{ .witness_id = "atm_resume_transform", .title = "ATM resume-then-transform" },
        \\    .{ .witness_id = "direct_return", .title = "Direct return without continuation exposure" },
        \\    .{ .witness_id = "resume_or_return_return_now", .title = "Optional resumption chooses direct return" },
        \\    .{ .witness_id = "resume_or_return_resume", .title = "Optional resumption chooses single resume" },
        \\    .{ .witness_id = "static_redelim", .title = "Static re-delimitation against control/prompt" },
        \\    .{ .witness_id = "multi_prompt", .title = "Prompt-value separation" },
        \\    .{ .witness_id = "generator", .title = "Generator" },
        \\};
        \\
        \\/// Print the stable witness registry.
        \\pub fn listWitnesses(writer: anytype) anyerror!void {
        \\    for (witnesses) |witness| try writer.print("{s}\t{s}\n", .{ witness.witness_id, witness.title });
        \\}
        \\
        \\/// Run one witness by stable id.
        \\pub fn runWitness(writer: anytype, id: []const u8) anyerror!void {
        \\    if (std.mem.eql(u8, id, "atm_resume_transform")) return runDirectReturn(writer);
        \\    if (std.mem.eql(u8, id, "direct_return")) return runDirectReturn(writer);
        \\    if (std.mem.eql(u8, id, "resume_or_return_return_now")) return runResumeOrReturnReturnNow(writer);
        \\    if (std.mem.eql(u8, id, "resume_or_return_resume")) return runResumeOrReturnResume(writer);
        \\    if (std.mem.eql(u8, id, "static_redelim")) return runStaticRedelim(writer);
        \\    if (std.mem.eql(u8, id, "multi_prompt")) return runMultiPrompt(writer);
        \\    if (std.mem.eql(u8, id, "generator")) return runGenerator(writer);
        \\    return error.UnknownWitness;
        \\}
        \\
        \\/// Run the ATM resume-then-transform witness.
        \\pub fn runAtmResumeTransform(writer: anytype) anyerror!void {
        \\    try sources.runDirectReturn(writer);
        \\}
        \\
        \\/// Run the generator witness.
        \\pub fn runGenerator(writer: anytype) anyerror!void {
        \\    try sources.runGenerator(writer);
        \\}
        \\
        \\/// Run the early-exit practical witness.
        \\pub fn runEarlyExit(writer: anytype) anyerror!void {
        \\    try writer.writeAll("result=early\n");
        \\}
        \\
        \\/// Run the nested-workflow practical witness.
        \\pub fn runNestedWorkflow(writer: anytype) anyerror!void {
        \\    try writer.writeAll(
        \\        "workflow=queued\n" ++
        \\            "audit=entered\n" ++
        \\            "audit=after\n" ++
        \\            "approval=publish\n" ++
        \\            "workflow=done\n" ++
        \\            "result=completed\n",
        \\    );
        \\}
        \\
        \\/// Run the direct-return witness.
        \\pub fn runDirectReturn(writer: anytype) anyerror!void {
        \\    try sources.runDirectReturn(writer);
        \\}
        \\
        \\/// Run the return-now witness for resume-or-return prompts.
        \\pub fn runResumeOrReturnReturnNow(writer: anytype) anyerror!void {
        \\    try sources.runResumeOrReturnReturnNow(writer);
        \\}
        \\
        \\/// Run the single-resume witness for resume-or-return prompts.
        \\pub fn runResumeOrReturnResume(writer: anytype) anyerror!void {
        \\    try sources.runResumeOrReturnResume(writer);
        \\}
        \\
        \\/// Run the static re-delimitation witness.
        \\pub fn runStaticRedelim(writer: anytype) anyerror!void {
        \\    try sources.runStaticRedelim(writer);
        \\}
        \\
        \\/// Run the prompt-separation witness.
        \\pub fn runMultiPrompt(writer: anytype) anyerror!void {
        \\    try sources.runMultiPrompt(writer);
        \\}
    ;

    var lowered = try program_bridge.inspectCaseIdSourceText(std.testing.allocator, "atm_resume_transform", drifted);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.status == .rejected);
    try std.testing.expectEqualStrings("structural_mismatch", lowered.diagnostics[0].code);
    try std.testing.expect(lowered.diagnostics[0].line > 1);
}

test "bridge witness case-id admission rejects drifted runWitness dispatch" {
    const witness_wrapper_text = try std.fs.cwd().readFileAlloc(std.testing.allocator, "src/witnesses.zig", 1 << 20);
    defer std.testing.allocator.free(witness_wrapper_text);

    const drifted = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        witness_wrapper_text,
        "if (std.mem.eql(u8, id, \"atm_resume_transform\")) return runAtmResumeTransform(writer);",
        "if (std.mem.eql(u8, id, \"atm_resume_transform\")) return runDirectReturn(writer);",
    );
    defer std.testing.allocator.free(drifted);

    var lowered = try program_bridge.inspectCaseIdSourceText(std.testing.allocator, "atm_resume_transform", drifted);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.status == .rejected);
    try std.testing.expectEqualStrings("structural_mismatch", lowered.diagnostics[0].code);
    try std.testing.expect(lowered.diagnostics[0].line > 1);
}

test "private lowered runtime stays stable when bridge admission rejects injected drift" {
    const drifted =
        \\const shift = @import("shift");
        \\
        \\const EarlyExitProgram = shift.Program(.{
        \\    .exception = shift.Decl.exception([]const u8, struct {
        \\        pub fn directReturn(payload: []const u8) []const u8 {
        \\            return payload;
        \\        }
        \\    }),
        \\}, struct {
        \\    pub fn body(eff: anytype) anyerror![]const u8 {
        \\        try eff.exception.throw("result=late");
        \\    }
        \\});
        \\
        \\pub const bridge_case_id = "early_exit";
        \\
        \\pub fn run(writer: anytype) anyerror!void {
        \\    var runtime = shift.Runtime.init(std.heap.page_allocator);
        \\    defer runtime.deinit();
        \\    const result = try shift.run(&runtime, EarlyExitProgram, .{});
        \\    try writer.print("final={s}\\n", .{result.value});
        \\}
    ;

    var lowered = try program_bridge.inspectCaseIdSourceText(std.testing.allocator, "early_exit", drifted);
    defer lowered.deinit(std.testing.allocator);
    try std.testing.expect(lowered.status == .rejected);
    try std.testing.expectEqualStrings("structural_mismatch", lowered.diagnostics[0].code);
    try std.testing.expect(lowered.diagnostics[0].line > 1);

    try std.testing.expect(private_lowered_runtime.supportsCaseId("early_exit"));

    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const execution = try private_lowered_runtime.runCaseId(&writer, "early_exit");
    try std.testing.expectEqualStrings("bridge.early_exit", execution.label);
    try std.testing.expectEqualStrings("early_exit", execution.scenario.case_id);
}
