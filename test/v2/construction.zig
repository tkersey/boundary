// Copyright (c) 2026 Boundary contributors. MIT license.
const std = @import("std");
const boundary = @import("boundary");
const data = @import("boundary_data");
const world = @import("world");
const source = boundary.source;
const author = boundary.authoring;
const p = data.program;
const a = std.testing.allocator;
pub const Trace = struct {
    calls: usize = 0,
    digest: u64 = 14695981039346656037,
    fn observe(self: *@This(), ordinal: usize, flag: bool) void {
        self.calls += 1;
        self.digest = (self.digest ^ @as(u64, @intCast(ordinal))) *% 1099511628211;
        self.digest = (self.digest ^ @intFromBool(flag)) *% 1099511628211;
    }
};
/// The same native emitter type reads each instance's configuration. Sharing
/// code/type identity cannot authorize omitting an invocation or its trace.
pub const Configured = struct {
    ordinal: usize,
    flag: bool,
    fn raw(self: @This(), b: *source.Builder, previous: p.Id, boolean: p.Id, effects: [2]p.Id, trace: *Trace) !struct { request: p.Id, value: p.Id } {
        trace.observe(self.ordinal, self.flag);
        const literal = try b.constant(bool, self.flag);
        return .{
            .request = try b.term(.{ .perform = .{ .effect = effects[self.ordinal % 2], .payload = literal } }),
            .value = try b.primitive(boolean, .equal, &.{ previous, literal }, 0),
        };
    }
    fn typed(self: @This(), body: *author.Body, previous: *const author.Value, effects: [2]*const author.Operation, trace: *Trace) !*const author.Value {
        trace.observe(self.ordinal, self.flag);
        const literal = try body.constant(bool, self.flag);
        _ = try body.perform(effects[self.ordinal % 2], literal);
        return body.equal(previous, literal);
    }
};
pub fn rawChain(b: *source.Builder, flags: []const bool, trace: *Trace) !source.Module {
    const boolean = try b.scalar(bool);
    const unit = try b.scalar(void);
    const effects = [2]p.Id{
        try b.effect(.{ .identity = "construction/even", .payload = boolean, .result = unit, .external = true }),
        try b.effect(.{ .identity = "construction/odd", .payload = boolean, .result = unit, .external = true }),
    };
    const row = try (source.Row{ .effects = &.{effects[1]} }).unionWith(b.allocator(), .{ .effects = &.{ effects[0], effects[1] } });
    const entry = try b.declare(&.{boolean}, boolean, row.effects, &.{});
    const Recipe = struct { request: p.Id, unit_variable: p.Id, value: p.Id, variable: p.Id };
    const recipes = try b.allocator().alloc(Recipe, flags.len);
    var previous = try b.reference(b.parameter(entry, 0));
    for (flags, recipes, 0..) |flag, *recipe, i| {
        const emitted = try (Configured{ .ordinal = i, .flag = flag }).raw(b, previous, boolean, effects, trace);
        recipe.* = .{ .request = emitted.request, .unit_variable = try b.variable(unit), .value = try b.pure(emitted.value), .variable = try b.variable(boolean) };
        previous = try b.reference(recipe.variable);
    }
    var body = try b.pure(previous);
    var i = recipes.len;
    while (i != 0) {
        i -= 1;
        const recipe = recipes[i];
        body = try b.bind(recipe.unit_variable, recipe.request, try b.bind(recipe.variable, recipe.value, body));
    }
    try b.define(entry, body);
    return b.module(entry, unit);
}
pub fn typedChain(b: *source.Builder, flags: []const bool, trace: *Trace) !source.Module {
    const c = try author.Context.init(b);
    const boolean = try c.scalar(bool);
    const unit = try c.scalar(void);
    const effects = [2]*const author.Operation{ try c.external("construction/even", boolean, unit), try c.external("construction/odd", boolean, unit) };
    const entry = try c.function("chain", &.{.{ .name = "seed", .schema = boolean }}, boolean, &effects);
    const body = try c.body(entry);
    var previous = try body.parameter("seed");
    for (flags, 0..) |flag, i| previous = try (Configured{ .ordinal = i, .flag = flag }).typed(body, previous, effects, trace);
    try c.define(entry, try body.ret(previous));
    return c.module(entry, unit);
}
fn execute(program: data.activation.Program, flags: []const bool, seed: bool) !void {
    const bytes = try a.alloc(u8, try data.program_image.encodedLength(program));
    defer a.free(bytes);
    _ = try data.program_image.encode(a, program, bytes);
    var session = try world.Session.initImage(a, bytes, &.{@intFromBool(seed)});
    defer session.deinit();
    var expected = seed;
    var requests: usize = 0;
    while (true) switch (try session.run(null)) {
        .requested => {
            try std.testing.expect(requests < flags.len);
            var pending = try session.pendingRequest(a);
            defer pending.deinit();
            try std.testing.expectEqualStrings(if (requests % 2 == 0) "construction/even" else "construction/odd", pending.request.binding.semantic_identity);
            try std.testing.expectEqualSlices(u8, &.{@intFromBool(flags[requests])}, pending.request.binding.payload);
            const reply = try data.invocation.encodeOwned(data.invocation.Result, a, .{ .request_identity = pending.request.request_identity, .value = &.{} });
            defer a.free(reply);
            try session.answer(reply);
            expected = expected == flags[requests];
            requests += 1;
        },
        .completed => |value| {
            try std.testing.expectEqual(flags.len, requests);
            try std.testing.expectEqualSlices(u8, &.{@intFromBool(expected)}, try session.bytes(&value));
            return;
        },
        else => return error.UnexpectedOutcome,
    };
}
test "forward construction and explicit binding spine preserve emitted occurrences and runtime trace" {
    const flags = [_]bool{ true, false, true, true, false, false, true };
    var raw = source.Builder.init(a);
    defer raw.deinit();
    var typed = source.Builder.init(a);
    defer typed.deinit();
    var raw_trace: Trace = .{};
    var typed_trace: Trace = .{};
    const rm = try rawChain(&raw, &flags, &raw_trace);
    const tm = try typedChain(&typed, &flags, &typed_trace);
    try std.testing.expectEqual(flags.len, raw_trace.calls);
    try std.testing.expectEqualDeep(raw_trace, typed_trace);
    var rc = try boundary.program.compile(a, rm);
    defer rc.deinit();
    var tc = try boundary.program.compile(a, tm);
    defer tc.deinit();
    for ([_]bool{ false, true }) |seed| {
        try execute(rc.program, &flags, seed);
        try execute(tc.program, &flags, seed);
    }
}
test "configuration-sensitive native emitters retain order count and distinct emitted behavior" {
    const cases = [_][3]bool{ .{ true, false, true }, .{ false, true, false } };
    var identities: [2][32]u8 = undefined;
    var traces: [2]Trace = @splat(.{});
    for (cases, 0..) |flags, i| {
        var builder = source.Builder.init(a);
        defer builder.deinit();
        var compiled = try boundary.program.compile(a, try typedChain(&builder, &flags, &traces[i]));
        defer compiled.deinit();
        try std.testing.expectEqual(flags.len, traces[i].calls);
        identities[i] = try data.program_image.identity(a, compiled.program);
        try execute(compiled.program, &flags, false);
    }
    try std.testing.expect(!std.mem.eql(u8, &identities[0], &identities[1]));
    try std.testing.expect(traces[0].digest != traces[1].digest);
}

