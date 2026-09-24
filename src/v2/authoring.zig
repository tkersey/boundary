// Copyright (c) 2026 Boundary contributors. MIT license.
//! Checked, forward staged construction over the existing source language.
const std = @import("std");
const source = @import("source.zig");
const p = @import("boundary_data").program;
pub const Module = struct { origin: *const ModuleOrigin };
pub const Compiled = source.Compiled;

/// The application callback constructs source; execution remains in World.
pub fn lower(allocator: std.mem.Allocator, comptime Application: type) !Compiled {
    var raw = source.Builder.init(allocator);
    defer raw.deinit();
    var builder = Builder.init(&raw);
    return builder.compile(allocator, try Application.emit(&builder));
}

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
    expected_count: ?usize = null,
    actual_count: ?usize = null,
    introduced_in: ?[]const u8 = null,
    used_in: ?[]const u8 = null,
    relationship: ?[]const u8 = null,
    source_detail: ?source.Diagnostic = null,

    pub fn render(self: Diagnostic, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{s}: {s}", .{ @tagName(self.category), self.entity });
        if (self.expected) |id| try writer.print("; expected schema {d}", .{id});
        if (self.actual) |id| try writer.print("; actual schema {d}", .{id});
        if (self.expected_count) |count| try writer.print("; expected {d}", .{count});
        if (self.actual_count) |count| try writer.print("; actual {d}", .{count});
        if (self.introduced_in) |name| try writer.print("; introduced in {s}", .{name});
        if (self.used_in) |name| try writer.print("; used in {s}", .{name});
        if (self.relationship) |relation| try writer.print("; {s}", .{relation});
        if (self.source_detail) |detail| {
            if (detail.code) |code| try writer.print("; source check: {s}", .{@errorName(code)});
            if (detail.function) |id| try writer.print("; function {d}", .{id});
            if (detail.term) |id| try writer.print("; term {d}", .{id});
            if (detail.variable) |id| try writer.print("; variable {d}", .{id});
        }
    }
};

pub const OwnedDiagnostic = struct {
    allocator: std.mem.Allocator,
    detail: Diagnostic,

    pub fn copy(allocator: std.mem.Allocator, borrowed: Diagnostic) !OwnedDiagnostic {
        const entity = try allocator.dupe(u8, borrowed.entity);
        errdefer allocator.free(entity);
        const introduced = if (borrowed.introduced_in) |name|
            try allocator.dupe(u8, name)
        else
            null;
        errdefer if (introduced) |name| allocator.free(name);
        const used = if (borrowed.used_in) |name|
            try allocator.dupe(u8, name)
        else
            null;
        errdefer if (used) |name| allocator.free(name);
        const relationship = if (borrowed.relationship) |name|
            try allocator.dupe(u8, name)
        else
            null;
        errdefer if (relationship) |name| allocator.free(name);
        var detail = borrowed;
        detail.entity = entity;
        detail.introduced_in = introduced;
        detail.used_in = used;
        detail.relationship = relationship;
        return .{ .allocator = allocator, .detail = detail };
    }

    pub fn deinit(self: *OwnedDiagnostic) void {
        self.allocator.free(self.detail.entity);
        if (self.detail.introduced_in) |name| self.allocator.free(name);
        if (self.detail.used_in) |name| self.allocator.free(name);
        if (self.detail.relationship) |name| self.allocator.free(name);
        self.* = undefined;
    }
};

pub const Schema = struct {
    owner: *Builder,
    id: p.Id,
    layout: ?*const NamedLayout = null,
    structure: ?*const StructureInfo = null,
    callable: ?*const CallableInfo = null,
    resumption: ?*const ResumptionInfo = null,
    resource: ?*const Schema = null,
    borrowed: ?*const Schema = null,
};
const LayoutKind = enum { record, variant };
const NamedLayout = struct {
    kind: LayoutKind,
    fields: []const Field,
};
const StructureKind = enum { product, sum, sequence, cell, exit_info };
const StructureInfo = struct { kind: StructureKind, children: []const Schema };
const CallableInfo = struct { parameters: []const Schema, result: Schema };
const ResumptionInfo = struct { input: Schema, answer: Schema };

const SchemaPair = struct { left: Schema, right: Schema };

fn sameMetadataPointers(left: Schema, right: Schema) bool {
    return left.structure == right.structure and left.callable == right.callable and
        left.resumption == right.resumption and left.resource == right.resource and
        left.borrowed == right.borrowed;
}

fn hasNamedMetadata(schema: Schema, allocator: std.mem.Allocator) Error!bool {
    var pending: std.ArrayList(Schema) = .empty;
    var seen: std.AutoHashMapUnmanaged(Schema, void) = .empty;
    try pending.append(allocator, schema);
    while (pending.pop()) |current| {
        if (current.layout != null) return true;
        if (seen.contains(current)) continue;
        try seen.put(allocator, current, {});
        if (current.structure) |info| for (info.children) |child| try pending.append(allocator, child);
        if (current.callable) |info| {
            try pending.append(allocator, info.result);
            for (info.parameters) |parameter| try pending.append(allocator, parameter);
        }
        if (current.resumption) |info| {
            try pending.append(allocator, info.input);
            try pending.append(allocator, info.answer);
        }
        if (current.resource) |representation| try pending.append(allocator, representation.*);
        if (current.borrowed) |owned| try pending.append(allocator, owned.*);
    }
    return false;
}

fn sameSchema(left: Schema, right: Schema) Error!bool {
    if (left.owner != right.owner or left.id != right.id or left.layout != right.layout)
        return false;
    if (sameMetadataPointers(left, right)) return true;
    var scratch = std.heap.ArenaAllocator.init(left.owner.raw.arena.child_allocator);
    defer scratch.deinit();
    const allocator = scratch.allocator();
    var pending: std.ArrayList(SchemaPair) = .empty;
    var seen: std.AutoHashMapUnmanaged(SchemaPair, void) = .empty;
    try pending.append(allocator, .{ .left = left, .right = right });
    while (pending.pop()) |pair| {
        const a = pair.left;
        const b = pair.right;
        if (a.owner != b.owner or a.id != b.id or a.layout != b.layout) return false;
        if (sameMetadataPointers(a, b)) continue;
        if (seen.contains(pair)) continue;
        try seen.put(allocator, pair, {});
        if (a.structure != b.structure) {
            if (a.structure) |x| {
                if (b.structure) |y| {
                    if (x.kind != y.kind or x.children.len != y.children.len) return false;
                    for (x.children, y.children) |child_a, child_b|
                        try pending.append(allocator, .{ .left = child_a, .right = child_b });
                } else if (try hasNamedMetadata(a, allocator)) return false;
            } else if (try hasNamedMetadata(b, allocator)) return false;
        }
        if (a.callable != b.callable) {
            if (a.callable) |x| {
                if (b.callable) |y| {
                    if (x.parameters.len != y.parameters.len) return false;
                    try pending.append(allocator, .{ .left = x.result, .right = y.result });
                    for (x.parameters, y.parameters) |parameter_a, parameter_b|
                        try pending.append(allocator, .{ .left = parameter_a, .right = parameter_b });
                } else if (try hasNamedMetadata(a, allocator)) return false;
            } else if (try hasNamedMetadata(b, allocator)) return false;
        }
        if (a.resumption != b.resumption) {
            if (a.resumption) |x| {
                if (b.resumption) |y| {
                    try pending.append(allocator, .{ .left = x.input, .right = y.input });
                    try pending.append(allocator, .{ .left = x.answer, .right = y.answer });
                } else if (try hasNamedMetadata(a, allocator)) return false;
            } else if (try hasNamedMetadata(b, allocator)) return false;
        }
        if (a.resource != b.resource) {
            if (a.resource) |x| {
                if (b.resource) |y| {
                    try pending.append(allocator, .{ .left = x.*, .right = y.* });
                } else if (try hasNamedMetadata(a, allocator)) return false;
            } else if (try hasNamedMetadata(b, allocator)) return false;
        }
        if (a.borrowed != b.borrowed) {
            if (a.borrowed) |x| {
                if (b.borrowed) |y| {
                    try pending.append(allocator, .{ .left = x.*, .right = y.* });
                } else if (try hasNamedMetadata(a, allocator)) return false;
            } else if (try hasNamedMetadata(b, allocator)) return false;
        }
    }
    return true;
}

