// Copyright (c) 2026 Boundary contributors. MIT license.
//! Derived borrow dependencies and outlives requirements over the finite code
//! graph. Scoped calls bind their generative inputs and implicit context here;
//! State admission interprets the same projections against actual graph owners.
//! No instruction or user computation runs during this fixed-point analysis.
const std = @import("std");
const p = @import("program.zig");
const a = @import("admission.zig");
const contracts = @import("contracts.zig");

pub const Step = union(enum) {
    field: p.Id,
    element,
    environment: struct { constructor: p.Id, field: p.Id },
    handler_state: struct { handler: p.Id, field: p.Id },
    use_site: struct { index: p.Id, schema: p.Id },
    cell_content,
    package_token,
    outer: ?Ambient,
    resumed: ?Ambient,
    body_result: p.Id,
};
const Path = struct { step: Step, tail: usize };
pub const Ambient = enum { evidence, region };
pub const Source = struct { parameter: p.Id = 0, path: usize = 0, ambient: ?Ambient = null };
const Trace = struct {
    block: p.Id,
    slot: p.Id = 0,
    path: usize = 0,
    ambient: ?Ambient = null,
    body_result: bool = false,
};
const Incoming = struct { block: p.Id, edge: ?p.Edge = null, variant: ?usize = null };
const Query = struct { start: p.Id, path: usize, target: ?Trace = null, writes: ?p.Id = null, sources: std.ArrayList(Source) = .empty };
pub const Bound = enum { region, clause, capture };
pub const Constraint = struct { value: Source, owner: Source, bound: Bound };
const Requirements = struct { start: p.Id, constraints: std.ArrayList(Constraint) = .empty };
const Binding = struct {
    block: p.Id,
    function: p.Id,
    arguments: []const p.Id,
    constructor: ?p.Id = null,
    computation_slot: ?p.Id = null,
    supplied: usize = 0,
    fresh: ?Ambient = null,
    handler: ?p.Id = null,
    state: []const p.Id = &.{},
    operation: ?p.Perform = null,
    resumed: ?p.Id = null,
};
const Mapped = struct {
    fresh: ?Ambient = null,
    items: [2]Trace = undefined,
    len: usize = 0,
    fn one(trace: Trace) Mapped {
        return .{ .items = .{ trace, undefined }, .len = 1 };
    }
    fn ambient(block: p.Id, component: ?Ambient) Mapped {
        if (component) |selected| return one(.{ .block = block, .ambient = selected });
        return .{ .items = .{ .{ .block = block, .ambient = .evidence }, .{ .block = block, .ambient = .region } }, .len = 2 };
    }
};

