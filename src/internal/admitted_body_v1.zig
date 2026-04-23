const std = @import("std");
// zlinter-disable field_ordering - semantic union tag order is kept grouped by lowering role during the AdmittedBodyV1 migration.
// zlinter-disable no_undefined - fixed-size scratch buffers intentionally use sentinel-free comptime initialization in this internal parser.
// zlinter-disable require_doc_comment - this internal IR module is still stabilizing and will get narrative docs after the seam is proven.
// zlinter-disable require_exhaustive_enum_switch - tokenizer tag switches are intentionally partial and fail closed through explicit fallback returns.

pub const max_steps: usize = 128;
pub const max_helper_args: usize = 8;
const max_aliases: usize = 128;
const max_body_tokens: usize = 256;

pub const Token = struct {
    tag: std.zig.Token.Tag,
    lexeme: []const u8,
};

pub const ValueExpr = union(enum) {
    local: []const u8,
    bool_literal: bool,
    number_literal: []const u8,
    string_literal: []const u8,
    add_const_i32: struct {
        local_name: []const u8,
        increment_literal: []const u8,
    },
};

pub const Literal = union(enum) {
    bool_value: bool,
    number_literal: []const u8,
    string_value: []const u8,
};

pub const DirectCall = struct {
    requirement_label: []const u8,
    op_name: []const u8,
    payload: ?ValueExpr,
    ignored_result: bool,
};

pub const HelperCall = struct {
    callee_name: []const u8,
    import_alias: ?[]const u8,
    arg_count: usize,
    args: [max_helper_args]ValueExpr,
};

pub const BranchAction = union(enum) {
    direct_call: DirectCall,
    helper_call: HelperCall,
    return_unit,
};

pub const ReturnValue = union(enum) {
    unit,
    literal: Literal,
    local: []const u8,
    direct_call: DirectCall,
    helper_call: HelperCall,
    add_locals: struct {
        left_name: []const u8,
        right_name: []const u8,
    },
};

pub const Step = union(enum) {
    bind_local_from_helper: struct {
        local_name: []const u8,
        helper_call: HelperCall,
    },
    bind_local_from_nested_with: struct {
        local_name: []const u8,
        requirement_label: []const u8,
        factory_name: []const u8,
        container_name: []const u8,
        handler_name: []const u8,
        carrier_name: ?[]const u8,
    },
    bind_local_from_direct: struct {
        local_name: []const u8,
        direct_call: DirectCall,
    },
    if_local_eq_zero_return_unit: []const u8,
    if_local_eq_zero_branch: struct {
        local_name: []const u8,
        then_action: BranchAction,
        else_action: BranchAction,
    },
    decrement_local_direct: struct {
        local_name: []const u8,
        requirement_label: []const u8,
        op_name: []const u8,
    },
    return_continuation_direct: struct {
        direct_call: DirectCall,
        apply_param_name: ?[]const u8,
        apply_return: ReturnValue,
    },
    call_direct: DirectCall,
    call_helper: HelperCall,
    return_value: ReturnValue,
};

pub const Body = struct {
    step_count: usize,
    steps: [max_steps]Step,

    pub fn slice(self: *const Body) []const Step {
        return self.steps[0..self.step_count];
    }
};

const StatementRange = struct {
    start: usize,
    end: usize,
};

const AliasKind = union(enum) {
    effect_root,
    requirement: []const u8,
};

const Alias = struct {
    name: []const u8,
    kind: AliasKind,
};

fn tokenIsBoolLiteral(token: Token) bool {
    return token.tag == .identifier and
        (std.mem.eql(u8, token.lexeme, "true") or std.mem.eql(u8, token.lexeme, "false"));
}

fn statementIsSimpleReturn(statement: []const Token) bool {
    return statement.len == 2 and
        statement[0].tag == .keyword_return and
        statement[1].tag == .semicolon;
}

fn statementTrimSemicolon(statement: []const Token) []const Token {
    if (statement.len == 0) return statement;
    if (statement[statement.len - 1].tag != .semicolon) return statement;
    return statement[0 .. statement.len - 1];
}

fn importPathEndsWithZig(import_path: []const u8) bool {
    return std.mem.endsWith(u8, import_path, ".zig");
}

fn findImportAlias(imports: anytype, name: []const u8) ?[]const u8 {
    for (imports) |import_alias| {
        if (std.mem.eql(u8, import_alias.name, name)) return import_alias.import_path;
    }
    return null;
}

fn bodyAliasKind(effect_param: ?[]const u8, aliases: []const Alias, name: []const u8) ?AliasKind {
    if (effect_param) |param| {
        if (std.mem.eql(u8, param, name)) return .effect_root;
    } else if (std.mem.eql(u8, name, "eff")) {
        return .effect_root;
    }
    for (aliases) |alias| {
        if (std.mem.eql(u8, alias.name, name)) return alias.kind;
    }
    return null;
}

