const source_lowering = @import("source_lowering");
const source_lowering_registry = @import("source_lowering_registry");
const std = @import("std");

fn compatIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

fn cwdReadFileAlloc(
    allocator: std.mem.Allocator,
    path: []const u8,
    limit: usize,
) ![]u8 {
    return try std.Io.Dir.cwd().readFileAlloc(compatIo(), path, allocator, .limited(limit));
}

fn cwdRealPathAlloc(allocator: std.mem.Allocator, path: []const u8) ![:0]u8 {
    return try std.Io.Dir.cwd().realPathFileAlloc(compatIo(), path, allocator);
}

fn currentPathAlloc(allocator: std.mem.Allocator) ![:0]u8 {
    return try std.process.currentPathAlloc(compatIo(), allocator);
}

fn symlinkAliasPath(
    allocator: std.mem.Allocator,
    tmp: *std.testing.TmpDir,
    target_path: []const u8,
    alias_name: []const u8,
) ![]u8 {
    try tmp.dir.symLink(compatIo(), target_path, alias_name, .{});
    const tmp_path = try tmp.dir.realPathFileAlloc(compatIo(), ".", allocator);
    defer allocator.free(tmp_path);
    return try std.fmt.allocPrint(allocator, "{s}{c}{s}", .{ tmp_path, std.Io.Dir.path.sep, alias_name });
}

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

test "source-lowering rejects unreadable non-canonical paths before reading" {
    var lowered = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = "source.branch_resume",
        .source_path = "/tmp/shift_missing_noncanonical_branch_resume.zig",
        .entry_symbol = "run",
        .surface_kind = .source_case,
    });
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("non_canonical_source_path", lowered.diagnostics[0].code);
}

test "source-lowering rejects external symlink aliases for canonical files" {
    const canonical_path = try cwdRealPathAlloc(std.testing.allocator, "test/source_lowering_corpus/fixtures/branch_resume.zig");
    defer std.testing.allocator.free(canonical_path);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const alias_path = try symlinkAliasPath(std.testing.allocator, &tmp, canonical_path, "branch_resume_alias.zig");
    defer std.testing.allocator.free(alias_path);

    var lowered = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = "source.branch_resume",
        .source_path = alias_path,
        .entry_symbol = "run",
        .surface_kind = .source_case,
    });
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("non_canonical_source_path", lowered.diagnostics[0].code);
}

test "source-lowering rejects the wrong entry function for supported examples" {
    var lowered = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = "example.open_row_transform_basic",
        .source_path = "examples/open_row_transform_basic.zig",
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
        /// Public `source_case_id` declaration.
        pub const source_case_id = "source.branch_resume";
        /// Public `source` declaration.
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
        /// Public `source_case_id` declaration.
        pub const source_case_id = "source.branch_resume";
        /// Public `source` declaration.
        pub const source = comment_only_source;
    };

    var lowered = try source_lowering.lowerFixture(std.testing.allocator, modified_fixture);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.isAccepted());
}

