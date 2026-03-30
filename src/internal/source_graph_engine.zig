const std = @import("std");

/// Shared error surface for same-module source graph extraction.
pub const Error = error{
    EntryMissing,
    RecursiveHelpers,
    TooManyFunctions,
    TooManyHelperEdges,
    TooManyOpUses,
    UnsupportedEffectAccess,
};

/// Analysis options for the shared source-graph extractor.
pub const AnalyzeOptions = struct {
    entry_symbol: ?[]const u8 = null,
    reject_recursive_helpers: bool = false,
};

/// One top-level function discovered in a Zig source module.
pub const FunctionNode = struct {
    name: []const u8,
    effect_param: ?[]const u8,
};

/// One helper-call edge between top-level functions in the same source file.
pub const HelperEdge = struct {
    caller_index: usize,
    callee_index: usize,
    caller_name: []const u8,
    callee_name: []const u8,
    line: usize,
    column: usize,
};

/// One direct `eff.requirement.op(...)` use discovered inside a function body.
pub const DirectOpUse = struct {
    function_index: usize,
    requirement_label: []const u8,
    op_name: []const u8,
};

/// Shared same-module source graph returned by runtime and comptime extraction.
pub const ModuleGraph = struct {
    entry_index: ?usize,
    functions: []const FunctionNode,
    helper_edges: []const HelperEdge,
    direct_op_uses: []const DirectOpUse,
};

const AnalysisError = std.mem.Allocator.Error || Error;

const PendingIdentifier = struct {
    lexeme: []const u8,
    offset: usize,
};

const TokenItem = struct {
    tag: std.zig.Token.Tag,
    lexeme: []const u8,
};

const TokenWindow = struct {
    items: [6]TokenItem = [_]TokenItem{.{
        .tag = .invalid,
        .lexeme = "",
    }} ** 6,
    count: usize = 0,

    fn push(self: *@This(), item: TokenItem) void {
        if (self.count < self.items.len) {
            self.items[self.count] = item;
            self.count += 1;
            return;
        }
        var index: usize = 1;
        while (index < self.items.len) : (index += 1) {
            self.items[index - 1] = self.items[index];
        }
        self.items[self.items.len - 1] = item;
    }

    fn matchesDirectOpUse(self: *const @This(), effect_param: []const u8) ?DirectOpUseMatch {
        if (self.count < self.items.len) return null;
        const tail = self.items[self.count - self.items.len .. self.count];
        if (tail[0].tag != .identifier or !std.mem.eql(u8, tail[0].lexeme, effect_param)) return null;
        if (tail[1].tag != .period) return null;
        if (tail[2].tag != .identifier) return null;
        if (tail[3].tag != .period) return null;
        if (tail[4].tag != .identifier) return null;
        if (tail[5].tag != .l_paren) return null;
        return .{
            .requirement_label = tail[2].lexeme,
            .op_name = tail[4].lexeme,
        };
    }
};

const DirectOpUseMatch = struct {
    requirement_label: []const u8,
    op_name: []const u8,
};

const RuntimeCollector = struct {
    allocator: std.mem.Allocator,
    functions: std.ArrayList(FunctionNode) = .empty,
    helper_edges: std.ArrayList(HelperEdge) = .empty,
    direct_op_uses: std.ArrayList(DirectOpUse) = .empty,

    fn deinit(self: *@This()) void {
        self.functions.deinit(self.allocator);
        self.helper_edges.deinit(self.allocator);
        self.direct_op_uses.deinit(self.allocator);
    }

    fn pushFunction(self: *@This(), function: FunctionNode) AnalysisError!usize {
        try self.functions.append(self.allocator, function);
        return self.functions.items.len - 1;
    }

    fn functionsSlice(self: *const @This()) []const FunctionNode {
        return self.functions.items;
    }

    fn pushHelperEdge(self: *@This(), edge: HelperEdge) AnalysisError!void {
        try self.helper_edges.append(self.allocator, edge);
    }

    fn helperEdgesSlice(self: *const @This()) []const HelperEdge {
        return self.helper_edges.items;
    }

    fn helperEdgesSliceMut(self: *@This()) []HelperEdge {
        return self.helper_edges.items;
    }

    fn setHelperEdgeCount(self: *@This(), count: usize) void {
        self.helper_edges.items.len = count;
    }

    fn pushDirectOpUse(self: *@This(), direct_op_use: DirectOpUse) AnalysisError!void {
        try self.direct_op_uses.append(self.allocator, direct_op_use);
    }

    fn directOpUsesSlice(self: *const @This()) []const DirectOpUse {
        return self.direct_op_uses.items;
    }

    fn intoModuleGraph(self: *@This(), entry_index: ?usize) AnalysisError!ModuleGraph {
        const functions = try self.functions.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(functions);
        self.functions = .empty;

        const helper_edges = try self.helper_edges.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(helper_edges);
        self.helper_edges = .empty;

        const direct_op_uses = try self.direct_op_uses.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(direct_op_uses);
        self.direct_op_uses = .empty;

        return .{
            .entry_index = entry_index,
            .functions = functions,
            .helper_edges = helper_edges,
            .direct_op_uses = direct_op_uses,
        };
    }
};

