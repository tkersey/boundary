// Copyright (c) 2026 Boundary contributors. MIT license.
//! Temporary stable-slot definition facts. Incoming values are unknown; a
//! definition never means a slot keeps that value after a later assignment.
const std = @import("std");
const ir = @import("activation.zig");
const p = @import("program.zig");
const image = @import("program_image.zig");
const ownership = @import("activation_ownership.zig");
pub const Error = ownership.Error || image.Error || error{StaleFacts};
pub const Version = usize;
pub const Value = struct {
    boolean: ?bool = null,
    unsigned: ?u64 = null,
    constructor: ?p.Id = null,
    constructors_known: bool = false,
    constructors: [4]p.Id = @splat(0),
    constructor_count: u3 = 0,
    /// The producing computation instruction, not an opaque environment projection.
    construction: ?usize = null,
    maximum: ?u64 = null,
    known_zero: u64 = 0,
    known_one: u64 = 0,
    length: ?u64 = null,
    length_bound: ?u64 = null,
};
pub const Definition = struct {
    slot: p.Id,
    instruction: ?usize,
    operands: []const Version,
    value: Value,
};
pub const Block = struct {
    reachable: bool,
    definitions: []const Definition,
    /// Version before each instruction's write, and at the terminator.
    results: []const Version,
    exit: []const Version,
};
pub const Facts = struct {
    arena: std.heap.ArenaAllocator,
    epoch: [32]u8,
    blocks: []const Block,
    transfers: usize,
    block_visits: usize,
    pub fn deinit(self: *Facts) void {
        self.arena.deinit();
        self.* = undefined;
    }
    pub fn requireEpoch(self: *const Facts, allocator: std.mem.Allocator, program: ir.Program) Error!void {
        if (!std.mem.eql(u8, &self.epoch, &try image.identity(allocator, program))) return error.StaleFacts;
    }
};

