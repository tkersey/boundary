// Copyright (c) 2026 Boundary contributors. MIT license.
//! Build-time translation of admitted BPI1 into ordinary BPI2 instructions.
//! Constructor retention becomes block parameters; no legacy execution state
//! or instruction dispatch table survives in the resulting program.
const std = @import("std");
const data = @import("boundary_data_v2");
const legacy = @import("root.zig");
const p = data.program;
const Op = legacy.contract.WireOperation;
const Role = legacy.contract.FailureRole;

fn read(comptime T: type, bytes: []const u8, offset: usize) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}
fn edgeLength(bytes: []const u8) usize {
    return 4 + @as(usize, read(u16, bytes, 2)) * 4;
}
const OldEdge = struct { target: u16, arguments: []const p.Argument };
const Term = union(enum) {
    jump: OldEdge,
    branch: struct { condition: u16, yes: OldEdge, no: OldEdge },
    suspension: struct { kind: u8, effect: u32, payload: ?u16, callee: ?OldEdge, next: OldEdge },
    returned: ?u16,
    fail_tag: u32,
    fail_value: u16,
};
const Segment = struct {
    function: p.Id,
    parameters: []const u16,
    instructions: []const []const u8,
    terminator: Term,
    live: []bool,
    defined: []bool,
};

pub fn lift(allocator: std.mem.Allocator, bytes: []const u8) !data.canonical.Normalized {
    var decoded = try legacy.decode(allocator, bytes);
    defer decoded.deinit();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var converted = try legacy.types.schemas(arena.allocator(), decoded.program.catalogs.schemas);
    defer converted.deinit();
    var builder: Lift = .{ .allocator = arena.allocator(), .old = decoded.program };
    try builder.schemas.appendSlice(builder.allocator, converted.types);
    try builder.readCatalogs();
    try builder.findLive();
    const program = try builder.lower();
    return data.canonical.normalize(allocator, program);
}

