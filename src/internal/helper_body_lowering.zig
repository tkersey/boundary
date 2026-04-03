const effect_ir = @import("effect_ir");
const program_frontend = @import("program_frontend");
const source_graph_embed = @import("source_graph_embed");
const source_graph_engine = @import("source_graph_engine");
const std = @import("std");

const BodyToken = struct {
    tag: std.zig.Token.Tag,
    lexeme: []const u8,
};

const StatementRange = struct {
    start: usize,
    end: usize,
};

const BodyAliasKind = union(enum) {
    effect_root,
    requirement: []const u8,
};

const BodyAlias = struct {
    name: []const u8,
    kind: BodyAliasKind,
};

const BoundLocal = struct {
    name: []const u8,
    codec: effect_ir.LocalCodec,
    local_id: u16,
};

const LocalStorage = struct {
    bindings: []BoundLocal,
    codecs: []effect_ir.LocalCodec,
    binding_count: *usize,
    local_count: *usize,
};

const BodyBuildState = struct {
    local_storage: LocalStorage,
    call_args: []u16,
    call_arg_count: *usize,
    instructions: []program_frontend.BodyInstruction,
    instruction_count: *usize,
};

const BranchBuildContext = struct {
    graph: source_graph_embed.ProgramGraph,
    lowered_index_map: []const u16,
    functions: []const effect_ir.Function,
    graph_function_index: usize,
    lowered_function_index: usize,
};

/// Pair an optional root source path with the caller-owned embedded source bytes.
pub const RootSource = struct {
    path: ?[]const u8,
    content: ?[:0]const u8,
    imported_sources: []const source_graph_embed.OwnedSource = &.{},
};

const FunctionBuildContext = struct {
    graph: source_graph_embed.ProgramGraph,
    lowered_index_map: []const u16,
    functions: []const effect_ir.Function,
    graph_function_index: usize,
    lowered_function_index: usize,
    root_source: RootSource,
};

fn cloneBytes(comptime bytes: []const u8) []const u8 {
    return std.fmt.comptimePrint("{s}", .{bytes});
}

fn failUnsupportedBodyLowering(comptime function: source_graph_embed.ProgramFunction) noreturn {
    @compileError(std.fmt.comptimePrint(
        "public lowering cannot synthesize unsupported helper or entry bodies; {s}:{s} must stay within the retained lowered-body subset",
        .{ function.module_path, function.name },
    ));
}

fn isBodyIgnorable(tag: std.zig.Token.Tag) bool {
    return switch (tag) {
        .doc_comment,
        .container_doc_comment,
        => true,
        else => false,
    };
}

// Linear-body scratch must accommodate the largest single retained statement shape:
// `if (local == 0) try helper(..., eff) else try helper(..., eff)`, which emits one
// predicate instruction plus two max-arity helper-call lowerings in the same body.
const max_helper_call_scratch_instructions = source_graph_engine.max_function_params + 1;
const max_helper_call_scratch_locals = source_graph_engine.max_function_params;
const max_branch_statement_scratch_instructions = 1 + (max_helper_call_scratch_instructions * 2);
const max_branch_statement_scratch_locals = 1 + (max_helper_call_scratch_locals * 2);
const max_branch_statement_call_args = source_graph_engine.max_function_params * 2;
const max_statement_scratch_instructions = max_branch_statement_scratch_instructions;
const max_statement_scratch_locals = max_branch_statement_scratch_locals;
const max_statement_bound_locals = 1;
const max_statement_call_args = max_branch_statement_call_args;

fn bodyTokensForFunction(
    comptime module_path: []const u8,
    comptime root_source: RootSource,
    comptime body_start_offset: usize,
    comptime body_end_offset: usize,
) []const BodyToken {
    const module_source = source_graph_embed.sourceBytes(
        module_path,
        root_source.path,
        root_source.content,
        root_source.imported_sources,
    ) catch |err| switch (err) {
        error.MissingImport => @compileError("public lowering recursive helper subset could not resolve one caller-owned helper module"),
        else => unreachable,
    };
    return comptime blk: {
        var tokenizer = std.zig.Tokenizer.init(module_source);
        var token_count: usize = 0;
        while (true) {
            const token = tokenizer.next();
            if (token.tag == .eof or token.loc.start >= body_end_offset) break;
            if (token.loc.end <= body_start_offset or isBodyIgnorable(token.tag)) continue;
            token_count += 1;
        }

        var buffer: [token_count]BodyToken = undefined;
        tokenizer = std.zig.Tokenizer.init(module_source);
        var index: usize = 0;
        while (true) {
            const token = tokenizer.next();
            if (token.tag == .eof or token.loc.start >= body_end_offset) break;
            if (token.loc.end <= body_start_offset or isBodyIgnorable(token.tag)) continue;
            buffer[index] = .{
                .tag = token.tag,
                .lexeme = module_source[token.loc.start..token.loc.end],
            };
            index += 1;
        }
        break :blk &buffer;
    };
}

fn statementRangesForTokens(comptime tokens: []const BodyToken) []const StatementRange {
    return comptime blk: {
        var statement_count: usize = 0;
        var start: usize = 0;
        for (tokens, 0..) |token, index| {
            if (token.tag != .semicolon) continue;
            if (index + 1 > start) statement_count += 1;
            start = index + 1;
        }

        var buffer: [statement_count]StatementRange = undefined;
        var out_index: usize = 0;
        start = 0;
        for (tokens, 0..) |token, index| {
            if (token.tag != .semicolon) continue;
            if (index + 1 > start) {
                buffer[out_index] = .{
                    .start = start,
                    .end = index + 1,
                };
                out_index += 1;
            }
            start = index + 1;
        }
        break :blk &buffer;
    };
}

fn statementTrimSemicolon(comptime statement: []const BodyToken) []const BodyToken {
    if (statement.len == 0) return statement;
    if (statement[statement.len - 1].tag != .semicolon) return statement;
    return statement[0 .. statement.len - 1];
}

fn statementIsSimpleReturn(comptime statement: []const BodyToken) bool {
    return statement.len == 2 and statement[0].tag == .keyword_return and statement[1].tag == .semicolon;
}

fn statementIsLiteralReturn(comptime statement: []const BodyToken) bool {
    return statement.len == 3 and
        statement[0].tag == .keyword_return and
        (statement[1].tag == .string_literal or statement[1].tag == .number_literal) and
        statement[2].tag == .semicolon;
}

fn bodyAliasKind(
    comptime effect_param: ?[]const u8,
    comptime aliases: []const BodyAlias,
    comptime name: []const u8,
) ?BodyAliasKind {
    if (effect_param) |param| {
        if (std.mem.eql(u8, param, name)) return .effect_root;
    }
    for (aliases) |alias| {
        if (std.mem.eql(u8, alias.name, name)) return alias.kind;
    }
    return null;
}

fn upsertBodyAlias(
    aliases: []BodyAlias,
    alias_count: *usize,
    comptime name: []const u8,
    comptime kind: BodyAliasKind,
) void {
    for (aliases[0..alias_count.*]) |*alias| {
        if (!std.mem.eql(u8, alias.name, name)) continue;
        alias.kind = kind;
        return;
    }
    aliases[alias_count.*] = .{
        .name = name,
        .kind = kind,
    };
    alias_count.* += 1;
}

