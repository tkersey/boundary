const std = @import("std");
const data = @import("boundary_data");
const fixtures = @import("evidence_forwarding.zig");
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
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    for ([_]bool{ false, true }) |nested| {
        const original = if (nested) try fixtures.nestedFixture(arena.allocator()) else try fixtures.fixture(arena.allocator());
        const names = if (nested) [_][]const u8{ "nested-checked", "nested-shared", "nested-linked" } else [_][]const u8{ "evidence-checked", "evidence-shared", "evidence-linked" };
        for (names, 0..) |name, index| {
            var baseline = try data.coalescing.run(init.gpa, original, .{});
            defer baseline.deinit();
            try save(init, directory, name, "structural", baseline.program);
            if (index == 2) {
                const borrows = try arena.allocator().alloc(data.borrow_contract.Summary, original.functions.len);
                for (borrows, 0..) |*summary, id| summary.* = .{ .function = id };
                const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = borrows };
                const encoded = try init.gpa.alloc(u8, try data.component.encodedLength(object));
                defer init.gpa.free(encoded);
                _ = try data.component.encode(init.gpa, object, encoded);
                var result = try data.linker.linkWithCompilation(init.gpa, &.{.{ .key = "evidence", .object = encoded }}, &.{}, .{ .instance = "evidence", .symbol = "main" }, .{ .contract = .semantic });
                defer result.deinit();
                @memset(encoded, 0xff);
                try save(init, directory, name, "semantic", result.program);
            } else {
                var result = if (index == 0) try data.evidence_forwarding.run(init.gpa, original, null, .{}) else try data.closed_compilation.run(init.gpa, original, .{ .contract = .semantic });
                defer result.deinit();
                try save(init, directory, name, "semantic", result.program);
            }
        }
        if (nested) {
            var forged = original;
            const blocks = try arena.allocator().dupe(data.activation.Block, original.blocks);
            blocks[9].terminator.perform.capability = 0;
            forged.blocks = blocks;
            try save(init, directory, "nested-forged", "semantic", forged);
        }
    }
}
