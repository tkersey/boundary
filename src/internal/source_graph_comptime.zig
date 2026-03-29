const std = @import("std");

/// Error surface for comptime helper/source graph extraction.
pub const Error = error{
    EntryMissing,
    RecursiveHelpers,
    TooManyFunctions,
    TooManyHelperEdges,
    TooManyOpUses,
    UnsupportedEffectAccess,
};

/// One top-level function discovered by the comptime source extractor.
pub const FunctionNode = struct {
    name: []const u8,
    effect_param: ?[]const u8,
    body: []const u8,
};

/// One helper-call edge between top-level functions in the same source file.
pub const HelperEdge = struct {
    caller_index: usize,
    callee_index: usize,
};

/// One direct `eff.requirement.op(...)` use discovered inside a function body.
pub const DirectOpUse = struct {
    function_index: usize,
    requirement_label: []const u8,
    op_name: []const u8,
};

/// Comptime-extracted same-file helper graph and direct op-use summary.
pub const ModuleGraph = struct {
    entry_index: usize,
    functions: []const FunctionNode,
    helper_edges: []const HelperEdge,
    direct_op_uses: []const DirectOpUse,
};

const TokenItem = struct {
    tag: std.zig.Token.Tag,
    lexeme: []const u8,
};

fn isIgnorable(tag: std.zig.Token.Tag) bool {
    return switch (tag) {
        .doc_comment,
        .container_doc_comment,
        => true,
        else => false,
    };
}

fn tokenSlice(source: []const u8, token: anytype) []const u8 {
    return source[token.loc.start..token.loc.end];
}

fn pushFunction(
    comptime functions: *[128]FunctionNode,
    comptime count: *usize,
    function: FunctionNode,
) Error!void {
    if (count.* >= functions.len) return error.TooManyFunctions;
    functions[count.*] = function;
    count.* += 1;
}

fn parseTopLevelFunctions(comptime source: [:0]const u8) Error!struct {
    count: usize,
    functions: [128]FunctionNode,
} {
    var functions = [_]FunctionNode{.{
        .name = "",
        .effect_param = null,
        .body = "",
    }} ** 128;
    var count: usize = 0;
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
                if (depth != 0) {
                    continue;
                }

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

                var body_open: ?usize = null;
                while (body_open == null) {
                    const next = tokenizer.next();
                    if (next.tag == .eof) break;
                    if (isIgnorable(next.tag)) continue;
                    switch (next.tag) {
                        .l_brace => body_open = next.loc.start,
                        .semicolon => break,
                        else => {},
                    }
                }
                if (body_open == null) continue;

                var body_depth: usize = 1;
                var body_close: ?usize = null;
                while (body_depth != 0) {
                    const next = tokenizer.next();
                    switch (next.tag) {
                        .eof => break,
                        .l_brace => body_depth += 1,
                        .r_brace => {
                            body_depth -= 1;
                            if (body_depth == 0) {
                                body_close = next.loc.start;
                                break;
                            }
                        },
                        else => {},
                    }
                }
                if (body_close == null) continue;

                try pushFunction(&functions, &count, .{
                    .name = name,
                    .effect_param = effect_param,
                    .body = source[body_open.? + 1 .. body_close.?],
                });
            },
            else => {},
        }
    }

    return .{ .count = count, .functions = functions };
}

fn functionIndexByName(functions: []const FunctionNode, name: []const u8) ?usize {
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

fn pushHelperEdge(
    comptime edges: *[512]HelperEdge,
    comptime count: *usize,
    caller_index: usize,
    callee_index: usize,
) Error!void {
    if (edgeExists(edges[0..count.*], caller_index, callee_index)) return;
    if (count.* >= edges.len) return error.TooManyHelperEdges;
    edges[count.*] = .{ .caller_index = caller_index, .callee_index = callee_index };
    count.* += 1;
}

fn pushDirectOpUse(
    comptime uses: *[1024]DirectOpUse,
    comptime count: *usize,
    function_index: usize,
    requirement_label: []const u8,
    op_name: []const u8,
) Error!void {
    if (count.* >= uses.len) return error.TooManyOpUses;
    uses[count.*] = .{
        .function_index = function_index,
        .requirement_label = requirement_label,
        .op_name = op_name,
    };
    count.* += 1;
}

fn tokenizeBody(comptime body: []const u8) struct {
    tokens: [body.len]TokenItem,
    count: usize,
} {
    var tokens = [_]TokenItem{.{
        .tag = .invalid,
        .lexeme = "",
    }} ** body.len;
    const sentinel_body = std.fmt.comptimePrint("{s}\x00", .{body});
    var tokenizer = std.zig.Tokenizer.init(sentinel_body);
    var count: usize = 0;
    var index: usize = 0;
    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) break;
        if (isIgnorable(token.tag)) continue;
        tokens[index] = .{
            .tag = token.tag,
            .lexeme = tokenSlice(sentinel_body, token),
        };
        index += 1;
        count += 1;
    }
    return .{
        .tokens = tokens,
        .count = count,
    };
}

