// Copyright (c) 2026 Boundary contributors. MIT license.
//! Block interfaces transfer ownership; recursive edges obey the same local law.
const std = @import("std");
const p = @import("program.zig");
const a = @import("admission.zig");
const contracts = @import("contracts.zig");
const Facts = @import("traits.zig").Facts;
const effect_scope = @import("effect_scope.zig");

pub fn block(allocator: std.mem.Allocator, image: p.Program, code: p.Block, slots: []const p.Id, facts: Facts, effect_facts: effect_scope.Facts, diagnostic: ?*a.Diagnostic) a.Error!void {
    const used = try allocator.alloc(bool, slots.len);
    @memset(used, false);
    var check: Check = .{ .image = image, .slots = slots, .facts = facts, .used = used, .diagnostic = diagnostic };
    for (code.instructions, 0..) |instruction, instruction_index| {
        if (diagnostic) |d| {
            d.instruction = instruction_index;
            d.terminator = null;
        }
        if (instruction.opcode.borrowsOperands()) {
            for (instruction.operands) |operand| try check.borrow(operand);
            if (instruction.opcode == .sequence_get) {
                const source = image.schemas[@intCast(slots[@intCast(instruction.operands[0])])];
                const element = try @import("aggregate_admission.zig").element(source);
                if (!facts.copy[@intCast(element)]) return error.InvalidOwnership;
            }
            continue;
        }
        switch (instruction.opcode) {
            .select => {
                if (!facts.drop[@intCast(instruction.result_type)]) return error.InvalidOwnership;
                for (instruction.operands) |operand| try check.consume(operand);
            },
            .sequence_set, .sequence_take => {
                const element = try @import("aggregate_admission.zig").element(image.schemas[@intCast(instruction.result_type)]);
                if (!facts.drop[@intCast(element)]) return error.InvalidOwnership;
                for (instruction.operands) |operand| try check.consume(operand);
            },
            .field => {
                const fields = image.schemas[@intCast(slots[@intCast(instruction.operands[0])])].product;
                for (fields, 0..) |field, index| if (index != instruction.immediate and !facts.drop[@intCast(field)]) return error.InvalidOwnership;
                try check.consume(instruction.operands[0]);
            },
            else => for (instruction.operands) |operand| try check.consume(operand),
        }
    }
    if (diagnostic) |d| {
        d.instruction = null;
        d.terminator = std.meta.activeTag(code.terminator);
    }
    switch (code.terminator) {
        .return_value => |slot| try check.consume(slot),
        .fail => return, // Abrupt exit transfers remaining custody to unwinding.
        .jump, .yield_value => |edge| try check.edge(edge, null),
        .branch => |branch| {
            try check.consume(branch.condition);
            const alternative = try allocator.dupe(bool, used);
            try check.edge(branch.when_true, null);
            try check.finish();
            check.used = alternative;
            try check.edge(branch.when_false, null);
        },
        .switch_variant => |selected| {
            try check.consume(selected.value);
            const entry = try allocator.dupe(bool, check.used);
            const fields = image.schemas[@intCast(slots[@intCast(selected.value)])].sum;
            for (selected.cases, fields) |target, payload| {
                @memcpy(check.used, entry);
                try check.edge(target, payload);
                try check.finish();
            }
        },
        .unpack_product => |unpack| {
            try check.consume(unpack.value);
            for (unpack.arguments) |slot| try check.consume(slot);
        },
        .call => |call| {
            for (call.arguments) |slot| try check.consume(slot);
            try check.control(image.functions[@intCast(call.function)].effects, call.next);
            try check.edge(call.next, image.functions[@intCast(call.function)].result);
        },
        .perform => |perform| {
            try check.consume(perform.payload);
            for (perform.bodies) |slot| try check.consume(slot);
            if (perform.capability) |slot| try check.consume(slot);
            for (perform.use_site_capabilities) |slot| try check.consume(slot);
            try check.control(&.{perform.effect}, perform.next);
            try check.control(image.effects[@intCast(perform.effect)].use_site_effects, perform.next);
            try check.edge(perform.next, image.effects[@intCast(perform.effect)].result);
        },
        .apply => |apply| {
            try check.consume(apply.computation);
            for (apply.arguments) |slot| try check.consume(slot);
            const signature = try contracts.computation(image, slots[@intCast(apply.computation)]);
            try check.control(signature.effects, apply.next);
            try check.edge(apply.next, signature.result);
        },
        .handle => |handle| {
            try check.consume(handle.body);
            for (handle.arguments) |slot| try check.consume(slot);
            for (handle.state) |slot| try check.consume(slot);
            const handler = image.handlers[@intCast(handle.handler)];
            const signature = try contracts.computation(image, slots[@intCast(handle.body)]);
            for (signature.effects) |effect| {
                if (!effect_scope.discharged(image, effect_facts, handler, signature, effect)) {
                    try check.control(&.{effect}, handle.next);
                    for (handle.state) |slot| try check.captureSlot(effect, slot);
                }
            }
            try check.control(handler.effects, handle.next);
            try check.edge(handle.next, handler.answer);
        },
        .resume_value => |resuming| {
            try check.consume(resuming.resumption);
            try check.consume(resuming.argument);
            const signature = try contracts.resumption(image, slots[@intCast(resuming.resumption)]);
            try check.control(signature.effects, resuming.next);
            try check.edge(resuming.next, signature.answer);
        },
        .resume_with => |resuming| {
            try check.consume(resuming.resumption);
            try check.consume(resuming.argument);
            for (resuming.state) |slot| try check.consume(slot);
            const signature = try contracts.resumption(image, slots[@intCast(resuming.resumption)]);
            const successor = image.handlers[@intCast(resuming.handler)];
            for (signature.effects) |effect| {
                const escapes = std.mem.indexOfScalar(p.Id, signature.handled, effect) == null or
                    std.mem.indexOfScalar(p.Id, signature.escaping, effect) != null;
                if (escapes) {
                    try check.control(&.{effect}, resuming.next);
                    for (resuming.state) |slot| try check.captureSlot(effect, slot);
                }
            }
            try check.control(successor.effects, resuming.next);
            try check.edge(resuming.next, successor.answer);
        },
        .resume_computation => |resuming| {
            try check.consume(resuming.resumption);
            try check.consume(resuming.computation);
            const signature = try contracts.resumption(image, slots[@intCast(resuming.resumption)]);
            try check.control(signature.effects, resuming.next);
            try check.edge(resuming.next, signature.answer);
        },
        .with_region => |scope| {
            try check.consume(scope.body);
            for (scope.arguments) |slot| try check.consume(slot);
            const body = try contracts.computation(image, slots[@intCast(scope.body)]);
            try check.control(body.effects, scope.next);
            try check.edge(scope.next, body.result);
        },
        .protect => |protection| {
            try check.consume(protection.body);
            try check.consume(protection.cleanup);
            if (protection.resource) |slot| try check.consume(slot);
            for (protection.arguments) |slot| try check.consume(slot);
            const body = try contracts.computation(image, slots[@intCast(protection.body)]);
            const cleanup = try contracts.computation(image, slots[@intCast(protection.cleanup)]);
            try check.control(body.effects, protection.next);
            try check.control(cleanup.effects, protection.next);
            try check.edge(protection.next, body.result);
        },
        .dispose => |disposal| {
            try check.consume(disposal.owned);
            const signature = try contracts.resumption(image, slots[@intCast(disposal.owned)]);
            try check.control(signature.effects, disposal.next);
            try check.edge(disposal.next, null);
        },
        else => return error.UnsupportedInstruction,
    }
    try check.finish();
}

