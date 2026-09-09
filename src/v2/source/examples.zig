// Copyright (c) 2026 Boundary contributors. MIT license.
//! Public source construction examples; no target blocks or runtime callbacks.
const source = @import("../source.zig");
const data = @import("boundary_data_v2");
const p = data.program;
const Error = source.Error;

fn binary(builder: *source.Builder, opcode: p.Opcode, schema: p.Id, left: p.Id, right: p.Id, fault: p.Id) Error!p.Id {
    return builder.value(.{ .schema = schema, .expression = .{ .primitive = .{ .opcode = opcode, .operands = &.{ left, right }, .failures = if (opcode == .equal or opcode == .less) &.{} else &.{.{ .kind = .arithmetic_overflow, .value = try builder.failureLiteral(fault) }} } } });
}

pub const ownership = @import("ownership_example.zig").build;
pub const generator = @import("generator_example.zig").build;
pub const stateLocal = @import("state_choice_example.zig").local;
pub const stateShared = @import("state_choice_example.zig").shared;
pub const resourceScalar = @import("resource_example.zig").scalar;
pub const resourcePair = @import("resource_example.zig").pair;
pub const answers = @import("answer_example.zig").build;
pub const scopedReader = @import("scoped_reader_example.zig").build;
pub const writerRaise = @import("writer_raise_example.zig").build;
pub const schedulerFifo = @import("scheduler_example.zig").build;
pub const scalarContracts = @import("scalar_contract_example.zig").build;
pub const yieldingCleanup = @import("unwind_example.zig").yielding;
pub const borrowOperands = @import("borrow_operand_example.zig").build;

pub fn boundedValues(builder: *source.Builder) Error!source.ast.Module {
    const byte = try builder.scalar(u8);
    const enumeration = try builder.schema(.{ .enumeration = &.{ 2, 7 } });
    const never = try builder.schema(.{ .enumeration = &.{} });
    const array = try builder.schema(.{ .array = .{ .element = byte, .length = 2 } });
    const text = try builder.schema(.{ .bounded_text = 2 });
    const bytes = try builder.schema(.{ .bounded_bytes = 2 });
    const result = try builder.schema(.{ .product = &.{ enumeration, array, text, bytes } });
    const main = try builder.declare(&.{}, result, &.{}, &.{});
    const selected = try builder.literal(.{ .schema = enumeration, .bytes = &.{ 7, 0, 0, 0 } });
    const elements = try builder.primitive(array, .sequence, &.{ try builder.constant(u8, 9), try builder.constant(u8, 8) }, 0);
    const label = try builder.literal(.{ .schema = text, .bytes = &.{ 2, 0xc3, 0xa9 } });
    const payload = try builder.literal(.{ .schema = bytes, .bytes = &.{ 2, 0xff, 0 } });
    try builder.define(main, try builder.pure(try builder.primitive(result, .product, &.{ selected, elements, label, payload }, 0)));
    return builder.module(main, never);
}

pub fn lexical(builder: *source.Builder) Error!source.ast.Module {
    const integer = try builder.scalar(u64);
    const unit = try builder.scalar(void);
    const fault = try builder.constant(void, {});
    const main = try builder.declare(&.{integer}, integer, &.{}, &.{});
    const inner = try builder.declare(&.{integer}, integer, &.{}, &.{});
    const x = try builder.reference(builder.parameter(main, 0));
    const y = try builder.reference(builder.parameter(inner, 0));
    try builder.define(inner, try builder.pure(try binary(builder, .integer_add, integer, x, y, fault)));
    const function_type = try builder.schema(.{ .internal = .{ .computation = .{ .parameters = &.{integer}, .result = integer, .capture_bound = &.{integer} } } });
    const closure = try builder.lambda(inner, function_type);
    const retained = try builder.variable(function_type);
    const use = try builder.term(.{ .apply = .{ .computation = try builder.reference(retained), .arguments = &.{try builder.constant(u64, 2)} } });
    try builder.define(main, try builder.bind(retained, try builder.pure(closure), use));
    return builder.module(main, unit);
}

pub fn deep(builder: *source.Builder) Error!source.ast.Module {
    const unit = try builder.scalar(void);
    const integer = try builder.scalar(u64);
    const fault = try builder.constant(void, {});
    const operation = try builder.effect(.{ .identity = "example/ask", .payload = unit, .result = integer, .external = false });
    const capability = try builder.schema(.{ .internal = .{ .capability = operation } });
    const resumption = try builder.schema(.{ .internal = .{ .resumption = .{ .effect = operation, .input = integer, .answer = integer, .handled = &.{operation}, .mode = .deep, .use = .linear } } });
    const computation = try builder.schema(.{ .internal = .{ .computation = .{ .parameters = &.{capability}, .result = integer, .effects = &.{operation} } } });
    const main = try builder.declare(&.{}, integer, &.{}, &.{});
    const body = try builder.declare(&.{capability}, integer, &.{operation}, &.{});
    const returns = try builder.declare(&.{integer}, integer, &.{}, &.{});
    const clause = try builder.declare(&.{ unit, resumption }, integer, &.{}, &.{});
    const x = try builder.variable(integer);
    const performed = try builder.term(.{ .perform = .{ .effect = operation, .capability = try builder.reference(builder.parameter(body, 0)), .payload = fault } });
    try builder.define(body, try builder.bind(x, performed, try builder.pure(try binary(builder, .integer_add, integer, try builder.reference(x), try builder.constant(u64, 1), fault))));
    try builder.define(returns, try builder.pure(try binary(builder, .integer_mul, integer, try builder.reference(builder.parameter(returns, 0)), try builder.constant(u64, 10), fault)));
    const answer = try builder.variable(integer);
    const resumed = try builder.term(.{ .resume_value = .{ .resumption = try builder.reference(builder.parameter(clause, 1)), .argument = try builder.constant(u64, 5) } });
    try builder.define(clause, try builder.bind(answer, resumed, try builder.pure(try binary(builder, .integer_add, integer, try builder.reference(answer), try builder.constant(u64, 7), fault))));
    const handler = try builder.handler(.{ .mode = .deep, .input = integer, .answer = integer, .return_function = returns, .clauses = &.{.{ .effect = operation, .function = clause, .resumption = resumption }} });
    try builder.define(main, try builder.term(.{ .handle = .{ .handler = handler, .body = try builder.lambda(body, computation) } }));
    return builder.module(main, unit);
}

