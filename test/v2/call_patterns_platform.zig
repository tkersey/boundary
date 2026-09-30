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
    const mode = args.next();
    const variants = if (mode) |name| std.mem.eql(u8, name, "variants") else false;
    const constants = if (mode) |name| std.mem.eql(u8, name, "constants") else false;
    const word_mode = if (mode) |name| std.mem.eql(u8, name, "words") else false;
    const captures = if (mode) |name| std.mem.eql(u8, name, "captures") else false;
    if ((mode != null and !variants and !constants and !word_mode and !captures) or args.next() != null) return error.Arguments;
    const names: []const []const u8 = if (captures) &.{ "capture-checked", "capture-shared", "capture-linked" } else if (word_mode) &.{ "word-checked", "word-shared", "word-linked" } else if (constants) &.{ "constant-checked", "constant-shared", "constant-linked" } else if (variants) &.{ "variant-fallback-checked", "variant-fallback-shared", "variant-fallback-linked", "variant-total-checked", "variant-total-shared", "variant-total-linked", "variant-overwritten-checked", "variant-overwritten-shared", "variant-overwritten-linked", "variant-payload-checked", "variant-payload-shared", "variant-payload-linked" } else &.{ "callable-checked", "callable-shared", "callable-linked" };
    for (names, 0..) |name, index| {
        var original = if (captures) fixtures.captured else if (word_mode) fixtures.word_constants else if (constants) fixtures.choice else if (variants) fixtures.tagged else fixtures.repeated;
        var blocks: [9]data.activation.Block = undefined;
        @memcpy(blocks[0..7], fixtures.tagged.blocks);
        if (variants) {
            if (index / 3 == 1) blocks[4].instructions = fixtures.tagged.blocks[1].instructions;
            if (index / 3 == 2) blocks[1].instructions = &.{ fixtures.tagged.blocks[1].instructions[0], .{ .destination = 0, .opcode = .integer_bit_not, .operands = &.{0} } };
            if (index / 3 == 3) {
                blocks[6].instructions = &.{};
                blocks[6].terminator = .{ .switch_variant = .{ .value = 0, .cases = &.{
                    .{ .block = 7, .assignments = &.{.{ .destination = 1, .source = .returned }} },
                    .{ .block = 8, .assignments = &.{.{ .destination = 1, .source = .returned }} },
                } } };
                blocks[7] = .{ .function = 1, .instructions = &.{}, .terminator = .{ .return_value = 1 } };
                blocks[8] = blocks[7];
            }
            original.blocks = blocks[0..(if (index / 3 == 3) @as(usize, 9) else 7)];
        }
        var baseline = try data.coalescing.run(init.gpa, original, .{});
        defer baseline.deinit();
        try save(init, directory, name, "structural", baseline.program);
        if (index % 3 == 2) {
            const object: data.component.Object = .{ .program = original, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = 0 } }}, .borrows = if (variants or constants or word_mode) &.{ .{ .function = 0 }, .{ .function = 1 } } else &.{ .{ .function = 0 }, .{ .function = 1 }, .{ .function = 2 }, .{ .function = 3 } } };
            const bytes = try init.gpa.alloc(u8, try data.component.encodedLength(object));
            defer init.gpa.free(bytes);
            _ = try data.component.encode(init.gpa, object, bytes);
            var linked = try data.linker.linkWithCompilation(init.gpa, &.{.{ .key = "object", .object = bytes }}, &.{}, .{ .instance = "object", .symbol = "main" }, .{ .contract = .semantic });
            defer linked.deinit();
            @memset(bytes, 0xff);
            try save(init, directory, name, "semantic", linked.program);
        } else {
            var candidate = if (index % 3 == 0) blk: {
                if (@hasDecl(data, "call_patterns")) break :blk try data.call_patterns.run(init.gpa, original, null, .{});
                break :blk try data.coalescing.run(init.gpa, original, .{});
            } else try data.closed_compilation.run(init.gpa, original, .{ .contract = .semantic });
            defer candidate.deinit();
            try save(init, directory, name, "semantic", candidate.program);
        }
    }
}
