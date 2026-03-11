const std = @import("std");

pub const CompileError = error{
    ParseFailed,
    TypeFailed,
    Unsupported,
};

pub const Type = enum {
    i32,
    bool,
    string,
    unit,

    fn zigName(self: Type) []const u8 {
        return switch (self) {
            .i32 => "i32",
            .bool => "bool",
            .string => "[]const u8",
            .unit => "void",
        };
    }
};

pub const Diagnostic = struct {
    line: usize,
    message: []const u8,
};

pub const DiagnosticList = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(Diagnostic) = .empty,

    pub fn init(allocator: std.mem.Allocator) DiagnosticList {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *DiagnosticList) void {
        self.items.deinit(self.allocator);
    }

    pub fn append(self: *DiagnosticList, diagnostic: Diagnostic) !void {
        try self.items.append(self.allocator, diagnostic);
    }
};

pub const Artifact = struct {
    zig: []u8,
    source_map_json: []u8,
    certificate_json: []u8,
};

pub fn freeArtifact(allocator: std.mem.Allocator, artifact: Artifact) void {
    allocator.free(artifact.zig);
    allocator.free(artifact.source_map_json);
    allocator.free(artifact.certificate_json);
}

const TokenTag = enum {
    lparen,
    rparen,
    atom,
    string,
};

const Token = struct {
    tag: TokenTag,
    lexeme: []const u8,
    line: usize,
};

const Form = struct {
    line: usize,
    data: union(enum) {
        atom: []const u8,
        string: []const u8,
        list: []const Form,
    },
};

const Param = struct {
    name: []const u8,
    value_type: Type,
};

const EffectDecl = struct {
    name: []const u8,
    request_ty: Type,
    response_ty: Type,
};

const HandlerActionTag = enum {
    @"resume",
    discard,
};

const Expr = union(enum) {
    int_lit: i32,
    bool_lit: bool,
    string_lit: []const u8,
    unit_lit: void,
    ident: []const u8,
    add: struct { lhs: *Expr, rhs: *Expr },
    perform: struct { effect_name: []const u8, request: *Expr },
};

const ProgramStmt = union(enum) {
    let_stmt: struct { name: []const u8, expr: *Expr, line: usize },
    return_stmt: struct { expr: *Expr, line: usize },
    if_stmt: struct { cond: *Expr, then_block: []const ProgramStmt, else_block: []const ProgramStmt, line: usize },
};

const HandlerStmt = union(enum) {
    let_stmt: struct { name: []const u8, expr: *Expr, line: usize },
    resume_stmt: struct { expr: *Expr, line: usize },
    discard_stmt: struct { expr: *Expr, line: usize },
    if_stmt: struct { cond: *Expr, then_block: []const HandlerStmt, else_block: []const HandlerStmt, line: usize },
};

const Handler = struct {
    effect_name: []const u8,
    request_name: []const u8,
    resume_name: []const u8,
    body: []const HandlerStmt,
    line: usize,
};

const ExportDecl = struct {
    name: []const u8,
    params: []const Param,
    return_ty: Type,
    handlers: []const Handler,
    program: []const ProgramStmt,
    line: usize,
};

const Module = struct {
    name: []const u8,
    effects: []const EffectDecl,
    export_decl: ExportDecl,
};

const HandlerCertificate = struct {
    effect_name: []const u8,
    action: HandlerActionTag,
    line: usize,
};

fn upperCamelName(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    var uppercase_next = true;
    for (text) |ch| {
        if (ch == '_') {
            uppercase_next = true;
            continue;
        }
        const next = if (uppercase_next) std.ascii.toUpper(ch) else ch;
        uppercase_next = false;
        try out.append(allocator, next);
    }
    return out.toOwnedSlice(allocator);
}

const TypeEnv = struct {
    map: std.StringHashMap(Type),

    fn init(allocator: std.mem.Allocator) TypeEnv {
        return .{ .map = std.StringHashMap(Type).init(allocator) };
    }

    fn deinit(self: *TypeEnv) void {
        self.map.deinit();
    }

    fn put(self: *TypeEnv, name: []const u8, value_type: Type) !void {
        try self.map.put(name, value_type);
    }

    fn get(self: *const TypeEnv, name: []const u8) ?Type {
        return self.map.get(name);
    }
};

const ParseCtx = struct {
    arena: std.mem.Allocator,
    tokens: []const Token,
    index: usize = 0,
    diagnostics: *DiagnosticList,

    fn eof(self: *const ParseCtx) bool {
        return self.index >= self.tokens.len;
    }

    fn peek(self: *const ParseCtx) ?Token {
        if (self.eof()) return null;
        return self.tokens[self.index];
    }

    fn advance(self: *ParseCtx) ?Token {
        const tok = self.peek() orelse return null;
        self.index += 1;
        return tok;
    }

    fn expectTag(self: *ParseCtx, tag: TokenTag, message: []const u8) !Token {
        const tok = self.advance() orelse {
            try self.diagnostics.append(.{ .line = if (self.tokens.len == 0) 1 else self.tokens[self.tokens.len - 1].line, .message = message });
            return CompileError.ParseFailed;
        };
        if (tok.tag != tag) {
            try self.diagnostics.append(.{ .line = tok.line, .message = message });
            return CompileError.ParseFailed;
        }
        return tok;
    }

    fn parseForm(self: *ParseCtx) !Form {
        const tok = self.advance() orelse {
            try self.diagnostics.append(.{ .line = 1, .message = "unexpected end of file" });
            return CompileError.ParseFailed;
        };
        return switch (tok.tag) {
            .atom => .{ .line = tok.line, .data = .{ .atom = tok.lexeme } },
            .string => .{ .line = tok.line, .data = .{ .string = tok.lexeme } },
            .lparen => blk: {
                var forms: std.ArrayList(Form) = .empty;
                while (true) {
                    const next = self.peek() orelse {
                        try self.diagnostics.append(.{ .line = tok.line, .message = "missing closing ')'" });
                        return CompileError.ParseFailed;
                    };
                    if (next.tag == .rparen) {
                        _ = self.advance();
                        break;
                    }
                    try forms.append(self.arena, try self.parseForm());
                }
                break :blk .{ .line = tok.line, .data = .{ .list = try forms.toOwnedSlice(self.arena) } };
            },
            .rparen => {
                try self.diagnostics.append(.{ .line = tok.line, .message = "unexpected ')'" });
                return CompileError.ParseFailed;
            },
        };
    }
};

