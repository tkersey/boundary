// zlinter-disable declaration_naming field_naming field_ordering require_doc_comment no_inferred_error_unions max_positional_args
const ability = @import("ability");
const std = @import("std");

const RefExpectation = struct {
    codec: ability.ir.ValueCodec,
    schema_index: ?u16 = null,
};

fn mustInstruction(result: anyerror!ability.ir.plan.Instruction) ability.ir.plan.Instruction {
    return result catch |err| std.debug.panic("invalid contract matrix instruction: {s}", .{@errorName(err)});
}

fn mustPlan(result: anyerror!ability.ir.ProgramPlan) ability.ir.ProgramPlan {
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

const optional_plan = ability.effect.optional.plan;
const OptionalOutcome = optional_plan.Outcome(i32);

const OptionalHandlers = struct {
    request: struct {
        pub fn dispatch(_: *const @This()) !ability.effect.choice.Decision(OptionalOutcome, i32) {
            return ability.effect.choice.Decision(OptionalOutcome, i32).resumeWith(40);
        }

        pub fn afterDispatch(_: *const @This(), value: i32) !i32 {
            return value + 1;
        }
    },
};

fn optionalPlan() ability.ir.ProgramPlan {
    const layout = ability.ir.builder.layout;
    const root = comptime ability.ir.builder.function(0);
    const resumed = comptime ability.ir.builder.local(root, 0);
    const is_some = comptime ability.ir.builder.local(root, 1);
    const extracted = comptime ability.ir.builder.local(root, 2);
    const fallback = comptime ability.ir.builder.local(root, 3);
    const requirements = [_]ability.ir.plan.Requirement{optional_plan.requirement(0)};
    const ops = [_]ability.ir.plan.Op{optional_plan.requestOp(0, 0, .present)};
    const variants = optional_plan.variants(i32);
    const schemas = [_]ability.ir.ValueSchemaPlan{optional_plan.schema(i32, 0, 0)};

    return mustPlan(ability.ir.builder.layout.finish(.{
        .label = "matrix-plan-native-optional",
        .ir_hash = 9001,
        .entry = root,
        .requirements = &requirements,
        .ops = &ops,
        .value_schemas = &schemas,
        .value_variants = &variants,
        .functions = .{.{
            .symbol_name = "run",
            .value_ref = ability.ir.ValueRef{ .codec = .i32 },
            .result_ref = ability.ir.ValueRef{ .codec = .i32 },
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
                        mustInstruction(optional_plan.callRequest(root, resumed, ability.ir.builder.op(root, 0))),
                        mustInstruction(optional_plan.isSome(root, is_some, resumed)),
                    },
                    .terminator = ability.ir.plan.Terminator{ .kind = .branch_if, .primary = 1, .secondary = 2 },
                },
                .{
                    .instructions = .{
                        mustInstruction(optional_plan.extractSome(root, extracted, resumed)),
                        mustInstruction(ability.ir.builder.returnValue(root, extracted)),
                    },
                    .terminator = ability.ir.plan.Terminator{ .kind = .return_value },
                },
                .{
                    .instructions = .{
                        .{ .kind = .const_i32, .dst = fallback.index, .operand = 0 },
                        mustInstruction(ability.ir.builder.returnValue(root, fallback)),
                    },
                    .terminator = ability.ir.plan.Terminator{ .kind = .return_value },
                },
            },
        }},
    }));
}

const ProductThenOptionalInput = struct {
    amount: i32,
};

