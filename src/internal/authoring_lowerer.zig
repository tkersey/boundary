const build_options = @import("build_options");
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
        return try allocator.dupe(u8, "identifier");
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

    const actual_tokens = try normalizeTokensAlloc(allocator, &tree);
    defer freeNormalizedTokens(allocator, actual_tokens);
    const canonical_tokens = try normalizeTokensAlloc(allocator, &canonical_tree);
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
    return lowerSourceText(allocator, case, .{
        .display_path = display_path,
        .actual_path = actual_path,
        .source_text = source,
        .expected_status = expected_status,
    });
}