fn tokenize(allocator: std.mem.Allocator, source: []const u8) ![]Token {
    var tokens: std.ArrayList(Token) = .empty;
    errdefer tokens.deinit(allocator);
    var i: usize = 0;
    var line: usize = 1;
    while (i < source.len) {
        switch (source[i]) {
            ' ', '\t', '\r' => i += 1,
            '\n' => {
                line += 1;
                i += 1;
            },
            ';' => {
                while (i < source.len and source[i] != '\n') i += 1;
            },
            '(' => {
                try tokens.append(allocator, .{ .tag = .lparen, .lexeme = source[i .. i + 1], .line = line });
                i += 1;
            },
            ')' => {
                try tokens.append(allocator, .{ .tag = .rparen, .lexeme = source[i .. i + 1], .line = line });
                i += 1;
            },
            '"' => {
                const start_line = line;
                i += 1;
                var buf: std.ArrayList(u8) = .empty;
                defer buf.deinit(allocator);
                while (i < source.len and source[i] != '"') {
                    if (source[i] == '\\' and i + 1 < source.len) {
                        i += 1;
                        const escaped = switch (source[i]) {
                            'n' => '\n',
                            '"', '\\' => source[i],
                            else => source[i],
                        };
                        try buf.append(allocator, escaped);
                        i += 1;
                        continue;
                    }
                    if (source[i] == '\n') line += 1;
                    try buf.append(allocator, source[i]);
                    i += 1;
                }
                if (i >= source.len) return error.EndOfStream;
                i += 1;
                try tokens.append(allocator, .{
                    .tag = .string,
                    .lexeme = try allocator.dupe(u8, buf.items),
                    .line = start_line,
                });
            },
            else => {
                const start = i;
                while (i < source.len) : (i += 1) {
                    const ch = source[i];
                    if (ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n' or ch == '(' or ch == ')' or ch == ';') break;
                }
                try tokens.append(allocator, .{ .tag = .atom, .lexeme = source[start..i], .line = line });
            },
        }
    }
    return tokens.toOwnedSlice(allocator);
}

fn parseType(text: []const u8) ?Type {
    if (std.mem.eql(u8, text, "i32")) return .i32;
    if (std.mem.eql(u8, text, "bool")) return .bool;
    if (std.mem.eql(u8, text, "string")) return .string;
    if (std.mem.eql(u8, text, "unit")) return .unit;
    return null;
}

fn expectAtom(form: Form) ![]const u8 {
    return switch (form.data) {
        .atom => |atom| atom,
        else => CompileError.ParseFailed,
    };
}

fn expectList(form: Form) ![]const Form {
    return switch (form.data) {
        .list => |list| list,
        else => CompileError.ParseFailed,
    };
}

fn parseExpr(arena: std.mem.Allocator, diagnostics: *DiagnosticList, form: Form) anyerror!*Expr {
    const expr = try arena.create(Expr);
    switch (form.data) {
        .atom => |atom| {
            if (std.mem.eql(u8, atom, "true")) {
                expr.* = .{ .bool_lit = true };
            } else if (std.mem.eql(u8, atom, "false")) {
                expr.* = .{ .bool_lit = false };
            } else if (std.mem.eql(u8, atom, "unit")) {
                expr.* = .{ .unit_lit = {} };
            } else if (std.fmt.parseInt(i32, atom, 10)) |value| {
                expr.* = .{ .int_lit = value };
            } else |_| {
                expr.* = .{ .ident = atom };
            }
        },
        .string => |value| expr.* = .{ .string_lit = value },
        .list => |list| {
            if (list.len == 0) {
                try diagnostics.append(.{ .line = form.line, .message = "empty expression list" });
                return CompileError.ParseFailed;
            }
            const head = try expectAtom(list[0]);
            if (std.mem.eql(u8, head, "add")) {
                if (list.len != 3) {
                    try diagnostics.append(.{ .line = form.line, .message = "add expects two arguments" });
                    return CompileError.ParseFailed;
                }
                expr.* = .{
                    .add = .{
                        .lhs = try parseExpr(arena, diagnostics, list[1]),
                        .rhs = try parseExpr(arena, diagnostics, list[2]),
                    },
                };
            } else if (std.mem.eql(u8, head, "perform")) {
                if (list.len != 3) {
                    try diagnostics.append(.{ .line = form.line, .message = "perform expects an effect name and one request expression" });
                    return CompileError.ParseFailed;
                }
                expr.* = .{
                    .perform = .{
                        .effect_name = try expectAtom(list[1]),
                        .request = try parseExpr(arena, diagnostics, list[2]),
                    },
                };
            } else {
                try diagnostics.append(.{ .line = form.line, .message = "unsupported expression form" });
                return CompileError.ParseFailed;
            }
        },
    }
    return expr;
}

fn parseProgramBlock(arena: std.mem.Allocator, diagnostics: *DiagnosticList, form: Form) anyerror![]const ProgramStmt {
    const list = try expectList(form);
    if (list.len == 0 or !std.mem.eql(u8, try expectAtom(list[0]), "program")) {
        try diagnostics.append(.{ .line = form.line, .message = "expected (program ...)" });
        return CompileError.ParseFailed;
    }
    var stmts: std.ArrayList(ProgramStmt) = .empty;
    errdefer stmts.deinit(arena);
    for (list[1..]) |stmt_form| {
        const stmt_list = try expectList(stmt_form);
        if (stmt_list.len == 0) {
            try diagnostics.append(.{ .line = stmt_form.line, .message = "empty statement" });
            return CompileError.ParseFailed;
        }
        const head = try expectAtom(stmt_list[0]);
        if (std.mem.eql(u8, head, "let")) {
            if (stmt_list.len != 3) {
                try diagnostics.append(.{ .line = stmt_form.line, .message = "let expects a name and an expression" });
                return CompileError.ParseFailed;
            }
            try stmts.append(arena, .{
                .let_stmt = .{
                    .name = try expectAtom(stmt_list[1]),
                    .expr = try parseExpr(arena, diagnostics, stmt_list[2]),
                    .line = stmt_form.line,
                },
            });
        } else if (std.mem.eql(u8, head, "return")) {
            if (stmt_list.len != 2) {
                try diagnostics.append(.{ .line = stmt_form.line, .message = "return expects one expression" });
                return CompileError.ParseFailed;
            }
            try stmts.append(arena, .{
                .return_stmt = .{
                    .expr = try parseExpr(arena, diagnostics, stmt_list[1]),
                    .line = stmt_form.line,
                },
            });
        } else if (std.mem.eql(u8, head, "if")) {
            if (stmt_list.len != 4) {
                try diagnostics.append(.{ .line = stmt_form.line, .message = "if expects condition, then block, and else block" });
                return CompileError.ParseFailed;
            }
            try stmts.append(arena, .{
                .if_stmt = .{
                    .cond = try parseExpr(arena, diagnostics, stmt_list[1]),
                    .then_block = try parseProgramNestedBlock(arena, diagnostics, stmt_list[2]),
                    .else_block = try parseProgramNestedBlock(arena, diagnostics, stmt_list[3]),
                    .line = stmt_form.line,
                },
            });
        } else {
            try diagnostics.append(.{ .line = stmt_form.line, .message = "unsupported program statement" });
            return CompileError.ParseFailed;
        }
    }
    return stmts.toOwnedSlice(arena);
}

fn parseProgramNestedBlock(arena: std.mem.Allocator, diagnostics: *DiagnosticList, form: Form) anyerror![]const ProgramStmt {
    const list = try expectList(form);
    if (list.len == 0 or !std.mem.eql(u8, try expectAtom(list[0]), "block")) {
        try diagnostics.append(.{ .line = form.line, .message = "expected (block ...)" });
        return CompileError.ParseFailed;
    }
    var program_like: std.ArrayList(Form) = .empty;
    errdefer program_like.deinit(arena);
    try program_like.append(arena, .{ .line = form.line, .data = .{ .atom = "program" } });
    for (list[1..]) |item| try program_like.append(arena, item);
    return parseProgramBlock(arena, diagnostics, .{ .line = form.line, .data = .{ .list = try program_like.toOwnedSlice(arena) } });
}

fn parseHandlerNestedBlock(arena: std.mem.Allocator, diagnostics: *DiagnosticList, form: Form) anyerror![]const HandlerStmt {
    const list = try expectList(form);
    if (list.len == 0 or !std.mem.eql(u8, try expectAtom(list[0]), "block")) {
        try diagnostics.append(.{ .line = form.line, .message = "expected handler (block ...)" });
        return CompileError.ParseFailed;
    }
    var stmts: std.ArrayList(HandlerStmt) = .empty;
    errdefer stmts.deinit(arena);
    for (list[1..]) |item| try stmts.append(arena, try parseHandlerStmt(arena, diagnostics, item));
    return stmts.toOwnedSlice(arena);
}

fn parseHandlerStmt(arena: std.mem.Allocator, diagnostics: *DiagnosticList, form: Form) anyerror!HandlerStmt {
    const list = try expectList(form);
    if (list.len == 0) {
        try diagnostics.append(.{ .line = form.line, .message = "empty handler statement" });
        return CompileError.ParseFailed;
    }
    const head = try expectAtom(list[0]);
    if (std.mem.eql(u8, head, "let")) {
        if (list.len != 3) {
            try diagnostics.append(.{ .line = form.line, .message = "handler let expects a name and an expression" });
            return CompileError.ParseFailed;
        }
        return .{
            .let_stmt = .{
                .name = try expectAtom(list[1]),
                .expr = try parseExpr(arena, diagnostics, list[2]),
                .line = form.line,
            },
        };
    }
    if (std.mem.eql(u8, head, "resume")) {
        if (list.len != 2) {
            try diagnostics.append(.{ .line = form.line, .message = "resume expects one expression" });
            return CompileError.ParseFailed;
        }
        return .{
            .resume_stmt = .{
                .expr = try parseExpr(arena, diagnostics, list[1]),
                .line = form.line,
            },
        };
    }
    if (std.mem.eql(u8, head, "discard")) {
        if (list.len != 2) {
            try diagnostics.append(.{ .line = form.line, .message = "discard expects one expression" });
            return CompileError.ParseFailed;
        }
        return .{
            .discard_stmt = .{
                .expr = try parseExpr(arena, diagnostics, list[1]),
                .line = form.line,
            },
        };
    }
    if (std.mem.eql(u8, head, "if")) {
        if (list.len != 4) {
            try diagnostics.append(.{ .line = form.line, .message = "handler if expects condition, then block, and else block" });
            return CompileError.ParseFailed;
        }
        return .{
            .if_stmt = .{
                .cond = try parseExpr(arena, diagnostics, list[1]),
                .then_block = try parseHandlerNestedBlock(arena, diagnostics, list[2]),
                .else_block = try parseHandlerNestedBlock(arena, diagnostics, list[3]),
                .line = form.line,
            },
        };
    }
    try diagnostics.append(.{ .line = form.line, .message = "unsupported handler statement" });
    return CompileError.ParseFailed;
}

fn parseModule(arena: std.mem.Allocator, diagnostics: *DiagnosticList, forms: []const Form) anyerror!Module {
    if (forms.len != 1) {
        try diagnostics.append(.{ .line = if (forms.len == 0) 1 else forms[0].line, .message = "expected exactly one top-level module form" });
        return CompileError.ParseFailed;
    }
    const module_list = try expectList(forms[0]);
    if (module_list.len < 3 or !std.mem.eql(u8, try expectAtom(module_list[0]), "module")) {
        try diagnostics.append(.{ .line = forms[0].line, .message = "expected (module name ...)" });
        return CompileError.ParseFailed;
    }
    const module_name = try expectAtom(module_list[1]);
    var effects: std.ArrayList(EffectDecl) = .empty;
    errdefer effects.deinit(arena);
    var export_decl_opt: ?ExportDecl = null;
    for (module_list[2..]) |item| {
        const list = try expectList(item);
        if (list.len == 0) {
            try diagnostics.append(.{ .line = item.line, .message = "empty module item" });
            return CompileError.ParseFailed;
        }
        const head = try expectAtom(list[0]);
        if (std.mem.eql(u8, head, "effect")) {
            if (list.len != 4) {
                try diagnostics.append(.{ .line = item.line, .message = "effect expects name, request type, and response type" });
                return CompileError.ParseFailed;
            }
            const request_ty = parseType(try expectAtom(list[2])) orelse {
                try diagnostics.append(.{ .line = item.line, .message = "unknown effect request type" });
                return CompileError.ParseFailed;
            };
            const response_ty = parseType(try expectAtom(list[3])) orelse {
                try diagnostics.append(.{ .line = item.line, .message = "unknown effect response type" });
                return CompileError.ParseFailed;
            };
            try effects.append(arena, .{
                .name = try expectAtom(list[1]),
                .request_ty = request_ty,
                .response_ty = response_ty,
            });
        } else if (std.mem.eql(u8, head, "export")) {
            if (export_decl_opt != null) {
                try diagnostics.append(.{ .line = item.line, .message = "module may define only one export" });
                return CompileError.ParseFailed;
            }
            if (list.len != 6) {
                try diagnostics.append(.{ .line = item.line, .message = "export expects name, params, return type, handlers, and program" });
                return CompileError.ParseFailed;
            }
            const params_form = try expectList(list[2]);
            var params: std.ArrayList(Param) = .empty;
            for (params_form) |param_form| {
                const param_list = try expectList(param_form);
                if (param_list.len != 2) {
                    try diagnostics.append(.{ .line = param_form.line, .message = "parameter expects name and type" });
                    return CompileError.ParseFailed;
                }
                const param_ty = parseType(try expectAtom(param_list[1])) orelse {
                    try diagnostics.append(.{ .line = param_form.line, .message = "unknown parameter type" });
                    return CompileError.ParseFailed;
                };
                try params.append(arena, .{ .name = try expectAtom(param_list[0]), .value_type = param_ty });
            }
            const return_ty = parseType(try expectAtom(list[3])) orelse {
                try diagnostics.append(.{ .line = item.line, .message = "unknown export return type" });
                return CompileError.ParseFailed;
            };
            const handlers_form = try expectList(list[4]);
            if (handlers_form.len == 0 or !std.mem.eql(u8, try expectAtom(handlers_form[0]), "handlers")) {
                try diagnostics.append(.{ .line = list[4].line, .message = "expected (handlers ...)" });
                return CompileError.ParseFailed;
            }
            var handlers: std.ArrayList(Handler) = .empty;
            for (handlers_form[1..]) |handler_form| {
                const handler_list = try expectList(handler_form);
                if (handler_list.len < 4) {
                    try diagnostics.append(.{ .line = handler_form.line, .message = "handler expects effect name, request binder, resume binder, and body" });
                    return CompileError.ParseFailed;
                }
                var body: std.ArrayList(HandlerStmt) = .empty;
                for (handler_list[3..]) |body_form| try body.append(arena, try parseHandlerStmt(arena, diagnostics, body_form));
                try handlers.append(arena, .{
                    .effect_name = try expectAtom(handler_list[0]),
                    .request_name = try expectAtom(handler_list[1]),
                    .resume_name = try expectAtom(handler_list[2]),
                    .body = try body.toOwnedSlice(arena),
                    .line = handler_form.line,
                });
            }
            export_decl_opt = .{
                .name = try expectAtom(list[1]),
                .params = try params.toOwnedSlice(arena),
                .return_ty = return_ty,
                .handlers = try handlers.toOwnedSlice(arena),
                .program = try parseProgramBlock(arena, diagnostics, list[5]),
                .line = item.line,
            };
        } else {
            try diagnostics.append(.{ .line = item.line, .message = "unsupported module form" });
            return CompileError.ParseFailed;
        }
    }
    if (export_decl_opt == null) {
        try diagnostics.append(.{ .line = forms[0].line, .message = "module must define one export" });
        return CompileError.ParseFailed;
    }
    return .{
        .name = module_name,
        .effects = try effects.toOwnedSlice(arena),
        .export_decl = export_decl_opt.?,
    };
}

fn findEffect(module: Module, name: []const u8) ?EffectDecl {
    for (module.effects) |effect_decl| {
        if (std.mem.eql(u8, effect_decl.name, name)) return effect_decl;
    }
    return null;
}

fn findHandler(export_decl: ExportDecl, effect_name: []const u8) ?Handler {
    for (export_decl.handlers) |handler| {
        if (std.mem.eql(u8, handler.effect_name, effect_name)) return handler;
    }
    return null;
}

fn requireTypeEqual(diagnostics: *DiagnosticList, line: usize, expected: Type, actual: Type, message: []const u8) !void {
    if (expected != actual) {
        try diagnostics.append(.{ .line = line, .message = message });
        return CompileError.TypeFailed;
    }
}

const ProgramFlow = enum {
    continues,
    returns,
};

const TypecheckCtx = struct {
    module: Module,
    export_decl: ExportDecl,
    diagnostics: *DiagnosticList,

    fn exprType(self: *const TypecheckCtx, env: *const TypeEnv, expr: *const Expr, line: usize) anyerror!Type {
        return switch (expr.*) {
            .int_lit => .i32,
            .bool_lit => .bool,
            .string_lit => .string,
            .unit_lit => .unit,
            .ident => |name| env.get(name) orelse {
                try self.diagnostics.append(.{ .line = line, .message = "unknown identifier" });
                return CompileError.TypeFailed;
            },
            .add => |pair| blk: {
                try requireTypeEqual(self.diagnostics, line, .i32, try self.exprType(env, pair.lhs, line), "add lhs must be i32");
                try requireTypeEqual(self.diagnostics, line, .i32, try self.exprType(env, pair.rhs, line), "add rhs must be i32");
                break :blk .i32;
            },
            .perform => |call| blk: {
                const effect_decl = findEffect(self.module, call.effect_name) orelse {
                    try self.diagnostics.append(.{ .line = line, .message = "unknown effect in perform" });
                    return CompileError.TypeFailed;
                };
                _ = findHandler(self.export_decl, call.effect_name) orelse {
                    try self.diagnostics.append(.{ .line = line, .message = "unhandled effect at export boundary" });
                    return CompileError.TypeFailed;
                };
                try requireTypeEqual(self.diagnostics, line, effect_decl.request_ty, try self.exprType(env, call.request, line), "perform request type mismatch");
                break :blk effect_decl.response_ty;
            },
        };
    }

    fn programBlock(self: *const TypecheckCtx, env: *TypeEnv, block: []const ProgramStmt) anyerror!ProgramFlow {
        var flow: ProgramFlow = .continues;
        for (block, 0..) |stmt, idx| {
            if (flow == .returns) {
                const line = switch (stmt) {
                    .let_stmt => |value| value.line,
                    .return_stmt => |value| value.line,
                    .if_stmt => |value| value.line,
                };
                try self.diagnostics.append(.{ .line = line, .message = "statement after terminal return" });
                return CompileError.TypeFailed;
            }
            switch (stmt) {
                .let_stmt => |value| {
                    const value_type = try self.exprType(env, value.expr, value.line);
                    try env.put(value.name, value_type);
                },
                .return_stmt => |value| {
                    try requireTypeEqual(self.diagnostics, value.line, self.export_decl.return_ty, try self.exprType(env, value.expr, value.line), "return type mismatch");
                    flow = .returns;
                },
                .if_stmt => |value| {
                    try requireTypeEqual(self.diagnostics, value.line, .bool, try self.exprType(env, value.cond, value.line), "if condition must be bool");
                    if (idx != block.len - 1) {
                        try self.diagnostics.append(.{ .line = value.line, .message = "if must be terminal in program blocks" });
                        return CompileError.TypeFailed;
                    }
                    var then_env = TypeEnv.init(env.map.allocator);
                    defer then_env.deinit();
                    var then_iter = env.map.iterator();
                    while (then_iter.next()) |entry| try then_env.put(entry.key_ptr.*, entry.value_ptr.*);
                    var else_env = TypeEnv.init(env.map.allocator);
                    defer else_env.deinit();
                    var else_iter = env.map.iterator();
                    while (else_iter.next()) |entry| try else_env.put(entry.key_ptr.*, entry.value_ptr.*);
                    const then_flow = try self.programBlock(&then_env, value.then_block);
                    const else_flow = try self.programBlock(&else_env, value.else_block);
                    if (then_flow != .returns or else_flow != .returns) {
                        try self.diagnostics.append(.{ .line = value.line, .message = "both program branches must terminate" });
                        return CompileError.TypeFailed;
                    }
                    flow = .returns;
                },
            }
        }
        return flow;
    }

    fn handlerBlock(self: *const TypecheckCtx, effect_decl: EffectDecl, env: *TypeEnv, block: []const HandlerStmt) anyerror!HandlerActionTag {
        var action_opt: ?HandlerActionTag = null;
        for (block, 0..) |stmt, idx| {
            if (action_opt != null) {
                const line = switch (stmt) {
                    .let_stmt => |value| value.line,
                    .resume_stmt => |value| value.line,
                    .discard_stmt => |value| value.line,
                    .if_stmt => |value| value.line,
                };
                try self.diagnostics.append(.{ .line = line, .message = "linear use of resume must terminate the handler exactly once" });
                return CompileError.TypeFailed;
            }
            switch (stmt) {
                .let_stmt => |value| {
                    const value_type = try self.exprType(env, value.expr, value.line);
                    try env.put(value.name, value_type);
                },
                .resume_stmt => |value| {
                    try requireTypeEqual(self.diagnostics, value.line, effect_decl.response_ty, try self.exprType(env, value.expr, value.line), "resume value type mismatch");
                    action_opt = .@"resume";
                },
                .discard_stmt => |value| {
                    try requireTypeEqual(self.diagnostics, value.line, self.export_decl.return_ty, try self.exprType(env, value.expr, value.line), "discard value must match export return type");
                    action_opt = .discard;
                },
                .if_stmt => |value| {
                    try requireTypeEqual(self.diagnostics, value.line, .bool, try self.exprType(env, value.cond, value.line), "handler if condition must be bool");
                    if (idx != block.len - 1) {
                        try self.diagnostics.append(.{ .line = value.line, .message = "handler if must be terminal" });
                        return CompileError.TypeFailed;
                    }
                    var then_env = TypeEnv.init(env.map.allocator);
                    defer then_env.deinit();
                    var then_iter = env.map.iterator();
                    while (then_iter.next()) |entry| try then_env.put(entry.key_ptr.*, entry.value_ptr.*);
                    var else_env = TypeEnv.init(env.map.allocator);
                    defer else_env.deinit();
                    var else_iter = env.map.iterator();
                    while (else_iter.next()) |entry| try else_env.put(entry.key_ptr.*, entry.value_ptr.*);
                    const then_action = try self.handlerBlock(effect_decl, &then_env, value.then_block);
                    const else_action = try self.handlerBlock(effect_decl, &else_env, value.else_block);
                    if (then_action != else_action) {
                        try self.diagnostics.append(.{ .line = value.line, .message = "handler branches must agree on resume or discard" });
                        return CompileError.TypeFailed;
                    }
                    action_opt = then_action;
                },
            }
        }
        if (action_opt == null) {
            try self.diagnostics.append(.{ .line = effect_decl.name.len, .message = "handler must resume or discard exactly once" });
            return CompileError.TypeFailed;
        }
        return action_opt.?;
    }
};

fn typecheckModule(allocator: std.mem.Allocator, module: Module, diagnostics: *DiagnosticList) anyerror![]HandlerCertificate {
    var env = TypeEnv.init(allocator);
    defer env.deinit();
    const ctx = TypecheckCtx{
        .module = module,
        .export_decl = module.export_decl,
        .diagnostics = diagnostics,
    };
    for (module.export_decl.params) |param| try env.put(param.name, param.value_type);
    const program_flow = try ctx.programBlock(&env, module.export_decl.program);
    if (program_flow != .returns) {
        try diagnostics.append(.{ .line = module.export_decl.line, .message = "export program must return on every path" });
        return CompileError.TypeFailed;
    }
    var certificates: std.ArrayList(HandlerCertificate) = .empty;
    errdefer certificates.deinit(allocator);
    for (module.export_decl.handlers) |handler| {
        const effect_decl = findEffect(module, handler.effect_name) orelse {
            try diagnostics.append(.{ .line = handler.line, .message = "handler references unknown effect" });
            return CompileError.TypeFailed;
        };
        var handler_env = TypeEnv.init(allocator);
        defer handler_env.deinit();
        for (module.export_decl.params) |param| try handler_env.put(param.name, param.value_type);
        try handler_env.put(handler.request_name, effect_decl.request_ty);
        const action = try ctx.handlerBlock(effect_decl, &handler_env, handler.body);
        try certificates.append(allocator, .{ .effect_name = handler.effect_name, .action = action, .line = handler.line });
    }
    return certificates.toOwnedSlice(allocator);
}

const SourceMapEntry = struct {
    dsl_line: usize,
    generated_line: usize,
    kind: []const u8,
};

const CodeWriter = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    line: usize = 1,
    maps: std.ArrayList(SourceMapEntry),

    fn init(allocator: std.mem.Allocator) CodeWriter {
        return .{
            .allocator = allocator,
            .buffer = .empty,
            .maps = .empty,
        };
    }

    fn deinit(self: *CodeWriter) void {
        self.buffer.deinit(self.allocator);
        self.maps.deinit(self.allocator);
    }

    fn emitLine(self: *CodeWriter, dsl_line: ?usize, kind: []const u8, comptime fmt: []const u8, args: anytype) !void {
        if (dsl_line) |line| try self.maps.append(self.allocator, .{ .dsl_line = line, .generated_line = self.line, .kind = kind });
        try self.buffer.print(self.allocator, fmt, args);
        try self.buffer.append(self.allocator, '\n');
        self.line += 1;
    }
};

