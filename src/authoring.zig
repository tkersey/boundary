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
    UndefinedSchema,
    SchemaAlreadyDefined,
};
pub const Schema = opaque {
    pub fn fields(self: *const Schema) []const Field {
        return data(SchemaData, self).fields;
    }
    pub fn resultSchema(self: *const Schema) ?*const Schema {
        return data(SchemaData, self).result;
    }
    pub fn describe(self: *const Schema, writer: *std.Io.Writer) !void {
        const item = data(SchemaData, self);
        if (item.pending) |kind| return writer.print("unresolved {s}", .{@tagName(kind)});
        const shape = contextData(item.owner).raw.schemas.items[@intCast(item.id)];
        if (shape == .internal and shape.internal == .capability) {
            const instance = shape.internal.capability;
            if (instance >= contextData(item.owner).raw.effects.items.len)
                return writer.writeAll("capability(invalid instance)");
            return writer.print("capability({s}, instance {d})", .{
                contextData(item.owner).raw.effects.items[@intCast(instance)].identity, instance,
            });
        }
        if (shape == .internal) {
            try writer.writeAll(@tagName(shape.internal));
            if (shape.internal == .computation)
                try writer.print("[{s}]", .{@tagName(shape.internal.computation.use)});
            if (shape.internal == .resumption)
                try writer.print("[{s}, {s}]", .{ @tagName(shape.internal.resumption.mode), @tagName(shape.internal.resumption.use) });
        } else try writer.writeAll(@tagName(shape));
        if (item.fields.len != 0) {
            try writer.writeByte('(');
            for (item.fields, 0..) |named, i| {
                if (i != 0) try writer.writeAll(", ");
                try writer.writeAll(named.name);
            }
            try writer.writeByte(')');
        }
        if (item.result) |returned| {
            const result_info = data(SchemaData, returned);
            try writer.print(" -> {s}", .{
                @tagName(contextData(result_info.owner).raw.schemas.items[@intCast(result_info.id)]),
            });
        }
    }
};
pub const Operation = opaque {};
pub const SchemaKind = enum { alternatives, callable, resumption };
pub const SchemaDeclaration = opaque {
    pub fn schema(self: *const SchemaDeclaration) *const Schema {
        return data(SchemaDeclarationData, self).schema;
    }
};
pub const Function = opaque {};
pub const Value = opaque {};
pub const FailureLiteral = opaque {};
pub const Computation = opaque {};
pub const Handler = opaque {};
pub const Region = opaque {};
pub const Case = opaque {
    pub fn body(self: *const Case) *Body {
        return data(CaseData, self).body;
    }
    pub fn payload(self: *const Case) *const Value {
        return data(CaseData, self).payload;
    }
    pub fn ret(self: *const Case, value: *const Value) Error!*const FinishedCase {
        const item = data(CaseData, self);
        const computation = try item.body.ret(value);
        return handle(FinishedCase, try bodyData(item.body).context.save(FinishedCaseData, .{ .case = self, .computation = computation }));
    }
    pub fn fail(self: *const Case, result: *const Schema, failure: *const Value) Error!*const FinishedCase {
        const item = data(CaseData, self);
        const computation = try item.body.fail(result, failure);
        return handle(FinishedCase, try bodyData(item.body).context.save(FinishedCaseData, .{ .case = self, .computation = computation }));
    }
};
pub const FinishedCase = opaque {};
pub const ProductParts = opaque {
    pub fn get(self: *const ProductParts, name: []const u8) Error!*const Value {
        const parts = data(ProductPartsData, self);
        try parts.body.ready();
        for (parts.fields) |field| if (std.mem.eql(u8, field.name, name)) return field.value;
        return bodyData(parts.body).context.reject(error.UnknownName, "product", "unknown field");
    }
};
pub const CallableOptions = struct {
    use: p.Use,
    captures: []const *const Schema,
    regions: []const *const Region = &.{},
};
pub const HandlerOptions = struct {
    /// Optional forward declarations, in operation order, completed by this handler.
    resumption_slots: ?[]const *const SchemaDeclaration = null,
    /// Permit protected cleanup obligations in captured resumptions.
    obligations: bool = false,
    mode: p.Mode,
    use: p.Use,
    residual: []const *const Operation,
    /// Null preserves the handler's residual row; an empty row declares a pure return arm.
    return_effects: ?[]const *const Operation = null,
    /// Null preserves the residual row; a packaging-only clause can be pure.
    clause_effects: ?[]const *const Operation = null,
    escaping: []const *const Operation = &.{},
    captures: []const *const Schema,
    body_use: p.Use = .linear,
    body_captures: []const *const Schema = &.{},
    /// Explicit inputs following the automatically supplied capabilities.
    body_parameters: []const Field = &.{},
    owned_regions: []const *const Region = &.{},
    borrowed_regions: []const *const Region = &.{},
    state: []const Field = &.{},
};
pub const Field = struct { name: []const u8, schema: *const Schema };
pub const CaptureBounds = struct { continuation: []const *const Schema, body: []const *const Schema = &.{} };
pub const HandledOperation = struct { name: []const u8, operation: *const Operation };
pub const Argument = struct { name: []const u8, value: *const Value };
pub const Arithmetic = enum { add, subtract, multiply, divide, remainder };
pub const ArithmeticFailures = struct {
    overflow: *const FailureLiteral,
    division_by_zero: ?*const FailureLiteral = null,
};
pub const Diagnostic = struct {
    code: ?anyerror = null,
    entity: []const u8 = "",
    relationship: []const u8 = "",
    expected: ?*const Schema = null,
    actual: ?*const Schema = null,
    source: ?@import("source.zig").Diagnostic = null,

    pub fn renderAlloc(
        self: Diagnostic,
        allocator: std.mem.Allocator,
    ) std.mem.Allocator.Error![]u8 {
        var output = std.Io.Writer.Allocating.init(allocator);
        errdefer output.deinit();
        // This writer's only failure cause is allocation, unlike an arbitrary I/O writer.
        self.render(&output.writer) catch return error.OutOfMemory;
        return output.toOwnedSlice();
    }
    pub fn render(self: Diagnostic, writer: *std.Io.Writer) !void {
        try writer.print("{s}: {s}: {s}", .{
            if (self.code) |code| @errorName(code) else "ok", self.entity, self.relationship,
        });
        if (self.expected) |schema| {
            try writer.writeAll("; expected ");
            try schema.describe(writer);
        }
        if (self.actual) |schema| {
            try writer.writeAll("; actual ");
            try schema.describe(writer);
        }
    }
};
const SchemaData = struct {
    owner: *Context,
    id: p.Id,
    fields: []const Field = &.{},
    result: ?*const Schema = null,
    captures: []const *const Schema = &.{},
    pending: ?SchemaKind = null,
};
const SchemaDeclarationData = struct { schema: *const Schema };
const OperationData = struct {
    owner: *Context,
    id: p.Id,
    name: []const u8,
    payload: *const Schema,
    result: *const Schema,
    external: bool,
    bodies: []const Field = &.{},
};
const FunctionData = struct {
    owner: *Context,
    id: p.Id,
    name: []const u8,
    parameters: []const Field,
    result: *const Schema,
    scope: ?*Scope = null,
    callable_schema: ?*const Schema = null,
};
const ValueData = struct {
    owner: *Context,
    id: p.Id,
    schema: *const Schema,
    scope: ?*Scope,
};
const FailureLiteralData = struct {
    owner: *Context,
    value: *const Value,
    literal: p.Id,
};
const ComputationData = struct {
    owner: *Context,
    id: p.Id,
    schema: *const Schema,
    scope: *Scope,
};
const HandlerData = struct {
    owner: *Context,
    id: p.Id,
    clauses: []const HandlerClauseData,
    input: *const Schema,
    answer: *const Schema,
    body_schema: *const Schema,
    returns: *const Function,
    state: []const Field,
};
const HandlerClauseData = struct { operation: *const Operation, resumption: *const Schema, function: *const Function };
const CaseData = struct {
    body: *Body,
    payload: *const Value,
    sum: *const Value,
    index: usize,
    variable: p.Id,
};
const FinishedCaseData = struct { case: *const Case, computation: *const Computation };
const RegionData = struct { owner: *Context, id: p.Id };
const Scope = struct { parent: ?*Scope, active: bool = true };
const PublicationUse = struct {
    anchor: union(enum) { value: p.Id, term: p.Id },
    contract: union(enum) {
        failure: *const Schema,
        cleanup: *const Schema,
        function_scope: struct { declaration: *const Function, scope: *Scope },
    },
};
const ProductPartsData = struct { body: *Body, fields: []const Argument };
const Binding = union(enum) {
    bind: struct { variable: p.Id, term: p.Id },
    unpack: struct { value: p.Id, variables: []const p.Id },
};
fn data(comptime T: type, pointer: anytype) *const T {
    return @ptrCast(@alignCast(pointer));
}
fn handle(comptime T: type, pointer: anytype) *const T {
    return @ptrCast(pointer);
}

