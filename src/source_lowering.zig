const authoring_lowerer = @import("authoring_lowerer");
const effect_ir = @import("effect_ir");
const error_witness = @import("error_witness");
const lowered_machine = @import("lowered_machine");
const parity_scenarios = @import("parity_scenarios");
const program_frontend = @import("program_frontend");
const shipped_open_row_corpus = @import("shipped_open_row_corpus_registry");
const source_registry = @import("source_lowering_registry");
const std = @import("std");

/// Source classification for one restricted source-lowering request.
pub const SurfaceKind = enum {
    effect,
    example,
    source_case,
    user_defined_effect,
    witness,
};

/// Progress state for one source-lowering result.
pub const LowerStatus = authoring_lowerer.LowerStatus;

/// One source-lowering diagnostic with source location.
pub const Diagnostic = authoring_lowerer.Diagnostic;

/// One lowered-machine step emitted through the source-lowering surface.
pub const Step = lowered_machine.Step;

/// Executable kernel program artifact carried by a source-lowering result.
pub const KernelProgramArtifact = authoring_lowerer.KernelProgramArtifact;

/// Generic same-module source analysis seam exposed without proof-corpus coupling.
pub const SourceValidationError = authoring_lowerer.SourceValidationError;
/// Generic same-module source analysis result exposed without proof-corpus coupling.
pub const SameModuleSourceAnalysis = authoring_lowerer.SameModuleSourceAnalysis;
/// One top-level function discovered by the generic same-module source analyzer.
pub const SameModuleTopLevelFunction = authoring_lowerer.SameModuleTopLevelFunction;
/// One same-module helper-call edge discovered by the generic same-module source analyzer.
pub const SameModuleHelperCallEdge = authoring_lowerer.SameModuleHelperCallEdge;

/// Input specification for one restricted source-lowering request.
pub const Spec = struct {
    case_id: []const u8,
    source_path: []const u8,
    entry_symbol: []const u8,
    surface_kind: SurfaceKind,
    expected_status: LowerStatus = .canonical,
};
/// Generated source-lowering result plus one executable kernel program artifact.
pub const GeneratedProgram = struct {
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
    error_witness: error_witness.ErrorWitnessV1,

    /// Return the executable kernel program artifact for this lowered result.
    pub fn kernelProgramArtifact(self: *const GeneratedProgram) KernelProgramArtifact {
        return .{
            .status = self.status,
            .canonical_scenario_id = self.canonical_scenario_id,
            .expected_transcript = self.expected_transcript,
            .steps = self.steps,
            .feature_flags = self.feature_flags,
        };
    }

    /// Release dynamically allocated slices owned by this generated program.
    pub fn deinit(self: *GeneratedProgram, allocator: std.mem.Allocator) void {
        allocator.free(self.source_path);
        allocator.free(self.steps);
        allocator.free(self.feature_flags);
        allocator.free(self.diagnostics);
        if (self.error_witness.diagnostics.len != 0) allocator.free(self.error_witness.diagnostics);
        self.* = undefined;
    }

    /// Return whether the source was accepted by the restricted lowerer.
    pub fn isAccepted(self: GeneratedProgram) bool {
        return self.kernelProgramArtifact().isExecutable();
    }
};

/// One open-row lowering record that keeps the resolved Effect IR plus its normalization proof.
pub const OpenRowGeneratedProgram = struct {
    label: []const u8,
    normalization: effect_ir.NormalizationDigest,
    program: program_frontend.LoweredOpenRowProgram,
};

/// Lower one open-row frontend payload into the Effect IR shell and capture its normalization digest.
pub fn lowerOpenRowProgram(comptime program: program_frontend.OpenRowProgram) effect_ir.NormalizeError!OpenRowGeneratedProgram {
    const lowered = try authoring_lowerer.lowerOpenRowProgram(program);
    return .{
        .label = lowered.label,
        .normalization = lowered.normalization,
        .program = lowered.program,
    };
}

/// Analyze one same-module source buffer without proof-corpus admission checks.
pub fn analyzeSameModuleSourceText(
    allocator: std.mem.Allocator,
    source_text: []const u8,
) SourceValidationError!SameModuleSourceAnalysis {
    return try authoring_lowerer.analyzeSameModuleSourceText(allocator, source_text);
}

/// Analyze one file-backed same-module source file without proof-corpus admission checks.
pub fn analyzeFileBackedSource(
    allocator: std.mem.Allocator,
    actual_path: []const u8,
) SourceValidationError!SameModuleSourceAnalysis {
    return try authoring_lowerer.analyzeFileBackedSource(allocator, actual_path);
}

/// Validate that one file-backed source parses and exposes the requested top-level entry symbol.
pub fn validateFileBackedSourceEntry(
    allocator: std.mem.Allocator,
    actual_path: []const u8,
    entry_symbol: []const u8,
) SourceValidationError!void {
    return try authoring_lowerer.validateFileBackedSourceEntry(allocator, actual_path, entry_symbol);
}

/// Error surface for source-lowering entrypoints.
pub const LowerError = anyerror;