fn emitProgramExpr(writer: *CodeWriter, expr: *const Expr) !void {
    switch (expr.*) {
        .int_lit => |value| try writer.buffer.print(writer.allocator, "{d}", .{value}),
        .bool_lit => |value| try writer.buffer.appendSlice(writer.allocator, if (value) "true" else "false"),
        .string_lit => |value| try writer.buffer.print(writer.allocator, "\"{s}\"", .{value}),
        .unit_lit => try writer.buffer.appendSlice(writer.allocator, "{}"),
        .ident => |name| try writer.buffer.appendSlice(writer.allocator, name),
        .add => |pair| {
            try writer.buffer.appendSlice(writer.allocator, "(");
            try emitProgramExpr(writer, pair.lhs);
            try writer.buffer.appendSlice(writer.allocator, " + ");
            try emitProgramExpr(writer, pair.rhs);
            try writer.buffer.appendSlice(writer.allocator, ")");
        },
        .perform => unreachable,
    }
}

fn exprUsesIdent(expr: *const Expr, needle: []const u8) bool {
    return switch (expr.*) {
        .int_lit, .bool_lit, .string_lit, .unit_lit => false,
        .ident => |name| std.mem.eql(u8, name, needle),
        .add => |pair| exprUsesIdent(pair.lhs, needle) or exprUsesIdent(pair.rhs, needle),
        .perform => |call| exprUsesIdent(call.request, needle),
    };
}