/// One arena-owned authoring context. No global registry or runtime evaluator.
const ContextData = struct {
    raw: *source.Builder,
    poisoned: bool = false,
    diagnostic: Diagnostic = .{},
    schemas: std.ArrayList(*const Schema) = .empty,
    imported: std.AutoHashMapUnmanaged(p.Id, *const Schema) = .empty,
    functions: std.ArrayList(*const Function) = .empty,
    twice_definitions: std.AutoHashMapUnmanaged(*const Schema, *const Function) = .empty,
    publication_uses: std.ArrayList(PublicationUse) = .empty,
    variable_schemas: std.AutoHashMapUnmanaged(p.Id, *const Schema) = .empty,
    lambda_schemas: std.AutoHashMapUnmanaged(p.Id, *const Schema) = .empty,
    handlers: std.ArrayList(*const Handler) = .empty,
    capture_failure: ?Error = null,
};
fn contextData(c: *const Context) *ContextData {
    return @ptrCast(@alignCast(@constCast(c)));
}
pub const Context = opaque {
    pub fn lastDiagnostic(self: *const Context) Diagnostic {
        return contextData(self).diagnostic;
    }
    pub fn init(raw: *source.Builder) Error!*Context {
        const self = try raw.allocator().create(ContextData);
        self.* = .{ .raw = raw };
        return @ptrCast(self);
    }
    fn poison(self: *Context, err: anyerror) void {
        const state = contextData(self);
        state.poisoned = true;
        if (err == error.OutOfMemory) state.diagnostic = .{
            .code = error.OutOfMemory,
            .entity = "authoring",
            .relationship = "allocation failed; discard this context",
        };
    }
    fn ready(self: *Context) Error!void {
        if (contextData(self).poisoned) return error.PoisonedAuthoring;
    }
    fn save(self: *Context, comptime T: type, item: T) Error!*T {
        errdefer |err| self.poison(err);
        const result = try contextData(self).raw.allocator().create(T);
        result.* = item;
        return result;
    }
    fn label(self: *Context, value: []const u8) Error![]const u8 {
        errdefer |err| self.poison(err);
        return contextData(self).raw.allocator().dupe(u8, value);
    }
    fn reject(self: *Context, code: Error, entity: []const u8, relation: []const u8) Error {
        contextData(self).diagnostic = .{ .code = code, .entity = entity, .relationship = relation };
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
        errdefer |err| if (err == error.OutOfMemory) {
            self.poison(err);
        };
        if (!try self.compatible(expected, actual)) {
            contextData(self).diagnostic = .{
                .code = error.SchemaMismatch,
                .entity = "value",
                .relationship = "schema or named layout differs",
                .expected = expected,
                .actual = actual,
            };
            return error.SchemaMismatch;
        }
    }
    /// Allocation identity is only a fast path. Raw schema identity preserves
    /// nominal contracts; the metadata graph additionally preserves field names.
    /// Each pair is visited once, including recursive and shared schema graphs.
    fn compatible(self: *Context, expected: *const Schema, actual: *const Schema) Error!bool {
        if (expected == actual) return true;
        const Pair = struct { expected: *const Schema, actual: *const Schema };
        const allocator = contextData(self).raw.arena.child_allocator;
        var pending: std.ArrayList(Pair) = .empty;
        defer pending.deinit(allocator);
        var seen: std.AutoHashMapUnmanaged(Pair, void) = .empty;
        defer seen.deinit(allocator);
        try pending.append(allocator, .{ .expected = expected, .actual = actual });
        var index: usize = 0;
        while (index < pending.items.len) : (index += 1) {
            const pair = pending.items[index];
            if (pair.expected == pair.actual) continue;
            const a = data(SchemaData, pair.expected);
            const b = data(SchemaData, pair.actual);
            try self.origin(a.owner);
            try self.origin(b.owner);
            if (a.id != b.id or a.fields.len != b.fields.len or a.captures.len != b.captures.len)
                return false;
            const visited = try seen.getOrPut(allocator, pair);
            if (visited.found_existing) continue;
            for (a.fields, b.fields) |left, right| {
                if (!std.mem.eql(u8, left.name, right.name)) return false;
                if (left.schema != right.schema) try pending.append(allocator, .{ .expected = left.schema, .actual = right.schema });
            }
            for (a.captures, b.captures) |left, right| {
                if (left != right) try pending.append(allocator, .{ .expected = left, .actual = right });
            }
            if (a.result) |left| {
                const right = b.result orelse return false;
                if (left != right) try pending.append(allocator, .{ .expected = left, .actual = right });
            } else if (b.result != null) return false;
        }
        return true;
    }
    fn fields(self: *Context, input: []const Field) Error![]const Field {
        errdefer |err| self.poison(err);
        const output = try contextData(self).raw.allocator().alloc(Field, input.len);
        for (input, 0..) |field, i| {
            _ = try self.schemaId(field.schema);
            for (input[0..i]) |prior| if (std.mem.eql(u8, prior.name, field.name))
                return @as(Error![]const Field, self.reject(error.DuplicateName, "declaration", "duplicate field name"));
            output[i] = .{ .name = try self.label(field.name), .schema = field.schema };
        }
        return output;
    }
    fn intern(self: *Context, id: p.Id, names: []const Field) Error!*const Schema {
        return self.internResult(id, names, null);
    }
    fn internResult(
        self: *Context,
        id: p.Id,
        names: []const Field,
        result: ?*const Schema,
    ) Error!*const Schema {
        return self.internComplete(id, names, result, &.{});
    }
    fn internComplete(
        self: *Context,
        id: p.Id,
        names: []const Field,
        result: ?*const Schema,
        captures: []const *const Schema,
    ) Error!*const Schema {
        try self.ready();
        errdefer |err| self.poison(err);
        for (contextData(self).schemas.items) |existing| {
            const s = data(SchemaData, existing);
            if (s.id != id or s.result != result or s.fields.len != names.len or
                !std.mem.eql(*const Schema, s.captures, captures)) continue;
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
            .result = result,
            .captures = try contextData(self).raw.allocator().dupe(*const Schema, captures),
        }));
        try contextData(self).schemas.append(contextData(self).raw.allocator(), item);
        return item;
    }
    pub fn scalar(self: *Context, comptime T: type) Error!*const Schema {
        try self.ready();
        errdefer |err| self.poison(err);
        return self.intern(try contextData(self).raw.scalar(T), &.{});
    }
    /// A checked forward reference. Every declaration must be completed before publication.
    pub fn declareSchema(self: *Context, kind: SchemaKind) Error!*const SchemaDeclaration {
        try self.ready();
        errdefer |err| self.poison(err);
        const raw = contextData(self).raw;
        const id = try raw.reserveSchema();
        // This invalid nominal index cannot alias any ordinary schema, including
        // the empty sum used by raw source binders.
        raw.schemas.items[@intCast(id)] = .{ .internal = .{ .abstract_resource = std.math.maxInt(p.Id) } };
        const schema = handle(Schema, try self.save(SchemaData, .{ .owner = self, .id = id, .pending = kind }));
        try contextData(self).schemas.append(raw.allocator(), schema);
        return handle(SchemaDeclaration, try self.save(SchemaDeclarationData, .{ .schema = schema }));
    }
    fn declarationSlot(self: *Context, declaration: *const SchemaDeclaration, kind: SchemaKind) Error!*SchemaData {
        const item = @constCast(data(SchemaData, declaration.schema()));
        try self.origin(item.owner);
        const pending = item.pending orelse return self.reject(error.SchemaAlreadyDefined, "schema", "declaration is already complete");
        if (pending != kind) return self.reject(error.InvalidCategory, "schema", "declaration kind differs from its definition");
        return item;
    }
    fn bindSchema(self: *Context, declaration: *const SchemaDeclaration, kind: SchemaKind, shape: p.Schema, names: []const Field, result: ?*const Schema, captures: []const *const Schema) Error!*const Schema {
        const item = try self.declarationSlot(declaration, kind);
        errdefer |err| self.poison(err);
        const allocator = contextData(self).raw.allocator();
        const fields_copy = try self.fields(names);
        if (result) |value| _ = try self.schemaId(value);
        _ = try self.schemaIds(captures);
        const captures_copy = try allocator.dupe(*const Schema, captures);
        const owned_shape = try source.own(p.Schema, allocator, shape);
        contextData(self).raw.schemas.items[@intCast(item.id)] = owned_shape;
        item.fields = fields_copy;
        item.result = result;
        item.captures = captures_copy;
        item.pending = null;
        return declaration.schema();
    }
    pub fn defineAlternatives(self: *Context, declaration: *const SchemaDeclaration, cases: []const Field) Error!void {
        _ = try self.declarationSlot(declaration, .alternatives);
        const completed = try self.alternatives(cases);
        const info = data(SchemaData, completed);
        _ = try self.bindSchema(declaration, .alternatives, contextData(self).raw.schemas.items[@intCast(info.id)], info.fields, null, &.{});
    }
    pub fn defineCallable(self: *Context, declaration: *const SchemaDeclaration, parameters: []const Field, result: *const Schema, allowed: []const *const Operation, options: CallableOptions) Error!void {
        _ = try self.declarationSlot(declaration, .callable);
        const completed = try self.callable(parameters, result, allowed, options);
        const info = data(SchemaData, completed);
        _ = try self.bindSchema(declaration, .callable, contextData(self).raw.schemas.items[@intCast(info.id)], info.fields, info.result, info.captures);
    }
    pub fn record(self: *Context, names: []const Field) Error!*const Schema {
        try self.ready();
        errdefer |err| self.poison(err);
        const ids = try contextData(self).raw.allocator().alloc(p.Id, names.len);
        for (names, ids) |field, *id| id.* = try self.schemaId(field.schema);
        return self.intern(try contextData(self).raw.schema(.{ .product = ids }), names);
    }
    pub fn external(
        self: *Context,
        name: []const u8,
        payload: *const Schema,
        result: *const Schema,
    ) Error!*const Operation {
        return self.operation(name, payload, result, true, .linear);
    }
    pub fn local(
        self: *Context,
        name: []const u8,
        payload: *const Schema,
        result: *const Schema,
        use: p.Use,
    ) Error!*const Operation {
        return self.operation(name, payload, result, false, use);
    }
    pub fn scoped(
        self: *Context,
        name: []const u8,
        payload: *const Schema,
        result: *const Schema,
        use: p.Use,
        bodies: []const Field,
    ) Error!*const Operation {
        const names = try self.fields(bodies);
        errdefer |err| self.poison(err);
        const ids = try contextData(self).raw.allocator().alloc(p.Id, names.len);
        for (names, ids) |item, *id| {
            id.* = try self.schemaId(item.schema);
            const shape = contextData(self).raw.schemas.items[@intCast(id.*)];
            if ((shape != .internal or shape.internal != .computation) and data(SchemaData, item.schema).pending != .callable)
                return @as(Error!*const Operation, self.reject(error.InvalidCategory, "scoped operation", "body operands must be callable"));
        }
        const id = try contextData(self).raw.effect(.{
            .identity = name,
            .payload = try self.schemaId(payload),
            .result = try self.schemaId(result),
            .external = false,
            .control_use = use,
            .bodies = ids,
        });
        return handle(Operation, try self.save(OperationData, .{
            .owner = self,
            .id = id,
            .name = try self.label(name),
            .payload = payload,
            .result = result,
            .external = false,
            .bodies = names,
        }));
    }
    fn operation(
        self: *Context,
        name: []const u8,
        payload: *const Schema,
        result: *const Schema,
        external_operation: bool,
        use: p.Use,
    ) Error!*const Operation {
        try self.ready();
        errdefer |err| self.poison(err);
        const id = try contextData(self).raw.effect(.{
            .identity = name,
            .payload = try self.schemaId(payload),
            .result = try self.schemaId(result),
            .external = external_operation,
            .control_use = use,
        });
        return handle(Operation, try self.save(OperationData, .{
            .owner = self,
            .id = id,
            .name = try self.label(name),
            .payload = payload,
            .result = result,
            .external = external_operation,
        }));
    }
    fn row(self: *Context, operations: []const *const Operation) Error![]const p.Id {
        errdefer |err| self.poison(err);
        const ids = try contextData(self).raw.allocator().alloc(p.Id, operations.len);
        for (operations, ids) |op, *id| {
            const o = data(OperationData, op);
            try self.origin(o.owner);
            id.* = o.id;
        }
        std.mem.sort(p.Id, ids, {}, std.sort.asc(p.Id));
        var length: usize = 0;
        for (ids) |id| {
            if (length == 0 or ids[length - 1] != id) {
                ids[length] = id;
                length += 1;
            }
        }
        return ids[0..length];
    }
    fn saveFunction(self: *Context, item: FunctionData) Error!*const Function {
        errdefer |err| self.poison(err);
        const result = handle(Function, try self.save(FunctionData, item));
        try contextData(self).functions.append(contextData(self).raw.allocator(), result);
        return result;
    }
    pub fn function(
        self: *Context,
        name: []const u8,
        parameters: []const Field,
        result: *const Schema,
        allowed: []const *const Operation,
    ) Error!*const Function {
        try self.ready();
        errdefer |err| self.poison(err);
        const names = try self.fields(parameters);
        const ids = try contextData(self).raw.allocator().alloc(p.Id, names.len);
        for (names, ids) |field, *id| id.* = try self.schemaId(field.schema);
        const id = try contextData(self).raw.declare(ids, try self.schemaId(result), try self.row(allowed), &.{});
        return try self.saveFunction(.{
            .owner = self,
            .id = id,
            .name = try self.label(name),
            .parameters = names,
            .result = result,
        });
    }
    fn schemaIds(self: *Context, schemas: []const *const Schema) Error![]const p.Id {
        errdefer |err| self.poison(err);
        const ids = try contextData(self).raw.allocator().alloc(p.Id, schemas.len);
        for (schemas, ids) |schema, *id| id.* = try self.schemaId(schema);
        return ids;
    }
    fn regionIds(self: *Context, regions: []const *const Region) Error![]const p.Id {
        errdefer |err| self.poison(err);
        const ids = try contextData(self).raw.allocator().alloc(p.Id, regions.len);
        for (regions, ids) |region_handle, *id| {
            const r = data(RegionData, region_handle);
            try self.origin(r.owner);
            id.* = r.id;
        }
        std.mem.sort(p.Id, ids, {}, std.sort.asc(p.Id));
        var length: usize = 0;
        for (ids) |id| {
            if (length == 0 or ids[length - 1] != id) {
                ids[length] = id;
                length += 1;
            }
        }
        return ids[0..length];
    }
    pub fn region(self: *Context) Error!*const Region {
        try self.ready();
        return handle(Region, try self.save(RegionData, .{ .owner = self, .id = contextData(self).raw.region() }));
    }
    pub fn regionSchema(self: *Context, region_handle: *const Region) Error!*const Schema {
        const r = data(RegionData, region_handle);
        try self.origin(r.owner);
        errdefer |err| self.poison(err);
        return self.intern(try contextData(self).raw.schema(.{ .internal = .{ .region = r.id } }), &.{});
    }
    pub fn cell(self: *Context, region_handle: *const Region, element: *const Schema) Error!*const Schema {
        const r = data(RegionData, region_handle);
        try self.origin(r.owner);
        errdefer |err| self.poison(err);
        const id = try contextData(self).raw.schema(.{ .internal = .{ .cell = .{
            .region = r.id,
            .element = try self.schemaId(element),
        } } });
        return self.internResult(id, &.{}, element);
    }
    /// The first parameter is supplied by withRegion, not by the caller's arguments.
    pub fn regionBodySchema(
        self: *Context,
        region_handle: *const Region,
        parameters: []const Field,
        result: *const Schema,
        allowed: []const *const Operation,
        options: CallableOptions,
    ) Error!*const Schema {
        const r = data(RegionData, region_handle);
        try self.origin(r.owner);
        errdefer |err| self.poison(err);
        const token = try self.regionSchema(region_handle);
        const names = try contextData(self).raw.allocator().alloc(Field, parameters.len + 1);
        names[0] = .{ .name = "region", .schema = token };
        @memcpy(names[1..], parameters);
        const regions = try contextData(self).raw.allocator().alloc(*const Region, options.regions.len + 1);
        regions[0] = region_handle;
        @memcpy(regions[1..], options.regions);
        return self.callable(names, result, allowed, .{
            .use = options.use,
            .captures = options.captures,
            .regions = regions,
        });
    }
    pub fn borrowed(
        self: *Context,
        schema: *const Schema,
        region_handle: *const Region,
    ) Error!*const Schema {
        const r = data(RegionData, region_handle);
        try self.origin(r.owner);
        errdefer |err| self.poison(err);
        return self.internResult(try contextData(self).raw.schema(.{ .internal = .{ .borrowed = .{
            .value = try self.schemaId(schema),
            .region = r.id,
        } } }), &.{}, schema);
    }
    pub fn resource(self: *Context, representation: *const Schema) Error!*const Schema {
        const id = try self.schemaId(representation);
        errdefer |err| self.poison(err);
        return self.internResult(try contextData(self).raw.resource(id), &.{}, representation);
    }
    fn authorityIds(self: *Context, functions: []const *const Function) Error![]const p.Id {
        const ids = try contextData(self).raw.allocator().alloc(p.Id, functions.len);
        for (functions, ids) |function_handle, *id| {
            const f = data(FunctionData, function_handle);
            try self.origin(f.owner);
            id.* = f.id;
        }
        std.mem.sort(p.Id, ids, {}, std.sort.asc(p.Id));
        var length: usize = 0;
        for (ids) |id| {
            if (length == 0 or ids[length - 1] != id) {
                ids[length] = id;
                length += 1;
            }
        }
        return ids[0..length];
    }
    /// Bind the existing nominal representation authority to typed declarations.
    pub fn resourceAuthority(self: *Context, schema: *const Schema, introducers: []const *const Function, eliminators: []const *const Function) Error!void {
        const id = try self.schemaId(schema);
        const shape = contextData(self).raw.schemas.items[@intCast(id)];
        if (shape != .internal or shape.internal != .abstract_resource)
            return self.reject(error.InvalidCategory, "resource authority", "requires a nominal resource schema");
        errdefer |err| self.poison(err);
        try contextData(self).raw.resourceAuthority(id, try self.authorityIds(introducers), try self.authorityIds(eliminators));
    }
    pub fn cleanupInfo(self: *Context, failure: *const Schema) Error!*const Schema {
        _ = try self.schemaId(failure);
        errdefer |err| self.poison(err);
        const unit = try self.scalar(void);
        const text = try self.intern(try contextData(self).raw.schema(.text), &.{});
        const bytes = try self.intern(try contextData(self).raw.schema(.bytes), &.{});
        const reason = try self.alternatives(&.{
            .{ .name = "0", .schema = text }, .{ .name = "1", .schema = bytes },
        });
        const primary = try self.alternatives(&.{
            .{ .name = "0", .schema = unit },   .{ .name = "1", .schema = failure },
            .{ .name = "2", .schema = reason }, .{ .name = "3", .schema = unit },
        });
        const cancellation = try self.alternatives(&.{
            .{ .name = "0", .schema = unit }, .{ .name = "1", .schema = reason },
        });
        return self.record(&.{
            .{ .name = "0", .schema = primary },
            .{ .name = "1", .schema = cancellation },
            .{ .name = "2", .schema = try self.sequence(failure) },
        });
    }
    pub fn sequence(self: *Context, element: *const Schema) Error!*const Schema {
        errdefer |err| self.poison(err);
        const id = try contextData(self).raw.schema(.{ .seq = try self.schemaId(element) });
        return self.internResult(id, &.{}, element);
    }
    pub fn suspensionPackage(self: *Context, resumption: *const Schema) Error!*const Schema {
        const id = try self.schemaId(resumption);
        const shape = contextData(self).raw.schemas.items[@intCast(id)];
        if (shape != .internal or shape.internal != .resumption)
            return self.reject(error.InvalidCategory, "package", "requires a resumption schema");
        errdefer |err| self.poison(err);
        const package_id = try contextData(self).raw.schema(.{
            .internal = .{ .suspension_package = id },
        });
        return self.internResult(package_id, &.{}, resumption);
    }
    pub fn alternatives(self: *Context, cases: []const Field) Error!*const Schema {
        try self.ready();
        errdefer |err| self.poison(err);
        const ids = try contextData(self).raw.allocator().alloc(p.Id, cases.len);
        for (cases, ids) |item, *id| id.* = try self.schemaId(item.schema);
        return self.intern(try contextData(self).raw.schema(.{ .sum = ids }), cases);
    }
    pub fn callable(
        self: *Context,
        parameters: []const Field,
        result: *const Schema,
        allowed: []const *const Operation,
        options: CallableOptions,
    ) Error!*const Schema {
        try self.ready();
        errdefer |err| self.poison(err);
        const names = try self.fields(parameters);
        const ids = try contextData(self).raw.allocator().alloc(p.Id, names.len);
        for (names, ids) |item, *id| id.* = try self.schemaId(item.schema);
        const id = try contextData(self).raw.schema(.{ .internal = .{ .computation = .{
            .parameters = ids,
            .result = try self.schemaId(result),
            .effects = try self.row(allowed),
            .capture_bound = try self.schemaIds(options.captures),
            .use = options.use,
            .regions = try self.regionIds(options.regions),
        } } });
        return self.internComplete(id, names, result, options.captures);
    }
    pub fn capability(self: *Context, operation_handle: *const Operation) Error!*const Schema {
        const op = data(OperationData, operation_handle);
        try self.origin(op.owner);
        if (op.external) return self.reject(error.InvalidCategory, op.name, "external operation has no local capability");
        errdefer |err| self.poison(err);
        return self.intern(try contextData(self).raw.schema(.{ .internal = .{ .capability = op.id } }), &.{});
    }
    pub fn functionFor(
        self: *Context,
        name: []const u8,
        schema: *const Schema,
    ) Error!*const Function {
        const id = try self.schemaId(schema);
        const shape = contextData(self).raw.schemas.items[@intCast(id)];
        if (shape != .internal or shape.internal != .computation)
            return self.reject(error.InvalidCategory, "function", "requires callable schema");
        const info = data(SchemaData, schema);
        const result = info.result orelse return self.reject(error.InvalidSchema, "function declaration", "callable metadata lacks its result");
        errdefer |err| self.poison(err);
        const signature = shape.internal.computation;
        return try self.saveFunction(.{
            .owner = self,
            .id = try contextData(self).raw.declare(signature.parameters, signature.result, signature.effects, signature.regions),
            .name = try self.label(name),
            .parameters = info.fields,
            .result = result,
            .callable_schema = schema,
        });
    }
    pub fn twice(self: *Context, schema: *const Schema) Error!*const Function {
        errdefer |err| if (err == error.OutOfMemory) self.poison(err);
        const id = try self.schemaId(schema);
        if (contextData(self).twice_definitions.get(schema)) |existing| return existing;
        const shape = contextData(self).raw.schemas.items[@intCast(id)];
        if (shape != .internal or shape.internal != .computation) return @as(Error!*const Function, self.reject(error.InvalidCategory, "twice", "requires a reusable zero-argument callable"));
        const signature = shape.internal.computation;
        if (signature.parameters.len != 0 or signature.use != .reusable)
            return @as(Error!*const Function, self.reject(error.InvalidOwnership, "twice", "requires a reusable zero-argument callable"));
        const info = data(SchemaData, schema);
        const element = info.result orelse return @as(Error!*const Function, self.reject(error.InvalidSchema, "twice", "requires a reusable zero-argument callable"));
        const pair = try self.record(&.{
            .{ .name = "first", .schema = element },
            .{ .name = "second", .schema = element },
        });
        const effects = try contextData(self).raw.allocator().alloc(*const Operation, signature.effects.len);
        for (signature.effects, effects) |effect_id, *out| out.* = try interop.operation(self, effect_id);
        const function_handle = try self.function("twice", &.{.{ .name = "callable", .schema = schema }}, pair, effects);
        const f = data(FunctionData, function_handle);
        contextData(self).raw.functions.items[@intCast(f.id)].regions = signature.regions;
        const forward = try self.body(function_handle);
        const callable_value = try forward.parameter("callable");
        const first = try forward.apply(callable_value, &.{});
        const second = try forward.apply(callable_value, &.{});
        const result = try forward.product(pair, &.{
            .{ .name = "first", .value = first },
            .{ .name = "second", .value = second },
        });
        try self.define(function_handle, try forward.ret(result));
        try contextData(self).twice_definitions.put(
            contextData(self).raw.allocator(),
            schema,
            function_handle,
        );
        return function_handle;
    }
    fn handlerReturn(self: *Context, input: *const Schema, answer: *const Schema, options: HandlerOptions) Error!*const Function {
        const parameter_fields = try contextData(self).raw.allocator().alloc(Field, 1 + options.state.len);
        @memcpy(parameter_fields[0..options.state.len], options.state);
        parameter_fields[options.state.len] = .{ .name = "result", .schema = input };
        const function_handle = try self.function("handler return", parameter_fields, answer, options.return_effects orelse options.residual);
        contextData(self).raw.functions.items[@intCast(data(FunctionData, function_handle).id)].regions = try self.regionIds(options.borrowed_regions);
        return function_handle;
    }
    fn handlerClause(self: *Context, op: *const OperationData, answer: *const Schema, resumption: *const Schema, options: HandlerOptions) Error!*const Function {
        const parameter_fields = try contextData(self).raw.allocator().alloc(Field, 2 + options.state.len + op.bodies.len);
        @memcpy(parameter_fields[0..options.state.len], options.state);
        parameter_fields[options.state.len] = .{ .name = "payload", .schema = op.payload };
        @memcpy(parameter_fields[options.state.len + 1 .. parameter_fields.len - 1], op.bodies);
        parameter_fields[parameter_fields.len - 1] = .{ .name = "resumption", .schema = resumption };
        const function_handle = try self.function("operation clause", parameter_fields, answer, options.clause_effects orelse options.residual);
        contextData(self).raw.functions.items[@intCast(data(FunctionData, function_handle).id)].regions = try self.regionIds(options.borrowed_regions);
        return function_handle;
    }
    pub fn handler(self: *Context, operation_handle: *const Operation, input: *const Schema, answer: *const Schema, options: HandlerOptions) Error!*const Handler {
        return self.handlerSet(&.{.{ .name = "capability", .operation = operation_handle }}, input, answer, options);
    }
    /// One return arm and state vector, with a named capability and clause for each operation.
    pub fn handlerSet(self: *Context, operations: []const HandledOperation, input: *const Schema, answer: *const Schema, options: HandlerOptions) Error!*const Handler {
        try self.ready();
        if (operations.len == 0) return self.reject(error.InvalidCategory, "handler", "requires at least one local operation");
        if (options.resumption_slots) |slots| {
            if (slots.len != operations.len) return self.reject(error.SchemaMismatch, "handler", "one resumption declaration is required per operation");
            for (slots, 0..) |slot, index| {
                _ = try self.declarationSlot(slot, .resumption);
                for (slots[0..index]) |previous| if (previous == slot)
                    return self.reject(error.DuplicateName, "handler", "resumption declarations must be distinct");
            }
        }
        for (operations, 0..) |item, index| {
            const op = data(OperationData, item.operation);
            try self.origin(op.owner);
            if (op.external) return self.reject(error.InvalidCategory, op.name, "handler requires local operation");
            for (operations[0..index]) |previous| {
                if (data(OperationData, previous.operation).id == op.id)
                    return self.reject(error.InvalidEffect, op.name, "operation occurs twice in handler");
                if (std.mem.eql(u8, previous.name, item.name))
                    return self.reject(error.DuplicateName, item.name, "handler capability name occurs twice");
            }
        }
        const allocator = contextData(self).raw.allocator();
        errdefer |err| self.poison(err);
        const handled = try allocator.alloc(p.Id, operations.len);
        const parameters = try allocator.alloc(Field, operations.len + options.body_parameters.len);
        const body_effects = try allocator.alloc(*const Operation, options.residual.len + operations.len);
        @memcpy(body_effects[0..options.residual.len], options.residual);
        for (operations, handled, parameters[0..operations.len], 0..) |item, *id, *parameter, index| {
            const op = data(OperationData, item.operation);
            id.* = op.id;
            parameter.* = .{ .name = item.name, .schema = try self.capability(item.operation) };
            body_effects[options.residual.len + index] = item.operation;
        }
        @memcpy(parameters[operations.len..], options.body_parameters);
        const body_schema = try self.callable(parameters, input, body_effects, .{
            .use = options.body_use,
            .captures = options.body_captures,
            .regions = options.borrowed_regions,
        });
        const residual = try self.row(options.residual);
        const answer_id = try self.schemaId(answer);
        const resume_answer = if (options.mode == .deep) answer else input;
        const returns = try self.handlerReturn(input, answer, options);
        const clauses = try allocator.alloc(p.Clause, operations.len);
        const metadata = try allocator.alloc(HandlerClauseData, operations.len);
        for (operations, clauses, metadata, 0..) |item, *clause, *meta, index| {
            const op = data(OperationData, item.operation);
            const resume_shape: p.Schema = .{ .internal = .{ .resumption = .{
                .effect = op.id,
                .input = try self.schemaId(op.result),
                .answer = try self.schemaId(resume_answer),
                .effects = residual,
                .escaping = try self.row(options.escaping),
                .capture_bound = try self.schemaIds(options.captures),
                .handled = handled,
                .mode = options.mode,
                .use = options.use,
                .owned_regions = try self.regionIds(options.owned_regions),
                .obligations = options.obligations,
            } } };
            const resumption = if (options.resumption_slots) |slots|
                try self.bindSchema(slots[index], .resumption, resume_shape, &.{.{ .name = "reply", .schema = op.result }}, resume_answer, options.captures)
            else
                try self.internComplete(try contextData(self).raw.schema(resume_shape), &.{.{ .name = "reply", .schema = op.result }}, resume_answer, options.captures);
            const resume_id = try self.schemaId(resumption);
            const function_handle = try self.handlerClause(op, answer, resumption, options);
            clause.* = .{ .effect = op.id, .function = data(FunctionData, function_handle).id, .resumption = resume_id };
            meta.* = .{ .operation = item.operation, .function = function_handle, .resumption = resumption };
        }
        const state_ids = try allocator.alloc(p.Id, options.state.len);
        for (options.state, state_ids) |item, *id| id.* = try self.schemaId(item.schema);
        const result = handle(Handler, try self.save(HandlerData, .{
            .owner = self,
            .id = try contextData(self).raw.handler(.{
                .mode = options.mode,
                .input = try self.schemaId(input),
                .answer = answer_id,
                .return_function = data(FunctionData, returns).id,
                .clauses = clauses,
                .state = state_ids,
                .effects = residual,
            }),
            .clauses = metadata,
            .input = input,
            .answer = answer,
            .body_schema = body_schema,
            .returns = returns,
            .state = try self.fields(options.state),
        }));
        try contextData(self).handlers.append(allocator, result);
        return result;
    }
    /// Derive the resumption clause from a responder with an explicit residual contract.
    pub fn responder(
        self: *Context,
        operation_handle: *const Operation,
        answer: *const Schema,
        responder_function: *const Function,
        options: HandlerOptions,
    ) Error!*const Handler {
        const op = data(OperationData, operation_handle);
        const f = data(FunctionData, responder_function);
        try self.origin(op.owner);
        try self.origin(f.owner);
        if (f.parameters.len != 1 or options.state.len != 0)
            return self.reject(error.SchemaMismatch, f.name, "responder requires one payload parameter and no handler state");
        try self.same(op.payload, f.parameters[0].schema);
        try self.same(op.result, f.result);
        const h = try self.handler(operation_handle, answer, answer, options);
        const hd = data(HandlerData, h);
        const returns = try self.body(hd.returns);
        try self.define(hd.returns, try returns.ret(try returns.parameter("result")));
        const clause = try self.body(hd.clauses[0].function);
        const reply = try clause.call(responder_function, &.{
            .{
                .name = f.parameters[0].name,
                .value = try clause.parameter("payload"),
            },
        });
        const resumed = try clause.resumeValue(try clause.parameter("resumption"), reply);
        try self.define(hd.clauses[0].function, try clause.ret(resumed));
        return h;
    }
    pub fn returnFunction(self: *Context, handler_handle: *const Handler) Error!*const Function {
        const h = data(HandlerData, handler_handle);
        try self.origin(h.owner);
        return h.returns;
    }
    pub fn clauseFunction(self: *Context, handler_handle: *const Handler) Error!*const Function {
        const h = data(HandlerData, handler_handle);
        try self.origin(h.owner);
        if (h.clauses.len != 1) return self.reject(error.InvalidCategory, "clause", "select an operation for a multi-clause handler");
        return h.clauses[0].function;
    }
    pub fn clauseFunctionFor(self: *Context, handler_handle: *const Handler, operation_handle: *const Operation) Error!*const Function {
        return (try self.clauseFor(handler_handle, operation_handle)).function;
    }
    pub fn resumptionSchemaFor(self: *Context, handler_handle: *const Handler, operation_handle: *const Operation) Error!*const Schema {
        return (try self.clauseFor(handler_handle, operation_handle)).resumption;
    }
    fn clauseFor(self: *Context, handler_handle: *const Handler, operation_handle: *const Operation) Error!*const HandlerClauseData {
        const h = data(HandlerData, handler_handle);
        try self.origin(h.owner);
        try self.origin(data(OperationData, operation_handle).owner);
        for (h.clauses) |*clause| if (data(OperationData, clause.operation).id == data(OperationData, operation_handle).id) return clause;
        return self.reject(error.InvalidEffect, "clause", "operation is not handled here");
    }
    pub fn handledSchema(self: *Context, handler_handle: *const Handler) Error!*const Schema {
        const h = data(HandlerData, handler_handle);
        try self.origin(h.owner);
        return h.body_schema;
    }
    pub fn body(self: *Context, function_handle: *const Function) Error!*Body {
        return self.nestedBody(function_handle, null);
    }
    fn nestedBody(self: *Context, function_handle: *const Function, parent: ?*Scope) Error!*Body {
        const f = @constCast(data(FunctionData, function_handle));
        try self.origin(f.owner);
        if (f.scope != null) return self.reject(error.ClosedBody, f.name, "body already started");
        const scope = try self.save(Scope, .{ .parent = parent });
        const result = try self.save(BodyData, .{
            .context = self,
            .scope = scope,
            .function_handle = function_handle,
        });
        f.scope = scope;
        return @ptrCast(result);
    }
    pub fn define(
        self: *Context,
        function_handle: *const Function,
        computation: *const Computation,
    ) Error!void {
        const f = data(FunctionData, function_handle);
        const c = data(ComputationData, computation);
        try self.origin(f.owner);
        try self.origin(c.owner);
        if (f.scope != c.scope or c.scope.active)
            return self.reject(error.OutOfScope, f.name, "definition belongs to another body");
        self.same(f.result, c.schema) catch |err| {
            contextData(self).diagnostic.entity = f.name;
            contextData(self).diagnostic.relationship = "body result differs from the function result";
            return err;
        };
        errdefer |err| self.poison(err);
        try contextData(self).raw.define(f.id, c.id);
    }
    /// Source/target admission remains authoritative; diagnostics retain its causal site.
    pub fn compile(
        self: *Context,
        allocator: std.mem.Allocator,
        entry: *const Function,
        failure: *const Schema,
    ) Error!source.Compiled {
        return self.lowerNamed(allocator, try self.publish(entry, failure, false));
    }
    /// Narrow options preserve the mandatory original-occurrence capture observer.
    pub fn compileWithOptions(
        self: *Context,
        allocator: std.mem.Allocator,
        entry: *const Function,
        failure: *const Schema,
        coalescing: @import("boundary_data").coalescing.Options,
    ) Error!source.Compiled {
        return self.lowerNamedWithOptions(allocator, try self.publish(entry, failure, false), coalescing);
    }
    fn lowerNamed(self: *Context, allocator: std.mem.Allocator, module_value: source.Module) Error!source.Compiled {
        return self.lowerNamedWithOptions(allocator, module_value, .{});
    }
    fn lowerNamedWithOptions(
        self: *Context,
        allocator: std.mem.Allocator,
        module_value: source.Module,
        coalescing: @import("boundary_data").coalescing.Options,
    ) Error!source.Compiled {
        var diagnostic: source.Diagnostic = .{};
        var result = source.lowerObserved(allocator, module_value, .{
            .diagnostic = &diagnostic,
            .coalescing = coalescing,
            .captures = if (contextData(self).lambda_schemas.count() != 0 or contextData(self).handlers.items.len != 0) .{ .context = self, .capture = observeCapture, .closure = observeClosure } else null,
        }) catch |err| {
            if (contextData(self).capture_failure) |failure| return failure;
            const name = if (diagnostic.function) |id|
                self.functionName(id) orelse "compiled source"
            else
                "compiled source";
            contextData(self).diagnostic = .{ .code = err, .entity = name, .source = diagnostic, .relationship = switch (err) {
                error.InvalidOwnership, error.OverwrittenOwner, error.UnavailableSlot => "capture, borrow or use obligation failed authoritative admission",
                error.InvalidEffect => "effect exceeds declared residual allowance",
                error.TypeMismatch => "argument, result or handler answer relationship differs",
                error.UnboundVariable => "value is unavailable at this lexical use",
                else => "authoritative source or target admission rejected the construction",
            } };
            return err;
        };
        if (contextData(self).capture_failure) |err| {
            result.deinit();
            return err;
        }
        return result;
    }
    fn functionName(self: *const Context, id: p.Id) ?[]const u8 {
        for (contextData(self).functions.items) |function_handle| {
            const item = data(FunctionData, function_handle);
            if (item.id == id) return item.name;
        }
        return null;
    }
    pub fn literalFailure(self: *Context, comptime T: type, item: T) Error!*const FailureLiteral {
        try self.ready();
        errdefer |err| self.poison(err);
        const schema = try self.scalar(T);
        return interop.literalFailure(self, try contextData(self).raw.constant(T, item), schema);
    }
    fn notePublication(self: *Context, use: PublicationUse) Error!void {
        errdefer |err| self.poison(err);
        try contextData(self).publication_uses.append(contextData(self).raw.allocator(), use);
    }
    fn publication(self: *Context, failure: *const Schema) Error!void {
        if (contextData(self).publication_uses.items.len == 0) return;
        var scratch = std.heap.ArenaAllocator.init(contextData(self).raw.arena.child_allocator);
        defer scratch.deinit();
        const allocator = scratch.allocator();
        const terms = try allocator.alloc(bool, contextData(self).raw.terms.items.len);
        const values = try allocator.alloc(bool, contextData(self).raw.values.items.len);
        @memset(terms, false);
        @memset(values, false);
        var pending_terms: std.ArrayList(p.Id) = .empty;
        var pending_values: std.ArrayList(p.Id) = .empty;
        for (contextData(self).raw.functions.items) |definition| if (definition.body) |term_id|
            try pending_terms.append(allocator, term_id);
        var refs: @import("source/check.zig").References = .{ .allocator = allocator };
        while (pending_terms.pop()) |id| {
            if (id >= terms.len) return error.InvalidReference;
            if (terms[@intCast(id)]) continue;
            terms[@intCast(id)] = true;
            refs.values.clearRetainingCapacity();
            refs.terms.clearRetainingCapacity();
            refs.bound.clearRetainingCapacity();
            try refs.collect(contextData(self).raw.terms.items[@intCast(id)]);
            try pending_terms.appendSlice(allocator, refs.terms.items);
            try pending_values.appendSlice(allocator, refs.values.items);
        }
        while (pending_values.pop()) |id| {
            if (id >= values.len) return error.InvalidReference;
            if (values[@intCast(id)]) continue;
            values[@intCast(id)] = true;
            const expression = contextData(self).raw.values.items[@intCast(id)].expression;
            if (expression == .primitive)
                try pending_values.appendSlice(allocator, expression.primitive.operands);
        }
        var cleanup: ?*const Schema = null;
        for (contextData(self).publication_uses.items) |use| {
            const included = switch (use.anchor) {
                .value => |id| id < values.len and values[@intCast(id)],
                .term => |id| id < terms.len and terms[@intCast(id)],
            };
            if (!included) continue;
            switch (use.contract) {
                .function_scope => |pending| try self.functionVisible(data(FunctionData, pending.declaration), pending.scope),
                .failure, .cleanup => |schema| {
                    const is_cleanup = use.contract == .cleanup;
                    if (is_cleanup and cleanup == null) cleanup = try self.cleanupInfo(failure);
                    self.same(if (is_cleanup) cleanup.? else failure, schema) catch |err| {
                        contextData(self).diagnostic.entity = if (is_cleanup) "cleanup" else "authored failure";
                        contextData(self).diagnostic.relationship = "named failure layout differs from module failure contract";
                        return err;
                    };
                },
            }
        }
    }
    fn functionVisible(self: *Context, f: *const FunctionData, at: *Scope) Error!void {
        try self.origin(f.owner);
        if (f.scope) |scope| if (scope.parent) |parent| {
            var cursor: ?*Scope = at;
            while (cursor) |current| : (cursor = current.parent) if (current == parent) return;
            return self.reject(error.OutOfScope, f.name, "closure belongs to another lexical scope");
        };
    }
    fn checkCapture(self: *Context, bound: []const *const Schema, variable: p.Id) Error!void {
        // Raw interoperation has no recoverable field names. Known authored
        // metadata is never replaced by raw structural equality.
        const actual = contextData(self).variable_schemas.get(variable) orelse return;
        for (bound) |allowed| if (try self.compatible(allowed, actual)) return;
        return self.reject(error.SchemaMismatch, "capture", "retained named value is outside its declared capture allowance");
    }
    fn observeCapture(pointer: *anyopaque, effect: p.Id, variable: p.Id) void {
        const self: *Context = @ptrCast(@alignCast(pointer));
        if (contextData(self).capture_failure != null) return;
        for (contextData(self).handlers.items) |handler_handle| {
            const h = data(HandlerData, handler_handle);
            for (h.clauses) |clause| {
                if (data(OperationData, clause.operation).id != effect) continue;
                self.checkCapture(data(SchemaData, clause.resumption).captures, variable) catch |err| {
                    contextData(self).capture_failure = err;
                    return;
                };
            }
        }
    }
    fn observeClosure(pointer: *anyopaque, value_id: p.Id, variable: p.Id) void {
        const self: *Context = @ptrCast(@alignCast(pointer));
        if (contextData(self).capture_failure != null) return;
        const schema = contextData(self).lambda_schemas.get(value_id) orelse return;
        self.checkCapture(data(SchemaData, schema).captures, variable) catch |err| {
            contextData(self).capture_failure = err;
        };
    }
    fn capturePublication(self: *Context, module_value: source.Module) Error!void {
        if (contextData(self).lambda_schemas.count() == 0 and contextData(self).handlers.items.len == 0) return;
        var checked = try self.lowerNamed(contextData(self).raw.arena.child_allocator, module_value);
        checked.deinit();
    }
    /// Copies all source arrays: later low-level builder growth cannot invalidate this snapshot.
    /// Compilation still performs the authoritative source and target admission.
    pub fn module(
        self: *Context,
        entry: *const Function,
        failure: *const Schema,
    ) Error!source.Module {
        return self.publish(entry, failure, true);
    }
    fn publish(self: *Context, entry: *const Function, failure: *const Schema, check_captures: bool) Error!source.Module {
        const f = data(FunctionData, entry);
        try self.origin(f.owner);
        const failure_id = try self.schemaId(failure);
        for (contextData(self).schemas.items) |schema| if (data(SchemaData, schema).pending != null) {
            const err = self.reject(error.UndefinedSchema, "schema", "forward declaration has no definition");
            contextData(self).diagnostic.actual = schema;
            return err;
        };
        for (contextData(self).raw.functions.items, 0..) |function_item, id| if (function_item.body == null)
            return self.reject(error.UndefinedBody, self.functionName(id) orelse "unnamed source function", "declaration has no body");
        errdefer |err| self.poison(err);
        try self.publication(failure);
        const result = contextData(self).raw.module(f.id, failure_id);
        if (check_captures) try self.capturePublication(result);
        return source.own(source.Module, contextData(self).raw.allocator(), result);
    }
};