fn upsertAlias(aliases: *[max_aliases]Alias, alias_count: *usize, name: []const u8, kind: AliasKind) bool {
    for (aliases[0..alias_count.*]) |*alias| {
        if (!std.mem.eql(u8, alias.name, name)) continue;
        alias.* = .{ .name = name, .kind = kind };
        return true;
    }
    if (alias_count.* >= aliases.len) return false;
    aliases[alias_count.*] = .{ .name = name, .kind = kind };
    alias_count.* += 1;
    return true;
}

fn parseAliasDeclaration(effect_param: ?[]const u8, aliases: []const Alias, statement: []const Token) ?Alias {
    if (statement.len != 7) return null;
    if (!(statement[0].tag == .keyword_const or statement[0].tag == .keyword_var)) return null;
    if (statement[1].tag != .identifier) return null;
    if (statement[2].tag != .equal) return null;
    if (statement[3].tag != .identifier) return null;
    const base_kind = bodyAliasKind(effect_param, aliases, statement[3].lexeme) orelse return null;
    switch (base_kind) {
        .effect_root => {
            if (statement[4].tag != .period or statement[5].tag != .identifier or statement[6].tag != .semicolon) return null;
            return .{
                .name = statement[1].lexeme,
                .kind = .{ .requirement = statement[5].lexeme },
            };
        },
        .requirement => return null,
    }
}

fn parseRequirementAliasTouch(effect_param: ?[]const u8, aliases: []const Alias, statement: []const Token) bool {
    const tokens = statementTrimSemicolon(statement);
    if (tokens.len != 5) return false;
    if (tokens[0].tag != .identifier or !std.mem.eql(u8, tokens[0].lexeme, "_")) return false;
    if (tokens[1].tag != .equal) return false;
    if (tokens[2].tag != .identifier) return false;
    const base_kind = bodyAliasKind(effect_param, aliases, tokens[2].lexeme) orelse return false;
    if (base_kind != .effect_root) return false;
    return tokens[3].tag == .period and tokens[4].tag == .identifier;
}

fn parseSingleValueExpr(statement: []const Token) ?ValueExpr {
    if (statement.len == 1) {
        return switch (statement[0].tag) {
            .identifier => blk: {
                if (std.mem.eql(u8, statement[0].lexeme, "true")) break :blk .{ .bool_literal = true };
                if (std.mem.eql(u8, statement[0].lexeme, "false")) break :blk .{ .bool_literal = false };
                break :blk .{ .local = statement[0].lexeme };
            },
            .number_literal => .{ .number_literal = statement[0].lexeme },
            .string_literal => .{ .string_literal = statement[0].lexeme },
            else => null,
        };
    }
    if (statement.len == 3 and
        statement[0].tag == .identifier and
        statement[1].tag == .plus and
        statement[2].tag == .number_literal)
    {
        return .{
            .add_const_i32 = .{
                .local_name = statement[0].lexeme,
                .increment_literal = statement[2].lexeme,
            },
        };
    }
    return null;
}

fn parseCommaSeparatedArgs(args: []const Token, out: *[max_helper_args]ValueExpr) ?usize {
    if (args.len == 0) return 0;
    var count: usize = 0;
    var start: usize = 0;
    var index: usize = 0;
    while (index <= args.len) : (index += 1) {
        if (index != args.len and args[index].tag != .comma) continue;
        if (count >= out.len) return null;
        out[count] = parseSingleValueExpr(args[start..index]) orelse return null;
        count += 1;
        start = index + 1;
    }
    return count;
}

fn helperValueTokens(effect_param: ?[]const u8, args: []const Token) ?[]const Token {
    if (args.len == 0) return &.{};
    if (args.len == 1 and args[0].tag == .identifier) {
        if (effect_param) |param| {
            if (std.mem.eql(u8, args[0].lexeme, param)) return &.{};
        } else if (std.mem.eql(u8, args[0].lexeme, "eff")) {
            return &.{};
        }
    }
    if (args.len >= 3 and args[args.len - 1].tag == .identifier and args[args.len - 2].tag == .comma) {
        const trailing_identifier = args[args.len - 1].lexeme;
        if (effect_param) |param| {
            if (std.mem.eql(u8, trailing_identifier, param)) return args[0 .. args.len - 2];
        } else if (std.mem.eql(u8, trailing_identifier, "eff")) {
            return args[0 .. args.len - 2];
        }
    }
    return args;
}

fn parseDirectPayload(args: []const Token) ?ValueExpr {
    if (args.len == 0) return null;
    return parseSingleValueExpr(args);
}

