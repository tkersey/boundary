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
pub const SessionBlockerTag = enum {
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
pub const SessionBlocker = struct {
    tag: SessionBlockerTag,
    function_index: u16 = std.math.maxInt(u16),
    instruction_index: u32 = std.math.maxInt(u32),
    op_index: u16 = std.math.maxInt(u16),
    codec: ValueCodec = .unit,
};
pub const ExecutablePlanSupportError = error{
    UnsupportedHelperCycle,
    UnsupportedNestedWith,
    UnsupportedAfterHook,
    UnsupportedResultCodec,
    UnsupportedParameterCodec,
    UnsupportedPayloadCodec,
    UnsupportedResumeCodec,
    UnsupportedLocalCodec,
};
pub const SessionPlanSupportError = error{
    UnsupportedSessionPlan,
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

fn appendSessionBlocker(
    comptime blockers: *[max_capability_blockers]SessionBlocker,
    comptime count: *usize,
    comptime truncated: *bool,
    comptime blocker: SessionBlocker,
) void {
    if (count.* == max_capability_blockers) {
        truncated.* = true;
        return;
    }
    blockers[count.*] = blocker;
    count.* += 1;
}

fn sessionBlockerTagForCapability(comptime tag: CapabilityBlockerTag) SessionBlockerTag {
    return switch (tag) {
        .helper_cycle => .helper_cycle,
        .nested_with_unresolved => .nested_with_unresolved,
        .nested_with_target_has_parameters => .nested_with_target_has_parameters,
        .nested_with_result_codec => .nested_with_result_codec,
        .result_codec => .result_codec,
        .parameter_codec => .parameter_codec,
        .payload_codec => .payload_codec,
        .resume_codec => .resume_codec,
        .local_codec => .local_codec,
    };
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
                    if (!executableTypedRef(schema_types, .{ .codec = result_codec }) or
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
        pub const blockers = data.items;
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

pub fn SessionCapabilityLedgerForPlan(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
) type {
    const data = comptime blk: {
        var blockers: [max_capability_blockers]SessionBlocker = undefined;
        var count: usize = 0;
        var truncated = false;
        _ = program_plan.entryExecutionAnalysisWithNestedTargets(compiled_plan, nested_with_targets) catch {
            appendSessionBlocker(&blockers, &count, &truncated, .{ .tag = .local_codec });
            break :blk .{ .items = blockers[0..count].*, .truncated = truncated };
        };
        break :blk .{ .items = blockers[0..count].*, .truncated = truncated };
    };
    return struct {
        pub const blockers = data.items;
        pub const truncated = data.truncated;
    };
}

pub fn TypedSessionCapabilityLedgerForPlan(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
) type {
    const data = comptime blk: {
        var blockers: [max_capability_blockers]SessionBlocker = undefined;
        var count: usize = 0;
        var truncated = false;
        const executable_ledger = ExecutableCapabilityLedgerForPlan(compiled_plan, schema_types, nested_with_targets);
        for (executable_ledger.blockers) |blocker| {
            appendSessionBlocker(&blockers, &count, &truncated, .{
                .tag = sessionBlockerTagForCapability(blocker.tag),
                .function_index = blocker.function_index,
                .instruction_index = blocker.instruction_index,
                .codec = blocker.codec,
            });
        }
        const session_ledger = SessionCapabilityLedgerForPlan(compiled_plan, nested_with_targets);
        for (session_ledger.blockers) |blocker| {
            appendSessionBlocker(&blockers, &count, &truncated, blocker);
        }
        break :blk .{ .items = blockers[0..count].*, .truncated = truncated or executable_ledger.truncated or session_ledger.truncated };
    };
    return struct {
        pub const blockers = data.items;
        pub const truncated = data.truncated;
    };
}

pub fn sessionCapabilitySummary(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
) []const u8 {
    const ledger = SessionCapabilityLedgerForPlan(compiled_plan, nested_with_targets);
    if (ledger.blockers.len == 0) return "session capability ledger: blockers=0 truncated=false";
    const first = ledger.blockers[0];
    return std.fmt.comptimePrint(
        "session capability ledger: blockers={d} truncated={} cap={d} first_tag={s} first_function={d} first_instruction={d} first_op={d}",
        .{
            ledger.blockers.len,
            ledger.truncated,
            max_capability_blockers,
            @tagName(first.tag),
            first.function_index,
            first.instruction_index,
            first.op_index,
        },
    );
}

pub fn typedSessionCapabilitySummary(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
) []const u8 {
    const ledger = TypedSessionCapabilityLedgerForPlan(compiled_plan, schema_types, nested_with_targets);
    if (ledger.blockers.len == 0) return "session capability ledger: blockers=0 truncated=false";
    const first = ledger.blockers[0];
    return std.fmt.comptimePrint(
        "session capability ledger: blockers={d} truncated={} cap={d} first_tag={s} first_function={d} first_instruction={d} first_op={d}",
        .{
            ledger.blockers.len,
            ledger.truncated,
            max_capability_blockers,
            @tagName(first.tag),
            first.function_index,
            first.instruction_index,
            first.op_index,
        },
    );
}

pub fn validateSessionPlanSupportWithNestedTargets(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
) SessionPlanSupportError!void {
    comptime {
        const ledger = SessionCapabilityLedgerForPlan(compiled_plan, nested_with_targets);
        if (ledger.blockers.len != 0) return error.UnsupportedSessionPlan;
    }
}

pub fn validateTypedSessionExecutablePlanSupportWithNestedTargets(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
) ExecutablePlanSupportError!void {
    try validateTypedExecutablePlanSupportWithNestedTargets(compiled_plan, schema_types, nested_with_targets);
    validateSessionPlanSupportWithNestedTargets(compiled_plan, nested_with_targets) catch return error.UnsupportedLocalCodec;
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
                .sum_variant_is, .sum_extract_payload => return error.UnsupportedLocalCodec,
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
                    if (!executableTypedRef(schema_types, .{ .codec = result_codec })) return error.UnsupportedResultCodec;
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
                .sum_variant_is => {
                    const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return error.UnsupportedLocalCodec;
                    if (!instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.dst) or
                        !instructionLocalHasExecutableTypedRef(compiled_plan, schema_types, owner, instruction.operand))
                    {
                        return error.UnsupportedLocalCodec;
                    }
                },
                .sum_extract_payload => {
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

pub fn executablePlanNeedsBodyValueSchemaTypes(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime nested_with_targets: anytype,
) bool {
    comptime {
        const analysis = program_plan.entryExecutionAnalysisWithNestedTargets(compiled_plan, nested_with_targets) catch return false;
        const entry = compiled_plan.functions[compiled_plan.entry_index];
        if (valueRefNeedsSchemaTypes(program_plan.functionResultRef(entry))) return true;

        for (compiled_plan.functions, 0..) |function, function_index| {
            if (!analysis.reachable_functions[function_index]) continue;
            for (0..function.parameter_count) |parameter_index| {
                const local = compiled_plan.locals[function.first_local + parameter_index];
                if (valueRefNeedsSchemaTypes(.{ .codec = local.codec, .schema_index = local.schema_index })) return true;
            }
            if ((analysis.terminal_functions[function_index] or analysis.after_result_functions[function_index]) and
                valueRefNeedsSchemaTypes(program_plan.functionResultRef(function)))
            {
                return true;
            }
        }

        for (compiled_plan.instructions, 0..) |instruction, instruction_index| {
            if (!analysis.reachable_instructions[instruction_index]) continue;
            const owner = instructionOwnerFunction(compiled_plan, instruction_index) orelse return false;
            switch (instruction.kind) {
                .call_nested_with => {
                    const target_index = nestedWithTargetIndexForMetadata(compiled_plan, nested_with_targets, instruction.string_literal) orelse continue;
                    const target = compiled_plan.functions[target_index];
                    const result_codec = program_plan.valueCodecFromInstructionAux(instruction.aux) catch continue;
                    if (structuredSchemaCodec(result_codec)) return true;
                    const completion_ref = effectiveCompletionRefForFunction(analysis, target, target_index);
                    if (valueRefNeedsSchemaTypes(completion_ref)) return true;
                    if (result_codec != .unit) {
                        const local_ref = functionLocalRef(compiled_plan, owner, instruction.dst) orelse return false;
                        if (valueRefNeedsSchemaTypes(local_ref)) return true;
                    }
                },
                .call_op => {
                    const op = compiled_plan.ops[instruction.operand];
                    if (valueRefNeedsSchemaTypes(.{ .codec = op.payload_codec, .schema_index = op.payload_schema_index }) or
                        valueRefNeedsSchemaTypes(.{ .codec = op.resume_codec, .schema_index = op.resume_schema_index }))
                    {
                        return true;
                    }
                },
                .call_helper => {
                    const callee = compiled_plan.functions[instruction.operand];
                    for (0..callee.parameter_count) |arg_index| {
                        const local_id = planCallArgAt(compiled_plan, instruction.aux + arg_index);
                        const local_ref = functionLocalRef(compiled_plan, owner, local_id) orelse return false;
                        if (valueRefNeedsSchemaTypes(local_ref)) return true;
                    }
                    if (program_plan.functionResultCodec(callee) != .unit and instruction.dst != std.math.maxInt(u16)) {
                        const local_ref = functionLocalRef(compiled_plan, owner, instruction.dst) orelse return false;
                        if (valueRefNeedsSchemaTypes(local_ref)) return true;
                    }
                },
                .return_value => {
                    const local_ref = functionLocalRef(compiled_plan, owner, instruction.operand) orelse return false;
                    if (valueRefNeedsSchemaTypes(local_ref)) return true;
                },
                .sum_extract_payload, .sum_variant_is => {
                    const source_ref = functionLocalRef(compiled_plan, owner, instruction.operand) orelse return false;
                    const dst_ref = functionLocalRef(compiled_plan, owner, instruction.dst) orelse return false;
                    if (valueRefNeedsSchemaTypes(source_ref) or valueRefNeedsSchemaTypes(dst_ref)) return true;
                },
                .add_const_i32, .add_i32, .compare_eq_zero, .const_i32, .const_string, .const_usize, .return_error, .sub_one => {},
            }
        }

        return false;
    }
}

fn executableScalarCodec(comptime codec: program_plan.ValueCodec) bool {
    return switch (codec) {
        .unit, .bool, .i32, .usize, .string => true,
        .product, .sum, .string_list => false,
    };
}

fn structuredSchemaCodec(comptime codec: program_plan.ValueCodec) bool {
    return switch (codec) {
        .product, .sum => true,
        .unit, .bool, .i32, .usize, .string, .string_list => false,
    };
}

fn valueRefNeedsSchemaTypes(comptime ref: program_plan.ValueRef) bool {
    return structuredSchemaCodec(ref.codec);
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

/// Stable version tag mixed into Program.Session trace fingerprints.
pub const trace_fingerprint_version: u32 = 1;

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

fn maxSchemaValueSize(comptime schema_types: anytype) comptime_int {
    var max_size: comptime_int = 0;
    inline for (schema_types) |SchemaType| {
        if (@sizeOf(SchemaType) > max_size) max_size = @sizeOf(SchemaType);
    }
    return max_size;
}

fn maxSchemaValueAlign(comptime schema_types: anytype) comptime_int {
    var max_align: comptime_int = 1;
    inline for (schema_types) |SchemaType| {
        if (@alignOf(SchemaType) > max_align) max_align = @alignOf(SchemaType);
    }
    return max_align;
}

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

fn isStringListCarrier(comptime T: type) bool {
    return T == []const []const u8 or T == [][]const u8;
}

fn typeMatchesRef(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime ref: program_plan.ValueRef,
    comptime T: type,
) bool {
    return switch (ref.codec) {
        .string_list => isStringListCarrier(T),
        else => T == ValueTypeForRef(compiled_plan, schema_types, ref),
    };
}

fn typeMatchesRuntimeRef(
    comptime schema_types: anytype,
    ref: program_plan.ValueRef,
    comptime T: type,
) bool {
    if (T == void) return ref.eql(.{ .codec = .unit });
    if (T == bool) return ref.eql(.{ .codec = .bool });
    if (T == i32) return ref.eql(.{ .codec = .i32 });
    if (T == usize) return ref.eql(.{ .codec = .usize });
    if (T == []const u8) return ref.eql(.{ .codec = .string });
    if (comptime isStringListCarrier(T)) return ref.eql(.{ .codec = .string_list });
    const structured_codec: program_plan.ValueCodec = switch (@typeInfo(T)) {
        .@"struct" => .product,
        .@"enum", .@"union", .optional => .sum,
        else => return false,
    };
    if (ref.codec != structured_codec) return false;
    const schema_index = ref.schema_index orelse return false;
    inline for (schema_types, 0..) |SchemaType, index| {
        if (schema_index == index) return SchemaType == T;
    }
    return false;
}

fn encodeScalarValue(value: anytype) ExecutableValue {
    if (comptime isStringListCarrier(@TypeOf(value))) return .{ .string_list = value };
    return switch (@TypeOf(value)) {
        void => .none,
        bool => .{ .bool = value },
        i32 => .{ .i32 = value },
        usize => .{ .usize = value },
        []const u8 => .{ .string = value },
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
    if (isStringListCarrier(T)) return .{ .codec = .string_list };
    const schema_index = schemaIndexForType(schema_types, T) orelse
        @compileError("authored structured value type is not present in Body.value_schema_types: " ++ @typeName(T));
    return switch (@typeInfo(T)) {
        .@"struct" => .{ .codec = .product, .schema_index = schema_index },
        .@"enum", .@"union", .optional => .{ .codec = .sum, .schema_index = schema_index },
        else => @compileError("unsupported authored value type: " ++ @typeName(T)),
    };
}

fn runtimeValueRefForType(comptime schema_types: anytype, comptime T: type) ?program_plan.ValueRef {
    if (T == void) return .{ .codec = .unit };
    if (T == bool) return .{ .codec = .bool };
    if (T == i32) return .{ .codec = .i32 };
    if (T == usize) return .{ .codec = .usize };
    if (T == []const u8) return .{ .codec = .string };
    if (isStringListCarrier(T)) return .{ .codec = .string_list };
    const schema_index = schemaIndexForType(schema_types, T) orelse return null;
    return switch (@typeInfo(T)) {
        .@"struct" => .{ .codec = .product, .schema_index = schema_index },
        .@"enum", .@"union", .optional => .{ .codec = .sum, .schema_index = schema_index },
        else => null,
    };
}

fn ReturnPayloadType(comptime ReturnType: type) type {
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.payload,
        else => ReturnType,
    };
}

fn CallableReturnPayloadType(comptime callable: anytype) type {
    return ReturnPayloadType(@typeInfo(@TypeOf(callable)).@"fn".return_type.?);
}

fn runtimeTypeNeedsSchemaStorage(comptime schema_types: anytype, comptime T: type) bool {
    const ref = runtimeValueRefForType(schema_types, T) orelse return false;
    return structuredSchemaCodec(ref.codec);
}

fn PreparedRuntimeValue(comptime T: type, comptime structured: bool) type {
    return struct {
        schema_index: u16 = 0,
        ptr: ?*T = null,

        fn encode(self: @This(), value: T) ExecutableValue {
            if (comptime structured) {
                const ptr = self.ptr.?;
                ptr.* = value;
                return .{ .schema = .{
                    .schema_index = self.schema_index,
                    .ptr = ptr,
                } };
            }
            return encodeScalarValue(value);
        }
    };
}

fn prepareRuntimeValueForRef(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime ref: program_plan.ValueRef,
    scratch: anytype,
) std.mem.Allocator.Error!PreparedRuntimeValue(
    ValueTypeForRef(compiled_plan, schema_types, ref),
    structuredSchemaCodec(ref.codec),
) {
    const Expected = ValueTypeForRef(compiled_plan, schema_types, ref);
    return switch (comptime ref.codec) {
        .unit, .bool, .i32, .usize, .string, .string_list => .{},
        .product, .sum => .{
            .schema_index = ref.schema_index orelse @compileError("structured ValueRef is missing a schema index"),
            .ptr = try scratch.reserveSchemaValueStorage(
                Expected,
            ),
        },
    };
}

fn prepareRuntimeValueForType(
    comptime schema_types: anytype,
    scratch: anytype,
    comptime T: type,
) anyerror!struct {
    value: PreparedRuntimeValue(T, runtimeTypeNeedsSchemaStorage(schema_types, T)),
    ref: program_plan.ValueRef,
} {
    const ref = comptime runtimeValueRefForType(schema_types, T) orelse return error.ProgramContractViolation;
    return switch (comptime ref.codec) {
        .unit, .bool, .i32, .usize, .string, .string_list => .{ .value = .{}, .ref = ref },
        .product, .sum => .{
            .value = .{
                .schema_index = ref.schema_index orelse @compileError("structured ValueRef is missing a schema index"),
                .ptr = try scratch.reserveSchemaValueStorage(
                    T,
                ),
            },
            .ref = ref,
        },
    };
}

fn encodeRuntimeValueForRuntimeRef(
    comptime schema_types: anytype,
    ref: program_plan.ValueRef,
    scratch: anytype,
    value: anytype,
) anyerror!ExecutableValue {
    const Value = @TypeOf(value);
    if (!typeMatchesRuntimeRef(schema_types, ref, Value)) return error.ProgramContractViolation;
    if (comptime Value == void or Value == bool or Value == i32 or Value == usize or Value == []const u8 or isStringListCarrier(Value)) {
        return encodeScalarValue(value);
    }
    return scratch.storeSchemaValue(
        Value,
        ref.schema_index orelse return error.ProgramContractViolation,
        value,
    );
}

fn decodeRuntimeValueAs(
    comptime schema_types: anytype,
    ref: program_plan.ValueRef,
    value: ExecutableValue,
    comptime T: type,
) error{ProgramContractViolation}!T {
    if (!typeMatchesRuntimeRef(schema_types, ref, T)) return error.ProgramContractViolation;
    if (T == void) return switch (value) {
        .none => {},
        else => error.ProgramContractViolation,
    };
    if (T == bool) return switch (value) {
        .bool => |typed| typed,
        else => error.ProgramContractViolation,
    };
    if (T == i32) return switch (value) {
        .i32 => |typed| typed,
        else => error.ProgramContractViolation,
    };
    if (T == usize) return switch (value) {
        .usize => |typed| typed,
        else => error.ProgramContractViolation,
    };
    if (T == []const u8) return switch (value) {
        .string => |typed| typed,
        else => error.ProgramContractViolation,
    };
    if (T == []const []const u8) return switch (value) {
        .string_list => |typed| typed,
        else => error.ProgramContractViolation,
    };
    if (T == [][]const u8) return error.ProgramContractViolation;
    const schema_index = ref.schema_index orelse return error.ProgramContractViolation;
    const expected_codec: program_plan.ValueCodec = comptime switch (@typeInfo(T)) {
        .@"struct" => .product,
        .@"enum", .@"union", .optional => .sum,
        else => return error.ProgramContractViolation,
    };
    if (ref.codec != expected_codec) return error.ProgramContractViolation;
    return switch (value) {
        .schema => |schema| blk: {
            if (schema.schema_index != schema_index) return error.ProgramContractViolation;
            const typed: *const T = @ptrCast(@alignCast(schema.ptr));
            break :blk typed.*;
        },
        else => error.ProgramContractViolation,
    };
}

fn encodeRuntimeValueForPreparedRef(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime ref: program_plan.ValueRef,
    prepared: anytype,
    value: anytype,
) anyerror!ExecutableValue {
    if (comptime !typeMatchesRef(compiled_plan, schema_types, ref, @TypeOf(value))) return error.ProgramContractViolation;
    return prepared.encode(value);
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
    if (comptime isStringListCarrier(Value)) return .{ .value = .{ .string_list = value }, .ref = .{ .codec = .string_list } };
    return switch (Value) {
        void => .{ .value = .none, .ref = .{ .codec = .unit } },
        bool => .{ .value = .{ .bool = value }, .ref = .{ .codec = .bool } },
        i32 => .{ .value = .{ .i32 = value }, .ref = .{ .codec = .i32 } },
        usize => .{ .value = .{ .usize = value }, .ref = .{ .codec = .usize } },
        []const u8 => .{ .value = .{ .string = value }, .ref = .{ .codec = .string } },
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

fn activeVariantOrdinalForTyped(
    comptime T: type,
    value: T,
) error{ProgramContractViolation}!u16 {
    return switch (@typeInfo(T)) {
        .@"enum" => |enum_info| {
            inline for (enum_info.fields, 0..) |field, field_index| {
                if (value == @field(T, field.name)) return @intCast(field_index);
            }
            return error.ProgramContractViolation;
        },
        .@"union" => |union_info| {
            const Tag = union_info.tag_type orelse return error.ProgramContractViolation;
            const active = std.meta.activeTag(value);
            inline for (union_info.fields, 0..) |field, field_index| {
                if (active == @field(Tag, field.name)) return @intCast(field_index);
            }
            return error.ProgramContractViolation;
        },
        .optional => if (value == null) 0 else 1,
        else => error.ProgramContractViolation,
    };
}

fn activeVariantOrdinalForExecutable(
    comptime schema_types: anytype,
    value: ExecutableValue,
) error{ProgramContractViolation}!u16 {
    const schema = switch (value) {
        .schema => |typed| typed,
        else => return error.ProgramContractViolation,
    };
    inline for (schema_types, 0..) |SchemaType, schema_index| {
        if (schema.schema_index == schema_index) {
            const typed: *const SchemaType = @ptrCast(@alignCast(schema.ptr));
            return activeVariantOrdinalForTyped(SchemaType, typed.*);
        }
    }
    return error.ProgramContractViolation;
}

fn extractVariantPayloadForTyped(
    comptime schema_types: anytype,
    ref: program_plan.ValueRef,
    scratch: anytype,
    comptime T: type,
    value: T,
    variant_ordinal: u16,
) anyerror!RuntimeValueWithRef {
    const active = try activeVariantOrdinalForTyped(T, value);
    if (active != variant_ordinal) return error.ProgramContractViolation;
    return switch (@typeInfo(T)) {
        .@"union" => |union_info| {
            inline for (union_info.fields, 0..) |field, field_index| {
                if (variant_ordinal == field_index) {
                    if (field.type == void) return error.ProgramContractViolation;
                    return .{
                        .value = try encodeRuntimeValueForRuntimeRef(schema_types, ref, scratch, @field(value, field.name)),
                        .ref = ref,
                    };
                }
            }
            return error.ProgramContractViolation;
        },
        .optional => |optional_info| {
            _ = optional_info;
            if (variant_ordinal != 1) return error.ProgramContractViolation;
            return .{
                .value = try encodeRuntimeValueForRuntimeRef(schema_types, ref, scratch, value.?),
                .ref = ref,
            };
        },
        else => error.ProgramContractViolation,
    };
}

fn extractVariantPayloadForExecutable(
    comptime schema_types: anytype,
    ref: program_plan.ValueRef,
    scratch: anytype,
    value: ExecutableValue,
    variant_ordinal: u16,
) anyerror!RuntimeValueWithRef {
    const schema = switch (value) {
        .schema => |typed| typed,
        else => return error.ProgramContractViolation,
    };
    inline for (schema_types, 0..) |SchemaType, schema_index| {
        if (schema.schema_index == schema_index) {
            const typed: *const SchemaType = @ptrCast(@alignCast(schema.ptr));
            return extractVariantPayloadForTyped(schema_types, ref, scratch, SchemaType, typed.*, variant_ordinal);
        }
    }
    return error.ProgramContractViolation;
}

fn encodeRuntimeValueForRef(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime ref: program_plan.ValueRef,
    scratch: anytype,
    value: anytype,
) anyerror!ExecutableValue {
    if (comptime !typeMatchesRef(compiled_plan, schema_types, ref, @TypeOf(value))) return error.ProgramContractViolation;
    const Expected = ValueTypeForRef(compiled_plan, schema_types, ref);
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

        fn reserveSchemaValueStorage(self: *@This(), comptime T: type) std.mem.Allocator.Error!*T {
            const typed = try self.allocator.create(T);
            errdefer self.allocator.destroy(typed);
            try self.owned_schema_values.append(self.allocator, .{
                .ptr = typed,
                .destroy = SchemaDestroyer(T).destroy,
            });
            return typed;
        }

        fn storeSchemaValue(self: *@This(), comptime T: type, schema_index: u16, value: T) std.mem.Allocator.Error!ExecutableValue {
            const typed = try self.reserveSchemaValueStorage(T);
            typed.* = value;
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

fn constI32Value(instruction: program_plan.Instruction) error{ProgramContractViolation}!i32 {
    if (instruction.string_literal.len != 0) {
        return std.fmt.parseInt(i32, instruction.string_literal, 0) catch error.ProgramContractViolation;
    }
    return @intCast(instruction.operand);
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
    return typeMatchesRef(compiled_plan, schema_types, input_ref, ValueParamType);
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
    return switch (comptime op.mode) {
        .abort => blk: {
            const output = try prepareRuntimeValueForRef(compiled_plan, schema_types, terminal_ref, scratch);
            const dispatched = if (comptime op.payload_codec == .unit)
                try authored.dispatch()
            else
                try authored.dispatch(try decodeTypedValue(compiled_plan, schema_types, payload_ref, payload));
            break :blk .{
                .value = try encodeRuntimeValueForPreparedRef(compiled_plan, schema_types, terminal_ref, output, dispatched),
                .resumes = false,
            };
        },
        .transform => blk: {
            const output = try prepareRuntimeValueForRef(compiled_plan, schema_types, resume_ref, scratch);
            const dispatched = if (comptime op.payload_codec == .unit)
                try authored.dispatch()
            else
                try authored.dispatch(try decodeTypedValue(compiled_plan, schema_types, payload_ref, payload));
            break :blk .{
                .value = try encodeRuntimeValueForPreparedRef(compiled_plan, schema_types, resume_ref, output, dispatched),
                .resumes = true,
            };
        },
        .choice => blk: {
            const resume_output = try prepareRuntimeValueForRef(compiled_plan, schema_types, resume_ref, scratch);
            const terminal_output = try prepareRuntimeValueForRef(compiled_plan, schema_types, terminal_ref, scratch);
            const dispatched = if (comptime op.payload_codec == .unit)
                try authored.dispatch()
            else
                try authored.dispatch(try decodeTypedValue(compiled_plan, schema_types, payload_ref, payload));
            break :blk switch (dispatched) {
                .resume_with => |resume_value| .{
                    .value = try encodeRuntimeValueForPreparedRef(compiled_plan, schema_types, resume_ref, resume_output, resume_value),
                    .resumes = true,
                },
                .return_now => |answer| .{
                    .value = try encodeRuntimeValueForPreparedRef(compiled_plan, schema_types, terminal_ref, terminal_output, answer),
                    .resumes = false,
                },
            };
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

fn AfterDispatchHandlerType(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime op: program_plan.OpPlan,
    comptime HandlersPtr: type,
) type {
    const requirement = comptime compiled_plan.requirements[op.requirement_index];
    const HandlerSet = HandlerSetType(HandlersPtr);
    return if (comptime @hasField(HandlerSet, requirement.label) and
        @hasDecl(HandlerType(@FieldType(HandlerSet, requirement.label)), "dispatch"))
        HandlerType(@FieldType(HandlerSet, requirement.label))
    else if (comptime @hasField(HandlerSet, requirement.label) and
        @hasField(HandlerSetType(@FieldType(HandlerSet, requirement.label)), op.op_name))
        HandlerType(@FieldType(HandlerSetType(@FieldType(HandlerSet, requirement.label)), op.op_name))
    else if (comptime @hasField(HandlerSet, requirement.label) and
        @hasField(HandlerSetType(@FieldType(HandlerSet, requirement.label)), "authored"))
        HandlerType(@FieldType(HandlerSetType(@FieldType(HandlerSet, requirement.label)), "authored"))
    else if (comptime @hasField(HandlerSet, op.op_name) and opNameIsUnique(compiled_plan, op.op_name))
        HandlerType(@FieldType(HandlerSet, op.op_name))
    else if (comptime @hasField(HandlerSet, "authored") and opNameIsUnique(compiled_plan, op.op_name))
        HandlerType(@FieldType(HandlerSet, "authored"))
    else
        @compileError("ProgramPlan op has no unambiguous handler field, requirement handler, or authored fallback");
}

fn hasAfterDispatchHandlerType(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime op: program_plan.OpPlan,
    comptime HandlersPtr: type,
) bool {
    const requirement = comptime compiled_plan.requirements[op.requirement_index];
    const HandlerSet = HandlerSetType(HandlersPtr);
    return if (comptime @hasField(HandlerSet, requirement.label) and
        @hasDecl(HandlerType(@FieldType(HandlerSet, requirement.label)), "dispatch"))
        @hasDecl(HandlerType(@FieldType(HandlerSet, requirement.label)), "afterDispatch")
    else if (comptime @hasField(HandlerSet, requirement.label) and
        @hasField(HandlerSetType(@FieldType(HandlerSet, requirement.label)), op.op_name))
        @hasDecl(HandlerType(@FieldType(HandlerSetType(@FieldType(HandlerSet, requirement.label)), op.op_name)), "afterDispatch")
    else if (comptime @hasField(HandlerSet, requirement.label) and
        @hasField(HandlerSetType(@FieldType(HandlerSet, requirement.label)), "authored"))
        @hasDecl(HandlerType(@FieldType(HandlerSetType(@FieldType(HandlerSet, requirement.label)), "authored")), "afterDispatch")
    else if (comptime @hasField(HandlerSet, op.op_name) and opNameIsUnique(compiled_plan, op.op_name))
        @hasDecl(HandlerType(@FieldType(HandlerSet, op.op_name)), "afterDispatch")
    else if (comptime @hasField(HandlerSet, "authored") and opNameIsUnique(compiled_plan, op.op_name))
        @hasDecl(HandlerType(@FieldType(HandlerSet, "authored")), "afterDispatch")
    else
        false;
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
            const output = try prepareRuntimeValueForRef(compiled_plan, schema_types, output_ref, scratch);
            const completed = try authored.afterDispatch(decoded);
            return .{
                .value = try encodeRuntimeValueForPreparedRef(compiled_plan, schema_types, output_ref, output, completed),
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
            const Value = CallableReturnPayloadType(HandlerType(@TypeOf(authored)).afterDispatch);
            var output = try prepareRuntimeValueForType(schema_types, scratch, Value);
            const completed = try authored.afterDispatch(decoded);
            return .{
                .value = output.value.encode(completed),
                .ref = output.ref,
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

fn sessionAfterOutputRefByIndex(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime HandlersType: type,
    op_index: u16,
    current_ref: program_plan.ValueRef,
    remaining: usize,
    final_ref: program_plan.ValueRef,
) anyerror!program_plan.ValueRef {
    if (remaining == 1) return final_ref;
    return switch (current_ref.codec) {
        .unit => sessionIntermediateAfterOutputRefByIndexForRef(.{ .codec = .unit }, compiled_plan, schema_types, HandlersType, op_index, final_ref),
        .bool => sessionIntermediateAfterOutputRefByIndexForRef(.{ .codec = .bool }, compiled_plan, schema_types, HandlersType, op_index, final_ref),
        .i32 => sessionIntermediateAfterOutputRefByIndexForRef(.{ .codec = .i32 }, compiled_plan, schema_types, HandlersType, op_index, final_ref),
        .usize => sessionIntermediateAfterOutputRefByIndexForRef(.{ .codec = .usize }, compiled_plan, schema_types, HandlersType, op_index, final_ref),
        .string => sessionIntermediateAfterOutputRefByIndexForRef(.{ .codec = .string }, compiled_plan, schema_types, HandlersType, op_index, final_ref),
        .string_list => sessionIntermediateAfterOutputRefByIndexForRef(.{ .codec = .string_list }, compiled_plan, schema_types, HandlersType, op_index, final_ref),
        .product => {
            inline for (schema_types, 0..) |_, schema_index| {
                if (current_ref.schema_index == @as(u16, @intCast(schema_index))) {
                    return sessionIntermediateAfterOutputRefByIndexForRef(
                        .{ .codec = .product, .schema_index = @intCast(schema_index) },
                        compiled_plan,
                        schema_types,
                        HandlersType,
                        op_index,
                        final_ref,
                    );
                }
            }
            return error.ProgramContractViolation;
        },
        .sum => {
            inline for (schema_types, 0..) |_, schema_index| {
                if (current_ref.schema_index == @as(u16, @intCast(schema_index))) {
                    return sessionIntermediateAfterOutputRefByIndexForRef(
                        .{ .codec = .sum, .schema_index = @intCast(schema_index) },
                        compiled_plan,
                        schema_types,
                        HandlersType,
                        op_index,
                        final_ref,
                    );
                }
            }
            return error.ProgramContractViolation;
        },
    };
}

fn sessionIntermediateAfterOutputRefByIndexForRef(
    comptime input_ref: program_plan.ValueRef,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime HandlersType: type,
    op_index: u16,
    final_ref: program_plan.ValueRef,
) anyerror!program_plan.ValueRef {
    inline for (compiled_plan.ops, 0..) |op, index| {
        if (op_index == index) {
            if (!op.has_after) return error.ProgramContractViolation;
            if (comptime !hasAfterDispatchHandlerType(compiled_plan, op, HandlersType)) {
                if (input_ref.eql(final_ref)) return final_ref;
                return error.ProgramContractViolation;
            }
            const Authored = AfterDispatchHandlerType(compiled_plan, op, HandlersType);
            if (comptime !afterDispatchAccepts(compiled_plan, schema_types, Authored, input_ref)) return error.ProgramContractViolation;
            const Value = CallableReturnPayloadType(Authored.afterDispatch);
            return runtimeValueRefForType(schema_types, Value) orelse error.ProgramContractViolation;
        }
    }
    return error.ProgramContractViolation;
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
                .sum_variant_is => {
                    const is_variant = (try activeVariantOrdinalForExecutable(schema_types, locals[instruction.operand])) == instruction.aux;
                    locals[instruction.dst] = .{ .bool = is_variant };
                    last_condition = is_variant;
                },
                .sum_extract_payload => {
                    const dst_ref = functionLocalRef(compiled_plan, function, instruction.dst) orelse return error.ProgramContractViolation;
                    const extracted = try extractVariantPayloadForExecutable(schema_types, dst_ref, scratch, locals[instruction.operand], instruction.aux);
                    if (!valueMatchesRef(dst_ref, extracted.value)) return error.ProgramContractViolation;
                    locals[instruction.dst] = extracted.value;
                },
                .const_i32 => locals[instruction.dst] = .{ .i32 = try constI32Value(instruction) },
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

const inline_active_frame_capacity = 16;

const ActiveFrameStack = struct {
    inline_buffer: [inline_active_frame_capacity]ActiveInterpreterFrame = undefined,
    heap_frames: std.ArrayList(ActiveInterpreterFrame) = .empty,
    inline_len: usize = 0,

    fn init(
        allocator: std.mem.Allocator,
        initial_capacity: usize,
    ) std.mem.Allocator.Error!@This() {
        var self: @This() = .{};
        errdefer self.deinit(allocator);
        if (initial_capacity > self.inline_buffer.len) try self.heap_frames.ensureTotalCapacity(allocator, initial_capacity);
        return self;
    }

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.heap_frames.deinit(allocator);
    }

    fn usingHeap(self: @This()) bool {
        return self.heap_frames.capacity != 0;
    }

    fn append(self: *@This(), allocator: std.mem.Allocator, frame: ActiveInterpreterFrame) (std.mem.Allocator.Error || error{ExecutionBudgetExceeded})!void {
        if (self.len() == max_interpreter_steps) return error.ExecutionBudgetExceeded;
        if (self.usingHeap()) {
            try self.heap_frames.append(allocator, frame);
            return;
        }
        if (self.inline_len < self.inline_buffer.len) {
            self.inline_buffer[self.inline_len] = frame;
            self.inline_len += 1;
            return;
        }
        try self.heap_frames.ensureTotalCapacity(allocator, self.inline_buffer.len * 2);
        try self.heap_frames.appendSlice(allocator, self.inline_buffer[0..self.inline_len]);
        try self.heap_frames.append(allocator, frame);
        self.inline_len = 0;
    }

    fn pop(self: *@This()) ?ActiveInterpreterFrame {
        if (self.usingHeap()) return self.heap_frames.pop();
        if (self.inline_len == 0) return null;
        self.inline_len -= 1;
        return self.inline_buffer[self.inline_len];
    }

    fn top(self: *@This()) *ActiveInterpreterFrame {
        if (self.usingHeap()) return &self.heap_frames.items[self.heap_frames.items.len - 1];
        return &self.inline_buffer[self.inline_len - 1];
    }

    fn at(self: *const @This(), index: usize) ?ActiveInterpreterFrame {
        if (self.usingHeap()) {
            if (index >= self.heap_frames.items.len) return null;
            return self.heap_frames.items[index];
        }
        if (index >= self.inline_len) return null;
        return self.inline_buffer[index];
    }

    fn len(self: @This()) usize {
        if (self.usingHeap()) return self.heap_frames.items.len;
        return self.inline_len;
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
        if (frames.len() == 0) return error.ProgramContractViolation;
        const completed_frame = frames.pop().?;
        scratch.popFrame(completed_frame.frame);

        if (frames.len() == 0) return returned;
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
    const analysis = comptime program_plan.entryExecutionAnalysisWithNestedTargets(compiled_plan, nested_with_targets) catch |err|
        @compileError("validated ProgramPlan entry analysis failed: " ++ @errorName(err));
    const allocator = scratch.allocator;
    var frames = try ActiveFrameStack.init(allocator, analysis.max_active_frame_depth);
    defer frames.deinit(allocator);
    defer {
        while (frames.len() != 0) {
            const active = frames.pop().?;
            scratch.popFrame(active.frame);
        }
    }

    try pushActiveInterpreterFrame(allocator, compiled_plan, scratch, &frames, function_index, args);
    while (frames.len() != 0) {
        try consumeInterpreterStep(remaining_steps);
        const active = frames.top();
        if (active.waiting_helper_dst != null) return error.ProgramContractViolation;

        if (active.instruction_index < active.instruction_end) {
            if (comptime compiled_plan.instructions.len == 0) return error.ProgramContractViolation;
            const instruction_index = active.instruction_index;
            active.instruction_index += 1;

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
                .sum_variant_is => {
                    const is_variant = (try activeVariantOrdinalForExecutable(schema_types, locals[instruction.operand])) == instruction.aux;
                    locals[instruction.dst] = .{ .bool = is_variant };
                    active.last_condition = is_variant;
                },
                .sum_extract_payload => {
                    const dst_ref = localRefForFunctionIndex(compiled_plan, active.function_index, instruction.dst) orelse return error.ProgramContractViolation;
                    const extracted = try extractVariantPayloadForExecutable(schema_types, dst_ref, scratch, locals[instruction.operand], instruction.aux);
                    if (!valueMatchesRef(dst_ref, extracted.value)) return error.ProgramContractViolation;
                    locals[instruction.dst] = extracted.value;
                },
                .const_i32 => locals[instruction.dst] = .{ .i32 = try constI32Value(instruction) },
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

fn completeSessionFunctionValue(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime function_index: usize,
    completion: CompletionValue,
) anyerror!ExecutableValue {
    const function = comptime compiled_plan.functions[function_index];
    if (completion.kind == .normal and completion.after_stack.len != 0) return error.ProgramContractViolation;
    const result_ref = comptime program_plan.functionResultRef(function);
    const value_ref: program_plan.ValueRef = comptime .{
        .codec = function.value_codec,
        .schema_index = function.value_schema_index,
    };
    const final_ref = if (completion.kind == .terminal or completion.initial_ref.eql(result_ref)) result_ref else value_ref;
    if (!valueMatchesRef(final_ref, completion.value)) return error.ProgramContractViolation;
    return completion.value;
}

fn completeSessionFunctionValueByIndex(
    comptime compiled_plan: program_plan.ProgramPlan,
    function_index: usize,
    completion: CompletionValue,
) anyerror!ExecutableValue {
    inline for (compiled_plan.functions, 0..) |_, index| {
        if (function_index == index) {
            return completeSessionFunctionValue(compiled_plan, index, completion);
        }
    }
    return error.ProgramContractViolation;
}

fn returnFromSessionFrame(
    comptime compiled_plan: program_plan.ProgramPlan,
    scratch: anytype,
    frames: *ActiveFrameStack,
    initial_returned: ExecutionResult,
) anyerror!?ExecutionResult {
    var returned = initial_returned;
    while (true) {
        if (frames.len() == 0) return error.ProgramContractViolation;
        const completed_frame = frames.pop().?;
        scratch.popFrame(completed_frame.frame);

        if (frames.len() == 0) return returned;
        var parent = frames.top();
        if (returned.terminal) {
            const parent_function = compiled_plan.functions[parent.function_index];
            const completed = try completeSessionFunctionValueByIndex(
                compiled_plan,
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

fn validateSessionTerminalPropagation(
    comptime compiled_plan: program_plan.ProgramPlan,
    scratch: anytype,
    frames: *const ActiveFrameStack,
    terminal_value: ExecutableValue,
) anyerror!void {
    const frame_count = frames.len();
    if (frame_count == 0) return error.ProgramContractViolation;

    var returned = terminal_value;
    var index = frame_count - 1;
    while (index > 0) {
        index -= 1;
        const parent = frames.at(index) orelse return error.ProgramContractViolation;
        const parent_function = compiled_plan.functions[parent.function_index];
        returned = try completeSessionFunctionValueByIndex(
            compiled_plan,
            parent.function_index,
            .{
                .value = returned,
                .initial_ref = program_plan.functionResultRef(parent_function),
                .after_stack = scratch.frameAfterStack(parent.frame),
                .kind = .terminal,
            },
        );
    }
}

pub fn ExecutableSessionForPlan(
    comptime ErrorSet: type,
    comptime program_label: []const u8,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_with_targets: anytype,
    comptime HandlersType: type,
) type {
    const entry = compiled_plan.functions[compiled_plan.entry_index];
    const analysis = comptime program_plan.entryExecutionAnalysisWithNestedTargets(compiled_plan, nested_with_targets) catch |err|
        @compileError("validated ProgramPlan entry analysis failed: " ++ @errorName(err));
    const RawResult = TypedRunResultTypeForPlan(compiled_plan, schema_types);
    const session_after_stack_capacity = if (analysis.reachable_after_count == 0) 0 else max_interpreter_steps;
    const plan_hash = compiled_plan.hash();

    return struct {
        const Self = @This();
        const request_payload_storage_size = maxSchemaValueSize(schema_types);
        const request_payload_storage_align = maxSchemaValueAlign(schema_types);

        const PendingRequest = struct {
            session_id: usize,
            token: u64,
            function_index: usize,
            dst: u16,
            op_index: u16,
            mode: program_plan.ControlMode,
            resume_ref: program_plan.ValueRef,
            result_ref: program_plan.ValueRef,
            has_after: bool,
        };

        const PendingAfter = struct {
            session_id: usize,
            token: u64,
            function_index: usize,
            op_index: u16,
            value_ref: program_plan.ValueRef,
            output_ref: program_plan.ValueRef,
            result_ref: program_plan.ValueRef,
            remaining: usize,
        };

        const Pending = union(enum) {
            after: PendingAfter,
            op: PendingRequest,
        };

        const AfterUnwind = struct {
            function_index: usize,
            value: ExecutableValue,
            current_ref: program_plan.ValueRef,
            final_ref: program_plan.ValueRef,
            remaining: usize,
        };

        const RequestPayload = union(enum) {
            none,
            bool: bool,
            i32: i32,
            usize: usize,
            string: []const u8,
            string_list: []const []const u8,
            schema_index: u16,
        };

        // zlinter-disable declaration_naming - Program.Session.Trace is the documented host-facing trace namespace.
        pub const Trace = struct {
            pub const fingerprint_version = trace_fingerprint_version;

            pub const RequestKind = enum {
                after,
                operation,
            };

            pub const ResponseKind = enum {
                @"resume",
                return_now,
                resume_after,
            };

            pub const FingerprintError = error{
                TraceFingerprintMismatch,
            };

            pub const OperationRequest = struct {
                fingerprint_version: u32 = trace_fingerprint_version,
                program_label: []const u8,
                plan_label: []const u8,
                plan_hash: u64,
                turn_index: usize,
                kind: RequestKind = .operation,
                requirement_index: u16,
                requirement_label: []const u8,
                op_index: u16,
                op_name: []const u8,
                mode: program_plan.ControlMode,
                payload_ref: program_plan.ValueRef,
                has_payload: bool,
                payload_value_fingerprint: u64,
                resume_ref: program_plan.ValueRef,
                result_ref: program_plan.ValueRef,
                has_after: bool,
                fingerprint: u64,

                pub fn eql(self: @This(), expected: u64) bool {
                    return self.fingerprint == expected;
                }
            };

            pub const AfterRequest = struct {
                fingerprint_version: u32 = trace_fingerprint_version,
                program_label: []const u8,
                plan_label: []const u8,
                plan_hash: u64,
                turn_index: usize,
                kind: RequestKind = .after,
                original_requirement_index: u16,
                original_requirement_label: []const u8,
                original_op_index: u16,
                original_op_name: []const u8,
                current_value_ref: program_plan.ValueRef,
                current_value_fingerprint: u64,
                expected_output_ref: program_plan.ValueRef,
                result_ref: program_plan.ValueRef,
                fingerprint: u64,

                pub fn eql(self: @This(), expected: u64) bool {
                    return self.fingerprint == expected;
                }
            };

            pub const Response = struct {
                fingerprint_version: u32 = trace_fingerprint_version,
                request_fingerprint: u64,
                kind: ResponseKind,
                response_ref: program_plan.ValueRef,
                response_value_fingerprint: u64,
                fingerprint: u64,
            };
        };
        // zlinter-enable declaration_naming

        allocator: std.mem.Allocator,
        scratch: InterpreterScratch(session_after_stack_capacity),
        frames: ActiveFrameStack,
        session_id: usize,
        remaining_steps: usize = max_interpreter_steps,
        next_token: u64 = 1,
        next_turn_index: usize = 0,
        pending: ?Pending = null,
        unwinding_after: ?AfterUnwind = null,
        completed: ?ExecutionResult = null,
        done_consumed: bool = false,

        pub const Request = struct {
            _session_id: usize,
            token: u64,
            requirement_index: u16,
            requirement_label: []const u8,
            op_index: u16,
            op_name: []const u8,
            mode: program_plan.ControlMode,
            payload_ref: program_plan.ValueRef,
            has_payload: bool,
            resume_ref: program_plan.ValueRef,
            result_ref: program_plan.ValueRef,
            has_after: bool,
            _payload: RequestPayload,
            _payload_storage: [request_payload_storage_size]u8 align(request_payload_storage_align) = undefined,
            _turn_index: usize,
            _payload_value_fingerprint: u64,
            _fingerprint: u64,

            pub fn payload(self: @This(), comptime T: type) error{ProgramContractViolation}!T {
                if (!typeMatchesRuntimeRef(schema_types, self.payload_ref, T)) return error.ProgramContractViolation;
                if (T == void) return switch (self._payload) {
                    .none => {},
                    else => error.ProgramContractViolation,
                };
                if (T == bool) return switch (self._payload) {
                    .bool => |typed| typed,
                    else => error.ProgramContractViolation,
                };
                if (T == i32) return switch (self._payload) {
                    .i32 => |typed| typed,
                    else => error.ProgramContractViolation,
                };
                if (T == usize) return switch (self._payload) {
                    .usize => |typed| typed,
                    else => error.ProgramContractViolation,
                };
                if (T == []const u8) return switch (self._payload) {
                    .string => |typed| typed,
                    else => error.ProgramContractViolation,
                };
                if (T == []const []const u8) return switch (self._payload) {
                    .string_list => |typed| typed,
                    else => error.ProgramContractViolation,
                };
                if (T == [][]const u8) return error.ProgramContractViolation;

                const schema_index = self.payload_ref.schema_index orelse return error.ProgramContractViolation;
                const expected_codec: program_plan.ValueCodec = comptime switch (@typeInfo(T)) {
                    .@"struct" => .product,
                    .@"enum", .@"union", .optional => .sum,
                    else => return error.ProgramContractViolation,
                };
                if (self.payload_ref.codec != expected_codec) return error.ProgramContractViolation;
                return switch (self._payload) {
                    .schema_index => |actual_index| blk: {
                        if (actual_index != schema_index) return error.ProgramContractViolation;
                        const typed: *const T = @ptrCast(@alignCast(&self._payload_storage));
                        break :blk typed.*;
                    },
                    else => error.ProgramContractViolation,
                };
            }

            pub fn trace(self: @This()) Trace.OperationRequest {
                return .{
                    .program_label = program_label,
                    .plan_label = compiled_plan.label,
                    .plan_hash = plan_hash,
                    .turn_index = self._turn_index,
                    .requirement_index = self.requirement_index,
                    .requirement_label = self.requirement_label,
                    .op_index = self.op_index,
                    .op_name = self.op_name,
                    .mode = self.mode,
                    .payload_ref = self.payload_ref,
                    .has_payload = self.has_payload,
                    .payload_value_fingerprint = self._payload_value_fingerprint,
                    .resume_ref = self.resume_ref,
                    .result_ref = self.result_ref,
                    .has_after = self.has_after,
                    .fingerprint = self._fingerprint,
                };
            }

            pub fn fingerprint(self: @This()) u64 {
                return self._fingerprint;
            }

            pub fn expectFingerprint(self: @This(), expected: u64) Trace.FingerprintError!void {
                if (self._fingerprint != expected) return error.TraceFingerprintMismatch;
            }

            pub fn responseTrace(self: @This(), kind: Trace.ResponseKind, response_value: anytype) error{ProgramContractViolation}!Trace.Response {
                const response_ref = switch (kind) {
                    .@"resume" => blk: {
                        if (self.mode == .abort) return error.ProgramContractViolation;
                        break :blk self.resume_ref;
                    },
                    .return_now => blk: {
                        if (self.mode == .transform) return error.ProgramContractViolation;
                        break :blk self.result_ref;
                    },
                    .resume_after => return error.ProgramContractViolation,
                };
                const value_fingerprint = try Self.fingerprintTypedValueForRef(response_ref, response_value);
                return Self.responseTraceFor(self._fingerprint, kind, response_ref, value_fingerprint);
            }

            fn setPayload(self: *@This(), payload_value: ExecutableValue) error{ProgramContractViolation}!void {
                self._payload = switch (payload_value) {
                    .none => .none,
                    .bool => |typed| .{ .bool = typed },
                    .i32 => |typed| .{ .i32 = typed },
                    .usize => |typed| .{ .usize = typed },
                    .string => |typed| .{ .string = typed },
                    .string_list => |typed| .{ .string_list = typed },
                    .schema => |schema| try self.storeStructuredPayload(schema),
                };
            }

            fn storeStructuredPayload(self: *@This(), schema: SchemaValue) error{ProgramContractViolation}!RequestPayload {
                inline for (schema_types, 0..) |SchemaType, schema_index| {
                    if (schema.schema_index == @as(u16, @intCast(schema_index))) {
                        const source: *const SchemaType = @ptrCast(@alignCast(schema.ptr));
                        const destination: *SchemaType = @ptrCast(@alignCast(&self._payload_storage));
                        destination.* = source.*;
                        return .{ .schema_index = schema.schema_index };
                    }
                }
                return error.ProgramContractViolation;
            }
        };

        pub const AfterRequest = struct {
            _session_id: usize,
            token: u64,
            requirement_index: u16,
            requirement_label: []const u8,
            op_index: u16,
            op_name: []const u8,
            value_ref: program_plan.ValueRef,
            has_value: bool,
            output_ref: program_plan.ValueRef,
            result_ref: program_plan.ValueRef,
            _remaining: usize,
            _value: RequestPayload,
            _value_storage: [request_payload_storage_size]u8 align(request_payload_storage_align) = undefined,
            _turn_index: usize,
            _value_fingerprint: u64,
            _fingerprint: u64,

            pub fn value(self: @This(), comptime T: type) error{ProgramContractViolation}!T {
                if (!typeMatchesRuntimeRef(schema_types, self.value_ref, T)) return error.ProgramContractViolation;
                if (T == void) return switch (self._value) {
                    .none => {},
                    else => error.ProgramContractViolation,
                };
                if (T == bool) return switch (self._value) {
                    .bool => |typed| typed,
                    else => error.ProgramContractViolation,
                };
                if (T == i32) return switch (self._value) {
                    .i32 => |typed| typed,
                    else => error.ProgramContractViolation,
                };
                if (T == usize) return switch (self._value) {
                    .usize => |typed| typed,
                    else => error.ProgramContractViolation,
                };
                if (T == []const u8) return switch (self._value) {
                    .string => |typed| typed,
                    else => error.ProgramContractViolation,
                };
                if (T == []const []const u8) return switch (self._value) {
                    .string_list => |typed| typed,
                    else => error.ProgramContractViolation,
                };
                if (T == [][]const u8) return error.ProgramContractViolation;

                const schema_index = self.value_ref.schema_index orelse return error.ProgramContractViolation;
                const expected_codec: program_plan.ValueCodec = comptime switch (@typeInfo(T)) {
                    .@"struct" => .product,
                    .@"enum", .@"union", .optional => .sum,
                    else => return error.ProgramContractViolation,
                };
                if (self.value_ref.codec != expected_codec) return error.ProgramContractViolation;
                return switch (self._value) {
                    .schema_index => |actual_index| blk: {
                        if (actual_index != schema_index) return error.ProgramContractViolation;
                        const typed: *const T = @ptrCast(@alignCast(&self._value_storage));
                        break :blk typed.*;
                    },
                    else => error.ProgramContractViolation,
                };
            }

            pub fn trace(self: @This()) Trace.AfterRequest {
                return .{
                    .program_label = program_label,
                    .plan_label = compiled_plan.label,
                    .plan_hash = plan_hash,
                    .turn_index = self._turn_index,
                    .original_requirement_index = self.requirement_index,
                    .original_requirement_label = self.requirement_label,
                    .original_op_index = self.op_index,
                    .original_op_name = self.op_name,
                    .current_value_ref = self.value_ref,
                    .current_value_fingerprint = self._value_fingerprint,
                    .expected_output_ref = self.output_ref,
                    .result_ref = self.result_ref,
                    .fingerprint = self._fingerprint,
                };
            }

            pub fn fingerprint(self: @This()) u64 {
                return self._fingerprint;
            }

            pub fn expectFingerprint(self: @This(), expected: u64) Trace.FingerprintError!void {
                if (self._fingerprint != expected) return error.TraceFingerprintMismatch;
            }

            pub fn responseTrace(self: @This(), kind: Trace.ResponseKind, response_value: anytype) error{ProgramContractViolation}!Trace.Response {
                if (kind != .resume_after) return error.ProgramContractViolation;
                const value_fingerprint = try Self.fingerprintTypedValueForRef(self.output_ref, response_value);
                return Self.responseTraceFor(self._fingerprint, kind, self.output_ref, value_fingerprint);
            }

            fn setValue(self: *@This(), current_value: ExecutableValue) error{ProgramContractViolation}!void {
                self._value = switch (current_value) {
                    .none => .none,
                    .bool => |typed| .{ .bool = typed },
                    .i32 => |typed| .{ .i32 = typed },
                    .usize => |typed| .{ .usize = typed },
                    .string => |typed| .{ .string = typed },
                    .string_list => |typed| .{ .string_list = typed },
                    .schema => |schema| try self.storeStructuredValue(schema),
                };
            }

            fn storeStructuredValue(self: *@This(), schema: SchemaValue) error{ProgramContractViolation}!RequestPayload {
                inline for (schema_types, 0..) |SchemaType, schema_index| {
                    if (schema.schema_index == @as(u16, @intCast(schema_index))) {
                        const source: *const SchemaType = @ptrCast(@alignCast(schema.ptr));
                        const destination: *SchemaType = @ptrCast(@alignCast(&self._value_storage));
                        destination.* = source.*;
                        return .{ .schema_index = schema.schema_index };
                    }
                }
                return error.ProgramContractViolation;
            }
        };

        pub const Step = union(enum) {
            after: AfterRequest,
            done: RawResult,
            request: Request,
        };

        fn nextTurnIndex(self: *Self) usize {
            const turn_index = self.next_turn_index;
            self.next_turn_index += 1;
            return turn_index;
        }

        fn traceHashBytes(hasher: *std.hash.Wyhash, value: []const u8) void {
            traceHashUsize(hasher, value.len);
            hasher.update(value);
        }

        fn traceHashBool(hasher: *std.hash.Wyhash, value: bool) void {
            hasher.update(&[_]u8{@intFromBool(value)});
        }

        fn traceHashU8(hasher: *std.hash.Wyhash, value: u8) void {
            hasher.update(&[_]u8{value});
        }

        fn traceHashU16(hasher: *std.hash.Wyhash, value: u16) void {
            var bytes: [2]u8 = undefined;
            std.mem.writeInt(u16, &bytes, value, .little);
            hasher.update(&bytes);
        }

        fn traceHashU32(hasher: *std.hash.Wyhash, value: u32) void {
            var bytes: [4]u8 = undefined;
            std.mem.writeInt(u32, &bytes, value, .little);
            hasher.update(&bytes);
        }

        fn traceHashI32(hasher: *std.hash.Wyhash, value: i32) void {
            traceHashU32(hasher, @bitCast(value));
        }

        fn traceHashU64(hasher: *std.hash.Wyhash, value: u64) void {
            var bytes: [8]u8 = undefined;
            std.mem.writeInt(u64, &bytes, value, .little);
            hasher.update(&bytes);
        }

        fn traceHashUsize(hasher: *std.hash.Wyhash, value: usize) void {
            traceHashU64(hasher, @intCast(value));
        }

        fn traceHashOptionalU16(hasher: *std.hash.Wyhash, value: ?u16) void {
            traceHashBool(hasher, value != null);
            if (value) |actual| traceHashU16(hasher, actual);
        }

        fn traceHashCodec(hasher: *std.hash.Wyhash, codec: program_plan.ValueCodec) void {
            traceHashU8(hasher, @intFromEnum(codec));
        }

        fn traceHashMode(hasher: *std.hash.Wyhash, mode: program_plan.ControlMode) void {
            traceHashBytes(hasher, @tagName(mode));
        }

        fn traceHashRequestKind(hasher: *std.hash.Wyhash, kind: Trace.RequestKind) void {
            traceHashBytes(hasher, @tagName(kind));
        }

        fn traceHashResponseKind(hasher: *std.hash.Wyhash, kind: Trace.ResponseKind) void {
            traceHashBytes(hasher, @tagName(kind));
        }

        fn traceHashValueRef(hasher: *std.hash.Wyhash, ref: program_plan.ValueRef) void {
            traceHashCodec(hasher, ref.codec);
            traceHashOptionalU16(hasher, ref.schema_index);
        }

        fn traceHashCommonRequestPrefix(hasher: *std.hash.Wyhash, turn_index: usize, kind: Trace.RequestKind) void {
            traceHashBytes(hasher, "ability.session.request");
            traceHashU32(hasher, trace_fingerprint_version);
            traceHashBytes(hasher, program_label);
            traceHashBytes(hasher, compiled_plan.label);
            traceHashU64(hasher, plan_hash);
            traceHashUsize(hasher, turn_index);
            traceHashRequestKind(hasher, kind);
        }

        fn operationRequestFingerprint(
            turn_index: usize,
            requirement_index: u16,
            requirement_label: []const u8,
            op_index: u16,
            op_name: []const u8,
            mode: program_plan.ControlMode,
            payload_ref: program_plan.ValueRef,
            payload_fingerprint: u64,
            resume_ref: program_plan.ValueRef,
            result_ref: program_plan.ValueRef,
            has_after: bool,
        ) u64 {
            var hasher = std.hash.Wyhash.init(0);
            traceHashCommonRequestPrefix(&hasher, turn_index, .operation);
            traceHashU16(&hasher, requirement_index);
            traceHashBytes(&hasher, requirement_label);
            traceHashU16(&hasher, op_index);
            traceHashBytes(&hasher, op_name);
            traceHashMode(&hasher, mode);
            traceHashValueRef(&hasher, payload_ref);
            traceHashU64(&hasher, payload_fingerprint);
            traceHashValueRef(&hasher, resume_ref);
            traceHashValueRef(&hasher, result_ref);
            traceHashBool(&hasher, has_after);
            return hasher.final();
        }

        fn afterRequestFingerprint(
            turn_index: usize,
            requirement_index: u16,
            requirement_label: []const u8,
            op_index: u16,
            op_name: []const u8,
            value_ref: program_plan.ValueRef,
            value_fingerprint: u64,
            output_ref: program_plan.ValueRef,
            result_ref: program_plan.ValueRef,
        ) u64 {
            var hasher = std.hash.Wyhash.init(0);
            traceHashCommonRequestPrefix(&hasher, turn_index, .after);
            traceHashU16(&hasher, requirement_index);
            traceHashBytes(&hasher, requirement_label);
            traceHashU16(&hasher, op_index);
            traceHashBytes(&hasher, op_name);
            traceHashValueRef(&hasher, value_ref);
            traceHashU64(&hasher, value_fingerprint);
            traceHashValueRef(&hasher, output_ref);
            traceHashValueRef(&hasher, result_ref);
            return hasher.final();
        }

        fn responseTraceFor(
            request_fingerprint: u64,
            kind: Trace.ResponseKind,
            response_ref: program_plan.ValueRef,
            response_value_fingerprint: u64,
        ) Trace.Response {
            var hasher = std.hash.Wyhash.init(0);
            traceHashBytes(&hasher, "ability.session.response");
            traceHashU32(&hasher, trace_fingerprint_version);
            traceHashU64(&hasher, request_fingerprint);
            traceHashResponseKind(&hasher, kind);
            traceHashValueRef(&hasher, response_ref);
            traceHashU64(&hasher, response_value_fingerprint);
            return .{
                .request_fingerprint = request_fingerprint,
                .kind = kind,
                .response_ref = response_ref,
                .response_value_fingerprint = response_value_fingerprint,
                .fingerprint = hasher.final(),
            };
        }

        fn fingerprintTypedValueForRef(ref: program_plan.ValueRef, value: anytype) error{ProgramContractViolation}!u64 {
            if (!typeMatchesRuntimeRef(schema_types, ref, @TypeOf(value))) return error.ProgramContractViolation;
            var hasher = std.hash.Wyhash.init(0);
            traceHashBytes(&hasher, "ability.session.value");
            traceHashU32(&hasher, trace_fingerprint_version);
            traceHashValueRef(&hasher, ref);
            try traceHashTypedValuePayload(&hasher, ref, value);
            return hasher.final();
        }

        fn fingerprintExecutableValueForRef(ref: program_plan.ValueRef, value: ExecutableValue) error{ProgramContractViolation}!u64 {
            if (!valueMatchesRef(ref, value)) return error.ProgramContractViolation;
            var hasher = std.hash.Wyhash.init(0);
            traceHashBytes(&hasher, "ability.session.value");
            traceHashU32(&hasher, trace_fingerprint_version);
            traceHashValueRef(&hasher, ref);
            try traceHashExecutableValuePayload(&hasher, ref, value);
            return hasher.final();
        }

        fn traceHashExecutableValuePayload(
            hasher: *std.hash.Wyhash,
            ref: program_plan.ValueRef,
            value: ExecutableValue,
        ) error{ProgramContractViolation}!void {
            switch (ref.codec) {
                .unit => switch (value) {
                    .none => {},
                    else => return error.ProgramContractViolation,
                },
                .bool => switch (value) {
                    .bool => |typed| traceHashBool(hasher, typed),
                    else => return error.ProgramContractViolation,
                },
                .i32 => switch (value) {
                    .i32 => |typed| traceHashI32(hasher, typed),
                    else => return error.ProgramContractViolation,
                },
                .usize => switch (value) {
                    .usize => |typed| traceHashUsize(hasher, typed),
                    else => return error.ProgramContractViolation,
                },
                .string => switch (value) {
                    .string => |typed| traceHashBytes(hasher, typed),
                    else => return error.ProgramContractViolation,
                },
                .string_list => switch (value) {
                    .string_list => |typed| {
                        traceHashUsize(hasher, typed.len);
                        for (typed) |item| traceHashBytes(hasher, item);
                    },
                    else => return error.ProgramContractViolation,
                },
                .product, .sum => switch (value) {
                    .schema => |schema| {
                        const expected_schema_index = ref.schema_index orelse return error.ProgramContractViolation;
                        if (schema.schema_index != expected_schema_index) {
                            return error.ProgramContractViolation;
                        }
                        inline for (schema_types, 0..) |SchemaType, schema_index| {
                            if (schema.schema_index == schema_index) {
                                const typed: *const SchemaType = @ptrCast(@alignCast(schema.ptr));
                                return traceHashStructuredTypedValuePayload(hasher, ref, SchemaType, typed.*);
                            }
                        }
                        return error.ProgramContractViolation;
                    },
                    else => return error.ProgramContractViolation,
                },
            }
        }

        fn traceHashTypedValuePayload(
            hasher: *std.hash.Wyhash,
            ref: program_plan.ValueRef,
            value: anytype,
        ) error{ProgramContractViolation}!void {
            if (!typeMatchesRuntimeRef(schema_types, ref, @TypeOf(value))) return error.ProgramContractViolation;
            if (comptime isStringListCarrier(@TypeOf(value))) {
                if (!ref.eql(.{ .codec = .string_list })) return error.ProgramContractViolation;
                traceHashUsize(hasher, value.len);
                for (value) |item| traceHashBytes(hasher, item);
                return;
            }
            switch (@TypeOf(value)) {
                void => {
                    if (!ref.eql(.{ .codec = .unit })) return error.ProgramContractViolation;
                },
                bool => {
                    if (!ref.eql(.{ .codec = .bool })) return error.ProgramContractViolation;
                    traceHashBool(hasher, value);
                },
                i32 => {
                    if (!ref.eql(.{ .codec = .i32 })) return error.ProgramContractViolation;
                    traceHashI32(hasher, value);
                },
                usize => {
                    if (!ref.eql(.{ .codec = .usize })) return error.ProgramContractViolation;
                    traceHashUsize(hasher, value);
                },
                []const u8 => {
                    if (!ref.eql(.{ .codec = .string })) return error.ProgramContractViolation;
                    traceHashBytes(hasher, value);
                },
                else => try traceHashStructuredTypedValuePayload(hasher, ref, @TypeOf(value), value),
            }
        }

        fn traceHashStructuredTypedValuePayload(
            hasher: *std.hash.Wyhash,
            ref: program_plan.ValueRef,
            comptime T: type,
            value: T,
        ) error{ProgramContractViolation}!void {
            const schema_index = ref.schema_index orelse return error.ProgramContractViolation;
            inline for (schema_types, 0..) |SchemaType, index| {
                if (schema_index == index) {
                    if (SchemaType != T) return error.ProgramContractViolation;
                    const schema = compiled_plan.value_schemas[index];
                    if (schema.codec != ref.codec) return error.ProgramContractViolation;
                    traceHashU16(hasher, @intCast(index));
                    traceHashBytes(hasher, schema.label);
                    traceHashCodec(hasher, schema.codec);
                    return switch (schema.codec) {
                        .product => traceHashProductValuePayload(hasher, index, T, value),
                        .sum => traceHashSumValuePayload(hasher, index, T, value),
                        else => error.ProgramContractViolation,
                    };
                }
            }
            return error.ProgramContractViolation;
        }

        fn traceHashProductValuePayload(
            hasher: *std.hash.Wyhash,
            comptime schema_index: usize,
            comptime T: type,
            value: T,
        ) error{ProgramContractViolation}!void {
            const schema = compiled_plan.value_schemas[schema_index];
            if (schema.codec != .product) return error.ProgramContractViolation;
            const fields = std.meta.fields(T);
            if (fields.len != schema.field_count) return error.ProgramContractViolation;
            traceHashU16(hasher, schema.first_field);
            traceHashU16(hasher, schema.field_count);
            inline for (0..schema.field_count) |field_offset| {
                const field = compiled_plan.value_fields[@as(usize, schema.first_field) + field_offset];
                const field_ref: program_plan.ValueRef = .{
                    .codec = field.codec,
                    .schema_index = field.schema_index,
                };
                traceHashU16(hasher, @intCast(field_offset));
                traceHashBytes(hasher, field.name);
                traceHashValueRef(hasher, field_ref);
                const field_fingerprint = try fingerprintTypedValueForRef(field_ref, @field(value, field.name));
                traceHashU64(hasher, field_fingerprint);
            }
        }

        fn traceHashSumValuePayload(
            hasher: *std.hash.Wyhash,
            comptime schema_index: usize,
            comptime T: type,
            value: T,
        ) error{ProgramContractViolation}!void {
            const schema = compiled_plan.value_schemas[schema_index];
            if (schema.codec != .sum) return error.ProgramContractViolation;
            const active = try activeVariantOrdinalForTyped(T, value);
            if (active >= schema.variant_count) return error.ProgramContractViolation;
            traceHashU16(hasher, schema.first_variant);
            traceHashU16(hasher, schema.variant_count);
            traceHashU16(hasher, active);
            inline for (0..schema.variant_count) |variant_offset| {
                if (active == variant_offset) {
                    const variant = compiled_plan.value_variants[@as(usize, schema.first_variant) + variant_offset];
                    const variant_ref: program_plan.ValueRef = .{
                        .codec = variant.codec,
                        .schema_index = variant.schema_index,
                    };
                    traceHashBytes(hasher, variant.name);
                    traceHashValueRef(hasher, variant_ref);
                    const payload_fingerprint = try sumVariantPayloadFingerprint(variant_offset, variant_ref, T, value);
                    traceHashU64(hasher, payload_fingerprint);
                    return;
                }
            }
            return error.ProgramContractViolation;
        }

        fn sumVariantPayloadFingerprint(
            comptime variant_offset: usize,
            variant_ref: program_plan.ValueRef,
            comptime T: type,
            value: T,
        ) error{ProgramContractViolation}!u64 {
            return switch (@typeInfo(T)) {
                .@"enum" => fingerprintTypedValueForRef(variant_ref, {}),
                .optional => if (variant_offset == 0)
                    fingerprintTypedValueForRef(variant_ref, {})
                else
                    fingerprintTypedValueForRef(variant_ref, value.?),
                .@"union" => |union_info| blk: {
                    inline for (union_info.fields, 0..) |field, field_index| {
                        if (variant_offset == field_index) {
                            if (field.type == void) break :blk fingerprintTypedValueForRef(variant_ref, {});
                            break :blk fingerprintTypedValueForRef(variant_ref, @field(value, field.name));
                        }
                    }
                    return error.ProgramContractViolation;
                },
                else => error.ProgramContractViolation,
            };
        }

        const session_id_source = struct {
            var next: std.atomic.Value(usize) = std.atomic.Value(usize).init(1);
        };

        fn nextSessionId() usize {
            var session_identifier = session_id_source.next.fetchAdd(1, .monotonic);
            if (session_identifier == 0) session_identifier = session_id_source.next.fetchAdd(1, .monotonic);
            return session_identifier;
        }

        pub fn start(allocator: std.mem.Allocator, args: anytype) anyerror!Self {
            comptime validateTypedExecutablePlanSupportWithNestedTargets(compiled_plan, schema_types, nested_with_targets) catch |err|
                @compileError("Program.Session.start failed executable support validation: " ++ @errorName(err));
            comptime validateSessionPlanSupportWithNestedTargets(compiled_plan, nested_with_targets) catch |err|
                @compileError("Program.Session.start unsupported: " ++ @errorName(err));
            var scratch = try InterpreterScratch(session_after_stack_capacity).init(
                allocator,
                analysis.max_active_local_slots,
                analysis.max_active_call_arg_slots,
            );
            errdefer scratch.deinit();

            var frames = try ActiveFrameStack.init(allocator, analysis.max_active_frame_depth);
            errdefer frames.deinit(allocator);

            var self: Self = .{
                .allocator = allocator,
                .scratch = scratch,
                .frames = frames,
                .session_id = nextSessionId(),
            };
            scratch = .{ .allocator = allocator };
            frames = .{};
            errdefer self.deinit();

            var entry_args: [entry.parameter_count]ExecutableValue = undefined;
            try encodeEntryArgs(compiled_plan, schema_types, &self.scratch, entry_args[0..], args);
            try pushActiveInterpreterFrame(allocator, compiled_plan, &self.scratch, &self.frames, compiled_plan.entry_index, entry_args[0..]);
            return self;
        }

        pub fn deinit(self: *Self) void {
            while (self.frames.len() != 0) {
                const active = self.frames.pop().?;
                self.scratch.popFrame(active.frame);
            }
            self.frames.deinit(self.allocator);
            self.scratch.deinit();
            self.pending = null;
            self.unwinding_after = null;
            self.completed = null;
        }

        pub fn hasPendingRequest(self: *const Self) bool {
            return self.pending != null;
        }

        pub fn next(self: *Self) anyerror!Step {
            if (self.pending != null) return error.ProgramContractViolation;
            if (self.unwinding_after != null) {
                if (try self.continueAfterUnwind()) |step| return step;
            }
            if (self.completed != null) return self.consumeCompleted();
            if (self.done_consumed) return error.ProgramContractViolation;

            while (self.frames.len() != 0) {
                try consumeInterpreterStep(&self.remaining_steps);
                if (self.unwinding_after != null) {
                    if (try self.continueAfterUnwind()) |step| return step;
                    continue;
                }
                const active = self.frames.top();
                if (active.waiting_helper_dst != null) return error.ProgramContractViolation;

                if (active.instruction_index < active.instruction_end) {
                    if (comptime compiled_plan.instructions.len == 0) return error.ProgramContractViolation;
                    const instruction_index = active.instruction_index;
                    active.instruction_index += 1;
                    const instruction = compiled_plan.instructions[instruction_index];
                    const function = compiled_plan.functions[active.function_index];
                    var locals = self.scratch.frameLocals(active.frame);
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
                            const buffer = try self.scratch.pushCallArgs(callee.parameter_count);
                            var args_popped = false;
                            errdefer if (!args_popped) self.scratch.popCallArgs(buffer[0..callee.parameter_count]);
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
                                self.allocator,
                                compiled_plan,
                                &self.scratch,
                                &self.frames,
                                instruction.operand,
                                buffer[0..callee.parameter_count],
                            );
                            self.frames.top().frame.call_args_start -= callee.parameter_count;
                            self.scratch.popCallArgs(buffer[0..callee.parameter_count]);
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
                                self.allocator,
                                compiled_plan,
                                &self.scratch,
                                &self.frames,
                                target_index,
                                &.{},
                            );
                        },
                        .call_op => {
                            if (comptime compiled_plan.ops.len == 0) return error.ProgramContractViolation;
                            if (instruction.operand >= compiled_plan.ops.len) return error.ProgramContractViolation;
                            const op = compiled_plan.ops[instruction.operand];
                            const payload_ref: program_plan.ValueRef = .{
                                .codec = op.payload_codec,
                                .schema_index = op.payload_schema_index,
                            };
                            const payload = if (op.payload_codec == .unit) .none else locals[instruction.aux];
                            if (!valueMatchesRef(payload_ref, payload)) return error.ProgramContractViolation;
                            const result_ref = program_plan.functionResultRef(function);
                            const request = try self.makeRequest(
                                active.function_index,
                                instruction.dst,
                                instruction.operand,
                                result_ref,
                                payload,
                            );
                            return .{ .request = request };
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
                        .sum_variant_is => {
                            const is_variant = (try activeVariantOrdinalForExecutable(schema_types, locals[instruction.operand])) == instruction.aux;
                            locals[instruction.dst] = .{ .bool = is_variant };
                            active.last_condition = is_variant;
                        },
                        .sum_extract_payload => {
                            const dst_ref = localRefForFunctionIndex(compiled_plan, active.function_index, instruction.dst) orelse return error.ProgramContractViolation;
                            const extracted = try extractVariantPayloadForExecutable(schema_types, dst_ref, &self.scratch, locals[instruction.operand], instruction.aux);
                            if (!valueMatchesRef(dst_ref, extracted.value)) return error.ProgramContractViolation;
                            locals[instruction.dst] = extracted.value;
                        },
                        .const_i32 => locals[instruction.dst] = .{ .i32 = try constI32Value(instruction) },
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
                        const completion: CompletionValue = .{
                            .value = if (function.value_codec == .unit) .none else active.last_return,
                            .initial_ref = .{ .codec = function.value_codec, .schema_index = function.value_schema_index },
                            .after_stack = self.scratch.frameAfterStack(active.frame),
                            .kind = .normal,
                        };
                        if (try self.beginOrCompleteSessionReturn(active.function_index, completion)) |step| return step;
                    },
                    .return_value => {
                        const completion: CompletionValue = .{
                            .value = active.last_return,
                            .initial_ref = .{ .codec = function.value_codec, .schema_index = function.value_schema_index },
                            .after_stack = self.scratch.frameAfterStack(active.frame),
                            .kind = .normal,
                        };
                        if (try self.beginOrCompleteSessionReturn(active.function_index, completion)) |step| return step;
                    },
                }
            }
            return error.ProgramContractViolation;
        }

        pub fn @"resume"(self: *Self, request: Request, value: anytype) anyerror!void {
            const pending = try self.checkedPending(request);
            if (pending.mode == .abort) return error.ProgramContractViolation;
            const encoded = try encodeRuntimeValueForRuntimeRef(schema_types, pending.resume_ref, &self.scratch, value);
            if (!valueMatchesRef(pending.resume_ref, encoded)) return error.ProgramContractViolation;
            if (self.frames.len() == 0) return error.ProgramContractViolation;
            const active = self.frames.top();
            if (active.function_index != pending.function_index or active.waiting_helper_dst != null) return error.ProgramContractViolation;
            var locals = self.scratch.frameLocals(active.frame);
            if (pending.has_after) try self.scratch.pushAfter(pending.op_index);
            if (pending.resume_ref.codec == .unit) {
                active.last_return = encoded;
            } else if (pending.dst != std.math.maxInt(u16)) {
                locals[pending.dst] = encoded;
            } else {
                active.last_return = encoded;
            }
            self.pending = null;
        }

        pub fn resumeAfter(self: *Self, request: AfterRequest, value: anytype) anyerror!void {
            const pending = try self.checkedPendingAfter(request);
            const encoded = try encodeRuntimeValueForRuntimeRef(schema_types, pending.output_ref, &self.scratch, value);
            if (!valueMatchesRef(pending.output_ref, encoded)) return error.ProgramContractViolation;
            if (self.unwinding_after) |*unwind| {
                if (unwind.function_index != pending.function_index or
                    unwind.remaining != pending.remaining or
                    !unwind.current_ref.eql(pending.value_ref) or
                    !unwind.final_ref.eql(pending.result_ref))
                {
                    return error.ProgramContractViolation;
                }
                unwind.value = encoded;
                unwind.current_ref = pending.output_ref;
                unwind.remaining -= 1;
            } else return error.ProgramContractViolation;
            self.pending = null;
        }

        pub fn returnNow(self: *Self, request: Request, value: anytype) anyerror!void {
            const pending = try self.checkedPending(request);
            if (pending.mode == .transform) return error.ProgramContractViolation;
            if (self.frames.len() == 0) return error.ProgramContractViolation;
            const active = self.frames.top();
            if (active.function_index != pending.function_index or active.waiting_helper_dst != null) return error.ProgramContractViolation;
            const encoded = try encodeRuntimeValueForRuntimeRef(schema_types, pending.result_ref, &self.scratch, value);
            if (!valueMatchesRef(pending.result_ref, encoded)) return error.ProgramContractViolation;
            const completed = try completeSessionFunctionValueByIndex(
                compiled_plan,
                active.function_index,
                .{
                    .value = encoded,
                    .initial_ref = pending.result_ref,
                    .after_stack = self.scratch.frameAfterStack(active.frame),
                    .kind = .terminal,
                },
            );
            try validateSessionTerminalPropagation(compiled_plan, &self.scratch, &self.frames, completed);
            const result = (try returnFromSessionFrame(compiled_plan, &self.scratch, &self.frames, .{ .value = completed, .terminal = true })) orelse
                return error.ProgramContractViolation;
            self.completed = result;
            self.pending = null;
        }

        fn beginOrCompleteSessionReturn(
            self: *Self,
            function_index: usize,
            completion: CompletionValue,
        ) anyerror!?Step {
            if (completion.kind == .normal and completion.after_stack.len != 0) {
                const function = compiled_plan.functions[function_index];
                self.unwinding_after = .{
                    .function_index = function_index,
                    .value = completion.value,
                    .current_ref = completion.initial_ref,
                    .final_ref = program_plan.functionResultRef(function),
                    .remaining = completion.after_stack.len,
                };
                return self.continueAfterUnwind();
            }

            const completed = try completeSessionFunctionValueByIndex(
                compiled_plan,
                function_index,
                completion,
            );
            if (try returnFromSessionFrame(compiled_plan, &self.scratch, &self.frames, .{ .value = completed, .terminal = false })) |result| {
                self.completed = result;
                return @as(?Step, try self.consumeCompleted());
            }
            return null;
        }

        fn continueAfterUnwind(self: *Self) anyerror!?Step {
            const unwind = self.unwinding_after orelse return null;
            if (self.frames.len() == 0) return error.ProgramContractViolation;
            const active = self.frames.top();
            if (active.function_index != unwind.function_index or active.waiting_helper_dst != null) return error.ProgramContractViolation;

            if (unwind.remaining == 0) {
                return self.completeUnwoundFunction(unwind);
            }

            const after_stack = self.scratch.frameAfterStack(active.frame);
            if (unwind.remaining > after_stack.len) return error.ProgramContractViolation;
            const after_index = unwind.remaining - 1;
            const op_index = after_stack[after_index];
            const output_ref = try sessionAfterOutputRefByIndex(
                compiled_plan,
                schema_types,
                HandlersType,
                op_index,
                unwind.current_ref,
                unwind.remaining,
                unwind.final_ref,
            );
            const request = try self.makeAfterRequest(
                unwind.function_index,
                op_index,
                unwind.current_ref,
                output_ref,
                unwind.final_ref,
                unwind.remaining,
                unwind.value,
            );
            return .{ .after = request };
        }

        fn completeUnwoundFunction(self: *Self, unwind: AfterUnwind) anyerror!?Step {
            self.unwinding_after = null;
            const completed = try completeSessionFunctionValueByIndex(
                compiled_plan,
                unwind.function_index,
                .{
                    .value = unwind.value,
                    .initial_ref = unwind.final_ref,
                    .after_stack = &.{},
                    .kind = .normal,
                },
            );
            if (try returnFromSessionFrame(compiled_plan, &self.scratch, &self.frames, .{ .value = completed, .terminal = false })) |result| {
                self.completed = result;
                return @as(?Step, try self.consumeCompleted());
            }
            return null;
        }

        fn makeRequest(
            self: *Self,
            function_index: usize,
            dst: u16,
            op_index: u16,
            result_ref: program_plan.ValueRef,
            payload: ExecutableValue,
        ) error{ProgramContractViolation}!Request {
            inline for (compiled_plan.ops, 0..) |op, index| {
                if (op_index == index) {
                    const requirement = compiled_plan.requirements[op.requirement_index];
                    const resume_ref: program_plan.ValueRef = .{
                        .codec = op.resume_codec,
                        .schema_index = op.resume_schema_index,
                    };
                    const payload_ref: program_plan.ValueRef = .{
                        .codec = op.payload_codec,
                        .schema_index = op.payload_schema_index,
                    };
                    const turn_index = self.nextTurnIndex();
                    const payload_fingerprint = try Self.fingerprintExecutableValueForRef(payload_ref, payload);
                    const request_fingerprint = Self.operationRequestFingerprint(
                        turn_index,
                        op.requirement_index,
                        requirement.label,
                        op_index,
                        op.op_name,
                        op.mode,
                        payload_ref,
                        payload_fingerprint,
                        resume_ref,
                        result_ref,
                        op.has_after,
                    );
                    const token = self.next_token;
                    self.next_token +%= 1;
                    self.pending = .{ .op = .{
                        .session_id = self.session_id,
                        .token = token,
                        .function_index = function_index,
                        .dst = dst,
                        .op_index = op_index,
                        .mode = op.mode,
                        .resume_ref = resume_ref,
                        .result_ref = result_ref,
                        .has_after = op.has_after,
                    } };
                    var request: Request = .{
                        ._session_id = self.session_id,
                        .token = token,
                        .requirement_index = op.requirement_index,
                        .requirement_label = requirement.label,
                        .op_index = op_index,
                        .op_name = op.op_name,
                        .mode = op.mode,
                        .payload_ref = payload_ref,
                        .has_payload = op.payload_codec != .unit,
                        .resume_ref = resume_ref,
                        .result_ref = result_ref,
                        .has_after = op.has_after,
                        ._payload = .none,
                        ._turn_index = turn_index,
                        ._payload_value_fingerprint = payload_fingerprint,
                        ._fingerprint = request_fingerprint,
                    };
                    try request.setPayload(payload);
                    return request;
                }
            }
            unreachable;
        }

        fn makeAfterRequest(
            self: *Self,
            function_index: usize,
            op_index: u16,
            value_ref: program_plan.ValueRef,
            output_ref: program_plan.ValueRef,
            result_ref: program_plan.ValueRef,
            remaining: usize,
            value: ExecutableValue,
        ) error{ProgramContractViolation}!AfterRequest {
            inline for (compiled_plan.ops, 0..) |op, index| {
                if (op_index == index) {
                    if (!op.has_after) return error.ProgramContractViolation;
                    if (!valueMatchesRef(value_ref, value)) return error.ProgramContractViolation;
                    const requirement = compiled_plan.requirements[op.requirement_index];
                    const turn_index = self.nextTurnIndex();
                    const value_fingerprint = try Self.fingerprintExecutableValueForRef(value_ref, value);
                    const request_fingerprint = Self.afterRequestFingerprint(
                        turn_index,
                        op.requirement_index,
                        requirement.label,
                        op_index,
                        op.op_name,
                        value_ref,
                        value_fingerprint,
                        output_ref,
                        result_ref,
                    );
                    const token = self.next_token;
                    self.next_token +%= 1;
                    self.pending = .{ .after = .{
                        .session_id = self.session_id,
                        .token = token,
                        .function_index = function_index,
                        .op_index = op_index,
                        .value_ref = value_ref,
                        .output_ref = output_ref,
                        .result_ref = result_ref,
                        .remaining = remaining,
                    } };
                    var request: AfterRequest = .{
                        ._session_id = self.session_id,
                        .token = token,
                        .requirement_index = op.requirement_index,
                        .requirement_label = requirement.label,
                        .op_index = op_index,
                        .op_name = op.op_name,
                        .value_ref = value_ref,
                        .has_value = value_ref.codec != .unit,
                        .output_ref = output_ref,
                        .result_ref = result_ref,
                        ._remaining = remaining,
                        ._value = .none,
                        ._turn_index = turn_index,
                        ._value_fingerprint = value_fingerprint,
                        ._fingerprint = request_fingerprint,
                    };
                    try request.setValue(value);
                    return request;
                }
            }
            return error.ProgramContractViolation;
        }

        fn checkedPending(self: *Self, request: Request) error{ProgramContractViolation}!PendingRequest {
            const pending = switch (self.pending orelse return error.ProgramContractViolation) {
                .op => |pending_op| pending_op,
                .after => return error.ProgramContractViolation,
            };
            if (pending.session_id != request._session_id or
                pending.token != request.token or
                pending.op_index != request.op_index or
                pending.mode != request.mode or
                !pending.resume_ref.eql(request.resume_ref) or
                !pending.result_ref.eql(request.result_ref))
            {
                return error.ProgramContractViolation;
            }
            return pending;
        }

        fn checkedPendingAfter(self: *Self, request: AfterRequest) error{ProgramContractViolation}!PendingAfter {
            const pending = switch (self.pending orelse return error.ProgramContractViolation) {
                .op => return error.ProgramContractViolation,
                .after => |pending_after| pending_after,
            };
            if (pending.session_id != request._session_id or
                pending.token != request.token or
                pending.op_index != request.op_index or
                pending.remaining != request._remaining or
                !pending.value_ref.eql(request.value_ref) or
                !pending.output_ref.eql(request.output_ref) or
                !pending.result_ref.eql(request.result_ref))
            {
                return error.ProgramContractViolation;
            }
            return pending;
        }

        fn consumeCompleted(self: *Self) anyerror!Step {
            const result = self.completed orelse return error.ProgramContractViolation;
            self.completed = null;
            self.done_consumed = true;
            return .{ .done = .{
                .value = try decodeTypedValue(compiled_plan, schema_types, program_plan.functionResultRef(entry), result.value),
            } };
        }

        pub fn takeCompleted(self: *Self) anyerror!?RawResult {
            if (self.completed == null) return null;
            return switch (try self.consumeCompleted()) {
                .done => |done| done,
                .request => unreachable,
                .after => unreachable,
            };
        }
    };
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
        if (comptime !typeMatchesRef(compiled_plan, schema_types, ref, field.type)) {
            @compileError(
                "Body.encodeArgs tuple field type does not match ProgramPlan entry parameter " ++
                    std.fmt.comptimePrint("{d}", .{index}) ++
                    ": expected " ++
                    @typeName(ValueTypeForRef(compiled_plan, schema_types, ref)) ++
                    ", found " ++
                    @typeName(field.type),
            );
        }
        out[index] = encodeRuntimeValueForRef(compiled_plan, schema_types, ref, scratch, @field(args, field.name)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.ProgramContractViolation,
        };
    }
}

const PublicProgramValueArgsKind = enum {
    slice,
    array_pointer,
};

fn publicProgramValueArgsKind(comptime Args: type) ?PublicProgramValueArgsKind {
    if (Args == []const lowered_machine.ProgramValue or Args == []lowered_machine.ProgramValue) {
        return .slice;
    }
    return switch (@typeInfo(Args)) {
        .pointer => |pointer| switch (pointer.size) {
            .slice => if (pointer.child == lowered_machine.ProgramValue) .slice else null,
            .one => switch (@typeInfo(pointer.child)) {
                .array => |array| if (array.child == lowered_machine.ProgramValue) .array_pointer else null,
                else => null,
            },
            .many, .c => null,
        },
        else => null,
    };
}

fn publicProgramValueArgsSlice(args: anytype, comptime kind: PublicProgramValueArgsKind) []const lowered_machine.ProgramValue {
    return switch (kind) {
        .slice => args,
        .array_pointer => args[0..],
    };
}

fn encodeEntryArgs(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime schema_types: anytype,
    scratch: anytype,
    out: []ExecutableValue,
    args: anytype,
) (std.mem.Allocator.Error || error{ProgramContractViolation})!void {
    const public_args_kind = comptime publicProgramValueArgsKind(@TypeOf(args));
    if (comptime public_args_kind != null) {
        const public_args = publicProgramValueArgsSlice(args, public_args_kind.?);
        return encodePublicEntryArgs(compiled_plan, out, public_args);
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

fn supportNestedWithStringListTargetPlan() program_plan.ProgramPlan {
    const root = program_plan.program_plan_builder.function(0);
    const nested = program_plan.program_plan_builder.function(1);
    const root_value = program_plan.program_plan_builder.local(root, 0);
    const nested_value = program_plan.program_plan_builder.local(nested, 0);
    const instructions = [_]program_plan.Instruction{
        .{
            .kind = .call_nested_with,
            .dst = root_value.index,
            .aux = @intFromEnum(program_plan.ValueCodec.string_list),
            .string_literal = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi",
        },
        program_plan.program_plan_builder.returnValue(root, root_value) catch |err| supportPlanError(err),
        program_plan.program_plan_builder.callOp(nested, nested_value, program_plan.program_plan_builder.op(nested, 0), null) catch |err| supportPlanError(err),
        program_plan.program_plan_builder.returnValue(nested, nested_value) catch |err| supportPlanError(err),
    };
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .string_list,
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
            .symbol_name = "nested",
            .value_codec = .string_list,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 1,
            .local_count = 1,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 2,
            .instruction_count = 2,
        },
    };
    const requirements = [_]program_plan.RequirementPlan{.{ .label = "structured", .first_op = 0, .op_count = 1 }};
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "structured",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .string_list,
    }};
    const blocks = [_]program_plan.BlockPlan{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
    };
    const terminators = [_]program_plan.Terminator{ .{ .kind = .return_value }, .{ .kind = .return_value } };
    return program_plan.program_plan_builder.finish(.{
        .label = "nested-with-string-list-target",
        .ir_hash = 117,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .string_list }, .{ .codec = .string_list } },
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

test "ability.program executable capability ledger accepts string-list nested target results" {
    const targets = [_]NestedWithTarget{.{
        .metadata = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi",
        .function_index = 1,
    }};
    try validateTypedExecutablePlanSupportWithNestedTargets(supportNestedWithStringListTargetPlan(), &.{}, &targets);

    const ledger = ExecutableCapabilityLedgerForPlan(supportNestedWithStringListTargetPlan(), &.{}, &targets);
    try std.testing.expectEqual(@as(usize, 0), ledger.blockers.len);
    try std.testing.expect(!ledger.truncated);
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

test "Program.Session start failure owns moved scratch and frame buffers once" {
    const Session = ExecutableSessionForPlan(error{}, "support-parameter", supportParameterPlan(.i32), &.{}, &.{}, struct {});
    const bad_args = [_]lowered_machine.ProgramValue{.{ .bool = true }};

    try std.testing.expectError(
        error.ProgramContractViolation,
        Session.start(std.testing.allocator, bad_args[0..]),
    );
}

test "Program.Session terminal precheck preserves frames on caller result mismatch" {
    const functions = [_]program_plan.FunctionPlan{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .result_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 0,
            .first_instruction = 0,
            .instruction_count = 0,
        },
        .{
            .symbol_name = "helper",
            .value_codec = .unit,
            .result_codec = .string,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 0,
            .first_instruction = 0,
            .instruction_count = 0,
        },
    };
    const plan = program_plan.ProgramPlan{
        .label = "session-terminal-precheck",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &.{},
        .terminators = &.{},
        .instructions = &.{},
    };

    var scratch = try InterpreterScratch(0).init(std.testing.allocator, 0, 0);
    defer scratch.deinit();
    var frames = try ActiveFrameStack.init(std.testing.allocator, 2);
    defer frames.deinit(std.testing.allocator);
    defer while (frames.len() != 0) {
        const active = frames.pop().?;
        scratch.popFrame(active.frame);
    };

    const root_frame = try scratch.pushFrame(0);
    try frames.append(std.testing.allocator, .{
        .function_index = 0,
        .frame = root_frame,
        .block_index = 0,
        .instruction_index = 0,
        .instruction_end = 0,
    });
    const helper_frame = try scratch.pushFrame(0);
    try frames.append(std.testing.allocator, .{
        .function_index = 1,
        .frame = helper_frame,
        .block_index = 0,
        .instruction_index = 0,
        .instruction_end = 0,
    });

    try std.testing.expectError(
        error.ProgramContractViolation,
        validateSessionTerminalPropagation(plan, &scratch, &frames, .{ .string = "terminal" }),
    );
    try std.testing.expectEqual(@as(usize, 2), frames.len());
}
