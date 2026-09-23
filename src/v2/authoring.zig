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

pub const Category = enum {
    foreign_builder,
    out_of_scope,
    closed_body,
    schema_mismatch,
    argument_mismatch,
    field_mismatch,
    branch_mismatch,
    capability_mismatch,
};

/// The most recent authoring failure. Text labels live in the source arena.
pub const Diagnostic = struct {
    category: Category,
    entity: []const u8,
    expected: ?p.Id = null,
    actual: ?p.Id = null,
    introduced_in: ?[]const u8 = null,
    used_in: ?[]const u8 = null,

    pub fn render(self: Diagnostic, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{s}: {s}", .{ @tagName(self.category), self.entity });
        if (self.expected) |id| try writer.print("; expected schema {d}", .{id});
        if (self.actual) |id| try writer.print("; actual schema {d}", .{id});
        if (self.introduced_in) |name| try writer.print("; introduced in {s}", .{name});
        if (self.used_in) |name| try writer.print("; used in {s}", .{name});
    }
};

pub const Schema = struct { owner: *Builder, id: p.Id };
pub const Effect = struct {
    owner: *Builder,
    id: p.Id,
    payload: Schema,
    result: Schema,
    external: bool,
};
pub const Parameter = struct { name: []const u8, schema: Schema };
pub const Function = struct {
    owner: *Builder,
    id: p.Id,
    name: []const u8,
    parameters: []const Parameter,
    result: Schema,
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

const Scope = struct {
    parent: ?*Scope,
    name: []const u8,
    open: bool = true,
};
const Step = struct { variable: p.Id, term: p.Id };

pub const Builder = struct {
    raw: *source.Builder,
    diagnostic: ?Diagnostic = null,

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

    pub fn dynamicSchema(self: *Builder, shape: p.Schema) Error!Schema {
        return .{ .owner = self, .id = try self.raw.schema(shape) };
    }

    pub fn productSchema(self: *Builder, fields: []const Schema) Error!Schema {
        const ids = try self.raw.allocator().alloc(p.Id, fields.len);
        for (fields, ids) |field, *id| {
            try self.checkSchema(field);
            id.* = field.id;
        }
        return self.dynamicSchema(.{ .product = ids });
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
        return .{ .owner = self, .id = try self.raw.declare(param_ids, result.id, effect_ids, &.{}), .name = try self.raw.allocator().dupe(u8, name), .parameters = copied, .result = result };
    }

    pub fn body(self: *Builder, function: Function) Error!Body {
        if (function.owner != self) return error.ForeignBuilder;
        const scope = try self.raw.allocator().create(Scope);
        scope.* = .{ .parent = null, .name = function.name };
        return .{ .author = self, .scope = scope, .function = function };
    }

    pub fn define(self: *Builder, function: Function, block: Block) Error!void {
        if (function.owner != self or block.owner != self) return error.ForeignBuilder;
        if (block.scope.parent != null) return error.InvalidBranch;
        if (block.result.id != function.result.id) {
            self.report(.schema_mismatch, function.name, function.result.id, block.result.id, null, null);
            return error.TypeMismatch;
        }
        try self.raw.define(function.id, block.term);
    }

    pub fn module(self: *Builder, entry: Function, failure: Schema) Error!source.Module {
        if (entry.owner != self) return error.ForeignBuilder;
        try self.checkSchema(failure);
        return self.raw.module(entry.id, failure.id);
    }

    pub fn literal(self: *Builder, comptime T: type, value: T) Error!Value {
        return .{ .owner = self, .id = try self.raw.constant(T, value), .schema = try self.scalar(T) };
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
        var term = try self.author.raw.pure(result.id);
        var index = self.steps.items.len;
        while (index != 0) {
            index -= 1;
            const step = self.steps.items[index];
            term = try self.author.raw.bind(step.variable, step.term, term);
        }
        self.scope.open = false;
        return .{ .owner = self.author, .term = term, .result = result.schema, .scope = self.scope };
    }
};
