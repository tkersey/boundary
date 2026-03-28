const build_options = @import("authoring_build_options");
const effect_ir = @import("effect_ir");
const lowered_machine = @import("lowered_machine");
const parity_scenarios = @import("parity_scenarios");
const program_frontend = @import("program_frontend");
const std = @import("std");

/// Internal lowering surfaces that share the canonical authoring lowerer.
pub const SurfaceKind = enum {
    bridge,
    effect,
    example,
    source_case,
    user_defined_effect,
    witness,
};

/// Public `CompareScope` declaration.
pub const CompareScope = enum {
    entry,
    file,
};

/// Progress state for one shared authoring-lowering result.
pub const LowerStatus = enum {
    candidate_green,
    canonical,
    parity_green,
    rejected,
};

/// One diagnostic emitted by the shared authoring lowerer.
pub const Diagnostic = struct {
    code: []const u8,
    message: []const u8,
    path: []const u8,
    line: usize,
    column: usize,
};

/// One canonical row that can be checked and lowered through the shared core.
pub const CanonicalCase = struct {
    case_id: []const u8,
    label: []const u8,
    source_path: []const u8,
    entry_symbol: []const u8,
    compare_scope: CompareScope = .file,
    surface_kind: SurfaceKind,
    status: LowerStatus,
    scenario_id: parity_scenarios.ScenarioId,
    feature_flags: []const []const u8,
};

/// One lowered authoring result shared by source-lowering and bridge tooling.
pub const LoweredAuthoring = struct {
    case_id: []const u8,
    label: []const u8,
    source_path: []const u8,
    surface_kind: SurfaceKind,
    status: LowerStatus,
    canonical_scenario_id: ?parity_scenarios.ScenarioId,
    expected_transcript: []const u8,
    steps: []const lowered_machine.Step,
    feature_flags: []const []const u8,
    diagnostics: []const Diagnostic,

    /// Release owned slices captured in a lowered authoring result.
    pub fn deinit(self: *LoweredAuthoring, allocator: std.mem.Allocator) void {
        allocator.free(self.source_path);
        allocator.free(self.steps);
        allocator.free(self.feature_flags);
        allocator.free(self.diagnostics);
        self.* = undefined;
    }
};

/// One open-row lowering record lowered through the shared authoring-lowering seam.
pub const OpenRowLoweredAuthoring = struct {
    label: []const u8,
    normalization: effect_ir.NormalizationDigest,
    program: effect_ir.Program,
};

/// Lower one open-row frontend payload through the shared semantic center.
pub fn lowerOpenRowProgram(program: program_frontend.OpenRowProgram) effect_ir.NormalizeError!OpenRowLoweredAuthoring {
    const lowered = program_frontend.lowerOpenRow(program);
    return .{
        .label = program.label,
        .normalization = try effect_ir.rowDigest(program.function.row, program.function.outputs),
        .program = lowered,
    };
}

/// One machine-readable accepted-row equivalence record.
pub const EquivalenceRecord = struct {
    case_id: []const u8,
    surface_kind: SurfaceKind,
    source_path: []const u8,
    entry_symbol: []const u8,
    canonical_scenario_id: ?parity_scenarios.ScenarioId,
    lower_status: LowerStatus,
    transcript_equivalence: bool,
    feature_flags: []const []const u8,
    diagnostic_count: usize,
};

/// One machine-readable rejected-row record.
pub const RejectionRecord = struct {
    case_id: []const u8,
    source_path: []const u8,
    entry_symbol: []const u8,
    diagnostic_code: []const u8,
    diagnostic_line: usize,
    diagnostic_column: usize,
};

const LowerSourceInput = struct {
    display_path: []const u8,
    actual_path: []const u8,
    source_text: []const u8,
    expected_status: LowerStatus,
};

const NormalizedToken = struct {
    value: []const u8,
    token_index: std.zig.Ast.TokenIndex,
};

fn duplicateFeatureFlags(
    allocator: std.mem.Allocator,
    feature_flags: []const []const u8,
) std.mem.Allocator.Error![]const []const u8 {
    var duped = try allocator.alloc([]const u8, feature_flags.len);
    for (feature_flags, 0..) |flag, index| {
        duped[index] = flag;
    }
    return duped;
}