fn productThenOptionalPlan() ability.ir.ProgramPlan {
    const layout = ability.ir.builder.layout;
    const root = comptime ability.ir.builder.function(0);
    const resumed = comptime ability.ir.builder.local(root, 1);
    const is_some = comptime ability.ir.builder.local(root, 2);
    const extracted = comptime ability.ir.builder.local(root, 3);
    const fallback = comptime ability.ir.builder.local(root, 4);
    const fields = [_]ability.ir.ValueFieldPlan{
        ability.ir.value.field("amount", i32),
    };
    const requirements = [_]ability.ir.plan.Requirement{optional_plan.requirement(0)};
    const ops = [_]ability.ir.plan.Op{optional_plan.requestOp(0, 1, .present)};
    const variants = optional_plan.variants(i32);
    const schemas = [_]ability.ir.ValueSchemaPlan{
        .{
            .label = @typeName(ProductThenOptionalInput),
            .codec = .product,
            .first_field = 0,
            .field_count = @intCast(fields.len),
        },
        optional_plan.schema(i32, @intCast(fields.len), 0),
    };

    return mustPlan(ability.ir.builder.layout.finish(.{
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
            .value_ref = ability.ir.ValueRef{ .codec = .i32 },
            .result_ref = ability.ir.ValueRef{ .codec = .i32 },
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
                        mustInstruction(optional_plan.callRequest(root, resumed, ability.ir.builder.op(root, 0))),
                        mustInstruction(optional_plan.isSome(root, is_some, resumed)),
                    },
                    .terminator = ability.ir.plan.Terminator{ .kind = .branch_if, .primary = 1, .secondary = 2 },
                },
                .{
                    .instructions = .{
                        mustInstruction(optional_plan.extractSome(root, extracted, resumed)),
                        mustInstruction(ability.ir.builder.returnValue(root, extracted)),
                    },
                    .terminator = ability.ir.plan.Terminator{ .kind = .return_value },
                },
                .{
                    .instructions = .{
                        .{ .kind = .const_i32, .dst = fallback.index, .operand = 0 },
                        mustInstruction(ability.ir.builder.returnValue(root, fallback)),
                    },
                    .terminator = ability.ir.plan.Terminator{ .kind = .return_value },
                },
            },
        }},
    }));
}

const LayoutProductPayload = struct {
    amount: i32,
};

const LayoutProductHandlers = struct {};

