// zlinter-disable declaration_naming field_naming field_ordering require_doc_comment no_inferred_error_unions max_positional_args
const boundary = @import("boundary");
const std = @import("std");

const RefExpectation = struct {
    codec: boundary.ir.ValueCodec,
    schema_index: ?u16 = null,
};

fn mustInstruction(result: anyerror!boundary.ir.plan.Instruction) boundary.ir.plan.Instruction {
    return result catch |err| std.debug.panic("invalid contract matrix instruction: {s}", .{@errorName(err)});
}

fn mustPlan(result: anyerror!boundary.ir.ProgramPlan) boundary.ir.ProgramPlan {
    return result catch |err| std.debug.panic("invalid contract matrix plan: {s}", .{@errorName(err)});
}

fn expectRequirement(
    comptime Contract: type,
    comptime index: usize,
    comptime label: []const u8,
    comptime lifecycle_tag: anytype,
    comptime output_tag: anytype,
) !void {
    try std.testing.expectEqualStrings(label, Contract.requirements[index].label);
    try std.testing.expectEqual(
        @as(@TypeOf(Contract.requirements[index].lifecycle_tag), lifecycle_tag),
        Contract.requirements[index].lifecycle_tag,
    );
    try std.testing.expectEqual(
        @as(@TypeOf(Contract.requirements[index].output_tag), output_tag),
        Contract.requirements[index].output_tag,
    );
}

fn expectOp(
    comptime Contract: type,
    comptime index: usize,
    comptime requirement_label: []const u8,
    comptime op_name: []const u8,
    comptime mode: anytype,
    payload_ref: RefExpectation,
    resume_ref: RefExpectation,
    has_after: bool,
) !void {
    try std.testing.expectEqualStrings(requirement_label, Contract.ops[index].requirement_label);
    try std.testing.expectEqualStrings(op_name, Contract.ops[index].op_name);
    try std.testing.expectEqual(@as(@TypeOf(Contract.ops[index].mode), mode), Contract.ops[index].mode);
    try expectRef(Contract.ops[index].payload_ref, payload_ref);
    try expectRef(Contract.ops[index].resume_ref, resume_ref);
    try std.testing.expectEqual(has_after, Contract.ops[index].has_after);
}

fn expectRef(actual: anytype, expected: RefExpectation) !void {
    try std.testing.expectEqual(expected.codec, actual.codec);
    try std.testing.expectEqual(expected.schema_index, actual.schema_index);
}

fn expectExecutable(comptime Contract: type) !void {
    try std.testing.expect(Contract.executable.supported);
    try std.testing.expectEqual(@as(usize, 0), Contract.executable.blocker_count);
    try std.testing.expectEqualStrings("capability ledger: blockers=0 truncated=false", Contract.executable.summary);
}

fn expectNoNestedTargetsOrReturnErrors(comptime Contract: type) !void {
    try std.testing.expect(!Contract.has_nested_with_targets);
    try std.testing.expectEqual(@as(usize, 0), Contract.nested_with_targets.len);
    try std.testing.expectEqual(@as(usize, 0), Contract.return_errors.len);
}

const optional_plan = boundary.effect.optional.plan;
const reader_plan = boundary.effect.reader.plan;
const state_plan = boundary.effect.state.plan;
const writer_plan = boundary.effect.writer.plan;
const OptionalOutcome = optional_plan.Outcome(i32);

const OptionalHandlers = struct {
    request: struct {
        pub fn dispatch(_: *const @This()) !boundary.effect.choice.Decision(OptionalOutcome, i32) {
            return boundary.effect.choice.Decision(OptionalOutcome, i32).resumeWith(40);
        }

        pub fn afterDispatch(_: *const @This(), value: i32) !i32 {
            return value + 1;
        }
    },
};

fn optionalPlan() boundary.ir.ProgramPlan {
    const layout = boundary.ir.builder.layout;
    const root = comptime boundary.ir.builder.function(0);
    const resumed = comptime boundary.ir.builder.local(root, 0);
    const is_some = comptime boundary.ir.builder.local(root, 1);
    const extracted = comptime boundary.ir.builder.local(root, 2);
    const fallback = comptime boundary.ir.builder.local(root, 3);
    const requirements = [_]boundary.ir.plan.Requirement{optional_plan.requirement(0)};
    const ops = [_]boundary.ir.plan.Op{optional_plan.requestOp(0, 0, .present)};
    const variants = optional_plan.variants(i32);
    const schemas = [_]boundary.ir.ValueSchemaPlan{optional_plan.schema(i32, 0, 0)};

    return mustPlan(boundary.ir.builder.layout.finish(.{
        .label = "matrix-plan-native-optional",
        .ir_hash = 9001,
        .entry = root,
        .requirements = &requirements,
        .ops = &ops,
        .value_schemas = &schemas,
        .value_variants = &variants,
        .functions = .{.{
            .symbol_name = "run",
            .value_ref = boundary.ir.ValueRef{ .codec = .i32 },
            .result_ref = boundary.ir.ValueRef{ .codec = .i32 },
            .requirements = layout.span(0, 1),
            .locals = .{
                optional_plan.local(0),
                .{ .codec = .bool },
                .{ .codec = .i32 },
                .{ .codec = .i32 },
            },
            .blocks = .{
                .{
                    .instructions = .{
                        mustInstruction(optional_plan.callRequest(root, resumed, boundary.ir.builder.op(root, 0))),
                        mustInstruction(optional_plan.isSome(root, is_some, resumed)),
                    },
                    .terminator = boundary.ir.plan.Terminator{ .kind = .branch_if, .primary = 1, .secondary = 2 },
                },
                .{
                    .instructions = .{
                        mustInstruction(optional_plan.extractSome(root, extracted, resumed)),
                        mustInstruction(boundary.ir.builder.returnValue(root, extracted)),
                    },
                    .terminator = boundary.ir.plan.Terminator{ .kind = .return_value },
                },
                .{
                    .instructions = .{
                        .{ .kind = .const_i32, .dst = fallback.index, .operand = 0 },
                        mustInstruction(boundary.ir.builder.returnValue(root, fallback)),
                    },
                    .terminator = boundary.ir.plan.Terminator{ .kind = .return_value },
                },
            },
        }},
    }));
}

const ProductThenOptionalInput = struct {
    amount: i32,
};

