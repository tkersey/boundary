// zlinter-disable require_doc_comment field_naming field_ordering no_undefined no_unused
const lowered_machine = @import("lowered_machine");
const program_plan = @import("internal_program_plan");
const std = @import("std");

pub const ProgramPlan = program_plan.ProgramPlan;
pub const ValueCodec = program_plan.ValueCodec;
pub const ValueRef = program_plan.ValueRef;
pub const ValueSchemaRegistryForTypes = program_plan.ValueSchemaRegistryForTypes;
pub const NestedWithTarget = struct {
    metadata: []const u8,
    function_index: u16,
};
pub const max_capability_blockers = 64;
pub const CapabilityBlockerTag = enum {
    helper_cycle,
    nested_with_unresolved,
    nested_with_target_has_parameters,
    nested_with_result_codec,
    result_codec,
    parameter_codec,
    payload_codec,
    resume_codec,
    local_codec,
};
pub const CapabilityBlocker = struct {
    tag: CapabilityBlockerTag,
    function_index: u16 = std.math.maxInt(u16),
    instruction_index: u32 = std.math.maxInt(u32),
    codec: ValueCodec = .unit,
};
pub const ExecutablePlanSupportError = error{
    UnsupportedHelperCycle,
    UnsupportedNestedWith,
    UnsupportedResultCodec,
    UnsupportedParameterCodec,
    UnsupportedPayloadCodec,
    UnsupportedResumeCodec,
    UnsupportedLocalCodec,
};

fn appendCapabilityBlocker(
    comptime blockers: *[max_capability_blockers]CapabilityBlocker,
    comptime count: *usize,
    comptime truncated: *bool,
    comptime blocker: CapabilityBlocker,
) void {
    if (count.* == max_capability_blockers) {
        truncated.* = true;
        return;
    }
    blockers[count.*] = blocker;
    count.* += 1;
}

pub fn ExecutableCapabilityLedgerForPlan(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
) type {
    const data = comptime blk: {
        var blockers: [max_capability_blockers]CapabilityBlocker = undefined;
        var count: usize = 0;
        var truncated = false;
        const analysis = program_plan.entryExecutionAnalysisWithNestedTargets(compiled_plan, nested_with_targets) catch {
            appendCapabilityBlocker(&blockers, &count, &truncated, .{ .tag = .local_codec });
            const items = blockers[0..count].*;
            break :blk .{ .items = items, .truncated = truncated };
        };
        for (compiled_plan.functions, 0..) |function, function_index| {
            if (!analysis.reachable_functions[function_index]) continue;
            for (0..function.parameter_count) |parameter_index| {
                const local = compiled_plan.locals[function.first_local + parameter_index];
                if (!executableTypedRef(schema_types, .{ .codec = local.codec, .schema_index = local.schema_index })) {
                    appendCapabilityBlocker(&blockers, &count, &truncated, .{
                        .tag = .parameter_codec,
                        .function_index = @intCast(function_index),
                        .codec = local.codec,
                    });
                }
            }
            if (!executableTypedRef(schema_types, program_plan.functionResultRef(function))) {
                appendCapabilityBlocker(&blockers, &count, &truncated, .{
                    .tag = .result_codec,
                    .function_index = @intCast(function_index),
                    .codec = program_plan.functionResultCodec(function),
                });
            }
        }
        for (compiled_plan.instructions, 0..) |instruction, instruction_index| {
            if (!analysis.reachable_instructions[instruction_index]) continue;
            const owner_index = instructionOwnerFunctionIndex(compiled_plan, instruction_index) orelse std.math.maxInt(usize);
            const owner: ?program_plan.FunctionPlan = if (owner_index == std.math.maxInt(usize)) null else compiled_plan.functions[owner_index];
            switch (instruction.kind) {
                .call_nested_with => {
                    const target_index = nestedWithTargetIndexForMetadata(compiled_plan, nested_with_targets, instruction.string_literal) orelse {
                        appendCapabilityBlocker(&blockers, &count, &truncated, .{
                            .tag = .nested_with_unresolved,
                            .function_index = @intCast(owner_index),
                            .instruction_index = @intCast(instruction_index),
                        });
                        continue;
                    };
                    const target = compiled_plan.functions[target_index];
                    if (target.parameter_count != 0) {
                        appendCapabilityBlocker(&blockers, &count, &truncated, .{
                            .tag = .nested_with_target_has_parameters,
                            .function_index = @intCast(owner_index),
                            .instruction_index = @intCast(instruction_index),
                        });
                    }
                    const result_codec = program_plan.valueCodecFromInstructionAux(instruction.aux) catch .unit;
                    const completion_ref = effectiveCompletionRefForFunction(analysis, target, target_index);
                    if (!executableScalarCodec(result_codec) or
                        completion_ref.codec != result_codec or
                        completion_ref.schema_index != null)
                    {
                        appendCapabilityBlocker(&blockers, &count, &truncated, .{
                            .tag = .nested_with_result_codec,
                            .function_index = @intCast(owner_index),
                            .instruction_index = @intCast(instruction_index),
                            .codec = result_codec,
                        });
                    } else if (owner) |owner_function| {
                        if (result_codec != .unit and !instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner_function, instruction.dst)) {
                            appendCapabilityBlocker(&blockers, &count, &truncated, .{
                                .tag = .local_codec,
                                .function_index = @intCast(owner_index),
                                .instruction_index = @intCast(instruction_index),
                                .codec = result_codec,
                            });
                        }
                        if (analysis.terminal_functions[target_index] and
                            !program_plan.functionResultRef(target).eql(program_plan.functionResultRef(owner_function)))
                        {
                            appendCapabilityBlocker(&blockers, &count, &truncated, .{
                                .tag = .nested_with_result_codec,
                                .function_index = @intCast(owner_index),
                                .instruction_index = @intCast(instruction_index),
                                .codec = program_plan.functionResultCodec(target),
                            });
                        }
                    }
                },
                .call_op => {
                    const op = compiled_plan.ops[instruction.operand];
                    if (!executableTypedRef(schema_types, .{ .codec = op.payload_codec, .schema_index = op.payload_schema_index })) {
                        appendCapabilityBlocker(&blockers, &count, &truncated, .{ .tag = .payload_codec, .function_index = @intCast(owner_index), .instruction_index = @intCast(instruction_index), .codec = op.payload_codec });
                    }
                    if (!executableTypedRef(schema_types, .{ .codec = op.resume_codec, .schema_index = op.resume_schema_index })) {
                        appendCapabilityBlocker(&blockers, &count, &truncated, .{ .tag = .resume_codec, .function_index = @intCast(owner_index), .instruction_index = @intCast(instruction_index), .codec = op.resume_codec });
                    }
                },
                else => {},
            }
        }
        const items = blockers[0..count].*;
        break :blk .{ .items = items, .truncated = truncated };
    };
    return struct {
        pub const blockers = &data.items;
        pub const truncated = data.truncated;
    };
}

pub fn executableCapabilitySummary(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
) []const u8 {
    const ledger = ExecutableCapabilityLedgerForPlan(compiled_plan, schema_types, nested_with_targets);
    if (ledger.blockers.len == 0) return "capability ledger: blockers=0 truncated=false";
    const first = ledger.blockers[0];
    return std.fmt.comptimePrint(
        "capability ledger: blockers={d} truncated={} cap={d} first_tag={s} first_function={d} first_instruction={d}",
        .{
            ledger.blockers.len,
            ledger.truncated,
            max_capability_blockers,
            @tagName(first.tag),
            first.function_index,
            first.instruction_index,
        },
    );
}

pub fn executableResultCodecForType(comptime T: type) program_plan.CodecError!program_plan.ValueCodec {
    return program_plan.codecForType(T);
}

pub fn executableResultCodecForPlan(comptime compiled_plan: program_plan.ProgramPlan) program_plan.ValueCodec {
    return program_plan.functionResultCodec(compiled_plan.functions[compiled_plan.entry_index]);
}

pub fn executableResultRefForPlan(comptime compiled_plan: program_plan.ProgramPlan) program_plan.ValueRef {
    return program_plan.functionResultRef(compiled_plan.functions[compiled_plan.entry_index]);
}

pub fn validateExecutablePlanSupport(comptime compiled_plan: program_plan.ProgramPlan) ExecutablePlanSupportError!void {
    comptime {
        const analysis = program_plan.entryExecutionAnalysis(compiled_plan) catch return error.UnsupportedLocalCodec;
        if (analysis.helper_cycle) return error.UnsupportedHelperCycle;

        for (compiled_plan.functions, 0..) |function, function_index| {
            if (!analysis.reachable_functions[function_index]) continue;
            for (0..function.parameter_count) |parameter_index| {
                const local = compiled_plan.locals[function.first_local + parameter_index];
                if (!executableScalarCodec(local.codec)) return error.UnsupportedParameterCodec;
            }
            if ((analysis.terminal_functions[function_index] or analysis.after_result_functions[function_index]) and
                !executableScalarCodec(program_plan.functionResultCodec(function)))
            {
                return error.UnsupportedResultCodec;
            }
        }

        const entry = compiled_plan.functions[compiled_plan.entry_index];
        if (!executableScalarCodec(program_plan.functionResultCodec(entry))) return error.UnsupportedResultCodec;

        for (compiled_plan.instructions, 0..) |instruction, instruction_index| {
            if (!analysis.reachable_instructions[instruction_index]) continue;
            switch (instruction.kind) {
                .call_nested_with => return error.UnsupportedNestedWith,
                .call_op => {
                    const op = compiled_plan.ops[instruction.operand];
                    if (!executableScalarCodec(op.payload_codec)) return error.UnsupportedPayloadCodec;
                    if (!executableScalarCodec(op.resume_codec)) return error.UnsupportedResumeCodec;
                    if (op.payload_codec != .unit and !instructionLocalHasExecutableScalarCodec(
                        compiled_plan,
                        instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec,
                        instruction.aux,
                    )) return error.UnsupportedLocalCodec;
                    if (op.resume_codec != .unit and instruction.dst != std.math.maxInt(u16) and !instructionLocalHasExecutableScalarCodec(
                        compiled_plan,
                        instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec,
                        instruction.dst,
                    )) return error.UnsupportedLocalCodec;
                },
                .call_helper => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    const callee = compiled_plan.functions[instruction.operand];
                    if (callee.parameter_count != 0) {
                        for (0..callee.parameter_count) |arg_index| {
                            const local_id = planCallArgAt(compiled_plan, instruction.aux + arg_index);
                            if (!instructionLocalHasExecutableScalarCodec(compiled_plan, owner, local_id)) return error.UnsupportedLocalCodec;
                        }
                    }
                    if (program_plan.functionResultCodec(callee) != .unit and instruction.dst != std.math.maxInt(u16) and
                        !instructionLocalHasExecutableScalarCodec(compiled_plan, owner, instruction.dst))
                    {
                        return error.UnsupportedLocalCodec;
                    }
                },
                .add_const_i32, .const_i32, .const_string, .const_usize => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    if (!instructionLocalHasExecutableScalarCodec(compiled_plan, owner, instruction.dst)) return error.UnsupportedLocalCodec;
                    if (instruction.kind == .add_const_i32 and !instructionLocalHasExecutableScalarCodec(compiled_plan, owner, instruction.operand)) {
                        return error.UnsupportedLocalCodec;
                    }
                },
                .add_i32 => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    if (!instructionLocalHasExecutableScalarCodec(compiled_plan, owner, instruction.dst) or
                        !instructionLocalHasExecutableScalarCodec(compiled_plan, owner, instruction.operand) or
                        !instructionLocalHasExecutableScalarCodec(compiled_plan, owner, instruction.aux))
                    {
                        return error.UnsupportedLocalCodec;
                    }
                },
                .compare_eq_zero, .sub_one => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    if (!instructionLocalHasExecutableScalarCodec(compiled_plan, owner, instruction.dst) or
                        !instructionLocalHasExecutableScalarCodec(compiled_plan, owner, instruction.operand))
                    {
                        return error.UnsupportedLocalCodec;
                    }
                },
                .return_value => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    if (!instructionLocalHasExecutableScalarCodec(compiled_plan, owner, instruction.operand)) return error.UnsupportedLocalCodec;
                },
                .return_error => {},
            }
        }
    }
}

pub fn validateTypedExecutablePlanSupport(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
) ExecutablePlanSupportError!void {
    return validateTypedExecutablePlanSupportWithNestedTargets(compiled_plan, schema_types, &.{});
}