fn parseDirectCall(effect_param: ?[]const u8, aliases: []const Alias, statement: []const Token) ?DirectCall {
    const tokens = statementTrimSemicolon(statement);
    if (tokens.len == 0) return null;

    var index: usize = 0;
    var ignored_result = false;
    if (tokens.len >= 2 and
        tokens[0].tag == .identifier and
        std.mem.eql(u8, tokens[0].lexeme, "_") and
        tokens[1].tag == .equal)
    {
        index = 2;
        ignored_result = true;
    }
    if (index < tokens.len and tokens[index].tag == .keyword_try) index += 1;
    if (index >= tokens.len or tokens[index].tag != .identifier) return null;
    const base_kind = bodyAliasKind(effect_param, aliases, tokens[index].lexeme) orelse return null;

    return switch (base_kind) {
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
                return .{
                    .requirement_label = tokens[index + 2].lexeme,
                    .op_name = tokens[index + 4].lexeme,
                    .payload = parseDirectPayload(tokens[index + 8 .. tokens.len - 1]),
                    .ignored_result = ignored_result,
                };
            }
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
                .payload = parseDirectPayload(tokens[index + 6 .. tokens.len - 1]),
                .ignored_result = ignored_result,
            };
        },
        .requirement => |requirement_label| {
            if (index + 6 <= tokens.len and
                tokens[index + 1].tag == .period and
                tokens[index + 2].tag == .identifier and
                tokens[index + 3].tag == .period and
                tokens[index + 4].tag == .identifier and
                tokens[index + 5].tag == .l_paren and
                tokens[tokens.len - 1].tag == .r_paren and
                (std.mem.eql(u8, tokens[index + 4].lexeme, "perform") or std.mem.eql(u8, tokens[index + 4].lexeme, "abort")))
            {
                return .{
                    .requirement_label = requirement_label,
                    .op_name = tokens[index + 2].lexeme,
                    .payload = parseDirectPayload(tokens[index + 6 .. tokens.len - 1]),
                    .ignored_result = ignored_result,
                };
            }
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
                .payload = parseDirectPayload(tokens[index + 4 .. tokens.len - 1]),
                .ignored_result = ignored_result,
            };
        },
    };
}

fn parseHelperCall(effect_param: ?[]const u8, aliases: []const Alias, imports: anytype, statement: []const Token) ?HelperCall {
    const tokens = statementTrimSemicolon(statement);
    if (tokens.len == 0) return null;

    var index: usize = 0;
    if (tokens[index].tag == .keyword_try) index += 1;
    if (index >= tokens.len or tokens[index].tag != .identifier) return null;

    var helper_call = HelperCall{
        .callee_name = "",
        .import_alias = null,
        .arg_count = 0,
        .args = undefined,
    };

    if (index + 2 <= tokens.len and
        tokens[index + 1].tag == .l_paren and
        tokens[tokens.len - 1].tag == .r_paren)
    {
        helper_call.callee_name = tokens[index].lexeme;
        helper_call.arg_count = parseCommaSeparatedArgs(
            helperValueTokens(effect_param, tokens[index + 2 .. tokens.len - 1]) orelse return null,
            &helper_call.args,
        ) orelse return null;
        return helper_call;
    }

    if (index + 4 <= tokens.len and
        tokens[index + 1].tag == .period and
        tokens[index + 2].tag == .identifier and
        tokens[index + 3].tag == .l_paren and
        tokens[tokens.len - 1].tag == .r_paren)
    {
        if (bodyAliasKind(effect_param, aliases, tokens[index].lexeme) != null) return null;
        const import_path = findImportAlias(imports, tokens[index].lexeme) orelse return null;
        if (!importPathEndsWithZig(import_path)) return null;
        helper_call.callee_name = tokens[index + 2].lexeme;
        helper_call.import_alias = tokens[index].lexeme;
        helper_call.arg_count = parseCommaSeparatedArgs(
            helperValueTokens(effect_param, tokens[index + 4 .. tokens.len - 1]) orelse return null,
            &helper_call.args,
        ) orelse return null;
        return helper_call;
    }

    return null;
}

fn helperCallWithoutArgs(effect_param: ?[]const u8, aliases: []const Alias, imports: anytype, statement: []const Token) ?HelperCall {
    const helper_call = parseHelperCall(effect_param, aliases, imports, statement) orelse return null;
    if (helper_call.arg_count != 0) return null;
    return helper_call;
}

fn parseLiteralReturn(statement: []const Token) ?Literal {
    if (statement.len != 3) return null;
    if (statement[0].tag != .keyword_return or statement[2].tag != .semicolon) return null;
    if (tokenIsBoolLiteral(statement[1])) {
        return .{ .bool_value = std.mem.eql(u8, statement[1].lexeme, "true") };
    }
    return switch (statement[1].tag) {
        .number_literal => .{ .number_literal = statement[1].lexeme },
        .string_literal => .{ .string_value = statement[1].lexeme },
        else => null,
    };
}

fn parseLocalReturn(statement: []const Token) ?[]const u8 {
    if (statement.len != 3) return null;
    if (statement[0].tag != .keyword_return or statement[1].tag != .identifier or statement[2].tag != .semicolon) return null;
    return statement[1].lexeme;
}

