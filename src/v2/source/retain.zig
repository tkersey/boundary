// Copyright (c) 2026 Boundary contributors. MIT license.
//! Retain an owner at its position among the successor's existing owners.
//! Failure unwinds it; an ordinary return still exposes an illegal discard.
const std = @import("std");
const p = @import("boundary_data_v2").program;
const Error = @import("../source.zig").Error;
const custody = @import("custody.zig");
const Placement = struct { block: p.Id, position: usize, depth: usize };
const Ids = std.AutoHashMapUnmanaged(Placement, p.Id);
pub const Scopes = std.AutoHashMapUnmanaged(p.Id, usize);

pub fn throughGraph(allocator: std.mem.Allocator, blocks: *std.ArrayList(p.Block), scopes: *Scopes, owners: *custody.Blocks, root: p.Id, schema: p.Id, position: usize, depth: usize) Error!p.Id {
    var ids: Ids = .empty;
    var pending: std.ArrayList(Placement) = .empty;
    const start = placement(root, position, depth, owners.*);
    try ids.put(allocator, start, blocks.items.len);
    try pending.append(allocator, start);
    var index: usize = 0;
    while (index < pending.items.len) : (index += 1) {
        const current = pending.items[index];
        const original = blocks.items[@intCast(current.block)];
        std.debug.assert(current.position <= original.parameters.len);
        const arity = original.parameters.len;
        var next: std.ArrayList(Placement) = .empty;
        switch (original.terminator) {
            .fail, .return_value => {},
            .jump, .yield_value => |edge| try next.append(allocator, successor(edge, arity, current.position, scopes.*, current.depth, owners.*)),
            .branch => |branch| {
                try next.append(allocator, successor(branch.when_true, arity, current.position, scopes.*, current.depth, owners.*));
                try next.append(allocator, successor(branch.when_false, arity, current.position, scopes.*, current.depth, owners.*));
            },
            .switch_variant => |selected| for (selected.cases) |edge| try next.append(allocator, successor(edge, arity, current.position, scopes.*, current.depth, owners.*)),
            .unpack_product => |unpack| try next.append(allocator, unpackSuccessor(blocks.items, unpack, arity, current.position, current.depth, owners.*)),
            inline .call, .perform, .apply, .handle, .resume_value, .resume_with, .resume_computation, .dispose, .protect, .with_region => |operation| try next.append(allocator, successor(operation.next, arity, current.position, scopes.*, current.depth, owners.*)),
            .forward => return error.InvalidSource,
        }
        for (next.items) |child| if (!ids.contains(child)) {
            try ids.put(allocator, child, blocks.items.len + pending.items.len);
            try pending.append(allocator, child);
        };
    }
    const first = blocks.items.len;
    for (pending.items) |current| {
        const original = blocks.items[@intCast(current.block)];
        const parameters = try allocator.alloc(p.Id, original.parameters.len + 1);
        @memcpy(parameters[0..current.position], original.parameters[0..current.position]);
        parameters[current.position] = schema;
        @memcpy(parameters[current.position + 1 ..], original.parameters[current.position..]);
        const instructions = try allocator.dupe(p.Instruction, original.instructions);
        for (instructions) |*operation| operation.operands = try slots(allocator, operation.operands, current.position);
        const rewritten = try rewriteTerminator(allocator, blocks.items, original, current.position, ids, scopes.*, current.depth, owners.*);
        if (scopes.get(current.block)) |scoped| {
            try scopes.put(allocator, blocks.items.len, scoped + @intFromBool(scoped >= current.position));
        }
        const scope = owners.get(current.block).?;
        const depths = try allocator.alloc(usize, parameters.len);
        @memcpy(depths[0..current.position], scope.parameters[0..current.position]);
        depths[current.position] = current.depth;
        @memcpy(depths[current.position + 1 ..], scope.parameters[current.position..]);
        try owners.put(allocator, blocks.items.len, .{
            .depth = scope.depth,
            .parameters = depths,
        });
        try blocks.append(allocator, .{ .function = original.function, .parameters = parameters, .instructions = instructions, .terminator = rewritten });
    }
    return first;
}

fn successor(edge: p.Edge, arity: usize, position: usize, scopes: Scopes, depth: usize, owners: custody.Blocks) Placement {
    // Values introduced within this successor keep their local scope. Preserve
    // the retained owner's order relative to parameters that outlive this edge.
    for (edge.arguments, 0..) |argument, index| {
        if (scopes.get(edge.block)) |scoped| if (index <= scoped) continue;
        if (argument == .slot and argument.slot >= position and argument.slot < arity)
            return placement(edge.block, index, depth, owners);
    }
    return placement(edge.block, edge.arguments.len, depth, owners);
}

fn unpackSuccessor(blocks: []const p.Block, unpack: @FieldType(p.Terminator, "unpack_product"), arity: usize, position: usize, depth: usize, owners: custody.Blocks) Placement {
    const prefix = blocks[@intCast(unpack.block)].parameters.len - unpack.arguments.len;
    for (unpack.arguments, 0..) |argument, index| {
        if (argument >= position and argument < arity)
            return placement(unpack.block, prefix + index, depth, owners);
    }
    return placement(unpack.block, prefix + unpack.arguments.len, depth, owners);
}

