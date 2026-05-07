// zlinter-disable require_doc_comment
const lowered_machine = @import("lowered_machine");
const program_plan = @import("internal_program_plan");
const std = @import("std");

pub const ProgramPlan = program_plan.ProgramPlan;
pub const ValueCodec = program_plan.ValueCodec;
pub const ExecutablePlanSupportError = error{
    UnsupportedHelperCycle,
    UnsupportedNestedWith,
    UnsupportedResultCodec,
    UnsupportedParameterCodec,
    UnsupportedPayloadCodec,
    UnsupportedResumeCodec,
    UnsupportedLocalCodec,
};

pub fn executableResultCodecForType(comptime T: type) program_plan.CodecError!program_plan.ValueCodec {
    return program_plan.codecForType(T);
}

pub fn executableResultCodecForPlan(comptime compiled_plan: program_plan.ProgramPlan) program_plan.ValueCodec {
    return program_plan.functionResultCodec(compiled_plan.functions[compiled_plan.entry_index]);
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

fn executableScalarCodec(comptime codec: program_plan.ValueCodec) bool {
    return switch (codec) {
        .unit, .bool, .i32, .usize, .string => true,
        .product, .sum, .string_list => false,
    };
}

fn instructionOwnerFunction(comptime compiled_plan: program_plan.ProgramPlan, comptime instruction_index: usize) ?program_plan.FunctionPlan {
    inline for (compiled_plan.functions) |function| {
        const instruction_end = @as(usize, function.first_instruction) + function.instruction_count;
        if (instruction_index >= function.first_instruction and instruction_index < instruction_end) return function;
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

const InterpreterFrame = struct {
    locals_start: usize,
    locals_len: usize,
    call_args_start: usize,
    after_start: usize,
};

const InterpreterScratch = struct {
    allocator: std.mem.Allocator,
    locals: std.ArrayList(lowered_machine.ProgramValue) = .empty,
    call_args: std.ArrayList(lowered_machine.ProgramValue) = .empty,
    after_stack: std.ArrayList(u16) = .empty,

    fn init(
        allocator: std.mem.Allocator,
        comptime compiled_plan: program_plan.ProgramPlan,
    ) std.mem.Allocator.Error!@This() {
        const analysis = comptime program_plan.entryExecutionAnalysis(compiled_plan) catch |err|
            @compileError("validated ProgramPlan entry analysis failed: " ++ @errorName(err));
        var scratch: @This() = .{ .allocator = allocator };
        errdefer scratch.deinit();
        try scratch.locals.ensureTotalCapacity(allocator, analysis.max_active_local_slots);
        try scratch.call_args.ensureTotalCapacity(allocator, analysis.max_active_call_arg_slots);
        if (analysis.reachable_after_count != 0) {
            try scratch.after_stack.ensureTotalCapacity(allocator, max_interpreter_steps);
        }
        return scratch;
    }

    fn deinit(self: *@This()) void {
        self.after_stack.deinit(self.allocator);
        self.call_args.deinit(self.allocator);
        self.locals.deinit(self.allocator);
    }

    fn pushFrame(self: *@This(), local_count: usize) std.mem.Allocator.Error!InterpreterFrame {
        const frame: InterpreterFrame = .{
            .locals_start = self.locals.items.len,
            .locals_len = local_count,
            .call_args_start = self.call_args.items.len,
            .after_start = self.after_stack.items.len,
        };
        try self.locals.resize(self.allocator, frame.locals_start + local_count);
        @memset(self.locals.items[frame.locals_start..][0..local_count], .none);
        return frame;
    }

    fn popFrame(self: *@This(), frame: InterpreterFrame) void {
        self.after_stack.shrinkRetainingCapacity(frame.after_start);
        self.call_args.shrinkRetainingCapacity(frame.call_args_start);
        self.locals.shrinkRetainingCapacity(frame.locals_start);
    }

    fn frameLocals(self: *@This(), frame: InterpreterFrame) []lowered_machine.ProgramValue {
        return self.locals.items[frame.locals_start..][0..frame.locals_len];
    }

    fn pushCallArgs(self: *@This(), count: usize) std.mem.Allocator.Error![]lowered_machine.ProgramValue {
        const start = self.call_args.items.len;
        try self.call_args.resize(self.allocator, start + count);
        return self.call_args.items[start..][0..count];
    }

    fn popCallArgs(self: *@This(), args: []const lowered_machine.ProgramValue) void {
        self.call_args.shrinkRetainingCapacity(self.call_args.items.len - args.len);
    }

    fn pushAfter(self: *@This(), op_index: u16) std.mem.Allocator.Error!void {
        try self.after_stack.append(self.allocator, op_index);
    }

    fn frameAfterStack(self: *@This(), frame: InterpreterFrame) []const u16 {
        return self.after_stack.items[frame.after_start..];
    }
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
    scratch: *InterpreterScratch,
    comptime function_index: usize,
    args: []const lowered_machine.ProgramValue,
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
            if (!valueMatchesCodec(local.codec, arg)) return error.ProgramContractViolation;
            locals[index] = arg;
        }
    }

    var block_index: usize = @as(usize, function.first_block) + function.entry_block;
    var last_return: lowered_machine.ProgramValue = .none;
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
                        if (callee.parameter_count == 0) break :blk &[_]lowered_machine.ProgramValue{};
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
                    const helper_result = executeFunction(ErrorSet, runtime, compiled_plan, handlers, scratch, instruction.operand, call_args, remaining_steps) catch |err| {
                        if (callee.parameter_count != 0) scratch.popCallArgs(call_args);
                        return err;
                    };
                    if (callee.parameter_count != 0) scratch.popCallArgs(call_args);
                    locals = scratch.frameLocals(frame);
                    if (helper_result.terminal) {
                        return .{
                            .value = try completeFunctionValue(
                                compiled_plan,
                                function_index,
                                handlers,
                                .{
                                    .value = helper_result.value,
                                    .initial_codec = program_plan.functionResultCodec(function),
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
                                    .after_stack = scratch.frameAfterStack(frame),
                                    .kind = .terminal,
                                },
                            ),
                            .terminal = true,
                        };
                    }
                    if (!valueMatchesCodec(op.resume_codec, op_result.value)) return error.ProgramContractViolation;
                    if (op.has_after) {
                        if (scratch.frameAfterStack(frame).len >= max_interpreter_steps) return error.ProgramContractViolation;
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
                    function_index,
                    handlers,
                    .{
                        .value = if (function.value_codec == .unit) .none else last_return,
                        .initial_codec = function.value_codec,
                        .after_stack = scratch.frameAfterStack(frame),
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
    handlers: anytype,
    scratch: *InterpreterScratch,
    function_index: usize,
    args: []const lowered_machine.ProgramValue,
    remaining_steps: *usize,
) anyerror!ExecutionResult {
    inline for (compiled_plan.functions, 0..) |_, index| {
        if (function_index == index) {
            return executeKnownFunction(ErrorSet, runtime, compiled_plan, handlers, scratch, index, args, remaining_steps);
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
    var remaining_steps: usize = max_interpreter_steps;
    var scratch = try InterpreterScratch.init(lowered_machine.runtimeAllocator(runtime), compiled_plan);
    defer scratch.deinit();
    const raw = try executeFunction(ErrorSet, runtime, compiled_plan, handlers, &scratch, compiled_plan.entry_index, args, &remaining_steps);
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

test "ability.program executable support ignores unreachable structured helper metadata" {
    try validateExecutablePlanSupport(supportUnreachableStructuredHelperPlan());
}

test "ability.program executable support ignores post-terminal structured helper metadata" {
    try validateExecutablePlanSupport(supportAbortBeforeStructuredHelperPlan());
    try validateExecutablePlanSupport(supportAbortBeforeStructuredSuccessorPlan());
    try validateExecutablePlanSupport(supportErrorBeforeStructuredHelperPlan());
}
