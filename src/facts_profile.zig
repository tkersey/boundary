// Copyright (c) 2026 Boundary contributors. MIT license.
//! Source-checker measurements; no execution or image-codec timing is included.
const std = @import("std");
const source = @import("source.zig");
const check = @import("source/check.zig");
const Id = @import("boundary_data").program.Id;

const Sample = struct {
    nanoseconds: u64,
    arena_bytes: usize,
    memberships: usize,
    nodes: ?usize,
    set_visits: ?usize,
    digest: [64]u8,
};

fn measure(io: std.Io, allocator: std.mem.Allocator, module: source.Module) !Sample {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const start = std.Io.Clock.awake.now(io);
    const facts = try check.analyze(arena.allocator(), module);
    const elapsed = start.durationTo(std.Io.Clock.awake.now(io)).nanoseconds;
    const arena_bytes = arena.queryCapacity();
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    var memberships: usize = 0;
    inline for (.{ "values", "terms", "functions" }) |field| {
        for (@field(facts, field)) |set| {
            var word: [8]u8 = undefined;
            if (comptime !@hasField(check.Facts, "sets") or std.mem.eql(u8, field, "functions")) {
                std.mem.writeInt(u64, &word, set.items.len, .little);
                hash.update(&word);
                for (set.items) |member| {
                    std.mem.writeInt(Id, &word, member, .little);
                    hash.update(&word);
                    memberships += 1;
                }
            } else {
                std.mem.writeInt(u64, &word, facts.sets.count(set), .little);
                hash.update(&word);
                var traversal = facts.sets.iterator(set);
                while (traversal.next()) |member| {
                    std.mem.writeInt(Id, &word, member, .little);
                    hash.update(&word);
                    memberships += 1;
                }
            }
        }
    }
    return .{
        .nanoseconds = @intCast(elapsed),
        .arena_bytes = arena_bytes,
        .memberships = memberships,
        .nodes = if (@hasField(check.Facts, "sets")) facts.sets.nodeCount() else null,
        .set_visits = if (@hasField(check.Facts, "sets")) facts.sets.visits else null,
        .digest = std.fmt.bytesToHex(hash.finalResult(), .lower),
    };
}

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    for ([_]usize{ 1, 8, 64, 128, 256 }) |count| {
        var builder = source.Builder.init(init.gpa);
        defer builder.deinit();
        const module = try source.examples.installations(&builder, count);
        for (0..3) |_| _ = try measure(init.io, init.gpa, module);
        var samples: [9]Sample = undefined;
        for (&samples) |*sample| sample.* = try measure(init.io, init.gpa, module);
        try std.json.Stringify.value(.{ .installations = count, .samples = samples }, .{}, &output.interface);
        try output.interface.writeByte('\n');
    }
    try output.interface.flush();
}
