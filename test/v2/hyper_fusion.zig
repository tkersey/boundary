const std = @import("std");
const boundary = @import("boundary");
const data = @import("boundary_data");
const world = @import("world");
const source = boundary.source;
const hyper = boundary.library.hyper;
const a = std.testing.allocator;
pub fn borrowContracts(allocator: std.mem.Allocator, program: data.activation.Program) ![]data.borrow_contract.Summary {
    const schemas = try data.admission.schemas(allocator, program.schemas);
    var solver = try data.borrow_flow.contracted(allocator, program, &.{}, schemas.exportable, &.{});
    // These objects export only the entry function. Internal functions retain
    // their normal body checks without inventing additional public contracts.
    const summaries = try allocator.alloc(data.borrow_contract.Summary, 1);
    summaries[0] = try data.borrow_contract.infer(&solver, program.roots.entry);
    return summaries;
}
pub fn identityProject(b: *source.Builder) !source.Module {
    const boolean = try b.scalar(bool);
    const types = try hyper.pair(b, boolean, boolean);
    const main = try b.declare(&.{boolean}, boolean, &.{}, &.{});
    const participant = try b.variable(types.forward);
    const answer = try b.variable(types.answer_forward);
    const argument = try hyper.deferValue(b, types.answer_backward, try b.reference(b.parameter(main, 0)));
    const projected = try hyper.project(b, types, try b.reference(participant), argument);
    try b.define(main, try b.bind(participant, try hyper.identity(b, types), try b.bind(answer, projected, try hyper.force(b, try b.reference(answer)))));
    return b.module(main, try b.scalar(void));
}
// This ordinary staged eta wrapper isolates the layer while the wrapped answer
// still contains the complete generated reciprocal participant graph.
fn wrapper(b: *source.Builder, schema: source.Id, value: source.Id) !source.Id {
    const result = b.schemas.items[@intCast(schema)].internal.computation.result;
    const factory = try b.declare(&.{schema}, schema, &.{}, &.{});
    const thunk = try b.declare(&.{}, result, &.{}, &.{});
    try b.define(thunk, try hyper.force(b, try b.reference(b.parameter(factory, 0))));
    try b.define(factory, try b.pure(try b.lambda(thunk, schema)));
    const forwarded = try b.variable(schema);
    return b.bind(forwarded, try b.term(.{ .call = .{ .function = factory, .arguments = &.{value} } }), try hyper.force(b, try b.reference(forwarded)));
}
pub fn ignoredPeer(b: *source.Builder) !source.Module {
    const boolean = try b.scalar(bool);
    const types = try hyper.pair(b, boolean, boolean);
    const main = try b.declare(&.{boolean}, boolean, &.{}, &.{});
    const peer = try b.declare(&.{}, types.backward, &.{}, &.{});
    try b.define(peer, try b.term(.{ .call = .{ .function = peer, .arguments = &.{} } }));
    const participant = try hyper.base(b, types, try hyper.deferValue(b, types.answer_forward, try b.reference(b.parameter(main, 0))));
    const answer = try b.variable(types.answer_forward);
    const invoked = try hyper.invoke(b, participant, try b.lambda(peer, types.peer_backward));
    try b.define(main, try b.bind(answer, invoked, try wrapper(b, types.answer_forward, try b.reference(answer))));
    return b.module(main, try b.scalar(void));
}
pub fn ignoredFault(b: *source.Builder) !source.Module {
    const boolean = try b.scalar(bool);
    const types = try hyper.pair(b, boolean, boolean);
    const main = try b.declare(&.{boolean}, boolean, &.{}, &.{});
    const fault = try b.declare(&.{}, boolean, &.{}, &.{});
    try b.define(fault, try b.term(.{ .fail = try b.constant(void, {}) }));
    const participant = try hyper.base(b, types, try hyper.deferValue(b, types.answer_forward, try b.reference(b.parameter(main, 0))));
    const answer = try b.variable(types.answer_forward);
    const projected = try hyper.project(b, types, participant, try b.lambda(fault, types.answer_backward));
    try b.define(main, try b.bind(answer, projected, try wrapper(b, types.answer_forward, try b.reference(answer))));
    return b.module(main, try b.scalar(void));
}
fn add(b: *source.Builder, left: source.Id, right: source.Id) !source.Id {
    return b.value(.{ .schema = try b.scalar(u64), .expression = .{ .primitive = .{ .opcode = .integer_add, .operands = &.{ left, right }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = try b.failureLiteral(try b.constant(void, {})) }} } } });
}
fn reciprocalStep(b: *source.Builder, query: hyper.Query, stop: bool, increment: u64, suspended: bool) !source.Id {
    const integer = try b.scalar(u64);
    const thunk = try b.declare(&.{}, integer, &.{}, &.{});
    const delayed = try b.variable(query.types.answer_backward);
    const answer = try b.variable(integer);
    const nested = try b.bind(delayed, try query.ask(b, try b.constant(bool, true)), try b.bind(answer, try hyper.force(b, try b.reference(delayed)), try b.pure(try add(b, try b.reference(answer), try b.constant(u64, increment)))));
    const body = if (stop) try b.term(.{ .conditional = .{ .condition = query.state, .when_true = try b.pure(try b.constant(u64, 19)), .when_false = nested } }) else nested;
    try b.define(thunk, if (suspended) try b.term(.{ .yield_then = body }) else body);
    return b.pure(try b.lambda(thunk, query.types.answer_forward));
}
const Producer = struct {
    var suspended = false;
    pub fn emit(b: *source.Builder, query: hyper.Query) !source.Id {
        return reciprocalStep(b, query, false, 10, suspended);
    }
};
const Consumer = struct {
    pub fn emit(b: *source.Builder, query: hyper.Query) !source.Id {
        return reciprocalStep(b, query, true, 13, false);
    }
};
pub fn reciprocal(b: *source.Builder) !source.Module {
    Producer.suspended = false;
    return reciprocalImpl(b);
}
pub fn reciprocalSuspended(b: *source.Builder) !source.Module {
    Producer.suspended = true;
    return reciprocalImpl(b);
}
fn reciprocalImpl(b: *source.Builder) !source.Module {
    const integer = try b.scalar(u64);
    const boolean = try b.scalar(bool);
    const types = try hyper.pairWith(b, integer, integer, &.{boolean});
    const producer = try hyper.ana(b, types, boolean, Producer);
    const consumer = try hyper.ana(b, hyper.swap(types), boolean, Consumer);
    const main = try b.declare(&.{}, integer, &.{}, &.{});
    const left = try b.variable(types.forward);
    const right = try b.variable(types.backward);
    const answer = try b.variable(types.answer_backward);
    const peer = try b.declare(&.{}, types.forward, &.{}, &.{});
    try b.define(peer, try b.pure(try b.reference(left)));
    const invoked = try hyper.invoke(b, try b.reference(right), try b.lambda(peer, types.peer_forward));
    const finish = try b.bind(answer, invoked, try wrapper(b, types.answer_backward, try b.reference(answer)));
    try b.define(main, try b.bind(left, try hyper.start(b, producer, try b.constant(bool, false)), try b.bind(right, try hyper.start(b, consumer, try b.constant(bool, false)), finish)));
    return b.module(main, try b.scalar(void));
}
fn execute(program: data.activation.Program, input: []const u8, expected: []const u8, expected_yields: usize) !usize {
    const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
    defer a.free(bytes);
    _ = try data.program_image.encode(a, program, bytes);
    var result = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .initial_args = input }, .quantum = 1 });
    defer result.deinit();
    var steps: usize = 1;
    var yields: usize = 0;
    while (result.record == .progressed or result.record == .yielded) {
        try std.testing.expect(steps < 512);
        const yielded = result.record == .yielded;
        yields += @intFromBool(yielded);
        const state = if (yielded) result.record.yielded.? else result.record.progressed.?;
        const next = try world.invocation.invoke(a, .{ .image = bytes, .instance = .{ .state = state }, .control = if (yielded) .resume_yield else .none, .quantum = 1 });
        result.deinit();
        result = next;
        steps += 1;
    }
    try std.testing.expectEqual(expected_yields, yields);
    try std.testing.expect(result.record == .completed);
    try std.testing.expectEqualSlices(u8, expected, result.record.completed);
    return steps;
}
test "generated identity and reciprocal hyper helpers retain non-strict demand through source-free linking" {
    inline for (.{ identityProject, ignoredPeer, ignoredFault, reciprocal, reciprocalSuspended, configured }, 0..) |build, index| {
        var b = source.Builder.init(a);
        defer b.deinit();
        var original = try boundary.program.compile(a, try build(&b));
        defer original.deinit();
        var stats: data.thunk_forwarding.Statistics = .{};
        var checked = try data.thunk_forwarding.run(a, original.program, &stats, .{});
        defer checked.deinit();
        std.debug.print("hyper construction case={d} stats={any}\n", .{ index, stats });
        try std.testing.expect(stats.wrappers_removed > 0);
        var compiled = try data.closed_compilation.run(a, original.program, .{ .contract = .semantic });
        defer compiled.deinit();
        var contracts = std.heap.ArenaAllocator.init(a);
        defer contracts.deinit();
        const borrows = try borrowContracts(contracts.allocator(), original.program);
        const object: data.component.Object = .{ .program = original.program, .exports = &.{.{ .name = "main", .reference = .{ .kind = .function, .id = original.program.roots.entry } }}, .borrows = borrows };
        const bmo = try a.alloc(u8, try data.component.encodedLength(object));
        defer a.free(bmo);
        _ = try data.component.encode(a, object, bmo);
        var linked = try data.linker.linkWithCompilation(a, &.{.{ .key = "hyper", .object = bmo }}, &.{}, .{ .instance = "hyper", .symbol = "main" }, .{ .contract = .semantic });
        defer linked.deinit();
        @memset(bmo, 0xff);
        for (0..if (index == 3 or index == 4 or index == 6) @as(usize, 1) else 2) |value| {
            const bit = [_]u8{@intCast(value)};
            const input: []const u8 = if (index == 3 or index == 4 or index == 6) &.{} else &bit;
            const pair = [_]u8{ @intCast(value), @intCast(1 - value) };
            const expected: []const u8 = if (index == 6) &.{ 145, 0, 0, 0, 0, 0, 0, 0 } else if (index == 3 or index == 4) &.{ 42, 0, 0, 0, 0, 0, 0, 0 } else if (index == 5) &pair else &bit;
            var counts: [4]usize = undefined;
            for ([_]data.activation.Program{ original.program, checked.program, compiled.program, linked.program }, &counts) |program, *count| count.* = try execute(program, input, expected, @intFromBool(index == 4 or index == 6));
            try std.testing.expect(counts[1] < counts[0]);
            std.debug.print("hyper case={d} value={d} removed={d} steps={any}\n", .{ index, value, stats.wrappers_removed, counts });
        }
    }
}