test "inline source lowering rejects non-canonical source paths even for canonical text" {
    const canonical_text = try cwdReadFileAlloc(std.testing.allocator, "test/source_lowering_corpus/fixtures/branch_resume.zig", 1 << 20);
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

test "inline source lowering rejects external symlink aliases for canonical text" {
    const canonical_text = try cwdReadFileAlloc(std.testing.allocator, "test/source_lowering_corpus/fixtures/branch_resume.zig", 1 << 20);
    defer std.testing.allocator.free(canonical_text);

    const canonical_path = try cwdRealPathAlloc(std.testing.allocator, "test/source_lowering_corpus/fixtures/branch_resume.zig");
    defer std.testing.allocator.free(canonical_path);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const alias_path = try symlinkAliasPath(std.testing.allocator, &tmp, canonical_path, "branch_resume_inline_alias.zig");
    defer std.testing.allocator.free(alias_path);

    var lowered = try source_lowering.inspectInlineSource(std.testing.allocator, .{
        .case_id = "source.branch_resume",
        .source_path = alias_path,
        .entry_symbol = "run",
        .surface_kind = .source_case,
    }, canonical_text);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("non_canonical_source_path", lowered.diagnostics[0].code);
}

test "inline source lowering accepts canonical repo-relative paths from subdirectories" {
    const canonical_text = try cwdReadFileAlloc(std.testing.allocator, "test/source_lowering_corpus/fixtures/branch_resume.zig", 1 << 20);
    defer std.testing.allocator.free(canonical_text);

    const original_cwd = try currentPathAlloc(std.testing.allocator);
    defer std.testing.allocator.free(original_cwd);
    try std.process.setCurrentPath(compatIo(), "examples");
    defer std.process.setCurrentPath(compatIo(), original_cwd) catch unreachable;

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

test "source-lowering accepts canonical repo-relative paths from symlinked checkouts" {
    const original_cwd = try currentPathAlloc(std.testing.allocator);
    defer std.testing.allocator.free(original_cwd);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const checkout_alias = try symlinkAliasPath(std.testing.allocator, &tmp, original_cwd, "shift_repo_alias");
    defer std.testing.allocator.free(checkout_alias);

    try std.process.setCurrentPath(compatIo(), checkout_alias);
    defer std.process.setCurrentPath(compatIo(), original_cwd) catch unreachable;

    var lowered = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = "source.branch_resume",
        .source_path = "test/source_lowering_corpus/fixtures/branch_resume.zig",
        .entry_symbol = "run",
        .surface_kind = .source_case,
    });
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.isAccepted());
    try std.testing.expectEqualStrings("test/source_lowering_corpus/fixtures/branch_resume.zig", lowered.source_path);
}

test "inline source lowering rejects alias-root prefix matches without a path boundary" {
    const canonical_text = try cwdReadFileAlloc(std.testing.allocator, "test/source_lowering_corpus/fixtures/branch_resume.zig", 1 << 20);
    defer std.testing.allocator.free(canonical_text);

    const original_cwd = try currentPathAlloc(std.testing.allocator);
    defer std.testing.allocator.free(original_cwd);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const checkout_alias = try symlinkAliasPath(std.testing.allocator, &tmp, original_cwd, "shift_repo_alias_prefix");
    defer std.testing.allocator.free(checkout_alias);

    const prefixed_alias_path = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}{s}",
        .{ checkout_alias, "test/source_lowering_corpus/fixtures/branch_resume.zig" },
    );
    defer std.testing.allocator.free(prefixed_alias_path);

    var lowered = try source_lowering.inspectInlineSource(std.testing.allocator, .{
        .case_id = "source.branch_resume",
        .source_path = prefixed_alias_path,
        .entry_symbol = "run",
        .surface_kind = .source_case,
    }, canonical_text);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("non_canonical_source_path", lowered.diagnostics[0].code);
}

test "inline source lowering rejects repo-internal checkout aliases" {
    const canonical_text = try cwdReadFileAlloc(std.testing.allocator, "test/source_lowering_corpus/fixtures/branch_resume.zig", 1 << 20);
    defer std.testing.allocator.free(canonical_text);

    const original_cwd = try currentPathAlloc(std.testing.allocator);
    defer std.testing.allocator.free(original_cwd);

    const internal_alias_name = ".tmp_shift_repo_alias_internal";
    std.Io.Dir.cwd().deleteFile(compatIo(), internal_alias_name) catch {};
    try std.Io.Dir.cwd().symLink(compatIo(), original_cwd, internal_alias_name, .{});
    defer std.Io.Dir.cwd().deleteFile(compatIo(), internal_alias_name) catch unreachable;

    const alias_source_path = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}{c}{s}",
        .{ internal_alias_name, std.Io.Dir.path.sep, "test/source_lowering_corpus/fixtures/branch_resume.zig" },
    );
    defer std.testing.allocator.free(alias_source_path);

    var lowered = try source_lowering.inspectInlineSource(std.testing.allocator, .{
        .case_id = "source.branch_resume",
        .source_path = alias_source_path,
        .entry_symbol = "run",
        .surface_kind = .source_case,
    }, canonical_text);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("non_canonical_source_path", lowered.diagnostics[0].code);
}

