//! Need behavior using existing scoped cells, not a new runtime memo facility.
const std = @import("std");
const boundary = @import("boundary");
const data = @import("boundary_data");
const world = @import("world");
const source = boundary.source;
const Id = source.Id;
const a = std.testing.allocator;
fn increment(b: *source.Builder, value: Id) !Id {
    return b.value(.{ .schema = try b.scalar(u64), .expression = .{ .primitive = .{ .opcode = .integer_add, .operands = &.{ value, try b.constant(u64, 1) }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = try b.failureLiteral(try b.constant(void, {})) }} } } });
}
pub fn build(b: *source.Builder, shared: bool) !source.Module {
    const unit = try b.scalar(void);
    const boolean = try b.scalar(bool);
    const integer = try b.scalar(u64);
    const result = try b.schema(.{ .product = &.{ integer, integer, integer, integer } });
    const region = b.region();
    const token = try b.schema(.{ .internal = .{ .region = region } });
    const ready_type = try b.schema(.{ .internal = .{ .cell = .{ .region = region, .element = boolean } } });
    const value_type = try b.schema(.{ .internal = .{ .cell = .{ .region = region, .element = integer } } });
    const force = try b.declare(&.{ ready_type, value_type, value_type }, integer, &.{}, &.{region});
    const ready = try b.reference(b.parameter(force, 0));
    const cached = try b.reference(b.parameter(force, 1));
    const counter = try b.reference(b.parameter(force, 2));
    const next = try b.variable(integer);
    const publish_ready = try b.bind(try b.variable(unit), try b.pure(try b.primitive(unit, .cell_set, &.{ ready, try b.constant(bool, true) }, 0)), try b.pure(try b.reference(next)));
    const publish_value = try b.bind(try b.variable(unit), try b.pure(try b.primitive(unit, .cell_set, &.{ cached, try b.reference(next) }, 0)), publish_ready);
    const count = try b.bind(try b.variable(unit), try b.pure(try b.primitive(unit, .cell_set, &.{ counter, try b.reference(next) }, 0)), publish_value);
    const compute = try b.bind(next, try b.pure(try increment(b, try b.primitive(integer, .cell_get, &.{counter}, 0))), count);
    try b.define(force, try b.term(.{ .conditional = .{ .condition = try b.primitive(boolean, .cell_get, &.{ready}, 0), .when_true = try b.pure(try b.primitive(integer, .cell_get, &.{cached}, 0)), .when_false = compute } }));
    const body = try b.declare(&.{token}, result, &.{}, &.{region});
    const calls = try b.variable(value_type);
    const first_ready = try b.variable(ready_type);
    const first_value = try b.variable(value_type);
    const second_ready = try b.variable(ready_type);
    const second_value = try b.variable(value_type);
    const one = try b.variable(integer);
    const two = try b.variable(integer);
    const three = try b.variable(integer);
    const row = try b.primitive(result, .product, &.{ try b.reference(one), try b.reference(two), try b.reference(three), try b.primitive(integer, .cell_get, &.{try b.reference(calls)}, 0) }, 0);
    const first_arguments = [_]Id{ try b.reference(first_ready), try b.reference(first_value), try b.reference(calls) };
    const last_arguments = [_]Id{ try b.reference(second_ready), try b.reference(second_value), try b.reference(calls) };
    const observe = try b.bind(one, try b.term(.{ .call = .{ .function = force, .arguments = &first_arguments } }), try b.bind(two, try b.term(.{ .call = .{ .function = force, .arguments = &first_arguments } }), try b.bind(three, try b.term(.{ .call = .{ .function = force, .arguments = &last_arguments } }), try b.pure(row))));
    const r = try b.reference(b.parameter(body, 0));
    const right_value = if (shared) try b.reference(first_value) else try b.primitive(value_type, .cell_new, &.{ r, try b.constant(u64, 0) }, 0);
    const right_ready = if (shared) try b.reference(first_ready) else try b.primitive(ready_type, .cell_new, &.{ r, try b.constant(bool, false) }, 0);
    const right = try b.bind(second_ready, try b.pure(right_ready), try b.bind(second_value, try b.pure(right_value), observe));
    const left = try b.bind(first_ready, try b.pure(try b.primitive(ready_type, .cell_new, &.{ r, try b.constant(bool, false) }, 0)), try b.bind(first_value, try b.pure(try b.primitive(value_type, .cell_new, &.{ r, try b.constant(u64, 0) }, 0)), right));
    try b.define(body, try b.bind(calls, try b.pure(try b.primitive(value_type, .cell_new, &.{ r, try b.constant(u64, 0) }, 0)), left));
    const body_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{token}, .result = result, .regions = &.{region} } } });
    const main = try b.declare(&.{}, result, &.{}, &.{});
    try b.define(main, try b.term(.{ .with_region = .{ .region = region, .body = try b.lambda(body, body_type) } }));
    return b.module(main, unit);
}
fn cells(program: data.activation.Program) usize {
    var count: usize = 0;
    for (program.blocks) |block| for (block.instructions) |op| {
        count += @intFromBool(op.opcode == .cell_new);
    };
    return count;
}
test "repeated need demand retains distinct cells and deliberately shared cells" {
    for ([_]bool{ false, true }) |shared| {
        var b = source.Builder.init(a);
        defer b.deinit();
        var original = try boundary.program.compile(a, try build(&b, shared));
        defer original.deinit();
        var checked = try data.thunk_forwarding.run(a, original.program, null, .{});
        defer checked.deinit();
        try std.testing.expectEqual(cells(original.program), cells(checked.program));
        try std.testing.expectEqual(@as(usize, if (shared) 3 else 5), cells(checked.program));
        var compiled = try data.closed_compilation.run(a, original.program, .{ .contract = .semantic });
        defer compiled.deinit();
        var expected: [32]u8 = undefined;
        for ([_]u64{ 1, 1, if (shared) 1 else 2, if (shared) 1 else 2 }, 0..) |value, i| std.mem.writeInt(u64, expected[i * 8 ..][0..8], value, .little);
        for ([_]data.activation.Program{ original.program, checked.program, compiled.program }) |program| {
            const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
            defer a.free(bytes);
            _ = try data.program_image.encode(a, program, bytes);
            var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &.{} }, .quantum = 1 });
            defer outcome.deinit();
            var steps: usize = 0;
            while (outcome.record == .progressed) {
                try std.testing.expect(steps < 512);
                const next = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .state = outcome.record.progressed.? }, .quantum = 1 });
                outcome.deinit();
                outcome = next;
                steps += 1;
            }
            try std.testing.expect(outcome.record == .completed);
            try std.testing.expectEqualSlices(u8, &expected, outcome.record.completed);
        }
    }
}