const SupportedCase = struct {
    case_id: []const u8,
    label: []const u8,
    source_path: []const u8,
    scenario_id: parity_scenarios.ScenarioId,
    status: LowerStatus,
    entry_symbol: []const u8 = "run",
    compare_scope: authoring_lowerer.CompareScope = .file,
    feature_flags: []const []const u8,
};

test "lowerOpenRowProgram preserves label and normalization digest" {
    const row = effect_ir.rowFromSpec(.{
        .state = .{
            .get = effect_ir.Transform(void, i32),
            .set = effect_ir.Transform(i32, void),
        },
        .writer = .{
            .tell = effect_ir.Transform([]const u8, void),
        },
    });
    const program = try lowerOpenRowProgram(.{
        .label = "example.open_row_state_writer",
        .entry_symbol = "runBody",
        .functions = &.{.{
            .symbol = .{
                .module_path = "examples/open_row_state_writer.zig",
                .symbol_name = "runBody",
            },
            .row = row,
            .outputs = &.{
                .{ .label = "state", .OutputType = i32 },
                .{ .label = "writer", .OutputType = [][]const u8 },
            },
        }},
        .call_edges = &.{},
    });

    try std.testing.expectEqualStrings("example.open_row_state_writer", program.label);
    try std.testing.expectEqual(@as(usize, 2), program.normalization.requirement_count);
    try std.testing.expectEqual(@as(usize, 3), program.normalization.op_count);
    try std.testing.expectEqual(@as(usize, 2), program.normalization.output_count);
    try std.testing.expectEqual(@as(usize, 1), program.program.functions.len);
    try std.testing.expectEqual(@as(usize, 0), program.program.entry_index);
    try std.testing.expectEqualStrings("runBody", program.program.functions[0].symbol.symbol_name);
    _ = program_frontend;
}

test "analyzeSameModuleSourceText stays generic and same-module only" {
    var analysis = try analyzeSameModuleSourceText(std.testing.allocator,
        \\fn helper() void {}
        \\pub fn run() void {
        \\    helper();
        \\}
    );
    defer analysis.deinit(std.testing.allocator);

    try std.testing.expect(analysis.isParseClean());
    try std.testing.expect(analysis.hasTopLevelFunctionNamed("run"));
    try std.testing.expectEqual(@as(usize, 1), analysis.helper_call_edges.len);
    try std.testing.expectEqualStrings("run", analysis.helper_call_edges[0].caller_name);
    try std.testing.expectEqualStrings("helper", analysis.helper_call_edges[0].callee_name);
}

test "analyzeSameModuleSourceText propagates same-module graph limits" {
    const source = comptime blk: {
        var text = "";
        for (0..65) |index| {
            text = text ++ std.fmt.comptimePrint("const dep{d} = @import(\"dep{d}.zig\");\n", .{ index, index });
        }
        break :blk text ++
            \\pub fn run() void {}
        ;
    };

    try std.testing.expectError(error.TooManyImports, analyzeSameModuleSourceText(std.testing.allocator, source));
}

fn sourceCaseFeatureFlags(case_id: []const u8) []const []const u8 {
    if (std.mem.eql(u8, case_id, "source.local_mutation_resume")) return &.{ "locals", "mutation", "resume_value" };
    if (std.mem.eql(u8, case_id, "source.branch_resume")) return &.{ "if_else", "locals", "resume_value" };
    if (std.mem.eql(u8, case_id, "source.loop_resume")) return &.{ "while_loop", "locals", "resume_value" };
    if (std.mem.eql(u8, case_id, "source.helper_call_resume")) return &.{ "same_module_helper", "resume_value", "calls" };
    if (std.mem.eql(u8, case_id, "source.nested_prompt_static_redelim")) return &.{ "nested_helpers", "static_redelim_shape", "calls" };
    if (std.mem.eql(u8, case_id, "source.typed_error_try")) return &.{ "typed_error", "try", "catch" };
    if (std.mem.eql(u8, case_id, "source.defer_resume")) return &.{ "defer", "resume_value", "helper_body" };
    if (std.mem.eql(u8, case_id, "source.errdefer_error")) return &.{ "errdefer", "error_path", "helper_body" };
    unreachable;
}

fn customScenarioId(kind: shipped_open_row_corpus.CustomExampleKind) parity_scenarios.ScenarioId {
    return switch (kind) {
        .transform_basic => .define_basic,
        .choice_basic => .define_choice_basic,
        .abort_basic => .define_abort_basic,
        .workflow => .front_door_workflow,
        .abortive_validation => .algebraic_abortive_validation,
        .artifact_search => .algebraic_artifact_search,
        .generator => .generator,
    };
}

fn customFeatureFlags(kind: shipped_open_row_corpus.CustomExampleKind) []const []const u8 {
    return switch (kind) {
        .transform_basic => &.{ "generated_transform", "user_defined_effect", "open_row", "source_canonical" },
        .choice_basic => &.{ "generated_choice", "user_defined_effect", "open_row", "source_canonical" },
        .abort_basic => &.{ "generated_abort", "user_defined_effect", "open_row", "source_canonical" },
        .workflow => &.{ "generated_transform", "generated_choice", "open_row", "source_canonical" },
        .abortive_validation => &.{ "generated_abort", "user_defined_effect", "open_row", "source_canonical" },
        .artifact_search => &.{ "generated_transform", "user_defined_effect", "open_row", "source_canonical" },
        .generator => &.{ "state_effect", "writer_effect", "open_row", "source_canonical" },
    };
}

