const build_options = @import("authoring_build_options");
const builtin = @import("builtin");
const source_graph_comptime = @import("source_graph_comptime");
const source_graph_engine = @import("source_graph_engine");
const std = @import("std");

/// Shared error surface for repo-root embedded source graph analysis.
pub const Error = source_graph_engine.Error;

/// One function in a flattened explicit-path program graph.
pub const ProgramFunction = struct {
    module_path: []const u8,
    name: []const u8,
    effect_param: ?[]const u8,
    value_param_names: [source_graph_engine.max_function_params][]const u8,
    value_param_shapes: [source_graph_engine.max_function_params]source_graph_engine.ValueShape,
    value_param_count: u8,
    return_shape: ?source_graph_engine.ValueShape,
    body_lowering_supported: bool,
    body_start_offset: usize,
    body_end_offset: usize,
};

/// One helper edge in a flattened explicit-path program graph.
pub const ProgramHelperEdge = struct {
    caller_index: usize,
    callee_index: usize,
    line: usize,
    column: usize,
};

/// One direct effect-op use in a flattened explicit-path program graph.
pub const ProgramDirectOpUse = struct {
    function_index: usize,
    requirement_label: []const u8,
    op_name: []const u8,
    line: usize,
    column: usize,
};

/// Flattened same-file plus imported-helper program graph for explicit-path lowering.
pub const ProgramGraph = struct {
    entry_index: usize,
    functions: []const ProgramFunction,
    helper_edges: []const ProgramHelperEdge,
    direct_op_uses: []const ProgramDirectOpUse,
};

/// One caller-owned source file supplied alongside the root lowering source.
pub const OwnedSource = struct {
    path: []const u8,
    content: [:0]const u8,
};

const ModuleSummary = struct {
    first_function_index: usize,
    function_count: usize,
    graph: source_graph_engine.ModuleGraph,
};

const ModuleEntry = struct {
    path: []const u8,
    summary: ModuleSummary,
};

const Buffers = struct {
    functions: [256]ProgramFunction = [_]ProgramFunction{.{
        .module_path = "",
        .name = "",
        .effect_param = null,
        .value_param_names = [_][]const u8{""} ** source_graph_engine.max_function_params,
        .value_param_shapes = [_]source_graph_engine.ValueShape{.i32} ** source_graph_engine.max_function_params,
        .value_param_count = 0,
        .return_shape = null,
        .body_lowering_supported = false,
        .body_start_offset = 0,
        .body_end_offset = 0,
    }} ** 256,
    function_count: usize = 0,
    helper_edges: [1024]ProgramHelperEdge = [_]ProgramHelperEdge{.{
        .caller_index = 0,
        .callee_index = 0,
        .line = 0,
        .column = 0,
    }} ** 1024,
    helper_edge_count: usize = 0,
    direct_op_uses: [2048]ProgramDirectOpUse = [_]ProgramDirectOpUse{.{
        .function_index = 0,
        .requirement_label = "",
        .op_name = "",
        .line = 0,
        .column = 0,
    }} ** 2048,
    direct_op_use_count: usize = 0,
    modules: [64]ModuleEntry = [_]ModuleEntry{.{
        .path = "",
        .summary = .{
            .first_function_index = 0,
            .function_count = 0,
            .graph = .{
                .entry_index = null,
                .functions = &.{},
                .imports = &.{},
                .helper_uses = &.{},
                .helper_edges = &.{},
                .direct_op_uses = &.{},
            },
        },
    }} ** 64,
    module_count: usize = 0,
};

const NormalizeRelativePathError = error{
    EmptyPath,
    EscapesRoot,
    TooManySegments,
};

fn joinRelativePathSegments(comptime segments: []const []const u8) []const u8 {
    return comptime blk: {
        if (segments.len == 0) break :blk "";
        var result = segments[0];
        for (segments[1..]) |segment| {
            result = std.fmt.comptimePrint("{s}/{s}", .{ result, segment });
        }
        break :blk result;
    };
}

fn pathEquals(comptime lhs: []const u8, comptime rhs: []const u8) bool {
    if (lhs.len != rhs.len) return false;
    inline for (rhs, 0..) |expected, index| {
        const actual = lhs[index];
        if (expected == '/' or expected == '\\') {
            if (actual != '/' and actual != '\\') return false;
            continue;
        }
        if (actual != expected) return false;
    }
    return true;
}

