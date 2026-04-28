const build_options = @import("authoring_build_options");
const effect_ir = @import("effect_ir");
const lowered_machine = @import("lowered_machine");
const parity_scenarios = @import("parity_scenarios");
const program_frontend = @import("program_frontend");
const source_analysis = @import("source_analysis.zig");
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

/// Public file-backed source validation error surface shared by additive and future public lowering.
pub const SourceValidationError = error{
    EntryMissing,
    OutOfMemory,
    ParseError,
    SourceUnreadable,
    TooManyFunctions,
    TooManyFunctionParams,
    TooManyImports,
    TooManyHelperUses,
    TooManyHelperEdges,
    TooManyOpUses,
    UnsupportedEffectAccess,
};
/// Generic same-module source analysis result shared by public lowering and proof adapters.
pub const SameModuleSourceAnalysis = source_analysis.ModuleAnalysis;
/// One top-level function discovered in generic same-module analysis.
pub const SameModuleTopLevelFunction = source_analysis.TopLevelFunction;
/// One same-module helper-call edge discovered in generic same-module analysis.
pub const SameModuleHelperCallEdge = source_analysis.HelperCallEdge;

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

    /// Return the executable kernel program artifact carried by this lowering.
    pub fn kernelProgramArtifact(self: *const LoweredAuthoring) KernelProgramArtifact {
        return .{
            .status = self.status,
            .canonical_scenario_id = self.canonical_scenario_id,
            .expected_transcript = self.expected_transcript,
            .steps = self.steps,
            .feature_flags = self.feature_flags,
        };
    }

    /// Release owned slices captured in a lowered authoring result.
    pub fn deinit(self: *LoweredAuthoring, allocator: std.mem.Allocator) void {
        allocator.free(self.source_path);
        allocator.free(self.steps);
        allocator.free(self.feature_flags);
        allocator.free(self.diagnostics);
        self.* = undefined;
    }
};

/// Executable kernel program artifact produced by the structural authoring lowerer.
pub const KernelProgramArtifact = struct {
    status: LowerStatus,
    canonical_scenario_id: ?parity_scenarios.ScenarioId,
    expected_transcript: []const u8,
    steps: []const lowered_machine.Step,
    feature_flags: []const []const u8,

    /// Return whether this artifact can execute through the lowered kernel.
    pub fn isExecutable(self: KernelProgramArtifact) bool {
        return self.status != .rejected;
    }
};

/// One open-row lowering record lowered through the shared authoring-lowering seam.
pub const OpenRowLoweredAuthoring = struct {
    label: []const u8,
    normalization: effect_ir.NormalizationDigest,
    program: program_frontend.LoweredOpenRowProgram,
};

fn entryFunctionForProgram(comptime program: program_frontend.OpenRowProgram) effect_ir.NormalizeError!effect_ir.Function {
    comptime var found: ?effect_ir.Function = null;
    inline for (program.functions) |function| {
        if (!std.mem.eql(u8, function.symbol.symbol_name, program.entry_symbol)) continue;
        if (program.entry_module_path) |module_path| {
            if (!std.mem.eql(u8, function.symbol.module_path, module_path)) continue;
        }
        if (found != null) return error.DuplicateSymbol;
        found = function;
    }
    return found orelse error.UnknownSymbol;
}

/// Lower one open-row frontend payload through the shared semantic center.
pub fn lowerOpenRowProgram(comptime program: program_frontend.OpenRowProgram) effect_ir.NormalizeError!OpenRowLoweredAuthoring {
    const lowered = try program_frontend.lowerOpenRow(program);
    const entry_function = try entryFunctionForProgram(program);
    return .{
        .label = program.label,
        .normalization = try effect_ir.rowDigest(entry_function.row, entry_function.outputs),
        .program = lowered,
    };
}

test "analyzeSameModuleSourceText exposes generic helper metadata" {
    var analysis = try analyzeSameModuleSourceText(std.testing.allocator,
        \\fn helper() void {}
        \\pub fn run() void {
        \\    helper();
        \\}
    );
    defer analysis.deinit(std.testing.allocator);

    try std.testing.expect(analysis.isParseClean());
    try std.testing.expect(analysis.hasTopLevelFunctionNamed("run"));
    try std.testing.expectEqual(@as(usize, 2), analysis.top_level_functions.len);
    try std.testing.expectEqual(@as(usize, 1), analysis.helper_call_edges.len);
    try std.testing.expectEqualStrings("run", analysis.helper_call_edges[0].caller_name);
    try std.testing.expectEqualStrings("helper", analysis.helper_call_edges[0].callee_name);
}