/// Admission runs before facts can hide an originally invalid instruction.
/// Function entries are open-world roots. Edges transfer predecessor values
/// simultaneously; joins only lose precision and constructor sets widen to top.
pub fn analyze(allocator: std.mem.Allocator, program: ir.Program) Error!Facts {
    var checked = try ownership.analyze(allocator, program);
    defer checked.deinit();
    const epoch = try image.identity(allocator, program);
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const a = arena.allocator();
    const work = try a.alloc(Working, program.blocks.len);
    for (program.blocks, work) |block, *out| {
        const layout = program.functions[@intCast(block.function)].layout.slots;
        const versions = try a.alloc(Version, layout.len);
        const definitions = try a.alloc(Definition, layout.len + block.instructions.len);
        for (layout, versions, 0..) |schema, *version, slot| {
            version.* = slot;
            definitions[slot] = .{ .slot = slot, .instruction = null, .operands = &.{}, .value = bounds(program.schemas[@intCast(schema)]) };
        }
        const results = try a.alloc(Version, block.instructions.len);
        for (block.instructions, results, 0..) |instruction, *result, index| {
            const operands = try a.alloc(Version, instruction.operands.len);
            for (instruction.operands, operands) |slot, *version| version.* = versions[@intCast(slot)];
            result.* = layout.len + index;
            definitions[result.*] = .{ .slot = instruction.destination, .instruction = index, .operands = operands, .value = .{} };
            versions[@intCast(instruction.destination)] = result.*;
        }
        out.* = .{ .definitions = definitions, .results = results, .exit = versions, .outgoing = try a.alloc(Value, layout.len) };
    }
    // Every function can initially receive unknown arguments. Interprocedural
    // specialization must supply a separate checked calling-context contract.
    var queue: std.ArrayList(usize) = .empty;
    const queued = try a.alloc(bool, work.len);
    @memset(queued, false);
    for (program.functions) |function| {
        const entry: usize = @intCast(function.entry);
        work[entry].reachable = true;
        if (!queued[entry]) {
            try queue.append(a, entry);
            queued[entry] = true;
        }
    }
    var transfers: usize = 0;
    var visits: usize = 0;
    var head: usize = 0;
    while (head < queue.items.len) {
        const id = queue.items[head];
        head += 1;
        queued[id] = false;
        const block = program.blocks[id];
        const state = &work[id];
        visits += 1;
        const layout = program.functions[@intCast(block.function)].layout.slots;
        for (block.instructions, state.results, 0..) |instruction, version, index| {
            state.definitions[version].value = transfer(program, layout[@intCast(instruction.destination)], instruction, state.definitions[version].operands, state.definitions, index);
            transfers += 1;
        }
        for (state.exit, state.outgoing) |version, *value| value.* = state.definitions[version].value;
        var propagation: Propagation = .{ .program = program, .work = work, .source = state, .allocator = a, .queue = &queue, .queued = queued };
        try propagation.terminator(block.terminator);
    }
    const blocks = try a.alloc(Block, work.len);
    for (work, blocks) |state, *out| out.* = .{ .reachable = state.reachable, .definitions = state.definitions, .results = state.results, .exit = state.exit };
    return .{ .arena = arena, .epoch = epoch, .blocks = blocks, .transfers = transfers, .block_visits = visits };
}
const Working = struct {
    reachable: bool = false,
    outgoing: []Value,
    definitions: []Definition,
    results: []const Version,
    exit: []const Version,
};
fn forgetOrigin(value: Value) Value {
    var result = value;
    result.construction = null;
    return result;
}
fn maximum(left: ?u64, right: ?u64) ?u64 {
    return if (left != null and right != null) @max(left.?, right.?) else null;
}
fn joined(left: Value, right: Value) Value {
    var result: Value = .{
        .boolean = if (left.boolean == right.boolean) left.boolean else null,
        .unsigned = if (left.unsigned == right.unsigned) left.unsigned else null,
        .maximum = maximum(left.maximum, right.maximum),
        .known_zero = left.known_zero & right.known_zero,
        .known_one = left.known_one & right.known_one,
        .length = if (left.length == right.length) left.length else null,
        .length_bound = maximum(left.length_bound, right.length_bound),
    };
    if (left.constructors_known and right.constructors_known) {
        result.constructors_known = true;
        for ([_]Value{ left, right }) |value| for (value.constructors[0..value.constructor_count]) |id| {
            if (std.mem.indexOfScalar(p.Id, result.constructors[0..result.constructor_count], id) != null) continue;
            if (result.constructor_count == result.constructors.len) {
                result.constructors_known = false;
                result.constructor_count = 0;
                result.constructors = @splat(0);
                return result;
            }
            result.constructors[result.constructor_count] = id;
            result.constructor_count += 1;
        };
        std.mem.sort(p.Id, result.constructors[0..result.constructor_count], {}, std.sort.asc(p.Id));
        if (result.constructor_count == 1) result.constructor = result.constructors[0];
    }
    return result;
}
const Propagation = struct {
    program: ir.Program,
    work: []Working,
    source: *const Working,
    allocator: std.mem.Allocator,
    queue: *std.ArrayList(usize),
    queued: []bool,
    fn value(self: Propagation, slot: p.Id) Value {
        return self.source.outgoing[@intCast(slot)];
    }
    fn edge(self: Propagation, next: ir.Edge, overwritten: []const p.Id) std.mem.Allocator.Error!void {
        const target = &self.work[@intCast(next.block)];
        var changed = !target.reachable;
        const layout = self.program.functions[@intCast(self.program.blocks[@intCast(next.block)].function)].layout.slots;
        // Read only source exit versions. No assignment can see an earlier
        // destination write from this same parallel edge.
        for (layout, 0..) |schema, slot| {
            var incoming = if (std.mem.indexOfScalar(p.Id, overwritten, slot) != null) bounds(self.program.schemas[@intCast(schema)]) else self.value(slot);
            for (next.assignments) |assignment| if (assignment.destination == slot) {
                incoming = switch (assignment.source) {
                    .returned => bounds(self.program.schemas[@intCast(schema)]),
                    .slot => |origin| if (std.mem.indexOfScalar(p.Id, overwritten, origin) != null) bounds(self.program.schemas[@intCast(schema)]) else self.value(origin),
                };
            };
            incoming = forgetOrigin(incoming);
            const merged = if (target.reachable) joined(target.definitions[slot].value, incoming) else incoming;
            if (!std.meta.eql(target.definitions[slot].value, merged)) {
                target.definitions[slot].value = merged;
                changed = true;
            }
        }
        target.reachable = true;
        if (changed and !self.queued[@intCast(next.block)]) {
            try self.queue.append(self.allocator, @intCast(next.block));
            self.queued[@intCast(next.block)] = true;
        }
    }
    fn terminator(self: *Propagation, term: ir.Terminator) std.mem.Allocator.Error!void {
        switch (term) {
            .return_value, .fail => {},
            .jump, .yield_value => |next| try self.edge(next, &.{}),
            .branch => |v| if (self.value(v.condition).boolean) |condition| {
                try self.edge(if (condition) v.when_true else v.when_false, &.{});
            } else {
                try self.edge(v.when_true, &.{});
                try self.edge(v.when_false, &.{});
            },
            .switch_variant => |v| for (v.cases) |next| try self.edge(next, &.{}),
            .unpack_product => |v| try self.edge(v.next, v.destinations),
            inline else => |v| try self.edge(v.next, &.{}),
        }
    }
};
fn bounds(schema: p.Schema) Value {
    return switch (schema) {
        .u8 => .{ .maximum = 255, .known_zero = ~@as(u64, 255) },
        .u16 => .{ .maximum = 65535, .known_zero = ~@as(u64, 65535) },
        .u32 => .{ .maximum = 4294967295, .known_zero = ~@as(u64, 4294967295) },
        .u64 => .{ .maximum = std.math.maxInt(u64) },
        .array => |v| .{ .length = v.length, .length_bound = v.length },
        .vector => |v| .{ .length_bound = v.maximum },
        else => .{},
    };
}
fn number(value: u64) Value {
    return .{ .unsigned = value, .maximum = value, .known_zero = ~value, .known_one = value };
}
fn transfer(program: ir.Program, schema: p.Id, instruction: ir.Instruction, operands: []const Version, definitions: []const Definition, index: usize) Value {
    const result = bounds(program.schemas[@intCast(schema)]);
    const left: Value = if (operands.len > 0) definitions[operands[0]].value else .{};
    const right: Value = if (operands.len > 1) definitions[operands[1]].value else .{};
    return switch (instruction.opcode) {
        .constant => blk: {
            const literal = program.constants[@intCast(instruction.immediate)];
            break :blk switch (program.schemas[@intCast(literal.schema)]) {
                .boolean => .{ .boolean = literal.bytes[0] == 1 },
                .u8 => number(literal.bytes[0]),
                .u16 => number(std.mem.readInt(u16, literal.bytes[0..2], .little)),
                .u32 => number(std.mem.readInt(u32, literal.bytes[0..4], .little)),
                .u64 => number(std.mem.readInt(u64, literal.bytes[0..8], .little)),
                else => result,
            };
        },
        .move => left,
        .computation => .{ .constructor = instruction.immediate, .construction = index, .constructors_known = true, .constructors = .{ instruction.immediate, 0, 0, 0 }, .constructor_count = 1 },
        .boolean_not => if (left.boolean) |v| .{ .boolean = !v } else result,
        .equal => if (left.unsigned != null and right.unsigned != null) .{ .boolean = left.unsigned.? == right.unsigned.? } else if (left.boolean != null and right.boolean != null) .{ .boolean = left.boolean.? == right.boolean.? } else result,
        .less => if (left.unsigned != null and right.unsigned != null) .{ .boolean = left.unsigned.? < right.unsigned.? } else result,
        .integer_bit_and => blk: {
            if (result.maximum == null) break :blk result;
            if (left.unsigned != null and right.unsigned != null) break :blk number(left.unsigned.? & right.unsigned.?);
            const mask = right.unsigned orelse left.unsigned orelse break :blk result;
            const other = if (right.unsigned != null) left else right;
            if (mask == 0) break :blk number(0);
            break :blk .{ .maximum = mask & ~other.known_zero, .known_zero = other.known_zero | ~mask, .known_one = other.known_one & mask };
        },
        .sequence => .{ .length = instruction.operands.len, .length_bound = result.length_bound },
        .sequence_length => if (left.length) |length| number(length) else .{ .maximum = left.length_bound },
        .select => if (left.boolean) |condition| definitions[operands[if (condition) 1 else 2]].value else joined(definitions[operands[1]].value, definitions[operands[2]].value),
        else => result,
    };
}

test "constructor-set precision cap widens to unknown rather than an empty set" {
    var value: Value = .{ .constructor = 0, .constructors_known = true, .constructors = .{ 0, 0, 0, 0 }, .constructor_count = 1 };
    for (1..5) |id| value = joined(value, .{ .constructor = id, .constructors_known = true, .constructors = .{ id, 0, 0, 0 }, .constructor_count = 1 });
    try std.testing.expect(!value.constructors_known);
    try std.testing.expectEqual(@as(?p.Id, null), value.constructor);
    try std.testing.expectEqual(@as(u3, 0), value.constructor_count);
}
