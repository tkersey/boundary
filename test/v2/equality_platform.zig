const std = @import("std");
const data = @import("boundary_data");
const fixtures = @import("equality_saturation.zig");
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const family = args.next() orelse return error.Family;
    const arm = args.next() orelse return error.Arm;
    if (args.next() != null) return error.Arguments;
    const original = if (std.mem.eql(u8, family, "xor")) fixtures.interaction else if (std.mem.eql(u8, family, "projection")) fixtures.projected else if (std.mem.eql(u8, family, "sharing")) fixtures.shared_product else return error.Family;
    if (std.mem.eql(u8, arm, "measure")) {
        if (@hasDecl(data, "equality_saturation")) {
            var search: [9]f64 = undefined;
            var proof: [9]f64 = undefined;
            var stats: data.equality_saturation.Statistics = .{};
            var bytes: usize = 0;
            for (0..12) |window| {
                const start = std.Io.Clock.awake.now(init.io);
                var candidate = (try data.equality_saturation.construct(init.gpa, original, &stats, .{})).?;
                defer candidate.deinit();
                const middle = std.Io.Clock.awake.now(init.io);
                try data.equality_saturation.validate(init.gpa, original, candidate.program, candidate.proof, .{});
                const end = std.Io.Clock.awake.now(init.io);
                var final = try data.coalescing.run(init.gpa, candidate.program, .{});
                defer final.deinit();
                bytes = try data.program_image.encodedLength(final.program);
                if (window >= 3) {
                    search[window - 3] = @floatFromInt(start.durationTo(middle).nanoseconds);
                    proof[window - 3] = @floatFromInt(middle.durationTo(end).nanoseconds);
                }
            }
            var buffer: [4096]u8 = undefined;
            var out = std.Io.File.stdout().writer(init.io, &buffer);
            try std.json.Stringify.value(.{ .searchNs = search, .proofNs = proof, .statistics = stats, .finalBytes = bytes }, .{}, &out.interface);
            try out.interface.writeByte('\n');
            try out.interface.flush();
            return;
        } else return error.Unavailable;
    }
    if (std.mem.eql(u8, arm, "checked")) {
        if (@hasDecl(data, "equality_saturation")) {
            var result = try data.equality_saturation.run(init.gpa, original, null, .{});
            defer result.deinit();
            return emit(init, result.program);
        } else return error.Unavailable;
    }
    if (std.mem.eql(u8, arm, "linked")) {
        const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{.{ .function = 0 }} };
        const bytes = try init.gpa.alloc(u8, try data.component.encodedLength(object));
        defer init.gpa.free(bytes);
        _ = try data.component.encode(init.gpa, object, bytes);
        var result = try data.linker.linkWithCompilation(init.gpa, &.{.{ .key = "equality", .object = bytes }}, &.{}, .{ .instance = "equality", .symbol = "main" }, .{ .contract = .semantic });
        defer result.deinit();
        @memset(bytes, 0xff);
        return emit(init, result.program);
    }
    if (!std.mem.eql(u8, arm, "structural") and !std.mem.eql(u8, arm, "semantic")) return error.Arm;
    var result = try data.closed_compilation.run(init.gpa, original, .{ .contract = if (std.mem.eql(u8, arm, "semantic")) .semantic else .structural });
    defer result.deinit();
    return emit(init, result.program);
}
fn emit(init: std.process.Init, program: data.activation.Program) !void {
    const bytes = try init.gpa.alloc(u8, try data.program_image.encodedLength(program));
    defer init.gpa.free(bytes);
    _ = try data.program_image.encode(init.gpa, program, bytes);
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    try out.interface.writeAll(bytes);
    try out.interface.flush();
}
