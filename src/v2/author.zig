// Copyright (c) 2026 Boundary contributors. MIT license.
//! Checked, forward source authoring. All executable meaning is emitted as
//! ordinary source terms and remains subject to source and target admission.
const std = @import("std");
const source = @import("source.zig");
const p = @import("boundary_data").program;

pub const Error = source.Error || error{
    WrongBuilder,
    OutOfScope,
    ClosedBody,
    SchemaMismatch,
    InvalidOperation,
    Poisoned,
};

pub const Category = enum {
    wrong_builder,
    out_of_scope,
    closed_body,
    schema_mismatch,
    invalid_operation,
};

/// Authoring diagnostics remain valid until the underlying source Builder dies.
pub const Diagnostic = struct {
    category: Category,
    entity: []const u8,
    expected_schema: ?p.Id = null,
    actual_schema: ?p.Id = null,

    pub fn message(self: Diagnostic) []const u8 {
        return switch (self.category) {
            .wrong_builder => "handle belongs to another authoring builder",
            .out_of_scope => "value is not visible in this lexical body",
            .closed_body => "authoring body has already been finalized",
            .schema_mismatch => "authored schemas do not match",
            .invalid_operation => "operation is not available at this boundary",
        };
    }
};

const Token = struct { alive: bool = true, poisoned: bool = false };
const Scope = struct { parent: ?*Scope, open: bool = true };
const Step = struct { variable: p.Id, term: p.Id };

pub const Schema = struct { token: *Token, id: p.Id };
pub const Operation = struct {
    token: *Token,
    id: p.Id,
    payload: Schema,
    result: Schema,
    boundary: enum { external, local },
};
pub const NamedParameter = struct { name: []const u8, schema: Schema };
pub const Function = struct {
    token: *Token,
    id: p.Id,
    parameters: []const NamedParameter,
    result: Schema,
};
pub const Value = struct {
    token: *Token,
    id: p.Id,
    schema: Schema,
    scope: ?*Scope,
};
pub const Computation = struct {
    token: *Token,
    id: p.Id,
    result: Schema,
    scope: *Scope,
};

/// A Session is scoped to a live source Builder. Its token is arena-owned so
/// closing a session cannot accidentally make an old handle denote a new one.
pub const Session = struct {
    raw: *source.Builder,
    token: *Token,
    diagnostic: ?Diagnostic = null,

    pub fn init(raw: *source.Builder) Error!Session {
        const token = try raw.allocator().create(Token);
        token.* = .{};
        return .{ .raw = raw, .token = token };
    }
    pub fn deinit(self: *Session) void {
        self.token.alive = false;
    }
    fn report(self: *Session, category: Category, entity: []const u8, expected: ?p.Id, actual: ?p.Id) void {
        self.diagnostic = .{ .category = category, .entity = entity, .expected_schema = expected, .actual_schema = actual };
    }
    fn check(self: *Session, token: *Token, entity: []const u8) Error!void {
        if (token != self.token) {
            self.report(.wrong_builder, entity, null, null);
            return error.WrongBuilder;
        }
        if (!self.token.alive or self.token.poisoned) return error.Poisoned;
    }
    fn checkSchema(self: *Session, schema: Schema) Error!void {
        try self.check(schema.token, "schema");
        if (schema.id >= self.raw.schemas.items.len) return error.InvalidSchema;
    }
    pub fn scalar(self: *Session, comptime T: type) Error!Schema {
        return .{ .token = self.token, .id = try self.raw.scalar(T) };
    }
    pub fn dynamicSchema(self: *Session, shape: p.Schema) Error!Schema {
        return .{ .token = self.token, .id = try self.raw.schema(shape) };
    }
    pub fn external(self: *Session, name: []const u8, payload: Schema, result: Schema) Error!Operation {
        try self.checkSchema(payload);
        try self.checkSchema(result);
        const id = try self.raw.effect(.{ .identity = name, .payload = payload.id, .result = result.id });
        return .{ .token = self.token, .id = id, .payload = payload, .result = result, .boundary = .external };
    }
    pub fn local(self: *Session, name: []const u8, payload: Schema, result: Schema, use: p.Use) Error!Operation {
        try self.checkSchema(payload);
        try self.checkSchema(result);
        const id = try self.raw.effect(.{ .identity = name, .payload = payload.id, .result = result.id, .control_use = use, .external = false });
        return .{ .token = self.token, .id = id, .payload = payload, .result = result, .boundary = .local };
    }
    pub fn declare(self: *Session, parameters: []const NamedParameter, result: Schema, effects: []const Operation) Error!Function {
        try self.checkSchema(result);
        const a = self.raw.allocator();
        const names = try a.dupe(NamedParameter, parameters);
        const schemas = try a.alloc(p.Id, parameters.len);
        const row = try a.alloc(p.Id, effects.len);
        for (parameters, schemas) |parameter, *id| {
            try self.checkSchema(parameter.schema);
            id.* = parameter.schema.id;
        }
        for (effects, row) |effect, *id| {
            try self.check(effect.token, "effect");
            id.* = effect.id;
        }
        return .{ .token = self.token, .id = try self.raw.declare(schemas, result.id, row, &.{}), .parameters = names, .result = result };
    }
    pub fn body(self: *Session, function: Function) Error!Body {
        try self.check(function.token, "function");
        const scope = try self.raw.allocator().create(Scope);
        scope.* = .{ .parent = null };
        return .{ .session = self, .scope = scope, .function = function };
    }
    pub fn module(self: *Session, entry: Function, failure: Schema) Error!source.Module {
        try self.check(entry.token, "entry function");
        try self.checkSchema(failure);
        if (self.token.poisoned) return error.Poisoned;
        return self.raw.module(entry.id, failure.id);
    }
};