fn parseAddLocalsReturn(statement: []const Token) ?struct {
    left_name: []const u8,
    right_name: []const u8,
} {
    if (statement.len != 5) return null;
    if (statement[0].tag != .keyword_return or statement[1].tag != .identifier or statement[2].tag != .plus or statement[3].tag != .identifier or statement[4].tag != .semicolon) return null;
    return .{
        .left_name = statement[1].lexeme,
        .right_name = statement[3].lexeme,
    };
}

fn parseReturnValue(effect_param: ?[]const u8, aliases: []const Alias, imports: anytype, statement: []const Token) ?ReturnValue {
    if (statementIsSimpleReturn(statement)) return .unit;
    if (parseLiteralReturn(statement)) |literal| return .{ .literal = literal };
    if (parseLocalReturn(statement)) |local_name| return .{ .local = local_name };
    if (parseAddLocalsReturn(statement)) |pair| return .{ .add_locals = .{
        .left_name = pair.left_name,
        .right_name = pair.right_name,
    } };

    const tokens = statementTrimSemicolon(statement);
    if (tokens.len < 2 or tokens[0].tag != .keyword_return) return null;
    if (parseDirectCall(effect_param, aliases, tokens[1..])) |direct_call| {
        if (direct_call.payload != null and direct_call.ignored_result) return null;
        return .{ .direct_call = direct_call };
    }
    if (helperCallWithoutArgs(effect_param, aliases, imports, tokens[1..])) |helper_call| {
        return .{ .helper_call = helper_call };
    }
    return null;
}

fn parseBoundLocalFromHelperCall(effect_param: ?[]const u8, aliases: []const Alias, imports: anytype, statement: []const Token) ?struct {
    local_name: []const u8,
    helper_call: HelperCall,
} {
    if (statement.len < 6) return null;
    if (statement[0].tag != .keyword_const or statement[1].tag != .identifier or statement[2].tag != .equal) return null;
    return .{
        .local_name = statement[1].lexeme,
        .helper_call = parseHelperCall(effect_param, aliases, imports, statement[3..]) orelse return null,
    };
}

fn parseBoundLocalFromNestedWith(
    statement: []const Token,
) ?struct {
    local_name: []const u8,
    requirement_label: []const u8,
    factory_name: []const u8,
    container_name: []const u8,
    handler_name: []const u8,
    carrier_name: ?[]const u8,
} {
    const tokens = statementTrimSemicolon(statement);
    if (tokens.len < 25) return null;
    if (tokens[0].tag != .keyword_const or tokens[1].tag != .identifier or tokens[2].tag != .equal) return null;
    if (tokens[3].tag != .l_paren or tokens[4].tag != .keyword_try) return null;
    if (!(tokens[5].tag == .identifier and std.mem.eql(u8, tokens[5].lexeme, "lexical_runtime"))) return null;
    if (tokens[6].tag != .period or tokens[7].tag != .identifier or !std.mem.eql(u8, tokens[7].lexeme, "with")) return null;
    if (tokens[8].tag != .l_paren) return null;

    var with_paren_depth: usize = 1;
    var brace_depth: usize = 0;
    var arg_index: usize = 0;
    var arg_start: usize = 9;
    var runtime_arg: ?[]const Token = null;
    var handlers_arg: ?[]const Token = null;
    var body_arg: ?[]const Token = null;
    var index: usize = 9;
    while (index < tokens.len) : (index += 1) {
        switch (tokens[index].tag) {
            .l_paren => with_paren_depth += 1,
            .r_paren => {
                with_paren_depth -= 1;
                if (with_paren_depth == 0 and brace_depth == 0) {
                    const arg = tokens[arg_start..index];
                    switch (arg_index) {
                        0 => runtime_arg = arg,
                        1 => handlers_arg = arg,
                        2 => body_arg = arg,
                        else => return null,
                    }
                    break;
                }
            },
            .l_brace => brace_depth += 1,
            .r_brace => {
                if (brace_depth != 0) brace_depth -= 1;
            },
            .comma => if (with_paren_depth == 1 and brace_depth == 0) {
                const arg = tokens[arg_start..index];
                switch (arg_index) {
                    0 => runtime_arg = arg,
                    1 => handlers_arg = arg,
                    else => return null,
                }
                arg_index += 1;
                arg_start = index + 1;
            },
            else => {},
        }
    }
    _ = runtime_arg orelse return null;
    const handlers = handlers_arg orelse return null;
    const body_tokens = body_arg orelse return null;

    if (!(index + 3 < tokens.len and
        tokens[index + 1].tag == .r_paren and
        tokens[index + 2].tag == .period and
        tokens[index + 3].tag == .identifier and
        std.mem.eql(u8, tokens[index + 3].lexeme, "value")))
    {
        return null;
    }

    if (!(handlers.len >= 18 and handlers[0].tag == .period and handlers[1].tag == .l_brace and handlers[2].tag == .period and handlers[3].tag == .identifier)) return null;
    if (!(handlers[4].tag == .equal and handlers[5].tag == .identifier and handlers[6].tag == .period and handlers[7].tag == .identifier and std.mem.eql(u8, handlers[7].lexeme, "use") and handlers[8].tag == .l_paren and handlers[9].tag == .period and handlers[10].tag == .l_brace and handlers[11].tag == .period and handlers[12].tag == .identifier and std.mem.eql(u8, handlers[12].lexeme, "handler"))) return null;
    const nested_label = handlers[3].lexeme;
    const factory_name = handlers[5].lexeme;
    if (!(handlers[13].tag == .equal and handlers[14].tag == .identifier and handlers[15].tag == .period and handlers[16].tag == .identifier and handlers[17].tag == .l_brace)) return null;
    const container_name = handlers[14].lexeme;
    const handler_name = handlers[16].lexeme;

    if (body_tokens.len == 0) return null;
    const carrier_name: ?[]const u8 = if (body_tokens[0].tag == .identifier)
        body_tokens[0].lexeme
    else if (body_tokens.len >= 2 and body_tokens[0].tag == .keyword_struct and body_tokens[1].tag == .l_brace)
        null
    else
        return null;

    return .{
        .local_name = tokens[1].lexeme,
        .requirement_label = nested_label,
        .factory_name = factory_name,
        .container_name = container_name,
        .handler_name = handler_name,
        .carrier_name = carrier_name,
    };
}

