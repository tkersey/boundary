const std = @import("std");
const g = @import("graph.zig");
const s = @import("process_state.zig");
const codec = @import("state_image.zig");
const testing = std.testing;

fn ref(id: u64) g.Value {
    return .{ .schema = 0, .body = .{ .reference = .{ .id = id } } };
}
const fixture: s.State = .{
    .program_identity = .{7} ** 32,
    .status = .active,
    .roots = .{ .current = .{ .id = 1 } },
    .nodes = &.{
        .{ .record = .{ .region = .{ .descriptor = 0, .outer = null, .obligations = &.{} } } },
        .{ .record = .{ .control = .{ .block = 0, .arguments = &.{} } }, .activation = .{
            .position = 3,
            .scope = 0,
            .bindings = &.{.{ .slot = 8, .value = ref(2) }},
            .owners = &.{},
        } },
        .{ .record = .{ .cell = .{ .schema = 0, .region = .{ .id = 0 }, .value = ref(2) } } },
        .{ .record = .{ .environment = .{ .values = &.{}, .tail = null } } }, // dead
    },
};

test "PST3 visits frame values and cycles but excludes unreachable nodes" {
    const bytes = try codec.emit(testing.allocator, fixture);
    defer testing.allocator.free(bytes);
    var decoded = try codec.decodeGraph(testing.allocator, bytes);
    defer decoded.deinit();
    @memset(bytes, 0xa5);
    try testing.expectEqual(3, decoded.state.nodes.len);
    const frame = decoded.state.nodes[0].activation.?;
    try testing.expectEqual(3, frame.position);
    try testing.expectEqual(8, frame.bindings[0].slot);
    try testing.expectEqual(1, frame.bindings[0].value.body.reference.id);
    try testing.expectEqual(1, decoded.state.nodes[1].record.cell.value.?.body.reference.id);
    try testing.expectEqual(2, decoded.state.nodes[1].record.cell.region.id);
}

test "PST3 is independent of physical node order and unused prefix" {
    const nodes = [_]s.Node{
        fixture.nodes[3],
        .{ .record = .{ .cell = .{ .schema = 0, .region = .{ .id = 2 }, .value = ref(1) } } },
        fixture.nodes[0],
        .{ .record = .{ .control = .{ .block = 0, .arguments = &.{} } }, .activation = .{
            .position = 3,
            .scope = 0,
            .bindings = &.{.{ .slot = 8, .value = ref(1) }},
            .owners = &.{},
        } },
    };
    var permuted = fixture;
    permuted.nodes = &nodes;
    permuted.roots.current = .{ .id = 3 };
    const left = try codec.emit(testing.allocator, fixture);
    defer testing.allocator.free(left);
    const right = try codec.emit(testing.allocator, permuted);
    defer testing.allocator.free(right);
    try testing.expectEqualSlices(u8, left, right);
}

test "PST3 graph shape rejects missing frames and forged owner lists atomically" {
    var nodes = fixture.nodes[0..3].*;
    var state = fixture;
    state.nodes = &nodes;
    nodes[1].activation = null;
    var output = [_]u8{0xa5} ** 1024;
    try testing.expectError(error.InvalidState, codec.encode(testing.allocator, state, &output));
    for (output) |byte| try testing.expectEqual(0xa5, byte);
    nodes[1] = fixture.nodes[1];
    nodes[1].activation.?.owners = &.{.{ .scope = 0, .slot = 8 }};
    try testing.expectError(error.InvalidState, codec.encode(testing.allocator, state, &output));
    for (output) |byte| try testing.expectEqual(0xa5, byte);
    try testing.expectError(error.Capacity, codec.encode(testing.allocator, fixture, output[0..1]));
    for (output) |byte| try testing.expectEqual(0xa5, byte);
}

