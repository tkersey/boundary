// zlinter-disable field_ordering - result union order stays value-first to match the interpreter control flow.
// zlinter-disable function_naming - internal codec helpers intentionally mirror the ProgramPlan vocabulary even when they return comptime types.
// zlinter-disable max_positional_args - the interpreter core keeps the live execution state explicit instead of packing it into a transient context struct.
// zlinter-disable no_undefined - fixed-size local helper buffers are completely overwritten before observation in the interpreter hot path.
const lowered_machine = @import("lowered_machine");
const program_plan = @import("internal_program_plan");
const std = @import("std");

fn sentinelBytes(comptime bytes: []const u8) [:0]const u8 {
    const raw = std.fmt.comptimePrint("{s}\x00", .{bytes});
    return raw[0..bytes.len :0];
}

fn decodeI32InstructionLiteral(instruction: program_plan.Instruction) i32 {
    const low = @as(u32, instruction.operand);
    const high = @as(u32, instruction.aux) << 16;
    return @bitCast(high | low);
}

fn decodeU32InstructionLiteral(instruction: program_plan.Instruction) u32 {
    const low = @as(u32, instruction.operand);
    const high = @as(u32, instruction.aux) << 16;
    return high | low;
}

fn functionLocalCodec(compiled_plan: program_plan.ProgramPlan, function: program_plan.FunctionPlan, local_id: u16) ?program_plan.ValueCodec {
    if (local_id >= function.local_count) return null;
    return compiled_plan.locals[function.first_local + local_id].codec;
}

fn entryOutputsForPlan(comptime compiled_plan: program_plan.ProgramPlan) []const program_plan.OutputPlan {
    const entry_function = compiled_plan.functions[compiled_plan.entry_index];
    return compiled_plan.outputs[entry_function.first_output..][0..entry_function.output_count];
}

