// Copyright (c) 2026 Boundary contributors. MIT license.
//! Authored Boolean choice interpretations. The runtime has no choice operation.
const source = @import("../source.zig");
const p = @import("boundary_data_v2").program;
const Error = source.Error;
pub const Family = struct { effect: p.Id, capability: p.Id };
pub const Interpretation = struct { handler: p.Id, answer: p.Id, resumption: p.Id };

pub fn family(builder: *source.Builder, identity: []const u8) Error!Family {
    const effect = try builder.effect(.{ .identity = identity, .payload = try builder.scalar(void), .result = try builder.scalar(bool), .control_use = .multi, .external = false });
    return .{ .effect = effect, .capability = try builder.schema(.{ .internal = .{ .capability = effect } }) };
}

pub fn all(builder: *source.Builder, choice: Family, element: p.Id, captures: []const p.Id, residual: source.Row) Error!Interpretation {
    return interpret(builder, choice, element, captures, residual, &.{}, &.{}, true);
}
pub fn first(builder: *source.Builder, choice: Family, element: p.Id, captures: []const p.Id, residual: source.Row) Error!Interpretation {
    return interpret(builder, choice, element, captures, residual, &.{}, &.{}, false);
}
pub fn allScoped(builder: *source.Builder, choice: Family, element: p.Id, captures: []const p.Id, residual: source.Row, owned_regions: []const p.Id, borrowed_regions: []const p.Id) Error!Interpretation {
    return interpret(builder, choice, element, captures, residual, owned_regions, borrowed_regions, true);
}

fn interpret(builder: *source.Builder, choice: Family, element: p.Id, captures: []const p.Id, residual: source.Row, owned_regions: []const p.Id, borrowed_regions: []const p.Id, comptime every: bool) Error!Interpretation {
    const instance = try builder.specialization(Interpretation, "boundary.library.choice/v2", .{ choice, element, captures, residual, owned_regions, borrowed_regions, every });
    if (instance.cached) |value| return value;
    const unit = try builder.scalar(void);
    const boolean = try builder.scalar(bool);
    const answer = try builder.schema(.{ .seq = element });
    const resumption = try builder.schema(.{ .internal = .{ .resumption = .{ .effect = choice.effect, .input = boolean, .answer = answer, .effects = residual.effects, .capture_bound = captures, .handled = &.{choice.effect}, .mode = .deep, .use = .multi, .owned_regions = owned_regions } } });
    const returns = try builder.declare(&.{element}, answer, &.{}, borrowed_regions);
    const clause = try builder.declare(&.{ unit, resumption }, answer, residual.effects, borrowed_regions);
    const item = try builder.reference(builder.parameter(returns, 0));
    try builder.define(returns, try builder.pure(try builder.value(.{ .schema = answer, .expression = .{ .primitive = .{ .opcode = .sequence, .operands = &.{item} } } })));
    const token = try builder.reference(builder.parameter(clause, 1));
    const left = try builder.term(.{ .resume_value = .{ .resumption = token, .argument = try builder.constant(bool, false) } });
    const body = if (every) blk: {
        const left_result = try builder.variable(answer);
        const right_result = try builder.variable(answer);
        const right = try builder.term(.{ .resume_value = .{ .resumption = token, .argument = try builder.constant(bool, true) } });
        const results = try builder.pure(try builder.value(.{ .schema = answer, .expression = .{ .primitive = .{ .opcode = .sequence_concat, .operands = &.{ try builder.reference(left_result), try builder.reference(right_result) } } } }));
        break :blk try builder.bind(left_result, left, try builder.bind(right_result, right, results));
    } else left;
    try builder.define(clause, body);
    return instance.finish(builder, .{ .handler = try builder.handler(.{ .mode = .deep, .input = element, .answer = answer, .return_function = returns, .clauses = &.{.{ .effect = choice.effect, .function = clause, .resumption = resumption }}, .effects = residual.effects }), .answer = answer, .resumption = resumption });
}
