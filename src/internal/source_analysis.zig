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
pub const TopLevelFunction = struct {
    name: []const u8,
    node: std.zig.Ast.Node.Index,
};

/// One conservative same-module helper call discovered inside a top-level function body.
pub const HelperCallEdge = struct {
    caller_name: []const u8,
    callee_name: []const u8,
    line: usize,
    column: usize,
};

/// One reusable same-module source analysis result.
pub const ModuleAnalysis = struct {
    parsed: ParsedSource,
    top_level_functions: []const TopLevelFunction,
    helper_call_edges: []const HelperCallEdge,

    /// Release the owned parse payload and derived analysis slices.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.top_level_functions);
        allocator.free(self.helper_call_edges);
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

/// Parse one Zig source buffer into an owned AST payload.
pub fn parseSource(allocator: std.mem.Allocator, source: []const u8) ParseSourceError!ParsedSource {
    const source_z = try allocator.dupeZ(u8, source);
    errdefer allocator.free(source_z);
    var tree = try std.zig.Ast.parse(allocator, source_z, .zig);
    errdefer tree.deinit(allocator);
    return .{
        .source_z = source_z,
        .tree = tree,
    };
}

fn collectTopLevelFunctions(
    allocator: std.mem.Allocator,
    tree: std.zig.Ast,
) std.mem.Allocator.Error![]const TopLevelFunction {
    var container_buffer: [2]std.zig.Ast.Node.Index = undefined;
    const root = tree.fullContainerDecl(&container_buffer, .root) orelse return try allocator.alloc(TopLevelFunction, 0);

    var functions = std.ArrayList(TopLevelFunction).empty;
    defer functions.deinit(allocator);

    for (root.ast.members) |member| {
        const name = topLevelFunctionName(tree, member) orelse continue;
        try functions.append(allocator, .{
            .name = name,
            .node = member,
        });
    }
    return try functions.toOwnedSlice(allocator);
}

fn findTopLevelFunction(functions: []const TopLevelFunction, name: []const u8) ?TopLevelFunction {
    for (functions) |function| {
        if (std.mem.eql(u8, function.name, name)) return function;
    }
    return null;
}

fn nextKeptTokenIndex(
    tree: std.zig.Ast,
    first_index: usize,
    last_index: usize,
) ?std.zig.Ast.TokenIndex {
    var raw_index = first_index;
    while (raw_index <= last_index) : (raw_index += 1) {
        const token_index: std.zig.Ast.TokenIndex = @intCast(raw_index);
        const tag = tree.tokenTag(token_index);
        if (shouldSkipToken(tag)) continue;
        return token_index;
    }
    return null;
}

fn shouldSkipToken(tag: std.zig.Token.Tag) bool {
    return switch (tag) {
        .doc_comment, .container_doc_comment => true,
        else => false,
    };
}

fn collectHelperCallEdges(
    allocator: std.mem.Allocator,
    tree: std.zig.Ast,
    functions: []const TopLevelFunction,
) std.mem.Allocator.Error![]const HelperCallEdge {
    var edges = std.ArrayList(HelperCallEdge).empty;
    defer edges.deinit(allocator);

    for (functions) |function| {
        const first = tree.firstToken(function.node);
        const last = tree.lastToken(function.node);
        var previous_kept_tag: ?std.zig.Token.Tag = null;
        var raw_index: usize = first;
        while (raw_index <= last) : (raw_index += 1) {
            const token_index: std.zig.Ast.TokenIndex = @intCast(raw_index);
            const tag = tree.tokenTag(token_index);
            if (shouldSkipToken(tag)) continue;

            if (tag == .identifier and previous_kept_tag != .period) {
                const next_token = nextKeptTokenIndex(tree, raw_index + 1, last);
                if (next_token != null and tree.tokenTag(next_token.?) == .l_paren) {
                    const callee_name = tree.tokenSlice(token_index);
                    if (findTopLevelFunction(functions, callee_name)) |callee|
                        if (!std.mem.eql(u8, callee.name, function.name)) {
                            const loc = tree.tokenLocation(0, token_index);
                            try edges.append(allocator, .{
                                .caller_name = function.name,
                                .callee_name = callee.name,
                                .line = loc.line + 1,
                                .column = loc.column + 1,
                            });
                        };
                }
            }

            previous_kept_tag = tag;
        }
    }

    return try edges.toOwnedSlice(allocator);
}

/// Parse and analyze one same-module Zig source buffer.
pub fn analyzeModuleSource(allocator: std.mem.Allocator, source: []const u8) ParseSourceError!ModuleAnalysis {
    var parsed = try parseSource(allocator, source);
    errdefer parsed.deinit(allocator);

    const top_level_functions = try collectTopLevelFunctions(allocator, parsed.tree);
    errdefer allocator.free(top_level_functions);

    const helper_call_edges = try collectHelperCallEdges(allocator, parsed.tree, top_level_functions);
    errdefer allocator.free(helper_call_edges);

    return .{
        .parsed = parsed,
        .top_level_functions = top_level_functions,
        .helper_call_edges = helper_call_edges,
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