fn pathStartsWithRoot(comptime path: []const u8, comptime root: []const u8) bool {
    if (path.len < root.len) return false;
    inline for (root, 0..) |expected, index| {
        const actual = path[index];
        if (expected == '/' or expected == '\\') {
            if (actual != '/' and actual != '\\') return false;
            continue;
        }
        if (actual != expected) return false;
    }
    return path.len == root.len or path[root.len] == '/' or path[root.len] == '\\';
}

fn normalizeRelativePath(comptime source_path: []const u8) NormalizeRelativePathError![]const u8 {
    var segments = [_][]const u8{""} ** 64;
    var segment_count: usize = 0;
    var start: usize = 0;
    var index: usize = 0;
    while (index <= source_path.len) : (index += 1) {
        if (index != source_path.len and source_path[index] != '/' and source_path[index] != '\\') continue;
        const segment = source_path[start..index];
        start = index + 1;
        if (segment.len == 0 or std.mem.eql(u8, segment, ".")) continue;
        if (std.mem.eql(u8, segment, "..")) {
            if (segment_count == 0) return error.EscapesRoot;
            segment_count -= 1;
            continue;
        }
        if (segment_count >= segments.len) return error.TooManySegments;
        segments[segment_count] = segment;
        segment_count += 1;
    }
    if (segment_count == 0) return error.EmptyPath;
    return joinRelativePathSegments(segments[0..segment_count]);
}

fn repoRelativeAbsolutePath(
    comptime source_path: []const u8,
    comptime root_path: []const u8,
) ?[]const u8 {
    if (!pathStartsWithRoot(source_path, root_path)) return null;
    if (source_path.len <= root_path.len) {
        @compileError("public lowering source path must point to a file under the package root");
    }
    if (source_path[root_path.len] != '/' and source_path[root_path.len] != '\\') {
        @compileError("public lowering source path must point to a file under the package root");
    }
    return source_path[root_path.len + 1 ..];
}

fn repoRelativePath(comptime source_path: []const u8) []const u8 {
    if (std.fs.path.isAbsolute(source_path)) {
        if (repoRelativeAbsolutePath(source_path, build_options.package_root)) |repo_source_path| {
            return normalizeRelativePath(repo_source_path) catch |err| switch (err) {
                error.EmptyPath => @compileError("public lowering source path must point to a file under the package root"),
                error.EscapesRoot => @compileError("public lowering source path must stay under the package root"),
                error.TooManySegments => @compileError("public lowering source path exceeded the supported segment budget"),
            };
        }
        if (repoRelativeAbsolutePath(source_path, build_options.package_root_alias)) |repo_source_path| {
            return normalizeRelativePath(repo_source_path) catch |err| switch (err) {
                error.EmptyPath => @compileError("public lowering source path must point to a file under the package root"),
                error.EscapesRoot => @compileError("public lowering source path must stay under the package root"),
                error.TooManySegments => @compileError("public lowering source path exceeded the supported segment budget"),
            };
        }
        @compileError("public lowering source path must stay under the package root");
    }
    return normalizeRelativePath(source_path) catch |err| switch (err) {
        error.EmptyPath => @compileError("public lowering source path must point to a file under the package root"),
        error.EscapesRoot => @compileError("public lowering source path must stay under the package root"),
        error.TooManySegments => @compileError("public lowering source path exceeded the supported segment budget"),
    };
}

fn registryContainsLine(comptime registry: []const u8, comptime candidate: []const u8) bool {
    comptime {
        @setEvalBranchQuota(50_000);
    }
    var start: usize = 0;
    while (start < registry.len) {
        var end = start;
        while (end < registry.len and registry[end] != '\n') : (end += 1) {}
        const line = registry[start..end];
        if (line.len != 0 and std.mem.eql(u8, line, candidate)) return true;
        start = end + 1;
    }
    return false;
}

fn ownedRepoRelativePath(comptime source_path: []const u8) []const u8 {
    const repo_path = repoRelativePath(source_path);
    if (!registryContainsLine(build_options.repo_zig_paths, repo_path)) {
        @compileError("public lowering source path must resolve to an owned repo file");
    }
    return repo_path;
}

fn absoluteSourcePath(comptime source_path: []const u8) []const u8 {
    if (!std.fs.path.isAbsolute(source_path)) @compileError("public lowering absolute source path must be absolute");
    return normalizeAbsolutePath(source_path) catch |err| switch (err) {
        error.EmptyPath => @compileError("public lowering source path must point to a file"),
        error.EscapesRoot => @compileError("public lowering source path must stay within the absolute root"),
        error.TooManySegments => @compileError("public lowering source path exceeded the supported segment budget"),
    };
}

