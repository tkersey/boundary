const admitted_body_v1 = @import("admitted_body_v1");
const std = @import("std");
// zlinter-disable no_unused - AdmittedBodyV1 migration keeps the legacy statement matcher scaffolding in place until all witness paths are ported.

/// Shared error surface for same-module source graph extraction.
pub const Error = error{
    EntryMissing,
    MissingImport,
    ParseError,
    RecursiveHelpers,
    TooManyFunctions,
    TooManyFunctionParams,
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
    reject_malformed_statements: bool = false,
};

/// One supported scalar or string value shape discovered in a function signature.
pub const ValueShape = enum {
    bool,
    i32,
    string,
    usize,
};

/// Maximum admitted ordinary helper parameters in the restricted source-lowering ABI.
pub const max_function_params: usize = 8;

/// One top-level function discovered in a Zig source module.
pub const FunctionNode = struct {
    name: []const u8,
    effect_param: ?[]const u8,
    value_param_names: [max_function_params][]const u8,
    value_param_shapes: [max_function_params]ValueShape,
    value_param_count: u8,
    return_shape: ?ValueShape,
    body_lowering_supported: bool,
    body_start_offset: usize,
    body_end_offset: usize,
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
    has_after: bool = false,
    line: usize,
    column: usize,
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

const StatementWindow = struct {
    items: [128]TokenItem = [_]TokenItem{.{
        .tag = .invalid,
        .lexeme = "",
        .offset = 0,
    }} ** 128,
    count: usize = 0,

    fn push(self: *@This(), item: TokenItem) void {
        if (self.count < self.items.len) {
            self.items[self.count] = item;
            self.count += 1;
        }
    }

    fn reset(self: *@This()) void {
        self.count = 0;
    }

    fn slice(self: *const @This()) []const TokenItem {
        return self.items[0..self.count];
    }
};

const DirectOpUseMatch = struct {
    requirement_label: []const u8,
    op_name: []const u8,
    has_after: bool = false,
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

/// Decode one unquoted Zig import path string using Zig string-literal escapes.
pub fn decodeImportPathLiteral(import_path: []const u8, buffer: []u8) ?[]const u8 {
    if (std.mem.findScalar(u8, import_path, '\\') == null) {
        if (std.mem.findAny(u8, import_path, "\"\n") != null) return null;
        return import_path;
    }

    var out_index: usize = 0;
    var index: usize = 0;
    while (index < import_path.len) {
        switch (import_path[index]) {
            '\\' => {
                const escape_char_index = index + 1;
                const parsed = std.zig.string_literal.parseEscapeSequence(import_path, &index);
                const codepoint = switch (parsed) {
                    .success => |value| value,
                    .failure => return null,
                };
                if (escape_char_index >= import_path.len) return null;
                if (import_path[escape_char_index] == 'u') {
                    var utf8_buffer: [4]u8 = undefined;
                    const utf8_len = std.unicode.utf8Encode(codepoint, &utf8_buffer) catch return null;
                    if (out_index + utf8_len > buffer.len) return null;
                    @memcpy(buffer[out_index .. out_index + utf8_len], utf8_buffer[0..utf8_len]);
                    out_index += utf8_len;
                } else {
                    if (out_index >= buffer.len) return null;
                    buffer[out_index] = @as(u8, @intCast(codepoint));
                    out_index += 1;
                }
            },
            '"' => return null,
            '\n' => return null,
            else => {
                if (out_index >= buffer.len) return null;
                buffer[out_index] = import_path[index];
                out_index += 1;
                index += 1;
            },
        }
    }
    return buffer[0..out_index];
}

fn importPathEndsWithZig(import_path: []const u8) bool {
    var decoded_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const decoded = decodeImportPathLiteral(import_path, &decoded_buffer) orelse return false;
    return std.mem.endsWith(u8, decoded, ".zig");
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

    fn setFunctionBodyLoweringSupported(self: *@This(), function_index: usize, supported: bool) void {
        self.functions.items[function_index].body_lowering_supported = supported;
    }

    fn setFunctionBodyOffsets(self: *@This(), function_index: usize, body_start_offset: usize, body_end_offset: usize) void {
        self.functions.items[function_index].body_start_offset = body_start_offset;
        self.functions.items[function_index].body_end_offset = body_end_offset;
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

    fn markDirectOpUseHasAfter(self: *@This(), function_index: usize, requirement_label: []const u8, op_name: []const u8) bool {
        var index = self.direct_op_uses.items.len;
        while (index != 0) {
            index -= 1;
            const direct_op_use = &self.direct_op_uses.items[index];
            if (direct_op_use.function_index != function_index) continue;
            if (!std.mem.eql(u8, direct_op_use.requirement_label, requirement_label)) continue;
            if (!std.mem.eql(u8, direct_op_use.op_name, op_name)) continue;
            direct_op_use.has_after = true;
            return true;
        }
        return false;
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
        .value_param_names = [_][]const u8{""} ** max_function_params,
        .value_param_shapes = [_]ValueShape{.i32} ** max_function_params,
        .value_param_count = 0,
        .return_shape = null,
        .body_lowering_supported = false,
        .body_start_offset = 0,
        .body_end_offset = 0,
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
        .line = 0,
        .column = 0,
    }} ** 1024,
    direct_op_use_count: usize = 0,

    fn pushFunction(self: *@This(), function: FunctionNode) AnalysisError!usize {
        if (self.function_count >= self.functions.len) return error.TooManyFunctions;
        self.functions[self.function_count] = function;
        self.function_count += 1;
        return self.function_count - 1;
    }

    fn setFunctionBodyLoweringSupported(self: *@This(), function_index: usize, supported: bool) void {
        self.functions[function_index].body_lowering_supported = supported;
    }

    fn setFunctionBodyOffsets(self: *@This(), function_index: usize, body_start_offset: usize, body_end_offset: usize) void {
        self.functions[function_index].body_start_offset = body_start_offset;
        self.functions[function_index].body_end_offset = body_end_offset;
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

    fn markDirectOpUseHasAfter(self: *@This(), function_index: usize, requirement_label: []const u8, op_name: []const u8) bool {
        var index = self.direct_op_use_count;
        while (index != 0) {
            index -= 1;
            const direct_op_use = &self.direct_op_uses[index];
            if (direct_op_use.function_index != function_index) continue;
            if (!std.mem.eql(u8, direct_op_use.requirement_label, requirement_label)) continue;
            if (!std.mem.eql(u8, direct_op_use.op_name, op_name)) continue;
            direct_op_use.has_after = true;
            return true;
        }
        return false;
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
    return tag == .doc_comment or tag == .container_doc_comment;
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
    aliases: []const Alias,
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
    if (token_window.count >= 8) {
        const tail = token_window.items[token_window.count - 8 .. token_window.count];
        if (tail[0].tag == .identifier and
            tail[1].tag == .period and
            tail[2].tag == .identifier and
            tail[3].tag == .period and
            tail[4].tag == .identifier and
            tail[5].tag == .period and
            tail[6].tag == .identifier and
            tail[7].tag == .l_paren and
            (std.mem.eql(u8, tail[6].lexeme, "perform") or std.mem.eql(u8, tail[6].lexeme, "abort")))
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
                .requirement => |requirement_label| .{
                    .requirement_label = requirement_label,
                    .op_name = tail[2].lexeme,
                },
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
    return tag == .period or tag == .semicolon;
}

fn isAllowedRequirementAliasFollowTag(tag: std.zig.Token.Tag) bool {
    return tag == .period or tag == .semicolon or tag == .equal;
}

/// Return whether a function parameter name is treated as the lexical effect root.
pub fn isEffectParamName(name: []const u8) bool {
    return std.mem.eql(u8, name, "eff") or
        std.mem.eql(u8, name, "_") or
        std.mem.eql(u8, name, "_eff") or
        std.mem.eql(u8, name, "outer_eff") or
        std.mem.eql(u8, name, "inner_eff") or
        std.mem.eql(u8, name, "ctx") or
        std.mem.eql(u8, name, "context") or
        std.mem.endsWith(u8, name, "_eff") or
        std.mem.endsWith(u8, name, "_ctx");
}

fn pushValueParam(
    names: *[max_function_params][]const u8,
    shapes: *[max_function_params]ValueShape,
    count: *u8,
    name: []const u8,
    shape: ValueShape,
) AnalysisError!void {
    if (count.* >= max_function_params) return error.TooManyFunctionParams;
    names[count.*] = name;
    shapes[count.*] = shape;
    count.* += 1;
}

const FunctionParamStorage = struct {
    effect_param: *?[]const u8,
    value_param_names: *[max_function_params][]const u8,
    value_param_shapes: *[max_function_params]ValueShape,
    value_param_count: *u8,
};

fn finalizeFunctionParam(
    storage: FunctionParamStorage,
    param_name: []const u8,
    type_tokens: []const TokenItem,
) AnalysisError!void {
    if (type_tokens.len == 0) return;
    if (type_tokens.len == 1 and type_tokens[0].tag == .keyword_anytype) {
        if (storage.effect_param.* == null and isEffectParamName(param_name)) storage.effect_param.* = param_name;
        return;
    }
    const parsed = parseValueShapeFromTypeTokens(type_tokens, 0) orelse return;
    if (parsed.next_index != type_tokens.len) return;
    try pushValueParam(storage.value_param_names, storage.value_param_shapes, storage.value_param_count, param_name, parsed.shape);
}

fn parseValueShapeFromTypeTokens(
    tokens: []const TokenItem,
    start_index: usize,
) ?struct {
    shape: ValueShape,
    next_index: usize,
} {
    if (start_index >= tokens.len) return null;
    if (tokens[start_index].tag == .identifier) {
        if (std.mem.eql(u8, tokens[start_index].lexeme, "bool")) {
            return .{ .shape = .bool, .next_index = start_index + 1 };
        }
        if (std.mem.eql(u8, tokens[start_index].lexeme, "i32")) {
            return .{ .shape = .i32, .next_index = start_index + 1 };
        }
        if (std.mem.eql(u8, tokens[start_index].lexeme, "usize")) {
            return .{ .shape = .usize, .next_index = start_index + 1 };
        }
    }
    if (start_index + 3 < tokens.len and
        tokens[start_index].tag == .l_bracket and
        tokens[start_index + 1].tag == .r_bracket and
        tokens[start_index + 2].tag == .keyword_const and
        tokens[start_index + 3].tag == .identifier and
        std.mem.eql(u8, tokens[start_index + 3].lexeme, "u8"))
    {
        return .{ .shape = .string, .next_index = start_index + 4 };
    }
    return null;
}

fn parseReturnShape(tokens: []const TokenItem) ?ValueShape {
    if (tokens.len == 0) return null;
    var start_index: usize = if (tokens[0].tag == .bang) 1 else 0;
    if (tokens[0].tag != .bang) {
        for (tokens, 0..) |token, index| {
            if (token.tag != .bang) continue;
            start_index = index + 1;
            break;
        }
    }
    if (start_index >= tokens.len) return null;
    if (tokens[start_index].tag == .identifier and std.mem.eql(u8, tokens[start_index].lexeme, "void")) {
        return null;
    }
    const parsed = parseValueShapeFromTypeTokens(tokens, start_index) orelse return null;
    return parsed.shape;
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

fn statementIsSimpleReturn(statement: []const TokenItem) bool {
    return statement.len == 2 and statement[0].tag == .keyword_return and statement[1].tag == .semicolon;
}

fn tokenIsBoolLiteral(token: TokenItem) bool {
    return token.tag == .identifier and
        (std.mem.eql(u8, token.lexeme, "true") or std.mem.eql(u8, token.lexeme, "false"));
}

fn statementIsLiteralReturn(statement: []const TokenItem) bool {
    return statement.len == 3 and
        statement[0].tag == .keyword_return and
        (statement[1].tag == .string_literal or
            statement[1].tag == .number_literal or
            tokenIsBoolLiteral(statement[1])) and
        statement[2].tag == .semicolon;
}

fn statementIsLocalReturn(statement: []const TokenItem) bool {
    return statement.len == 3 and
        statement[0].tag == .keyword_return and
        statement[1].tag == .identifier and
        statement[2].tag == .semicolon;
}

fn statementIsLocalAddReturn(statement: []const TokenItem) bool {
    return statement.len == 5 and
        statement[0].tag == .keyword_return and
        statement[1].tag == .identifier and
        statement[2].tag == .plus and
        statement[3].tag == .identifier and
        statement[4].tag == .semicolon;
}

fn statementTrimSemicolon(statement: []const TokenItem) []const TokenItem {
    if (statement.len == 0) return statement;
    if (statement[statement.len - 1].tag != .semicolon) return statement;
    return statement[0 .. statement.len - 1];
}

fn statementArgsSupported(args: []const TokenItem) bool {
    for (args) |item| {
        if (item.tag != .comma and
            item.tag != .identifier and
            item.tag != .string_literal and
            item.tag != .number_literal and
            item.tag != .plus)
        {
            return false;
        }
    }
    return true;
}

fn helperCallArgsSupported(effect_param: ?[]const u8, args: []const TokenItem) bool {
    if (args.len == 0) return true;
    if (args.len == 1 and args[0].tag == .identifier) {
        if (effect_param) |param| return std.mem.eql(u8, args[0].lexeme, param);
        return std.mem.eql(u8, args[0].lexeme, "eff");
    }
    if (statementArgsSupported(args)) {
        const trailing_eff = args.len >= 3 and
            args[args.len - 1].tag == .identifier and
            args[args.len - 2].tag == .comma and
            ((effect_param != null and std.mem.eql(u8, args[args.len - 1].lexeme, effect_param.?)) or
                (effect_param == null and std.mem.eql(u8, args[args.len - 1].lexeme, "eff")));
        if (!trailing_eff) return true;
    }
    if (args.len < 3) return false;
    if (args[args.len - 1].tag != .identifier) return false;
    const trailing_identifier = args[args.len - 1].lexeme;
    if (effect_param) |param| {
        if (!std.mem.eql(u8, trailing_identifier, param)) return false;
    } else if (!std.mem.eql(u8, trailing_identifier, "eff")) return false;
    if (args[args.len - 2].tag != .comma) return false;
    return statementArgsSupported(args[0 .. args.len - 2]);
}

fn statementMatchesSupportedDirectOp(
    effect_param: ?[]const u8,
    aliases: []const Alias,
    statement: []const TokenItem,
) bool {
    const tokens = statementTrimSemicolon(statement);
    if (tokens.len == 0) return false;

    var index: usize = 0;
    if (tokens.len >= 2 and
        tokens[0].tag == .identifier and
        std.mem.eql(u8, tokens[0].lexeme, "_") and
        tokens[1].tag == .equal)
    {
        index = 2;
    }
    if (index < tokens.len and tokens[index].tag == .keyword_try) index += 1;

    if (index >= tokens.len or tokens[index].tag != .identifier) return false;
    const base_kind = aliasKind(effect_param, aliases, tokens[index].lexeme) orelse return false;

    switch (base_kind) {
        .effect_root => {
            if (index + 8 <= tokens.len and
                tokens[index + 1].tag == .period and
                tokens[index + 2].tag == .identifier and
                tokens[index + 3].tag == .period and
                tokens[index + 4].tag == .identifier and
                tokens[index + 5].tag == .period and
                tokens[index + 6].tag == .identifier and
                tokens[index + 7].tag == .l_paren and
                tokens[tokens.len - 1].tag == .r_paren and
                (std.mem.eql(u8, tokens[index + 6].lexeme, "perform") or std.mem.eql(u8, tokens[index + 6].lexeme, "abort")))
            {
                return statementArgsSupported(tokens[index + 8 .. tokens.len - 1]);
            }
            if (index + 6 > tokens.len) return false;
            if (tokens[index + 1].tag != .period) return false;
            if (tokens[index + 2].tag != .identifier) return false;
            if (tokens[index + 3].tag != .period) return false;
            if (tokens[index + 4].tag != .identifier) return false;
            if (tokens[index + 5].tag != .l_paren) return false;
            if (tokens[tokens.len - 1].tag != .r_paren) return false;
            return statementArgsSupported(tokens[index + 6 .. tokens.len - 1]);
        },
        .requirement => {
            if (index + 6 <= tokens.len and
                tokens[index + 1].tag == .period and
                tokens[index + 2].tag == .identifier and
                tokens[index + 3].tag == .period and
                tokens[index + 4].tag == .identifier and
                tokens[index + 5].tag == .l_paren and
                tokens[tokens.len - 1].tag == .r_paren and
                (std.mem.eql(u8, tokens[index + 4].lexeme, "perform") or std.mem.eql(u8, tokens[index + 4].lexeme, "abort")))
            {
                return statementArgsSupported(tokens[index + 6 .. tokens.len - 1]);
            }
            if (index + 4 > tokens.len) return false;
            if (tokens[index + 1].tag != .period) return false;
            if (tokens[index + 2].tag != .identifier) return false;
            if (tokens[index + 3].tag != .l_paren) return false;
            if (tokens[tokens.len - 1].tag != .r_paren) return false;
            return statementArgsSupported(tokens[index + 4 .. tokens.len - 1]);
        },
    }
}

fn statementMatchesSupportedRequirementAliasTouch(
    effect_param: ?[]const u8,
    aliases: []const Alias,
    statement: []const TokenItem,
) bool {
    const tokens = statementTrimSemicolon(statement);
    if (tokens.len != 5) return false;
    if (tokens[0].tag != .identifier or !std.mem.eql(u8, tokens[0].lexeme, "_")) return false;
    if (tokens[1].tag != .equal) return false;
    if (tokens[2].tag != .identifier) return false;
    const base_kind = aliasKind(effect_param, aliases, tokens[2].lexeme) orelse return false;
    if (base_kind != .effect_root) return false;
    return tokens[3].tag == .period and tokens[4].tag == .identifier;
}

fn statementMatchesSupportedReturnDirectOp(
    effect_param: ?[]const u8,
    aliases: []const Alias,
    statement: []const TokenItem,
) bool {
    const tokens = statementTrimSemicolon(statement);
    if (tokens.len == 0 or tokens[0].tag != .keyword_return) return false;
    return statementMatchesSupportedDirectOp(effect_param, aliases, tokens[1..]);
}

fn continuationStructStart(args: []const TokenItem) ?struct {
    payload_end: usize,
    struct_start: usize,
} {
    if (args.len >= 2 and args[0].tag == .keyword_struct and args[1].tag == .l_brace) {
        return .{
            .payload_end = 0,
            .struct_start = 0,
        };
    }

    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    var brace_depth: usize = 0;
    for (args, 0..) |token, index| {
        if (token.tag == .l_paren) {
            paren_depth += 1;
        } else if (token.tag == .r_paren) {
            if (paren_depth != 0) paren_depth -= 1;
        } else if (token.tag == .l_bracket) {
            bracket_depth += 1;
        } else if (token.tag == .r_bracket) {
            if (bracket_depth != 0) bracket_depth -= 1;
        } else if (token.tag == .l_brace) {
            brace_depth += 1;
        } else if (token.tag == .r_brace) {
            if (brace_depth != 0) brace_depth -= 1;
        } else if (token.tag == .comma and paren_depth == 0 and bracket_depth == 0 and brace_depth == 0) {
            const next_index = index + 1;
            if (next_index + 1 < args.len and
                args[next_index].tag == .keyword_struct and
                args[next_index + 1].tag == .l_brace)
            {
                return .{
                    .payload_end = index,
                    .struct_start = next_index,
                };
            }
        }
    }
    return null;
}

fn continuationApplyBodySupported(struct_tokens: []const TokenItem) bool {
    if (struct_tokens.len < 4) return false;
    if (struct_tokens[0].tag != .keyword_struct or struct_tokens[1].tag != .l_brace) return false;

    var index: usize = 2;
    while (index + 1 < struct_tokens.len) : (index += 1) {
        if (struct_tokens[index].tag != .keyword_fn and
            !(struct_tokens[index].tag == .keyword_pub and
                index + 1 < struct_tokens.len and
                struct_tokens[index + 1].tag == .keyword_fn))
        {
            continue;
        }

        const fn_index = if (struct_tokens[index].tag == .keyword_pub) index + 1 else index;
        if (fn_index + 1 >= struct_tokens.len or
            struct_tokens[fn_index + 1].tag != .identifier or
            !std.mem.eql(u8, struct_tokens[fn_index + 1].lexeme, "apply"))
        {
            continue;
        }
        if (fn_index + 2 >= struct_tokens.len or struct_tokens[fn_index + 2].tag != .l_paren) return false;

        var param_depth: usize = 1;
        var cursor = fn_index + 3;
        while (cursor < struct_tokens.len and param_depth != 0) : (cursor += 1) {
            if (struct_tokens[cursor].tag == .l_paren) {
                param_depth += 1;
            } else if (struct_tokens[cursor].tag == .r_paren) {
                if (param_depth == 0) return false;
                param_depth -= 1;
            }
        }
        if (param_depth != 0 or cursor >= struct_tokens.len) return false;

        while (cursor < struct_tokens.len and struct_tokens[cursor].tag != .l_brace) : (cursor += 1) {}
        if (cursor >= struct_tokens.len) return false;

        const body_start = cursor + 1;
        var body_depth: usize = 1;
        cursor = body_start;
        while (cursor < struct_tokens.len and body_depth != 0) : (cursor += 1) {
            if (struct_tokens[cursor].tag == .l_brace) {
                body_depth += 1;
            } else if (struct_tokens[cursor].tag == .r_brace) {
                if (body_depth == 0) return false;
                body_depth -= 1;
            }
        }
        if (body_depth != 0 or cursor == 0) return false;

        const body_tokens = struct_tokens[body_start .. cursor - 1];
        return statementIsSimpleReturn(body_tokens) or
            statementIsLiteralReturn(body_tokens) or
            statementIsLocalReturn(body_tokens);
    }

    return false;
}

fn supportedContinuationDirectOp(
    effect_param: ?[]const u8,
    aliases: []const Alias,
    statement: []const TokenItem,
) ?DirectOpUseMatch {
    const tokens = statementTrimSemicolon(statement);
    if (tokens.len == 0 or tokens[0].tag != .keyword_return) return null;

    var index: usize = 1;
    if (index < tokens.len and tokens[index].tag == .keyword_try) index += 1;
    if (index >= tokens.len or tokens[index].tag != .identifier) return null;
    const base_kind = aliasKind(effect_param, aliases, tokens[index].lexeme) orelse return null;

    const ArgsBounds = struct {
        start: usize,
        end: usize,
    };
    const DirectCall = struct {
        args_bounds: ArgsBounds,
        match: DirectOpUseMatch,
    };
    const direct_call = switch (base_kind) {
        .effect_root => blk: {
            if (index + 8 <= tokens.len and
                tokens[index + 1].tag == .period and
                tokens[index + 2].tag == .identifier and
                tokens[index + 3].tag == .period and
                tokens[index + 4].tag == .identifier and
                tokens[index + 5].tag == .period and
                tokens[index + 6].tag == .identifier and
                tokens[index + 7].tag == .l_paren and
                std.mem.eql(u8, tokens[index + 6].lexeme, "perform") and
                tokens[tokens.len - 1].tag == .r_paren)
            {
                break :blk DirectCall{
                    .args_bounds = .{ .start = index + 8, .end = tokens.len - 1 },
                    .match = .{
                        .requirement_label = tokens[index + 2].lexeme,
                        .op_name = tokens[index + 4].lexeme,
                        .has_after = true,
                    },
                };
            }
            if (index + 6 <= tokens.len and
                tokens[index + 1].tag == .period and
                tokens[index + 2].tag == .identifier and
                tokens[index + 3].tag == .period and
                tokens[index + 4].tag == .identifier and
                tokens[index + 5].tag == .l_paren and
                tokens[tokens.len - 1].tag == .r_paren)
            {
                break :blk DirectCall{
                    .args_bounds = .{ .start = index + 6, .end = tokens.len - 1 },
                    .match = .{
                        .requirement_label = tokens[index + 2].lexeme,
                        .op_name = tokens[index + 4].lexeme,
                        .has_after = true,
                    },
                };
            }
            return null;
        },
        .requirement => |requirement_label| blk: {
            if (index + 6 <= tokens.len and
                tokens[index + 1].tag == .period and
                tokens[index + 2].tag == .identifier and
                tokens[index + 3].tag == .period and
                tokens[index + 4].tag == .identifier and
                tokens[index + 5].tag == .l_paren and
                std.mem.eql(u8, tokens[index + 4].lexeme, "perform") and
                tokens[tokens.len - 1].tag == .r_paren)
            {
                break :blk DirectCall{
                    .args_bounds = .{ .start = index + 6, .end = tokens.len - 1 },
                    .match = .{
                        .requirement_label = requirement_label,
                        .op_name = tokens[index + 2].lexeme,
                        .has_after = true,
                    },
                };
            }
            if (index + 4 <= tokens.len and
                tokens[index + 1].tag == .period and
                tokens[index + 2].tag == .identifier and
                tokens[index + 3].tag == .l_paren and
                tokens[tokens.len - 1].tag == .r_paren)
            {
                break :blk DirectCall{
                    .args_bounds = .{ .start = index + 4, .end = tokens.len - 1 },
                    .match = .{
                        .requirement_label = requirement_label,
                        .op_name = tokens[index + 2].lexeme,
                        .has_after = true,
                    },
                };
            }
            return null;
        },
    };

    const args = tokens[direct_call.args_bounds.start..direct_call.args_bounds.end];
    const struct_arg = continuationStructStart(args) orelse return null;
    if (!statementArgsSupported(args[0..struct_arg.payload_end])) return null;
    if (!continuationApplyBodySupported(args[struct_arg.struct_start..])) return null;
    return direct_call.match;
}

fn statementMatchesSupportedContinuationDirectOp(
    effect_param: ?[]const u8,
    aliases: []const Alias,
    statement: []const TokenItem,
) bool {
    return supportedContinuationDirectOp(effect_param, aliases, statement) != null;
}

fn statementMatchesSupportedLocalFromDirectOp(
    effect_param: ?[]const u8,
    aliases: []const Alias,
    statement: []const TokenItem,
) bool {
    const tokens = statementTrimSemicolon(statement);
    if (tokens.len < 5) return false;
    if (tokens[0].tag != .keyword_const) return false;
    if (tokens[1].tag != .identifier) return false;
    if (tokens[2].tag != .equal) return false;
    if (tokens[3].tag != .keyword_try) return false;
    if (tokens[4].tag != .identifier) return false;

    const base_kind = aliasKind(effect_param, aliases, tokens[4].lexeme) orelse return false;
    return switch (base_kind) {
        .effect_root => {
            if (tokens.len >= 12 and
                tokens[5].tag == .period and
                tokens[6].tag == .identifier and
                tokens[7].tag == .period and
                tokens[8].tag == .identifier and
                tokens[9].tag == .period and
                tokens[10].tag == .identifier and
                tokens[11].tag == .l_paren and
                tokens[tokens.len - 1].tag == .r_paren and
                (std.mem.eql(u8, tokens[10].lexeme, "perform") or std.mem.eql(u8, tokens[10].lexeme, "abort")))
            {
                return statementArgsSupported(tokens[12 .. tokens.len - 1]);
            }
            if (tokens.len < 10) return false;
            if (tokens[5].tag != .period or
                tokens[6].tag != .identifier or
                tokens[7].tag != .period or
                tokens[8].tag != .identifier or
                tokens[9].tag != .l_paren or
                tokens[tokens.len - 1].tag != .r_paren)
            {
                return false;
            }
            return statementArgsSupported(tokens[10 .. tokens.len - 1]);
        },
        .requirement => {
            if (tokens.len >= 10 and
                tokens[5].tag == .period and
                tokens[6].tag == .identifier and
                tokens[7].tag == .period and
                tokens[8].tag == .identifier and
                tokens[9].tag == .l_paren and
                tokens[tokens.len - 1].tag == .r_paren and
                (std.mem.eql(u8, tokens[8].lexeme, "perform") or std.mem.eql(u8, tokens[8].lexeme, "abort")))
            {
                return statementArgsSupported(tokens[10 .. tokens.len - 1]);
            }
            if (tokens.len < 8) return false;
            if (tokens[5].tag != .period or
                tokens[6].tag != .identifier or
                tokens[7].tag != .l_paren or
                tokens[tokens.len - 1].tag != .r_paren)
            {
                return false;
            }
            return statementArgsSupported(tokens[8 .. tokens.len - 1]);
        },
    };
}

fn statementMatchesSupportedLocalFromHelperCall(
    effect_param: ?[]const u8,
    imports: []const ImportAlias,
    statement: []const TokenItem,
) bool {
    if (statement.len < 6) return false;
    if (statement[0].tag != .keyword_const) return false;
    if (statement[1].tag != .identifier) return false;
    if (statement[2].tag != .equal) return false;
    return statementMatchesSupportedHelperCall(effect_param, imports, statement[3..]);
}

fn statementMatchesSupportedHelperCall(
    effect_param: ?[]const u8,
    imports: []const ImportAlias,
    statement: []const TokenItem,
) bool {
    const tokens = statementTrimSemicolon(statement);
    if (tokens.len == 0) return false;

    var index: usize = 0;
    if (tokens[index].tag == .keyword_try) index += 1;
    if (index >= tokens.len or tokens[index].tag != .identifier) return false;

    if (index + 2 <= tokens.len and
        tokens[index + 1].tag == .l_paren and
        tokens[tokens.len - 1].tag == .r_paren)
    {
        return helperCallArgsSupported(effect_param, tokens[index + 2 .. tokens.len - 1]);
    }

    if (index + 4 > tokens.len) return false;
    if (tokens[index + 1].tag != .period) return false;
    if (tokens[index + 2].tag != .identifier) return false;
    if (tokens[index + 3].tag != .l_paren) return false;
    if (tokens[tokens.len - 1].tag != .r_paren) return false;
    const import_alias = findImportAlias(imports, tokens[index].lexeme) orelse return false;
    if (!importPathEndsWithZig(import_alias.import_path)) return false;
    return helperCallArgsSupported(effect_param, tokens[index + 4 .. tokens.len - 1]);
}

fn statementMatchesSupportedReturnHelperCall(
    effect_param: ?[]const u8,
    imports: []const ImportAlias,
    statement: []const TokenItem,
) bool {
    const tokens = statementTrimSemicolon(statement);
    if (tokens.len < 2 or tokens[0].tag != .keyword_return) return false;
    return statementMatchesSupportedHelperCall(effect_param, imports, tokens[1..]);
}

fn statementMatchesSupportedIfLocalEqZeroReturn(statement: []const TokenItem) bool {
    return statement.len == 8 and
        statement[0].tag == .keyword_if and
        statement[1].tag == .l_paren and
        statement[2].tag == .identifier and
        statement[3].tag == .equal_equal and
        statement[4].tag == .number_literal and
        std.mem.eql(u8, statement[4].lexeme, "0") and
        statement[5].tag == .r_paren and
        statement[6].tag == .keyword_return and
        statement[7].tag == .semicolon;
}

fn statementMatchesSupportedIfLocalEqZeroBranch(
    effect_param: ?[]const u8,
    aliases: []const Alias,
    imports: []const ImportAlias,
    statement: []const TokenItem,
) bool {
    if (statement.len < 10) return false;
    if (statement[0].tag != .keyword_if or
        statement[1].tag != .l_paren or
        statement[2].tag != .identifier or
        statement[3].tag != .equal_equal or
        statement[4].tag != .number_literal or
        !std.mem.eql(u8, statement[4].lexeme, "0") or
        statement[5].tag != .r_paren)
    {
        return false;
    }

    const else_index = for (statement[6..], 6..) |item, index| {
        if (item.tag == .keyword_else) break index;
    } else return false;

    if (else_index == 6 or else_index + 1 >= statement.len) return false;

    const then_branch = statement[6..else_index];
    const else_branch = statement[(else_index + 1)..];
    const then_supported = statementMatchesSupportedDirectOp(effect_param, aliases, then_branch) or
        statementMatchesSupportedHelperCall(effect_param, imports, then_branch) or
        statementIsSimpleReturn(then_branch);
    const else_supported = statementMatchesSupportedDirectOp(effect_param, aliases, else_branch) or
        statementMatchesSupportedHelperCall(effect_param, imports, else_branch) or
        statementIsSimpleReturn(else_branch);
    return then_supported and else_supported;
}

fn statementMatchesSupportedLocalDecrementOp(
    effect_param: ?[]const u8,
    aliases: []const Alias,
    statement: []const TokenItem,
) bool {
    const tokens = statementTrimSemicolon(statement);
    if (tokens.len == 0) return false;

    var index: usize = 0;
    if (index < tokens.len and tokens[index].tag == .keyword_try) index += 1;
    if (index >= tokens.len or tokens[index].tag != .identifier) return false;
    const base_kind = aliasKind(effect_param, aliases, tokens[index].lexeme) orelse return false;
    switch (base_kind) {
        .effect_root => {},
        .requirement => return false,
    }
    if (index + 10 > tokens.len) return false;

    return tokens[index + 1].tag == .period and
        tokens[index + 2].tag == .identifier and
        tokens[index + 3].tag == .period and
        tokens[index + 4].tag == .identifier and
        tokens[index + 5].tag == .l_paren and
        tokens[index + 6].tag == .identifier and
        tokens[index + 7].tag == .minus and
        tokens[index + 8].tag == .number_literal and
        std.mem.eql(u8, tokens[index + 8].lexeme, "1") and
        tokens[index + 9].tag == .r_paren;
}

fn statementSupportsBodyLowering(
    effect_param: ?[]const u8,
    aliases: []const Alias,
    imports: []const ImportAlias,
    statement_window: *const StatementWindow,
) bool {
    const statement = statement_window.slice();
    if (statement.len == 0) return true;
    if (statementIsSimpleReturn(statement)) return true;
    if (statementIsLiteralReturn(statement)) return true;
    if (statementIsLocalReturn(statement)) return true;
    if (statementIsLocalAddReturn(statement)) return true;

    var token_window = TokenWindow{};
    for (statement) |item| token_window.push(item);
    if (maybeAliasFromDeclaration(effect_param, aliases, &token_window) != null) return true;
    if (statementMatchesSupportedLocalFromHelperCall(effect_param, imports, statement)) return true;
    if (statementMatchesSupportedLocalFromDirectOp(effect_param, aliases, statement)) return true;
    if (statementMatchesSupportedIfLocalEqZeroReturn(statement)) return true;
    if (statementMatchesSupportedIfLocalEqZeroBranch(effect_param, aliases, imports, statement)) return true;
    if (statementMatchesSupportedContinuationDirectOp(effect_param, aliases, statement)) return true;
    if (statementMatchesSupportedReturnDirectOp(effect_param, aliases, statement)) return true;
    if (statementMatchesSupportedReturnHelperCall(effect_param, imports, statement)) return true;
    if (statementMatchesSupportedRequirementAliasTouch(effect_param, aliases, statement)) return true;
    if (statementMatchesSupportedDirectOp(effect_param, aliases, statement)) return true;
    if (statementMatchesSupportedLocalDecrementOp(effect_param, aliases, statement)) return true;
    if (statementMatchesSupportedHelperCall(effect_param, imports, statement)) return true;
    return false;
}

fn statementLooksMalformed(statement_window: *const StatementWindow) bool {
    const statement = statementTrimSemicolon(statement_window.slice());
    if (statement.len == 0) return false;

    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    for (statement) |token| {
        if (token.tag == .l_paren) {
            paren_depth += 1;
        } else if (token.tag == .r_paren) {
            if (paren_depth == 0) return true;
            paren_depth -= 1;
        } else if (token.tag == .l_bracket) {
            bracket_depth += 1;
        } else if (token.tag == .r_bracket) {
            if (bracket_depth == 0) return true;
            bracket_depth -= 1;
        }
    }
    if (paren_depth != 0 or bracket_depth != 0) return true;

    const last_tag = statement[statement.len - 1].tag;
    return last_tag == .equal or
        last_tag == .period or
        last_tag == .comma or
        last_tag == .colon or
        last_tag == .keyword_try;
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

fn maybeTopLevelImportForwardAlias(
    imports: []const ImportAlias,
    token_window: *const TokenWindow,
) ?TopLevelImportMatch {
    if (token_window.count < 5) return null;
    const tail = token_window.items[token_window.count - 5 .. token_window.count];
    if (!((tail[0].tag == .keyword_const or tail[0].tag == .keyword_var) and
        tail[1].tag == .identifier and
        tail[2].tag == .equal and
        tail[3].tag == .identifier and
        tail[4].tag == .semicolon))
    {
        return null;
    }
    const import_alias = findImportAlias(imports, tail[3].lexeme) orelse return null;
    return .{
        .name = tail[1].lexeme,
        .import_path = import_alias.import_path,
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
    if (!importPathEndsWithZig(import_alias.import_path)) return null;
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
    body_start_offset: usize,
    imports: []const ImportAlias,
    options: AnalyzeOptions,
};

const BodyScanResult = struct {
    body_end_offset: usize,
    body_lowering_supported: bool,
};

fn scanBody(context: *BodyScanContext, collector: anytype) AnalysisError!BodyScanResult {
    var aliases = [_]Alias{.{
        .name = "",
        .kind = .effect_root,
    }} ** 128;
    var alias_count: usize = 0;
    var body_depth: usize = 1;
    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    var previous_kept_tag: ?std.zig.Token.Tag = null;
    var pending_identifier: ?PendingIdentifier = null;
    var token_window = TokenWindow{};
    var statement_window = StatementWindow{};

    while (body_depth != 0) {
        const token = context.tokenizer.next();
        if (token.tag == .eof) {
            if (context.options.reject_malformed_statements) return error.ParseError;
            break;
        } else if (token.tag == .l_brace) {
            body_depth += 1;
        } else if (token.tag == .r_brace) {
            body_depth -= 1;
            if (body_depth == 0) {
                return .{
                    .body_end_offset = token.loc.start,
                    .body_lowering_supported = admitted_body_v1.parseFunctionBody(
                        context.source,
                        "",
                        context.body_start_offset,
                        token.loc.start,
                        context.effect_param,
                        context.imports,
                    ) != null,
                };
            }
        } else if (token.tag == .l_paren) {
            paren_depth += 1;
        } else if (token.tag == .r_paren) {
            if (paren_depth != 0) paren_depth -= 1;
        } else if (token.tag == .l_bracket) {
            bracket_depth += 1;
        } else if (token.tag == .r_bracket) {
            if (bracket_depth != 0) bracket_depth -= 1;
        }
        if (isIgnorable(token.tag)) continue;

        const current = TokenItem{
            .tag = token.tag,
            .lexeme = tokenSlice(context.source, token),
            .offset = token.loc.start,
        };
        statement_window.push(current);
        if (body_depth != 1) continue;

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
            const loc = locationForOffset(context.source, current.offset);
            try collector.pushDirectOpUse(.{
                .function_index = context.caller_index,
                .requirement_label = match.requirement_label,
                .op_name = match.op_name,
                .line = loc.line,
                .column = loc.column,
            });
        }
        if (current.tag == .semicolon and body_depth == 1 and paren_depth == 0 and bracket_depth == 0) {
            if (context.options.reject_malformed_statements and
                statement_window.count < statement_window.items.len and
                statementLooksMalformed(&statement_window))
            {
                return error.ParseError;
            }
            if (maybeAliasFromDeclaration(context.effect_param, aliases[0..alias_count], &token_window)) |alias| {
                try upsertAlias(aliases[0..], &alias_count, alias.name, alias.kind);
            }
            if (supportedContinuationDirectOp(context.effect_param, aliases[0..alias_count], statement_window.slice())) |match| {
                if (!collector.markDirectOpUseHasAfter(context.caller_index, match.requirement_label, match.op_name)) {
                    const loc = locationForOffset(context.source, current.offset);
                    try collector.pushDirectOpUse(.{
                        .function_index = context.caller_index,
                        .requirement_label = match.requirement_label,
                        .op_name = match.op_name,
                        .has_after = match.has_after,
                        .line = loc.line,
                        .column = loc.column,
                    });
                }
            }
            statement_window.reset();
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

    return .{
        .body_end_offset = context.source.len,
        .body_lowering_supported = admitted_body_v1.parseFunctionBody(
            context.source,
            "",
            context.body_start_offset,
            context.source.len,
            context.effect_param,
            context.imports,
        ) != null,
    };
}

fn scanSource(source: [:0]const u8, collector: anytype, options: AnalyzeOptions) AnalysisError!void {
    var tokenizer = std.zig.Tokenizer.init(source);
    var depth: usize = 0;
    var top_level_window = TokenWindow{};

    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof) {
            break;
        } else if (token.tag == .l_brace) {
            depth += 1;
        } else if (token.tag == .r_brace) {
            if (depth != 0) depth -= 1;
        } else if (token.tag == .keyword_fn) {
            if (depth != 0) continue;
            top_level_window = .{};

            var name_token = tokenizer.next();
            while (isIgnorable(name_token.tag)) : (name_token = tokenizer.next()) {}
            if (name_token.tag != .identifier) continue;
            const name = tokenSlice(source, name_token);

            var effect_param: ?[]const u8 = null;
            var value_param_names = [_][]const u8{""} ** max_function_params;
            var value_param_shapes = [_]ValueShape{.i32} ** max_function_params;
            var value_param_count: u8 = 0;
            var param_candidate: ?[]const u8 = null;
            var pending_type_param: ?[]const u8 = null;
            var pending_type_tokens = [_]TokenItem{.{
                .tag = .invalid,
                .lexeme = "",
                .offset = 0,
            }} ** 8;
            var pending_type_token_count: usize = 0;
            var param_depth: usize = 0;

            seek_param_list: while (true) {
                const next = tokenizer.next();
                if (next.tag == .eof) {
                    if (options.reject_malformed_statements) return error.ParseError;
                    break;
                }
                if (isIgnorable(next.tag)) continue :seek_param_list;
                if (next.tag == .l_paren) {
                    param_depth = 1;
                    break;
                }
            }

            scan_param_tokens: while (param_depth != 0) {
                const next = tokenizer.next();
                if (next.tag == .eof) {
                    if (options.reject_malformed_statements) return error.ParseError;
                    break;
                }
                if (isIgnorable(next.tag)) continue :scan_param_tokens;
                if (next.tag == .l_paren) {
                    param_depth += 1;
                } else if (next.tag == .r_paren) {
                    if (param_depth == 1 and pending_type_param != null) {
                        try finalizeFunctionParam(
                            .{
                                .effect_param = &effect_param,
                                .value_param_names = &value_param_names,
                                .value_param_shapes = &value_param_shapes,
                                .value_param_count = &value_param_count,
                            },
                            pending_type_param.?,
                            pending_type_tokens[0..pending_type_token_count],
                        );
                    }
                    param_depth -= 1;
                    param_candidate = null;
                    pending_type_param = null;
                    pending_type_token_count = 0;
                } else if (next.tag == .comma) {
                    if (param_depth == 1 and pending_type_param != null) {
                        try finalizeFunctionParam(
                            .{
                                .effect_param = &effect_param,
                                .value_param_names = &value_param_names,
                                .value_param_shapes = &value_param_shapes,
                                .value_param_count = &value_param_count,
                            },
                            pending_type_param.?,
                            pending_type_tokens[0..pending_type_token_count],
                        );
                    }
                    param_candidate = null;
                    pending_type_param = null;
                    pending_type_token_count = 0;
                } else if (next.tag == .colon and param_depth == 1 and param_candidate != null) {
                    pending_type_param = param_candidate;
                    pending_type_token_count = 0;
                } else if (next.tag == .identifier and param_depth == 1 and pending_type_param == null and param_candidate == null) {
                    param_candidate = tokenSlice(source, next);
                } else if ((next.tag == .identifier or
                    next.tag == .keyword_anytype or
                    next.tag == .l_bracket or
                    next.tag == .r_bracket or
                    next.tag == .keyword_const) and
                    param_depth == 1 and
                    pending_type_param != null and
                    pending_type_token_count < pending_type_tokens.len)
                {
                    pending_type_tokens[pending_type_token_count] = .{
                        .tag = next.tag,
                        .lexeme = tokenSlice(source, next),
                        .offset = next.loc.start,
                    };
                    pending_type_token_count += 1;
                }
            }

            var return_tokens = [_]TokenItem{.{
                .tag = .invalid,
                .lexeme = "",
                .offset = 0,
            }} ** 8;
            var return_token_count: usize = 0;
            var body_start: ?std.zig.Token = null;
            seek_body_start: while (body_start == null) {
                const next = tokenizer.next();
                if (next.tag == .eof) {
                    if (options.reject_malformed_statements) return error.ParseError;
                    break;
                }
                if (isIgnorable(next.tag)) continue :seek_body_start;
                if (next.tag == .l_brace or next.tag == .semicolon) {
                    body_start = next;
                    break;
                }
                if (return_token_count < return_tokens.len) {
                    return_tokens[return_token_count] = .{
                        .tag = next.tag,
                        .lexeme = tokenSlice(source, next),
                        .offset = next.loc.start,
                    };
                    return_token_count += 1;
                }
            }
            const return_shape = parseReturnShape(return_tokens[0..return_token_count]);

            const function_index = try collector.pushFunction(.{
                .name = name,
                .effect_param = effect_param,
                .value_param_names = value_param_names,
                .value_param_shapes = value_param_shapes,
                .value_param_count = value_param_count,
                .return_shape = return_shape,
                .body_lowering_supported = false,
                .body_start_offset = 0,
                .body_end_offset = 0,
            });

            if (body_start) |next| {
                if (next.tag == .l_brace) {
                    var context: BodyScanContext = .{
                        .source = source,
                        .tokenizer = &tokenizer,
                        .caller_index = function_index,
                        .caller_name = name,
                        .effect_param = effect_param,
                        .body_start_offset = next.loc.end,
                        .imports = collector.importsSlice(),
                        .options = options,
                    };
                    const body_scan = try scanBody(&context, collector);
                    collector.setFunctionBodyLoweringSupported(function_index, body_scan.body_lowering_supported);
                    collector.setFunctionBodyOffsets(function_index, next.loc.end, body_scan.body_end_offset);
                }
            }
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
                } else if (maybeTopLevelImportForwardAlias(collector.importsSlice(), &top_level_window)) |import_alias| {
                    try collector.pushImport(.{
                        .name = import_alias.name,
                        .import_path = import_alias.import_path,
                    });
                }
            }
        }
    }

    if (options.reject_malformed_statements and depth != 0) return error.ParseError;
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
        error.ParseError => return error.ParseError,
        error.MissingImport => return error.MissingImport,
        error.RecursiveHelpers => return error.RecursiveHelpers,
        error.TooManyFunctions => return error.TooManyFunctions,
        error.TooManyFunctionParams => return error.TooManyFunctionParams,
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

test "shared engine decodes escaped helper import strings before helper classification" {
    const graph = try analyzeComptime(
        \\const helpers = @import("helpers\x2futil\x2ezig");
        \\pub fn runBody(eff: anytype) !void {
        \\    try helpers.helper(eff);
        \\}
    ,
        .{
            .entry_symbol = "runBody",
            .reject_recursive_helpers = true,
            .reject_indirect_effect_access = true,
        },
    );

    try std.testing.expectEqual(@as(usize, 1), graph.imports.len);
    try std.testing.expectEqual(@as(usize, 1), graph.helper_uses.len);
    try std.testing.expectEqualStrings("helpers\\x2futil\\x2ezig", graph.imports[0].import_path);
    try std.testing.expectEqualStrings("helper", graph.helper_uses[0].callee_name);
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

test "shared engine recognizes generated perform calls through suffixed effect params" {
    const graph = try analyzeComptime(
        \\pub fn runBody(outer_eff: anytype) !i32 {
        \\    return try outer_eff.search.query.perform("artifact-search");
        \\}
    ,
        .{
            .entry_symbol = "runBody",
            .reject_recursive_helpers = true,
            .reject_indirect_effect_access = true,
        },
    );

    try std.testing.expectEqual(@as(usize, 1), graph.direct_op_uses.len);
    try std.testing.expectEqualStrings("search", graph.direct_op_uses[0].requirement_label);
    try std.testing.expectEqualStrings("query", graph.direct_op_uses[0].op_name);
}

test "shared engine keeps explicit continuation request bodies in the lowering subset" {
    const graph = try analyzeComptime(
        \\pub fn runBody(eff: anytype) anyerror![]const u8 {
        \\    return try eff.optional.request(struct {
        \\        pub fn apply(_: i32, _: anytype) anyerror![]const u8 {
        \\            return "answer=42";
        \\        }
        \\    });
        \\}
    ,
        .{
            .entry_symbol = "runBody",
            .reject_recursive_helpers = true,
            .reject_indirect_effect_access = true,
        },
    );

    try std.testing.expectEqual(@as(usize, 1), graph.direct_op_uses.len);
    try std.testing.expect(graph.functions[graph.entry_index.?].body_lowering_supported);
    try std.testing.expectEqualStrings("optional", graph.direct_op_uses[0].requirement_label);
    try std.testing.expectEqualStrings("request", graph.direct_op_uses[0].op_name);
}

test "shared engine keeps bool payload literals in the lowering subset" {
    const graph = try analyzeComptime(
        \\pub fn runBody(eff: anytype) anyerror!bool {
        \\    try eff.state.set(true);
        \\    return try eff.state.get();
        \\}
    ,
        .{
            .entry_symbol = "runBody",
            .reject_recursive_helpers = true,
            .reject_indirect_effect_access = true,
        },
    );

    try std.testing.expectEqual(@as(usize, 2), graph.direct_op_uses.len);
    try std.testing.expect(graph.functions[graph.entry_index.?].body_lowering_supported);
    try std.testing.expectEqualStrings("state", graph.direct_op_uses[0].requirement_label);
    try std.testing.expectEqualStrings("set", graph.direct_op_uses[0].op_name);
}

test "shared engine keeps bool literal continuation request bodies in the lowering subset" {
    const graph = try analyzeComptime(
        \\pub fn runBody(eff: anytype) anyerror!bool {
        \\    return try eff.optional.request(struct {
        \\        pub fn apply(_: i32, _: anytype) anyerror!bool {
        \\            return true;
        \\        }
        \\    });
        \\}
    ,
        .{
            .entry_symbol = "runBody",
            .reject_recursive_helpers = true,
            .reject_indirect_effect_access = true,
        },
    );

    try std.testing.expectEqual(@as(usize, 1), graph.direct_op_uses.len);
    try std.testing.expect(graph.functions[graph.entry_index.?].body_lowering_supported);
    try std.testing.expectEqualStrings("optional", graph.direct_op_uses[0].requirement_label);
    try std.testing.expectEqualStrings("request", graph.direct_op_uses[0].op_name);
}

test "shared engine admits public ability nested with only through ability import evidence" {
    const graph = try analyzeComptime(
        \\const ability = @import("ability");
        \\pub fn runBody() anyerror!i32 {
        \\    const nested_result = (try ability.with(runtime_holder.ptr.?, .{
        \\        .inner = NestedResumeWitness.use(.{ .handler = nested.InnerHandler{} }),
        \\    }, static_redelim_inner_body_carrier)).value;
        \\    return nested_result;
        \\}
    ,
        .{
            .entry_symbol = "runBody",
            .reject_recursive_helpers = true,
            .reject_indirect_effect_access = true,
        },
    );

    try std.testing.expect(graph.functions[graph.entry_index.?].body_lowering_supported);
}

test "shared engine rejects public ability nested with through shadow import" {
    const graph = try analyzeComptime(
        \\const ability = @import("shadow.zig");
        \\pub fn runBody() anyerror!i32 {
        \\    const nested_result = (try ability.with(runtime_holder.ptr.?, .{
        \\        .inner = NestedResumeWitness.use(.{ .handler = nested.InnerHandler{} }),
        \\    }, static_redelim_inner_body_carrier)).value;
        \\    return nested_result;
        \\}
    ,
        .{
            .entry_symbol = "runBody",
            .reject_recursive_helpers = true,
            .reject_indirect_effect_access = true,
        },
    );

    try std.testing.expect(!graph.functions[graph.entry_index.?].body_lowering_supported);
}

test "shared engine admits forwarded ability import alias for nested with" {
    const graph = try analyzeComptime(
        \\const ability = @import("ability");
        \\const lexical_runtime = ability;
        \\pub fn runBody() anyerror!i32 {
        \\    const nested_result = (try lexical_runtime.with(runtime_holder.ptr.?, .{
        \\        .inner = NestedResumeWitness.use(.{ .handler = nested.InnerHandler{} }),
        \\    }, static_redelim_inner_body_carrier)).value;
        \\    return nested_result;
        \\}
    ,
        .{
            .entry_symbol = "runBody",
            .reject_recursive_helpers = true,
            .reject_indirect_effect_access = true,
        },
    );

    try std.testing.expect(graph.functions[graph.entry_index.?].body_lowering_supported);
}

test "shared engine admits forwarded synthetic ability import alias for nested with" {
    const graph = try analyzeComptime(
        \\const ability = @import("synthetic_ability");
        \\const lexical_runtime = ability;
        \\pub fn runBody() anyerror!i32 {
        \\    const nested_result = (try lexical_runtime.with(runtime_holder.ptr.?, .{
        \\        .inner = NestedResumeWitness.use(.{ .handler = nested.InnerHandler{} }),
        \\    }, static_redelim_inner_body_carrier)).value;
        \\    return nested_result;
        \\}
    ,
        .{
            .entry_symbol = "runBody",
            .reject_recursive_helpers = true,
            .reject_indirect_effect_access = true,
        },
    );

    try std.testing.expect(graph.functions[graph.entry_index.?].body_lowering_supported);
}

test "shared engine rejects negative payload literals from the lowering subset" {
    const graph = try analyzeComptime(
        \\pub fn runBody(eff: anytype) anyerror!i32 {
        \\    try eff.state.set(-1);
        \\    return try eff.state.get();
        \\}
    ,
        .{
            .entry_symbol = "runBody",
            .reject_recursive_helpers = true,
            .reject_indirect_effect_access = true,
        },
    );

    try std.testing.expectEqual(@as(usize, 2), graph.direct_op_uses.len);
    try std.testing.expect(!graph.functions[graph.entry_index.?].body_lowering_supported);
    try std.testing.expectEqualStrings("state", graph.direct_op_uses[0].requirement_label);
    try std.testing.expectEqualStrings("set", graph.direct_op_uses[0].op_name);
}

test "shared engine rejects try payload helper calls from the lowering subset" {
    const graph = try analyzeComptime(
        \\fn helper(value: i32, eff: anytype) anyerror!void {
        \\    _ = value;
        \\    try eff.writer.tell("queued");
        \\}
        \\pub fn runBody(eff: anytype) anyerror!void {
        \\    const value: anyerror!i32 = 41;
        \\    try helper(try value, eff);
        \\}
    ,
        .{
            .entry_symbol = "runBody",
            .reject_recursive_helpers = true,
            .reject_indirect_effect_access = true,
        },
    );

    try std.testing.expectEqual(@as(usize, 1), graph.direct_op_uses.len);
    try std.testing.expectEqual(@as(usize, 1), graph.helper_uses.len);
    try std.testing.expect(!graph.functions[graph.entry_index.?].body_lowering_supported);
    try std.testing.expectEqualStrings("helper", graph.helper_uses[0].callee_name);
}

test "shared engine keeps explicit continuation perform bodies in the lowering subset" {
    const graph = try analyzeComptime(
        \\pub fn runBody(eff: anytype) anyerror![]const u8 {
        \\    return try eff.picker.pick.perform(41, struct {
        \\        pub fn apply(_: i32, _: anytype) anyerror![]const u8 {
        \\            return "answer=42";
        \\        }
        \\    });
        \\}
    ,
        .{
            .entry_symbol = "runBody",
            .reject_recursive_helpers = true,
            .reject_indirect_effect_access = true,
        },
    );

    try std.testing.expectEqual(@as(usize, 1), graph.direct_op_uses.len);
    try std.testing.expect(graph.functions[graph.entry_index.?].body_lowering_supported);
    try std.testing.expectEqualStrings("picker", graph.direct_op_uses[0].requirement_label);
    try std.testing.expectEqualStrings("pick", graph.direct_op_uses[0].op_name);
}

test "shared engine records explicit perform and abort calls through requirement aliases" {
    const graph = try analyzeComptime(
        \\pub fn runBody(eff: anytype) anyerror!i32 {
        \\    const counter = eff.counter;
        \\    const guard = eff.guard;
        \\    _ = try counter.get.perform();
        \\    try guard.fail.abort("missing-name");
        \\    return 42;
        \\}
    ,
        .{
            .entry_symbol = "runBody",
            .reject_recursive_helpers = true,
            .reject_indirect_effect_access = true,
        },
    );

    try std.testing.expectEqual(@as(usize, 2), graph.direct_op_uses.len);
    try std.testing.expectEqualStrings("counter", graph.direct_op_uses[0].requirement_label);
    try std.testing.expectEqualStrings("get", graph.direct_op_uses[0].op_name);
    try std.testing.expectEqualStrings("guard", graph.direct_op_uses[1].requirement_label);
    try std.testing.expectEqualStrings("fail", graph.direct_op_uses[1].op_name);
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

test "shared engine finds appended entry after top-level const struct declarations" {
    const graph = try analyzeComptime(
        \\const common = @import("common.zig");
        \\const lexical_runtime = common.lexical_runtime;
        \\const std = common.std;
        \\pub const ResumeWitness = common.ResumeWitness;
        \\
        \\pub const transcript = struct {
        \\    pub const InnerHandler = struct {};
        \\};
        \\
        \\pub fn staticRedelimInnerBody(inner_eff: anytype) anyerror!i32 {
        \\    _ = inner_eff;
        \\    return 2;
        \\}
        \\
        \\const static_redelim_inner_body_carrier = struct {
        \\    pub const source_path = "source_graph_engine_demo.zig";
        \\    pub const body_symbol = "staticRedelimInnerBody";
        \\
        \\    pub fn body(inner_eff: anytype) anyerror!i32 {
        \\        return staticRedelimInnerBody(inner_eff);
        \\    }
        \\};
        \\
        \\fn runStaticRedelim(writer: anytype) anyerror!void {
        \\    _ = writer;
        \\    _ = try lexical_runtime.with(&runtime, .{
        \\        .outer = ResumeWitness.use(.{ .handler = transcript.OuterHandler{} }),
        \\    }, struct {
        \\        pub fn body(outer_eff: anytype) anyerror!i32 {
        \\            _ = try outer_eff.outer.step.perform();
        \\            const nested = (try lexical_runtime.with(transcript.runtime_ptr.?, .{
        \\                .inner = NestedResumeWitness.use(.{ .handler = Nested.InnerHandler{} }),
        \\            }, static_redelim_inner_body_carrier)).value;
        \\            return nested;
        \\        }
        \\
        \\        pub const NestedResumeWitness = common.ResumeWitness;
        \\        pub const Nested = struct {
        \\            pub const InnerHandler = transcript.InnerHandler;
        \\        };
        \\    });
        \\}
        \\
        \\pub const NestedResumeWitness = common.ResumeWitness;
        \\pub const Nested = struct {
        \\    pub const InnerHandler = transcript.InnerHandler;
        \\};
        \\pub fn __ability_with_entry_demo(outer_eff: anytype) anyerror!i32 {
        \\    _ = try outer_eff.outer.step.perform();
        \\    const nested = (try lexical_runtime.with(transcript.runtime_ptr.?, .{
        \\        .inner = NestedResumeWitness.use(.{ .handler = Nested.InnerHandler{} }),
        \\    }, static_redelim_inner_body_carrier)).value;
        \\    return nested;
        \\}
    ,
        .{
            .entry_symbol = "__ability_with_entry_demo",
            .reject_recursive_helpers = false,
            .reject_indirect_effect_access = true,
            .reject_malformed_statements = true,
        },
    );

    try std.testing.expectEqualStrings("__ability_with_entry_demo", graph.functions[graph.entry_index.?].name);
}