fn productThenOptionalPlan() boundary.ir.ProgramPlan {
    const layout = boundary.ir.builder.layout;
    const root = comptime boundary.ir.builder.function(0);
    const resumed = comptime boundary.ir.builder.local(root, 1);
    const is_some = comptime boundary.ir.builder.local(root, 2);
    const extracted = comptime boundary.ir.builder.local(root, 3);
    const fallback = comptime boundary.ir.builder.local(root, 4);
    const fields = [_]boundary.ir.ValueFieldPlan{
        boundary.ir.value.field("amount", i32),
    };
    const requirements = [_]boundary.ir.plan.Requirement{optional_plan.requirement(0)};
    const ops = [_]boundary.ir.plan.Op{optional_plan.requestOp(0, 1, .present)};
    const variants = optional_plan.variants(i32);
    const schemas = [_]boundary.ir.ValueSchemaPlan{
        .{
            .label = @typeName(ProductThenOptionalInput),
            .codec = .product,
            .first_field = 0,
            .field_count = @intCast(fields.len),
        },
        optional_plan.schema(i32, @intCast(fields.len), 0),
    };

    return mustPlan(boundary.ir.builder.layout.finish(.{
        .label = "matrix-product-then-optional",
        .ir_hash = 9010,
        .entry = root,
        .requirements = &requirements,
        .ops = &ops,
        .value_schemas = &schemas,
        .value_fields = &fields,
        .value_variants = &variants,
        .functions = .{.{
            .symbol_name = "run",
            .value_ref = boundary.ir.ValueRef{ .codec = .i32 },
            .result_ref = boundary.ir.ValueRef{ .codec = .i32 },
            .parameter_count = 1,
            .requirements = layout.span(0, 1),
            .locals = .{
                .{ .codec = .product, .schema_index = 0 },
                optional_plan.local(1),
                .{ .codec = .bool },
                .{ .codec = .i32 },
                .{ .codec = .i32 },
            },
            .blocks = .{
                .{
                    .instructions = .{
                        mustInstruction(optional_plan.callRequest(root, resumed, boundary.ir.builder.op(root, 0))),
                        mustInstruction(optional_plan.isSome(root, is_some, resumed)),
                    },
                    .terminator = boundary.ir.plan.Terminator{ .kind = .branch_if, .primary = 1, .secondary = 2 },
                },
                .{
                    .instructions = .{
                        mustInstruction(optional_plan.extractSome(root, extracted, resumed)),
                        mustInstruction(boundary.ir.builder.returnValue(root, extracted)),
                    },
                    .terminator = boundary.ir.plan.Terminator{ .kind = .return_value },
                },
                .{
                    .instructions = .{
                        .{ .kind = .const_i32, .dst = fallback.index, .operand = 0 },
                        mustInstruction(boundary.ir.builder.returnValue(root, fallback)),
                    },
                    .terminator = boundary.ir.plan.Terminator{ .kind = .return_value },
                },
            },
        }},
    }));
}

const LayoutProductPayload = struct {
    amount: i32,
};

const LayoutProductHandlers = struct {};

fn layoutProductOutputPlan() boundary.ir.ProgramPlan {
    const layout = boundary.ir.builder.layout;
    const root = comptime boundary.ir.builder.function(0);
    const payload = comptime boundary.ir.builder.local(root, 0);
    const fields = [_]boundary.ir.ValueFieldPlan{
        boundary.ir.value.field("amount", i32),
    };
    const schemas = [_]boundary.ir.ValueSchemaPlan{.{
        .label = @typeName(LayoutProductPayload),
        .codec = .product,
        .first_field = 0,
        .field_count = @intCast(fields.len),
    }};
    const outputs = [_]boundary.ir.plan.Output{.{
        .label = "writer",
        .codec = .i32,
    }};

    return mustPlan(boundary.ir.builder.layout.finish(.{
        .label = "matrix-layout-product-output",
        .ir_hash = 9002,
        .entry = root,
        .outputs = &outputs,
        .value_schemas = &schemas,
        .value_fields = &fields,
        .functions = .{.{
            .symbol_name = "run",
            .value_ref = boundary.ir.ValueRef{ .codec = .product, .schema_index = 0 },
            .result_ref = boundary.ir.ValueRef{ .codec = .product, .schema_index = 0 },
            .parameter_count = 1,
            .outputs = layout.span(0, 1),
            .locals = .{
                .{ .codec = .product, .schema_index = 0 },
            },
            .blocks = .{.{
                .instructions = .{
                    mustInstruction(boundary.ir.builder.returnValue(root, payload)),
                },
                .terminator = boundary.ir.plan.Terminator{ .kind = .return_value },
            }},
        }},
    }));
}

test "layout builder contract exposes product parameter and output metadata" {
    const Body = struct {
        pub const value_schema_types = .{LayoutProductPayload};
        pub const Outputs = []i32;
        pub const compiled_plan = layoutProductOutputPlan();

        pub fn encodeArgs(_: LayoutProductHandlers) @TypeOf(.{LayoutProductPayload{ .amount = 7 }}) {
            return .{LayoutProductPayload{ .amount = 7 }};
        }

        pub fn collectOutputs(allocator: std.mem.Allocator, _: *LayoutProductHandlers) !Outputs {
            const outputs = try allocator.alloc(i32, 1);
            outputs[0] = 12;
            return outputs;
        }

        pub fn deinitOutputs(allocator: std.mem.Allocator, outputs: Outputs) void {
            allocator.free(outputs);
        }
    };
    const Program = boundary.program("matrix-layout-product-output", LayoutProductHandlers, Body);

    try std.testing.expectEqualStrings("matrix-layout-product-output", Program.contract.label);
    try expectRef(Program.contract.result_ref, .{ .codec = .product, .schema_index = 0 });
    try std.testing.expectEqual(@as(usize, 1), Program.contract.entry_parameters.len);
    try std.testing.expectEqual(@as(u16, 0), Program.contract.entry_parameters[0].local_index);
    try expectRef(Program.contract.entry_parameters[0].ref, .{ .codec = .product, .schema_index = 0 });
    try std.testing.expectEqual(@as(usize, 1), Program.contract.value_schemas.len);
    try std.testing.expectEqualStrings(@typeName(LayoutProductPayload), Program.contract.value_schemas[0].label);
    try std.testing.expectEqual(boundary.ir.ValueCodec.product, Program.contract.value_schemas[0].codec);
    try std.testing.expectEqual(@as(u16, 0), Program.contract.value_schemas[0].first_field);
    try std.testing.expectEqual(@as(u16, 1), Program.contract.value_schemas[0].field_count);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.value_fields.len);
    try std.testing.expectEqualStrings("amount", Program.contract.value_fields[0].name);
    try expectRef(Program.contract.value_fields[0].ref, .{ .codec = .i32 });
    try std.testing.expectEqual(@as(usize, 0), Program.contract.value_variants.len);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.outputs.len);
    try std.testing.expectEqualStrings("writer", Program.contract.outputs[0].label);
    try std.testing.expectEqual(boundary.ir.ValueCodec.i32, Program.contract.outputs[0].codec);
    try std.testing.expectEqual(@as(?u16, null), Program.contract.outputs[0].schema_index);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.requirements.len);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.ops.len);
    try expectNoNestedTargetsOrReturnErrors(Program.contract);
    try expectExecutable(Program.contract);
}