fn handlerBlockUsesIdent(block: []const HandlerStmt, needle: []const u8) bool {
    for (block) |stmt| switch (stmt) {
        .let_stmt => |value| if (exprUsesIdent(value.expr, needle)) return true,
        .resume_stmt => |value| if (exprUsesIdent(value.expr, needle)) return true,
        .discard_stmt => |value| if (exprUsesIdent(value.expr, needle)) return true,
        .if_stmt => |value| {
            if (exprUsesIdent(value.cond, needle)) return true;
            if (handlerBlockUsesIdent(value.then_block, needle)) return true;
            if (handlerBlockUsesIdent(value.else_block, needle)) return true;
        },
    };
    return false;
}

fn emitIndented(writer: *CodeWriter, indent: usize, dsl_line: ?usize, kind: []const u8, comptime fmt: []const u8, args: anytype) !void {
    const spaces = indent * 4;
    var padding: std.ArrayList(u8) = .empty;
    defer padding.deinit(writer.allocator);
    try padding.resize(writer.allocator, spaces);
    @memset(padding.items, ' ');
    if (dsl_line) |line| try writer.maps.append(writer.allocator, .{ .dsl_line = line, .generated_line = writer.line, .kind = kind });
    try writer.buffer.appendSlice(writer.allocator, padding.items);
    try writer.buffer.print(writer.allocator, fmt, args);
    try writer.buffer.append(writer.allocator, '\n');
    writer.line += 1;
}