const FixedCollector = struct {
    functions: [128]FunctionNode = [_]FunctionNode{.{
        .name = "",
        .effect_param = null,
    }} ** 128,
    function_count: usize = 0,
    helper_edges: [512]HelperEdge = [_]HelperEdge{.{
        .caller_index = 0,
        .callee_index = 0,
        .caller_name = "",
        .callee_name = "",
        .line = 0,
        .column = 0,
    }} ** 512,
    helper_edge_count: usize = 0,
    direct_op_uses: [1024]DirectOpUse = [_]DirectOpUse{.{
        .function_index = 0,
        .requirement_label = "",
        .op_name = "",
    }} ** 1024,
    direct_op_use_count: usize = 0,

    fn pushFunction(self: *@This(), function: FunctionNode) AnalysisError!usize {
        if (self.function_count >= self.functions.len) return error.TooManyFunctions;
        self.functions[self.function_count] = function;
        self.function_count += 1;
        return self.function_count - 1;
    }

    fn functionsSlice(self: *const @This()) []const FunctionNode {
        return self.functions[0..self.function_count];
    }

    fn pushHelperEdge(self: *@This(), edge: HelperEdge) AnalysisError!void {
        if (self.helper_edge_count >= self.helper_edges.len) return error.TooManyHelperEdges;
        self.helper_edges[self.helper_edge_count] = edge;
        self.helper_edge_count += 1;
    }

    fn helperEdgesSlice(self: *const @This()) []const HelperEdge {
        return self.helper_edges[0..self.helper_edge_count];
    }

    fn helperEdgesSliceMut(self: *@This()) []HelperEdge {
        return self.helper_edges[0..self.helper_edge_count];
    }

    fn setHelperEdgeCount(self: *@This(), count: usize) void {
        self.helper_edge_count = count;
    }

    fn pushDirectOpUse(self: *@This(), direct_op_use: DirectOpUse) AnalysisError!void {
        if (self.direct_op_use_count >= self.direct_op_uses.len) return error.TooManyOpUses;
        self.direct_op_uses[self.direct_op_use_count] = direct_op_use;
        self.direct_op_use_count += 1;
    }

    fn directOpUsesSlice(self: *const @This()) []const DirectOpUse {
        return self.direct_op_uses[0..self.direct_op_use_count];
    }

    fn intoModuleGraph(self: *const @This(), entry_index: ?usize) ModuleGraph {
        return .{
            .entry_index = entry_index,
            .functions = self.functions[0..self.function_count],
            .helper_edges = self.helper_edges[0..self.helper_edge_count],
            .direct_op_uses = self.direct_op_uses[0..self.direct_op_use_count],
        };
    }
};

fn isIgnorable(tag: std.zig.Token.Tag) bool {
    return switch (tag) {
        .doc_comment,
        .container_doc_comment,
        => true,
        else => false,
    };
}

fn tokenSlice(source: [:0]const u8, token: anytype) []const u8 {
    return source[token.loc.start..token.loc.end];
}