const Lift = struct {
    allocator: std.mem.Allocator,
    old: legacy.image.ValidatedImage,
    schemas: std.ArrayList(p.Schema) = .empty,
    constants: std.ArrayList(p.Literal) = .empty,
    segments: []Segment = &.{},
    constant_values: []?p.Id = &.{},
    zero_values: []bool = &.{},
    effects: []p.Effect = &.{},
    functions: []p.Function = &.{},

    fn schema(self: *Lift, shape: p.Schema) !p.Id {
        // Scalar helpers are shared. Structured helper types are canonicalized
        // with the complete program after lowering.
        for (self.schemas.items, 0..) |candidate, index| {
            if (std.meta.activeTag(candidate) != std.meta.activeTag(shape)) continue;
            switch (shape) {
                .unit, .boolean, .u8, .u32, .u64, .i8, .bytes, .text => return index,
                else => {},
            }
        }
        const index = self.schemas.items.len;
        try self.schemas.append(self.allocator, shape);
        return index;
    }
    fn valueType(self: Lift, value: p.Id) !p.Id {
        return try self.old.catalogs.valueSchemaId(@intCast(value));
    }
    fn literal(self: *Lift, ty: p.Id, bytes: []const u8) !p.Id {
        for (self.constants.items, 0..) |constant, index| {
            if (constant.schema == ty and std.mem.eql(u8, constant.bytes, bytes)) return index;
        }
        const index = self.constants.items.len;
        try self.constants.append(self.allocator, .{ .schema = ty, .bytes = try self.allocator.dupe(u8, bytes) });
        return index;
    }
    fn readEdge(self: *Lift, bytes: []const u8) !OldEdge {
        const arguments = try self.allocator.alloc(p.Argument, read(u16, bytes, 2));
        for (arguments, 0..) |*argument, index| argument.* = if (bytes[4 + index * 4] == 1) .returned else .{ .slot = read(u16, bytes, 6 + index * 4) };
        return .{ .target = read(u16, bytes, 0), .arguments = arguments };
    }
    fn readTerm(self: *Lift, bytes: []const u8) !Term {
        const payload = bytes[8..];
        return switch (bytes[4]) {
            0 => .{ .jump = try self.readEdge(payload) },
            1 => .{ .branch = .{ .condition = read(u16, payload, 0), .yes = try self.readEdge(payload[4..]), .no = try self.readEdge(payload[4 + edgeLength(payload[4..]) ..]) } },
            2 => blk: {
                const request_count = read(u16, payload, 10);
                var cursor = 12 + @as(usize, request_count) * 2;
                const present = payload[cursor] == 1;
                cursor += 4;
                const callee = if (present) try self.readEdge(payload[cursor..]) else null;
                if (present) cursor += edgeLength(payload[cursor..]);
                break :blk .{ .suspension = .{ .kind = payload[0], .effect = read(u32, payload, 4), .payload = if (request_count == 1) read(u16, payload, 12) else null, .callee = callee, .next = try self.readEdge(payload[cursor..]) } };
            },
            3 => .{ .returned = if (payload[0] == 1) read(u16, payload, 2) else null },
            4 => .{ .returned = read(u16, payload, 0) },
            5 => .{ .fail_tag = read(u32, payload, 0) },
            6 => .{ .fail_value = read(u16, payload, 0) },
            else => error.InvalidTerminator,
        };
    }
    fn readCatalogs(self: *Lift) !void {
        const catalogs = self.old.catalogs;
        const constants = catalogs.envelope.section(.constants);
        var cursor: usize = 4;
        for (0..catalogs.constant_count) |_| {
            const ty = read(u32, constants, cursor);
            const count = read(u32, constants, cursor + 4);
            cursor += 8;
            const bytes = try legacy.types.toV2(self.allocator, catalogs.schemas, ty, constants[cursor..][0..count]);
            try self.constants.append(self.allocator, .{ .schema = ty, .bytes = bytes });
            cursor += count;
        }
        self.constant_values = try self.allocator.alloc(?p.Id, catalogs.value_count);
        @memset(self.constant_values, null);
        self.zero_values = try self.allocator.alloc(bool, catalogs.value_count);
        for (self.zero_values, 0..) |*zero, value| zero.* = (try catalogs.schemas.node(@intCast(try self.valueType(value)))).maximum_encoded_size == 0;
        self.segments = try self.allocator.alloc(Segment, self.old.segment_count);
        for (self.segments, 0..) |*segment, index| {
            const bytes = try legacy.image.evaluatorSegmentRecord(self.old, @intCast(index));
            const parameters = try self.allocator.alloc(u16, read(u16, bytes, 10));
            for (parameters, 0..) |*parameter, k| parameter.* = read(u16, bytes, 16 + k * 2);
            const instructions = try self.allocator.alloc([]const u8, read(u32, bytes, 12));
            cursor = 16 + parameters.len * 2;
            const defined = try self.allocator.alloc(bool, catalogs.value_count);
            @memset(defined, false);
            for (instructions) |*instruction| {
                const count = read(u32, bytes, cursor);
                instruction.* = bytes[cursor..][0..count];
                const result = read(u16, instruction.*, 8);
                defined[result] = true;
                if (read(u16, instruction.*, 6) == 0) self.constant_values[result] = read(u32, instruction.*, 12);
                cursor += count;
            }
            const live = try self.allocator.alloc(bool, catalogs.value_count);
            @memset(live, false);
            segment.* = .{ .function = read(u16, bytes, 6), .parameters = parameters, .instructions = instructions, .terminator = try self.readTerm(bytes[cursor..]), .live = live, .defined = defined };
        }
        self.effects = try self.allocator.alloc(p.Effect, catalogs.effect_count);
        for (self.effects, 0..) |*effect, index| {
            const descriptor = try legacy.image.evaluatorEffect(self.old, @intCast(index));
            effect.* = .{ .identity = descriptor.semantic_identity, .payload = descriptor.payload_schema, .result = descriptor.resume_schema };
        }
    }
    fn need(self: *Lift, segment: *Segment, value: p.Id) bool {
        const id: usize = @intCast(value);
        if (segment.defined[id] or self.constant_values[id] != null or self.zero_values[id] or segment.live[id]) return false;
        segment.live[id] = true;
        return true;
    }
    fn sourceArgument(self: Lift, edge: OldEdge, target_value: usize) p.Argument {
        for (self.segments[edge.target].parameters, 0..) |parameter, index| if (parameter == target_value) return edge.arguments[index];
        return .{ .slot = target_value };
    }
    fn propagate(self: *Lift, segment: *Segment, edge: OldEdge) bool {
        var changed = false;
        for (self.segments[edge.target].live, 0..) |live, value| {
            if (!live) continue;
            const source = self.sourceArgument(edge, value);
            if (source == .slot) changed = self.need(segment, source.slot) or changed;
        }
        return changed;
    }
    fn findLive(self: *Lift) !void {
        const entry = &self.segments[self.old.catalogs.entry_segment_id];
        // InitialArgs stays the same public value, including an unused argument.
        for (entry.parameters) |parameter| entry.live[parameter] = true;
        for (self.segments) |*segment| {
            for (segment.instructions) |instruction| {
                const op = std.enums.fromInt(Op, read(u16, instruction, 6)).?;
                const arity = legacy.contract.fixedOperandCount(op) orelse read(u16, instruction, 10);
                for (0..arity) |index| _ = self.need(segment, read(u16, instruction, 16 + index * 2));
            }
            switch (segment.terminator) {
                .branch => |branch| _ = self.need(segment, branch.condition),
                .suspension => |suspension| if (suspension.payload) |value| {
                    _ = self.need(segment, value);
                },
                .returned => |maybe| if (maybe) |value| {
                    _ = self.need(segment, value);
                },
                .fail_value => |value| _ = self.need(segment, value),
                else => {},
            }
        }
        var changed = true;
        while (changed) {
            changed = false;
            for (self.segments) |*segment| switch (segment.terminator) {
                .jump => |edge| changed = self.propagate(segment, edge) or changed,
                .branch => |branch| {
                    changed = self.propagate(segment, branch.yes) or changed;
                    changed = self.propagate(segment, branch.no) or changed;
                },
                .suspension => |suspension| {
                    if (suspension.callee) |callee| changed = self.propagate(segment, callee) or changed;
                    changed = self.propagate(segment, suspension.next) or changed;
                },
                else => {},
            };
        }
    }
    fn failure(self: *Lift, instruction: []const u8, role: Role) !p.Id {
        const op = std.enums.fromInt(Op, read(u16, instruction, 6)).?;
        const ordinary = legacy.contract.fixedOperandCount(op).?;
        const roles = legacy.contract.failureRolesForWire(op);
        if (read(u16, instruction, 10) > ordinary) {
            for (roles, 0..) |candidate, index| if (candidate == role) return self.constant_values[read(u16, instruction, 16 + (ordinary + index) * 2)].?;
        }
        const bytes = self.old.catalogs.envelope.section(.failures);
        var cursor: usize = 4;
        for (0..read(u32, bytes, 0)) |_| {
            const tag = read(u32, bytes, cursor);
            const count = read(u32, bytes, cursor + 4);
            cursor += 8;
            const matches = std.mem.eql(u8, bytes[cursor..][0..count], @tagName(role));
            cursor += count;
            if (matches) return self.failureTag(tag);
        }
        return error.InvalidFailureMap;
    }
    fn failureTag(self: *Lift, tag: u32) !p.Id {
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, tag, .little);
        return self.literal(self.old.catalogs.failure_schema_id, &bytes);
    }
    fn lower(self: *Lift) !p.Program {
        const blocks = try self.allocator.alloc(p.Block, self.segments.len);
        self.functions = try self.allocator.alloc(p.Function, self.old.catalogs.function_count);
        for (self.functions, 0..) |*function, index| {
            const bytes = self.old.catalogs.functions_section;
            const entry = read(u16, bytes, 6 + index * 8);
            function.* = .{ .entry = entry, .parameters = try self.parameterTypes(self.segments[entry]), .result = read(u32, bytes, 8 + index * 8) };
        }
        const effect_sets = try self.allocator.alloc(bool, self.functions.len * self.effects.len);
        @memset(effect_sets, false);
        var changed = true;
        while (changed) {
            changed = false;
            for (self.segments) |segment| {
                if (segment.terminator != .suspension) continue;
                const suspension = segment.terminator.suspension;
                const row = effect_sets[@as(usize, @intCast(segment.function)) * self.effects.len ..][0..self.effects.len];
                if (suspension.kind == 0 and !row[suspension.effect]) {
                    row[suspension.effect] = true;
                    changed = true;
                }
                if (suspension.callee) |callee| {
                    const incoming = effect_sets[@as(usize, @intCast(self.segments[callee.target].function)) * self.effects.len ..][0..self.effects.len];
                    for (row, incoming) |*owned, used| if (used and !owned.*) {
                        owned.* = true;
                        changed = true;
                    };
                }
            }
        }
        for (self.functions, 0..) |*function, index| {
            var row: std.ArrayList(p.Id) = .empty;
            for (effect_sets[index * self.effects.len ..][0..self.effects.len], 0..) |used, effect| if (used) {
                try row.append(self.allocator, effect);
            };
            function.effects = try row.toOwnedSlice(self.allocator);
        }
        for (self.segments, blocks) |segment, *block| {
            var lowering: Block = .{ .owner = self, .types = .empty, .mapping = try self.allocator.alloc(?p.Id, self.old.catalogs.value_count) };
            @memset(lowering.mapping, null);
            for (segment.live, 0..) |live, value| if (live) {
                lowering.mapping[value] = lowering.types.items.len;
                try lowering.types.append(self.allocator, try self.valueType(value));
            };
            const parameters = try self.allocator.dupe(p.Id, lowering.types.items);
            for (segment.instructions) |instruction| lowering.mapping[read(u16, instruction, 8)] = try lowering.operation(instruction);
            const terminator: p.Terminator = switch (segment.terminator) {
                .jump => |edge| .{ .jump = try lowering.edge(edge) },
                .branch => |branch| .{ .branch = .{ .condition = try lowering.value(branch.condition), .when_true = try lowering.edge(branch.yes), .when_false = try lowering.edge(branch.no) } },
                .suspension => |suspension| if (suspension.callee) |callee| blk: {
                    const arguments = (try lowering.edge(callee)).arguments;
                    const supplied = try self.allocator.alloc(p.Id, arguments.len);
                    for (supplied, arguments) |*slot, argument| slot.* = argument.slot;
                    break :blk .{ .call = .{ .function = self.segments[callee.target].function, .arguments = supplied, .next = try lowering.edge(suspension.next) } };
                } else if (suspension.kind == 0) .{ .perform = .{ .effect = suspension.effect, .payload = try lowering.value(suspension.payload.?), .next = try lowering.edge(suspension.next) } } else .{ .yield_value = try lowering.edge(suspension.next) },
                .returned => |maybe| .{ .return_value = if (maybe) |value| try lowering.value(value) else try lowering.constant(try self.literal(self.functions[@intCast(segment.function)].result, &.{})) },
                .fail_tag => |tag| .{ .fail = try lowering.constant(try self.failureTag(tag)) },
                .fail_value => |value| .{ .fail = try lowering.value(value) },
            };
            block.* = .{ .function = segment.function, .parameters = parameters, .instructions = try lowering.instructions.toOwnedSlice(self.allocator), .terminator = terminator };
        }
        return .{ .roots = .{ .entry = self.segments[self.old.catalogs.entry_segment_id].function, .result = self.old.catalogs.result_schema_id, .failure = self.old.catalogs.failure_schema_id }, .schemas = self.schemas.items, .constants = self.constants.items, .effects = self.effects, .functions = self.functions, .blocks = blocks };
    }
    fn parameterTypes(self: *Lift, segment: Segment) ![]const p.Id {
        var result: std.ArrayList(p.Id) = .empty;
        for (segment.live, 0..) |live, value| if (live) {
            try result.append(self.allocator, try self.valueType(value));
        };
        return result.toOwnedSlice(self.allocator);
    }
};

