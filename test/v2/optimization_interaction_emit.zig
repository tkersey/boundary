const std = @import("std");
const data = @import("boundary_data");
const fixture = @import("application_specialization.zig");
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const mode = args.next() orelse return error.Mode;
    if (args.next() != null) return error.Arguments;
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
