const shared_graph = @import("source_graph_engine");
const std = @import("std");

/// Parsed source text plus the AST that owns token views into it.
pub const ParsedSource = struct {
    source_z: [:0]u8,
    tree: std.zig.Ast,

    /// Release the owned source buffer and AST storage.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.tree.deinit(allocator);
        allocator.free(self.source_z);
        self.* = undefined;
    }
};

/// One top-level function discovered in a parsed Zig source module.
pub const TopLevelFunction = shared_graph.FunctionNode;
/// One top-level import alias discovered in a parsed Zig source module.
pub const ImportAlias = shared_graph.ImportAlias;
/// One helper use discovered before same-file or cross-file resolution.
pub const HelperUse = shared_graph.HelperUse;
/// One conservative same-module helper call discovered inside a top-level function body.
pub const HelperCallEdge = shared_graph.HelperEdge;
/// One direct effect-op use discovered through the shared source graph.
pub const DirectOpUse = shared_graph.DirectOpUse;

/// One reusable same-module source analysis result.
pub const ModuleAnalysis = struct {
    parsed: ParsedSource,
    top_level_functions: []const TopLevelFunction,
    imports: []const ImportAlias,
    helper_uses: []const HelperUse,
    helper_call_edges: []const HelperCallEdge,
    direct_op_uses: []const DirectOpUse,

    /// Release the owned parse payload and derived analysis slices.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.top_level_functions);
        allocator.free(self.imports);
        allocator.free(self.helper_uses);
        allocator.free(self.helper_call_edges);
        allocator.free(self.direct_op_uses);
        self.parsed.deinit(allocator);
        self.* = undefined;
    }

    /// Return whether the parsed source contains no syntax errors.
    pub fn isParseClean(self: *const @This()) bool {
        return self.parsed.tree.errors.len == 0;
    }

    /// Return whether the parsed source has a top-level function with `name`.
    pub fn hasTopLevelFunctionNamed(self: *const @This(), name: []const u8) bool {
        return findTopLevelFunction(self.top_level_functions, name) != null;
    }

    /// Return one top-level function declaration by name, if present.
    pub fn topLevelFunctionNamed(self: *const @This(), name: []const u8) ?TopLevelFunction {
        return findTopLevelFunction(self.top_level_functions, name);
    }
};

/// Error surface for parsing source buffers into owned AST payloads.
pub const ParseSourceError = error{OutOfMemory};
/// Error surface for generic same-module source analysis.
pub const AnalyzeModuleSourceError = ParseSourceError || error{
    TooManyFunctions,
    TooManyFunctionParams,
    TooManyImports,
    TooManyHelperUses,
    TooManyHelperEdges,
    TooManyOpUses,
    UnsupportedEffectAccess,
};

/// Parse one Zig source buffer into an owned AST payload.
pub fn parseSource(allocator: std.mem.Allocator, source: []const u8) ParseSourceError!ParsedSource {
    const source_z = try allocator.dupeSentinel(u8, source, 0);
    errdefer allocator.free(source_z);
    var tree = try std.zig.Ast.parse(allocator, source_z, .zig);
    errdefer tree.deinit(allocator);
    return .{
        .source_z = source_z,
        .tree = tree,
    };
}

fn findTopLevelFunction(functions: []const TopLevelFunction, name: []const u8) ?TopLevelFunction {
    for (functions) |function| {
        if (std.mem.eql(u8, function.name, name)) return function;
    }
    return null;
}

/// Parse and analyze one same-module Zig source buffer.
pub fn analyzeModuleSource(allocator: std.mem.Allocator, source: []const u8) AnalyzeModuleSourceError!ModuleAnalysis {
    var parsed = try parseSource(allocator, source);
    errdefer parsed.deinit(allocator);

    const graph = shared_graph.analyzeRuntime(allocator, parsed.source_z, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.TooManyFunctions => return error.TooManyFunctions,
        error.TooManyFunctionParams => return error.TooManyFunctionParams,
        error.TooManyImports => return error.TooManyImports,
        error.TooManyHelperUses => return error.TooManyHelperUses,
        error.TooManyHelperEdges => return error.TooManyHelperEdges,
        error.TooManyOpUses => return error.TooManyOpUses,
        error.UnsupportedEffectAccess => return error.UnsupportedEffectAccess,
        else => unreachable,
    };
    errdefer {
        allocator.free(graph.functions);
        allocator.free(graph.imports);
        allocator.free(graph.helper_uses);
        allocator.free(graph.helper_edges);
        allocator.free(graph.direct_op_uses);
    }

    return .{
        .parsed = parsed,
        .top_level_functions = graph.functions,
        .imports = graph.imports,
        .helper_uses = graph.helper_uses,
        .helper_call_edges = graph.helper_edges,
        .direct_op_uses = graph.direct_op_uses,
    };
}

/// Return whether the parsed source has a top-level function with `name`.
pub fn hasTopLevelFunctionNamed(tree: std.zig.Ast, name: []const u8) bool {
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

/// Return the name of one top-level function member, if the member is a function with a name.
pub fn topLevelFunctionName(tree: std.zig.Ast, member: std.zig.Ast.Node.Index) ?[]const u8 {
    var fn_buffer: [1]std.zig.Ast.Node.Index = undefined;
    const fn_proto = tree.fullFnProto(&fn_buffer, member) orelse return null;
    const name_token = fn_proto.name_token orelse return null;
    return tree.tokenSlice(name_token);
}

test "parseSource preserves top-level function names" {
    var parsed = try parseSource(std.testing.allocator,
        \\pub fn alpha() void {}
        \\fn beta() void {}
    );
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expect(hasTopLevelFunctionNamed(parsed.tree, "alpha"));
    try std.testing.expect(hasTopLevelFunctionNamed(parsed.tree, "beta"));
    try std.testing.expect(!hasTopLevelFunctionNamed(parsed.tree, "gamma"));
}

test "analyzeModuleSource infers top-level helpers without proof coupling" {
    var analysis = try analyzeModuleSource(std.testing.allocator,
        \\fn helper() void {}
        \\fn nested() void {
        \\    helper();
        \\}
        \\pub fn entry() void {
        \\    nested();
        \\}
    );
    defer analysis.deinit(std.testing.allocator);

    try std.testing.expect(analysis.isParseClean());
    try std.testing.expectEqual(@as(usize, 3), analysis.top_level_functions.len);
    try std.testing.expect(analysis.hasTopLevelFunctionNamed("entry"));
    try std.testing.expectEqualStrings("helper", analysis.helper_call_edges[0].callee_name);
    try std.testing.expectEqualStrings("nested", analysis.helper_call_edges[1].callee_name);
    try std.testing.expectEqual(@as(usize, 2), analysis.helper_call_edges.len);
}