fn rewriteTerminator(allocator: std.mem.Allocator, blocks: []const p.Block, original: p.Block, position: usize, ids: Ids, scopes: Scopes, depth: usize, owners: custody.Blocks) Error!p.Terminator {
    const arity = original.parameters.len;
    const term = original.terminator;
    return switch (term) {
        .fail => |value| .{ .fail = slot(value, position) },
        .return_value => |value| .{ .return_value = slot(value, position) },
        .jump, .yield_value => |target| if (term == .jump) .{ .jump = try rewriteEdge(allocator, target, arity, position, ids, scopes, depth, owners) } else .{ .yield_value = try rewriteEdge(allocator, target, arity, position, ids, scopes, depth, owners) },
        .branch => |branch| .{ .branch = .{ .condition = slot(branch.condition, position), .when_true = try rewriteEdge(allocator, branch.when_true, arity, position, ids, scopes, depth, owners), .when_false = try rewriteEdge(allocator, branch.when_false, arity, position, ids, scopes, depth, owners) } },
        .switch_variant => |selected| blk: {
            const cases = try allocator.alloc(p.Edge, selected.cases.len);
            for (cases, selected.cases) |*target, from| target.* = try rewriteEdge(allocator, from, arity, position, ids, scopes, depth, owners);
            break :blk .{ .switch_variant = .{ .value = slot(selected.value, position), .cases = cases } };
        },
        .unpack_product => |unpack| blk: {
            const target = unpackSuccessor(blocks, unpack, arity, position, depth, owners);
            const insertion = target.position - (blocks[@intCast(unpack.block)].parameters.len - unpack.arguments.len);
            const arguments = try allocator.alloc(p.Id, unpack.arguments.len + 1);
            for (unpack.arguments, 0..) |from, index| arguments[index + @intFromBool(index >= insertion)] = slot(from, position);
            arguments[insertion] = position;
            break :blk .{ .unpack_product = .{ .value = slot(unpack.value, position), .block = ids.get(target).?, .arguments = arguments } };
        },
        inline .call, .perform, .apply, .handle, .resume_value, .resume_with, .resume_computation, .dispose, .protect, .with_region => |operation, kind| blk: {
            var changed = operation;
            changed.next = try rewriteEdge(allocator, operation.next, arity, position, ids, scopes, depth, owners);
            inline for (@typeInfo(@TypeOf(operation)).@"struct".fields) |field| {
                if (comptime std.mem.eql(u8, field.name, "next") or std.mem.eql(u8, field.name, "function") or std.mem.eql(u8, field.name, "handler") or std.mem.eql(u8, field.name, "effect") or std.mem.eql(u8, field.name, "region") or std.mem.eql(u8, field.name, "loan_region")) continue;
                if (comptime !isOperand(field.name)) @compileError("classify the new terminator field before retaining custody");
                @field(changed, field.name) = switch (field.type) {
                    p.Id => slot(@field(operation, field.name), position),
                    ?p.Id => if (@field(operation, field.name)) |value| slot(value, position) else null,
                    []const p.Id => try slots(allocator, @field(operation, field.name), position),
                    else => @compileError("classify the new terminator field before retaining custody"),
                };
            }
            break :blk @unionInit(p.Terminator, @tagName(kind), changed);
        },
        .forward => return error.InvalidSource,
    };
}

pub fn isOperand(comptime name: []const u8) bool {
    const fields = [_][]const u8{ "arguments", "capability", "payload", "bodies", "use_site_capabilities", "computation", "body", "state", "resumption", "argument", "owned", "cleanup", "resource" };
    inline for (fields) |field| if (std.mem.eql(u8, name, field)) return true;
    return false;
}
fn slot(value: p.Id, position: usize) p.Id {
    return value + @intFromBool(value >= position);
}
fn slots(allocator: std.mem.Allocator, values: []const p.Id, position: usize) Error![]const p.Id {
    const output = try allocator.alloc(p.Id, values.len);
    for (output, values) |*to, from| to.* = slot(from, position);
    return output;
}
fn rewriteEdge(allocator: std.mem.Allocator, original: p.Edge, arity: usize, position: usize, ids: Ids, scopes: Scopes, depth: usize, owners: custody.Blocks) Error!p.Edge {
    const target = successor(original, arity, position, scopes, depth, owners);
    const arguments = try allocator.alloc(p.Argument, original.arguments.len + 1);
    for (original.arguments, 0..) |from, index| arguments[index + @intFromBool(index >= target.position)] = switch (from) {
        .slot => |value| .{ .slot = slot(value, position) },
        .returned => .returned,
    };
    arguments[target.position] = .{ .slot = position };
    return .{ .block = ids.get(target).?, .arguments = arguments };
}

fn placement(block: p.Id, position: usize, depth: usize, owners: custody.Blocks) Placement {
    return .{ .block = block, .position = position, .depth = @min(depth, owners.get(block).?.depth) };
}