pub const Flow = struct {
    allocator: std.mem.Allocator,
    program: p.Program,
    exportable: []const bool,
    incoming: []std.ArrayList(Incoming),
    paths: std.ArrayList(Path) = .empty,
    queries: std.ArrayList(Query) = .empty,
    requirements: std.ArrayList(Requirements) = .empty,
    changed: bool = false,
    diagnostic: ?*a.Diagnostic = null,

    fn rejected(self: Flow, binding: Binding) a.Error {
        if (self.diagnostic) |diagnostic| diagnostic.* = .{ .phase = .block, .function = self.program.blocks[@intCast(binding.block)].function, .block = binding.block, .callee = binding.function, .handler = binding.handler };
        return error.InvalidOwnership;
    }

    pub fn init(allocator: std.mem.Allocator, program: p.Program, exportable: []const bool) a.Error!Flow {
        var self: Flow = .{ .allocator = allocator, .program = program, .exportable = exportable, .incoming = try allocator.alloc(std.ArrayList(Incoming), program.blocks.len) };
        @memset(self.incoming, .empty);
        for (program.blocks, 0..) |block, id| switch (block.terminator) {
            .jump, .yield_value => |edge| try self.link(id, edge, null),
            .branch => |branch| {
                try self.link(id, branch.when_true, null);
                try self.link(id, branch.when_false, null);
            },
            .switch_variant => |selected| for (selected.cases, 0..) |edge, variant| try self.link(id, edge, variant),
            .unpack_product => |unpack| try self.incoming[@intCast(unpack.block)].append(allocator, .{ .block = id }),
            .call => |v| try self.link(id, v.next, null),
            .perform, .forward => |v| try self.link(id, v.next, null),
            .apply => |v| try self.link(id, v.next, null),
            .handle => |v| try self.link(id, v.next, null),
            .resume_value => |v| try self.link(id, v.next, null),
            .resume_with => |v| try self.link(id, v.next, null),
            .resume_computation => |v| try self.link(id, v.next, null),
            .dispose => |v| try self.link(id, v.next, null),
            .protect => |v| try self.link(id, v.next, null),
            .with_region => |v| try self.link(id, v.next, null),
            .return_value, .fail => {},
        };
        return self;
    }

    fn link(self: *Flow, from: p.Id, edge: p.Edge, variant: ?usize) a.Error!void {
        try self.incoming[@intCast(edge.block)].append(self.allocator, .{ .block = from, .edge = edge, .variant = variant });
    }

    fn prepend(self: *Flow, step: Step, tail: usize) a.Error!usize {
        if (step == .outer and tail != 0 and std.meta.eql(self.paths.items[tail - 1].step, step)) return tail;
        for (self.paths.items, 0..) |path, index| if (path.tail == tail and std.meta.eql(path.step, step)) return index + 1;
        try self.paths.append(self.allocator, .{ .step = step, .tail = tail });
        return self.paths.items.len;
    }

    fn slotType(self: Flow, block: p.Id, slot: p.Id) p.Id {
        const code = self.program.blocks[@intCast(block)];
        return if (slot < code.parameters.len) code.parameters[@intCast(slot)] else code.instructions[@intCast(slot - code.parameters.len)].result_type;
    }

    fn selectedSchema(self: Flow, schema: p.Id, step: Step) ?p.Id {
        const shape = self.program.schemas[@intCast(schema)];
        return switch (step) {
            .field => |field| switch (shape) {
                .product, .sum => |fields| if (field < fields.len) fields[@intCast(field)] else null,
                else => null,
            },
            .element => switch (shape) {
                .seq => |element| element,
                .vector => |vector| vector.element,
                .array => |array| array.element,
                else => null,
            },
            .environment => |environment| blk: {
                const constructor = self.program.constructors[@intCast(environment.constructor)];
                if (constructor.schema != schema) break :blk null;
                const fields = self.program.scopes.captures[@intCast(constructor.capture)].fields;
                break :blk if (environment.field < fields.len) fields[@intCast(environment.field)] else null;
            },
            .handler_state => |state| blk: {
                if (shape != .internal or shape.internal != .capability) break :blk null;
                const handler = self.program.handlers[@intCast(state.handler)];
                break :blk if (state.field < handler.state.len) handler.state[@intCast(state.field)] else null;
            },
            .cell_content => if (shape == .internal and shape.internal == .cell) shape.internal.cell.element else null,
            .package_token => if (shape == .internal and shape.internal == .suspension_package) shape.internal.suspension_package else null,
            .use_site => |site| blk: {
                if (shape != .internal or shape.internal != .resumption) break :blk null;
                const effects = self.program.effects[@intCast(shape.internal.resumption.effect)].use_site_effects;
                const selected = self.program.schemas[@intCast(site.schema)];
                break :blk if (site.index < effects.len and selected == .internal and selected.internal == .capability and selected.internal.capability == effects[@intCast(site.index)]) site.schema else null;
            },
            .outer => if (shape == .internal and shape.internal == .capability) schema else null,
            .resumed => if (shape == .internal and (shape.internal == .capability or shape.internal == .resumption)) schema else null,
            .body_result => |result| if (shape == .internal) switch (shape.internal) {
                .capability => result,
                .resumption => |signature| if (signature.mode == .shallow and
                    signature.answer == result) result else null,
                else => null,
            } else null,
        };
    }

    // A repeated recursive schema means an arbitrary subtree at that position.
    // Widening to the whole subtree terminates recursive selector growth without
    // dropping any dependency. Products before the cycle remain field-sensitive.
    fn normalizePath(self: *Flow, schema: p.Id, path: usize) a.Error!usize {
        var steps: std.ArrayList(Step) = .empty;
        defer steps.deinit(self.allocator);
        var seen: std.ArrayList(p.Id) = .empty;
        defer seen.deinit(self.allocator);
        var current = schema;
        var cursor = path;
        while (cursor != 0) {
            const item = self.paths.items[cursor - 1];
            if (item.step != .outer) {
                if (std.mem.indexOfScalar(p.Id, seen.items, current) != null) break;
                try seen.append(self.allocator, current);
            }
            current = self.selectedSchema(current, item.step) orelse return path;
            try steps.append(self.allocator, item.step);
            cursor = item.tail;
        }
        if (cursor == 0) return path;
        var result: usize = 0;
        var index = steps.items.len;
        while (index != 0) {
            index -= 1;
            result = try self.prepend(steps.items[index], result);
        }
        return result;
    }

    fn query(self: *Flow, start: p.Id, path: usize) a.Error!usize {
        const function = self.program.functions[@intCast(self.program.blocks[@intCast(start)].function)];
        const selected = try self.normalizePath(function.result, path);
        for (self.queries.items, 0..) |item, index| if (item.start == start and item.path == selected and item.target == null and item.writes == null) return index;
        try self.queries.append(self.allocator, .{ .start = start, .path = selected });
        self.changed = true;
        return self.queries.items.len - 1;
    }

    pub fn returned(self: *Flow, start: p.Id) a.Error![]const Source {
        return self.returnedAt(start, 0);
    }

    pub fn returnedAt(self: *Flow, start: p.Id, path: usize) a.Error![]const Source {
        const index = try self.query(start, path);
        try self.settle();
        return self.queries.items[index].sources.items;
    }

    fn origin(self: *Flow, start: p.Id, target: Trace) a.Error!usize {
        for (self.queries.items, 0..) |item, index| if (item.start == start and item.target != null and std.meta.eql(item.target.?, target)) return index;
        try self.queries.append(self.allocator, .{ .start = start, .path = 0, .target = target });
        self.changed = true;
        return self.queries.items.len - 1;
    }

    fn writeQuery(self: *Flow, start: p.Id, schema: p.Id, path: usize) a.Error!usize {
        for (self.queries.items, 0..) |item, index| if (item.start == start and item.writes == schema and item.path == path) return index;
        try self.queries.append(self.allocator, .{ .start = start, .path = path, .writes = schema });
        self.changed = true;
        return self.queries.items.len - 1;
    }

    fn settle(self: *Flow) a.Error!void {
        // Every new query or fact marks the analysis dirty. A failed pass must
        // remain dirty so a retry cannot publish a partially settled result.
        errdefer self.changed = true;
        while (self.changed) {
            self.changed = false;
            var current: usize = 0;
            while (current < self.queries.items.len) : (current += 1) try self.solve(current);
            current = 0;
            while (current < self.requirements.items.len) : (current += 1) try self.solveRequirements(current);
        }
    }

    fn addSource(self: *Flow, query_index: usize, source: Source) a.Error!void {
        for (self.queries.items[query_index].sources.items) |existing| if (std.meta.eql(existing, source)) return;
        try self.queries.items[query_index].sources.append(self.allocator, source);
        self.changed = true;
    }

    fn requirementsQuery(self: *Flow, start: p.Id) a.Error!usize {
        for (self.requirements.items, 0..) |item, index| if (item.start == start) return index;
        try self.requirements.append(self.allocator, .{ .start = start });
        self.changed = true;
        return self.requirements.items.len - 1;
    }

    pub fn required(self: *Flow, start: p.Id) a.Error![]const Constraint {
        const index = try self.requirementsQuery(start);
        try self.settle();
        return self.requirements.items[index].constraints.items;
    }

    fn addConstraint(self: *Flow, index: usize, value: Source, owner: Source, bound: Bound) a.Error!void {
        const constraint: Constraint = .{ .value = value, .owner = owner, .bound = bound };
        for (self.requirements.items[index].constraints.items) |item| if (std.meta.eql(item, constraint)) return;
        try self.requirements.items[index].constraints.append(self.allocator, constraint);
        self.changed = true;
    }

    fn relation(self: *Flow, index: usize, block: p.Id, value: p.Id, owner: p.Id, bound: Bound) a.Error!void {
        if (self.exportable[@intCast(self.slotType(block, value))]) return;
        const start = self.requirements.items[index].start;
        const values = try self.origin(start, .{ .block = block, .slot = value, .path = 0 });
        const owners = try self.origin(start, .{ .block = block, .slot = owner, .path = 0 });
        for (self.queries.items[values].sources.items) |source| for (self.queries.items[owners].sources.items) |destination| try self.addConstraint(index, source, destination, bound);
    }

    fn mapInput(self: *Flow, binding: Binding, source: Source) a.Error!Mapped {
        if (source.ambient) |ambient| {
            if (binding.resumed) |token| return Mapped.one(.{ .block = binding.block, .slot = token, .path = try self.prepend(.{ .resumed = ambient }, 0) });
            if (binding.operation) |op| return Mapped.one(.{ .block = binding.block, .slot = op.capability.?, .path = try self.prepend(.{ .outer = ambient }, 0) });
            if (binding.fresh == ambient) return .{ .fresh = ambient };
            return Mapped.one(.{ .block = binding.block, .ambient = ambient });
        }
        if (binding.operation) |op| {
            const handler = self.program.handlers[@intCast(binding.handler.?)];
            if (source.parameter < handler.state.len) return Mapped.one(.{ .block = binding.block, .slot = op.capability.?, .path = try self.prepend(.{ .handler_state = .{ .handler = binding.handler.?, .field = source.parameter } }, source.path) });
            const argument = source.parameter - handler.state.len;
            if (argument == 0) return Mapped.one(.{ .block = binding.block, .slot = op.payload, .path = source.path });
            if (argument <= op.bodies.len) return Mapped.one(.{ .block = binding.block, .slot = op.bodies[@intCast(argument - 1)], .path = source.path });
            if (source.path != 0 and self.paths.items[source.path - 1].step == .body_result)
                return Mapped.one(.{
                    .block = binding.block,
                    .slot = op.capability.?,
                    .path = source.path,
                });
            if (source.path != 0 and self.paths.items[source.path - 1].step == .use_site) {
                const path = self.paths.items[source.path - 1];
                return Mapped.one(.{ .block = binding.block, .slot = op.use_site_capabilities[@intCast(path.step.use_site.index)], .path = path.tail });
            }
            if (source.path != 0 and self.paths.items[source.path - 1].step == .resumed) return Mapped.one(.{ .block = binding.block, .slot = op.capability.?, .path = source.path });
            return Mapped.one(.{ .block = binding.block, .slot = op.capability.?, .path = try self.prepend(.{ .outer = null }, 0) });
        }
        const captures = if (binding.constructor) |id| self.program.scopes.captures[@intCast(self.program.constructors[@intCast(id)].capture)].fields.len else 0;
        if (source.parameter < captures) return Mapped.one(.{ .block = binding.block, .slot = binding.computation_slot.?, .path = try self.prepend(.{ .environment = .{ .constructor = binding.constructor.?, .field = source.parameter } }, source.path) });
        if (binding.resumed) |token| return Mapped.one(.{ .block = binding.block, .slot = token, .path = try self.prepend(.{ .use_site = .{ .index = source.parameter - captures, .schema = self.program.functions[@intCast(binding.function)].parameters[@intCast(source.parameter)] } }, source.path) });
        if (source.parameter < captures + binding.supplied) {
            if (source.path != 0) {
                const path = self.paths.items[source.path - 1];
                if (path.step == .outer) return Mapped.ambient(binding.block, path.step.outer);
                if (path.step == .resumed and binding.fresh == .evidence) {
                    if (path.step.resumed == .region) return Mapped.ambient(binding.block, .region);
                    if (path.step.resumed == null) {
                        var context = Mapped.ambient(binding.block, .region);
                        context.fresh = .evidence;
                        return context;
                    }
                }
                if (path.step == .handler_state) {
                    if (binding.handler != path.step.handler_state.handler) return .{};
                    return Mapped.one(.{ .block = binding.block, .slot = binding.state[@intCast(path.step.handler_state.field)], .path = path.tail });
                }
                if (path.step == .body_result and binding.fresh == .evidence) {
                    const handler = self.program.handlers[@intCast(binding.handler.?)];
                    if (handler.input != path.step.body_result) return .{};
                    return Mapped.one(.{
                        .block = binding.block,
                        .path = path.tail,
                        .body_result = true,
                    });
                }
            }
            return .{ .fresh = binding.fresh orelse return self.rejected(binding) };
        }
        return Mapped.one(.{ .block = binding.block, .slot = binding.arguments[@intCast(source.parameter - captures - binding.supplied)], .path = source.path });
    }

    fn transferRequirements(self: *Flow, index: usize, binding: Binding) a.Error!void {
        const called = try self.requirementsQuery(self.program.functions[@intCast(binding.function)].entry);
        const pairs = try self.allocator.dupe(Constraint, self.requirements.items[called].constraints.items);
        defer self.allocator.free(pairs);
        const start = self.requirements.items[index].start;
        for (pairs) |pair| {
            const values = try self.mapInput(binding, pair.value);
            const owners = try self.mapOwner(binding, pair.owner, pair.bound);
            if (values.fresh) |component| {
                // Capabilities need evidence ancestry; region references need
                // region ancestry. A constraint on the other component cannot
                // make a fresh value escape its owner.
                for (owners.items[0..owners.len]) |owner| {
                    if (self.selectedComponent(owner)) |selected| if (selected != component) continue;
                    return self.rejected(binding);
                }
            }
            for (values.items[0..values.len]) |value_trace| for (owners.items[0..owners.len]) |owner_trace| {
                const v = try self.origin(start, value_trace);
                const o = try self.origin(start, owner_trace);
                for (self.queries.items[v].sources.items) |value| for (self.queries.items[o].sources.items) |owner| try self.addConstraint(index, value, owner, pair.bound);
            };
        }
    }

    fn mapOwner(self: *Flow, binding: Binding, source: Source, bound: Bound) a.Error!Mapped {
        const mapped = try self.mapInput(binding, source);
        // A clause executes outside the capability's delimiter. Explicit
        // ambient/resumed projections already denote a context; a newly bound
        // capability value still needs this owner projection before comparison.
        if (bound == .clause and mapped.fresh == .evidence and source.ambient == null and source.path == 0)
            return Mapped.ambient(binding.block, null);
        return mapped;
    }

    fn selectedComponent(self: Flow, trace: Trace) ?Ambient {
        if (trace.ambient) |selected| return selected;
        var cursor = trace.path;
        while (cursor != 0) {
            const path = self.paths.items[cursor - 1];
            switch (path.step) {
                .outer, .resumed => |selected| return selected,
                else => cursor = path.tail,
            }
        }
        return null;
    }

    fn bodyBinding(self: Flow, block: p.Id, computation_slot: p.Id, arguments: []const p.Id, supplied: usize, id: p.Id) Binding {
        const term = self.program.blocks[@intCast(block)].terminator;
        return .{ .block = block, .function = self.program.constructors[@intCast(id)].function, .arguments = arguments, .constructor = id, .computation_slot = computation_slot, .supplied = supplied, .resumed = if (term == .resume_computation) term.resume_computation.resumption else null, .fresh = switch (term) {
            .handle => .evidence,
            .with_region => .region,
            .protect => |v| if (v.body == computation_slot and v.loan_region != null) .region else null,
            else => null,
        }, .handler = if (term == .handle) term.handle.handler else null, .state = if (term == .handle) term.handle.state else &.{} };
    }

    fn bodyRequirements(self: *Flow, index: usize, block: p.Id, computation_slot: p.Id, arguments: []const p.Id, supplied: usize) a.Error!void {
        const schema = self.slotType(block, computation_slot);
        for (self.program.constructors, 0..) |constructor, id| if (constructor.schema == schema) try self.transferRequirements(index, self.bodyBinding(block, computation_slot, arguments, supplied, id));
    }

    fn returnInput(
        self: *Flow,
        pending: *std.ArrayList(Trace),
        block: p.Id,
        source: Source,
    ) a.Error!void {
        const term = self.program.blocks[@intCast(block)].terminator;
        const state = switch (term) {
            inline .handle, .resume_with => |v| v.state,
            else => return error.InvalidProgram,
        };
        if (source.ambient) |ambient| {
            return self.pushTrace(pending, .{ .block = block, .ambient = ambient });
        }
        if (source.parameter < state.len) {
            return self.push(pending, block, state[@intCast(source.parameter)], source.path);
        }
        switch (term) {
            .handle => |v| try self.body(
                pending,
                block,
                v.body,
                v.arguments,
                self.program.handlers[@intCast(v.handler)].clauses.len,
                source.path,
            ),
            .resume_with => |v| {
                // Operation inputs are exportable. Project the captured body's
                // result, retaining its selectors rather than its whole context.
                const schema = self.program.handlers[@intCast(v.handler)].input;
                const path = try self.prepend(.{ .body_result = schema }, source.path);
                try self.push(pending, block, v.resumption, path);
            },
            else => return error.InvalidProgram,
        }
    }

    fn returnInputs(self: *Flow, start: p.Id, block: p.Id, source: Source) a.Error!std.ArrayList(Source) {
        var pending: std.ArrayList(Trace) = .empty;
        defer pending.deinit(self.allocator);
        try self.returnInput(&pending, block, source);
        var result: std.ArrayList(Source) = .empty;
        for (pending.items) |trace| {
            const query_id = try self.origin(start, trace);
            try result.appendSlice(self.allocator, self.queries.items[query_id].sources.items);
        }
        return result;
    }

    fn returnRequirements(self: *Flow, index: usize, block: p.Id) a.Error!void {
        const handler_id = switch (self.program.blocks[@intCast(block)].terminator) {
            inline .handle, .resume_with => |v| v.handler,
            else => return error.InvalidProgram,
        };
        const handler = self.program.handlers[@intCast(handler_id)];
        const query_id = try self.requirementsQuery(self.program.functions[@intCast(handler.return_function)].entry);
        const constraints = try self.allocator.dupe(Constraint, self.requirements.items[query_id].constraints.items);
        defer self.allocator.free(constraints);
        for (constraints) |constraint| {
            var values = try self.returnInputs(self.requirements.items[index].start, block, constraint.value);
            defer values.deinit(self.allocator);
            var owners = try self.returnInputs(self.requirements.items[index].start, block, constraint.owner);
            defer owners.deinit(self.allocator);
            for (values.items) |value| for (owners.items) |owner| try self.addConstraint(index, value, owner, constraint.bound);
        }
    }

    fn solveRequirements(self: *Flow, index: usize) a.Error!void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const live = try self.reachable(self.requirements.items[index].start, arena.allocator());
        for (self.program.blocks, 0..) |block, id| if (live[id]) {
            for (block.instructions) |op| switch (op.opcode) {
                .cell_new, .cell_set => try self.relation(index, id, op.operands[1], op.operands[0], .region),
                else => {},
            };
            switch (block.terminator) {
                .call => |v| try self.transferRequirements(index, .{ .block = id, .function = v.function, .arguments = v.arguments }),
                .apply => |v| try self.bodyRequirements(index, id, v.computation, v.arguments, 0),
                .with_region => |v| try self.bodyRequirements(index, id, v.body, v.arguments, 1),
                .protect => |v| {
                    try self.bodyRequirements(index, id, v.body, v.arguments, @intFromBool(v.resource != null));
                    // Exit information and the owned resource are exportable;
                    // cleanup's retained environment still has ordinary bounds.
                    try self.bodyRequirements(index, id, v.cleanup, &.{}, if (v.resource == null) 1 else 2);
                },
                .handle => |v| {
                    try self.bodyRequirements(index, id, v.body, v.arguments, self.program.handlers[@intCast(v.handler)].clauses.len);
                    try self.returnRequirements(index, id);
                },
                .perform, .forward => |v| if (v.capability) |capability| {
                    var captures = false;
                    for (self.program.handlers) |handler| for (handler.clauses) |clause| if (clause.effect == v.effect and !clause.direct) {
                        captures = true;
                    };
                    if (captures) {
                        try self.relation(index, id, v.payload, capability, .clause);
                        for (v.bodies) |slot| try self.relation(index, id, slot, capability, .clause);
                    }
                    for (self.program.handlers, 0..) |handler, handler_id| for (handler.clauses) |clause| if (clause.effect == v.effect) try self.transferRequirements(index, .{ .block = id, .function = clause.function, .arguments = &.{}, .handler = handler_id, .operation = v });
                },
                .resume_value => |v| try self.relation(index, id, v.argument, v.resumption, .capture),
                .resume_with => |v| {
                    try self.relation(index, id, v.argument, v.resumption, .capture);
                    for (v.state) |slot| try self.relation(index, id, slot, v.resumption, .capture);
                    try self.returnRequirements(index, id);
                },
                .resume_computation => |v| {
                    try self.relation(index, id, v.computation, v.resumption, .capture);
                    try self.bodyRequirements(index, id, v.computation, &.{}, 0);
                },
                else => {},
            }
        };
    }

    fn push(self: *Flow, pending: *std.ArrayList(Trace), block: p.Id, slot: p.Id, path: usize) a.Error!void {
        const schema = self.slotType(block, slot);
        const selected = try self.normalizePath(schema, path);
        var current = schema;
        var cursor = selected;
        while (cursor != 0) {
            const item = self.paths.items[cursor - 1];
            current = self.selectedSchema(current, item.step) orelse return;
            cursor = item.tail;
        }
        if (self.exportable[@intCast(current)]) return;
        try pending.append(self.allocator, .{ .block = block, .slot = slot, .path = selected });
    }

    fn pushTrace(self: *Flow, pending: *std.ArrayList(Trace), trace: Trace) a.Error!void {
        if (trace.ambient != null or trace.body_result)
            return pending.append(self.allocator, trace);
        try self.push(pending, trace.block, trace.slot, trace.path);
    }

    fn transferSources(self: *Flow, pending: *std.ArrayList(Trace), binding: Binding, index: usize) a.Error!void {
        const sources = try self.allocator.dupe(Source, self.queries.items[index].sources.items);
        defer self.allocator.free(sources);
        for (sources) |source| {
            const mapped = try self.mapInput(binding, source);
            if (mapped.fresh != null) return self.rejected(binding);
            for (mapped.items[0..mapped.len]) |trace| try self.pushTrace(pending, trace);
        }
    }

    fn reachable(self: Flow, start: p.Id, allocator: std.mem.Allocator) a.Error![]bool {
        const visited = try allocator.alloc(bool, self.program.blocks.len);
        @memset(visited, false);
        visited[@intCast(start)] = true;
        var changed = true;
        while (changed) {
            changed = false;
            for (self.incoming, 0..) |incoming, target| {
                if (visited[target]) continue;
                for (incoming.items) |edge| if (visited[@intCast(edge.block)]) {
                    visited[target] = true;
                    changed = true;
                    break;
                };
            }
        }
        return visited;
    }

    fn solve(self: *Flow, query_index: usize) a.Error!void {
        const query_start = self.queries.items[query_index].start;
        const query_path = self.queries.items[query_index].path;
        const query_target = self.queries.items[query_index].target;
        const query_writes = self.queries.items[query_index].writes;
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const allocator = arena.allocator();
        const live = try self.reachable(query_start, allocator);
        var pending: std.ArrayList(Trace) = .empty;
        defer pending.deinit(self.allocator);
        var visited: std.AutoHashMapUnmanaged(Trace, void) = .empty;
        if (query_target) |target| {
            if (live[@intCast(target.block)]) try self.pushTrace(&pending, target);
        } else if (query_writes) |schema| {
            for (self.program.blocks, 0..) |block, id| if (live[id]) {
                for (block.instructions) |op| if (op.opcode == .cell_set and self.slotType(id, op.operands[0]) == schema) try self.push(&pending, id, op.operands[1], query_path);
                try self.calledWrites(&pending, id, schema, query_path);
            };
        } else for (self.program.blocks, 0..) |block, id| if (live[id] and block.terminator == .return_value) try self.push(&pending, id, block.terminator.return_value, query_path);
        while (pending.pop()) |trace| {
            if ((try visited.getOrPut(allocator, trace)).found_existing) continue;
            if (trace.body_result) {
                const term = self.program.blocks[@intCast(trace.block)].terminator;
                if (term != .handle) return error.InvalidProgram;
                const v = term.handle;
                try self.body(
                    &pending,
                    trace.block,
                    v.body,
                    v.arguments,
                    self.program.handlers[@intCast(v.handler)].clauses.len,
                    trace.path,
                );
                continue;
            }
            if (trace.ambient) |ambient| {
                try self.addSource(query_index, .{ .ambient = ambient });
                continue;
            }
            const code = self.program.blocks[@intCast(trace.block)];
            if (trace.slot >= code.parameters.len) {
                const op = code.instructions[@intCast(trace.slot - code.parameters.len)];
                try self.instruction(&pending, trace, op);
                if (op.opcode == .cell_get) {
                    const writes = try self.writeQuery(query_start, self.slotType(trace.block, op.operands[0]), trace.path);
                    const sources = try allocator.dupe(Source, self.queries.items[writes].sources.items);
                    for (sources) |source| try self.addSource(query_index, source);
                }
                continue;
            }
            if (trace.block == query_start) try self.addSource(query_index, .{ .parameter = trace.slot, .path = trace.path });
            for (self.incoming[@intCast(trace.block)].items) |incoming| {
                if (!live[@intCast(incoming.block)]) continue;
                if (incoming.edge) |edge| switch (edge.arguments[@intCast(trace.slot)]) {
                    .slot => |slot| try self.push(&pending, incoming.block, slot, trace.path),
                    .returned => if (incoming.variant) |variant| {
                        const selected = self.program.blocks[@intCast(incoming.block)].terminator.switch_variant;
                        try self.push(&pending, incoming.block, selected.value, try self.prepend(.{ .field = variant }, trace.path));
                    } else try self.output(&pending, incoming.block, trace.path),
                } else {
                    const unpack = self.program.blocks[@intCast(incoming.block)].terminator.unpack_product;
                    const fields = self.program.schemas[@intCast(self.slotType(incoming.block, unpack.value))].product.len;
                    if (trace.slot < fields) {
                        try self.push(&pending, incoming.block, unpack.value, try self.prepend(.{ .field = trace.slot }, trace.path));
                    } else try self.push(&pending, incoming.block, unpack.arguments[@intCast(trace.slot - fields)], trace.path);
                }
            }
        }
    }

    fn childPath(self: Flow, path: usize, step: Step) ?usize {
        if (path == 0) return 0;
        const selected = self.paths.items[path - 1];
        return if (std.meta.eql(selected.step, step)) selected.tail else null;
    }

    fn sequenceInstruction(
        self: *Flow,
        pending: *std.ArrayList(Trace),
        trace: Trace,
        op: p.Instruction,
    ) a.Error!void {
        const sequence = op.operands[0];
        switch (op.opcode) {
            .sequence_concat, .sequence_take => {
                try self.push(pending, trace.block, sequence, trace.path);
                if (op.opcode == .sequence_concat)
                    try self.push(pending, trace.block, op.operands[1], trace.path);
            },
            .sequence_append, .sequence_set => {
                const element = self.childPath(trace.path, .element) orelse return;
                try self.push(pending, trace.block, sequence, trace.path);
                const added = op.operands[if (op.opcode == .sequence_append) 1 else 2];
                try self.push(pending, trace.block, added, element);
            },
            .sequence_pop => {
                const present = self.childPath(trace.path, .{ .field = 1 }) orelse return;
                if (self.childPath(present, .{ .field = 0 })) |element|
                    try self.push(pending, trace.block, sequence, try self.prepend(.element, element));
                if (self.childPath(present, .{ .field = 1 })) |rest| {
                    if (self.childPath(rest, .element)) |element|
                        try self.push(pending, trace.block, sequence, try self.prepend(.element, element));
                }
            },
            .sequence_pop_last => {
                if (self.childPath(trace.path, .{ .field = 0 })) |rest|
                    try self.push(pending, trace.block, sequence, rest);
                if (self.childPath(trace.path, .{ .field = 1 })) |optional| {
                    if (self.childPath(optional, .{ .field = 1 })) |element|
                        try self.push(pending, trace.block, sequence, try self.prepend(.element, element));
                }
            },
            else => return error.InvalidProgram,
        }
    }

    fn instruction(self: *Flow, pending: *std.ArrayList(Trace), trace: Trace, op: p.Instruction) a.Error!void {
        const path = if (trace.path == 0) null else self.paths.items[trace.path - 1];
        switch (op.opcode) {
            .move => try self.push(pending, trace.block, op.operands[0], trace.path),
            .select => for (op.operands[1..]) |slot|
                try self.push(pending, trace.block, slot, trace.path),
            .product => {
                if (path) |selected| {
                    if (selected.step == .field and selected.step.field < op.operands.len) try self.push(pending, trace.block, op.operands[@intCast(selected.step.field)], selected.tail);
                } else for (op.operands) |slot| try self.push(pending, trace.block, slot, 0);
            },
            .field, .variant_payload => try self.push(pending, trace.block, op.operands[0], try self.prepend(.{ .field = op.immediate }, trace.path)),
            .variant => {
                if (path) |selected| {
                    if (selected.step == .field and selected.step.field == op.immediate) try self.push(pending, trace.block, op.operands[0], selected.tail);
                } else for (op.operands) |slot| try self.push(pending, trace.block, slot, 0);
            },
            .computation => {
                if (path) |selected| {
                    if (selected.step == .environment and selected.step.environment.constructor == op.immediate) try self.push(pending, trace.block, op.operands[@intCast(selected.step.environment.field)], selected.tail);
                } else for (op.operands) |slot| try self.push(pending, trace.block, slot, 0);
            },
            .cell_new => if (path) |selected| {
                if (selected.step == .cell_content) try self.push(pending, trace.block, op.operands[1], selected.tail);
            } else try self.push(pending, trace.block, op.operands[0], 0),
            .cell_get => try self.push(pending, trace.block, op.operands[0], try self.prepend(.cell_content, trace.path)),
            .sequence => for (op.operands) |slot| try self.push(pending, trace.block, slot, if (path) |selected| selected.tail else 0),
            .sequence_get => if (path) |selected| {
                // Lookup returns Optional<Element>; only Some carries a borrow.
                if (selected.step == .field and selected.step.field == 1) try self.push(pending, trace.block, op.operands[0], try self.prepend(.element, selected.tail));
            } else try self.push(pending, trace.block, op.operands[0], try self.prepend(.element, 0)),
            .clone_resumption => try self.push(pending, trace.block, op.operands[0], trace.path),
            .unpack => try self.push(pending, trace.block, op.operands[0], try self.prepend(.package_token, trace.path)),
            .package => if (path) |selected| {
                if (selected.step == .package_token) try self.push(pending, trace.block, op.operands[0], selected.tail);
            } else try self.push(pending, trace.block, op.operands[0], 0),
            .sequence_append,
            .sequence_concat,
            .sequence_pop,
            .sequence_set,
            .sequence_take,
            .sequence_pop_last,
            => try self.sequenceInstruction(pending, trace, op),
            .constant, .integer_add, .integer_sub, .integer_mul, .integer_div, .integer_rem, .integer_bit_not, .integer_bit_and, .integer_bit_or, .integer_bit_xor, .integer_convert, .enum_tag, .equal, .less, .boolean_not, .variant_tag, .sequence_length, .cell_set, .resource_pack, .resource_unpack, .blob_length, .blob_concat, .blob_slice, .blob_compare, .blob_byte, .text_scalar, .text_integer, .blob_from_byte => {}, // Scalar results and owned resources with exportable representations have no borrows.
        }
    }

    fn call(self: *Flow, pending: *std.ArrayList(Trace), block: p.Id, function: p.Id, arguments: []const p.Id, path: usize) a.Error!void {
        const index = try self.query(self.program.functions[@intCast(function)].entry, path);
        try self.transferSources(pending, .{ .block = block, .function = function, .arguments = arguments }, index);
    }

    fn body(self: *Flow, pending: *std.ArrayList(Trace), block: p.Id, computation_slot: p.Id, arguments: []const p.Id, supplied: usize, path: usize) a.Error!void {
        const schema = self.slotType(block, computation_slot);
        for (self.program.constructors, 0..) |constructor, id| {
            if (constructor.schema != schema) continue;
            const index = try self.query(self.program.functions[@intCast(constructor.function)].entry, path);
            try self.transferSources(pending, self.bodyBinding(block, computation_slot, arguments, supplied, id), index);
        }
    }

    fn callWrites(self: *Flow, pending: *std.ArrayList(Trace), block: p.Id, function: p.Id, arguments: []const p.Id, schema: p.Id, path: usize) a.Error!void {
        const index = try self.writeQuery(self.program.functions[@intCast(function)].entry, schema, path);
        try self.transferSources(pending, .{ .block = block, .function = function, .arguments = arguments }, index);
    }

    fn bodyWrites(self: *Flow, pending: *std.ArrayList(Trace), block: p.Id, computation_slot: p.Id, arguments: []const p.Id, supplied: usize, schema: p.Id, path: usize) a.Error!void {
        const computation_schema = self.slotType(block, computation_slot);
        for (self.program.constructors, 0..) |constructor, id| {
            if (constructor.schema != computation_schema) continue;
            const index = try self.writeQuery(self.program.functions[@intCast(constructor.function)].entry, schema, path);
            try self.transferSources(pending, self.bodyBinding(block, computation_slot, arguments, supplied, id), index);
        }
    }

    fn calledWrites(self: *Flow, pending: *std.ArrayList(Trace), block: p.Id, schema: p.Id, path: usize) a.Error!void {
        switch (self.program.blocks[@intCast(block)].terminator) {
            .call => |v| try self.callWrites(pending, block, v.function, v.arguments, schema, path),
            .apply => |v| try self.bodyWrites(pending, block, v.computation, v.arguments, 0, schema, path),
            .with_region => |v| try self.bodyWrites(pending, block, v.body, v.arguments, 1, schema, path),
            .protect => |v| {
                try self.bodyWrites(pending, block, v.body, v.arguments, @intFromBool(v.resource != null), schema, path);
                try self.bodyWrites(pending, block, v.cleanup, &.{}, if (v.resource == null) 1 else 2, schema, path);
            },
            .handle => |v| {
                const handler = self.program.handlers[@intCast(v.handler)];
                try self.bodyWrites(pending, block, v.body, v.arguments, handler.clauses.len, schema, path);
                const index = try self.writeQuery(self.program.functions[@intCast(handler.return_function)].entry, schema, path);
                const sources = try self.allocator.dupe(Source, self.queries.items[index].sources.items);
                defer self.allocator.free(sources);
                for (sources) |source| try self.returnInput(pending, block, source);
            },
            .perform, .forward => |v| if (v.capability != null) {
                for (self.program.handlers, 0..) |handler, handler_id| for (handler.clauses) |clause| if (clause.effect == v.effect) {
                    const index = try self.writeQuery(self.program.functions[@intCast(clause.function)].entry, schema, path);
                    try self.transferSources(pending, .{ .block = block, .function = clause.function, .arguments = &.{}, .handler = handler_id, .operation = v }, index);
                };
            },
            .resume_value => |v| {
                try self.push(pending, block, v.resumption, 0);
                try self.push(pending, block, v.argument, 0);
            },
            .resume_with => |v| {
                try self.push(pending, block, v.resumption, 0);
                try self.push(pending, block, v.argument, 0);
                for (v.state) |slot| try self.push(pending, block, slot, 0);
            },
            .resume_computation => |v| {
                try self.push(pending, block, v.resumption, 0);
                try self.push(pending, block, v.computation, 0);
            },
            else => {},
        }
    }

    pub fn isOuter(self: Flow, path: usize) bool {
        var cursor = path;
        while (cursor != 0) {
            const item = self.paths.items[cursor - 1];
            if (item.step == .outer) return true;
            cursor = item.tail;
        }
        return false;
    }

    fn output(self: *Flow, pending: *std.ArrayList(Trace), block: p.Id, path: usize) a.Error!void {
        switch (self.program.blocks[@intCast(block)].terminator) {
            .call => |v| try self.call(pending, block, v.function, v.arguments, path),
            .apply => |v| try self.body(pending, block, v.computation, v.arguments, 0, path),
            .with_region => |v| try self.body(pending, block, v.body, v.arguments, 1, path),
            .protect => |v| try self.body(pending, block, v.body, v.arguments, @intFromBool(v.resource != null), path),
            .handle => |v| {
                const handler = self.program.handlers[@intCast(v.handler)];
                const returns = try self.query(self.program.functions[@intCast(handler.return_function)].entry, path);
                const sources = try self.allocator.dupe(Source, self.queries.items[returns].sources.items);
                defer self.allocator.free(sources);
                for (sources) |source| try self.returnInput(pending, block, source);
                // A clause can return state or a borrow arriving from the body's
                // older inputs. Fresh body capabilities are checked separately.
                for (handler.clauses) |clause| {
                    if (clause.direct) continue;
                    const index = try self.query(self.program.functions[@intCast(clause.function)].entry, path);
                    for (self.queries.items[index].sources.items) |source| {
                        if (source.ambient) |ambient| {
                            try self.pushTrace(pending, .{ .block = block, .ambient = ambient });
                        } else if (source.parameter < v.state.len) {
                            try self.push(pending, block, v.state[@intCast(source.parameter)], source.path);
                        } else {
                            try self.push(pending, block, v.body, 0);
                            for (v.arguments) |slot| try self.push(pending, block, slot, 0);
                            if (source.parameter == self.program.functions[@intCast(clause.function)].parameters.len - 1) {
                                try self.pushTrace(pending, .{ .block = block, .ambient = .evidence });
                                try self.pushTrace(pending, .{ .block = block, .ambient = .region });
                            }
                        }
                    }
                }
            },
            .resume_value => |v| {
                try self.push(pending, block, v.resumption, 0);
                try self.push(pending, block, v.argument, 0);
            },
            .resume_with => |v| {
                try self.push(pending, block, v.resumption, 0);
                try self.push(pending, block, v.argument, 0);
                for (v.state) |slot| try self.push(pending, block, slot, 0);
            },
            .resume_computation => |v| {
                try self.push(pending, block, v.resumption, 0);
                try self.push(pending, block, v.computation, 0);
            },
            .perform, .forward => |v| {
                // Keep all incoming borrows for internal result schemas. External
                // results are exportable and are removed by push's schema check.
                if (v.capability) |slot| try self.push(pending, block, slot, try self.prepend(.{ .outer = null }, 0));
                try self.push(pending, block, v.payload, 0);
                for (v.bodies) |slot| try self.push(pending, block, slot, 0);
                for (v.use_site_capabilities) |slot| try self.push(pending, block, slot, 0);
            },
            else => {},
        }
    }
};

