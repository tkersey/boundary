const std = @import("std");
const data = @import("boundary_data");
fn save(init: std.process.Init, directory: []const u8, name: []const u8, arm: []const u8, program: data.activation.Program) !void {
    const bytes = try init.gpa.alloc(u8, try data.program_image.encodedLength(program));
    defer init.gpa.free(bytes);
    _ = try data.program_image.encode(init.gpa, program, bytes);
    const path = try init.gpa.print("{s}/{s}-{s}.bpi3", .{ directory, name, arm });
    defer init.gpa.free(path);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = bytes });
}
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const directory = args.next() orelse return error.Directory;
    if (args.next() != null) return error.Arguments;
    const fixture = @import("slot_packing.zig").threshold;
    for ([_][]const u8{ "packing-checked", "packing-shared", "packing-linked" }, 0..) |name, index| {
        var baseline = try data.coalescing.run(init.gpa, fixture, .{});
        defer baseline.deinit();
        try save(init, directory, name, "structural", baseline.program);
        if (index == 2) {
            const object: data.component.Object = .{ .program = fixture, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{.{ .function = 0 }} };
            const bytes = try init.gpa.alloc(u8, try data.component.encodedLength(object));
            defer init.gpa.free(bytes);
            _ = try data.component.encode(init.gpa, object, bytes);
            var linked = try data.linker.linkWithCompilation(init.gpa, &.{.{ .key = "packing", .object = bytes }}, &.{}, .{ .instance = "packing", .symbol = "main" }, .{ .contract = .semantic });
            defer linked.deinit();
            @memset(bytes, 0xff);
            try save(init, directory, name, "semantic", linked.program);
        } else {
            var candidate = if (index == 0) blk: {
                if (@hasDecl(data, "slot_packing")) break :blk try data.slot_packing.run(init.gpa, fixture, null, .{});
                break :blk try data.coalescing.run(init.gpa, fixture, .{});
            } else try data.closed_compilation.run(init.gpa, fixture, .{ .contract = .semantic });
            defer candidate.deinit();
            try save(init, directory, name, "semantic", candidate.program);
        }
    }
}