fn duplicateSteps(
    allocator: std.mem.Allocator,
    steps: []const lowered_machine.Step,
) std.mem.Allocator.Error![]const lowered_machine.Step {
    return try allocator.dupe(lowered_machine.Step, steps);
}

fn emptyDiagnostics(allocator: std.mem.Allocator) std.mem.Allocator.Error![]const Diagnostic {
    return try allocator.alloc(Diagnostic, 0);
}

fn normalizeCallerVisiblePathAlloc(
    allocator: std.mem.Allocator,
    base_path: []const u8,
    path: []const u8,
) ![]u8 {
    if (std.fs.path.isAbsolute(path)) {
        return try std.fs.path.resolve(allocator, &.{path});
    }
    return try std.fs.path.resolve(allocator, &.{ base_path, path });
}

fn canonicalRepoRootAlloc(allocator: std.mem.Allocator) ![]u8 {
    return try std.fs.realpathAlloc(allocator, build_options.package_root);
}

fn normalizeRepoRelativePathAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const normalized = try allocator.dupe(u8, path);
    for (normalized) |*byte| {
        if (byte.* == '/' or byte.* == '\\') byte.* = std.fs.path.sep;
    }
    return normalized;
}

fn normalizeExpectedCanonicalPathAlloc(
    allocator: std.mem.Allocator,
    canonical_repo_root: []const u8,
    expected_path: []const u8,
) ![]u8 {
    return try std.fs.path.resolve(allocator, &.{ canonical_repo_root, expected_path });
}

fn repoAliasRootMatchesExpected(
    allocator: std.mem.Allocator,
    normalized_actual: []const u8,
    expected_path: []const u8,
    canonical_repo_root: []const u8,
) bool {
    if (!std.mem.endsWith(u8, normalized_actual, expected_path)) return false;
    if (normalized_actual.len <= expected_path.len) return false;
    if (normalized_actual[normalized_actual.len - expected_path.len - 1] != std.fs.path.sep) return false;

    var repo_alias_root = normalized_actual[0 .. normalized_actual.len - expected_path.len];
    while (repo_alias_root.len != 0 and repo_alias_root[repo_alias_root.len - 1] == std.fs.path.sep) {
        repo_alias_root.len -= 1;
    }
    if (repo_alias_root.len == 0) return false;
    if (std.mem.startsWith(u8, repo_alias_root, canonical_repo_root)) {
        if (repo_alias_root.len == canonical_repo_root.len) return false;
        if (repo_alias_root[canonical_repo_root.len] == std.fs.path.sep) return false;
    }

    const canonical_alias_root = std.fs.realpathAlloc(allocator, repo_alias_root) catch return false;
    defer allocator.free(canonical_alias_root);
    if (!std.mem.eql(u8, canonical_alias_root, canonical_repo_root)) return false;

    const alias_parent = std.fs.path.dirname(repo_alias_root) orelse return false;
    const canonical_alias_parent = std.fs.realpathAlloc(allocator, alias_parent) catch return false;
    defer allocator.free(canonical_alias_parent);

    if (std.mem.startsWith(u8, canonical_alias_parent, canonical_repo_root)) {
        if (canonical_alias_parent.len == canonical_repo_root.len) return false;
        if (canonical_alias_parent[canonical_repo_root.len] == std.fs.path.sep) return false;
    }
    return true;
}

fn sourcePathMatchesExpected(allocator: std.mem.Allocator, actual_path: []const u8, expected_path: []const u8) bool {
    const cwd_path = std.process.getCwdAlloc(allocator) catch return false;
    defer allocator.free(cwd_path);

    const normalized_actual = normalizeCallerVisiblePathAlloc(allocator, cwd_path, actual_path) catch return false;
    defer allocator.free(normalized_actual);

    const canonical_repo_root = canonicalRepoRootAlloc(allocator) catch return false;
    defer allocator.free(canonical_repo_root);

    const normalized_expected_path = normalizeRepoRelativePathAlloc(allocator, expected_path) catch return false;
    defer allocator.free(normalized_expected_path);

    const canonical_expected = normalizeExpectedCanonicalPathAlloc(allocator, canonical_repo_root, normalized_expected_path) catch return false;
    defer allocator.free(canonical_expected);

    if (std.mem.eql(u8, normalized_actual, canonical_expected)) return true;
    return repoAliasRootMatchesExpected(allocator, normalized_actual, normalized_expected_path, canonical_repo_root);
}

