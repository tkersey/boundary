// Copyright (c) 2026 Boundary contributors. MIT license.
//! Explicit pure call-by-name computations. Runtime closures use normal lowering.
const source = @import("../source.zig");
const Id = source.Id;

/// A zero-argument pure computation. Captures are checked by normal admission.
pub fn delayed(b: *source.Builder, result: Id, captures: []const Id) source.Error!Id {
    return b.schema(.{ .internal = .{ .computation = .{
        .parameters = &.{},
        .result = result,
        .capture_bound = captures,
    } } });
}

/// Demand a delayed value, producing a source term rather than a host result.
pub fn force(b: *source.Builder, value: Id) source.Error!Id {
    return b.term(.{ .apply = .{ .computation = value, .arguments = &.{} } });
}

pub const Pair = struct {
    forward: Id,
    backward: Id,
    peer_forward: Id,
    peer_backward: Id,
    answer_forward: Id,
    answer_backward: Id,
};

pub fn pair(b: *source.Builder, a: Id, z: Id) source.Error!Pair {
    return pairWith(b, a, z, &.{});
}

/// A finite recursive interface group, not an unfolding of its endpoint types.
/// The bound permits captures; lowering retains only the actually captured values.
/// Reusable pure values cannot hide linear captures: ordinary fixed-point use
/// analysis checks these schemas and the actual generated environments.
pub fn pairWith(b: *source.Builder, a: Id, z: Id, captures: []const Id) source.Error!Pair {
    const cached = try b.specialization(Pair, "boundary.hyper.pair/v1", .{ a, z, captures });
    if (cached.cached) |value| return value;
    const forward = try b.reserveSchema();
    const backward = try b.reserveSchema();
    const peer_forward = try b.reserveSchema();
    const peer_backward = try b.reserveSchema();
    const answer_forward = try b.reserveSchema();
    const answer_backward = try b.reserveSchema();
    const ids = [_]Id{ forward, backward, peer_forward, peer_backward, answer_forward, answer_backward };
    const bound = try b.allocator().alloc(Id, captures.len + ids.len + 2);
    @memcpy(bound[0..captures.len], captures);
    @memcpy(bound[captures.len..][0..ids.len], &ids);
    bound[bound.len - 2] = a;
    bound[bound.len - 1] = z;
    const results = [_]Id{ answer_forward, answer_backward, forward, backward, z, a };
    for (ids, results, 0..) |id, result, index| {
        const parameters: []const Id = switch (index) {
            0 => &.{peer_backward},
            1 => &.{peer_forward},
            else => &.{},
        };
        try b.defineSchema(id, .{ .internal = .{ .computation = .{
            .parameters = parameters,
            .result = result,
            .capture_bound = bound,
        } } });
    }
    return cached.finish(b, .{
        .forward = forward,
        .backward = backward,
        .peer_forward = peer_forward,
        .peer_backward = peer_backward,
        .answer_forward = answer_forward,
        .answer_backward = answer_backward,
    });
}

/// A staged body takes the complementary delayed participant and returns a
/// delayed answer. Boundary checks the actual body against this callable schema.
pub fn make(b: *source.Builder, body: Id, interface: Id) source.Error!Id {
    return b.lambda(body, interface);
}

/// Construct a delayed invocation. Neither body nor peer is entered until force.
/// The result is a source term yielding Delayed<B>, preserving the normal staged
/// distinction between source terms and source values.
pub fn invoke(b: *source.Builder, participant: Id, peer: Id) source.Error!Id {
    if (participant >= b.values.items.len) return error.InvalidReference;
    const interface = b.values.items[@intCast(participant)].schema;
    if (interface >= b.schemas.items.len) return error.InvalidReference;
    const shape = b.schemas.items[@intCast(interface)];
    if (shape != .internal or shape.internal != .computation) return error.TypeMismatch;
    const answer = shape.internal.computation.result;
    if (answer >= b.schemas.items.len) return error.InvalidReference;
    const answer_shape = b.schemas.items[@intCast(answer)];
    if (answer_shape != .internal or answer_shape.internal != .computation or
        answer_shape.internal.computation.parameters.len != 0) return error.TypeMismatch;
    const thunk = try b.declare(&.{}, answer_shape.internal.computation.result, &.{}, &.{});
    const result = try b.variable(answer);
    const applied = try b.term(.{ .apply = .{
        .computation = participant,
        .arguments = &.{peer},
    } });
    try b.define(thunk, try b.bind(result, applied, try force(b, try b.reference(result))));
    return b.pure(try b.lambda(thunk, answer));
}