fn layoutProductOutputPlan() ability.ir.ProgramPlan {
    const layout = ability.ir.builder.layout;
    const root = comptime ability.ir.builder.function(0);
    const payload = comptime ability.ir.builder.local(root, 0);
    const fields = [_]ability.ir.ValueFieldPlan{
        ability.ir.value.field("amount", i32),
    };
    const schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(LayoutProductPayload),
        .codec = .product,
        .first_field = 0,
        .field_count = @intCast(fields.len),
    }};
    const outputs = [_]ability.ir.plan.Output{.{
        .label = "writer",
        .codec = .i32,
    }};

    return mustPlan(ability.ir.builder.layout.finish(.{
        .label = "matrix-layout-product-output",
        .ir_hash = 9002,
        .entry = root,
        .outputs = &outputs,
        .value_schemas = &schemas,
        .value_fields = &fields,
        .functions = .{.{
            .symbol_name = "run",
            .value_ref = ability.ir.ValueRef{ .codec = .product, .schema_index = 0 },
            .result_ref = ability.ir.ValueRef{ .codec = .product, .schema_index = 0 },
            .parameter_count = 1,
            .outputs = layout.span(0, 1),
            .locals = .{
                .{ .codec = .product, .schema_index = 0 },
            },
            .blocks = .{.{
                .instructions = .{
                    mustInstruction(ability.ir.builder.returnValue(root, payload)),
                },
                .terminator = ability.ir.plan.Terminator{ .kind = .return_value },
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
    const Program = ability.program("matrix-layout-product-output", LayoutProductHandlers, Body);

    try std.testing.expectEqualStrings("matrix-layout-product-output", Program.contract.label);
    try expectRef(Program.contract.result_ref, .{ .codec = .product, .schema_index = 0 });
    try std.testing.expectEqual(@as(usize, 1), Program.contract.entry_parameters.len);
    try std.testing.expectEqual(@as(u16, 0), Program.contract.entry_parameters[0].local_index);
    try expectRef(Program.contract.entry_parameters[0].ref, .{ .codec = .product, .schema_index = 0 });
    try std.testing.expectEqual(@as(usize, 1), Program.contract.value_schemas.len);
    try std.testing.expectEqualStrings(@typeName(LayoutProductPayload), Program.contract.value_schemas[0].label);
    try std.testing.expectEqual(ability.ir.ValueCodec.product, Program.contract.value_schemas[0].codec);
    try std.testing.expectEqual(@as(u16, 0), Program.contract.value_schemas[0].first_field);
    try std.testing.expectEqual(@as(u16, 1), Program.contract.value_schemas[0].field_count);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.value_fields.len);
    try std.testing.expectEqualStrings("amount", Program.contract.value_fields[0].name);
    try expectRef(Program.contract.value_fields[0].ref, .{ .codec = .i32 });
    try std.testing.expectEqual(@as(usize, 0), Program.contract.value_variants.len);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.outputs.len);
    try std.testing.expectEqualStrings("writer", Program.contract.outputs[0].label);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, Program.contract.outputs[0].codec);
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
    const Program = ability.program("matrix-plan-native-optional", OptionalHandlers, Body);

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
    try std.testing.expectEqual(ability.ir.ValueCodec.sum, Program.contract.value_schemas[0].codec);
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
    const Program = ability.program("matrix-product-then-optional", OptionalHandlers, Body);

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
    try std.testing.expectEqual(ability.ir.ValueCodec.product, Program.contract.value_schemas[0].codec);
    try std.testing.expectEqual(@as(u16, 0), Program.contract.value_schemas[0].first_field);
    try std.testing.expectEqual(@as(u16, 1), Program.contract.value_schemas[0].field_count);
    try std.testing.expectEqualStrings(@typeName(OptionalOutcome), Program.contract.value_schemas[1].label);
    try std.testing.expectEqual(ability.ir.ValueCodec.sum, Program.contract.value_schemas[1].codec);
    try std.testing.expectEqual(@as(u16, 1), Program.contract.value_schemas[1].first_field);
    try std.testing.expectEqual(@as(u16, 0), Program.contract.value_schemas[1].first_variant);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.value_fields.len);
    try std.testing.expectEqual(@as(usize, 2), Program.contract.value_variants.len);

    var runtime = ability.Runtime.init(std.testing.allocator);
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

fn stateReaderPlan() ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const env = ability.ir.builder.local(root, 0);
    const before = ability.ir.builder.local(root, 1);
    const next = ability.ir.builder.local(root, 2);
    const instructions = [_]ability.ir.plan.Instruction{
        mustInstruction(ability.ir.builder.callOp(root, env, ability.ir.builder.op(root, 2), null)),
        mustInstruction(ability.ir.builder.callOp(root, before, ability.ir.builder.op(root, 0), null)),
        .{ .kind = .add_i32, .dst = next.index, .operand = before.index, .aux = env.index },
        mustInstruction(ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 1), next)),
        mustInstruction(ability.ir.builder.returnValue(root, next)),
    };
    const StateRows = ability.ir.schema.LowerBinding(
        ability.ir.schema.Binding("state", ability.effect.state.Schema(i32, error{}), void),
        .{ .requirement_index = 0, .first_op = 0, .first_output = 0 },
    );
    const ReaderRows = ability.ir.schema.LowerBinding(
        ability.ir.schema.Binding("reader", ability.effect.reader.Schema(i32, error{}), void),
        .{ .requirement_index = 1, .first_op = StateRows.op_count, .first_output = StateRows.output_count },
    );
    const requirements = [_]ability.ir.plan.Requirement{
        StateRows.requirement,
        ReaderRows.requirement,
    };
    const ops = StateRows.ops ++ ReaderRows.ops;
    const outputs = StateRows.outputs ++ ReaderRows.outputs;
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 2,
        .first_output = 0,
        .output_count = 1,
        .first_local = 0,
        .local_count = 3,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return mustPlan(ability.ir.builder.finish(.{
        .label = "matrix-plan-native-state-reader",
        .ir_hash = 9002,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &outputs,
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
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
    const Program = ability.program("matrix-plan-native-state-reader", StateReaderHandlers, Body);

    try expectRequirement(Program.contract, 0, "state", .state_cell, .final_state);
    try expectRequirement(Program.contract, 1, "reader", .reader_environment, .none);
    try expectOp(Program.contract, 0, "state", "get", .transform, .{ .codec = .unit }, .{ .codec = .i32 }, false);
    try expectOp(Program.contract, 1, "state", "set", .transform, .{ .codec = .i32 }, .{ .codec = .unit }, false);
    try expectOp(Program.contract, 2, "reader", "ask", .transform, .{ .codec = .unit }, .{ .codec = .i32 }, false);
    try expectRef(Program.contract.result_ref, .{ .codec = .i32 });
    try std.testing.expectEqual(@as(usize, 1), Program.contract.outputs.len);
    try std.testing.expectEqualStrings("final_state", Program.contract.outputs[0].label);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, Program.contract.outputs[0].codec);
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

fn writerPlan() ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const first = ability.ir.builder.local(root, 0);
    const second = ability.ir.builder.local(root, 1);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_i32, .dst = first.index, .operand = 4 },
        mustInstruction(ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 0), first)),
        .{ .kind = .const_i32, .dst = second.index, .operand = 8 },
        mustInstruction(ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 0), second)),
    };
    const WriterRows = ability.ir.schema.LowerBinding(
        ability.ir.schema.Binding("writer", ability.effect.writer.Schema(i32, error{}), void),
        .{ .requirement_index = 0, .first_op = 0, .first_output = 0 },
    );
    const requirements = [_]ability.ir.plan.Requirement{WriterRows.requirement};
    const ops = WriterRows.ops;
    const outputs = WriterRows.outputs;
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 1,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_unit }};

    return mustPlan(ability.ir.builder.finish(.{
        .label = "matrix-plan-native-writer",
        .ir_hash = 9003,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &outputs,
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
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
    const Program = ability.program("matrix-plan-native-writer", WriterHandlers, Body);

    try expectRequirement(Program.contract, 0, "writer", .writer_accumulator, .accumulator);
    try expectOp(Program.contract, 0, "writer", "tell", .transform, .{ .codec = .i32 }, .{ .codec = .unit }, false);
    try expectRef(Program.contract.result_ref, .{ .codec = .unit });
    try std.testing.expectEqual(@as(usize, 1), Program.contract.outputs.len);
    try std.testing.expectEqualStrings("writer", Program.contract.outputs[0].label);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, Program.contract.outputs[0].codec);
    try std.testing.expectEqual(@as(?u16, null), Program.contract.outputs[0].schema_index);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.value_schemas.len);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.value_fields.len);
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

