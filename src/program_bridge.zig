const authoring_lowerer = @import("authoring_lowerer");
const bridge_manifest = @import("direct_style_bridge_manifest");
const std = @import("std");

fn bridgeFeatureFlags(case: *const bridge_manifest.Case) []const []const u8 {
    if (std.mem.eql(u8, case.case_id, "atm_resume_transform")) return &.{ "witness", "transform", "source_canonical" };
    if (std.mem.eql(u8, case.case_id, "direct_return")) return &.{ "witness", "abort", "source_canonical" };
    if (std.mem.eql(u8, case.case_id, "multi_prompt")) return &.{ "witness", "multi_prompt", "source_canonical" };
    if (std.mem.eql(u8, case.case_id, "resume_or_return_resume")) return &.{ "witness", "choice_resume", "source_canonical" };
    if (std.mem.eql(u8, case.case_id, "resume_or_return_return_now")) return &.{ "witness", "choice_return_now", "source_canonical" };
    if (std.mem.eql(u8, case.case_id, "static_redelim")) return &.{ "witness", "static_redelim", "source_canonical" };
    if (std.mem.eql(u8, case.case_id, "early_exit")) return &.{ "lexical_exception", "direct_return", "promoted_example" };
    if (std.mem.eql(u8, case.case_id, "resume_or_return")) return &.{ "lexical_optional", "return_now", "resume_with", "promoted_example" };
    if (std.mem.eql(u8, case.case_id, "nested_workflow")) return &.{ "generated_choice", "nested_workflow", "promoted_example" };
    if (std.mem.eql(u8, case.case_id, "open_row_generator")) return &.{ "witness", "generator", "source_canonical" };
    if (std.mem.eql(u8, case.case_id, "state_basic")) return &.{ "state_effect", "lexical_effect", "promoted_cohort_a" };
    if (std.mem.eql(u8, case.case_id, "reader_basic")) return &.{ "reader_effect", "lexical_effect", "promoted_cohort_a" };
    if (std.mem.eql(u8, case.case_id, "optional_basic")) return &.{ "optional_effect", "lexical_effect", "promoted_cohort_a" };
    if (std.mem.eql(u8, case.case_id, "exception_basic")) return &.{ "exception_effect", "lexical_effect", "promoted_cohort_a" };
    if (std.mem.eql(u8, case.case_id, "resource_basic")) return &.{ "resource_effect", "lexical_effect", "source_canonical" };
    if (std.mem.eql(u8, case.case_id, "writer_basic")) return &.{ "writer_effect", "lexical_effect", "source_canonical" };
    if (std.mem.eql(u8, case.case_id, "open_row_abortive_validation")) return &.{ "generated_abort", "open_row", "source_canonical" };
    if (std.mem.eql(u8, case.case_id, "open_row_artifact_search")) return &.{ "generated_transform", "open_row", "source_canonical" };
    return &.{};
}

fn canonicalBridgeCase(case: *const bridge_manifest.Case) authoring_lowerer.CanonicalCase {
    return .{
        .case_id = case.case_id,
        .label = case.label,
        .source_path = case.source_module,
        .entry_symbol = case.entry_symbol,
        .compare_scope = switch (case.source_kind) {
            .example => .file,
            .witness => .entry,
        },
        .surface_kind = .bridge,
        .status = .canonical,
        .scenario_id = case.scenario_id,
        .feature_flags = bridgeFeatureFlags(case),
    };
}

fn canonicalFixtureCase(case: *const bridge_manifest.Case) authoring_lowerer.CanonicalCase {
    return .{
        .case_id = case.case_id,
        .label = case.label,
        .source_path = case.fixture_module,
        .entry_symbol = "run",
        .compare_scope = .file,
        .surface_kind = .bridge,
        .status = .canonical,
        .scenario_id = case.scenario_id,
        .feature_flags = bridgeFeatureFlags(case),
    };
}

/// Lower one supported unchanged direct-style fixture through the shared authoring lowerer.
pub fn lowerFixture(allocator: std.mem.Allocator, comptime Fixture: type) anyerror!authoring_lowerer.LoweredAuthoring {
    if (!@hasDecl(Fixture, "bridge_case_id")) {
        @compileError(@typeName(Fixture) ++ " must declare bridge_case_id");
    }
    const case = bridge_manifest.find(Fixture.bridge_case_id) orelse return error.UnsupportedBridgeCase;
    if (case.status == .blocked) return error.UnsupportedBridgeCase;
    if (!@hasDecl(Fixture, "source_path")) return error.UnsupportedBridgeCase;
    if (!@hasDecl(Fixture, "source")) return error.UnsupportedBridgeCase;
    const resolved_source_path = try authoring_lowerer.resolveRepoSourcePathAlloc(allocator, Fixture.source_path);
    defer allocator.free(resolved_source_path);

    return try authoring_lowerer.lowerFileBackedSourceText(.{
        .allocator = allocator,
        .case = canonicalFixtureCase(case),
        .display_path = case.fixture_module,
        .actual_path = resolved_source_path,
        .source_text = Fixture.source,
        .expected_status = .canonical,
    });
}

/// Inspect one supported bridge case id against injected file-backed source text.
pub fn inspectCaseIdSourceText(
    allocator: std.mem.Allocator,
    case_id: []const u8,
    source_text: []const u8,
) anyerror!authoring_lowerer.LoweredAuthoring {
    const case = bridge_manifest.find(case_id) orelse return error.UnsupportedBridgeCase;
    if (case.status == .blocked) return error.UnsupportedBridgeCase;
    const fixture_backed = std.mem.eql(u8, case.source_module, case.fixture_module);
    const source_path = if (fixture_backed) case.fixture_module else case.source_module;
    const resolved_source_path = try authoring_lowerer.resolveRepoSourcePathAlloc(allocator, source_path);
    defer allocator.free(resolved_source_path);

    return try authoring_lowerer.lowerFileBackedSourceText(.{
        .allocator = allocator,
        .case = if (fixture_backed) canonicalFixtureCase(case) else canonicalBridgeCase(case),
        .display_path = source_path,
        .actual_path = resolved_source_path,
        .source_text = source_text,
        .expected_status = .canonical,
    });
}

/// Lower one supported bridge example case id through the shared authoring lowerer.
pub fn lowerCaseId(allocator: std.mem.Allocator, case_id: []const u8) anyerror!authoring_lowerer.LoweredAuthoring {
    const case = bridge_manifest.find(case_id) orelse return error.UnsupportedBridgeCase;
    if (case.status == .blocked) return error.UnsupportedBridgeCase;
    const fixture_backed = std.mem.eql(u8, case.source_module, case.fixture_module);
    const source_path = if (fixture_backed) case.fixture_module else case.source_module;
    const resolved_source_path = try authoring_lowerer.resolveRepoSourcePathAlloc(allocator, source_path);
    defer allocator.free(resolved_source_path);

    return try authoring_lowerer.lowerSourceFile(
        allocator,
        if (fixture_backed) canonicalFixtureCase(case) else canonicalBridgeCase(case),
        source_path,
        resolved_source_path,
        .canonical,
    );
}