test "hyper recursive interfaces share finite schema declarations" {
    const std = @import("std");
    var b = source.Builder.init(std.testing.allocator);
    defer b.deinit();
    const integer = try b.scalar(u64);
    const boolean = try b.scalar(bool);
    const first = try pair(&b, integer, boolean);
    const count = b.schemas.items.len;
    for (0..100) |_| {
        const again = try pair(&b, integer, boolean);
        try std.testing.expectEqual(first, again);
        try std.testing.expectEqual(count, b.schemas.items.len);
    }
    const entry = try b.declare(&.{}, integer, &.{}, &.{});
    try b.define(entry, try b.pure(try b.constant(u64, 42)));
    var compiled = try source.lower(std.testing.allocator, b.module(entry, try b.scalar(void)));
    defer compiled.deinit();
}

test "hyper recursive wrapping cannot declare an exclusive capture reusable" {
    const std = @import("std");
    var b = source.Builder.init(std.testing.allocator);
    defer b.deinit();
    const integer = try b.scalar(u64);
    const owned = try b.resource(integer);
    _ = try pairWith(&b, integer, integer, &.{owned});
    const entry = try b.declare(&.{}, integer, &.{}, &.{});
    try b.define(entry, try b.pure(try b.constant(u64, 42)));
    try std.testing.expectError(error.InvalidOwnership, source.lower(std.testing.allocator, b.module(entry, try b.scalar(void))));
}

pub const Ana = struct { function: Id, interface: Id };

/// Step.emit receives source values and a staged query builder. It may emit zero,
/// one, or arbitrarily many runtime queries; no host function enters the image.
/// State must be admitted by the interface's capture bound.
pub fn ana(b: *source.Builder, types: Pair, state: Id, comptime Step: type) source.Error!Ana {
    const cache = try b.specialization(Ana, "boundary.hyper.ana/v1", .{
        types, state, @typeName(Step),
    });
    if (cache.cached) |value| return value;
    const maker = try b.declare(&.{state}, types.forward, &.{}, &.{});
    const body = try b.declare(&.{types.peer_backward}, types.answer_forward, &.{}, &.{});
    try b.define(body, try Step.emit(b, Query{
        .types = types,
        .maker = maker,
        .state = try b.reference(b.parameter(maker, 0)),
        .peer = try b.reference(b.parameter(body, 0)),
    }));
    try b.define(maker, try b.pure(try make(b, body, types.forward)));
    return cache.finish(b, .{ .function = maker, .interface = types.forward });
}

pub fn start(b: *source.Builder, definition: Ana, state: Id) source.Error!Id {
    return b.term(.{ .call = .{ .function = definition.function, .arguments = &.{state} } });
}

pub fn swap(types: Pair) Pair {
    return .{
        .forward = types.backward,
        .backward = types.forward,
        .peer_forward = types.peer_backward,
        .peer_backward = types.peer_forward,
        .answer_forward = types.answer_backward,
        .answer_backward = types.answer_forward,
    };
}

pub const Query = struct {
    types: Pair,
    maker: Id,
    state: Id,
    peer: Id,

    /// Return a delayed counterpart answer. Even looking up the counterpart is
    /// deferred, so an unused query cannot evaluate its peer or successor state.
    pub fn ask(self: Query, b: *source.Builder, next_state: Id) source.Error!Id {
        const answer_shape = b.schemas.items[@intCast(self.types.answer_backward)];
        const answer = answer_shape.internal.computation.result;
        const tail = try b.declare(&.{}, self.types.forward, &.{}, &.{});
        try b.define(tail, try b.term(.{ .call = .{
            .function = self.maker,
            .arguments = &.{next_state},
        } }));
        const thunk = try b.declare(&.{}, answer, &.{}, &.{});
        const peer = try b.variable(self.types.backward);
        const result = try b.variable(self.types.answer_backward);
        const invoked = try invoke(b, try b.reference(peer), try b.lambda(tail, self.types.peer_forward));
        try b.define(thunk, try b.bind(peer, try force(b, self.peer), try b.bind(result, invoked, try force(b, try b.reference(result)))));
        return b.pure(try b.lambda(thunk, self.types.answer_backward));
    }
};