pub fn validateTypedExecutablePlanSupportWithNestedTargets(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
) ExecutablePlanSupportError!void {
    comptime {
        const analysis = program_plan.entryExecutionAnalysisWithNestedTargets(compiled_plan, nested_with_targets) catch return error.UnsupportedLocalCodec;

        for (compiled_plan.functions, 0..) |function, function_index| {
            if (!analysis.reachable_functions[function_index]) continue;
            for (0..function.parameter_count) |parameter_index| {
                const local = compiled_plan.locals[function.first_local + parameter_index];
                if (!executableTypedRef(schema_types, .{ .codec = local.codec, .schema_index = local.schema_index })) return error.UnsupportedParameterCodec;
            }
            if ((analysis.terminal_functions[function_index] or analysis.after_result_functions[function_index]) and
                !executableTypedRef(schema_types, program_plan.functionResultRef(function)))
            {
                return error.UnsupportedResultCodec;
            }
        }

        const entry = compiled_plan.functions[compiled_plan.entry_index];
        if (!executableTypedRef(schema_types, program_plan.functionResultRef(entry))) return error.UnsupportedResultCodec;

        for (compiled_plan.instructions, 0..) |instruction, instruction_index| {
            if (!analysis.reachable_instructions[instruction_index]) continue;
            switch (instruction.kind) {
                .call_nested_with => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    const target_index = nestedWithTargetIndexForMetadata(compiled_plan, nested_with_targets, instruction.string_literal) orelse return error.UnsupportedNestedWith;
                    const target = compiled_plan.functions[target_index];
                    if (target.parameter_count != 0) return error.UnsupportedNestedWith;
                    const result_codec = program_plan.valueCodecFromInstructionAux(instruction.aux) catch return error.UnsupportedResultCodec;
                    if (!executableScalarCodec(result_codec)) return error.UnsupportedResultCodec;
                    const completion_ref = effectiveCompletionRefForFunction(analysis, target, target_index);
                    if (completion_ref.codec != result_codec or completion_ref.schema_index != null) return error.UnsupportedResultCodec;
                    if (result_codec != .unit and !instructionLocalHasExecutableTypedRef(
                        compiled_plan,
                        schema_types,
                        owner,
                        instruction.dst,
                    )) return error.UnsupportedLocalCodec;
                    if (analysis.terminal_functions[target_index] and
                        !program_plan.functionResultRef(target).eql(program_plan.functionResultRef(owner)))
                    {
                        return error.UnsupportedResultCodec;
                    }
                },
                .call_op => {
                    const op = compiled_plan.ops[instruction.operand];
                    if (!executableTypedRef(schema_types, .{ .codec = op.payload_codec, .schema_index = op.payload_schema_index })) return error.UnsupportedPayloadCodec;
                    if (!executableTypedRef(schema_types, .{ .codec = op.resume_codec, .schema_index = op.resume_schema_index })) return error.UnsupportedResumeCodec;
                    if (op.payload_codec != .unit and !instructionLocalHasExecutableTypedRef(
                        compiled_plan,
                        schema_types,
                        instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec,
                        instruction.aux,
                    )) return error.UnsupportedLocalCodec;
                    if (op.resume_codec != .unit and instruction.dst != std.math.maxInt(u16) and !instructionLocalHasExecutableTypedRef(
                        compiled_plan,
                        schema_types,
                        instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec,
                        instruction.dst,
                    )) return error.UnsupportedLocalCodec;
                },
                .call_helper => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    const callee = compiled_plan.functions[instruction.operand];
                    if (callee.parameter_count != 0) {
                        for (0..callee.parameter_count) |arg_index| {
                            const local_id = planCallArgAt(compiled_plan, instruction.aux + arg_index);
                            if (!instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, local_id)) return error.UnsupportedLocalCodec;
                        }
                    }
                    if (program_plan.functionResultCodec(callee) != .unit and instruction.dst != std.math.maxInt(u16) and
                        !instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.dst))
                    {
                        return error.UnsupportedLocalCodec;
                    }
                },
                .add_const_i32, .const_i32, .const_string, .const_usize => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    if (!instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.dst)) return error.UnsupportedLocalCodec;
                    if (instruction.kind == .add_const_i32 and !instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.operand)) {
                        return error.UnsupportedLocalCodec;
                    }
                },
                .add_i32 => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    if (!instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.dst) or
                        !instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.operand) or
                        !instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.aux))
                    {
                        return error.UnsupportedLocalCodec;
                    }
                },
                .compare_eq_zero, .sub_one => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    if (!instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.dst) or
                        !instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.operand))
                    {
                        return error.UnsupportedLocalCodec;
                    }
                },
                .return_value => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    if (!instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.operand)) return error.UnsupportedLocalCodec;
                },
                .return_error => {},
            }
        }
    }
}

fn executableScalarCodec(comptime codec: program_plan.ValueCodec) bool {
    return switch (codec) {
        .unit, .bool, .i32, .usize, .string => true,
        .product, .sum, .string_list => false,
    };
}

fn executableTypedRef(comptime schema_types: anytype, comptime ref: program_plan.ValueRef) bool {
    return switch (ref.codec) {
        .unit, .bool, .i32, .usize, .string, .string_list => ref.schema_index == null,
        .product, .sum => if (ref.schema_index) |index| index < schema_types.len else false,
    };
}

fn instructionOwnerFunction(comptime compiled_plan: program_plan.ProgramPlan, comptime instruction_index: usize) ?program_plan.FunctionPlan {
    inline for (compiled_plan.functions) |function| {
        const instruction_end = @as(usize, function.first_instruction) + function.instruction_count;
        if (instruction_index >= function.first_instruction and instruction_index < instruction_end) return function;
    }
    return null;
}

fn instructionOwnerFunctionIndex(comptime compiled_plan: program_plan.ProgramPlan, comptime instruction_index: usize) ?usize {
    inline for (compiled_plan.functions, 0..) |function, function_index| {
        const instruction_end = @as(usize, function.first_instruction) + function.instruction_count;
        if (instruction_index >= function.first_instruction and instruction_index < instruction_end) return function_index;
    }
    return null;
}

fn instructionLocalHasExecutableScalarCodec(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime function: program_plan.FunctionPlan,
    comptime local_id: u16,
) bool {
    const local_codec = functionLocalCodec(compiled_plan, function, local_id) orelse return false;
    return executableScalarCodec(local_codec);
}

fn instructionLocalHasExecutableTypedRef(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime function: program_plan.FunctionPlan,
    comptime local_id: u16,
) bool {
    const local_ref = functionLocalRef(compiled_plan, function, local_id) orelse return false;
    return executableTypedRef(schema_types, local_ref);
}

fn functionValueRef(comptime function: program_plan.FunctionPlan) program_plan.ValueRef {
    return .{ .codec = function.value_codec, .schema_index = function.value_schema_index };
}

fn effectiveCompletionRefForFunction(
    comptime analysis: anytype,
    comptime function: program_plan.FunctionPlan,
    comptime function_index: usize,
) program_plan.ValueRef {
    if (analysis.after_result_functions[function_index]) return program_plan.functionResultRef(function);
    return functionValueRef(function);
}

pub fn authoredBoundProgramPlan(
    comptime label: []const u8,
    comptime Payload: type,
    comptime Resume: type,
    comptime Answer: type,
    comptime mode: program_plan.ControlMode,
) ?program_plan.ProgramPlan {
    return program_plan.authoredBoundPlan(label, Payload, Resume, Answer, mode);
}

const max_interpreter_steps = 10_000;

const SchemaValue = struct {
    schema_index: u16,
    ptr: *const anyopaque,
};

const ExecutableValue = union(enum) {
    none,
    bool: bool,
    i32: i32,
    usize: usize,
    string: []const u8,
    string_list: []const []const u8,
    schema: SchemaValue,
};

fn ValueTypeForCodec(comptime codec: program_plan.ValueCodec) type {
    return switch (codec) {
        .unit => void,
        .bool => bool,
        .i32 => i32,
        .product => @compileError("product ValueCodec requires a schema-specific typed decoder"),
        .usize => usize,
        .string => []const u8,
        .string_list => []const []const u8,
        .sum => @compileError("sum ValueCodec requires a schema-specific typed decoder"),
    };
}

fn ValueTypeForRef(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime ref: program_plan.ValueRef,
) type {
    _ = compiled_plan;
    return switch (ref.codec) {
        .unit => void,
        .bool => bool,
        .i32 => i32,
        .usize => usize,
        .string => []const u8,
        .string_list => []const []const u8,
        .product, .sum => schema_types[ref.schema_index orelse @compileError("structured ValueRef is missing a schema index")],
    };
}

fn encodeScalarValue(value: anytype) ExecutableValue {
    return switch (@TypeOf(value)) {
        void => .none,
        bool => .{ .bool = value },
        i32 => .{ .i32 = value },
        usize => .{ .usize = value },
        []const u8 => .{ .string = value },
        []const []const u8 => .{ .string_list = value },
        else => @compileError("unsupported authored scalar result type"),
    };
}

fn RunResultTypeForPlan(comptime compiled_plan: program_plan.ProgramPlan) type {
    return struct {
        value: ValueTypeForCodec(program_plan.functionResultCodec(compiled_plan.functions[compiled_plan.entry_index])),
    };
}

fn TypedRunResultTypeForPlan(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
) type {
    return struct {
        value: ValueTypeForRef(compiled_plan, schema_types, program_plan.functionResultRef(compiled_plan.functions[compiled_plan.entry_index])),
    };
}

fn executableValueRef(codec: program_plan.ValueCodec, value: ExecutableValue) ?program_plan.ValueRef {
    return switch (codec) {
        .unit => switch (value) {
            .none => .{ .codec = .unit },
            else => null,
        },
        .bool => switch (value) {
            .bool => .{ .codec = .bool },
            else => null,
        },
        .i32 => switch (value) {
            .i32 => .{ .codec = .i32 },
            else => null,
        },
        .usize => switch (value) {
            .usize => .{ .codec = .usize },
            else => null,
        },
        .string => switch (value) {
            .string => .{ .codec = .string },
            else => null,
        },
        .string_list => switch (value) {
            .string_list => .{ .codec = .string_list },
            else => null,
        },
        .product, .sum => switch (value) {
            .schema => |schema| .{ .codec = codec, .schema_index = schema.schema_index },
            else => null,
        },
    };
}

fn decodeArg(
    comptime codec: program_plan.ValueCodec,
    value: ExecutableValue,
) error{ProgramContractViolation}!ValueTypeForCodec(codec) {
    return switch (codec) {
        .unit => switch (value) {
            .none => {},
            else => error.ProgramContractViolation,
        },
        .bool => switch (value) {
            .bool => |typed| typed,
            else => error.ProgramContractViolation,
        },
        .i32 => switch (value) {
            .i32 => |typed| typed,
            else => error.ProgramContractViolation,
        },
        .usize => switch (value) {
            .usize => |typed| typed,
            else => error.ProgramContractViolation,
        },
        .string => switch (value) {
            .string => |typed| typed,
            else => error.ProgramContractViolation,
        },
        .string_list => switch (value) {
            .string_list => |typed| typed,
            else => error.ProgramContractViolation,
        },
        .product, .sum => error.ProgramContractViolation,
    };
}

fn decodeTypedValue(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime ref: program_plan.ValueRef,
    value: ExecutableValue,
) error{ProgramContractViolation}!ValueTypeForRef(compiled_plan, schema_types, ref) {
    return switch (comptime ref.codec) {
        .unit => try decodeArg(.unit, value),
        .bool => try decodeArg(.bool, value),
        .i32 => try decodeArg(.i32, value),
        .usize => try decodeArg(.usize, value),
        .string => try decodeArg(.string, value),
        .string_list => try decodeArg(.string_list, value),
        .product, .sum => switch (value) {
            .schema => |schema| blk: {
                const expected_index = ref.schema_index orelse return error.ProgramContractViolation;
                if (schema.schema_index != expected_index) return error.ProgramContractViolation;
                const T = ValueTypeForRef(compiled_plan, schema_types, ref);
                const typed: *const T = @ptrCast(@alignCast(schema.ptr));
                break :blk typed.*;
            },
            else => error.ProgramContractViolation,
        },
    };
}

fn encodeTypedValue(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime ref: program_plan.ValueRef,
    value: ValueTypeForRef(compiled_plan, schema_types, ref),
) ExecutableValue {
    return switch (comptime ref.codec) {
        .unit, .bool, .i32, .usize, .string, .string_list => encodeScalarValue(value),
        .product, .sum => .{
            .schema = .{
                .schema_index = ref.schema_index orelse @compileError("structured ValueRef is missing a schema index"),
                .ptr = &value,
            },
        },
    };
}

fn schemaIndexForType(comptime schema_types: anytype, comptime T: type) ?u16 {
    inline for (schema_types, 0..) |SchemaType, index| {
        if (SchemaType == T) return @intCast(index);
    }
    return null;
}

fn valueRefForType(comptime schema_types: anytype, comptime T: type) program_plan.ValueRef {
    if (T == void) return .{ .codec = .unit };
    if (T == bool) return .{ .codec = .bool };
    if (T == i32) return .{ .codec = .i32 };
    if (T == usize) return .{ .codec = .usize };
    if (T == []const u8) return .{ .codec = .string };
    if (T == []const []const u8) return .{ .codec = .string_list };
    const schema_index = schemaIndexForType(schema_types, T) orelse
        @compileError("authored structured value type is not present in Body.value_schema_types: " ++ @typeName(T));
    return switch (@typeInfo(T)) {
        .@"struct" => .{ .codec = .product, .schema_index = schema_index },
        .@"enum", .@"union", .optional => .{ .codec = .sum, .schema_index = schema_index },
        else => @compileError("unsupported authored value type: " ++ @typeName(T)),
    };
}

fn encodeRuntimeValue(
    comptime schema_types: anytype,
    scratch: anytype,
    value: anytype,
) anyerror!ExecutableValue {
    const ref = comptime valueRefForType(schema_types, @TypeOf(value));
    return switch (comptime ref.codec) {
        .unit, .bool, .i32, .usize, .string, .string_list => encodeScalarValue(value),
        .product, .sum => try scratch.storeSchemaValue(
            @TypeOf(value),
            ref.schema_index orelse @compileError("structured ValueRef is missing a schema index"),
            value,
        ),
    };
}

const RuntimeValueWithRef = struct {
    value: ExecutableValue,
    ref: program_plan.ValueRef,
};

fn encodeRuntimeValueWithInferredRef(
    comptime schema_types: anytype,
    scratch: anytype,
    value: anytype,
) anyerror!RuntimeValueWithRef {
    const Value = @TypeOf(value);
    return switch (Value) {
        void => .{ .value = .none, .ref = .{ .codec = .unit } },
        bool => .{ .value = .{ .bool = value }, .ref = .{ .codec = .bool } },
        i32 => .{ .value = .{ .i32 = value }, .ref = .{ .codec = .i32 } },
        usize => .{ .value = .{ .usize = value }, .ref = .{ .codec = .usize } },
        []const u8 => .{ .value = .{ .string = value }, .ref = .{ .codec = .string } },
        []const []const u8 => .{ .value = .{ .string_list = value }, .ref = .{ .codec = .string_list } },
        else => blk: {
            const schema_index = comptime schemaIndexForType(schema_types, Value) orelse std.math.maxInt(u16);
            if (comptime schema_index == std.math.maxInt(u16)) return error.ProgramContractViolation;
            const ref: program_plan.ValueRef = comptime switch (@typeInfo(Value)) {
                .@"struct" => .{ .codec = .product, .schema_index = schema_index },
                .@"enum", .@"union", .optional => .{ .codec = .sum, .schema_index = schema_index },
                else => return error.ProgramContractViolation,
            };
            break :blk .{
                .value = try scratch.storeSchemaValue(Value, schema_index, value),
                .ref = ref,
            };
        },
    };
}