test "plan-native contract conformance matrix optional" {
    const Body = struct {
        pub const value_schema_types = .{OptionalOutcome};
        pub const compiled_plan = optionalPlan();
    };
    const Program = boundary.program("matrix-plan-native-optional", OptionalHandlers, Body);

    try expectRequirement(Program.contract, 0, "optional", .choice_policy, .none);
    try expectOp(
        Program.contract,
        0,
        "optional",
        "request",
        .choice,
        .{ .codec = .unit },
        .{ .codec = .sum, .schema_index = 0 },
        true,
    );
    try expectRef(Program.contract.result_ref, .{ .codec = .i32 });
    try std.testing.expectEqual(@as(usize, 0), Program.contract.outputs.len);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.value_schemas.len);
    try std.testing.expectEqualStrings(@typeName(OptionalOutcome), Program.contract.value_schemas[0].label);
    try std.testing.expectEqual(boundary.ir.ValueCodec.sum, Program.contract.value_schemas[0].codec);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.value_fields.len);
    try std.testing.expectEqual(@as(usize, 2), Program.contract.value_variants.len);
    try std.testing.expectEqualStrings("none", Program.contract.value_variants[0].name);
    try expectRef(Program.contract.value_variants[0].ref, .{ .codec = .unit });
    try std.testing.expectEqualStrings("some", Program.contract.value_variants[1].name);
    try expectRef(Program.contract.value_variants[1].ref, .{ .codec = .i32 });
    try expectNoNestedTargetsOrReturnErrors(Program.contract);
    try expectExecutable(Program.contract);
}

test "optional helper schema preserves field offsets after product schemas" {
    const Body = struct {
        pub const value_schema_types = .{ ProductThenOptionalInput, OptionalOutcome };
        pub const compiled_plan = productThenOptionalPlan();

        pub fn encodeArgs(_: OptionalHandlers) @TypeOf(.{ProductThenOptionalInput{ .amount = 7 }}) {
            return .{ProductThenOptionalInput{ .amount = 7 }};
        }
    };
    const Program = boundary.program("matrix-product-then-optional", OptionalHandlers, Body);

    try expectRef(Program.contract.entry_parameters[0].ref, .{ .codec = .product, .schema_index = 0 });
    try expectOp(
        Program.contract,
        0,
        "optional",
        "request",
        .choice,
        .{ .codec = .unit },
        .{ .codec = .sum, .schema_index = 1 },
        true,
    );
    try std.testing.expectEqual(@as(usize, 2), Program.contract.value_schemas.len);
    try std.testing.expectEqualStrings(@typeName(ProductThenOptionalInput), Program.contract.value_schemas[0].label);
    try std.testing.expectEqual(boundary.ir.ValueCodec.product, Program.contract.value_schemas[0].codec);
    try std.testing.expectEqual(@as(u16, 0), Program.contract.value_schemas[0].first_field);
    try std.testing.expectEqual(@as(u16, 1), Program.contract.value_schemas[0].field_count);
    try std.testing.expectEqualStrings(@typeName(OptionalOutcome), Program.contract.value_schemas[1].label);
    try std.testing.expectEqual(boundary.ir.ValueCodec.sum, Program.contract.value_schemas[1].codec);
    try std.testing.expectEqual(@as(u16, 1), Program.contract.value_schemas[1].first_field);
    try std.testing.expectEqual(@as(u16, 0), Program.contract.value_schemas[1].first_variant);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.value_fields.len);
    try std.testing.expectEqual(@as(usize, 2), Program.contract.value_variants.len);

    var runtime = boundary.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var result = try Program.run(&runtime, .{ .request = .{} });
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 41), result.value);
}

const StateReaderHandlers = struct {
    get: struct {
        pub fn dispatch(_: *const @This()) !i32 {
            return 5;
        }
    },
    set: struct {
        pub fn dispatch(_: *const @This(), _: i32) !void {
            return {};
        }
    },
    ask: struct {
        pub fn dispatch(_: *const @This()) !i32 {
            return 7;
        }
    },
};

fn stateReaderPlan() boundary.ir.ProgramPlan {
    const layout = boundary.ir.builder.layout;
    const root = comptime boundary.ir.builder.function(0);
    const env = comptime boundary.ir.builder.local(root, 0);
    const before = comptime boundary.ir.builder.local(root, 1);
    const next = comptime boundary.ir.builder.local(root, 2);
    const StateRows = state_plan.Rows("state", i32, error{}, .{
        .requirement_index = 0,
        .first_op = 0,
        .first_output = 0,
    });
    const ReaderRows = reader_plan.Rows("reader", i32, error{}, .{
        .requirement_index = 1,
        .first_op = StateRows.op_count,
        .first_output = StateRows.output_count,
    });
    const requirements = [_]boundary.ir.plan.Requirement{
        StateRows.requirement,
        ReaderRows.requirement,
    };
    const ops = StateRows.ops ++ ReaderRows.ops;
    const outputs = StateRows.outputs ++ ReaderRows.outputs;
    return mustPlan(boundary.ir.builder.layout.finish(.{
        .label = "matrix-plan-native-state-reader",
        .ir_hash = 9002,
        .entry = root,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &outputs,
        .functions = .{.{
            .symbol_name = "run",
            .value_ref = boundary.ir.ValueRef{ .codec = .i32 },
            .result_ref = boundary.ir.ValueRef{ .codec = .i32 },
            .requirements = layout.span(0, 2),
            .outputs = layout.span(0, 1),
            .locals = .{
                reader_plan.envLocal(i32),
                state_plan.stateLocal(i32),
                state_plan.stateLocal(i32),
            },
            .blocks = .{.{
                .instructions = .{
                    mustInstruction(reader_plan.callAsk(root, env, reader_plan.askOp(root, StateRows.op_count))),
                    mustInstruction(state_plan.callGet(root, before, state_plan.getOp(root, 0))),
                    .{ .kind = .add_i32, .dst = next.index, .operand = before.index, .aux = env.index },
                    mustInstruction(state_plan.callSet(root, next, state_plan.setOp(root, 0))),
                    mustInstruction(boundary.ir.builder.returnValue(root, next)),
                },
                .terminator = boundary.ir.plan.Terminator{ .kind = .return_value },
            }},
        }},
    }));
}

