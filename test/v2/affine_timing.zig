//! Uninstrumented synthetic admission and complete fresh-invocation observations.
const std = @import("std");
const data = @import("boundary_data");
const world = @import("world");
const fixture = @import("affine_capture.zig");
pub fn main(init: std.process.Init) !void {
    const a = init.gpa;
    const original = comptime fixture.recurrentFixture();
    var program = try data.closed_compilation.run(a, original, .{ .contract = .semantic });
    defer program.deinit();
    const bytes = try a.alloc(u8, try data.program_image.encodedLength(program.program));
    defer a.free(bytes);
    _ = try data.program_image.encode(a, program.program, bytes);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    var args: [33]u8 = undefined;
    for ([_]u64{ 1, 2, 4, 8 }, 0..) |value, i| std.mem.writeInt(u64, args[i * 8 ..][0..8], value, .little);
    args[32] = 31;
    var p: u64 = 1;
    var q: u64 = 2;
    var r: u64 = 4;
    for (0..31) |_| {
        const old = p;
        p = q;
        q = r;
        r = old ^ 8 ^ 0xa5;
    }
    var expected: [8]u8 = undefined;
    std.mem.writeInt(u64, &expected, p ^ q ^ 8 ^ 0xa5, .little);
    var admission: [9]u64 = undefined;
    var execution: [9]u64 = undefined;
    const storage = try a.alloc(u8, 64 << 20);
    defer a.free(storage);
    for (0..12) |round| {
        var admit_ns: u64 = 0;
        var invoke_ns: u64 = 0;
        for (0..64) |_| {
            var workspace = world.Workspace.init(storage);
            const start = std.Io.Clock.awake.now(init.io);
            var prepared = try world.Prepared.init(workspace.allocator(), bytes);
            admit_ns += @intCast(start.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds);
            prepared.deinit();
            const invoked = std.Io.Clock.awake.now(init.io);
            var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
            invoke_ns += @intCast(invoked.durationTo(std.Io.Clock.awake.now(init.io)).nanoseconds);
            defer outcome.deinit();
            if (outcome.record != .completed or !std.mem.eql(u8, &expected, outcome.record.completed)) return error.WrongResult;
        }
        if (round >= 3) {
            admission[round - 3] = admit_ns / 64;
            execution[round - 3] = invoke_ns / 64;
        }
    }
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    try std.json.Stringify.value(.{ .imageSha256 = std.fmt.bytesToHex(digest, .lower), .admissionNs = admission, .freshInvocationNs = execution, .warmups = 3, .batch = 64, .samples = 9 }, .{}, &out.interface);
    try out.interface.writeByte('\n');
    try out.interface.flush();
}
