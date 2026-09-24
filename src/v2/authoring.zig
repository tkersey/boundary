// Copyright (c) 2026 Boundary contributors. MIT license.
//! Checked, forward staged construction over the existing source language.
const std = @import("std");
const source = @import("source.zig");
const p = @import("boundary_data").program;

pub const Error = source.Error || error{
    ForeignBuilder,
    OutOfScope,
    ClosedBody,
    InvalidField,
    InvalidArgument,
    InvalidCapability,
    InvalidBranch,
    DuplicateName,
};

pub fn sourceError(err: Error) source.Error {
    return switch (err) {
        error.ForeignBuilder, error.OutOfScope, error.ClosedBody, error.InvalidField, error.InvalidArgument, error.InvalidCapability, error.InvalidBranch, error.DuplicateName => error.InvalidSource,
        else => @errorCast(err),
    };
}

pub const Category = enum {
    foreign_builder,
    out_of_scope,
    closed_body,
    schema_mismatch,
    argument_mismatch,
    field_mismatch,
    branch_mismatch,
    capability_mismatch,
    residual_effect_disallowed,
    handler_mismatch,
    ownership_use,
};

/// The most recent authoring failure. Text labels live in the source arena.
pub const Diagnostic = struct {
    category: Category,
    entity: []const u8,
    expected: ?p.Id = null,
    actual: ?p.Id = null,
    introduced_in: ?[]const u8 = null,
    used_in: ?[]const u8 = null,
    source_detail: ?source.Diagnostic = null,

    pub fn render(self: Diagnostic, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{s}: {s}", .{ @tagName(self.category), self.entity });
        if (self.expected) |id| try writer.print("; expected schema {d}", .{id});
        if (self.actual) |id| try writer.print("; actual schema {d}", .{id});
        if (self.introduced_in) |name| try writer.print("; introduced in {s}", .{name});
        if (self.used_in) |name| try writer.print("; used in {s}", .{name});
        if (self.source_detail) |detail| {
            if (detail.code) |code| try writer.print("; source check: {s}", .{@errorName(code)});
            if (detail.function) |id| try writer.print("; function {d}", .{id});
            if (detail.term) |id| try writer.print("; term {d}", .{id});
            if (detail.variable) |id| try writer.print("; variable {d}", .{id});
        }
    }
};

pub const Schema = struct { owner: *Builder, id: p.Id };
pub const Region = struct { owner: *Builder, id: p.Id };
pub const Effect = struct {
    owner: *Builder,
    id: p.Id,
    payload: Schema,
    result: Schema,
    external: bool,
};
pub const Parameter = struct { name: []const u8, schema: Schema };
pub const Field = Parameter;
pub const NamedValue = struct { name: []const u8, value: Value };
pub const Record = struct { owner: *Builder, schema: Schema, fields: []const Field };
pub const Variant = struct { owner: *Builder, schema: Schema, alternatives: []const Field };
pub const Function = struct {
    owner: *Builder,
    id: p.Id,
    name: []const u8,
    parameters: []const Parameter,
    result: Schema,
    effects: []const p.Id,
    regions: []const p.Id,
};
pub const Value = struct {
    owner: *Builder,
    id: p.Id,
    schema: Schema,
    scope: ?*Scope = null,
};
pub const Block = struct {
    owner: *Builder,
    term: p.Id,
    result: Schema,
    scope: *Scope,
};
pub const Callable = struct { value: Value };
pub const FinishedCase = struct {
    variant: Variant,
    index: usize,
    variable: p.Id,
    block: Block,
};
pub const MatchCase = struct {
    body: Body,
    payload: Value,
    variant: Variant,
    index: usize,
    variable: p.Id,

    pub fn finish(self: *MatchCase, result: Value) Error!FinishedCase {
        return .{ .variant = self.variant, .index = self.index, .variable = self.variable, .block = try self.body.finish(result) };
    }
};
pub const Interpretation = struct {
    owner: *Builder,
    id: p.Id,
    operation: Effect,
    input: Schema,
    answer: Schema,
    resumption: Schema,
    returns: Function,
    clause: Function,
    state: []const Parameter,
    mode: p.Mode,
};
pub const InterpretationOptions = struct {
    operation: Effect,
    input: Schema,
    answer: Schema,
    mode: p.Mode,
    use: p.Use,
    residual: []const Effect = &.{},
    resumption_effects: ?[]const Effect = null,
    return_effects: ?[]const Effect = null,
    capture_bound: []const Schema = &.{},
    state: []const Parameter = &.{},
    escaping: []const Effect = &.{},
    owned_regions: []const Region = &.{},
    borrowed_regions: []const Region = &.{},
    obligations: bool = false,
};

const Scope = struct {
    parent: ?*Scope,
    name: []const u8,
    function: ?p.Id = null,
    open: bool = true,
};
const Step = struct { variable: p.Id, term: p.Id };