/// Forward statement builder. Finalization closes this scope to further authoring.
const BodyData = struct {
    context: *Context,
    scope: *Scope,
    function_handle: ?*const Function = null,
    bindings: std.ArrayList(Binding) = .empty,
    parameter_values: ?[]?*const Value = null,
};
fn bodyData(body: *Body) *BodyData {
    return @ptrCast(@alignCast(body));
}
pub const Body = opaque {
    fn ready(self: *Body) Error!void {
        try bodyData(self).context.ready();
        var cursor: ?*Scope = bodyData(self).scope;
        while (cursor) |scope| : (cursor = scope.parent) {
            if (!scope.active)
                return bodyData(self).context.reject(error.ClosedBody, "body", "body or ancestor already finalized");
        }
    }
    fn useValue(self: *Body, value: *const Value) Error!*const ValueData {
        try self.ready();
        const v = data(ValueData, value);
        try bodyData(self).context.origin(v.owner);
        if (v.scope) |origin| {
            var cursor: ?*Scope = bodyData(self).scope;
            while (cursor) |scope| : (cursor = scope.parent) if (scope == origin) return v;
            return bodyData(self).context.reject(error.OutOfScope, "value", "not introduced in lexical ancestry");
        }
        return v;
    }
    fn makeValue(self: *Body, id: p.Id, schema: *const Schema) Error!*const Value {
        errdefer |err| if (err == error.OutOfMemory) bodyData(self).context.poison(err);
        const expression = contextData(bodyData(self).context).raw.values.items[@intCast(id)].expression;
        if (expression == .variable) {
            if (contextData(bodyData(self).context).variable_schemas.get(expression.variable)) |prior| try bodyData(self).context.same(prior, schema);
            try contextData(bodyData(self).context).variable_schemas.put(contextData(bodyData(self).context).raw.allocator(), expression.variable, schema);
        }
        return handle(Value, try bodyData(self).context.save(ValueData, .{
            .owner = bodyData(self).context,
            .id = id,
            .schema = schema,
            .scope = bodyData(self).scope,
        }));
    }
    fn bind(self: *Body, term: p.Id, schema: *const Schema) Error!*const Value {
        try self.ready();
        const c = bodyData(self).context;
        errdefer |err| c.poison(err);
        const variable = try contextData(c).raw.variable(try c.schemaId(schema));
        const result = try self.makeValue(try contextData(c).raw.reference(variable), schema);
        try bodyData(self).bindings.append(contextData(c).raw.allocator(), .{
            .bind = .{ .variable = variable, .term = term },
        });
        return result;
    }
    pub fn parameter(self: *Body, name: []const u8) Error!*const Value {
        try self.ready();
        const f = data(FunctionData, bodyData(self).function_handle orelse
            return bodyData(self).context.reject(error.UnknownName, "branch", "branch has no parameters"));
        for (f.parameters, 0..) |named, i| if (std.mem.eql(u8, name, named.name)) {
            errdefer |err| bodyData(self).context.poison(err);
            if (bodyData(self).parameter_values == null) {
                const values = try contextData(bodyData(self).context).raw.allocator().alloc(?*const Value, f.parameters.len);
                @memset(values, null);
                bodyData(self).parameter_values = values;
            }
            if (bodyData(self).parameter_values.?[i]) |present| return present;
            const result = try self.makeValue(try contextData(bodyData(self).context).raw.reference(contextData(bodyData(self).context).raw.parameter(f.id, i)), named.schema);
            bodyData(self).parameter_values.?[i] = result;
            return result;
        };
        return bodyData(self).context.reject(error.UnknownName, f.name, "unknown named parameter");
    }
    pub fn constant(self: *Body, comptime T: type, item: T) Error!*const Value {
        try self.ready();
        errdefer |err| bodyData(self).context.poison(err);
        return self.makeValue(try contextData(bodyData(self).context).raw.constant(T, item), try bodyData(self).context.scalar(T));
    }
    fn arguments(self: *Body, fields: []const Field, args: []const Argument) Error![]const p.Id {
        const c = bodyData(self).context;
        if (fields.len != args.len)
            return c.reject(error.SchemaMismatch, "arguments", "wrong number of named arguments");
        errdefer |err| c.poison(err);
        const ids = try contextData(c).raw.allocator().alloc(p.Id, fields.len);
        for (fields, ids) |named, *id| {
            var found: ?*const Value = null;
            for (args) |arg| if (std.mem.eql(u8, named.name, arg.name)) {
                if (found != null) return @as(Error![]const p.Id, c.reject(error.DuplicateName, "arguments", "duplicate name"));
                found = arg.value;
            };
            const v = try self.useValue(found orelse
                return @as(Error![]const p.Id, c.reject(error.UnknownName, "arguments", "missing declared name")));
            c.same(named.schema, v.schema) catch |err| {
                contextData(c).diagnostic.entity = named.name;
                contextData(c).diagnostic.relationship = "argument or product field differs from its declared schema";
                return @as(Error![]const p.Id, err);
            };
            id.* = v.id;
        }
        return ids;
    }
    pub fn call(
        self: *Body,
        function_handle: *const Function,
        args: []const Argument,
    ) Error!*const Value {
        try self.ready();
        const f = try self.visibleFunction(function_handle);
        errdefer |err| bodyData(self).context.poison(err);
        const term = try contextData(bodyData(self).context).raw.term(.{
            .call = .{
                .function = f.id,
                .arguments = try self.arguments(f.parameters, args),
            },
        });
        try self.noteForwardUse(function_handle, .{ .term = term });
        return self.bind(term, f.result);
    }
    pub fn perform(
        self: *Body,
        operation_handle: *const Operation,
        payload: *const Value,
    ) Error!*const Value {
        try self.ready();
        const c = bodyData(self).context;
        const op = data(OperationData, operation_handle);
        try c.origin(op.owner);
        if (!op.external) return c.reject(error.InvalidCategory, op.name, "local operation needs capability");
        const v = try self.useValue(payload);
        try c.same(op.payload, v.schema);
        errdefer |err| c.poison(err);
        return self.bind(try contextData(c).raw.term(.{ .perform = .{ .effect = op.id, .payload = v.id } }), op.result);
    }
    pub fn product(
        self: *Body,
        schema: *const Schema,
        fields: []const Argument,
    ) Error!*const Value {
        const c = bodyData(self).context;
        const id = try c.schemaId(schema);
        if (contextData(c).raw.schemas.items[@intCast(id)] != .product)
            return c.reject(error.InvalidCategory, "product", "requires a record schema");
        errdefer |err| c.poison(err);
        return self.bind(try contextData(c).raw.pure(try contextData(c).raw.primitive(id, .product, try self.arguments(data(SchemaData, schema).fields, fields), 0)), schema);
    }
    pub fn field(self: *Body, product_value: *const Value, name: []const u8) Error!*const Value {
        const c = bodyData(self).context;
        const v = try self.useValue(product_value);
        const s = data(SchemaData, v.schema);
        if (contextData(c).raw.schemas.items[@intCast(s.id)] != .product)
            return c.reject(error.InvalidCategory, "field", "requires a named record value");
        for (s.fields, 0..) |item, index| if (std.mem.eql(u8, item.name, name)) {
            errdefer |err| c.poison(err);
            return self.bind(try contextData(c).raw.pure(try contextData(c).raw.primitive(try c.schemaId(item.schema), .field, &.{v.id}, index)), item.schema);
        };
        return c.reject(error.UnknownName, "field", "unknown named product field");
    }
    pub fn closureBody(self: *Body, function_handle: *const Function) Error!*Body {
        try self.ready();
        return bodyData(self).context.nestedBody(function_handle, bodyData(self).scope);
    }
    fn visibleFunction(self: *Body, function_handle: *const Function) Error!*const FunctionData {
        try self.ready();
        const f = data(FunctionData, function_handle);
        try bodyData(self).context.functionVisible(f, bodyData(self).scope);
        return f;
    }
    fn noteForwardUse(self: *Body, declaration: *const Function, anchor: @FieldType(PublicationUse, "anchor")) Error!void {
        // A declaration may acquire its lexical parent after this use. Only
        // published uses constrain that eventual parent; abandoned AST does not.
        if (data(FunctionData, declaration).scope == null)
            try bodyData(self).context.notePublication(.{ .anchor = anchor, .contract = .{
                .function_scope = .{ .declaration = declaration, .scope = bodyData(self).scope },
            } });
    }
    pub fn lambda(
        self: *Body,
        function_handle: *const Function,
        schema: *const Schema,
    ) Error!*const Value {
        const c = bodyData(self).context;
        const f = try self.visibleFunction(function_handle);
        const id = try c.schemaId(schema);
        const shape = contextData(c).raw.schemas.items[@intCast(id)];
        if (shape != .internal or shape.internal != .computation)
            return c.reject(error.InvalidCategory, f.name, "lambda requires callable schema");
        const info = data(SchemaData, schema);
        if (f.callable_schema) |declared| try c.same(declared, schema);
        try c.same(f.result, info.result orelse return error.InvalidSchema);
        if (f.parameters.len != info.fields.len)
            return c.reject(error.SchemaMismatch, f.name, "callable parameter count differs from declaration");
        for (f.parameters, info.fields) |actual, expected| {
            if (!std.mem.eql(u8, actual.name, expected.name))
                return c.reject(error.SchemaMismatch, f.name, "callable parameter names differ from declaration");
            try c.same(expected.schema, actual.schema);
        }
        errdefer |err| c.poison(err);
        const value_id = try contextData(c).raw.lambda(f.id, id);
        try self.noteForwardUse(function_handle, .{ .value = value_id });
        try contextData(c).lambda_schemas.put(contextData(c).raw.allocator(), value_id, schema);
        return self.bind(try contextData(c).raw.pure(value_id), schema);
    }
    pub fn apply(
        self: *Body,
        callable_value: *const Value,
        args: []const Argument,
    ) Error!*const Value {
        const v = try self.useValue(callable_value);
        const c = bodyData(self).context;
        const info = data(SchemaData, v.schema);
        const shape = contextData(c).raw.schemas.items[@intCast(info.id)];
        if (shape != .internal or shape.internal != .computation)
            return c.reject(error.InvalidCategory, "apply", "value is not callable");
        errdefer |err| c.poison(err);
        return self.bind(try contextData(c).raw.term(.{
            .apply = .{
                .computation = v.id,
                .arguments = try self.arguments(info.fields, args),
            },
        }), info.result orelse return error.InvalidSchema);
    }
    pub fn performLocal(
        self: *Body,
        operation_handle: *const Operation,
        capability_value: *const Value,
        payload: *const Value,
    ) Error!*const Value {
        return self.performScoped(operation_handle, capability_value, payload, &.{});
    }
    pub fn performScoped(
        self: *Body,
        operation_handle: *const Operation,
        capability_value: *const Value,
        payload: *const Value,
        bodies: []const Argument,
    ) Error!*const Value {
        const c = bodyData(self).context;
        const op = data(OperationData, operation_handle);
        try c.origin(op.owner);
        const cap = try self.useValue(capability_value);
        const expected_capability = try c.capability(operation_handle);
        c.same(expected_capability, cap.schema) catch |err| {
            contextData(c).diagnostic.entity = op.name;
            contextData(c).diagnostic.relationship = "capability belongs to a different operation instance";
            return err;
        };
        const v = try self.useValue(payload);
        try c.same(op.payload, v.schema);
        errdefer |err| c.poison(err);
        return self.bind(try contextData(c).raw.term(.{
            .perform = .{
                .effect = op.id,
                .payload = v.id,
                .capability = cap.id,
                .bodies = try self.arguments(op.bodies, bodies),
            },
        }), op.result);
    }
    pub fn package(self: *Body, resumption: *const Value) Error!*const Value {
        const token = try self.useValue(resumption);
        const c = bodyData(self).context;
        const schema = try c.suspensionPackage(token.schema);
        errdefer |err| c.poison(err);
        const value = try contextData(c).raw.primitive(
            try c.schemaId(schema),
            .package,
            &.{token.id},
            0,
        );
        return self.bind(try contextData(c).raw.pure(value), schema);
    }
    pub fn unpack(self: *Body, package_value: *const Value) Error!*const Value {
        const packaged = try self.useValue(package_value);
        const c = bodyData(self).context;
        const info = data(SchemaData, packaged.schema);
        const shape = contextData(c).raw.schemas.items[@intCast(info.id)];
        if (shape != .internal or shape.internal != .suspension_package)
            return c.reject(error.InvalidCategory, "unpack", "requires a suspension package");
        const result = info.result orelse return error.InvalidSchema;
        errdefer |err| c.poison(err);
        const value = try contextData(c).raw.primitive(
            try c.schemaId(result),
            .unpack,
            &.{packaged.id},
            0,
        );
        return self.bind(try contextData(c).raw.pure(value), result);
    }
    pub fn resumeValue(
        self: *Body,
        resumption: *const Value,
        reply: *const Value,
    ) Error!*const Value {
        const token = try self.useValue(resumption);
        const v = try self.useValue(reply);
        const c = bodyData(self).context;
        const info = data(SchemaData, token.schema);
        const shape = contextData(c).raw.schemas.items[@intCast(info.id)];
        if (shape != .internal or shape.internal != .resumption)
            return c.reject(error.InvalidCategory, "resume", "value is not a resumption");
        if (info.fields.len != 1) return error.InvalidSchema;
        try c.same(info.fields[0].schema, v.schema);
        errdefer |err| c.poison(err);
        return self.bind(try contextData(c).raw.term(.{ .resume_value = .{ .resumption = token.id, .argument = v.id } }), info.result orelse return error.InvalidSchema);
    }
    pub fn handleWith(
        self: *Body,
        handler_handle: *const Handler,
        callable_value: *const Value,
        state: []const Argument,
    ) Error!*const Value {
        return self.handleWithArguments(handler_handle, callable_value, &.{}, state);
    }
    pub fn handleWithArguments(self: *Body, handler_handle: *const Handler, callable_value: *const Value, args: []const Argument, state: []const Argument) Error!*const Value {
        const c = bodyData(self).context;
        const h = data(HandlerData, handler_handle);
        try c.origin(h.owner);
        const v = try self.useValue(callable_value);
        try c.same(h.body_schema, v.schema);
        errdefer |err| c.poison(err);
        return self.bind(try contextData(c).raw.term(.{
            .handle = .{
                .handler = h.id,
                .body = v.id,
                .arguments = try self.arguments(data(SchemaData, h.body_schema).fields[h.clauses.len..], args),
                .state = try self.arguments(h.state, state),
            },
        }), h.answer);
    }
    pub fn checkedAdd(self: *Body, left: *const Value, right: *const Value, failure: *const FailureLiteral) Error!*const Value {
        return self.checked(.add, left, right, .{ .overflow = failure });
    }
    pub fn checked(
        self: *Body,
        operation: Arithmetic,
        left: *const Value,
        right: *const Value,
        failures: ArithmeticFailures,
    ) Error!*const Value {
        const c = bodyData(self).context;
        const a = try self.useValue(left);
        const b = try self.useValue(right);
        try c.same(a.schema, b.schema);
        const schema = try c.schemaId(a.schema);
        switch (contextData(c).raw.schemas.items[@intCast(schema)]) {
            .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64 => {},
            else => return c.reject(error.InvalidCategory, "arithmetic", "requires scalar integer operands"),
        }
        const opcode: p.Opcode = switch (operation) {
            .add => .integer_add,
            .subtract => .integer_sub,
            .multiply => .integer_mul,
            .divide => .integer_div,
            .remainder => .integer_rem,
        };
        const overflow = data(FailureLiteralData, failures.overflow);
        try c.origin(overflow.owner);
        var faults: [2]p.InstructionFailure = undefined;
        faults[0] = .{ .kind = .arithmetic_overflow, .value = overflow.literal };
        const division = operation == .divide or operation == .remainder;
        if (division) {
            const zero = data(FailureLiteralData, failures.division_by_zero orelse
                return c.reject(error.InvalidCategory, "division", "requires an authored zero-divisor failure"));
            try c.origin(zero.owner);
            faults[1] = .{ .kind = .division_by_zero, .value = zero.literal };
        } else if (failures.division_by_zero != null)
            return c.reject(error.InvalidCategory, "arithmetic", "zero-divisor failure only applies to division or remainder");
        errdefer |err| c.poison(err);
        const value_id = try contextData(c).raw.value(.{ .schema = schema, .expression = .{ .primitive = .{
            .opcode = opcode,
            .operands = &.{ a.id, b.id },
            .failures = faults[0..@as(usize, if (division) 2 else 1)],
        } } });
        try c.notePublication(.{ .anchor = .{ .value = value_id }, .contract = .{ .failure = data(ValueData, overflow.value).schema } });
        if (division) try c.notePublication(.{ .anchor = .{ .value = value_id }, .contract = .{ .failure = data(ValueData, data(FailureLiteralData, failures.division_by_zero.?).value).schema } });
        return self.bind(try contextData(c).raw.pure(value_id), a.schema);
    }
    /// Consume one product and bind its fields in the current lexical body.
    pub fn destructure(self: *Body, product_value: *const Value) Error!*const ProductParts {
        const tuple = try self.useValue(product_value);
        const c = bodyData(self).context;
        const info = data(SchemaData, tuple.schema);
        if (contextData(c).raw.schemas.items[@intCast(info.id)] != .product)
            return c.reject(error.InvalidCategory, "destructure", "requires a product value");
        errdefer |err| c.poison(err);
        const allocator = contextData(c).raw.allocator();
        const variables = try allocator.alloc(p.Id, info.fields.len);
        const fields = try allocator.alloc(Argument, info.fields.len);
        for (info.fields, variables, fields) |named, *variable, *out| {
            variable.* = try contextData(c).raw.variable(try c.schemaId(named.schema));
            out.* = .{ .name = named.name, .value = try self.makeValue(
                try contextData(c).raw.reference(variable.*),
                named.schema,
            ) };
        }
        const result = handle(ProductParts, try c.save(ProductPartsData, .{
            .body = self,
            .fields = fields,
        }));
        try bodyData(self).bindings.append(allocator, .{
            .unpack = .{ .value = tuple.id, .variables = variables },
        });
        return result;
    }
    pub fn equal(self: *Body, left: *const Value, right: *const Value) Error!*const Value {
        const a = try self.useValue(left);
        const b = try self.useValue(right);
        const c = bodyData(self).context;
        try c.same(a.schema, b.schema);
        errdefer |err| c.poison(err);
        const boolean = try c.scalar(bool);
        return self.bind(try contextData(c).raw.pure(try contextData(c).raw.primitive(
            try c.schemaId(boolean),
            .equal,
            &.{ a.id, b.id },
            0,
        )), boolean);
    }
    pub fn less(self: *Body, left: *const Value, right: *const Value) Error!*const Value {
        const lhs = try self.useValue(left);
        const rhs = try self.useValue(right);
        const c = bodyData(self).context;
        try c.same(lhs.schema, rhs.schema);
        const id = try c.schemaId(lhs.schema);
        switch (contextData(c).raw.schemas.items[@intCast(id)]) {
            .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64 => {},
            else => return c.reject(error.InvalidCategory, "less", "requires matching integer values"),
        }
        errdefer |err| c.poison(err);
        const boolean = try c.scalar(bool);
        return self.bind(try contextData(c).raw.pure(try contextData(c).raw.primitive(try c.schemaId(boolean), .less, &.{ lhs.id, rhs.id }, 0)), boolean);
    }
    pub fn sequenceLength(self: *Body, sequence: *const Value) Error!*const Value {
        const value = try self.useValue(sequence);
        const c = bodyData(self).context;
        const shape = contextData(c).raw.schemas.items[@intCast(try c.schemaId(value.schema))];
        if (shape != .seq) return c.reject(error.InvalidCategory, "length", "requires an unbounded sequence");
        errdefer |err| c.poison(err);
        const integer = try c.scalar(u64);
        return self.bind(try contextData(c).raw.pure(try contextData(c).raw.primitive(try c.schemaId(integer), .sequence_length, &.{value.id}, 0)), integer);
    }
    pub fn sequenceGet(self: *Body, sequence: *const Value, index: *const Value) Error!*const Value {
        const value = try self.useValue(sequence);
        const offset = try self.useValue(index);
        const c = bodyData(self).context;
        const info = data(SchemaData, value.schema);
        if (contextData(c).raw.schemas.items[@intCast(info.id)] != .seq)
            return c.reject(error.InvalidCategory, "sequence get", "requires an unbounded sequence");
        try c.same(try c.scalar(u64), offset.schema);
        errdefer |err| c.poison(err);
        const optional = try c.alternatives(&.{ .{ .name = "none", .schema = try c.scalar(void) }, .{ .name = "some", .schema = info.result orelse return error.InvalidSchema } });
        return self.bind(try contextData(c).raw.pure(try contextData(c).raw.primitive(try c.schemaId(optional), .sequence_get, &.{ value.id, offset.id }, 0)), optional);
    }
    pub fn yieldNow(self: *Body) Error!*const Value {
        try self.ready();
        const c = bodyData(self).context;
        errdefer |err| c.poison(err);
        const unit = try c.scalar(void);
        return self.bind(try contextData(c).raw.term(.{ .yield_then = try contextData(c).raw.pure(try contextData(c).raw.constant(void, {})) }), unit);
    }
    pub fn newCell(self: *Body, schema: *const Schema, region: *const Value, initial: *const Value) Error!*const Value {
        try self.ready();
        const c = bodyData(self).context;
        const id = try c.schemaId(schema);
        const shape = contextData(c).raw.schemas.items[@intCast(id)];
        if (shape != .internal or shape.internal != .cell)
            return c.reject(error.InvalidCategory, "cell", "requires a cell schema");
        const token = try self.useValue(region);
        const token_shape = contextData(c).raw.schemas.items[@intCast(try c.schemaId(token.schema))];
        if (token_shape != .internal or token_shape.internal != .region or token_shape.internal.region != shape.internal.cell.region)
            return c.reject(error.SchemaMismatch, "cell", "allocation requires its region token");
        const value = try self.useValue(initial);
        try c.same(data(SchemaData, schema).result orelse return error.InvalidSchema, value.schema);
        errdefer |err| c.poison(err);
        return self.bind(try contextData(c).raw.pure(try contextData(c).raw.primitive(id, .cell_new, &.{ token.id, value.id }, 0)), schema);
    }
    pub fn readCell(self: *Body, cell_value: *const Value) Error!*const Value {
        const value = try self.useValue(cell_value);
        const c = bodyData(self).context;
        const info = data(SchemaData, value.schema);
        const shape = contextData(c).raw.schemas.items[@intCast(info.id)];
        if (shape != .internal or shape.internal != .cell)
            return c.reject(error.InvalidCategory, "cell", "read requires a cell");
        const element = info.result orelse return error.InvalidSchema;
        errdefer |err| c.poison(err);
        return self.bind(try contextData(c).raw.pure(try contextData(c).raw.primitive(try c.schemaId(element), .cell_get, &.{value.id}, 0)), element);
    }
    pub fn writeCell(self: *Body, cell_value: *const Value, new_value: *const Value) Error!*const Value {
        const target = try self.useValue(cell_value);
        const value = try self.useValue(new_value);
        const c = bodyData(self).context;
        const info = data(SchemaData, target.schema);
        const shape = contextData(c).raw.schemas.items[@intCast(info.id)];
        if (shape != .internal or shape.internal != .cell)
            return c.reject(error.InvalidCategory, "cell", "write requires a cell");
        try c.same(info.result orelse return error.InvalidSchema, value.schema);
        errdefer |err| c.poison(err);
        const unit = try c.scalar(void);
        return self.bind(try contextData(c).raw.pure(try contextData(c).raw.primitive(try c.schemaId(unit), .cell_set, &.{ target.id, value.id }, 0)), unit);
    }
    pub fn append(self: *Body, sequence: *const Value, element: *const Value) Error!*const Value {
        const seq = try self.useValue(sequence);
        const item = try self.useValue(element);
        const c = bodyData(self).context;
        const info = data(SchemaData, seq.schema);
        if (contextData(c).raw.schemas.items[@intCast(info.id)] != .seq)
            return c.reject(error.InvalidCategory, "append", "requires an unbounded sequence");
        try c.same(info.result orelse return error.InvalidSchema, item.schema);
        errdefer |err| c.poison(err);
        return self.bind(try contextData(c).raw.pure(try contextData(c).raw.primitive(
            info.id,
            .sequence_append,
            &.{ seq.id, item.id },
            0,
        )), seq.schema);
    }
    pub fn pop(self: *Body, sequence: *const Value) Error!*const Value {
        const seq = try self.useValue(sequence);
        const c = bodyData(self).context;
        const info = data(SchemaData, seq.schema);
        if (contextData(c).raw.schemas.items[@intCast(info.id)] != .seq)
            return c.reject(error.InvalidCategory, "pop", "requires an unbounded sequence");
        errdefer |err| c.poison(err);
        const item = try c.record(&.{
            .{ .name = "head", .schema = info.result orelse return error.InvalidSchema },
            .{ .name = "tail", .schema = seq.schema },
        });
        const result = try c.alternatives(&.{
            .{ .name = "empty", .schema = try c.scalar(void) },
            .{ .name = "item", .schema = item },
        });
        return self.bind(try contextData(c).raw.pure(try contextData(c).raw.primitive(
            try c.schemaId(result),
            .sequence_pop,
            &.{seq.id},
            0,
        )), result);
    }
    pub fn sequenceValue(
        self: *Body,
        schema: *const Schema,
        items: []const *const Value,
    ) Error!*const Value {
        const c = bodyData(self).context;
        const id = try c.schemaId(schema);
        const shape = contextData(c).raw.schemas.items[@intCast(id)];
        if (shape != .seq) return c.reject(error.InvalidCategory, "sequence", "requires a sequence schema and matching element metadata");
        const element = data(SchemaData, schema).result orelse return c.reject(error.InvalidSchema, "sequence", "requires a sequence schema and matching element metadata");
        errdefer |err| c.poison(err);
        const ids = try contextData(c).raw.allocator().alloc(p.Id, items.len);
        for (items, ids) |item, *out| {
            const v = try self.useValue(item);
            try c.same(element, v.schema);
            out.* = v.id;
        }
        return self.bind(try contextData(c).raw.pure(try contextData(c).raw.primitive(id, .sequence, ids, 0)), schema);
    }
    pub fn concat(self: *Body, left: *const Value, right: *const Value) Error!*const Value {
        const a = try self.useValue(left);
        const b = try self.useValue(right);
        const c = bodyData(self).context;
        try c.same(a.schema, b.schema);
        const id = try c.schemaId(a.schema);
        if (contextData(c).raw.schemas.items[@intCast(id)] != .seq) return c.reject(error.InvalidCategory, "concatenation", "requires sequence operands");
        errdefer |err| c.poison(err);
        return self.bind(try contextData(c).raw.pure(try contextData(c).raw.primitive(id, .sequence_concat, &.{ a.id, b.id }, 0)), a.schema);
    }
    pub fn variant(
        self: *Body,
        schema: *const Schema,
        name: []const u8,
        payload_value: *const Value,
    ) Error!*const Value {
        const c = bodyData(self).context;
        const id = try c.schemaId(schema);
        const v = try self.useValue(payload_value);
        if (contextData(c).raw.schemas.items[@intCast(id)] != .sum) return c.reject(error.InvalidCategory, "variant", "requires a tagged alternative schema");
        for (data(SchemaData, schema).fields, 0..) |item, index| {
            if (!std.mem.eql(u8, item.name, name)) continue;
            try c.same(item.schema, v.schema);
            errdefer |err| c.poison(err);
            return self.bind(try contextData(c).raw.pure(try contextData(c).raw.primitive(id, .variant, &.{v.id}, index)), schema);
        }
        return c.reject(error.UnknownName, "variant", "unknown alternative");
    }
    pub fn caseOf(self: *Body, sum: *const Value, name: []const u8) Error!*const Case {
        const v = try self.useValue(sum);
        const c = bodyData(self).context;
        const schema = data(SchemaData, v.schema);
        if (contextData(c).raw.schemas.items[@intCast(schema.id)] != .sum) return c.reject(error.InvalidCategory, "match case", "requires a tagged alternative value");
        for (schema.fields, 0..) |item, index| {
            if (!std.mem.eql(u8, item.name, name)) continue;
            errdefer |err| c.poison(err);
            const arm = try self.branch();
            const variable = try contextData(c).raw.variable(try c.schemaId(item.schema));
            const payload = try arm.makeValue(try contextData(c).raw.reference(variable), item.schema);
            return handle(Case, try c.save(CaseData, .{
                .body = arm,
                .payload = payload,
                .sum = sum,
                .index = index,
                .variable = variable,
            }));
        }
        return c.reject(error.UnknownName, "match", "unknown alternative");
    }
    pub fn match(
        self: *Body,
        sum: *const Value,
        cases: []const *const FinishedCase,
    ) Error!*const Value {
        const v = try self.useValue(sum);
        const c = bodyData(self).context;
        const schema = data(SchemaData, v.schema);
        if (contextData(c).raw.schemas.items[@intCast(schema.id)] != .sum or
            cases.len != schema.fields.len or cases.len == 0) return c.reject(error.InvalidCategory, "match", "cases must cover this value once and return compatible schemas");
        errdefer |err| c.poison(err);
        const RawCase = @typeInfo(@FieldType(source.ast.Term, "match_sum")).@"struct".fields[1].type;
        const raw_cases = try contextData(c).raw.allocator().alloc(@typeInfo(RawCase).pointer.child, cases.len);
        const seen = try contextData(c).raw.allocator().alloc(bool, cases.len);
        @memset(seen, false);
        var result: ?*const Schema = null;
        for (cases) |finished| {
            const f = data(FinishedCaseData, finished);
            const arm = data(CaseData, f.case);
            const computation = data(ComputationData, f.computation);
            try c.origin(computation.owner);
            if (arm.sum != sum or bodyData(arm.body).scope.parent != bodyData(self).scope or
                arm.index >= cases.len or seen[arm.index]) return @as(Error!*const Value, c.reject(error.InvalidBranch, "match", "cases must cover this value once and return compatible schemas"));
            if (result) |expected| try c.same(expected, computation.schema);
            result = computation.schema;
            seen[arm.index] = true;
            raw_cases[arm.index] = .{ .variable = arm.variable, .body = computation.id };
        }
        return self.bind(try contextData(c).raw.term(.{ .match_sum = .{ .value = v.id, .cases = raw_cases } }), result.?);
    }
    pub fn resumeWith(
        self: *Body,
        resumption: *const Value,
        reply: *const Value,
        successor: *const Handler,
        state: []const Argument,
    ) Error!*const Value {
        const token = try self.useValue(resumption);
        const v = try self.useValue(reply);
        const c = bodyData(self).context;
        const info = data(SchemaData, token.schema);
        const shape = contextData(c).raw.schemas.items[@intCast(info.id)];
        if (shape != .internal or shape.internal != .resumption) return c.reject(error.InvalidCategory, "resumption", "resumeWith requires a shallow token and compatible successor");
        const h = data(HandlerData, successor);
        try c.origin(h.owner);
        if (shape.internal.resumption.mode != .shallow or info.fields.len != 1)
            return c.reject(error.InvalidCategory, "resumption", "resumeWith requires a shallow token and compatible successor");
        try c.same(info.fields[0].schema, v.schema);
        try c.same(info.result orelse return c.reject(error.InvalidSchema, "resumption", "resumeWith requires a shallow token and compatible successor"), h.input);
        errdefer |err| c.poison(err);
        return self.bind(try contextData(c).raw.term(.{
            .resume_with = .{
                .resumption = token.id,
                .argument = v.id,
                .handler = h.id,
                .state = try self.arguments(h.state, state),
            },
        }), h.answer);
    }
    pub fn dispose(self: *Body, owned: *const Value) Error!*const Value {
        const v = try self.useValue(owned);
        const c = bodyData(self).context;
        errdefer |err| c.poison(err);
        return self.bind(try contextData(c).raw.term(.{ .dispose = v.id }), try c.scalar(void));
    }
    pub fn withRegion(
        self: *Body,
        region_handle: *const Region,
        work: *const Value,
        args: []const Argument,
    ) Error!*const Value {
        const c = bodyData(self).context;
        const r = data(RegionData, region_handle);
        try c.origin(r.owner);
        const v = try self.useValue(work);
        const info = data(SchemaData, v.schema);
        const shape = contextData(c).raw.schemas.items[@intCast(info.id)];
        if (shape != .internal or shape.internal != .computation) return c.reject(error.InvalidCategory, "region", "requires a callable with the matching implicit region parameter");
        if (info.fields.len == 0) return c.reject(error.SchemaMismatch, "region", "requires a callable with the matching implicit region parameter");
        const token_id = try c.schemaId(info.fields[0].schema);
        const token = contextData(c).raw.schemas.items[@intCast(token_id)];
        if (token != .internal or token.internal != .region or token.internal.region != r.id)
            return c.reject(error.SchemaMismatch, "region", "body belongs to another region");
        errdefer |err| c.poison(err);
        return self.bind(try contextData(c).raw.term(.{
            .with_region = .{
                .region = r.id,
                .body = v.id,
                .arguments = try self.arguments(info.fields[1..], args),
            },
        }), info.result orelse return @as(Error!*const Value, c.reject(error.InvalidSchema, "region", "requires a callable with the matching implicit region parameter")));
    }
    pub fn protect(
        self: *Body,
        work: *const Value,
        cleanup: *const Value,
        args: []const Argument,
    ) Error!*const Value {
        const v = try self.useValue(work);
        const finalizer = try self.useValue(cleanup);
        const c = bodyData(self).context;
        const info = data(SchemaData, v.schema);
        const shape = contextData(c).raw.schemas.items[@intCast(info.id)];
        if (shape != .internal or shape.internal != .computation) return c.reject(error.InvalidCategory, "protection", "requires callable body and cleanup contracts");
        const cleanup_shape = contextData(c).raw.schemas.items[@intCast(data(SchemaData, finalizer.schema).id)];
        if (cleanup_shape != .internal or cleanup_shape.internal != .computation)
            return c.reject(error.InvalidCategory, "protection", "requires callable body and cleanup contracts");
        const cleanup_info = data(SchemaData, finalizer.schema);
        if (cleanup_info.fields.len != 1)
            return c.reject(error.SchemaMismatch, "cleanup", "requires one exit-information parameter");
        errdefer |err| c.poison(err);
        const term = try contextData(c).raw.term(.{
            .protect = .{
                .body = v.id,
                .cleanup = finalizer.id,
                .arguments = try self.arguments(info.fields, args),
            },
        });
        try c.notePublication(.{ .anchor = .{ .term = term }, .contract = .{ .cleanup = cleanup_info.fields[0].schema } });
        return self.bind(term, info.result orelse return @as(Error!*const Value, c.reject(error.InvalidSchema, "protection", "requires callable body and cleanup contracts")));
    }
    pub fn packResource(self: *Body, schema: *const Schema, representation: *const Value) Error!*const Value {
        try self.ready();
        const c = bodyData(self).context;
        const id = try c.schemaId(schema);
        const shape = contextData(c).raw.schemas.items[@intCast(id)];
        if (shape != .internal or shape.internal != .abstract_resource)
            return c.reject(error.InvalidCategory, "resource pack", "requires a nominal resource schema");
        const value = try self.useValue(representation);
        try c.same(data(SchemaData, schema).result orelse return error.InvalidSchema, value.schema);
        errdefer |err| c.poison(err);
        return self.bind(try contextData(c).raw.pure(try contextData(c).raw.primitive(id, .resource_pack, &.{value.id}, 0)), schema);
    }
    pub fn unpackResource(self: *Body, resource_value: *const Value) Error!*const Value {
        const value = try self.useValue(resource_value);
        const c = bodyData(self).context;
        var info = data(SchemaData, value.schema);
        var shape = contextData(c).raw.schemas.items[@intCast(info.id)];
        if (shape == .internal and shape.internal == .borrowed) {
            info = data(SchemaData, info.result orelse return error.InvalidSchema);
            shape = contextData(c).raw.schemas.items[@intCast(info.id)];
        }
        if (shape != .internal or shape.internal != .abstract_resource)
            return c.reject(error.InvalidCategory, "resource unpack", "requires an owned or borrowed nominal resource");
        const representation = info.result orelse return error.InvalidSchema;
        errdefer |err| c.poison(err);
        return self.bind(try contextData(c).raw.pure(try contextData(c).raw.primitive(try c.schemaId(representation), .resource_unpack, &.{value.id}, 0)), representation);
    }
    /// Transfer an owner to cleanup; the body receives only its scoped loan.
    pub fn bracket(self: *Body, resource_value: *const Value, region_handle: *const Region, work: *const Value, cleanup: *const Value, args: []const Argument) Error!*const Value {
        const owned = try self.useValue(resource_value);
        const v = try self.useValue(work);
        const finalizer = try self.useValue(cleanup);
        const c = bodyData(self).context;
        const r = data(RegionData, region_handle);
        try c.origin(r.owner);
        const resource_shape = contextData(c).raw.schemas.items[@intCast(try c.schemaId(owned.schema))];
        if (resource_shape != .internal or resource_shape.internal != .abstract_resource)
            return c.reject(error.InvalidCategory, "bracket", "requires an owned nominal resource");
        const info = data(SchemaData, v.schema);
        const cleanup_info = data(SchemaData, finalizer.schema);
        const work_shape = contextData(c).raw.schemas.items[@intCast(info.id)];
        const cleanup_shape = contextData(c).raw.schemas.items[@intCast(cleanup_info.id)];
        if (work_shape != .internal or work_shape.internal != .computation or cleanup_shape != .internal or cleanup_shape.internal != .computation)
            return c.reject(error.InvalidCategory, "bracket", "requires callable body and cleanup contracts");
        if (info.fields.len == 0 or cleanup_info.fields.len != 2)
            return c.reject(error.SchemaMismatch, "bracket", "requires a body loan and cleanup exit-info/owner parameters");
        try c.same(try c.borrowed(owned.schema, region_handle), info.fields[0].schema);
        try c.same(owned.schema, cleanup_info.fields[1].schema);
        try c.same(try c.scalar(void), cleanup_info.result orelse return error.InvalidSchema);
        errdefer |err| c.poison(err);
        const term = try contextData(c).raw.term(.{ .protect = .{
            .body = v.id,
            .cleanup = finalizer.id,
            .resource = owned.id,
            .loan_region = r.id,
            .arguments = try self.arguments(info.fields[1..], args),
        } });
        try c.notePublication(.{ .anchor = .{ .term = term }, .contract = .{ .cleanup = cleanup_info.fields[0].schema } });
        return self.bind(term, info.result orelse return error.InvalidSchema);
    }
    pub fn branch(self: *Body) Error!*Body {
        try self.ready();
        return @ptrCast(try bodyData(self).context.save(BodyData, .{
            .context = bodyData(self).context,
            .scope = try bodyData(self).context.save(Scope, .{ .parent = bodyData(self).scope }),
        }));
    }
    pub fn block(self: *Body, finished: *const Computation) Error!*const Value {
        try self.ready();
        const c = bodyData(self).context;
        const value = data(ComputationData, finished);
        try c.origin(value.owner);
        if (value.scope.parent != bodyData(self).scope) return c.reject(error.InvalidBranch, "block", "completed body must belong to this parent scope");
        return self.bind(value.id, value.schema);
    }
    pub fn conditional(
        self: *Body,
        condition: *const Value,
        when_true: *const Computation,
        when_false: *const Computation,
    ) Error!*const Value {
        const c = bodyData(self).context;
        const v = try self.useValue(condition);
        try c.same(try c.scalar(bool), v.schema);
        const a = data(ComputationData, when_true);
        const b = data(ComputationData, when_false);
        try c.origin(a.owner);
        try c.origin(b.owner);
        if (a.scope.parent != bodyData(self).scope or b.scope.parent != bodyData(self).scope or a.scope == b.scope)
            return c.reject(error.InvalidBranch, "conditional", "requires two direct child branches");
        try c.same(a.schema, b.schema);
        errdefer |err| c.poison(err);
        return self.bind(try contextData(c).raw.term(.{
            .conditional = .{ .condition = v.id, .when_true = a.id, .when_false = b.id },
        }), a.schema);
    }
    /// Close unused staging work. Abandoning a function leaves it undefined;
    /// module publication will reject it. Descendant bodies become unusable.
    pub fn abandon(self: *Body) void {
        bodyData(self).scope.active = false;
    }
    pub fn ret(self: *Body, result: *const Value) Error!*const Computation {
        const v = try self.useValue(result);
        const c = bodyData(self).context;
        errdefer |err| c.poison(err);
        const bindings = &bodyData(self).bindings;
        const expression = contextData(c).raw.values.items[@intCast(v.id)].expression;
        if (bindings.items.len != 0 and expression == .variable) {
            const last = bindings.items[bindings.items.len - 1];
            if (last == .bind and last.bind.variable == expression.variable) {
                // bind x = operation; return x is exactly operation in tail position.
                // Keep all preceding work; no other use or intervening effect moves.
                bindings.items.len -= 1;
                return self.finish(last.bind.term, v.schema);
            }
        }
        return self.finish(try contextData(c).raw.pure(v.id), v.schema);
    }
    /// Fail with an authored value and close this body. The result schema lets
    /// a failing branch compose with another branch that returns that type.
    /// Publication checks the failure value against the module failure contract.
    pub fn fail(
        self: *Body,
        result: *const Schema,
        failure: *const Value,
    ) Error!*const Computation {
        const value = try self.useValue(failure);
        const c = bodyData(self).context;
        _ = try c.schemaId(result);
        errdefer |err| c.poison(err);
        const term = try contextData(c).raw.term(.{ .fail = value.id });
        try c.notePublication(.{
            .anchor = .{ .term = term },
            .contract = .{ .failure = value.schema },
        });
        return self.finish(term, result);
    }
    fn finish(self: *Body, final: p.Id, schema: *const Schema) Error!*const Computation {
        const c = bodyData(self).context;
        errdefer |err| c.poison(err);
        var term = final;
        var index = bodyData(self).bindings.items.len;
        while (index != 0) {
            index -= 1;
            const binding = bodyData(self).bindings.items[index];
            term = switch (binding) {
                .bind => |value| try contextData(c).raw.bind(value.variable, value.term, term),
                .unpack => |value| try contextData(c).raw.term(.{ .unpack_product = .{
                    .value = value.value,
                    .variables = value.variables,
                    .body = term,
                } }),
            };
        }
        const computation = handle(Computation, try c.save(ComputationData, .{
            .owner = c,
            .id = term,
            .schema = schema,
            .scope = bodyData(self).scope,
        }));
        bodyData(self).scope.active = false;
        return computation;
    }
};

