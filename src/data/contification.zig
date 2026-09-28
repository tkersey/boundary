// Copyright (c) 2026 Boundary contributors. MIT license.
//! One private, non-suspending helper becomes one shared caller-local join body.
const std = @import("std");
const ir = @import("activation.zig");
const p = @import("program.zig");
const ownership = @import("activation_ownership.zig");
const contexts = @import("call_contexts.zig");
const traits = @import("traits.zig");
const admission = @import("admission.zig");
const equal = @import("record_equal.zig").equal;
const p01 = @import("coalescing.zig");
const image = @import("program_image.zig");
pub const Error = p01.Error || error{ InvalidContification, ContificationLimit };
pub const Options = struct { work_limit: usize = 1_000_000, max_blocks: usize = 256, max_slots: usize = 512, max_added_bytes: usize = 4096, coalescing: p01.Options = .{} };
pub const Witness = struct { helper: p.Id, caller: p.Id, first_slot: usize, first_block: usize };
pub const Statistics = struct { helpers: usize = 0, calls_removed: usize = 0, body_blocks: usize = 0, work_limit: bool = false };
pub const Candidate = struct {
    arena: std.heap.ArenaAllocator,
    program: ir.Program,
    witness: Witness,
    pub fn deinit(self: *Candidate) void {
        self.arena.deinit();
        self.* = undefined;
    }
};
const Budget = struct {
    left: usize,
    fn tick(self: *Budget) Error!void {
        try self.take(1);
    }
    fn take(self: *Budget, amount: usize) Error!void {
        if (self.left < amount) return error.ContificationLimit;
        self.left -= amount;
    }
};
const Context = struct { caller: p.Id, continuation: ir.Edge, calls: usize, blocks: usize };
fn quietFunction(program: ir.Program, id: p.Id, helper: p.Id, permissions: traits.Facts, exportable: []const bool, budget: *Budget) Error!bool {
    const function = program.functions[@intCast(id)];
    if (function.effects.len != 0 or function.regions.len != 0 or function.custody.len != 1) return false;
    for (function.layout.slots) |schema| {
        try budget.tick();
        if (!permissions.copy[@intCast(schema)] or !permissions.drop[@intCast(schema)] or !exportable[@intCast(schema)]) return false;
    }
    for (program.blocks) |block| {
        try budget.tick();
        if (block.function != id) continue;
        if (block.custody != 0) return false;
        for (block.instructions) |op| {
            try budget.tick();
            try budget.take(op.operands.len);
            if (op.failures.len != 0) return false;
            switch (op.opcode) {
                .constant, .move, .product, .field, .variant, .equal, .less, .boolean_not, .integer_bit_not, .integer_bit_and, .integer_bit_or, .integer_bit_xor => {},
                else => return false,
            }
        }
        switch (block.terminator) {
            .return_value, .fail, .jump, .branch => {},
            .call => |call| if (id == helper or call.function != helper) return false,
            else => return false,
        }
    }
    return true;
}
fn classify(program: ir.Program, helper: p.Id, permissions: traits.Facts, exportable: []const bool, budget: *Budget) Error!?Context {
    try budget.tick();
    if (helper >= program.functions.len or contexts.unknownEntry(program, helper)) return null;
    var context: ?Context = null;
    for (program.blocks) |block| {
        try budget.tick();
        if (block.terminator != .call or block.terminator.call.function != helper) continue;
        if (block.function == helper) return null;
        if (context) |*known| {
            if (known.caller != block.function or !equal(ir.Edge, known.continuation, block.terminator.call.next)) return null;
            known.calls += 1;
        } else context = .{ .caller = block.function, .continuation = block.terminator.call.next, .calls = 1, .blocks = 0 };
    }
    const found = context orelse return null;
    if (!try quietFunction(program, helper, helper, permissions, exportable, budget) or !try quietFunction(program, found.caller, helper, permissions, exportable, budget)) return null;
    var result = found;
    for (program.blocks) |block| {
        try budget.tick();
        if (block.function == helper) result.blocks += 1;
    }
    return result;
}
pub fn possible(program: ir.Program) bool {
    for (program.blocks) |block| if (block.terminator == .call and !contexts.unknownEntry(program, block.terminator.call.function)) return true;
    return false;
}
fn targetBlock(program: ir.Program, witness: Witness, old: p.Id) Error!p.Id {
    var next = witness.first_block;
    for (program.blocks, 0..) |block, id| if (block.function == witness.helper) {
        if (id == old) return next;
        next += 1;
    };
    return error.InvalidContification;
}
fn localEdge(a: std.mem.Allocator, program: ir.Program, witness: Witness, old: ir.Edge) Error!ir.Edge {
    const assignments = try a.dupe(ir.Assignment, old.assignments);
    for (assignments) |*assignment| {
        assignment.destination += witness.first_slot;
        switch (assignment.source) {
            .slot => |slot| assignment.source = .{ .slot = slot + witness.first_slot },
            .returned => return error.InvalidContification,
        }
    }
    return .{ .block = try targetBlock(program, witness, old.block), .assignments = assignments };
}
fn terminalReturn(program: ir.Program, edge: ir.Edge) ?ir.Source {
    const continuation = program.blocks[@intCast(edge.block)];
    if (continuation.instructions.len != 0 or continuation.terminator != .return_value) return null;
    const result = continuation.terminator.return_value;
    for (edge.assignments) |assignment| if (assignment.destination == result) return assignment.source;
    return .{ .slot = result };
}
pub fn construct(allocator: std.mem.Allocator, original: ir.Program, options: Options) Error!?Candidate {
    var admitted = try ownership.analyze(allocator, original);
    defer admitted.deinit();
    var arena = std.heap.ArenaAllocator.init(allocator);
    var keep = false;
    defer if (!keep) arena.deinit();
    const a = arena.allocator();
    const permissions = try traits.derive(a, original.schemas);
    const schemas = try admission.schemas(a, original.schemas);
    var budget: Budget = .{ .left = options.work_limit };
    var selected: ?Witness = null;
    var context: Context = undefined;
    for (original.functions, 0..) |function, id| {
        const found = (try classify(original, id, permissions, schemas.exportable, &budget)) orelse continue;
        if (found.blocks > options.max_blocks or function.layout.slots.len > options.max_slots) return error.ContificationLimit;
        selected = .{ .helper = id, .caller = found.caller, .first_slot = original.functions[@intCast(found.caller)].layout.slots.len, .first_block = original.blocks.len };
        context = found;
        break;
    }
    const witness = selected orelse return null;
    const helper = original.functions[@intCast(witness.helper)];
    const functions = try a.dupe(ir.Function, original.functions);
    const slots = try a.alloc(p.Id, witness.first_slot + helper.layout.slots.len);
    @memcpy(slots[0..witness.first_slot], functions[@intCast(witness.caller)].layout.slots);
    @memcpy(slots[witness.first_slot..], helper.layout.slots);
    functions[@intCast(witness.caller)].layout.slots = slots;
    const blocks = try a.alloc(ir.Block, original.blocks.len + context.blocks);
    @memcpy(blocks[0..original.blocks.len], original.blocks);
    var next = witness.first_block;
    for (original.blocks, 0..) |block, bid| {
        try budget.tick();
        if (block.terminator == .call and block.terminator.call.function == witness.helper) {
            const assignments = try a.alloc(ir.Assignment, helper.inputs.len);
            for (assignments, helper.inputs, block.terminator.call.arguments) |*assignment, input, argument| assignment.* = .{ .destination = witness.first_slot + input, .source = .{ .slot = argument } };
            blocks[bid].terminator = .{ .jump = .{ .block = try targetBlock(original, witness, helper.entry), .assignments = assignments } };
        }
        if (block.function != witness.helper) continue;
        var copied = block;
        copied.function = witness.caller;
        const instructions = try a.dupe(ir.Instruction, block.instructions);
        for (instructions) |*op| {
            try budget.tick();
            op.destination += witness.first_slot;
            const operands = try a.dupe(p.Id, op.operands);
            for (operands) |*slot| slot.* += witness.first_slot;
            op.operands = operands;
        }
        copied.instructions = instructions;
        switch (block.terminator) {
            .return_value => |value| {
                if (terminalReturn(original, context.continuation)) |source| {
                    copied.terminator = .{ .return_value = switch (source) {
                        .returned => value + witness.first_slot,
                        .slot => |slot| slot,
                    } };
                } else {
                    const assignments = try a.dupe(ir.Assignment, context.continuation.assignments);
                    for (assignments) |*assignment| if (assignment.source == .returned) {
                        assignment.source = .{ .slot = value + witness.first_slot };
                    };
                    copied.terminator = .{ .jump = .{ .block = context.continuation.block, .assignments = assignments } };
                }
            },
            .fail => |value| copied.terminator = .{ .fail = value + witness.first_slot },
            .jump => |edge| copied.terminator = .{ .jump = try localEdge(a, original, witness, edge) },
            .branch => |branch| copied.terminator = .{ .branch = .{ .condition = branch.condition + witness.first_slot, .when_true = try localEdge(a, original, witness, branch.when_true), .when_false = try localEdge(a, original, witness, branch.when_false) } },
            else => return error.InvalidContification,
        }
        blocks[next] = copied;
        next += 1;
    }
    var program = original;
    program.functions = functions;
    program.blocks = blocks;
    const before = try image.encodedLength(original);
    const after = try image.encodedLength(program);
    if (after > before and after - before > options.max_added_bytes) return error.ContificationLimit;
    keep = true;
    return .{ .arena = arena, .program = program, .witness = witness };
}
fn edgeCorresponds(program: ir.Program, witness: Witness, old: ir.Edge, new: ir.Edge) bool {
    var ordinal: usize = 0;
    var destination: ?usize = null;
    for (program.blocks, 0..) |block, id| if (block.function == witness.helper) {
        if (id == old.block) destination = witness.first_block + ordinal;
        ordinal += 1;
    };
    if (destination == null or new.block != destination.? or old.assignments.len != new.assignments.len) return false;
    for (old.assignments, new.assignments) |before, after| {
        if (before.source != .slot or after.source != .slot or after.destination != before.destination + witness.first_slot or after.source.slot != before.source.slot + witness.first_slot) return false;
    }
    return true;
}
pub fn validate(allocator: std.mem.Allocator, original: ir.Program, candidate: ir.Program, witness: Witness, options: Options) Error!void {
    var before = try ownership.analyze(allocator, original);
    defer before.deinit();
    var after = try ownership.analyze(allocator, candidate);
    defer after.deinit();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const permissions = try traits.derive(a, original.schemas);
    const schemas = try admission.schemas(a, original.schemas);
    var budget: Budget = .{ .left = options.work_limit };
    const context = (try classify(original, witness.helper, permissions, schemas.exportable, &budget)) orelse return error.InvalidContification;
    if (context.caller != witness.caller or candidate.functions.len != original.functions.len or witness.first_block != original.blocks.len or candidate.blocks.len != original.blocks.len + context.blocks) return error.InvalidContification;
    const helper = original.functions[@intCast(witness.helper)];
    const caller = original.functions[@intCast(witness.caller)];
    if (witness.first_slot != caller.layout.slots.len) return error.InvalidContification;
    var unchanged = candidate;
    unchanged.functions = original.functions;
    unchanged.blocks = original.blocks;
    if (!equal(ir.Program, original, unchanged)) return error.InvalidContification;
    for (original.functions, candidate.functions, 0..) |old, new, id| {
        if (id != witness.caller) {
            if (!equal(ir.Function, old, new)) return error.InvalidContification;
            continue;
        }
        var metadata = new;
        metadata.layout = old.layout;
        if (!equal(ir.Function, old, metadata) or new.layout.slots.len != witness.first_slot + helper.layout.slots.len or !std.mem.eql(p.Id, old.layout.slots, new.layout.slots[0..witness.first_slot]) or !std.mem.eql(p.Id, helper.layout.slots, new.layout.slots[witness.first_slot..])) return error.InvalidContification;
    }
    var copied_id = witness.first_block;
    var entry: ?usize = null;
    for (original.blocks, candidate.blocks[0..original.blocks.len], 0..) |old, new, bid| {
        try budget.tick();
        if (old.terminator == .call and old.terminator.call.function == witness.helper) {
            var metadata = new;
            metadata.terminator = old.terminator;
            if (!equal(ir.Block, old, metadata) or new.terminator != .jump or new.terminator.jump.assignments.len != helper.inputs.len) return error.InvalidContification;
            // Entry identity is checked below after deriving the helper block order.
            if (entry) |known| {
                if (new.terminator.jump.block != known) return error.InvalidContification;
            } else entry = @intCast(new.terminator.jump.block);
            for (helper.inputs, old.terminator.call.arguments, new.terminator.jump.assignments) |input, argument, transfer| {
                if (transfer.destination != witness.first_slot + input or transfer.source != .slot or transfer.source.slot != argument) return error.InvalidContification;
            }
        } else if (!equal(ir.Block, old, new)) return error.InvalidContification;
        if (old.function != witness.helper) continue;
        const copied = candidate.blocks[copied_id];
        // Calls may occur later in record order; retain the independently derived entry.
        if (bid == helper.entry) {
            if (entry != null and entry.? != copied_id) return error.InvalidContification;
            entry = copied_id;
        }
        copied_id += 1;
        if (copied.function != witness.caller or copied.custody != old.custody or copied.instructions.len != old.instructions.len) return error.InvalidContification;
        for (old.instructions, copied.instructions) |op, replacement| {
            try budget.tick();
            if (replacement.destination != op.destination + witness.first_slot or replacement.operands.len != op.operands.len) return error.InvalidContification;
            for (op.operands, replacement.operands) |operand, mapped| if (mapped != operand + witness.first_slot) return error.InvalidContification;
            var metadata = replacement;
            metadata.destination = op.destination;
            metadata.operands = op.operands;
            if (!equal(ir.Instruction, op, metadata)) return error.InvalidContification;
        }
        switch (old.terminator) {
            .return_value => |value| {
                if (copied.terminator == .return_value) {
                    // Reconstruct the continuation's returned value directly;
                    // all edge sources read the original caller view.
                    const continuation = original.blocks[@intCast(context.continuation.block)];
                    if (continuation.instructions.len != 0 or continuation.terminator != .return_value) return error.InvalidContification;
                    const result = continuation.terminator.return_value;
                    var expected = result;
                    for (context.continuation.assignments) |transfer| if (transfer.destination == result) {
                        expected = switch (transfer.source) {
                            .returned => value + witness.first_slot,
                            .slot => |slot| slot,
                        };
                    };
                    if (copied.terminator.return_value != expected) return error.InvalidContification;
                    continue;
                }
                if (copied.terminator != .jump or copied.terminator.jump.block != context.continuation.block or copied.terminator.jump.assignments.len != context.continuation.assignments.len) return error.InvalidContification;
                for (context.continuation.assignments, copied.terminator.jump.assignments) |transfer, replacement| {
                    var expected = transfer;
                    if (expected.source == .returned) expected.source = .{ .slot = value + witness.first_slot };
                    if (!equal(ir.Assignment, expected, replacement)) return error.InvalidContification;
                }
            },
            .fail => |value| if (copied.terminator != .fail or copied.terminator.fail != value + witness.first_slot) return error.InvalidContification,
            .jump => |edge| if (copied.terminator != .jump or !edgeCorresponds(original, witness, edge, copied.terminator.jump)) return error.InvalidContification,
            .branch => |branch| if (copied.terminator != .branch or copied.terminator.branch.condition != branch.condition + witness.first_slot or !edgeCorresponds(original, witness, branch.when_true, copied.terminator.branch.when_true) or !edgeCorresponds(original, witness, branch.when_false, copied.terminator.branch.when_false)) return error.InvalidContification,
            else => return error.InvalidContification,
        }
    }
}
pub fn run(allocator: std.mem.Allocator, original: ir.Program, statistics: ?*Statistics, options: Options) Error!p01.Owned {
    var stats: Statistics = .{};
    defer if (statistics) |out| {
        out.* = stats;
    };
    var candidate = (construct(allocator, original, options) catch |err| switch (err) {
        error.ContificationLimit => {
            stats.work_limit = true;
            return p01.run(allocator, original, options.coalescing);
        },
        else => return err,
    }) orelse return p01.run(allocator, original, options.coalescing);
    defer candidate.deinit();
    validate(allocator, original, candidate.program, candidate.witness, options) catch |err| switch (err) {
        error.ContificationLimit => {
            stats.work_limit = true;
            return p01.run(allocator, original, options.coalescing);
        },
        else => return err,
    };
    stats.helpers = 1;
    stats.body_blocks = candidate.program.blocks.len - original.blocks.len;
    for (original.blocks) |block| if (block.terminator == .call and block.terminator.call.function == candidate.witness.helper) {
        stats.calls_removed += 1;
    };
    return p01.run(allocator, candidate.program, options.coalescing);
}