test "plan-native contract conformance matrix state reader" {
    const Body = struct {
        pub const Outputs = []i32;
        pub const compiled_plan = stateReaderPlan();

        pub fn collectOutputs(allocator: std.mem.Allocator, _: *StateReaderHandlers) !Outputs {
            return try allocator.alloc(i32, 0);
        }

        pub fn deinitOutputs(allocator: std.mem.Allocator, outputs: Outputs) void {
            allocator.free(outputs);
        }
    };
    const Program = boundary.program("matrix-plan-native-state-reader", StateReaderHandlers, Body);

    try expectRequirement(Program.contract, 0, "state", .state_cell, .final_state);
    try expectRequirement(Program.contract, 1, "reader", .reader_environment, .none);
    try expectOp(Program.contract, 0, "state", "get", .transform, .{ .codec = .unit }, .{ .codec = .i32 }, false);
    try expectOp(Program.contract, 1, "state", "set", .transform, .{ .codec = .i32 }, .{ .codec = .unit }, false);
    try expectOp(Program.contract, 2, "reader", "ask", .transform, .{ .codec = .unit }, .{ .codec = .i32 }, false);
    try expectRef(Program.contract.result_ref, .{ .codec = .i32 });
    try std.testing.expectEqual(@as(usize, 1), Program.contract.outputs.len);
    try std.testing.expectEqualStrings("state", Program.contract.outputs[0].label);
    try std.testing.expectEqual(boundary.ir.ValueCodec.i32, Program.contract.outputs[0].codec);
    try std.testing.expectEqual(@as(?u16, null), Program.contract.outputs[0].schema_index);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.value_schemas.len);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.value_fields.len);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.value_variants.len);
    try expectNoNestedTargetsOrReturnErrors(Program.contract);
    try expectExecutable(Program.contract);
}

const WriterHandlers = struct {
    tell: struct {
        pub fn dispatch(_: *const @This(), _: i32) !void {
            return {};
        }
    },
};

fn writerPlan() boundary.ir.ProgramPlan {
    const layout = boundary.ir.builder.layout;
    const root = comptime boundary.ir.builder.function(0);
    const first = comptime boundary.ir.builder.local(root, 0);
    const second = comptime boundary.ir.builder.local(root, 1);
    const WriterRows = writer_plan.Rows("writer", i32, error{}, .{
        .requirement_index = 0,
        .first_op = 0,
        .first_output = 0,
    });
    const requirements = [_]boundary.ir.plan.Requirement{WriterRows.requirement};
    const ops = WriterRows.ops;
    const outputs = WriterRows.outputs;

    return mustPlan(boundary.ir.builder.layout.finish(.{
        .label = "matrix-plan-native-writer",
        .ir_hash = 9003,
        .entry = root,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &outputs,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = layout.span(0, 1),
            .outputs = layout.span(0, 1),
            .locals = .{
                writer_plan.itemLocal(i32),
                writer_plan.itemLocal(i32),
            },
            .blocks = .{.{
                .instructions = .{
                    .{ .kind = .const_i32, .dst = first.index, .operand = 4 },
                    mustInstruction(writer_plan.callTell(root, first, writer_plan.tellOp(root, 0))),
                    .{ .kind = .const_i32, .dst = second.index, .operand = 8 },
                    mustInstruction(writer_plan.callTell(root, second, writer_plan.tellOp(root, 0))),
                },
                .terminator = boundary.ir.plan.Terminator{ .kind = .return_unit },
            }},
        }},
    }));
}

test "plan-native contract conformance matrix writer" {
    const Body = struct {
        pub const Outputs = []i32;
        pub const compiled_plan = writerPlan();

        pub fn collectOutputs(allocator: std.mem.Allocator, _: *WriterHandlers) !Outputs {
            return try allocator.alloc(i32, 0);
        }

        pub fn deinitOutputs(allocator: std.mem.Allocator, outputs: Outputs) void {
            allocator.free(outputs);
        }
    };
    const Program = boundary.program("matrix-plan-native-writer", WriterHandlers, Body);

    try expectRequirement(Program.contract, 0, "writer", .writer_accumulator, .accumulator);
    try expectOp(Program.contract, 0, "writer", "tell", .transform, .{ .codec = .i32 }, .{ .codec = .unit }, false);
    try expectRef(Program.contract.result_ref, .{ .codec = .unit });
    try std.testing.expectEqual([]i32, Program.contract.OutputsType);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.outputs.len);
    try std.testing.expectEqualStrings("writer", Program.contract.outputs[0].label);
    try std.testing.expectEqual(boundary.ir.ValueCodec.i32, Program.contract.outputs[0].codec);
    try std.testing.expectEqual(@as(?u16, null), Program.contract.outputs[0].schema_index);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.value_schemas.len);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.value_fields.len);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.value_variants.len);
    try expectNoNestedTargetsOrReturnErrors(Program.contract);
    try expectExecutable(Program.contract);
}

const StructuredEffectPayload = struct {
    amount: i32,
};

const StructuredEffectOutputs = struct {
    final_state: StructuredEffectPayload,
    writer_items: []StructuredEffectPayload,
};

const StructuredEffectHandlers = struct {
    get: struct {
        pub fn dispatch(_: *const @This()) !StructuredEffectPayload {
            return .{ .amount = 5 };
        }
    },
    set: struct {
        pub fn dispatch(_: *const @This(), _: StructuredEffectPayload) !void {
            return {};
        }
    },
    ask: struct {
        pub fn dispatch(_: *const @This()) !StructuredEffectPayload {
            return .{ .amount = 7 };
        }
    },
    tell: struct {
        pub fn dispatch(_: *const @This(), _: StructuredEffectPayload) !void {
            return {};
        }
    },
};

