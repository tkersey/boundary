// Copyright (c) 2026 Boundary contributors. MIT license.
//! Checked replacement of a locally constructed computation by its direct call.
//! This is an external-semantics transformation, not a same-microstep quotient.
const std = @import("std");
const ir = @import("activation.zig");
const p = @import("program.zig");
const facts = @import("value_facts.zig");
const ownership = @import("activation_ownership.zig");
const admission = @import("admission.zig");
const coalescing = @import("coalescing.zig");
pub const Error = facts.Error || coalescing.Error || error{InvalidSpecialization};
pub const Statistics = struct { direct_applications: usize = 0, eliminated_constructions: usize = 0, unavailable_captures: usize = 0, retained_applications: usize = 0 };
pub const Witness = struct { block: usize, construction: usize };

/// Original admission, versioned discovery, independent correspondence,
/// fresh admission, and final mandatory P01. No runtime image is modified.
pub fn run(allocator: std.mem.Allocator, original: ir.Program, statistics: ?*Statistics, options: coalescing.Options) Error!coalescing.Owned {
    var observed: Statistics = .{};
    defer if (statistics) |out| {
        out.* = observed;
    };
    var known = try facts.analyze(allocator, original);
    defer known.deinit();
    try known.requireEpoch(allocator, original);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schemas = try admission.schemas(a, original.schemas);
    const blocks = try a.dupe(ir.Block, original.blocks);
    var witnesses: std.ArrayList(Witness) = .empty;
    for (original.blocks, known.blocks, 0..) |block, state, index| {
        if (!state.reachable or block.terminator != .apply) continue;
        const apply = block.terminator.apply;
        const value = state.definitions[state.exit[@intCast(apply.computation)]].value;
        const origin = value.construction orelse {
            observed.retained_applications += 1;
            continue;
        };
        if (value.constructor == null or !eligible(original, index, origin, schemas.exportable)) {
            observed.retained_applications += 1;
            continue;
        }
        const construction = block.instructions[origin];
        const definition = state.definitions[state.results[origin]];
        var available = true;
        for (construction.operands, definition.operands) |slot, version| {
            if (state.exit[@intCast(slot)] != version) available = false;
        }
        if (!available) {
            observed.unavailable_captures += 1;
            continue;
        }
        const constructor = original.constructors[@intCast(construction.immediate)];
        const arguments = try a.alloc(p.Id, construction.operands.len + apply.arguments.len);
        @memcpy(arguments[0..construction.operands.len], construction.operands);
        @memcpy(arguments[construction.operands.len..], apply.arguments);
        const instructions = try a.alloc(ir.Instruction, block.instructions.len - 1);
        @memcpy(instructions[0..origin], block.instructions[0..origin]);
        @memcpy(instructions[origin..], block.instructions[origin + 1 ..]);
        blocks[index].instructions = instructions;
        blocks[index].terminator = .{ .call = .{ .function = constructor.function, .arguments = arguments, .next = apply.next } };
        try witnesses.append(a, .{ .block = index, .construction = origin });
    }
    var candidate = original;
    candidate.blocks = blocks;
    try validate(allocator, original, candidate, witnesses.items);
    var checked = try ownership.analyze(allocator, candidate);
    checked.deinit();
    observed.direct_applications = witnesses.items.len;
    observed.eliminated_constructions = witnesses.items.len;
    return coalescing.run(allocator, candidate, options);
}

fn eligible(program: ir.Program, block_id: usize, index: usize, exportable: []const bool) bool {
    const block = program.blocks[block_id];
    if (index >= block.instructions.len or block.terminator != .apply) return false;
    const instruction = block.instructions[index];
    if (instruction.opcode != .computation or instruction.destination != block.terminator.apply.computation) return false;
    const constructor = program.constructors[@intCast(instruction.immediate)];
    const capture = program.scopes.captures[@intCast(constructor.capture)];
    const function = program.functions[@intCast(constructor.function)];
    if (capture.owned_regions.len != 0 or capture.borrowed_regions.len != 0 or function.regions.len != 0) return false;
    for (capture.fields) |schema| if (!exportable[@intCast(schema)]) return false;
    // One definition and one consumption prevent both escaping aliases and
    // accidentally retaining a prior value when the construction is removed.
    var reads: usize = 0;
    var writes: usize = std.mem.count(p.Id, program.functions[@intCast(block.function)].inputs, &.{instruction.destination});
    for (program.blocks) |other| {
        if (other.function != block.function) continue;
        for (other.instructions) |operation| {
            reads += std.mem.count(p.Id, operation.operands, &.{instruction.destination});
            if (operation.destination == instruction.destination) writes += 1;
        }
        const uses = access(other.terminator, instruction.destination);
        reads += uses.reads;
        writes += uses.writes;
    }
    return reads == 1 and writes == 1;
}