/// Public `resolveRepoSourcePathAlloc` helper.
pub fn resolveRepoSourcePathAlloc(allocator: std.mem.Allocator, source_path: []const u8) ![]u8 {
    return try normalizeCallerVisiblePathAlloc(allocator, build_options.package_root, source_path);
}

fn readCanonicalSource(allocator: std.mem.Allocator, source_path: []const u8) ![]u8 {
    var repo_dir = try std.fs.openDirAbsolute(build_options.package_root, .{});
    defer repo_dir.close();
    return try repo_dir.readFileAlloc(allocator, source_path, 1 << 20);
}

fn canonicalSourceHash(expected_path: []const u8) ?[32]u8 {
    if (std.mem.eql(u8, expected_path, "test/source_lowering_corpus/fixtures/local_mutation_resume.zig")) return build_options.hash_local_mutation_resume;
    if (std.mem.eql(u8, expected_path, "test/source_lowering_corpus/fixtures/branch_resume.zig")) return build_options.hash_branch_resume;
    if (std.mem.eql(u8, expected_path, "test/source_lowering_corpus/fixtures/loop_resume.zig")) return build_options.hash_loop_resume;
    if (std.mem.eql(u8, expected_path, "test/source_lowering_corpus/fixtures/helper_call_resume.zig")) return build_options.hash_helper_call_resume;
    if (std.mem.eql(u8, expected_path, "test/source_lowering_corpus/fixtures/nested_prompt_static_redelim.zig")) return build_options.hash_nested_prompt_static_redelim;
    if (std.mem.eql(u8, expected_path, "test/source_lowering_corpus/fixtures/typed_error_try.zig")) return build_options.hash_typed_error_try;
    if (std.mem.eql(u8, expected_path, "test/source_lowering_corpus/fixtures/defer_resume.zig")) return build_options.hash_defer_resume;
    if (std.mem.eql(u8, expected_path, "test/source_lowering_corpus/fixtures/errdefer_error.zig")) return build_options.hash_errdefer_error;
    if (std.mem.eql(u8, expected_path, "examples/open_row_transform_basic.zig")) return build_options.hash_define_basic;
    if (std.mem.eql(u8, expected_path, "examples/open_row_choice_basic.zig")) return build_options.hash_define_choice_basic;
    if (std.mem.eql(u8, expected_path, "examples/open_row_abort_basic.zig")) return build_options.hash_define_abort_basic;
    if (std.mem.eql(u8, expected_path, "examples/early_exit.zig")) return build_options.hash_early_exit;
    if (std.mem.eql(u8, expected_path, "examples/open_row_generator.zig")) return build_options.hash_generator;
    if (std.mem.eql(u8, expected_path, "examples/resume_or_return.zig")) return build_options.hash_resume_or_return;
    if (std.mem.eql(u8, expected_path, "examples/open_row_workflow.zig")) return build_options.hash_front_door_workflow;
    if (std.mem.eql(u8, expected_path, "examples/nested_workflow.zig")) return build_options.hash_nested_workflow;
    if (std.mem.eql(u8, expected_path, "examples/state_basic.zig")) return build_options.hash_state_basic;
    if (std.mem.eql(u8, expected_path, "examples/reader_basic.zig")) return build_options.hash_reader_basic;
    if (std.mem.eql(u8, expected_path, "examples/optional_basic.zig")) return build_options.hash_optional_basic;
    if (std.mem.eql(u8, expected_path, "examples/exception_basic.zig")) return build_options.hash_exception_basic;
    if (std.mem.eql(u8, expected_path, "examples/resource_basic.zig")) return build_options.hash_resource_basic;
    if (std.mem.eql(u8, expected_path, "examples/writer_basic.zig")) return build_options.hash_writer_basic;
    if (std.mem.eql(u8, expected_path, "examples/open_row_abortive_validation.zig")) return build_options.hash_algebraic_abortive_validation;
    if (std.mem.eql(u8, expected_path, "examples/open_row_artifact_search.zig")) return build_options.hash_algebraic_artifact_search;
    if (std.mem.eql(u8, expected_path, "src/witness_sources.zig")) return build_options.hash_witness_sources;
    if (std.mem.eql(u8, expected_path, "src/witnesses.zig")) return build_options.hash_witnesses;
    if (std.mem.eql(u8, expected_path, "test/direct_style_bridge/open_row_abortive_validation.zig")) return build_options.hash_bridge_fixture_algebraic_abortive_validation;
    if (std.mem.eql(u8, expected_path, "test/direct_style_bridge/open_row_artifact_search.zig")) return build_options.hash_bridge_fixture_algebraic_artifact_search;
    if (std.mem.eql(u8, expected_path, "test/direct_style_bridge/atm_resume_transform.zig")) return build_options.hash_bridge_fixture_atm_resume_transform;
    if (std.mem.eql(u8, expected_path, "test/direct_style_bridge/direct_return.zig")) return build_options.hash_bridge_fixture_direct_return;
    if (std.mem.eql(u8, expected_path, "test/direct_style_bridge/early_exit.zig")) return build_options.hash_bridge_fixture_early_exit;
    if (std.mem.eql(u8, expected_path, "test/direct_style_bridge/exception_basic.zig")) return build_options.hash_bridge_fixture_exception_basic;
    if (std.mem.eql(u8, expected_path, "test/direct_style_bridge/open_row_generator.zig")) return build_options.hash_bridge_fixture_generator;
    if (std.mem.eql(u8, expected_path, "test/direct_style_bridge/multi_prompt.zig")) return build_options.hash_bridge_fixture_multi_prompt;
    if (std.mem.eql(u8, expected_path, "test/direct_style_bridge/nested_workflow.zig")) return build_options.hash_bridge_fixture_nested_workflow;
    if (std.mem.eql(u8, expected_path, "test/direct_style_bridge/optional_basic.zig")) return build_options.hash_bridge_fixture_optional_basic;
    if (std.mem.eql(u8, expected_path, "test/direct_style_bridge/reader_basic.zig")) return build_options.hash_bridge_fixture_reader_basic;
    if (std.mem.eql(u8, expected_path, "test/direct_style_bridge/resource_basic.zig")) return build_options.hash_bridge_fixture_resource_basic;
    if (std.mem.eql(u8, expected_path, "test/direct_style_bridge/resume_or_return.zig")) return build_options.hash_bridge_fixture_resume_or_return;
    if (std.mem.eql(u8, expected_path, "test/direct_style_bridge/resume_or_return_resume.zig")) return build_options.hash_bridge_fixture_resume_or_return_resume;
    if (std.mem.eql(u8, expected_path, "test/direct_style_bridge/resume_or_return_return_now.zig")) return build_options.hash_bridge_fixture_resume_or_return_return_now;
    if (std.mem.eql(u8, expected_path, "test/direct_style_bridge/state_basic.zig")) return build_options.hash_bridge_fixture_state_basic;
    if (std.mem.eql(u8, expected_path, "test/direct_style_bridge/static_redelim.zig")) return build_options.hash_bridge_fixture_static_redelim;
    if (std.mem.eql(u8, expected_path, "test/direct_style_bridge/writer_basic.zig")) return build_options.hash_bridge_fixture_writer_basic;
    return null;
}