fn encodeRuntimeValueForRef(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime ref: program_plan.ValueRef,
    scratch: anytype,
    value: anytype,
) anyerror!ExecutableValue {
    const Expected = ValueTypeForRef(compiled_plan, schema_types, ref);
    if (comptime @TypeOf(value) != Expected) return error.ProgramContractViolation;
    return switch (comptime ref.codec) {
        .unit, .bool, .i32, .usize, .string, .string_list => encodeScalarValue(value),
        .product, .sum => try scratch.storeSchemaValue(
            Expected,
            ref.schema_index orelse @compileError("structured ValueRef is missing a schema index"),
            value,
        ),
    };
}

fn encodeBorrowedTypedValue(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime ref: program_plan.ValueRef,
    value: *const ValueTypeForRef(compiled_plan, schema_types, ref),
) ExecutableValue {
    return switch (comptime ref.codec) {
        .unit, .bool, .i32, .usize, .string, .string_list => encodeScalarValue(value.*),
        .product, .sum => .{ .schema = .{
            .schema_index = ref.schema_index orelse @compileError("structured ValueRef is missing a schema index"),
            .ptr = value,
        } },
    };
}

fn valueMatchesRef(ref: program_plan.ValueRef, value: ExecutableValue) bool {
    const actual = executableValueRef(ref.codec, value) orelse return false;
    return actual.eql(ref);
}

fn valueMatchesCodec(codec: program_plan.ValueCodec, value: ExecutableValue) bool {
    return executableValueRef(codec, value) != null;
}

fn codecForScalarValue(value: ExecutableValue) program_plan.ValueCodec {
    return switch (value) {
        .none => .unit,
        .bool => .bool,
        .i32 => .i32,
        .usize => .usize,
        .string => .string,
        .string_list => .string_list,
        .schema => unreachable,
    };
}

fn executableValueFromPublic(value: lowered_machine.ProgramValue) ExecutableValue {
    return switch (value) {
        .none => .none,
        .bool => |typed| .{ .bool = typed },
        .i32 => |typed| .{ .i32 = typed },
        .usize => |typed| .{ .usize = typed },
        .string => |typed| .{ .string = typed },
    };
}

fn functionLocalCodec(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime function: program_plan.FunctionPlan,
    local_id: u16,
) ?program_plan.ValueCodec {
    if (compiled_plan.locals.len == 0) return null;
    const index = @as(usize, function.first_local) + local_id;
    if (index >= compiled_plan.locals.len) return null;
    return compiled_plan.locals[index].codec;
}

fn functionLocalRef(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime function: program_plan.FunctionPlan,
    local_id: u16,
) ?program_plan.ValueRef {
    if (compiled_plan.locals.len == 0) return null;
    const index = @as(usize, function.first_local) + local_id;
    if (index >= compiled_plan.locals.len) return null;
    const local = compiled_plan.locals[index];
    return .{ .codec = local.codec, .schema_index = local.schema_index };
}

const OperationDispatch = struct {
    value: ExecutableValue,
    resumes: bool,
};

const ExecutionResult = struct {
    value: ExecutableValue,
    terminal: bool,
};

const AfterApplication = struct {
    value: ExecutableValue,
    ref: program_plan.ValueRef,
};

const AfterOutputRefMode = enum {
    inferred,
    exact,
};

const CompletionKind = enum {
    normal,
    terminal,
};

const CompletionValue = struct {
    value: ExecutableValue,
    initial_ref: program_plan.ValueRef,
    after_stack: []const u16,
    kind: CompletionKind,
};

const InterpreterFrame = struct {
    locals_start: usize,
    locals_len: usize,
    call_args_start: usize,
    after_start: usize,
};

const OwnedSchemaValue = struct {
    ptr: *anyopaque,
    destroy: *const fn (std.mem.Allocator, *anyopaque) void,
};

fn SchemaDestroyer(comptime T: type) type {
    return struct {
        fn destroy(allocator: std.mem.Allocator, ptr: *anyopaque) void {
            const typed: *T = @ptrCast(@alignCast(ptr));
            allocator.destroy(typed);
        }
    };
}

fn InterpreterScratch(comptime after_stack_capacity: usize) type {
    return struct {
        allocator: std.mem.Allocator,
        locals: std.ArrayList(ExecutableValue) = .empty,
        call_args: std.ArrayList(ExecutableValue) = .empty,
        owned_schema_values: std.ArrayList(OwnedSchemaValue) = .empty,
        after_stack: [after_stack_capacity]u16 = [_]u16{0} ** after_stack_capacity,
        after_stack_len: usize = 0,

        fn init(
            allocator: std.mem.Allocator,
            max_active_local_slots: usize,
            max_active_call_arg_slots: usize,
        ) std.mem.Allocator.Error!@This() {
            var scratch: @This() = .{ .allocator = allocator };
            errdefer scratch.deinit();
            try scratch.locals.ensureTotalCapacity(allocator, max_active_local_slots);
            try scratch.call_args.ensureTotalCapacity(allocator, max_active_call_arg_slots);
            return scratch;
        }

        fn deinit(self: *@This()) void {
            for (self.owned_schema_values.items) |owned| owned.destroy(self.allocator, owned.ptr);
            self.owned_schema_values.deinit(self.allocator);
            self.call_args.deinit(self.allocator);
            self.locals.deinit(self.allocator);
        }

        fn storeSchemaValue(self: *@This(), comptime T: type, schema_index: u16, value: T) std.mem.Allocator.Error!ExecutableValue {
            const typed = try self.allocator.create(T);
            errdefer self.allocator.destroy(typed);
            typed.* = value;
            try self.owned_schema_values.append(self.allocator, .{
                .ptr = typed,
                .destroy = SchemaDestroyer(T).destroy,
            });
            return .{ .schema = .{
                .schema_index = schema_index,
                .ptr = typed,
            } };
        }

        fn pushFrame(self: *@This(), local_count: usize) std.mem.Allocator.Error!InterpreterFrame {
            const frame: InterpreterFrame = .{
                .locals_start = self.locals.items.len,
                .locals_len = local_count,
                .call_args_start = self.call_args.items.len,
                .after_start = self.after_stack_len,
            };
            try self.locals.resize(self.allocator, frame.locals_start + local_count);
            @memset(self.locals.items[frame.locals_start..][0..local_count], .none);
            return frame;
        }

        fn popFrame(self: *@This(), frame: InterpreterFrame) void {
            self.after_stack_len = frame.after_start;
            self.call_args.shrinkRetainingCapacity(frame.call_args_start);
            self.locals.shrinkRetainingCapacity(frame.locals_start);
        }

        fn frameLocals(self: *@This(), frame: InterpreterFrame) []ExecutableValue {
            return self.locals.items[frame.locals_start..][0..frame.locals_len];
        }

        fn pushCallArgs(self: *@This(), count: usize) std.mem.Allocator.Error![]ExecutableValue {
            const start = self.call_args.items.len;
            try self.call_args.resize(self.allocator, start + count);
            return self.call_args.items[start..][0..count];
        }

        fn popCallArgs(self: *@This(), args: []const ExecutableValue) void {
            self.call_args.shrinkRetainingCapacity(self.call_args.items.len - args.len);
        }

        fn pushAfter(self: *@This(), op_index: u16) error{ExecutionBudgetExceeded}!void {
            if (self.after_stack_len >= self.after_stack.len) return error.ExecutionBudgetExceeded;
            self.after_stack[self.after_stack_len] = op_index;
            self.after_stack_len += 1;
        }

        fn frameAfterStack(self: *@This(), frame: InterpreterFrame) []const u16 {
            return self.after_stack[frame.after_start..self.after_stack_len];
        }
    };
}

fn consumeInterpreterStep(remaining_steps: *usize) error{ExecutionBudgetExceeded}!void {
    if (remaining_steps.* == 0) return error.ExecutionBudgetExceeded;
    remaining_steps.* -= 1;
}

fn mappedReturnError(comptime ErrorSet: type, comptime literal: []const u8) anyerror {
    return switch (@typeInfo(ErrorSet)) {
        .error_set => |errors| blk: {
            if (errors) |decls| {
                inline for (decls) |decl| {
                    if (std.mem.eql(u8, decl.name, literal)) break :blk @field(ErrorSet, decl.name);
                }
            } else {
                break :blk @field(ErrorSet, literal);
            }
            break :blk error.ProgramContractViolation;
        },
        else => @compileError("ProgramPlan return_error mapping requires an error set"),
    };
}

fn mappedReturnErrorForInstruction(
    comptime ErrorSet: type,
    comptime compiled_plan: program_plan.ProgramPlan,
    instruction_index: usize,
) anyerror {
    inline for (compiled_plan.instructions, 0..) |instruction, index| {
        if (instruction_index == index and instruction.kind == .return_error) {
            return mappedReturnError(ErrorSet, instruction.string_literal);
        }
    }
    return error.ProgramContractViolation;
}

fn HandlerSetType(comptime HandlersPtr: type) type {
    return switch (@typeInfo(HandlersPtr)) {
        .pointer => |pointer| pointer.child,
        else => HandlersPtr,
    };
}

fn HandlerFieldPtrType(comptime HandlersPtr: type, comptime field_name: []const u8) type {
    const Field = @FieldType(HandlerSetType(HandlersPtr), field_name);
    return switch (@typeInfo(Field)) {
        .pointer => Field,
        else => switch (@typeInfo(HandlersPtr)) {
            .pointer => |pointer| if (pointer.is_const) *const Field else *Field,
            else => *Field,
        },
    };
}

fn handlerFieldPtr(handlers: anytype, comptime field_name: []const u8) HandlerFieldPtrType(@TypeOf(handlers), field_name) {
    const Field = @FieldType(HandlerSetType(@TypeOf(handlers)), field_name);
    return switch (@typeInfo(Field)) {
        .pointer => switch (@typeInfo(@TypeOf(handlers))) {
            .pointer => @field(handlers.*, field_name),
            else => @field(handlers, field_name),
        },
        else => switch (@typeInfo(@TypeOf(handlers))) {
            .pointer => &@field(handlers.*, field_name),
            else => &@field(handlers, field_name),
        },
    };
}

fn opNameIsUnique(comptime compiled_plan: program_plan.ProgramPlan, comptime op_name: []const u8) bool {
    comptime var count: usize = 0;
    inline for (compiled_plan.ops) |candidate| {
        if (std.mem.eql(u8, candidate.op_name, op_name)) count += 1;
    }
    return count == 1;
}

fn HandlerType(comptime HandlerPtr: type) type {
    return switch (@typeInfo(HandlerPtr)) {
        .pointer => |pointer| pointer.child,
        else => HandlerPtr,
    };
}

fn afterDispatchAccepts(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime AuthoredPtr: type,
    comptime input_ref: program_plan.ValueRef,
) bool {
    const Authored = HandlerType(AuthoredPtr);
    const after_dispatch_info = @typeInfo(@TypeOf(Authored.afterDispatch)).@"fn";
    if (after_dispatch_info.params.len != 2) return false;
    const ValueParamType = after_dispatch_info.params[1].type orelse return false;
    return ValueParamType == ValueTypeForRef(compiled_plan, schema_types, input_ref);
}

fn dispatchAuthored(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime op: program_plan.OpPlan,
    comptime terminal_ref: program_plan.ValueRef,
    authored: anytype,
    payload: ExecutableValue,
    scratch: anytype,
) anyerror!OperationDispatch {
    const resume_ref: program_plan.ValueRef = comptime .{ .codec = op.resume_codec, .schema_index = op.resume_schema_index };
    const payload_ref: program_plan.ValueRef = .{ .codec = op.payload_codec, .schema_index = op.payload_schema_index };
    const dispatched = if (comptime op.payload_codec == .unit)
        try authored.dispatch()
    else
        try authored.dispatch(try decodeTypedValue(compiled_plan, schema_types, payload_ref, payload));
    return switch (comptime op.mode) {
        .abort => .{
            .value = try encodeRuntimeValueForRef(compiled_plan, schema_types, terminal_ref, scratch, dispatched),
            .resumes = false,
        },
        .transform => .{
            .value = try encodeRuntimeValueForRef(compiled_plan, schema_types, resume_ref, scratch, dispatched),
            .resumes = true,
        },
        .choice => switch (dispatched) {
            .resume_with => |resume_value| .{
                .value = try encodeRuntimeValueForRef(compiled_plan, schema_types, resume_ref, scratch, resume_value),
                .resumes = true,
            },
            .return_now => |answer| .{
                .value = try encodeRuntimeValueForRef(compiled_plan, schema_types, terminal_ref, scratch, answer),
                .resumes = false,
            },
        },
    };
}