pub fn validate(allocator: std.mem.Allocator, program: p.Program, exportable: []const bool, diagnostic: ?*a.Diagnostic) a.Error!void {
    var flow = try Flow.init(allocator, program, exportable);
    flow.diagnostic = diagnostic;
    for (program.functions) |function| _ = try flow.requirementsQuery(function.entry);
    try flow.settle();
    for (program.blocks, 0..) |block, block_id| {
        const body_slot, const arguments, const supplied = switch (block.terminator) {
            .handle => |v| .{ v.body, v.arguments, program.handlers[@intCast(v.handler)].clauses.len },
            .with_region => |v| .{ v.body, v.arguments, @as(usize, 1) },
            .protect => |v| .{ v.body, v.arguments, @as(usize, @intFromBool(v.resource != null)) },
            else => continue,
        };
        const body_schema = flow.slotType(block_id, body_slot);
        for (program.constructors, 0..) |constructor, id| {
            if (constructor.schema != body_schema) continue;
            const start = program.functions[@intCast(constructor.function)].entry;
            const returned = try flow.returned(start);
            const binding = flow.bodyBinding(block_id, body_slot, arguments, supplied, id);
            for (returned) |source| {
                if ((try flow.mapInput(binding, source)).fresh != null) {
                    return flow.rejected(binding);
                }
            }
        }
    }
}
