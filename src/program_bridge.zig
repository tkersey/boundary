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

/// Lower one supported unchanged direct-style fixture through the shared authoring lowerer.
pub fn lowerFixture(comptime Fixture: type) anyerror!authoring_lowerer.LoweredAuthoring {
    if (!@hasDecl(Fixture, "bridge_case_id")) {
        @compileError(@typeName(Fixture) ++ " must declare bridge_case_id");
    }
    return lowerCaseId(std.heap.page_allocator, Fixture.bridge_case_id);
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

    return try authoring_lowerer.lowerFileBackedSourceText(
        allocator,
        canonicalBridgeCase(case),
        case.source_module,
        resolved_source_path,
        source_text,
        .canonical,
    );
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
