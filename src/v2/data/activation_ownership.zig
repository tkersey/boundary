// Copyright (c) 2026 Boundary contributors. MIT license.
//! Compose independently derived stable-slot facts with use/capture contracts.
//! Borrow provenance and dynamic State admission remain separate obligations.
const std = @import("std");
const p = @import("program.zig");
const ir = @import("activation.zig");
const flow = @import("activation_flow.zig");
const types = @import("activation_types.zig");
const contracts = @import("contracts.zig");
const effect_scope = @import("effect_scope.zig");
const sets = @import("analysis_sets.zig");
pub const Error = types.Error || flow.Error;

/// All facts are derived inside this call from the same immutable input. A caller
/// cannot supply a live map or a weaker capture summary as proof of the program.
pub fn analyze(allocator: std.mem.Allocator, image: ir.Program) Error!flow.Facts {
    return analyzeInternal(allocator, image, &.{}, false, &.{});
}

pub fn analyzeComponent(
    allocator: std.mem.Allocator,
    image: ir.Program,
    imports: []const p.Id,
    borrows: []const @import("borrow_contract.zig").Summary,
) Error!flow.Facts {
    return analyzeInternal(allocator, image, imports, true, borrows);
}
fn analyzeInternal(
    allocator: std.mem.Allocator,
    image: ir.Program,
    imports: []const p.Id,
    component: bool,
    borrows: []const @import("borrow_contract.zig").Summary,
) Error!flow.Facts {
    if (component) try types.validateComponent(allocator, image, imports, borrows) else try types.validate(allocator, image);
    var facts = try flow.analyzeComponent(allocator, image, imports);
    errdefer facts.deinit();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    var checker: Check = .{
        .image = image,
        .facts = &facts,
        .uses = try @import("traits.zig").derive(scratch, image.schemas),
        .effects = try effect_scope.deriveComponent(scratch, image, imports),
    };
    for (image.blocks, 0..) |block, id| {
        if (facts.entries[id] == null) continue;
        if (block.terminator == .return_value) {
            var obligations = facts.positions[id][block.instructions.len].obligations;
            obligations = try facts.pool.remove(obligations, block.terminator.return_value);
            if (obligations != sets.empty) return error.InvalidOwnership;
        }
        try checker.block(block);
    }
    return facts;
}

const Check = struct {
    image: ir.Program,
    facts: *flow.Facts,
    uses: @import("traits.zig").Facts,
    effects: effect_scope.Facts,

    fn computation(self: Check, slots: []const p.Id, slot: p.Id) Error!p.ComputationType {
        return contracts.computation(self.image, slots[@intCast(slot)]);
    }

    fn resumption(self: Check, slots: []const p.Id, slot: p.Id) Error!p.ResumptionType {
        return contracts.resumption(self.image, slots[@intCast(slot)]);
    }

    fn block(self: *Check, code: ir.Block) Error!void {
        const slots = self.image.functions[@intCast(code.function)].layout.slots;
        switch (code.terminator) {
            .call => |call| try self.control(slots, self.image.functions[@intCast(call.function)].effects, call.next),
            .perform => |perform| {
                try self.control(slots, &.{perform.effect}, perform.next);
                const effect = self.image.effects[@intCast(perform.effect)];
                try self.control(slots, effect.use_site_effects, perform.next);
            },
            .apply => |apply| try self.control(slots, (try self.computation(slots, apply.computation)).effects, apply.next),
            .handle => |handle| try self.checkHandler(slots, handle),
            inline .resume_value, .resume_computation => |operation| try self.control(slots, (try self.resumption(slots, operation.resumption)).effects, operation.next),
            .resume_with => |operation| try self.resumeWith(slots, operation),
            .with_region => |region| try self.control(slots, (try self.computation(slots, region.body)).effects, region.next),
            .protect => |protect| {
                try self.control(slots, (try self.computation(slots, protect.body)).effects, protect.next);
                try self.control(slots, (try self.computation(slots, protect.cleanup)).effects, protect.next);
            },
            .dispose => |dispose| try self.control(slots, (try self.resumption(slots, dispose.owned)).effects, dispose.next),
            else => {},
        }
    }

    fn checkHandler(self: *Check, slots: []const p.Id, operation: anytype) Error!void {
        const handler = self.image.handlers[@intCast(operation.handler)];
        const signature = try self.computation(slots, operation.body);
        for (signature.effects) |effect| {
            if (effect_scope.discharged(self.image, self.effects, handler, signature, effect))
                continue;
            try self.control(slots, &.{effect}, operation.next);
            for (operation.state) |slot| try self.capture(slots, effect, slot);
        }
        try self.control(slots, handler.effects, operation.next);
    }

    fn resumeWith(self: *Check, slots: []const p.Id, operation: anytype) Error!void {
        const signature = try self.resumption(slots, operation.resumption);
        const successor = self.image.handlers[@intCast(operation.handler)];
        for (signature.effects) |effect| {
            const escapes = !contracts.containsEffect(signature.handled, effect) or
                contracts.containsEffect(signature.escaping, effect);
            if (!escapes) continue;
            try self.control(slots, &.{effect}, operation.next);
            for (operation.state) |slot| try self.capture(slots, effect, slot);
        }
        try self.control(slots, successor.effects, operation.next);
    }

    fn retained(self: *Check, next: ir.Edge) Error!sets.Root {
        const pool = self.facts.pool;
        const after = self.facts.live[@intCast(next.block)][0];
        var result = after;
        for (next.assignments) |assignment|
            result = try pool.remove(result, assignment.destination);
        for (next.assignments) |assignment| {
            if (assignment.source == .slot and pool.contains(after, assignment.destination))
                result = try pool.insert(result, assignment.source.slot);
        }
        return result;
    }

    fn control(self: *Check, slots: []const p.Id, effects: []const p.Id, next: ir.Edge) Error!void {
        if (effects.len == 0) return;
        const root = try self.retained(next);
        for (effects) |effect| {
            var live = self.facts.pool.iterator(root);
            while (live.next()) |slot| try self.capture(slots, effect, slot);
        }
    }

    fn capture(self: Check, slots: []const p.Id, effect: p.Id, slot: p.Id) Error!void {
        const schema = slots[@intCast(slot)];
        if (self.image.effects[@intCast(effect)].control_use == .multi and
            !self.uses.clone[@intCast(schema)]) return error.InvalidOwnership;
        for (self.image.handlers) |handler| for (handler.clauses) |clause| {
            if (clause.effect != effect) continue;
            const signature = try contracts.resumption(self.image, clause.resumption);
            if (std.mem.indexOfScalar(p.Id, signature.capture_bound, schema) == null)
                return error.InvalidOwnership;
        };
    }
};
