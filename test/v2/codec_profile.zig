//! Already-built codec phases on a fixed admitted Program, separate from authoring.
const std = @import("std");
const data = @import("boundary_data_v2");
const Row = struct {
    legacy_size_ns: i96,
    identity_ns: i96,
    legacy_encode_ns: i96,
    compact_size_ns: ?i96 = null,
    compact_encode_ns: ?i96 = null,
};

fn elapsed(io: std.Io, start: std.Io.Timestamp) i96 {
    return start.durationTo(std.Io.Clock.awake.now(io)).nanoseconds;
}

fn measure(init: std.process.Init, program: data.program.Program, old: []u8, new: []u8) !Row {
    var start = std.Io.Clock.awake.now(init.io);
    std.mem.doNotOptimizeAway(try data.image.encodedLength(program));
    const sized = elapsed(init.io, start);
    start = std.Io.Clock.awake.now(init.io);
    std.mem.doNotOptimizeAway(try data.image.identity(program));
    const identified = elapsed(init.io, start);
    start = std.Io.Clock.awake.now(init.io);
    _ = try data.image.encode(init.gpa, program, old);
    var result: Row = .{ .legacy_size_ns = sized, .identity_ns = identified, .legacy_encode_ns = elapsed(init.io, start) };
    if (comptime @hasDecl(data, "compact_image")) {
        start = std.Io.Clock.awake.now(init.io);
        std.mem.doNotOptimizeAway(try data.compact_image.encodedLength(init.gpa, program));
        result.compact_size_ns = elapsed(init.io, start);
        start = std.Io.Clock.awake.now(init.io);
        _ = try data.compact_image.encode(init.gpa, program, new);
        result.compact_encode_ns = elapsed(init.io, start);
    }
    return result;
}

pub fn main(init: std.process.Init) !void {
    var input_buffer: [4096]u8 = undefined;
    var input = std.Io.File.stdin().reader(init.io, &input_buffer);
    const bytes = try input.interface.allocRemaining(init.gpa, .unlimited);
    defer init.gpa.free(bytes);
    var decoded = try data.image.decode(init.gpa, bytes);
    defer decoded.deinit();
    const old = try init.gpa.alloc(u8, try data.image.encodedLength(decoded.program));
    defer init.gpa.free(old);
    const length = if (comptime @hasDecl(data, "compact_image"))
        try data.compact_image.encodedLength(init.gpa, decoded.program)
    else
        old.len;
    const new = try init.gpa.alloc(u8, length);
    defer init.gpa.free(new);
    for (0..5) |_| _ = try measure(init, decoded.program, old, new);
    var rows: [21]Row = undefined;
    for (&rows) |*row| row.* = try measure(init, decoded.program, old, new);
    try std.testing.expectEqualSlices(u8, bytes, old);
    var output_buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &output_buffer);
    try std.json.Stringify.value(.{ .image_bytes = bytes.len, .compact_bytes = length, .image_sha256 = std.fmt.bytesToHex(data.wire.digest(bytes), .lower), .method = "single-operation native phases, five warmups and 21 observations; output allocation excluded", .rows = rows }, .{}, &output.interface);
    try output.interface.writeByte('\n');
    try output.interface.flush();
}