const ConfiguredStep = struct {
    var invert = false;
    var emissions: usize = 0;
    pub fn emit(b: *source.Builder, query: hyper.Query) !source.Id {
        emissions += 1;
        const value = if (invert) try b.primitive(try b.scalar(bool), .boolean_not, &.{query.state}, 0) else query.state;
        return b.pure(try hyper.deferValue(b, query.types.answer_forward, value));
    }
};
fn observeConfigured(b: *source.Builder, types: hyper.Pair, definition: hyper.Ana, value: source.Id) !source.Id {
    const participant = try b.variable(types.forward);
    const answer = try b.variable(types.answer_forward);
    const ignored = try hyper.deferValue(b, types.answer_backward, try b.constant(bool, false));
    return b.bind(participant, try hyper.start(b, definition, value), try b.bind(answer, try hyper.project(b, types, try b.reference(participant), ignored), try wrapper(b, types.answer_forward, try b.reference(answer))));
}
pub fn configured(b: *source.Builder) !source.Module {
    const boolean = try b.scalar(bool);
    const types = try hyper.pairWith(b, boolean, boolean, &.{boolean});
    ConfiguredStep.emissions = 0;
    ConfiguredStep.invert = false;
    const first = try hyper.ana(b, types, boolean, ConfiguredStep);
    ConfiguredStep.invert = true;
    const second = try hyper.ana(b, types, boolean, ConfiguredStep);
    if (ConfiguredStep.emissions != 2 or first.function == second.function) return error.SkippedConfiguredEmission;
    const pair = try b.schema(.{ .product = &.{ boolean, boolean } });
    const main = try b.declare(&.{boolean}, pair, &.{}, &.{});
    const left = try b.variable(boolean);
    const right = try b.variable(boolean);
    const input = try b.reference(b.parameter(main, 0));
    const result = try b.pure(try b.primitive(pair, .product, &.{ try b.reference(left), try b.reference(right) }, 0));
    try b.define(main, try b.bind(left, try observeConfigured(b, types, first, input), try b.bind(right, try observeConfigured(b, types, second, input), result)));
    return b.module(main, try b.scalar(void));
}