fn customLabel(comptime row: shipped_open_row_corpus.CustomExample) []const u8 {
    return std.fmt.comptimePrint("source.{s}", .{row.example_case_id});
}

const boom_error_names = [_][]const u8{"Boom"};
const typed_error_contributors = [_]error_witness.Contributor{
    .{
        .kind = .body,
        .surface = .ordinary,
        .symbol = "fail",
        .error_names = boom_error_names[0..],
    },
};

const errdefer_error_contributors = [_]error_witness.Contributor{
    .{
        .kind = .body,
        .surface = .ordinary,
        .symbol = "body",
        .error_names = boom_error_names[0..],
    },
};

const WitnessTemplate = struct {
    setup_error_names: []const []const u8,
    semantic_error_names: []const []const u8,
    contributors: []const error_witness.Contributor,
};

fn sourceSupportedCase(case: *const source_registry.Case) SupportedCase {
    return .{
        .case_id = case.case_id,
        .label = case.label,
        .source_path = case.fixture_path,
        .scenario_id = case.scenario_id,
        .status = switch (case.status) {
            .candidate_green => .candidate_green,
            .parity_green => .parity_green,
            .canonical => .canonical,
        },
        .feature_flags = sourceCaseFeatureFlags(case.case_id),
    };
}

fn setupHasOutOfMemory(surface_kind: SurfaceKind) bool {
    return switch (surface_kind) {
        .source_case => false,
        .example, .effect, .user_defined_effect, .witness => true,
    };
}

fn witnessTemplate(spec: Spec, case: SupportedCase) WitnessTemplate {
    if (std.mem.eql(u8, case.case_id, "source.typed_error_try")) return .{
        .setup_error_names = error_witness.setupErrorNames(setupHasOutOfMemory(spec.surface_kind)),
        .semantic_error_names = boom_error_names[0..],
        .contributors = typed_error_contributors[0..],
    };
    if (std.mem.eql(u8, case.case_id, "source.errdefer_error")) return .{
        .setup_error_names = error_witness.setupErrorNames(setupHasOutOfMemory(spec.surface_kind)),
        .semantic_error_names = boom_error_names[0..],
        .contributors = errdefer_error_contributors[0..],
    };
    return .{
        .setup_error_names = error_witness.setupErrorNames(setupHasOutOfMemory(spec.surface_kind)),
        .semantic_error_names = error_witness.no_error_names[0..],
        .contributors = error_witness.no_contributors[0..],
    };
}

fn rejectedWitnessTemplate(spec: Spec) WitnessTemplate {
    _ = spec;
    return .{
        .setup_error_names = error_witness.no_error_names[0..],
        .semantic_error_names = error_witness.no_error_names[0..],
        .contributors = error_witness.no_contributors[0..],
    };
}

