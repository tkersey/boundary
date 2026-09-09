// Copyright (c) 2026 Boundary contributors. MIT license.
//! Keep active owners in lexical unwind order at every instruction boundary.
//! Scope depths are compiler metadata; ordinary block edges realize the order.
const std = @import("std");
const data = @import("boundary_data_v2");
const p = data.program;
const Error = @import("../source.zig").Error;
const missing = std.math.maxInt(p.Id);
pub const Scope = struct { depth: usize, parameters: []const usize };
pub const Blocks = std.AutoHashMapUnmanaged(p.Id, Scope);

pub fn normalize(
    a: std.mem.Allocator,
    program: p.Program,
    scopes: Blocks,
    traits: data.traits.Facts,
) Error!p.Program {
    // At most one entry split and one split per owned instruction result. Each
    // edge carries only live slots from that original block; no graph unrolling.
    var blocks: std.ArrayList(p.Block) = .empty;
    try blocks.appendSlice(a, program.blocks);
    for (program.blocks, 0..) |block, id| {
        const scope = scopes.get(id).?;
        std.debug.assert(scope.parameters.len == block.parameters.len);
        var previous: usize = std.math.maxInt(usize);
        var unordered = false;
        var outer = false;
        for (block.parameters, scope.parameters) |schema, depth| {
            if (traits.drop[@intCast(schema)]) continue;
            std.debug.assert(depth <= scope.depth);
            unordered = unordered or depth > previous;
            outer = outer or depth < scope.depth;
            previous = depth;
        }
        if (!unordered and !outer) continue;
        var rewrite = try Rewrite.init(a, &blocks, block, id, scope, traits);
        if (unordered) try rewrite.split(block.parameters.len);
        for (block.instructions, 0..) |operation, index| {
            const slot = block.parameters.len + index;
            var emitted = operation;
            emitted.operands = try rewrite.mapper.ids(operation.operands);
            rewrite.mapping[slot] = rewrite.parameters.len + rewrite.instructions.items.len;
            try rewrite.instructions.append(a, emitted);
            if (!operation.opcode.borrowsOperands()) {
                for (operation.operands) |operand| {
                    if (!traits.copy[@intCast(rewrite.types[@intCast(operand)])])
                        rewrite.alive[@intCast(operand)] = false;
                }
            }
            rewrite.alive[slot] = true;
            if (!traits.drop[@intCast(operation.result_type)]) {
                for (0..slot) |prior| {
                    if (rewrite.alive[prior] and !traits.drop[@intCast(rewrite.types[prior])] and
                        rewrite.depths[prior] < scope.depth)
                    {
                        try rewrite.split(slot + 1);
                        break;
                    }
                }
            }
        }
        rewrite.finish(try rewrite.mapper.term(block.terminator));
    }
    var result = program;
    result.blocks = blocks.items;
    return result;
}

const Rewrite = struct {
    a: std.mem.Allocator,
    blocks: *std.ArrayList(p.Block),
    original: p.Block,
    current: p.Id,
    traits: data.traits.Facts,
    types: []p.Id,
    depths: []usize,
    alive: []bool,
    mapping: []p.Id,
    last_use: []usize,
    mapper: Mapper,
    parameters: []const p.Id,
    instructions: std.ArrayList(p.Instruction) = .empty,

    fn init(
        a: std.mem.Allocator,
        blocks: *std.ArrayList(p.Block),
        block: p.Block,
        id: p.Id,
        scope: Scope,
        traits: data.traits.Facts,
    ) Error!Rewrite {
        const count = block.parameters.len + block.instructions.len;
        const types = try a.alloc(p.Id, count);
        const depths = try a.alloc(usize, count);
        const alive = try a.alloc(bool, count);
        const mapping = try a.alloc(p.Id, count);
        const last_use = try a.alloc(usize, count);
        @memcpy(types[0..block.parameters.len], block.parameters);
        @memcpy(depths[0..block.parameters.len], scope.parameters);
        @memset(depths[block.parameters.len..], scope.depth);
        @memset(alive, false);
        @memset(alive[0..block.parameters.len], true);
        @memset(last_use, 0);
        for (mapping, 0..) |*slot, index| slot.* = index;
        for (block.instructions, 0..) |operation, index| {
            const position = block.parameters.len + index;
            types[position] = operation.result_type;
            for (operation.operands) |operand| last_use[@intCast(operand)] = position;
        }
        const observer: Mapper = .{ .a = a, .mapping = mapping, .last_use = last_use };
        _ = try observer.term(block.terminator);
        return .{
            .a = a,
            .blocks = blocks,
            .original = block,
            .current = id,
            .traits = traits,
            .types = types,
            .depths = depths,
            .alive = alive,
            .mapping = mapping,
            .last_use = last_use,
            .mapper = .{ .a = a, .mapping = mapping },
            .parameters = block.parameters,
        };
    }
    fn before(self: Rewrite, left: p.Id, right: p.Id) bool {
        const left_owned = !self.traits.drop[@intCast(self.types[@intCast(left)])];
        const right_owned = !self.traits.drop[@intCast(self.types[@intCast(right)])];
        if (left_owned != right_owned) return left_owned;
        if (left_owned and self.depths[@intCast(left)] != self.depths[@intCast(right)])
            return self.depths[@intCast(left)] > self.depths[@intCast(right)];
        return left < right;
    }
    fn split(self: *Rewrite, end: usize) Error!void {
        var order: std.ArrayList(p.Id) = .empty;
        for (0..end) |slot| {
            if (!self.alive[slot]) continue;
            if (self.traits.drop[@intCast(self.types[slot])] and self.last_use[slot] < end)
                continue;
            try order.append(self.a, slot);
        }
        std.mem.sort(p.Id, order.items, self.*, before);
        const parameters = try self.a.alloc(p.Id, order.items.len);
        const arguments = try self.a.alloc(p.Argument, order.items.len);
        for (order.items, parameters, arguments) |slot, *schema, *argument| {
            schema.* = self.types[@intCast(slot)];
            argument.* = .{ .slot = self.mapping[@intCast(slot)] };
        }
        const next = self.blocks.items.len;
        self.finish(.{ .jump = .{ .block = next, .arguments = arguments } });
        try self.blocks.append(self.a, self.original);
        self.current = next;
        self.parameters = parameters;
        self.instructions = .empty;
        @memset(self.mapping[0..end], missing);
        for (order.items, 0..) |slot, index| self.mapping[@intCast(slot)] = index;
    }
    fn finish(self: Rewrite, term: p.Terminator) void {
        self.blocks.items[@intCast(self.current)] = .{
            .function = self.original.function,
            .parameters = self.parameters,
            .instructions = self.instructions.items,
            .terminator = term,
        };
    }
};

