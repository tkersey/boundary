const std = @import("std");
const legacy = @import("boundary_bpi1");
const data = @import("boundary_data_v2");

const fixtures = [_][]const u8{
    @embedFile("legacy/authored-failure-v1.bpi1"),
    @embedFile("legacy/authored-failure-v2-success.bpi1"),
    @embedFile("legacy/authored-failure-v2-bad-math.bpi1"),
    @embedFile("legacy/effect-morphism.bpi1"),
    @embedFile("legacy/explicit-yield.bpi1"),
    @embedFile("legacy/initial-progress.bpi1"),
    @embedFile("legacy/typed-effect-initial.bpi1"),
    @embedFile("legacy/recursion-complete.bpi1"),
    @embedFile("legacy/v1.8.2-one-effect.bpi1"),
    @embedFile("legacy/v1.8.2-portable-values.bpi1"),
    @embedFile("legacy/v1.8.2-integer-boolean.bpi1"),
    @embedFile("legacy/v1.8.2-remainder-i8.bpi1"),
    @embedFile("legacy/v1.8.2-remainder-i16.bpi1"),
    @embedFile("legacy/v1.8.2-remainder-i32.bpi1"),
    @embedFile("legacy/v1.8.2-remainder-i64.bpi1"),
    @embedFile("legacy/v1.8.2-algebraic-collections.bpi1"),
    @embedFile("legacy/v1.8.2-text-byte-at.bpi1"),
    @embedFile("legacy/v1.8.2-bytes-byte-at.bpi1"),
    @embedFile("legacy/v1.8.2-enum-tag.bpi1"),
    @embedFile("legacy/v1.8.2-derived-copy.bpi1"),
};

const Size = struct { fixture: usize, v1_image_bytes: usize, v2_image_bytes: usize, shared_v1_constant_bytes: usize, v2_constant_bytes: usize, conservative_overhead_limit: usize };
fn size(allocator: std.mem.Allocator, fixture: []const u8, index: usize) !Size {
    var decoded = try legacy.decode(allocator, fixture);
    defer decoded.deinit();
    var lifted = try legacy.lift(allocator, fixture);
    defer lifted.deinit();
    const section = decoded.program.catalogs.envelope.section(.constants);
    var seen: std.ArrayList(data.program.Literal) = .empty;
    defer seen.deinit(allocator);
    var shared: usize = 0;
    var cursor: usize = 4;
    for (0..decoded.program.catalogs.constant_count) |_| {
        const schema = std.mem.readInt(u32, section[cursor..][0..4], .little);
        const length = std.mem.readInt(u32, section[cursor + 4 ..][0..4], .little);
        cursor += 8;
        const value = section[cursor..][0..length];
        const duplicate = for (seen.items) |previous| {
            if (previous.schema == schema and std.mem.eql(u8, previous.bytes, value)) break true;
        } else false;
        if (!duplicate) {
            try seen.append(allocator, .{ .schema = schema, .bytes = value });
            shared += length;
        }
        cursor += length;
    }
    var after_payload: usize = 0;
    for (lifted.program.constants) |constant| after_payload += constant.bytes.len;
    return .{ .fixture = index, .v1_image_bytes = fixture.len, .v2_image_bytes = try data.image.encodedLength(lifted.program), .shared_v1_constant_bytes = shared, .v2_constant_bytes = after_payload, .conservative_overhead_limit = (fixture.len - shared) * 3 / 2 + 4096 };
}

test "all lifted images satisfy the serialized-overhead gate even before subtracting v2 payloads" {
    for (fixtures, 0..) |fixture, index| {
        const measured = try size(std.testing.allocator, fixture, index);
        // Counting every v2 payload as overhead is a conservative upper bound.
        try std.testing.expect(measured.v2_image_bytes <= measured.conservative_overhead_limit);
    }
}