fn allocationFailure(allocator: std.mem.Allocator) !void {
    const bytes = try codec.emit(allocator, fixture);
    defer allocator.free(bytes);
    var decoded = try codec.decodeGraph(allocator, bytes);
    defer decoded.deinit();
    try testing.expectEqual(3, decoded.state.nodes.len);
}
test "PST3 allocation failures release partial graph owners" {
    try testing.checkAllAllocationFailures(testing.allocator, allocationFailure, .{});
}

test "PST3 framing and decoded allocation budget reject malformed input" {
    const bytes = try codec.emit(testing.allocator, fixture);
    defer testing.allocator.free(bytes);
    for (0..bytes.len) |length| {
        if (codec.decodeGraph(testing.allocator, bytes[0..length])) |result| {
            var owner = result;
            owner.deinit();
            return error.AcceptedTruncation;
        } else |_| {}
    }
    try testing.expectError(error.Capacity, codec.decodeGraphLimited(testing.allocator, bytes, .{ .max_decoded_bytes = bytes.len }));
    bytes[7] = '2';
    try testing.expectError(error.InvalidFamily, codec.decodeGraph(testing.allocator, bytes));
    bytes[7] = '3';
    bytes[10] = 1;
    try testing.expectError(error.InvalidFlags, codec.decodeGraph(testing.allocator, bytes));
}

test "PST3 terminal unit golden is independently specified" {
    const state: s.State = .{
        .program_identity = .{0} ** 32,
        .status = .completed,
        .roots = .{ .exit = .{ .id = 0 } },
        .nodes = &.{.{ .record = .{ .exit = .{ .reason = .{ .normal = .{ .schema = 0, .body = .{ .scalar = .{0} ** 8 } } } } } }},
    };
    const golden = "ABL_PST3".* ++ [_]u8{ 3, 0, 0, 0, 59, 0, 0, 0, 0, 0, 0, 0 } ++
        [_]u8{0} ** 32 ++ // Program identity
        [_]u8{ 4, 0, 0, 0, 1, 0, 0 } ++ // status and roots
        [_]u8{ 1, 23, 0, 0, 0 } ++ // node count, exit, normal, schema, scalar
        [_]u8{0} ** 8 ++ // scalar padding
        [_]u8{ 0, 0, 0, 0, 0, 0, 0 }; // exit fields, absent activation, blobs
    const bytes = try codec.emit(testing.allocator, state);
    defer testing.allocator.free(bytes);
    try testing.expectEqualSlices(u8, &golden, bytes);
    var decoded = try codec.decodeGraph(testing.allocator, &golden);
    defer decoded.deinit();
    try testing.expectEqualDeep(state, decoded.state);
}

test "PST3 keeps equal node identities distinct while interning immutable blobs" {
    var nodes = fixture.nodes[0..3].*;
    nodes[1].activation.?.bindings = &.{
        .{ .slot = 0, .value = ref(0) },
        .{ .slot = 1, .value = ref(2) },
    };
    nodes[0].record = .{ .environment = .{ .values = &.{.{ .schema = 0, .body = .{ .blob = .{ .id = 0 } } }}, .tail = null } };
    nodes[2].record = .{ .environment = .{ .values = &.{.{ .schema = 0, .body = .{ .blob = .{ .id = 1 } } }}, .tail = null } };
    var state = fixture;
    state.nodes = &nodes;
    state.blobs = &.{ .{ .schema = 0, .bytes = "payload" }, .{ .schema = 0, .bytes = "payload" } };
    const bytes = try codec.emit(testing.allocator, state);
    defer testing.allocator.free(bytes);
    var decoded = try codec.decodeGraph(testing.allocator, bytes);
    defer decoded.deinit();
    @memset(bytes, 0xff);
    try testing.expectEqual(3, decoded.state.nodes.len);
    try testing.expectEqual(1, decoded.state.blobs.len);
    try testing.expectEqualStrings("payload", decoded.state.blobs[0].bytes);
    const bindings = decoded.state.nodes[0].activation.?.bindings;
    try testing.expect(bindings[0].value.body.reference.id != bindings[1].value.body.reference.id);
}