const Mapper = struct {
    a: std.mem.Allocator,
    mapping: []p.Id,
    last_use: ?[]usize = null,

    fn slot(self: Mapper, value: p.Id) p.Id {
        std.debug.assert(value < self.mapping.len);
        std.debug.assert(self.mapping[@intCast(value)] != missing);
        if (self.last_use) |uses| uses[@intCast(value)] = self.mapping.len;
        return self.mapping[@intCast(value)];
    }
    fn ids(self: Mapper, input: []const p.Id) Error![]const p.Id {
        const result = try self.a.alloc(p.Id, input.len);
        for (result, input) |*to, from| to.* = self.slot(from);
        return result;
    }
    fn edge(self: Mapper, input: p.Edge) Error!p.Edge {
        const arguments = try self.a.alloc(p.Argument, input.arguments.len);
        for (arguments, input.arguments) |*to, from| to.* = switch (from) {
            .slot => |value| .{ .slot = self.slot(value) },
            .returned => .returned,
        };
        return .{ .block = input.block, .arguments = arguments };
    }
    fn term(self: Mapper, input: p.Terminator) Error!p.Terminator {
        return switch (input) {
            inline .return_value, .fail => |value, kind| blk: {
                break :blk @unionInit(p.Terminator, @tagName(kind), self.slot(value));
            },
            inline .jump, .yield_value => |value, kind| blk: {
                break :blk @unionInit(p.Terminator, @tagName(kind), try self.edge(value));
            },
            .branch => |branch| .{ .branch = .{
                .condition = self.slot(branch.condition),
                .when_true = try self.edge(branch.when_true),
                .when_false = try self.edge(branch.when_false),
            } },
            .switch_variant => |selected| blk: {
                const cases = try self.a.alloc(p.Edge, selected.cases.len);
                for (cases, selected.cases) |*to, from| to.* = try self.edge(from);
                break :blk .{ .switch_variant = .{
                    .value = self.slot(selected.value),
                    .cases = cases,
                } };
            },
            .unpack_product => |unpack| .{ .unpack_product = .{
                .value = self.slot(unpack.value),
                .block = unpack.block,
                .arguments = try self.ids(unpack.arguments),
            } },
            inline .call,
            .perform,
            .apply,
            .handle,
            .resume_value,
            .resume_with,
            .resume_computation,
            .dispose,
            .protect,
            .with_region,
            => |operation, kind| blk: {
                break :blk @unionInit(p.Terminator, @tagName(kind), try self.control(operation));
            },
            .forward => return error.InvalidSource,
        };
    }
    fn control(self: Mapper, operation: anytype) Error!@TypeOf(operation) {
        @setEvalBranchQuota(4000); // Exhaustive fields of the finite terminator union.
        var result = operation;
        result.next = try self.edge(operation.next);
        inline for (@typeInfo(@TypeOf(operation)).@"struct".fields) |field| {
            if (comptime @import("retain.zig").isOperand(field.name)) {
                @field(result, field.name) = switch (field.type) {
                    p.Id => self.slot(@field(operation, field.name)),
                    ?p.Id => if (@field(operation, field.name)) |v| self.slot(v) else null,
                    []const p.Id => try self.ids(@field(operation, field.name)),
                    else => @compileError("classify the new operand type"),
                };
            } else if (comptime !std.mem.eql(u8, field.name, "next") and
                !std.mem.eql(u8, field.name, "function") and
                !std.mem.eql(u8, field.name, "handler") and
                !std.mem.eql(u8, field.name, "effect") and
                !std.mem.eql(u8, field.name, "region") and
                !std.mem.eql(u8, field.name, "loan_region"))
                @compileError("classify the new terminator field");
        }
        return result;
    }
};