const Check = struct {
    image: p.Program,
    slots: []const p.Id,
    facts: Facts,
    used: []bool,
    diagnostic: ?*a.Diagnostic,

    fn consume(self: *Check, id: p.Id) a.Error!void {
        const slot: usize = @intCast(id);
        if (!self.facts.copy[@intCast(self.slots[slot])]) {
            if (self.used[slot]) {
                if (self.diagnostic) |d| d.slot = id;
                return error.InvalidOwnership;
            }
            self.used[slot] = true;
        }
    }
    fn borrow(self: Check, id: p.Id) a.Error!void {
        if (self.used[@intCast(id)]) {
            if (self.diagnostic) |d| d.slot = id;
            return error.InvalidOwnership;
        }
    }
    fn edge(self: *Check, target: p.Edge, result: ?p.Id) a.Error!void {
        // A returned owned value also has one disposition in the edge interface.
        var returned_count: usize = 0;
        for (target.arguments, self.image.blocks[@intCast(target.block)].parameters) |argument, schema| switch (argument) {
            .slot => |slot| try self.consume(slot),
            .returned => {
                returned_count += 1;
                if (!self.facts.copy[@intCast(schema)] and returned_count > 1) return error.InvalidOwnership;
            },
        };
        if (result) |schema| if (returned_count == 0 and !self.facts.drop[@intCast(schema)]) return error.InvalidOwnership;
    }
    fn finish(self: Check) a.Error!void {
        for (self.slots, self.used, 0..) |schema, consumed, index| {
            if (!consumed and !self.facts.drop[@intCast(schema)]) {
                if (self.diagnostic) |d| d.slot = index;
                return error.InvalidOwnership;
            }
        }
    }
    fn control(self: Check, effects: []const p.Id, target: p.Edge) a.Error!void {
        for (effects) |effect| {
            for (target.arguments) |argument| if (argument == .slot) {
                try self.captureSlot(effect, argument.slot);
            };
        }
    }

    fn captureSlot(self: Check, effect: p.Id, slot: p.Id) a.Error!void {
        const schema = self.slots[@intCast(slot)];
        if (self.image.effects[@intCast(effect)].control_use == .multi and
            !self.facts.clone[@intCast(schema)])
        {
            if (self.diagnostic) |d| {
                d.slot = slot;
                d.effect = effect;
            }
            return error.InvalidOwnership;
        }
        // Both continuation arguments and crossed handler state belong to the capture.
        for (self.image.handlers) |handler| for (handler.clauses) |clause| {
            if (clause.effect != effect) continue;
            const signature = try contracts.resumption(self.image, clause.resumption);
            if (std.mem.indexOfScalar(p.Id, signature.capture_bound, schema) == null)
                return error.InvalidOwnership;
        };
    }
};