fn scalarExceptionPlan() ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_i32, .dst = payload.index, .operand = 40 },
        mustInstruction(ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 0), payload)),
    };
    return exceptionPlan(
        "matrix-plan-native-exception-scalar",
        9004,
        .i32,
        null,
        &instructions,
        &.{.{ .codec = .i32 }},
        &.{},
        &.{},
        &.{},
    );
}

fn productExceptionPlan() ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        mustInstruction(ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 0), payload)),
    };
    const schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(ProductPayload),
        .codec = .product,
        .first_field = 0,
        .field_count = 1,
    }};
    const fields = [_]ability.ir.ValueFieldPlan{.{ .name = "amount", .codec = .i32 }};
    return exceptionPlan(
        "matrix-plan-native-exception-product",
        9005,
        .product,
        0,
        &instructions,
        &.{.{ .codec = .product, .schema_index = 0 }},
        &schemas,
        &fields,
        &.{},
    );
}

fn sumExceptionPlan() ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        mustInstruction(ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 0), payload)),
    };
    const variants = [_]ability.ir.ValueVariantPlan{
        ability.ir.value.unitVariant("none"),
        ability.ir.value.variant("some", i32),
    };
    const schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(OptionalPayload),
        .codec = .sum,
        .first_variant = 0,
        .variant_count = @intCast(variants.len),
    }};
    return exceptionPlan(
        "matrix-plan-native-exception-sum",
        9006,
        .sum,
        0,
        &instructions,
        &.{.{ .codec = .sum, .schema_index = 0 }},
        &schemas,
        &.{},
        &variants,
    );
}