fn sourceTextMatchesCanonicalHash(
    allocator: std.mem.Allocator,
    expected_path: []const u8,
    source_text: []const u8,
) bool {
    const expected_hash = canonicalSourceHash(expected_path) orelse return false;
    const normalized = normalizeSourceForHashAlloc(allocator, source_text) catch return false;
    defer allocator.free(normalized);

    var actual_hash = std.mem.zeroes([32]u8);
    std.crypto.hash.Blake3.hash(normalized, &actual_hash, .{});
    return std.mem.eql(u8, &actual_hash, &expected_hash);
}

fn normalizeSourceForHashAlloc(allocator: std.mem.Allocator, source: []const u8) std.mem.Allocator.Error![]u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var in_string = false;
    var escaped = false;
    var idx: usize = 0;
    while (idx < source.len) : (idx += 1) {
        const byte = source[idx];
        if (in_string) {
            try out.append(allocator, byte);
            if (escaped) {
                escaped = false;
            } else if (byte == '\\') {
                escaped = true;
            } else if (byte == '"') {
                in_string = false;
            }
            continue;
        }

        if (byte == '"') {
            in_string = true;
            try out.append(allocator, byte);
            continue;
        }
        if (byte == '/' and idx + 1 < source.len and source[idx + 1] == '/') {
            idx += 2;
            while (idx < source.len and source[idx] != '\n') : (idx += 1) {}
            continue;
        }
        if (std.ascii.isWhitespace(byte)) continue;
        try out.append(allocator, byte);
    }

    return try out.toOwnedSlice(allocator);
}

