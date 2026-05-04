// zlinter-disable require_doc_comment
const lowered_machine = @import("lowered_machine");
const program_plan = @import("internal_program_plan");
const std = @import("std");

pub const ProgramPlan = program_plan.ProgramPlan;
pub const ValueCodec = program_plan.ValueCodec;
pub const ExecutablePlanSupportError = error{
    UnsupportedNestedWith,
};

pub fn executableResultCodecForType(comptime T: type) program_plan.CodecError!program_plan.ValueCodec {
    return program_plan.codecForType(T);
}

pub fn executableResultCodecForPlan(comptime compiled_plan: program_plan.ProgramPlan) program_plan.ValueCodec {
    return program_plan.functionResultCodec(compiled_plan.functions[compiled_plan.entry_index]);
}

pub fn validateExecutablePlanSupport(comptime compiled_plan: program_plan.ProgramPlan) ExecutablePlanSupportError!void {
    for (compiled_plan.instructions) |instruction| {
        if (instruction.kind == .call_nested_with) return error.UnsupportedNestedWith;
    }
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

fn encodeScalarValue(value: anytype) lowered_machine.ProgramValue {
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

fn decodeArg(
    comptime codec: program_plan.ValueCodec,
    value: lowered_machine.ProgramValue,
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
        .string_list => error.ProgramContractViolation,
        .product, .sum => error.ProgramContractViolation,
    };
}

fn valueMatchesCodec(codec: program_plan.ValueCodec, value: lowered_machine.ProgramValue) bool {
    return switch (codec) {
        .unit => value == .none,
        .bool => value == .bool,
        .i32 => value == .i32,
        .usize => value == .usize,
        .string => value == .string,
        .string_list, .product, .sum => false,
    };
}

fn codecForScalarValue(value: lowered_machine.ProgramValue) program_plan.ValueCodec {
    return switch (value) {
        .none => .unit,
        .bool => .bool,
        .i32 => .i32,
        .usize => .usize,
        .string => .string,
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

const OperationDispatch = struct {
    value: lowered_machine.ProgramValue,
    resumes: bool,
};

const ExecutionResult = struct {
    value: lowered_machine.ProgramValue,
    terminal: bool,
};

const AfterApplication = struct {
    value: lowered_machine.ProgramValue,
    codec: program_plan.ValueCodec,
};

const CompletionKind = enum {
    normal,
    terminal,
};

const CompletionValue = struct {
    value: lowered_machine.ProgramValue,
    initial_codec: program_plan.ValueCodec,
    after_stack: []const u16,
    kind: CompletionKind,
};

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
    return switch (@typeInfo(HandlersPtr)) {
        .pointer => |pointer| if (pointer.is_const) *const Field else *Field,
        else => *Field,
    };
}

fn handlerFieldPtr(handlers: anytype, comptime field_name: []const u8) HandlerFieldPtrType(@TypeOf(handlers), field_name) {
    return switch (@typeInfo(@TypeOf(handlers))) {
        .pointer => &@field(handlers.*, field_name),
        else => &@field(handlers, field_name),
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

fn afterDispatchAccepts(comptime AuthoredPtr: type, comptime input_codec: program_plan.ValueCodec) bool {
    return switch (input_codec) {
        .unit, .bool, .i32, .usize, .string => blk: {
            const Authored = HandlerType(AuthoredPtr);
            const after_dispatch_info = @typeInfo(@TypeOf(Authored.afterDispatch)).@"fn";
            if (after_dispatch_info.params.len != 2) break :blk false;
            const ValueParamType = after_dispatch_info.params[1].type orelse break :blk false;
            break :blk ValueParamType == ValueTypeForCodec(input_codec);
        },
        .string_list, .product, .sum => false,
    };
}

fn dispatchAuthored(
    comptime op: program_plan.OpPlan,
    authored: anytype,
    payload: lowered_machine.ProgramValue,
) anyerror!OperationDispatch {
    const dispatched = switch (comptime op.payload_codec) {
        .unit => try authored.dispatch(),
        .bool => try authored.dispatch(try decodeArg(.bool, payload)),
        .i32 => try authored.dispatch(try decodeArg(.i32, payload)),
        .usize => try authored.dispatch(try decodeArg(.usize, payload)),
        .string => try authored.dispatch(try decodeArg(.string, payload)),
        .string_list, .product, .sum => return error.ProgramContractViolation,
    };
    return switch (comptime op.mode) {
        .abort => .{
            .value = encodeScalarValue(dispatched),
            .resumes = false,
        },
        .transform => .{
            .value = encodeScalarValue(dispatched),
            .resumes = true,
        },
        .choice => switch (dispatched) {
            .resume_with => |resume_value| .{
                .value = encodeScalarValue(resume_value),
                .resumes = true,
            },
            .return_now => |answer| .{
                .value = encodeScalarValue(answer),
                .resumes = false,
            },
        },
    };
}

fn callOpByIndex(
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers: anytype,
    op_index: u16,
    payload: lowered_machine.ProgramValue,
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
            const result = try dispatchAuthored(op, authored, payload);
            if (result.resumes and !valueMatchesCodec(op.resume_codec, result.value)) return error.ProgramContractViolation;
            return result;
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

fn applyAfterByIndexForCodec(
    comptime input_codec: program_plan.ValueCodec,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime function_index: usize,
    handlers: anytype,
    op_index: u16,
    value: lowered_machine.ProgramValue,
) anyerror!AfterApplication {
    _ = function_index;
    inline for (compiled_plan.ops, 0..) |op, index| {
        if (op_index == index) {
            if (!op.has_after) return error.ProgramContractViolation;
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
            if (comptime !afterDispatchAccepts(@TypeOf(authored), input_codec)) return error.ProgramContractViolation;
            const decoded = try decodeArg(input_codec, value);
            const completed = try authored.afterDispatch(decoded);
            const encoded = encodeScalarValue(completed);
            return .{
                .value = encoded,
                .codec = codecForScalarValue(encoded),
            };
        }
    }
    return error.ProgramContractViolation;
}

fn applyAfterByIndex(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime function_index: usize,
    handlers: anytype,
    op_index: u16,
    value: lowered_machine.ProgramValue,
    current_codec: program_plan.ValueCodec,
) anyerror!AfterApplication {
    return switch (current_codec) {
        .unit => applyAfterByIndexForCodec(.unit, compiled_plan, function_index, handlers, op_index, value),
        .bool => applyAfterByIndexForCodec(.bool, compiled_plan, function_index, handlers, op_index, value),
        .i32 => applyAfterByIndexForCodec(.i32, compiled_plan, function_index, handlers, op_index, value),
        .usize => applyAfterByIndexForCodec(.usize, compiled_plan, function_index, handlers, op_index, value),
        .string => applyAfterByIndexForCodec(.string, compiled_plan, function_index, handlers, op_index, value),
        .string_list, .product, .sum => error.ProgramContractViolation,
    };
}

fn completeFunctionValue(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime function_index: usize,
    handlers: anytype,
    completion: CompletionValue,
) anyerror!lowered_machine.ProgramValue {
    const function = comptime compiled_plan.functions[function_index];
    const result_codec = comptime program_plan.functionResultCodec(function);
    var completed = completion.value;
    var current_codec = completion.initial_codec;
    if (completion.kind == .normal) {
        var remaining = completion.after_stack.len;
        while (remaining != 0) {
            remaining -= 1;
            const after = try applyAfterByIndex(compiled_plan, function_index, handlers, completion.after_stack[remaining], completed, current_codec);
            completed = after.value;
            current_codec = after.codec;
        }
    }
    const final_codec = if (completion.kind == .terminal or completion.after_stack.len != 0) result_codec else function.value_codec;
    if (!valueMatchesCodec(final_codec, completed)) return error.ProgramContractViolation;
    return completed;
}

// zlinter-disable max_positional_args - interpreter recursion keeps the comptime plan, error set, handler bundle, and call frame explicit.
fn executeKnownFunction(
    comptime ErrorSet: type,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers: anytype,
    comptime function_index: usize,
    args: []const lowered_machine.ProgramValue,
    remaining_steps: *usize,
) anyerror!ExecutionResult {
    if (comptime function_index >= compiled_plan.functions.len) return error.ProgramContractViolation;
    const function = comptime compiled_plan.functions[function_index];
    if (args.len != function.parameter_count) return error.ProgramContractViolation;

    const allocator = lowered_machine.runtimeAllocator(runtime);
    const locals = try allocator.alloc(lowered_machine.ProgramValue, function.local_count);
    defer allocator.free(locals);
    @memset(locals, .none);
    if (comptime function.parameter_count != 0) {
        for (args, 0..) |arg, index| {
            const local = compiled_plan.locals[function.first_local + index];
            if (!valueMatchesCodec(local.codec, arg)) return error.ProgramContractViolation;
            locals[index] = arg;
        }
    }

    var block_index: usize = @as(usize, function.first_block) + function.entry_block;
    var last_return: lowered_machine.ProgramValue = .none;
    var last_condition: bool = false;
    const after_stack = try allocator.alloc(u16, max_interpreter_steps);
    defer allocator.free(after_stack);
    var after_count: usize = 0;
    while (true) {
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
                    const buffer = try allocator.alloc(lowered_machine.ProgramValue, callee.parameter_count);
                    defer allocator.free(buffer);
                    const call_args = blk: {
                        if (callee.parameter_count == 0) break :blk &[_]lowered_machine.ProgramValue{};
                        if (instruction.aux == std.math.maxInt(u16)) return error.ProgramContractViolation;
                        if (comptime compiled_plan.call_args.len == 0) return error.ProgramContractViolation;

                        const arg_start = instruction.aux;
                        for (0..callee.parameter_count) |arg_index| {
                            const local_id = planCallArgAt(compiled_plan, arg_start + arg_index);
                            if (local_id >= locals.len) return error.ProgramContractViolation;
                            buffer[arg_index] = locals[local_id];
                        }
                        break :blk buffer[0..callee.parameter_count];
                    };
                    const helper_result = try executeFunction(ErrorSet, runtime, compiled_plan, handlers, instruction.operand, call_args, remaining_steps);
                    if (helper_result.terminal) {
                        return .{
                            .value = try completeFunctionValue(
                                compiled_plan,
                                function_index,
                                handlers,
                                .{
                                    .value = helper_result.value,
                                    .initial_codec = program_plan.functionResultCodec(function),
                                    .after_stack = after_stack[0..after_count],
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
                    const op_result = try callOpByIndex(compiled_plan, handlers, instruction.operand, payload);
                    if (!op_result.resumes) {
                        return .{
                            .value = try completeFunctionValue(
                                compiled_plan,
                                function_index,
                                handlers,
                                .{
                                    .value = op_result.value,
                                    .initial_codec = program_plan.functionResultCodec(function),
                                    .after_stack = after_stack[0..after_count],
                                    .kind = .terminal,
                                },
                            ),
                            .terminal = true,
                        };
                    }
                    if (!valueMatchesCodec(op.resume_codec, op_result.value)) return error.ProgramContractViolation;
                    if (op.has_after) {
                        if (after_count >= after_stack.len) return error.ProgramContractViolation;
                        after_stack[after_count] = instruction.operand;
                        after_count += 1;
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
                    function_index,
                    handlers,
                    .{
                        .value = if (function.value_codec == .unit) .none else last_return,
                        .initial_codec = function.value_codec,
                        .after_stack = after_stack[0..after_count],
                        .kind = .normal,
                    },
                ),
                .terminal = false,
            },
            .return_value => return .{
                .value = try completeFunctionValue(
                    compiled_plan,
                    function_index,
                    handlers,
                    .{
                        .value = last_return,
                        .initial_codec = function.value_codec,
                        .after_stack = after_stack[0..after_count],
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
    handlers: anytype,
    function_index: usize,
    args: []const lowered_machine.ProgramValue,
    remaining_steps: *usize,
) anyerror!ExecutionResult {
    inline for (compiled_plan.functions, 0..) |_, index| {
        if (function_index == index) {
            return executeKnownFunction(ErrorSet, runtime, compiled_plan, handlers, index, args, remaining_steps);
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

    const entry = comptime compiled_plan.functions[compiled_plan.entry_index];
    if (args.len != entry.parameter_count) return error.ProgramContractViolation;
    var remaining_steps: usize = max_interpreter_steps;
    const raw = try executeFunction(ErrorSet, runtime, compiled_plan, handlers, compiled_plan.entry_index, args, &remaining_steps);
    return .{ .value = try decodeArg(program_plan.functionResultCodec(entry), raw.value) };
}

pub fn runExecutablePlanWithArgs(
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers: anytype,
    args: []const lowered_machine.ProgramValue,
) anyerror!RunResultTypeForPlan(compiled_plan) {
    return runExecutablePlanWithArgsForErrorSet(error{}, runtime, compiled_plan, handlers, args);
}