fn emitHandlerExpr(writer: *CodeWriter, expr: *const Expr) !void {
    try emitProgramExpr(writer, expr);
}

fn emitProgramBlock(writer: *CodeWriter, block: []const ProgramStmt, indent: usize) !void {
    for (block) |stmt| switch (stmt) {
        .let_stmt => |value| switch (value.expr.*) {
            .perform => |call| {
                const handler_suffix = try upperCamelName(writer.allocator, call.effect_name);
                defer writer.allocator.free(handler_suffix);
                try emitIndented(writer, indent, value.line, "perform", "const __{s}_action = handle{s}(", .{ value.name, handler_suffix });
                try emitProgramExpr(writer, call.request);
                try writer.buffer.appendSlice(writer.allocator, ");\n");
                writer.line += 1;
                if (std.mem.eql(u8, value.name, "_")) {
                    try emitIndented(writer, indent, value.line, "perform-switch", "switch (____action) {{", .{});
                    try emitIndented(writer, indent + 1, value.line, "perform-continue", ".@\"continue\" => {{}},", .{});
                    try emitIndented(writer, indent + 1, value.line, "perform-discard", ".discard => |answer| return answer,", .{});
                    try emitIndented(writer, indent, value.line, "perform-switch-end", "}}", .{});
                } else {
                    try emitIndented(writer, indent, value.line, "perform-switch", "const {s} = switch (__{s}_action) {{", .{ value.name, value.name });
                    try emitIndented(writer, indent + 1, value.line, "perform-continue", ".@\"continue\" => |value| value,", .{});
                    try emitIndented(writer, indent + 1, value.line, "perform-discard", ".discard => |answer| return answer,", .{});
                    try emitIndented(writer, indent, value.line, "perform-switch-end", "}};", .{});
                }
            },
            else => {
                var scratch = CodeWriter.init(writer.allocator);
                defer scratch.deinit();
                try emitProgramExpr(&scratch, value.expr);
                if (std.mem.eql(u8, value.name, "_")) {
                    try emitIndented(writer, indent, value.line, "let", "_ = {s};", .{scratch.buffer.items});
                } else {
                    try emitIndented(writer, indent, value.line, "let", "const {s} = {s};", .{ value.name, scratch.buffer.items });
                }
            },
        },
        .return_stmt => |value| {
            var scratch = CodeWriter.init(writer.allocator);
            defer scratch.deinit();
            try emitProgramExpr(&scratch, value.expr);
            try emitIndented(writer, indent, value.line, "return", "return {s};", .{scratch.buffer.items});
        },
        .if_stmt => |value| {
            var cond = CodeWriter.init(writer.allocator);
            defer cond.deinit();
            try emitProgramExpr(&cond, value.cond);
            try emitIndented(writer, indent, value.line, "if", "if ({s}) {{", .{cond.buffer.items});
            try emitProgramBlock(writer, value.then_block, indent + 1);
            try emitIndented(writer, indent, value.line, "else", "}} else {{", .{});
            try emitProgramBlock(writer, value.else_block, indent + 1);
            try emitIndented(writer, indent, value.line, "ifend", "}}", .{});
        },
    };
}