/// Explicit low-level integration. Numeric IDs have no recoverable historical
/// provenance. The caller promises they belong to contextData(c).raw; available bounds and
/// categories are checked. These adapters never certify raw source admission.
pub const interop = struct {
    pub fn builder(c: *Context) *source.Builder {
        return contextData(c).raw;
    }
    /// Adopt a raw literal with an explicit named schema. Raw ID provenance remains caller-owned.
    pub fn literalFailure(c: *Context, id: p.Id, expected: *const Schema) Error!*const FailureLiteral {
        try c.ready();
        if (id >= contextData(c).raw.values.items.len) return error.InvalidReference;
        if (contextData(c).raw.values.items[@intCast(id)].schema != try c.schemaId(expected))
            return error.SchemaMismatch;
        const literal = try contextData(c).raw.failureLiteral(id);
        errdefer |err| c.poison(err);
        const value = handle(Value, try c.save(ValueData, .{
            .owner = c,
            .id = id,
            .schema = expected,
            .scope = null,
        }));
        return handle(FailureLiteral, try c.save(FailureLiteralData, .{
            .owner = c,
            .value = value,
            .literal = literal,
        }));
    }

    pub fn scope(c: *Context) Error!*Body {
        try c.ready();
        return @ptrCast(try c.save(BodyData, .{ .context = c, .scope = try c.save(Scope, .{ .parent = null }) }));
    }
    pub fn adoptValue(body: *Body, id: p.Id, expected: *const Schema) Error!*const Value {
        try body.ready();
        const c = bodyData(body).context;
        if (id >= contextData(c).raw.values.items.len) return error.InvalidReference;
        if (contextData(c).raw.values.items[@intCast(id)].schema != try c.schemaId(expected)) return error.SchemaMismatch;
        const expression = contextData(c).raw.values.items[@intCast(id)].expression;
        if (expression == .variable or expression == .literal) return body.makeValue(id, expected);
        errdefer |err| c.poison(err);
        return body.bind(try contextData(c).raw.pure(id), expected);
    }
    pub fn valueId(body: *Body, item: *const Value) Error!p.Id {
        return (try body.useValue(item)).id;
    }
    pub fn term(body: *Body, id: p.Id, result: *const Schema) Error!*const Value {
        try body.ready();
        if (id >= contextData(bodyData(body).context).raw.terms.items.len) return error.InvalidReference;
        _ = try bodyData(body).context.schemaId(result);
        return body.bind(id, result);
    }
    pub fn computationId(c: *Context, item: *const Computation) Error!p.Id {
        const v = data(ComputationData, item);
        try c.origin(v.owner);
        return v.id;
    }
    pub fn schema(c: *Context, id: p.Id) Error!*const Schema {
        try c.ready();
        if (id >= contextData(c).raw.schemas.items.len) return error.InvalidSchema;
        if (contextData(c).imported.get(id)) |present| return present;
        errdefer |err| c.poison(err);
        const shape = contextData(c).raw.schemas.items[@intCast(id)];
        switch (shape) {
            .product, .sum, .seq => {},
            .internal => |inner| switch (inner) {
                .computation, .resumption, .borrowed, .suspension_package, .cell, .abstract_resource => {},
                else => return c.intern(id, &.{}),
            },
            else => return c.intern(id, &.{}),
        }
        // Install a stable placeholder before following recursive schema edges.
        const info = try c.save(SchemaData, .{ .owner = c, .id = id });
        const result = handle(Schema, info);
        try contextData(c).imported.put(contextData(c).raw.allocator(), id, result);
        const ids: []const p.Id = switch (shape) {
            .product => |v| v,
            .sum => |v| v,
            .internal => |v| if (v == .computation) v.computation.parameters else &.{},
            else => &.{},
        };
        info.fields = try positionalFields(c, ids);
        info.result = switch (shape) {
            .seq => |element| try schema(c, element),
            .internal => |v| switch (v) {
                .computation => |signature| try schema(c, signature.result),
                .resumption => |signature| try schema(c, signature.answer),
                .borrowed => |borrow| try schema(c, borrow.value),
                .suspension_package => |token| try schema(c, token),
                .cell => |cell_shape| try schema(c, cell_shape.element),
                .abstract_resource => |resource_id| if (resource_id < contextData(c).raw.resources.items.len)
                    try schema(c, contextData(c).raw.resources.items[@intCast(resource_id)].representation)
                else
                    return error.InvalidReference,
                else => null,
            },
            else => null,
        };
        if (shape == .internal and shape.internal == .resumption) {
            const input = try schema(c, shape.internal.resumption.input);
            info.fields = try c.fields(&.{.{ .name = "reply", .schema = input }});
        }
        const capture_ids: []const p.Id = if (shape == .internal) switch (shape.internal) {
            .computation => |signature| signature.capture_bound,
            .resumption => |signature| signature.capture_bound,
            else => &.{},
        } else &.{};
        const captures = try contextData(c).raw.allocator().alloc(*const Schema, capture_ids.len);
        for (capture_ids, captures) |child, *item| item.* = try schema(c, child);
        info.captures = captures;
        return result;
    }
    pub fn namedCallable(c: *Context, id: p.Id, names: []const []const u8) Error!*const Schema {
        const imported = try schema(c, id);
        const shape = contextData(c).raw.schemas.items[@intCast(id)];
        if (shape != .internal or shape.internal != .computation) return error.InvalidCategory;
        const info = data(SchemaData, imported);
        if (names.len != info.fields.len) return error.SchemaMismatch;
        errdefer |err| c.poison(err);
        const fields = try contextData(c).raw.allocator().alloc(Field, names.len);
        for (fields, names, info.fields) |*item, name, old| item.* = .{ .name = name, .schema = old.schema };
        return c.internComplete(id, fields, info.result, info.captures);
    }
    fn positionalFields(c: *Context, ids: []const p.Id) Error![]const Field {
        errdefer |err| c.poison(err);
        const fields = try contextData(c).raw.allocator().alloc(Field, ids.len);
        for (ids, fields, 0..) |child, *item, i| item.* = .{
            .name = try std.fmt.allocPrint(contextData(c).raw.allocator(), "{d}", .{i}),
            .schema = try schema(c, child),
        };
        return fields;
    }
    pub fn operation(c: *Context, id: p.Id) Error!*const Operation {
        try c.ready();
        if (id >= contextData(c).raw.effects.items.len) return error.InvalidEffect;
        const op = contextData(c).raw.effects.items[@intCast(id)];
        return handle(Operation, try c.save(OperationData, .{
            .owner = c,
            .id = id,
            .name = try c.label(op.identity),
            .payload = try schema(c, op.payload),
            .result = try schema(c, op.result),
            .external = op.external,
            .bodies = try positionalFields(c, op.bodies),
        }));
    }
    pub fn region(c: *Context, id: p.Id) Error!*const Region {
        try c.ready();
        if (id >= contextData(c).raw.region_count) return error.InvalidReference;
        return handle(Region, try c.save(RegionData, .{ .owner = c, .id = id }));
    }
    pub fn schemaId(c: *Context, value: *const Schema) Error!p.Id {
        return c.schemaId(value);
    }
    pub fn operationId(c: *Context, value: *const Operation) Error!p.Id {
        const item = data(OperationData, value);
        try c.origin(item.owner);
        return item.id;
    }
    pub fn functionId(c: *Context, value: *const Function) Error!p.Id {
        const item = data(FunctionData, value);
        try c.origin(item.owner);
        return item.id;
    }
    pub fn handlerId(c: *Context, value: *const Handler) Error!p.Id {
        const item = data(HandlerData, value);
        try c.origin(item.owner);
        return item.id;
    }
    pub fn resumptionSchema(c: *Context, value: *const Handler) Error!*const Schema {
        const item = data(HandlerData, value);
        try c.origin(item.owner);
        if (item.clauses.len != 1) return c.reject(error.InvalidCategory, "resumption", "select a clause through its function parameter");
        return item.clauses[0].resumption;
    }
    pub fn resultSchema(c: *Context, value: *const Schema) Error!*const Schema {
        _ = try c.schemaId(value);
        return data(SchemaData, value).result orelse error.InvalidSchema;
    }
};

/// Compatibility adapters retain the existing low-level error set.
pub fn sourceError(err: Error) source.Error {
    return switch (err) {
        error.ForeignHandle, error.OutOfScope, error.ClosedBody, error.PoisonedAuthoring, error.SchemaMismatch, error.UnknownName, error.DuplicateName, error.InvalidCategory, error.InvalidBranch, error.UndefinedBody, error.UndefinedSchema, error.SchemaAlreadyDefined => error.InvalidSource,
        else => |other| other,
    };
}