pub fn reentrant(b: *source.Builder) !source.Module {
    const integer = try b.scalar(u64);
    const types = try hyper.pair(b, integer, integer);
    const compute = try b.declare(&.{}, integer, &.{}, &.{});
    const participant = try b.variable(types.forward);
    const answer = try b.variable(types.answer_forward);
    const projected = try hyper.project(b, types, try b.reference(participant), try hyper.deferValue(b, types.answer_backward, try b.constant(u64, 42)));
    try b.define(compute, try b.bind(participant, try hyper.identity(b, types), try b.bind(answer, projected, try hyper.force(b, try b.reference(answer)))));
    return source.examples.reentrantWithResult(b, compute, true);
}

test "reentrant multi-shot force retains its yielded control and result" {
    var b = source.Builder.init(a);
    defer b.deinit();
    var original = try boundary.program.compile(a, try reentrant(&b));
    defer original.deinit();
    // Original component publication cannot describe this fresh-region write.
    // Keep that boundary explicit; do not optimize first to evade its rejection.
    var contracts = std.heap.ArenaAllocator.init(a);
    defer contracts.deinit();
    try std.testing.expectError(error.InvalidOwnership, borrowContracts(contracts.allocator(), original.program));
    var stats: data.thunk_forwarding.Statistics = .{};
    var checked = try data.thunk_forwarding.run(a, original.program, &stats, .{});
    defer checked.deinit();
    try std.testing.expect(stats.wrappers_removed > 0);
    var compiled = try data.closed_compilation.run(a, original.program, .{ .contract = .semantic });
    defer compiled.deinit();
    var counts: [3]usize = undefined;
    for ([_]data.activation.Program{ original.program, checked.program, compiled.program }, &counts) |program, *count| count.* = try execute(program, &.{}, &.{ 145, 0, 0, 0, 0, 0, 0, 0 }, 1);
    try std.testing.expect(counts[1] < counts[0]);
}