fn emitHandlerBlock(writer: *CodeWriter, block: []const HandlerStmt, indent: usize) !void {
    for (block) |stmt| switch (stmt) {
        .let_stmt => |value| {
            var scratch = CodeWriter.init(writer.allocator);
            defer scratch.deinit();
            try emitHandlerExpr(&scratch, value.expr);
            try emitIndented(writer, indent, value.line, "handler-let", "const {s} = {s};", .{ value.name, scratch.buffer.items });
        },
        .resume_stmt => |value| {
            var scratch = CodeWriter.init(writer.allocator);
            defer scratch.deinit();
            try emitHandlerExpr(&scratch, value.expr);
            try emitIndented(writer, indent, value.line, "handler-resume", "return .{{ .@\"continue\" = {s} }};", .{scratch.buffer.items});
        },
        .discard_stmt => |value| {
            var scratch = CodeWriter.init(writer.allocator);
            defer scratch.deinit();
            try emitHandlerExpr(&scratch, value.expr);
            try emitIndented(writer, indent, value.line, "handler-discard", "return .{{ .discard = {s} }};", .{scratch.buffer.items});
        },
        .if_stmt => |value| {
            var cond = CodeWriter.init(writer.allocator);
            defer cond.deinit();
            try emitHandlerExpr(&cond, value.cond);
            try emitIndented(writer, indent, value.line, "handler-if", "if ({s}) {{", .{cond.buffer.items});
            try emitHandlerBlock(writer, value.then_block, indent + 1);
            try emitIndented(writer, indent, value.line, "handler-else", "}} else {{", .{});
            try emitHandlerBlock(writer, value.else_block, indent + 1);
            try emitIndented(writer, indent, value.line, "handler-ifend", "}}", .{});
        },
    };
}