/// An authored busy-cell guard rejects a recursive force before computing a
/// second result. This uses ordinary cells/failure, not a kernel black-hole mode.
pub fn blackHole(b: *source.Builder) !source.Module {
    const unit = try b.scalar(void);
    const boolean = try b.scalar(bool);
    const integer = try b.scalar(u64);
    const region = b.region();
    const token = try b.schema(.{ .internal = .{ .region = region } });
    const cell = try b.schema(.{ .internal = .{ .cell = .{ .element = boolean, .region = region } } });
    const force = try b.declare(&.{cell}, integer, &.{}, &.{region});
    const busy = try b.reference(b.parameter(force, 0));
    const reenter = try b.bind(try b.variable(unit), try b.pure(try b.primitive(unit, .cell_set, &.{ busy, try b.constant(bool, true) }, 0)), try b.term(.{ .call = .{ .function = force, .arguments = &.{busy} } }));
    try b.define(force, try b.term(.{ .conditional = .{ .condition = try b.primitive(boolean, .cell_get, &.{busy}, 0), .when_true = try b.term(.{ .fail = try b.constant(void, {}) }), .when_false = reenter } }));
    const body = try b.declare(&.{token}, integer, &.{}, &.{region});
    const allocated = try b.variable(cell);
    try b.define(body, try b.bind(allocated, try b.pure(try b.primitive(cell, .cell_new, &.{ try b.reference(b.parameter(body, 0)), try b.constant(bool, false) }, 0)), try b.term(.{ .call = .{ .function = force, .arguments = &.{try b.reference(allocated)} } })));
    const schema = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{token}, .result = integer, .regions = &.{region} } } });
    const main = try b.declare(&.{}, integer, &.{}, &.{});
    try b.define(main, try b.term(.{ .with_region = .{ .region = region, .body = try b.lambda(body, schema) } }));
    return b.module(main, unit);
}
test "authored black-hole guard survives reentrant force and interruption" {
    var b = source.Builder.init(a);
    defer b.deinit();
    var original = try boundary.program.compile(a, try blackHole(&b));
    defer original.deinit();
    var checked = try data.thunk_forwarding.run(a, original.program, null, .{});
    defer checked.deinit();
    try std.testing.expectEqual(try data.program_image.identity(a, original.program), try data.program_image.identity(a, checked.program));
    var compiled = try data.closed_compilation.run(a, original.program, .{ .contract = .semantic });
    defer compiled.deinit();
    for ([_]data.activation.Program{ original.program, checked.program, compiled.program }) |program| {
        const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
        defer a.free(bytes);
        _ = try data.program_image.encode(a, program, bytes);
        var outcome = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = &.{} }, .quantum = 1 });
        defer outcome.deinit();
        var steps: usize = 0;
        while (outcome.record == .progressed) {
            try std.testing.expect(steps < 256);
            const next = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .state = outcome.record.progressed.? }, .quantum = 1 });
            outcome.deinit();
            outcome = next;
            steps += 1;
        }
        try std.testing.expect(outcome.record == .failed);
        try std.testing.expectEqualSlices(u8, &.{}, outcome.record.failed.value);
    }
}