fn testCanonicalSourceCase() CanonicalCase {
    return .{
        .case_id = "source.branch_resume",
        .label = "source.branch_resume",
        .source_path = "test/source_lowering_corpus/fixtures/branch_resume.zig",
        .entry_symbol = "run",
        .surface_kind = .source_case,
        .status = .canonical,
        .scenario_id = .source_branch_resume,
        .feature_flags = &.{ "if_else", "locals", "resume_value" },
    };
}

test "lowerSourceText rejects mismatched expected_status before canonical fast-path acceptance" {
    const case = testCanonicalSourceCase();
    const source_text = try readCanonicalSource(std.testing.allocator, case.source_path);
    defer std.testing.allocator.free(source_text);
    const actual_path = try resolveRepoSourcePathAlloc(std.testing.allocator, case.source_path);
    defer std.testing.allocator.free(actual_path);

    var lowered = try lowerSourceText(std.testing.allocator, case, .{
        .display_path = case.source_path,
        .actual_path = actual_path,
        .source_text = source_text,
        .expected_status = .candidate_green,
    });
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expectEqual(LowerStatus.rejected, lowered.status);
    try std.testing.expectEqual(@as(usize, 1), lowered.diagnostics.len);
    try std.testing.expectEqualStrings("expected_status_mismatch", lowered.diagnostics[0].code);
}

test "lowerFileBackedSourceText rejects mismatched expected_status before canonical fast-path acceptance" {
    const case = testCanonicalSourceCase();
    const source_text = try readCanonicalSource(std.testing.allocator, case.source_path);
    defer std.testing.allocator.free(source_text);
    const actual_path = try resolveRepoSourcePathAlloc(std.testing.allocator, case.source_path);
    defer std.testing.allocator.free(actual_path);

    var lowered = try lowerFileBackedSourceText(.{
        .allocator = std.testing.allocator,
        .case = case,
        .display_path = case.source_path,
        .actual_path = actual_path,
        .source_text = source_text,
        .expected_status = .candidate_green,
    });
    defer lowered.deinit(std.testing.allocator);

    try std.testing.expectEqual(LowerStatus.rejected, lowered.status);
    try std.testing.expectEqual(@as(usize, 1), lowered.diagnostics.len);
    try std.testing.expectEqualStrings("expected_status_mismatch", lowered.diagnostics[0].code);
}

test "canonical fast-path requires the frozen admitted baseline" {
    const case = testCanonicalSourceCase();
    const canonical_source = try readCanonicalSource(std.testing.allocator, case.source_path);
    defer std.testing.allocator.free(canonical_source);

    try std.testing.expect(sourceTextMatchesFrozenCanonical(std.testing.allocator, case.source_path, canonical_source, canonical_source));

    const drifted = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        canonical_source,
        "answer = resumed + 1;",
        "answer = resumed + 2;",
    );
    defer std.testing.allocator.free(drifted);

    try std.testing.expect(!sourceTextMatchesFrozenCanonical(std.testing.allocator, case.source_path, drifted, drifted));
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
    if (std.Io.Dir.path.isAbsolute(path)) {
        return try std.Io.Dir.path.resolve(allocator, &.{path});
    }
    return try std.Io.Dir.path.resolve(allocator, &.{ base_path, path });
}

fn canonicalRepoRootAlloc(allocator: std.mem.Allocator) ![]u8 {
    const canonical_z = try std.Io.Dir.realPathFileAbsoluteAlloc(
        std.Io.Threaded.global_single_threaded.io(),
        build_options.package_root,
        allocator,
    );
    defer allocator.free(canonical_z);
    return try allocator.dupe(u8, canonical_z);
}

fn normalizeRepoRelativePathAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const normalized = try allocator.dupe(u8, path);
    for (normalized) |*byte| {
        if (byte.* == '/' or byte.* == '\\') byte.* = std.Io.Dir.path.sep;
    }
    return normalized;
}

fn normalizeExpectedCanonicalPathAlloc(
    allocator: std.mem.Allocator,
    canonical_repo_root: []const u8,
    expected_path: []const u8,
) ![]u8 {
    return try std.Io.Dir.path.resolve(allocator, &.{ canonical_repo_root, expected_path });
}