fn normalizeAbsolutePathWithType(
    comptime path_type: std.fs.path.PathType,
    comptime source_path: []const u8,
) NormalizeRelativePathError![]const u8 {
    var iterator = std.fs.path.ComponentIterator(path_type, u8).init(source_path) catch return error.EmptyPath;
    const root = iterator.root() orelse return error.EmptyPath;
    const relative = normalizeRelativePath(source_path[root.len..]) catch |err| switch (err) {
        error.EmptyPath => return error.EmptyPath,
        error.EscapesRoot => return error.EscapesRoot,
        error.TooManySegments => return error.TooManySegments,
    };
    return std.fmt.comptimePrint("{s}{s}", .{ root, relative });
}

fn normalizeAbsolutePath(comptime source_path: []const u8) NormalizeRelativePathError![]const u8 {
    if (!std.fs.path.isAbsolute(source_path)) return error.EmptyPath;
    const path_type: std.fs.path.PathType = if (builtin.os.tag == .windows) .windows else .posix;
    return normalizeAbsolutePathWithType(path_type, source_path);
}

/// Return caller-owned source bytes for one exact module path when provided explicitly.
pub fn ownedSourceContent(
    comptime source_path: []const u8,
    comptime root_source_path: ?[]const u8,
    comptime root_source: ?[:0]const u8,
    comptime imported_sources: []const OwnedSource,
) ?[:0]const u8 {
    if (root_source_path != null and pathEquals(source_path, root_source_path.?)) {
        return root_source;
    }
    for (imported_sources) |imported_source| {
        if (pathEquals(source_path, imported_source.path)) return imported_source.content;
    }
    return null;
}

/// Resolve one module path to caller-owned bytes first, then fall back to repo-embedded bytes.
pub fn sourceBytes(
    comptime source_path: []const u8,
    comptime root_source_path: ?[]const u8,
    comptime root_source: ?[:0]const u8,
    comptime imported_sources: []const OwnedSource,
) [:0]const u8 {
    return ownedSourceContent(source_path, root_source_path, root_source, imported_sources) orelse embeddedSource(source_path);
}

/// Embed one repo-relative source file through a repo-root module so examples remain package-visible.
pub fn embeddedSource(comptime source_path: []const u8) [:0]const u8 {
    return @embedFile(ownedRepoRelativePath(source_path));
}

/// Analyze one repo-relative source file through the shared comptime source-graph extractor.
pub fn analyzeModuleAt(comptime source_path: []const u8, comptime entry_symbol: []const u8) source_graph_comptime.Error!source_graph_comptime.ModuleGraph {
    return source_graph_comptime.analyzeModule(embeddedSource(source_path), entry_symbol);
}

fn dirname(comptime path: []const u8) []const u8 {
    return std.fs.path.dirname(path) orelse "";
}

/// Keep absolute caller-owned helper imports inside the entry directory or one parent sibling tree.
pub fn absoluteOwnedImportWithinEntryTree(path: []const u8) bool {
    var iterator = std.mem.tokenizeAny(u8, path, "/\\");
    var leading_parent_count: usize = 0;
    var entered_subtree = false;

    while (iterator.next()) |segment| {
        if (segment.len == 0 or std.mem.eql(u8, segment, ".")) continue;
        if (std.mem.eql(u8, segment, "..")) {
            if (entered_subtree) return false;
            leading_parent_count += 1;
            if (leading_parent_count > 1) return false;
            continue;
        }
        entered_subtree = true;
    }

    return entered_subtree;
}

fn resolveImportPath(comptime from_path: []const u8, comptime import_path: []const u8) Error![]const u8 {
    if (std.mem.startsWith(u8, import_path, "/")) return error.UnsupportedImportPath;
    if (!std.mem.endsWith(u8, import_path, ".zig")) return error.UnsupportedImportPath;

    const normalized_from_path = if (std.fs.path.isAbsolute(from_path))
        absoluteSourcePath(from_path)
    else
        repoRelativePath(from_path);
    if (std.fs.path.isAbsolute(normalized_from_path) and !absoluteOwnedImportWithinEntryTree(import_path)) {
        return error.UnsupportedImportPath;
    }
    const base_dir = dirname(normalized_from_path);
    const joined = if (base_dir.len == 0)
        import_path
    else
        std.fmt.comptimePrint("{s}/{s}", .{ base_dir, import_path });

    return if (std.fs.path.isAbsolute(normalized_from_path))
        normalizeAbsolutePath(joined) catch |err| switch (err) {
            error.EmptyPath, error.EscapesRoot => error.UnsupportedImportPath,
            error.TooManySegments => error.TooManyImports,
        }
    else
        normalizeRelativePath(joined) catch |err| switch (err) {
            error.EmptyPath, error.EscapesRoot => error.UnsupportedImportPath,
            error.TooManySegments => error.TooManyImports,
        };
}