pub fn main(init: std.process.Init) !void {
    var rows: [fixtures.len]Size = undefined;
    for (&rows, fixtures, 0..) |*row, fixture, index| row.* = try size(init.gpa, fixture, index);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try std.json.Stringify.value(rows, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}

fn decodeCase(allocator: std.mem.Allocator, fixture: []const u8) !void {
    const input = try allocator.dupe(u8, fixture);
    defer allocator.free(input);
    var decoded = try legacy.decode(allocator, input);
    defer decoded.deinit();
    @memset(input, 0xa5);
    try std.testing.expectEqualSlices(u8, fixture, decoded.program.catalogs.envelope.image);
    for (0..decoded.program.catalogs.schemas.count()) |index| {
        _ = try decoded.program.catalogs.schemas.node(@intCast(index));
    }
}

test "frozen BPI1 corpus admits independently of the legacy compiler and evaluator" {
    for (fixtures) |fixture| try decodeCase(std.testing.allocator, fixture);
}

test "every BPI1 decoding allocation failure releases temporary and owned storage" {
    for (fixtures) |fixture| try std.testing.checkAllAllocationFailures(std.testing.allocator, decodeCase, .{fixture});
}

test "unsupported evaluator versions and PST1 are not lifting inputs" {
    var bytes: [fixtures[0].len]u8 = fixtures[0][0..fixtures[0].len].*;
    std.mem.writeInt(u16, bytes[10..12], 4, .little);
    try std.testing.expectError(error.UnsupportedEvaluatorSemantics, legacy.decode(std.testing.allocator, &bytes));
    @memcpy(bytes[0..8], "ABL_PST1");
    try std.testing.expectError(error.InvalidMagic, legacy.decode(std.testing.allocator, &bytes));
}

fn constantRoundTrips(allocator: std.mem.Allocator, fixture: []const u8) !void {
    var decoded = try legacy.decode(allocator, fixture);
    defer decoded.deinit();
    var translated = try legacy.types.schemas(allocator, decoded.program.catalogs.schemas);
    defer translated.deinit();
    try std.testing.expect(translated.types.len >= decoded.program.catalogs.schemas.count());
    const constants = decoded.program.catalogs.envelope.section(.constants);
    var cursor: usize = 4;
    for (0..decoded.program.catalogs.constant_count) |_| {
        const schema = std.mem.readInt(u32, constants[cursor..][0..4], .little);
        const length = std.mem.readInt(u32, constants[cursor + 4 ..][0..4], .little);
        cursor += 8;
        const before = constants[cursor..][0..length];
        const encoded = try legacy.types.toV2(allocator, decoded.program.catalogs.schemas, schema, before);
        defer allocator.free(encoded);
        const after = try legacy.types.toV1(allocator, decoded.program.catalogs.schemas, schema, encoded);
        defer allocator.free(after);
        try std.testing.expectEqualSlices(u8, before, after);
        cursor += length;
    }
}

test "legacy types and every frozen authored constant preserve their exact value bytes" {
    for (fixtures) |fixture| try constantRoundTrips(std.testing.allocator, fixture);
}

test "allocation failures in type and constant lifting reclaim all partial results" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, constantRoundTrips, .{fixtures[2]});
}

test "every frozen BPI1 program lowers to admitted ordinary v2 code" {
    for (fixtures, 0..) |fixture, index| {
        var lifted = legacy.lift(std.testing.allocator, fixture) catch |err| {
            std.debug.print("lifting fixture {d}: {s}\n", .{ index, @errorName(err) });
            return err;
        };
        defer lifted.deinit();
        try std.testing.expect(lifted.program.blocks.len != 0);
        try std.testing.expectEqual(@as(usize, 0), lifted.program.handlers.len);
    }
}

fn liftOwned(allocator: std.mem.Allocator, fixture: []const u8) !void {
    const bytes = try allocator.dupe(u8, fixture);
    defer allocator.free(bytes);
    var result = try legacy.lift(allocator, bytes);
    defer result.deinit();
    @memset(bytes, 0xa5);
    // The complete owned result remains usable after the legacy input dies.
    const buffer = try allocator.alloc(u8, try data.image.encodedLength(result.program));
    defer allocator.free(buffer);
    _ = try data.image.encode(allocator, result.program, buffer);
}

test "immutable legacy operation fixtures cover all sixty frozen wire operations" {
    var covered = [_]bool{false} ** 60;
    for (fixtures) |fixture| {
        var decoded = try legacy.decode(std.testing.allocator, fixture);
        defer decoded.deinit();
        for (0..decoded.program.segment_count) |index| {
            const segment = try legacy.image.evaluatorSegmentRecord(decoded.program, @intCast(index));
            const parameters = std.mem.readInt(u16, segment[10..12], .little);
            const count = std.mem.readInt(u32, segment[12..16], .little);
            var cursor: usize = 16 + @as(usize, parameters) * 2;
            for (0..count) |_| {
                covered[std.mem.readInt(u16, segment[cursor + 6 ..][0..2], .little)] = true;
                cursor += std.mem.readInt(u32, segment[cursor..][0..4], .little);
            }
        }
    }
    for (covered) |seen| try std.testing.expect(seen);
}

test "lifting allocation failures reclaim parser, liveness, translation, and canonicalization storage" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, liftOwned, .{fixtures[7]});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, liftOwned, .{fixtures[17]});
}
