//! Checked staged authoring. Handles borrow the source builder's arena.
//! Keep the source Builder at a stable address until all handles are discarded.
const std = @import("std");
const source = @import("source.zig");
const p = @import("boundary_data").program;
pub const Error = source.Error || error{
    ForeignHandle,
    OutOfScope,
    ClosedBody,
    PoisonedAuthoring,
    SchemaMismatch,
    UnknownName,
    DuplicateName,
    InvalidCategory,
    InvalidBranch,
    UndefinedBody,
};
pub const Schema = opaque {};
pub const Operation = opaque {};
pub const Function = opaque {};
pub const Value = opaque {};
pub const Computation = opaque {};
pub const Field = struct { name: []const u8, schema: *const Schema };
pub const Argument = struct { name: []const u8, value: *const Value };
pub const Diagnostic = struct {
    code: ?anyerror = null,
    entity: []const u8 = "",
    relationship: []const u8 = "",
    expected: ?*const Schema = null,
    actual: ?*const Schema = null,

    pub fn render(self: Diagnostic, writer: *std.Io.Writer) !void {
        try writer.print("{s}: {s}: {s}", .{
            if (self.code) |code| @errorName(code) else "ok", self.entity, self.relationship,
        });
    }
};
const SchemaData = struct {
    owner: *Context,
    id: p.Id,
    fields: []const Field = &.{},
};
const OperationData = struct {
    owner: *Context,
    id: p.Id,
    name: []const u8,
    payload: *const Schema,
    result: *const Schema,
    external: bool,
};
const FunctionData = struct {
    owner: *Context,
    id: p.Id,
    name: []const u8,
    parameters: []const Field,
    result: *const Schema,
    scope: ?*Scope = null,
};
const ValueData = struct {
    owner: *Context,
    id: p.Id,
    schema: *const Schema,
    scope: ?*Scope,
};
const ComputationData = struct {
    owner: *Context,
    id: p.Id,
    schema: *const Schema,
    scope: *Scope,
};
const Scope = struct { parent: ?*Scope, active: bool = true };
const Binding = struct { variable: p.Id, term: p.Id };
fn data(comptime T: type, pointer: anytype) *const T {
    return @ptrCast(@alignCast(pointer));
}
fn handle(comptime T: type, pointer: anytype) *const T {
    return @ptrCast(pointer);
}