test "inline source lowering rejects repo-internal aliases nested inside symlinked checkouts" {
    const canonical_text = try cwdReadFileAlloc(std.testing.allocator, "test/source_lowering_corpus/fixtures/branch_resume.zig", 1 << 20);
    defer std.testing.allocator.free(canonical_text);

    const original_cwd = try currentPathAlloc(std.testing.allocator);
    defer std.testing.allocator.free(original_cwd);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const checkout_alias = try symlinkAliasPath(std.testing.allocator, &tmp, original_cwd, "shift_repo_alias_nested");
    defer std.testing.allocator.free(checkout_alias);

    var checkout_dir = try std.Io.Dir.openDirAbsolute(compatIo(), checkout_alias, .{});
    defer checkout_dir.close(compatIo());
    const nested_alias_name = ".tmp_shift_repo_alias_nested_internal";
    checkout_dir.deleteFile(compatIo(), nested_alias_name) catch {};
    try checkout_dir.symLink(compatIo(), original_cwd, nested_alias_name, .{});
    defer checkout_dir.deleteFile(compatIo(), nested_alias_name) catch unreachable;

    const alias_source_path = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}{c}{s}{c}{s}",
        .{
            checkout_alias,
            std.Io.Dir.path.sep,
            nested_alias_name,
            std.Io.Dir.path.sep,
            "test/source_lowering_corpus/fixtures/branch_resume.zig",
        },
    );
    defer std.testing.allocator.free(alias_source_path);

    var lowered = try source_lowering.inspectInlineSource(std.testing.allocator, .{
        .case_id = "source.branch_resume",
        .source_path = alias_source_path,
        .entry_symbol = "run",
        .surface_kind = .source_case,
    }, canonical_text);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("non_canonical_source_path", lowered.diagnostics[0].code);
}

test "inline source lowering rejects drifted canonical text even on the canonical path" {
    const canonical_text = try cwdReadFileAlloc(std.testing.allocator, "test/source_lowering_corpus/fixtures/branch_resume.zig", 1 << 20);
    defer std.testing.allocator.free(canonical_text);

    const drifted = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        canonical_text,
        "answer = resumed + 1;",
        "answer = resumed + 2;",
    );
    defer std.testing.allocator.free(drifted);

    var lowered = try source_lowering.inspectInlineSource(std.testing.allocator, .{
        .case_id = "source.branch_resume",
        .source_path = "test/source_lowering_corpus/fixtures/branch_resume.zig",
        .entry_symbol = "run",
        .surface_kind = .source_case,
    }, drifted);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("unsupported_shape", lowered.diagnostics[0].code);
}

test "inline source lowering rejects whitespace drift after accepted authoring admission" {
    const canonical_text = try cwdReadFileAlloc(std.testing.allocator, "test/source_lowering_corpus/fixtures/branch_resume.zig", 1 << 20);
    defer std.testing.allocator.free(canonical_text);

    const drifted = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        canonical_text,
        "answer = resumed + 1;",
        "answer = resumed +\n            1;",
    );
    defer std.testing.allocator.free(drifted);

    var lowered = try source_lowering.inspectInlineSource(std.testing.allocator, .{
        .case_id = "source.branch_resume",
        .source_path = "test/source_lowering_corpus/fixtures/branch_resume.zig",
        .entry_symbol = "run",
        .surface_kind = .source_case,
    }, drifted);
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("unsupported_shape", lowered.diagnostics[0].code);
}

