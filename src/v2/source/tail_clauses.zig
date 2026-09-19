// Copyright (c) 2026 Boundary contributors. MIT license.
//! Select total tail resumptions without changing general callable functions.
const std = @import("std");
const data = @import("boundary_data");
const p = data.program;
const ir = data.activation;
const total = data.total_clause;
const Error = std.mem.Allocator.Error;

pub fn optimize(a: std.mem.Allocator, input: ir.Program, uses: data.traits.Facts) Error!ir.Program {
    var functions: std.ArrayList(ir.Function) = .empty;
    var blocks: std.ArrayList(ir.Block) = .empty;
    try functions.appendSlice(a, input.functions);
    try blocks.appendSlice(a, input.blocks);
    const handlers = try a.dupe(ir.Handler, input.handlers);
    var memo: std.AutoHashMapUnmanaged(p.Id, ?p.Id) = .empty;
    for (handlers) |*handler| {
        const clauses = try a.dupe(ir.Clause, handler.clauses);
        handler.clauses = clauses;
        for (clauses) |*clause| {
            if (!eligible(input, handler.*, clause.*)) continue;
            const lookup = try memo.getOrPut(a, clause.function);
            if (!lookup.found_existing) lookup.value_ptr.* = try specialize(a, input, clause.*, uses, &functions, &blocks);
            if (lookup.value_ptr.*) |id| {
                clause.function = id;
                clause.strategy = .tail;
            }
        }
    }
    var result = input;
    result.functions = functions.items;
    result.blocks = blocks.items;
    result.handlers = handlers;
    return result;
}

fn eligible(image: ir.Program, handler: ir.Handler, clause: ir.Clause) bool {
    if (handler.mode != .deep or clause.strategy != .general or
        clause.effect >= image.effects.len or clause.function >= image.functions.len or
        clause.resumption >= image.schemas.len) return false;
    const schema = image.schemas[@intCast(clause.resumption)];
    if (schema != .internal or schema.internal != .resumption or
        schema.internal.resumption.use != .linear) return false;
    const function = image.functions[@intCast(clause.function)];
    if (function.entry >= image.blocks.len or
        function.inputs.len != handler.state.len + 2 or
        function.result != handler.answer or
        image.effects[@intCast(clause.effect)].bodies.len != 0) return false;
    for (function.effects) |effect| if (std.mem.indexOfScalar(p.Id, handler.effects, effect) == null)
        return false;
    for (handler.state, function.inputs[0..handler.state.len]) |schema_id, slot|
        if (function.layout.slots[@intCast(slot)] != schema_id) return false;
    if (function.layout.slots[@intCast(function.inputs[handler.state.len])] !=
        image.effects[@intCast(clause.effect)].payload) return false;
    return function.layout.slots[@intCast(function.inputs[function.inputs.len - 1])] ==
        clause.resumption;
}

fn specialize(
    a: std.mem.Allocator,
    image: ir.Program,
    clause: ir.Clause,
    uses: data.traits.Facts,
    functions: *std.ArrayList(ir.Function),
    blocks: *std.ArrayList(ir.Block),
) Error!?p.Id {
    const original = image.functions[@intCast(clause.function)];
    const token = original.inputs[original.inputs.len - 1];
    for (original.layout.slots, 0..) |schema, slot| {
        if (slot != token and !uses.copy[@intCast(schema)]) return null;
    }
    var ids: std.ArrayList(p.Id) = .empty;
    var mapping: std.AutoHashMapUnmanaged(p.Id, p.Id) = .empty;
    try add(a, &ids, &mapping, original.entry, blocks.items.len);
    var cursor: usize = 0;
    while (cursor < ids.items.len) : (cursor += 1) {
        const block = image.blocks[@intCast(ids.items[cursor])];
        for (block.instructions) |operation| {
            if (!total.instruction(operation) or operation.destination == token) return null;
            for (operation.operands) |slot| if (slot == token) return null;
        }
        if (!try discover(a, image, block, token, &ids, &mapping, blocks.items.len)) return null;
    }
    const function_id = functions.items.len;
    const block_start = blocks.items.len;
    for (ids.items) |id| {
        var block = image.blocks[@intCast(id)];
        block.function = function_id;
        block.terminator = try remap(a, block.terminator, &mapping);
        try blocks.append(a, block);
    }
    const slots = try a.dupe(p.Id, original.layout.slots);
    slots[@intCast(token)] = image.effects[@intCast(clause.effect)].payload;
    var function = original;
    function.inputs = original.inputs[0 .. original.inputs.len - 1];
    function.entry = mapping.get(original.entry).?;
    function.layout.slots = slots;
    function.result = image.effects[@intCast(clause.effect)].result;
    // The original row includes effects performed by the resumed body. The
    // selected CFG contains only total local operations and ordinary returns.
    function.effects = &.{};
    try functions.append(a, function);
    var candidate = image;
    candidate.functions = functions.items;
    candidate.blocks = blocks.items;
    total.validate(a, candidate, function_id, uses) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        functions.items.len = function_id;
        blocks.items.len = block_start;
        return null;
    };
    return function_id;
}

