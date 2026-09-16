// Copyright (c) 2026 Boundary contributors. MIT license.
//! Canonical ordered graph encoding. No instruction is executed here.
const std = @import("std");
const g = @import("graph.zig");
const wire = @import("wire.zig");
const record = @import("record.zig");
pub const Error = record.Error || error{ InvalidReference, InvalidState };
const order = @import("graph_order.zig");
pub const Reference = order.Reference;
pub const Statistics = order.Statistics;
pub const Owned = order.Owned(g.State);
pub const references = order.references;

pub fn canonicalize(allocator: std.mem.Allocator, state: g.State) Error!Owned {
    return order.canonicalize(allocator, state, null);
}
pub fn canonicalizeMeasured(allocator: std.mem.Allocator, state: g.State, statistics: ?*Statistics) Error!Owned {
    return order.canonicalize(allocator, state, statistics);
}

/// Exact output size for the same logical records passed to encode.
pub fn encodedLength(allocator: std.mem.Allocator, state: g.State) Error!usize {
    var normalized = try canonicalize(allocator, state);
    defer normalized.deinit();
    return canonicalLength(normalized.state);
}

fn canonicalLength(state: g.State) Error!usize {
    var writer: wire.Writer = .{};
    try record.write(g.State, state, &writer);
    return std.math.add(usize, writer.position, wire.header_length) catch error.InvalidLength;
}

/// Produces canonical bytes from caller-supplied logical records.
pub fn encode(allocator: std.mem.Allocator, state: g.State, output: []u8) Error![]const u8 {
    return encodeMeasured(allocator, state, output, null);
}

pub fn encodeMeasured(allocator: std.mem.Allocator, state: g.State, output: []u8, statistics: ?*Statistics) Error![]const u8 {
    var normalized = try canonicalizeMeasured(allocator, state, statistics);
    defer normalized.deinit();
    return encodeCanonical(normalized.state, output);
}

pub const Emission = struct {
    /// The caller releases this temporary graph with `normalized.deinit()`.
    normalized: Owned,
    /// Independently owned by the caller's output allocator.
    bytes: []u8,
};

/// Normalize once, size, and write. The returned graph is the exact graph whose
/// bytes were emitted, so a consumer can perform program-relative admission
/// without normalizing it again. No admission claim is made by this codec.
pub fn emit(allocator: std.mem.Allocator, state: g.State, output: std.mem.Allocator, statistics: ?*Statistics) Error!Emission {
    var normalized = try canonicalizeMeasured(allocator, state, statistics);
    errdefer normalized.deinit();
    const bytes = try output.alloc(u8, try canonicalLength(normalized.state));
    errdefer output.free(bytes);
    _ = try encodeCanonical(normalized.state, bytes);
    return .{ .normalized = normalized, .bytes = bytes };
}

/// Encodes a canonical logical graph. Full program-relative admission is separate.
fn encodeCanonical(state: g.State, output: []u8) Error![]const u8 {
    const length = try canonicalLength(state);
    if (output.len < length) return error.Capacity;
    var writer: wire.Writer = .{ .output = output[0..length] };
    try writer.put(wire.magic(.pst));
    try writer.fixed(u16, 2);
    try writer.fixed(u16, 0);
    try writer.fixed(u64, length - wire.header_length);
    try record.write(g.State, state, &writer);
    return output[0..writer.position];
}

/// Validates framing, references, reachability, numbering, and blob canonicality.
/// It does not grant program-relative type/ownership admission on its own.
pub fn decodeGraph(allocator: std.mem.Allocator, input: []const u8) Error!Owned {
    var temporary = std.heap.ArenaAllocator.init(allocator);
    defer temporary.deinit();
    const body = try wire.unframe(.pst, input);
    var reader: wire.Reader = .{ .input = body };
    const state = try record.read(g.State, &reader, temporary.allocator());
    try reader.finish();
    var normalized = try canonicalize(allocator, state);
    errdefer normalized.deinit();
    var comparison: wire.Writer = .{ .expected = body };
    try record.write(g.State, normalized.state, &comparison);
    if (comparison.position != body.len) return error.NonCanonical;
    return normalized;
}

test "ordered graph encoding preserves aliases and a region cell cycle" {
    const value: g.Value = .{ .schema = 0, .body = .{ .reference = .{ .id = 2 } } };
    const nodes: []const g.Node = &.{
        .{ .region = .{ .descriptor = 0, .outer = null, .obligations = &.{} } },
        .{ .control = .{ .block = 0, .arguments = &.{ value, value } } },
        .{ .cell = .{ .schema = 0, .region = .{ .id = 0 }, .value = value } },
    };
    var canonical = try canonicalize(std.testing.allocator, .{
        .program_identity = .{0} ** 32,
        .status = .active,
        .roots = .{ .current = .{ .id = 1 } },
        .nodes = nodes,
    });
    defer canonical.deinit();
    try std.testing.expectEqual(@as(usize, 3), canonical.state.nodes.len);
    try std.testing.expectEqual(@as(u64, 1), canonical.state.nodes[0].control.arguments[0].body.reference.id);
    try std.testing.expectEqual(@as(u64, 1), canonical.state.nodes[0].control.arguments[1].body.reference.id);
    var output: [2048]u8 = undefined;
    const bytes = try encodeCanonical(canonical.state, &output);
    var decoded = try decodeGraph(std.testing.allocator, bytes);
    defer decoded.deinit();
    try std.testing.expectEqual(@as(u64, 1), decoded.state.nodes[1].cell.value.?.body.reference.id);
}

