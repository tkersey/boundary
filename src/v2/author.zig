// Copyright (c) 2026 Boundary contributors. MIT license.
//! Checked, forward source authoring. All executable meaning is emitted as
//! ordinary source terms and remains subject to source and target admission.
const std = @import("std");
const source = @import("source.zig");
const p = @import("boundary_data").program;

pub const Error = source.Error;

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
    capability: ?Schema = null,
};
pub const Region = struct { token: *Token, id: p.Id };
pub const HandlerOptions = struct {
    mode: p.Mode,
    input: Schema,
    answer: Schema,
    state: []const NamedParameter = &.{},
    residual: []const Operation = &.{},
    resumption_use: p.Use,
    capture_bound: []const Schema,
    owned_regions: []const Region = &.{},
    borrowed_regions: []const Region = &.{},
    obligations: bool = false,
};
pub const Handler = struct {
    token: *Token,
    id: p.Id,
    operation: Operation,
    input: Schema,
    answer: Schema,
    state: []const NamedParameter,
    residual: []const Operation,
    on_return: Function,
    on_operation: Function,
    resumption: Schema,
};
pub const NamedParameter = struct { name: []const u8, schema: Schema };
pub const Record = struct { schema: Schema, fields: []const NamedParameter };
pub const NamedValue = struct { name: []const u8, value: Value };
pub const Function = struct {
    token: *Token,
    id: p.Id,
    parameters: []const NamedParameter,
    result: Schema,
    home: ?*Scope = null,
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
    pub fn record(self: *Session, fields: []const NamedParameter) Error!Record {
        const a = self.raw.allocator();
        const names = try a.dupe(NamedParameter, fields);
        const schemas = try a.alloc(p.Id, fields.len);
        for (fields, schemas, 0..) |field, *id, index| {
            try self.checkSchema(field.schema);
            for (fields[0..index]) |prior| if (std.mem.eql(u8, prior.name, field.name)) return error.InvalidSource;
            id.* = field.schema.id;
        }
        return .{ .schema = try self.dynamicSchema(.{ .product = schemas }), .fields = names };
    }
    pub fn sequence(self: *Session, element: Schema) Error!Schema {
        try self.checkSchema(element);
        return self.dynamicSchema(.{ .seq = element.id });
    }
    /// Advanced interoperation. Raw IDs have no recoverable builder provenance;
    /// callers must supply only IDs produced by this Session's source Builder.
    pub fn legacy(self: *Session) Legacy {
        return .{ .session = self };
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
        const capability = try self.raw.schema(.{ .internal = .{ .capability = id } });
        return .{ .token = self.token, .id = id, .payload = payload, .result = result, .boundary = .local, .capability = .{ .token = self.token, .id = capability } };
    }
    pub fn region(self: *Session) Region {
        return .{ .token = self.token, .id = self.raw.region() };
    }
    pub fn interpret(self: *Session, operation: Operation, options: HandlerOptions) Error!Handler {
        errdefer self.token.poisoned = true;
        try self.check(operation.token, "operation");
        if (operation.boundary != .local) return error.InvalidOperation;
        try self.checkSchema(options.input);
        try self.checkSchema(options.answer);
        const a = self.raw.allocator();
        const state = try a.dupe(NamedParameter, options.state);
        const residual = try a.dupe(Operation, options.residual);
        const residual_ids = try a.alloc(p.Id, residual.len);
        const state_ids = try a.alloc(p.Id, state.len);
        const captures = try a.alloc(p.Id, options.capture_bound.len);
        const owned = try a.alloc(p.Id, options.owned_regions.len);
        const borrowed = try a.alloc(p.Id, options.borrowed_regions.len);
        for (state, state_ids) |item, *id| {
            try self.checkSchema(item.schema);
            id.* = item.schema.id;
        }
        for (residual, residual_ids) |item, *id| {
            try self.check(item.token, "residual effect");
            id.* = item.id;
        }
        for (options.capture_bound, captures) |item, *id| {
            try self.checkSchema(item);
            id.* = item.id;
        }
        for (options.owned_regions, owned) |item, *id| {
            try self.check(item.token, "owned region");
            id.* = item.id;
        }
        for (options.borrowed_regions, borrowed) |item, *id| {
            try self.check(item.token, "borrowed region");
            id.* = item.id;
        }
        const resume_id = try self.raw.schema(.{ .internal = .{ .resumption = .{
            .effect = operation.id,
            .input = operation.result.id,
            .answer = options.answer.id,
            .effects = residual_ids,
            .capture_bound = captures,
            .handled = &.{operation.id},
            .mode = options.mode,
            .use = options.resumption_use,
            .owned_regions = owned,
            .obligations = options.obligations,
        } } });
        const resume_schema = Schema{ .token = self.token, .id = resume_id };
        const return_parameters = try a.alloc(NamedParameter, state.len + 1);
        @memcpy(return_parameters[0..state.len], state);
        return_parameters[state.len] = .{ .name = "body_result", .schema = options.input };
        const clause_parameters = try a.alloc(NamedParameter, state.len + 2);
        @memcpy(clause_parameters[0..state.len], state);
        clause_parameters[state.len] = .{ .name = "payload", .schema = operation.payload };
        clause_parameters[state.len + 1] = .{ .name = "resume", .schema = resume_schema };
        const returns = try self.declareWithRegions(return_parameters, options.answer, &.{}, borrowed);
        const clause = try self.declareWithRegions(clause_parameters, options.answer, residual, borrowed);
        const id = try self.raw.handler(.{
            .mode = options.mode,
            .input = options.input.id,
            .answer = options.answer.id,
            .return_function = returns.id,
            .clauses = &.{.{ .effect = operation.id, .function = clause.id, .resumption = resume_id }},
            .state = state_ids,
            .effects = residual_ids,
        });
        return .{ .token = self.token, .id = id, .operation = operation, .input = options.input, .answer = options.answer, .state = state, .residual = residual, .on_return = returns, .on_operation = clause, .resumption = resume_schema };
    }
    pub fn declare(self: *Session, parameters: []const NamedParameter, result: Schema, effects: []const Operation) Error!Function {
        return self.declareWithRegions(parameters, result, effects, &.{});
    }
    fn declareWithRegions(self: *Session, parameters: []const NamedParameter, result: Schema, effects: []const Operation, regions: []const p.Id) Error!Function {
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
        return .{ .token = self.token, .id = try self.raw.declare(schemas, result.id, row, regions), .parameters = names, .result = result };
    }
    pub fn body(self: *Session, function: Function) Error!Body {
        try self.check(function.token, "function");
        if (function.home) |parent| if (!parent.open) return error.ClosedBody;
        const scope = try self.raw.allocator().create(Scope);
        scope.* = .{ .parent = function.home };
        return .{ .session = self, .scope = scope, .function = function };
    }
    pub fn module(self: *Session, entry: Function, failure: Schema) Error!source.Module {
        try self.check(entry.token, "entry function");
        try self.checkSchema(failure);
        if (self.token.poisoned) return error.Poisoned;
        return self.raw.module(entry.id, failure.id);
    }
};