fn structuredStateReaderWriterPlan() boundary.ir.ProgramPlan {
    const layout = boundary.ir.builder.layout;
    const root = comptime boundary.ir.builder.function(0);
    const current_state = comptime boundary.ir.builder.local(root, 0);
    const environment = comptime boundary.ir.builder.local(root, 1);
    const fields = [_]boundary.ir.ValueFieldPlan{boundary.ir.value.field("amount", i32)};
    const schemas = [_]boundary.ir.ValueSchemaPlan{.{
        .label = @typeName(StructuredEffectPayload),
        .codec = .product,
        .first_field = 0,
        .field_count = @intCast(fields.len),
    }};
    const schema_refs = boundary.ir.schema.SchemaRefs(.{
        boundary.ir.schema.ref(StructuredEffectPayload, 0),
    });
    const StateRows = state_plan.Rows("state", StructuredEffectPayload, error{}, .{
        .requirement_index = 0,
        .first_op = 0,
        .first_output = 0,
        .schema_refs = schema_refs,
    });
    const ReaderRows = reader_plan.Rows("reader", StructuredEffectPayload, error{}, .{
        .requirement_index = 1,
        .first_op = StateRows.op_count,
        .first_output = StateRows.output_count,
        .schema_refs = schema_refs,
    });
    const WriterRows = writer_plan.Rows("writer", StructuredEffectPayload, error{}, .{
        .requirement_index = 2,
        .first_op = StateRows.op_count + ReaderRows.op_count,
        .first_output = StateRows.output_count,
        .schema_refs = schema_refs,
    });
    const requirements = [_]boundary.ir.plan.Requirement{
        StateRows.requirement,
        ReaderRows.requirement,
        WriterRows.requirement,
    };
    const ops = StateRows.ops ++ ReaderRows.ops ++ WriterRows.ops;
    const outputs = StateRows.outputs ++ WriterRows.outputs;

    return mustPlan(boundary.ir.builder.layout.finish(.{
        .label = "matrix-plan-native-structured-effects",
        .ir_hash = 9011,
        .entry = root,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &outputs,
        .value_schemas = &schemas,
        .value_fields = &fields,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = layout.span(0, 3),
            .outputs = layout.span(0, 2),
            .locals = .{
                state_plan.stateLocalFromSchema(StructuredEffectPayload, 0),
                reader_plan.envLocalFromSchema(StructuredEffectPayload, 0),
            },
            .blocks = .{.{
                .instructions = .{
                    mustInstruction(state_plan.callGet(root, current_state, state_plan.getOp(root, 0))),
                    mustInstruction(reader_plan.callAsk(root, environment, reader_plan.askOp(root, StateRows.op_count))),
                    mustInstruction(state_plan.callSet(root, current_state, state_plan.setOp(root, 0))),
                    mustInstruction(writer_plan.callTell(root, environment, writer_plan.tellOp(root, StateRows.op_count + ReaderRows.op_count))),
                },
                .terminator = boundary.ir.plan.Terminator{ .kind = .return_unit },
            }},
        }},
    }));
}

test "plan-native contract conformance matrix structured state reader writer helpers" {
    const Body = struct {
        pub const value_schema_types = .{StructuredEffectPayload};
        pub const Outputs = StructuredEffectOutputs;
        pub const compiled_plan = structuredStateReaderWriterPlan();

        pub fn collectOutputs(allocator: std.mem.Allocator, _: *StructuredEffectHandlers) !Outputs {
            return .{
                .final_state = .{ .amount = 0 },
                .writer_items = try allocator.alloc(StructuredEffectPayload, 0),
            };
        }

        pub fn deinitOutputs(allocator: std.mem.Allocator, outputs: Outputs) void {
            allocator.free(outputs.writer_items);
        }
    };
    const Program = boundary.program("matrix-plan-native-structured-effects", StructuredEffectHandlers, Body);

    try expectRequirement(Program.contract, 0, "state", .state_cell, .final_state);
    try expectRequirement(Program.contract, 1, "reader", .reader_environment, .none);
    try expectRequirement(Program.contract, 2, "writer", .writer_accumulator, .accumulator);
    try expectOp(Program.contract, 0, "state", "get", .transform, .{ .codec = .unit }, .{ .codec = .product, .schema_index = 0 }, false);
    try expectOp(Program.contract, 1, "state", "set", .transform, .{ .codec = .product, .schema_index = 0 }, .{ .codec = .unit }, false);
    try expectOp(Program.contract, 2, "reader", "ask", .transform, .{ .codec = .unit }, .{ .codec = .product, .schema_index = 0 }, false);
    try expectOp(Program.contract, 3, "writer", "tell", .transform, .{ .codec = .product, .schema_index = 0 }, .{ .codec = .unit }, false);
    try std.testing.expectEqual(StructuredEffectOutputs, Program.contract.OutputsType);
    try std.testing.expectEqual(@as(usize, 2), Program.contract.outputs.len);
    try std.testing.expectEqualStrings("state", Program.contract.outputs[0].label);
    try expectRef(Program.contract.outputs[0], .{ .codec = .product, .schema_index = 0 });
    try std.testing.expectEqualStrings("writer", Program.contract.outputs[1].label);
    try expectRef(Program.contract.outputs[1], .{ .codec = .product, .schema_index = 0 });
    try std.testing.expectEqual(@as(usize, 1), Program.contract.value_schemas.len);
    try std.testing.expectEqualStrings(@typeName(StructuredEffectPayload), Program.contract.value_schemas[0].label);
    try std.testing.expectEqual(boundary.ir.ValueCodec.product, Program.contract.value_schemas[0].codec);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.value_fields.len);
    try std.testing.expectEqualStrings("amount", Program.contract.value_fields[0].name);
    try expectRef(Program.contract.value_fields[0].ref, .{ .codec = .i32 });
    try std.testing.expectEqual(@as(usize, 0), Program.contract.value_variants.len);
    try expectNoNestedTargetsOrReturnErrors(Program.contract);
    try expectExecutable(Program.contract);
}

const ProductPayload = struct {
    amount: i32,
};
const OptionalPayload = ?i32;

const ScalarExceptionHandlers = struct {
    throw: struct {
        pub fn dispatch(_: *const @This(), payload: i32) !i32 {
            return payload + 1;
        }
    },
};

