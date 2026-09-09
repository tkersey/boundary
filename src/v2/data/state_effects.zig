// Copyright (c) 2026 Boundary contributors. MIT license.
//! Effect interfaces of saved control frames. Capability origins are derived
//! from the logical graph; no instruction or application computation executes.
const std = @import("std");
const p = @import("program.zig");
const g = @import("graph.zig");
const a = @import("admission.zig");
const contracts = @import("contracts.zig");
const effect_scope = @import("effect_scope.zig");
pub const Error = a.Error || error{ InvalidState, InvalidScope };

pub const Check = struct {
    allocator: std.mem.Allocator,
    program: p.Program,
    state: g.State,
    captures: []const ?p.Id,
    children: []const ?g.NodeRef,
    enter: []const usize,
    leave: []const usize,
    facts: effect_scope.Facts,
    origins: std.AutoHashMapUnmanaged(p.Id, Origins) = .empty,

    pub fn init(
        allocator: std.mem.Allocator,
        program: p.Program,
        state: g.State,
        captures: []const ?p.Id,
        children: []const ?g.NodeRef,
        enter: []const usize,
        leave: []const usize,
    ) Error!Check {
        return .{
            .allocator = allocator,
            .program = program,
            .state = state,
            .captures = captures,
            .children = children,
            .enter = enter,
            .leave = leave,
            .facts = try effect_scope.derive(allocator, program),
        };
    }

    fn node(self: Check, ref: g.NodeRef) Error!g.Node {
        if (ref.id >= self.state.nodes.len) return error.InvalidReference;
        return self.state.nodes[@intCast(ref.id)];
    }

    fn handler(self: Check, ref: g.NodeRef) Error!p.Handler {
        const activation = try self.node(ref);
        if (activation != .handler or activation.handler.definition >= self.program.handlers.len)
            return error.InvalidState;
        return self.program.handlers[@intCast(activation.handler.definition)];
    }

    fn block(self: Check, id: p.Id) Error!p.Block {
        if (id >= self.program.blocks.len) return error.InvalidReference;
        return self.program.blocks[@intCast(id)];
    }

    fn scopeEffects(self: Check, source: p.Id, cleanup: bool, effect: p.Id) Error!bool {
        const code = try self.block(source);
        const operand = switch (code.terminator) {
            .with_region => |v| v.body,
            .protect => |v| if (cleanup) v.cleanup else v.body,
            else => return error.InvalidState,
        };
        const signature = try contracts.computation(self.program, try contracts.slotSchema(code, operand));
        return contracts.containsEffect(signature.effects, effect);
    }

    pub fn requireEffects(self: *Check, parent: ?g.NodeRef, effects: []const p.Id) Error!void {
        for (effects) |effect| if (!try self.allows(parent, effect)) return error.InvalidEffect;
    }

    fn allows(self: *Check, parent: ?g.NodeRef, effect: p.Id) Error!bool {
        var cursor = parent;
        while (cursor) |ref| switch (try self.node(ref)) {
            .continuation => |v| return contracts.invocationEffect(
                self.program,
                try self.block(v.source_block),
                self.facts,
                effect,
            ),
            .attachment => |v| {
                const handler_ = try self.handler(v.handler);
                if (v.phase == .suspended) {
                    const schema = self.captures[@intCast(ref.id)] orelse return error.InvalidState;
                    const signature = try contracts.resumption(self.program, schema);
                    if (contracts.containsEffect(signature.effects, effect)) return true;
                    if (signature.mode != .deep) return false;
                }
                for (handler_.clauses) |clause| if (clause.effect == effect) {
                    if (try self.local(ref, effect)) return true;
                    break;
                };
                if (v.phase == .suspended) return false;
                cursor = v.return_to;
            },
            .region_scope => |v| return self.scopeEffects(v.source_block, false, effect),
            .protection => |v| return self.scopeEffects(v.source_block, false, effect),
            .cleanup_return => |v| {
                const obligation = try self.node(v.obligation.node);
                if (obligation != .obligation) return error.InvalidState;
                return self.scopeEffects(obligation.obligation.source_block, true, effect);
            },
            .injection => |v| {
                const saved = try self.node(v.continuation);
                if (saved != .continuation) return error.InvalidState;
                const source = try self.block(saved.continuation.source_block);
                if (source.terminator != .perform) return error.InvalidState;
                return contracts.containsEffect(
                    self.program.effects[@intCast(source.terminator.perform.effect)].use_site_effects,
                    effect,
                );
            },
            .disposal_return => |v| return contracts.containsEffect(
                (try contracts.resumption(self.program, v.schema)).effects,
                effect,
            ),
            else => return error.InvalidState,
        };
        return contracts.containsEffect(
            self.program.functions[@intCast(self.program.roots.entry)].effects,
            effect,
        );
    }

    pub fn attachment(self: *Check, ref: g.NodeRef) Error!void {
        const record = (try self.node(ref)).attachment;
        const definition = try self.handler(record.handler);
        if (record.phase == .active) return self.requireEffects(record.return_to, definition.effects);
        const schema = self.captures[@intCast(ref.id)] orelse return error.InvalidState;
        const signature = try contracts.resumption(self.program, schema);
        if (signature.mode == .deep) try contracts.subset(definition.effects, signature.effects);
    }

    fn inside(self: Check, ref: g.NodeRef, scope: g.NodeRef) bool {
        return self.enter[@intCast(scope.id)] <= self.enter[@intCast(ref.id)] and
            self.leave[@intCast(ref.id)] <= self.leave[@intCast(scope.id)];
    }

    fn local(self: *Check, scope: g.NodeRef, effect: p.Id) Error!bool {
        if (self.facts.ambient[@intCast(effect)]) return false;
        if (!self.origins.contains(effect)) {
            var origins = try Origins.init(self, effect);
            try origins.solve(self);
            try self.origins.put(self.allocator, effect, origins);
        }
        const origins = self.origins.getPtr(effect).?;
        const scratch = try self.allocator.alloc(usize, origins.width);
        defer self.allocator.free(scratch);
        @memset(scratch, 0);
        _ = try origins.child(self, @intCast(scope.id), scratch, null);
        for (origins.capabilities.items, 0..) |cap, bit| {
            if (Origins.contains(scratch, bit) and !self.inside(cap, scope)) return false;
        }
        return true;
    }
};

