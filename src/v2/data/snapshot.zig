// Copyright (c) 2026 Boundary contributors. MIT license.
//! Canonical ordered graph encoding. No instruction is executed here.
const std = @import("std");
const g = @import("graph.zig");
const wire = @import("wire.zig");
const record = @import("record.zig");
pub const Error = record.Error || error{ InvalidReference, InvalidState };
const absent = std.math.maxInt(u64);
pub const Reference = union(enum) { node: u64, blob: u64 };

/// Optional work counters. Graph discovery is distinct from the flat remapping
/// pass and byte interning; none of these observations is part of PST2.
pub const Statistics = struct {
    nodes: u64 = 0,
    edges: u64 = 0,
    blobs: u64 = 0,
    remapped_nodes: u64 = 0,
    stored_payload_bytes: u64 = 0,
    interning_hash_bytes: u64 = 0,
    interning_comparisons: u64 = 0,
};

pub const Owned = struct {
    arena: std.heap.ArenaAllocator,
    state: g.State,

    pub fn deinit(self: *Owned) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

/// Normalizes irrelevant IDs and interns blobs; distinct nodes never merge.
/// The returned owner retains every byte, including the immutable blob payloads.
pub fn canonicalize(allocator: std.mem.Allocator, state: g.State) Error!Owned {
    return canonicalizeMeasured(allocator, state, null);
}

pub fn canonicalizeMeasured(allocator: std.mem.Allocator, state: g.State, statistics: ?*Statistics) Error!Owned {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const storage = arena.allocator();
    const node_map = try storage.alloc(u64, state.nodes.len);
    const blob_map = try storage.alloc(u64, state.blobs.len);
    @memset(node_map, absent);
    @memset(blob_map, absent);
    var order: std.ArrayList(usize) = .empty;
    var blobs: std.ArrayList(g.Blob) = .empty;
    var interned: std.HashMapUnmanaged(g.Blob, usize, BlobContext, 80) = .empty;
    var pending: std.ArrayList(Reference) = .empty;
    var children: std.ArrayList(Reference) = .empty;
    try references(g.Roots, state.roots, &children, storage);
    if (statistics) |s| s.edges +|= children.items.len;
    try reverseAppend(&pending, children.items, storage);
    while (pending.pop()) |reference| {
        switch (reference) {
            .node => |id| {
                if (id >= state.nodes.len) return error.InvalidReference;
                const index: usize = @intCast(id);
                if (node_map[index] != absent) continue;
                node_map[index] = order.items.len;
                try order.append(storage, index);
                if (statistics) |s| s.nodes +|= 1;
                children.clearRetainingCapacity();
                try references(g.Node, state.nodes[index], &children, storage);
                if (statistics) |s| s.edges +|= children.items.len;
                try reverseAppend(&pending, children.items, storage);
            },
            .blob => |id| {
                if (id >= state.blobs.len) return error.InvalidReference;
                const index: usize = @intCast(id);
                if (blob_map[index] != absent) continue;
                if (statistics) |s| s.blobs +|= 1;
                const source = state.blobs[index];
                const context: BlobContext = .{ .statistics = statistics };
                var selected = interned.getContext(source, context);
                if (selected == null) {
                    selected = blobs.items.len;
                    try blobs.append(storage, .{ .schema = source.schema, .bytes = try storage.dupe(u8, source.bytes) });
                    try interned.putContext(storage, blobs.items[blobs.items.len - 1], selected.?, context);
                    if (statistics) |s| s.stored_payload_bytes +|= source.bytes.len;
                }
                blob_map[index] = selected.?;
            },
        }
    }
    const nodes = try storage.alloc(g.Node, order.items.len);
    for (nodes, order.items) |*node, original| {
        node.* = try remap(g.Node, state.nodes[original], node_map, blob_map, storage);
        if (statistics) |s| s.remapped_nodes +|= 1;
    }
    const canonical_state: g.State = .{
        .program_identity = state.program_identity,
        .status = state.status,
        .roots = try remap(g.Roots, state.roots, node_map, blob_map, storage),
        .nodes = nodes,
        .blobs = blobs.items,
    };
    return .{ .arena = arena, .state = canonical_state };
}

const BlobContext = struct {
    statistics: ?*Statistics = null,
    pub fn hash(self: BlobContext, blob: g.Blob) u64 {
        if (self.statistics) |s| s.interning_hash_bytes +|= blob.bytes.len;
        return std.hash.Wyhash.hash(blob.schema, blob.bytes);
    }
    pub fn eql(self: BlobContext, left: g.Blob, right: g.Blob) bool {
        if (self.statistics) |s| s.interning_comparisons +|= 1;
        return left.schema == right.schema and std.mem.eql(u8, left.bytes, right.bytes);
    }
};

fn reverseAppend(list: *std.ArrayList(Reference), children: []const Reference, allocator: std.mem.Allocator) Error!void {
    var index = children.len;
    while (index != 0) {
        index -= 1;
        try list.append(allocator, children[index]);
    }
}

/// The record type graph is acyclic; process cycles appear only as NodeRef IDs.
pub fn references(comptime T: type, value: T, list: *std.ArrayList(Reference), allocator: std.mem.Allocator) Error!void {
    if (T == g.NodeRef) return list.append(allocator, .{ .node = value.id });
    if (T == g.BlobRef) return list.append(allocator, .{ .blob = value.id });
    switch (@typeInfo(T)) {
        .pointer => |info| {
            if (info.child != u8) for (value) |element| try references(info.child, element, list, allocator);
        },
        .array => |info| {
            if (info.child != u8) for (value) |element| try references(info.child, element, list, allocator);
        },
        .optional => |info| {
            if (value) |present| try references(info.child, present, list, allocator);
        },
        .@"struct" => |info| inline for (info.fields) |field| try references(field.type, @field(value, field.name), list, allocator),
        .@"union" => |info| inline for (info.fields) |field| {
            if (std.mem.eql(u8, @tagName(value), field.name)) {
                try references(field.type, @field(value, field.name), list, allocator);
                return;
            }
        },
        else => {},
    }
}

fn remap(comptime T: type, value: T, nodes: []const u64, blobs: []const u64, allocator: std.mem.Allocator) Error!T {
    if (T == g.NodeRef) return .{ .id = nodes[@intCast(value.id)] };
    if (T == g.BlobRef) return .{ .id = blobs[@intCast(value.id)] };
    return switch (@typeInfo(T)) {
        .pointer => |info| blk: {
            const result = try allocator.alloc(info.child, value.len);
            for (result, value) |*target, source| target.* = try remap(info.child, source, nodes, blobs, allocator);
            break :blk result;
        },
        .optional => |info| if (value) |present| try remap(info.child, present, nodes, blobs, allocator) else null,
        .array => |info| blk: {
            var result: T = undefined;
            for (&result, value) |*target, source| target.* = try remap(info.child, source, nodes, blobs, allocator);
            break :blk result;
        },
        .@"struct" => |info| blk: {
            var result: T = undefined;
            inline for (info.fields) |field| @field(result, field.name) = try remap(field.type, @field(value, field.name), nodes, blobs, allocator);
            break :blk result;
        },
        .@"union" => |info| blk: {
            inline for (info.fields) |field| {
                if (std.mem.eql(u8, @tagName(value), field.name))
                    break :blk @unionInit(T, field.name, try remap(field.type, @field(value, field.name), nodes, blobs, allocator));
            }
            unreachable; // The active tag is one of this closed native union's fields.
        },
        else => value,
    };
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