fn exceptionPlan(
    comptime label: []const u8,
    comptime hash: u64,
    comptime payload_codec: ability.ir.ValueCodec,
    comptime payload_schema_index: ?u16,
    instructions: []const ability.ir.plan.Instruction,
    locals: []const ability.ir.plan.Local,
    schemas: []const ability.ir.ValueSchemaPlan,
    fields: []const ability.ir.ValueFieldPlan,
    variants: []const ability.ir.ValueVariantPlan,
) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "exception",
        .first_op = 0,
        .op_count = 1,
        .lifecycle_tag = .abort_catch,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "throw",
        .mode = .abort,
        .payload_codec = payload_codec,
        .payload_schema_index = payload_schema_index,
        .resume_codec = .unit,
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_unit }};
    return mustPlan(ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = hash,
        .entry = root,
        .functions = &.{.{
            .symbol_name = "run",
            .value_codec = .unit,
            .result_codec = if (payload_codec == .sum) .i32 else payload_codec,
            .result_schema_index = if (payload_codec == .sum) null else payload_schema_index,
            .parameter_count = if (payload_schema_index) |_| 1 else 0,
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
    const ScalarProgram = ability.program("matrix-plan-native-exception-scalar", ScalarExceptionHandlers, ScalarBody);
    const ProductProgram = ability.program("matrix-plan-native-exception-product", ProductExceptionHandlers, ProductBody);
    const SumProgram = ability.program("matrix-plan-native-exception-sum", SumExceptionHandlers, SumBody);

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
    try std.testing.expectEqual(ability.ir.ValueCodec.product, ProductProgram.contract.value_schemas[0].codec);
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
    try std.testing.expectEqual(ability.ir.ValueCodec.sum, SumProgram.contract.value_schemas[0].codec);
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
        pub fn dispatch(_: *const @This()) !ability.effect.choice.Decision(i32, i32) {
            return ability.effect.choice.Decision(i32, i32).returnNow(90);
        }
    },
};

fn resourcePlan(comptime mode: ResourceMode) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const outer = ability.ir.builder.local(root, 0);
    const inner = ability.ir.builder.local(root, 1);
    const value = ability.ir.builder.local(root, 2);
    const instructions = comptime blk: {
        var buffer: [6]ability.ir.plan.Instruction = undefined;
        buffer[0] = mustInstruction(ability.ir.builder.callOp(root, outer, ability.ir.builder.op(root, 0), null));
        buffer[1] = mustInstruction(ability.ir.builder.callOp(root, inner, ability.ir.builder.op(root, 0), null));
        buffer[2] = mustInstruction(ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 1), inner));
        buffer[3] = mustInstruction(ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 1), outer));
        switch (mode) {
            .normal => {
                buffer[4] = .{ .kind = .const_i32, .dst = value.index, .operand = 12 };
                buffer[5] = mustInstruction(ability.ir.builder.returnValue(root, value));
            },
            .exception_escape => {
                buffer[4] = .{ .kind = .const_i32, .dst = value.index, .operand = 80 };
                buffer[5] = mustInstruction(ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 2), value));
            },
            .optional_escape => {
                buffer[4] = mustInstruction(ability.ir.builder.callOp(root, value, ability.ir.builder.op(root, 2), null));
                buffer[5] = mustInstruction(ability.ir.builder.returnValue(root, value));
            },
        }
        break :blk buffer;
    };
    const requirements = switch (mode) {
        .normal => [_]ability.ir.plan.Requirement{.{
            .label = "resource",
            .first_op = 0,
            .op_count = 2,
            .lifecycle_tag = .resource_bracket,
        }},
        .exception_escape => [_]ability.ir.plan.Requirement{
            .{ .label = "resource", .first_op = 0, .op_count = 2, .lifecycle_tag = .resource_bracket },
            .{ .label = "exception", .first_op = 2, .op_count = 1, .lifecycle_tag = .abort_catch },
        },
        .optional_escape => [_]ability.ir.plan.Requirement{
            .{ .label = "resource", .first_op = 0, .op_count = 2, .lifecycle_tag = .resource_bracket },
            .{ .label = "optional", .first_op = 2, .op_count = 1, .lifecycle_tag = .choice_policy },
        },
    };
    const ops = switch (mode) {
        .normal => [_]ability.ir.plan.Op{
            .{ .requirement_index = 0, .op_name = "acquire", .mode = .transform, .payload_codec = .unit, .resume_codec = .product, .resume_schema_index = 0 },
            .{ .requirement_index = 0, .op_name = "release", .mode = .transform, .payload_codec = .product, .payload_schema_index = 0, .resume_codec = .unit },
        },
        .exception_escape => [_]ability.ir.plan.Op{
            .{ .requirement_index = 0, .op_name = "acquire", .mode = .transform, .payload_codec = .unit, .resume_codec = .product, .resume_schema_index = 0 },
            .{ .requirement_index = 0, .op_name = "release", .mode = .transform, .payload_codec = .product, .payload_schema_index = 0, .resume_codec = .unit },
            .{ .requirement_index = 1, .op_name = "throw", .mode = .abort, .payload_codec = .i32, .resume_codec = .unit },
        },
        .optional_escape => [_]ability.ir.plan.Op{
            .{ .requirement_index = 0, .op_name = "acquire", .mode = .transform, .payload_codec = .unit, .resume_codec = .product, .resume_schema_index = 0 },
            .{ .requirement_index = 0, .op_name = "release", .mode = .transform, .payload_codec = .product, .payload_schema_index = 0, .resume_codec = .unit },
            .{ .requirement_index = 1, .op_name = "request", .mode = .choice, .payload_codec = .unit, .resume_codec = .i32 },
        },
    };
    const schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Resource),
        .codec = .product,
        .first_field = 0,
        .field_count = 1,
    }};
    const fields = [_]ability.ir.ValueFieldPlan{.{ .name = "id", .codec = .i32 }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = if (mode == .exception_escape) .return_unit else .return_value }};

    return mustPlan(ability.ir.builder.finish(.{
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
    const NormalProgram = ability.program("matrix-plan-native-resource-normal", ResourceHandlers, NormalBody);
    const ExceptionProgram = ability.program("matrix-plan-native-resource-exception", ResourceHandlers, ExceptionBody);
    const OptionalProgram = ability.program("matrix-plan-native-resource-optional", ResourceHandlers, OptionalBody);

    try expectRequirement(NormalProgram.contract, 0, "resource", .resource_bracket, .none);
    try expectOp(NormalProgram.contract, 0, "resource", "acquire", .transform, .{ .codec = .unit }, .{ .codec = .product, .schema_index = 0 }, false);
    try expectOp(NormalProgram.contract, 1, "resource", "release", .transform, .{ .codec = .product, .schema_index = 0 }, .{ .codec = .unit }, false);
    try expectRef(NormalProgram.contract.result_ref, .{ .codec = .i32 });
    try std.testing.expectEqual(@as(usize, 0), NormalProgram.contract.outputs.len);
    try std.testing.expectEqual(@as(usize, 1), NormalProgram.contract.value_schemas.len);
    try std.testing.expectEqualStrings(@typeName(Resource), NormalProgram.contract.value_schemas[0].label);
    try std.testing.expectEqual(ability.ir.ValueCodec.product, NormalProgram.contract.value_schemas[0].codec);
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