const ProductExceptionHandlers = struct {
    throw: struct {
        pub fn dispatch(_: *const @This(), payload: ProductPayload) !ProductPayload {
            return .{ .amount = payload.amount + 1 };
        }
    },
};

const SumExceptionHandlers = struct {
    throw: struct {
        pub fn dispatch(_: *const @This(), payload: OptionalPayload) !i32 {
            return (payload orelse 0) + 1;
        }
    },
};

fn scalarExceptionPlan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const payload = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        .{ .kind = .const_i32, .dst = payload.index, .operand = 40 },
        mustInstruction(boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 0), payload)),
    };
    const ExceptionRows = boundary.ir.schema.LowerBinding(
        boundary.ir.schema.Binding("exception", boundary.effect.exception.Schema(i32, error{}, void), void),
        .{ .requirement_index = 0, .first_op = 0 },
    );
    return exceptionPlan(
        ExceptionRows,
        "matrix-plan-native-exception-scalar",
        9004,
        .{ .codec = .i32 },
        0,
        &instructions,
        &.{.{ .codec = .i32 }},
        &.{},
        &.{},
        &.{},
    );
}

fn productExceptionPlan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const payload = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        mustInstruction(boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 0), payload)),
    };
    const ExceptionRows = boundary.ir.schema.LowerBinding(
        boundary.ir.schema.Binding("exception", boundary.effect.exception.Schema(ProductPayload, error{}, void), void),
        .{
            .requirement_index = 0,
            .first_op = 0,
            .schema_refs = boundary.ir.schema.SchemaRefs(.{
                boundary.ir.schema.ref(ProductPayload, 0),
            }),
        },
    );
    const schemas = [_]boundary.ir.ValueSchemaPlan{.{
        .label = @typeName(ProductPayload),
        .codec = .product,
        .first_field = 0,
        .field_count = 1,
    }};
    const fields = [_]boundary.ir.ValueFieldPlan{.{ .name = "amount", .codec = .i32 }};
    return exceptionPlan(
        ExceptionRows,
        "matrix-plan-native-exception-product",
        9005,
        .{ .codec = .product, .schema_index = 0 },
        1,
        &instructions,
        &.{.{ .codec = .product, .schema_index = 0 }},
        &schemas,
        &fields,
        &.{},
    );
}

fn sumExceptionPlan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const payload = boundary.ir.builder.local(root, 0);
    const instructions = [_]boundary.ir.plan.Instruction{
        mustInstruction(boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 0), payload)),
    };
    const ExceptionRows = boundary.ir.schema.LowerBinding(
        boundary.ir.schema.Binding("exception", boundary.effect.exception.Schema(OptionalPayload, error{}, void), void),
        .{
            .requirement_index = 0,
            .first_op = 0,
            .schema_refs = boundary.ir.schema.SchemaRefs(.{
                boundary.ir.schema.ref(OptionalPayload, 0),
            }),
        },
    );
    const variants = [_]boundary.ir.ValueVariantPlan{
        boundary.ir.value.unitVariant("none"),
        boundary.ir.value.variant("some", i32),
    };
    const schemas = [_]boundary.ir.ValueSchemaPlan{.{
        .label = @typeName(OptionalPayload),
        .codec = .sum,
        .first_variant = 0,
        .variant_count = @intCast(variants.len),
    }};
    return exceptionPlan(
        ExceptionRows,
        "matrix-plan-native-exception-sum",
        9006,
        .{ .codec = .i32 },
        1,
        &instructions,
        &.{.{ .codec = .sum, .schema_index = 0 }},
        &schemas,
        &.{},
        &variants,
    );
}

fn exceptionPlan(
    comptime ExceptionRows: type,
    comptime label: []const u8,
    comptime hash: u64,
    comptime result_ref: boundary.ir.ValueRef,
    comptime parameter_count: u16,
    instructions: []const boundary.ir.plan.Instruction,
    locals: []const boundary.ir.plan.Local,
    schemas: []const boundary.ir.ValueSchemaPlan,
    fields: []const boundary.ir.ValueFieldPlan,
    variants: []const boundary.ir.ValueVariantPlan,
) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const requirements = [_]boundary.ir.plan.Requirement{ExceptionRows.requirement};
    const ops = ExceptionRows.ops;
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_unit }};
    return mustPlan(boundary.ir.builder.finish(.{
        .label = label,
        .ir_hash = hash,
        .entry = root,
        .functions = &.{.{
            .symbol_name = "run",
            .value_codec = .unit,
            .result_codec = result_ref.codec,
            .result_schema_index = result_ref.schema_index,
            .parameter_count = parameter_count,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = @intCast(locals.len),
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = @intCast(instructions.len),
        }},
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = schemas,
        .value_fields = fields,
        .value_variants = variants,
        .locals = locals,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = instructions,
    }));
}