/// Return the concrete output bundle type for one executable ProgramPlan.
pub fn ResultOutputsTypeForPlan(comptime compiled_plan: program_plan.ProgramPlan) type {
    const outputs = comptime entryOutputsForPlan(compiled_plan);
    var fields = [_]std.builtin.Type.StructField{.{
        .name = "",
        .type = void,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = @alignOf(void),
    }} ** outputs.len;
    inline for (outputs, 0..) |output, index| {
        fields[index] = .{
            .name = sentinelBytes(output.label),
            .type = runtimeValueType(output.codec),
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(runtimeValueType(output.codec)),
        };
    }
    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

/// Return the typed native run result for one executable ProgramPlan.
pub fn RunResultTypeForPlan(comptime compiled_plan: program_plan.ProgramPlan) type {
    return struct {
        outputs: ResultOutputsTypeForPlan(compiled_plan),
        value: runtimeValueType(program_plan.functionResultCodec(compiled_plan.functions[compiled_plan.entry_index])),
    };
}

fn runtimeValueType(comptime codec: program_plan.ValueCodec) type {
    return switch (codec) {
        .unit => void,
        .bool => bool,
        .i32 => i32,
        .string => []const u8,
        .string_list => [][]const u8,
        .usize => usize,
    };
}

fn decodeRuntimeValue(comptime codec: program_plan.ValueCodec, value: lowered_machine.ProgramValue) runtimeValueType(codec) {
    return switch (codec) {
        .unit => {},
        .bool => switch (value) {
            .bool => |typed| typed,
            else => unreachable,
        },
        .i32 => switch (value) {
            .i32 => |typed| typed,
            else => unreachable,
        },
        .string => switch (value) {
            .string => |typed| typed,
            else => unreachable,
        },
        .usize => switch (value) {
            .usize => |typed| typed,
            else => unreachable,
        },
        .string_list => unreachable,
    };
}

fn runtimeValueMatchesCodec(comptime codec: program_plan.ValueCodec, value: lowered_machine.ProgramValue) bool {
    return switch (codec) {
        .unit => value == .none,
        .bool => value == .bool,
        .i32 => value == .i32,
        .string => value == .string,
        .usize => value == .usize,
        .string_list => false,
    };
}

fn encodeRuntimeValue(comptime codec: program_plan.ValueCodec, value: anytype) lowered_machine.ProgramValue {
    return switch (codec) {
        .unit => .none,
        .bool => .{ .bool = value },
        .i32 => .{ .i32 = value },
        .string => .{ .string = value },
        .usize => .{ .usize = value },
        .string_list => unreachable,
    };
}

/// Reject unsupported codecs before native direct-handler execution.
pub fn assertExecutableCodecSupport(comptime compiled_plan: program_plan.ProgramPlan) void {
    inline for (compiled_plan.functions) |function| switch (function.value_codec) {
        .unit, .bool, .i32, .string, .usize => {},
        .string_list => @compileError("public lowering runtime plan rejected string_list values across executable boundaries"),
    };
    inline for (compiled_plan.functions) |function| {
        if (function.result_codec) |codec| switch (codec) {
            .unit, .bool, .i32, .string, .usize => {},
            .string_list => @compileError("public lowering runtime plan rejected string_list values across executable boundaries"),
        };
    }
    inline for (compiled_plan.ops) |op| {
        inline for ([_]program_plan.ValueCodec{ op.payload_codec, op.resume_codec }) |codec| switch (codec) {
            .unit, .bool, .i32, .string, .usize => {},
            .string_list => @compileError("public lowering runtime plan rejected string_list values across executable boundaries"),
        };
    }
}

fn afterMethodName(comptime op_name: []const u8) []const u8 {
    var buffer: [5 + op_name.len]u8 = undefined;
    var len: usize = 0;
    buffer[len..][0..5].* = "after".*;
    len += 5;
    var upper_next = true;
    inline for (op_name) |byte| {
        if (byte == '_') {
            buffer[len] = byte;
            len += 1;
            upper_next = true;
            continue;
        }
        buffer[len] = if (upper_next and byte >= 'a' and byte <= 'z') byte - 32 else byte;
        len += 1;
        upper_next = false;
    }
    return buffer[0..len];
}

const OpResume = struct {
    value: lowered_machine.ProgramValue,
    apply_after: bool,
};

const OpResult = union(enum) {
    resumed: OpResume,
    terminal: lowered_machine.ProgramValue,
};

/// One direct native function result while interpreting a ProgramPlan.
pub const FunctionResult = union(enum) {
    value: lowered_machine.ProgramValue,
    terminal: lowered_machine.ProgramValue,
};

fn callOp(
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers_ptr: anytype,
    comptime function_result_codec: program_plan.ValueCodec,
    op_index: u16,
    payload: lowered_machine.ProgramValue,
) anyerror!OpResult {
    if (compiled_plan.ops.len == 0) return error.ProgramContractViolation;
    return switch (op_index) {
        inline 0...(compiled_plan.ops.len - 1) => |active_index| blk: {
            const op = compiled_plan.ops[active_index];
            const requirement = compiled_plan.requirements[op.requirement_index];
            const handler_ptr = &@field(handlers_ptr.*, requirement.label);
            const HandlerType = @TypeOf(handler_ptr.*);
            const method = @field(HandlerType, op.op_name);
            const ResumeType = runtimeValueType(op.resume_codec);
            const ResultType = runtimeValueType(function_result_codec);
            const after_name = comptime afterMethodName(op.op_name);
            const has_after = @hasDecl(HandlerType, after_name);

            switch (op.mode) {
                .transform => {
                    if (op.payload_codec == .unit) {
                        const result = try resolveMaybeError(@call(.auto, method, .{handler_ptr}));
                        break :blk .{ .resumed = .{
                            .value = if (op.resume_codec == .unit)
                                .none
                            else
                                encodeRuntimeValue(op.resume_codec, result),
                            .apply_after = has_after,
                        } };
                    }

                    const PayloadType = runtimeValueType(op.payload_codec);
                    const decoded_payload = decodeRuntimeValue(op.payload_codec, payload);
                    const result = try resolveMaybeError(@call(.auto, method, .{ handler_ptr, @as(PayloadType, decoded_payload) }));
                    break :blk .{ .resumed = .{
                        .value = if (op.resume_codec == .unit)
                            .none
                        else
                            encodeRuntimeValue(op.resume_codec, @as(ResumeType, result)),
                        .apply_after = has_after,
                    } };
                },
                .choice => {
                    const decision = if (op.payload_codec == .unit)
                        try resolveMaybeError(@call(.auto, method, .{handler_ptr}))
                    else blk_decision: {
                        const PayloadType = runtimeValueType(op.payload_codec);
                        const decoded_payload = decodeRuntimeValue(op.payload_codec, payload);
                        break :blk_decision try resolveMaybeError(@call(.auto, method, .{ handler_ptr, @as(PayloadType, decoded_payload) }));
                    };
                    break :blk switch (decision) {
                        .resume_with => |resume_value| .{ .resumed = .{
                            .value = if (op.resume_codec == .unit)
                                .none
                            else
                                encodeRuntimeValue(op.resume_codec, @as(ResumeType, resume_value)),
                            .apply_after = has_after,
                        } },
                        .return_now => |answer| .{ .terminal = encodeRuntimeValue(function_result_codec, @as(ResultType, answer)) },
                    };
                },
                .abort => {
                    const answer = if (op.payload_codec == .unit)
                        try resolveMaybeError(@call(.auto, method, .{handler_ptr}))
                    else blk_answer: {
                        const PayloadType = runtimeValueType(op.payload_codec);
                        const decoded_payload = decodeRuntimeValue(op.payload_codec, payload);
                        break :blk_answer try resolveMaybeError(@call(.auto, method, .{ handler_ptr, @as(PayloadType, decoded_payload) }));
                    };
                    break :blk .{ .terminal = encodeRuntimeValue(function_result_codec, @as(ResultType, answer)) };
                },
            }
        },
        else => error.ProgramContractViolation,
    };
}

fn applyAfter(
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers_ptr: anytype,
    comptime function_value_codec: program_plan.ValueCodec,
    comptime function_result_codec: program_plan.ValueCodec,
    op_index: u16,
    answer: lowered_machine.ProgramValue,
) anyerror!lowered_machine.ProgramValue {
    if (compiled_plan.ops.len == 0) return error.ProgramContractViolation;
    return switch (op_index) {
        inline 0...(compiled_plan.ops.len - 1) => |active_index| blk: {
            const op = compiled_plan.ops[active_index];
            const requirement = compiled_plan.requirements[op.requirement_index];
            const handler_ptr = &@field(handlers_ptr.*, requirement.label);
            const HandlerType = @TypeOf(handler_ptr.*);
            const after_name = comptime afterMethodName(op.op_name);
            if (!@hasDecl(HandlerType, after_name)) break :blk answer;

            const InputType = runtimeValueType(function_value_codec);
            const ResultType = runtimeValueType(function_result_codec);
            const method = @field(HandlerType, after_name);
            const decoded_answer = decodeRuntimeValue(function_value_codec, answer);
            const transformed_answer = try resolveMaybeError(@call(.auto, method, .{ handler_ptr, @as(InputType, decoded_answer) }));
            break :blk encodeRuntimeValue(function_result_codec, @as(ResultType, transformed_answer));
        },
        else => error.ProgramContractViolation,
    };
}

fn unwindAfterStack(
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers_ptr: anytype,
    comptime function_value_codec: program_plan.ValueCodec,
    comptime function_result_codec: program_plan.ValueCodec,
    after_stack: *std.ArrayList(u16),
    result: FunctionResult,
) anyerror!FunctionResult {
    var final_result = result;
    while (after_stack.items.len != 0) {
        const op_index = after_stack.pop().?;
        final_result = switch (final_result) {
            .value => |typed| .{ .value = try applyAfter(compiled_plan, handlers_ptr, function_value_codec, function_result_codec, op_index, typed) },
            .terminal => |typed| .{ .terminal = typed },
        };
    }
    return final_result;
}

fn continueFunction(
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers_ptr: anytype,
    comptime function_index: usize,
    locals: []lowered_machine.ProgramValue,
    after_stack: *std.ArrayList(u16),
    initial_block_index: u16,
    initial_instruction_index: u16,
    initial_return_local: ?u16,
) anyerror!FunctionResult {
    const function = compiled_plan.functions[function_index];
    const function_result_codec = comptime program_plan.functionResultCodec(function);
    var current_block_index = initial_block_index;
    var instruction_index = initial_instruction_index;
    var return_local = initial_return_local;

    while (true) {
        const block = compiled_plan.blocks[current_block_index];
        const instruction_end = block.first_instruction + block.instruction_count;
        while (instruction_index < instruction_end) : (instruction_index += 1) {
            const instruction = compiled_plan.instructions[instruction_index];
            switch (instruction.kind) {
                .add_i32 => setLocal(locals, instruction.dst, .{
                    .i32 = switch (getLocal(locals, instruction.operand)) {
                        .i32 => |left| switch (getLocal(locals, instruction.aux)) {
                            .i32 => |right| try checkedAddI32(left, right),
                            else => unreachable,
                        },
                        else => unreachable,
                    },
                }),
                .add_const_i32 => setLocal(locals, instruction.dst, switch (getLocal(locals, instruction.operand)) {
                    .i32 => |typed| .{ .i32 = try checkedAddI32(typed, @as(i32, @intCast(instruction.aux))) },
                    else => unreachable,
                }),
                .call_helper => {
                    const callee = compiled_plan.functions[instruction.operand];
                    const helper_result_codec = program_plan.functionResultCodec(callee);
                    var helper_args_storage: [helperArgStorageCapacity(compiled_plan)]lowered_machine.ProgramValue = undefined;
                    const helper_args = helper_args: {
                        if (callee.parameter_count == 0) break :helper_args &.{};
                        const call_arg_end = instruction.aux + callee.parameter_count;
                        if (call_arg_end > compiled_plan.call_args.len) return error.ProgramContractViolation;
                        for (compiled_plan.call_args[instruction.aux..call_arg_end], 0..) |local_id, arg_index| {
                            if (local_id >= locals.len) return error.ProgramContractViolation;
                            helper_args_storage[arg_index] = getLocal(locals, local_id);
                        }
                        break :helper_args helper_args_storage[0..callee.parameter_count];
                    };
                    const result = try executeDispatch(compiled_plan, handlers_ptr, instruction.operand, helper_args);
                    switch (result) {
                        .value => |typed| {
                            if (instruction.dst < locals.len and helper_result_codec != .unit) {
                                setLocal(locals, instruction.dst, typed);
                            }
                        },
                        .terminal => |terminal| {
                            if (!runtimeValueMatchesCodec(function_result_codec, terminal)) return error.ProgramContractViolation;
                            return unwindAfterStack(
                                compiled_plan,
                                handlers_ptr,
                                function.value_codec,
                                function_result_codec,
                                after_stack,
                                .{ .terminal = terminal },
                            );
                        },
                    }
                },
                .call_op => {
                    const op = compiled_plan.ops[instruction.operand];
                    const payload = if (op.payload_codec == .unit)
                        .none
                    else if (instruction.aux < locals.len)
                        getLocal(locals, instruction.aux)
                    else
                        return error.ProgramContractViolation;
                    const result = try callOp(compiled_plan, handlers_ptr, function_result_codec, instruction.operand, payload);
                    switch (result) {
                        .resumed => |resumed_value| {
                            if (instruction.dst < locals.len and op.resume_codec != .unit) {
                                setLocal(locals, instruction.dst, resumed_value.value);
                            }
                            if (resumed_value.apply_after) {
                                try after_stack.append(std.heap.page_allocator, instruction.operand);
                            }
                        },
                        .terminal => |terminal| return unwindAfterStack(
                            compiled_plan,
                            handlers_ptr,
                            function.value_codec,
                            function_result_codec,
                            after_stack,
                            .{ .terminal = terminal },
                        ),
                    }
                },
                .compare_eq_zero => setLocal(locals, instruction.dst, .{
                    .bool = switch (getLocal(locals, instruction.operand)) {
                        .i32 => |typed| typed == 0,
                        .usize => |typed| typed == 0,
                        else => unreachable,
                    },
                }),
                .const_i32 => setLocal(locals, instruction.dst, switch (functionLocalCodec(compiled_plan, function, instruction.dst) orelse return error.ProgramContractViolation) {
                    .i32 => .{ .i32 = decodeI32InstructionLiteral(instruction) },
                    .usize => .{ .usize = decodeU32InstructionLiteral(instruction) },
                    else => return error.ProgramContractViolation,
                }),
                .const_usize => setLocal(locals, instruction.dst, .{
                    .usize = std.fmt.parseUnsigned(usize, instruction.string_literal, 0) catch
                        return error.ProgramContractViolation,
                }),
                .const_string => setLocal(locals, instruction.dst, .{ .string = instruction.string_literal }),
                .return_value => return_local = instruction.operand,
                .sub_one => setLocal(locals, instruction.dst, switch (getLocal(locals, instruction.operand)) {
                    .i32 => |typed| .{ .i32 = typed - 1 },
                    .usize => |typed| .{ .usize = typed - 1 },
                    else => unreachable,
                }),
            }
        }

        const terminator = compiled_plan.terminators[block.terminator_index];
        switch (terminator.kind) {
            .branch_if => {
                if (instruction_end == block.first_instruction) return error.ProgramContractViolation;
                const predicate_instruction = compiled_plan.instructions[instruction_end - 1];
                if (predicate_instruction.kind != .compare_eq_zero or predicate_instruction.dst >= locals.len) {
                    return error.ProgramContractViolation;
                }
                const predicate = switch (getLocal(locals, predicate_instruction.dst)) {
                    .bool => |typed| typed,
                    else => return error.ProgramContractViolation,
                };
                current_block_index = if (predicate) terminator.primary else terminator.secondary;
                instruction_index = compiled_plan.blocks[current_block_index].first_instruction;
                return_local = null;
            },
            .jump => {
                current_block_index = terminator.primary;
                instruction_index = compiled_plan.blocks[current_block_index].first_instruction;
                return_local = null;
            },
            .return_unit => return unwindAfterStack(
                compiled_plan,
                handlers_ptr,
                function.value_codec,
                function_result_codec,
                after_stack,
                .{ .value = .none },
            ),
            .return_value => return unwindAfterStack(
                compiled_plan,
                handlers_ptr,
                function.value_codec,
                function_result_codec,
                after_stack,
                .{ .value = getLocal(locals, return_local orelse return error.ProgramContractViolation) },
            ),
        }
    }
}

fn executeFunction(
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers_ptr: anytype,
    comptime function_index: usize,
    args: []const lowered_machine.ProgramValue,
) anyerror!FunctionResult {
    const function = compiled_plan.functions[function_index];
    var locals_storage: [function.local_count]lowered_machine.ProgramValue = [_]lowered_machine.ProgramValue{.none} ** function.local_count;
    const locals = locals_storage[0..];
    if (args.len != function.parameter_count) return error.ProgramContractViolation;
    for (args, 0..) |arg, arg_index| {
        setLocal(locals, @intCast(arg_index), arg);
    }

    var after_stack = std.ArrayList(u16).empty;
    defer after_stack.deinit(std.heap.page_allocator);

    const entry_block_index = function.first_block + function.entry_block;
    return continueFunction(
        compiled_plan,
        handlers_ptr,
        function_index,
        locals,
        &after_stack,
        entry_block_index,
        compiled_plan.blocks[entry_block_index].first_instruction,
        null,
    );
}

/// Execute one ProgramPlan function through direct Zig handler dispatch.
pub fn executeDispatch(
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers_ptr: anytype,
    function_index: u16,
    args: []const lowered_machine.ProgramValue,
) anyerror!FunctionResult {
    if (compiled_plan.functions.len == 0) return error.ProgramContractViolation;
    return switch (function_index) {
        inline 0...(compiled_plan.functions.len - 1) => |active_index| executeFunction(compiled_plan, handlers_ptr, active_index, args),
        else => error.ProgramContractViolation,
    };
}

fn maxFunctionParameterCount(comptime compiled_plan: program_plan.ProgramPlan) usize {
    var max_count: usize = 0;
    for (compiled_plan.functions) |function| {
        if (function.parameter_count > max_count) max_count = function.parameter_count;
    }
    return max_count;
}

fn helperArgStorageCapacity(comptime compiled_plan: program_plan.ProgramPlan) usize {
    return @max(@as(usize, 1), maxFunctionParameterCount(compiled_plan));
}

fn requirementForOutputLabel(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime label: []const u8,
) ?program_plan.RequirementPlan {
    inline for (compiled_plan.requirements) |requirement| {
        if (std.mem.eql(u8, requirement.label, label)) return requirement;
    }
    return null;
}

/// Finalize the declared entry outputs for one ProgramPlan from the current handlers.
pub fn collectOutputsForPlan(
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers_ptr: anytype,
) anyerror!ResultOutputsTypeForPlan(compiled_plan) {
    const outputs = comptime entryOutputsForPlan(compiled_plan);
    var value: ResultOutputsTypeForPlan(compiled_plan) = std.mem.zeroInit(ResultOutputsTypeForPlan(compiled_plan), .{});
    inline for (outputs) |output| {
        const handler_ptr = &@field(handlers_ptr.*, output.label);
        const requirement = comptime requirementForOutputLabel(compiled_plan, output.label) orelse
            @compileError("ProgramPlan outputs must map to one requirement");
        switch (comptime requirement.output_tag) {
            .none => {
                if (@hasDecl(@TypeOf(handler_ptr.*), "finish")) {
                    @field(value, output.label) = try resolveMaybeError(handler_ptr.finish());
                    continue;
                }
                if (@hasField(@TypeOf(handler_ptr.*), "state")) {
                    @field(value, output.label) = handler_ptr.state;
                    continue;
                }
                return error.ProgramContractViolation;
            },
            .accumulator, .custom_finalizer => {
                if (!@hasDecl(@TypeOf(handler_ptr.*), "finish")) return error.ProgramContractViolation;
                @field(value, output.label) = try resolveMaybeError(handler_ptr.finish());
            },
            .final_state => {
                if (@hasDecl(@TypeOf(handler_ptr.*), "finish")) {
                    @field(value, output.label) = try resolveMaybeError(handler_ptr.finish());
                    continue;
                }
                if (@hasField(@TypeOf(handler_ptr.*), "state")) {
                    @field(value, output.label) = handler_ptr.state;
                    continue;
                }
                return error.ProgramContractViolation;
            },
        }
    }
    return value;
}

fn setLocal(locals: []lowered_machine.ProgramValue, index: u16, value: lowered_machine.ProgramValue) void {
    locals[index] = value;
}

fn getLocal(locals: []lowered_machine.ProgramValue, index: u16) lowered_machine.ProgramValue {
    return locals[index];
}

fn resolveMaybeError(value: anytype) anyerror!switch (@typeInfo(@TypeOf(value))) {
    .error_union => |info| info.payload,
    else => @TypeOf(value),
} {
    return if (@typeInfo(@TypeOf(value)) == .error_union) try value else value;
}

fn checkedAddI32(left: i32, right: i32) anyerror!i32 {
    return std.math.add(i32, left, right) catch return error.ProgramContractViolation;
}

/// Execute the entry function of one ProgramPlan and finalize its outputs.
pub fn runEntry(
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers: anytype,
) anyerror!RunResultTypeForPlan(compiled_plan) {
    try lowered_machine.beginExecution(runtime);
    defer lowered_machine.endExecution(runtime);
    const outcome = try executeDispatch(compiled_plan, handlers, compiled_plan.entry_index, &.{});
    const value = switch (outcome) {
        .value => |typed| typed,
        .terminal => |typed| typed,
    };
    return .{
        .outputs = try collectOutputsForPlan(compiled_plan, handlers),
        .value = decodeRuntimeValue(program_plan.functionResultCodec(compiled_plan.functions[compiled_plan.entry_index]), value),
    };
}

/// Execute the entry function of one ProgramPlan with explicit runtime entry arguments and finalize its outputs.
pub fn runEntryWithArgs(
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers: anytype,
    args: []const lowered_machine.ProgramValue,
) anyerror!RunResultTypeForPlan(compiled_plan) {
    try lowered_machine.beginExecution(runtime);
    defer lowered_machine.endExecution(runtime);
    const outcome = try executeDispatch(compiled_plan, handlers, compiled_plan.entry_index, args);
    const value = switch (outcome) {
        .value => |typed| typed,
        .terminal => |typed| typed,
    };
    return .{
        .outputs = try collectOutputsForPlan(compiled_plan, handlers),
        .value = decodeRuntimeValue(program_plan.functionResultCodec(compiled_plan.functions[compiled_plan.entry_index]), value),
    };
}