fn parseBoundLocalFromDirectCall(effect_param: ?[]const u8, aliases: []const Alias, statement: []const Token) ?struct {
    local_name: []const u8,
    direct_call: DirectCall,
} {
    if (statement.len < 6) return null;
    if (statement[0].tag != .keyword_const or statement[1].tag != .identifier or statement[2].tag != .equal) return null;
    return .{
        .local_name = statement[1].lexeme,
        .direct_call = parseDirectCall(effect_param, aliases, statement[3..]) orelse return null,
    };
}

fn parseBranchAction(effect_param: ?[]const u8, aliases: []const Alias, imports: anytype, statement: []const Token) ?BranchAction {
    if (parseDirectCall(effect_param, aliases, statement)) |direct_call| return .{ .direct_call = direct_call };
    if (helperCallWithoutArgs(effect_param, aliases, imports, statement)) |helper_call| return .{ .helper_call = helper_call };
    if (statementIsSimpleReturn(statement)) return .return_unit;
    return null;
}

fn parseIfLocalEqZeroReturnUnit(statement: []const Token) ?[]const u8 {
    if (statement.len != 8) return null;
    if (statement[0].tag != .keyword_if or
        statement[1].tag != .l_paren or
        statement[2].tag != .identifier or
        statement[3].tag != .equal_equal or
        statement[4].tag != .number_literal or
        !std.mem.eql(u8, statement[4].lexeme, "0") or
        statement[5].tag != .r_paren or
        statement[6].tag != .keyword_return or
        statement[7].tag != .semicolon)
    {
        return null;
    }
    return statement[2].lexeme;
}

fn parseIfLocalEqZeroBranch(effect_param: ?[]const u8, aliases: []const Alias, imports: anytype, statement: []const Token) ?struct {
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
    return .{
        .local_name = statement[2].lexeme,
        .then_action = parseBranchAction(effect_param, aliases, imports, statement[6..else_index]) orelse return null,
        .else_action = parseBranchAction(effect_param, aliases, imports, statement[(else_index + 1)..]) orelse return null,
    };
}

fn parseLocalDecrementOp(effect_param: ?[]const u8, aliases: []const Alias, statement: []const Token) ?struct {
    local_name: []const u8,
    requirement_label: []const u8,
    op_name: []const u8,
} {
    const tokens = statementTrimSemicolon(statement);
    if (tokens.len == 0) return null;
    var index: usize = 0;
    if (tokens[index].tag == .keyword_try) index += 1;
    if (index >= tokens.len or tokens[index].tag != .identifier) return null;
    const base_kind = bodyAliasKind(effect_param, aliases, tokens[index].lexeme) orelse return null;
    if (base_kind != .effect_root) return null;
    if (index + 10 > tokens.len) return null;
    if (!(tokens[index + 1].tag == .period and
        tokens[index + 2].tag == .identifier and
        tokens[index + 3].tag == .period and
        tokens[index + 4].tag == .identifier and
        tokens[index + 5].tag == .l_paren and
        tokens[index + 6].tag == .identifier and
        tokens[index + 7].tag == .minus and
        tokens[index + 8].tag == .number_literal and
        std.mem.eql(u8, tokens[index + 8].lexeme, "1") and
        tokens[index + 9].tag == .r_paren))
    {
        return null;
    }
    return .{
        .local_name = tokens[index + 6].lexeme,
        .requirement_label = tokens[index + 2].lexeme,
        .op_name = tokens[index + 4].lexeme,
    };
}

