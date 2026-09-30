const std = @import("std");
const data = @import("boundary_data");
const fixture = @import("application_specialization.zig");
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const mode = args.next() orelse return error.Mode;
    if (args.next() != null) return error.Arguments;
    if (std.mem.startsWith(u8, mode, "transfer-")) {
        var direct = try data.dead_computation.run(init.gpa, fixture.predecessor_transfer, null, .{});
        defer direct.deinit();
        var shared_transfer = try data.closed_compilation.run(init.gpa, fixture.predecessor_transfer, .{ .contract = .semantic });
        defer shared_transfer.deinit();
        const object: data.component.Object = .{ .program = fixture.predecessor_transfer, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = &.{.{ .function = 0 }} };
        const object_bytes = try init.gpa.alloc(u8, try data.component.encodedLength(object));
        defer init.gpa.free(object_bytes);
        _ = try data.component.encode(init.gpa, object, object_bytes);
        var linked = try data.linker.linkWithCompilation(init.gpa, &.{.{ .key = "transfer", .object = object_bytes }}, &.{}, .{ .instance = "transfer", .symbol = "main" }, .{ .contract = .semantic });
        defer linked.deinit();
        @memset(object_bytes, 0xff);
        const program = if (std.mem.eql(u8, mode, "transfer-original")) fixture.predecessor_transfer else if (std.mem.eql(u8, mode, "transfer-selected")) direct.program else if (std.mem.eql(u8, mode, "transfer-shared")) shared_transfer.program else if (std.mem.eql(u8, mode, "transfer-linked")) linked.program else return error.Mode;
        const bytes = try init.gpa.alloc(u8, try data.program_image.encodedLength(program));
        defer init.gpa.free(bytes);
        _ = try data.program_image.encode(init.gpa, program, bytes);
        var buffer: [4096]u8 = undefined;
        var out = std.Io.File.stdout().writer(init.io, &buffer);
        try out.interface.writeAll(bytes);
        try out.interface.flush();
        return;
    }
    var pruned = try data.branch_reduction.run(init.gpa, fixture.interaction, null, .{});
    defer pruned.deinit();
    var direct = try data.application_specialization.run(init.gpa, pruned.program, null, .{});
    defer direct.deinit();
    var selected = try data.dead_arguments.run(init.gpa, direct.program, null, .{});
    defer selected.deinit();
    var shared = try data.closed_compilation.run(init.gpa, fixture.interaction, .{ .contract = .semantic });
    defer shared.deinit();
    const program = if (std.mem.eql(u8, mode, "original")) fixture.interaction else if (std.mem.eql(u8, mode, "selected")) selected.program else if (std.mem.eql(u8, mode, "shared")) shared.program else return error.Mode;
    const bytes = try init.gpa.alloc(u8, try data.program_image.encodedLength(program));
    defer init.gpa.free(bytes);
    _ = try data.program_image.encode(init.gpa, program, bytes);
    var buffer: [4096]u8 = undefined;
    var out = std.Io.File.stdout().writer(init.io, &buffer);
    try out.interface.writeAll(bytes);
    try out.interface.flush();
}