fn callOpByIndex(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime terminal_ref: program_plan.ValueRef,
    handlers: anytype,
    scratch: anytype,
    op_index: u16,
    payload: ExecutableValue,
) anyerror!OperationDispatch {
    inline for (compiled_plan.ops, 0..) |op, index| {
        if (op_index == index) {
            const requirement = comptime compiled_plan.requirements[op.requirement_index];
            const HandlerSet = HandlerSetType(@TypeOf(handlers));
            const authored = if (comptime @hasField(HandlerSet, requirement.label) and
                @hasDecl(HandlerType(@TypeOf(handlerFieldPtr(handlers, requirement.label))), "dispatch"))
                handlerFieldPtr(handlers, requirement.label)
            else if (comptime @hasField(HandlerSet, requirement.label) and
                @hasField(HandlerSetType(@TypeOf(handlerFieldPtr(handlers, requirement.label))), op.op_name))
            blk: {
                const requirement_handler = handlerFieldPtr(handlers, requirement.label);
                break :blk handlerFieldPtr(requirement_handler, op.op_name);
            } else if (comptime @hasField(HandlerSet, requirement.label) and
                @hasField(HandlerSetType(@TypeOf(handlerFieldPtr(handlers, requirement.label))), "authored"))
            blk: {
                const requirement_handler = handlerFieldPtr(handlers, requirement.label);
                break :blk handlerFieldPtr(requirement_handler, "authored");
            } else if (comptime @hasField(HandlerSet, op.op_name) and opNameIsUnique(compiled_plan, op.op_name))
                handlerFieldPtr(handlers, op.op_name)
            else if (comptime @hasField(HandlerSet, "authored") and opNameIsUnique(compiled_plan, op.op_name))
                handlerFieldPtr(handlers, "authored")
            else
                @compileError("ProgramPlan op has no unambiguous handler field, requirement handler, or authored fallback");
            const result = try dispatchAuthored(compiled_plan, schema_types, op, terminal_ref, authored, payload, scratch);
            if (result.resumes and !valueMatchesRef(.{
                .codec = op.resume_codec,
                .schema_index = op.resume_schema_index,
            }, result.value)) return error.ProgramContractViolation;
            return result;
        }
    }
    return error.ProgramContractViolation;
}

fn callOpByIndexForFunctionIndex(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    function_index: usize,
    handlers: anytype,
    scratch: anytype,
    op_index: u16,
    payload: ExecutableValue,
) anyerror!OperationDispatch {
    inline for (compiled_plan.functions, 0..) |function, index| {
        if (function_index == index) {
            return callOpByIndex(
                compiled_plan,
                schema_types,
                program_plan.functionResultRef(function),
                handlers,
                scratch,
                op_index,
                payload,
            );
        }
    }
    return error.ProgramContractViolation;
}

fn planCallArgAt(comptime compiled_plan: program_plan.ProgramPlan, index: usize) u16 {
    if (compiled_plan.call_args.len == 0 or index >= compiled_plan.call_args.len) {
        return std.math.maxInt(u16);
    }
    return compiled_plan.call_args[index];
}

fn afterDispatchHandler(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime op: program_plan.OpPlan,
    handlers: anytype,
) @TypeOf(blk: {
    const requirement = comptime compiled_plan.requirements[op.requirement_index];
    const HandlerSet = HandlerSetType(@TypeOf(handlers));
    const authored = if (comptime @hasField(HandlerSet, requirement.label) and
        @hasDecl(HandlerType(@TypeOf(handlerFieldPtr(handlers, requirement.label))), "dispatch"))
        handlerFieldPtr(handlers, requirement.label)
    else if (comptime @hasField(HandlerSet, requirement.label) and
        @hasField(HandlerSetType(@TypeOf(handlerFieldPtr(handlers, requirement.label))), op.op_name))
    op_field: {
        const requirement_handler = handlerFieldPtr(handlers, requirement.label);
        break :op_field handlerFieldPtr(requirement_handler, op.op_name);
    } else if (comptime @hasField(HandlerSet, requirement.label) and
        @hasField(HandlerSetType(@TypeOf(handlerFieldPtr(handlers, requirement.label))), "authored"))
    authored_field: {
        const requirement_handler = handlerFieldPtr(handlers, requirement.label);
        break :authored_field handlerFieldPtr(requirement_handler, "authored");
    } else if (comptime @hasField(HandlerSet, op.op_name) and opNameIsUnique(compiled_plan, op.op_name))
        handlerFieldPtr(handlers, op.op_name)
    else if (comptime @hasField(HandlerSet, "authored") and opNameIsUnique(compiled_plan, op.op_name))
        handlerFieldPtr(handlers, "authored")
    else
        @compileError("ProgramPlan op has no unambiguous handler field, requirement handler, or authored fallback");
    break :blk authored;
}) {
    const requirement = comptime compiled_plan.requirements[op.requirement_index];
    const HandlerSet = HandlerSetType(@TypeOf(handlers));
    return if (comptime @hasField(HandlerSet, requirement.label) and
        @hasDecl(HandlerType(@TypeOf(handlerFieldPtr(handlers, requirement.label))), "dispatch"))
        handlerFieldPtr(handlers, requirement.label)
    else if (comptime @hasField(HandlerSet, requirement.label) and
        @hasField(HandlerSetType(@TypeOf(handlerFieldPtr(handlers, requirement.label))), op.op_name))
    op_field: {
        const requirement_handler = handlerFieldPtr(handlers, requirement.label);
        break :op_field handlerFieldPtr(requirement_handler, op.op_name);
    } else if (comptime @hasField(HandlerSet, requirement.label) and
        @hasField(HandlerSetType(@TypeOf(handlerFieldPtr(handlers, requirement.label))), "authored"))
    authored_field: {
        const requirement_handler = handlerFieldPtr(handlers, requirement.label);
        break :authored_field handlerFieldPtr(requirement_handler, "authored");
    } else if (comptime @hasField(HandlerSet, op.op_name) and opNameIsUnique(compiled_plan, op.op_name))
        handlerFieldPtr(handlers, op.op_name)
    else if (comptime @hasField(HandlerSet, "authored") and opNameIsUnique(compiled_plan, op.op_name))
        handlerFieldPtr(handlers, "authored")
    else
        @compileError("ProgramPlan op has no unambiguous handler field, requirement handler, or authored fallback");
}

// zlinter-disable max_positional_args - after dispatch preserves explicit input/output refs while keeping the op, plan, handlers, and scratch state visible.
fn applyAfterByIndexForRefExact(
    comptime input_ref: program_plan.ValueRef,
    comptime output_ref: program_plan.ValueRef,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime function_index: usize,
    handlers: anytype,
    scratch: anytype,
    op_index: u16,
    value: ExecutableValue,
) anyerror!AfterApplication {
    _ = function_index;
    inline for (compiled_plan.ops, 0..) |op, index| {
        if (op_index == index) {
            if (!op.has_after) return error.ProgramContractViolation;
            const authored = afterDispatchHandler(compiled_plan, op, handlers);
            if (comptime !afterDispatchAccepts(compiled_plan, schema_types, @TypeOf(authored), input_ref)) return error.ProgramContractViolation;
            const decoded = try decodeTypedValue(compiled_plan, schema_types, input_ref, value);
            const completed = try authored.afterDispatch(decoded);
            const encoded = try encodeRuntimeValueForRef(compiled_plan, schema_types, output_ref, scratch, completed);
            return .{
                .value = encoded,
                .ref = output_ref,
            };
        }
    }
    return error.ProgramContractViolation;
}

// zlinter-disable max_positional_args - after dispatch preserves inferred intermediate refs while keeping interpreter state visible.
fn applyAfterByIndexForRefInferred(
    comptime input_ref: program_plan.ValueRef,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime function_index: usize,
    handlers: anytype,
    scratch: anytype,
    op_index: u16,
    value: ExecutableValue,
) anyerror!AfterApplication {
    _ = function_index;
    inline for (compiled_plan.ops, 0..) |op, index| {
        if (op_index == index) {
            if (!op.has_after) return error.ProgramContractViolation;
            const authored = afterDispatchHandler(compiled_plan, op, handlers);
            if (comptime !afterDispatchAccepts(compiled_plan, schema_types, @TypeOf(authored), input_ref)) return error.ProgramContractViolation;
            const decoded = try decodeTypedValue(compiled_plan, schema_types, input_ref, value);
            const completed = try authored.afterDispatch(decoded);
            const encoded = try encodeRuntimeValueWithInferredRef(schema_types, scratch, completed);
            return .{
                .value = encoded.value,
                .ref = encoded.ref,
            };
        }
    }
    return error.ProgramContractViolation;
}