pub const Builder = struct {
    raw: *source.Builder,
    diagnostic: ?Diagnostic = null,
    function_names: std.AutoHashMapUnmanaged(p.Id, []const u8) = .empty,
    poisoned: bool = false,

    pub fn init(raw: *source.Builder) Builder {
        return .{ .raw = raw };
    }

    fn report(self: *Builder, category: Category, entity: []const u8, expected: ?p.Id, actual: ?p.Id, introduced: ?[]const u8, used: ?[]const u8) void {
        self.diagnostic = .{ .category = category, .entity = entity, .expected = expected, .actual = actual, .introduced_in = introduced, .used_in = used };
    }

    fn checkSchema(self: *Builder, schema: Schema) Error!void {
        if (schema.owner != self) {
            self.report(.foreign_builder, "schema", null, null, null, null);
            return error.ForeignBuilder;
        }
        if (schema.id >= self.raw.schemas.items.len) return error.InvalidSchema;
    }

    pub fn scalar(self: *Builder, comptime T: type) Error!Schema {
        return .{ .owner = self, .id = try self.raw.scalar(T) };
    }

    pub fn region(self: *Builder) Region {
        return .{ .owner = self, .id = self.raw.region() };
    }

    pub fn adoptRegion(self: *Builder, id: p.Id) Error!Region {
        if (id >= self.raw.region_count) return error.InvalidReference;
        return .{ .owner = self, .id = id };
    }

    pub fn regionSchema(self: *Builder, region_handle: Region) Error!Schema {
        if (region_handle.owner != self or region_handle.id >= self.raw.region_count)
            return error.InvalidReference;
        return self.dynamicSchema(.{ .internal = .{ .region = region_handle.id } });
    }

    pub fn cellSchema(self: *Builder, region_handle: Region, element: Schema) Error!Schema {
        _ = try self.regionSchema(region_handle);
        try self.checkSchema(element);
        return self.dynamicSchema(.{ .internal = .{ .cell = .{
            .element = element.id,
            .region = region_handle.id,
        } } });
    }

    fn dynamicSchema(self: *Builder, shape: p.Schema) Error!Schema {
        return .{ .owner = self, .id = try self.raw.schema(shape) };
    }

    pub fn adoptSchema(self: *Builder, id: p.Id) Error!Schema {
        if (id >= self.raw.schemas.items.len) return error.InvalidSchema;
        return .{ .owner = self, .id = id };
    }

    pub fn adoptEffect(self: *Builder, id: p.Id) Error!Effect {
        if (id >= self.raw.effects.items.len) return error.InvalidReference;
        const original = self.raw.effects.items[@intCast(id)];
        return .{ .owner = self, .id = id, .payload = try self.adoptSchema(original.payload), .result = try self.adoptSchema(original.result), .external = original.external };
    }

    pub fn sumSchema(self: *Builder, alternatives: []const Schema) Error!Schema {
        const ids = try self.raw.allocator().alloc(p.Id, alternatives.len);
        for (alternatives, ids) |alternative, *id| {
            try self.checkSchema(alternative);
            id.* = alternative.id;
        }
        return self.dynamicSchema(.{ .sum = ids });
    }

    pub fn sequenceSchema(self: *Builder, element: Schema) Error!Schema {
        try self.checkSchema(element);
        return self.dynamicSchema(.{ .seq = element.id });
    }

    pub fn productSchema(self: *Builder, fields: []const Schema) Error!Schema {
        const ids = try self.raw.allocator().alloc(p.Id, fields.len);
        for (fields, ids) |field, *id| {
            try self.checkSchema(field);
            id.* = field.id;
        }
        return self.dynamicSchema(.{ .product = ids });
    }

    pub fn record(self: *Builder, fields: []const Field) Error!Record {
        const copied = try self.raw.allocator().alloc(Field, fields.len);
        const schemas = try self.raw.allocator().alloc(Schema, fields.len);
        for (fields, copied, schemas, 0..) |field, *copy, *schema, index| {
            try self.checkSchema(field.schema);
            for (fields[0..index]) |prior| if (std.mem.eql(u8, prior.name, field.name)) return error.DuplicateName;
            copy.* = .{ .name = try self.raw.allocator().dupe(u8, field.name), .schema = field.schema };
            schema.* = field.schema;
        }
        return .{ .owner = self, .schema = try self.productSchema(schemas), .fields = copied };
    }

    pub fn variant(self: *Builder, alternatives: []const Field) Error!Variant {
        const copied = try self.raw.allocator().alloc(Field, alternatives.len);
        const schemas = try self.raw.allocator().alloc(Schema, alternatives.len);
        for (alternatives, copied, schemas, 0..) |field, *copy, *schema, index| {
            try self.checkSchema(field.schema);
            for (alternatives[0..index]) |prior| if (std.mem.eql(u8, prior.name, field.name)) return error.DuplicateName;
            copy.* = .{ .name = try self.raw.allocator().dupe(u8, field.name), .schema = field.schema };
            schema.* = field.schema;
        }
        return .{ .owner = self, .schema = try self.sumSchema(schemas), .alternatives = copied };
    }

    fn declareEffect(self: *Builder, name: []const u8, payload: Schema, result: Schema, is_external: bool, control_use: p.Use) Error!Effect {
        try self.checkSchema(payload);
        try self.checkSchema(result);
        const id = try self.raw.effect(.{ .identity = name, .payload = payload.id, .result = result.id, .external = is_external, .control_use = control_use });
        return .{ .owner = self, .id = id, .payload = payload, .result = result, .external = is_external };
    }

    pub fn external(self: *Builder, name: []const u8, payload: Schema, result: Schema) Error!Effect {
        return self.declareEffect(name, payload, result, true, .linear);
    }

    pub fn local(self: *Builder, name: []const u8, payload: Schema, result: Schema, use: p.Use) Error!Effect {
        return self.declareEffect(name, payload, result, false, use);
    }

    pub fn capability(self: *Builder, effect: Effect) Error!Schema {
        if (effect.owner != self or effect.external) {
            self.report(.capability_mismatch, "local effect capability", null, null, null, null);
            return error.InvalidCapability;
        }
        return self.dynamicSchema(.{ .internal = .{ .capability = effect.id } });
    }

    pub fn declare(self: *Builder, name: []const u8, parameters: []const Parameter, result: Schema, effects: []const Effect) Error!Function {
        return self.declareScoped(name, parameters, result, effects, &.{});
    }

    pub fn declareScoped(self: *Builder, name: []const u8, parameters: []const Parameter, result: Schema, effects: []const Effect, regions: []const Region) Error!Function {
        errdefer |err| {
            if (err == error.OutOfMemory) self.poisoned = true;
        }
        try self.checkSchema(result);
        const copied = try self.raw.allocator().alloc(Parameter, parameters.len);
        const param_ids = try self.raw.allocator().alloc(p.Id, parameters.len);
        for (parameters, copied, param_ids, 0..) |parameter, *copy, *id, index| {
            try self.checkSchema(parameter.schema);
            for (parameters[0..index]) |earlier| if (std.mem.eql(u8, earlier.name, parameter.name)) return error.DuplicateName;
            copy.* = .{ .name = try self.raw.allocator().dupe(u8, parameter.name), .schema = parameter.schema };
            id.* = parameter.schema.id;
        }
        const effect_ids = try self.raw.allocator().alloc(p.Id, effects.len);
        for (effects, effect_ids) |effect, *id| {
            if (effect.owner != self) return error.ForeignBuilder;
            id.* = effect.id;
        }
        const region_ids = try self.raw.allocator().alloc(p.Id, regions.len);
        for (regions, region_ids) |region_handle, *id| {
            if (region_handle.owner != self) return error.ForeignBuilder;
            id.* = region_handle.id;
        }
        const saved_name = try self.raw.allocator().dupe(u8, name);
        const id = try self.raw.declare(param_ids, result.id, effect_ids, region_ids);
        try self.function_names.put(self.raw.allocator(), id, saved_name);
        return .{ .owner = self, .id = id, .name = saved_name, .parameters = copied, .result = result, .effects = effect_ids, .regions = region_ids };
    }

    pub fn body(self: *Builder, function: Function) Error!Body {
        if (function.owner != self) return error.ForeignBuilder;
        const scope = try self.raw.allocator().create(Scope);
        scope.* = .{ .parent = null, .name = function.name, .function = function.id };
        return .{ .author = self, .scope = scope, .function = function };
    }

    /// A source-library staging callback can supply lexical context that it owns.
    /// Raw adoption into this context is confined to Interop below.
    pub fn ambient(self: *Builder, name: []const u8) Error!Body {
        const scope = try self.raw.allocator().create(Scope);
        scope.* = .{ .parent = null, .name = try self.raw.allocator().dupe(u8, name) };
        return .{ .author = self, .scope = scope };
    }

    pub fn bodyWithin(self: *Builder, parent: *Body, function: Function) Error!Body {
        try parent.ensureOpen();
        if (parent.author != self or function.owner != self) return error.ForeignBuilder;
        const scope = try self.raw.allocator().create(Scope);
        scope.* = .{ .parent = parent.scope, .name = function.name, .function = function.id };
        return .{ .author = self, .scope = scope, .function = function };
    }

    pub fn define(self: *Builder, function: Function, block: Block) Error!void {
        if (function.owner != self or block.owner != self) return error.ForeignBuilder;
        if (block.scope.function != function.id) return error.InvalidBranch;
        if (block.result.id != function.result.id) {
            self.report(.schema_mismatch, function.name, function.result.id, block.result.id, null, null);
            return error.TypeMismatch;
        }
        try self.raw.define(function.id, block.term);
    }

    pub fn module(self: *Builder, entry: Function, failure: Schema) Error!source.Module {
        if (self.poisoned) return error.InvalidSource;
        if (entry.owner != self) return error.ForeignBuilder;
        try self.checkSchema(failure);
        return self.raw.module(entry.id, failure.id);
    }

    pub fn compile(self: *Builder, allocator: std.mem.Allocator, input: source.Module) source.Error!source.Compiled {
        if (self.poisoned) return error.InvalidSource;
        var detail: source.Diagnostic = .{};
        return source.lowerObserved(allocator, input, .{ .diagnostic = &detail }) catch |err| {
            const category: Category = switch (err) {
                error.UnboundVariable => .out_of_scope,
                error.InvalidOwnership, error.UnavailableSlot => .ownership_use,
                error.InvalidEffect => .residual_effect_disallowed,
                else => .schema_mismatch,
            };
            const name = if (detail.function) |id|
                self.function_names.get(id) orelse "source declaration"
            else
                "source declaration";
            self.diagnostic = .{ .category = category, .entity = name, .source_detail = detail };
            return err;
        };
    }

    pub fn literal(self: *Builder, comptime T: type, value: T) Error!Value {
        return .{ .owner = self, .id = try self.raw.constant(T, value), .schema = try self.scalar(T) };
    }

    /// The caller vouches for historical raw-ID provenance. The current catalog
    /// and schema are checked; a numeric ID alone cannot recover its origin.
    fn adoptValue(self: *Builder, id: p.Id, schema: Schema) Error!Value {
        try self.checkSchema(schema);
        if (id >= self.raw.values.items.len) return error.InvalidReference;
        if (self.raw.values.items[@intCast(id)].schema != schema.id) return error.TypeMismatch;
        return .{ .owner = self, .id = id, .schema = schema };
    }

    fn effectIds(self: *Builder, effects: []const Effect) Error![]const p.Id {
        const ids = try self.raw.allocator().alloc(p.Id, effects.len);
        for (effects, ids) |effect, *id| {
            if (effect.owner != self) return error.ForeignBuilder;
            id.* = effect.id;
        }
        return ids;
    }

    fn regionIds(self: *Builder, regions: []const Region) Error![]const p.Id {
        const ids = try self.raw.allocator().alloc(p.Id, regions.len);
        for (regions, ids) |region_handle, *id| {
            if (region_handle.owner != self or region_handle.id >= self.raw.region_count)
                return error.InvalidReference;
            id.* = region_handle.id;
        }
        return ids;
    }

    pub fn interpret(self: *Builder, options: InterpretationOptions) Error!Interpretation {
        if (options.operation.owner != self or options.operation.external) return error.InvalidCapability;
        try self.checkSchema(options.input);
        try self.checkSchema(options.answer);
        const residual = try self.effectIds(options.residual);
        const resumed_effects = try self.effectIds(options.resumption_effects orelse options.residual);
        const escaping = try self.effectIds(options.escaping);
        const owned_regions = try self.regionIds(options.owned_regions);
        const bounds = try self.raw.allocator().alloc(p.Id, options.capture_bound.len);
        for (options.capture_bound, bounds) |schema, *id| {
            try self.checkSchema(schema);
            id.* = schema.id;
        }
        const state = try self.raw.allocator().alloc(Parameter, options.state.len);
        const state_ids = try self.raw.allocator().alloc(p.Id, options.state.len);
        for (options.state, state, state_ids) |named, *copy, *id| {
            try self.checkSchema(named.schema);
            copy.* = .{ .name = try self.raw.allocator().dupe(u8, named.name), .schema = named.schema };
            id.* = named.schema.id;
        }
        const token = try self.dynamicSchema(.{ .internal = .{ .resumption = .{
            .effect = options.operation.id,
            .input = options.operation.result.id,
            .answer = options.answer.id,
            .effects = resumed_effects,
            .capture_bound = bounds,
            .handled = &.{options.operation.id},
            .escaping = escaping,
            .mode = options.mode,
            .use = options.use,
            .owned_regions = owned_regions,
            .obligations = options.obligations,
        } } });
        const return_params = try self.raw.allocator().alloc(Parameter, state.len + 1);
        @memcpy(return_params[0..state.len], state);
        return_params[state.len] = .{ .name = "value", .schema = options.input };
        const clause_params = try self.raw.allocator().alloc(Parameter, state.len + 2);
        @memcpy(clause_params[0..state.len], state);
        clause_params[state.len] = .{ .name = "payload", .schema = options.operation.payload };
        clause_params[state.len + 1] = .{ .name = "resume", .schema = token };
        const returns = try self.declareScoped("handler return", return_params, options.answer, options.return_effects orelse options.residual, options.borrowed_regions);
        const clause = try self.declareScoped("handler clause", clause_params, options.answer, options.residual, options.borrowed_regions);
        const id = try self.raw.handler(.{
            .mode = options.mode,
            .input = options.input.id,
            .answer = options.answer.id,
            .return_function = returns.id,
            .state = state_ids,
            .effects = residual,
            .clauses = &.{.{ .effect = options.operation.id, .function = clause.id, .resumption = token.id }},
        });
        return .{ .owner = self, .id = id, .operation = options.operation, .input = options.input, .answer = options.answer, .resumption = token, .returns = returns, .clause = clause, .state = state, .mode = options.mode };
    }

    /// The responder's declared residual effects remain an explicit allowance.
    pub fn responder(self: *Builder, operation: Effect, function: Function, residual: []const Effect, capture_bound: []const Schema, mode: p.Mode, use: p.Use) Error!Interpretation {
        return self.responding(operation, function, operation.result, residual, capture_bound, mode, use);
    }

    pub fn responding(self: *Builder, operation: Effect, function: Function, body_result: Schema, residual: []const Effect, capture_bound: []const Schema, mode: p.Mode, use: p.Use) Error!Interpretation {
        if (function.owner != self or operation.owner != self) return error.ForeignBuilder;
        try self.checkSchema(body_result);
        if (function.parameters.len != 1 or function.parameters[0].schema.id != operation.payload.id or
            function.result.id != operation.result.id) return error.TypeMismatch;
        const allowed = try self.effectIds(residual);
        for (function.effects) |effect_id| {
            if (std.mem.indexOfScalar(p.Id, allowed, effect_id) == null) {
                self.report(.residual_effect_disallowed, function.name, null, effect_id, null, null);
                return error.InvalidCapability;
            }
        }
        const result = try self.interpret(.{
            .operation = operation,
            .input = body_result,
            .answer = body_result,
            .mode = mode,
            .use = use,
            .residual = residual,
            .capture_bound = capture_bound,
        });
        var returns = try self.body(result.returns);
        try self.define(result.returns, try returns.finish(try returns.parameter("value")));
        var clause = try self.body(result.clause);
        const reply = try clause.call(function, &.{try clause.parameter("payload")});
        const resumed = try clause.resumeValue(try clause.parameter("resume"), reply);
        try self.define(result.clause, try clause.finish(resumed));
        return result;
    }
};