/// The checker does not consume finder facts. It checks the actual construction,
/// every intervening write, ordered ABI operands, and all unchanged records.
pub fn validate(allocator: std.mem.Allocator, original: ir.Program, candidate: ir.Program, witnesses: []const Witness) Error!void {
    var original_check = try ownership.analyze(allocator, original);
    defer original_check.deinit();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const schemas = try admission.schemas(arena.allocator(), original.schemas);
    var unchanged = candidate;
    unchanged.blocks = original.blocks;
    if (!equal(ir.Program, original, unchanged) or candidate.blocks.len != original.blocks.len) return error.InvalidSpecialization;
    for (original.blocks, candidate.blocks, 0..) |before, after, index| {
        var witness: ?Witness = null;
        for (witnesses) |item| if (item.block == index) {
            if (witness != null) return error.InvalidSpecialization;
            witness = item;
        };
        if (witness) |item| {
            if (!eligible(original, index, item.construction, schemas.exportable)) return error.InvalidSpecialization;
            const construction = before.instructions[item.construction];
            const apply = before.terminator.apply;
            for (before.instructions[item.construction + 1 ..]) |operation| {
                for (construction.operands) |capture| if (operation.destination == capture) return error.InvalidSpecialization;
            }
            if (after.function != before.function or after.custody != before.custody or after.terminator != .call) return error.InvalidSpecialization;
            const call = after.terminator.call;
            const constructor = original.constructors[@intCast(construction.immediate)];
            if (call.function != constructor.function or !equal(ir.Edge, call.next, apply.next)) return error.InvalidSpecialization;
            if (call.arguments.len != construction.operands.len + apply.arguments.len) return error.InvalidSpecialization;
            if (!std.mem.eql(p.Id, call.arguments[0..construction.operands.len], construction.operands) or
                !std.mem.eql(p.Id, call.arguments[construction.operands.len..], apply.arguments)) return error.InvalidSpecialization;
            if (after.instructions.len + 1 != before.instructions.len) return error.InvalidSpecialization;
            for (before.instructions, 0..) |instruction, old| {
                if (old == item.construction) continue;
                const at = old - @intFromBool(old > item.construction);
                if (!equal(ir.Instruction, instruction, after.instructions[at])) return error.InvalidSpecialization;
            }
        } else if (!equal(ir.Block, before, after)) return error.InvalidSpecialization;
    }
    for (witnesses) |item| if (item.block >= original.blocks.len) return error.InvalidSpecialization;
}
fn equal(comptime T: type, left: T, right: T) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => |info| blk: {
            inline for (info.fields) |field| if (!equal(field.type, @field(left, field.name), @field(right, field.name))) break :blk false;
            break :blk true;
        },
        .@"union" => blk: {
            if (std.meta.activeTag(left) != std.meta.activeTag(right)) break :blk false;
            break :blk switch (left) {
                inline else => |value, tag| equal(@TypeOf(value), value, @field(right, @tagName(tag))),
            };
        },
        .pointer => |info| blk: {
            if (info.size != .slice) break :blk left == right;
            if (left.len != right.len) break :blk false;
            for (left, right) |x, y| if (!equal(info.child, x, y)) break :blk false;
            break :blk true;
        },
        .optional => |info| if (left) |value| if (right) |other| equal(info.child, value, other) else false else right == null,
        .array => |info| blk: {
            for (left, right) |x, y| if (!equal(info.child, x, y)) break :blk false;
            break :blk true;
        },
        else => left == right,
    };
}
const Access = struct { reads: usize = 0, writes: usize = 0 };
fn slots(values: []const p.Id, slot: p.Id) usize {
    return std.mem.count(p.Id, values, &.{slot});
}
fn edge(value: ir.Edge, slot: p.Id) Access {
    var result: Access = .{};
    for (value.assignments) |assignment| {
        if (assignment.destination == slot) result.writes += 1;
        if (assignment.source == .slot and assignment.source.slot == slot) result.reads += 1;
    }
    return result;
}
fn access(term: ir.Terminator, slot: p.Id) Access {
    var result: Access = .{};
    switch (term) {
        .return_value, .fail => |value| result.reads = @intFromBool(value == slot),
        .jump, .yield_value => |next| result = edge(next, slot),
        .branch => |v| {
            const yes = edge(v.when_true, slot);
            const no = edge(v.when_false, slot);
            result = .{ .reads = @as(usize, @intFromBool(v.condition == slot)) + yes.reads + no.reads, .writes = yes.writes + no.writes };
        },
        .switch_variant => |v| {
            result.reads = @intFromBool(v.value == slot);
            for (v.cases) |next| {
                const use = edge(next, slot);
                result.reads += use.reads;
                result.writes += use.writes;
            }
        },
        .unpack_product => |v| {
            result = edge(v.next, slot);
            result.reads += @intFromBool(v.value == slot);
            result.writes += slots(v.destinations, slot);
        },
        .call => |v| {
            result = edge(v.next, slot);
            result.reads += slots(v.arguments, slot);
        },
        .apply => |v| {
            result = edge(v.next, slot);
            result.reads += @as(usize, @intFromBool(v.computation == slot)) + slots(v.arguments, slot);
        },
        .perform => |v| {
            result = edge(v.next, slot);
            result.reads += @as(usize, @intFromBool(v.payload == slot)) + slots(v.bodies, slot) + slots(v.use_site_capabilities, slot);
            if (v.capability) |id| {
                result.reads += @intFromBool(id == slot);
            }
        },
        .handle => |v| {
            result = edge(v.next, slot);
            result.reads += slots(v.arguments, slot) + slots(v.state, slot);
        },
        .resume_value => |v| {
            result = edge(v.next, slot);
            result.reads += @as(usize, @intFromBool(v.resumption == slot)) + @intFromBool(v.argument == slot);
        },
        .resume_with => |v| {
            result = edge(v.next, slot);
            result.reads += @as(usize, @intFromBool(v.resumption == slot)) + @intFromBool(v.argument == slot) + slots(v.state, slot);
        },
        .resume_computation => |v| {
            result = edge(v.next, slot);
            result.reads += @as(usize, @intFromBool(v.resumption == slot)) + @intFromBool(v.computation == slot);
        },
        .dispose => |v| {
            result = edge(v.next, slot);
            result.reads += @intFromBool(v.owned == slot);
        },
        .protect => |v| {
            result = edge(v.next, slot);
            result.reads += slots(v.arguments, slot);
            if (v.resource) |id| {
                result.reads += @intFromBool(id == slot);
            }
        },
        .with_region => |v| {
            result = edge(v.next, slot);
            result.reads += slots(v.arguments, slot);
        },
    }
    return result;
}