test "plan-native contract conformance matrix exception" {
    const ScalarBody = struct {
        pub const compiled_plan = scalarExceptionPlan();
    };
    const ProductBody = struct {
        pub const value_schema_types = .{ProductPayload};
        pub const compiled_plan = productExceptionPlan();

        pub fn encodeArgs(_: ProductExceptionHandlers) @TypeOf(.{ProductPayload{ .amount = 50 }}) {
            return .{ProductPayload{ .amount = 50 }};
        }
    };
    const SumBody = struct {
        pub const value_schema_types = .{OptionalPayload};
        pub const compiled_plan = sumExceptionPlan();

        pub fn encodeArgs(_: SumExceptionHandlers) @TypeOf(.{@as(OptionalPayload, 60)}) {
            return .{@as(OptionalPayload, 60)};
        }
    };
    const ScalarProgram = boundary.program("matrix-plan-native-exception-scalar", ScalarExceptionHandlers, ScalarBody);
    const ProductProgram = boundary.program("matrix-plan-native-exception-product", ProductExceptionHandlers, ProductBody);
    const SumProgram = boundary.program("matrix-plan-native-exception-sum", SumExceptionHandlers, SumBody);

    try expectRequirement(ScalarProgram.contract, 0, "exception", .abort_catch, .none);
    try expectOp(ScalarProgram.contract, 0, "exception", "throw", .abort, .{ .codec = .i32 }, .{ .codec = .unit }, false);
    try expectRef(ScalarProgram.contract.result_ref, .{ .codec = .i32 });
    try expectNoNestedTargetsOrReturnErrors(ScalarProgram.contract);
    try expectExecutable(ScalarProgram.contract);

    try expectRequirement(ProductProgram.contract, 0, "exception", .abort_catch, .none);
    try expectOp(ProductProgram.contract, 0, "exception", "throw", .abort, .{ .codec = .product, .schema_index = 0 }, .{ .codec = .unit }, false);
    try expectRef(ProductProgram.contract.result_ref, .{ .codec = .product, .schema_index = 0 });
    try std.testing.expectEqual(@as(usize, 1), ProductProgram.contract.value_schemas.len);
    try std.testing.expectEqualStrings(@typeName(ProductPayload), ProductProgram.contract.value_schemas[0].label);
    try std.testing.expectEqual(boundary.ir.ValueCodec.product, ProductProgram.contract.value_schemas[0].codec);
    try std.testing.expectEqual(@as(usize, 1), ProductProgram.contract.value_fields.len);
    try std.testing.expectEqualStrings("amount", ProductProgram.contract.value_fields[0].name);
    try expectRef(ProductProgram.contract.value_fields[0].ref, .{ .codec = .i32 });
    try expectNoNestedTargetsOrReturnErrors(ProductProgram.contract);
    try expectExecutable(ProductProgram.contract);

    try expectRequirement(SumProgram.contract, 0, "exception", .abort_catch, .none);
    try expectOp(SumProgram.contract, 0, "exception", "throw", .abort, .{ .codec = .sum, .schema_index = 0 }, .{ .codec = .unit }, false);
    try expectRef(SumProgram.contract.result_ref, .{ .codec = .i32 });
    try std.testing.expectEqual(@as(usize, 1), SumProgram.contract.value_schemas.len);
    try std.testing.expectEqualStrings(@typeName(OptionalPayload), SumProgram.contract.value_schemas[0].label);
    try std.testing.expectEqual(boundary.ir.ValueCodec.sum, SumProgram.contract.value_schemas[0].codec);
    try std.testing.expectEqual(@as(usize, 2), SumProgram.contract.value_variants.len);
    try std.testing.expectEqualStrings("none", SumProgram.contract.value_variants[0].name);
    try expectRef(SumProgram.contract.value_variants[0].ref, .{ .codec = .unit });
    try std.testing.expectEqualStrings("some", SumProgram.contract.value_variants[1].name);
    try expectRef(SumProgram.contract.value_variants[1].ref, .{ .codec = .i32 });
    try expectNoNestedTargetsOrReturnErrors(SumProgram.contract);
    try expectExecutable(SumProgram.contract);
}

const Resource = struct {
    id: i32,
};

const ResourceMode = enum {
    normal,
    exception_escape,
    optional_escape,
};

const ResourceHandlers = struct {
    acquire: struct {
        pub fn dispatch(_: *const @This()) !Resource {
            return .{ .id = 1 };
        }
    },
    release: struct {
        pub fn dispatch(_: *const @This(), _: Resource) !void {
            return {};
        }
    },
    throw: struct {
        pub fn dispatch(_: *const @This(), payload: i32) !i32 {
            return payload;
        }
    },
    request: struct {
        pub fn dispatch(_: *const @This()) !boundary.effect.choice.Decision(i32, i32) {
            return boundary.effect.choice.Decision(i32, i32).returnNow(90);
        }
    },
};

fn resourcePlan(comptime mode: ResourceMode) boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const outer = boundary.ir.builder.local(root, 0);
    const inner = boundary.ir.builder.local(root, 1);
    const value = boundary.ir.builder.local(root, 2);
    const instructions = comptime blk: {
        var buffer: [6]boundary.ir.plan.Instruction = undefined;
        buffer[0] = mustInstruction(boundary.ir.builder.callOp(root, outer, boundary.ir.builder.op(root, 0), null));
        buffer[1] = mustInstruction(boundary.ir.builder.callOp(root, inner, boundary.ir.builder.op(root, 0), null));
        buffer[2] = mustInstruction(boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 1), inner));
        buffer[3] = mustInstruction(boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 1), outer));
        switch (mode) {
            .normal => {
                buffer[4] = .{ .kind = .const_i32, .dst = value.index, .operand = 12 };
                buffer[5] = mustInstruction(boundary.ir.builder.returnValue(root, value));
            },
            .exception_escape => {
                buffer[4] = .{ .kind = .const_i32, .dst = value.index, .operand = 80 };
                buffer[5] = mustInstruction(boundary.ir.builder.callOp(root, null, boundary.ir.builder.op(root, 2), value));
            },
            .optional_escape => {
                buffer[4] = mustInstruction(boundary.ir.builder.callOp(root, value, boundary.ir.builder.op(root, 2), null));
                buffer[5] = mustInstruction(boundary.ir.builder.returnValue(root, value));
            },
        }
        break :blk buffer;
    };
    const ResourceRows = boundary.ir.schema.LowerBinding(
        boundary.ir.schema.Binding("resource", boundary.effect.resource.Schema(Resource, error{}, void), void),
        .{
            .requirement_index = 0,
            .first_op = 0,
            .schema_refs = boundary.ir.schema.SchemaRefs(.{
                boundary.ir.schema.ref(Resource, 0),
            }),
        },
    );
    const ExceptionRows = boundary.ir.schema.LowerBinding(
        boundary.ir.schema.Binding("exception", boundary.effect.exception.Schema(i32, error{}, void), void),
        .{ .requirement_index = 1, .first_op = ResourceRows.op_count },
    );
    const OptionalRows = boundary.ir.schema.LowerBinding(
        boundary.ir.schema.Binding("optional", boundary.effect.optional.Schema(i32, error{}, void), void),
        .{ .requirement_index = 1, .first_op = ResourceRows.op_count },
    );
    const requirements = switch (mode) {
        .normal => [_]boundary.ir.plan.Requirement{ResourceRows.requirement},
        .exception_escape => [_]boundary.ir.plan.Requirement{
            ResourceRows.requirement,
            ExceptionRows.requirement,
        },
        .optional_escape => [_]boundary.ir.plan.Requirement{
            ResourceRows.requirement,
            OptionalRows.requirement,
        },
    };
    const ops = switch (mode) {
        .normal => ResourceRows.ops,
        .exception_escape => ResourceRows.ops ++ ExceptionRows.ops,
        .optional_escape => ResourceRows.ops ++ OptionalRows.ops,
    };
    const schemas = [_]boundary.ir.ValueSchemaPlan{.{
        .label = @typeName(Resource),
        .codec = .product,
        .first_field = 0,
        .field_count = 1,
    }};
    const fields = [_]boundary.ir.ValueFieldPlan{.{ .name = "id", .codec = .i32 }};
    const blocks = [_]boundary.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = if (mode == .exception_escape) .return_unit else .return_value }};

    return mustPlan(boundary.ir.builder.finish(.{
        .label = switch (mode) {
            .normal => "matrix-plan-native-resource-normal",
            .exception_escape => "matrix-plan-native-resource-exception",
            .optional_escape => "matrix-plan-native-resource-optional",
        },
        .ir_hash = switch (mode) {
            .normal => 9007,
            .exception_escape => 9008,
            .optional_escape => 9009,
        },
        .entry = root,
        .functions = &.{.{
            .symbol_name = "run",
            .value_codec = if (mode == .exception_escape) .unit else .i32,
            .result_codec = .i32,
            .first_requirement = 0,
            .requirement_count = if (mode == .normal) 1 else 2,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 3,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = @intCast(instructions.len),
        }},
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &schemas,
        .value_fields = &fields,
        .value_variants = &.{},
        .locals = &.{
            .{ .codec = .product, .schema_index = 0 },
            .{ .codec = .product, .schema_index = 0 },
            .{ .codec = .i32 },
        },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }));
}