/// One arena-owned authoring context. No global registry or runtime evaluator.
pub const Context = struct {
    raw: *source.Builder,
    poisoned: bool = false,
    diagnostic: Diagnostic = .{},
    schemas: std.ArrayList(*const Schema) = .empty,

    pub fn init(raw: *source.Builder) Error!*Context {
        const self = try raw.allocator().create(Context);
        self.* = .{ .raw = raw };
        return self;
    }
    fn ready(self: *Context) Error!void {
        if (self.poisoned) return error.PoisonedAuthoring;
    }
    fn save(self: *Context, comptime T: type, item: T) Error!*T {
        errdefer self.poisoned = true;
        const result = try self.raw.allocator().create(T);
        result.* = item;
        return result;
    }
    fn label(self: *Context, value: []const u8) Error![]const u8 {
        errdefer self.poisoned = true;
        return self.raw.allocator().dupe(u8, value);
    }
    fn reject(self: *Context, code: Error, entity: []const u8, relation: []const u8) Error {
        self.diagnostic = .{ .code = code, .entity = entity, .relationship = relation };
        return code;
    }
    fn origin(self: *Context, owner: *Context) Error!void {
        try self.ready();
        if (owner != self) return self.reject(error.ForeignHandle, "handle", "different builder");
    }
    fn schemaId(self: *Context, schema: *const Schema) Error!p.Id {
        const s = data(SchemaData, schema);
        try self.origin(s.owner);
        return s.id;
    }
    fn same(self: *Context, expected: *const Schema, actual: *const Schema) Error!void {
        _ = try self.schemaId(expected);
        _ = try self.schemaId(actual);
        if (expected != actual) {
            self.diagnostic = .{ .code = error.SchemaMismatch, .entity = "value", .relationship = "schema or named layout differs", .expected = expected, .actual = actual };
            return error.SchemaMismatch;
        }
    }
    fn fields(self: *Context, input: []const Field) Error![]const Field {
        errdefer self.poisoned = true;
        const output = try self.raw.allocator().alloc(Field, input.len);
        for (input, 0..) |field, i| {
            _ = try self.schemaId(field.schema);
            for (input[0..i]) |prior| if (std.mem.eql(u8, prior.name, field.name))
                return self.reject(error.DuplicateName, "declaration", "duplicate field name");
            output[i] = .{ .name = try self.label(field.name), .schema = field.schema };
        }
        return output;
    }
    fn intern(self: *Context, id: p.Id, names: []const Field) Error!*const Schema {
        try self.ready();
        errdefer self.poisoned = true;
        for (self.schemas.items) |existing| {
            const s = data(SchemaData, existing);
            if (s.id != id or s.fields.len != names.len) continue;
            var same_names = true;
            for (s.fields, names) |a, b| {
                if (a.schema != b.schema or !std.mem.eql(u8, a.name, b.name)) same_names = false;
            }
            if (same_names) return existing;
        }
        const item = handle(Schema, try self.save(SchemaData, .{
            .owner = self,
            .id = id,
            .fields = try self.fields(names),
        }));
        try self.schemas.append(self.raw.allocator(), item);
        return item;
    }
    pub fn scalar(self: *Context, comptime T: type) Error!*const Schema {
        try self.ready();
        errdefer self.poisoned = true;
        return self.intern(try self.raw.scalar(T), &.{});
    }
    pub fn record(self: *Context, names: []const Field) Error!*const Schema {
        try self.ready();
        errdefer self.poisoned = true;
        const ids = try self.raw.allocator().alloc(p.Id, names.len);
        for (names, ids) |field, *id| id.* = try self.schemaId(field.schema);
        return self.intern(try self.raw.schema(.{ .product = ids }), names);
    }
    pub fn external(self: *Context, name: []const u8, payload: *const Schema, result: *const Schema) Error!*const Operation {
        return self.operation(name, payload, result, true, .linear);
    }
    pub fn local(self: *Context, name: []const u8, payload: *const Schema, result: *const Schema, use: p.Use) Error!*const Operation {
        return self.operation(name, payload, result, false, use);
    }
    fn operation(self: *Context, name: []const u8, payload: *const Schema, result: *const Schema, external_operation: bool, use: p.Use) Error!*const Operation {
        try self.ready();
        errdefer self.poisoned = true;
        const id = try self.raw.effect(.{ .identity = name, .payload = try self.schemaId(payload), .result = try self.schemaId(result), .external = external_operation, .control_use = use });
        return handle(Operation, try self.save(OperationData, .{ .owner = self, .id = id, .name = try self.label(name), .payload = payload, .result = result, .external = external_operation }));
    }
    fn row(self: *Context, operations: []const *const Operation) Error![]const p.Id {
        errdefer self.poisoned = true;
        const ids = try self.raw.allocator().alloc(p.Id, operations.len);
        for (operations, ids) |op, *id| {
            const o = data(OperationData, op);
            try self.origin(o.owner);
            id.* = o.id;
        }
        return ids;
    }
    pub fn function(self: *Context, name: []const u8, parameters: []const Field, result: *const Schema, allowed: []const *const Operation) Error!*const Function {
        try self.ready();
        errdefer self.poisoned = true;
        const names = try self.fields(parameters);
        const ids = try self.raw.allocator().alloc(p.Id, names.len);
        for (names, ids) |field, *id| id.* = try self.schemaId(field.schema);
        const id = try self.raw.declare(ids, try self.schemaId(result), try self.row(allowed), &.{});
        return handle(Function, try self.save(FunctionData, .{ .owner = self, .id = id, .name = try self.label(name), .parameters = names, .result = result }));
    }
    pub fn body(self: *Context, function_handle: *const Function) Error!*Body {
        return self.nestedBody(function_handle, null);
    }
    fn nestedBody(self: *Context, function_handle: *const Function, parent: ?*Scope) Error!*Body {
        const f = @constCast(data(FunctionData, function_handle));
        try self.origin(f.owner);
        if (f.scope != null) return self.reject(error.ClosedBody, f.name, "body already started");
        const scope = try self.save(Scope, .{ .parent = parent });
        const result = try self.save(Body, .{ .context = self, .scope = scope, .function_handle = function_handle });
        f.scope = scope;
        return result;
    }
    pub fn define(self: *Context, function_handle: *const Function, computation: *const Computation) Error!void {
        const f = data(FunctionData, function_handle);
        const c = data(ComputationData, computation);
        try self.origin(f.owner);
        try self.origin(c.owner);
        if (f.scope != c.scope or c.scope.active)
            return self.reject(error.OutOfScope, f.name, "definition belongs to another body");
        try self.same(f.result, c.schema);
        errdefer self.poisoned = true;
        try self.raw.define(f.id, c.id);
    }
    /// Copies all source arrays: later low-level builder growth cannot invalidate this snapshot.
    /// Compilation still performs the authoritative source and target admission.
    pub fn module(self: *Context, entry: *const Function, failure: *const Schema) Error!source.Module {
        const f = data(FunctionData, entry);
        try self.origin(f.owner);
        const failure_id = try self.schemaId(failure);
        for (self.raw.functions.items) |function_item| if (function_item.body == null)
            return self.reject(error.UndefinedBody, f.name, "all declarations must be defined");
        errdefer self.poisoned = true;
        return source.own(source.Module, self.raw.allocator(), self.raw.module(f.id, failure_id));
    }
};

