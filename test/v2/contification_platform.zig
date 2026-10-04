const std = @import("std");
const data = @import("boundary_data");
const fixtures = @import("contification.zig");
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
    const mode = args.next();
    const recursive = if (mode) |value| std.mem.eql(u8, value, "recursive") else false;
    if ((mode != null and !recursive) or args.next() != null) return error.Arguments;
    const fixture = if (recursive) fixtures.mutual else fixtures.shared;
    const names: []const []const u8 = if (recursive) &.{ "recursive-checked", "recursive-shared", "recursive-linked" } else &.{ "join-checked", "join-shared", "join-linked" };
    for (names, 0..) |name, index| {
        var baseline = try data.coalescing.run(init.gpa, fixture, .{});
        defer baseline.deinit();
        try save(init, directory, name, "structural", baseline.program);
        if (index == 2) {
            const object: data.component.Object = .{ .program = fixture, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = if (recursive) &.{ .{ .function = 0 }, .{ .function = 1 }, .{ .function = 2 } } else &.{ .{ .function = 0 }, .{ .function = 1 } } };
            const bytes = try init.gpa.alloc(u8, try data.component.encodedLength(object));
            defer init.gpa.free(bytes);
            _ = try data.component.encode(init.gpa, object, bytes);
            var linked = try data.linker.linkWithCompilation(init.gpa, &.{.{ .key = "join", .object = bytes }}, &.{}, .{ .instance = "join", .symbol = "main" }, .{ .contract = .semantic });
            defer linked.deinit();
            @memset(bytes, 0xff);
            try save(init, directory, name, "semantic", linked.program);
        } else {
            var candidate = if (index == 0) blk: {
                if (@hasDecl(data, "contification")) break :blk try data.contification.run(init.gpa, fixture, null, .{});
                break :blk try data.coalescing.run(init.gpa, fixture, .{});
            } else try data.closed_compilation.run(init.gpa, fixture, .{ .contract = .semantic });
            defer candidate.deinit();
            try save(init, directory, name, "semantic", candidate.program);
        }
    }
}
