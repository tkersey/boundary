const build_options = @import("authoring_build_options");
const source_graph_comptime = @import("source_graph_comptime");
const source_graph_engine = @import("source_graph_engine");
const std = @import("std");

/// Shared error surface for repo-root embedded source graph analysis.
pub const Error = source_graph_engine.Error;

/// One function in a flattened explicit-path program graph.
pub const ProgramFunction = struct {
    module_path: []const u8,
    name: []const u8,
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

fn repoRelativePath(comptime source_path: []const u8) []const u8 {
    if (std.fs.path.isAbsolute(source_path)) {
        if (!std.mem.startsWith(u8, source_path, build_options.package_root)) {
            @compileError("public lowering source path must stay under the package root");
        }
        if (source_path.len <= build_options.package_root.len or source_path[build_options.package_root.len] != std.fs.path.sep) {
            @compileError("public lowering source path must point to a file under the package root");
        }
        return source_path[build_options.package_root.len + 1 ..];
    }
    return source_path;
}

/// Embed one repo-relative source file through a repo-root module so examples remain package-visible.
pub fn embeddedSource(comptime source_path: []const u8) [:0]const u8 {
    return @embedFile(repoRelativePath(source_path));
}

/// Analyze one repo-relative source file through the shared comptime source-graph extractor.
pub fn analyzeModuleAt(comptime source_path: []const u8, comptime entry_symbol: []const u8) source_graph_comptime.Error!source_graph_comptime.ModuleGraph {
    return source_graph_comptime.analyzeModule(embeddedSource(source_path), entry_symbol);
}

fn dirname(comptime path: []const u8) []const u8 {
    return std.fs.path.dirname(path) orelse "";
}

fn resolveImportPath(comptime from_path: []const u8, comptime import_path: []const u8) Error![]const u8 {
    if (std.mem.startsWith(u8, import_path, "/")) return error.UnsupportedImportPath;
    if (!std.mem.endsWith(u8, import_path, ".zig")) return error.UnsupportedImportPath;

    const base_dir = dirname(repoRelativePath(from_path));
    const joined = if (base_dir.len == 0)
        import_path
    else
        std.fmt.comptimePrint("{s}/{s}", .{ base_dir, import_path });

    var segments = [_][]const u8{""} ** 64;
    var segment_count: usize = 0;
    var start: usize = 0;
    var index: usize = 0;
    while (index <= joined.len) : (index += 1) {
        if (index != joined.len and joined[index] != '/') continue;
        const segment = joined[start..index];
        start = index + 1;
        if (segment.len == 0 or std.mem.eql(u8, segment, ".")) continue;
        if (std.mem.eql(u8, segment, "..")) {
            if (segment_count == 0) return error.UnsupportedImportPath;
            segment_count -= 1;
            continue;
        }
        if (segment_count >= segments.len) return error.TooManyImports;
        segments[segment_count] = segment;
        segment_count += 1;
    }

    return comptime blk: {
        if (segment_count == 0) break :blk "";
        var result = segments[0];
        for (segments[1..segment_count]) |segment| {
            result = std.fmt.comptimePrint("{s}/{s}", .{ result, segment });
        }
        break :blk result;
    };
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
    comptime entry_symbol: ?[]const u8,
) Error!source_graph_engine.ModuleGraph {
    return source_graph_engine.analyzeComptime(embeddedSource(source_path), .{
        .entry_symbol = entry_symbol,
        .reject_recursive_helpers = false,
        .reject_indirect_effect_access = true,
    });
}

fn collectModule(comptime source_path: []const u8, buffers: *Buffers) Error!ModuleSummary {
    if (findModule(buffers, source_path)) |existing| return existing;

    if (buffers.module_count >= buffers.modules.len) return error.TooManyImports;
    const graph = try analyzeOwnedModule(source_path, null);
    const first_function_index = buffers.function_count;

    if (buffers.function_count + graph.functions.len > buffers.functions.len) return error.TooManyFunctions;
    for (graph.functions) |function| {
        buffers.functions[buffers.function_count] = .{
            .module_path = source_path,
            .name = function.name,
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
        const imported = try collectModule(imported_path, buffers);
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
    var buffers = Buffers{};
    const root = try collectModule(source_path, &buffers);
    const root_graph = try analyzeOwnedModule(source_path, entry_symbol);
    const entry_local_index = root_graph.entry_index orelse return error.EntryMissing;
    const entry_index = root.first_function_index + entry_local_index;

    return .{
        .entry_index = entry_index,
        .functions = buffers.functions[0..buffers.function_count],
        .helper_edges = buffers.helper_edges[0..buffers.helper_edge_count],
        .direct_op_uses = buffers.direct_op_uses[0..buffers.direct_op_use_count],
    };
}
