const std = @import("std");

/// Shared error surface for same-module source graph extraction.
pub const Error = error{
    EntryMissing,
    MissingImport,
    RecursiveHelpers,
    TooManyFunctions,
    TooManyImports,
    TooManyHelperUses,
    TooManyHelperEdges,
    TooManyOpUses,
    UnsupportedEffectAccess,
    UnsupportedImportPath,
};

/// Analysis options for the shared source-graph extractor.
pub const AnalyzeOptions = struct {
    entry_symbol: ?[]const u8 = null,
    reject_recursive_helpers: bool = false,
    reject_indirect_effect_access: bool = false,
};

/// One top-level function discovered in a Zig source module.
pub const FunctionNode = struct {
    name: []const u8,
    effect_param: ?[]const u8,
};

/// One top-level import alias discovered in a Zig source module.
pub const ImportAlias = struct {
    name: []const u8,
    import_path: []const u8,
};

/// One helper call discovered before same-file or cross-file resolution.
pub const HelperUse = struct {
    caller_index: usize,
    callee_name: []const u8,
    import_alias: ?[]const u8,
    line: usize,
    column: usize,
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
    imports: []const ImportAlias,
    helper_uses: []const HelperUse,
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
    offset: usize,
};

const TokenWindow = struct {
    items: [8]TokenItem = [_]TokenItem{.{
        .tag = .invalid,
        .lexeme = "",
        .offset = 0,
    }} ** 8,
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
};

const DirectOpUseMatch = struct {
    requirement_label: []const u8,
    op_name: []const u8,
};

const AliasKind = union(enum) {
    effect_root,
    requirement: []const u8,
};

const Alias = struct {
    name: []const u8,
    kind: AliasKind,
};

const TopLevelImportMatch = struct {
    name: []const u8,
    import_path: []const u8,
};

fn unquoteImportPath(literal: []const u8) ?[]const u8 {
    if (literal.len < 2) return null;
    if (literal[0] != '"' or literal[literal.len - 1] != '"') return null;
    return literal[1 .. literal.len - 1];
}