fn continuationStructStart(args: []const Token) ?struct {
    payload_end: usize,
    struct_start: usize,
} {
    if (args.len >= 2 and args[0].tag == .keyword_struct and args[1].tag == .l_brace) {
        return .{ .payload_end = 0, .struct_start = 0 };
    }

    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    var brace_depth: usize = 0;
    for (args, 0..) |token, index| {
        switch (token.tag) {
            .l_paren => paren_depth += 1,
            .r_paren => {
                if (paren_depth != 0) paren_depth -= 1;
            },
            .l_bracket => bracket_depth += 1,
            .r_bracket => {
                if (bracket_depth != 0) bracket_depth -= 1;
            },
            .l_brace => brace_depth += 1,
            .r_brace => {
                if (brace_depth != 0) brace_depth -= 1;
            },
            .comma => if (paren_depth == 0 and bracket_depth == 0 and brace_depth == 0) {
                const next_index = index + 1;
                if (next_index + 1 < args.len and
                    args[next_index].tag == .keyword_struct and
                    args[next_index + 1].tag == .l_brace)
                {
                    return .{ .payload_end = index, .struct_start = next_index };
                }
            },
            else => {},
        }
    }
    return null;
}

fn continuationStructTokens(args: []const Token, struct_start: usize) ?[]const Token {
    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    var brace_depth: usize = 0;
    var index: usize = struct_start;
    while (index < args.len) : (index += 1) {
        switch (args[index].tag) {
            .l_paren => paren_depth += 1,
            .r_paren => {
                if (paren_depth == 0) return null;
                paren_depth -= 1;
            },
            .l_bracket => bracket_depth += 1,
            .r_bracket => {
                if (bracket_depth == 0) return null;
                bracket_depth -= 1;
            },
            .l_brace => brace_depth += 1,
            .r_brace => {
                if (brace_depth == 0) return null;
                brace_depth -= 1;
            },
            else => {},
        }
        if (index == struct_start or paren_depth != 0 or bracket_depth != 0 or brace_depth != 0) continue;
        const struct_end = index + 1;
        const tail = args[struct_end..];
        if (tail.len == 0) return args[struct_start..struct_end];
        if (tail.len == 1 and tail[0].tag == .comma) return args[struct_start..struct_end];
        return null;
    }
    return null;
}

fn parseContinuationApplyReturn(struct_tokens: []const Token) ?struct {
    param_name: ?[]const u8,
    return_value: ReturnValue,
} {
    if (struct_tokens.len < 4) return null;
    if (struct_tokens[0].tag != .keyword_struct or struct_tokens[1].tag != .l_brace) return null;

    var index: usize = 2;
    while (index + 1 < struct_tokens.len) : (index += 1) {
        if (struct_tokens[index].tag != .keyword_fn and
            !(struct_tokens[index].tag == .keyword_pub and index + 1 < struct_tokens.len and struct_tokens[index + 1].tag == .keyword_fn))
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
        if (fn_index + 2 >= struct_tokens.len or struct_tokens[fn_index + 2].tag != .l_paren) return null;

        var param_name: ?[]const u8 = null;
        var expect_param_name = true;
        var param_depth: usize = 1;
        var cursor = fn_index + 3;
        while (cursor < struct_tokens.len and param_depth != 0) : (cursor += 1) {
            if (struct_tokens[cursor].tag == .l_paren) {
                param_depth += 1;
            } else if (struct_tokens[cursor].tag == .r_paren) {
                param_depth -= 1;
            } else if (struct_tokens[cursor].tag == .comma and param_depth == 1) {
                expect_param_name = true;
            } else if (struct_tokens[cursor].tag == .colon and param_depth == 1) {
                expect_param_name = false;
            } else if (struct_tokens[cursor].tag == .identifier and param_depth == 1 and expect_param_name and param_name == null) {
                if (!std.mem.eql(u8, struct_tokens[cursor].lexeme, "_")) param_name = struct_tokens[cursor].lexeme;
                expect_param_name = false;
            }
        }
        if (param_depth != 0 or cursor >= struct_tokens.len) return null;

        while (cursor < struct_tokens.len and struct_tokens[cursor].tag != .l_brace) : (cursor += 1) {}
        if (cursor >= struct_tokens.len) return null;
        const body_start = cursor + 1;
        var body_depth: usize = 1;
        cursor = body_start;
        while (cursor < struct_tokens.len and body_depth != 0) : (cursor += 1) {
            if (struct_tokens[cursor].tag == .l_brace) {
                body_depth += 1;
            } else if (struct_tokens[cursor].tag == .r_brace) {
                body_depth -= 1;
            }
        }
        if (body_depth != 0 or cursor == 0) return null;
        return .{
            .param_name = param_name,
            .return_value = parseReturnValue(null, &.{}, &.{}, struct_tokens[body_start .. cursor - 1]) orelse return null,
        };
    }
    return null;
}