/// Forward statement builder. Finalization closes this scope to further authoring.
pub const Body = struct {
    context: *Context,
    scope: *Scope,
    function_handle: ?*const Function = null,
    bindings: std.ArrayList(Binding) = .empty,

    fn ready(self: *Body) Error!void {
        try self.context.ready();
        if (!self.scope.active)
            return self.context.reject(error.ClosedBody, "body", "body already finalized");
    }
    fn useValue(self: *Body, value: *const Value) Error!*const ValueData {
        try self.ready();
        const v = data(ValueData, value);
        try self.context.origin(v.owner);
        if (v.scope) |origin| {
            var cursor: ?*Scope = self.scope;
            while (cursor) |scope| : (cursor = scope.parent) if (scope == origin) return v;
            return self.context.reject(error.OutOfScope, "value", "not introduced in lexical ancestry");
        }
        return v;
    }
    fn makeValue(self: *Body, id: p.Id, schema: *const Schema) Error!*const Value {
        return handle(Value, try self.context.save(ValueData, .{ .owner = self.context, .id = id, .schema = schema, .scope = self.scope }));
    }
    fn bind(self: *Body, term: p.Id, schema: *const Schema) Error!*const Value {
        try self.ready();
        const c = self.context;
        errdefer c.poisoned = true;
        const variable = try c.raw.variable(try c.schemaId(schema));
        const result = try self.makeValue(try c.raw.reference(variable), schema);
        try self.bindings.append(c.raw.allocator(), .{ .variable = variable, .term = term });
        return result;
    }
    pub fn parameter(self: *Body, name: []const u8) Error!*const Value {
        try self.ready();
        const f = data(FunctionData, self.function_handle orelse
            return self.context.reject(error.UnknownName, "branch", "branch has no parameters"));
        for (f.parameters, 0..) |named, i| if (std.mem.eql(u8, name, named.name)) {
            errdefer self.context.poisoned = true;
            return self.makeValue(try self.context.raw.reference(self.context.raw.parameter(f.id, i)), named.schema);
        };
        return self.context.reject(error.UnknownName, f.name, "unknown named parameter");
    }
    pub fn constant(self: *Body, comptime T: type, item: T) Error!*const Value {
        try self.ready();
        errdefer self.context.poisoned = true;
        return self.makeValue(try self.context.raw.constant(T, item), try self.context.scalar(T));
    }
    fn arguments(self: *Body, fields: []const Field, args: []const Argument) Error![]const p.Id {
        const c = self.context;
        if (fields.len != args.len)
            return c.reject(error.SchemaMismatch, "arguments", "wrong number of named arguments");
        errdefer c.poisoned = true;
        const ids = try c.raw.allocator().alloc(p.Id, fields.len);
        for (fields, ids) |named, *id| {
            var found: ?*const Value = null;
            for (args) |arg| if (std.mem.eql(u8, named.name, arg.name)) {
                if (found != null) return c.reject(error.DuplicateName, "arguments", "duplicate name");
                found = arg.value;
            };
            const v = try self.useValue(found orelse
                return c.reject(error.UnknownName, "arguments", "missing declared name"));
            try c.same(named.schema, v.schema);
            id.* = v.id;
        }
        return ids;
    }
    pub fn call(self: *Body, function_handle: *const Function, args: []const Argument) Error!*const Value {
        try self.ready();
        const f = data(FunctionData, function_handle);
        try self.context.origin(f.owner);
        errdefer self.context.poisoned = true;
        return self.bind(try self.context.raw.term(.{ .call = .{ .function = f.id, .arguments = try self.arguments(f.parameters, args) } }), f.result);
    }
    pub fn perform(self: *Body, operation_handle: *const Operation, payload: *const Value) Error!*const Value {
        try self.ready();
        const c = self.context;
        const op = data(OperationData, operation_handle);
        try c.origin(op.owner);
        if (!op.external) return c.reject(error.InvalidCategory, op.name, "local operation needs capability");
        const v = try self.useValue(payload);
        try c.same(op.payload, v.schema);
        errdefer c.poisoned = true;
        return self.bind(try c.raw.term(.{ .perform = .{ .effect = op.id, .payload = v.id } }), op.result);
    }
    pub fn product(self: *Body, schema: *const Schema, fields: []const Argument) Error!*const Value {
        const c = self.context;
        const id = try c.schemaId(schema);
        if (c.raw.schemas.items[@intCast(id)] != .product)
            return c.reject(error.InvalidCategory, "product", "requires a record schema");
        errdefer c.poisoned = true;
        return self.makeValue(try c.raw.primitive(id, .product, try self.arguments(data(SchemaData, schema).fields, fields), 0), schema);
    }
    pub fn field(self: *Body, product_value: *const Value, name: []const u8) Error!*const Value {
        const c = self.context;
        const v = try self.useValue(product_value);
        const s = data(SchemaData, v.schema);
        for (s.fields, 0..) |item, index| if (std.mem.eql(u8, item.name, name)) {
            errdefer c.poisoned = true;
            return self.makeValue(try c.raw.primitive(try c.schemaId(item.schema), .field, &.{v.id}, index), item.schema);
        };
        return c.reject(error.UnknownName, "field", "unknown named product field");
    }
    pub fn branch(self: *Body) Error!*Body {
        try self.ready();
        return self.context.save(Body, .{ .context = self.context, .scope = try self.context.save(Scope, .{ .parent = self.scope }) });
    }
    pub fn conditional(self: *Body, condition: *const Value, when_true: *const Computation, when_false: *const Computation) Error!*const Value {
        const c = self.context;
        const v = try self.useValue(condition);
        try c.same(try c.scalar(bool), v.schema);
        const a = data(ComputationData, when_true);
        const b = data(ComputationData, when_false);
        try c.origin(a.owner);
        try c.origin(b.owner);
        if (a.scope.parent != self.scope or b.scope.parent != self.scope or a.scope == b.scope)
            return c.reject(error.InvalidBranch, "conditional", "requires two direct child branches");
        try c.same(a.schema, b.schema);
        errdefer c.poisoned = true;
        return self.bind(try c.raw.term(.{ .conditional = .{ .condition = v.id, .when_true = a.id, .when_false = b.id } }), a.schema);
    }
    pub fn ret(self: *Body, result: *const Value) Error!*const Computation {
        const v = try self.useValue(result);
        const c = self.context;
        errdefer c.poisoned = true;
        var term = try c.raw.pure(v.id);
        var index = self.bindings.items.len;
        while (index != 0) {
            index -= 1;
            const binding = self.bindings.items[index];
            term = try c.raw.bind(binding.variable, binding.term, term);
        }
        const computation = handle(Computation, try c.save(ComputationData, .{
            .owner = c,
            .id = term,
            .schema = v.schema,
            .scope = self.scope,
        }));
        self.scope.active = false;
        return computation;
    }
};