fn hasTopLevelFunctionNamed(tree: std.zig.Ast, name: []const u8) bool {
    var container_buffer: [2]std.zig.Ast.Node.Index = undefined;
    const root = tree.fullContainerDecl(&container_buffer, .root) orelse return false;
    for (root.ast.members) |member| {
        var fn_buffer: [1]std.zig.Ast.Node.Index = undefined;
        const fn_proto = tree.fullFnProto(&fn_buffer, member) orelse continue;
        const name_token = fn_proto.name_token orelse continue;
        if (std.mem.eql(u8, tree.tokenSlice(name_token), name)) return true;
    }
    return false;
}

fn topLevelFunctionName(tree: std.zig.Ast, member: std.zig.Ast.Node.Index) ?[]const u8 {
    var fn_buffer: [1]std.zig.Ast.Node.Index = undefined;
    const fn_proto = tree.fullFnProto(&fn_buffer, member) orelse return null;
    const name_token = fn_proto.name_token orelse return null;
    return tree.tokenSlice(name_token);
}

fn isSharedWitnessSourceEntryName(name: []const u8) bool {
    return std.mem.eql(u8, name, "runAtmResumeTransform") or
        std.mem.eql(u8, name, "runDirectReturn") or
        std.mem.eql(u8, name, "runResumeOrReturnReturnNow") or
        std.mem.eql(u8, name, "runResumeOrReturnResume") or
        std.mem.eql(u8, name, "runStaticRedelim") or
        std.mem.eql(u8, name, "runMultiPrompt") or
        std.mem.eql(u8, name, "runGenerator");
}

fn includeEntryCompareMember(tree: std.zig.Ast, member: std.zig.Ast.Node.Index, entry_symbol: []const u8) bool {
    const fn_name = topLevelFunctionName(tree, member) orelse return true;
    if (!isSharedWitnessSourceEntryName(fn_name)) return true;
    return std.mem.eql(u8, fn_name, entry_symbol);
}

const DiagnosticAtInput = struct {
    allocator: std.mem.Allocator,
    display_path: []const u8,
    code: []const u8,
    message: []const u8,
    line: usize,
    column: usize,
};

fn diagnosticAt(input: DiagnosticAtInput) std.mem.Allocator.Error![]const Diagnostic {
    const allocator = input.allocator;
    const owned_path = try allocator.dupe(u8, input.display_path);
    errdefer allocator.free(owned_path);
    const diags = try allocator.alloc(Diagnostic, 1);
    diags[0] = .{
        .code = input.code,
        .message = input.message,
        .path = owned_path,
        .line = input.line,
        .column = input.column,
    };
    return diags;
}

fn parseFailureDiagnostic(
    allocator: std.mem.Allocator,
    display_path: []const u8,
    source: [:0]const u8,
    tree: std.zig.Ast,
) std.mem.Allocator.Error![]const Diagnostic {
    if (tree.errors.len == 0) {
        return diagnosticAt(.{
            .allocator = allocator,
            .display_path = display_path,
            .code = "invalid_source",
            .message = "authoring lowerer rejected the source before building a lowered result",
            .line = 1,
            .column = 1,
        });
    }

    const parse_error = tree.errors[0];
    const loc = tree.tokenLocation(0, parse_error.token);
    _ = source;
    return diagnosticAt(.{
        .allocator = allocator,
        .display_path = display_path,
        .code = "parse_error",
        .message = @tagName(parse_error.tag),
        .line = loc.line + 1,
        .column = loc.column + 1,
    });
}

fn tokenLiteralKind(tag: std.zig.Token.Tag) bool {
    return switch (tag) {
        .number_literal,
        .string_literal,
        .multiline_string_literal_line,
        .char_literal,
        .builtin,
        => true,
        else => false,
    };
}