fn promotedSupportedCase(case_id: []const u8, surface_kind: SurfaceKind) ?SupportedCase {
    if (surface_kind == .example) {
        inline for (shipped_open_row_corpus.custom_examples) |row| {
            if (std.mem.eql(u8, case_id, row.example_case_id)) return .{
                .case_id = case_id,
                .label = customLabel(row),
                .source_path = row.source_path,
                .scenario_id = customScenarioId(row.kind),
                .status = .canonical,
                .feature_flags = customFeatureFlags(row.kind),
            };
        }
        if (std.mem.eql(u8, case_id, "example.early_exit")) return .{
            .case_id = case_id,
            .label = "source.example.early_exit",
            .source_path = "examples/early_exit.zig",
            .scenario_id = .early_exit,
            .status = .canonical,
            .feature_flags = &.{ "lexical_exception", "direct_return", "promoted_example" },
        };
        if (std.mem.eql(u8, case_id, "example.resume_or_return")) return .{
            .case_id = case_id,
            .label = "source.example.resume_or_return",
            .source_path = "examples/resume_or_return.zig",
            .scenario_id = .resume_or_return,
            .status = .canonical,
            .feature_flags = &.{ "lexical_optional", "return_now", "resume_with", "promoted_example" },
        };
        if (std.mem.eql(u8, case_id, "example.nested_workflow")) return .{
            .case_id = case_id,
            .label = "source.example.nested_workflow",
            .source_path = "examples/nested_workflow.zig",
            .scenario_id = .nested_workflow_publish,
            .status = .canonical,
            .feature_flags = &.{ "lexical_optional", "nested_workflow", "promoted_example" },
        };
        if (std.mem.eql(u8, case_id, "example.state_basic")) return .{
            .case_id = case_id,
            .label = "source.example.state_basic",
            .source_path = "examples/state_basic.zig",
            .scenario_id = .state_basic,
            .status = .canonical,
            .feature_flags = &.{ "state_effect", "lexical_effect", "promoted_cohort_a" },
        };
        if (std.mem.eql(u8, case_id, "example.reader_basic")) return .{
            .case_id = case_id,
            .label = "source.example.reader_basic",
            .source_path = "examples/reader_basic.zig",
            .scenario_id = .reader_basic,
            .status = .canonical,
            .feature_flags = &.{ "reader_effect", "lexical_effect", "promoted_cohort_a" },
        };
        if (std.mem.eql(u8, case_id, "example.optional_basic")) return .{
            .case_id = case_id,
            .label = "source.example.optional_basic",
            .source_path = "examples/optional_basic.zig",
            .scenario_id = .optional_basic,
            .status = .canonical,
            .feature_flags = &.{ "optional_effect", "lexical_effect", "promoted_cohort_a" },
        };
        if (std.mem.eql(u8, case_id, "example.exception_basic")) return .{
            .case_id = case_id,
            .label = "source.example.exception_basic",
            .source_path = "examples/exception_basic.zig",
            .scenario_id = .exception_basic,
            .status = .canonical,
            .feature_flags = &.{ "exception_effect", "lexical_effect", "promoted_cohort_a" },
        };
        if (std.mem.eql(u8, case_id, "example.resource_basic")) return .{
            .case_id = case_id,
            .label = "source.example.resource_basic",
            .source_path = "examples/resource_basic.zig",
            .scenario_id = .resource_basic,
            .status = .canonical,
            .feature_flags = &.{ "resource_effect", "lexical_effect", "source_canonical" },
        };
        if (std.mem.eql(u8, case_id, "example.writer_basic")) return .{
            .case_id = case_id,
            .label = "source.example.writer_basic",
            .source_path = "examples/writer_basic.zig",
            .scenario_id = .writer_basic,
            .status = .canonical,
            .feature_flags = &.{ "writer_effect", "lexical_effect", "source_canonical" },
        };
    }
    if (surface_kind == .effect) {
        if (std.mem.eql(u8, case_id, "effect.state_basic")) return .{
            .case_id = case_id,
            .label = "source.effect.state_basic",
            .source_path = "examples/state_basic.zig",
            .scenario_id = .state_basic,
            .status = .canonical,
            .feature_flags = &.{ "state_effect", "lexical_effect", "promoted_cohort_a" },
        };
        if (std.mem.eql(u8, case_id, "effect.reader_basic")) return .{
            .case_id = case_id,
            .label = "source.effect.reader_basic",
            .source_path = "examples/reader_basic.zig",
            .scenario_id = .reader_basic,
            .status = .canonical,
            .feature_flags = &.{ "reader_effect", "lexical_effect", "promoted_cohort_a" },
        };
        if (std.mem.eql(u8, case_id, "effect.optional_basic")) return .{
            .case_id = case_id,
            .label = "source.effect.optional_basic",
            .source_path = "examples/optional_basic.zig",
            .scenario_id = .optional_basic,
            .status = .canonical,
            .feature_flags = &.{ "optional_effect", "lexical_effect", "promoted_cohort_a" },
        };
        if (std.mem.eql(u8, case_id, "effect.exception_basic")) return .{
            .case_id = case_id,
            .label = "source.effect.exception_basic",
            .source_path = "examples/exception_basic.zig",
            .scenario_id = .exception_basic,
            .status = .canonical,
            .feature_flags = &.{ "exception_effect", "lexical_effect", "promoted_cohort_a" },
        };
        if (std.mem.eql(u8, case_id, "effect.resource_basic")) return .{
            .case_id = case_id,
            .label = "source.effect.resource_basic",
            .source_path = "examples/resource_basic.zig",
            .scenario_id = .resource_basic,
            .status = .canonical,
            .feature_flags = &.{ "resource_effect", "lexical_effect", "source_canonical" },
        };
        if (std.mem.eql(u8, case_id, "effect.writer_basic")) return .{
            .case_id = case_id,
            .label = "source.effect.writer_basic",
            .source_path = "examples/writer_basic.zig",
            .scenario_id = .writer_basic,
            .status = .canonical,
            .feature_flags = &.{ "writer_effect", "lexical_effect", "source_canonical" },
        };
    }
    if (surface_kind == .user_defined_effect) {
        inline for (shipped_open_row_corpus.custom_examples) |row| {
            const user_defined_case_id = row.user_defined_case_id orelse continue;
            if (std.mem.eql(u8, case_id, user_defined_case_id)) return .{
                .case_id = case_id,
                .label = std.fmt.comptimePrint("source.{s}", .{user_defined_case_id}),
                .source_path = row.source_path,
                .scenario_id = customScenarioId(row.kind),
                .status = .canonical,
                .feature_flags = customFeatureFlags(row.kind),
            };
        }
    }
    if (surface_kind == .witness) {
        if (std.mem.eql(u8, case_id, "witness.atm_resume_transform")) return .{
            .case_id = case_id,
            .label = "source.witness.atm_resume_transform",
            .source_path = "src/witness_sources.zig",
            .scenario_id = .atm_resume_transform,
            .status = .canonical,
            .entry_symbol = "runAtmResumeTransform",
            .compare_scope = .entry,
            .feature_flags = &.{ "witness", "transform", "source_canonical" },
        };
        if (std.mem.eql(u8, case_id, "witness.direct_return")) return .{
            .case_id = case_id,
            .label = "source.witness.direct_return",
            .source_path = "src/witness_sources.zig",
            .scenario_id = .direct_return,
            .status = .canonical,
            .entry_symbol = "runDirectReturn",
            .compare_scope = .entry,
            .feature_flags = &.{ "witness", "abort", "source_canonical" },
        };
        if (std.mem.eql(u8, case_id, "witness.multi_prompt")) return .{
            .case_id = case_id,
            .label = "source.witness.multi_prompt",
            .source_path = "src/witness_sources.zig",
            .scenario_id = .multi_prompt,
            .status = .canonical,
            .entry_symbol = "runMultiPrompt",
            .compare_scope = .entry,
            .feature_flags = &.{ "witness", "multi_prompt", "source_canonical" },
        };
        if (std.mem.eql(u8, case_id, "witness.resume_or_return_return_now")) return .{
            .case_id = case_id,
            .label = "source.witness.resume_or_return_return_now",
            .source_path = "src/witness_sources.zig",
            .scenario_id = .resume_or_return_return_now,
            .status = .canonical,
            .entry_symbol = "runResumeOrReturnReturnNow",
            .compare_scope = .entry,
            .feature_flags = &.{ "witness", "choice_return_now", "source_canonical" },
        };
        if (std.mem.eql(u8, case_id, "witness.resume_or_return_resume")) return .{
            .case_id = case_id,
            .label = "source.witness.resume_or_return_resume",
            .source_path = "src/witness_sources.zig",
            .scenario_id = .resume_or_return_resume,
            .status = .canonical,
            .entry_symbol = "runResumeOrReturnResume",
            .compare_scope = .entry,
            .feature_flags = &.{ "witness", "choice_resume", "source_canonical" },
        };
        if (std.mem.eql(u8, case_id, "witness.static_redelim")) return .{
            .case_id = case_id,
            .label = "source.witness.static_redelim",
            .source_path = "src/witness_sources.zig",
            .scenario_id = .static_redelim,
            .status = .canonical,
            .entry_symbol = "runStaticRedelim",
            .compare_scope = .entry,
            .feature_flags = &.{ "witness", "static_redelim", "source_canonical" },
        };
        if (std.mem.eql(u8, case_id, "witness.generator")) return .{
            .case_id = case_id,
            .label = "source.witness.generator",
            .source_path = "src/witness_sources.zig",
            .scenario_id = .generator,
            .status = .canonical,
            .entry_symbol = "runGenerator",
            .compare_scope = .entry,
            .feature_flags = &.{ "witness", "generator", "source_canonical" },
        };
    }
    return null;
}