const BodyAnalysisBuffers = struct {
    helper_edges: *[512]HelperEdge,
    helper_edge_count: *usize,
    direct_op_uses: *[1024]DirectOpUse,
    direct_op_use_count: *usize,
};

fn analyzeBody(function_index: usize, functions: []const FunctionNode, buffers: BodyAnalysisBuffers) Error!void {
    const function = functions[function_index];
    const tokenized = comptime tokenizeBody(function.body);
    const body_tokens = tokenized.tokens;
    const token_count = tokenized.count;

    var index: usize = 0;
    while (index < token_count) : (index += 1) {
        const current = body_tokens[index];
        if (current.tag != .identifier) continue;

        if (function.effect_param) |effect_param| {
            if (std.mem.eql(u8, current.lexeme, effect_param)) {
                if (index + 5 < token_count and
                    body_tokens[index + 1].tag == .period and
                    body_tokens[index + 2].tag == .identifier and
                    body_tokens[index + 3].tag == .period and
                    body_tokens[index + 4].tag == .identifier and
                    body_tokens[index + 5].tag == .l_paren)
                {
                    try pushDirectOpUse(
                        buffers.direct_op_uses,
                        buffers.direct_op_use_count,
                        function_index,
                        body_tokens[index + 2].lexeme,
                        body_tokens[index + 4].lexeme,
                    );
                    index += 5;
                    continue;
                }
                continue;
            }
        }

        if (index + 1 >= token_count) continue;
        if (body_tokens[index + 1].tag != .l_paren) continue;
        if (index != 0 and body_tokens[index - 1].tag == .period) continue;

        const callee_index = functionIndexByName(functions, current.lexeme) orelse continue;
        if (callee_index == function_index) continue;
        try pushHelperEdge(buffers.helper_edges, buffers.helper_edge_count, function_index, callee_index);
    }
}

fn visitCycle(
    comptime function_index: usize,
    comptime edges: []const HelperEdge,
    visiting: *[128]bool,
    visited: *[128]bool,
) Error!void {
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

/// Parse and analyze one same-module Zig source buffer at comptime.
pub fn analyzeModule(comptime source: [:0]const u8, comptime entry_symbol: []const u8) Error!ModuleGraph {
    comptime {
        @setEvalBranchQuota(500_000);
    }
    const parsed = try parseTopLevelFunctions(source);
    const functions = parsed.functions[0..parsed.count];
    const entry_index = functionIndexByName(functions, entry_symbol) orelse return error.EntryMissing;

    var helper_edges_buffer: [512]HelperEdge = undefined;
    var helper_edge_count: usize = 0;
    var direct_op_uses_buffer: [1024]DirectOpUse = undefined;
    var direct_op_use_count: usize = 0;

    for (functions, 0..) |_, function_index| {
        try analyzeBody(
            function_index,
            functions,
            .{
                .helper_edges = &helper_edges_buffer,
                .helper_edge_count = &helper_edge_count,
                .direct_op_uses = &direct_op_uses_buffer,
                .direct_op_use_count = &direct_op_use_count,
            },
        );
    }

    var visiting = [_]bool{false} ** 128;
    var visited = [_]bool{false} ** 128;
    try visitCycle(entry_index, helper_edges_buffer[0..helper_edge_count], &visiting, &visited);

    return .{
        .entry_index = entry_index,
        .functions = functions,
        .helper_edges = helper_edges_buffer[0..helper_edge_count],
        .direct_op_uses = direct_op_uses_buffer[0..direct_op_use_count],
    };
}

test "analyzeModule finds helper edges and direct op uses" {
    const graph = try analyzeModule(
        \\fn helper(eff: anytype) void {
        \\    _ = eff.writer.tell("queued");
        \\}
        \\pub fn runBody(eff: anytype) void {
        \\    _ = eff.state.get();
        \\    helper(eff);
        \\}
    ,
        "runBody",
    );

    try std.testing.expectEqual(@as(usize, 2), graph.functions.len);
    try std.testing.expectEqual(@as(usize, 1), graph.entry_index);
    try std.testing.expectEqual(@as(usize, 1), graph.helper_edges.len);
    try std.testing.expectEqual(@as(usize, 2), graph.direct_op_uses.len);
    try std.testing.expectEqualStrings("writer", graph.direct_op_uses[0].requirement_label);
    try std.testing.expectEqualStrings("tell", graph.direct_op_uses[0].op_name);
}

test "analyzeModule rejects recursive helper graphs" {
    try std.testing.expectError(error.RecursiveHelpers, analyzeModule(
        \\fn helper() void { runBody(); }
        \\pub fn runBody() void { helper(); }
    ,
        "runBody",
    ));
}