/// Deliberate bridge to existing source libraries. Raw IDs have no recoverable
/// historical builder provenance; callers must supply IDs from `author.raw`.
pub const Interop = struct {
    pub fn rawValue(body: *Body, value: Value) Error!p.Id {
        try body.check(value);
        return value.id;
    }

    pub fn adoptValue(body: *Body, id: p.Id, schema: Schema) Error!Value {
        try body.ensureOpen();
        var value = try body.author.adoptValue(id, schema);
        value.scope = body.scope;
        return value;
    }

    pub fn term(body: *Body, id: p.Id, result: Schema) Error!Value {
        try body.ensureOpen();
        try body.author.checkSchema(result);
        if (id >= body.author.raw.terms.items.len) return error.InvalidReference;
        return body.append(id, result);
    }

    pub fn terminal(body: *Body, id: p.Id, result: Schema) Error!Block {
        try body.ensureOpen();
        try body.author.checkSchema(result);
        if (id >= body.author.raw.terms.items.len) return error.InvalidReference;
        return body.close(id, result);
    }

    pub fn lambdaAs(body: *Body, function: Function, schema: Schema) Error!Callable {
        try body.ensureOpen();
        try body.author.checkSchema(schema);
        if (function.owner != body.author) return error.ForeignBuilder;
        const shape = body.author.raw.schemas.items[@intCast(schema.id)];
        if (shape != .internal or shape.internal != .computation) return error.TypeMismatch;
        const signature = shape.internal.computation;
        if (signature.parameters.len != function.parameters.len or
            signature.result != function.result.id or
            !std.mem.eql(p.Id, signature.effects, function.effects) or
            !std.mem.eql(p.Id, signature.regions, function.regions)) return error.TypeMismatch;
        for (signature.parameters, function.parameters) |id, parameter| {
            if (id != parameter.schema.id) return error.TypeMismatch;
        }
        return .{ .value = .{ .owner = body.author, .schema = schema, .id = try body.author.raw.lambda(function.id, schema.id), .scope = body.scope } };
    }

    pub fn rawTerm(block: Block) p.Id {
        return block.term;
    }
};