const Block = struct {
    owner: *Lift,
    mapping: []?p.Id,
    types: std.ArrayList(p.Id),
    instructions: std.ArrayList(p.Instruction) = .empty,

    fn emit(self: *Block, op: p.Opcode, result: p.Id, operands: []const p.Id, immediate: p.Id, failures: []const p.InstructionFailure) !p.Id {
        const slot = self.types.items.len;
        try self.types.append(self.owner.allocator, result);
        try self.instructions.append(self.owner.allocator, .{ .opcode = op, .result_type = result, .operands = try self.owner.allocator.dupe(p.Id, operands), .immediate = immediate, .failures = try self.owner.allocator.dupe(p.InstructionFailure, failures) });
        return slot;
    }
    fn constant(self: *Block, id: p.Id) !p.Id {
        return self.emit(.constant, self.owner.constants.items[@intCast(id)].schema, &.{}, id, &.{});
    }
    fn number(self: *Block, ty: p.Id, n: i128) !p.Id {
        const shape = self.owner.schemas.items[@intCast(ty)];
        const bytes = if (shape == .boolean) blk: {
            var result = [_]u8{0} ** 8;
            result[0] = @intCast(n);
            break :blk result;
        } else data.scalar.fromInteger(shape, n).?;
        return self.constant(try self.owner.literal(ty, bytes[0..data.scalar.width(shape).?]));
    }
    fn value(self: *Block, id: p.Id) !p.Id {
        if (self.mapping[@intCast(id)]) |slot| return slot;
        const constant_id = self.owner.constant_values[@intCast(id)] orelse if (self.owner.zero_values[@intCast(id)]) try self.owner.literal(try self.owner.valueType(id), &.{}) else return error.InvalidCapture;
        const slot = try self.constant(constant_id);
        self.mapping[@intCast(id)] = slot;
        return slot;
    }
    fn edge(self: *Block, source: OldEdge) !p.Edge {
        var arguments: std.ArrayList(p.Argument) = .empty;
        for (self.owner.segments[source.target].live, 0..) |live, value_id| if (live) {
            const argument = self.owner.sourceArgument(source, value_id);
            try arguments.append(self.owner.allocator, if (argument == .returned) .returned else .{ .slot = try self.value(argument.slot) });
        };
        return .{ .block = source.target, .arguments = try arguments.toOwnedSlice(self.owner.allocator) };
    }
    fn unary(self: *Block, opcode: p.Opcode, result: p.Id, operand: p.Id) !p.Id {
        return self.emit(opcode, result, &.{operand}, 0, &.{});
    }
    fn widen(self: *Block, operand: p.Id) !p.Id {
        const integer = try self.owner.schema(.u64);
        if (self.types.items[@intCast(operand)] == integer) return operand;
        return self.unary(.integer_convert, integer, operand);
    }
    fn operation(self: *Block, encoded: []const u8) !p.Id {
        const owner = self.owner;
        const op = std.enums.fromInt(Op, read(u16, encoded, 6)).?;
        const result = try owner.valueType(read(u16, encoded, 8));
        const immediate = read(u32, encoded, 12);
        const arity = legacy.contract.fixedOperandCount(op) orelse read(u16, encoded, 10);
        const args = try owner.allocator.alloc(p.Id, arity);
        for (args, 0..) |*arg, index| arg.* = try self.value(read(u16, encoded, 16 + index * 2));
        var failures: std.ArrayList(p.InstructionFailure) = .empty;
        for (legacy.contract.failureRolesForWire(op)) |role| try failures.append(owner.allocator, .{ .kind = std.meta.stringToEnum(p.Fault, @tagName(role)).?, .value = try owner.failure(encoded, role) });
        const direct: ?p.Opcode = switch (op) {
            .constant => .constant,
            .copy => .move,
            .integer_add => .integer_add,
            .integer_subtract => .integer_sub,
            .integer_multiply => .integer_mul,
            .integer_divide => .integer_div,
            .integer_remainder => .integer_rem,
            .integer_equal => .equal,
            .integer_less_than => .less,
            .integer_bit_not => .integer_bit_not,
            .integer_bit_and => .integer_bit_and,
            .integer_bit_or => .integer_bit_or,
            .integer_bit_xor => .integer_bit_xor,
            .boolean_not => .boolean_not,
            .select => .select,
            .product_construct => .product,
            .product_extract => .field,
            .sum_extract => .variant_payload,
            .vector_empty, .vector_clear => .sequence,
            .vector_length => .sequence_length,
            .vector_push => .sequence_append,
            .vector_pop => .sequence_pop_last,
            .text_append, .bytes_append => .blob_concat,
            .text_compare, .bytes_compare => .blob_compare,
            .text_length, .bytes_length => .blob_length,
            .enum_to_u32 => .enum_tag,
            else => null,
        };
        if (direct) |opcode| return self.emit(opcode, result, if (op == .vector_clear) &.{} else args, immediate, failures.items);
        switch (op) {
            .integer_convert => {
                const source = owner.schemas.items[@intCast(self.types.items[@intCast(args[0])])];
                return self.emit(.integer_convert, result, args, 0, if (data.scalar.conversionCanFail(source, owner.schemas.items[@intCast(result)])) failures.items else &.{});
            },
            .compare_eq_zero => {
                const ty = self.types.items[@intCast(args[0])];
                return self.emit(.equal, result, &.{ args[0], try self.number(ty, 0) }, 0, &.{});
            },
            .integer_negate => return self.emit(.integer_sub, result, &.{ try self.number(result, 0), args[0] }, 0, failures.items),
            .integer_not_equal, .integer_less_equal, .integer_greater_than, .integer_greater_equal => {
                const reversed = op == .integer_less_equal or op == .integer_greater_than;
                const compared = try self.emit(if (op == .integer_not_equal) .equal else .less, result, if (reversed) &.{ args[1], args[0] } else args, 0, &.{});
                return if (op == .integer_greater_than) compared else self.unary(.boolean_not, result, compared);
            },
            .boolean_and, .boolean_or => return self.emit(.select, result, if (op == .boolean_and) &.{ args[0], args[1], try self.number(result, 0) } else &.{ args[0], try self.number(result, 1), args[1] }, 0, &.{}),
            .product_replace => {
                const fields = owner.schemas.items[@intCast(result)].product;
                const values = try owner.allocator.alloc(p.Id, fields.len);
                for (values, fields, 0..) |*value_slot, ty, index| value_slot.* = if (index == immediate) args[1] else try self.emit(.field, ty, &.{args[0]}, index, &.{});
                return self.emit(.product, result, values, 0, &.{});
            },
            .sum_construct, .optional_none, .optional_some => {
                const tag = if (op == .optional_none) @as(p.Id, 0) else if (op == .optional_some) 1 else immediate;
                const payload_type = owner.schemas.items[@intCast(result)].sum[@intCast(tag)];
                const payload = if (args.len == 0) try self.constant(try owner.literal(payload_type, &.{})) else args[0];
                return self.emit(.variant, result, &.{payload}, tag, &.{});
            },
            .sum_tag_is, .optional_is_some => {
                const integer = try owner.schema(.u64);
                const tag = try self.unary(.variant_tag, integer, args[0]);
                return self.emit(.equal, result, &.{ tag, try self.number(integer, if (op == .optional_is_some) 1 else immediate) }, 0, &.{});
            },
            .vector_get, .text_byte_at, .bytes_byte_at => {
                const unit = try owner.schema(.unit);
                const optional = try owner.schema(.{ .sum = try owner.allocator.dupe(p.Id, &.{ unit, result }) });
                const found = try self.emit(if (op == .vector_get) .sequence_get else .blob_byte, optional, &.{ args[0], try self.widen(args[1]) }, 0, &.{});
                return self.emit(.variant_payload, result, &.{found}, 1, &.{.{ .kind = .invalid_variant, .value = failures.items[0].value }});
            },
            .vector_set => return self.emit(.sequence_set, result, &.{ args[0], try self.widen(args[1]), args[2] }, 0, failures.items),
            .vector_truncate => return self.emit(.sequence_take, result, &.{ args[0], try self.widen(args[1]) }, 0, &.{}),
            .text_empty, .bytes_empty => return self.constant(try owner.literal(result, &.{0})),
            .text_append_scalar, .text_append_unsigned, .text_append_signed, .bytes_append_scalar => {
                const scalar = op == .text_append_scalar;
                const byte = op == .bytes_append_scalar;
                const ty = try owner.schema(if (byte) .bytes else .text);
                const suffix = try self.emit(if (scalar) .text_scalar else if (byte) .blob_from_byte else .text_integer, ty, &.{args[1]}, 0, if (scalar) failures.items[1..2] else &.{});
                return self.emit(.blob_concat, result, &.{ args[0], suffix }, 0, failures.items[0..1]);
            },
            .text_copy, .bytes_copy => return self.emit(.blob_slice, result, &.{ args[0], try self.widen(args[1]), try self.widen(args[2]) }, 0, failures.items),
            .text_join, .bytes_join => {
                const first = try self.emit(.blob_concat, result, args[0..2], 0, failures.items);
                return self.emit(.blob_concat, result, &.{ first, args[2] }, 0, failures.items);
            },
            else => unreachable, // Every frozen wire operation is translated above.
        }
    }
};