test "plan-native contract conformance matrix resource" {
    const NormalBody = struct {
        pub const Error = error{ReleaseFailed};
        pub const value_schema_types = .{Resource};
        pub const compiled_plan = resourcePlan(.normal);
    };
    const ExceptionBody = struct {
        pub const Error = error{ReleaseFailed};
        pub const value_schema_types = .{Resource};
        pub const compiled_plan = resourcePlan(.exception_escape);
    };
    const OptionalBody = struct {
        pub const Error = error{ReleaseFailed};
        pub const value_schema_types = .{Resource};
        pub const compiled_plan = resourcePlan(.optional_escape);
    };
    const NormalProgram = boundary.program("matrix-plan-native-resource-normal", ResourceHandlers, NormalBody);
    const ExceptionProgram = boundary.program("matrix-plan-native-resource-exception", ResourceHandlers, ExceptionBody);
    const OptionalProgram = boundary.program("matrix-plan-native-resource-optional", ResourceHandlers, OptionalBody);

    try expectRequirement(NormalProgram.contract, 0, "resource", .resource_bracket, .none);
    try expectOp(NormalProgram.contract, 0, "resource", "acquire", .transform, .{ .codec = .unit }, .{ .codec = .product, .schema_index = 0 }, false);
    try expectOp(NormalProgram.contract, 1, "resource", "release", .transform, .{ .codec = .product, .schema_index = 0 }, .{ .codec = .unit }, false);
    try expectRef(NormalProgram.contract.result_ref, .{ .codec = .i32 });
    try std.testing.expectEqual(@as(usize, 0), NormalProgram.contract.outputs.len);
    try std.testing.expectEqual(@as(usize, 1), NormalProgram.contract.value_schemas.len);
    try std.testing.expectEqualStrings(@typeName(Resource), NormalProgram.contract.value_schemas[0].label);
    try std.testing.expectEqual(boundary.ir.ValueCodec.product, NormalProgram.contract.value_schemas[0].codec);
    try std.testing.expectEqual(@as(usize, 1), NormalProgram.contract.value_fields.len);
    try std.testing.expectEqualStrings("id", NormalProgram.contract.value_fields[0].name);
    try expectRef(NormalProgram.contract.value_fields[0].ref, .{ .codec = .i32 });
    try std.testing.expectEqual(@as(usize, 0), NormalProgram.contract.value_variants.len);
    try expectNoNestedTargetsOrReturnErrors(NormalProgram.contract);
    try expectExecutable(NormalProgram.contract);

    try expectRequirement(ExceptionProgram.contract, 0, "resource", .resource_bracket, .none);
    try expectRequirement(ExceptionProgram.contract, 1, "exception", .abort_catch, .none);
    try expectOp(ExceptionProgram.contract, 0, "resource", "acquire", .transform, .{ .codec = .unit }, .{ .codec = .product, .schema_index = 0 }, false);
    try expectOp(ExceptionProgram.contract, 1, "resource", "release", .transform, .{ .codec = .product, .schema_index = 0 }, .{ .codec = .unit }, false);
    try expectOp(ExceptionProgram.contract, 2, "exception", "throw", .abort, .{ .codec = .i32 }, .{ .codec = .unit }, false);
    try expectRef(ExceptionProgram.contract.result_ref, .{ .codec = .i32 });
    try std.testing.expectEqual(@as(usize, 0), ExceptionProgram.contract.outputs.len);
    try std.testing.expectEqual(@as(usize, 1), ExceptionProgram.contract.value_schemas.len);
    try std.testing.expectEqual(@as(usize, 1), ExceptionProgram.contract.value_fields.len);
    try std.testing.expectEqual(@as(usize, 0), ExceptionProgram.contract.value_variants.len);
    try expectNoNestedTargetsOrReturnErrors(ExceptionProgram.contract);
    try expectExecutable(ExceptionProgram.contract);

    try expectRequirement(OptionalProgram.contract, 0, "resource", .resource_bracket, .none);
    try expectRequirement(OptionalProgram.contract, 1, "optional", .choice_policy, .none);
    try expectOp(OptionalProgram.contract, 0, "resource", "acquire", .transform, .{ .codec = .unit }, .{ .codec = .product, .schema_index = 0 }, false);
    try expectOp(OptionalProgram.contract, 1, "resource", "release", .transform, .{ .codec = .product, .schema_index = 0 }, .{ .codec = .unit }, false);
    try expectOp(OptionalProgram.contract, 2, "optional", "request", .choice, .{ .codec = .unit }, .{ .codec = .i32 }, false);
    try expectRef(OptionalProgram.contract.result_ref, .{ .codec = .i32 });
    try std.testing.expectEqual(@as(usize, 0), OptionalProgram.contract.outputs.len);
    try std.testing.expectEqual(@as(usize, 1), OptionalProgram.contract.value_schemas.len);
    try std.testing.expectEqual(@as(usize, 1), OptionalProgram.contract.value_fields.len);
    try std.testing.expectEqual(@as(usize, 0), OptionalProgram.contract.value_variants.len);
    try expectNoNestedTargetsOrReturnErrors(OptionalProgram.contract);
    try expectExecutable(OptionalProgram.contract);
}
