const source_lowering_registry = @import("source_lowering_registry");
const source_lowering = @import("source_lowering");
const std = @import("std");

test "source-lowering registry keeps the exact wave-one case count" {
    try std.testing.expectEqual(@as(usize, 8), source_lowering_registry.cases.len);
    for (source_lowering_registry.cases) |case| {
        try std.testing.expect(case.status == .canonical);
    }
}

test "source-lowering rejects unsupported fixture ids" {
    const unsupported_fixture = struct {
        /// Stable unsupported source-lowering case id.
        pub const source_case_id = "source.recursion";
    };

    try std.testing.expectError(error.UnsupportedSourceCase, source_lowering.lowerFixture(std.testing.allocator, unsupported_fixture));
}

test "source-lowering rejects non-canonical source paths for known cases" {
    var lowered = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = "source.branch_resume",
        .source_path = "test/source_lowering_corpus/fixtures/helper_call_resume.zig",
        .entry_symbol = "run",
        .surface_kind = .source_case,
    });
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("non_canonical_source_path", lowered.diagnostics[0].code);
}

test "source-lowering rejects the wrong entry function for supported examples" {
    var lowered = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = "example.define_basic",
        .source_path = "examples/define_basic.zig",
        .entry_symbol = "runCounter",
        .surface_kind = .example,
    });
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("unsupported_shape", lowered.diagnostics[0].code);
}

test "source-lowering rejects the wrong witness entry in shared witness sources" {
    var lowered = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = "witness.atm_resume_transform",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runResumeOrReturnResume",
        .surface_kind = .witness,
    });
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("unsupported_shape", lowered.diagnostics[0].code);
}

test "source-lowering rejects return-now witness ids when pointed at the resume witness body" {
    var lowered = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = "witness.resume_or_return_return_now",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runResumeOrReturnResume",
        .surface_kind = .witness,
    });
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("unsupported_shape", lowered.diagnostics[0].code);
}

test "source-lowering rejects resume witness ids when pointed at the ATM witness body" {
    var lowered = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = "witness.resume_or_return_resume",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runAtmResumeTransform",
        .surface_kind = .witness,
    });
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("unsupported_shape", lowered.diagnostics[0].code);
}

test "source-lowering rejects altered fixture sources with dead-code canonical snippets" {
    const modified_source =
        \\pub fn run(writer: anytype) anyerror!void {
        \\    try writer.writeAll("branch=before\n");
        \\    return;
        \\    var answer: i32 = 0;
        \\    const take_branch = true;
        \\    if (take_branch) {
        \\        try writer.writeAll("branch=taken\n");
        \\        const resumed: i32 = 41;
        \\        try writer.print("resume={d}\n", .{resumed});
        \\        answer = resumed + 1;
        \\    }
        \\    try writer.writeAll("branch=after\n");
        \\    try writer.print("final={d}\n", .{answer});
        \\}
    ;

    const modified_fixture = struct {
        pub const source_case_id = "source.branch_resume";
        pub const source = modified_source;
    };

    var lowered = try source_lowering.lowerFixture(std.testing.allocator, modified_fixture);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("unsupported_shape", lowered.diagnostics[0].code);
}

test "source-lowering accepts comment-only edits to canonical fixtures" {
    const comment_only_source =
        \\/// Stable source-lowering case id.
        \\pub const source_case_id = "source.branch_resume";
        \\/// Embedded source text consumed by the source-validated source-lowering checker.
        \\pub const source = @embedFile("branch_resume.zig");
        \\// harmless fixture comment
        \\
        \\/// Run the branch case with source-lowering control flow.
        \\pub fn run(writer: anytype) anyerror!void {
        \\    try writer.writeAll("branch=before\n");
        \\    var answer: i32 = 0;
        \\    const take_branch = true;
        \\    if (take_branch) {
        \\        try writer.writeAll("branch=taken\n");
        \\        const resumed: i32 = 41;
        \\        try writer.print("resume={d}\n", .{resumed});
        \\        answer = resumed + 1;
        \\    }
        \\    try writer.writeAll("branch=after\n");
        \\    try writer.print("final={d}\n", .{answer});
        \\}
    ;

    const modified_fixture = struct {
        pub const source_case_id = "source.branch_resume";
        pub const source = comment_only_source;
    };

    var lowered = try source_lowering.lowerFixture(std.testing.allocator, modified_fixture);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.isAccepted());
}

test "inline source lowering rejects non-canonical source paths even for canonical text" {
    const canonical_text = try std.fs.cwd().readFileAlloc(
        std.testing.allocator,
        "test/source_lowering_corpus/fixtures/branch_resume.zig",
        1 << 20,
    );
    defer std.testing.allocator.free(canonical_text);

    var lowered = try source_lowering.inspectInlineSource(std.testing.allocator, .{
        .case_id = "source.branch_resume",
        .source_path = "/tmp/shift-inline-noncanonical.zig",
        .entry_symbol = "run",
        .surface_kind = .source_case,
    }, canonical_text);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("non_canonical_source_path", lowered.diagnostics[0].code);
}

test "inline source lowering accepts canonical repo-relative paths from subdirectories" {
    const canonical_text = try std.fs.cwd().readFileAlloc(
        std.testing.allocator,
        "test/source_lowering_corpus/fixtures/branch_resume.zig",
        1 << 20,
    );
    defer std.testing.allocator.free(canonical_text);

    const original_cwd = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(original_cwd);
    try std.posix.chdir("examples");
    defer std.posix.chdir(original_cwd) catch unreachable;

    var lowered = try source_lowering.inspectInlineSource(std.testing.allocator, .{
        .case_id = "source.branch_resume",
        .source_path = "test/source_lowering_corpus/fixtures/branch_resume.zig",
        .entry_symbol = "run",
        .surface_kind = .source_case,
    }, canonical_text);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.isAccepted());
    try std.testing.expectEqualStrings("test/source_lowering_corpus/fixtures/branch_resume.zig", lowered.source_path);
}

