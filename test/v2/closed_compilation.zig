const std = @import("std");
const boundary = @import("boundary");
const world = @import("world");
const data = boundary.data;

fn authored(allocator: std.mem.Allocator, contract: data.closed_compilation.Contract, stats: *data.closed_compilation.Statistics) !boundary.source.Compiled {
    var raw = boundary.source.Builder.init(allocator);
    defer raw.deinit();
    const c = try boundary.authoring.Context.init(&raw);
    const integer = try c.scalar(u64);
    const unit = try c.scalar(void);
    const entry = try c.function("entry", &.{.{ .name = "x", .schema = integer }}, integer, &.{});
    const body = try c.body(entry);
    const x = try body.parameter("x");
    const schema = try c.callable(&.{}, integer, &.{}, .{ .use = .reusable, .captures = &.{integer} });
    const nested = try c.functionFor("nested", schema);
    const inner = try body.closureBody(nested);
    try c.define(nested, try inner.ret(x));
    try c.define(entry, try body.ret(try body.apply(try body.lambda(nested, schema), &.{})));
    return c.compileWithCompilation(allocator, entry, unit, .{ .contract = contract, .statistics = stats });
}

test "World executes typed structural and semantic images after all source owners are released" {
    const a = std.testing.allocator;
    for ([_]data.closed_compilation.Contract{ .structural, .semantic }) |contract| {
        var stats: data.closed_compilation.Statistics = .{};
        var compiled = try authored(a, contract, &stats);
        defer compiled.deinit();
        if (contract == .semantic) try std.testing.expect(stats.outcome == .applied);
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(compiled.program));
        defer a.free(bytes);
        _ = try compiled.encode(a, bytes);
        for ([_]u64{ 0, 21, 999 }) |value| {
            var args: [8]u8 = undefined;
            std.mem.writeInt(u64, &args, value, .little);
            var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &args } });
            defer result.deinit();
            try std.testing.expect(result.record == .completed);
            try std.testing.expectEqualSlices(u8, &args, result.record.completed);
        }
    }
}