fn repoAliasRootMatchesExpected(
    allocator: std.mem.Allocator,
    normalized_actual: []const u8,
    expected_path: []const u8,
    canonical_repo_root: []const u8,
) bool {
    if (!std.mem.endsWith(u8, normalized_actual, expected_path)) return false;
    if (normalized_actual.len <= expected_path.len) return false;
    if (normalized_actual[normalized_actual.len - expected_path.len - 1] != std.Io.Dir.path.sep) return false;

    var repo_alias_root = normalized_actual[0 .. normalized_actual.len - expected_path.len];
    while (repo_alias_root.len != 0 and repo_alias_root[repo_alias_root.len - 1] == std.Io.Dir.path.sep) {
        repo_alias_root.len -= 1;
    }
    if (repo_alias_root.len == 0) return false;
    if (std.mem.startsWith(u8, repo_alias_root, canonical_repo_root)) {
        if (repo_alias_root.len == canonical_repo_root.len) return false;
        if (repo_alias_root[canonical_repo_root.len] == std.Io.Dir.path.sep) return false;
    }

    const canonical_alias_root = std.Io.Dir.realPathFileAbsoluteAlloc(std.Io.Threaded.global_single_threaded.io(), repo_alias_root, allocator) catch return false;
    defer allocator.free(canonical_alias_root);
    if (!std.mem.eql(u8, canonical_alias_root, canonical_repo_root)) return false;

    const alias_parent = std.Io.Dir.path.dirname(repo_alias_root) orelse return false;
    const canonical_alias_parent = std.Io.Dir.realPathFileAbsoluteAlloc(std.Io.Threaded.global_single_threaded.io(), alias_parent, allocator) catch return false;
    defer allocator.free(canonical_alias_parent);

    if (std.mem.startsWith(u8, canonical_alias_parent, canonical_repo_root)) {
        if (canonical_alias_parent.len == canonical_repo_root.len) return false;
        if (canonical_alias_parent[canonical_repo_root.len] == std.Io.Dir.path.sep) return false;
    }
    return true;
}

fn sourcePathMatchesExpected(allocator: std.mem.Allocator, actual_path: []const u8, expected_path: []const u8) bool {
    const io = std.Io.Threaded.global_single_threaded.io();
    const cwd_path = std.process.currentPathAlloc(io, allocator) catch return false;
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
    const io = std.Io.Threaded.global_single_threaded.io();
    var repo_dir = try std.Io.Dir.openDirAbsolute(io, build_options.package_root, .{});
    defer repo_dir.close(io);
    return try repo_dir.readFileAlloc(io, source_path, allocator, .limited(1 << 20));
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

/// Return whether one caller-provided source text exactly matches the current canonical file bytes.
pub fn sourceTextMatchesCanonicalSource(
    allocator: std.mem.Allocator,
    expected_path: []const u8,
    source_text: []const u8,
) bool {
    const canonical_path = resolveRepoSourcePathAlloc(allocator, expected_path) catch return false;
    defer allocator.free(canonical_path);
    const canonical_source = std.Io.Dir.cwd().readFileAlloc(
        std.Io.Threaded.global_single_threaded.io(),
        canonical_path,
        allocator,
        .limited(1 << 20),
    ) catch return false;
    defer allocator.free(canonical_source);
    return std.mem.eql(u8, canonical_source, source_text);
}

fn sourceTextMatchesFrozenCanonical(
    allocator: std.mem.Allocator,
    expected_path: []const u8,
    canonical_source: []const u8,
    source_text: []const u8,
) bool {
    return std.mem.eql(u8, canonical_source, source_text) and
        sourceTextMatchesCanonicalHash(allocator, expected_path, canonical_source);
}

fn sourceTextMatchesAcceptedCanonicalSource(
    allocator: std.mem.Allocator,
    expected_path: []const u8,
    source_text: []const u8,
) bool {
    const canonical_source = readCanonicalSource(allocator, expected_path) catch return false;
    defer allocator.free(canonical_source);
    return sourceTextMatchesFrozenCanonical(allocator, expected_path, canonical_source, source_text);
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
    const fn_name = source_analysis.topLevelFunctionName(tree, member) orelse return true;
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

/// Validate that one file-backed source parses and exposes the requested top-level entry symbol.
pub fn validateFileBackedSourceEntry(
    allocator: std.mem.Allocator,
    actual_path: []const u8,
    entry_symbol: []const u8,
) SourceValidationError!void {
    var analysis = try analyzeFileBackedSource(allocator, actual_path);
    defer analysis.deinit(allocator);
    try requireEntrySymbol(&analysis, entry_symbol);
}

/// Analyze one same-module source buffer without any proof-corpus admission checks.
pub fn analyzeSameModuleSourceText(
    allocator: std.mem.Allocator,
    source_text: []const u8,
) SourceValidationError!SameModuleSourceAnalysis {
    return try source_analysis.analyzeModuleSource(allocator, source_text);
}

/// Analyze one file-backed same-module source file without proof-corpus admission checks.
pub fn analyzeFileBackedSource(
    allocator: std.mem.Allocator,
    actual_path: []const u8,
) SourceValidationError!SameModuleSourceAnalysis {
    const source = std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), actual_path, allocator, .limited(1 << 20)) catch {
        return error.SourceUnreadable;
    };
    defer allocator.free(source);

    return try analyzeSameModuleSourceText(allocator, source);
}