// zlinter-disable max_positional_args - output-ref dispatch mirrors input-ref dispatch without hiding the interpreter state.
fn applyAfterByIndexWithExactOutputRef(
    comptime output_ref: program_plan.ValueRef,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime function_index: usize,
    handlers: anytype,
    scratch: anytype,
    op_index: u16,
    value: ExecutableValue,
    current_ref: program_plan.ValueRef,
) anyerror!AfterApplication {
    return switch (current_ref.codec) {
        .unit => applyAfterByIndexForRefExact(.{ .codec = .unit }, output_ref, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .bool => applyAfterByIndexForRefExact(.{ .codec = .bool }, output_ref, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .i32 => applyAfterByIndexForRefExact(.{ .codec = .i32 }, output_ref, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .usize => applyAfterByIndexForRefExact(.{ .codec = .usize }, output_ref, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .string => applyAfterByIndexForRefExact(.{ .codec = .string }, output_ref, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .string_list => applyAfterByIndexForRefExact(.{ .codec = .string_list }, output_ref, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .product => {
            inline for (schema_types, 0..) |_, schema_index| {
                if (current_ref.schema_index == @as(u16, @intCast(schema_index))) {
                    return applyAfterByIndexForRefExact(.{ .codec = .product, .schema_index = @intCast(schema_index) }, output_ref, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value);
                }
            }
            return error.ProgramContractViolation;
        },
        .sum => {
            inline for (schema_types, 0..) |_, schema_index| {
                if (current_ref.schema_index == @as(u16, @intCast(schema_index))) {
                    return applyAfterByIndexForRefExact(.{ .codec = .sum, .schema_index = @intCast(schema_index) }, output_ref, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value);
                }
            }
            return error.ProgramContractViolation;
        },
    };
}

// zlinter-disable max_positional_args - inferred output-ref dispatch mirrors exact output dispatch for intermediate after frames.
fn applyAfterByIndexWithInferredOutputRef(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime function_index: usize,
    handlers: anytype,
    scratch: anytype,
    op_index: u16,
    value: ExecutableValue,
    current_ref: program_plan.ValueRef,
) anyerror!AfterApplication {
    return switch (current_ref.codec) {
        .unit => applyAfterByIndexForRefInferred(.{ .codec = .unit }, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .bool => applyAfterByIndexForRefInferred(.{ .codec = .bool }, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .i32 => applyAfterByIndexForRefInferred(.{ .codec = .i32 }, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .usize => applyAfterByIndexForRefInferred(.{ .codec = .usize }, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .string => applyAfterByIndexForRefInferred(.{ .codec = .string }, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .string_list => applyAfterByIndexForRefInferred(.{ .codec = .string_list }, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value),
        .product => {
            inline for (schema_types, 0..) |_, schema_index| {
                if (current_ref.schema_index == @as(u16, @intCast(schema_index))) {
                    return applyAfterByIndexForRefInferred(.{ .codec = .product, .schema_index = @intCast(schema_index) }, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value);
                }
            }
            return error.ProgramContractViolation;
        },
        .sum => {
            inline for (schema_types, 0..) |_, schema_index| {
                if (current_ref.schema_index == @as(u16, @intCast(schema_index))) {
                    return applyAfterByIndexForRefInferred(.{ .codec = .sum, .schema_index = @intCast(schema_index) }, compiled_plan, schema_types, function_index, handlers, scratch, op_index, value);
                }
            }
            return error.ProgramContractViolation;
        },
    };
}

// zlinter-disable max_positional_args - after-stack unwinding needs the current op, next op, and final function result refs together.
fn applyAfterByIndex(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime function_index: usize,
    handlers: anytype,
    scratch: anytype,
    op_index: u16,
    value: ExecutableValue,
    current_ref: program_plan.ValueRef,
    next_after_op_index: ?u16,
    comptime final_ref: program_plan.ValueRef,
) anyerror!AfterApplication {
    if (next_after_op_index != null) {
        return applyAfterByIndexWithInferredOutputRef(
            compiled_plan,
            schema_types,
            function_index,
            handlers,
            scratch,
            op_index,
            value,
            current_ref,
        );
    }
    return applyAfterByIndexWithExactOutputRef(
        final_ref,
        compiled_plan,
        schema_types,
        function_index,
        handlers,
        scratch,
        op_index,
        value,
        current_ref,
    );
}

fn completeFunctionValue(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime function_index: usize,
    handlers: anytype,
    scratch: anytype,
    completion: CompletionValue,
) anyerror!ExecutableValue {
    const function = comptime compiled_plan.functions[function_index];
    const result_ref = comptime program_plan.functionResultRef(function);
    const value_ref: program_plan.ValueRef = comptime .{
        .codec = function.value_codec,
        .schema_index = function.value_schema_index,
    };
    var completed = completion.value;
    var current_ref = completion.initial_ref;
    const final_ref = if (completion.kind == .terminal or completion.after_stack.len != 0) result_ref else value_ref;
    if (completion.kind == .normal) {
        var remaining = completion.after_stack.len;
        while (remaining != 0) {
            remaining -= 1;
            const next_after = if (remaining == 0) null else completion.after_stack[remaining - 1];
            const after = try applyAfterByIndex(
                compiled_plan,
                schema_types,
                function_index,
                handlers,
                scratch,
                completion.after_stack[remaining],
                completed,
                current_ref,
                next_after,
                result_ref,
            );
            completed = after.value;
            current_ref = after.ref;
        }
    }
    if (!valueMatchesRef(final_ref, completed)) return error.ProgramContractViolation;
    return completed;
}

// zlinter-disable max_positional_args - interpreter recursion keeps the comptime plan, error set, handler bundle, and call frame explicit.
fn executeKnownFunction(
    comptime ErrorSet: type,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    handlers: anytype,
    scratch: anytype,
    comptime function_index: usize,
    args: []const ExecutableValue,
    remaining_steps: *usize,
) anyerror!ExecutionResult {
    if (comptime function_index >= compiled_plan.functions.len) return error.ProgramContractViolation;
    const function = comptime compiled_plan.functions[function_index];
    if (args.len != function.parameter_count) return error.ProgramContractViolation;

    const frame = try scratch.pushFrame(function.local_count);
    defer scratch.popFrame(frame);
    var locals = scratch.frameLocals(frame);
    if (comptime function.parameter_count != 0) {
        for (args, 0..) |arg, index| {
            const local = compiled_plan.locals[function.first_local + index];
            if (!valueMatchesRef(.{ .codec = local.codec, .schema_index = local.schema_index }, arg)) return error.ProgramContractViolation;
            locals[index] = arg;
        }
    }

    var block_index: usize = @as(usize, function.first_block) + function.entry_block;
    var last_return: ExecutableValue = .none;
    var last_condition: bool = false;
    while (true) {
        locals = scratch.frameLocals(frame);
        try consumeInterpreterStep(remaining_steps);
        const function_block_end = @as(usize, function.first_block) + function.block_count;
        if (block_index < function.first_block or block_index >= function_block_end) return error.ProgramContractViolation;
        const block = compiled_plan.blocks[block_index];
        const instruction_end = @as(usize, block.first_instruction) + block.instruction_count;
        for (compiled_plan.instructions[block.first_instruction..instruction_end], block.first_instruction..) |instruction, instruction_index| {
            try consumeInterpreterStep(remaining_steps);
            switch (instruction.kind) {
                .add_const_i32 => {
                    const operand = try decodeArg(.i32, locals[instruction.operand]);
                    locals[instruction.dst] = .{
                        .i32 = std.math.add(i32, operand, @as(i32, @intCast(instruction.aux))) catch return error.ProgramContractViolation,
                    };
                },
                .add_i32 => {
                    const lhs = try decodeArg(.i32, locals[instruction.operand]);
                    const rhs = try decodeArg(.i32, locals[instruction.aux]);
                    locals[instruction.dst] = .{
                        .i32 = std.math.add(i32, lhs, rhs) catch return error.ProgramContractViolation,
                    };
                },
                .call_helper => {
                    const callee = compiled_plan.functions[instruction.operand];
                    const call_args = blk: {
                        if (callee.parameter_count == 0) break :blk &[_]ExecutableValue{};
                        if (instruction.aux == std.math.maxInt(u16)) return error.ProgramContractViolation;
                        if (comptime compiled_plan.call_args.len == 0) return error.ProgramContractViolation;

                        const buffer = try scratch.pushCallArgs(callee.parameter_count);
                        const arg_start = instruction.aux;
                        for (0..callee.parameter_count) |arg_index| {
                            const local_id = planCallArgAt(compiled_plan, arg_start + arg_index);
                            if (local_id >= locals.len) return error.ProgramContractViolation;
                            buffer[arg_index] = locals[local_id];
                        }
                        break :blk buffer[0..callee.parameter_count];
                    };
                    const helper_result = executeFunction(ErrorSet, runtime, compiled_plan, schema_types, handlers, scratch, instruction.operand, call_args, remaining_steps) catch |err| {
                        if (callee.parameter_count != 0) scratch.popCallArgs(call_args);
                        return err;
                    };
                    if (callee.parameter_count != 0) scratch.popCallArgs(call_args);
                    locals = scratch.frameLocals(frame);
                    if (helper_result.terminal) {
                        return .{
                            .value = try completeFunctionValue(
                                compiled_plan,
                                schema_types,
                                function_index,
                                handlers,
                                scratch,
                                .{
                                    .value = helper_result.value,
                                    .initial_ref = program_plan.functionResultRef(function),
                                    .after_stack = scratch.frameAfterStack(frame),
                                    .kind = .terminal,
                                },
                            ),
                            .terminal = true,
                        };
                    }
                    if (instruction.dst != std.math.maxInt(u16)) switch (helper_result.value) {
                        .none => {},
                        else => locals[instruction.dst] = helper_result.value,
                    };
                },
                .call_nested_with => return error.ProgramContractViolation,
                .call_op => {
                    if (comptime compiled_plan.ops.len == 0) return error.ProgramContractViolation;
                    if (instruction.operand >= compiled_plan.ops.len) return error.ProgramContractViolation;
                    const op = compiled_plan.ops[instruction.operand];
                    const payload = if (op.payload_codec == .unit) .none else locals[instruction.aux];
                    const op_result = try callOpByIndex(
                        compiled_plan,
                        schema_types,
                        program_plan.functionResultRef(function),
                        handlers,
                        scratch,
                        instruction.operand,
                        payload,
                    );
                    if (!op_result.resumes) {
                        return .{
                            .value = try completeFunctionValue(
                                compiled_plan,
                                schema_types,
                                function_index,
                                handlers,
                                scratch,
                                .{
                                    .value = op_result.value,
                                    .initial_ref = program_plan.functionResultRef(function),
                                    .after_stack = scratch.frameAfterStack(frame),
                                    .kind = .terminal,
                                },
                            ),
                            .terminal = true,
                        };
                    }
                    if (!valueMatchesRef(.{ .codec = op.resume_codec, .schema_index = op.resume_schema_index }, op_result.value)) return error.ProgramContractViolation;
                    if (op.has_after) {
                        try scratch.pushAfter(instruction.operand);
                    }
                    if (op.resume_codec == .unit) {
                        last_return = op_result.value;
                    } else if (instruction.dst != std.math.maxInt(u16)) {
                        locals[instruction.dst] = op_result.value;
                    } else {
                        last_return = op_result.value;
                    }
                },
                .compare_eq_zero => {
                    const is_zero = switch (functionLocalCodec(compiled_plan, function, instruction.operand) orelse return error.ProgramContractViolation) {
                        .bool => !(try decodeArg(.bool, locals[instruction.operand])),
                        .i32 => (try decodeArg(.i32, locals[instruction.operand])) == 0,
                        .usize => (try decodeArg(.usize, locals[instruction.operand])) == 0,
                        else => return error.ProgramContractViolation,
                    };
                    locals[instruction.dst] = .{ .bool = is_zero };
                    last_condition = is_zero;
                },
                .const_i32 => locals[instruction.dst] = .{ .i32 = @intCast(instruction.operand) },
                .const_string => locals[instruction.dst] = .{ .string = instruction.string_literal },
                .const_usize => {
                    locals[instruction.dst] = .{
                        .usize = std.fmt.parseUnsigned(usize, instruction.string_literal, 0) catch return error.ProgramContractViolation,
                    };
                },
                .return_error => return mappedReturnErrorForInstruction(ErrorSet, compiled_plan, instruction_index),
                .return_value => last_return = locals[instruction.operand],
                .sub_one => {
                    locals[instruction.dst] = switch (functionLocalCodec(compiled_plan, function, instruction.operand) orelse return error.ProgramContractViolation) {
                        .i32 => .{ .i32 = std.math.sub(i32, try decodeArg(.i32, locals[instruction.operand]), 1) catch return error.ProgramContractViolation },
                        .usize => .{ .usize = std.math.sub(usize, try decodeArg(.usize, locals[instruction.operand]), 1) catch return error.ProgramContractViolation },
                        else => return error.ProgramContractViolation,
                    };
                },
            }
        }
        const terminator = compiled_plan.terminators[block.terminator_index];
        switch (terminator.kind) {
            .branch_if => {
                block_index = if (last_condition) terminator.primary else terminator.secondary;
            },
            .jump => block_index = terminator.primary,
            .return_unit => return .{
                .value = try completeFunctionValue(
                    compiled_plan,
                    schema_types,
                    function_index,
                    handlers,
                    scratch,
                    .{
                        .value = if (function.value_codec == .unit) .none else last_return,
                        .initial_ref = .{ .codec = function.value_codec, .schema_index = function.value_schema_index },
                        .after_stack = scratch.frameAfterStack(frame),
                        .kind = .normal,
                    },
                ),
                .terminal = false,
            },
            .return_value => return .{
                .value = try completeFunctionValue(
                    compiled_plan,
                    schema_types,
                    function_index,
                    handlers,
                    scratch,
                    .{
                        .value = last_return,
                        .initial_ref = .{ .codec = function.value_codec, .schema_index = function.value_schema_index },
                        .after_stack = scratch.frameAfterStack(frame),
                        .kind = .normal,
                    },
                ),
                .terminal = false,
            },
        }
    }
}

// zlinter-disable max_positional_args - dynamic helper dispatch mirrors executeKnownFunction while selecting the comptime function body.
fn executeFunction(
    comptime ErrorSet: type,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    handlers: anytype,
    scratch: anytype,
    function_index: usize,
    args: []const ExecutableValue,
    remaining_steps: *usize,
) anyerror!ExecutionResult {
    inline for (compiled_plan.functions, 0..) |_, index| {
        if (function_index == index) {
            return executeKnownFunction(ErrorSet, runtime, compiled_plan, schema_types, handlers, scratch, index, args, remaining_steps);
        }
    }
    return error.ProgramContractViolation;
}

const ActiveInterpreterFrame = struct {
    function_index: usize,
    frame: InterpreterFrame,
    block_index: usize,
    instruction_index: usize,
    instruction_end: usize,
    last_return: ExecutableValue = .none,
    last_condition: bool = false,
    waiting_helper_dst: ?u16 = null,
};

const ActiveFrameStack = struct {
    buffer: []ActiveInterpreterFrame,
    len: usize = 0,

    fn append(self: *@This(), allocator: std.mem.Allocator, frame: ActiveInterpreterFrame) error{ExecutionBudgetExceeded}!void {
        _ = allocator;
        if (self.len == self.buffer.len) return error.ExecutionBudgetExceeded;
        self.buffer[self.len] = frame;
        self.len += 1;
    }

    fn pop(self: *@This()) ?ActiveInterpreterFrame {
        if (self.len == 0) return null;
        self.len -= 1;
        return self.buffer[self.len];
    }

    fn top(self: *@This()) *ActiveInterpreterFrame {
        return &self.buffer[self.len - 1];
    }
};

fn localRefForFunctionIndex(
    comptime compiled_plan: program_plan.ProgramPlan,
    function_index: usize,
    local_id: u16,
) ?program_plan.ValueRef {
    if (comptime compiled_plan.locals.len == 0) return null;
    if (function_index >= compiled_plan.functions.len) return null;
    const function = compiled_plan.functions[function_index];
    if (local_id >= function.local_count) return null;
    const local = compiled_plan.locals[function.first_local + local_id];
    return .{ .codec = local.codec, .schema_index = local.schema_index };
}

fn blockInstructionBounds(
    comptime compiled_plan: program_plan.ProgramPlan,
    function_index: usize,
    block_index: usize,
) error{ProgramContractViolation}!struct { first: usize, end: usize } {
    if (function_index >= compiled_plan.functions.len) return error.ProgramContractViolation;
    const function = compiled_plan.functions[function_index];
    const function_block_end = @as(usize, function.first_block) + function.block_count;
    if (block_index < function.first_block or block_index >= function_block_end) return error.ProgramContractViolation;
    const block = compiled_plan.blocks[block_index];
    const first = @as(usize, block.first_instruction);
    return .{ .first = first, .end = first + block.instruction_count };
}

fn completeFunctionValueByIndex(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    handlers: anytype,
    scratch: anytype,
    function_index: usize,
    completion: CompletionValue,
) anyerror!ExecutableValue {
    inline for (compiled_plan.functions, 0..) |_, index| {
        if (function_index == index) {
            return completeFunctionValue(compiled_plan, schema_types, index, handlers, scratch, completion);
        }
    }
    return error.ProgramContractViolation;
}

fn nestedWithTargetForMetadata(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    metadata: []const u8,
) ?program_plan.FunctionPlan {
    inline for (nested_with_targets) |target| {
        if (std.mem.eql(u8, target.metadata, metadata)) {
            if (target.function_index >= compiled_plan.functions.len) return null;
            return compiled_plan.functions[target.function_index];
        }
    }
    return null;
}

fn nestedWithTargetIndexForMetadata(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
    metadata: []const u8,
) ?usize {
    inline for (nested_with_targets) |target| {
        if (std.mem.eql(u8, target.metadata, metadata)) {
            if (target.function_index >= compiled_plan.functions.len) return null;
            return target.function_index;
        }
    }
    return null;
}

fn pushActiveInterpreterFrame(
    allocator: std.mem.Allocator,
    comptime compiled_plan: program_plan.ProgramPlan,
    scratch: anytype,
    frames: *ActiveFrameStack,
    function_index: usize,
    args: []const ExecutableValue,
) anyerror!void {
    if (function_index >= compiled_plan.functions.len) return error.ProgramContractViolation;
    const function = compiled_plan.functions[function_index];
    if (args.len != function.parameter_count) return error.ProgramContractViolation;

    const frame = try scratch.pushFrame(function.local_count);
    errdefer scratch.popFrame(frame);
    var locals = scratch.frameLocals(frame);
    if (comptime compiled_plan.locals.len == 0) {
        if (args.len != 0) return error.ProgramContractViolation;
    } else {
        for (args, 0..) |arg, index| {
            const local = compiled_plan.locals[function.first_local + index];
            if (!valueMatchesRef(.{ .codec = local.codec, .schema_index = local.schema_index }, arg)) return error.ProgramContractViolation;
            locals[index] = arg;
        }
    }

    const entry_block = @as(usize, function.first_block) + function.entry_block;
    const bounds = try blockInstructionBounds(compiled_plan, function_index, entry_block);
    try frames.append(allocator, .{
        .function_index = function_index,
        .frame = frame,
        .block_index = entry_block,
        .instruction_index = bounds.first,
        .instruction_end = bounds.end,
    });
}

// zlinter-disable max_positional_args - the trampoline keeps runtime execution, plan data, handlers, and frame state explicit.
fn returnFromActiveFrame(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    handlers: anytype,
    scratch: anytype,
    frames: *ActiveFrameStack,
    initial_returned: ExecutionResult,
) anyerror!?ExecutionResult {
    var returned = initial_returned;
    while (true) {
        if (frames.len == 0) return error.ProgramContractViolation;
        const completed_frame = frames.pop().?;
        scratch.popFrame(completed_frame.frame);

        if (frames.len == 0) return returned;
        var parent = frames.top();
        if (returned.terminal) {
            const parent_function = compiled_plan.functions[parent.function_index];
            const completed = try completeFunctionValueByIndex(
                compiled_plan,
                schema_types,
                handlers,
                scratch,
                parent.function_index,
                .{
                    .value = returned.value,
                    .initial_ref = program_plan.functionResultRef(parent_function),
                    .after_stack = scratch.frameAfterStack(parent.frame),
                    .kind = .terminal,
                },
            );
            returned = .{ .value = completed, .terminal = true };
            continue;
        }

        const dst = parent.waiting_helper_dst orelse return error.ProgramContractViolation;
        parent.waiting_helper_dst = null;
        if (dst != std.math.maxInt(u16)) switch (returned.value) {
            .none => {},
            else => scratch.frameLocals(parent.frame)[dst] = returned.value,
        };
        return null;
    }
}

// zlinter-disable max_positional_args - explicit frame-machine executor avoids host recursion for helper calls.
fn executeFunctionWithFrameStack(
    comptime ErrorSet: type,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
    handlers: anytype,
    scratch: anytype,
    function_index: usize,
    args: []const ExecutableValue,
    remaining_steps: *usize,
) anyerror!ExecutionResult {
    _ = runtime;
    const allocator = scratch.allocator;
    var frame_storage: [max_interpreter_steps]ActiveInterpreterFrame = undefined;
    var frames = ActiveFrameStack{ .buffer = &frame_storage };
    defer {
        while (frames.len != 0) {
            const active = frames.pop().?;
            scratch.popFrame(active.frame);
        }
    }

    try pushActiveInterpreterFrame(allocator, compiled_plan, scratch, &frames, function_index, args);
    while (frames.len != 0) {
        try consumeInterpreterStep(remaining_steps);
        var active = frames.top();
        if (active.waiting_helper_dst != null) return error.ProgramContractViolation;

        if (active.instruction_index < active.instruction_end) {
            if (comptime compiled_plan.instructions.len == 0) return error.ProgramContractViolation;
            const instruction_index = active.instruction_index;
            active.instruction_index += 1;
            try consumeInterpreterStep(remaining_steps);

            const instruction = compiled_plan.instructions[instruction_index];
            const function = compiled_plan.functions[active.function_index];
            var locals = scratch.frameLocals(active.frame);
            switch (instruction.kind) {
                .add_const_i32 => {
                    const operand = try decodeArg(.i32, locals[instruction.operand]);
                    locals[instruction.dst] = .{
                        .i32 = std.math.add(i32, operand, @as(i32, @intCast(instruction.aux))) catch return error.ProgramContractViolation,
                    };
                },
                .add_i32 => {
                    const lhs = try decodeArg(.i32, locals[instruction.operand]);
                    const rhs = try decodeArg(.i32, locals[instruction.aux]);
                    locals[instruction.dst] = .{
                        .i32 = std.math.add(i32, lhs, rhs) catch return error.ProgramContractViolation,
                    };
                },
                .call_helper => {
                    const callee = compiled_plan.functions[instruction.operand];
                    const buffer = try scratch.pushCallArgs(callee.parameter_count);
                    var args_popped = false;
                    errdefer if (!args_popped) scratch.popCallArgs(buffer[0..callee.parameter_count]);
                    if (callee.parameter_count != 0) {
                        if (instruction.aux == std.math.maxInt(u16)) return error.ProgramContractViolation;
                        for (0..callee.parameter_count) |arg_index| {
                            const local_id = planCallArgAt(compiled_plan, instruction.aux + arg_index);
                            if (local_id >= locals.len) return error.ProgramContractViolation;
                            buffer[arg_index] = locals[local_id];
                        }
                    }
                    active.waiting_helper_dst = instruction.dst;
                    try pushActiveInterpreterFrame(
                        allocator,
                        compiled_plan,
                        scratch,
                        &frames,
                        instruction.operand,
                        buffer[0..callee.parameter_count],
                    );
                    frames.top().frame.call_args_start -= callee.parameter_count;
                    scratch.popCallArgs(buffer[0..callee.parameter_count]);
                    args_popped = true;
                },
                .call_nested_with => {
                    const target_index = nestedWithTargetIndexForMetadata(compiled_plan, nested_with_targets, instruction.string_literal) orelse return error.ProgramContractViolation;
                    const target = compiled_plan.functions[target_index];
                    if (target.parameter_count != 0) return error.ProgramContractViolation;
                    const result_codec = program_plan.valueCodecFromInstructionAux(instruction.aux) catch return error.ProgramContractViolation;
                    if (result_codec != .unit and instruction.dst == std.math.maxInt(u16)) return error.ProgramContractViolation;
                    active.waiting_helper_dst = instruction.dst;
                    try pushActiveInterpreterFrame(
                        allocator,
                        compiled_plan,
                        scratch,
                        &frames,
                        target_index,
                        &.{},
                    );
                },
                .call_op => {
                    if (comptime compiled_plan.ops.len == 0) return error.ProgramContractViolation;
                    if (instruction.operand >= compiled_plan.ops.len) return error.ProgramContractViolation;
                    const op = compiled_plan.ops[instruction.operand];
                    const payload = if (op.payload_codec == .unit) .none else locals[instruction.aux];
                    const op_result = try callOpByIndexForFunctionIndex(
                        compiled_plan,
                        schema_types,
                        active.function_index,
                        handlers,
                        scratch,
                        instruction.operand,
                        payload,
                    );
                    if (!op_result.resumes) {
                        const completed = try completeFunctionValueByIndex(
                            compiled_plan,
                            schema_types,
                            handlers,
                            scratch,
                            active.function_index,
                            .{
                                .value = op_result.value,
                                .initial_ref = program_plan.functionResultRef(function),
                                .after_stack = scratch.frameAfterStack(active.frame),
                                .kind = .terminal,
                            },
                        );
                        if (try returnFromActiveFrame(compiled_plan, schema_types, handlers, scratch, &frames, .{ .value = completed, .terminal = true })) |result| return result;
                    } else {
                        if (!valueMatchesRef(.{ .codec = op.resume_codec, .schema_index = op.resume_schema_index }, op_result.value)) return error.ProgramContractViolation;
                        if (op.has_after) try scratch.pushAfter(instruction.operand);
                        if (op.resume_codec == .unit) {
                            active.last_return = op_result.value;
                        } else if (instruction.dst != std.math.maxInt(u16)) {
                            locals[instruction.dst] = op_result.value;
                        } else {
                            active.last_return = op_result.value;
                        }
                    }
                },
                .compare_eq_zero => {
                    const operand_ref = localRefForFunctionIndex(compiled_plan, active.function_index, instruction.operand) orelse return error.ProgramContractViolation;
                    const is_zero = switch (operand_ref.codec) {
                        .bool => !(try decodeArg(.bool, locals[instruction.operand])),
                        .i32 => (try decodeArg(.i32, locals[instruction.operand])) == 0,
                        .usize => (try decodeArg(.usize, locals[instruction.operand])) == 0,
                        else => return error.ProgramContractViolation,
                    };
                    locals[instruction.dst] = .{ .bool = is_zero };
                    active.last_condition = is_zero;
                },
                .const_i32 => locals[instruction.dst] = .{ .i32 = @intCast(instruction.operand) },
                .const_string => locals[instruction.dst] = .{ .string = instruction.string_literal },
                .const_usize => {
                    locals[instruction.dst] = .{
                        .usize = std.fmt.parseUnsigned(usize, instruction.string_literal, 0) catch return error.ProgramContractViolation,
                    };
                },
                .return_error => return mappedReturnErrorForInstruction(ErrorSet, compiled_plan, instruction_index),
                .return_value => active.last_return = locals[instruction.operand],
                .sub_one => {
                    const operand_ref = localRefForFunctionIndex(compiled_plan, active.function_index, instruction.operand) orelse return error.ProgramContractViolation;
                    locals[instruction.dst] = switch (operand_ref.codec) {
                        .i32 => .{ .i32 = std.math.sub(i32, try decodeArg(.i32, locals[instruction.operand]), 1) catch return error.ProgramContractViolation },
                        .usize => .{ .usize = std.math.sub(usize, try decodeArg(.usize, locals[instruction.operand]), 1) catch return error.ProgramContractViolation },
                        else => return error.ProgramContractViolation,
                    };
                },
            }
            continue;
        }

        const block = compiled_plan.blocks[active.block_index];
        const terminator = compiled_plan.terminators[block.terminator_index];
        const function = compiled_plan.functions[active.function_index];
        switch (terminator.kind) {
            .branch_if => {
                const next_block = if (active.last_condition) terminator.primary else terminator.secondary;
                const bounds = try blockInstructionBounds(compiled_plan, active.function_index, next_block);
                active.block_index = next_block;
                active.instruction_index = bounds.first;
                active.instruction_end = bounds.end;
            },
            .jump => {
                const bounds = try blockInstructionBounds(compiled_plan, active.function_index, terminator.primary);
                active.block_index = terminator.primary;
                active.instruction_index = bounds.first;
                active.instruction_end = bounds.end;
            },
            .return_unit => {
                const completed = try completeFunctionValueByIndex(
                    compiled_plan,
                    schema_types,
                    handlers,
                    scratch,
                    active.function_index,
                    .{
                        .value = if (function.value_codec == .unit) .none else active.last_return,
                        .initial_ref = .{ .codec = function.value_codec, .schema_index = function.value_schema_index },
                        .after_stack = scratch.frameAfterStack(active.frame),
                        .kind = .normal,
                    },
                );
                if (try returnFromActiveFrame(compiled_plan, schema_types, handlers, scratch, &frames, .{ .value = completed, .terminal = false })) |result| return result;
            },
            .return_value => {
                const completed = try completeFunctionValueByIndex(
                    compiled_plan,
                    schema_types,
                    handlers,
                    scratch,
                    active.function_index,
                    .{
                        .value = active.last_return,
                        .initial_ref = .{ .codec = function.value_codec, .schema_index = function.value_schema_index },
                        .after_stack = scratch.frameAfterStack(active.frame),
                        .kind = .normal,
                    },
                );
                if (try returnFromActiveFrame(compiled_plan, schema_types, handlers, scratch, &frames, .{ .value = completed, .terminal = false })) |result| return result;
            },
        }
    }
    return error.ProgramContractViolation;
}

pub fn runExecutablePlanWithArgsForErrorSet(
    comptime ErrorSet: type,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers: anytype,
    args: []const lowered_machine.ProgramValue,
) anyerror!RunResultTypeForPlan(compiled_plan) {
    try validateExecutablePlanSupport(compiled_plan);
    try lowered_machine.beginExecution(runtime);
    defer lowered_machine.endExecution(runtime);
    return runExecutablePlanWithArgsForErrorSetUnchecked(ErrorSet, runtime, compiled_plan, handlers, args);
}

/// Interpret an executable plan after the caller has already entered runtime execution.
pub fn runExecutablePlanWithArgsForErrorSetInRuntimeExecution(
    comptime ErrorSet: type,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers: anytype,
    args: []const lowered_machine.ProgramValue,
) anyerror!RunResultTypeForPlan(compiled_plan) {
    try validateExecutablePlanSupport(compiled_plan);
    return runExecutablePlanWithArgsForErrorSetUnchecked(ErrorSet, runtime, compiled_plan, handlers, args);
}

fn runExecutablePlanWithArgsForErrorSetUnchecked(
    comptime ErrorSet: type,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers: anytype,
    args: []const lowered_machine.ProgramValue,
) anyerror!RunResultTypeForPlan(compiled_plan) {
    const entry = comptime compiled_plan.functions[compiled_plan.entry_index];
    if (args.len != entry.parameter_count) return error.ProgramContractViolation;
    const analysis = comptime program_plan.entryExecutionAnalysis(compiled_plan) catch |err|
        @compileError("validated ProgramPlan entry analysis failed: " ++ @errorName(err));
    const after_stack_capacity = if (analysis.reachable_after_count == 0) 0 else max_interpreter_steps;
    var remaining_steps: usize = max_interpreter_steps;
    var scratch = try InterpreterScratch(after_stack_capacity).init(
        lowered_machine.runtimeAllocator(runtime),
        analysis.max_active_local_slots,
        analysis.max_active_call_arg_slots,
    );
    defer scratch.deinit();
    var entry_args: [entry.parameter_count]ExecutableValue = undefined;
    try encodePublicEntryArgs(compiled_plan, entry_args[0..], args);
    const raw = try executeFunctionWithFrameStack(ErrorSet, runtime, compiled_plan, &.{}, &.{}, handlers, &scratch, compiled_plan.entry_index, entry_args[0..], &remaining_steps);
    return .{ .value = try decodeArg(program_plan.functionResultCodec(entry), raw.value) };
}

fn encodePublicEntryArgs(
    comptime compiled_plan: program_plan.ProgramPlan,
    out: []ExecutableValue,
    args: []const lowered_machine.ProgramValue,
) error{ProgramContractViolation}!void {
    const entry = comptime compiled_plan.functions[compiled_plan.entry_index];
    if (args.len != entry.parameter_count or out.len != entry.parameter_count) return error.ProgramContractViolation;
    if (comptime entry.parameter_count == 0) return;
    for (args, 0..) |arg, index| {
        const encoded = executableValueFromPublic(arg);
        const local = compiled_plan.locals[entry.first_local + index];
        if (!valueMatchesRef(.{ .codec = local.codec, .schema_index = local.schema_index }, encoded)) return error.ProgramContractViolation;
        out[index] = encoded;
    }
}

fn encodeTypedTupleEntryArgs(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    scratch: anytype,
    out: []ExecutableValue,
    args: anytype,
) (std.mem.Allocator.Error || error{ProgramContractViolation})!void {
    const entry = comptime compiled_plan.functions[compiled_plan.entry_index];
    const Args = @TypeOf(args);
    const args_info = @typeInfo(Args);
    if (args_info != .@"struct" or !args_info.@"struct".is_tuple) {
        @compileError("Body.encodeArgs must return []const ability.ir.ProgramValue or a tuple matching entry parameters");
    }
    const fields = args_info.@"struct".fields;
    if (fields.len != entry.parameter_count) {
        @compileError("Body.encodeArgs tuple length must match ProgramPlan entry parameter_count");
    }
    if (out.len != entry.parameter_count) return error.ProgramContractViolation;
    inline for (fields, 0..) |field, index| {
        const local = compiled_plan.locals[entry.first_local + index];
        const ref: program_plan.ValueRef = .{ .codec = local.codec, .schema_index = local.schema_index };
        const Expected = ValueTypeForRef(compiled_plan, schema_types, ref);
        if (field.type != Expected) {
            @compileError("Body.encodeArgs tuple field type does not match ProgramPlan entry parameter " ++ std.fmt.comptimePrint("{d}", .{index}));
        }
        out[index] = encodeRuntimeValueForRef(compiled_plan, schema_types, ref, scratch, @field(args, field.name)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.ProgramContractViolation,
        };
    }
}

fn encodeEntryArgs(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    scratch: anytype,
    out: []ExecutableValue,
    args: anytype,
) (std.mem.Allocator.Error || error{ProgramContractViolation})!void {
    const Args = @TypeOf(args);
    if (Args == []const lowered_machine.ProgramValue) {
        return encodePublicEntryArgs(compiled_plan, out, args);
    }
    return encodeTypedTupleEntryArgs(compiled_plan, schema_types, scratch, out, args);
}

pub fn runExecutablePlanWithTypedArgsForErrorSetInRuntimeExecution(
    comptime ErrorSet: type,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    handlers: anytype,
    args: anytype,
) anyerror!TypedRunResultTypeForPlan(compiled_plan, schema_types) {
    try validateTypedExecutablePlanSupport(compiled_plan, schema_types);
    return runExecutablePlanWithTypedArgsForErrorSetUnchecked(ErrorSet, runtime, compiled_plan, schema_types, handlers, args);
}

pub fn runExecutablePlanWithTypedArgsForErrorSetAndNestedTargetsInRuntimeExecution(
    comptime ErrorSet: type,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
    handlers: anytype,
    args: anytype,
) anyerror!TypedRunResultTypeForPlan(compiled_plan, schema_types) {
    try validateTypedExecutablePlanSupportWithNestedTargets(compiled_plan, schema_types, nested_with_targets);
    return runExecutablePlanWithTypedArgsForErrorSetAndNestedTargetsUnchecked(ErrorSet, runtime, compiled_plan, schema_types, nested_with_targets, handlers, args);
}

fn runExecutablePlanWithTypedArgsForErrorSetUnchecked(
    comptime ErrorSet: type,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    handlers: anytype,
    args: anytype,
) anyerror!TypedRunResultTypeForPlan(compiled_plan, schema_types) {
    return runExecutablePlanWithTypedArgsForErrorSetAndNestedTargetsUnchecked(ErrorSet, runtime, compiled_plan, schema_types, &.{}, handlers, args);
}

fn runExecutablePlanWithTypedArgsForErrorSetAndNestedTargetsUnchecked(
    comptime ErrorSet: type,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
    handlers: anytype,
    args: anytype,
) anyerror!TypedRunResultTypeForPlan(compiled_plan, schema_types) {
    const entry = comptime compiled_plan.functions[compiled_plan.entry_index];
    const analysis = comptime program_plan.entryExecutionAnalysisWithNestedTargets(compiled_plan, nested_with_targets) catch |err|
        @compileError("validated ProgramPlan entry analysis failed: " ++ @errorName(err));
    const after_stack_capacity = if (analysis.reachable_after_count == 0) 0 else max_interpreter_steps;
    var remaining_steps: usize = max_interpreter_steps;
    var scratch = try InterpreterScratch(after_stack_capacity).init(
        lowered_machine.runtimeAllocator(runtime),
        analysis.max_active_local_slots,
        analysis.max_active_call_arg_slots,
    );
    defer scratch.deinit();
    var entry_args: [entry.parameter_count]ExecutableValue = undefined;
    try encodeEntryArgs(compiled_plan, schema_types, &scratch, entry_args[0..], args);
    const raw = try executeFunctionWithFrameStack(ErrorSet, runtime, compiled_plan, schema_types, nested_with_targets, handlers, &scratch, compiled_plan.entry_index, entry_args[0..], &remaining_steps);
    return .{ .value = try decodeTypedValue(compiled_plan, schema_types, program_plan.functionResultRef(entry), raw.value) };
}

pub fn runExecutablePlanWithArgs(
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers: anytype,
    args: []const lowered_machine.ProgramValue,
) anyerror!RunResultTypeForPlan(compiled_plan) {
    return runExecutablePlanWithArgsForErrorSet(error{}, runtime, compiled_plan, handlers, args);
}

fn supportPlanError(comptime err: anyerror) noreturn {
    @compileError("invalid executable support test plan: " ++ @errorName(err));
}

fn supportSchemaTables(comptime codec: program_plan.ValueCodec) struct {
    schemas: []const program_plan.ValueSchemaPlan,
    fields: []const program_plan.ValueFieldPlan,
    variants: []const program_plan.ValueVariantPlan,
    schema_index: ?u16,
} {
    if (codec == .product) {
        const schemas = [_]program_plan.ValueSchemaPlan{.{
            .label = "Product",
            .codec = .product,
            .first_field = 0,
            .field_count = 1,
        }};
        const fields = [_]program_plan.ValueFieldPlan{.{ .name = "value", .codec = .i32 }};
        return .{ .schemas = &schemas, .fields = &fields, .variants = &.{}, .schema_index = 0 };
    }
    if (codec == .sum) {
        const schemas = [_]program_plan.ValueSchemaPlan{.{
            .label = "Sum",
            .codec = .sum,
            .first_variant = 0,
            .variant_count = 1,
        }};
        const variants = [_]program_plan.ValueVariantPlan{.{ .name = "value", .codec = .i32 }};
        return .{ .schemas = &schemas, .fields = &.{}, .variants = &variants, .schema_index = 0 };
    }
    return .{ .schemas = &.{}, .fields = &.{}, .variants = &.{}, .schema_index = null };
}

fn supportResultPlan(comptime codec: program_plan.ValueCodec) program_plan.ProgramPlan {
    if (codec == .unit) return supportUnitPlan("unit-result");
    const root = program_plan.program_plan_builder.function(0);
    const value = program_plan.program_plan_builder.local(root, 0);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.returnValue(root, value) catch |err| supportPlanError(err),
    };
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "run",
        .value_codec = codec,
        .value_schema_index = supportSchemaTables(codec).schema_index,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 1,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]program_plan.BlockPlan{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_value }};
    const schema = supportSchemaTables(codec);
    return program_plan.program_plan_builder.finish(.{
        .label = "unsupported-result",
        .ir_hash = 101,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .value_variants = schema.variants,
        .locals = &.{.{ .codec = codec, .schema_index = schema.schema_index }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportUnitPlan(comptime label: []const u8) program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 0,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = 0,
    }};
    const blocks = [_]program_plan.BlockPlan{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_unit }};
    return program_plan.program_plan_builder.finish(.{
        .label = label,
        .ir_hash = 100,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &.{},
    }) catch |err| supportPlanError(err);
}

fn supportParameterPlan(comptime codec: program_plan.ValueCodec) program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 1,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = 0,
    }};
    const blocks = [_]program_plan.BlockPlan{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_unit }};
    const schema = supportSchemaTables(codec);
    return program_plan.program_plan_builder.finish(.{
        .label = "unsupported-parameter",
        .ir_hash = 102,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .value_variants = schema.variants,
        .locals = &.{.{ .codec = codec, .schema_index = schema.schema_index }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &.{},
    }) catch |err| supportPlanError(err);
}

fn supportOpPlan(comptime payload_codec: program_plan.ValueCodec, comptime resume_codec: program_plan.ValueCodec) program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const local = program_plan.program_plan_builder.local(root, 0);
    const payload_ref = if (payload_codec == .unit) null else local;
    const dst_ref = if (resume_codec == .unit) null else local;
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callOp(root, dst_ref, program_plan.program_plan_builder.op(root, 0), payload_ref) catch |err| supportPlanError(err),
    };
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 1,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "structured", .first_op = 0, .op_count = 1 }};
    const payload_schema = supportSchemaTables(payload_codec);
    const resume_schema = supportSchemaTables(resume_codec);
    const schemas = if (payload_codec == .product or payload_codec == .sum)
        payload_schema.schemas
    else
        resume_schema.schemas;
    const fields = if (payload_codec == .product) payload_schema.fields else resume_schema.fields;
    const variants = if (payload_codec == .sum) payload_schema.variants else resume_schema.variants;
    const local_codec = if (payload_codec == .unit) resume_codec else payload_codec;
    const local_schema_index = if (payload_codec == .unit) resume_schema.schema_index else payload_schema.schema_index;
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "structured",
        .mode = .transform,
        .payload_codec = payload_codec,
        .payload_schema_index = payload_schema.schema_index,
        .resume_codec = resume_codec,
        .resume_schema_index = resume_schema.schema_index,
    }};
    const blocks = [_]program_plan.BlockPlan{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_unit }};
    return program_plan.program_plan_builder.finish(.{
        .label = "unsupported-op",
        .ir_hash = 103,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = schemas,
        .value_fields = fields,
        .value_variants = variants,
        .locals = &.{.{ .codec = local_codec, .schema_index = local_schema_index }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportNestedWithPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const instructions = [_]program_plan.Instruction{.{
        .kind = .call_nested_with,
        .string_literal = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi",
    }};
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 0,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]program_plan.BlockPlan{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_unit }};
    return program_plan.program_plan_builder.finish(.{
        .label = "nested-with",
        .ir_hash = 104,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportNestedWithStructuredTargetPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const nested = program_plan.program_plan_builder.function(1);
    const nested_payload = program_plan.program_plan_builder.local(nested, 0);
    const instructions = [_]program_plan.Instruction{
        .{
            .kind = .call_nested_with,
            .aux = @intFromEnum(program_plan.ValueCodec.unit),
            .string_literal = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi",
        },
        program_plan.program_plan_builder.callOp(nested, null, program_plan.program_plan_builder.op(nested, 0), nested_payload) catch |err| supportPlanError(err),
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        },
        .{
            .symbol_name = "nested",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 1,
            .instruction_count = 1,
        },
    };
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "structured", .first_op = 0, .op_count = 1 }};
    const schema = supportSchemaTables(.product);
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "structured",
        .mode = .transform,
        .payload_codec = .product,
        .payload_schema_index = schema.schema_index,
        .resume_codec = .unit,
    }};
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{ .{ .kind = .return_unit }, .{ .kind = .return_unit } };
    return program_plan.program_plan_builder.finish(.{
        .label = "nested-with-structured-target",
        .ir_hash = 115,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .locals = &.{.{ .codec = .product, .schema_index = schema.schema_index }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportNestedWithTerminalResultMismatchPlan() program_plan.ProgramPlan {
    const instructions = [_]program_plan.Instruction{
        .{
            .kind = .call_nested_with,
            .aux = @intFromEnum(program_plan.ValueCodec.unit),
            .string_literal = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi",
        },
        .{ .kind = .call_op, .operand = 0 },
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
            .result_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        },
        .{
            .symbol_name = "nested",
            .value_codec = .unit,
            .result_codec = .string,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 1,
            .instruction_count = 1,
        },
    };
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "abort", .first_op = 0, .op_count = 1 }};
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "abort",
        .mode = .abort,
        .payload_codec = .unit,
        .resume_codec = .unit,
    }};
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
    };
    return .{
        .label = "nested-with-terminal-result-mismatch",
        .ir_hash = 116,
        .entry_index = 0,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    };
}

