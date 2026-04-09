const bridge_manifest = @import("direct_style_bridge_manifest");
const early_exit = @import("direct_style_bridge_early_exit");
const private_lowered_runtime = @import("private_lowered_runtime");
const program_bridge = @import("program_bridge");
const std = @import("std");
const witness_admission = @import("witness_admission_registry");

test "direct-style bridge manifest stays aligned with witness admission truth" {
    for (witness_admission.entries) |entry| {
        const case = bridge_manifest.findWitnessCase(entry.witness_id).?;
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

test "bridge witness case-id lowering reports canonical witness sources" {
    var lowered = try program_bridge.lowerCaseId(std.testing.allocator, "atm_resume_transform");
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.status == .canonical);
    try std.testing.expectEqualStrings("src/witness_sources.zig", lowered.source_path);
    try std.testing.expectEqualStrings("witness", lowered.feature_flags[0]);
    try std.testing.expectEqualStrings("transform", lowered.feature_flags[1]);
}

test "bridge example case-id lowering preserves feature flags" {
    var lowered = try program_bridge.lowerCaseId(std.testing.allocator, "early_exit");
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.status == .canonical);
    try std.testing.expectEqualStrings("lexical_exception", lowered.feature_flags[0]);
    try std.testing.expectEqualStrings("direct_return", lowered.feature_flags[1]);
    try std.testing.expectEqualStrings("promoted_example", lowered.feature_flags[2]);
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
    try std.testing.expect(lowered.diagnostics[0].line >= 1);
}

test "bridge witness case-id admission rejects drifted canonical witness helpers" {
    const witness_source_text = try std.fs.cwd().readFileAlloc(std.testing.allocator, "src/witness_sources.zig", 1 << 20);
    defer std.testing.allocator.free(witness_source_text);

    const drifted = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        witness_source_text,
        "writer.print(\"{s}\\n\", .{line})",
        "writer.print(\"[{s}]\\n\", .{line})",
    );
    defer std.testing.allocator.free(drifted);

    var lowered = try program_bridge.inspectCaseIdSourceText(std.testing.allocator, "atm_resume_transform", drifted);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.status == .rejected);
    try std.testing.expectEqualStrings("structural_mismatch", lowered.diagnostics[0].code);
    try std.testing.expect(lowered.diagnostics[0].line >= 1);
}

test "private lowered runtime rejects drifted bridge fixture wrappers" {
    const drifted =
        \\const example = @import("example_early_exit");
        \\
        \\pub const bridge_case_id = "early_exit";
        \\pub const source_path = "test/direct_style_bridge/early_exit.zig";
        \\pub const source = @embedFile("early_exit.zig");
        \\
        \\pub fn run(writer: anytype) anyerror!void {
        \\    _ = example;
        \\    try writer.writeAll("status=late\\n");
        \\}
    ;

    const modified_fixture = struct {
        /// Stable bridge case id for the synthetic drifted fixture.
        pub const bridge_case_id = "early_exit";
        /// Canonical path for the synthetic drifted fixture wrapper.
        pub const source_path = "test/direct_style_bridge/early_exit.zig";
        /// Drifted fixture source consumed by bridge admission.
        pub const source = drifted;
    };

    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(error.RejectedBridgeFixture, private_lowered_runtime.runBridgeFixture(modified_fixture, &writer));
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
    try std.testing.expect(lowered.diagnostics[0].line >= 1);

    try std.testing.expect(private_lowered_runtime.supportsCaseId("early_exit"));

    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const execution = try private_lowered_runtime.runCaseId(&writer, "early_exit");
    try std.testing.expectEqualStrings("bridge.early_exit", execution.label);
    try std.testing.expectEqualStrings("early_exit", execution.scenario.case_id);
}