fn findBoundLocal(
    comptime locals: []const BoundLocal,
    comptime name: []const u8,
) ?BoundLocal {
    for (locals) |local| {
        if (std.mem.eql(u8, local.name, name)) return local;
    }
    return null;
}

fn appendBoundLocal(
    local_storage: *LocalStorage,
    comptime name: []const u8,
    comptime codec: effect_ir.LocalCodec,
) u16 {
    const local_id: u16 = @intCast(local_storage.local_count.*);
    local_storage.bindings[local_storage.binding_count.*] = .{
        .name = name,
        .codec = codec,
        .local_id = local_id,
    };
    local_storage.binding_count.* += 1;
    local_storage.codecs[local_storage.local_count.*] = codec;
    local_storage.local_count.* += 1;
    return local_id;
}

fn appendAnonymousLocal(
    local_storage: *LocalStorage,
    comptime codec: effect_ir.LocalCodec,
) u16 {
    const local_id: u16 = @intCast(local_storage.local_count.*);
    local_storage.codecs[local_storage.local_count.*] = codec;
    local_storage.local_count.* += 1;
    return local_id;
}

fn parseAliasDeclaration(
    comptime effect_param: ?[]const u8,
    comptime aliases: []const BodyAlias,
    comptime statement: []const BodyToken,
) ?struct {
    name: []const u8,
    kind: BodyAliasKind,
} {
    if (statement.len == 5 and
        (statement[0].tag == .keyword_const or statement[0].tag == .keyword_var) and
        statement[1].tag == .identifier and
        statement[2].tag == .equal and
        statement[3].tag == .identifier and
        statement[4].tag == .semicolon)
    {
        const source_kind = bodyAliasKind(effect_param, aliases, statement[3].lexeme) orelse return null;
        return .{
            .name = statement[1].lexeme,
            .kind = source_kind,
        };
    }

    if (statement.len == 7 and
        (statement[0].tag == .keyword_const or statement[0].tag == .keyword_var) and
        statement[1].tag == .identifier and
        statement[2].tag == .equal and
        statement[3].tag == .identifier and
        statement[4].tag == .period and
        statement[5].tag == .identifier and
        statement[6].tag == .semicolon)
    {
        const source_kind = bodyAliasKind(effect_param, aliases, statement[3].lexeme) orelse return null;
        return switch (source_kind) {
            .effect_root => .{
                .name = statement[1].lexeme,
                .kind = .{ .requirement = statement[5].lexeme },
            },
            .requirement => null,
        };
    }

    return null;
}

const DirectCall = struct {
    requirement_label: []const u8,
    op_name: []const u8,
    args: []const BodyToken,
};

fn parseDirectCall(
    comptime effect_param: ?[]const u8,
    comptime aliases: []const BodyAlias,
    comptime statement: []const BodyToken,
) ?DirectCall {
    const tokens = statementTrimSemicolon(statement);
    if (tokens.len == 0) return null;

    var index: usize = 0;
    if (tokens.len >= 2 and
        tokens[0].tag == .identifier and
        std.mem.eql(u8, tokens[0].lexeme, "_") and
        tokens[1].tag == .equal)
    {
        index = 2;
    }
    if (index < tokens.len and tokens[index].tag == .keyword_try) index += 1;
    if (index >= tokens.len or tokens[index].tag != .identifier) return null;
    const base_kind = bodyAliasKind(effect_param, aliases, tokens[index].lexeme) orelse return null;

    return switch (base_kind) {
        .effect_root => {
            if (index + 6 > tokens.len) return null;
            if (tokens[index + 1].tag != .period or
                tokens[index + 2].tag != .identifier or
                tokens[index + 3].tag != .period or
                tokens[index + 4].tag != .identifier or
                tokens[index + 5].tag != .l_paren or
                tokens[tokens.len - 1].tag != .r_paren)
            {
                return null;
            }
            return .{
                .requirement_label = tokens[index + 2].lexeme,
                .op_name = tokens[index + 4].lexeme,
                .args = tokens[index + 6 .. tokens.len - 1],
            };
        },
        .requirement => |requirement_label| {
            if (index + 4 > tokens.len) return null;
            if (tokens[index + 1].tag != .period or
                tokens[index + 2].tag != .identifier or
                tokens[index + 3].tag != .l_paren or
                tokens[tokens.len - 1].tag != .r_paren)
            {
                return null;
            }
            return .{
                .requirement_label = requirement_label,
                .op_name = tokens[index + 2].lexeme,
                .args = tokens[index + 4 .. tokens.len - 1],
            };
        },
    };
}

fn parseBoundLocalFromDirectCall(
    comptime effect_param: ?[]const u8,
    comptime aliases: []const BodyAlias,
    comptime statement: []const BodyToken,
) ?struct {
    local_name: []const u8,
    requirement_label: []const u8,
    op_name: []const u8,
} {
    if (statement.len < 6) return null;
    if (statement[0].tag != .keyword_const) return null;
    if (statement[1].tag != .identifier) return null;
    if (statement[2].tag != .equal) return null;
    const direct = parseDirectCall(effect_param, aliases, statement[3..]) orelse return null;
    if (direct.args.len != 0) return null;
    return .{
        .local_name = statement[1].lexeme,
        .requirement_label = direct.requirement_label,
        .op_name = direct.op_name,
    };
}

const HelperCall = struct {
    callee_name: []const u8,
    import_alias: ?[]const u8,
    value_args: []const BodyToken,
};

fn parseHelperCall(
    comptime statement: []const BodyToken,
) ?HelperCall {
    const tokens = statementTrimSemicolon(statement);
    if (tokens.len == 0) return null;
    var index: usize = 0;
    if (tokens[index].tag == .keyword_try) index += 1;
    if (index >= tokens.len or tokens[index].tag != .identifier) return null;

    if (index + 2 <= tokens.len and
        tokens[index + 1].tag == .l_paren and
        tokens[tokens.len - 1].tag == .r_paren)
    {
        const args = tokens[index + 2 .. tokens.len - 1];
        const value_args = helperCallValueArgs(args) orelse return null;
        return .{
            .callee_name = tokens[index].lexeme,
            .import_alias = null,
            .value_args = value_args,
        };
    }

    if (index + 4 <= tokens.len and
        tokens[index + 1].tag == .period and
        tokens[index + 2].tag == .identifier and
        tokens[index + 3].tag == .l_paren and
        tokens[tokens.len - 1].tag == .r_paren)
    {
        const args = tokens[index + 4 .. tokens.len - 1];
        const value_args = helperCallValueArgs(args) orelse return null;
        return .{
            .callee_name = tokens[index + 2].lexeme,
            .import_alias = tokens[index].lexeme,
            .value_args = value_args,
        };
    }

    return null;
}

fn helperCallValueArgs(comptime args: []const BodyToken) ?[]const BodyToken {
    if (args.len == 1 and args[0].tag == .identifier and std.mem.eql(u8, args[0].lexeme, "eff")) {
        return &.{};
    }
    if (args.len < 3) return null;
    if (args[args.len - 1].tag != .identifier or !std.mem.eql(u8, args[args.len - 1].lexeme, "eff")) return null;
    if (args[args.len - 2].tag != .comma) return null;
    return args[0 .. args.len - 2];
}