fn parseReturnContinuationDirect(effect_param: ?[]const u8, aliases: []const Alias, statement: []const Token) ?struct {
    direct_call: DirectCall,
    apply_param_name: ?[]const u8,
    apply_return: ReturnValue,
} {
    const tokens = statementTrimSemicolon(statement);
    if (tokens.len == 0 or tokens[0].tag != .keyword_return) return null;

    var index: usize = 1;
    if (index < tokens.len and tokens[index].tag == .keyword_try) index += 1;
    if (index >= tokens.len or tokens[index].tag != .identifier) return null;
    const base_kind = bodyAliasKind(effect_param, aliases, tokens[index].lexeme) orelse return null;

    const ArgsBounds = struct {
        requirement_label: []const u8,
        op_name: []const u8,
        start: usize,
    };
    const args_bounds: ArgsBounds = switch (base_kind) {
        .effect_root => blk: {
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
                break :blk .{
                    .requirement_label = tokens[index + 2].lexeme,
                    .op_name = tokens[index + 4].lexeme,
                    .start = index + 8,
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
                break :blk .{
                    .requirement_label = tokens[index + 2].lexeme,
                    .op_name = tokens[index + 4].lexeme,
                    .start = index + 6,
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
                tokens[tokens.len - 1].tag == .r_paren and
                (std.mem.eql(u8, tokens[index + 4].lexeme, "perform") or std.mem.eql(u8, tokens[index + 4].lexeme, "abort")))
            {
                break :blk .{
                    .requirement_label = requirement_label,
                    .op_name = tokens[index + 2].lexeme,
                    .start = index + 6,
                };
            }
            if (index + 4 <= tokens.len and
                tokens[index + 1].tag == .period and
                tokens[index + 2].tag == .identifier and
                tokens[index + 3].tag == .l_paren and
                tokens[tokens.len - 1].tag == .r_paren)
            {
                break :blk .{
                    .requirement_label = requirement_label,
                    .op_name = tokens[index + 2].lexeme,
                    .start = index + 4,
                };
            }
            return null;
        },
    };

    const args = tokens[args_bounds.start .. tokens.len - 1];
    const struct_arg = continuationStructStart(args) orelse return null;
    const struct_tokens = continuationStructTokens(args, struct_arg.struct_start) orelse return null;
    const apply = parseContinuationApplyReturn(struct_tokens) orelse return null;
    return .{
        .direct_call = .{
            .requirement_label = args_bounds.requirement_label,
            .op_name = args_bounds.op_name,
            .payload = parseDirectPayload(args[0..struct_arg.payload_end]),
            .ignored_result = false,
        },
        .apply_param_name = apply.param_name,
        .apply_return = apply.return_value,
    };
}

fn bodyTokens(source: [:0]const u8, body_start_offset: usize, body_end_offset: usize, out: *[max_body_tokens]Token) ?usize {
    var tokenizer = std.zig.Tokenizer.init(source);
    var count: usize = 0;
    while (true) {
        const token = tokenizer.next();
        if (token.tag == .eof or token.loc.start >= body_end_offset) break;
        if (token.loc.end <= body_start_offset) continue;
        if (token.tag == .doc_comment or token.tag == .container_doc_comment) continue;
        if (count >= out.len) return null;
        out[count] = .{
            .tag = token.tag,
            .lexeme = source[token.loc.start..token.loc.end],
        };
        count += 1;
    }
    return count;
}

fn statementRanges(tokens: []const Token, out: *[max_steps]StatementRange) ?usize {
    var count: usize = 0;
    var start: usize = 0;
    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    var brace_depth: usize = 0;
    for (tokens, 0..) |token, index| {
        switch (token.tag) {
            .l_paren => paren_depth += 1,
            .r_paren => {
                if (paren_depth != 0) paren_depth -= 1;
            },
            .l_bracket => bracket_depth += 1,
            .r_bracket => {
                if (bracket_depth != 0) bracket_depth -= 1;
            },
            .l_brace => brace_depth += 1,
            .r_brace => {
                if (brace_depth != 0) brace_depth -= 1;
            },
            else => {},
        }
        if (token.tag != .semicolon or paren_depth != 0 or bracket_depth != 0 or brace_depth != 0) continue;
        if (count >= out.len) return null;
        out[count] = .{ .start = start, .end = index + 1 };
        count += 1;
        start = index + 1;
    }
    if (start != tokens.len) return null;
    return count;
}

pub fn parseFunctionBody(
    source: [:0]const u8,
    comptime module_path: []const u8,
    body_start_offset: usize,
    body_end_offset: usize,
    effect_param: ?[]const u8,
    imports: anytype,
) ?Body {
    var tokens_buffer: [max_body_tokens]Token = undefined;
    const token_count = bodyTokens(source, body_start_offset, body_end_offset, &tokens_buffer) orelse return null;
    const tokens = tokens_buffer[0..token_count];

    var ranges_buffer: [max_steps]StatementRange = undefined;
    const statement_count = statementRanges(tokens, &ranges_buffer) orelse return null;
    const statement_ranges = ranges_buffer[0..statement_count];

    var body: Body = .{ .step_count = 0, .steps = undefined };
    var aliases: [max_aliases]Alias = undefined;
    var alias_count: usize = 0;

    for (statement_ranges) |range| {
        const statement = tokens[range.start..range.end];
        if (statement.len == 0) continue;
        if (parseAliasDeclaration(effect_param, aliases[0..alias_count], statement)) |alias| {
            if (!upsertAlias(&aliases, &alias_count, alias.name, alias.kind)) return null;
            continue;
        }
        if (parseRequirementAliasTouch(effect_param, aliases[0..alias_count], statement)) continue;
        if (body.step_count >= body.steps.len) return null;

        _ = module_path;
        if (parseBoundLocalFromNestedWith(statement)) |nested_with| {
            body.steps[body.step_count] = .{ .bind_local_from_nested_with = .{
                .local_name = nested_with.local_name,
                .requirement_label = nested_with.requirement_label,
                .factory_name = nested_with.factory_name,
                .container_name = nested_with.container_name,
                .handler_name = nested_with.handler_name,
                .carrier_name = nested_with.carrier_name,
            } };
            body.step_count += 1;
            continue;
        }
        if (parseBoundLocalFromHelperCall(effect_param, aliases[0..alias_count], imports, statement)) |bound_helper| {
            body.steps[body.step_count] = .{ .bind_local_from_helper = .{
                .local_name = bound_helper.local_name,
                .helper_call = bound_helper.helper_call,
            } };
            body.step_count += 1;
            continue;
        }
        if (parseBoundLocalFromDirectCall(effect_param, aliases[0..alias_count], statement)) |bound_direct| {
            body.steps[body.step_count] = .{ .bind_local_from_direct = .{
                .local_name = bound_direct.local_name,
                .direct_call = bound_direct.direct_call,
            } };
            body.step_count += 1;
            continue;
        }
        if (parseIfLocalEqZeroBranch(effect_param, aliases[0..alias_count], imports, statement)) |branch| {
            body.steps[body.step_count] = .{ .if_local_eq_zero_branch = .{
                .local_name = branch.local_name,
                .then_action = branch.then_action,
                .else_action = branch.else_action,
            } };
            body.step_count += 1;
            continue;
        }
        if (parseIfLocalEqZeroReturnUnit(statement)) |local_name| {
            body.steps[body.step_count] = .{ .if_local_eq_zero_return_unit = local_name };
            body.step_count += 1;
            continue;
        }
        if (parseReturnContinuationDirect(effect_param, aliases[0..alias_count], statement)) |continuation_call| {
            body.steps[body.step_count] = .{ .return_continuation_direct = .{
                .direct_call = continuation_call.direct_call,
                .apply_param_name = continuation_call.apply_param_name,
                .apply_return = continuation_call.apply_return,
            } };
            body.step_count += 1;
            continue;
        }
        if (parseLocalDecrementOp(effect_param, aliases[0..alias_count], statement)) |decrement_op| {
            body.steps[body.step_count] = .{ .decrement_local_direct = .{
                .local_name = decrement_op.local_name,
                .requirement_label = decrement_op.requirement_label,
                .op_name = decrement_op.op_name,
            } };
            body.step_count += 1;
            continue;
        }
        if (parseDirectCall(effect_param, aliases[0..alias_count], statement)) |direct_call| {
            body.steps[body.step_count] = .{ .call_direct = direct_call };
            body.step_count += 1;
            continue;
        }
        if (parseHelperCall(effect_param, aliases[0..alias_count], imports, statement)) |helper_call| {
            body.steps[body.step_count] = .{ .call_helper = helper_call };
            body.step_count += 1;
            continue;
        }
        if (parseReturnValue(effect_param, aliases[0..alias_count], imports, statement)) |return_value| {
            body.steps[body.step_count] = .{ .return_value = return_value };
            body.step_count += 1;
            continue;
        }
        return null;
    }

    return body;
}

test "parseFunctionBody normalizes a bound helper and literal return" {
    const source =
        \\pub fn run(eff: anytype) i32 {
        \\    const value = try helper(eff);
        \\    return value;
        \\}
    ;
    const body_start = comptime std.mem.findScalar(u8, source, '{').? + 1;
    const body_end = comptime std.mem.findScalarLast(u8, source, '}').?;
    const body = parseFunctionBody(source, "test/direct_return.zig", body_start, body_end, "eff", &.{}) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 2), body.step_count);
    try std.testing.expect(body.steps[0] == .bind_local_from_helper);
    try std.testing.expect(body.steps[1] == .return_value);
}

test "parseFunctionBody normalizes continuation apply return" {
    const source =
        \\pub fn run(eff: anytype) i32 {
        \\    return try eff.state.get(struct {
        \\        fn apply(value: i32) i32 {
        \\            return value;
        \\        }
        \\    });
        \\}
    ;
    const body_start = comptime std.mem.findScalar(u8, source, '{').? + 1;
    const body_end = comptime std.mem.findScalarLast(u8, source, '}').?;
    const body = parseFunctionBody(source, "test/continuation.zig", body_start, body_end, "eff", &.{}) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 1), body.step_count);
    try std.testing.expect(body.steps[0] == .return_continuation_direct);
}
