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

/// Minimal reciprocal interface group. Bodies return delayed endpoint values.
/// This initial group admits capture-free participants; general capture bounds
/// and the full public combinators remain subsequent implementation work.
pub const Pair = struct { forward: Id, backward: Id, peer_forward: Id, peer_backward: Id };

pub fn pair(b: *source.Builder, a: Id, z: Id) source.Error!Pair {
    const forward = try b.reserveSchema();
    const backward = try b.reserveSchema();
    const peer_forward = try delayed(b, forward, &.{});
    const peer_backward = try delayed(b, backward, &.{});
    const answer_a = try delayed(b, a, &.{});
    const answer_z = try delayed(b, z, &.{});
    try b.defineSchema(forward, .{ .internal = .{ .computation = .{
        .parameters = &.{peer_backward},
        .result = answer_z,
    } } });
    try b.defineSchema(backward, .{ .internal = .{ .computation = .{
        .parameters = &.{peer_forward},
        .result = answer_a,
    } } });
    return .{ .forward = forward, .backward = backward, .peer_forward = peer_forward, .peer_backward = peer_backward };
}

pub fn invoke(b: *source.Builder, participant: Id, peer: Id) source.Error!Id {
    return b.term(.{ .apply = .{ .computation = participant, .arguments = &.{peer} } });
}