test "file-backed inline source lowering accepts canonical repo-relative paths from subdirectories" {
    const canonical_text = try cwdReadFileAlloc(std.testing.allocator, "test/source_lowering_corpus/fixtures/branch_resume.zig", 1 << 20);
    defer std.testing.allocator.free(canonical_text);

    const original_cwd = try currentPathAlloc(std.testing.allocator);
    defer std.testing.allocator.free(original_cwd);
    try std.process.setCurrentPath(compatIo(), "examples");
    defer std.process.setCurrentPath(compatIo(), original_cwd) catch unreachable;

    var lowered = try source_lowering.inspectFileBackedInlineSource(std.testing.allocator, .{
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

test "file-backed inline source lowering rejects whitespace drift after accepted authoring admission" {
    const canonical_text = try cwdReadFileAlloc(std.testing.allocator, "test/source_lowering_corpus/fixtures/branch_resume.zig", 1 << 20);
    defer std.testing.allocator.free(canonical_text);

    const drifted = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        canonical_text,
        "answer = resumed + 1;",
        "answer = resumed +\n            1;",
    );
    defer std.testing.allocator.free(drifted);

    var lowered = try source_lowering.inspectFileBackedInlineSource(std.testing.allocator, .{
        .case_id = "source.branch_resume",
        .source_path = "test/source_lowering_corpus/fixtures/branch_resume.zig",
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
    const witness_source_text = try cwdReadFileAlloc(std.testing.allocator, "src/witness_sources.zig", 1 << 20);
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
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const witness_source_text = try cwdReadFileAlloc(allocator, "src/witness_sources.zig", 1 << 20);

    const mutated = try std.mem.replaceOwned(
        u8,
        allocator,
        witness_source_text,
        "writer.print(\"{s}\\n\", .{line})",
        "writer.print(\"[{s}]\\n\", .{line})",
    );

    var lowered = try source_lowering.inspectInlineSource(allocator, .{
        .case_id = "witness.atm_resume_transform",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runAtmResumeTransform",
        .surface_kind = .witness,
    }, mutated);
    defer lowered.deinit(allocator);

    try std.testing.expect(!lowered.isAccepted());
    try std.testing.expectEqualStrings("unsupported_shape", lowered.diagnostics[0].code);
}

test "shared static redelim witness rejects stateful nested handler initializers" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const witness_source_text = try cwdReadFileAlloc(allocator, "src/witness_sources.zig", 1 << 20);

    const mutated = try std.mem.replaceOwned(
        u8,
        allocator,
        witness_source_text,
        ".inner = ResumeWitness.use(.{ .handler = transcript_static_redelim.InnerHandler{} }),",
        ".inner = ResumeWitness.use(.{ .handler = transcript_static_redelim.InnerHandler{ .state = {} } }),",
    );

    var lowered = try source_lowering.inspectInlineSource(allocator, .{
        .case_id = "witness.static_redelim",
        .source_path = "src/witness_sources.zig",
        .entry_symbol = "runStaticRedelim",
        .surface_kind = .witness,
    }, mutated);
    defer lowered.deinit(allocator);

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
    const original_cwd = try currentPathAlloc(std.testing.allocator);
    defer std.testing.allocator.free(original_cwd);
    try std.process.setCurrentPath(compatIo(), "examples");
    defer std.process.setCurrentPath(compatIo(), original_cwd) catch unreachable;

    var lowered = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = "example.open_row_transform_basic",
        .source_path = "open_row_transform_basic.zig",
        .entry_symbol = "run",
        .surface_kind = .example,
    });
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.isAccepted());
    try std.testing.expectEqualStrings("examples/open_row_transform_basic.zig", lowered.source_path);
}

test "source-lowering accepts canonical repo-relative paths from subdirectories" {
    const original_cwd = try currentPathAlloc(std.testing.allocator);
    defer std.testing.allocator.free(original_cwd);
    try std.process.setCurrentPath(compatIo(), "examples");
    defer std.process.setCurrentPath(compatIo(), original_cwd) catch unreachable;

    var lowered = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = "example.open_row_transform_basic",
        .source_path = "examples/open_row_transform_basic.zig",
        .entry_symbol = "run",
        .surface_kind = .example,
    });
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expect(lowered.isAccepted());
    try std.testing.expectEqualStrings("examples/open_row_transform_basic.zig", lowered.source_path);
}

test "source-lowering rejects mismatched expected_status values" {
    var lowered = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = "example.open_row_transform_basic",
        .source_path = "examples/open_row_transform_basic.zig",
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