pub fn recursive(builder: *source.Builder) Error!source.ast.Module {
    const integer = try builder.scalar(u64);
    const boolean = try builder.scalar(bool);
    const unit = try builder.scalar(void);
    const fault = try builder.constant(void, {});
    const main = try builder.declare(&.{integer}, boolean, &.{}, &.{});
    const even = try builder.declare(&.{integer}, boolean, &.{}, &.{});
    const odd = try builder.declare(&.{integer}, boolean, &.{}, &.{});
    for ([_]p.Id{ even, odd }, 0..) |function, index| {
        const n = try builder.reference(builder.parameter(function, 0));
        const condition = try binary(builder, .equal, boolean, n, try builder.constant(u64, 0), fault);
        const decrement = try binary(builder, .integer_sub, integer, n, try builder.constant(u64, 1), fault);
        const recurse = try builder.term(.{ .call = .{ .function = if (index == 0) odd else even, .arguments = &.{decrement} } });
        try builder.define(function, try builder.term(.{ .conditional = .{ .condition = condition, .when_true = try builder.pure(try builder.constant(bool, index == 0)), .when_false = recurse } }));
    }
    try builder.define(main, try builder.term(.{ .call = .{ .function = even, .arguments = &.{try builder.reference(builder.parameter(main, 0))} } }));
    return builder.module(main, unit);
}

pub fn choicesAll(builder: *source.Builder) Error!source.ast.Module {
    return choices(builder, true);
}
pub fn choicesFirst(builder: *source.Builder) Error!source.ast.Module {
    return choices(builder, false);
}

fn choices(builder: *source.Builder, comptime every: bool) Error!source.ast.Module {
    const choice_library = @import("../library/choice.zig");
    const unit = try builder.scalar(void);
    const boolean = try builder.scalar(bool);
    const pair = try builder.schema(.{ .product = &.{ boolean, boolean } });
    const choice = try choice_library.family(builder, "example/boolean-choice");
    const answer = if (every) try choice_library.all(builder, choice, pair, &.{ boolean, choice.capability }, .{ .effects = &.{} }) else try choice_library.first(builder, choice, pair, &.{ boolean, choice.capability }, .{ .effects = &.{} });
    const main = try builder.declare(&.{}, answer.answer, &.{}, &.{});
    const body = try builder.declare(&.{choice.capability}, pair, &.{choice.effect}, &.{});
    const capability = try builder.reference(builder.parameter(body, 0));
    const payload = try builder.constant(void, {});
    const first_result = try builder.variable(boolean);
    const second_result = try builder.variable(boolean);
    const first = try builder.term(.{ .perform = .{ .effect = choice.effect, .capability = capability, .payload = payload } });
    const second = try builder.term(.{ .perform = .{ .effect = choice.effect, .capability = capability, .payload = payload } });
    const result = try builder.pure(try builder.value(.{ .schema = pair, .expression = .{ .primitive = .{ .opcode = .product, .operands = &.{ try builder.reference(first_result), try builder.reference(second_result) } } } }));
    try builder.define(body, try builder.bind(first_result, first, try builder.bind(second_result, second, result)));
    const body_schema = try builder.schema(.{ .internal = .{ .computation = .{ .parameters = &.{choice.capability}, .result = pair, .effects = &.{choice.effect} } } });
    try builder.define(main, try builder.term(.{ .handle = .{ .handler = answer.handler, .body = try builder.lambda(body, body_schema) } }));
    return builder.module(main, unit);
}
pub const queensDfs = @import("queens_example.zig").dfs;
pub const queensBfs = @import("queens_example.zig").bfs;
pub const cellOrder = @import("cell_order_example.zig").build;
pub const nested = @import("control_examples.zig").nested;
pub const shallow = @import("control_examples.zig").shallow;
pub const injection = @import("injection_example.zig").build;
pub const indexed = @import("indexed_example.zig").build;
pub const abortCustody = @import("abort_example.zig").build;
pub const unwind = @import("unwind_example.zig").build;
pub const reentrant = @import("reentrant_example.zig").build;
pub const cloned = @import("reentrant_example.zig").cloned;
pub const shallowResumptions = @import("shallow_resume_example.zig").build;
pub const shallowInjection = @import("injection_example.zig").shallow;
pub const handleOperandOrder = @import("operand_order_example.zig").handle;
pub const protectOperandOrder = @import("operand_order_example.zig").protect;
pub const successorState = @import("successor_state_example.zig").build;
pub const clausePayload = @import("clause_payload_example.zig").build;
pub const clauseAbort = @import("clause_abort_example.zig").build;
pub const installations = @import("economy_examples.zig").installations;
pub const blobCapture = @import("economy_examples.zig").blobCapture;