fn hasAuthoringMetadata(schema: Schema) bool {
    return schema.layout != null or schema.structure != null or schema.callable != null or
        schema.resumption != null or schema.resource != null or
        schema.borrowed != null;
}
pub const Region = struct { owner: *Builder, id: p.Id };
pub const Effect = struct {
    owner: *Builder,
    id: p.Id,
    payload: Schema,
    result: Schema,
    external: bool,
    bodies: []const Parameter = &.{},
    use_site_effects: []const p.Id = &.{},
    origin: ?*const EffectOrigin = null,
};
pub const Parameter = struct { name: []const u8, schema: Schema };
pub const Field = Parameter;
pub const NamedValue = struct { name: []const u8, value: Value };
pub const Record = struct { owner: *Builder, schema: Schema };
pub const Variant = struct { owner: *Builder, schema: Schema };
pub const Function = struct {
    owner: *Builder,
    id: p.Id,
    name: []const u8,
    parameters: []const Parameter,
    result: Schema,
    effects: []const p.Id,
    regions: []const p.Id,
    origin: ?*const FunctionOrigin = null,
};
pub const Value = struct {
    owner: *Builder,
    id: p.Id,
    schema: Schema,
    scope: ?*Scope = null,
    origin: ?*const ValueOrigin = null,
};
pub const FailureLiteral = struct { origin: *const FailureLiteralInfo };
pub const Block = struct {
    owner: *Builder,
    term: p.Id,
    result: Schema,
    scope: *Scope,
    origin: ?*const BlockOrigin = null,
};
pub const Callable = struct { value: Value };
pub const FinishedCase = struct {
    block: Block,
    origin: *const CaseOrigin,
};
pub const MatchCase = struct {
    body: Body,
    payload: Value,
    origin: *CaseOrigin,

    pub fn finish(self: *MatchCase, result: Value) Error!FinishedCase {
        const author = self.body.author;
        if (author.case_origins.get(self.body.scope) != self.origin) {
            author.report(.branch_mismatch, "variant case origin", null, null, null, self.body.scope.name);
            return error.InvalidBranch;
        }
        const block = try self.body.finish(result);
        return .{ .block = block, .origin = self.origin };
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
    origin: ?*const InterpretationOrigin = null,
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
    steps: std.ArrayList(Step) = .empty,
};
const CaseOrigin = struct {
    variant: Schema,
    index: usize,
    variable: p.Id,
    scope: *Scope,
};
const FunctionOrigin = struct {
    parameters: []const Parameter,
    result: Schema,
    effects: []const p.Id,
    regions: []const p.Id,
};
const EffectOrigin = struct {
    id: p.Id,
    payload: Schema,
    result: Schema,
    external: bool,
    bodies: []const Parameter,
    use_site_effects: []const p.Id,
};
const BlockOrigin = struct { term: p.Id, result: Schema, scope: *Scope };
const InterpretationOrigin = struct {
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
const ExportedValue = struct { schema: Schema, scope: ?*Scope };
const ExportedTerm = struct { schema: Schema, scope: *Scope };
const ValueOrigin = struct { schema: Schema, scope: ?*Scope };
const FailureLiteralInfo = struct { value: Value, literal: p.Id };
const ModuleOrigin = struct { owner: *Builder, entry: p.Id, failure: Schema };

fn scopeVisible(introduced: ?*Scope, used: *Scope) bool {
    const origin = introduced orelse return true;
    var current: ?*Scope = used;
    while (current) |scope| : (current = scope.parent) {
        if (scope == origin) return true;
    }
    return false;
}
const Step = struct { variable: p.Id, term: p.Id };

pub const Builder = struct {
    raw: *source.Builder,
    diagnostic: ?Diagnostic = null,
    function_names: std.AutoHashMapUnmanaged(p.Id, []const u8) = .empty,
    function_origins: std.AutoHashMapUnmanaged(p.Id, *const FunctionOrigin) = .empty,
    effect_origins: std.AutoHashMapUnmanaged(*const EffectOrigin, void) = .empty,
    block_origins: std.AutoHashMapUnmanaged(*const BlockOrigin, void) = .empty,
    interpretation_origins: std.AutoHashMapUnmanaged(*const InterpretationOrigin, void) = .empty,
    named_layouts: std.ArrayList(*const NamedLayout) = .empty,
    value_origins: std.AutoHashMapUnmanaged(p.Id, *const ValueOrigin) = .empty,
    failure_literals: std.AutoHashMapUnmanaged(*const FailureLiteralInfo, void) = .empty,
    checked_add_failures: std.AutoHashMapUnmanaged(p.Id, Schema) = .empty,
    module_origins: std.AutoHashMapUnmanaged(*const ModuleOrigin, void) = .empty,
    case_origins: std.AutoHashMapUnmanaged(*Scope, *CaseOrigin) = .empty,
    value_exports: std.AutoHashMapUnmanaged(p.Id, ExportedValue) = .empty,
    term_exports: std.AutoHashMapUnmanaged(p.Id, ExportedTerm) = .empty,
    poisoned: bool = false,

    pub fn init(raw: *source.Builder) Builder {
        return .{ .raw = raw };
    }

    fn onError(self: *Builder, err: anyerror) void {
        if (err == error.OutOfMemory) self.poisoned = true;
    }

    fn diagnosticName(self: *Builder, name: []const u8) Error![]const u8 {
        errdefer |err| self.onError(err);
        return self.raw.allocator().dupe(u8, name);
    }

    fn report(self: *Builder, category: Category, entity: []const u8, expected: ?p.Id, actual: ?p.Id, introduced: ?[]const u8, used: ?[]const u8) void {
        self.diagnostic = .{ .category = category, .entity = entity, .expected = expected, .actual = actual, .introduced_in = introduced, .used_in = used };
    }

    fn foreign(self: *Builder, entity: []const u8, used: ?[]const u8) Error!noreturn {
        self.report(.foreign_builder, entity, null, null, null, used);
        return error.ForeignBuilder;
    }

    fn arity(self: *Builder, entity: []const u8, expected: usize, actual: usize, used: ?[]const u8) Error!noreturn {
        self.report(.argument_mismatch, entity, null, null, null, used);
        self.diagnostic.?.expected_count = expected;
        self.diagnostic.?.actual_count = actual;
        self.diagnostic.?.relationship = "argument count";
        return error.InvalidArgument;
    }

    fn issueFunction(self: *Builder, function: Function) Error!Function {
        errdefer |err| self.onError(err);
        const origin = try self.raw.allocator().create(FunctionOrigin);
        origin.* = .{ .parameters = function.parameters, .result = function.result, .effects = function.effects, .regions = function.regions };
        try self.function_origins.put(self.raw.allocator(), function.id, origin);
        var issued = function;
        issued.origin = origin;
        return issued;
    }

    fn checkFunction(self: *Builder, function: Function) Error!void {
        errdefer |err| self.onError(err);
        if (function.owner != self) return try self.foreign("function", null);
        const origin = self.function_origins.get(function.id) orelse {
            self.report(.schema_mismatch, "function origin", null, function.result.id, null, null);
            return error.InvalidSource;
        };
        if (function.origin != origin or
            function.parameters.ptr != origin.parameters.ptr or function.parameters.len != origin.parameters.len or
            function.effects.ptr != origin.effects.ptr or function.effects.len != origin.effects.len or
            function.regions.ptr != origin.regions.ptr or function.regions.len != origin.regions.len or
            !try sameSchema(function.result, origin.result))
        {
            self.report(.schema_mismatch, "function origin", origin.result.id, function.result.id, null, null);
            self.diagnostic.?.relationship = "issued declaration signature";
            return error.TypeMismatch;
        }
    }

    fn issueEffect(self: *Builder, effect: Effect) Error!Effect {
        errdefer |err| self.onError(err);
        const origin = try self.raw.allocator().create(EffectOrigin);
        origin.* = .{ .id = effect.id, .payload = effect.payload, .result = effect.result, .external = effect.external, .bodies = effect.bodies, .use_site_effects = effect.use_site_effects };
        try self.effect_origins.put(self.raw.allocator(), origin, {});
        var issued = effect;
        issued.origin = origin;
        return issued;
    }

    fn checkEffect(self: *Builder, effect: Effect) Error!void {
        errdefer |err| self.onError(err);
        if (effect.owner != self) return try self.foreign("effect", null);
        const origin = effect.origin orelse {
            self.report(.capability_mismatch, "effect origin", null, effect.id, null, null);
            return error.InvalidSource;
        };
        if (!self.effect_origins.contains(origin)) {
            self.report(.capability_mismatch, "effect origin", null, effect.id, null, null);
            return error.InvalidSource;
        }
        if (effect.id != origin.id or effect.external != origin.external or
            effect.bodies.ptr != origin.bodies.ptr or effect.bodies.len != origin.bodies.len or
            effect.use_site_effects.ptr != origin.use_site_effects.ptr or effect.use_site_effects.len != origin.use_site_effects.len or
            !try sameSchema(effect.payload, origin.payload) or !try sameSchema(effect.result, origin.result))
        {
            self.report(.capability_mismatch, "effect origin", origin.payload.id, effect.payload.id, null, null);
            self.diagnostic.?.relationship = "issued operation signature";
            return error.TypeMismatch;
        }
    }

    fn issueBlock(self: *Builder, block: Block) Error!Block {
        errdefer |err| self.onError(err);
        const origin = try self.raw.allocator().create(BlockOrigin);
        origin.* = .{ .term = block.term, .result = block.result, .scope = block.scope };
        try self.block_origins.put(self.raw.allocator(), origin, {});
        var issued = block;
        issued.origin = origin;
        return issued;
    }

    fn checkBlock(self: *Builder, block: Block) Error!void {
        errdefer |err| self.onError(err);
        if (block.owner != self) return try self.foreign("block", null);
        const origin = block.origin orelse {
            self.report(.schema_mismatch, "block origin", null, block.result.id, null, null);
            return error.InvalidSource;
        };
        if (!self.block_origins.contains(origin)) {
            self.report(.schema_mismatch, "block origin", null, block.result.id, null, null);
            return error.InvalidSource;
        }
        if (block.term != origin.term or block.scope != origin.scope or
            !try sameSchema(block.result, origin.result))
        {
            self.report(.schema_mismatch, "block origin", origin.result.id, block.result.id, null, null);
            self.diagnostic.?.relationship = "finished body result";
            return error.TypeMismatch;
        }
    }

    fn issueInterpretation(self: *Builder, interpretation: Interpretation) Error!Interpretation {
        errdefer |err| self.onError(err);
        const origin = try self.raw.allocator().create(InterpretationOrigin);
        origin.* = .{ .id = interpretation.id, .operation = interpretation.operation, .input = interpretation.input, .answer = interpretation.answer, .resumption = interpretation.resumption, .returns = interpretation.returns, .clause = interpretation.clause, .state = interpretation.state, .mode = interpretation.mode };
        try self.interpretation_origins.put(self.raw.allocator(), origin, {});
        var issued = interpretation;
        issued.origin = origin;
        return issued;
    }

    fn checkInterpretation(self: *Builder, interpretation: Interpretation) Error!void {
        errdefer |err| self.onError(err);
        if (interpretation.owner != self) return try self.foreign("interpretation", null);
        const origin = interpretation.origin orelse {
            self.report(.handler_mismatch, "interpretation origin", null, interpretation.id, null, null);
            return error.InvalidSource;
        };
        if (!self.interpretation_origins.contains(origin)) {
            self.report(.handler_mismatch, "interpretation origin", null, interpretation.id, null, null);
            return error.InvalidSource;
        }
        try self.checkEffect(interpretation.operation);
        try self.checkFunction(interpretation.returns);
        try self.checkFunction(interpretation.clause);
        if (interpretation.id != origin.id or interpretation.operation.origin != origin.operation.origin or
            interpretation.returns.origin != origin.returns.origin or interpretation.clause.origin != origin.clause.origin or
            interpretation.state.ptr != origin.state.ptr or interpretation.state.len != origin.state.len or
            interpretation.mode != origin.mode or
            !try sameSchema(interpretation.input, origin.input) or
            !try sameSchema(interpretation.answer, origin.answer) or
            !try sameSchema(interpretation.resumption, origin.resumption))
        {
            self.report(.handler_mismatch, "interpretation origin", origin.answer.id, interpretation.answer.id, null, null);
            self.diagnostic.?.relationship = "issued handler signature";
            return error.TypeMismatch;
        }
    }

    fn checkCleanupFailure(self: *Builder, cleanup_id: p.Id, failure: Schema, allocator: std.mem.Allocator) Error!void {
        const value = self.value_origins.get(cleanup_id) orelse {
            if (try hasNamedMetadata(failure, allocator)) {
                self.report(.schema_mismatch, "cleanup exit failure", failure.id, null, null, null);
                self.diagnostic.?.relationship = "missing raw cleanup provenance";
                return error.TypeMismatch;
            }
            return;
        };
        const callable = value.schema.callable orelse {
            if (try hasNamedMetadata(failure, allocator)) {
                self.report(.schema_mismatch, "cleanup exit failure", failure.id, null, null, null);
                self.diagnostic.?.relationship = "missing named cleanup provenance";
                return error.TypeMismatch;
            }
            return;
        };
        if (callable.parameters.len == 0) {
            if (try hasNamedMetadata(failure, allocator)) {
                self.report(.schema_mismatch, "cleanup exit failure", failure.id, null, null, null);
                self.diagnostic.?.relationship = "missing cleanup exit parameter";
                return error.TypeMismatch;
            }
            return;
        }
        const exit_info = callable.parameters[0].structure orelse {
            if (try hasNamedMetadata(failure, allocator)) {
                self.report(.schema_mismatch, "cleanup exit failure", failure.id, callable.parameters[0].id, null, null);
                self.diagnostic.?.relationship = "missing named cleanup exit provenance";
                return error.TypeMismatch;
            }
            return;
        };
        if (exit_info.kind != .exit_info or exit_info.children.len != 1) {
            if (try hasNamedMetadata(failure, allocator)) {
                self.report(.schema_mismatch, "cleanup exit failure", failure.id, callable.parameters[0].id, null, null);
                self.diagnostic.?.relationship = "invalid cleanup exit description";
                return error.TypeMismatch;
            }
            return;
        }
        if (!try sameSchema(exit_info.children[0], failure)) {
            self.report(.schema_mismatch, "cleanup exit failure", failure.id, exit_info.children[0].id, null, null);
            self.diagnostic.?.relationship = "named module failure layout";
            return error.TypeMismatch;
        }
    }

    fn checkFailureLayouts(self: *Builder, input: source.Module, failure: Schema) Error!void {
        var scratch = std.heap.ArenaAllocator.init(self.raw.arena.child_allocator);
        defer scratch.deinit();
        const allocator = scratch.allocator();
        const named_failure = try hasNamedMetadata(failure, allocator);
        var pending: std.ArrayList(p.Id) = .empty;
        var pending_values: std.ArrayList(p.Id) = .empty;
        var seen: std.AutoHashMapUnmanaged(p.Id, void) = .empty;
        var seen_values: std.AutoHashMapUnmanaged(p.Id, void) = .empty;
        for (input.functions) |function| if (function.body) |term|
            try pending.append(allocator, term);
        while (pending.pop()) |term_id| {
            if (term_id >= input.terms.len) return error.InvalidReference;
            if (seen.contains(term_id)) continue;
            try seen.put(allocator, term_id, {});
            switch (input.terms[@intCast(term_id)]) {
                .value => |value_id| try pending_values.append(allocator, value_id),
                .fail => |value_id| {
                    try pending_values.append(allocator, value_id);
                    const value = self.value_origins.get(value_id) orelse {
                        if (named_failure) {
                            self.report(.schema_mismatch, "failure value", failure.id, null, null, null);
                            self.diagnostic.?.relationship = "missing raw failure provenance";
                            return error.TypeMismatch;
                        }
                        continue;
                    };
                    if (!try sameSchema(value.schema, failure)) {
                        self.report(.schema_mismatch, "failure value", failure.id, value.schema.id, null, null);
                        self.diagnostic.?.relationship = "named module failure layout";
                        return error.TypeMismatch;
                    }
                },
                .protect => |term| {
                    try self.checkCleanupFailure(term.cleanup, failure, allocator);
                    try pending_values.append(allocator, term.body);
                    try pending_values.append(allocator, term.cleanup);
                    for (term.arguments) |argument| try pending_values.append(allocator, argument);
                    if (term.resource) |owned_resource| try pending_values.append(allocator, owned_resource);
                },
                .bind => |term| {
                    try pending.append(allocator, term.value);
                    try pending.append(allocator, term.next);
                },
                .conditional => |term| {
                    try pending_values.append(allocator, term.condition);
                    try pending.append(allocator, term.when_true);
                    try pending.append(allocator, term.when_false);
                },
                .call => |term| for (term.arguments) |argument|
                    try pending_values.append(allocator, argument),
                .apply => |term| {
                    try pending_values.append(allocator, term.computation);
                    for (term.arguments) |argument| try pending_values.append(allocator, argument);
                },
                .perform => |term| {
                    try pending_values.append(allocator, term.payload);
                    if (term.capability) |capability_value| try pending_values.append(allocator, capability_value);
                    for (term.bodies) |scoped_body| try pending_values.append(allocator, scoped_body);
                    for (term.use_site_capabilities) |site_capability| try pending_values.append(allocator, site_capability);
                },
                .handle => |term| {
                    try pending_values.append(allocator, term.body);
                    for (term.arguments) |argument| try pending_values.append(allocator, argument);
                    for (term.state) |state| try pending_values.append(allocator, state);
                },
                .resume_value => |term| {
                    try pending_values.append(allocator, term.resumption);
                    try pending_values.append(allocator, term.argument);
                },
                .resume_with => |term| {
                    try pending_values.append(allocator, term.resumption);
                    try pending_values.append(allocator, term.argument);
                    for (term.state) |state| try pending_values.append(allocator, state);
                },
                .resume_computation => |term| {
                    try pending_values.append(allocator, term.resumption);
                    try pending_values.append(allocator, term.computation);
                },
                .with_region => |term| {
                    try pending_values.append(allocator, term.body);
                    for (term.arguments) |argument| try pending_values.append(allocator, argument);
                },
                .dispose => |value_id| try pending_values.append(allocator, value_id),
                .match_sum => |term| {
                    try pending_values.append(allocator, term.value);
                    for (term.cases) |case| try pending.append(allocator, case.body);
                },
                .unpack_product => |term| {
                    try pending_values.append(allocator, term.value);
                    try pending.append(allocator, term.body);
                },
                .yield_then => |next| try pending.append(allocator, next),
            }
        }
        while (pending_values.pop()) |value_id| {
            if (value_id >= input.values.len) return error.InvalidReference;
            if (seen_values.contains(value_id)) continue;
            try seen_values.put(allocator, value_id, {});
            switch (input.values[@intCast(value_id)].expression) {
                .primitive => |primitive| {
                    for (primitive.operands) |operand| try pending_values.append(allocator, operand);
                    if (primitive.failures.len == 0) continue;
                    const authored = self.checked_add_failures.get(value_id) orelse {
                        if (named_failure) {
                            self.report(.schema_mismatch, "checked failure literal", failure.id, null, null, null);
                            self.diagnostic.?.relationship = "missing primitive failure provenance";
                            return error.TypeMismatch;
                        }
                        continue;
                    };
                    if (!try sameSchema(authored, failure)) {
                        self.report(.schema_mismatch, "checked failure literal", failure.id, authored.id, null, null);
                        self.diagnostic.?.relationship = "named module failure layout";
                        return error.TypeMismatch;
                    }
                },
                else => {},
            }
        }
    }

    fn checkSchema(self: *Builder, schema: Schema) Error!void {
        errdefer |err| self.onError(err);
        self.diagnostic = null;
        if (schema.owner != self) {
            self.report(.foreign_builder, "schema", null, null, null, null);
            return error.ForeignBuilder;
        }
        if (schema.id >= self.raw.schemas.items.len) return error.InvalidSchema;
    }

    fn sourceSchema(self: *Builder, id: p.Id, entity: []const u8) Error!p.Schema {
        if (id >= self.raw.schemas.items.len) {
            self.report(.schema_mismatch, entity, null, id, null, null);
            return error.InvalidSchema;
        }
        return self.raw.schemas.items[@intCast(id)];
    }

    fn sourceEffect(self: *Builder, id: p.Id, entity: []const u8) Error!p.Effect {
        if (id >= self.raw.effects.items.len) {
            self.report(.capability_mismatch, entity, null, id, null, null);
            return error.InvalidReference;
        }
        return self.raw.effects.items[@intCast(id)];
    }

    fn mintValue(self: *Builder, value: Value) Error!Value {
        errdefer |err| self.onError(err);
        if (value.id >= self.raw.values.items.len or
            self.raw.values.items[@intCast(value.id)].schema != value.schema.id)
            return error.InvalidSource;
        if (self.value_origins.get(value.id)) |known| {
            if (!try sameSchema(known.schema, value.schema) or known.scope != value.scope)
                return error.TypeMismatch;
            var sealed = value;
            sealed.origin = known;
            return sealed;
        }
        const origin = try self.raw.allocator().create(ValueOrigin);
        origin.* = .{ .schema = value.schema, .scope = value.scope };
        try self.value_origins.put(self.raw.allocator(), value.id, origin);
        var sealed = value;
        sealed.origin = origin;
        return sealed;
    }

    pub fn scalar(self: *Builder, comptime T: type) Error!Schema {
        self.diagnostic = null;
        errdefer |err| self.onError(err);
        return .{ .owner = self, .id = try self.raw.scalar(T) };
    }

    pub fn region(self: *Builder) Region {
        self.diagnostic = null;
        return .{ .owner = self, .id = self.raw.region() };
    }

    pub fn adoptRegion(self: *Builder, id: p.Id) Error!Region {
        errdefer |err| self.onError(err);
        self.diagnostic = null;
        if (id >= self.raw.region_count) return error.InvalidReference;
        return .{ .owner = self, .id = id };
    }

    pub fn regionSchema(self: *Builder, region_handle: Region) Error!Schema {
        errdefer |err| self.onError(err);
        self.diagnostic = null;
        if (region_handle.owner != self) return try self.foreign("region", null);
        if (region_handle.id >= self.raw.region_count) return error.InvalidReference;
        return self.dynamicSchema(.{ .internal = .{ .region = region_handle.id } });
    }

    pub fn cellSchema(self: *Builder, region_handle: Region, element: Schema) Error!Schema {
        errdefer |err| self.onError(err);
        _ = try self.regionSchema(region_handle);
        try self.checkSchema(element);
        return self.withChildren(try self.dynamicSchema(.{ .internal = .{ .cell = .{
            .element = element.id,
            .region = region_handle.id,
        } } }), .cell, &.{element});
    }

    pub fn resource(self: *Builder, representation: Schema) Error!Schema {
        errdefer |err| self.onError(err);
        try self.checkSchema(representation);
        var owned = try self.adoptSchema(try self.raw.resource(representation.id));
        const saved = try self.raw.allocator().create(Schema);
        saved.* = representation;
        owned.resource = saved;
        return owned;
    }

    pub fn borrowedSchema(self: *Builder, owned: Schema, region_handle: Region) Error!Schema {
        errdefer |err| self.onError(err);
        try self.checkSchema(owned);
        _ = try self.regionSchema(region_handle);
        const shape = self.raw.schemas.items[@intCast(owned.id)];
        if (shape != .internal or shape.internal != .abstract_resource)
            return error.TypeMismatch;
        var borrowed = try self.dynamicSchema(.{ .internal = .{ .borrowed = .{
            .value = owned.id,
            .region = region_handle.id,
        } } });
        const saved = try self.raw.allocator().create(Schema);
        saved.* = owned;
        borrowed.borrowed = saved;
        return borrowed;
    }

    pub fn resourceAuthority(self: *Builder, owned: Schema, introducers: []const Function, eliminators: []const Function) Error!void {
        errdefer |err| self.onError(err);
        try self.checkSchema(owned);
        const introduced = try self.raw.allocator().alloc(p.Id, introducers.len);
        const eliminated = try self.raw.allocator().alloc(p.Id, eliminators.len);
        for (introducers, introduced) |function, *id| {
            try self.checkFunction(function);
            id.* = function.id;
        }
        for (eliminators, eliminated) |function, *id| {
            try self.checkFunction(function);
            id.* = function.id;
        }
        try self.raw.resourceAuthority(owned.id, introduced, eliminated);
    }

    fn dynamicSchema(self: *Builder, shape: p.Schema) Error!Schema {
        errdefer |err| self.onError(err);
        return .{ .owner = self, .id = try self.raw.schema(shape) };
    }

    pub fn adoptSchema(self: *Builder, id: p.Id) Error!Schema {
        errdefer |err| self.onError(err);
        self.diagnostic = null;
        if (id >= self.raw.schemas.items.len) return error.InvalidSchema;
        return .{ .owner = self, .id = id };
    }

    pub fn adoptEffect(self: *Builder, id: p.Id) Error!Effect {
        self.diagnostic = null;
        errdefer |err| self.onError(err);
        if (id >= self.raw.effects.items.len) return error.InvalidReference;
        const original = self.raw.effects.items[@intCast(id)];
        const bodies = try self.raw.allocator().alloc(Parameter, original.bodies.len);
        for (original.bodies, bodies, 0..) |schema_id, *named, index| {
            named.* = .{ .name = try std.fmt.allocPrint(self.raw.allocator(), "body{d}", .{index}), .schema = try self.adoptSchema(schema_id) };
        }
        return self.issueEffect(.{ .owner = self, .id = id, .payload = try self.adoptSchema(original.payload), .result = try self.adoptSchema(original.result), .external = original.external, .bodies = bodies, .use_site_effects = original.use_site_effects });
    }

    fn withChildren(self: *Builder, base: Schema, kind: StructureKind, children: []const Schema) Error!Schema {
        errdefer |err| self.onError(err);
        const info = try self.raw.allocator().create(StructureInfo);
        info.* = .{ .kind = kind, .children = try self.raw.allocator().dupe(Schema, children) };
        var result = base;
        result.structure = info;
        return result;
    }

    pub fn sumSchema(self: *Builder, alternatives: []const Schema) Error!Schema {
        self.diagnostic = null;
        errdefer |err| self.onError(err);
        const ids = try self.raw.allocator().alloc(p.Id, alternatives.len);
        for (alternatives, ids) |alternative, *id| {
            try self.checkSchema(alternative);
            id.* = alternative.id;
        }
        return self.withChildren(try self.dynamicSchema(.{ .sum = ids }), .sum, alternatives);
    }

    pub fn sequenceSchema(self: *Builder, element: Schema) Error!Schema {
        errdefer |err| self.onError(err);
        try self.checkSchema(element);
        return self.withChildren(try self.dynamicSchema(.{ .seq = element.id }), .sequence, &.{element});
    }

    pub fn exitInfo(self: *Builder, failure: Schema) Error!Schema {
        errdefer |err| self.onError(err);
        try self.checkSchema(failure);
        return self.withChildren(try self.adoptSchema(try @import("library/cleanup.zig").exitInfo(self.raw, failure.id)), .exit_info, &.{failure});
    }

    pub fn productSchema(self: *Builder, fields: []const Schema) Error!Schema {
        self.diagnostic = null;
        errdefer |err| self.onError(err);
        const ids = try self.raw.allocator().alloc(p.Id, fields.len);
        for (fields, ids) |field, *id| {
            try self.checkSchema(field);
            id.* = field.id;
        }
        return self.withChildren(try self.dynamicSchema(.{ .product = ids }), .product, fields);
    }

    fn namedLayout(self: *Builder, kind: LayoutKind, fields: []const Field) Error!*const NamedLayout {
        errdefer |err| self.onError(err);
        for (self.named_layouts.items) |existing| {
            if (existing.kind != kind or existing.fields.len != fields.len) continue;
            var equal = true;
            for (existing.fields, fields) |left, right| {
                if (!std.mem.eql(u8, left.name, right.name) or
                    !try sameSchema(left.schema, right.schema))
                {
                    equal = false;
                    break;
                }
            }
            if (equal) return existing;
        }
        const layout = try self.raw.allocator().create(NamedLayout);
        layout.* = .{ .kind = kind, .fields = fields };
        try self.named_layouts.append(self.raw.allocator(), layout);
        return layout;
    }

    pub fn record(self: *Builder, fields: []const Field) Error!Record {
        self.diagnostic = null;
        errdefer |err| self.onError(err);
        const copied = try self.raw.allocator().alloc(Field, fields.len);
        const schemas = try self.raw.allocator().alloc(Schema, fields.len);
        for (fields, copied, schemas, 0..) |field, *copy, *schema, index| {
            try self.checkSchema(field.schema);
            for (fields[0..index]) |prior| if (std.mem.eql(u8, prior.name, field.name)) return error.DuplicateName;
            copy.* = .{ .name = try self.raw.allocator().dupe(u8, field.name), .schema = field.schema };
            schema.* = field.schema;
        }
        var schema = try self.productSchema(schemas);
        schema.layout = try self.namedLayout(.record, copied);
        return .{ .owner = self, .schema = schema };
    }

    pub fn variant(self: *Builder, alternatives: []const Field) Error!Variant {
        self.diagnostic = null;
        errdefer |err| self.onError(err);
        const copied = try self.raw.allocator().alloc(Field, alternatives.len);
        const schemas = try self.raw.allocator().alloc(Schema, alternatives.len);
        for (alternatives, copied, schemas, 0..) |field, *copy, *schema, index| {
            try self.checkSchema(field.schema);
            for (alternatives[0..index]) |prior| if (std.mem.eql(u8, prior.name, field.name)) return error.DuplicateName;
            copy.* = .{ .name = try self.raw.allocator().dupe(u8, field.name), .schema = field.schema };
            schema.* = field.schema;
        }
        var schema = try self.sumSchema(schemas);
        schema.layout = try self.namedLayout(.variant, copied);
        return .{ .owner = self, .schema = schema };
    }

    fn declareEffect(self: *Builder, name: []const u8, payload: Schema, result: Schema, is_external: bool, control_use: p.Use) Error!Effect {
        errdefer |err| self.onError(err);
        try self.checkSchema(payload);
        try self.checkSchema(result);
        const id = try self.raw.effect(.{ .identity = name, .payload = payload.id, .result = result.id, .external = is_external, .control_use = control_use });
        return self.issueEffect(.{ .owner = self, .id = id, .payload = payload, .result = result, .external = is_external });
    }

    pub fn external(self: *Builder, name: []const u8, payload: Schema, result: Schema) Error!Effect {
        errdefer |err| self.onError(err);
        return self.declareEffect(name, payload, result, true, .linear);
    }

    pub fn local(self: *Builder, name: []const u8, payload: Schema, result: Schema, use: p.Use) Error!Effect {
        return self.declareEffect(name, payload, result, false, use);
    }

    pub fn scopedLocal(self: *Builder, name: []const u8, payload: Schema, result: Schema, bodies: []const Parameter, use_site_effects: []const Effect, use: p.Use) Error!Effect {
        errdefer |err| self.onError(err);
        try self.checkSchema(payload);
        try self.checkSchema(result);
        const copied = try self.raw.allocator().alloc(Parameter, bodies.len);
        const body_ids = try self.raw.allocator().alloc(p.Id, bodies.len);
        for (bodies, copied, body_ids, 0..) |named, *target, *id, index| {
            try self.checkSchema(named.schema);
            for (bodies[0..index]) |earlier| if (std.mem.eql(u8, earlier.name, named.name))
                return error.DuplicateName;
            target.* = .{ .name = try self.raw.allocator().dupe(u8, named.name), .schema = named.schema };
            id.* = named.schema.id;
        }
        const site_effects = try self.effectIds(use_site_effects);
        const id = try self.raw.effect(.{ .identity = name, .payload = payload.id, .result = result.id, .bodies = body_ids, .use_site_effects = site_effects, .control_use = use, .external = false });
        return self.issueEffect(.{ .owner = self, .id = id, .payload = payload, .result = result, .external = false, .bodies = copied, .use_site_effects = site_effects });
    }

    pub fn capability(self: *Builder, effect: Effect) Error!Schema {
        errdefer |err| self.onError(err);
        self.diagnostic = null;
        try self.checkEffect(effect);
        if (effect.external) {
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
            try self.checkEffect(effect);
            id.* = effect.id;
        }
        const region_ids = try self.raw.allocator().alloc(p.Id, regions.len);
        for (regions, region_ids) |region_handle, *id| {
            if (region_handle.owner != self) return try self.foreign("region", null);
            id.* = region_handle.id;
        }
        const saved_name = try self.raw.allocator().dupe(u8, name);
        const id = try self.raw.declare(param_ids, result.id, effect_ids, region_ids);
        try self.function_names.put(self.raw.allocator(), id, saved_name);
        return self.issueFunction(.{ .owner = self, .id = id, .name = saved_name, .parameters = copied, .result = result, .effects = effect_ids, .regions = region_ids });
    }

    pub fn callableSchema(self: *Builder, function: Function, captures: []const Schema, use: p.Use) Error!Schema {
        self.diagnostic = null;
        errdefer |err| self.onError(err);
        try self.checkFunction(function);
        const params = try self.raw.allocator().alloc(p.Id, function.parameters.len);
        for (function.parameters, params) |named, *id| id.* = named.schema.id;
        const bounds = try self.raw.allocator().alloc(p.Id, captures.len);
        for (captures, bounds) |schema, *id| {
            try self.checkSchema(schema);
            id.* = schema.id;
        }
        var callable = try self.dynamicSchema(.{ .internal = .{ .computation = .{
            .parameters = params,
            .result = function.result.id,
            .effects = function.effects,
            .capture_bound = bounds,
            .use = use,
            .regions = function.regions,
        } } });
        const parameter_schemas = try self.raw.allocator().alloc(Schema, function.parameters.len);
        for (function.parameters, parameter_schemas) |named, *schema| schema.* = named.schema;
        const info = try self.raw.allocator().create(CallableInfo);
        info.* = .{ .parameters = parameter_schemas, .result = function.result };
        callable.callable = info;
        return callable;
    }

    pub fn body(self: *Builder, function: Function) Error!Body {
        self.diagnostic = null;
        errdefer |err| self.onError(err);
        try self.checkFunction(function);
        const scope = try self.raw.allocator().create(Scope);
        scope.* = .{ .parent = null, .name = function.name, .function = function.id };
        return .{ .author = self, .scope = scope, .function = function };
    }

    /// A source-library staging callback can supply lexical context that it owns.
    /// Raw adoption into this context is confined to Interop below.
    pub fn ambient(self: *Builder, name: []const u8) Error!Body {
        self.diagnostic = null;
        errdefer |err| self.onError(err);
        const scope = try self.raw.allocator().create(Scope);
        scope.* = .{ .parent = null, .name = try self.raw.allocator().dupe(u8, name) };
        return .{ .author = self, .scope = scope };
    }

    pub fn bodyWithin(self: *Builder, parent: *Body, function: Function) Error!Body {
        errdefer |err| self.onError(err);
        try parent.ensureOpen();
        if (parent.author != self) return try self.foreign("function body", parent.scope.name);
        try self.checkFunction(function);
        const scope = try self.raw.allocator().create(Scope);
        scope.* = .{ .parent = parent.scope, .name = function.name, .function = function.id };
        return .{ .author = self, .scope = scope, .function = function };
    }

    pub fn define(self: *Builder, function: Function, block: Block) Error!void {
        errdefer |err| self.onError(err);
        self.diagnostic = null;
        try self.checkFunction(function);
        try self.checkBlock(block);
        if (block.scope.function != function.id) return error.InvalidBranch;
        if (!try sameSchema(block.result, function.result)) {
            self.report(.schema_mismatch, function.name, function.result.id, block.result.id, null, null);
            self.diagnostic.?.relationship = "declared result layout";
            return error.TypeMismatch;
        }
        try self.raw.define(function.id, block.term);
    }

    pub fn module(self: *Builder, entry: Function, failure: Schema) Error!Module {
        errdefer |err| self.onError(err);
        self.diagnostic = null;
        if (self.poisoned) return error.InvalidSource;
        try self.checkFunction(entry);
        try self.checkSchema(failure);
        const input = self.raw.module(entry.id, failure.id);
        try self.checkFailureLayouts(input, failure);
        const origin = try self.raw.allocator().create(ModuleOrigin);
        origin.* = .{ .owner = self, .entry = entry.id, .failure = failure };
        try self.module_origins.put(self.raw.allocator(), origin, {});
        return .{ .origin = origin };
    }

    pub fn compile(self: *Builder, allocator: std.mem.Allocator, published: Module) Error!source.Compiled {
        errdefer |err| self.onError(err);
        self.diagnostic = null;
        if (self.poisoned) return error.InvalidSource;
        if (!self.module_origins.contains(published.origin)) {
            self.report(.foreign_builder, "module", null, null, null, null);
            return error.ForeignBuilder;
        }
        const origin = published.origin;
        if (origin.owner != self) return error.ForeignBuilder;
        const input = self.raw.module(origin.entry, origin.failure.id);
        try self.checkFailureLayouts(input, origin.failure);
        var detail: source.Diagnostic = .{};
        return source.lowerObserved(allocator, input, .{ .diagnostic = &detail }) catch |err| {
            self.onError(err);
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
            return @errorCast(err);
        };
    }

    pub fn literal(self: *Builder, comptime T: type, value: T) Error!Value {
        self.diagnostic = null;
        errdefer |err| self.onError(err);
        return self.mintValue(.{ .owner = self, .id = try self.raw.constant(T, value), .schema = try self.scalar(T) });
    }

    /// Checked arithmetic embeds an authored failure literal in the source image.
    pub fn literalFailure(self: *Builder, comptime T: type, value: T) Error!FailureLiteral {
        errdefer |err| self.onError(err);
        const authored = try self.literal(T, value);
        const origin = try self.raw.allocator().create(FailureLiteralInfo);
        origin.* = .{ .value = authored, .literal = try self.raw.failureLiteral(authored.id) };
        try self.failure_literals.put(self.raw.allocator(), origin, {});
        return .{ .origin = origin };
    }

    /// The caller vouches for historical raw-ID provenance. The current catalog
    /// and schema are checked; a numeric ID alone cannot recover its origin.
    fn adoptValue(self: *Builder, id: p.Id, schema: Schema) Error!Value {
        errdefer |err| self.onError(err);
        try self.checkSchema(schema);
        if (id >= self.raw.values.items.len) return error.InvalidReference;
        if (self.raw.values.items[@intCast(id)].schema != schema.id) return error.TypeMismatch;
        return .{ .owner = self, .id = id, .schema = schema };
    }

    fn effectIds(self: *Builder, effects: []const Effect) Error![]const p.Id {
        errdefer |err| self.onError(err);
        const ids = try self.raw.allocator().alloc(p.Id, effects.len);
        for (effects, ids) |effect, *id| {
            try self.checkEffect(effect);
            id.* = effect.id;
        }
        return ids;
    }

    fn regionIds(self: *Builder, regions: []const Region) Error![]const p.Id {
        errdefer |err| self.onError(err);
        const ids = try self.raw.allocator().alloc(p.Id, regions.len);
        for (regions, ids) |region_handle, *id| {
            if (region_handle.owner != self) return try self.foreign("region", null);
            if (region_handle.id >= self.raw.region_count) return error.InvalidReference;
            id.* = region_handle.id;
        }
        return ids;
    }

    pub fn interpret(self: *Builder, options: InterpretationOptions) Error!Interpretation {
        self.diagnostic = null;
        errdefer |err| self.onError(err);
        try self.checkEffect(options.operation);
        if (options.operation.external) return error.InvalidCapability;
        for (options.state, 0..) |named, index| {
            for ([_][]const u8{ "value", "payload", "resume" }) |reserved| {
                if (std.mem.eql(u8, named.name, reserved)) return error.DuplicateName;
            }
            for (options.state[0..index]) |earlier| {
                if (std.mem.eql(u8, named.name, earlier.name)) return error.DuplicateName;
            }
        }
        for (options.operation.bodies, 0..) |named, index| {
            if (std.mem.eql(u8, named.name, "payload") or
                std.mem.eql(u8, named.name, "resume")) return error.DuplicateName;
            for (options.state) |state| {
                if (std.mem.eql(u8, named.name, state.name)) return error.DuplicateName;
            }
            for (options.operation.bodies[0..index]) |earlier| {
                if (std.mem.eql(u8, named.name, earlier.name)) return error.DuplicateName;
            }
        }
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
        var token = try self.dynamicSchema(.{ .internal = .{ .resumption = .{
            .effect = options.operation.id,
            .input = options.operation.result.id,
            .answer = if (options.mode == .deep) options.answer.id else options.input.id,
            .effects = resumed_effects,
            .capture_bound = bounds,
            .handled = &.{options.operation.id},
            .escaping = escaping,
            .mode = options.mode,
            .use = options.use,
            .owned_regions = owned_regions,
            .obligations = options.obligations,
        } } });
        const resumption_info = try self.raw.allocator().create(ResumptionInfo);
        resumption_info.* = .{ .input = options.operation.result, .answer = if (options.mode == .deep) options.answer else options.input };
        token.resumption = resumption_info;
        const return_params = try self.raw.allocator().alloc(Parameter, state.len + 1);
        @memcpy(return_params[0..state.len], state);
        return_params[state.len] = .{ .name = "value", .schema = options.input };
        const clause_params = try self.raw.allocator().alloc(Parameter, state.len + options.operation.bodies.len + 2);
        @memcpy(clause_params[0..state.len], state);
        clause_params[state.len] = .{ .name = "payload", .schema = options.operation.payload };
        @memcpy(clause_params[state.len + 1 ..][0..options.operation.bodies.len], options.operation.bodies);
        clause_params[clause_params.len - 1] = .{ .name = "resume", .schema = token };
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
        return self.issueInterpretation(.{ .owner = self, .id = id, .operation = options.operation, .input = options.input, .answer = options.answer, .resumption = token, .returns = returns, .clause = clause, .state = state, .mode = options.mode });
    }

    /// The responder's declared residual effects remain an explicit allowance.
    pub fn responder(self: *Builder, operation: Effect, function: Function, residual: []const Effect, capture_bound: []const Schema, mode: p.Mode, use: p.Use) Error!Interpretation {
        errdefer |err| self.onError(err);
        return self.responding(operation, function, operation.result, residual, capture_bound, mode, use);
    }

    pub fn responding(self: *Builder, operation: Effect, function: Function, body_result: Schema, residual: []const Effect, capture_bound: []const Schema, mode: p.Mode, use: p.Use) Error!Interpretation {
        errdefer |err| self.onError(err);
        self.diagnostic = null;
        try self.checkFunction(function);
        try self.checkEffect(operation);
        if (operation.bodies.len != 0) return try self.arity("responder operation bodies", 0, operation.bodies.len, null);
        try self.checkSchema(body_result);
        if (function.parameters.len != 1 or
            !try sameSchema(function.parameters[0].schema, operation.payload) or
            !try sameSchema(function.result, operation.result)) return error.TypeMismatch;
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
        errdefer |err| body.author.onError(err);
        try body.check(value);
        if (body.author.value_exports.get(value.id)) |known| {
            if (!try sameSchema(known.schema, value.schema) or known.scope != value.scope)
                return error.InvalidSource;
        } else try body.author.value_exports.put(body.author.raw.allocator(), value.id, .{ .schema = value.schema, .scope = value.scope });
        return value.id;
    }

    pub fn adoptValue(body: *Body, id: p.Id, schema: Schema) Error!Value {
        errdefer |err| body.author.onError(err);
        try body.ensureOpen();
        var value = try body.author.adoptValue(id, schema);
        if (body.author.value_exports.get(id)) |exported| {
            if (!try sameSchema(exported.schema, schema)) {
                body.author.report(.schema_mismatch, "interop value", exported.schema.id, schema.id, null, body.scope.name);
                body.author.diagnostic.?.relationship = "exported named layout";
                return error.TypeMismatch;
            }
            if (!scopeVisible(exported.scope, body.scope)) {
                body.author.report(.out_of_scope, "interop value", null, null, exported.scope.?.name, body.scope.name);
                return error.OutOfScope;
            }
            value.scope = exported.scope;
        } else {
            if (hasAuthoringMetadata(schema)) return error.InvalidSource;
            value.scope = body.scope;
        }
        return body.author.mintValue(value);
    }

    pub fn term(body: *Body, id: p.Id, result: Schema) Error!Value {
        errdefer |err| body.author.onError(err);
        try body.ensureOpen();
        try body.author.checkSchema(result);
        if (id >= body.author.raw.terms.items.len) return error.InvalidReference;
        if (body.author.term_exports.get(id)) |exported| {
            if (!try sameSchema(exported.schema, result)) return error.TypeMismatch;
            if (!scopeVisible(exported.scope, body.scope)) return error.OutOfScope;
        } else if (hasAuthoringMetadata(result)) return error.InvalidSource;
        return body.append(id, result);
    }

    pub fn terminal(body: *Body, id: p.Id, result: Schema) Error!Block {
        errdefer |err| body.author.onError(err);
        try body.ensureOpen();
        try body.author.checkSchema(result);
        if (id >= body.author.raw.terms.items.len) return error.InvalidReference;
        if (body.author.term_exports.get(id)) |exported| {
            if (!try sameSchema(exported.schema, result)) return error.TypeMismatch;
            if (!scopeVisible(exported.scope, body.scope)) return error.OutOfScope;
        } else if (hasAuthoringMetadata(result)) return error.InvalidSource;
        return body.close(id, result);
    }

    pub fn lambdaAs(body: *Body, function: Function, schema: Schema) Error!Callable {
        errdefer |err| body.author.onError(err);
        try body.ensureOpen();
        try body.author.checkSchema(schema);
        try body.author.checkFunction(function);
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
        const parameter_schemas = try body.author.raw.allocator().alloc(Schema, function.parameters.len);
        for (function.parameters, parameter_schemas) |named, *item| item.* = named.schema;
        const info = try body.author.raw.allocator().create(CallableInfo);
        info.* = .{ .parameters = parameter_schemas, .result = function.result };
        var annotated = schema;
        annotated.callable = info;
        return .{ .value = try body.author.mintValue(.{ .owner = body.author, .schema = annotated, .id = try body.author.raw.lambda(function.id, schema.id), .scope = body.scope }) };
    }

    pub fn rawTerm(block: Block) Error!p.Id {
        errdefer |err| block.owner.onError(err);
        try block.owner.checkBlock(block);
        try block.owner.term_exports.put(block.owner.raw.allocator(), block.term, .{ .schema = block.result, .scope = block.scope });
        return block.term;
    }
};

pub const Body = struct {
    author: *Builder,
    scope: *Scope,
    function: ?Function = null,

    fn ensureOpen(self: *Body) Error!void {
        errdefer |err| self.author.onError(err);
        self.author.diagnostic = null;
        if (self.author.poisoned) return error.InvalidSource;
        var current: ?*Scope = self.scope;
        while (current) |scope| : (current = scope.parent) {
            if (!scope.open) {
                self.author.report(.closed_body, scope.name, null, null, null, null);
                return error.ClosedBody;
            }
        }
    }

    pub fn abandon(self: *Body) void {
        self.scope.open = false;
    }

    fn check(self: *Body, value: Value) Error!void {
        errdefer |err| self.author.onError(err);
        try self.ensureOpen();
        if (value.owner != self.author or value.schema.owner != self.author) {
            self.author.report(.foreign_builder, "value", null, null, null, self.scope.name);
            return error.ForeignBuilder;
        }
        const origin = self.author.value_origins.get(value.id) orelse {
            self.author.report(.schema_mismatch, "value origin", null, value.schema.id, null, self.scope.name);
            return error.InvalidSource;
        };
        if (value.origin != origin or !try sameSchema(value.schema, origin.schema)) {
            self.author.report(.schema_mismatch, "value origin", origin.schema.id, value.schema.id, null, self.scope.name);
            return error.TypeMismatch;
        }
        if (value.scope != origin.scope) {
            self.author.report(.out_of_scope, "value origin", null, null, if (origin.scope) |scope| scope.name else null, self.scope.name);
            return error.OutOfScope;
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

    fn namedFields(self: *Body, schema: Schema, kind: LayoutKind) Error![]const Field {
        try self.author.checkSchema(schema);
        if (schema.layout) |layout| if (layout.kind == kind) return layout.fields;
        self.author.report(.schema_mismatch, if (kind == .record) "record layout" else "variant layout", null, schema.id, null, self.scope.name);
        return error.InvalidSchema;
    }

    pub fn parameter(self: *Body, name: []const u8) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.ensureOpen();
        const function = self.function orelse {
            self.author.report(.argument_mismatch, "function parameter", null, null, null, self.scope.name);
            self.author.diagnostic.?.relationship = "no function declaration";
            return error.InvalidArgument;
        };
        try self.author.checkFunction(function);
        if (self.scope.function != function.id) {
            self.author.report(.out_of_scope, "function parameter", null, null, function.name, self.scope.name);
            self.author.diagnostic.?.relationship = "body declaration identity";
            return error.InvalidBranch;
        }
        for (function.parameters, 0..) |named, index| if (std.mem.eql(u8, name, named.name)) {
            return self.author.mintValue(.{ .owner = self.author, .id = try self.author.raw.reference(self.author.raw.parameter(function.id, index)), .schema = named.schema, .scope = self.scope });
        };
        self.author.report(.argument_mismatch, try self.author.diagnosticName(name), null, null, null, self.scope.name);
        self.author.diagnostic.?.relationship = "named function parameter";
        return error.InvalidArgument;
    }

    pub fn child(self: *Body, name: []const u8) Error!Body {
        errdefer |err| self.author.onError(err);
        try self.ensureOpen();
        const scope = try self.author.raw.allocator().create(Scope);
        scope.* = .{ .parent = self.scope, .name = try self.author.raw.allocator().dupe(u8, name) };
        return .{ .author = self.author, .scope = scope };
    }

    fn append(self: *Body, term: p.Id, result: Schema) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.ensureOpen();
        const variable = try self.author.raw.variable(result.id);
        try self.scope.steps.append(self.author.raw.allocator(), .{ .variable = variable, .term = term });
        return self.author.mintValue(.{ .owner = self.author, .id = try self.author.raw.reference(variable), .schema = result, .scope = self.scope });
    }

    /// Evaluate one symbolic value once and bind its runtime result for reuse.
    /// Reusing an unbound lambda expression can construct distinct closures.
    pub fn bindValue(self: *Body, value: Value) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.check(value);
        return self.append(try self.author.raw.pure(value.id), value.schema);
    }

    pub fn perform(self: *Body, effect: Effect, payload: Value) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.check(payload);
        try self.author.checkEffect(effect);
        if (!effect.external) return error.InvalidCapability;
        if (effect.bodies.len != 0) return try self.author.arity("external operation bodies", 0, effect.bodies.len, self.scope.name);
        if (effect.use_site_effects.len != 0) return try self.author.arity("external operation use-site capabilities", 0, effect.use_site_effects.len, self.scope.name);
        if (!try sameSchema(payload.schema, effect.payload)) {
            self.author.report(.schema_mismatch, "operation payload", effect.payload.id, payload.schema.id, null, self.scope.name);
            return error.TypeMismatch;
        }
        return self.append(try self.author.raw.term(.{ .perform = .{ .effect = effect.id, .payload = payload.id } }), effect.result);
    }

    pub fn performLocal(self: *Body, effect: Effect, capability: Value, payload: Value) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.check(payload);
        try self.check(capability);
        try self.author.checkEffect(effect);
        if (effect.external) return error.InvalidCapability;
        if (effect.bodies.len != 0) return try self.author.arity("local operation bodies", 0, effect.bodies.len, self.scope.name);
        if (effect.use_site_effects.len != 0) return try self.author.arity("local operation use-site capabilities", 0, effect.use_site_effects.len, self.scope.name);
        const shape = self.author.raw.schemas.items[@intCast(capability.schema.id)];
        if (shape != .internal or shape.internal != .capability or shape.internal.capability != effect.id) {
            self.author.report(.capability_mismatch, "operation capability", null, capability.schema.id, null, self.scope.name);
            return error.InvalidCapability;
        }
        if (!try sameSchema(payload.schema, effect.payload)) {
            self.author.report(.schema_mismatch, "local operation payload", effect.payload.id, payload.schema.id, null, self.scope.name);
            self.author.diagnostic.?.relationship = "declared local payload schema";
            return error.TypeMismatch;
        }
        return self.append(try self.author.raw.term(.{ .perform = .{
            .effect = effect.id,
            .capability = capability.id,
            .payload = payload.id,
        } }), effect.result);
    }

    pub fn performScoped(self: *Body, effect: Effect, capability: Value, payload: Value, bodies: []const Callable, use_site_capabilities: []const Value) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.check(capability);
        try self.check(payload);
        try self.author.checkEffect(effect);
        if (effect.external) return error.InvalidCapability;
        if (!try sameSchema(payload.schema, effect.payload)) {
            self.author.report(.schema_mismatch, "scoped operation payload", effect.payload.id, payload.schema.id, null, self.scope.name);
            self.author.diagnostic.?.relationship = "declared scoped payload schema";
            return error.TypeMismatch;
        }
        if (bodies.len != effect.bodies.len) {
            self.author.report(.argument_mismatch, "scoped operation bodies", null, null, null, self.scope.name);
            self.author.diagnostic.?.expected_count = effect.bodies.len;
            self.author.diagnostic.?.actual_count = bodies.len;
            return error.TypeMismatch;
        }
        if (use_site_capabilities.len != effect.use_site_effects.len) {
            self.author.report(.argument_mismatch, "scoped use-site capabilities", null, null, null, self.scope.name);
            self.author.diagnostic.?.expected_count = effect.use_site_effects.len;
            self.author.diagnostic.?.actual_count = use_site_capabilities.len;
            return error.TypeMismatch;
        }
        const cap_shape = self.author.raw.schemas.items[@intCast(capability.schema.id)];
        if (cap_shape != .internal or cap_shape.internal != .capability or
            cap_shape.internal.capability != effect.id)
        {
            self.author.report(.capability_mismatch, "scoped operation capability", null, capability.schema.id, null, self.scope.name);
            return error.InvalidCapability;
        }
        const body_ids = try self.author.raw.allocator().alloc(p.Id, bodies.len);
        for (bodies, effect.bodies, body_ids) |work, named, *id| {
            try self.check(work.value);
            if (!try sameSchema(work.value.schema, named.schema)) {
                self.author.report(.argument_mismatch, named.name, named.schema.id, work.value.schema.id, null, self.scope.name);
                return error.TypeMismatch;
            }
            id.* = work.value.id;
        }
        const site_ids = try self.author.raw.allocator().alloc(p.Id, use_site_capabilities.len);
        for (use_site_capabilities, effect.use_site_effects, site_ids) |value, effect_id, *id| {
            try self.check(value);
            const shape = self.author.raw.schemas.items[@intCast(value.schema.id)];
            if (shape != .internal or shape.internal != .capability or
                shape.internal.capability != effect_id) return error.InvalidCapability;
            id.* = value.id;
        }
        return self.append(try self.author.raw.term(.{ .perform = .{
            .effect = effect.id,
            .capability = capability.id,
            .payload = payload.id,
            .bodies = body_ids,
            .use_site_capabilities = site_ids,
        } }), effect.result);
    }

    pub fn resumeValue(self: *Body, resumption: Value, argument: Value) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.check(resumption);
        try self.check(argument);
        const shape = self.author.raw.schemas.items[@intCast(resumption.schema.id)];
        if (shape != .internal or shape.internal != .resumption) return error.TypeMismatch;
        const signature = shape.internal.resumption;
        const info = resumption.schema.resumption;
        const input_matches = if (info) |known|
            try sameSchema(argument.schema, known.input)
        else
            try sameSchema(argument.schema, .{ .owner = self.author, .id = signature.input });
        if (!input_matches) {
            self.author.report(.schema_mismatch, "resumption input", signature.input, argument.schema.id, null, self.scope.name);
            return error.TypeMismatch;
        }
        return self.append(try self.author.raw.term(.{ .resume_value = .{
            .resumption = resumption.id,
            .argument = argument.id,
        } }), if (info) |known| known.answer else .{ .owner = self.author, .id = signature.answer });
    }

    pub fn resumeWith(self: *Body, resumption: Value, argument: Value, successor: Interpretation, state: []const Value) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.check(resumption);
        try self.check(argument);
        try self.author.checkInterpretation(successor);
        const shape = self.author.raw.schemas.items[@intCast(resumption.schema.id)];
        if (shape != .internal or shape.internal != .resumption) return error.TypeMismatch;
        const signature = shape.internal.resumption;
        const info = resumption.schema.resumption;
        const input_matches = if (info) |known|
            try sameSchema(argument.schema, known.input)
        else
            try sameSchema(argument.schema, .{ .owner = self.author, .id = signature.input });
        const successor_matches = if (info) |known|
            try sameSchema(successor.input, known.answer)
        else
            try sameSchema(successor.input, .{ .owner = self.author, .id = signature.answer });
        if (signature.mode != .shallow or signature.effect != successor.operation.id or
            !input_matches or !successor_matches)
        {
            self.author.report(.handler_mismatch, "shallow resumption", signature.input, argument.schema.id, null, self.scope.name);
            return error.TypeMismatch;
        }
        if (state.len != successor.state.len) return try self.author.arity("shallow successor state", successor.state.len, state.len, self.scope.name);
        const ids = try self.author.raw.allocator().alloc(p.Id, state.len);
        for (state, successor.state, ids) |value, named, *id| {
            try self.check(value);
            if (!try sameSchema(value.schema, named.schema)) return error.TypeMismatch;
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
        errdefer |err| self.author.onError(err);
        try self.check(resumption);
        try self.check(computation.value);
        const shape = self.author.raw.schemas.items[@intCast(resumption.schema.id)];
        if (shape != .internal or shape.internal != .resumption) return error.TypeMismatch;
        const signature = shape.internal.resumption;
        const work = self.author.raw.schemas.items[@intCast(computation.value.schema.id)];
        if (work != .internal or work.internal != .computation) return error.TypeMismatch;
        const thunk = work.internal.computation;
        const effect = try self.author.sourceEffect(signature.effect, "resumption effect");
        if (thunk.parameters.len != effect.use_site_effects.len) return error.TypeMismatch;
        const computation_result = if (computation.value.schema.callable) |known|
            known.result
        else
            Schema{ .owner = self.author, .id = thunk.result };
        const expected_input = if (resumption.schema.resumption) |known|
            known.input
        else
            Schema{ .owner = self.author, .id = signature.input };
        if (!try sameSchema(computation_result, expected_input)) return error.TypeMismatch;
        for (thunk.parameters, effect.use_site_effects) |schema_id, effect_id| {
            const parameter_schema = try self.author.sourceSchema(schema_id, "resumption computation parameter");
            if (parameter_schema != .internal or parameter_schema.internal != .capability or
                parameter_schema.internal.capability != effect_id) return error.InvalidCapability;
        }
        for (thunk.effects) |effect_id| {
            if (std.mem.indexOfScalar(p.Id, effect.use_site_effects, effect_id) == null)
                return error.InvalidCapability;
        }
        return self.append(try self.author.raw.term(.{ .resume_computation = .{
            .resumption = resumption.id,
            .computation = computation.value.id,
        } }), if (resumption.schema.resumption) |known| known.answer else .{ .owner = self.author, .id = signature.answer });
    }

    pub fn handle(self: *Body, interpretation: Interpretation, callable: Callable, arguments: []const Value, state: []const Value) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.check(callable.value);
        try self.author.checkInterpretation(interpretation);
        if (state.len != interpretation.state.len) return try self.author.arity("handler state", interpretation.state.len, state.len, self.scope.name);
        const state_ids = try self.author.raw.allocator().alloc(p.Id, state.len);
        for (state, interpretation.state, state_ids) |value, named, *id| {
            try self.check(value);
            if (!try sameSchema(value.schema, named.schema)) return error.TypeMismatch;
            id.* = value.id;
        }
        const argument_ids = try self.author.raw.allocator().alloc(p.Id, arguments.len);
        const shape = self.author.raw.schemas.items[@intCast(callable.value.schema.id)];
        if (shape != .internal or shape.internal != .computation) return error.TypeMismatch;
        const body_result = if (callable.value.schema.callable) |known|
            known.result
        else
            Schema{ .owner = self.author, .id = shape.internal.computation.result };
        if (!try sameSchema(body_result, interpretation.input)) {
            self.author.report(.argument_mismatch, "handled body result", interpretation.input.id, body_result.id, null, self.scope.name);
            self.author.diagnostic.?.relationship = "named callable result provenance";
            return error.TypeMismatch;
        }
        const parameters = shape.internal.computation.parameters;
        if (parameters.len != arguments.len + 1) {
            self.author.report(.argument_mismatch, "handled body capability", interpretation.operation.id, null, null, self.scope.name);
            self.author.diagnostic.?.relationship = "one injected capability parameter";
            self.author.diagnostic.?.expected_count = arguments.len + 1;
            self.author.diagnostic.?.actual_count = parameters.len;
            return error.InvalidArgument;
        }
        const cap = try self.author.sourceSchema(parameters[0], "handled body capability");
        if (cap != .internal or cap.internal != .capability or
            cap.internal.capability != interpretation.operation.id) return error.InvalidCapability;
        for (arguments, argument_ids, 0..) |value, *id, index| {
            try self.check(value);
            const expected = if (callable.value.schema.callable) |known|
                known.parameters[index + 1]
            else
                Schema{ .owner = self.author, .id = parameters[index + 1] };
            if (!try sameSchema(value.schema, expected)) {
                self.author.report(.argument_mismatch, "handled body argument", parameters[index + 1], value.schema.id, null, self.scope.name);
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
        errdefer |err| self.author.onError(err);
        try self.check(work.value);
        try self.check(cleanup.value);
        const shape = self.author.raw.schemas.items[@intCast(work.value.schema.id)];
        if (shape != .internal or shape.internal != .computation) return error.TypeMismatch;
        const cleanup_shape = self.author.raw.schemas.items[@intCast(cleanup.value.schema.id)];
        if (cleanup_shape != .internal or cleanup_shape.internal != .computation) return error.TypeMismatch;
        const signature = shape.internal.computation;
        const loaned: usize = @intFromBool(resource != null);
        if (work.value.schema.callable) |known| {
            if (known.parameters.len != arguments.len + loaned) return try self.author.arity("protected work arguments", known.parameters.len, arguments.len + loaned, self.scope.name);
            if (resource) |owned| {
                const borrowed = known.parameters[0].borrowed orelse return error.TypeMismatch;
                if (!try sameSchema(owned.schema, borrowed.*)) return error.TypeMismatch;
            }
        } else {
            if (signature.parameters.len != arguments.len + loaned) return try self.author.arity("protected work arguments", signature.parameters.len, arguments.len + loaned, self.scope.name);
            if (resource) |owned| {
                const borrowed_shape = try self.author.sourceSchema(signature.parameters[0], "protected borrowed resource");
                if (borrowed_shape != .internal or borrowed_shape.internal != .borrowed) return error.TypeMismatch;
                if (!try sameSchema(owned.schema, .{ .owner = self.author, .id = borrowed_shape.internal.borrowed.value })) return error.TypeMismatch;
            }
        }
        const cleanup_info = cleanup.value.schema.callable orelse {
            self.author.report(.schema_mismatch, "cleanup signature", null, cleanup.value.schema.id, null, self.scope.name);
            self.author.diagnostic.?.relationship = "missing authored cleanup signature";
            return error.TypeMismatch;
        };
        if (cleanup_info.parameters.len != loaned + 1) return try self.author.arity("cleanup arguments", cleanup_info.parameters.len, loaned + 1, self.scope.name);
        if (cleanup_shape.internal.computation.parameters.len != loaned + 1) return try self.author.arity("cleanup arguments", cleanup_shape.internal.computation.parameters.len, loaned + 1, self.scope.name);
        const exit_info = cleanup_info.parameters[0].structure orelse {
            self.author.report(.schema_mismatch, "cleanup exit parameter", null, cleanup_info.parameters[0].id, null, self.scope.name);
            self.author.diagnostic.?.relationship = "authored exit-info description";
            return error.TypeMismatch;
        };
        if (exit_info.kind != .exit_info or exit_info.children.len != 1) {
            self.author.report(.schema_mismatch, "cleanup exit parameter", null, cleanup_info.parameters[0].id, null, self.scope.name);
            self.author.diagnostic.?.relationship = "authored exit-info description";
            return error.TypeMismatch;
        }
        const unit = try self.author.scalar(void);
        if (cleanup_shape.internal.computation.result != unit.id or !try sameSchema(cleanup_info.result, unit)) {
            self.author.report(.schema_mismatch, "cleanup result", unit.id, cleanup_info.result.id, null, self.scope.name);
            self.author.diagnostic.?.relationship = "unit cleanup result";
            return error.TypeMismatch;
        }
        if (resource) |owned| if (!try sameSchema(owned.schema, cleanup_info.parameters[1]))
            return error.TypeMismatch;
        const ids = try self.author.raw.allocator().alloc(p.Id, arguments.len);
        for (arguments, ids, 0..) |value, *id, index| {
            try self.check(value);
            const expected = if (work.value.schema.callable) |known|
                known.parameters[index + loaned]
            else
                Schema{ .owner = self.author, .id = signature.parameters[index + loaned] };
            if (!try sameSchema(value.schema, expected)) return error.TypeMismatch;
            id.* = value.id;
        }
        if (resource) |value| try self.check(value);
        if (loan_region) |region_handle| {
            if (region_handle.owner != self.author) return try self.author.foreign("region", self.scope.name);
            if (region_handle.id >= self.author.raw.region_count) return error.InvalidReference;
        }
        return self.append(try self.author.raw.term(.{ .protect = .{
            .body = work.value.id,
            .cleanup = cleanup.value.id,
            .arguments = ids,
            .resource = if (resource) |value| value.id else null,
            .loan_region = if (loan_region) |region_handle| region_handle.id else null,
        } }), if (work.value.schema.callable) |known| known.result else .{ .owner = self.author, .id = shape.internal.computation.result });
    }

    pub fn withRegion(self: *Body, region_handle: Region, work: Callable, arguments: []const Value) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.check(work.value);
        if (region_handle.owner != self.author) return try self.author.foreign("region", self.scope.name);
        if (region_handle.id >= self.author.raw.region_count) return error.InvalidReference;
        const shape = self.author.raw.schemas.items[@intCast(work.value.schema.id)];
        if (shape != .internal or shape.internal != .computation) return error.TypeMismatch;
        const signature = shape.internal.computation;
        if (work.value.schema.callable) |known| {
            if (known.parameters.len != arguments.len + 1) return try self.author.arity("region body arguments", known.parameters.len, arguments.len + 1, self.scope.name);
            const first = try self.author.sourceSchema(known.parameters[0].id, "region body parameter");
            if (first != .internal or first.internal != .region or
                first.internal.region != region_handle.id) return error.TypeMismatch;
        } else {
            if (signature.parameters.len != arguments.len + 1) return try self.author.arity("region body arguments", signature.parameters.len, arguments.len + 1, self.scope.name);
            const first = try self.author.sourceSchema(signature.parameters[0], "region body parameter");
            if (first != .internal or first.internal != .region or
                first.internal.region != region_handle.id) return error.TypeMismatch;
        }
        const ids = try self.author.raw.allocator().alloc(p.Id, arguments.len);
        for (arguments, ids, 0..) |value, *id, index| {
            try self.check(value);
            const expected = if (work.value.schema.callable) |known|
                known.parameters[index + 1]
            else
                Schema{ .owner = self.author, .id = signature.parameters[index + 1] };
            if (!try sameSchema(value.schema, expected)) return error.TypeMismatch;
            id.* = value.id;
        }
        return self.append(try self.author.raw.term(.{ .with_region = .{
            .region = region_handle.id,
            .body = work.value.id,
            .arguments = ids,
        } }), if (work.value.schema.callable) |known| known.result else .{ .owner = self.author, .id = shape.internal.computation.result });
    }

    pub fn dispose(self: *Body, value: Value) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.check(value);
        return self.append(try self.author.raw.term(.{ .dispose = value.id }), try self.author.scalar(void));
    }

    pub fn packResource(self: *Body, owned: Schema, representation: Value) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.check(representation);
        try self.author.checkSchema(owned);
        const shape = self.author.raw.schemas.items[@intCast(owned.id)];
        if (shape != .internal or shape.internal != .abstract_resource)
            return error.TypeMismatch;
        const resource_id = shape.internal.abstract_resource;
        if (resource_id >= self.author.raw.resources.items.len or
            self.author.raw.resources.items[@intCast(resource_id)].representation !=
                representation.schema.id) return error.TypeMismatch;
        if (owned.resource) |known| if (!try sameSchema(representation.schema, known.*))
            return error.TypeMismatch;
        return self.author.mintValue(.{ .owner = self.author, .schema = owned, .scope = self.scope, .id = try self.author.raw.primitive(owned.id, .resource_pack, &.{representation.id}, 0) });
    }

    pub fn unpackResource(self: *Body, value: Value) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.check(value);
        var schema = self.author.raw.schemas.items[@intCast(value.schema.id)];
        if (schema == .internal and schema.internal == .borrowed) {
            schema = try self.author.sourceSchema(schema.internal.borrowed.value, "borrowed representation");
        }
        if (schema != .internal or schema.internal != .abstract_resource)
            return error.TypeMismatch;
        const resource_id = schema.internal.abstract_resource;
        if (resource_id >= self.author.raw.resources.items.len)
            return error.InvalidReference;
        const known_owned = if (value.schema.borrowed) |owned| owned.* else value.schema;
        const representation = if (known_owned.resource) |known|
            known.*
        else
            try self.author.adoptSchema(self.author.raw.resources.items[@intCast(resource_id)].representation);
        if (representation.id != self.author.raw.resources.items[@intCast(resource_id)].representation)
            return error.TypeMismatch;
        return self.author.mintValue(.{ .owner = self.author, .schema = representation, .scope = self.scope, .id = try self.author.raw.primitive(representation.id, .resource_unpack, &.{value.id}, 0) });
    }

    pub fn call(self: *Body, function: Function, arguments: []const Value) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.ensureOpen();
        try self.author.checkFunction(function);
        if (arguments.len != function.parameters.len) return try self.author.arity(function.name, function.parameters.len, arguments.len, self.scope.name);
        const ids = try self.author.raw.allocator().alloc(p.Id, arguments.len);
        for (arguments, function.parameters, ids) |argument, named, *id| {
            try self.check(argument);
            if (!try sameSchema(argument.schema, named.schema)) {
                self.author.report(.argument_mismatch, function.name, named.schema.id, argument.schema.id, null, self.scope.name);
                self.author.diagnostic.?.relationship = "callable argument layout";
                return error.TypeMismatch;
            }
            id.* = argument.id;
        }
        return self.append(try self.author.raw.term(.{ .call = .{ .function = function.id, .arguments = ids } }), function.result);
    }

    pub fn lambda(self: *Body, function: Function, captures: []const Schema, use: p.Use) Error!Callable {
        errdefer |err| self.author.onError(err);
        try self.ensureOpen();
        const schema = try self.author.callableSchema(function, captures, use);
        return .{ .value = try self.author.mintValue(.{ .owner = self.author, .schema = schema, .id = try self.author.raw.lambda(function.id, schema.id), .scope = self.scope }) };
    }

    pub fn apply(self: *Body, callable: Callable, arguments: []const Value) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.check(callable.value);
        const shape = self.author.raw.schemas.items[@intCast(callable.value.schema.id)];
        if (shape != .internal or shape.internal != .computation) return error.TypeMismatch;
        const signature = shape.internal.computation;
        if (arguments.len != signature.parameters.len) return try self.author.arity("callable application", signature.parameters.len, arguments.len, self.scope.name);
        const ids = try self.author.raw.allocator().alloc(p.Id, arguments.len);
        for (arguments, signature.parameters, ids, 0..) |argument, schema_id, *id, index| {
            try self.check(argument);
            const expected = if (callable.value.schema.callable) |known|
                known.parameters[index]
            else
                Schema{ .owner = self.author, .id = schema_id };
            if (!try sameSchema(argument.schema, expected)) {
                self.author.report(.argument_mismatch, "callable argument", schema_id, argument.schema.id, null, self.scope.name);
                self.author.diagnostic.?.relationship = "callable argument layout";
                return error.TypeMismatch;
            }
            id.* = argument.id;
        }
        return self.append(try self.author.raw.term(.{ .apply = .{
            .computation = callable.value.id,
            .arguments = ids,
        } }), if (callable.value.schema.callable) |known| known.result else .{ .owner = self.author, .id = signature.result });
    }

    pub fn asCallable(self: *Body, value: Value) Error!Callable {
        errdefer |err| self.author.onError(err);
        try self.check(value);
        const shape = self.author.raw.schemas.items[@intCast(value.schema.id)];
        if (shape != .internal or shape.internal != .computation) return error.TypeMismatch;
        return .{ .value = value };
    }

    pub fn product(self: *Body, record: Record, fields: []const NamedValue) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.ensureOpen();
        if (record.owner != self.author) return try self.author.foreign("record", self.scope.name);
        const declared_fields = try self.namedFields(record.schema, .record);
        if (fields.len != declared_fields.len) {
            self.author.report(.field_mismatch, "record fields", null, null, null, self.scope.name);
            self.author.diagnostic.?.expected_count = declared_fields.len;
            self.author.diagnostic.?.actual_count = fields.len;
            return error.InvalidField;
        }
        const ids = try self.author.raw.allocator().alloc(p.Id, fields.len);
        for (declared_fields, ids) |declared, *id| {
            var found: ?Value = null;
            for (fields) |provided| if (std.mem.eql(u8, provided.name, declared.name)) {
                if (found != null) return error.DuplicateName;
                found = provided.value;
            };
            const value = found orelse return error.InvalidField;
            try self.check(value);
            if (!try sameSchema(value.schema, declared.schema)) {
                self.author.report(.field_mismatch, declared.name, declared.schema.id, value.schema.id, null, self.scope.name);
                self.author.diagnostic.?.relationship = "named field schema and layout";
                return error.TypeMismatch;
            }
            id.* = value.id;
        }
        return self.author.mintValue(.{ .owner = self.author, .schema = record.schema, .scope = self.scope, .id = try self.author.raw.primitive(record.schema.id, .product, ids, 0) });
    }

    pub fn field(self: *Body, record: Record, value: Value, name: []const u8) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.check(value);
        if (record.owner != self.author) return try self.author.foreign("record", self.scope.name);
        const declared_fields = try self.namedFields(record.schema, .record);
        if (!try sameSchema(value.schema, record.schema)) {
            self.author.report(.field_mismatch, try self.author.diagnosticName(name), record.schema.id, value.schema.id, null, self.scope.name);
            self.author.diagnostic.?.relationship = "named record layout";
            return error.TypeMismatch;
        }
        for (declared_fields, 0..) |declared, index| if (std.mem.eql(u8, name, declared.name)) {
            return self.author.mintValue(.{ .owner = self.author, .schema = declared.schema, .scope = self.scope, .id = try self.author.raw.primitive(declared.schema.id, .field, &.{value.id}, index) });
        };
        self.author.report(.field_mismatch, try self.author.diagnosticName(name), null, value.schema.id, null, self.scope.name);
        return error.InvalidField;
    }

    pub fn inject(self: *Body, variant: Variant, name: []const u8, payload: Value) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.check(payload);
        if (variant.owner != self.author) return try self.author.foreign("variant", self.scope.name);
        const alternatives = try self.namedFields(variant.schema, .variant);
        for (alternatives, 0..) |alternative, index| if (std.mem.eql(u8, name, alternative.name)) {
            if (!try sameSchema(payload.schema, alternative.schema)) {
                self.author.report(.field_mismatch, alternative.name, alternative.schema.id, payload.schema.id, null, self.scope.name);
                self.author.diagnostic.?.relationship = "named alternative schema and layout";
                return error.TypeMismatch;
            }
            return self.author.mintValue(.{ .owner = self.author, .schema = variant.schema, .scope = self.scope, .id = try self.author.raw.primitive(variant.schema.id, .variant, &.{payload.id}, index) });
        };
        self.author.report(.field_mismatch, try self.author.diagnosticName(name), null, payload.schema.id, null, self.scope.name);
        return error.InvalidField;
    }

    pub fn variantCase(self: *Body, variant: Variant, name: []const u8) Error!MatchCase {
        errdefer |err| self.author.onError(err);
        try self.ensureOpen();
        if (variant.owner != self.author) return try self.author.foreign("variant", self.scope.name);
        const alternatives = try self.namedFields(variant.schema, .variant);
        for (alternatives, 0..) |alternative, index| if (std.mem.eql(u8, name, alternative.name)) {
            const body = try self.child(name);
            const variable = try self.author.raw.variable(alternative.schema.id);
            const payload = try self.author.mintValue(.{ .owner = self.author, .schema = alternative.schema, .scope = body.scope, .id = try self.author.raw.reference(variable) });
            const origin = try self.author.raw.allocator().create(CaseOrigin);
            origin.* = .{ .variant = variant.schema, .index = index, .variable = variable, .scope = body.scope };
            try self.author.case_origins.put(self.author.raw.allocator(), body.scope, origin);
            return .{ .body = body, .payload = payload, .origin = origin };
        };
        self.author.report(.branch_mismatch, try self.author.diagnosticName(name), variant.schema.id, null, null, self.scope.name);
        self.author.diagnostic.?.relationship = "named variant alternative";
        return error.InvalidField;
    }

    pub fn matchVariant(self: *Body, variant: Variant, value: Value, branches: []const FinishedCase) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.check(value);
        if (variant.owner != self.author) return try self.author.foreign("variant", self.scope.name);
        const alternatives = try self.namedFields(variant.schema, .variant);
        if (!try sameSchema(value.schema, variant.schema) or branches.len != alternatives.len) {
            self.author.report(.branch_mismatch, "tagged variant", variant.schema.id, value.schema.id, null, self.scope.name);
            self.author.diagnostic.?.relationship = "named variant layout and branch count";
            if (branches.len != alternatives.len) {
                self.author.diagnostic.?.expected_count = alternatives.len;
                self.author.diagnostic.?.actual_count = branches.len;
            }
            return error.TypeMismatch;
        }
        const cases = try self.author.raw.allocator().alloc(source.ast.SumCase, branches.len);
        var result: ?Schema = null;
        for (branches, 0..) |branch, position| {
            try self.author.checkBlock(branch.block);
            const origin = self.author.case_origins.get(branch.block.scope) orelse {
                self.author.report(.branch_mismatch, "variant case origin", null, null, null, self.scope.name);
                return error.InvalidBranch;
            };
            if (branch.origin != origin or origin.scope != branch.block.scope) {
                self.author.report(.branch_mismatch, "variant case origin", null, null, null, self.scope.name);
                return error.InvalidBranch;
            }
            if (!try sameSchema(origin.variant, variant.schema)) {
                self.author.report(.branch_mismatch, "variant case", variant.schema.id, origin.variant.id, branch.block.scope.name, self.scope.name);
                self.author.diagnostic.?.relationship = "named variant layout";
                return error.InvalidBranch;
            }
            if (branch.block.scope.parent != self.scope or origin.index >= cases.len)
                return error.InvalidBranch;
            for (branches[0..position]) |other| if (origin.index == other.origin.index) return error.InvalidBranch;
            if (result) |expected| {
                if (!try sameSchema(expected, branch.block.result)) return error.TypeMismatch;
            } else result = branch.block.result;
            cases[origin.index] = .{ .variable = origin.variable, .body = branch.block.term };
        }
        return self.append(try self.author.raw.term(.{ .match_sum = .{
            .value = value.id,
            .cases = cases,
        } }), result orelse return error.InvalidBranch);
    }

    pub fn singletonSequence(self: *Body, item: Value) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.check(item);
        const sequence = try self.author.sequenceSchema(item.schema);
        return self.author.mintValue(.{ .owner = self.author, .schema = sequence, .scope = self.scope, .id = try self.author.raw.primitive(sequence.id, .sequence, &.{item.id}, 0) });
    }

    pub fn concatSequences(self: *Body, left: Value, right: Value) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.check(left);
        try self.check(right);
        if (!try sameSchema(left.schema, right.schema)) return error.TypeMismatch;
        const shape = self.author.raw.schemas.items[@intCast(left.schema.id)];
        if (shape != .seq) return error.TypeMismatch;
        return self.author.mintValue(.{ .owner = self.author, .schema = left.schema, .scope = self.scope, .id = try self.author.raw.primitive(left.schema.id, .sequence_concat, &.{ left.id, right.id }, 0) });
    }

    pub fn checkedAdd(self: *Body, left: Value, right: Value, failure: FailureLiteral) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.check(left);
        try self.check(right);
        if (!self.author.failure_literals.contains(failure.origin)) {
            self.author.report(.argument_mismatch, "checked addition failure", null, null, null, self.scope.name);
            self.author.diagnostic.?.relationship = "issued literal failure";
            return error.InvalidSource;
        }
        try self.check(failure.origin.value);
        if (!try sameSchema(left.schema, right.schema)) return error.TypeMismatch;
        const shape = self.author.raw.schemas.items[@intCast(left.schema.id)];
        if (shape != .u8 and shape != .u16 and shape != .u32 and shape != .u64 and
            shape != .i8 and shape != .i16 and shape != .i32 and shape != .i64) return error.TypeMismatch;
        const id = try self.author.raw.value(.{
            .schema = left.schema.id,
            .expression = .{ .primitive = .{
                .opcode = .integer_add,
                .operands = &.{ left.id, right.id },
                .failures = &.{.{ .kind = .arithmetic_overflow, .value = failure.origin.literal }},
            } },
        });
        try self.author.checked_add_failures.put(self.author.raw.allocator(), id, failure.origin.value.schema);
        return self.author.mintValue(.{ .owner = self.author, .schema = left.schema, .scope = self.scope, .id = id });
    }

    pub fn equal(self: *Body, left: Value, right: Value) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.check(left);
        try self.check(right);
        if (!try sameSchema(left.schema, right.schema)) return error.TypeMismatch;
        const boolean = try self.author.scalar(bool);
        return self.author.mintValue(.{ .owner = self.author, .schema = boolean, .scope = self.scope, .id = try self.author.raw.primitive(boolean.id, .equal, &.{ left.id, right.id }, 0) });
    }

    pub fn booleanNot(self: *Body, value: Value) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.check(value);
        const boolean = try self.author.scalar(bool);
        if (value.schema.id != boolean.id) return error.TypeMismatch;
        return self.author.mintValue(.{ .owner = self.author, .schema = boolean, .scope = self.scope, .id = try self.author.raw.primitive(boolean.id, .boolean_not, &.{value.id}, 0) });
    }

    pub fn select(self: *Body, condition: Value, when_true: Block, when_false: Block) Error!Value {
        errdefer |err| self.author.onError(err);
        try self.check(condition);
        const boolean = try self.author.scalar(bool);
        if (condition.schema.id != boolean.id) return error.TypeMismatch;
        try self.author.checkBlock(when_true);
        try self.author.checkBlock(when_false);
        if (when_true.scope.parent != self.scope or when_false.scope.parent != self.scope or
            when_true.scope == when_false.scope) return error.InvalidBranch;
        if (!try sameSchema(when_true.result, when_false.result)) {
            self.author.report(.branch_mismatch, "conditional result", when_true.result.id, when_false.result.id, when_true.scope.name, when_false.scope.name);
            self.author.diagnostic.?.relationship = "joined result layout";
            return error.TypeMismatch;
        }
        return self.append(try self.author.raw.term(.{ .conditional = .{
            .condition = condition.id,
            .when_true = when_true.term,
            .when_false = when_false.term,
        } }), when_true.result);
    }

    pub fn finish(self: *Body, result: Value) Error!Block {
        errdefer |err| self.author.onError(err);
        try self.check(result);
        return self.close(try self.author.raw.pure(result.id), result.schema);
    }

    pub fn fail(self: *Body, failure: Value, expected_result: Schema) Error!Block {
        errdefer |err| self.author.onError(err);
        try self.check(failure);
        try self.author.checkSchema(expected_result);
        return self.close(try self.author.raw.term(.{ .fail = failure.id }), expected_result);
    }

    fn close(self: *Body, terminal: p.Id, result: Schema) Error!Block {
        errdefer |err| self.author.onError(err);
        try self.ensureOpen();
        var term = terminal;
        var index = self.scope.steps.items.len;
        while (index != 0) {
            index -= 1;
            const step = self.scope.steps.items[index];
            term = try self.author.raw.bind(step.variable, step.term, term);
        }
        self.scope.open = false;
        return self.author.issueBlock(.{ .owner = self.author, .term = term, .result = result, .scope = self.scope });
    }
};