fn emitSourceMap(allocator: std.mem.Allocator, entries: []const SourceMapEntry) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "{\"mappings\":[");
    for (entries, 0..) |entry, idx| {
        if (idx != 0) try out.appendSlice(allocator, ",");
        try out.print(allocator, "{{\"dsl_line\":{d},\"generated_line\":{d},\"kind\":\"{s}\"}}", .{ entry.dsl_line, entry.generated_line, entry.kind });
    }
    try out.appendSlice(allocator, "]}");
    return out.toOwnedSlice(allocator);
}

fn emitCertificate(allocator: std.mem.Allocator, module_name: []const u8, certs: []const HandlerCertificate) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.print(allocator, "{{\"module\":\"{s}\",\"handlers\":[", .{module_name});
    for (certs, 0..) |cert, idx| {
        if (idx != 0) try out.appendSlice(allocator, ",");
        try out.print(allocator, "{{\"effect\":\"{s}\",\"action\":\"{s}\",\"line\":{d}}}", .{
            cert.effect_name,
            switch (cert.action) {
                .@"resume" => "resume",
                .discard => "discard",
            },
            cert.line,
        });
    }
    try out.appendSlice(allocator, "]}");
    return out.toOwnedSlice(allocator);
}

fn emitZig(allocator: std.mem.Allocator, module: Module, certs: []const HandlerCertificate) !Artifact {
    var writer = CodeWriter.init(allocator);
    defer writer.deinit();

    try writer.emitLine(null, "header", "// Generated by shiftc. Do not edit by hand.", .{});
    try writer.emitLine(null, "header", "", .{});

    const export_decl = module.export_decl;
    for (export_decl.handlers) |handler| {
        const effect_decl = findEffect(module, handler.effect_name).?;
        const handler_suffix = try upperCamelName(allocator, handler.effect_name);
        defer allocator.free(handler_suffix);
        try writer.emitLine(@as(?usize, handler.line), "action-type", "const __{s}_action = union(enum) {{", .{handler.effect_name});
        try emitIndented(&writer, 1, handler.line, "action-continue", "@\"continue\": {s},", .{effect_decl.response_ty.zigName()});
        try emitIndented(&writer, 1, handler.line, "action-discard", "discard: {s},", .{export_decl.return_ty.zigName()});
        try writer.emitLine(@as(?usize, handler.line), "action-end", "}};", .{});
        try writer.emitLine(null, "spacing", "", .{});

        try writer.emitLine(@as(?usize, handler.line), "handler-fn", "fn handle{s}(request: {s}) __{s}_action {{", .{
            handler_suffix,
            effect_decl.request_ty.zigName(),
            handler.effect_name,
        });
        if (!handlerBlockUsesIdent(handler.body, handler.request_name)) {
            try emitIndented(&writer, 1, handler.line, "handler-request-mark", "_ = request;", .{});
        }
        try emitHandlerBlock(&writer, handler.body, 1);
        try writer.emitLine(@as(?usize, handler.line), "handler-end", "}}", .{});
        try writer.emitLine(null, "spacing", "", .{});
    }

    var params_buf: std.ArrayList(u8) = .empty;
    defer params_buf.deinit(allocator);
    for (export_decl.params, 0..) |param, idx| {
        if (idx != 0) try params_buf.appendSlice(allocator, ", ");
        try params_buf.print(allocator, "{s}: {s}", .{ param.name, param.value_type.zigName() });
    }

    try writer.emitLine(@as(?usize, export_decl.line), "export-fn", "pub fn {s}({s}) {s} {{", .{
        export_decl.name,
        params_buf.items,
        export_decl.return_ty.zigName(),
    });
    try emitProgramBlock(&writer, export_decl.program, 1);
    try writer.emitLine(@as(?usize, export_decl.line), "export-end", "}}", .{});

    return .{
        .zig = try allocator.dupe(u8, writer.buffer.items),
        .source_map_json = try emitSourceMap(allocator, writer.maps.items),
        .certificate_json = try emitCertificate(allocator, module.name, certs),
    };
}

pub fn compileSource(allocator: std.mem.Allocator, source_path: []const u8, source: []const u8, diagnostics: *DiagnosticList) anyerror!Artifact {
    _ = source_path;
    var arena_instance = std.heap.ArenaAllocator.init(allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const tokens = try tokenize(arena, source);
    var ctx = ParseCtx{
        .arena = arena,
        .tokens = tokens,
        .diagnostics = diagnostics,
    };

    var forms: std.ArrayList(Form) = .empty;
    errdefer forms.deinit(arena);
    while (!ctx.eof()) try forms.append(arena, try ctx.parseForm());
    const module = try parseModule(arena, diagnostics, try forms.toOwnedSlice(arena));
    const certificates = try typecheckModule(allocator, module, diagnostics);
    defer allocator.free(certificates);
    return emitZig(allocator, module, certificates);
}