fn loweringSurfaceKind(surface_kind: SurfaceKind) authoring_lowerer.SurfaceKind {
    return switch (surface_kind) {
        .effect => .effect,
        .example => .example,
        .source_case => .source_case,
        .user_defined_effect => .user_defined_effect,
        .witness => .witness,
    };
}

fn loweringCase(spec: Spec, case: SupportedCase) authoring_lowerer.CanonicalCase {
    return .{
        .case_id = case.case_id,
        .label = case.label,
        .source_path = case.source_path,
        .entry_symbol = case.entry_symbol,
        .compare_scope = case.compare_scope,
        .surface_kind = loweringSurfaceKind(spec.surface_kind),
        .status = case.status,
        .scenario_id = case.scenario_id,
        .feature_flags = case.feature_flags,
    };
}

fn duplicateFeatureFlags(allocator: std.mem.Allocator, flags: []const []const u8) std.mem.Allocator.Error![]const []const u8 {
    const duped = try allocator.alloc([]const u8, flags.len);
    for (flags, 0..) |flag, idx| duped[idx] = flag;
    return duped;
}

fn duplicateWitnessDiagnostics(
    allocator: std.mem.Allocator,
    diagnostics: []const Diagnostic,
) std.mem.Allocator.Error![]const error_witness.WitnessDiagnostic {
    const duped = try allocator.alloc(error_witness.WitnessDiagnostic, diagnostics.len);
    for (diagnostics, 0..) |diag, idx| {
        duped[idx] = .{
            .code = diag.code,
            .message = diag.message,
            .path = diag.path,
            .line = diag.line,
            .column = diag.column,
        };
    }
    return duped;
}

fn duplicateSourcePath(allocator: std.mem.Allocator, path: []const u8) std.mem.Allocator.Error![]const u8 {
    return try allocator.dupe(u8, path);
}

fn resolvedRepoSourcePathAlloc(allocator: std.mem.Allocator, source_path: []const u8) ![]u8 {
    const io = std.Io.Threaded.global_single_threaded.io();
    if (std.Io.Dir.path.isAbsolute(source_path)) {
        return try std.Io.Dir.path.resolve(allocator, &.{source_path});
    }

    const repo_relative = try authoring_lowerer.resolveRepoSourcePathAlloc(allocator, source_path);
    if (std.Io.Dir.cwd().access(io, repo_relative, .{})) {
        return repo_relative;
    } else |_| {
        allocator.free(repo_relative);
    }

    const cwd_path = try std.process.currentPathAlloc(io, allocator);
    defer allocator.free(cwd_path);
    return try std.Io.Dir.path.resolve(allocator, &.{ cwd_path, source_path });
}