fn parseBoundLocalFromHelperCall(
    comptime statement: []const BodyToken,
) ?struct {
    local_name: []const u8,
    helper_call: HelperCall,
} {
    if (statement.len < 6) return null;
    if (statement[0].tag != .keyword_const) return null;
    if (statement[1].tag != .identifier) return null;
    if (statement[2].tag != .equal) return null;
    const helper_call = parseHelperCall(statement[3..]) orelse return null;
    return .{
        .local_name = statement[1].lexeme,
        .helper_call = helper_call,
    };
}

fn parseLocalFromOpStatement(
    comptime statement: []const BodyToken,
) ?struct {
    local_name: []const u8,
    requirement_label: []const u8,
    op_name: []const u8,
} {
    if (statement.len != 12) return null;
    if (statement[0].tag != .keyword_const) return null;
    if (statement[1].tag != .identifier) return null;
    if (statement[2].tag != .equal) return null;
    if (statement[3].tag != .keyword_try) return null;
    if (statement[4].tag != .identifier or !std.mem.eql(u8, statement[4].lexeme, "eff")) return null;
    if (statement[5].tag != .period) return null;
    if (statement[6].tag != .identifier) return null;
    if (statement[7].tag != .period) return null;
    if (statement[8].tag != .identifier) return null;
    if (statement[9].tag != .l_paren) return null;
    if (statement[10].tag != .r_paren) return null;
    if (statement[11].tag != .semicolon) return null;
    return .{
        .local_name = statement[1].lexeme,
        .requirement_label = statement[6].lexeme,
        .op_name = statement[8].lexeme,
    };
}

fn parseIfLocalEqZeroReturnStatement(
    comptime statement: []const BodyToken,
    comptime local_name: []const u8,
) bool {
    return statement.len == 8 and
        statement[0].tag == .keyword_if and
        statement[1].tag == .l_paren and
        statement[2].tag == .identifier and
        std.mem.eql(u8, statement[2].lexeme, local_name) and
        statement[3].tag == .equal_equal and
        statement[4].tag == .number_literal and
        std.mem.eql(u8, statement[4].lexeme, "0") and
        statement[5].tag == .r_paren and
        statement[6].tag == .keyword_return and
        statement[7].tag == .semicolon;
}

const BranchAction = union(enum) {
    direct_call: DirectCall,
    helper_call: HelperCall,
    return_unit,
};

fn parseBranchAction(
    comptime effect_param: ?[]const u8,
    comptime aliases: []const BodyAlias,
    comptime statement: []const BodyToken,
) ?BranchAction {
    if (parseDirectCall(effect_param, aliases, statement)) |direct_call| {
        return .{ .direct_call = direct_call };
    }
    if (parseHelperCall(statement)) |helper_call| {
        return .{ .helper_call = helper_call };
    }
    if (statementIsSimpleReturn(statement)) {
        return .return_unit;
    }
    return null;
}

fn parseIfLocalEqZeroBranchStatement(
    comptime effect_param: ?[]const u8,
    comptime aliases: []const BodyAlias,
    comptime statement: []const BodyToken,
) ?struct {
    local_name: []const u8,
    then_action: BranchAction,
    else_action: BranchAction,
} {
    if (statement.len < 10) return null;
    if (statement[0].tag != .keyword_if or
        statement[1].tag != .l_paren or
        statement[2].tag != .identifier or
        statement[3].tag != .equal_equal or
        statement[4].tag != .number_literal or
        !std.mem.eql(u8, statement[4].lexeme, "0") or
        statement[5].tag != .r_paren)
    {
        return null;
    }

    const else_index = for (statement[6..], 6..) |item, index| {
        if (item.tag == .keyword_else) break index;
    } else return null;

    if (else_index == 6 or else_index + 1 >= statement.len) return null;

    const then_action = parseBranchAction(effect_param, aliases, statement[6..else_index]) orelse return null;
    const else_action = parseBranchAction(effect_param, aliases, statement[(else_index + 1)..]) orelse return null;
    return .{
        .local_name = statement[2].lexeme,
        .then_action = then_action,
        .else_action = else_action,
    };
}

fn parseLocalDecrementOpStatement(
    comptime statement: []const BodyToken,
    comptime local_name: []const u8,
) ?struct {
    requirement_label: []const u8,
    op_name: []const u8,
} {
    if (statement.len != 12) return null;
    if (statement[0].tag != .keyword_try) return null;
    if (statement[1].tag != .identifier or !std.mem.eql(u8, statement[1].lexeme, "eff")) return null;
    if (statement[2].tag != .period) return null;
    if (statement[3].tag != .identifier) return null;
    if (statement[4].tag != .period) return null;
    if (statement[5].tag != .identifier) return null;
    if (statement[6].tag != .l_paren) return null;
    if (statement[7].tag != .identifier or !std.mem.eql(u8, statement[7].lexeme, local_name)) return null;
    if (statement[8].tag != .minus) return null;
    if (statement[9].tag != .number_literal or !std.mem.eql(u8, statement[9].lexeme, "1")) return null;
    if (statement[10].tag != .r_paren) return null;
    if (statement[11].tag != .semicolon) return null;
    return .{
        .requirement_label = statement[3].lexeme,
        .op_name = statement[5].lexeme,
    };
}

fn parseHelperCallStatement(comptime statement: []const BodyToken) ?HelperCall {
    const helper_call = parseHelperCall(statement) orelse return null;
    if (helper_call.value_args.len != 0) return null;
    return helper_call;
}

fn parseReturnLiteralStatement(comptime statement: []const BodyToken) ?union(enum) {
    i32_value: i32,
    string_value: []const u8,
} {
    if (statement.len != 3) return null;
    if (statement[0].tag != .keyword_return) return null;
    if (statement[2].tag != .semicolon) return null;
    return switch (statement[1].tag) {
        .number_literal => .{ .i32_value = std.fmt.parseInt(i32, statement[1].lexeme, 10) catch return null },
        .string_literal => .{
            .string_value = stringLiteralContents(statement[1].lexeme) orelse return null,
        },
        else => null,
    };
}

fn parseReturnLocalStatement(comptime statement: []const BodyToken) ?[]const u8 {
    if (statement.len != 3) return null;
    if (statement[0].tag != .keyword_return) return null;
    if (statement[1].tag != .identifier) return null;
    if (statement[2].tag != .semicolon) return null;
    return statement[1].lexeme;
}

fn resumeCodecForFunctionUse(
    comptime functions: []const effect_ir.Function,
    comptime function_index: usize,
    comptime requirement_label: []const u8,
    comptime op_name: []const u8,
) effect_ir.LocalCodec {
    for (functions[function_index].row.requirements) |requirement| {
        if (!std.mem.eql(u8, requirement.label, requirement_label)) continue;
        for (requirement.ops) |op| {
            if (!std.mem.eql(u8, op.op_name, op_name)) continue;
            if (op.ResumeType == void) return .unit;
            if (op.ResumeType == bool) return .bool;
            if (op.ResumeType == i32) return .i32;
            if (op.ResumeType == usize) return .usize;
            if (op.ResumeType == []const u8) return .string;
            if (op.ResumeType == [][]const u8) return .string_list;
            @compileError("public lowering recursive helper subset produced an unsupported resume codec");
        }
    }
    @compileError("public lowering recursive helper subset could not map one bound local to an op resume codec");
}