/// Resolve one helper import relative to its owning repo-relative module path.
pub fn resolveImportPathAt(comptime from_path: []const u8, comptime import_path: []const u8) Error![]const u8 {
    return try resolveImportPath(from_path, import_path);
}

fn findModule(buffers: *const Buffers, comptime path: []const u8) ?ModuleSummary {
    for (buffers.modules[0..buffers.module_count]) |module| {
        if (std.mem.eql(u8, module.path, path)) return module.summary;
    }
    return null;
}

fn findImportAlias(imports: []const source_graph_engine.ImportAlias, comptime name: []const u8) ?source_graph_engine.ImportAlias {
    for (imports) |import_alias| {
        if (std.mem.eql(u8, import_alias.name, name)) return import_alias;
    }
    return null;
}

fn findLocalFunctionIndex(graph: source_graph_engine.ModuleGraph, comptime name: []const u8) ?usize {
    for (graph.functions, 0..) |function, index| {
        if (std.mem.eql(u8, function.name, name)) return index;
    }
    return null;
}

fn edgeExists(edges: []const ProgramHelperEdge, caller_index: usize, callee_index: usize) bool {
    for (edges) |edge| {
        if (edge.caller_index == caller_index and edge.callee_index == callee_index) return true;
    }
    return false;
}

fn pushHelperEdge(buffers: *Buffers, caller_index: usize, callee_index: usize, line: usize, column: usize) Error!void {
    if (edgeExists(buffers.helper_edges[0..buffers.helper_edge_count], caller_index, callee_index)) return;
    if (buffers.helper_edge_count >= buffers.helper_edges.len) return error.TooManyHelperEdges;
    buffers.helper_edges[buffers.helper_edge_count] = .{
        .caller_index = caller_index,
        .callee_index = callee_index,
        .line = line,
        .column = column,
    };
    buffers.helper_edge_count += 1;
}

fn analyzeOwnedModule(
    comptime source_path: []const u8,
    comptime root_source_path: ?[]const u8,
    comptime root_source: ?[:0]const u8,
    comptime imported_sources: []const OwnedSource,
    comptime entry_symbol: ?[]const u8,
) Error!source_graph_engine.ModuleGraph {
    return source_graph_engine.analyzeComptime(sourceBytes(source_path, root_source_path, root_source, imported_sources), .{
        .entry_symbol = entry_symbol,
        .reject_recursive_helpers = false,
        .reject_indirect_effect_access = true,
        .reject_malformed_statements = true,
    });
}

fn collectModule(
    comptime source_path: []const u8,
    comptime root_source_path: ?[]const u8,
    comptime root_source: ?[:0]const u8,
    comptime imported_sources: []const OwnedSource,
    buffers: *Buffers,
) Error!ModuleSummary {
    if (findModule(buffers, source_path)) |existing| return existing;

    if (buffers.module_count >= buffers.modules.len) return error.TooManyImports;
    const graph = try analyzeOwnedModule(
        source_path,
        root_source_path,
        root_source,
        imported_sources,
        null,
    );
    const first_function_index = buffers.function_count;

    if (buffers.function_count + graph.functions.len > buffers.functions.len) return error.TooManyFunctions;
    for (graph.functions) |function| {
        buffers.functions[buffers.function_count] = .{
            .module_path = source_path,
            .name = function.name,
            .effect_param = function.effect_param,
            .value_param_names = function.value_param_names,
            .value_param_shapes = function.value_param_shapes,
            .value_param_count = function.value_param_count,
            .return_shape = function.return_shape,
            .body_lowering_supported = function.body_lowering_supported,
            .body_start_offset = function.body_start_offset,
            .body_end_offset = function.body_end_offset,
        };
        buffers.function_count += 1;
    }

    if (buffers.direct_op_use_count + graph.direct_op_uses.len > buffers.direct_op_uses.len) return error.TooManyOpUses;
    for (graph.direct_op_uses) |direct_op_use| {
        buffers.direct_op_uses[buffers.direct_op_use_count] = .{
            .function_index = first_function_index + direct_op_use.function_index,
            .requirement_label = direct_op_use.requirement_label,
            .op_name = direct_op_use.op_name,
            .line = direct_op_use.line,
            .column = direct_op_use.column,
        };
        buffers.direct_op_use_count += 1;
    }

    const summary: ModuleSummary = .{
        .first_function_index = first_function_index,
        .function_count = graph.functions.len,
        .graph = graph,
    };
    buffers.modules[buffers.module_count] = .{
        .path = source_path,
        .summary = summary,
    };
    buffers.module_count += 1;

    for (graph.helper_edges) |edge| {
        try pushHelperEdge(
            buffers,
            first_function_index + edge.caller_index,
            first_function_index + edge.callee_index,
            edge.line,
            edge.column,
        );
    }

    for (graph.helper_uses) |helper_use| {
        const import_alias = helper_use.import_alias orelse continue;
        if (graph.functions[helper_use.caller_index].effect_param == null) continue;
        const import_row = findImportAlias(graph.imports, import_alias) orelse return error.MissingImport;
        const imported_path = try resolveImportPath(source_path, import_row.import_path);
        const imported = try collectModule(imported_path, root_source_path, root_source, imported_sources, buffers);
        const callee_local_index = findLocalFunctionIndex(imported.graph, helper_use.callee_name) orelse return error.MissingImport;
        try pushHelperEdge(
            buffers,
            first_function_index + helper_use.caller_index,
            imported.first_function_index + callee_local_index,
            helper_use.line,
            helper_use.column,
        );
    }

    return summary;
}