test "source-lowering rejects drifted canonical files even when the path stays canonical" {
    const fixture_path = "test/source_lowering_corpus/fixtures/helper_call_resume.zig";

    const drifted =
        \\/// Stable source-lowering case id.
        \\pub const source_case_id = "source.helper_call_resume";
        \\/// Embedded source text consumed by the source-validated source-lowering checker.
        \\pub const source = @embedFile("helper_call_resume.zig");
        \\
        \\fn helper(writer: anytype) anyerror!i32 {
        \\    try writer.writeAll("helper=enter\n");
        \\    const resumed: i32 = 41;
        \\    try writer.print("resume={d}\n", .{resumed});
        \\    try writer.writeAll("helper=exit\n");
        \\    return resumed + 2;
        \\}
        \\
        \\/// Run the helper-call case with source-lowering control flow.
        \\pub fn run(writer: anytype) anyerror!void {
        \\    const answer = try helper(writer);
        \\    try writer.print("final={d}\n", .{answer});
        \\}
    ;

    var lowered = try source_lowering.inspectFileBackedInlineSource(std.testing.allocator, .{
        .case_id = "source.helper_call_resume",
        .source_path = fixture_path,
        .entry_symbol = "run",
        .surface_kind = .source_case,
    }, drifted);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("unsupported_shape", lowered.diagnostics[0].code);
}

test "file-backed inline source lowering preserves parse-error locations" {
    const broken =
        \\pub fn run(writer: anytype) anyerror!void {
        \\    this is not zig
        \\}
    ;

    var lowered = try source_lowering.inspectFileBackedInlineSource(std.testing.allocator, .{
        .case_id = "source.branch_resume",
        .source_path = "test/source_lowering_corpus/fixtures/branch_resume.zig",
        .entry_symbol = "run",
        .surface_kind = .source_case,
    }, broken);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("parse_error", lowered.diagnostics[0].code);
    try std.testing.expectEqual(@as(usize, 2), lowered.diagnostics[0].line);
    try std.testing.expectEqual(@as(usize, 10), lowered.diagnostics[0].column);
}

test "shared witness rows ignore unrelated sibling edits in the same source file" {
    const witness_source_text = try std.fs.cwd().readFileAlloc(std.testing.allocator, "src/witness_sources.zig", 1 << 20);
    defer std.testing.allocator.free(witness_source_text);

    const mutated = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        witness_source_text,
        "return current;",
        "return current + 1;",
    );
    defer std.testing.allocator.free(mutated);

    var lowered = try source_lowering.inspectInlineSource(std.testing.allocator, .{
        .case_id = "witness.atm_resume_transform",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runAtmResumeTransform",
        .surface_kind = .witness,
    }, mutated);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.isAccepted());
}

test "shared witness rows reject shared helper edits in the same source file" {
    const witness_source_text = try std.fs.cwd().readFileAlloc(std.testing.allocator, "src/witness_sources.zig", 1 << 20);
    defer std.testing.allocator.free(witness_source_text);

    const mutated = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        witness_source_text,
        "writer.print(\"{s}\\n\", .{line})",
        "writer.print(\"[{s}]\\n\", .{line})",
    );
    defer std.testing.allocator.free(mutated);

    var lowered = try source_lowering.inspectInlineSource(std.testing.allocator, .{
        .case_id = "witness.atm_resume_transform",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runAtmResumeTransform",
        .surface_kind = .witness,
    }, mutated);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("unsupported_shape", lowered.diagnostics[0].code);
}

test "source-lowering owns rejected source paths" {
    const original_path = "test/source_lowering_corpus/fixtures/helper_call_resume.zig";
    const mutable_path = try std.testing.allocator.dupe(u8, original_path);
    defer std.testing.allocator.free(mutable_path);

    var lowered = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = "source.branch_resume",
        .source_path = mutable_path,
        .entry_symbol = "run",
        .surface_kind = .source_case,
    });
    defer lowered.deinit(std.testing.allocator);

    @memset(mutable_path, 'x');

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings(original_path, lowered.source_path);
    try std.testing.expectEqualStrings(original_path, lowered.diagnostics[0].path);
}

test "accepted source-lowering rows canonicalize source paths" {
    const original_cwd = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(original_cwd);
    try std.posix.chdir("examples");
    defer std.posix.chdir(original_cwd) catch unreachable;

    var lowered = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = "example.define_basic",
        .source_path = "define_basic.zig",
        .entry_symbol = "run",
        .surface_kind = .example,
    });
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.isAccepted());
    try std.testing.expectEqualStrings("examples/define_basic.zig", lowered.source_path);
}

test "source-lowering rejects mismatched expected_status values" {
    var lowered = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = "example.define_basic",
        .source_path = "examples/define_basic.zig",
        .entry_symbol = "run",
        .surface_kind = .example,
        .expected_status = .candidate_green,
    });
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("unsupported_shape", lowered.diagnostics[0].code);
}

test "source-lowering no longer exposes a public root surface" {
    const shift = @import("shift");

    try std.testing.expect(!@hasDecl(shift, "source_lowering"));
}
