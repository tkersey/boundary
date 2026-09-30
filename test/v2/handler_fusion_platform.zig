const std = @import("std");
const data = @import("boundary_data");
const empty = @import("handler_elimination.zig");
const reader = @import("reader_fusion.zig");
const capture = @import("capture_unpack.zig");
const arguments = @import("call_pattern_retention.zig");
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
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const programs = [_]data.activation.Program{ empty.identity, try empty.composedReturns(arena.allocator()), reader.readers, try reader.composedReturns(arena.allocator()), try reader.reverseReaderEffects(arena.allocator(), reader.readers), try reader.reverseReaderEffects(arena.allocator(), try reader.composedReturns(arena.allocator())), try capture.retentionFixture(arena.allocator(), .closure), try capture.retentionFixture(arena.allocator(), .indirect_call), try capture.retentionFixture(arena.allocator(), .worker_input), try capture.retentionFixture(arena.allocator(), .before_construction), try capture.retentionFixture(arena.allocator(), .after_application) };
    for (programs, [_][]const u8{ "empty", "empty-composed", "reader", "reader-composed", "reader-reversed", "reader-composed-reversed", "capture-closure", "capture-indirect", "capture-worker", "capture-before", "capture-after" }, 0..) |original, name, index| {
        var baseline = try data.coalescing.run(init.gpa, original, .{});
        defer baseline.deinit();
        try save(init, directory, name, "structural", baseline.program);
        var compiled = try data.closed_compilation.run(init.gpa, original, .{ .contract = .semantic });
        defer compiled.deinit();
        try save(init, directory, name, "shared-semantic", compiled.program);
        if (index < 6) {
            var checked = if (index < 2) try data.handler_elimination.run(init.gpa, original, null, .{}) else try data.reader_fusion.run(init.gpa, original, null, .{});
            defer checked.deinit();
            try save(init, directory, name, "checked", checked.program);
        }
        const borrows = try arena.allocator().alloc(data.borrow_contract.Summary, original.functions.len);
        for (borrows, 0..) |*summary, id| summary.* = .{ .function = id };
        const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = original.roots.entry } }}, .borrows = borrows };
        const encoded = try init.gpa.alloc(u8, try data.component.encodedLength(object));
        defer init.gpa.free(encoded);
        _ = try data.component.encode(init.gpa, object, encoded);
        var linked = try data.linker.linkWithCompilation(init.gpa, &.{.{ .key = "handlers", .object = encoded }}, &.{}, .{ .instance = "handlers", .symbol = "main" }, .{ .contract = .semantic });
        defer linked.deinit();
        @memset(encoded, 0xff);
        try save(init, directory, name, "linked", linked.program);
    }
    inline for (@typeInfo(arguments.Case).@"enum".fields) |field| {
        const original = try arguments.fixture(arena.allocator(), @enumFromInt(field.value));
        const name = "argument-" ++ field.name;
        var baseline = try data.closed_compilation.run(init.gpa, original, .{});
        defer baseline.deinit();
        try save(init, directory, name, "structural", baseline.program);
        var checked = try data.call_patterns.run(init.gpa, original, null, .{});
        defer checked.deinit();
        try save(init, directory, name, "checked", checked.program);
        var semantic = try data.closed_compilation.run(init.gpa, original, .{ .contract = .semantic });
        defer semantic.deinit();
        try save(init, directory, name, "shared-semantic", semantic.program);
        var linked = try arguments.linked(init.gpa, original);
        defer linked.deinit();
        try save(init, directory, name, "linked", linked.program);
    }
}
