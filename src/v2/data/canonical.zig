// Copyright (c) 2026 Boundary contributors. MIT license.
//! Root-ordered, first-visit catalog numbering. This module rewrites only data;
//! it neither evaluates code nor infers executable reachability from values.
const std = @import("std");
const p = @import("program.zig");
const admission = @import("admission.zig");
pub const Error = admission.Error;
const Kind = enum { schema, constant, effect, function, block, handler, capture, region, resource, constructor };
const count = std.meta.fields(Kind).len;
const missing = std.math.maxInt(p.Id);
const Ref = struct { kind: Kind, id: p.Id };

pub const Normalized = struct {
    arena: std.heap.ArenaAllocator,
    program: p.Program,
    pub fn deinit(self: *Normalized) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

/// Owns the complete result, including immutable bytes. Input may be released
/// immediately. Invalid unreachable declarations reject before pruning.
pub fn normalize(allocator: std.mem.Allocator, input: p.Program) Error!Normalized {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const storage = arena.allocator();
    var temporary = std.heap.ArenaAllocator.init(allocator);
    defer temporary.deinit();
    const scratch = temporary.allocator();
    try admission.program(scratch, input);
    const program = try build(storage, scratch, input);
    return .{ .arena = arena, .program = program };
}

/// Validate canonical numbering and absence of unreachable declarations. Every
/// discovered ID must already equal its canonical number. Admission separately
/// checks the ordered rows; no rewritten catalog or digest comparison is needed.
pub fn require(allocator: std.mem.Allocator, input: p.Program) Error!void {
    var temporary = std.heap.ArenaAllocator.init(allocator);
    defer temporary.deinit();
    const scratch = temporary.allocator();
    try admission.program(scratch, input);
    const visitor = try scan(scratch, input);
    for (visitor.maps) |map| for (map, 0..) |id, index| {
        if (id != index) return error.NonCanonical;
    };
    const regions = visitor.order[@intFromEnum(Kind.region)].items;
    if (regions.len != input.scopes.region_count) return error.NonCanonical;
    for (regions, 0..) |id, index| if (id != index) return error.NonCanonical;
}

pub fn equal(comptime T: type, a: T, b: T) bool {
    return switch (@typeInfo(T)) {
        .pointer => |info| blk: {
            if (a.len != b.len) break :blk false;
            for (a, b) |left, right| if (!equal(info.child, left, right)) break :blk false;
            break :blk true;
        },
        .@"struct" => |info| blk: {
            inline for (info.fields) |field| if (!equal(field.type, @field(a, field.name), @field(b, field.name))) break :blk false;
            break :blk true;
        },
        .@"union" => |info| blk: {
            if (std.meta.activeTag(a) != std.meta.activeTag(b)) break :blk false;
            inline for (info.fields) |field| if (std.mem.eql(u8, field.name, @tagName(a))) break :blk equal(field.type, @field(a, field.name), @field(b, field.name));
            unreachable;
        },
        .optional => |info| if (a) |left| (if (b) |right| equal(info.child, left, right) else false) else b == null,
        .void => true,
        else => a == b,
    };
}

fn scan(scratch: std.mem.Allocator, input: p.Program) Error!Visitor {
    var visitor: Visitor = .{ .allocator = scratch, .scratch = scratch, .input = input };
    const sizes = [_]usize{ input.schemas.len, input.constants.len, input.effects.len, input.functions.len, input.blocks.len, input.handlers.len, input.scopes.captures.len, 0, input.scopes.resources.len, input.constructors.len };
    for (&visitor.maps, sizes) |*map, size| {
        map.* = try scratch.alloc(p.Id, size);
        @memset(map.*, missing);
    }
    _ = try visitor.roots(input.roots);
    var pending: std.ArrayList(Ref) = .empty;
    try visitor.pushReverse(&pending);
    var literals: std.HashMapUnmanaged(p.Literal, p.Id, LiteralContext, 80) = .empty;
    while (pending.pop()) |ref| {
        const k = @intFromEnum(ref.kind);
        if (ref.kind == .region) {
            if (ref.id >= input.scopes.region_count) return error.InvalidReference;
            const entry = try visitor.region_ids.getOrPut(scratch, ref.id);
            if (entry.found_existing) continue;
            entry.value_ptr.* = visitor.order[k].items.len;
            try visitor.order[k].append(scratch, ref.id);
            continue;
        }
        const old = std.math.cast(usize, ref.id) orelse return error.InvalidReference;
        if (old >= visitor.maps[k].len) return error.InvalidReference;
        if (visitor.maps[k][old] != missing) continue;
        if (ref.kind == .constant) {
            const entry = try literals.getOrPutContext(scratch, input.constants[old], .{});
            if (entry.found_existing) {
                visitor.maps[k][old] = entry.value_ptr.*;
                continue;
            }
            entry.value_ptr.* = visitor.order[k].items.len;
        }
        visitor.maps[k][old] = visitor.order[k].items.len;
        try visitor.order[k].append(scratch, ref.id);
        try visitor.node(ref);
        try visitor.pushReverse(&pending);
    }
    return visitor;
}

fn build(allocator: std.mem.Allocator, scratch: std.mem.Allocator, input: p.Program) Error!p.Program {
    var visitor = try scan(scratch, input);
    visitor.allocator = allocator;
    visitor.scanning = false;
    const output: p.Program = .{
        .roots = try visitor.roots(input.roots),
        .schemas = try visitor.catalog(p.Schema, .schema, input.schemas, Visitor.schema),
        .constants = try visitor.catalog(p.Literal, .constant, input.constants, Visitor.literal),
        .effects = try visitor.catalog(p.Effect, .effect, input.effects, Visitor.effect),
        .functions = try visitor.catalog(p.Function, .function, input.functions, Visitor.function),
        .blocks = try visitor.catalog(p.Block, .block, input.blocks, Visitor.block),
        .handlers = try visitor.catalog(p.Handler, .handler, input.handlers, Visitor.handler),
        .scopes = .{
            .captures = try visitor.catalog(p.Capture, .capture, input.scopes.captures, Visitor.capture),
            .region_count = visitor.order[@intFromEnum(Kind.region)].items.len,
            .resources = try visitor.catalog(p.Resource, .resource, input.scopes.resources, Visitor.resource),
        },
        .constructors = try visitor.catalog(p.Constructor, .constructor, input.constructors, Visitor.constructor),
    };
    try admission.program(scratch, output);
    return output;
}

const LiteralContext = struct {
    pub fn hash(_: LiteralContext, value: p.Literal) u64 {
        return std.hash.Wyhash.hash(value.schema, value.bytes);
    }
    pub fn eql(_: LiteralContext, a: p.Literal, b: p.Literal) bool {
        return a.schema == b.schema and std.mem.eql(u8, a.bytes, b.bytes);
    }
};

const Visitor = struct {
    allocator: std.mem.Allocator,
    scratch: std.mem.Allocator,
    input: p.Program,
    scanning: bool = true,
    maps: [count][]p.Id = undefined,
    region_ids: std.AutoHashMapUnmanaged(p.Id, p.Id) = .empty,
    order: [count]std.ArrayList(p.Id) = @splat(.empty),
    children: std.ArrayList(Ref) = .empty,

    fn id(self: *Visitor, kind: Kind, old: p.Id) Error!p.Id {
        if (self.scanning) {
            try self.children.append(self.scratch, .{ .kind = kind, .id = old });
            return old;
        }
        if (kind == .region) return self.region_ids.get(old) orelse error.InvalidReference;
        const map = self.maps[@intFromEnum(kind)];
        if (old >= map.len or map[@intCast(old)] == missing) return error.InvalidReference;
        return map[@intCast(old)];
    }
    fn ids(self: *Visitor, kind: Kind, values: []const p.Id) Error![]const p.Id {
        const output = if (self.scanning) null else try self.allocator.alloc(p.Id, values.len);
        for (values, 0..) |old, index| {
            const value = try self.id(kind, old);
            if (output) |out| out[index] = value;
        }
        return output orelse values;
    }
    fn set(self: *Visitor, kind: Kind, values: []const p.Id) Error![]const p.Id {
        const output = try self.ids(kind, values);
        if (!self.scanning) std.mem.sort(p.Id, @constCast(output), {}, std.sort.asc(p.Id));
        return output;
    }
    fn row(self: *Visitor, values: []const p.Id) Error![]const p.Id {
        if (self.scanning) {
            const ordered = try self.scratch.dupe(p.Id, values);
            std.mem.sort(p.Id, ordered, self.input, struct {
                fn less(program: p.Program, a: p.Id, b: p.Id) bool {
                    return std.mem.order(u8, program.effects[@intCast(a)].identity, program.effects[@intCast(b)].identity) == .lt;
                }
            }.less);
            _ = try self.ids(.effect, ordered);
            return values;
        }
        return self.set(.effect, values);
    }
    fn regions(self: *Visitor, values: []const p.Id) Error![]const p.Id {
        return self.set(.region, values);
    }
    fn optional(self: *Visitor, kind: Kind, value: ?p.Id) Error!?p.Id {
        return if (value) |old| try self.id(kind, old) else null;
    }
    fn copy(self: *Visitor, comptime T: type, values: []const T) Error![]const T {
        return if (self.scanning) values else try self.allocator.dupe(T, values);
    }
    fn items(self: *Visitor, comptime T: type, values: []const T, comptime rewrite: anytype) Error![]const T {
        const output = if (self.scanning) null else try self.allocator.alloc(T, values.len);
        for (values, 0..) |old, index| {
            const value = try rewrite(self, old);
            if (output) |out| out[index] = value;
        }
        return output orelse values;
    }
    fn catalog(self: *Visitor, comptime T: type, kind: Kind, values: []const T, comptime rewrite: anytype) Error![]const T {
        const order = self.order[@intFromEnum(kind)].items;
        const output = try self.allocator.alloc(T, order.len);
        for (output, order) |*out, old| out.* = try rewrite(self, values[@intCast(old)]);
        return output;
    }
    fn pushReverse(self: *Visitor, pending: *std.ArrayList(Ref)) Error!void {
        var index = self.children.items.len;
        while (index != 0) {
            index -= 1;
            try pending.append(self.scratch, self.children.items[index]);
        }
        self.children.clearRetainingCapacity();
    }
    fn node(self: *Visitor, ref: Ref) Error!void {
        const index: usize = @intCast(ref.id);
        switch (ref.kind) {
            .schema => _ = try self.schema(self.input.schemas[index]),
            .constant => _ = try self.literal(self.input.constants[index]),
            .effect => _ = try self.effect(self.input.effects[index]),
            .function => _ = try self.function(self.input.functions[index]),
            .block => _ = try self.block(self.input.blocks[index]),
            .handler => _ = try self.handler(self.input.handlers[index]),
            .capture => _ = try self.capture(self.input.scopes.captures[index]),
            .region => {},
            .resource => _ = try self.resource(self.input.scopes.resources[index]),
            .constructor => _ = try self.constructor(self.input.constructors[index]),
        }
    }
    fn roots(self: *Visitor, value: p.Roots) Error!p.Roots {
        return .{ .profile = value.profile, .entry = try self.id(.function, value.entry), .result = try self.id(.schema, value.result), .failure = try self.id(.schema, value.failure) };
    }
    fn schema(self: *Visitor, value: p.Schema) Error!p.Schema {
        return switch (value) {
            .product => |v| .{ .product = try self.ids(.schema, v) },
            .sum => |v| .{ .sum = try self.ids(.schema, v) },
            .seq => |v| .{ .seq = try self.id(.schema, v) },
            .vector => |v| .{ .vector = .{ .element = try self.id(.schema, v.element), .maximum = v.maximum } },
            .array => |array| .{ .array = .{ .element = try self.id(.schema, array.element), .length = array.length } },
            .enumeration => |tags| .{ .enumeration = try self.copy(u32, tags) },
            .internal => |v| .{ .internal = try self.internal(v) },
            else => value,
        };
    }
    fn internal(self: *Visitor, value: p.Internal) Error!p.Internal {
        return switch (value) {
            .computation => |v| .{ .computation = .{ .parameters = try self.ids(.schema, v.parameters), .result = try self.id(.schema, v.result), .effects = try self.row(v.effects), .capture_bound = try self.ids(.schema, v.capture_bound), .use = v.use, .regions = try self.regions(v.regions) } },
            .capability => |v| .{ .capability = try self.id(.effect, v) },
            .cell => |v| .{ .cell = .{ .element = try self.id(.schema, v.element), .region = try self.id(.region, v.region) } },
            .region => |v| .{ .region = try self.id(.region, v) },
            .resumption => |v| .{ .resumption = .{ .effect = try self.id(.effect, v.effect), .input = try self.id(.schema, v.input), .answer = try self.id(.schema, v.answer), .effects = try self.row(v.effects), .capture_bound = try self.ids(.schema, v.capture_bound), .handled = try self.ids(.effect, v.handled), .escaping = try self.row(v.escaping), .mode = v.mode, .use = v.use, .owned_regions = try self.regions(v.owned_regions), .obligations = v.obligations } },
            .suspension_package => |v| .{ .suspension_package = try self.id(.schema, v) },
            .abstract_resource => |v| .{ .abstract_resource = try self.id(.resource, v) },
            .borrowed => |v| .{ .borrowed = .{ .value = try self.id(.schema, v.value), .region = try self.id(.region, v.region) } },
        };
    }
    fn literal(self: *Visitor, value: p.Literal) Error!p.Literal {
        return .{ .schema = try self.id(.schema, value.schema), .bytes = try self.copy(u8, value.bytes) };
    }
    fn effect(self: *Visitor, value: p.Effect) Error!p.Effect {
        return .{ .identity = try self.copy(u8, value.identity), .payload = try self.id(.schema, value.payload), .result = try self.id(.schema, value.result), .use_site_effects = try self.ids(.effect, value.use_site_effects), .bodies = try self.ids(.schema, value.bodies), .control_use = value.control_use, .external = value.external };
    }
    fn function(self: *Visitor, value: p.Function) Error!p.Function {
        return .{ .entry = try self.id(.block, value.entry), .parameters = try self.ids(.schema, value.parameters), .result = try self.id(.schema, value.result), .effects = try self.row(value.effects), .regions = try self.regions(value.regions) };
    }
    fn block(self: *Visitor, value: p.Block) Error!p.Block {
        return .{ .function = try self.id(.function, value.function), .parameters = try self.ids(.schema, value.parameters), .instructions = try self.items(p.Instruction, value.instructions, Visitor.instruction), .terminator = try self.terminator(value.terminator) };
    }
    fn instruction(self: *Visitor, value: p.Instruction) Error!p.Instruction {
        const result_type = try self.id(.schema, value.result_type);
        const immediate = switch (value.opcode) {
            .constant => try self.id(.constant, value.immediate),
            .computation => try self.id(.constructor, value.immediate),
            else => value.immediate,
        };
        return .{ .opcode = value.opcode, .result_type = result_type, .operands = try self.copy(p.Id, value.operands), .immediate = immediate, .failures = try self.items(p.InstructionFailure, value.failures, Visitor.failure) };
    }
    fn failure(self: *Visitor, value: p.InstructionFailure) Error!p.InstructionFailure {
        return .{ .kind = value.kind, .value = try self.id(.constant, value.value) };
    }
    fn edge(self: *Visitor, value: p.Edge) Error!p.Edge {
        return .{ .block = try self.id(.block, value.block), .arguments = try self.copy(p.Argument, value.arguments) };
    }
    fn perform(self: *Visitor, value: p.Perform) Error!p.Perform {
        return .{ .effect = try self.id(.effect, value.effect), .capability = value.capability, .payload = value.payload, .bodies = try self.copy(p.Id, value.bodies), .use_site_capabilities = try self.copy(p.Id, value.use_site_capabilities), .next = try self.edge(value.next) };
    }
    fn terminator(self: *Visitor, value: p.Terminator) Error!p.Terminator {
        return switch (value) {
            .return_value, .fail => value,
            .jump => |v| .{ .jump = try self.edge(v) },
            .branch => |v| .{ .branch = .{ .condition = v.condition, .when_true = try self.edge(v.when_true), .when_false = try self.edge(v.when_false) } },
            .switch_variant => |v| .{ .switch_variant = .{ .value = v.value, .cases = try self.items(p.Edge, v.cases, Visitor.edge) } },
            .unpack_product => |v| .{ .unpack_product = .{ .value = v.value, .block = try self.id(.block, v.block), .arguments = try self.copy(p.Id, v.arguments) } },
            .call => |v| .{ .call = .{ .function = try self.id(.function, v.function), .arguments = try self.copy(p.Id, v.arguments), .next = try self.edge(v.next) } },
            .perform => |v| .{ .perform = try self.perform(v) },
            .yield_value => |v| .{ .yield_value = try self.edge(v) },
            .apply => |v| .{ .apply = .{ .computation = v.computation, .arguments = try self.copy(p.Id, v.arguments), .next = try self.edge(v.next) } },
            .handle => |v| .{ .handle = .{ .handler = try self.id(.handler, v.handler), .body = v.body, .arguments = try self.copy(p.Id, v.arguments), .state = try self.copy(p.Id, v.state), .next = try self.edge(v.next) } },
            .resume_value => |v| .{ .resume_value = .{ .resumption = v.resumption, .argument = v.argument, .next = try self.edge(v.next) } },
            .resume_with => |v| .{ .resume_with = .{ .resumption = v.resumption, .argument = v.argument, .handler = try self.id(.handler, v.handler), .state = try self.copy(p.Id, v.state), .next = try self.edge(v.next) } },
            .resume_computation => |v| .{ .resume_computation = .{ .resumption = v.resumption, .computation = v.computation, .next = try self.edge(v.next) } },
            .forward => |v| .{ .forward = try self.perform(v) },
            .dispose => |v| .{ .dispose = .{ .owned = v.owned, .next = try self.edge(v.next) } },
            .protect => |v| .{ .protect = .{ .body = v.body, .cleanup = v.cleanup, .arguments = try self.copy(p.Id, v.arguments), .resource = v.resource, .loan_region = try self.optional(.region, v.loan_region), .next = try self.edge(v.next) } },
            .with_region => |v| .{ .with_region = .{ .region = try self.id(.region, v.region), .body = v.body, .arguments = try self.copy(p.Id, v.arguments), .next = try self.edge(v.next) } },
        };
    }
    fn clause(self: *Visitor, value: p.Clause) Error!p.Clause {
        return .{ .effect = try self.id(.effect, value.effect), .function = try self.id(.function, value.function), .resumption = try self.id(.schema, value.resumption), .direct = value.direct };
    }
    fn handler(self: *Visitor, value: p.Handler) Error!p.Handler {
        return .{ .mode = value.mode, .input = try self.id(.schema, value.input), .answer = try self.id(.schema, value.answer), .return_function = try self.id(.function, value.return_function), .clauses = try self.items(p.Clause, value.clauses, Visitor.clause), .forward_function = try self.optional(.function, value.forward_function), .state = try self.ids(.schema, value.state), .effects = try self.row(value.effects) };
    }
    fn capture(self: *Visitor, value: p.Capture) Error!p.Capture {
        return .{ .fields = try self.ids(.schema, value.fields), .owned_regions = try self.regions(value.owned_regions), .borrowed_regions = try self.regions(value.borrowed_regions), .use = value.use };
    }
    fn resource(self: *Visitor, value: p.Resource) Error!p.Resource {
        return .{ .representation = try self.id(.schema, value.representation), .introducers = try self.set(.function, value.introducers), .eliminators = try self.set(.function, value.eliminators) };
    }
    fn constructor(self: *Visitor, value: p.Constructor) Error!p.Constructor {
        return .{ .function = try self.id(.function, value.function), .capture = try self.id(.capture, value.capture), .schema = try self.id(.schema, value.schema) };
    }
};