fn supportManyNestedWithPlan(comptime count: usize) program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const instructions = comptime blk: {
        var rows: [count]program_plan.Instruction = undefined;
        for (0..count) |index| {
            rows[index] = .{
                .kind = .call_nested_with,
                .aux = @intFromEnum(program_plan.ValueCodec.unit),
                .string_literal = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi",
            };
        }
        break :blk rows;
    };
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 0,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]program_plan.BlockPlan{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_unit }};
    return program_plan.program_plan_builder.finish(.{
        .label = "many-nested-with",
        .ir_hash = 114,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportStructuredHelperLocalPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const helper = program_plan.program_plan_builder.function(1);
    const root_value = program_plan.program_plan_builder.local(root, 0);
    const helper_value = program_plan.program_plan_builder.local(helper, 0);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callHelper(root, root_value, helper, null) catch |err| supportPlanError(err),
        .{ .kind = .return_value, .operand = helper_value.index },
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        },
        .{
            .symbol_name = "helper",
            .value_codec = .product,
            .value_schema_index = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 1,
            .local_count = 1,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 1,
            .instruction_count = 1,
        },
    };
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_value },
    };
    const schema = supportSchemaTables(.product);
    return program_plan.program_plan_builder.finish(.{
        .label = "structured-local",
        .ir_hash = 105,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .locals = &.{ .{ .codec = .product, .schema_index = 0 }, .{ .codec = .product, .schema_index = 0 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportStructuredHelperParameterPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const helper = program_plan.program_plan_builder.function(1);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callHelperDiscardingResult(root, std.math.maxInt(u16), helper, 0),
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        },
        .{
            .symbol_name = "helper",
            .value_codec = .unit,
            .parameter_count = 1,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 1,
            .local_count = 1,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 1,
            .instruction_count = 0,
        },
    };
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 0, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
    };
    const schema = supportSchemaTables(.product);
    return program_plan.program_plan_builder.finish(.{
        .label = "structured-helper-parameter",
        .ir_hash = 108,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .locals = &.{
            .{ .codec = .product, .schema_index = 0 },
            .{ .codec = .product, .schema_index = 0 },
        },
        .call_args = &.{0},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportUnreachableStructuredHelperPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const helper = program_plan.program_plan_builder.function(1);
    const helper_value = program_plan.program_plan_builder.local(helper, 0);
    const instructions = [_]program_plan.Instruction{
        .{ .kind = .return_value, .operand = helper_value.index },
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        },
        .{
            .symbol_name = "dead_helper",
            .value_codec = .product,
            .value_schema_index = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        },
    };
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 },
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_value },
    };
    const schema = supportSchemaTables(.product);
    return program_plan.program_plan_builder.finish(.{
        .label = "dead-structured-helper",
        .ir_hash = 107,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .locals = &.{.{ .codec = .product, .schema_index = 0 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportHelperCyclePlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const helper = program_plan.program_plan_builder.function(1);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callHelperDiscardingResult(root, std.math.maxInt(u16), helper, null),
        program_plan.program_plan_builder.callHelperDiscardingResult(helper, std.math.maxInt(u16), root, null),
    };
    const functions = [_]program_plan.FunctionPlan{
        .{ .symbol_name = "run", .first_requirement = 0, .requirement_count = 0, .first_output = 0, .output_count = 0, .first_local = 0, .local_count = 0, .first_block = 0, .entry_block = 0, .block_count = 1, .first_instruction = 0, .instruction_count = 1 },
        .{ .symbol_name = "helper", .first_requirement = 0, .requirement_count = 0, .first_output = 0, .output_count = 0, .first_local = 0, .local_count = 0, .first_block = 1, .entry_block = 0, .block_count = 1, .first_instruction = 1, .instruction_count = 1 },
    };
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
    };
    return program_plan.program_plan_builder.finish(.{
        .label = "helper-cycle",
        .ir_hash = 106,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportAbortBeforeStructuredHelperPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const helper = program_plan.program_plan_builder.function(1);
    const root_value = program_plan.program_plan_builder.local(root, 0);
    const helper_value = program_plan.program_plan_builder.local(helper, 0);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callOp(root, null, program_plan.program_plan_builder.op(root, 0), null) catch |err| supportPlanError(err),
        program_plan.program_plan_builder.callHelper(root, root_value, helper, null) catch |err| supportPlanError(err),
        .{ .kind = .return_value, .operand = helper_value.index },
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        },
        .{
            .symbol_name = "dead_structured_helper",
            .value_codec = .product,
            .value_schema_index = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 1,
            .local_count = 1,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 2,
            .instruction_count = 1,
        },
    };
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "abort", .first_op = 0, .op_count = 1 }};
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "abort",
        .mode = .abort,
        .payload_codec = .unit,
        .resume_codec = .unit,
    }};
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_value },
    };
    const schema = supportSchemaTables(.product);
    return program_plan.program_plan_builder.finish(.{
        .label = "abort-before-structured-helper",
        .ir_hash = 109,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .locals = &.{ .{ .codec = .product, .schema_index = 0 }, .{ .codec = .product, .schema_index = 0 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportErrorBeforeStructuredHelperPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const error_helper = program_plan.program_plan_builder.function(1);
    const structured_helper = program_plan.program_plan_builder.function(2);
    const root_value = program_plan.program_plan_builder.local(root, 0);
    const helper_value = program_plan.program_plan_builder.local(structured_helper, 0);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callHelperDiscardingResult(root, std.math.maxInt(u16), error_helper, null),
        program_plan.program_plan_builder.callHelper(root, root_value, structured_helper, null) catch |err| supportPlanError(err),
        .{ .kind = .return_error, .string_literal = "Rejected" },
        .{ .kind = .return_value, .operand = helper_value.index },
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        },
        .{
            .symbol_name = "error_helper",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 1,
            .local_count = 0,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 2,
            .instruction_count = 1,
        },
        .{
            .symbol_name = "dead_structured_helper",
            .value_codec = .product,
            .value_schema_index = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 1,
            .local_count = 1,
            .first_block = 2,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 3,
            .instruction_count = 1,
        },
    };
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 1, .terminator_index = 1 },
        .{ .first_instruction = 3, .instruction_count = 1, .terminator_index = 2 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
        .{ .kind = .return_value },
    };
    const schema = supportSchemaTables(.product);
    return program_plan.program_plan_builder.finish(.{
        .label = "error-before-structured-helper",
        .ir_hash = 113,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .locals = &.{ .{ .codec = .product, .schema_index = 0 }, .{ .codec = .product, .schema_index = 0 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportAbortBeforeStructuredSuccessorPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const helper = program_plan.program_plan_builder.function(1);
    const root_value = program_plan.program_plan_builder.local(root, 0);
    const helper_value = program_plan.program_plan_builder.local(helper, 0);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callOp(root, null, program_plan.program_plan_builder.op(root, 0), null) catch |err| supportPlanError(err),
        program_plan.program_plan_builder.callHelper(root, root_value, helper, null) catch |err| supportPlanError(err),
        .{ .kind = .return_value, .operand = helper_value.index },
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 2,
            .first_instruction = 0,
            .instruction_count = 2,
        },
        .{
            .symbol_name = "dead_structured_helper",
            .value_codec = .product,
            .value_schema_index = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 1,
            .local_count = 1,
            .first_block = 2,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 2,
            .instruction_count = 1,
        },
    };
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "abort", .first_op = 0, .op_count = 1 }};
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "abort",
        .mode = .abort,
        .payload_codec = .unit,
        .resume_codec = .unit,
    }};
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
        .{ .first_instruction = 2, .instruction_count = 1, .terminator_index = 2 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .jump, .primary = 1 },
        .{ .kind = .return_unit },
        .{ .kind = .return_value },
    };
    const schema = supportSchemaTables(.product);
    return program_plan.program_plan_builder.finish(.{
        .label = "abort-before-structured-successor",
        .ir_hash = 110,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .locals = &.{ .{ .codec = .product, .schema_index = 0 }, .{ .codec = .product, .schema_index = 0 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportStructuredTerminalHelperResultPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const helper = program_plan.program_plan_builder.function(1);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callHelperDiscardingResult(root, std.math.maxInt(u16), helper, null),
        program_plan.program_plan_builder.callOp(helper, null, program_plan.program_plan_builder.op(helper, 0), null) catch |err| supportPlanError(err),
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        },
        .{
            .symbol_name = "structured_terminal_helper",
            .value_codec = .unit,
            .result_codec = .product,
            .result_schema_index = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 1,
            .instruction_count = 1,
        },
    };
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "abort", .first_op = 0, .op_count = 1 }};
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "abort",
        .mode = .abort,
        .payload_codec = .unit,
        .resume_codec = .unit,
    }};
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
    };
    const schema = supportSchemaTables(.product);
    return program_plan.program_plan_builder.finish(.{
        .label = "structured-terminal-helper-result",
        .ir_hash = 111,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

fn supportStructuredAfterHelperResultPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const helper = program_plan.program_plan_builder.function(1);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callHelperDiscardingResult(root, std.math.maxInt(u16), helper, null),
        program_plan.program_plan_builder.callOp(helper, null, program_plan.program_plan_builder.op(helper, 0), null) catch |err| supportPlanError(err),
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        },
        .{
            .symbol_name = "structured_after_helper",
            .value_codec = .unit,
            .result_codec = .product,
            .result_schema_index = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 1,
            .instruction_count = 1,
        },
    };
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "after", .first_op = 0, .op_count = 1 }};
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "after",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .unit,
        .has_after = true,
    }};
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
    };
    const schema = supportSchemaTables(.product);
    return program_plan.program_plan_builder.finish(.{
        .label = "structured-after-helper-result",
        .ir_hash = 112,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = schema.schemas,
        .value_fields = schema.fields,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| supportPlanError(err);
}

test "ability.program executable support accepts scalar entry codecs" {
    inline for (.{ program_plan.ValueCodec.unit, .bool, .i32, .usize, .string }) |codec| {
        try validateExecutablePlanSupport(supportResultPlan(codec));
    }
}

test "ability.program executable support rejects structured result codecs" {
    inline for (.{ program_plan.ValueCodec.product, .sum, .string_list }) |codec| {
        try std.testing.expectError(error.UnsupportedResultCodec, validateExecutablePlanSupport(supportResultPlan(codec)));
    }
}

test "ability.program executable support rejects structured terminal helper result codecs" {
    try std.testing.expectError(error.UnsupportedResultCodec, validateExecutablePlanSupport(supportStructuredTerminalHelperResultPlan()));
}

test "ability.program executable support rejects structured after helper result codecs" {
    try std.testing.expectError(error.UnsupportedResultCodec, validateExecutablePlanSupport(supportStructuredAfterHelperResultPlan()));
}

test "ability.program executable support rejects structured entry parameter codecs" {
    inline for (.{ program_plan.ValueCodec.product, .sum, .string_list }) |codec| {
        try std.testing.expectError(error.UnsupportedParameterCodec, validateExecutablePlanSupport(supportParameterPlan(codec)));
    }
}

test "ability.program executable support rejects structured helper parameter codecs" {
    try std.testing.expectError(error.UnsupportedParameterCodec, validateExecutablePlanSupport(supportStructuredHelperParameterPlan()));
}

test "ability.program executable support rejects structured op payload codecs" {
    inline for (.{ program_plan.ValueCodec.product, .sum, .string_list }) |codec| {
        try std.testing.expectError(error.UnsupportedPayloadCodec, validateExecutablePlanSupport(supportOpPlan(codec, .unit)));
    }
}

test "ability.program executable support rejects structured op resume codecs" {
    inline for (.{ program_plan.ValueCodec.product, .sum, .string_list }) |codec| {
        try std.testing.expectError(error.UnsupportedResumeCodec, validateExecutablePlanSupport(supportOpPlan(.unit, codec)));
    }
}

test "ability.program executable support rejects nested-with, reachable structured locals, and helper cycles" {
    try std.testing.expectError(error.UnsupportedNestedWith, validateExecutablePlanSupport(supportNestedWithPlan()));
    try std.testing.expectError(error.UnsupportedLocalCodec, validateExecutablePlanSupport(supportStructuredHelperLocalPlan()));
    try std.testing.expectError(error.UnsupportedHelperCycle, validateExecutablePlanSupport(supportHelperCyclePlan()));
}

test "ability.program executable capability ledger records unresolved nested-with blockers" {
    const ledger = ExecutableCapabilityLedgerForPlan(supportNestedWithPlan(), &.{}, &.{});
    try std.testing.expectEqual(@as(usize, 1), ledger.blockers.len);
    try std.testing.expectEqual(CapabilityBlockerTag.nested_with_unresolved, ledger.blockers[0].tag);
    try std.testing.expectEqual(@as(u16, 0), ledger.blockers[0].function_index);
    try std.testing.expectEqual(@as(u32, 0), ledger.blockers[0].instruction_index);
    try std.testing.expect(!ledger.truncated);
}

test "ability.program executable capability ledger does not block typed helper recursion" {
    try validateTypedExecutablePlanSupport(supportHelperCyclePlan(), &.{});

    const ledger = ExecutableCapabilityLedgerForPlan(supportHelperCyclePlan(), &.{}, &.{});
    try std.testing.expectEqual(@as(usize, 0), ledger.blockers.len);
    try std.testing.expect(!ledger.truncated);
}

test "ability.program executable capability ledger caps blocker records" {
    const ledger = ExecutableCapabilityLedgerForPlan(supportManyNestedWithPlan(max_capability_blockers + 1), &.{}, &.{});
    try std.testing.expectEqual(@as(usize, max_capability_blockers), ledger.blockers.len);
    try std.testing.expect(ledger.truncated);
}

test "ability.program executable support validates resolver-backed nested target bodies" {
    const targets = [_]NestedWithTarget{.{
        .metadata = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi",
        .function_index = 1,
    }};
    try std.testing.expectError(
        error.UnsupportedPayloadCodec,
        validateTypedExecutablePlanSupportWithNestedTargets(supportNestedWithStructuredTargetPlan(), &.{}, &targets),
    );
    const ledger = ExecutableCapabilityLedgerForPlan(supportNestedWithStructuredTargetPlan(), &.{}, &targets);
    try std.testing.expectEqual(CapabilityBlockerTag.payload_codec, ledger.blockers[0].tag);
}

test "ability.program executable support rejects terminal nested target result mismatches" {
    const targets = [_]NestedWithTarget{.{
        .metadata = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi",
        .function_index = 1,
    }};
    try std.testing.expectError(
        error.UnsupportedResultCodec,
        validateTypedExecutablePlanSupportWithNestedTargets(supportNestedWithTerminalResultMismatchPlan(), &.{}, &targets),
    );
    const ledger = ExecutableCapabilityLedgerForPlan(supportNestedWithTerminalResultMismatchPlan(), &.{}, &targets);
    try std.testing.expectEqual(CapabilityBlockerTag.nested_with_result_codec, ledger.blockers[0].tag);
}

test "ability.program executable support ignores unreachable structured helper metadata" {
    try validateExecutablePlanSupport(supportUnreachableStructuredHelperPlan());
}

test "ability.program executable support ignores post-terminal structured helper metadata" {
    try validateExecutablePlanSupport(supportAbortBeforeStructuredHelperPlan());
    try validateExecutablePlanSupport(supportAbortBeforeStructuredSuccessorPlan());
    try validateExecutablePlanSupport(supportErrorBeforeStructuredHelperPlan());
}