const RuntimeCollector = struct {
    allocator: std.mem.Allocator,
    functions: std.ArrayList(FunctionNode) = .empty,
    imports: std.ArrayList(ImportAlias) = .empty,
    helper_uses: std.ArrayList(HelperUse) = .empty,
    helper_edges: std.ArrayList(HelperEdge) = .empty,
    direct_op_uses: std.ArrayList(DirectOpUse) = .empty,

    fn deinit(self: *@This()) void {
        self.functions.deinit(self.allocator);
        self.imports.deinit(self.allocator);
        self.helper_uses.deinit(self.allocator);
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

    fn pushImport(self: *@This(), import_alias: ImportAlias) AnalysisError!void {
        try self.imports.append(self.allocator, import_alias);
    }

    fn importsSlice(self: *const @This()) []const ImportAlias {
        return self.imports.items;
    }

    fn pushHelperUse(self: *@This(), helper_use: HelperUse) AnalysisError!void {
        try self.helper_uses.append(self.allocator, helper_use);
    }

    fn helperUsesSlice(self: *const @This()) []const HelperUse {
        return self.helper_uses.items;
    }

    fn pushHelperEdge(self: *@This(), edge: HelperEdge) AnalysisError!void {
        if (edgeExists(self.helper_edges.items, edge.caller_index, edge.callee_index)) return;
        try self.helper_edges.append(self.allocator, edge);
    }

    fn helperEdgesSlice(self: *const @This()) []const HelperEdge {
        return self.helper_edges.items;
    }

    fn clearHelperEdges(self: *@This()) void {
        self.helper_edges.items.len = 0;
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

        const imports = try self.imports.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(imports);
        self.imports = .empty;

        const helper_uses = try self.helper_uses.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(helper_uses);
        self.helper_uses = .empty;

        const helper_edges = try self.helper_edges.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(helper_edges);
        self.helper_edges = .empty;

        const direct_op_uses = try self.direct_op_uses.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(direct_op_uses);
        self.direct_op_uses = .empty;

        return .{
            .entry_index = entry_index,
            .functions = functions,
            .imports = imports,
            .helper_uses = helper_uses,
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
    imports: [64]ImportAlias = [_]ImportAlias{.{
        .name = "",
        .import_path = "",
    }} ** 64,
    import_count: usize = 0,
    helper_uses: [1024]HelperUse = [_]HelperUse{.{
        .caller_index = 0,
        .callee_name = "",
        .import_alias = null,
        .line = 0,
        .column = 0,
    }} ** 1024,
    helper_use_count: usize = 0,
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

    fn pushImport(self: *@This(), import_alias: ImportAlias) AnalysisError!void {
        if (self.import_count >= self.imports.len) return error.TooManyImports;
        self.imports[self.import_count] = import_alias;
        self.import_count += 1;
    }

    fn importsSlice(self: *const @This()) []const ImportAlias {
        return self.imports[0..self.import_count];
    }

    fn pushHelperUse(self: *@This(), helper_use: HelperUse) AnalysisError!void {
        if (self.helper_use_count >= self.helper_uses.len) return error.TooManyHelperUses;
        self.helper_uses[self.helper_use_count] = helper_use;
        self.helper_use_count += 1;
    }

    fn helperUsesSlice(self: *const @This()) []const HelperUse {
        return self.helper_uses[0..self.helper_use_count];
    }

    fn pushHelperEdge(self: *@This(), edge: HelperEdge) AnalysisError!void {
        if (edgeExists(self.helper_edges[0..self.helper_edge_count], edge.caller_index, edge.callee_index)) return;
        if (self.helper_edge_count >= self.helper_edges.len) return error.TooManyHelperEdges;
        self.helper_edges[self.helper_edge_count] = edge;
        self.helper_edge_count += 1;
    }

    fn helperEdgesSlice(self: *const @This()) []const HelperEdge {
        return self.helper_edges[0..self.helper_edge_count];
    }

    fn clearHelperEdges(self: *@This()) void {
        self.helper_edge_count = 0;
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
            .imports = self.imports[0..self.import_count],
            .helper_uses = self.helper_uses[0..self.helper_use_count],
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

fn aliasKind(effect_param: ?[]const u8, aliases: []const Alias, name: []const u8) ?AliasKind {
    if (effect_param) |param| {
        if (std.mem.eql(u8, param, name)) return .effect_root;
    }
    for (aliases) |alias| {
        if (std.mem.eql(u8, alias.name, name)) return alias.kind;
    }
    return null;
}

fn upsertAlias(aliases: []Alias, alias_count: *usize, name: []const u8, kind: AliasKind) Error!void {
    for (aliases[0..alias_count.*]) |*alias| {
        if (!std.mem.eql(u8, alias.name, name)) continue;
        alias.kind = kind;
        return;
    }
    if (alias_count.* >= aliases.len) return error.TooManyFunctions;
    aliases[alias_count.*] = .{
        .name = name,
        .kind = kind,
    };
    alias_count.* += 1;
}

fn maybeAliasFromDeclaration(
    effect_param: ?[]const u8,
    aliases: []Alias,
    token_window: *const TokenWindow,
) ?struct {
    name: []const u8,
    kind: AliasKind,
} {
    if (token_window.count >= 5) {
        const tail = token_window.items[token_window.count - 5 .. token_window.count];
        if ((tail[0].tag == .keyword_const or tail[0].tag == .keyword_var) and
            tail[1].tag == .identifier and
            tail[2].tag == .equal and
            tail[3].tag == .identifier and
            tail[4].tag == .semicolon)
        {
            const source_kind = aliasKind(effect_param, aliases, tail[3].lexeme) orelse return null;
            return .{
                .name = tail[1].lexeme,
                .kind = source_kind,
            };
        }
    }

    if (token_window.count >= 7) {
        const tail = token_window.items[token_window.count - 7 .. token_window.count];
        if ((tail[0].tag == .keyword_const or tail[0].tag == .keyword_var) and
            tail[1].tag == .identifier and
            tail[2].tag == .equal and
            tail[3].tag == .identifier and
            tail[4].tag == .period and
            tail[5].tag == .identifier and
            tail[6].tag == .semicolon)
        {
            const source_kind = aliasKind(effect_param, aliases, tail[3].lexeme) orelse return null;
            return switch (source_kind) {
                .effect_root => .{
                    .name = tail[1].lexeme,
                    .kind = .{ .requirement = tail[5].lexeme },
                },
                .requirement => null,
            };
        }
    }

    return null;
}

fn maybeRecordDirectOpUse(
    effect_param: ?[]const u8,
    aliases: []const Alias,
    token_window: *const TokenWindow,
) ?DirectOpUseMatch {
    if (token_window.count >= 6) {
        const tail = token_window.items[token_window.count - 6 .. token_window.count];
        if (tail[0].tag == .identifier and
            tail[1].tag == .period and
            tail[2].tag == .identifier and
            tail[3].tag == .period and
            tail[4].tag == .identifier and
            tail[5].tag == .l_paren)
        {
            const source_kind = aliasKind(effect_param, aliases, tail[0].lexeme) orelse return null;
            return switch (source_kind) {
                .effect_root => .{
                    .requirement_label = tail[2].lexeme,
                    .op_name = tail[4].lexeme,
                },
                .requirement => null,
            };
        }
    }

    if (token_window.count >= 4) {
        const tail = token_window.items[token_window.count - 4 .. token_window.count];
        if (tail[0].tag == .identifier and
            tail[1].tag == .period and
            tail[2].tag == .identifier and
            tail[3].tag == .l_paren)
        {
            const source_kind = aliasKind(effect_param, aliases, tail[0].lexeme) orelse return null;
            return switch (source_kind) {
                .effect_root => null,
                .requirement => |requirement_label| .{
                    .requirement_label = requirement_label,
                    .op_name = tail[2].lexeme,
                },
            };
        }
    }

    return null;
}

fn isAllowedAccessFollowTag(tag: std.zig.Token.Tag) bool {
    return switch (tag) {
        .period, .semicolon => true,
        else => false,
    };
}

fn isAllowedRequirementAliasFollowTag(tag: std.zig.Token.Tag) bool {
    return switch (tag) {
        .period, .semicolon, .equal => true,
        else => false,
    };
}

fn isEffectParamName(name: []const u8) bool {
    return std.mem.eql(u8, name, "eff");
}

fn maybeUnsupportedEffectAccess(
    effect_param: ?[]const u8,
    aliases: []const Alias,
    token_window: *const TokenWindow,
) bool {
    if (token_window.count >= 4) {
        const tail = token_window.items[token_window.count - 4 .. token_window.count];
        if (tail[0].tag == .identifier and
            tail[1].tag == .period and
            tail[2].tag == .identifier)
        {
            const source_kind = aliasKind(effect_param, aliases, tail[0].lexeme) orelse return false;
            return switch (source_kind) {
                .effect_root => !isAllowedAccessFollowTag(tail[3].tag),
                .requirement => false,
            };
        }
    }

    if (token_window.count >= 2) {
        const tail = token_window.items[token_window.count - 2 .. token_window.count];
        if (tail[0].tag == .identifier) {
            const source_kind = aliasKind(effect_param, aliases, tail[0].lexeme) orelse return false;
            return switch (source_kind) {
                .effect_root => false,
                .requirement => !isAllowedRequirementAliasFollowTag(tail[1].tag),
            };
        }
    }

    return false;
}

fn findImportAlias(imports: []const ImportAlias, name: []const u8) ?ImportAlias {
    for (imports) |import_alias| {
        if (std.mem.eql(u8, import_alias.name, name)) return import_alias;
    }
    return null;
}

fn maybeTopLevelImportAlias(token_window: *const TokenWindow) ?TopLevelImportMatch {
    if (token_window.count < 8) return null;
    const tail = token_window.items[token_window.count - 8 .. token_window.count];
    if (!((tail[0].tag == .keyword_const or tail[0].tag == .keyword_var) and
        tail[1].tag == .identifier and
        tail[2].tag == .equal and
        tail[3].tag == .builtin and
        std.mem.eql(u8, tail[3].lexeme, "@import") and
        tail[4].tag == .l_paren and
        tail[5].tag == .string_literal and
        tail[6].tag == .r_paren and
        tail[7].tag == .semicolon))
    {
        return null;
    }
    const import_path = unquoteImportPath(tail[5].lexeme) orelse return null;
    return .{
        .name = tail[1].lexeme,
        .import_path = import_path,
    };
}

fn maybeQualifiedHelperUse(
    imports: []const ImportAlias,
    token_window: *const TokenWindow,
) ?struct {
    import_alias: []const u8,
    callee_name: []const u8,
    offset: usize,
} {
    if (token_window.count < 4) return null;
    const tail = token_window.items[token_window.count - 4 .. token_window.count];
    if (!(tail[0].tag == .identifier and
        tail[1].tag == .period and
        tail[2].tag == .identifier and
        tail[3].tag == .l_paren))
    {
        return null;
    }
    const import_alias = findImportAlias(imports, tail[0].lexeme) orelse return null;
    if (!std.mem.endsWith(u8, import_alias.import_path, ".zig")) return null;
    return .{
        .import_alias = tail[0].lexeme,
        .callee_name = tail[2].lexeme,
        .offset = tail[2].offset,
    };
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

fn resolveHelperEdges(collector: anytype) AnalysisError!void {
    const functions = collector.functionsSlice();
    const helper_uses = collector.helperUsesSlice();
    collector.clearHelperEdges();

    for (helper_uses) |helper_use| {
        if (helper_use.import_alias != null) continue;
        const callee_index = findFunctionIndex(functions, helper_use.callee_name) orelse continue;

        const resolved = HelperEdge{
            .caller_index = helper_use.caller_index,
            .callee_index = callee_index,
            .caller_name = functions[helper_use.caller_index].name,
            .callee_name = functions[callee_index].name,
            .line = helper_use.line,
            .column = helper_use.column,
        };
        try collector.pushHelperEdge(resolved);
    }
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

const BodyScanContext = struct {
    source: [:0]const u8,
    tokenizer: *std.zig.Tokenizer,
    caller_index: usize,
    caller_name: []const u8,
    effect_param: ?[]const u8,
    imports: []const ImportAlias,
    options: AnalyzeOptions,
};

fn scanBody(context: *BodyScanContext, collector: anytype) AnalysisError!void {
    var aliases = [_]Alias{.{
        .name = "",
        .kind = .effect_root,
    }} ** 128;
    var alias_count: usize = 0;
    var body_depth: usize = 1;
    var previous_kept_tag: ?std.zig.Token.Tag = null;
    var pending_identifier: ?PendingIdentifier = null;
    var token_window = TokenWindow{};

    while (body_depth != 0) {
        const token = context.tokenizer.next();
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
                const loc = locationForOffset(context.source, candidate.offset);
                try collector.pushHelperUse(.{
                    .caller_index = context.caller_index,
                    .callee_name = candidate.lexeme,
                    .import_alias = null,
                    .line = loc.line,
                    .column = loc.column,
                });
            }
            pending_identifier = null;
        }

        const current = TokenItem{
            .tag = token.tag,
            .lexeme = tokenSlice(context.source, token),
            .offset = token.loc.start,
        };
        token_window.push(current);
        if (maybeQualifiedHelperUse(context.imports, &token_window)) |qualified_use| {
            const loc = locationForOffset(context.source, qualified_use.offset);
            try collector.pushHelperUse(.{
                .caller_index = context.caller_index,
                .callee_name = qualified_use.callee_name,
                .import_alias = qualified_use.import_alias,
                .line = loc.line,
                .column = loc.column,
            });
            pending_identifier = null;
        }
        if (maybeRecordDirectOpUse(context.effect_param, aliases[0..alias_count], &token_window)) |match| {
            try collector.pushDirectOpUse(.{
                .function_index = context.caller_index,
                .requirement_label = match.requirement_label,
                .op_name = match.op_name,
            });
        }
        if (current.tag == .semicolon) {
            if (maybeAliasFromDeclaration(context.effect_param, aliases[0..alias_count], &token_window)) |alias| {
                try upsertAlias(aliases[0..], &alias_count, alias.name, alias.kind);
            }
        } else if (context.options.reject_indirect_effect_access and
            maybeUnsupportedEffectAccess(context.effect_param, aliases[0..alias_count], &token_window))
        {
            return error.UnsupportedEffectAccess;
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

fn scanSource(source: [:0]const u8, collector: anytype, options: AnalyzeOptions) AnalysisError!void {
    var tokenizer = std.zig.Tokenizer.init(source);
    var depth: usize = 0;
    var top_level_window = TokenWindow{};

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
                top_level_window = .{};

                var name_token = tokenizer.next();
                while (isIgnorable(name_token.tag)) : (name_token = tokenizer.next()) {}
                if (name_token.tag != .identifier) continue;
                const name = tokenSlice(source, name_token);

                var effect_param: ?[]const u8 = null;
                var param_candidate: ?[]const u8 = null;
                var pending_type_param: ?[]const u8 = null;
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
                        .r_paren => {
                            param_depth -= 1;
                            pending_type_param = null;
                        },
                        .comma => {
                            param_candidate = null;
                            pending_type_param = null;
                        },
                        .colon => if (param_depth == 1 and effect_param == null and param_candidate != null) {
                            pending_type_param = param_candidate;
                        },
                        .keyword_anytype => if (param_depth == 1 and effect_param == null and pending_type_param != null) {
                            if (isEffectParamName(pending_type_param.?)) effect_param = pending_type_param;
                            pending_type_param = null;
                        },
                        .identifier => if (param_depth == 1 and param_candidate == null) {
                            param_candidate = tokenSlice(source, next);
                        } else if (param_depth == 1 and effect_param == null and pending_type_param != null) {
                            pending_type_param = null;
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
                            var context: BodyScanContext = .{
                                .source = source,
                                .tokenizer = &tokenizer,
                                .caller_index = function_index,
                                .caller_name = name,
                                .effect_param = effect_param,
                                .imports = collector.importsSlice(),
                                .options = options,
                            };
                            try scanBody(&context, collector);
                            break;
                        },
                        .semicolon => break,
                        else => {},
                    }
                }
            },
            else => {},
        }

        if (depth == 0 and !isIgnorable(token.tag)) {
            top_level_window.push(.{
                .tag = token.tag,
                .lexeme = tokenSlice(source, token),
                .offset = token.loc.start,
            });
            if (token.tag == .semicolon) {
                if (maybeTopLevelImportAlias(&top_level_window)) |import_alias| {
                    try collector.pushImport(.{
                        .name = import_alias.name,
                        .import_path = import_alias.import_path,
                    });
                }
            }
        }
    }
}

fn finalizeGraph(source: [:0]const u8, collector: anytype, options: AnalyzeOptions) AnalysisError!?usize {
    try scanSource(source, collector, options);
    try resolveHelperEdges(collector);

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
    const entry_index = finalizeGraph(source, &collector, options) catch |err| switch (err) {
        error.OutOfMemory => unreachable,
        error.EntryMissing => return error.EntryMissing,
        error.MissingImport => return error.MissingImport,
        error.RecursiveHelpers => return error.RecursiveHelpers,
        error.TooManyFunctions => return error.TooManyFunctions,
        error.TooManyImports => return error.TooManyImports,
        error.TooManyHelperUses => return error.TooManyHelperUses,
        error.TooManyHelperEdges => return error.TooManyHelperEdges,
        error.TooManyOpUses => return error.TooManyOpUses,
        error.UnsupportedEffectAccess => return error.UnsupportedEffectAccess,
        error.UnsupportedImportPath => return error.UnsupportedImportPath,
    };
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
            .reject_indirect_effect_access = true,
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

test "shared engine supports alias-based effect access" {
    const graph = try analyzeComptime(
        \\fn helper(eff: anytype) !void {
        \\    const writer = eff.writer;
        \\    try writer.tell("queued");
        \\}
        \\pub fn runBody(eff: anytype) !void {
        \\    const e = eff;
        \\    const state = e.state;
        \\    _ = try state.get();
        \\    try helper(eff);
        \\}
    ,
        .{
            .entry_symbol = "runBody",
            .reject_recursive_helpers = true,
            .reject_indirect_effect_access = true,
        },
    );

    try std.testing.expectEqual(@as(usize, 2), graph.direct_op_uses.len);
    try std.testing.expectEqualStrings("writer", graph.direct_op_uses[0].requirement_label);
    try std.testing.expectEqualStrings("tell", graph.direct_op_uses[0].op_name);
    try std.testing.expectEqualStrings("state", graph.direct_op_uses[1].requirement_label);
    try std.testing.expectEqualStrings("get", graph.direct_op_uses[1].op_name);
}

test "shared engine rejects unsupported effect access" {
    try std.testing.expectError(error.UnsupportedEffectAccess, analyzeComptime(
        \\fn consume(_: anytype) void {}
        \\pub fn runBody(eff: anytype) void {
        \\    consume(eff.state);
        \\}
    ,
        .{
            .entry_symbol = "runBody",
            .reject_recursive_helpers = true,
            .reject_indirect_effect_access = true,
        },
    ));
}

test "shared engine rejects recursive helper graphs" {
    try std.testing.expectError(error.RecursiveHelpers, analyzeComptime(
        \\fn helper() void { runBody(); }
        \\pub fn runBody() void { helper(); }
    ,
        .{
            .entry_symbol = "runBody",
            .reject_recursive_helpers = true,
            .reject_indirect_effect_access = true,
        },
    ));
}