fn shouldSkipToken(tag: std.zig.Token.Tag) bool {
    return switch (tag) {
        .doc_comment, .container_doc_comment => true,
        else => false,
    };
}

fn normalizedTokenValueAlloc(
    allocator: std.mem.Allocator,
    tree: *const std.zig.Ast,
    token_index: std.zig.Ast.TokenIndex,
    previous_kept_tag: ?std.zig.Token.Tag,
) ![]const u8 {
    const tag = tree.tokenTag(token_index);
    if (tag == .identifier) {
        if (previous_kept_tag == .period) {
            return try std.fmt.allocPrint(allocator, "member:{s}", .{tree.tokenSlice(token_index)});
        }
        return try std.fmt.allocPrint(allocator, "identifier:{s}", .{tree.tokenSlice(token_index)});
    }
    if (tokenLiteralKind(tag)) {
        return try std.fmt.allocPrint(allocator, "literal:{s}", .{tree.tokenSlice(token_index)});
    }
    return try std.fmt.allocPrint(allocator, "tag:{s}", .{@tagName(tag)});
}

fn normalizeTokensAlloc(
    allocator: std.mem.Allocator,
    tree: *const std.zig.Ast,
) ![]NormalizedToken {
    var out = std.ArrayList(NormalizedToken).empty;
    errdefer {
        for (out.items) |item| allocator.free(item.value);
        out.deinit(allocator);
    }

    var previous_kept_tag: ?std.zig.Token.Tag = null;
    for (0..tree.tokens.len) |raw_index| {
        const token_index: std.zig.Ast.TokenIndex = @intCast(raw_index);
        const tag = tree.tokenTag(token_index);
        if (shouldSkipToken(tag)) continue;
        try out.append(allocator, .{
            .value = try normalizedTokenValueAlloc(allocator, tree, token_index, previous_kept_tag),
            .token_index = token_index,
        });
        previous_kept_tag = tag;
    }

    return try out.toOwnedSlice(allocator);
}

fn freeNormalizedTokens(allocator: std.mem.Allocator, tokens: []NormalizedToken) void {
    for (tokens) |item| allocator.free(item.value);
    allocator.free(tokens);
}

const Mismatch = struct {
    token_index: ?std.zig.Ast.TokenIndex,
    message: []const u8,
};

fn findMismatch(actual: []const NormalizedToken, canonical: []const NormalizedToken) ?Mismatch {
    const shared_len = @min(actual.len, canonical.len);
    for (0..shared_len) |index| {
        if (std.mem.eql(u8, actual[index].value, canonical[index].value)) continue;
        return .{
            .token_index = actual[index].token_index,
            .message = "source no longer matches the supported structural lowering shape for this case",
        };
    }
    if (actual.len != canonical.len) {
        return .{
            .token_index = if (actual.len == 0) null else actual[actual.len - 1].token_index,
            .message = "source token stream no longer matches the supported structural lowering shape for this case",
        };
    }
    return null;
}

fn duplicatedSourcePath(allocator: std.mem.Allocator, display_path: []const u8) ![]const u8 {
    return try allocator.dupe(u8, display_path);
}

fn normalizedComparisonTokensAlloc(
    allocator: std.mem.Allocator,
    case: CanonicalCase,
    source: [:0]const u8,
    tree: *const std.zig.Ast,
) ![]NormalizedToken {
    switch (case.compare_scope) {
        .file => return normalizeTokensAlloc(allocator, tree),
        .entry => {
            _ = source;
            var container_buffer: [2]std.zig.Ast.Node.Index = undefined;
            const root = tree.fullContainerDecl(&container_buffer, .root) orelse return error.InvalidCanonicalSource;
            var out = std.ArrayList(NormalizedToken).empty;
            errdefer {
                for (out.items) |item| allocator.free(item.value);
                out.deinit(allocator);
            }

            var previous_kept_tag: ?std.zig.Token.Tag = null;
            for (root.ast.members) |member| {
                if (!includeEntryCompareMember(tree.*, member, case.entry_symbol)) continue;
                const first = tree.firstToken(member);
                const last = tree.lastToken(member);
                var raw_index: usize = first;
                while (raw_index <= last) : (raw_index += 1) {
                    const token_index: std.zig.Ast.TokenIndex = @intCast(raw_index);
                    const tag = tree.tokenTag(token_index);
                    if (shouldSkipToken(tag)) continue;
                    try out.append(allocator, .{
                        .value = try normalizedTokenValueAlloc(allocator, tree, token_index, previous_kept_tag),
                        .token_index = token_index,
                    });
                    previous_kept_tag = tag;
                }
            }
            if (out.items.len == 0) return error.InvalidCanonicalSource;
            return try out.toOwnedSlice(allocator);
        },
    }
}