fn opIndexForFunctionUse(
    comptime functions: []const effect_ir.Function,
    comptime function_index: usize,
    comptime requirement_label: []const u8,
    comptime op_name: []const u8,
) u16 {
    var op_index: u16 = 0;
    for (functions, 0..) |function, active_function_index| {
        for (function.row.requirements) |requirement| {
            for (requirement.ops) |op| {
                if (active_function_index == function_index and
                    std.mem.eql(u8, requirement.label, requirement_label) and
                    std.mem.eql(u8, op.op_name, op_name))
                {
                    return op_index;
                }
                op_index += 1;
            }
        }
    }
    @compileError("public lowering could not map one direct effect-op use into the lowered function row");
}

fn helperImportModulePath(
    comptime caller_module_path: []const u8,
    comptime import_alias: []const u8,
    comptime root_source: RootSource,
) ?[]const u8 {
    const caller_source = source_graph_embed.sourceBytes(
        caller_module_path,
        root_source.path,
        root_source.content,
        root_source.imported_sources,
    ) catch return null;
    const caller_graph = source_graph_engine.analyzeComptime(caller_source, .{
        .entry_symbol = null,
        .reject_recursive_helpers = false,
        .reject_indirect_effect_access = true,
    }) catch return null;

    for (caller_graph.imports) |import_row| {
        if (!std.mem.eql(u8, import_row.name, import_alias)) continue;
        return source_graph_embed.resolveImportPathAt(caller_module_path, import_row.import_path) catch return null;
    }
    return null;
}

fn helperTargetIndex(
    comptime graph: source_graph_embed.ProgramGraph,
    comptime lowered_index_map: []const u16,
    comptime graph_function_index: usize,
    comptime root_source: RootSource,
    comptime helper_call: HelperCall,
) u16 {
    const caller_module_path = graph.functions[graph_function_index].module_path;
    const expected_module_path = if (helper_call.import_alias) |import_alias|
        helperImportModulePath(caller_module_path, import_alias, root_source) orelse
            @compileError("public lowering recursive helper subset could not resolve one helper import alias")
    else
        caller_module_path;

    for (graph.helper_edges) |edge| {
        if (edge.caller_index != graph_function_index) continue;
        const callee = graph.functions[edge.callee_index];
        if (std.mem.eql(u8, callee.name, helper_call.callee_name) and
            std.mem.eql(u8, callee.module_path, expected_module_path))
        {
            return lowered_index_map[edge.callee_index];
        }
    }
    @compileError("public lowering recursive helper subset could not resolve one helper call target");
}

fn instructionLocationLess(
    comptime left_line: usize,
    comptime left_column: usize,
    comptime right_line: usize,
    comptime right_column: usize,
) bool {
    if (left_line < right_line) return true;
    if (left_line > right_line) return false;
    return left_column < right_column;
}

fn noLocalId() u16 {
    return std.math.maxInt(u16);
}

fn stringLiteralContents(comptime literal: []const u8) ?[]const u8 {
    if (literal.len < 2) return null;
    if (literal[0] != '"' or literal[literal.len - 1] != '"') return null;

    return comptime blk: {
        var decoded_len: usize = 0;
        var index: usize = 1;
        while (index < literal.len - 1) {
            switch (literal[index]) {
                '\\' => {
                    const escape_char_index = index + 1;
                    const parsed = std.zig.string_literal.parseEscapeSequence(literal, &index);
                    const codepoint = switch (parsed) {
                        .success => |value| value,
                        .failure => return null,
                    };
                    if (literal[escape_char_index] == 'u') {
                        var utf8_buffer: [4]u8 = undefined;
                        decoded_len += std.unicode.utf8Encode(codepoint, &utf8_buffer) catch return null;
                    } else {
                        decoded_len += 1;
                    }
                },
                '"' => return null,
                '\n' => return null,
                else => {
                    decoded_len += 1;
                    index += 1;
                },
            }
        }

        var buffer: [decoded_len]u8 = undefined;
        var out_index: usize = 0;
        index = 1;
        while (index < literal.len - 1) {
            switch (literal[index]) {
                '\\' => {
                    const escape_char_index = index + 1;
                    const parsed = std.zig.string_literal.parseEscapeSequence(literal, &index);
                    const codepoint = switch (parsed) {
                        .success => |value| value,
                        .failure => return null,
                    };
                    if (literal[escape_char_index] == 'u') {
                        var utf8_buffer: [4]u8 = undefined;
                        const utf8_len = std.unicode.utf8Encode(codepoint, &utf8_buffer) catch return null;
                        @memcpy(buffer[out_index .. out_index + utf8_len], utf8_buffer[0..utf8_len]);
                        out_index += utf8_len;
                    } else {
                        buffer[out_index] = @as(u8, @intCast(codepoint));
                        out_index += 1;
                    }
                },
                '"' => return null,
                '\n' => return null,
                else => {
                    buffer[out_index] = literal[index];
                    out_index += 1;
                    index += 1;
                },
            }
        }
        break :blk &buffer;
    };
}

fn appendInstruction(
    instructions: []program_frontend.BodyInstruction,
    instruction_count: *usize,
    instruction: program_frontend.BodyInstruction,
) void {
    instructions[instruction_count.*] = instruction;
    instruction_count.* += 1;
}

fn emitPayloadValueForDirectCall(
    comptime direct_call: DirectCall,
    comptime local_bindings: []const BoundLocal,
    state: *BodyBuildState,
) ?u16 {
    if (direct_call.args.len == 0) return noLocalId();

    if (direct_call.args.len == 1) {
        return switch (direct_call.args[0].tag) {
            .identifier => if (findBoundLocal(local_bindings, direct_call.args[0].lexeme)) |local|
                local.local_id
            else
                null,
            .number_literal => blk: {
                const value = std.fmt.parseInt(i32, direct_call.args[0].lexeme, 10) catch return null;
                const dst = appendAnonymousLocal(&state.local_storage, .i32);
                appendInstruction(state.instructions, state.instruction_count, .{
                    .kind = .const_i32,
                    .dst = dst,
                    .operand = @bitCast(value),
                });
                break :blk dst;
            },
            .string_literal => blk: {
                const literal = stringLiteralContents(direct_call.args[0].lexeme) orelse return null;
                const dst = appendAnonymousLocal(&state.local_storage, .string);
                appendInstruction(state.instructions, state.instruction_count, .{
                    .kind = .const_string,
                    .dst = dst,
                    .string_literal = cloneBytes(literal),
                });
                break :blk dst;
            },
            else => null,
        };
    }

    if (direct_call.args.len == 3 and
        direct_call.args[0].tag == .identifier and
        direct_call.args[1].tag == .plus and
        direct_call.args[2].tag == .number_literal)
    {
        const source_local = findBoundLocal(local_bindings, direct_call.args[0].lexeme) orelse return null;
        if (source_local.codec != .i32) return null;
        const increment = std.fmt.parseInt(u16, direct_call.args[2].lexeme, 10) catch return null;
        const dst = appendAnonymousLocal(&state.local_storage, .i32);
        appendInstruction(state.instructions, state.instruction_count, .{
            .kind = .add_const_i32,
            .dst = dst,
            .operand = source_local.local_id,
            .aux = increment,
        });
        return dst;
    }

    return null;
}

