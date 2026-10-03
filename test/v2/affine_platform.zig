//! Emit admitted record fixtures for unchanged production World embeddings.
const std = @import("std");
const data = @import("boundary_data");
const fixtures = @import("affine_capture.zig");
fn writeCase(init: std.process.Init, directory: []const u8, name: []const u8, original: data.activation.Program, direct_affine: bool) !void {
    var baseline = try data.coalescing.run(init.gpa, original, .{});
    defer baseline.deinit();
    var candidate = if (direct_affine) try data.affine_state.run(init.gpa, original, 0, null, 10000000, .{}) else try data.closed_compilation.run(init.gpa, original, .{ .contract = .semantic });
    defer candidate.deinit();
    const programs = [_]data.activation.Program{ baseline.program, candidate.program };
    for (programs, [_][]const u8{ "structural", "semantic" }) |program, arm| {
        const bytes = try init.gpa.alloc(u8, try data.program_image.encodedLength(program));
        defer init.gpa.free(bytes);
        _ = try data.program_image.encode(init.gpa, program, bytes);
        const path = try init.gpa.print("{s}/{s}-{s}.bpi3", .{ directory, name, arm });
        defer init.gpa.free(path);
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = bytes });
    }
}
pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const directory = args.next() orelse return error.MissingOutputDirectory;
    if (args.next() != null) return error.UnexpectedArgument;
    try writeCase(init, directory, "rotating", fixtures.fixture, false);
    try writeCase(init, directory, "recurrent", comptime fixtures.recurrentFixture(), false);
    try writeCase(init, directory, "modes", comptime fixtures.twoModes(), false);
    try writeCase(init, directory, "parallel", fixtures.cyclic, false);
    try writeCase(init, directory, "product", fixtures.product_cycle, false);
    for ([_]usize{ 2, 3, 8, 32, 64, 128 }) |n| {
        var arena = std.heap.ArenaAllocator.init(init.gpa);
        defer arena.deinit();
        const name = try arena.allocator().print("parity-{d}", .{n});
        const original = try fixtures.parityFixture(arena.allocator(), n);
        try writeCase(init, directory, name, original, false);
        const direct = try arena.allocator().print("{s}-direct", .{name});
        try writeCase(init, directory, direct, original, true);
        if (n >= 8) {
            var parameters = original;
            const blocks = try arena.allocator().dupe(data.activation.Block, original.blocks);
            blocks[0].instructions = &.{};
            blocks[0].terminator = .{ .call = .{ .function = 1, .arguments = original.functions[0].inputs, .next = original.blocks[0].terminator.apply.next } };
            parameters.blocks = blocks;
            parameters.constructors = &.{};
            const parameter_name = try arena.allocator().print("parameters-{d}", .{n});
            try writeCase(init, directory, parameter_name, parameters, false);
        }
    }
}