const LowerFileBackedSourceTextInput = struct {
    allocator: std.mem.Allocator,
    case: CanonicalCase,
    display_path: []const u8,
    actual_path: []const u8,
    source_text: []const u8,
    expected_status: LowerStatus,
};

/// Lower one file-backed source text without rereading the file from disk.
pub fn lowerFileBackedSourceText(input: LowerFileBackedSourceTextInput) anyerror!LoweredAuthoring {
    const allocator = input.allocator;
    const case = input.case;
    const display_path = input.display_path;
    const actual_path = input.actual_path;
    const source_text = input.source_text;
    const expected_status = input.expected_status;
    if (!sourcePathMatchesExpected(allocator, actual_path, case.source_path)) {
        return rejectedResult(allocator, case, display_path, try diagnosticAt(.{
            .allocator = allocator,
            .display_path = display_path,
            .code = "non_canonical_source_path",
            .message = "source path does not match the canonical repo-owned path for this case",
            .line = 1,
            .column = 1,
        }));
    }
    const source_z = try allocator.dupeZ(u8, source_text);
    defer allocator.free(source_z);
    var tree = try std.zig.Ast.parse(allocator, source_z, .zig);
    defer tree.deinit(allocator);
    if (tree.errors.len != 0) {
        return rejectedResult(allocator, case, display_path, try parseFailureDiagnostic(allocator, display_path, source_z, tree));
    }
    return lowerSourceText(allocator, case, .{
        .display_path = display_path,
        .actual_path = actual_path,
        .source_text = source_text,
        .expected_status = expected_status,
    });
}

fn rejectedResult(
    allocator: std.mem.Allocator,
    case: CanonicalCase,
    display_path: []const u8,
    diagnostics: []const Diagnostic,
) !LoweredAuthoring {
    const source_path = if (diagnostics.len == 0)
        try duplicatedSourcePath(allocator, display_path)
    else
        diagnostics[0].path;
    errdefer if (diagnostics.len == 0) allocator.free(source_path);
    const steps = try allocator.alloc(lowered_machine.Step, 0);
    errdefer allocator.free(steps);
    const feature_flags = try duplicateFeatureFlags(allocator, case.feature_flags);
    errdefer allocator.free(feature_flags);
    return .{
        .case_id = case.case_id,
        .label = case.label,
        .source_path = source_path,
        .surface_kind = case.surface_kind,
        .status = .rejected,
        .canonical_scenario_id = case.scenario_id,
        .expected_transcript = "",
        .steps = steps,
        .feature_flags = feature_flags,
        .diagnostics = diagnostics,
    };
}

fn acceptedResult(
    allocator: std.mem.Allocator,
    case: CanonicalCase,
    display_path: []const u8,
) !LoweredAuthoring {
    _ = display_path;
    const scenario = parity_scenarios.byId(case.scenario_id);
    return .{
        .case_id = case.case_id,
        .label = case.label,
        .source_path = try duplicatedSourcePath(allocator, case.source_path),
        .surface_kind = case.surface_kind,
        .status = case.status,
        .canonical_scenario_id = case.scenario_id,
        .expected_transcript = scenario.expected_transcript,
        .steps = try duplicateSteps(allocator, scenario.steps),
        .feature_flags = try duplicateFeatureFlags(allocator, case.feature_flags),
        .diagnostics = try emptyDiagnostics(allocator),
    };
}