/// Each row is a set of capability origins exposed by a value or control
/// component. Union and subtraction of a fixed delimiter scope are monotone,
/// including continuation/cell cycles and recursively retained templates.
const Origins = struct {
    effect: p.Id,
    indices: []usize,
    capabilities: std.ArrayList(g.NodeRef) = .empty,
    width: usize = 0,
    bits: []usize = &.{},
    const word_bits = @bitSizeOf(usize);
    const absent = std.math.maxInt(usize);

    fn init(check: *Check, effect: p.Id) Error!Origins {
        var self: Origins = .{
            .effect = effect,
            .indices = try check.allocator.alloc(usize, check.state.nodes.len),
        };
        @memset(self.indices, absent);
        for (check.state.nodes) |record| try self.collect(g.Node, check, record);
        self.width = std.math.divCeil(usize, self.capabilities.items.len, word_bits) catch
            return error.InvalidLength;
        const length = std.math.mul(usize, check.state.nodes.len, self.width) catch
            return error.InvalidLength;
        self.bits = try check.allocator.alloc(usize, length);
        @memset(self.bits, 0);
        return self;
    }

    fn collect(self: *Origins, comptime T: type, check: *Check, value: T) Error!void {
        if (T == g.Value) {
            const shape = try a.schemaAt(check.program.schemas, value.schema);
            if (shape != .internal or shape.internal != .capability or
                shape.internal.capability != self.effect) return;
            if (value.body != .reference) return error.InvalidValue;
            const ref = value.body.reference;
            if (try check.node(ref) != .attachment) return error.InvalidState;
            if (self.indices[@intCast(ref.id)] == absent) {
                self.indices[@intCast(ref.id)] = self.capabilities.items.len;
                try self.capabilities.append(check.allocator, ref);
            }
            return;
        }
        switch (@typeInfo(T)) {
            inline .pointer, .array => |info| {
                if (info.child != u8) for (value) |item| try self.collect(info.child, check, item);
            },
            .optional => |info| if (value) |item| try self.collect(info.child, check, item),
            .@"struct" => |info| inline for (info.fields) |field|
                try self.collect(field.type, check, @field(value, field.name)),
            .@"union" => |info| inline for (info.fields) |field| {
                if (std.mem.eql(u8, @tagName(value), field.name)) {
                    try self.collect(field.type, check, @field(value, field.name));
                    return;
                }
            },
            else => {},
        }
    }

    fn row(self: Origins, id: usize) []usize {
        return self.bits[id * self.width ..][0..self.width];
    }

    fn contains(row_: []const usize, bit: usize) bool {
        return row_[bit / word_bits] & (@as(usize, 1) << @intCast(bit % word_bits)) != 0;
    }

    fn add(row_: []usize, bit: usize) bool {
        const mask = @as(usize, 1) << @intCast(bit % word_bits);
        const changed = row_[bit / word_bits] & mask == 0;
        row_[bit / word_bits] |= mask;
        return changed;
    }

    fn merge(self: Origins, check: *Check, into: []usize, ref: g.NodeRef, mask: ?g.NodeRef) Error!bool {
        _ = try check.node(ref);
        const from = self.row(@intCast(ref.id));
        var changed = false;
        for (self.capabilities.items, 0..) |cap, bit| {
            if (!contains(from, bit)) continue;
            if (mask) |scope| if (check.inside(cap, scope)) continue;
            changed = add(into, bit) or changed;
        }
        return changed;
    }

    fn valueOrigins(self: Origins, check: *Check, into: []usize, item: g.Value) Error!bool {
        const shape = try a.schemaAt(check.program.schemas, item.schema);
        if (shape == .internal and shape.internal == .capability) {
            if (shape.internal.capability != self.effect) return false;
            if (item.body != .reference) return error.InvalidValue;
            return add(into, self.indices[@intCast(item.body.reference.id)]);
        }
        return switch (item.body) {
            .reference => |ref| self.merge(check, into, ref, null),
            .owned => |ref| self.merge(check, into, ref.node, null),
            else => false,
        };
    }

    fn values(self: Origins, comptime T: type, check: *Check, into: []usize, input: T) Error!bool {
        if (T == g.Value) return self.valueOrigins(check, into, input);
        var changed = false;
        switch (@typeInfo(T)) {
            inline .pointer, .array => |info| {
                if (info.child != u8) for (input) |item| {
                    changed = try self.values(info.child, check, into, item) or changed;
                };
            },
            .optional => |info| if (input) |item| {
                changed = try self.values(info.child, check, into, item) or changed;
            },
            .@"struct" => |info| inline for (info.fields) |field| {
                changed = try self.values(field.type, check, into, @field(input, field.name)) or changed;
            },
            .@"union" => |info| inline for (info.fields) |field| {
                if (std.mem.eql(u8, @tagName(input), field.name))
                    return self.values(field.type, check, into, @field(input, field.name));
            },
            else => {},
        }
        return changed;
    }

    fn child(self: Origins, check: *Check, id: usize, into: []usize, mask: ?g.NodeRef) Error!bool {
        const ref = check.children[id] orelse return false;
        return switch (try check.node(ref)) {
            .one_shot, .multi_template => |capture| blk: {
                var changed = false;
                for (capture.use_site_capabilities) |item| {
                    const shape = try a.schemaAt(check.program.schemas, item.schema);
                    if (shape != .internal or shape.internal != .capability)
                        return error.TypeMismatch;
                    if (item.body != .reference) return error.InvalidValue;
                    _ = try check.node(item.body.reference);
                    if (mask) |scope| if (check.inside(item.body.reference, scope)) continue;
                    changed = try self.valueOrigins(check, into, item) or changed;
                }
                break :blk changed;
            },
            .pending => false, // Environmental resume values are first-order.
            else => self.merge(check, into, ref, mask),
        };
    }

    fn delimiter(self: Origins, check: *Check, id: usize, into: []usize) Error!bool {
        const attachment = check.state.nodes[id].attachment;
        const definition = try check.handler(attachment.handler);
        const reinstated = attachment.phase == .active or blk: {
            const schema = check.captures[id] orelse return error.InvalidState;
            break :blk (try contracts.resumption(check.program, schema)).mode == .deep;
        };
        var mask: ?g.NodeRef = null;
        if (reinstated) for (definition.clauses) |clause| if (clause.effect == self.effect) {
            mask = .{ .id = id };
            break;
        };
        var changed = try self.child(check, id, into, mask);
        if (reinstated) changed = try self.merge(check, into, attachment.handler, null) or changed;
        return changed;
    }

    fn solve(self: *Origins, check: *Check) Error!void {
        if (self.width == 0) return;
        var changed = true;
        while (changed) {
            changed = false;
            for (check.state.nodes, 0..) |record, id| {
                const into = self.row(id);
                switch (record) {
                    .attachment => {
                        changed = try self.delimiter(check, id, into) or changed;
                        continue;
                    },
                    .one_shot, .multi_template => |capture| {
                        changed = try self.merge(check, into, capture.delimiter, null) or changed;
                        continue;
                    },
                    .computation => |v| changed = try self.merge(check, into, v.environment, null) or changed,
                    .protection => |v| changed = try self.merge(check, into, v.obligation.node, null) or changed,
                    .cleanup_return => |v| changed = try self.merge(check, into, v.exit, null) or changed,
                    .borrow => |v| changed = try self.merge(check, into, v.resource, null) or changed,
                    .exit => |v| if (v.outer) |outer| {
                        changed = try self.merge(check, into, outer, null) or changed;
                    },
                    else => {},
                }
                changed = try self.values(g.Node, check, into, record) or changed;
                changed = try self.child(check, id, into, null) or changed;
            }
        }
    }
};