fn visible(introduction: ?*Scope, current: *Scope) bool {
    const origin = introduction orelse return true;
    var cursor: ?*Scope = current;
    while (cursor) |scope| : (cursor = scope.parent) if (scope == origin) return true;
    return false;
}

/// Statements are authored in execution order and folded into source binds
/// when the body is finished. Child bodies are lexical, not host execution.
pub const Body = struct {
    session: *Session,
    scope: *Scope,
    function: ?Function = null,
    steps: std.ArrayList(Step) = .empty,

    fn active(self: *Body) Error!void {
        if (!self.scope.open) {
            self.session.report(.closed_body, "body", null, null);
            return error.ClosedBody;
        }
        if (self.session.token.poisoned) return error.Poisoned;
    }
    fn value(self: *Body, item: Value) Error!void {
        try self.active();
        try self.session.check(item.token, "value");
        if (!visible(item.scope, self.scope)) {
            self.session.report(.out_of_scope, "value", null, null);
            return error.OutOfScope;
        }
    }
    pub fn parameter(self: *Body, name: []const u8) Error!Value {
        try self.active();
        const function = self.function orelse return error.InvalidReference;
        for (function.parameters, 0..) |named, index| {
            if (!std.mem.eql(u8, named.name, name)) continue;
            return .{ .token = self.session.token, .id = try self.session.raw.reference(self.session.raw.parameter(function.id, index)), .schema = named.schema, .scope = self.scope };
        }
        return error.InvalidReference;
    }
    pub fn constant(self: *Body, comptime T: type, item: T) Error!Value {
        try self.active();
        return .{ .token = self.session.token, .id = try self.session.raw.constant(T, item), .schema = try self.session.scalar(T), .scope = null };
    }
    pub fn perform(self: *Body, operation: Operation, payload: Value) Error!Computation {
        try self.value(payload);
        try self.session.check(operation.token, "operation");
        if (operation.boundary != .external) {
            self.session.report(.invalid_operation, "local operation requires a capability", null, null);
            return error.InvalidOperation;
        }
        if (payload.schema.id != operation.payload.id) {
            self.session.report(.schema_mismatch, "operation payload", operation.payload.id, payload.schema.id);
            return error.SchemaMismatch;
        }
        const id = try self.session.raw.term(.{ .perform = .{ .effect = operation.id, .payload = payload.id } });
        return .{ .token = self.session.token, .id = id, .result = operation.result, .scope = self.scope };
    }
    pub fn bind(self: *Body, computation: Computation) Error!Value {
        try self.active();
        try self.session.check(computation.token, "computation");
        if (!visible(computation.scope, self.scope)) {
            self.session.report(.out_of_scope, "computation", null, null);
            return error.OutOfScope;
        }
        const variable = try self.session.raw.variable(computation.result.id);
        const reference = try self.session.raw.reference(variable);
        self.steps.append(self.session.raw.allocator(), .{ .variable = variable, .term = computation.id }) catch |err| {
            self.session.token.poisoned = true;
            return err;
        };
        return .{ .token = self.session.token, .id = reference, .schema = computation.result, .scope = self.scope };
    }
    pub fn child(self: *Body) Error!Body {
        try self.active();
        const scope = try self.session.raw.allocator().create(Scope);
        scope.* = .{ .parent = self.scope };
        return .{ .session = self.session, .scope = scope };
    }
    pub fn conditional(self: *Body, condition: Value, when_true: Computation, when_false: Computation) Error!Computation {
        try self.value(condition);
        try self.session.check(when_true.token, "true branch");
        try self.session.check(when_false.token, "false branch");
        const boolean = try self.session.scalar(bool);
        if (condition.schema.id != boolean.id or when_true.result.id != when_false.result.id) {
            self.session.report(.schema_mismatch, "conditional branches", when_true.result.id, when_false.result.id);
            return error.SchemaMismatch;
        }
        if (when_true.scope.parent != self.scope or when_false.scope.parent != self.scope or when_true.scope.open or when_false.scope.open) {
            self.session.report(.out_of_scope, "conditional branch", null, null);
            return error.OutOfScope;
        }
        const id = try self.session.raw.term(.{ .conditional = .{ .condition = condition.id, .when_true = when_true.id, .when_false = when_false.id } });
        return .{ .token = self.session.token, .id = id, .result = when_true.result, .scope = self.scope };
    }
    pub fn finish(self: *Body, result: Value) Error!Computation {
        try self.value(result);
        var term = try self.session.raw.pure(result.id);
        for (self.steps.items, 0..) |_, index| {
            const step = self.steps.items[self.steps.items.len - 1 - index];
            term = try self.session.raw.bind(step.variable, step.term, term);
        }
        self.scope.open = false;
        return .{ .token = self.session.token, .id = term, .result = result.schema, .scope = self.scope };
    }
    pub fn finishFunction(self: *Body, result: Value) Error!void {
        const function = self.function orelse return error.InvalidReference;
        if (result.schema.id != function.result.id) {
            self.session.report(.schema_mismatch, "function result", function.result.id, result.schema.id);
            return error.SchemaMismatch;
        }
        const completed = try self.finish(result);
        try self.session.raw.define(function.id, completed.id);
    }
};
