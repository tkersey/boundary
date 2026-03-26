const authoring_lowerer = @import("authoring_lowerer");
const bridge_manifest = @import("direct_style_bridge_manifest");
const std = @import("std");

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
        .feature_flags = &.{},
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
        .feature_flags = &.{},
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
    const resolved_source_path = try authoring_lowerer.resolveRepoSourcePathAlloc(allocator, case.source_module);
    defer allocator.free(resolved_source_path);

    return try authoring_lowerer.lowerFileBackedSourceText(.{
        .allocator = allocator,
        .case = canonicalBridgeCase(case),
        .display_path = case.source_module,
        .actual_path = resolved_source_path,
        .source_text = source_text,
        .expected_status = .canonical,
    });
}

/// Lower one supported bridge example case id through the shared authoring lowerer.
pub fn lowerCaseId(allocator: std.mem.Allocator, case_id: []const u8) anyerror!authoring_lowerer.LoweredAuthoring {
    const case = bridge_manifest.find(case_id) orelse return error.UnsupportedBridgeCase;
    if (case.status == .blocked) return error.UnsupportedBridgeCase;
    const resolved_source_path = try authoring_lowerer.resolveRepoSourcePathAlloc(allocator, case.source_module);
    defer allocator.free(resolved_source_path);

    return try authoring_lowerer.lowerSourceFile(
        allocator,
        canonicalBridgeCase(case),
        case.source_module,
        resolved_source_path,
        .canonical,
    );
}