fn stripLineCommentsAlloc(allocator: std.mem.Allocator, source: []const u8) std.mem.Allocator.Error![]u8 {
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
            if (idx < source.len and source[idx] == '\n') try out.append(allocator, '\n');
            continue;
        }
        try out.append(allocator, byte);
    }

    return try out.toOwnedSlice(allocator);
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

fn comparisonSourceSlice(tree: std.zig.Ast, source: []const u8, case: SupportedCase) ?[]const u8 {
    return switch (case.compare_scope) {
        .file => source,
        .entry => entryFunctionSourceSlice(tree, source, case.entry_symbol),
    };
}

fn normalizeNonCommentLayoutAlloc(
    allocator: std.mem.Allocator,
    source: []const u8,
) std.mem.Allocator.Error![]u8 {
    const stripped = try stripLineCommentsAlloc(allocator, source);
    defer allocator.free(stripped);

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var lines = std.mem.splitScalar(u8, stripped, '\n');
    var wrote_line = false;
    while (lines.next()) |line| {
        if (std.mem.trim(u8, line, " \t\r").len == 0) continue;
        if (wrote_line) try out.append(allocator, '\n');
        try out.appendSlice(allocator, std.mem.trimEnd(u8, line, " \t\r"));
        wrote_line = true;
    }
    if (wrote_line) try out.append(allocator, '\n');
    return try out.toOwnedSlice(allocator);
}

fn sourceMatchesCanonicalLayout(
    allocator: std.mem.Allocator,
    case: SupportedCase,
    source_text: []const u8,
) !bool {
    if (authoring_lowerer.sourceTextMatchesCanonicalSource(allocator, case.source_path, source_text)) return true;

    const actual_z = try allocator.dupeSentinel(u8, source_text, 0);
    defer allocator.free(actual_z);
    var actual_tree = try std.zig.Ast.parse(allocator, actual_z, .zig);
    defer actual_tree.deinit(allocator);
    if (actual_tree.errors.len != 0) return false;

    const canonical_path = try authoring_lowerer.resolveRepoSourcePathAlloc(allocator, case.source_path);
    defer allocator.free(canonical_path);
    const canonical_source = try std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), canonical_path, allocator, .limited(1 << 20));
    defer allocator.free(canonical_source);

    const canonical_z = try allocator.dupeSentinel(u8, canonical_source, 0);
    defer allocator.free(canonical_z);
    var canonical_tree = try std.zig.Ast.parse(allocator, canonical_z, .zig);
    defer canonical_tree.deinit(allocator);
    if (canonical_tree.errors.len != 0) return false;

    const actual_scope = comparisonSourceSlice(actual_tree, actual_z, case) orelse return false;
    const canonical_scope = comparisonSourceSlice(canonical_tree, canonical_z, case) orelse return false;
    const normalized_actual = try normalizeNonCommentLayoutAlloc(allocator, actual_scope);
    defer allocator.free(normalized_actual);
    const normalized_canonical = try normalizeNonCommentLayoutAlloc(allocator, canonical_scope);
    defer allocator.free(normalized_canonical);
    return std.mem.eql(u8, normalized_actual, normalized_canonical);
}

fn generatedProgramFromLowered(
    allocator: std.mem.Allocator,
    spec: Spec,
    case: SupportedCase,
    lowered: authoring_lowerer.LoweredAuthoring,
) std.mem.Allocator.Error!GeneratedProgram {
    const artifact = lowered.kernelProgramArtifact();
    const diagnostics = blk: {
        if (lowered.status != .rejected) break :blk lowered.diagnostics;
        const translated = try allocator.dupe(Diagnostic, lowered.diagnostics);
        allocator.free(lowered.diagnostics);
        for (translated) |*diag| {
            if (std.mem.eql(u8, diag.code, "structural_mismatch") or
                std.mem.eql(u8, diag.code, "canonical_source_drift") or
                std.mem.eql(u8, diag.code, "expected_status_mismatch") or
                std.mem.eql(u8, diag.code, "entry_missing"))
            {
                diag.code = "unsupported_shape";
            }
        }
        break :blk translated;
    };

    const witness = blk: {
        if (lowered.status == .rejected) {
            const template = rejectedWitnessTemplate(spec);
            const witness_diagnostics = try duplicateWitnessDiagnostics(allocator, diagnostics);
            errdefer allocator.free(witness_diagnostics);
            break :blk error_witness.ErrorWitnessV1{
                .surface = .ordinary,
                .support_status = .unsupported,
                .public_runtime_errors = error_witness.no_runtime_error_tags[0..],
                .setup_error_names = template.setup_error_names,
                .semantic_error_names = template.semantic_error_names,
                .contributors = template.contributors,
                .diagnostics = witness_diagnostics,
            };
        }

        const template = witnessTemplate(spec, case);
        break :blk error_witness.ErrorWitnessV1{
            .surface = .ordinary,
            .support_status = .supported,
            .public_runtime_errors = error_witness.no_runtime_error_tags[0..],
            .setup_error_names = template.setup_error_names,
            .semantic_error_names = template.semantic_error_names,
            .contributors = template.contributors,
            .diagnostics = error_witness.no_diagnostics[0..],
        };
    };

    return .{
        .case_id = lowered.case_id,
        .label = lowered.label,
        .source_path = lowered.source_path,
        .surface_kind = spec.surface_kind,
        .status = artifact.status,
        .canonical_scenario_id = artifact.canonical_scenario_id,
        .expected_transcript = artifact.expected_transcript,
        .steps = artifact.steps,
        .feature_flags = artifact.feature_flags,
        .diagnostics = diagnostics,
        .error_witness = witness,
    };
}

