// Copyright (c) 2026 Boundary contributors. MIT license.
//! Four queens uses public source construction and ordinary library handlers.
const source = @import("../source.zig");
const search = @import("../library/search.zig");
const cleanup = @import("../library/cleanup.zig");
const p = @import("boundary_data_v2").program;
const Error = source.Error;
pub fn dfs(b: *source.Builder) Error!source.ast.Module {
    return build(b, .depth_first);
}
pub fn bfs(b: *source.Builder) Error!source.ast.Module {
    return build(b, .breadth_first);
}

fn arithmetic(b: *source.Builder, op: p.Opcode, left: p.Id, right: p.Id) Error!p.Id {
    return b.value(.{ .schema = try b.scalar(u64), .expression = .{ .primitive = .{ .opcode = op, .operands = &.{ left, right }, .failures = &.{.{ .kind = .arithmetic_overflow, .value = try b.failureLiteral(try b.constant(void, {})) }} } } });
}

fn build(b: *source.Builder, comptime order: search.Order) Error!source.ast.Module {
    const unit = try b.scalar(void);
    const boolean = try b.scalar(bool);
    const integer = try b.scalar(u64);
    const board = try b.schema(.{ .seq = integer });
    const shared = b.region();
    const local = b.region();
    const loan = b.region();
    const shared_region = try b.schema(.{ .internal = .{ .region = shared } });
    const local_region = try b.schema(.{ .internal = .{ .region = local } });
    const metrics_cell = try b.schema(.{ .internal = .{ .cell = .{ .element = integer, .region = shared } } });
    const board_cell = try b.schema(.{ .internal = .{ .cell = .{ .element = board, .region = local } } });
    const owned = try b.resource(integer);
    const borrowed = try b.schema(.{ .internal = .{ .borrowed = .{ .value = owned, .region = loan } } });
    const acquiring = try b.effect(.{ .identity = "example/queens-acquire", .payload = board, .result = integer });
    const use_payload = try b.schema(.{ .product = &.{ integer, board, integer } });
    const using = try b.effect(.{ .identity = "example/queens-use", .payload = use_payload, .result = unit });
    const releasing = try b.effect(.{ .identity = "example/queens-release", .payload = integer, .result = unit });
    const residual: source.Row = .{ .effects = &.{ acquiring, using, releasing } };
    const interpretation = try search.define(b, "example/queens", board, &.{ unit, boolean, integer, board, shared_region, local_region, metrics_cell, board_cell }, residual, &.{local}, &.{shared}, order);
    const operations = try residual.unionWith(b.allocator(), .{ .effects = &.{ interpretation.pick, interpretation.reject } });
    const answer = try b.schema(.{ .product = &.{ interpretation.solutions, integer } });
    const main = try b.declare(&.{}, answer, residual.effects, &.{});
    const outer = try b.declare(&.{shared_region}, answer, residual.effects, &.{shared});
    const handled_body = try b.declare(&.{ interpretation.pick_capability, interpretation.reject_capability }, board, operations.effects, &.{shared});
    const inside = try b.declare(&.{local_region}, board, operations.effects, &.{ shared, local });
    const solve = try b.declare(&.{ board_cell, metrics_cell, interpretation.pick_capability, interpretation.reject_capability }, board, operations.effects, &.{ shared, local });

    // The verifier walks prior rows. Sequence lookup is total and the impossible
    // miss has an authored failure, independent of any host-side constraint code.
    const safe = try b.declare(&.{ board, integer, integer }, boolean, &.{}, &.{});
    const old_board = try b.reference(b.parameter(safe, 0));
    const col = try b.reference(b.parameter(safe, 1));
    const row = try b.reference(b.parameter(safe, 2));
    const count = try b.primitive(integer, .sequence_length, &.{old_board}, 0);
    const missing = try b.variable(unit);
    const present = try b.variable(integer);
    const old_col = try b.reference(present);
    const row_distance = try arithmetic(b, .integer_sub, count, row);
    const column_distance = try b.variable(integer);
    const abs_difference = try b.term(.{ .conditional = .{ .condition = try b.primitive(boolean, .less, &.{ col, old_col }, 0), .when_true = try b.pure(try arithmetic(b, .integer_sub, old_col, col)), .when_false = try b.pure(try arithmetic(b, .integer_sub, col, old_col)) } });
    const retry = try b.term(.{ .call = .{ .function = safe, .arguments = &.{ old_board, col, try arithmetic(b, .integer_add, row, try b.constant(u64, 1)) } } });
    const diagonal = try b.term(.{ .conditional = .{ .condition = try b.primitive(boolean, .equal, &.{ try b.reference(column_distance), row_distance }, 0), .when_true = try b.pure(try b.constant(bool, false)), .when_false = retry } });
    const clash = try b.term(.{ .conditional = .{ .condition = try b.primitive(boolean, .equal, &.{ col, old_col }, 0), .when_true = try b.pure(try b.constant(bool, false)), .when_false = try b.bind(column_distance, abs_difference, diagonal) } });
    const optional_int = try b.schema(.{ .sum = &.{ unit, integer } });
    const checked = try b.term(.{ .match_sum = .{ .value = try b.primitive(optional_int, .sequence_get, &.{ old_board, row }, 0), .cases = &.{ .{ .variable = missing, .body = try b.term(.{ .fail = try b.constant(void, {}) }) }, .{ .variable = present, .body = clash } } } });
    try b.define(safe, try b.term(.{ .conditional = .{ .condition = try b.primitive(boolean, .equal, &.{ row, count }, 0), .when_true = try b.pure(try b.constant(bool, true)), .when_false = checked } }));

    // Representation access stays in these private implementation functions.
    const acquire = try b.declare(&.{board}, owned, &.{acquiring}, &.{});
    const use = try b.declare(&.{ borrowed, board, integer }, board, &.{using}, &.{loan});
    const info = try cleanup.exitInfo(b, unit);
    const release = try b.declare(&.{ info, owned }, unit, &.{releasing}, &.{});
    try b.resourceAuthority(owned, &.{acquire}, &.{ use, release });
    const raw = try b.variable(integer);
    try b.define(acquire, try b.bind(raw, try b.term(.{ .perform = .{ .effect = acquiring, .payload = try b.reference(b.parameter(acquire, 0)) } }), try b.pure(try b.primitive(owned, .resource_pack, &.{try b.reference(raw)}, 0))));
    const handle = try b.primitive(integer, .resource_unpack, &.{try b.reference(b.parameter(use, 0))}, 0);
    const use_board = try b.reference(b.parameter(use, 1));
    const payload = try b.primitive(use_payload, .product, &.{ handle, use_board, try b.reference(b.parameter(use, 2)) }, 0);
    try b.define(use, try b.bind(try b.variable(unit), try b.term(.{ .perform = .{ .effect = using, .payload = payload } }), try b.pure(use_board)));
    try b.define(release, try b.term(.{ .perform = .{ .effect = releasing, .payload = try b.primitive(integer, .resource_unpack, &.{try b.reference(b.parameter(release, 1))}, 0) } }));
    const use_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{ borrowed, board, integer }, .result = board, .effects = &.{using}, .regions = &.{loan} } } });
    const release_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{ info, owned }, .result = unit, .effects = &.{releasing} } } });

    const cell = try b.reference(b.parameter(solve, 0));
    const metric = try b.reference(b.parameter(solve, 1));
    const pick_cap = try b.reference(b.parameter(solve, 2));
    const reject_cap = try b.reference(b.parameter(solve, 3));
    const current = try b.variable(board);
    const current_board = try b.reference(current);
    const completed_resource = try b.variable(owned);
    const complete = try b.bind(completed_resource, try b.term(.{ .call = .{ .function = acquire, .arguments = &.{current_board} } }), try b.term(.{ .protect = .{ .body = try b.lambda(use, use_type), .cleanup = try b.lambda(release, release_type), .resource = try b.reference(completed_resource), .loan_region = loan, .arguments = &.{ current_board, try b.primitive(integer, .cell_get, &.{metric}, 0) } } }));
    const high = try b.variable(boolean);
    const low = try b.variable(boolean);
    const base = try b.variable(integer);
    const column = try b.variable(integer);
    const incremented = try b.variable(integer);
    const valid = try b.variable(boolean);
    const pick = try b.term(.{ .perform = .{ .effect = interpretation.pick, .capability = pick_cap, .payload = try b.constant(void, {}) } });
    const first_half = try b.term(.{ .conditional = .{ .condition = try b.reference(high), .when_true = try b.pure(try b.constant(u64, 3)), .when_false = try b.pure(try b.constant(u64, 1)) } });
    const selected_column = try b.term(.{ .conditional = .{ .condition = try b.reference(low), .when_true = try b.pure(try arithmetic(b, .integer_add, try b.reference(base), try b.constant(u64, 1))), .when_false = try b.pure(try b.reference(base)) } });
    const increased = try arithmetic(b, .integer_add, try b.primitive(integer, .cell_get, &.{metric}, 0), try b.constant(u64, 1));
    const recurse = try b.term(.{ .call = .{ .function = solve, .arguments = &.{ cell, metric, pick_cap, reject_cap } } });
    const accepted = try b.bind(try b.variable(unit), try b.pure(try b.primitive(unit, .cell_set, &.{ cell, try b.primitive(board, .sequence_append, &.{ current_board, try b.reference(column) }, 0) }, 0)), recurse);
    const rejected = try b.bind(try b.variable(unit), try b.term(.{ .perform = .{ .effect = interpretation.reject, .capability = reject_cap, .payload = try b.constant(void, {}) } }), try b.pure(current_board));
    const verdict = try b.term(.{ .conditional = .{ .condition = try b.reference(valid), .when_true = accepted, .when_false = rejected } });
    const validate = try b.bind(valid, try b.term(.{ .call = .{ .function = safe, .arguments = &.{ current_board, try b.reference(column), try b.constant(u64, 0) } } }), verdict);
    const transfer = try b.term(.{ .conditional = .{ .condition = try b.primitive(boolean, .equal, &.{ try b.reference(incremented), try b.constant(u64, 1) }, 0), .when_true = try b.term(.{ .yield_then = validate }), .when_false = validate } });
    const attempt = try b.bind(incremented, try b.pure(increased), try b.bind(try b.variable(unit), try b.pure(try b.primitive(unit, .cell_set, &.{ metric, try b.reference(incremented) }, 0)), transfer));
    const choose_column = try b.bind(high, pick, try b.bind(low, pick, try b.bind(base, first_half, try b.bind(column, selected_column, attempt))));
    try b.define(solve, try b.bind(current, try b.pure(try b.primitive(board, .cell_get, &.{cell}, 0)), try b.term(.{ .conditional = .{ .condition = try b.primitive(boolean, .equal, &.{ try b.primitive(integer, .sequence_length, &.{current_board}, 0), try b.constant(u64, 4) }, 0), .when_true = complete, .when_false = choose_column } })));

    const counter = try b.variable(metrics_cell);
    const constraints = try b.variable(board_cell);
    const solved = try b.term(.{ .call = .{ .function = solve, .arguments = &.{ try b.reference(constraints), try b.reference(counter), try b.reference(b.parameter(handled_body, 0)), try b.reference(b.parameter(handled_body, 1)) } } });
    try b.define(inside, try b.bind(constraints, try b.pure(try b.primitive(board_cell, .cell_new, &.{ try b.reference(b.parameter(inside, 0)), try b.primitive(board, .sequence, &.{}, 0) }, 0)), solved));
    const inside_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{local_region}, .result = board, .effects = operations.effects, .capture_bound = &.{ metrics_cell, interpretation.pick_capability, interpretation.reject_capability }, .regions = &.{ shared, local } } } });
    try b.define(handled_body, try b.term(.{ .with_region = .{ .region = local, .body = try b.lambda(inside, inside_type) } }));
    const handled_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{ interpretation.pick_capability, interpretation.reject_capability }, .result = board, .effects = operations.effects, .capture_bound = &.{metrics_cell}, .regions = &.{shared} } } });
    const step = try b.variable(interpretation.step);
    const solutions = try b.variable(interpretation.solutions);
    const collected = try b.bind(solutions, try search.collect(b, interpretation, try b.reference(step)), try b.pure(try b.primitive(answer, .product, &.{ try b.reference(solutions), try b.primitive(integer, .cell_get, &.{try b.reference(counter)}, 0) }, 0)));
    const handled = try b.bind(step, try b.term(.{ .handle = .{ .handler = interpretation.handler, .body = try b.lambda(handled_body, handled_type) } }), collected);
    try b.define(outer, try b.bind(counter, try b.pure(try b.primitive(metrics_cell, .cell_new, &.{ try b.reference(b.parameter(outer, 0)), try b.constant(u64, 0) }, 0)), handled));
    const outer_type = try b.schema(.{ .internal = .{ .computation = .{ .parameters = &.{shared_region}, .result = answer, .effects = residual.effects, .regions = &.{shared} } } });
    try b.define(main, try b.term(.{ .with_region = .{ .region = shared, .body = try b.lambda(outer, outer_type) } }));
    return b.module(main, unit);
}