pub const Body = struct {
    author: *Builder,
    scope: *Scope,
    function: ?Function = null,
    steps: std.ArrayList(Step) = .empty,

    fn ensureOpen(self: *Body) Error!void {
        if (!self.scope.open) {
            self.author.report(.closed_body, self.scope.name, null, null, null, null);
            return error.ClosedBody;
        }
    }

    fn check(self: *Body, value: Value) Error!void {
        try self.ensureOpen();
        if (value.owner != self.author or value.schema.owner != self.author) {
            self.author.report(.foreign_builder, "value", null, null, null, self.scope.name);
            return error.ForeignBuilder;
        }
        var ancestor: ?*Scope = self.scope;
        while (ancestor) |scope| : (ancestor = scope.parent) {
            if (value.scope == scope) return;
        }
        if (value.scope != null) {
            self.author.report(.out_of_scope, "value", null, null, value.scope.?.name, self.scope.name);
            return error.OutOfScope;
        }
    }

    pub fn parameter(self: *Body, name: []const u8) Error!Value {
        try self.ensureOpen();
        const function = self.function orelse return error.InvalidArgument;
        for (function.parameters, 0..) |named, index| if (std.mem.eql(u8, name, named.name)) {
            return .{ .owner = self.author, .id = try self.author.raw.reference(self.author.raw.parameter(function.id, index)), .schema = named.schema, .scope = self.scope };
        };
        return error.InvalidArgument;
    }

    pub fn child(self: *Body, name: []const u8) Error!Body {
        try self.ensureOpen();
        const scope = try self.author.raw.allocator().create(Scope);
        scope.* = .{ .parent = self.scope, .name = try self.author.raw.allocator().dupe(u8, name) };
        return .{ .author = self.author, .scope = scope };
    }

    fn append(self: *Body, term: p.Id, result: Schema) Error!Value {
        try self.ensureOpen();
        const variable = try self.author.raw.variable(result.id);
        try self.steps.append(self.author.raw.allocator(), .{ .variable = variable, .term = term });
        return .{ .owner = self.author, .id = try self.author.raw.reference(variable), .schema = result, .scope = self.scope };
    }

    /// Evaluate one symbolic value once and bind its runtime result for reuse.
    /// Reusing an unbound lambda expression can construct distinct closures.
    pub fn bindValue(self: *Body, value: Value) Error!Value {
        try self.check(value);
        return self.append(try self.author.raw.pure(value.id), value.schema);
    }

    pub fn perform(self: *Body, effect: Effect, payload: Value) Error!Value {
        try self.check(payload);
        if (effect.owner != self.author) return error.ForeignBuilder;
        if (!effect.external) return error.InvalidCapability;
        if (payload.schema.id != effect.payload.id) {
            self.author.report(.schema_mismatch, "operation payload", effect.payload.id, payload.schema.id, null, self.scope.name);
            return error.TypeMismatch;
        }
        return self.append(try self.author.raw.term(.{ .perform = .{ .effect = effect.id, .payload = payload.id } }), effect.result);
    }

    pub fn performLocal(self: *Body, effect: Effect, capability: Value, payload: Value) Error!Value {
        try self.check(payload);
        try self.check(capability);
        if (effect.owner != self.author or effect.external) return error.InvalidCapability;
        const shape = self.author.raw.schemas.items[@intCast(capability.schema.id)];
        if (shape != .internal or shape.internal != .capability or shape.internal.capability != effect.id) {
            self.author.report(.capability_mismatch, "operation capability", null, capability.schema.id, null, self.scope.name);
            return error.InvalidCapability;
        }
        if (payload.schema.id != effect.payload.id) return error.TypeMismatch;
        return self.append(try self.author.raw.term(.{ .perform = .{
            .effect = effect.id,
            .capability = capability.id,
            .payload = payload.id,
        } }), effect.result);
    }

    pub fn resumeValue(self: *Body, resumption: Value, argument: Value) Error!Value {
        try self.check(resumption);
        try self.check(argument);
        const shape = self.author.raw.schemas.items[@intCast(resumption.schema.id)];
        if (shape != .internal or shape.internal != .resumption) return error.TypeMismatch;
        const signature = shape.internal.resumption;
        if (argument.schema.id != signature.input) {
            self.author.report(.schema_mismatch, "resumption input", signature.input, argument.schema.id, null, self.scope.name);
            return error.TypeMismatch;
        }
        return self.append(try self.author.raw.term(.{ .resume_value = .{
            .resumption = resumption.id,
            .argument = argument.id,
        } }), .{ .owner = self.author, .id = signature.answer });
    }

    pub fn resumeWith(self: *Body, resumption: Value, argument: Value, successor: Interpretation, state: []const Value) Error!Value {
        try self.check(resumption);
        try self.check(argument);
        if (successor.owner != self.author or successor.mode != .shallow) return error.InvalidCapability;
        const shape = self.author.raw.schemas.items[@intCast(resumption.schema.id)];
        if (shape != .internal or shape.internal != .resumption) return error.TypeMismatch;
        const signature = shape.internal.resumption;
        if (signature.mode != .shallow or signature.effect != successor.operation.id or
            signature.input != argument.schema.id)
        {
            self.author.report(.handler_mismatch, "shallow resumption", signature.input, argument.schema.id, null, self.scope.name);
            return error.TypeMismatch;
        }
        if (state.len != successor.state.len) return error.InvalidArgument;
        const ids = try self.author.raw.allocator().alloc(p.Id, state.len);
        for (state, successor.state, ids) |value, named, *id| {
            try self.check(value);
            if (value.schema.id != named.schema.id) return error.TypeMismatch;
            id.* = value.id;
        }
        return self.append(try self.author.raw.term(.{ .resume_with = .{
            .resumption = resumption.id,
            .argument = argument.id,
            .handler = successor.id,
            .state = ids,
        } }), successor.answer);
    }

    pub fn resumeComputation(self: *Body, resumption: Value, computation: Callable) Error!Value {
        try self.check(resumption);
        try self.check(computation.value);
        const shape = self.author.raw.schemas.items[@intCast(resumption.schema.id)];
        if (shape != .internal or shape.internal != .resumption) return error.TypeMismatch;
        const signature = shape.internal.resumption;
        const work = self.author.raw.schemas.items[@intCast(computation.value.schema.id)];
        if (work != .internal or work.internal != .computation or
            work.internal.computation.parameters.len != 0 or
            work.internal.computation.result != signature.input) return error.TypeMismatch;
        return self.append(try self.author.raw.term(.{ .resume_computation = .{
            .resumption = resumption.id,
            .computation = computation.value.id,
        } }), .{ .owner = self.author, .id = signature.answer });
    }

    pub fn handle(self: *Body, interpretation: Interpretation, callable: Callable, arguments: []const Value, state: []const Value) Error!Value {
        try self.check(callable.value);
        if (interpretation.owner != self.author) return error.ForeignBuilder;
        if (state.len != interpretation.state.len) return error.InvalidArgument;
        const state_ids = try self.author.raw.allocator().alloc(p.Id, state.len);
        for (state, interpretation.state, state_ids) |value, named, *id| {
            try self.check(value);
            if (value.schema.id != named.schema.id) return error.TypeMismatch;
            id.* = value.id;
        }
        const argument_ids = try self.author.raw.allocator().alloc(p.Id, arguments.len);
        const shape = self.author.raw.schemas.items[@intCast(callable.value.schema.id)];
        if (shape != .internal or shape.internal != .computation or
            shape.internal.computation.result != interpretation.input.id) return error.TypeMismatch;
        const parameters = shape.internal.computation.parameters;
        const offset: usize = if (parameters.len == arguments.len + 1) 1 else if (parameters.len == arguments.len) 0 else return error.InvalidArgument;
        if (offset == 1) {
            const cap = self.author.raw.schemas.items[@intCast(parameters[0])];
            if (cap != .internal or cap.internal != .capability or
                cap.internal.capability != interpretation.operation.id) return error.InvalidCapability;
        }
        for (arguments, argument_ids, 0..) |value, *id, index| {
            try self.check(value);
            if (value.schema.id != parameters[index + offset]) {
                self.author.report(.argument_mismatch, "handled body argument", parameters[index + offset], value.schema.id, null, self.scope.name);
                return error.TypeMismatch;
            }
            id.* = value.id;
        }
        return self.append(try self.author.raw.term(.{ .handle = .{
            .handler = interpretation.id,
            .body = callable.value.id,
            .arguments = argument_ids,
            .state = state_ids,
        } }), interpretation.answer);
    }

    pub fn protect(self: *Body, work: Callable, cleanup: Callable, arguments: []const Value, resource: ?Value, loan_region: ?Region) Error!Value {
        try self.check(work.value);
        try self.check(cleanup.value);
        const shape = self.author.raw.schemas.items[@intCast(work.value.schema.id)];
        if (shape != .internal or shape.internal != .computation) return error.TypeMismatch;
        const ids = try self.author.raw.allocator().alloc(p.Id, arguments.len);
        for (arguments, ids) |value, *id| {
            try self.check(value);
            id.* = value.id;
        }
        if (resource) |value| try self.check(value);
        if (loan_region) |region_handle| if (region_handle.owner != self.author or
            region_handle.id >= self.author.raw.region_count) return error.InvalidReference;
        return self.append(try self.author.raw.term(.{ .protect = .{
            .body = work.value.id,
            .cleanup = cleanup.value.id,
            .arguments = ids,
            .resource = if (resource) |value| value.id else null,
            .loan_region = if (loan_region) |region_handle| region_handle.id else null,
        } }), .{ .owner = self.author, .id = shape.internal.computation.result });
    }

    pub fn withRegion(self: *Body, region_handle: Region, work: Callable, arguments: []const Value) Error!Value {
        try self.check(work.value);
        if (region_handle.owner != self.author or region_handle.id >= self.author.raw.region_count)
            return error.InvalidReference;
        const shape = self.author.raw.schemas.items[@intCast(work.value.schema.id)];
        if (shape != .internal or shape.internal != .computation) return error.TypeMismatch;
        const ids = try self.author.raw.allocator().alloc(p.Id, arguments.len);
        for (arguments, ids) |value, *id| {
            try self.check(value);
            id.* = value.id;
        }
        return self.append(try self.author.raw.term(.{ .with_region = .{
            .region = region_handle.id,
            .body = work.value.id,
            .arguments = ids,
        } }), .{ .owner = self.author, .id = shape.internal.computation.result });
    }

    pub fn dispose(self: *Body, value: Value) Error!Value {
        try self.check(value);
        return self.append(try self.author.raw.term(.{ .dispose = value.id }), try self.author.scalar(void));
    }

    pub fn call(self: *Body, function: Function, arguments: []const Value) Error!Value {
        try self.ensureOpen();
        if (function.owner != self.author) return error.ForeignBuilder;
        if (arguments.len != function.parameters.len) return error.InvalidArgument;
        const ids = try self.author.raw.allocator().alloc(p.Id, arguments.len);
        for (arguments, function.parameters, ids) |argument, named, *id| {
            try self.check(argument);
            if (argument.schema.id != named.schema.id) {
                self.author.report(.argument_mismatch, function.name, named.schema.id, argument.schema.id, null, self.scope.name);
                return error.TypeMismatch;
            }
            id.* = argument.id;
        }
        return self.append(try self.author.raw.term(.{ .call = .{ .function = function.id, .arguments = ids } }), function.result);
    }

    pub fn lambda(self: *Body, function: Function, captures: []const Schema, use: p.Use) Error!Callable {
        try self.ensureOpen();
        if (function.owner != self.author) return error.ForeignBuilder;
        const params = try self.author.raw.allocator().alloc(p.Id, function.parameters.len);
        for (function.parameters, params) |named, *id| id.* = named.schema.id;
        const bounds = try self.author.raw.allocator().alloc(p.Id, captures.len);
        for (captures, bounds) |schema, *id| {
            try self.author.checkSchema(schema);
            id.* = schema.id;
        }
        const schema = try self.author.dynamicSchema(.{ .internal = .{ .computation = .{
            .parameters = params,
            .result = function.result.id,
            .effects = function.effects,
            .capture_bound = bounds,
            .use = use,
            .regions = function.regions,
        } } });
        return .{ .value = .{ .owner = self.author, .schema = schema, .id = try self.author.raw.lambda(function.id, schema.id), .scope = self.scope } };
    }

    pub fn apply(self: *Body, callable: Callable, arguments: []const Value) Error!Value {
        try self.check(callable.value);
        const shape = self.author.raw.schemas.items[@intCast(callable.value.schema.id)];
        if (shape != .internal or shape.internal != .computation) return error.TypeMismatch;
        const signature = shape.internal.computation;
        if (arguments.len != signature.parameters.len) return error.InvalidArgument;
        const ids = try self.author.raw.allocator().alloc(p.Id, arguments.len);
        for (arguments, signature.parameters, ids) |argument, schema_id, *id| {
            try self.check(argument);
            if (argument.schema.id != schema_id) {
                self.author.report(.argument_mismatch, "callable argument", schema_id, argument.schema.id, null, self.scope.name);
                return error.TypeMismatch;
            }
            id.* = argument.id;
        }
        return self.append(try self.author.raw.term(.{ .apply = .{
            .computation = callable.value.id,
            .arguments = ids,
        } }), .{ .owner = self.author, .id = signature.result });
    }

    pub fn asCallable(self: *Body, value: Value) Error!Callable {
        try self.check(value);
        const shape = self.author.raw.schemas.items[@intCast(value.schema.id)];
        if (shape != .internal or shape.internal != .computation) return error.TypeMismatch;
        return .{ .value = value };
    }

    pub fn product(self: *Body, record: Record, fields: []const NamedValue) Error!Value {
        try self.ensureOpen();
        if (record.owner != self.author) return error.ForeignBuilder;
        if (fields.len != record.fields.len) return error.InvalidField;
        const ids = try self.author.raw.allocator().alloc(p.Id, fields.len);
        for (record.fields, ids) |declared, *id| {
            var found: ?Value = null;
            for (fields) |provided| if (std.mem.eql(u8, provided.name, declared.name)) {
                if (found != null) return error.DuplicateName;
                found = provided.value;
            };
            const value = found orelse return error.InvalidField;
            try self.check(value);
            if (value.schema.id != declared.schema.id) {
                self.author.report(.field_mismatch, declared.name, declared.schema.id, value.schema.id, null, self.scope.name);
                return error.TypeMismatch;
            }
            id.* = value.id;
        }
        return .{ .owner = self.author, .schema = record.schema, .scope = self.scope, .id = try self.author.raw.primitive(record.schema.id, .product, ids, 0) };
    }

    pub fn field(self: *Body, record: Record, value: Value, name: []const u8) Error!Value {
        try self.check(value);
        if (record.owner != self.author) return error.ForeignBuilder;
        if (value.schema.id != record.schema.id) return error.TypeMismatch;
        for (record.fields, 0..) |declared, index| if (std.mem.eql(u8, name, declared.name)) {
            return .{ .owner = self.author, .schema = declared.schema, .scope = self.scope, .id = try self.author.raw.primitive(declared.schema.id, .field, &.{value.id}, index) };
        };
        self.author.report(.field_mismatch, name, null, value.schema.id, null, self.scope.name);
        return error.InvalidField;
    }

    pub fn inject(self: *Body, variant: Variant, name: []const u8, payload: Value) Error!Value {
        try self.check(payload);
        if (variant.owner != self.author) return error.ForeignBuilder;
        for (variant.alternatives, 0..) |alternative, index| if (std.mem.eql(u8, name, alternative.name)) {
            if (payload.schema.id != alternative.schema.id) {
                self.author.report(.field_mismatch, name, alternative.schema.id, payload.schema.id, null, self.scope.name);
                return error.TypeMismatch;
            }
            return .{ .owner = self.author, .schema = variant.schema, .scope = self.scope, .id = try self.author.raw.primitive(variant.schema.id, .variant, &.{payload.id}, index) };
        };
        return error.InvalidField;
    }

    pub fn variantCase(self: *Body, variant: Variant, name: []const u8) Error!MatchCase {
        try self.ensureOpen();
        if (variant.owner != self.author) return error.ForeignBuilder;
        for (variant.alternatives, 0..) |alternative, index| if (std.mem.eql(u8, name, alternative.name)) {
            const body = try self.child(name);
            const variable = try self.author.raw.variable(alternative.schema.id);
            return .{ .body = body, .variant = variant, .index = index, .variable = variable, .payload = .{ .owner = self.author, .schema = alternative.schema, .scope = body.scope, .id = try self.author.raw.reference(variable) } };
        };
        return error.InvalidField;
    }

    pub fn matchVariant(self: *Body, variant: Variant, value: Value, branches: []const FinishedCase) Error!Value {
        try self.check(value);
        if (variant.owner != self.author) return error.ForeignBuilder;
        if (value.schema.id != variant.schema.id or branches.len != variant.alternatives.len)
            return error.TypeMismatch;
        const cases = try self.author.raw.allocator().alloc(source.ast.SumCase, branches.len);
        var result: ?Schema = null;
        for (branches, 0..) |branch, position| {
            if (branch.variant.owner != self.author or branch.variant.schema.id != variant.schema.id or
                branch.block.scope.parent != self.scope or branch.index >= cases.len) return error.InvalidBranch;
            for (branches[0..position]) |other| if (branch.index == other.index) return error.InvalidBranch;
            if (result) |expected| {
                if (expected.id != branch.block.result.id) return error.TypeMismatch;
            } else result = branch.block.result;
            cases[branch.index] = .{ .variable = branch.variable, .body = branch.block.term };
        }
        return self.append(try self.author.raw.term(.{ .match_sum = .{
            .value = value.id,
            .cases = cases,
        } }), result orelse return error.InvalidBranch);
    }

    pub fn singletonSequence(self: *Body, item: Value) Error!Value {
        try self.check(item);
        const sequence = try self.author.sequenceSchema(item.schema);
        return .{ .owner = self.author, .schema = sequence, .scope = self.scope, .id = try self.author.raw.primitive(sequence.id, .sequence, &.{item.id}, 0) };
    }

    pub fn concatSequences(self: *Body, left: Value, right: Value) Error!Value {
        try self.check(left);
        try self.check(right);
        if (left.schema.id != right.schema.id) return error.TypeMismatch;
        const shape = self.author.raw.schemas.items[@intCast(left.schema.id)];
        if (shape != .seq) return error.TypeMismatch;
        return .{ .owner = self.author, .schema = left.schema, .scope = self.scope, .id = try self.author.raw.primitive(left.schema.id, .sequence_concat, &.{ left.id, right.id }, 0) };
    }

    pub fn checkedAdd(self: *Body, left: Value, right: Value, failure: Value) Error!Value {
        try self.check(left);
        try self.check(right);
        try self.check(failure);
        if (left.schema.id != right.schema.id) return error.TypeMismatch;
        const shape = self.author.raw.schemas.items[@intCast(left.schema.id)];
        if (shape != .u8 and shape != .u16 and shape != .u32 and shape != .u64 and
            shape != .i8 and shape != .i16 and shape != .i32 and shape != .i64) return error.TypeMismatch;
        const fault = try self.author.raw.failureLiteral(failure.id);
        return .{ .owner = self.author, .schema = left.schema, .scope = self.scope, .id = try self.author.raw.value(.{
            .schema = left.schema.id,
            .expression = .{ .primitive = .{
                .opcode = .integer_add,
                .operands = &.{ left.id, right.id },
                .failures = &.{.{ .kind = .arithmetic_overflow, .value = fault }},
            } },
        }) };
    }

    pub fn equal(self: *Body, left: Value, right: Value) Error!Value {
        try self.check(left);
        try self.check(right);
        if (left.schema.id != right.schema.id) return error.TypeMismatch;
        const boolean = try self.author.scalar(bool);
        return .{ .owner = self.author, .schema = boolean, .scope = self.scope, .id = try self.author.raw.primitive(boolean.id, .equal, &.{ left.id, right.id }, 0) };
    }

    pub fn booleanNot(self: *Body, value: Value) Error!Value {
        try self.check(value);
        const boolean = try self.author.scalar(bool);
        if (value.schema.id != boolean.id) return error.TypeMismatch;
        return .{ .owner = self.author, .schema = boolean, .scope = self.scope, .id = try self.author.raw.primitive(boolean.id, .boolean_not, &.{value.id}, 0) };
    }

    pub fn select(self: *Body, condition: Value, when_true: Block, when_false: Block) Error!Value {
        try self.check(condition);
        const boolean = try self.author.scalar(bool);
        if (condition.schema.id != boolean.id) return error.TypeMismatch;
        if (when_true.owner != self.author or when_false.owner != self.author) return error.ForeignBuilder;
        if (when_true.scope.parent != self.scope or when_false.scope.parent != self.scope or
            when_true.scope == when_false.scope) return error.InvalidBranch;
        if (when_true.result.id != when_false.result.id) {
            self.author.report(.branch_mismatch, "conditional result", when_true.result.id, when_false.result.id, when_true.scope.name, when_false.scope.name);
            return error.TypeMismatch;
        }
        return self.append(try self.author.raw.term(.{ .conditional = .{
            .condition = condition.id,
            .when_true = when_true.term,
            .when_false = when_false.term,
        } }), when_true.result);
    }

    pub fn finish(self: *Body, result: Value) Error!Block {
        try self.check(result);
        return self.close(try self.author.raw.pure(result.id), result.schema);
    }

    pub fn fail(self: *Body, failure: Value, expected_result: Schema) Error!Block {
        try self.check(failure);
        try self.author.checkSchema(expected_result);
        return self.close(try self.author.raw.term(.{ .fail = failure.id }), expected_result);
    }

    fn close(self: *Body, terminal: p.Id, result: Schema) Error!Block {
        try self.ensureOpen();
        var term = terminal;
        var index = self.steps.items.len;
        while (index != 0) {
            index -= 1;
            const step = self.steps.items[index];
            term = try self.author.raw.bind(step.variable, step.term, term);
        }
        self.scope.open = false;
        return .{ .owner = self.author, .term = term, .result = result, .scope = self.scope };
    }
};