/// Analyze one repo-relative source file and flatten same-file plus imported helper graphs into one explicit program graph.
pub fn analyzeProgramAt(comptime source_path: []const u8, comptime entry_symbol: []const u8) Error!ProgramGraph {
    return try analyzeProgramWithRootSource(source_path, null, &.{}, entry_symbol);
}

/// Analyze one source-owned root module plus imported helper graphs into one explicit program graph.
pub fn analyzeProgramWithRootSource(
    comptime source_path: []const u8,
    comptime root_source: ?[:0]const u8,
    comptime imported_sources: []const OwnedSource,
    comptime entry_symbol: []const u8,
) Error!ProgramGraph {
    var buffers = Buffers{};
    const root_source_path = if (root_source != null) source_path else null;
    const root = try collectModule(source_path, root_source_path, root_source, imported_sources, &buffers);
    const root_graph = try analyzeOwnedModule(source_path, root_source_path, root_source, imported_sources, entry_symbol);
    const entry_local_index = root_graph.entry_index orelse return error.EntryMissing;
    const entry_index = root.first_function_index + entry_local_index;

    return .{
        .entry_index = entry_index,
        .functions = buffers.functions[0..buffers.function_count],
        .helper_edges = buffers.helper_edges[0..buffers.helper_edge_count],
        .direct_op_uses = buffers.direct_op_uses[0..buffers.direct_op_use_count],
    };
}

test "normalizeAbsolutePathWithType preserves Windows drive roots" {
    try std.testing.expectEqualStrings(
        "C:\\foo/bar.zig",
        try normalizeAbsolutePathWithType(.windows, "C:\\foo\\.\\bar.zig"),
    );
}

test "normalizeAbsolutePathWithType preserves UNC roots" {
    try std.testing.expectEqualStrings(
        "\\\\server\\share\\pkg/main.zig",
        try normalizeAbsolutePathWithType(.windows, "\\\\server\\share\\pkg\\.\\main.zig"),
    );
}

test "repoRelativeAbsolutePath accepts mixed separator spellings for checkout roots" {
    try std.testing.expectEqualStrings(
        "examples/open_row_state_writer.zig",
        repoRelativeAbsolutePath(
            "C:/repo/examples/open_row_state_writer.zig",
            "C:\\repo",
        ).?,
    );
    try std.testing.expectEqualStrings(
        "examples\\open_row_state_writer.zig",
        repoRelativeAbsolutePath(
            "C:\\repo\\examples\\open_row_state_writer.zig",
            "C:/repo",
        ).?,
    );
}

test "resolveImportPathAt preserves parent-directory helpers for absolute caller-owned roots" {
    try std.testing.expectEqualStrings(
        "/tmp/shift-owned-open-row/helpers/util.zig",
        try resolveImportPathAt(
            "/tmp/shift-owned-open-row/nested/entry.zig",
            "../helpers/util.zig",
        ),
    );
}

test "resolveImportPathAt rejects helper imports that climb above the admitted absolute entry tree" {
    try std.testing.expectError(
        error.UnsupportedImportPath,
        resolveImportPathAt(
            "/tmp/shift-owned-open-row/nested/deeper/entry.zig",
            "../../outside_helper.zig",
        ),
    );
    try std.testing.expectError(
        error.UnsupportedImportPath,
        resolveImportPathAt(
            "/tmp/shift-owned-open-row/nested/entry.zig",
            "helpers/../../outside_helper.zig",
        ),
    );
}
