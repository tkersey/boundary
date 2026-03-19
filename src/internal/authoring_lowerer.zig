const build_options = @import("authoring_build_options");
const lowered_machine = @import("lowered_machine");
const parity_scenarios = @import("parity_scenarios");
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

pub const CompareScope = enum {
    file,
    entry,
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

fn sourcePathMatchesExpected(allocator: std.mem.Allocator, actual_path: []const u8, expected_path: []const u8) bool {
    const cwd = std.fs.cwd();
    const actual_realpath = cwd.realpathAlloc(allocator, actual_path) catch return false;
    defer allocator.free(actual_realpath);

    var repo_dir = std.fs.openDirAbsolute(build_options.package_root, .{}) catch return false;
    defer repo_dir.close();

    const expected_realpath = repo_dir.realpathAlloc(allocator, expected_path) catch return false;
    defer allocator.free(expected_realpath);
    return std.mem.eql(u8, actual_realpath, expected_realpath);
}

fn readCanonicalSource(allocator: std.mem.Allocator, source_path: []const u8) ![]u8 {
    var repo_dir = try std.fs.openDirAbsolute(build_options.package_root, .{});
    defer repo_dir.close();
    return try repo_dir.readFileAlloc(allocator, source_path, 1 << 20);
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

fn entryFunctionSourceSlice(tree: std.zig.Ast, source: []const u8, name: []const u8) ?[]const u8 {
    var container_buffer: [2]std.zig.Ast.Node.Index = undefined;
    const root = tree.fullContainerDecl(&container_buffer, .root) orelse return null;
    for (root.ast.members) |member| {
        var fn_buffer: [1]std.zig.Ast.Node.Index = undefined;
        const fn_proto = tree.fullFnProto(&fn_buffer, member) orelse continue;
        const name_token = fn_proto.name_token orelse continue;
        if (!std.mem.eql(u8, tree.tokenSlice(name_token), name)) continue;
        const start = tree.tokenStart(fn_proto.firstToken());
        const last = tree.lastToken(member);
        const end = tree.tokenStart(last) + @as(u32, @intCast(tree.tokenSlice(last).len));
        return source[start..end];
    }
    return null;
}

fn diagnosticAt(
    allocator: std.mem.Allocator,
    display_path: []const u8,
    code: []const u8,
    message: []const u8,
    line: usize,
    column: usize,
) std.mem.Allocator.Error![]const Diagnostic {
    const owned_path = try allocator.dupe(u8, display_path);
    errdefer allocator.free(owned_path);
    const diags = try allocator.alloc(Diagnostic, 1);
    diags[0] = .{
        .code = code,
        .message = message,
        .path = owned_path,
        .line = line,
        .column = column,
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
        return diagnosticAt(allocator, display_path, "invalid_source", "authoring lowerer rejected the source before building a lowered result", 1, 1);
    }

    const parse_error = tree.errors[0];
    const loc = tree.tokenLocation(0, parse_error.token);
    _ = source;
    return diagnosticAt(allocator, display_path, "parse_error", @tagName(parse_error.tag), loc.line + 1, loc.column + 1);
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

fn canonicalSourceHash(expected_path: []const u8) ?[32]u8 {
    if (std.mem.eql(u8, expected_path, "test/source_lowering_corpus/fixtures/local_mutation_resume.zig")) return build_options.hash_local_mutation_resume;
    if (std.mem.eql(u8, expected_path, "test/source_lowering_corpus/fixtures/branch_resume.zig")) return build_options.hash_branch_resume;
    if (std.mem.eql(u8, expected_path, "test/source_lowering_corpus/fixtures/loop_resume.zig")) return build_options.hash_loop_resume;
    if (std.mem.eql(u8, expected_path, "test/source_lowering_corpus/fixtures/helper_call_resume.zig")) return build_options.hash_helper_call_resume;
    if (std.mem.eql(u8, expected_path, "test/source_lowering_corpus/fixtures/nested_prompt_static_redelim.zig")) return build_options.hash_nested_prompt_static_redelim;
    if (std.mem.eql(u8, expected_path, "test/source_lowering_corpus/fixtures/typed_error_try.zig")) return build_options.hash_typed_error_try;
    if (std.mem.eql(u8, expected_path, "test/source_lowering_corpus/fixtures/defer_resume.zig")) return build_options.hash_defer_resume;
    if (std.mem.eql(u8, expected_path, "test/source_lowering_corpus/fixtures/errdefer_error.zig")) return build_options.hash_errdefer_error;
    if (std.mem.eql(u8, expected_path, "examples/define_basic.zig")) return build_options.hash_define_basic;
    if (std.mem.eql(u8, expected_path, "examples/define_choice_basic.zig")) return build_options.hash_define_choice_basic;
    if (std.mem.eql(u8, expected_path, "examples/define_abort_basic.zig")) return build_options.hash_define_abort_basic;
    if (std.mem.eql(u8, expected_path, "examples/early_exit.zig")) return build_options.hash_early_exit;
    if (std.mem.eql(u8, expected_path, "examples/generator.zig")) return build_options.hash_generator;
    if (std.mem.eql(u8, expected_path, "examples/resume_or_return.zig")) return build_options.hash_resume_or_return;
    if (std.mem.eql(u8, expected_path, "examples/front_door_workflow.zig")) return build_options.hash_front_door_workflow;
    if (std.mem.eql(u8, expected_path, "examples/nested_workflow.zig")) return build_options.hash_nested_workflow;
    if (std.mem.eql(u8, expected_path, "examples/state_basic.zig")) return build_options.hash_state_basic;
    if (std.mem.eql(u8, expected_path, "examples/reader_basic.zig")) return build_options.hash_reader_basic;
    if (std.mem.eql(u8, expected_path, "examples/optional_basic.zig")) return build_options.hash_optional_basic;
    if (std.mem.eql(u8, expected_path, "examples/exception_basic.zig")) return build_options.hash_exception_basic;
    if (std.mem.eql(u8, expected_path, "examples/resource_basic.zig")) return build_options.hash_resource_basic;
    if (std.mem.eql(u8, expected_path, "examples/writer_basic.zig")) return build_options.hash_writer_basic;
    if (std.mem.eql(u8, expected_path, "examples/algebraic_abortive_validation.zig")) return build_options.hash_algebraic_abortive_validation;
    if (std.mem.eql(u8, expected_path, "examples/algebraic_artifact_search.zig")) return build_options.hash_algebraic_artifact_search;
    if (std.mem.eql(u8, expected_path, "src/witness_sources.zig")) return build_options.hash_witness_sources;
    return null;
}

fn canonicalEntryHash(case: CanonicalCase) ?[32]u8 {
    if (!std.mem.eql(u8, case.source_path, "src/witness_sources.zig")) return null;
    if (std.mem.eql(u8, case.entry_symbol, "runAtmResumeTransform")) return build_options.hash_witness_entry_atm_resume_transform;
    if (std.mem.eql(u8, case.entry_symbol, "runDirectReturn")) return build_options.hash_witness_entry_direct_return;
    if (std.mem.eql(u8, case.entry_symbol, "runResumeOrReturnReturnNow")) return build_options.hash_witness_entry_resume_or_return_return_now;
    if (std.mem.eql(u8, case.entry_symbol, "runResumeOrReturnResume")) return build_options.hash_witness_entry_resume_or_return_resume;
    if (std.mem.eql(u8, case.entry_symbol, "runStaticRedelim")) return build_options.hash_witness_entry_static_redelim;
    if (std.mem.eql(u8, case.entry_symbol, "runMultiPrompt")) return build_options.hash_witness_entry_multi_prompt;
    if (std.mem.eql(u8, case.entry_symbol, "runGenerator")) return build_options.hash_witness_entry_generator;
    return null;
}

fn normalizeSourceForHashAlloc(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
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

fn normalizedComparisonSourceAlloc(
    allocator: std.mem.Allocator,
    case: CanonicalCase,
    source_text: []const u8,
) ?[]u8 {
    switch (case.compare_scope) {
        .file => return normalizeSourceForHashAlloc(allocator, source_text) catch null,
        .entry => {
            const source_z = allocator.dupeZ(u8, source_text) catch return null;
            defer allocator.free(source_z);
            var tree = std.zig.Ast.parse(allocator, source_z, .zig) catch return null;
            defer tree.deinit(allocator);
            if (tree.errors.len != 0) return null;
            const entry_source = entryFunctionSourceSlice(tree, source_z, case.entry_symbol) orelse return null;
            return normalizeSourceForHashAlloc(allocator, entry_source) catch null;
        },
    }
}

fn sourceTextMatchesCanonicalHash(
    allocator: std.mem.Allocator,
    case: CanonicalCase,
    source_text: []const u8,
) bool {
    const expected_hash = switch (case.compare_scope) {
        .file => canonicalSourceHash(case.source_path),
        .entry => canonicalEntryHash(case),
    } orelse return false;
    const normalized = normalizedComparisonSourceAlloc(allocator, case, source_text) orelse return false;
    defer allocator.free(normalized);
    var actual_hash: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(normalized, &actual_hash, .{});
    return std.mem.eql(u8, &actual_hash, &expected_hash);
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
            const entry_source = entryFunctionSourceSlice(tree.*, source, case.entry_symbol) orelse return error.InvalidCanonicalSource;
            const entry_z = try allocator.dupeZ(u8, entry_source);
            defer allocator.free(entry_z);
            var entry_tree = try std.zig.Ast.parse(allocator, entry_z, .zig);
            defer entry_tree.deinit(allocator);
            if (entry_tree.errors.len != 0) return error.InvalidCanonicalSource;
            return normalizeTokensAlloc(allocator, &entry_tree);
        },
    }
}

/// Lower one file-backed source text without rereading the file from disk.
pub fn lowerFileBackedSourceText(
    allocator: std.mem.Allocator,
    case: CanonicalCase,
    display_path: []const u8,
    actual_path: []const u8,
    source_text: []const u8,
    expected_status: LowerStatus,
) anyerror!LoweredAuthoring {
    if (!sourcePathMatchesExpected(allocator, actual_path, case.source_path)) {
        return rejectedResult(allocator, case, display_path, try diagnosticAt(
            allocator,
            display_path,
            "non_canonical_source_path",
            "source path does not match the canonical repo-owned path for this case",
            1,
            1,
        ));
    }
    if (!sourceTextMatchesCanonicalHash(allocator, case, source_text)) {
        return rejectedResult(allocator, case, display_path, try diagnosticAt(
            allocator,
            display_path,
            "canonical_source_drift",
            "source no longer matches the canonical repo-owned source for this case",
            1,
            1,
        ));
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
    const scenario = parity_scenarios.byId(case.scenario_id);
    return .{
        .case_id = case.case_id,
        .label = case.label,
        .source_path = try duplicatedSourcePath(allocator, display_path),
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
        return rejectedResult(allocator, case, input.display_path, try diagnosticAt(
            allocator,
            input.display_path,
            "non_canonical_source_path",
            "source path does not match the canonical repo-owned path for this case",
            1,
            1,
        ));
    }

    const source_z = try allocator.dupeZ(u8, input.source_text);
    defer allocator.free(source_z);
    var tree = try std.zig.Ast.parse(allocator, source_z, .zig);
    defer tree.deinit(allocator);

    if (tree.errors.len != 0) {
        return rejectedResult(allocator, case, input.display_path, try parseFailureDiagnostic(allocator, input.display_path, source_z, tree));
    }
    if (!hasTopLevelFunctionNamed(tree, case.entry_symbol)) {
        return rejectedResult(allocator, case, input.display_path, try diagnosticAt(
            allocator,
            input.display_path,
            "entry_missing",
            "entry function was not found at the top level",
            1,
            1,
        ));
    }
    if (input.expected_status != case.status) {
        return rejectedResult(allocator, case, input.display_path, try diagnosticAt(
            allocator,
            input.display_path,
            "expected_status_mismatch",
            "requested expected_status does not match the supported status for this case",
            1,
            1,
        ));
    }

    const canonical_source = try readCanonicalSource(allocator, case.source_path);
    defer allocator.free(canonical_source);
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
        return rejectedResult(allocator, case, input.display_path, try diagnosticAt(
            allocator,
            input.display_path,
            "structural_mismatch",
            mismatch.message,
            loc.line + 1,
            loc.column + 1,
        ));
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
        return rejectedResult(allocator, case, display_path, try diagnosticAt(
            allocator,
            display_path,
            "source_unreadable",
            "source file could not be read",
            1,
            1,
        ));
    };
    defer allocator.free(source);
    return lowerFileBackedSourceText(allocator, case, display_path, actual_path, source, expected_status);
}