fn emitValueForExpectedCodec(
    comptime value_tokens: []const BodyToken,
    comptime expected_codec: effect_ir.LocalCodec,
    comptime local_bindings: []const BoundLocal,
    state: *BodyBuildState,
) ?u16 {
    if (value_tokens.len == 1) {
        return switch (value_tokens[0].tag) {
            .identifier => blk: {
                const local = findBoundLocal(local_bindings, value_tokens[0].lexeme) orelse return null;
                if (local.codec != expected_codec) return null;
                break :blk local.local_id;
            },
            .number_literal => blk: {
                if (expected_codec != .i32) return null;
                const value = std.fmt.parseInt(i32, value_tokens[0].lexeme, 10) catch return null;
                const dst = appendAnonymousLocal(&state.local_storage, .i32);
                appendInstruction(state.instructions, state.instruction_count, .{
                    .kind = .const_i32,
                    .dst = dst,
                    .operand = @bitCast(value),
                });
                break :blk dst;
            },
            .string_literal => blk: {
                if (expected_codec != .string) return null;
                const literal = stringLiteralContents(value_tokens[0].lexeme) orelse return null;
                const dst = appendAnonymousLocal(&state.local_storage, .string);
                appendInstruction(state.instructions, state.instruction_count, .{
                    .kind = .const_string,
                    .dst = dst,
                    .string_literal = cloneBytes(literal),
                });
                break :blk dst;
            },
            else => null,
        };
    }

    if (value_tokens.len == 3 and
        value_tokens[0].tag == .identifier and
        value_tokens[1].tag == .plus and
        value_tokens[2].tag == .number_literal)
    {
        if (expected_codec != .i32) return null;
        const source_local = findBoundLocal(local_bindings, value_tokens[0].lexeme) orelse return null;
        if (source_local.codec != .i32) return null;
        const increment = std.fmt.parseInt(u16, value_tokens[2].lexeme, 10) catch return null;
        const dst = appendAnonymousLocal(&state.local_storage, .i32);
        appendInstruction(state.instructions, state.instruction_count, .{
            .kind = .add_const_i32,
            .dst = dst,
            .operand = source_local.local_id,
            .aux = increment,
        });
        return dst;
    }

    return null;
}

fn appendCallArgs(state: *BodyBuildState, comptime locals: []const u16) u16 {
    const start: u16 = @intCast(state.call_arg_count.*);
    for (locals) |local_id| {
        state.call_args[state.call_arg_count.*] = local_id;
        state.call_arg_count.* += 1;
    }
    return start;
}

fn helperCallArgLocals(
    comptime helper_call: HelperCall,
    comptime callee: effect_ir.Function,
    comptime local_bindings: []const BoundLocal,
    state: *BodyBuildState,
) ?struct {
    start: u16,
    count: usize,
} {
    if (callee.parameter_codecs.len == 0) {
        if (helper_call.value_args.len != 0) return null;
        return .{ .start = noLocalId(), .count = 0 };
    }

    var value_segments = [_][]const BodyToken{&.{}} ** callee.parameter_codecs.len;
    var segment_count: usize = 0;
    var segment_start: usize = 0;
    var index: usize = 0;
    while (index <= helper_call.value_args.len) : (index += 1) {
        if (index != helper_call.value_args.len and helper_call.value_args[index].tag != .comma) continue;
        if (segment_count >= value_segments.len) return null;
        value_segments[segment_count] = helper_call.value_args[segment_start..index];
        segment_count += 1;
        segment_start = index + 1;
    }
    if (segment_count != callee.parameter_codecs.len) return null;

    var arg_locals = [_]u16{0} ** callee.parameter_codecs.len;
    for (callee.parameter_codecs, 0..) |codec, arg_index| {
        arg_locals[arg_index] = emitValueForExpectedCodec(value_segments[arg_index], codec, local_bindings, state) orelse return null;
    }
    return .{
        .start = appendCallArgs(state, arg_locals[0..segment_count]),
        .count = segment_count,
    };
}

const HelperEmission = struct {
    callee_index: u16,
    callee: effect_ir.Function,
    dst: u16,
    local_bindings: []const BoundLocal,
};

fn emitHelperCallInstruction(
    comptime helper_call: HelperCall,
    comptime emission: HelperEmission,
    state: *BodyBuildState,
) ?void {
    const arg_info = helperCallArgLocals(helper_call, emission.callee, emission.local_bindings, state) orelse return null;
    appendInstruction(state.instructions, state.instruction_count, .{
        .kind = .call_helper,
        .dst = emission.dst,
        .operand = emission.callee_index,
        .aux = arg_info.start,
    });
}

fn appendBranchActionInstructions(
    comptime context: BranchBuildContext,
    comptime action: BranchAction,
    comptime local_bindings: []const BoundLocal,
    state: *BodyBuildState,
) ?program_frontend.BodyTerminator {
    switch (action) {
        .direct_call => |direct_call| {
            const payload_local = emitPayloadValueForDirectCall(direct_call, local_bindings, state) orelse return null;
            appendInstruction(state.instructions, state.instruction_count, .{
                .kind = .call_op,
                .operand = opIndexForFunctionUse(
                    context.functions,
                    context.lowered_function_index,
                    direct_call.requirement_label,
                    direct_call.op_name,
                ),
                .aux = payload_local,
            });
            return .{ .kind = .return_unit };
        },
        .helper_call => |helper_call| {
            const callee_index = helperTargetIndex(
                context.graph,
                context.lowered_index_map,
                context.graph_function_index,
                context.root_source,
                helper_call,
            );
            const callee = context.functions[callee_index];
            emitHelperCallInstruction(helper_call, .{
                .callee_index = callee_index,
                .callee = callee,
                .dst = noLocalId(),
                .local_bindings = local_bindings,
            }, state) orelse return null;
            return .{ .kind = .return_unit };
        },
        .return_unit => return .{ .kind = .return_unit },
    }
}