fn requireEntrySymbol(
    analysis: *const SameModuleSourceAnalysis,
    entry_symbol: []const u8,
) SourceValidationError!void {
    if (!analysis.isParseClean()) return error.ParseError;
    if (!analysis.hasTopLevelFunctionNamed(entry_symbol)) return error.EntryMissing;
}

fn tokenLiteralKind(tag: std.zig.Token.Tag) bool {
    return tag == .number_literal or
        tag == .string_literal or
        tag == .multiline_string_literal_line or
        tag == .char_literal or
        tag == .builtin;
}

fn shouldSkipToken(tag: std.zig.Token.Tag) bool {
    return tag == .doc_comment or tag == .container_doc_comment;
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
            .message = "source differs from the registered lowering pattern for this case; use the registered source file or update the case registry and baseline before rerunning",
        };
    }
    if (actual.len != canonical.len) {
        return .{
            .token_index = if (actual.len == 0) null else actual[actual.len - 1].token_index,
            .message = "source token stream differs from the registered lowering pattern for this case; use the registered source file or update the case registry and baseline before rerunning",
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
                token_loop: while (raw_index <= last) : (raw_index += 1) {
                    const token_index: std.zig.Ast.TokenIndex = @intCast(raw_index);
                    const tag = tree.tokenTag(token_index);
                    if (shouldSkipToken(tag)) continue :token_loop;
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
    const expected_path = resolveRepoSourcePathAlloc(allocator, case.source_path) catch null;
    defer if (expected_path) |path| allocator.free(path);
    const exact_canonical_path = if (expected_path) |path| std.mem.eql(u8, actual_path, path) else false;

    if (!exact_canonical_path and !sourcePathMatchesExpected(allocator, actual_path, case.source_path)) {
        return rejectedResult(allocator, case, display_path, try diagnosticAt(.{
            .allocator = allocator,
            .display_path = display_path,
            .code = "non_canonical_source_path",
            .message = "source path is not the expected path for this case; pass the canonical repo file or an alias that resolves to it",
            .line = 1,
            .column = 1,
        }));
    }
    if (expected_status != case.status) {
        return rejectedExpectedStatusMismatch(allocator, case, display_path);
    }
    if (sourceTextMatchesAcceptedCanonicalSource(allocator, case.source_path, source_text)) {
        return acceptedResult(allocator, case, display_path);
    }
    var analysis = try analyzeSameModuleSourceText(allocator, source_text);
    defer analysis.deinit(allocator);
    return lowerAnalyzedSourceText(allocator, case, .{
        .display_path = display_path,
        .actual_path = actual_path,
        .source_text = source_text,
        .expected_status = expected_status,
    }, &analysis);
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

fn rejectedExpectedStatusMismatch(
    allocator: std.mem.Allocator,
    case: CanonicalCase,
    display_path: []const u8,
) !LoweredAuthoring {
    return rejectedResult(allocator, case, display_path, try diagnosticAt(.{
        .allocator = allocator,
        .display_path = display_path,
        .code = "expected_status_mismatch",
        .message = "requested support status does not match the registered status for this case",
        .line = 1,
        .column = 1,
    }));
}

/// Lower one inline source text against one canonical covered case.
pub fn lowerSourceText(
    allocator: std.mem.Allocator,
    case: CanonicalCase,
    input: LowerSourceInput,
) anyerror!LoweredAuthoring {
    const expected_path = resolveRepoSourcePathAlloc(allocator, case.source_path) catch null;
    defer if (expected_path) |path| allocator.free(path);
    const exact_canonical_path = if (expected_path) |path| std.mem.eql(u8, input.actual_path, path) else false;

    if (!exact_canonical_path and !sourcePathMatchesExpected(allocator, input.actual_path, case.source_path)) {
        return rejectedResult(allocator, case, input.display_path, try diagnosticAt(.{
            .allocator = allocator,
            .display_path = input.display_path,
            .code = "non_canonical_source_path",
            .message = "source path is not the expected path for this case; pass the canonical repo file or an alias that resolves to it",
            .line = 1,
            .column = 1,
        }));
    }
    if (input.expected_status != case.status) {
        return rejectedExpectedStatusMismatch(allocator, case, input.display_path);
    }
    if (sourceTextMatchesAcceptedCanonicalSource(allocator, case.source_path, input.source_text)) {
        return acceptedResult(allocator, case, input.display_path);
    }
    var analysis = try analyzeSameModuleSourceText(allocator, input.source_text);
    defer analysis.deinit(allocator);
    return lowerAnalyzedSourceText(allocator, case, input, &analysis);
}

fn lowerAnalyzedSourceText(
    allocator: std.mem.Allocator,
    case: CanonicalCase,
    input: LowerSourceInput,
    analysis: *const SameModuleSourceAnalysis,
) anyerror!LoweredAuthoring {
    if (!sourcePathMatchesExpected(allocator, input.actual_path, case.source_path)) {
        return rejectedResult(allocator, case, input.display_path, try diagnosticAt(.{
            .allocator = allocator,
            .display_path = input.display_path,
            .code = "non_canonical_source_path",
            .message = "source path is not the expected path for this case; pass the canonical repo file or an alias that resolves to it",
            .line = 1,
            .column = 1,
        }));
    }

    if (!analysis.isParseClean()) {
        return rejectedResult(allocator, case, input.display_path, try parseFailureDiagnostic(
            allocator,
            input.display_path,
            analysis.parsed.source_z,
            analysis.parsed.tree,
        ));
    }
    if (!analysis.hasTopLevelFunctionNamed(case.entry_symbol)) {
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
            .message = "requested support status does not match the registered status for this case",
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
            .message = "registered source on disk differs from the admitted baseline; regenerate the baseline or update the registry before lowering",
            .line = 1,
            .column = 1,
        }));
    }
    const canonical_z = try allocator.dupeSentinel(u8, canonical_source, 0);
    defer allocator.free(canonical_z);
    var canonical_tree = try std.zig.Ast.parse(allocator, canonical_z, .zig);
    defer canonical_tree.deinit(allocator);
    if (canonical_tree.errors.len != 0) {
        return error.InvalidCanonicalSource;
    }

    const actual_tokens = try normalizedComparisonTokensAlloc(allocator, case, analysis.parsed.source_z, &analysis.parsed.tree);
    defer freeNormalizedTokens(allocator, actual_tokens);
    const canonical_tokens = try normalizedComparisonTokensAlloc(allocator, case, canonical_z, &canonical_tree);
    defer freeNormalizedTokens(allocator, canonical_tokens);

    if (findMismatch(actual_tokens, canonical_tokens)) |mismatch| {
        const loc: std.zig.Ast.Location = if (mismatch.token_index) |token_index|
            analysis.parsed.tree.tokenLocation(0, token_index)
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
    const expected_path = resolveRepoSourcePathAlloc(allocator, case.source_path) catch null;
    defer if (expected_path) |path| allocator.free(path);
    const exact_canonical_path = if (expected_path) |path| std.mem.eql(u8, actual_path, path) else false;

    if (!exact_canonical_path and !sourcePathMatchesExpected(allocator, actual_path, case.source_path)) {
        return rejectedResult(allocator, case, display_path, try diagnosticAt(.{
            .allocator = allocator,
            .display_path = display_path,
            .code = "non_canonical_source_path",
            .message = "source path is not the expected path for this case; pass the canonical repo file or an alias that resolves to it",
            .line = 1,
            .column = 1,
        }));
    }
    const source = std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), actual_path, allocator, .limited(1 << 20)) catch {
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