test "indexed named arguments materialize in declaration order" {
    var b = source.Builder.init(a);
    defer b.deinit();
    const c = try author.Context.init(&b);
    const integer = try c.scalar(u64);
    const unit = try c.scalar(void);
    const fields = try b.allocator().alloc(author.Field, 17);
    for (fields, 0..) |*field, i| field.* = .{ .name = try std.fmt.allocPrint(b.allocator(), "field_{d}", .{i}), .schema = integer };
    const record = try c.record(fields);
    const entry = try c.function("ordered", &.{}, record, &.{});
    const body = try c.body(entry);
    var arguments: [17]author.Argument = undefined;
    var expected: [17 * 8]u8 = undefined;
    for (&arguments, 0..) |*arg, i| {
        const index = arguments.len - 1 - i;
        arg.* = .{ .name = fields[index].name, .value = try body.constant(u64, @intCast(index + 1)) };
        std.mem.writeInt(u64, expected[index * 8 ..][0..8], @intCast(index + 1), .little);
    }
    try c.define(entry, try body.ret(try body.product(record, &arguments)));
    var compiled = try c.compile(a, entry, unit);
    defer compiled.deinit();
    const bytes = try a.alloc(u8, try data.program_image.encodedLength(compiled.program));
    defer a.free(bytes);
    _ = try data.program_image.encode(a, compiled.program, bytes);
    var session = try world.Session.initImage(a, bytes, &.{});
    defer session.deinit();
    const result = try session.run(null);
    try std.testing.expect(result == .completed);
    try std.testing.expectEqualSlices(u8, &expected, try session.bytes(&result.completed));
}