fn buildLinearBodyForFunction(
    comptime context: FunctionBuildContext,
) ?program_frontend.FunctionBody {
    const function = context.graph.functions[context.graph_function_index];
    if (function.body_end_offset <= function.body_start_offset) return null;

    const tokens = bodyTokensForFunction(function.module_path, context.root_source, function.body_start_offset, function.body_end_offset);
    const statement_ranges = statementRangesForTokens(tokens);
    if (statement_ranges.len == 0) return null;

    return comptime blk: {
        var aliases: [statement_ranges.len]BodyAlias = [_]BodyAlias{.{
            .name = "",
            .kind = .effect_root,
        }} ** statement_ranges.len;
        var alias_count: usize = 0;
        var local_bindings: [statement_ranges.len * max_statement_bound_locals + source_graph_engine.max_function_params]BoundLocal = [_]BoundLocal{.{
            .name = "",
            .codec = .unit,
            .local_id = 0,
        }} ** (statement_ranges.len * max_statement_bound_locals + source_graph_engine.max_function_params);
        var binding_count: usize = 0;
        var local_codecs: [statement_ranges.len * max_statement_scratch_locals + source_graph_engine.max_function_params]effect_ir.LocalCodec = [_]effect_ir.LocalCodec{.unit} ** (statement_ranges.len * max_statement_scratch_locals + source_graph_engine.max_function_params);
        var local_count: usize = 0;
        var call_args: [statement_ranges.len * max_statement_call_args]u16 = [_]u16{0} ** (statement_ranges.len * max_statement_call_args);
        var call_arg_count: usize = 0;
        var instructions: [statement_ranges.len * max_statement_scratch_instructions]program_frontend.BodyInstruction = [_]program_frontend.BodyInstruction{.{
            .kind = .call_helper,
        }} ** (statement_ranges.len * max_statement_scratch_instructions);
        var instruction_count: usize = 0;
        var terminator: program_frontend.BodyTerminator = .{ .kind = .return_unit };
        var terminated = false;
        var local_storage: LocalStorage = .{
            .bindings = local_bindings[0..],
            .codecs = local_codecs[0..],
            .binding_count = &binding_count,
            .local_count = &local_count,
        };
        var body_state: BodyBuildState = .{
            .local_storage = local_storage,
            .call_args = call_args[0..],
            .call_arg_count = &call_arg_count,
            .instructions = instructions[0..],
            .instruction_count = &instruction_count,
        };

        for (0..function.value_param_count) |param_index| {
            const param_codec: effect_ir.LocalCodec = switch (function.value_param_shapes[param_index]) {
                .bool => .bool,
                .i32 => .i32,
                .string => .string,
                .usize => .usize,
            };
            _ = appendBoundLocal(&local_storage, function.value_param_names[param_index], param_codec);
        }
        const branch_build_context: BranchBuildContext = .{
            .graph = context.graph,
            .lowered_index_map = context.lowered_index_map,
            .functions = context.functions,
            .graph_function_index = context.graph_function_index,
            .lowered_function_index = context.lowered_function_index,
        };

        for (statement_ranges, 0..) |range, statement_index| {
            const statement = tokens[range.start..range.end];
            if (parseAliasDeclaration(function.effect_param, aliases[0..alias_count], statement)) |alias| {
                upsertBodyAlias(aliases[0..], &alias_count, alias.name, alias.kind);
                continue;
            }
            if (parseBoundLocalFromHelperCall(statement)) |bound_helper| {
                const callee_index = helperTargetIndex(
                    context.graph,
                    context.lowered_index_map,
                    context.graph_function_index,
                    context.root_source,
                    bound_helper.helper_call,
                );
                const callee = context.functions[callee_index];
                if (callee.ValueType == void) break :blk null;
                const dst = appendBoundLocal(
                    &local_storage,
                    bound_helper.local_name,
                    switch (callee.ValueType) {
                        bool => .bool,
                        i32 => .i32,
                        []const u8 => .string,
                        usize => .usize,
                        else => break :blk null,
                    },
                );
                emitHelperCallInstruction(
                    bound_helper.helper_call,
                    .{
                        .callee_index = callee_index,
                        .callee = callee,
                        .dst = dst,
                        .local_bindings = local_bindings[0..binding_count],
                    },
                    &body_state,
                ) orelse break :blk null;
                continue;
            }
            if (parseBoundLocalFromDirectCall(function.effect_param, aliases[0..alias_count], statement)) |bound_local| {
                const codec = resumeCodecForFunctionUse(
                    context.functions,
                    context.lowered_function_index,
                    bound_local.requirement_label,
                    bound_local.op_name,
                );
                const dst = appendBoundLocal(&local_storage, bound_local.local_name, codec);
                appendInstruction(instructions[0..], &instruction_count, .{
                    .kind = .call_op,
                    .dst = dst,
                    .operand = opIndexForFunctionUse(
                        context.functions,
                        context.lowered_function_index,
                        bound_local.requirement_label,
                        bound_local.op_name,
                    ),
                    .aux = noLocalId(),
                });
                continue;
            }
            if (parseIfLocalEqZeroBranchStatement(function.effect_param, aliases[0..alias_count], statement)) |branch_statement| {
                if (statement_index + 1 != statement_ranges.len) break :blk null;
                if (context.functions[context.lowered_function_index].ValueType != void) break :blk null;
                const condition_local = findBoundLocal(local_bindings[0..binding_count], branch_statement.local_name) orelse break :blk null;
                if (condition_local.codec != .i32 and condition_local.codec != .usize) break :blk null;

                const predicate_local = appendAnonymousLocal(&local_storage, .bool);
                appendInstruction(instructions[0..], &instruction_count, .{
                    .kind = .compare_eq_zero,
                    .dst = predicate_local,
                    .operand = condition_local.local_id,
                });
                const entry_instruction_end = instruction_count;
                const then_instruction_start = instruction_count;
                const then_terminator = appendBranchActionInstructions(
                    branch_build_context,
                    branch_statement.then_action,
                    local_bindings[0..binding_count],
                    &body_state,
                ) orelse break :blk null;
                const then_instruction_end = instruction_count;
                const else_instruction_start = instruction_count;
                const else_terminator = appendBranchActionInstructions(
                    branch_build_context,
                    branch_statement.else_action,
                    local_bindings[0..binding_count],
                    &body_state,
                ) orelse break :blk null;
                const body_locals = local_codecs[0..local_count];
                const blocks = [_]program_frontend.BodyBlock{
                    .{
                        .instructions = instructions[0..entry_instruction_end],
                        .terminator = .{
                            .kind = .branch_if,
                            .primary = 1,
                            .secondary = 2,
                        },
                    },
                    .{
                        .instructions = instructions[then_instruction_start..then_instruction_end],
                        .terminator = then_terminator,
                    },
                    .{
                        .instructions = instructions[else_instruction_start..instruction_count],
                        .terminator = else_terminator,
                    },
                };
                break :blk .{
                    .local_codecs = body_locals,
                    .call_arg_locals = call_args[0..call_arg_count],
                    .entry_block = 0,
                    .blocks = &blocks,
                };
            }
            if (parseDirectCall(function.effect_param, aliases[0..alias_count], statement)) |direct_call| {
                const payload_local = emitPayloadValueForDirectCall(
                    direct_call,
                    local_bindings[0..binding_count],
                    &body_state,
                ) orelse break :blk null;
                appendInstruction(instructions[0..], &instruction_count, .{
                    .kind = .call_op,
                    .operand = opIndexForFunctionUse(
                        context.functions,
                        context.lowered_function_index,
                        direct_call.requirement_label,
                        direct_call.op_name,
                    ),
                    .aux = payload_local,
                });
                continue;
            }
            if (parseHelperCall(statement)) |helper_call| {
                const callee_index = helperTargetIndex(
                    context.graph,
                    context.lowered_index_map,
                    context.graph_function_index,
                    context.root_source,
                    helper_call,
                );
                const callee = context.functions[callee_index];
                emitHelperCallInstruction(
                    helper_call,
                    .{
                        .callee_index = callee_index,
                        .callee = callee,
                        .dst = noLocalId(),
                        .local_bindings = local_bindings[0..binding_count],
                    },
                    &body_state,
                ) orelse break :blk null;
                continue;
            }
            if (statementIsLiteralReturn(statement)) {
                if (statement_index + 1 != statement_ranges.len) break :blk null;
                const return_literal = parseReturnLiteralStatement(statement) orelse break :blk null;
                switch (return_literal) {
                    .i32_value => |value| {
                        if (context.functions[context.lowered_function_index].ValueType != i32) break :blk null;
                        const dst = appendAnonymousLocal(&local_storage, .i32);
                        appendInstruction(instructions[0..], &instruction_count, .{
                            .kind = .const_i32,
                            .dst = dst,
                            .operand = @bitCast(value),
                        });
                        appendInstruction(instructions[0..], &instruction_count, .{
                            .kind = .return_value,
                            .operand = dst,
                        });
                        terminator = .{ .kind = .return_value };
                        terminated = true;
                    },
                    .string_value => |value| {
                        if (context.functions[context.lowered_function_index].ValueType != []const u8) break :blk null;
                        const dst = appendAnonymousLocal(&local_storage, .string);
                        appendInstruction(instructions[0..], &instruction_count, .{
                            .kind = .const_string,
                            .dst = dst,
                            .string_literal = cloneBytes(value),
                        });
                        appendInstruction(instructions[0..], &instruction_count, .{
                            .kind = .return_value,
                            .operand = dst,
                        });
                        terminator = .{ .kind = .return_value };
                        terminated = true;
                    },
                }
                continue;
            }
            if (statementIsSimpleReturn(statement)) {
                if (statement_index + 1 != statement_ranges.len) break :blk null;
                terminator = .{ .kind = .return_unit };
                terminated = true;
                continue;
            }
            if (parseReturnLocalStatement(statement)) |local_name| {
                if (statement_index + 1 != statement_ranges.len) break :blk null;
                const local = findBoundLocal(local_bindings[0..binding_count], local_name) orelse break :blk null;
                const expected_codec: effect_ir.LocalCodec = switch (context.functions[context.lowered_function_index].ValueType) {
                    void => break :blk null,
                    bool => .bool,
                    i32 => .i32,
                    []const u8 => .string,
                    usize => .usize,
                    else => break :blk null,
                };
                if (local.codec != expected_codec) break :blk null;
                appendInstruction(instructions[0..], &instruction_count, .{
                    .kind = .return_value,
                    .operand = local.local_id,
                });
                terminator = .{ .kind = .return_value };
                terminated = true;
                continue;
            }
            break :blk null;
        }

        if (!terminated and context.functions[context.lowered_function_index].ValueType != void) break :blk null;

        const body_instructions = instructions[0..instruction_count];
        const body_locals = local_codecs[0..local_count];
        const blocks = [_]program_frontend.BodyBlock{.{
            .instructions = body_instructions,
            .terminator = terminator,
        }};
        break :blk .{
            .local_codecs = body_locals,
            .call_arg_locals = call_args[0..call_arg_count],
            .entry_block = 0,
            .blocks = &blocks,
        };
    };
}