fn generatedRejectedProgram(
    allocator: std.mem.Allocator,
    spec: Spec,
    case: SupportedCase,
    message: []const u8,
) std.mem.Allocator.Error!GeneratedProgram {
    const source_path = try duplicateSourcePath(allocator, spec.source_path);
    errdefer allocator.free(source_path);
    const diagnostics = try allocator.alloc(Diagnostic, 1);
    errdefer allocator.free(diagnostics);
    diagnostics[0] = .{
        .code = "unsupported_shape",
        .message = message,
        .path = source_path,
        .line = 1,
        .column = 1,
    };
    const steps = try allocator.alloc(lowered_machine.Step, 0);
    errdefer allocator.free(steps);
    const feature_flags = try duplicateFeatureFlags(allocator, case.feature_flags);
    errdefer allocator.free(feature_flags);
    const template = rejectedWitnessTemplate(spec);
    const witness_diagnostics = try duplicateWitnessDiagnostics(allocator, diagnostics);
    errdefer allocator.free(witness_diagnostics);
    return .{
        .case_id = case.case_id,
        .label = case.label,
        .source_path = source_path,
        .surface_kind = spec.surface_kind,
        .status = .rejected,
        .canonical_scenario_id = case.scenario_id,
        .expected_transcript = "",
        .steps = steps,
        .feature_flags = feature_flags,
        .diagnostics = diagnostics,
        .error_witness = .{
            .surface = .ordinary,
            .support_status = .unsupported,
            .public_runtime_errors = error_witness.no_runtime_error_tags[0..],
            .setup_error_names = template.setup_error_names,
            .semantic_error_names = template.semantic_error_names,
            .contributors = template.contributors,
            .diagnostics = witness_diagnostics,
        },
    };
}

fn inspectSourceText(
    allocator: std.mem.Allocator,
    spec: Spec,
    case: SupportedCase,
    source_text: []const u8,
) !GeneratedProgram {
    if (!std.mem.eql(u8, spec.entry_symbol, case.entry_symbol)) {
        return generatedRejectedProgram(allocator, spec, case, "requested entry symbol is not supported for this case; use the case's canonical entry symbol");
    }
    if (spec.expected_status != case.status) {
        return generatedRejectedProgram(allocator, spec, case, "requested expected_status does not match this case; use the case's supported status or update the case definition");
    }

    const resolved_source_path = resolvedRepoSourcePathAlloc(allocator, spec.source_path) catch try allocator.dupe(u8, spec.source_path);
    defer allocator.free(resolved_source_path);

    var lowered = try authoring_lowerer.lowerSourceText(
        allocator,
        loweringCase(spec, case),
        .{
            .display_path = spec.source_path,
            .actual_path = resolved_source_path,
            .source_text = source_text,
            .expected_status = spec.expected_status,
        },
    );
    var lowered_owned = true;
    errdefer if (lowered_owned) lowered.deinit(allocator);
    if (lowered.status != .rejected and !(try sourceMatchesCanonicalLayout(allocator, case, source_text))) {
        lowered.deinit(allocator);
        lowered_owned = false;
        return generatedRejectedProgram(allocator, spec, case, "source differs from the supported artifact layout for this case; use the canonical fixture shape or update the case baseline");
    }
    const program = try generatedProgramFromLowered(allocator, spec, case, lowered);
    lowered_owned = false;
    return program;
}

fn inspectFileBackedSourceText(
    allocator: std.mem.Allocator,
    spec: Spec,
    case: SupportedCase,
    actual_path: []const u8,
    source_text: []const u8,
) !GeneratedProgram {
    if (!std.mem.eql(u8, spec.entry_symbol, case.entry_symbol)) {
        return generatedRejectedProgram(allocator, spec, case, "requested entry symbol is not supported for this case; use the case's canonical entry symbol");
    }
    if (spec.expected_status != case.status) {
        return generatedRejectedProgram(allocator, spec, case, "requested expected_status does not match this case; use the case's supported status or update the case definition");
    }

    var lowered = try authoring_lowerer.lowerFileBackedSourceText(.{
        .allocator = allocator,
        .case = loweringCase(spec, case),
        .display_path = spec.source_path,
        .actual_path = actual_path,
        .source_text = source_text,
        .expected_status = spec.expected_status,
    });
    var lowered_owned = true;
    errdefer if (lowered_owned) lowered.deinit(allocator);
    if (lowered.status != .rejected and !(try sourceMatchesCanonicalLayout(allocator, case, source_text))) {
        lowered.deinit(allocator);
        lowered_owned = false;
        return generatedRejectedProgram(allocator, spec, case, "source differs from the supported artifact layout for this case; use the canonical fixture shape or update the case baseline");
    }
    const program = try generatedProgramFromLowered(allocator, spec, case, lowered);
    lowered_owned = false;
    return program;
}

