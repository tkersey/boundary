const std = @import("std");
const data = @import("boundary_data");
const fixtures = @import("call_patterns.zig");
fn save(init: std.process.Init, directory: []const u8, name: []const u8, arm: []const u8, program: data.activation.Program) !void {
    const bytes = try init.gpa.alloc(u8, try data.program_image.encodedLength(program));
    defer init.gpa.free(bytes);
    _ = try data.program_image.encode(init.gpa, program, bytes);
    const path = try std.fmt.allocPrint(init.gpa, "{s}/{s}-{s}.bpi3", .{ directory, name, arm });
    defer init.gpa.free(path);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = bytes });
}
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const directory = args.next() orelse return error.Directory;
    if (args.next() != null) return error.Arguments;
    for ([_][]const u8{ "callable-checked", "callable-shared", "callable-linked" }, 0..) |name, index| {
        const original = fixtures.repeated;
        var baseline = try data.coalescing.run(init.gpa, original, .{});
        defer baseline.deinit();
        try save(init, directory, name, "structural", baseline.program);
        if (index == 2) {
            const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{ .{ .function = 0 }, .{ .function = 1 }, .{ .function = 2 }, .{ .function = 3 } } };
            const bytes = try init.gpa.alloc(u8, try data.component.encodedLength(object));
            defer init.gpa.free(bytes);
            _ = try data.component.encode(init.gpa, object, bytes);
            var linked = try data.linker.linkWithCompilation(init.gpa, &.{.{ .key = "object", .object = bytes }}, &.{}, .{ .instance = "object", .symbol = "main" }, .{ .contract = .semantic });
            defer linked.deinit();
            @memset(bytes, 0xff);
            try save(init, directory, name, "semantic", linked.program);
        } else {
            var candidate = if (index == 0) blk: {
                if (@hasDecl(data, "call_patterns")) break :blk try data.call_patterns.run(init.gpa, original, null, .{});
                break :blk try data.coalescing.run(init.gpa, original, .{});
            } else try data.closed_compilation.run(init.gpa, original, .{ .contract = .semantic });
            defer candidate.deinit();
            try save(init, directory, name, "semantic", candidate.program);
        }
    }
}