fn buildReturnLiteralBodyForFunction(
    comptime context: FunctionBuildContext,
) ?program_frontend.FunctionBody {
    const function = context.graph.functions[context.graph_function_index];
    const lowered_function = context.functions[context.lowered_function_index];
    if (lowered_function.ValueType == void) return null;
    if (function.body_end_offset <= function.body_start_offset) return null;

    const tokens = bodyTokensForFunction(function.module_path, context.root_source, function.body_start_offset, function.body_end_offset);
    const statement_ranges = statementRangesForTokens(tokens);
    if (statement_ranges.len == 0) return null;

    const tail_statement = tokens[statement_ranges[statement_ranges.len - 1].start..statement_ranges[statement_ranges.len - 1].end];
    const return_literal = parseReturnLiteralStatement(tail_statement) orelse return null;
    switch (return_literal) {
        .i32_value => if (lowered_function.ValueType != i32) return null,
        .string_value => if (lowered_function.ValueType != []const u8) return null,
    }

    const instructions = comptime blk: {
        const leading_instructions = buildBodyInstructionsForFunction(context);
        var buffer: [leading_instructions.len + 2]program_frontend.BodyInstruction = undefined;
        var index: usize = 0;
        for (leading_instructions) |instruction| {
            buffer[index] = instruction;
            index += 1;
        }

        switch (return_literal) {
            .i32_value => |value| buffer[index] = .{
                .kind = .const_i32,
                .dst = 0,
                .operand = @bitCast(value),
            },
            .string_value => |value| buffer[index] = .{
                .kind = .const_string,
                .dst = 0,
                .string_literal = cloneBytes(value),
            },
        }
        index += 1;
        buffer[index] = .{
            .kind = .return_value,
            .operand = 0,
        };
        break :blk &buffer;
    };

    const return_codec: effect_ir.LocalCodec = switch (return_literal) {
        .i32_value => .i32,
        .string_value => .string,
    };
    const blocks = [_]program_frontend.BodyBlock{.{
        .instructions = instructions,
        .terminator = .{ .kind = .return_value },
    }};
    return .{
        .local_codecs = &.{return_codec},
        .call_arg_locals = &.{},
        .entry_block = 0,
        .blocks = &blocks,
    };
}

fn buildRecursiveGuardBodyForFunction(
    comptime context: FunctionBuildContext,
) ?program_frontend.FunctionBody {
    const function = context.graph.functions[context.graph_function_index];
    if (function.body_end_offset <= function.body_start_offset) return null;

    const tokens = bodyTokensForFunction(function.module_path, context.root_source, function.body_start_offset, function.body_end_offset);
    const statement_ranges = statementRangesForTokens(tokens);
    if (statement_ranges.len < 3) return null;

    const bound = parseLocalFromOpStatement(tokens[statement_ranges[0].start..statement_ranges[0].end]) orelse return null;
    if (!parseIfLocalEqZeroReturnStatement(tokens[statement_ranges[1].start..statement_ranges[1].end], bound.local_name)) return null;

    const local_codec = resumeCodecForFunctionUse(
        context.functions,
        context.lowered_function_index,
        bound.requirement_label,
        bound.op_name,
    );

    const tail_instruction_count = comptime count: {
        var total: usize = 0;
        for (statement_ranges[2..]) |range| {
            const statement = tokens[range.start..range.end];
            if (parseLocalDecrementOpStatement(statement, bound.local_name) != null) {
                total += 2;
                continue;
            }
            if (parseDirectCall(function.effect_param, &.{}, statement)) |direct_call| {
                total += 1;
                if (direct_call.args.len == 1 and direct_call.args[0].tag == .string_literal) total += 1;
                if (direct_call.args.len != 0 and !(direct_call.args.len == 1 and direct_call.args[0].tag == .string_literal)) return null;
                continue;
            }
            if (parseHelperCallStatement(statement) != null) {
                total += 1;
                continue;
            }
            return null;
        }
        break :count total;
    };

    const tail_instructions = comptime blk: {
        var buffer: [tail_instruction_count]program_frontend.BodyInstruction = undefined;
        var index: usize = 0;
        for (statement_ranges[2..]) |range| {
            const statement = tokens[range.start..range.end];
            if (parseLocalDecrementOpStatement(statement, bound.local_name)) |decrement_op| {
                buffer[index] = .{
                    .kind = .sub_one,
                    .dst = 2,
                    .operand = 0,
                };
                index += 1;
                buffer[index] = .{
                    .kind = .call_op,
                    .operand = opIndexForFunctionUse(
                        context.functions,
                        context.lowered_function_index,
                        decrement_op.requirement_label,
                        decrement_op.op_name,
                    ),
                    .aux = 2,
                };
                index += 1;
                continue;
            }
            if (parseDirectCall(function.effect_param, &.{}, statement)) |direct_op| {
                if (direct_op.args.len == 1) {
                    const literal = stringLiteralContents(direct_op.args[0].lexeme).?;
                    buffer[index] = .{
                        .kind = .const_string,
                        .dst = 3,
                        .string_literal = cloneBytes(literal),
                    };
                    index += 1;
                }
                buffer[index] = .{
                    .kind = .call_op,
                    .operand = opIndexForFunctionUse(
                        context.functions,
                        context.lowered_function_index,
                        direct_op.requirement_label,
                        direct_op.op_name,
                    ),
                    .aux = if (direct_op.args.len == 0) noLocalId() else 3,
                };
                index += 1;
                continue;
            }
            const helper_call = parseHelperCallStatement(statement).?;
            buffer[index] = .{
                .kind = .call_helper,
                .operand = helperTargetIndex(
                    context.graph,
                    context.lowered_index_map,
                    context.graph_function_index,
                    context.root_source,
                    helper_call,
                ),
            };
            index += 1;
        }
        break :blk &buffer;
    };

    const entry_instructions = &[_]program_frontend.BodyInstruction{
        .{
            .kind = .call_op,
            .dst = 0,
            .operand = opIndexForFunctionUse(
                context.functions,
                context.lowered_function_index,
                bound.requirement_label,
                bound.op_name,
            ),
            .aux = noLocalId(),
        },
        .{
            .kind = .compare_eq_zero,
            .dst = 1,
            .operand = 0,
        },
    };
    const local_codecs = &[_]program_frontend.BodyLocalCodec{
        local_codec,
        .bool,
        local_codec,
        .string,
    };
    const blocks = &[_]program_frontend.BodyBlock{
        .{
            .instructions = entry_instructions,
            .terminator = .{
                .kind = .branch_if,
                .primary = 1,
                .secondary = 2,
            },
        },
        .{
            .instructions = &.{},
            .terminator = .{ .kind = .return_unit },
        },
        .{
            .instructions = tail_instructions,
            .terminator = .{ .kind = .return_unit },
        },
    };
    return .{
        .local_codecs = local_codecs,
        .call_arg_locals = &.{},
        .entry_block = 0,
        .blocks = blocks,
    };
}