/// Inspect and lower one restricted source-lowering source file.
pub fn inspectSource(allocator: std.mem.Allocator, spec: Spec) LowerError!GeneratedProgram {
    const case = switch (spec.surface_kind) {
        .source_case => sourceSupportedCase(source_registry.find(spec.case_id) orelse return error.UnsupportedSourceCase),
        .example, .effect, .user_defined_effect, .witness => promotedSupportedCase(spec.case_id, spec.surface_kind) orelse return error.UnsupportedSourceCase,
    };
    if (!std.mem.eql(u8, spec.entry_symbol, case.entry_symbol)) {
        return generatedRejectedProgram(allocator, spec, case, "requested entry symbol is not supported for this case; use the case's canonical entry symbol");
    }
    if (spec.expected_status != case.status) {
        return generatedRejectedProgram(allocator, spec, case, "requested expected_status does not match this case; use the case's supported status or update the case definition");
    }
    const resolved_source_path = resolvedRepoSourcePathAlloc(allocator, spec.source_path) catch try allocator.dupe(u8, spec.source_path);
    defer allocator.free(resolved_source_path);
    var lowered = try authoring_lowerer.lowerSourceFile(
        allocator,
        loweringCase(spec, case),
        spec.source_path,
        resolved_source_path,
        spec.expected_status,
    );
    var lowered_owned = true;
    errdefer if (lowered_owned) lowered.deinit(allocator);
    if (lowered.status != .rejected) {
        const source = std.Io.Dir.cwd().readFileAlloc(std.Io.Threaded.global_single_threaded.io(), resolved_source_path, allocator, .limited(1 << 20)) catch {
            lowered.deinit(allocator);
            lowered_owned = false;
            return generatedRejectedProgram(allocator, spec, case, "source file could not be read");
        };
        defer allocator.free(source);
        if (!(try sourceMatchesCanonicalLayout(allocator, case, source))) {
            lowered.deinit(allocator);
            lowered_owned = false;
            return generatedRejectedProgram(allocator, spec, case, "source differs from the supported artifact layout for this case; use the canonical fixture shape or update the case baseline");
        }
    }
    const program = try generatedProgramFromLowered(allocator, spec, case, lowered);
    lowered_owned = false;
    return program;
}

/// Inspect and lower one inline source body against a supported source-lowering case.
pub fn inspectInlineSource(allocator: std.mem.Allocator, spec: Spec, source_text: []const u8) LowerError!GeneratedProgram {
    const case = switch (spec.surface_kind) {
        .source_case => sourceSupportedCase(source_registry.find(spec.case_id) orelse return error.UnsupportedSourceCase),
        .example, .effect, .user_defined_effect, .witness => promotedSupportedCase(spec.case_id, spec.surface_kind) orelse return error.UnsupportedSourceCase,
    };
    return inspectSourceText(allocator, spec, case, source_text);
}

/// Inspect file-backed source text against the canonical file-backed lowering path without mutating the fixture on disk.
pub fn inspectFileBackedInlineSource(
    allocator: std.mem.Allocator,
    spec: Spec,
    source_text: []const u8,
) LowerError!GeneratedProgram {
    const case = switch (spec.surface_kind) {
        .source_case => sourceSupportedCase(source_registry.find(spec.case_id) orelse return error.UnsupportedSourceCase),
        .example, .effect, .user_defined_effect, .witness => promotedSupportedCase(spec.case_id, spec.surface_kind) orelse return error.UnsupportedSourceCase,
    };
    const resolved_source_path = resolvedRepoSourcePathAlloc(allocator, spec.source_path) catch try allocator.dupe(u8, spec.source_path);
    defer allocator.free(resolved_source_path);
    return inspectFileBackedSourceText(allocator, spec, case, resolved_source_path, source_text);
}

/// Lower one supported source-lowering fixture through the source-validated path.
pub fn lowerFixture(allocator: std.mem.Allocator, comptime Fixture: type) LowerError!GeneratedProgram {
    if (!@hasDecl(Fixture, "source_case_id")) {
        @compileError(@typeName(Fixture) ++ " must declare source_case_id");
    }
    const case = source_registry.find(Fixture.source_case_id) orelse return error.UnsupportedSourceCase;
    if (!@hasDecl(Fixture, "source")) {
        return error.UnsupportedSourceCase;
    }
    const supported = sourceSupportedCase(case);
    return inspectSourceText(allocator, .{
        .case_id = case.case_id,
        .source_path = case.fixture_path,
        .entry_symbol = "run",
        .surface_kind = .source_case,
        .expected_status = supported.status,
    }, supported, Fixture.source);
}

/// Execute one accepted kernel program artifact and render its transcript.
pub fn runLowered(writer: anytype, program: *const GeneratedProgram) anyerror!void {
    const artifact = program.kernelProgramArtifact();
    if (!artifact.isExecutable()) return error.RejectedGeneratedProgram;
    const state = lowered_machine.runSteps(artifact.steps);
    try lowered_machine.writeTranscript(writer, &state);
}