fn locationForOffset(source: []const u8, offset: usize) struct { line: usize, column: usize } {
    var line: usize = 1;
    var column: usize = 1;
    for (source[0..offset]) |byte| {
        if (byte == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }
    return .{ .line = line, .column = column };
}

fn findFunctionIndex(functions: []const FunctionNode, name: []const u8) ?usize {
    for (functions, 0..) |function, index| {
        if (std.mem.eql(u8, function.name, name)) return index;
    }
    return null;
}

fn edgeExists(edges: []const HelperEdge, caller_index: usize, callee_index: usize) bool {
    for (edges) |edge| {
        if (edge.caller_index == caller_index and edge.callee_index == callee_index) return true;
    }
    return false;
}

fn resolveHelperEdges(collector: anytype) void {
    const functions = collector.functionsSlice();
    var edges = collector.helperEdgesSliceMut();
    var write_index: usize = 0;

    for (edges, 0..) |edge, read_index| {
        const callee_index = findFunctionIndex(functions, edge.callee_name) orelse continue;
        if (callee_index == edge.caller_index) continue;

        const resolved = HelperEdge{
            .caller_index = edge.caller_index,
            .callee_index = callee_index,
            .caller_name = functions[edge.caller_index].name,
            .callee_name = functions[callee_index].name,
            .line = edge.line,
            .column = edge.column,
        };
        if (edgeExists(edges[0..write_index], resolved.caller_index, resolved.callee_index)) continue;
        edges[write_index] = resolved;
        _ = read_index;
        write_index += 1;
    }

    collector.setHelperEdgeCount(write_index);
}

fn visitCycle(function_index: usize, edges: []const HelperEdge, visiting: []bool, visited: []bool) Error!void {
    if (visiting[function_index]) return error.RecursiveHelpers;
    if (visited[function_index]) return;
    visiting[function_index] = true;
    for (edges) |edge| {
        if (edge.caller_index != function_index) continue;
        try visitCycle(edge.callee_index, edges, visiting, visited);
    }
    visiting[function_index] = false;
    visited[function_index] = true;
}

fn detectRecursiveHelpers(entry_index: usize, edges: []const HelperEdge) Error!void {
    var visiting = [_]bool{false} ** 128;
    var visited = [_]bool{false} ** 128;
    try visitCycle(entry_index, edges, visiting[0..], visited[0..]);
}

fn scanBody(
    source: [:0]const u8,
    tokenizer: *std.zig.Tokenizer,
    caller_index: usize,
    caller_name: []const u8,
    effect_param: ?[]const u8,
    collector: anytype,
) AnalysisError!void {
    var body_depth: usize = 1;
    var previous_kept_tag: ?std.zig.Token.Tag = null;
    var pending_identifier: ?PendingIdentifier = null;
    var token_window = TokenWindow{};

    while (body_depth != 0) {
        const token = tokenizer.next();
        switch (token.tag) {
            .eof => break,
            .l_brace => body_depth += 1,
            .r_brace => {
                body_depth -= 1;
                if (body_depth == 0) break;
            },
            else => {},
        }
        if (isIgnorable(token.tag)) continue;

        if (pending_identifier) |candidate| {
            if (token.tag == .l_paren) {
                const loc = locationForOffset(source, candidate.offset);
                try collector.pushHelperEdge(.{
                    .caller_index = caller_index,
                    .callee_index = 0,
                    .caller_name = caller_name,
                    .callee_name = candidate.lexeme,
                    .line = loc.line,
                    .column = loc.column,
                });
            }
            pending_identifier = null;
        }

        const current = TokenItem{
            .tag = token.tag,
            .lexeme = tokenSlice(source, token),
        };
        token_window.push(current);
        if (effect_param) |param| {
            if (token_window.matchesDirectOpUse(param)) |match| {
                try collector.pushDirectOpUse(.{
                    .function_index = caller_index,
                    .requirement_label = match.requirement_label,
                    .op_name = match.op_name,
                });
            }
        }

        if (token.tag == .identifier and previous_kept_tag != .period) {
            pending_identifier = .{
                .lexeme = current.lexeme,
                .offset = token.loc.start,
            };
        }
        previous_kept_tag = token.tag;
    }
}

fn scanSource(source: [:0]const u8, collector: anytype) AnalysisError!void {
    var tokenizer = std.zig.Tokenizer.init(source);
    var depth: usize = 0;

    while (true) {
        const token = tokenizer.next();
        switch (token.tag) {
            .eof => break,
            .l_brace => depth += 1,
            .r_brace => {
                if (depth != 0) depth -= 1;
            },
            .keyword_fn => {
                if (depth != 0) continue;

                var name_token = tokenizer.next();
                while (isIgnorable(name_token.tag)) : (name_token = tokenizer.next()) {}
                if (name_token.tag != .identifier) continue;
                const name = tokenSlice(source, name_token);

                var effect_param: ?[]const u8 = null;
                var param_candidate: ?[]const u8 = null;
                var param_depth: usize = 0;

                while (true) {
                    const next = tokenizer.next();
                    if (next.tag == .eof) break;
                    if (isIgnorable(next.tag)) continue;
                    if (next.tag == .l_paren) {
                        param_depth = 1;
                        break;
                    }
                }

                while (param_depth != 0) {
                    const next = tokenizer.next();
                    if (next.tag == .eof) break;
                    if (isIgnorable(next.tag)) continue;
                    switch (next.tag) {
                        .l_paren => param_depth += 1,
                        .r_paren => param_depth -= 1,
                        .comma => param_candidate = null,
                        .colon => if (param_depth == 1 and effect_param == null and param_candidate != null) {
                            effect_param = param_candidate;
                        },
                        .identifier => if (param_depth == 1 and param_candidate == null) {
                            param_candidate = tokenSlice(source, next);
                        },
                        else => {},
                    }
                }

                const function_index = try collector.pushFunction(.{
                    .name = name,
                    .effect_param = effect_param,
                });

                while (true) {
                    const next = tokenizer.next();
                    if (next.tag == .eof) break;
                    if (isIgnorable(next.tag)) continue;
                    switch (next.tag) {
                        .l_brace => {
                            try scanBody(source, &tokenizer, function_index, name, effect_param, collector);
                            break;
                        },
                        .semicolon => break,
                        else => {},
                    }
                }
            },
            else => {},
        }
    }
}

fn finalizeGraph(source: [:0]const u8, collector: anytype, options: AnalyzeOptions) AnalysisError!?usize {
    try scanSource(source, collector);
    resolveHelperEdges(collector);

    const entry_index: ?usize = if (options.entry_symbol) |entry_symbol|
        findFunctionIndex(collector.functionsSlice(), entry_symbol) orelse return error.EntryMissing
    else
        null;

    if (options.reject_recursive_helpers and entry_index != null) {
        try detectRecursiveHelpers(entry_index.?, collector.helperEdgesSlice());
    }
    return entry_index;
}

/// Analyze one same-module Zig source buffer at runtime through the shared source-graph engine.
pub fn analyzeRuntime(
    allocator: std.mem.Allocator,
    source: [:0]const u8,
    options: AnalyzeOptions,
) AnalysisError!ModuleGraph {
    var collector = RuntimeCollector{ .allocator = allocator };
    errdefer collector.deinit();

    const entry_index = try finalizeGraph(source, &collector, options);
    return try collector.intoModuleGraph(entry_index);
}

/// Analyze one same-module Zig source buffer at comptime through the shared source-graph engine.
pub fn analyzeComptime(
    comptime source: [:0]const u8,
    comptime options: AnalyzeOptions,
) Error!ModuleGraph {
    comptime {
        @setEvalBranchQuota(500_000);
    }

    var collector = FixedCollector{};
    const entry_index = try finalizeGraph(source, &collector, options);
    return collector.intoModuleGraph(entry_index);
}

test "shared engine finds helper edges and direct op uses" {
    const graph = try analyzeComptime(
        \\fn helper(eff: anytype) void {
        \\    _ = eff.writer.tell("queued");
        \\}
        \\pub fn runBody(eff: anytype) void {
        \\    _ = eff.state.get();
        \\    helper(eff);
        \\}
    ,
        .{
            .entry_symbol = "runBody",
            .reject_recursive_helpers = true,
        },
    );

    try std.testing.expectEqual(@as(usize, 2), graph.functions.len);
    try std.testing.expectEqual(@as(usize, 1), graph.entry_index.?);
    try std.testing.expectEqual(@as(usize, 1), graph.helper_edges.len);
    try std.testing.expectEqual(@as(usize, 2), graph.direct_op_uses.len);
    try std.testing.expectEqualStrings("runBody", graph.helper_edges[0].caller_name);
    try std.testing.expectEqualStrings("helper", graph.helper_edges[0].callee_name);
    try std.testing.expectEqualStrings("writer", graph.direct_op_uses[0].requirement_label);
    try std.testing.expectEqualStrings("tell", graph.direct_op_uses[0].op_name);
}

test "shared engine rejects recursive helper graphs" {
    try std.testing.expectError(error.RecursiveHelpers, analyzeComptime(
        \\fn helper() void { runBody(); }
        \\pub fn runBody() void { helper(); }
    ,
        .{
            .entry_symbol = "runBody",
            .reject_recursive_helpers = true,
        },
    ));
}