fn buildBodyInstructionsForFunction(
    comptime context: FunctionBuildContext,
) []const program_frontend.BodyInstruction {
    const helper_count = comptime count: {
        var total: usize = 0;
        for (context.graph.helper_edges) |edge| {
            if (edge.caller_index == context.graph_function_index) total += 1;
        }
        break :count total;
    };
    const op_count = comptime count: {
        var total: usize = 0;
        for (context.graph.direct_op_uses) |direct_use| {
            if (direct_use.function_index == context.graph_function_index) total += 1;
        }
        break :count total;
    };
    const helper_indices = comptime blk: {
        var buffer: [helper_count]usize = undefined;
        var index: usize = 0;
        for (context.graph.helper_edges, 0..) |edge, edge_index| {
            if (edge.caller_index != context.graph_function_index) continue;
            buffer[index] = edge_index;
            index += 1;
        }
        break :blk buffer;
    };
    const op_indices = comptime blk: {
        var buffer: [op_count]usize = undefined;
        var index: usize = 0;
        for (context.graph.direct_op_uses, 0..) |direct_use, direct_use_index| {
            if (direct_use.function_index != context.graph_function_index) continue;
            buffer[index] = direct_use_index;
            index += 1;
        }
        break :blk buffer;
    };

    return comptime blk: {
        var buffer: [helper_count + op_count]program_frontend.BodyInstruction = undefined;
        var helper_index: usize = 0;
        var op_index: usize = 0;
        var instruction_index: usize = 0;

        while (helper_index < helper_count or op_index < op_count) {
            const take_direct_op = if (op_index >= op_count)
                false
            else if (helper_index >= helper_count)
                true
            else choose_direct_op: {
                break :choose_direct_op instructionLocationLess(
                    context.graph.direct_op_uses[op_indices[op_index]].line,
                    context.graph.direct_op_uses[op_indices[op_index]].column,
                    context.graph.helper_edges[helper_indices[helper_index]].line,
                    context.graph.helper_edges[helper_indices[helper_index]].column,
                );
            };

            if (take_direct_op) {
                const direct_use = context.graph.direct_op_uses[op_indices[op_index]];
                buffer[instruction_index] = .{
                    .kind = .call_op,
                    .operand = opIndexForFunctionUse(
                        context.functions,
                        context.lowered_function_index,
                        direct_use.requirement_label,
                        direct_use.op_name,
                    ),
                    .aux = noLocalId(),
                };
                op_index += 1;
            } else {
                const edge = context.graph.helper_edges[helper_indices[helper_index]];
                buffer[instruction_index] = .{
                    .kind = .call_helper,
                    .operand = context.lowered_index_map[edge.callee_index],
                };
                helper_index += 1;
            }
            instruction_index += 1;
        }

        break :blk &buffer;
    };
}

/// Build lowered helper bodies for the admitted source-owned helper-body subset.
pub fn buildFunctionBodiesForGraph(
    comptime graph: source_graph_embed.ProgramGraph,
    comptime functions: []const effect_ir.Function,
    comptime reachable: [graph.functions.len]bool,
    comptime lowered_index_map: [graph.functions.len]u16,
    comptime root_source: RootSource,
) []const program_frontend.FunctionBody {
    return comptime blk: {
        var buffer: [functions.len]program_frontend.FunctionBody = undefined;

        for (graph.functions, 0..) |function, graph_function_index| {
            if (!reachable[graph_function_index]) continue;
            const lowered_function_index = lowered_index_map[graph_function_index];
            const lowered_function = functions[lowered_function_index];

            if (!function.body_lowering_supported) {
                failUnsupportedBodyLowering(function);
            }

            const context: FunctionBuildContext = .{
                .graph = graph,
                .lowered_index_map = lowered_index_map[0..],
                .functions = functions,
                .graph_function_index = graph_function_index,
                .lowered_function_index = lowered_function_index,
                .root_source = root_source,
            };

            if (buildRecursiveGuardBodyForFunction(context)) |control_flow_body| {
                buffer[lowered_function_index] = control_flow_body;
                continue;
            }

            if (buildLinearBodyForFunction(context)) |linear_body| {
                buffer[lowered_function_index] = linear_body;
                continue;
            }

            if (buildReturnLiteralBodyForFunction(context)) |return_literal_body| {
                buffer[lowered_function_index] = return_literal_body;
                continue;
            }

            if (lowered_function.ValueType != void) {
                @compileError("public lowering currently requires admitted literal return lowering for non-void helper or entry functions");
            }

            const instructions = buildBodyInstructionsForFunction(context);
            const blocks = [_]program_frontend.BodyBlock{.{
                .instructions = instructions,
                .terminator = .{ .kind = .return_unit },
            }};
            buffer[lowered_function_index] = .{
                .local_codecs = &.{},
                .call_arg_locals = &.{},
                .entry_block = 0,
                .blocks = &blocks,
            };
        }
        break :blk &buffer;
    };
}
