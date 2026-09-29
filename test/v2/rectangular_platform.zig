const std = @import("std");
const data = @import("boundary_data");
const fixtures = @import("rectangular.zig");
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const rows = try std.fmt.parseInt(u64, args.next() orelse return error.Rows, 10);
    const columns = try std.fmt.parseInt(u64, args.next() orelse return error.Columns, 10);
    const arm = args.next() orelse return error.Arm;
    if (args.next() != null) return error.Arguments;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const original = try fixtures.rectangle(a, rows, columns);
    if (std.mem.eql(u8, arm, "tiled")) {
        if (@hasDecl(data, "rectangular_tiling")) {
            var candidate = (try data.rectangular_tiling.construct(a, original, .{})).?;
            defer candidate.deinit();
            try data.rectangular_tiling.validate(a, original, candidate.program, candidate.source, .{});
            var result = try data.coalescing.run(a, candidate.program, .{});
            defer result.deinit();
            return emit(init, result.program);
        } else return error.Unavailable;
    }
    if (std.mem.eql(u8, arm, "linked")) {
        const borrows = try a.alloc(data.borrow_contract.Summary, original.functions.len);
        for (borrows, 0..) |*summary, id| summary.* = .{ .function = id };
        const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = original.roots.entry } }}, .borrows = borrows };
        const object_bytes = try a.alloc(u8, try data.component.encodedLength(object));
        _ = try data.component.encode(a, object, object_bytes);
        var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "context", .object = object_bytes }}, &.{}, .{ .instance = "context", .symbol = "main" }, .{ .contract = .semantic });
        defer linked.deinit();
        @memset(object_bytes, 0xff);
        return emit(init, linked.program);
    }
    if (!std.mem.eql(u8, arm, "structural") and !std.mem.eql(u8, arm, "semantic")) return error.Arm;
    var compiled = try data.closed_compilation.run(a, original, .{ .contract = if (std.mem.eql(u8, arm, "structural")) .structural else .semantic });
    defer compiled.deinit();
    return emit(init, compiled.program);
}
fn emit(init: std.process.Init, program: data.activation.Program) !void {
    const bytes = try init.gpa.alloc(u8, try data.program_image.encodedLength(program));
    defer init.gpa.free(bytes);
    _ = try data.program_image.encode(init.gpa, program, bytes);
    var buffer: [4096]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.writeAll(bytes);
    try output.interface.flush();
}