/// Lower one inline source text against one canonical covered case.
pub fn lowerSourceText(
    allocator: std.mem.Allocator,
    case: CanonicalCase,
    input: LowerSourceInput,
) anyerror!LoweredAuthoring {
    if (!sourcePathMatchesExpected(allocator, input.actual_path, case.source_path)) {
        return rejectedResult(allocator, case, input.display_path, try diagnosticAt(.{
            .allocator = allocator,
            .display_path = input.display_path,
            .code = "non_canonical_source_path",
            .message = "source path does not match the canonical repo-owned path for this case",
            .line = 1,
            .column = 1,
        }));
    }

    const source_z = try allocator.dupeZ(u8, input.source_text);
    defer allocator.free(source_z);
    var tree = try std.zig.Ast.parse(allocator, source_z, .zig);
    defer tree.deinit(allocator);

    if (tree.errors.len != 0) {
        return rejectedResult(allocator, case, input.display_path, try parseFailureDiagnostic(allocator, input.display_path, source_z, tree));
    }
    if (!hasTopLevelFunctionNamed(tree, case.entry_symbol)) {
        return rejectedResult(allocator, case, input.display_path, try diagnosticAt(.{
            .allocator = allocator,
            .display_path = input.display_path,
            .code = "entry_missing",
            .message = "entry function was not found at the top level",
            .line = 1,
            .column = 1,
        }));
    }
    if (input.expected_status != case.status) {
        return rejectedResult(allocator, case, input.display_path, try diagnosticAt(.{
            .allocator = allocator,
            .display_path = input.display_path,
            .code = "expected_status_mismatch",
            .message = "requested expected_status does not match the supported status for this case",
            .line = 1,
            .column = 1,
        }));
    }

    const canonical_source = try readCanonicalSource(allocator, case.source_path);
    defer allocator.free(canonical_source);
    if (!sourceTextMatchesCanonicalHash(allocator, case.source_path, canonical_source)) {
        return rejectedResult(allocator, case, case.source_path, try diagnosticAt(.{
            .allocator = allocator,
            .display_path = case.source_path,
            .code = "canonical_source_drift",
            .message = "canonical source on disk no longer matches the frozen admitted baseline for this case",
            .line = 1,
            .column = 1,
        }));
    }
    const canonical_z = try allocator.dupeZ(u8, canonical_source);
    defer allocator.free(canonical_z);
    var canonical_tree = try std.zig.Ast.parse(allocator, canonical_z, .zig);
    defer canonical_tree.deinit(allocator);
    if (canonical_tree.errors.len != 0) {
        return error.InvalidCanonicalSource;
    }

    const actual_tokens = try normalizedComparisonTokensAlloc(allocator, case, source_z, &tree);
    defer freeNormalizedTokens(allocator, actual_tokens);
    const canonical_tokens = try normalizedComparisonTokensAlloc(allocator, case, canonical_z, &canonical_tree);
    defer freeNormalizedTokens(allocator, canonical_tokens);

    if (findMismatch(actual_tokens, canonical_tokens)) |mismatch| {
        const loc: std.zig.Ast.Location = if (mismatch.token_index) |token_index|
            tree.tokenLocation(0, token_index)
        else
            .{ .line = 0, .column = 0, .line_start = 0, .line_end = 0 };
        return rejectedResult(allocator, case, input.display_path, try diagnosticAt(.{
            .allocator = allocator,
            .display_path = input.display_path,
            .code = "structural_mismatch",
            .message = mismatch.message,
            .line = loc.line + 1,
            .column = loc.column + 1,
        }));
    }

    return acceptedResult(allocator, case, input.display_path);
}

/// Lower one file-backed source through the shared authoring lowerer.
pub fn lowerSourceFile(
    allocator: std.mem.Allocator,
    case: CanonicalCase,
    display_path: []const u8,
    actual_path: []const u8,
    expected_status: LowerStatus,
) anyerror!LoweredAuthoring {
    const source = std.fs.cwd().readFileAlloc(allocator, actual_path, 1 << 20) catch {
        return rejectedResult(allocator, case, display_path, try diagnosticAt(.{
            .allocator = allocator,
            .display_path = display_path,
            .code = "source_unreadable",
            .message = "source file could not be read",
            .line = 1,
            .column = 1,
        }));
    };
    defer allocator.free(source);
    return lowerFileBackedSourceText(.{
        .allocator = allocator,
        .case = case,
        .display_path = display_path,
        .actual_path = actual_path,
        .source_text = source,
        .expected_status = expected_status,
    });
}
