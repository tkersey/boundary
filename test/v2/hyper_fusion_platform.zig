const std = @import("std");
const boundary = @import("boundary");
const data = @import("boundary_data");
const hyper = @import("hyper_fusion.zig");
const memo = @import("hyper_memo.zig");
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
    for ([_][]const u8{ "identity", "ignored-peer", "ignored-fault", "reciprocal", "suspended", "configured", "reentrant", "memo-separate", "memo-shared", "black-hole" }, 0..) |name, index| {
        var b = boundary.source.Builder.init(init.gpa);
        defer b.deinit();
        const module = switch (index) {
            0 => try hyper.identityProject(&b),
            1 => try hyper.ignoredPeer(&b),
            2 => try hyper.ignoredFault(&b),
            3 => try hyper.reciprocal(&b),
            4 => try hyper.reciprocalSuspended(&b),
            5 => try hyper.configured(&b),
            6 => try hyper.reentrant(&b),
            7 => try memo.build(&b, false),
            8 => try memo.build(&b, true),
            9 => try memo.blackHole(&b),
            else => unreachable,
        };
        var original = try boundary.program.compile(init.gpa, module);
        defer original.deinit();
        try save(init, directory, name, "structural", original.program);
        var compiled = try data.closed_compilation.run(init.gpa, original.program, .{ .contract = .semantic });
        defer compiled.deinit();
        try save(init, directory, name, "shared-semantic", compiled.program);
        if (comptime @hasDecl(data, "thunk_forwarding")) {
            var checked = try data.thunk_forwarding.run(init.gpa, original.program, null, .{});
            defer checked.deinit();
            try save(init, directory, name, "checked", checked.program);
        }
        // The original reentrant fresh-region write cannot be published under
        // the existing component borrow vocabulary; keep this exclusion exact.
        if (index == 6) continue;
        var arena = std.heap.ArenaAllocator.init(init.gpa);
        defer arena.deinit();
        const contracts = try hyper.borrowContracts(arena.allocator(), original.program);
        const object: data.component.Object = .{ .program = original.program, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = original.program.roots.entry } }}, .borrows = contracts };
        const bmo = try init.gpa.alloc(u8, try data.component.encodedLength(object));
        defer init.gpa.free(bmo);
        _ = try data.component.encode(init.gpa, object, bmo);
        var linked = try data.linker.linkWithCompilation(init.gpa, &.{.{ .key = "hyper", .object = bmo }}, &.{}, .{ .instance = "hyper", .symbol = "main" }, .{ .contract = .semantic });
        defer linked.deinit();
        @memset(bmo, 0xff);
        try save(init, directory, name, "linked", linked.program);
    }
}