pub const Legacy = struct {
    session: *Session,
    pub fn schema(self: Legacy, id: p.Id) Error!Schema {
        if (id >= self.session.raw.schemas.items.len) return error.InvalidSchema;
        return .{ .token = self.session.token, .id = id };
    }
    pub fn region(self: Legacy, id: p.Id) Error!Region {
        if (id >= self.session.raw.region_count) return error.InvalidReference;
        return .{ .token = self.session.token, .id = id };
    }
    pub fn operation(self: Legacy, id: p.Id) Error!Operation {
        if (id >= self.session.raw.effects.items.len) return error.InvalidReference;
        const effect = self.session.raw.effects.items[@intCast(id)];
        const capability: ?Schema = if (effect.external) null else .{ .token = self.session.token, .id = try self.session.raw.schema(.{ .internal = .{ .capability = id } }) };
        return .{
            .token = self.session.token,
            .id = id,
            .payload = try self.schema(effect.payload),
            .result = try self.schema(effect.result),
            .boundary = if (effect.external) .external else .local,
            .capability = capability,
        };
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
    pub fn performLocal(self: *Body, operation: Operation, capability: Value, payload: Value) Error!Computation {
        try self.value(capability);
        try self.value(payload);
        try self.session.check(operation.token, "operation");
        const expected = operation.capability orelse return error.InvalidOperation;
        if (operation.boundary != .local or capability.schema.id != expected.id) {
            self.session.report(.invalid_operation, "capability instance", expected.id, capability.schema.id);
            return error.InvalidOperation;
        }
        if (payload.schema.id != operation.payload.id) {
            self.session.report(.schema_mismatch, "operation payload", operation.payload.id, payload.schema.id);
            return error.SchemaMismatch;
        }
        const term = try self.session.raw.term(.{ .perform = .{ .effect = operation.id, .capability = capability.id, .payload = payload.id } });
        return .{ .token = self.session.token, .id = term, .result = operation.result, .scope = self.scope };
    }
    pub fn resumeValue(self: *Body, resumption: Value, argument: Value) Error!Computation {
        try self.value(resumption);
        try self.value(argument);
        const shape = self.session.raw.schemas.items[@intCast(resumption.schema.id)];
        if (shape != .internal or shape.internal != .resumption) return error.TypeMismatch;
        const contract = shape.internal.resumption;
        if (argument.schema.id != contract.input) {
            self.session.report(.schema_mismatch, "resumption input", contract.input, argument.schema.id);
            return error.SchemaMismatch;
        }
        const term = try self.session.raw.term(.{ .resume_value = .{ .resumption = resumption.id, .argument = argument.id } });
        return .{ .token = self.session.token, .id = term, .result = try self.session.legacy().schema(contract.answer), .scope = self.scope };
    }
    pub fn handle(self: *Body, handler: Handler, body: Value, arguments: []const Value, state: []const Value) Error!Computation {
        try self.value(body);
        try self.session.check(handler.token, "handler");
        const shape = self.session.raw.schemas.items[@intCast(body.schema.id)];
        if (shape != .internal or shape.internal != .computation) return error.TypeMismatch;
        const signature = shape.internal.computation;
        if (signature.result != handler.input.id or signature.parameters.len != arguments.len + 1 or handler.state.len != state.len) {
            self.session.report(.schema_mismatch, "handled body", handler.input.id, signature.result);
            return error.SchemaMismatch;
        }
        if (signature.parameters[0] != handler.operation.capability.?.id) {
            self.session.report(.invalid_operation, "handled capability instance", handler.operation.capability.?.id, signature.parameters[0]);
            return error.InvalidOperation;
        }
        for (signature.effects) |effect| {
            if (effect == handler.operation.id) continue;
            var allowed = false;
            for (handler.residual) |residual| if (residual.id == effect) {
                allowed = true;
                break;
            };
            if (!allowed) {
                self.session.report(.invalid_operation, "disallowed residual effect", null, null);
                return error.InvalidOperation;
            }
        }
        const args = try self.session.raw.allocator().alloc(p.Id, arguments.len);
        const states = try self.session.raw.allocator().alloc(p.Id, state.len);
        for (arguments, signature.parameters[1..], args) |item, expected, *id| {
            try self.value(item);
            if (item.schema.id != expected) return error.SchemaMismatch;
            id.* = item.id;
        }
        for (state, handler.state, states) |item, expected, *id| {
            try self.value(item);
            if (item.schema.id != expected.schema.id) return error.SchemaMismatch;
            id.* = item.id;
        }
        const term = try self.session.raw.term(.{ .handle = .{ .handler = handler.id, .body = body.id, .arguments = args, .state = states } });
        return .{ .token = self.session.token, .id = term, .result = handler.answer, .scope = self.scope };
    }
    pub fn singleton(self: *Body, sequence_schema: Schema, item: Value) Error!Value {
        try self.value(item);
        try self.session.checkSchema(sequence_schema);
        const shape = self.session.raw.schemas.items[@intCast(sequence_schema.id)];
        if (shape != .seq or shape.seq != item.schema.id) return error.SchemaMismatch;
        const id = try self.session.raw.primitive(sequence_schema.id, .sequence, &.{item.id}, 0);
        return .{ .token = self.session.token, .id = id, .schema = sequence_schema, .scope = self.scope };
    }
    pub fn concat(self: *Body, left: Value, right: Value) Error!Value {
        try self.value(left);
        try self.value(right);
        if (left.schema.id != right.schema.id) return error.SchemaMismatch;
        const shape = self.session.raw.schemas.items[@intCast(left.schema.id)];
        if (shape != .seq) return error.TypeMismatch;
        const id = try self.session.raw.primitive(left.schema.id, .sequence_concat, &.{ left.id, right.id }, 0);
        return .{ .token = self.session.token, .id = id, .schema = left.schema, .scope = self.scope };
    }
    pub fn call(self: *Body, function: Function, arguments: []const Value) Error!Computation {
        try self.active();
        try self.session.check(function.token, "function");
        if (!visible(function.home, self.scope)) return error.OutOfScope;
        if (arguments.len != function.parameters.len) return error.TypeMismatch;
        const ids = try self.session.raw.allocator().alloc(p.Id, arguments.len);
        for (arguments, function.parameters, ids) |argument, named, *id| {
            try self.value(argument);
            if (argument.schema.id != named.schema.id) {
                self.session.report(.schema_mismatch, named.name, named.schema.id, argument.schema.id);
                return error.SchemaMismatch;
            }
            id.* = argument.id;
        }
        const term = try self.session.raw.term(.{ .call = .{ .function = function.id, .arguments = ids } });
        return .{ .token = self.session.token, .id = term, .result = function.result, .scope = self.scope };
    }
    pub fn apply(self: *Body, callable: Value, arguments: []const Value) Error!Computation {
        try self.value(callable);
        const shape = self.session.raw.schemas.items[@intCast(callable.schema.id)];
        if (shape != .internal or shape.internal != .computation) return error.TypeMismatch;
        const signature = shape.internal.computation;
        if (arguments.len != signature.parameters.len) return error.TypeMismatch;
        const ids = try self.session.raw.allocator().alloc(p.Id, arguments.len);
        for (arguments, signature.parameters, ids) |argument, expected, *id| {
            try self.value(argument);
            if (argument.schema.id != expected) {
                self.session.report(.schema_mismatch, "callable argument", expected, argument.schema.id);
                return error.SchemaMismatch;
            }
            id.* = argument.id;
        }
        const term = try self.session.raw.term(.{ .apply = .{ .computation = callable.id, .arguments = ids } });
        return .{ .token = self.session.token, .id = term, .result = try self.session.legacy().schema(signature.result), .scope = self.scope };
    }
    pub fn product(self: *Body, schema: Schema, fields: []const Value) Error!Value {
        try self.active();
        try self.session.checkSchema(schema);
        const shape = self.session.raw.schemas.items[@intCast(schema.id)];
        if (shape != .product or shape.product.len != fields.len) return error.TypeMismatch;
        const ids = try self.session.raw.allocator().alloc(p.Id, fields.len);
        for (fields, shape.product, ids) |item, expected, *id| {
            try self.value(item);
            if (item.schema.id != expected) {
                self.session.report(.schema_mismatch, "product field", expected, item.schema.id);
                return error.SchemaMismatch;
            }
            id.* = item.id;
        }
        const value_id = try self.session.raw.primitive(schema.id, .product, ids, 0);
        return .{ .token = self.session.token, .id = value_id, .schema = schema, .scope = self.scope };
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
    pub fn declare(self: *Body, parameters: []const NamedParameter, result: Schema, effects: []const Operation) Error!Function {
        try self.active();
        var function = try self.session.declare(parameters, result, effects);
        function.home = self.scope;
        return function;
    }
    pub fn lambda(self: *Body, function: Function, schema: Schema) Error!Value {
        try self.active();
        try self.session.check(function.token, "function");
        try self.session.checkSchema(schema);
        if (!visible(function.home, self.scope)) return error.OutOfScope;
        const id = try self.session.raw.lambda(function.id, schema.id);
        return .{ .token = self.session.token, .id = id, .schema = schema, .scope = self.scope };
    }
    pub fn makeRecord(self: *Body, descriptor: Record, fields: []const NamedValue) Error!Value {
        try self.session.checkSchema(descriptor.schema);
        if (fields.len != descriptor.fields.len) return error.TypeMismatch;
        const ordered = try self.session.raw.allocator().alloc(Value, fields.len);
        for (descriptor.fields, ordered) |spec, *slot| {
            var found: ?Value = null;
            for (fields) |candidate| if (std.mem.eql(u8, spec.name, candidate.name)) {
                if (found != null) return error.InvalidSource;
                found = candidate.value;
            };
            slot.* = found orelse return error.InvalidReference;
        }
        return self.product(descriptor.schema, ordered);
    }
    pub fn field(self: *Body, descriptor: Record, product_value: Value, name: []const u8) Error!Value {
        try self.value(product_value);
        try self.session.checkSchema(descriptor.schema);
        if (product_value.schema.id != descriptor.schema.id) {
            self.session.report(.schema_mismatch, "product field", descriptor.schema.id, product_value.schema.id);
            return error.SchemaMismatch;
        }
        for (descriptor.fields, 0..) |field_spec, index| if (std.mem.eql(u8, field_spec.name, name)) {
            const id = try self.session.raw.primitive(field_spec.schema.id, .field, &.{product_value.id}, index);
            return .{ .token = self.session.token, .id = id, .schema = field_spec.schema, .scope = self.scope };
        };
        return error.InvalidReference;
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
