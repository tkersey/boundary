// Copyright (c) 2026 Boundary contributors. MIT license.
//! Two private representations satisfy one unchanged resource client.
const source = @import("../source.zig");
const cleanup = @import("../library/cleanup.zig");
const p = @import("boundary_data_v2").program;
const Error = source.Error;
pub fn scalar(b: *source.Builder) Error!source.ast.Module {
    return build(b, false);
}
pub fn pair(b: *source.Builder) Error!source.ast.Module {
    return build(b, true);
}
pub const Interface = struct { owned: p.Id, borrowed: p.Id, acquire: p.Id, read: p.Id, release: p.Id, acquire_effect: p.Id, release_effect: p.Id, loan: p.Id };

fn implementation(b: *source.Builder, comptime structured: bool) Error!Interface {
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const representation = if (structured) try b.schema(.{ .product = &.{ integer, try b.scalar(bool) } }) else integer;
    const owned = try b.resource(representation);
    const loan = b.region();
    const borrowed = try b.schema(.{ .internal = .{ .borrowed = .{ .value = owned, .region = loan } } });
    const acquiring = try b.effect(.{ .identity = "example/resource-acquire", .payload = unit, .result = integer });
    const releasing = try b.effect(.{ .identity = "example/resource-release", .payload = integer, .result = unit });
    const acquire = try b.declare(&.{}, owned, &.{acquiring}, &.{});
    const read = try b.declare(&.{borrowed}, integer, &.{}, &.{loan});
    const release = try b.declare(&.{owned}, unit, &.{releasing}, &.{});
    try b.resourceAuthority(owned, &.{acquire}, &.{ read, release });
    const raw = try b.variable(integer);
    const contents = if (structured) try b.primitive(representation, .product, &.{ try b.reference(raw), try b.constant(bool, true) }, 0) else try b.reference(raw);
    const introduced = try b.primitive(owned, .resource_pack, &.{contents}, 0);
    try b.define(acquire, try b.bind(raw, try b.term(.{ .perform = .{ .effect = acquiring, .payload = try b.constant(void, {}) } }), try b.pure(introduced)));
    for ([_]p.Id{ read, release }, 0..) |function, index| {
        const internal = try b.primitive(representation, .resource_unpack, &.{try b.reference(b.parameter(function, 0))}, 0);
        const extracted = if (structured) try b.primitive(integer, .field, &.{internal}, 0) else internal;
        try b.define(function, if (index == 0) try b.pure(extracted) else try b.term(.{ .perform = .{ .effect = releasing, .payload = extracted } }));
    }
    return .{ .owned = owned, .borrowed = borrowed, .acquire = acquire, .read = read, .release = release, .acquire_effect = acquiring, .release_effect = releasing, .loan = loan };
}

fn client(b: *source.Builder, interface: Interface) Error!source.ast.Module {
    const unit = try b.scalar(void);
    const integer = try b.scalar(u64);
    const inspecting = try b.effect(.{ .identity = "example/resource-use", .payload = integer, .result = unit });
    const main = try b.declare(&.{}, integer, &.{ interface.acquire_effect, interface.release_effect, inspecting }, &.{});
    const body = try b.declare(&.{interface.borrowed}, integer, &.{inspecting}, &.{interface.loan});
    const info = try cleanup.exitInfo(b, unit);
    const finalizer = try b.declare(&.{ info, interface.owned }, unit, &.{interface.release_effect}, &.{});
    const result = try b.variable(integer);
    const reread = try b.variable(integer);
    const inspected = try b.variable(unit);
    const read = try b.term(.{ .call = .{ .function = interface.read, .arguments = &.{try b.reference(b.parameter(body, 0))} } });
    const use = try b.term(.{ .perform = .{ .effect = inspecting, .payload = try b.reference(result) } });
    const increment = try b.value(.{ .schema = integer, .expression = .{ .primitive = .{ .opcode = .integer_add, .operands = &.{ try b.reference(reread), try b.constant(u64, 1) }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = try b.failureLiteral(try b.constant(void, {})) }} } } });
    try b.define(body, try b.bind(result, read, try b.bind(inspected, use, try b.bind(reread, read, try b.pure(increment)))));
    try b.define(finalizer, try b.term(.{ .call = .{ .function = interface.release, .arguments = &.{try b.reference(b.parameter(finalizer, 1))} } }));
    const resource = try b.variable(interface.owned);
    const body_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{interface.borrowed}, .result = integer, .effects = &.{inspecting}, .regions = &.{interface.loan} } } });
    const cleanup_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{ info, interface.owned }, .result = unit, .effects = &.{interface.release_effect} } } });
    const protected = try cleanup.bracket(b, try b.reference(resource), interface.loan, try b.lambda(body, body_type), try b.lambda(finalizer, cleanup_type));
    try b.define(main, try b.bind(resource, try b.term(.{ .call = .{ .function = interface.acquire, .arguments = &.{} } }), protected));
    return b.module(main, unit);
}
fn build(b: *source.Builder, comptime structured: bool) Error!source.ast.Module {
    return client(b, try implementation(b, structured));
}