fn add(
    a: std.mem.Allocator,
    ids: *std.ArrayList(p.Id),
    mapping: *std.AutoHashMapUnmanaged(p.Id, p.Id),
    id: p.Id,
    base: usize,
) Error!void {
    const entry = try mapping.getOrPut(a, id);
    if (entry.found_existing) return;
    entry.value_ptr.* = base + ids.items.len;
    try ids.append(a, id);
}

fn follow(
    a: std.mem.Allocator,
    ids: *std.ArrayList(p.Id),
    mapping: *std.AutoHashMapUnmanaged(p.Id, p.Id),
    edge: ir.Edge,
    token: p.Id,
    base: usize,
) Error!bool {
    for (edge.assignments) |assignment| {
        if (assignment.destination == token or assignment.source != .slot or
            assignment.source.slot == token) return false;
    }
    try add(a, ids, mapping, edge.block, base);
    return true;
}

fn discover(
    a: std.mem.Allocator,
    image: ir.Program,
    block: ir.Block,
    token: p.Id,
    ids: *std.ArrayList(p.Id),
    mapping: *std.AutoHashMapUnmanaged(p.Id, p.Id),
    base: usize,
) Error!bool {
    return switch (block.terminator) {
        .jump => |v| follow(a, ids, mapping, v, token, base),
        .branch => |v| v.condition != token and
            try follow(a, ids, mapping, v.when_true, token, base) and
            try follow(a, ids, mapping, v.when_false, token, base),
        .switch_variant => |v| blk: {
            if (v.value == token) break :blk false;
            for (v.cases) |edge| if (!try follow(a, ids, mapping, edge, token, base))
                break :blk false;
            break :blk true;
        },
        .unpack_product => |v| blk: {
            if (v.value == token) break :blk false;
            for (v.destinations) |slot| if (slot == token) break :blk false;
            break :blk try follow(a, ids, mapping, v.next, token, base);
        },
        .resume_value => |v| v.resumption == token and v.argument != token and
            returnsResult(image, block.function, v.next),
        else => false,
    };
}

fn returnsResult(image: ir.Program, function: p.Id, edge: ir.Edge) bool {
    const target = image.blocks[@intCast(edge.block)];
    if (target.function != function or target.instructions.len != 0 or
        target.terminator != .return_value or edge.assignments.len != 1) return false;
    return edge.assignments[0].source == .returned and
        edge.assignments[0].destination == target.terminator.return_value;
}

fn remapEdge(value: ir.Edge, mapping: *const std.AutoHashMapUnmanaged(p.Id, p.Id)) ir.Edge {
    var result = value;
    result.block = mapping.get(value.block).?;
    return result;
}

fn remap(
    a: std.mem.Allocator,
    value: ir.Terminator,
    mapping: *const std.AutoHashMapUnmanaged(p.Id, p.Id),
) Error!ir.Terminator {
    return switch (value) {
        .jump => |v| .{ .jump = remapEdge(v, mapping) },
        .branch => |v| .{ .branch = .{ .condition = v.condition, .when_true = remapEdge(v.when_true, mapping), .when_false = remapEdge(v.when_false, mapping) } },
        .resume_value => |v| .{ .return_value = v.argument },
        .switch_variant => |v| blk: {
            const cases = try a.alloc(ir.Edge, v.cases.len);
            for (cases, v.cases) |*target, original| target.* = remapEdge(original, mapping);
            break :blk .{ .switch_variant = .{ .value = v.value, .cases = cases } };
        },
        .unpack_product => |v| .{ .unpack_product = .{ .value = v.value, .destinations = v.destinations, .next = remapEdge(v.next, mapping) } },
        // discover rejects every other terminator before any copying starts.
        else => unreachable,
    };
}
