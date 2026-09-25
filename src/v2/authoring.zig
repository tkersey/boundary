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
pub const Schema = opaque {
    pub fn fields(self: *const Schema) []const Field {
        return data(SchemaData, self).fields;
    }
    pub fn resultSchema(self: *const Schema) ?*const Schema {
        return data(SchemaData, self).result;
    }
    pub fn describe(self: *const Schema, writer: *std.Io.Writer) !void {
        const item = data(SchemaData, self);
        const shape = item.owner.raw.schemas.items[@intCast(item.id)];
        if (shape == .internal and shape.internal == .capability) {
            const instance = shape.internal.capability;
            if (instance >= item.owner.raw.effects.items.len)
                return writer.writeAll("capability(invalid instance)");
            return writer.print("capability({s}, instance {d})", .{
                item.owner.raw.effects.items[@intCast(instance)].identity, instance,
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
                @tagName(result_info.owner.raw.schemas.items[@intCast(result_info.id)]),
            });
        }
    }
};
pub const Operation = opaque {};
pub const Function = opaque {};
pub const Value = opaque {};
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
        return handle(FinishedCase, try item.body.context.save(FinishedCaseData, .{ .case = self, .computation = computation }));
    }
};
pub const FinishedCase = opaque {};
pub const CallableOptions = struct {
    use: p.Use,
    captures: []const *const Schema,
    regions: []const *const Region = &.{},
};
pub const HandlerOptions = struct {
    mode: p.Mode,
    use: p.Use,
    residual: []const *const Operation,
    escaping: []const *const Operation = &.{},
    captures: []const *const Schema,
    body_use: p.Use = .linear,
    body_captures: []const *const Schema = &.{},
    owned_regions: []const *const Region = &.{},
    borrowed_regions: []const *const Region = &.{},
    state: []const Field = &.{},
};
pub const Field = struct { name: []const u8, schema: *const Schema };
pub const Argument = struct { name: []const u8, value: *const Value };
pub const Arithmetic = enum { add, subtract, multiply, divide, remainder };
pub const ArithmeticFailures = struct {
    overflow: *const Value,
    division_by_zero: ?*const Value = null,
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
};
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
const ComputationData = struct {
    owner: *Context,
    id: p.Id,
    schema: *const Schema,
    scope: *Scope,
};
const HandlerData = struct {
    owner: *Context,
    id: p.Id,
    operation: *const Operation,
    input: *const Schema,
    answer: *const Schema,
    resumption: *const Schema,
    body_schema: *const Schema,
    returns: *const Function,
    clause: *const Function,
    state: []const Field,
};
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
    imported: std.AutoHashMapUnmanaged(p.Id, *const Schema) = .empty,
    functions: std.ArrayList(*const Function) = .empty,
    publication_uses: std.ArrayList(PublicationUse) = .empty,
    variable_schemas: std.AutoHashMapUnmanaged(p.Id, *const Schema) = .empty,
    lambda_schemas: std.AutoHashMapUnmanaged(p.Id, *const Schema) = .empty,
    handlers: std.ArrayList(*const Handler) = .empty,
    capture_failure: ?Error = null,

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
        errdefer |err| if (err == error.OutOfMemory) {
            self.poisoned = true;
        };
        if (!try self.compatible(expected, actual)) {
            self.diagnostic = .{
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
        const allocator = self.raw.arena.child_allocator;
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
        errdefer self.poisoned = true;
        for (self.schemas.items) |existing| {
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
            .captures = try self.raw.allocator().dupe(*const Schema, captures),
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
        errdefer self.poisoned = true;
        const ids = try self.raw.allocator().alloc(p.Id, names.len);
        for (names, ids) |item, *id| {
            id.* = try self.schemaId(item.schema);
            const shape = self.raw.schemas.items[@intCast(id.*)];
            if (shape != .internal or shape.internal != .computation) return self.reject(error.InvalidCategory, "scoped operation", "body operands must be callable");
        }
        const id = try self.raw.effect(.{
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
        errdefer self.poisoned = true;
        const id = try self.raw.effect(.{
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
        errdefer self.poisoned = true;
        const ids = try self.raw.allocator().alloc(p.Id, operations.len);
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
        errdefer self.poisoned = true;
        const result = handle(Function, try self.save(FunctionData, item));
        try self.functions.append(self.raw.allocator(), result);
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
        errdefer self.poisoned = true;
        const names = try self.fields(parameters);
        const ids = try self.raw.allocator().alloc(p.Id, names.len);
        for (names, ids) |field, *id| id.* = try self.schemaId(field.schema);
        const id = try self.raw.declare(ids, try self.schemaId(result), try self.row(allowed), &.{});
        return try self.saveFunction(.{
            .owner = self,
            .id = id,
            .name = try self.label(name),
            .parameters = names,
            .result = result,
        });
    }
    fn schemaIds(self: *Context, schemas: []const *const Schema) Error![]const p.Id {
        errdefer self.poisoned = true;
        const ids = try self.raw.allocator().alloc(p.Id, schemas.len);
        for (schemas, ids) |schema, *id| id.* = try self.schemaId(schema);
        return ids;
    }
    fn regionIds(self: *Context, regions: []const *const Region) Error![]const p.Id {
        errdefer self.poisoned = true;
        const ids = try self.raw.allocator().alloc(p.Id, regions.len);
        for (regions, ids) |region_handle, *id| {
            const r = data(RegionData, region_handle);
            try self.origin(r.owner);
            id.* = r.id;
        }
        return ids;
    }
    pub fn region(self: *Context) Error!*const Region {
        try self.ready();
        return handle(Region, try self.save(RegionData, .{ .owner = self, .id = self.raw.region() }));
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
        errdefer self.poisoned = true;
        const token = try self.intern(try self.raw.schema(.{ .internal = .{ .region = r.id } }), &.{});
        const names = try self.raw.allocator().alloc(Field, parameters.len + 1);
        names[0] = .{ .name = "region", .schema = token };
        @memcpy(names[1..], parameters);
        const regions = try self.raw.allocator().alloc(*const Region, options.regions.len + 1);
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
        errdefer self.poisoned = true;
        return self.internResult(try self.raw.schema(.{ .internal = .{ .borrowed = .{
            .value = try self.schemaId(schema),
            .region = r.id,
        } } }), &.{}, schema);
    }
    pub fn cleanupInfo(self: *Context, failure: *const Schema) Error!*const Schema {
        _ = try self.schemaId(failure);
        errdefer self.poisoned = true;
        const unit = try self.scalar(void);
        const text = try self.intern(try self.raw.schema(.text), &.{});
        const bytes = try self.intern(try self.raw.schema(.bytes), &.{});
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
        errdefer self.poisoned = true;
        const id = try self.raw.schema(.{ .seq = try self.schemaId(element) });
        return self.internResult(id, &.{}, element);
    }
    pub fn alternatives(self: *Context, cases: []const Field) Error!*const Schema {
        try self.ready();
        errdefer self.poisoned = true;
        const ids = try self.raw.allocator().alloc(p.Id, cases.len);
        for (cases, ids) |item, *id| id.* = try self.schemaId(item.schema);
        return self.intern(try self.raw.schema(.{ .sum = ids }), cases);
    }
    pub fn callable(
        self: *Context,
        parameters: []const Field,
        result: *const Schema,
        allowed: []const *const Operation,
        options: CallableOptions,
    ) Error!*const Schema {
        try self.ready();
        errdefer self.poisoned = true;
        const names = try self.fields(parameters);
        const ids = try self.raw.allocator().alloc(p.Id, names.len);
        for (names, ids) |item, *id| id.* = try self.schemaId(item.schema);
        const id = try self.raw.schema(.{ .internal = .{ .computation = .{
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
        errdefer self.poisoned = true;
        return self.intern(try self.raw.schema(.{ .internal = .{ .capability = op.id } }), &.{});
    }
    pub fn functionFor(
        self: *Context,
        name: []const u8,
        schema: *const Schema,
    ) Error!*const Function {
        const id = try self.schemaId(schema);
        const shape = self.raw.schemas.items[@intCast(id)];
        if (shape != .internal or shape.internal != .computation)
            return self.reject(error.InvalidCategory, "function", "requires callable schema");
        const info = data(SchemaData, schema);
        const result = info.result orelse return self.reject(error.InvalidSchema, "function declaration", "callable metadata lacks its result");
        errdefer self.poisoned = true;
        const signature = shape.internal.computation;
        return try self.saveFunction(.{
            .owner = self,
            .id = try self.raw.declare(signature.parameters, signature.result, signature.effects, signature.regions),
            .name = try self.label(name),
            .parameters = info.fields,
            .result = result,
            .callable_schema = schema,
        });
    }
    pub fn twice(self: *Context, schema: *const Schema) Error!*const Function {
        const id = try self.schemaId(schema);
        const shape = self.raw.schemas.items[@intCast(id)];
        if (shape != .internal or shape.internal != .computation) return self.reject(error.InvalidCategory, "twice", "requires a reusable zero-argument callable");
        const signature = shape.internal.computation;
        if (signature.parameters.len != 0 or signature.use != .reusable)
            return self.reject(error.InvalidOwnership, "twice", "requires a reusable zero-argument callable");
        const info = data(SchemaData, schema);
        const element = info.result orelse return self.reject(error.InvalidSchema, "twice", "requires a reusable zero-argument callable");
        const pair = try self.record(&.{
            .{ .name = "first", .schema = element },
            .{ .name = "second", .schema = element },
        });
        const effects = try self.raw.allocator().alloc(*const Operation, signature.effects.len);
        for (signature.effects, effects) |effect_id, *out| out.* = try interop.operation(self, effect_id);
        const function_handle = try self.function("twice", &.{.{ .name = "callable", .schema = schema }}, pair, effects);
        const f = data(FunctionData, function_handle);
        self.raw.functions.items[@intCast(f.id)].regions = signature.regions;
        const forward = try self.body(function_handle);
        const callable_value = try forward.parameter("callable");
        const first = try forward.apply(callable_value, &.{});
        const second = try forward.apply(callable_value, &.{});
        const result = try forward.product(pair, &.{
            .{ .name = "first", .value = first },
            .{ .name = "second", .value = second },
        });
        try self.define(function_handle, try forward.ret(result));
        return function_handle;
    }
    const HandlerFunctions = struct { returns: *const Function, clause: *const Function };
    fn handlerFunctions(
        self: *Context,
        op: *const OperationData,
        input: *const Schema,
        answer: *const Schema,
        resumption: *const Schema,
        options: HandlerOptions,
    ) Error!HandlerFunctions {
        const borrowed_ids = try self.regionIds(options.borrowed_regions);
        const returns_fields = try self.raw.allocator().alloc(Field, 1 + options.state.len);
        @memcpy(returns_fields[0..options.state.len], options.state);
        returns_fields[options.state.len] = .{ .name = "result", .schema = input };
        const clause_fields = try self.raw.allocator().alloc(Field, 2 + options.state.len + op.bodies.len);
        @memcpy(clause_fields[0..options.state.len], options.state);
        clause_fields[options.state.len] = .{ .name = "payload", .schema = op.payload };
        @memcpy(clause_fields[options.state.len + 1 .. clause_fields.len - 1], op.bodies);
        clause_fields[clause_fields.len - 1] = .{ .name = "resumption", .schema = resumption };
        const returns = try self.function("handler return", returns_fields, answer, options.residual);
        const clause = try self.function("operation clause", clause_fields, answer, options.residual);
        const rf = data(FunctionData, returns).id;
        const cf = data(FunctionData, clause).id;
        self.raw.functions.items[@intCast(rf)].regions = borrowed_ids;
        self.raw.functions.items[@intCast(cf)].regions = borrowed_ids;
        return .{ .returns = returns, .clause = clause };
    }
    fn handlerBodySchema(
        self: *Context,
        operation_handle: *const Operation,
        input: *const Schema,
        options: HandlerOptions,
    ) Error!*const Schema {
        const body_effects = try self.raw.allocator().alloc(*const Operation, options.residual.len + 1);
        @memcpy(body_effects[0..options.residual.len], options.residual);
        body_effects[options.residual.len] = operation_handle;
        return self.callable(&.{
            .{
                .name = "capability",
                .schema = try self.capability(operation_handle),
            },
        }, input, body_effects, .{
            .use = options.body_use,
            .captures = options.body_captures,
            .regions = options.borrowed_regions,
        });
    }
    pub fn handler(
        self: *Context,
        operation_handle: *const Operation,
        input: *const Schema,
        answer: *const Schema,
        options: HandlerOptions,
    ) Error!*const Handler {
        const op = data(OperationData, operation_handle);
        try self.origin(op.owner);
        if (op.external) return self.reject(error.InvalidCategory, op.name, "handler requires local operation");
        errdefer self.poisoned = true;
        const residual = try self.row(options.residual);
        const answer_id = try self.schemaId(answer);
        const resume_answer = if (options.mode == .deep) answer else input;
        const resume_id = try self.raw.schema(.{ .internal = .{ .resumption = .{
            .effect = op.id,
            .input = try self.schemaId(op.result),
            .answer = try self.schemaId(resume_answer),
            .effects = residual,
            .escaping = try self.row(options.escaping),
            .capture_bound = try self.schemaIds(options.captures),
            .handled = &.{op.id},
            .mode = options.mode,
            .use = options.use,
            .owned_regions = try self.regionIds(options.owned_regions),
        } } });
        const resumption = try self.internComplete(resume_id, &.{.{ .name = "reply", .schema = op.result }}, resume_answer, options.captures);
        const functions = try self.handlerFunctions(op, input, answer, resumption, options);
        const rf = data(FunctionData, functions.returns).id;
        const cf = data(FunctionData, functions.clause).id;
        const state_ids = try self.raw.allocator().alloc(p.Id, options.state.len);
        for (options.state, state_ids) |item, *id| id.* = try self.schemaId(item.schema);
        const body_schema = try self.handlerBodySchema(operation_handle, input, options);
        const result = handle(Handler, try self.save(HandlerData, .{
            .owner = self,
            .id = try self.raw.handler(.{
                .mode = options.mode,
                .input = try self.schemaId(input),
                .answer = answer_id,
                .return_function = rf,
                .clauses = &.{.{ .effect = op.id, .function = cf, .resumption = resume_id }},
                .state = state_ids,
                .effects = residual,
            }),
            .operation = operation_handle,
            .input = input,
            .answer = answer,
            .resumption = resumption,
            .body_schema = body_schema,
            .returns = functions.returns,
            .clause = functions.clause,
            .state = try self.fields(options.state),
        }));
        try self.handlers.append(self.raw.allocator(), result);
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
        const clause = try self.body(hd.clause);
        const reply = try clause.call(responder_function, &.{
            .{
                .name = f.parameters[0].name,
                .value = try clause.parameter("payload"),
            },
        });
        const resumed = try clause.resumeValue(try clause.parameter("resumption"), reply);
        try self.define(hd.clause, try clause.ret(resumed));
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
        return h.clause;
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
        const result = try self.save(Body, .{
            .context = self,
            .scope = scope,
            .function_handle = function_handle,
        });
        f.scope = scope;
        return result;
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
            self.diagnostic.entity = f.name;
            self.diagnostic.relationship = "body result differs from the function result";
            return err;
        };
        errdefer self.poisoned = true;
        try self.raw.define(f.id, c.id);
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
    fn lowerNamed(self: *Context, allocator: std.mem.Allocator, module_value: source.Module) Error!source.Compiled {
        var diagnostic: source.Diagnostic = .{};
        var result = source.lowerObserved(allocator, module_value, .{
            .diagnostic = &diagnostic,
            .captures = if (self.lambda_schemas.count() != 0 or self.handlers.items.len != 0) .{ .context = self, .capture = observeCapture, .closure = observeClosure } else null,
        }) catch |err| {
            if (self.capture_failure) |failure| return failure;
            var name: []const u8 = "compiled source";
            const function_id = diagnostic.function;
            if (function_id) |id| for (self.functions.items) |f| {
                const item = data(FunctionData, f);
                if (item.id == id) {
                    name = item.name;
                    break;
                }
            };
            self.diagnostic = .{ .code = err, .entity = name, .source = diagnostic, .relationship = switch (err) {
                error.InvalidOwnership, error.OverwrittenOwner, error.UnavailableSlot => "capture, borrow or use obligation failed authoritative admission",
                error.InvalidEffect => "effect exceeds declared residual allowance",
                error.TypeMismatch => "argument, result or handler answer relationship differs",
                error.UnboundVariable => "value is unavailable at this lexical use",
                else => "authoritative source or target admission rejected the construction",
            } };
            return err;
        };
        if (self.capture_failure) |err| {
            result.deinit();
            return err;
        }
        return result;
    }
    fn notePublication(self: *Context, use: PublicationUse) Error!void {
        errdefer self.poisoned = true;
        try self.publication_uses.append(self.raw.allocator(), use);
    }
    fn publication(self: *Context, failure: *const Schema) Error!void {
        if (self.publication_uses.items.len == 0) return;
        var scratch = std.heap.ArenaAllocator.init(self.raw.arena.child_allocator);
        defer scratch.deinit();
        const allocator = scratch.allocator();
        const terms = try allocator.alloc(bool, self.raw.terms.items.len);
        const values = try allocator.alloc(bool, self.raw.values.items.len);
        @memset(terms, false);
        @memset(values, false);
        var pending_terms: std.ArrayList(p.Id) = .empty;
        var pending_values: std.ArrayList(p.Id) = .empty;
        for (self.raw.functions.items) |definition| if (definition.body) |term_id|
            try pending_terms.append(allocator, term_id);
        var refs: @import("source/check.zig").References = .{ .allocator = allocator };
        while (pending_terms.pop()) |id| {
            if (id >= terms.len) return error.InvalidReference;
            if (terms[@intCast(id)]) continue;
            terms[@intCast(id)] = true;
            refs.values.clearRetainingCapacity();
            refs.terms.clearRetainingCapacity();
            refs.bound.clearRetainingCapacity();
            try refs.collect(self.raw.terms.items[@intCast(id)]);
            try pending_terms.appendSlice(allocator, refs.terms.items);
            try pending_values.appendSlice(allocator, refs.values.items);
        }
        while (pending_values.pop()) |id| {
            if (id >= values.len) return error.InvalidReference;
            if (values[@intCast(id)]) continue;
            values[@intCast(id)] = true;
            const expression = self.raw.values.items[@intCast(id)].expression;
            if (expression == .primitive)
                try pending_values.appendSlice(allocator, expression.primitive.operands);
        }
        var cleanup: ?*const Schema = null;
        for (self.publication_uses.items) |use| {
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
                        self.diagnostic.entity = if (is_cleanup) "cleanup" else "authored failure";
                        self.diagnostic.relationship = "named failure layout differs from module failure contract";
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
        const actual = self.variable_schemas.get(variable) orelse return;
        for (bound) |allowed| if (try self.compatible(allowed, actual)) return;
        return self.reject(error.SchemaMismatch, "capture", "retained named value is outside its declared capture allowance");
    }
    fn observeCapture(pointer: *anyopaque, effect: p.Id, variable: p.Id) void {
        const self: *Context = @ptrCast(@alignCast(pointer));
        if (self.capture_failure != null) return;
        for (self.handlers.items) |handler_handle| {
            const h = data(HandlerData, handler_handle);
            if (data(OperationData, h.operation).id != effect) continue;
            self.checkCapture(data(SchemaData, h.resumption).captures, variable) catch |err| {
                self.capture_failure = err;
                return;
            };
        }
    }
    fn observeClosure(pointer: *anyopaque, value_id: p.Id, variable: p.Id) void {
        const self: *Context = @ptrCast(@alignCast(pointer));
        if (self.capture_failure != null) return;
        const schema = self.lambda_schemas.get(value_id) orelse return;
        self.checkCapture(data(SchemaData, schema).captures, variable) catch |err| {
            self.capture_failure = err;
        };
    }
    fn capturePublication(self: *Context, module_value: source.Module) Error!void {
        if (self.lambda_schemas.count() == 0 and self.handlers.items.len == 0) return;
        var checked = try self.lowerNamed(self.raw.arena.child_allocator, module_value);
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
        for (self.raw.functions.items) |function_item| if (function_item.body == null)
            return self.reject(error.UndefinedBody, f.name, "all declarations must be defined");
        errdefer self.poisoned = true;
        try self.publication(failure);
        const result = self.raw.module(f.id, failure_id);
        if (check_captures) try self.capturePublication(result);
        return source.own(source.Module, self.raw.allocator(), result);
    }
};

/// Forward statement builder. Finalization closes this scope to further authoring.
pub const Body = struct {
    context: *Context,
    scope: *Scope,
    function_handle: ?*const Function = null,
    bindings: std.ArrayList(Binding) = .empty,
    parameter_values: ?[]?*const Value = null,

    fn ready(self: *Body) Error!void {
        try self.context.ready();
        var cursor: ?*Scope = self.scope;
        while (cursor) |scope| : (cursor = scope.parent) {
            if (!scope.active)
                return self.context.reject(error.ClosedBody, "body", "body or ancestor already finalized");
        }
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
        const expression = self.context.raw.values.items[@intCast(id)].expression;
        if (expression == .variable) {
            if (self.context.variable_schemas.get(expression.variable)) |prior| try self.context.same(prior, schema);
            try self.context.variable_schemas.put(self.context.raw.allocator(), expression.variable, schema);
        }
        return handle(Value, try self.context.save(ValueData, .{
            .owner = self.context,
            .id = id,
            .schema = schema,
            .scope = self.scope,
        }));
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
            if (self.parameter_values == null) {
                const values = try self.context.raw.allocator().alloc(?*const Value, f.parameters.len);
                @memset(values, null);
                self.parameter_values = values;
            }
            if (self.parameter_values.?[i]) |present| return present;
            const result = try self.makeValue(try self.context.raw.reference(self.context.raw.parameter(f.id, i)), named.schema);
            self.parameter_values.?[i] = result;
            return result;
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
            c.same(named.schema, v.schema) catch |err| {
                c.diagnostic.entity = named.name;
                c.diagnostic.relationship = "argument or product field differs from its declared schema";
                return err;
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
        errdefer self.context.poisoned = true;
        const term = try self.context.raw.term(.{
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
        const c = self.context;
        const op = data(OperationData, operation_handle);
        try c.origin(op.owner);
        if (!op.external) return c.reject(error.InvalidCategory, op.name, "local operation needs capability");
        const v = try self.useValue(payload);
        try c.same(op.payload, v.schema);
        errdefer c.poisoned = true;
        return self.bind(try c.raw.term(.{ .perform = .{ .effect = op.id, .payload = v.id } }), op.result);
    }
    pub fn product(
        self: *Body,
        schema: *const Schema,
        fields: []const Argument,
    ) Error!*const Value {
        const c = self.context;
        const id = try c.schemaId(schema);
        if (c.raw.schemas.items[@intCast(id)] != .product)
            return c.reject(error.InvalidCategory, "product", "requires a record schema");
        errdefer c.poisoned = true;
        return self.bind(try c.raw.pure(try c.raw.primitive(id, .product, try self.arguments(data(SchemaData, schema).fields, fields), 0)), schema);
    }
    pub fn field(self: *Body, product_value: *const Value, name: []const u8) Error!*const Value {
        const c = self.context;
        const v = try self.useValue(product_value);
        const s = data(SchemaData, v.schema);
        if (c.raw.schemas.items[@intCast(s.id)] != .product)
            return c.reject(error.InvalidCategory, "field", "requires a named record value");
        for (s.fields, 0..) |item, index| if (std.mem.eql(u8, item.name, name)) {
            errdefer c.poisoned = true;
            return self.bind(try c.raw.pure(try c.raw.primitive(try c.schemaId(item.schema), .field, &.{v.id}, index)), item.schema);
        };
        return c.reject(error.UnknownName, "field", "unknown named product field");
    }
    pub fn closureBody(self: *Body, function_handle: *const Function) Error!*Body {
        try self.ready();
        return self.context.nestedBody(function_handle, self.scope);
    }
    fn visibleFunction(self: *Body, function_handle: *const Function) Error!*const FunctionData {
        try self.ready();
        const f = data(FunctionData, function_handle);
        try self.context.functionVisible(f, self.scope);
        return f;
    }
    fn noteForwardUse(self: *Body, declaration: *const Function, anchor: @FieldType(PublicationUse, "anchor")) Error!void {
        // A declaration may acquire its lexical parent after this use. Only
        // published uses constrain that eventual parent; abandoned AST does not.
        if (data(FunctionData, declaration).scope == null)
            try self.context.notePublication(.{ .anchor = anchor, .contract = .{
                .function_scope = .{ .declaration = declaration, .scope = self.scope },
            } });
    }
    pub fn lambda(
        self: *Body,
        function_handle: *const Function,
        schema: *const Schema,
    ) Error!*const Value {
        const c = self.context;
        const f = try self.visibleFunction(function_handle);
        const id = try c.schemaId(schema);
        const shape = c.raw.schemas.items[@intCast(id)];
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
        errdefer c.poisoned = true;
        const value_id = try c.raw.lambda(f.id, id);
        try self.noteForwardUse(function_handle, .{ .value = value_id });
        try c.lambda_schemas.put(c.raw.allocator(), value_id, schema);
        return self.bind(try c.raw.pure(value_id), schema);
    }
    pub fn apply(
        self: *Body,
        callable_value: *const Value,
        args: []const Argument,
    ) Error!*const Value {
        const v = try self.useValue(callable_value);
        const c = self.context;
        const info = data(SchemaData, v.schema);
        const shape = c.raw.schemas.items[@intCast(info.id)];
        if (shape != .internal or shape.internal != .computation)
            return c.reject(error.InvalidCategory, "apply", "value is not callable");
        errdefer c.poisoned = true;
        return self.bind(try c.raw.term(.{
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
        const c = self.context;
        const op = data(OperationData, operation_handle);
        try c.origin(op.owner);
        const cap = try self.useValue(capability_value);
        const expected_capability = try c.capability(operation_handle);
        c.same(expected_capability, cap.schema) catch |err| {
            c.diagnostic.entity = op.name;
            c.diagnostic.relationship = "capability belongs to a different operation instance";
            return err;
        };
        const v = try self.useValue(payload);
        try c.same(op.payload, v.schema);
        errdefer c.poisoned = true;
        return self.bind(try c.raw.term(.{
            .perform = .{
                .effect = op.id,
                .payload = v.id,
                .capability = cap.id,
                .bodies = try self.arguments(op.bodies, bodies),
            },
        }), op.result);
    }
    pub fn resumeValue(
        self: *Body,
        resumption: *const Value,
        reply: *const Value,
    ) Error!*const Value {
        const token = try self.useValue(resumption);
        const v = try self.useValue(reply);
        const c = self.context;
        const info = data(SchemaData, token.schema);
        const shape = c.raw.schemas.items[@intCast(info.id)];
        if (shape != .internal or shape.internal != .resumption)
            return c.reject(error.InvalidCategory, "resume", "value is not a resumption");
        if (info.fields.len != 1) return error.InvalidSchema;
        try c.same(info.fields[0].schema, v.schema);
        errdefer c.poisoned = true;
        return self.bind(try c.raw.term(.{ .resume_value = .{ .resumption = token.id, .argument = v.id } }), info.result orelse return error.InvalidSchema);
    }
    pub fn handleWith(
        self: *Body,
        handler_handle: *const Handler,
        callable_value: *const Value,
        state: []const Argument,
    ) Error!*const Value {
        const c = self.context;
        const h = data(HandlerData, handler_handle);
        try c.origin(h.owner);
        const v = try self.useValue(callable_value);
        try c.same(h.body_schema, v.schema);
        errdefer c.poisoned = true;
        return self.bind(try c.raw.term(.{
            .handle = .{
                .handler = h.id,
                .body = v.id,
                .state = try self.arguments(h.state, state),
            },
        }), h.answer);
    }
    pub fn checkedAdd(self: *Body, left: *const Value, right: *const Value, failure: *const Value) Error!*const Value {
        return self.checked(.add, left, right, .{ .overflow = failure });
    }
    pub fn checked(
        self: *Body,
        operation: Arithmetic,
        left: *const Value,
        right: *const Value,
        failures: ArithmeticFailures,
    ) Error!*const Value {
        const c = self.context;
        const a = try self.useValue(left);
        const b = try self.useValue(right);
        try c.same(a.schema, b.schema);
        const schema = try c.schemaId(a.schema);
        switch (c.raw.schemas.items[@intCast(schema)]) {
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
        const overflow = try self.useValue(failures.overflow);
        var faults: [2]p.InstructionFailure = undefined;
        faults[0] = .{ .kind = .arithmetic_overflow, .value = try c.raw.failureLiteral(overflow.id) };
        const division = operation == .divide or operation == .remainder;
        if (division) {
            const zero = try self.useValue(failures.division_by_zero orelse
                return c.reject(error.InvalidCategory, "division", "requires an authored zero-divisor failure"));
            faults[1] = .{ .kind = .division_by_zero, .value = try c.raw.failureLiteral(zero.id) };
        } else if (failures.division_by_zero != null)
            return c.reject(error.InvalidCategory, "arithmetic", "zero-divisor failure only applies to division or remainder");
        errdefer c.poisoned = true;
        const value_id = try c.raw.value(.{ .schema = schema, .expression = .{ .primitive = .{
            .opcode = opcode,
            .operands = &.{ a.id, b.id },
            .failures = faults[0..@as(usize, if (division) 2 else 1)],
        } } });
        try c.notePublication(.{ .anchor = .{ .value = value_id }, .contract = .{ .failure = overflow.schema } });
        if (division) try c.notePublication(.{ .anchor = .{ .value = value_id }, .contract = .{ .failure = (try self.useValue(failures.division_by_zero.?)).schema } });
        return self.bind(try c.raw.pure(value_id), a.schema);
    }
    pub fn sequenceValue(
        self: *Body,
        schema: *const Schema,
        items: []const *const Value,
    ) Error!*const Value {
        const c = self.context;
        const id = try c.schemaId(schema);
        const shape = c.raw.schemas.items[@intCast(id)];
        if (shape != .seq) return c.reject(error.InvalidCategory, "sequence", "requires a sequence schema and matching element metadata");
        const element = data(SchemaData, schema).result orelse return c.reject(error.InvalidSchema, "sequence", "requires a sequence schema and matching element metadata");
        errdefer c.poisoned = true;
        const ids = try c.raw.allocator().alloc(p.Id, items.len);
        for (items, ids) |item, *out| {
            const v = try self.useValue(item);
            try c.same(element, v.schema);
            out.* = v.id;
        }
        return self.bind(try c.raw.pure(try c.raw.primitive(id, .sequence, ids, 0)), schema);
    }
    pub fn concat(self: *Body, left: *const Value, right: *const Value) Error!*const Value {
        const a = try self.useValue(left);
        const b = try self.useValue(right);
        const c = self.context;
        try c.same(a.schema, b.schema);
        const id = try c.schemaId(a.schema);
        if (c.raw.schemas.items[@intCast(id)] != .seq) return c.reject(error.InvalidCategory, "concatenation", "requires sequence operands");
        errdefer c.poisoned = true;
        return self.bind(try c.raw.pure(try c.raw.primitive(id, .sequence_concat, &.{ a.id, b.id }, 0)), a.schema);
    }
    pub fn variant(
        self: *Body,
        schema: *const Schema,
        name: []const u8,
        payload_value: *const Value,
    ) Error!*const Value {
        const c = self.context;
        const id = try c.schemaId(schema);
        const v = try self.useValue(payload_value);
        if (c.raw.schemas.items[@intCast(id)] != .sum) return c.reject(error.InvalidCategory, "variant", "requires a tagged alternative schema");
        for (data(SchemaData, schema).fields, 0..) |item, index| {
            if (!std.mem.eql(u8, item.name, name)) continue;
            try c.same(item.schema, v.schema);
            errdefer c.poisoned = true;
            return self.bind(try c.raw.pure(try c.raw.primitive(id, .variant, &.{v.id}, index)), schema);
        }
        return c.reject(error.UnknownName, "variant", "unknown alternative");
    }
    pub fn caseOf(self: *Body, sum: *const Value, name: []const u8) Error!*const Case {
        const v = try self.useValue(sum);
        const c = self.context;
        const schema = data(SchemaData, v.schema);
        if (c.raw.schemas.items[@intCast(schema.id)] != .sum) return c.reject(error.InvalidCategory, "match case", "requires a tagged alternative value");
        for (schema.fields, 0..) |item, index| {
            if (!std.mem.eql(u8, item.name, name)) continue;
            errdefer c.poisoned = true;
            const arm = try self.branch();
            const variable = try c.raw.variable(try c.schemaId(item.schema));
            const payload = try arm.makeValue(try c.raw.reference(variable), item.schema);
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
        const c = self.context;
        const schema = data(SchemaData, v.schema);
        if (c.raw.schemas.items[@intCast(schema.id)] != .sum or
            cases.len != schema.fields.len or cases.len == 0) return c.reject(error.InvalidCategory, "match", "cases must cover this value once and return compatible schemas");
        errdefer c.poisoned = true;
        const RawCase = @typeInfo(@FieldType(source.ast.Term, "match_sum")).@"struct".fields[1].type;
        const raw_cases = try c.raw.allocator().alloc(@typeInfo(RawCase).pointer.child, cases.len);
        const seen = try c.raw.allocator().alloc(bool, cases.len);
        @memset(seen, false);
        var result: ?*const Schema = null;
        for (cases) |finished| {
            const f = data(FinishedCaseData, finished);
            const arm = data(CaseData, f.case);
            const computation = data(ComputationData, f.computation);
            try c.origin(computation.owner);
            if (arm.sum != sum or arm.body.scope.parent != self.scope or
                arm.index >= cases.len or seen[arm.index]) return c.reject(error.InvalidBranch, "match", "cases must cover this value once and return compatible schemas");
            if (result) |expected| try c.same(expected, computation.schema);
            result = computation.schema;
            seen[arm.index] = true;
            raw_cases[arm.index] = .{ .variable = arm.variable, .body = computation.id };
        }
        return self.bind(try c.raw.term(.{ .match_sum = .{ .value = v.id, .cases = raw_cases } }), result.?);
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
        const c = self.context;
        const info = data(SchemaData, token.schema);
        const shape = c.raw.schemas.items[@intCast(info.id)];
        if (shape != .internal or shape.internal != .resumption) return c.reject(error.InvalidCategory, "resumption", "resumeWith requires a shallow token and compatible successor");
        const h = data(HandlerData, successor);
        try c.origin(h.owner);
        if (shape.internal.resumption.mode != .shallow or info.fields.len != 1)
            return c.reject(error.InvalidCategory, "resumption", "resumeWith requires a shallow token and compatible successor");
        try c.same(info.fields[0].schema, v.schema);
        try c.same(info.result orelse return c.reject(error.InvalidSchema, "resumption", "resumeWith requires a shallow token and compatible successor"), h.input);
        errdefer c.poisoned = true;
        return self.bind(try c.raw.term(.{
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
        const c = self.context;
        errdefer c.poisoned = true;
        return self.bind(try c.raw.term(.{ .dispose = v.id }), try c.scalar(void));
    }
    pub fn withRegion(
        self: *Body,
        region_handle: *const Region,
        work: *const Value,
        args: []const Argument,
    ) Error!*const Value {
        const c = self.context;
        const r = data(RegionData, region_handle);
        try c.origin(r.owner);
        const v = try self.useValue(work);
        const info = data(SchemaData, v.schema);
        const shape = c.raw.schemas.items[@intCast(info.id)];
        if (shape != .internal or shape.internal != .computation) return c.reject(error.InvalidCategory, "region", "requires a callable with the matching implicit region parameter");
        if (info.fields.len == 0) return c.reject(error.SchemaMismatch, "region", "requires a callable with the matching implicit region parameter");
        const token_id = try c.schemaId(info.fields[0].schema);
        const token = c.raw.schemas.items[@intCast(token_id)];
        if (token != .internal or token.internal != .region or token.internal.region != r.id)
            return c.reject(error.SchemaMismatch, "region", "body belongs to another region");
        errdefer c.poisoned = true;
        return self.bind(try c.raw.term(.{
            .with_region = .{
                .region = r.id,
                .body = v.id,
                .arguments = try self.arguments(info.fields[1..], args),
            },
        }), info.result orelse return c.reject(error.InvalidSchema, "region", "requires a callable with the matching implicit region parameter"));
    }
    pub fn protect(
        self: *Body,
        work: *const Value,
        cleanup: *const Value,
        args: []const Argument,
    ) Error!*const Value {
        const v = try self.useValue(work);
        const finalizer = try self.useValue(cleanup);
        const c = self.context;
        const info = data(SchemaData, v.schema);
        const shape = c.raw.schemas.items[@intCast(info.id)];
        if (shape != .internal or shape.internal != .computation) return c.reject(error.InvalidCategory, "protection", "requires callable body and cleanup contracts");
        const cleanup_shape = c.raw.schemas.items[@intCast(data(SchemaData, finalizer.schema).id)];
        if (cleanup_shape != .internal or cleanup_shape.internal != .computation)
            return c.reject(error.InvalidCategory, "protection", "requires callable body and cleanup contracts");
        const cleanup_info = data(SchemaData, finalizer.schema);
        if (cleanup_info.fields.len != 1)
            return c.reject(error.SchemaMismatch, "cleanup", "requires one exit-information parameter");
        errdefer c.poisoned = true;
        const term = try c.raw.term(.{
            .protect = .{
                .body = v.id,
                .cleanup = finalizer.id,
                .arguments = try self.arguments(info.fields, args),
            },
        });
        try c.notePublication(.{ .anchor = .{ .term = term }, .contract = .{ .cleanup = cleanup_info.fields[0].schema } });
        return self.bind(term, info.result orelse return c.reject(error.InvalidSchema, "protection", "requires callable body and cleanup contracts"));
    }
    pub fn branch(self: *Body) Error!*Body {
        try self.ready();
        return self.context.save(Body, .{
            .context = self.context,
            .scope = try self.context.save(Scope, .{ .parent = self.scope }),
        });
    }
    pub fn block(self: *Body, finished: *const Computation) Error!*const Value {
        try self.ready();
        const c = self.context;
        const value = data(ComputationData, finished);
        try c.origin(value.owner);
        if (value.scope.parent != self.scope) return c.reject(error.InvalidBranch, "block", "completed body must belong to this parent scope");
        return self.bind(value.id, value.schema);
    }
    pub fn conditional(
        self: *Body,
        condition: *const Value,
        when_true: *const Computation,
        when_false: *const Computation,
    ) Error!*const Value {
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
        return self.bind(try c.raw.term(.{
            .conditional = .{ .condition = v.id, .when_true = a.id, .when_false = b.id },
        }), a.schema);
    }
    /// Close unused staging work. Abandoning a function leaves it undefined;
    /// module publication will reject it. Descendant bodies become unusable.
    pub fn abandon(self: *Body) void {
        self.scope.active = false;
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

/// Explicit low-level integration. Numeric IDs have no recoverable historical
/// provenance. The caller promises they belong to c.raw; available bounds and
/// categories are checked. These adapters never certify raw source admission.
pub const interop = struct {
    pub fn scope(c: *Context) Error!*Body {
        try c.ready();
        return c.save(Body, .{ .context = c, .scope = try c.save(Scope, .{ .parent = null }) });
    }
    pub fn adoptValue(body: *Body, id: p.Id, expected: *const Schema) Error!*const Value {
        try body.ready();
        const c = body.context;
        if (id >= c.raw.values.items.len) return error.InvalidReference;
        if (c.raw.values.items[@intCast(id)].schema != try c.schemaId(expected)) return error.SchemaMismatch;
        const expression = c.raw.values.items[@intCast(id)].expression;
        if (expression == .variable or expression == .literal) return body.makeValue(id, expected);
        errdefer c.poisoned = true;
        return body.bind(try c.raw.pure(id), expected);
    }
    pub fn valueId(body: *Body, item: *const Value) Error!p.Id {
        return (try body.useValue(item)).id;
    }
    pub fn term(body: *Body, id: p.Id, result: *const Schema) Error!*const Value {
        try body.ready();
        if (id >= body.context.raw.terms.items.len) return error.InvalidReference;
        _ = try body.context.schemaId(result);
        return body.bind(id, result);
    }
    pub fn computationId(c: *Context, item: *const Computation) Error!p.Id {
        const v = data(ComputationData, item);
        try c.origin(v.owner);
        return v.id;
    }
    pub fn schema(c: *Context, id: p.Id) Error!*const Schema {
        try c.ready();
        if (id >= c.raw.schemas.items.len) return error.InvalidSchema;
        if (c.imported.get(id)) |present| return present;
        errdefer c.poisoned = true;
        const shape = c.raw.schemas.items[@intCast(id)];
        switch (shape) {
            .product, .sum, .seq => {},
            .internal => |inner| switch (inner) {
                .computation, .resumption, .borrowed => {},
                else => return c.intern(id, &.{}),
            },
            else => return c.intern(id, &.{}),
        }
        // Install a stable placeholder before following recursive schema edges.
        const info = try c.save(SchemaData, .{ .owner = c, .id = id });
        const result = handle(Schema, info);
        try c.imported.put(c.raw.allocator(), id, result);
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
        const captures = try c.raw.allocator().alloc(*const Schema, capture_ids.len);
        for (capture_ids, captures) |child, *item| item.* = try schema(c, child);
        info.captures = captures;
        return result;
    }
    pub fn namedCallable(c: *Context, id: p.Id, names: []const []const u8) Error!*const Schema {
        const imported = try schema(c, id);
        const shape = c.raw.schemas.items[@intCast(id)];
        if (shape != .internal or shape.internal != .computation) return error.InvalidCategory;
        const info = data(SchemaData, imported);
        if (names.len != info.fields.len) return error.SchemaMismatch;
        errdefer c.poisoned = true;
        const fields = try c.raw.allocator().alloc(Field, names.len);
        for (fields, names, info.fields) |*item, name, old| item.* = .{ .name = name, .schema = old.schema };
        return c.internComplete(id, fields, info.result, info.captures);
    }
    fn positionalFields(c: *Context, ids: []const p.Id) Error![]const Field {
        errdefer c.poisoned = true;
        const fields = try c.raw.allocator().alloc(Field, ids.len);
        for (ids, fields, 0..) |child, *item, i| item.* = .{
            .name = try std.fmt.allocPrint(c.raw.allocator(), "{d}", .{i}),
            .schema = try schema(c, child),
        };
        return fields;
    }
    pub fn operation(c: *Context, id: p.Id) Error!*const Operation {
        try c.ready();
        if (id >= c.raw.effects.items.len) return error.InvalidEffect;
        const op = c.raw.effects.items[@intCast(id)];
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
        if (id >= c.raw.region_count) return error.InvalidReference;
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
        return item.resumption;
    }
    pub fn resultSchema(c: *Context, value: *const Schema) Error!*const Schema {
        _ = try c.schemaId(value);
        return data(SchemaData, value).result orelse error.InvalidSchema;
    }
};

/// Compatibility adapters retain the existing low-level error set.
pub fn sourceError(err: Error) source.Error {
    return switch (err) {
        error.ForeignHandle, error.OutOfScope, error.ClosedBody, error.PoisonedAuthoring, error.SchemaMismatch, error.UnknownName, error.DuplicateName, error.InvalidCategory, error.InvalidBranch, error.UndefinedBody => error.InvalidSource,
        else => |other| other,
    };
}
