// Copyright (c) 2026 Boundary contributors. MIT license.
//! Exact stable-slot reads and writes in control records. Global IDs are distinct.
const std = @import("std");
const ir = @import("activation.zig");
const p = @import("program.zig");
pub const Access = struct { reads: usize = 0, writes: usize = 0 };
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
pub fn terminator(term: ir.Terminator, slot: p.Id) Access {
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
            result.reads += @as(usize, @intFromBool(v.body == slot)) + slots(v.arguments, slot) + slots(v.state, slot);
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
            result.reads += @as(usize, @intFromBool(v.body == slot)) + @intFromBool(v.cleanup == slot) + slots(v.arguments, slot);
            if (v.resource) |id| {
                result.reads += @intFromBool(id == slot);
            }
        },
        .with_region => |v| {
            result = edge(v.next, slot);
            result.reads += @as(usize, @intFromBool(v.body == slot)) + slots(v.arguments, slot);
        },
    }
    return result;
}
