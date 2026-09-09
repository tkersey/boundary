// Copyright (c) 2026 Boundary contributors. MIT license.
//! Erase the unique terminal resumption from a total straight-line clause.
//! Source checking has already proved ownership; target admission independently
//! checks the resulting direct clause's entire executable block.
const std = @import("std");
const data = @import("boundary_data_v2");
const p = data.program;
const direct = data.direct_clause;
const ghost = std.math.maxInt(p.Id);
const Body = struct { instructions: []const p.Instruction, result: p.Id };

pub fn optimize(allocator: std.mem.Allocator, original: p.Program) std.mem.Allocator.Error!p.Program {
    var functions: std.ArrayList(p.Function) = .empty;
    var blocks: std.ArrayList(p.Block) = .empty;
    try functions.appendSlice(allocator, original.functions);
    try blocks.appendSlice(allocator, original.blocks);
    var memo: std.AutoHashMapUnmanaged(p.Id, p.Id) = .empty;
    const handlers = try allocator.dupe(p.Handler, original.handlers);
    for (handlers) |*handler| {
        const clauses = try allocator.dupe(p.Clause, handler.clauses);
        handler.clauses = clauses;
        for (clauses) |*clause| {
            const signature = original.schemas[@intCast(clause.resumption)].internal.resumption;
            if (clause.direct or handler.mode != .deep or signature.use != .linear or original.effects[@intCast(clause.effect)].bodies.len != 0) continue;
            if (memo.get(clause.function)) |function| {
                clause.function = function;
                clause.direct = true;
                continue;
            }
            var scratch = std.heap.ArenaAllocator.init(allocator);
            defer scratch.deinit();
            const body = try flatten(scratch.allocator(), original, clause.function) orelse continue;
            const function = original.functions[@intCast(clause.function)];
            const new_function = functions.items.len;
            const new_block = blocks.items.len;
            const parameters = function.parameters[0 .. function.parameters.len - 1];
            const instructions = try @import("../source.zig").own([]const p.Instruction, allocator, body.instructions);
            try blocks.append(allocator, .{ .function = new_function, .parameters = parameters, .instructions = instructions, .terminator = .{ .return_value = body.result } });
            try functions.append(allocator, .{ .entry = new_block, .parameters = parameters, .result = signature.input, .regions = function.regions });
            try memo.put(allocator, clause.function, new_function);
            clause.function = new_function;
            clause.direct = true;
        }
    }
    var result = original;
    result.handlers = handlers;
    result.functions = functions.items;
    result.blocks = blocks.items;
    return result;
}

fn flatten(allocator: std.mem.Allocator, image: p.Program, function_id: p.Id) std.mem.Allocator.Error!?Body {
    const function = image.functions[@intCast(function_id)];
    var mapping = try allocator.alloc(p.Id, function.parameters.len);
    for (mapping, 0..) |*slot, id| slot.* = if (id + 1 == mapping.len) ghost else id;
    const arity = function.parameters.len - 1;
    var instructions: std.ArrayList(p.Instruction) = .empty;
    const visited = try allocator.alloc(bool, image.blocks.len);
    @memset(visited, false);
    var cursor = function.entry;
    while (!visited[@intCast(cursor)]) {
        visited[@intCast(cursor)] = true;
        const block = image.blocks[@intCast(cursor)];
        const slots = try allocator.alloc(p.Id, mapping.len + block.instructions.len);
        @memcpy(slots[0..mapping.len], mapping);
        for (block.instructions, 0..) |operation, index| {
            if (!direct.instruction(operation)) return null;
            const operands = try allocator.alloc(p.Id, operation.operands.len);
            for (operands, operation.operands) |*operand, source| {
                operand.* = slots[@intCast(source)];
                if (operand.* == ghost) return null;
            }
            var emitted = operation;
            emitted.operands = operands;
            slots[mapping.len + index] = arity + instructions.items.len;
            try instructions.append(allocator, emitted);
        }
        switch (block.terminator) {
            .jump => |edge| {
                mapping = try allocator.alloc(p.Id, edge.arguments.len);
                for (mapping, edge.arguments) |*slot, arg| slot.* = slots[@intCast(arg.slot)];
                cursor = edge.block;
            },
            .resume_value => |resuming| {
                if (slots[@intCast(resuming.resumption)] != ghost or slots[@intCast(resuming.argument)] == ghost or !try returnsResult(allocator, image, resuming.next)) return null;
                return .{ .instructions = instructions.items, .result = slots[@intCast(resuming.argument)] };
            },
            else => return null,
        }
    }
    return null;
}

fn returnsResult(allocator: std.mem.Allocator, image: p.Program, next: p.Edge) std.mem.Allocator.Error!bool {
    var values = try allocator.alloc(bool, next.arguments.len);
    for (values, next.arguments) |*value, argument| value.* = argument == .returned;
    const visited = try allocator.alloc(bool, image.blocks.len);
    @memset(visited, false);
    var cursor = next.block;
    while (!visited[@intCast(cursor)]) {
        visited[@intCast(cursor)] = true;
        const block = image.blocks[@intCast(cursor)];
        if (block.instructions.len != 0) return false;
        switch (block.terminator) {
            .return_value => |slot| return values[@intCast(slot)],
            .jump => |edge| {
                const successor = try allocator.alloc(bool, edge.arguments.len);
                for (successor, edge.arguments) |*value, argument| value.* = values[@intCast(argument.slot)];
                values = successor;
                cursor = edge.block;
            },
            else => return false,
        }
    }
    return false;
}