test "graph decoding rejects unreachable garbage instead of dropping it" {
    const state: g.State = .{
        .program_identity = .{0} ** 32,
        .status = .active,
        .roots = .{},
        .nodes = &.{.{ .environment = .{ .values = &.{}, .tail = null } }},
    };
    var output: [256]u8 = undefined;
    const bytes = try encodeCanonical(state, &output);
    try std.testing.expectError(error.NonCanonical, decodeGraph(std.testing.allocator, bytes));
}

test "caller-owned sizing includes canonical reference widths" {
    const allocator = std.testing.allocator;
    var nodes: [130]g.Node = undefined;
    for (&nodes) |*node| node.* = .{ .environment = .{ .values = &.{}, .tail = null } };
    var aliases: [100]g.Value = undefined;
    @memset(&aliases, .{ .schema = 0, .body = .{ .reference = .{ .id = 0 } } });
    nodes[nodes.len - 1].environment.values = &aliases;
    var roots: [nodes.len - 1]g.OwnedRef = undefined;
    for (&roots, 1..) |*root, id| root.* = .{ .node = .{ .id = id } };
    const state: g.State = .{
        .program_identity = .{0} ** 32,
        .status = .active,
        .roots = .{ .detached = &roots },
        .nodes = &nodes,
    };
    const Measure = struct {
        fn run(storage: std.mem.Allocator, input: g.State) !void {
            try std.testing.expectEqual(@as(usize, 982), try encodedLength(storage, input));
        }
    };
    try std.testing.checkAllAllocationFailures(allocator, Measure.run, .{state});
    const length = try encodedLength(allocator, state);
    try std.testing.expect(length > try canonicalLength(state));
    const output = try allocator.alloc(u8, length);
    defer allocator.free(output);
    @memset(output, 0xaa);
    try std.testing.expectError(error.Capacity, encode(allocator, state, output[0 .. length - 1]));
    try std.testing.expect(std.mem.allEqual(u8, output, 0xaa));
    const bytes = try encode(allocator, state, output);
    try std.testing.expectEqual(length, bytes.len);
    var decoded = try decodeGraph(allocator, bytes);
    defer decoded.deinit();
    try std.testing.expectEqual(length, try encodedLength(allocator, decoded.state));
}

fn detachedAllocationCase(allocator: std.mem.Allocator) !void {
    var detached: [1024]g.OwnedRef = undefined;
    var nodes: [1024]g.Node = undefined;
    for (&detached, &nodes, 0..) |*root, *node, id| {
        root.* = .{ .node = .{ .id = id } };
        node.* = .{ .environment = .{ .values = &.{}, .tail = null } };
    }
    var normalized = try canonicalize(allocator, .{
        .program_identity = .{0} ** 32,
        .status = .active,
        .roots = .{ .detached = &detached },
        .nodes = &nodes,
    });
    defer normalized.deinit();
    try std.testing.expectEqual(detached.len, normalized.state.roots.detached.len);
    try std.testing.expectEqual(nodes.len, normalized.state.nodes.len);
}

test "canonical graph owner retains final detached-root allocations" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, detachedAllocationCase, .{});
}

fn scratchLifetimeCase(allocator: std.mem.Allocator) !void {
    var payload = [_]u8{ 1, 2, 3, 4 };
    const values = [_]g.Value{
        .{ .schema = 0, .body = .{ .blob = .{ .id = 0 } } },
        .{ .schema = 0, .body = .{ .blob = .{ .id = 1 } } },
    };
    const nodes = [_]g.Node{
        .{ .environment = .{ .values = &values, .tail = .{ .id = 1 } } },
        .{ .environment = .{ .values = &values, .tail = .{ .id = 0 } } },
    };
    var normalized = try canonicalize(allocator, .{
        .program_identity = .{0} ** 32,
        .status = .active,
        .roots = .{ .current = .{ .id = 0 } },
        .nodes = &nodes,
        .blobs = &.{
            .{ .schema = 0, .bytes = &payload },
            .{ .schema = 0, .bytes = &payload },
        },
    });
    defer normalized.deinit();
    @memset(&payload, 0xa5);
    try std.testing.expectEqual(@as(usize, 2), normalized.state.nodes.len);
    try std.testing.expectEqual(@as(usize, 1), normalized.state.blobs.len);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, normalized.state.blobs[0].bytes);
    try std.testing.expectEqual(@as(u64, 0), normalized.state.nodes[1].environment.tail.?.id);
    var output: [1024]u8 = undefined;
    const bytes = try encodeCanonical(normalized.state, &output);
    var decoded = try decodeGraph(allocator, bytes);
    defer decoded.deinit();
    var again: [1024]u8 = undefined;
    try std.testing.expectEqualSlices(u8, bytes, try encodeCanonical(decoded.state, &again));
}

test "snapshot scratch release preserves owned payloads, cycles and distinct nodes" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, scratchLifetimeCase, .{});
}
