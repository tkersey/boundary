// zlinter-disable field_ordering - result union order stays value-first to match the interpreter control flow.
// zlinter-disable declaration_naming - nested lexical metadata fixtures intentionally mirror source-visible declarations.
// zlinter-disable function_naming - internal codec helpers intentionally mirror the ProgramPlan vocabulary even when they return comptime types.
// zlinter-disable max_positional_args - the interpreter core keeps the live execution state explicit instead of packing it into a transient context struct.
// zlinter-disable no_undefined - fixed-size local helper buffers are completely overwritten before observation in the interpreter hot path.
// zlinter-disable require_doc_comment - executable plan interpreter helpers are internal runtime glue, not user-facing API docs.
const lowered_machine = @import("lowered_machine");
const nested_named_carrier_runtime = @import("nested_named_carrier_runtime.zig");
const program_plan = @import("internal_program_plan");
const std = @import("std");

/// Resource envelope for native ProgramPlan execution.
pub const RunOptions = struct {
    max_block_steps: usize = 100_000,
    max_instruction_steps: usize = 1_000_000,
    max_call_depth: usize = 256,
    max_after_frames: usize = 100_000,
};

const ExecutionBudget = struct {
    block_steps: usize = 0,
    instruction_steps: usize = 0,
    active_call_depth: usize = 0,
    pending_after_frames: usize = 0,
};

const ExecutionContext = struct {
    options: RunOptions = .{},
    budget: ExecutionBudget = .{},

    fn chargeBlockStep(self: *@This()) !void {
        self.budget.block_steps = std.math.add(usize, self.budget.block_steps, 1) catch
            return error.ExecutionBudgetExceeded;
        if (self.budget.block_steps > self.options.max_block_steps) return error.ExecutionBudgetExceeded;
    }

    fn chargeInstructionStep(self: *@This()) !void {
        self.budget.instruction_steps = std.math.add(usize, self.budget.instruction_steps, 1) catch
            return error.ExecutionBudgetExceeded;
        if (self.budget.instruction_steps > self.options.max_instruction_steps) return error.ExecutionBudgetExceeded;
    }

    fn enterFunctionCall(self: *@This()) !void {
        self.budget.active_call_depth = std.math.add(usize, self.budget.active_call_depth, 1) catch
            return error.ExecutionBudgetExceeded;
        if (self.budget.active_call_depth > self.options.max_call_depth) {
            self.budget.active_call_depth -= 1;
            return error.ExecutionBudgetExceeded;
        }
    }

    fn leaveFunctionCall(self: *@This()) void {
        self.budget.active_call_depth -= 1;
    }

    fn reserveAfterFrame(self: *@This()) !void {
        self.budget.pending_after_frames = std.math.add(usize, self.budget.pending_after_frames, 1) catch
            return error.ExecutionBudgetExceeded;
        if (self.budget.pending_after_frames > self.options.max_after_frames) {
            self.budget.pending_after_frames -= 1;
            return error.ExecutionBudgetExceeded;
        }
    }

    fn releaseAfterFrame(self: *@This()) void {
        std.debug.assert(self.budget.pending_after_frames != 0);
        self.budget.pending_after_frames -= 1;
    }
};

fn sentinelBytes(comptime bytes: []const u8) [:0]const u8 {
    const raw = std.fmt.comptimePrint("{s}\x00", .{bytes});
    return raw[0..bytes.len :0];
}

fn decodeI32InstructionLiteral(instruction: program_plan.Instruction) i32 {
    const low = @as(u32, instruction.operand);
    const high = @as(u32, instruction.aux) << 16;
    return @bitCast(high | low);
}

fn functionLocalCodec(compiled_plan: program_plan.ProgramPlan, function: program_plan.FunctionPlan, local_id: u16) ?program_plan.ValueCodec {
    if (local_id >= function.local_count) return null;
    return compiled_plan.locals[function.first_local + local_id].codec;
}

fn functionOwnsOpTarget(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime function: program_plan.FunctionPlan,
    comptime target: u16,
) bool {
    if (target >= compiled_plan.ops.len) return false;
    const requirement_index = compiled_plan.ops[target].requirement_index;
    const requirement_end = function.first_requirement + function.requirement_count;
    return requirement_index >= function.first_requirement and requirement_index < requirement_end;
}

fn entryOutputsForPlan(comptime compiled_plan: program_plan.ProgramPlan) []const program_plan.OutputPlan {
    const entry_function = compiled_plan.functions[compiled_plan.entry_index];
    return compiled_plan.outputs[entry_function.first_output..][0..entry_function.output_count];
}

/// Return the concrete output bundle type for one executable ProgramPlan.
pub fn ResultOutputsTypeForPlan(comptime compiled_plan: program_plan.ProgramPlan) type {
    const outputs = comptime entryOutputsForPlan(compiled_plan);
    var field_names = [_][:0]const u8{""} ** outputs.len;
    var field_types = [_]type{void} ** outputs.len;
    var field_attrs = [_]std.builtin.Type.StructField.Attributes{.{}} ** outputs.len;
    inline for (outputs, 0..) |output, index| {
        const FieldType = runtimeValueType(output.codec);
        field_names[index] = sentinelBytes(output.label);
        field_types[index] = FieldType;
        field_attrs[index] = .{ .@"align" = @alignOf(FieldType) };
    }
    return @Struct(.auto, null, &field_names, &field_types, &field_attrs);
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

const nested_with_metadata_delimiter = "\x1f";

const NestedWithMetadata = struct {
    requirement_label: []const u8,
    runtime_container_name: []const u8,
    runtime_field_name: []const u8,
    factory_name: []const u8,
    container_name: []const u8,
    handler_name: []const u8,
    carrier_name: ?[]const u8,
    source_path: ?[]const u8,
    body_symbol: ?[]const u8,
};

fn parseNestedWithMetadata(comptime encoded: []const u8) NestedWithMetadata {
    comptime var parts: [9][]const u8 = undefined;
    comptime var part_index: usize = 0;
    comptime var start: usize = 0;
    comptime var index: usize = 0;
    inline while (index <= encoded.len) : (index += 1) {
        const is_delimiter = index == encoded.len or std.mem.startsWith(u8, encoded[index..], nested_with_metadata_delimiter);
        if (!is_delimiter) continue;
        if (part_index >= parts.len) @compileError("nested lexical with metadata carried too many segments");
        parts[part_index] = encoded[start..index];
        part_index += 1;
        if (index != encoded.len) {
            index += nested_with_metadata_delimiter.len - 1;
            start = index + 1;
        }
    }
    if (part_index != parts.len) @compileError("nested lexical with metadata is malformed");
    return .{
        .requirement_label = parts[0],
        .runtime_container_name = parts[1],
        .runtime_field_name = parts[2],
        .factory_name = parts[3],
        .container_name = parts[4],
        .handler_name = parts[5],
        .carrier_name = if (parts[6].len == 0) null else parts[6],
        .source_path = if (parts[7].len == 0) null else parts[7],
        .body_symbol = if (parts[8].len == 0) null else parts[8],
    };
}

fn nestedWithSourceModule(comptime SourceModule: type) type {
    return SourceModule;
}

fn singleFieldStructType(comptime field_name: []const u8, comptime FieldType: type) type {
    const names = [_][:0]const u8{sentinelBytes(field_name)};
    const types = [_]type{FieldType};
    const attrs = [_]std.builtin.Type.StructField.Attributes{.{ .@"align" = @alignOf(FieldType) }};
    return @Struct(.auto, null, &names, &types, &attrs);
}

fn isGeneratedFamilyDescriptorWrapper(comptime HandlerType: type) bool {
    return @hasField(HandlerType, "handler") and
        @hasDecl(HandlerType, "BindingSchema") and
        @hasDecl(HandlerType, "HandleType") and
        @hasDecl(HandlerType, "bindLexical") and
        @hasDecl(HandlerType, "run");
}

fn EffectiveHandlerPtrType(comptime PtrType: type) type {
    const HandlerType = std.meta.Child(PtrType);
    return if (isGeneratedFamilyDescriptorWrapper(HandlerType))
        *@FieldType(HandlerType, "handler")
    else
        PtrType;
}

fn effectiveHandlerPtr(handler_ptr: anytype) EffectiveHandlerPtrType(@TypeOf(handler_ptr)) {
    if (comptime isGeneratedFamilyDescriptorWrapper(@TypeOf(handler_ptr.*))) {
        return &handler_ptr.handler;
    }
    return handler_ptr;
}

fn encodeTypedProgramValue(value: anytype) lowered_machine.ProgramValue {
    const ValueType = @TypeOf(value);
    if (ValueType == void) return .none;
    if (ValueType == bool) return .{ .bool = value };
    if (ValueType == i32) return .{ .i32 = value };
    if (ValueType == []const u8) return .{ .string = value };
    if (ValueType == usize) return .{ .usize = value };
    @compileError("nested lexical with execution only supports void, bool, i32, []const u8, and usize results");
}

fn executeNestedWithInstruction(
    comptime SourceModule: type,
    comptime metadata_source: []const u8,
    comptime result_codec: program_plan.ValueCodec,
    runtime: *lowered_machine.Runtime,
    ctx: *ExecutionContext,
) anyerror!lowered_machine.ProgramValue {
    _ = runtime;
    const metadata = comptime parseNestedWithMetadata(metadata_source);
    const carrier_name = metadata.carrier_name orelse @compileError("nested lexical with metadata requires a named body carrier");
    const nested_runtime = try nestedRuntimePointer(SourceModule, metadata);
    const nested_carrier = nested_named_carrier_runtime.NamedNestedCarrier(
        SourceModule,
        metadata.requirement_label,
        metadata.factory_name,
        metadata.container_name,
        metadata.handler_name,
        carrier_name,
        metadata.source_path orelse @compileError("named nested lexical metadata requires a source_path"),
        metadata.body_symbol orelse @compileError("named nested lexical metadata requires a body_symbol"),
    );
    const nested_result_codec = comptime program_plan.functionResultCodec(nested_carrier.compiled_plan_value.functions[nested_carrier.compiled_plan_value.entry_index]);
    if (comptime nested_result_codec != result_codec) return error.ProgramContractViolation;
    const HandlersType = singleFieldStructType(metadata.requirement_label, nested_carrier.descriptor_type);
    var handlers: HandlersType = undefined;
    @field(handlers, metadata.requirement_label) = nested_carrier.descriptor();
    const result = try runEntryInSourceWithContext(nested_runtime, nested_carrier.compiled_plan_value, SourceModule, &handlers, &.{}, ctx);
    const encoded = encodeTypedProgramValue(result.value);
    if (!runtimeValueMatchesCodec(result_codec, encoded)) return error.ProgramContractViolation;
    return encoded;
}

fn nestedRuntimePointer(
    comptime SourceModule: type,
    comptime metadata: NestedWithMetadata,
) anyerror!*lowered_machine.Runtime {
    const source_module = nestedWithSourceModule(SourceModule);
    if (!@hasDecl(source_module, metadata.runtime_container_name)) {
        @compileError("nested lexical with runtime argument must name a source-visible runtime container");
    }
    const RuntimeContainer = @field(source_module, metadata.runtime_container_name);
    if (!@hasDecl(RuntimeContainer, metadata.runtime_field_name)) {
        @compileError("nested lexical with runtime argument must name a source-visible runtime pointer field");
    }
    return @field(RuntimeContainer, metadata.runtime_field_name) orelse error.ProgramContractViolation;
}

fn executeNestedWithAtInstruction(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime SourceModule: type,
    instruction_index: u16,
    runtime: *lowered_machine.Runtime,
    ctx: *ExecutionContext,
) anyerror!lowered_machine.ProgramValue {
    return switch (instruction_index) {
        inline 0...(compiled_plan.instructions.len - 1) => |active_index| blk: {
            const instruction = compiled_plan.instructions[active_index];
            if (instruction.kind != .call_nested_with) break :blk error.ProgramContractViolation;
            const result_codec: ?program_plan.ValueCodec = comptime program_plan.valueCodecFromInstructionAux(instruction.aux) catch null;
            if (comptime result_codec == null) break :blk error.ProgramContractViolation;
            break :blk try executeNestedWithInstruction(SourceModule, instruction.string_literal, result_codec.?, runtime, ctx);
        },
        else => error.ProgramContractViolation,
    };
}

fn executeReturnErrorAtInstruction(
    comptime compiled_plan: program_plan.ProgramPlan,
    instruction_index: u16,
) anyerror {
    return switch (instruction_index) {
        inline 0...(compiled_plan.instructions.len - 1) => |active_index| blk: {
            const instruction = compiled_plan.instructions[active_index];
            if (instruction.kind != .return_error or instruction.string_literal.len == 0) {
                break :blk error.ProgramContractViolation;
            }
            break :blk @field(anyerror, instruction.string_literal);
        },
        else => error.ProgramContractViolation,
    };
}

fn runtimeValueMatchesCodec(codec: program_plan.ValueCodec, value: lowered_machine.ProgramValue) bool {
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

fn legacyAfterMethodName(comptime op_name: []const u8) []const u8 {
    var buffer: [5 + op_name.len]u8 = undefined;
    var len: usize = 0;
    buffer[len..][0..5].* = "after".*;
    len += 5;
    var upper_next = true;
    inline for (op_name) |byte| {
        if (byte == '_') {
            upper_next = true;
            continue;
        }
        buffer[len] = if (upper_next and byte >= 'a' and byte <= 'z') byte - 32 else byte;
        len += 1;
        upper_next = false;
    }
    return buffer[0..len];
}

fn resolvedAfterMethodName(comptime HandlerType: type, comptime op_name: []const u8) ?[]const u8 {
    const underscored_name = comptime afterMethodName(op_name);
    if (@hasDecl(HandlerType, underscored_name)) return underscored_name;
    const legacy_name = comptime legacyAfterMethodName(op_name);
    if (!std.mem.eql(u8, legacy_name, underscored_name) and @hasDecl(HandlerType, legacy_name)) return legacy_name;
    return null;
}

const OpResume = struct {
    value: lowered_machine.ProgramValue,
    apply_after: bool,
};

const OpResult = union(enum) {
    resumed: OpResume,
    terminal: lowered_machine.ProgramValue,
};

fn opRequiresAfterFrame(
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers_ptr: anytype,
    op_index: u16,
) anyerror!bool {
    if (compiled_plan.ops.len == 0) return error.ProgramContractViolation;
    return switch (op_index) {
        inline 0...(compiled_plan.ops.len - 1) => |active_index| blk: {
            const op = compiled_plan.ops[active_index];
            if (!op.has_after or op.mode == .abort) break :blk false;
            const requirement = compiled_plan.requirements[op.requirement_index];
            const handler_ptr = effectiveHandlerPtr(&@field(handlers_ptr.*, requirement.label));
            const HandlerType = @TypeOf(handler_ptr.*);
            break :blk comptime resolvedAfterMethodName(HandlerType, op.op_name) != null;
        },
        else => error.ProgramContractViolation,
    };
}

/// One direct native function result while interpreting a ProgramPlan.
pub const FunctionResult = union(enum) {
    value: lowered_machine.ProgramValue,
    terminal: lowered_machine.ProgramValue,
};

const UnitCompletionMode = enum {
    helper_allows_unit_completion,
    strict_result_codec,
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
            const handler_ptr = effectiveHandlerPtr(&@field(handlers_ptr.*, requirement.label));
            const HandlerType = @TypeOf(handler_ptr.*);
            const method = @field(HandlerType, op.op_name);
            const ResumeType = runtimeValueType(op.resume_codec);
            const ResultType = runtimeValueType(function_result_codec);
            const maybe_after_name = comptime resolvedAfterMethodName(HandlerType, op.op_name);
            const has_after = op.has_after and maybe_after_name != null;

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
    comptime function: program_plan.FunctionPlan,
    handlers_ptr: anytype,
    comptime function_value_codec: program_plan.ValueCodec,
    comptime function_result_codec: program_plan.ValueCodec,
    op_index: u16,
    answer: lowered_machine.ProgramValue,
) anyerror!lowered_machine.ProgramValue {
    if (compiled_plan.ops.len == 0) return error.ProgramContractViolation;
    return switch (op_index) {
        inline 0...(compiled_plan.ops.len - 1) => |active_index| blk: {
            if (!comptime functionOwnsOpTarget(compiled_plan, function, @intCast(active_index))) break :blk answer;
            const op = compiled_plan.ops[active_index];
            if (!op.has_after) break :blk answer;
            const requirement = compiled_plan.requirements[op.requirement_index];
            const handler_ptr = effectiveHandlerPtr(&@field(handlers_ptr.*, requirement.label));
            const HandlerType = @TypeOf(handler_ptr.*);
            const maybe_after_name = comptime resolvedAfterMethodName(HandlerType, op.op_name);
            const after_name = maybe_after_name orelse break :blk answer;

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
    ctx: *ExecutionContext,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime function: program_plan.FunctionPlan,
    handlers_ptr: anytype,
    comptime function_value_codec: program_plan.ValueCodec,
    comptime function_result_codec: program_plan.ValueCodec,
    comptime unit_completion_mode: UnitCompletionMode,
    after_stack: *std.ArrayList(u16),
    result: FunctionResult,
) anyerror!FunctionResult {
    if (function_value_codec != function_result_codec) switch (result) {
        .value => |typed| if (after_stack.items.len != 1 and
            !(unit_completion_mode == .helper_allows_unit_completion and function_value_codec == .unit and typed == .none and after_stack.items.len == 0))
        {
            return error.ProgramContractViolation;
        },
        .terminal => {},
    };
    var final_result = result;
    while (after_stack.items.len != 0) {
        const op_index = after_stack.pop().?;
        ctx.releaseAfterFrame();
        final_result = switch (final_result) {
            .value => |typed| .{ .value = try applyAfter(compiled_plan, function, handlers_ptr, function_value_codec, function_result_codec, op_index, typed) },
            .terminal => |typed| .{ .terminal = typed },
        };
    }
    return final_result;
}

fn continueFunction(
    ctx: *ExecutionContext,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime NestedSourceModule: type,
    handlers_ptr: anytype,
    comptime function_index: usize,
    locals: []lowered_machine.ProgramValue,
    after_stack: *std.ArrayList(u16),
    initial_block_index: u16,
    initial_instruction_index: u16,
    initial_return_local: ?u16,
    comptime unit_completion_mode: UnitCompletionMode,
) anyerror!FunctionResult {
    const function = compiled_plan.functions[function_index];
    const function_result_codec = comptime program_plan.functionResultCodec(function);
    var current_block_index = initial_block_index;
    var instruction_index = initial_instruction_index;
    var return_local = initial_return_local;

    while (true) {
        try ctx.chargeBlockStep();
        const block = compiled_plan.blocks[current_block_index];
        const instruction_end = block.first_instruction + block.instruction_count;
        while (instruction_index < instruction_end) : (instruction_index += 1) {
            try ctx.chargeInstructionStep();
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
                    const result = switch (instruction.operand) {
                        inline 0...(compiled_plan.functions.len - 1) => |helper_index| try executeFunction(
                            ctx,
                            runtime,
                            compiled_plan,
                            NestedSourceModule,
                            handlers_ptr,
                            helper_index,
                            helper_args,
                            .helper_allows_unit_completion,
                        ),
                        else => return error.ProgramContractViolation,
                    };
                    switch (result) {
                        .value => |typed| {
                            const completion_codec = if (runtimeValueMatchesCodec(callee.value_codec, typed))
                                callee.value_codec
                            else if (runtimeValueMatchesCodec(helper_result_codec, typed))
                                helper_result_codec
                            else
                                return error.ProgramContractViolation;
                            if (completion_codec != .unit) {
                                if (instruction.dst >= locals.len or
                                    functionLocalCodec(compiled_plan, function, instruction.dst) != completion_codec)
                                {
                                    return error.ProgramContractViolation;
                                }
                                setLocal(locals, instruction.dst, typed);
                            }
                        },
                        .terminal => |terminal| {
                            if (!runtimeValueMatchesCodec(function_result_codec, terminal)) return error.ProgramContractViolation;
                            return unwindAfterStack(
                                ctx,
                                compiled_plan,
                                function,
                                handlers_ptr,
                                function.value_codec,
                                function_result_codec,
                                unit_completion_mode,
                                after_stack,
                                .{ .terminal = terminal },
                            );
                        },
                    }
                },
                .call_nested_with => {
                    const nested_result = try executeNestedWithAtInstruction(
                        compiled_plan,
                        NestedSourceModule,
                        instruction_index,
                        runtime,
                        ctx,
                    );
                    const nested_codec = program_plan.valueCodecFromInstructionAux(instruction.aux) catch
                        return error.ProgramContractViolation;
                    if (nested_codec != .unit) {
                        if (instruction.dst >= locals.len) return error.ProgramContractViolation;
                        setLocal(locals, instruction.dst, nested_result);
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
                    const reserve_after_frame = try opRequiresAfterFrame(compiled_plan, handlers_ptr, instruction.operand);
                    if (reserve_after_frame) try ctx.reserveAfterFrame();
                    var reserved_after_frame = reserve_after_frame;
                    errdefer if (reserved_after_frame) ctx.releaseAfterFrame();
                    const result = try callOp(compiled_plan, handlers_ptr, function_result_codec, instruction.operand, payload);
                    switch (result) {
                        .resumed => |resumed_value| {
                            if (instruction.dst < locals.len and op.resume_codec != .unit) {
                                setLocal(locals, instruction.dst, resumed_value.value);
                            }
                            if (resumed_value.apply_after) {
                                if (!reserved_after_frame) return error.ProgramContractViolation;
                                try after_stack.append(std.heap.page_allocator, instruction.operand);
                                reserved_after_frame = false;
                            } else if (reserved_after_frame) {
                                ctx.releaseAfterFrame();
                                reserved_after_frame = false;
                            }
                        },
                        .terminal => |terminal| {
                            if (reserved_after_frame) {
                                ctx.releaseAfterFrame();
                                reserved_after_frame = false;
                            }
                            return unwindAfterStack(
                                ctx,
                                compiled_plan,
                                function,
                                handlers_ptr,
                                function.value_codec,
                                function_result_codec,
                                unit_completion_mode,
                                after_stack,
                                .{ .terminal = terminal },
                            );
                        },
                    }
                },
                .compare_eq_zero => setLocal(locals, instruction.dst, .{
                    .bool = switch (getLocal(locals, instruction.operand)) {
                        .bool => |typed| !typed,
                        .i32 => |typed| typed == 0,
                        .usize => |typed| typed == 0,
                        else => unreachable,
                    },
                }),
                .const_i32 => setLocal(locals, instruction.dst, switch (functionLocalCodec(compiled_plan, function, instruction.dst) orelse return error.ProgramContractViolation) {
                    .i32 => .{ .i32 = decodeI32InstructionLiteral(instruction) },
                    else => return error.ProgramContractViolation,
                }),
                .const_usize => setLocal(locals, instruction.dst, .{
                    .usize = std.fmt.parseUnsigned(usize, instruction.string_literal, 0) catch
                        return error.ProgramContractViolation,
                }),
                .const_string => setLocal(locals, instruction.dst, .{ .string = instruction.string_literal }),
                .return_error => return executeReturnErrorAtInstruction(compiled_plan, instruction_index),
                .return_value => return_local = instruction.operand,
                .sub_one => setLocal(locals, instruction.dst, switch (getLocal(locals, instruction.operand)) {
                    .i32 => |typed| .{ .i32 = try checkedSubI32(typed, 1) },
                    .usize => |typed| .{ .usize = try checkedSubUsize(typed, 1) },
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
                ctx,
                compiled_plan,
                function,
                handlers_ptr,
                function.value_codec,
                function_result_codec,
                unit_completion_mode,
                after_stack,
                .{ .value = .none },
            ),
            .return_value => return unwindAfterStack(
                ctx,
                compiled_plan,
                function,
                handlers_ptr,
                function.value_codec,
                function_result_codec,
                unit_completion_mode,
                after_stack,
                .{ .value = getLocal(locals, return_local orelse return error.ProgramContractViolation) },
            ),
        }
    }
}

fn executeFunction(
    ctx: *ExecutionContext,
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime NestedSourceModule: type,
    handlers_ptr: anytype,
    comptime function_index: usize,
    args: []const lowered_machine.ProgramValue,
    comptime unit_completion_mode: UnitCompletionMode,
) anyerror!FunctionResult {
    try ctx.enterFunctionCall();
    defer ctx.leaveFunctionCall();

    const function = compiled_plan.functions[function_index];
    var locals_storage: [function.local_count]lowered_machine.ProgramValue = [_]lowered_machine.ProgramValue{.none} ** function.local_count;
    const locals = locals_storage[0..];
    if (args.len != function.parameter_count) return error.ProgramContractViolation;
    for (args, 0..) |arg, arg_index| {
        const expected_codec = functionLocalCodec(compiled_plan, function, @intCast(arg_index)) orelse
            return error.ProgramContractViolation;
        if (!runtimeValueMatchesCodec(expected_codec, arg)) return error.ProgramContractViolation;
        setLocal(locals, @intCast(arg_index), arg);
    }

    var after_stack = std.ArrayList(u16).empty;
    defer after_stack.deinit(std.heap.page_allocator);

    const entry_block_index = function.first_block + function.entry_block;
    return continueFunction(
        ctx,
        runtime,
        compiled_plan,
        NestedSourceModule,
        handlers_ptr,
        function_index,
        locals,
        &after_stack,
        entry_block_index,
        compiled_plan.blocks[entry_block_index].first_instruction,
        null,
        unit_completion_mode,
    );
}

/// Execute one ProgramPlan function through direct Zig handler dispatch.
pub fn executeDispatchInSource(
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime NestedSourceModule: type,
    handlers_ptr: anytype,
    function_index: u16,
    args: []const lowered_machine.ProgramValue,
) anyerror!FunctionResult {
    var ctx: ExecutionContext = .{};
    return try executeDispatchInSourceWithOptions(runtime, compiled_plan, NestedSourceModule, handlers_ptr, function_index, args, &ctx);
}

fn executeDispatchInSourceWithOptions(
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime NestedSourceModule: type,
    handlers_ptr: anytype,
    function_index: u16,
    args: []const lowered_machine.ProgramValue,
    ctx: *ExecutionContext,
) anyerror!FunctionResult {
    if (compiled_plan.functions.len == 0) return error.ProgramContractViolation;
    return switch (function_index) {
        inline 0...(compiled_plan.functions.len - 1) => |active_index| executeFunction(
            ctx,
            runtime,
            compiled_plan,
            NestedSourceModule,
            handlers_ptr,
            active_index,
            args,
            .strict_result_codec,
        ),
        else => error.ProgramContractViolation,
    };
}

pub fn executeDispatch(
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers_ptr: anytype,
    function_index: u16,
    args: []const lowered_machine.ProgramValue,
) anyerror!FunctionResult {
    return try executeDispatchInSource(runtime, compiled_plan, @import("root"), handlers_ptr, function_index, args);
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

fn entryRequirementForOutputLabel(
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime label: []const u8,
) ?program_plan.RequirementPlan {
    const entry_function = compiled_plan.functions[compiled_plan.entry_index];
    const entry_requirements = compiled_plan.requirements[entry_function.first_requirement..][0..entry_function.requirement_count];
    inline for (entry_requirements) |requirement| {
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
        const requirement = comptime entryRequirementForOutputLabel(compiled_plan, output.label) orelse
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

fn checkedSubI32(left: i32, right: i32) anyerror!i32 {
    return std.math.sub(i32, left, right) catch return error.ProgramContractViolation;
}

fn checkedSubUsize(left: usize, right: usize) anyerror!usize {
    return std.math.sub(usize, left, right) catch return error.ProgramContractViolation;
}

fn runEntryInSourceWithContext(
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime NestedSourceModule: type,
    handlers: anytype,
    args: []const lowered_machine.ProgramValue,
    ctx: *ExecutionContext,
) anyerror!RunResultTypeForPlan(compiled_plan) {
    try lowered_machine.beginExecution(runtime);
    defer lowered_machine.endExecution(runtime);
    const outcome = try executeDispatchInSourceWithOptions(runtime, compiled_plan, NestedSourceModule, handlers, compiled_plan.entry_index, args, ctx);
    const value = switch (outcome) {
        .value => |typed| typed,
        .terminal => |typed| typed,
    };
    return .{
        .outputs = try collectOutputsForPlan(compiled_plan, handlers),
        .value = decodeRuntimeValue(program_plan.functionResultCodec(compiled_plan.functions[compiled_plan.entry_index]), value),
    };
}

/// Execute the entry function of one ProgramPlan and finalize its outputs.
pub fn runEntryInSource(
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime NestedSourceModule: type,
    handlers: anytype,
) anyerror!RunResultTypeForPlan(compiled_plan) {
    return try runEntryInSourceWithOptions(runtime, compiled_plan, NestedSourceModule, handlers, .{});
}

pub fn runEntryInSourceWithOptions(
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime NestedSourceModule: type,
    handlers: anytype,
    options: RunOptions,
) anyerror!RunResultTypeForPlan(compiled_plan) {
    var ctx: ExecutionContext = .{ .options = options };
    return try runEntryInSourceWithContext(runtime, compiled_plan, NestedSourceModule, handlers, &.{}, &ctx);
}

pub fn runEntry(
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers: anytype,
) anyerror!RunResultTypeForPlan(compiled_plan) {
    return try runEntryInSource(runtime, compiled_plan, @import("root"), handlers);
}

pub fn runEntryWithOptions(
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers: anytype,
    options: RunOptions,
) anyerror!RunResultTypeForPlan(compiled_plan) {
    return try runEntryInSourceWithOptions(runtime, compiled_plan, @import("root"), handlers, options);
}

/// Execute the entry function of one ProgramPlan with explicit runtime entry arguments and finalize its outputs.
pub fn runEntryWithArgsInSource(
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime NestedSourceModule: type,
    handlers: anytype,
    args: []const lowered_machine.ProgramValue,
) anyerror!RunResultTypeForPlan(compiled_plan) {
    return try runEntryWithArgsInSourceWithOptions(runtime, compiled_plan, NestedSourceModule, handlers, args, .{});
}

pub fn runEntryWithArgsInSourceWithOptions(
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime NestedSourceModule: type,
    handlers: anytype,
    args: []const lowered_machine.ProgramValue,
    options: RunOptions,
) anyerror!RunResultTypeForPlan(compiled_plan) {
    var ctx: ExecutionContext = .{ .options = options };
    return try runEntryInSourceWithContext(runtime, compiled_plan, NestedSourceModule, handlers, args, &ctx);
}

pub fn runEntryWithArgs(
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers: anytype,
    args: []const lowered_machine.ProgramValue,
) anyerror!RunResultTypeForPlan(compiled_plan) {
    return try runEntryWithArgsInSource(runtime, compiled_plan, @import("root"), handlers, args);
}

pub fn runEntryWithArgsAndOptions(
    runtime: *lowered_machine.Runtime,
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers: anytype,
    args: []const lowered_machine.ProgramValue,
    options: RunOptions,
) anyerror!RunResultTypeForPlan(compiled_plan) {
    return try runEntryWithArgsInSourceWithOptions(runtime, compiled_plan, @import("root"), handlers, args, options);
}

test "program plan interpreter rejects const_i32 instructions targeting usize locals" {
    const compiled_plan: program_plan.ProgramPlan = .{
        .label = "interpreter.invalid.const_i32_into_usize",
        .ir_hash = 0x305,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .value_codec = .usize,
            .parameter_count = 0,
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
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .usize }},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{
                .kind = .const_i32,
                .dst = 0,
                .operand = @as(u16, @bitCast(@as(i16, -1))),
                .aux = @as(u16, @bitCast(@as(i16, -1))),
            },
            .{ .kind = .return_value, .operand = 0 },
        },
    };
    try compiled_plan.validate();

    var handlers = struct {}{};
    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectError(error.ProgramContractViolation, executeDispatch(&runtime, compiled_plan, &handlers, 0, &.{}));
}

test "program plan interpreter rejects invalid call_nested_with aux codecs" {
    const compiled_plan: program_plan.ProgramPlan = .{
        .label = "interpreter.invalid.call_nested_with_aux_codec",
        .ir_hash = 0x306,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .value_codec = .unit,
            .parameter_count = 0,
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
        }},
        .requirements = &.{.{ .label = "req", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{
            .requirement_index = 0,
            .op_name = "noop",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .unit,
        }},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{.{
            .kind = .call_nested_with,
            .aux = 256,
            .string_literal = "nested\x1fruntime\x1fptr\x1ffactory\x1fcontainer\x1fhandler\x1f\x1f\x1f",
        }},
    };

    var handlers = struct {
        req: struct {
            /// Compile-only no-op handler for unreachable call_op branches.
            pub fn noop(_: *@This()) void {
                // The malformed nested-with instruction returns before this handler can run.
            }
        } = .{},
    }{};
    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectError(error.ProgramContractViolation, executeDispatch(&runtime, compiled_plan, &handlers, 0, &.{}));
}

const NestedBudgetTestSource = struct {
    pub const RuntimeBox = struct {
        pub threadlocal var ptr: ?*lowered_machine.Runtime = null;
    };

    const ResumeFamily = struct {
        pub const ops = .{struct {
            pub const name: [:0]const u8 = "step";
            pub const control_mode = enum { abort, choice, transform }.transform;
            pub const Payload = void;
            pub const Resume = i32;
            pub const after = enum { binding_optional, none }.none;
        }};
    };

    pub const Handlers = struct {
        pub const InnerHandler = struct {};
    };

    pub const ResumeFactory = struct {
        pub fn use(_: anytype) ResumeDescriptor {
            return .{};
        }
    };

    pub const ResumeDescriptor = struct {
        pub fn BindingSchema(comptime label: [:0]const u8) type {
            return struct {
                pub const requirement_label = label;
                pub const Family = ResumeFamily;
                pub const Handler = Handlers.InnerHandler;
            };
        }

        pub fn step(_: *@This()) i32 {
            return 1;
        }
    };
};

test "program plan interpreter applies caller budget to nested lexical with bodies" {
    const compiled_plan: program_plan.ProgramPlan = .{
        .label = "interpreter.budget.nested_lexical_with",
        .ir_hash = 0x30e,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .value_codec = .unit,
            .parameter_count = 0,
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
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{.{
            .kind = .call_nested_with,
            .dst = 0,
            .aux = @intFromEnum(program_plan.ValueCodec.i32),
            .string_literal = "inner" ++
                "\x1fRuntimeBox" ++
                "\x1fptr" ++
                "\x1fResumeFactory" ++
                "\x1fHandlers" ++
                "\x1fInnerHandler" ++
                "\x1fnested_budget" ++
                "\x1fsrc/internal/program_plan_interpreter.zig" ++
                "\x1fNestedBudgetTestSource",
        }},
    };
    try compiled_plan.validate();

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    NestedBudgetTestSource.RuntimeBox.ptr = &runtime;
    defer NestedBudgetTestSource.RuntimeBox.ptr = null;

    var handlers = struct {}{};
    try std.testing.expectError(
        error.ExecutionBudgetExceeded,
        runEntryInSourceWithOptions(&runtime, compiled_plan, NestedBudgetTestSource, &handlers, .{ .max_block_steps = 1 }),
    );
}

test "program plan interpreter gates after frames on plan metadata" {
    const compiled_plan: program_plan.ProgramPlan = .{
        .label = "interpreter.after_frame_plan_metadata_gate",
        .ir_hash = 0x30b,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .value_codec = .unit,
            .result_codec = .string,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{
            .requirement_index = 0,
            .op_name = "dispatch",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .unit,
            .has_after = false,
        }},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{.{ .kind = .call_op, .operand = 0, .aux = std.math.maxInt(u16) }},
    };
    try compiled_plan.validate();

    var handlers = struct {
        tooling: struct {
            pub fn dispatch(_: *@This()) anyerror!void {
                // The test targets after-frame gating, so the primary op deliberately resumes with unit.
            }

            pub fn afterDispatch(_: *@This(), _: void) anyerror![]const u8 {
                return "wrapped";
            }
        } = .{},
    }{};
    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectError(error.ProgramContractViolation, executeDispatch(&runtime, compiled_plan, &handlers, 0, &.{}));
}

test "program plan interpreter fails closed on native block budget exhaustion" {
    const compiled_plan: program_plan.ProgramPlan = .{
        .label = "interpreter.budget.self_jump",
        .ir_hash = 0x30c,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .value_codec = .unit,
            .parameter_count = 0,
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
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .jump, .primary = 0 }},
        .instructions = &.{},
    };
    try compiled_plan.validate();

    var handlers = struct {}{};
    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectError(
        error.ExecutionBudgetExceeded,
        runEntryWithOptions(&runtime, compiled_plan, &handlers, .{ .max_block_steps = 4 }),
    );
}

test "program plan interpreter fails closed on native after-frame budget exhaustion" {
    const compiled_plan: program_plan.ProgramPlan = .{
        .label = "interpreter.budget.after_frames",
        .ir_hash = 0x30d,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{
            .requirement_index = 0,
            .op_name = "dispatch",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .unit,
            .has_after = true,
        }},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{
            .{ .kind = .call_op, .operand = 0, .aux = std.math.maxInt(u16) },
            .{ .kind = .call_op, .operand = 0, .aux = std.math.maxInt(u16) },
        },
    };
    try compiled_plan.validate();

    var dispatch_calls: usize = 0;
    var handlers = struct {
        tooling: struct {
            calls: *usize,

            pub fn dispatch(self: *@This()) void {
                self.calls.* += 1;
            }

            pub fn afterDispatch(_: *@This(), _: void) void {
                // The budget should fail before these after hooks unwind.
            }
        },
    }{ .tooling = .{ .calls = &dispatch_calls } };
    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectError(
        error.ExecutionBudgetExceeded,
        runEntryWithOptions(&runtime, compiled_plan, &handlers, .{ .max_after_frames = 1 }),
    );
    try std.testing.expectEqual(@as(usize, 1), dispatch_calls);
}

test "program plan interpreter reserves native after-frame budget before dispatch" {
    const compiled_plan: program_plan.ProgramPlan = .{
        .label = "interpreter.budget.after_frame_pre_dispatch",
        .ir_hash = 0x30e,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{
            .requirement_index = 0,
            .op_name = "dispatch",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .unit,
            .has_after = true,
        }},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{.{ .kind = .call_op, .operand = 0, .aux = std.math.maxInt(u16) }},
    };
    try compiled_plan.validate();

    var dispatch_calls: usize = 0;
    var handlers = struct {
        tooling: struct {
            calls: *usize,

            pub fn dispatch(self: *@This()) void {
                self.calls.* += 1;
            }

            pub fn afterDispatch(_: *@This(), _: void) void {
                // The budget gate should prevent this hook from becoming reachable.
            }
        },
    }{ .tooling = .{ .calls = &dispatch_calls } };
    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectError(
        error.ExecutionBudgetExceeded,
        runEntryWithOptions(&runtime, compiled_plan, &handlers, .{ .max_after_frames = 0 }),
    );
    try std.testing.expectEqual(@as(usize, 0), dispatch_calls);
}

test "program plan interpreter rejects entry argument codec mismatches" {
    const compiled_plan: program_plan.ProgramPlan = .{
        .label = "interpreter.invalid.entry_arg_codec",
        .ir_hash = 0x309,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .value_codec = .i32,
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
            .instruction_count = 1,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{.{ .kind = .return_value, .operand = 0 }},
    };

    var handlers = struct {}{};
    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectError(error.ProgramContractViolation, executeDispatch(&runtime, compiled_plan, &handlers, 0, &.{.{ .bool = true }}));
}

test "program plan interpreter resolves output tags from entry requirement span" {
    const compiled_plan: program_plan.ProgramPlan = .{
        .label = "interpreter.entry_scoped_output_requirement",
        .ir_hash = 0x30a,
        .entry_index = 1,
        .functions = &.{
            .{
                .symbol_name = "helper",
                .first_requirement = 0,
                .requirement_count = 1,
                .first_output = 0,
                .output_count = 1,
                .first_local = 0,
                .local_count = 0,
                .first_block = 0,
                .entry_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 0,
            },
            .{
                .symbol_name = "root",
                .first_requirement = 1,
                .requirement_count = 1,
                .first_output = 1,
                .output_count = 1,
                .first_local = 0,
                .local_count = 0,
                .first_block = 1,
                .entry_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 0,
            },
        },
        .requirements = &.{
            .{ .label = "state", .first_op = 0, .op_count = 0, .output_tag = .accumulator },
            .{ .label = "state", .first_op = 0, .op_count = 0, .output_tag = .final_state },
        },
        .ops = &.{},
        .outputs = &.{
            .{ .label = "state", .codec = .i32 },
            .{ .label = "state", .codec = .i32 },
        },
        .locals = &.{},
        .blocks = &.{
            .{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 },
            .{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 1 },
        },
        .terminators = &.{
            .{ .kind = .return_unit },
            .{ .kind = .return_unit },
        },
        .instructions = &.{},
    };
    try compiled_plan.validate();

    var handlers = struct {
        state: struct {
            state: i32 = 42,
        } = .{},
    }{};
    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const result = try runEntry(&runtime, compiled_plan, &handlers);
    try std.testing.expectEqual(@as(i32, 42), result.outputs.state);
}

test "program plan interpreter returns ProgramContractViolation on i32 sub_one overflow" {
    const compiled_plan: program_plan.ProgramPlan = .{
        .label = "interpreter.invalid.sub_one_i32_overflow",
        .ir_hash = 0x307,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .value_codec = .i32,
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
            .instruction_count = 2,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{ .kind = .sub_one, .dst = 0, .operand = 0 },
            .{ .kind = .return_value, .operand = 0 },
        },
    };

    var handlers = struct {}{};
    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectError(error.ProgramContractViolation, executeDispatch(&runtime, compiled_plan, &handlers, 0, &.{.{ .i32 = std.math.minInt(i32) }}));
}

test "program plan interpreter returns ProgramContractViolation on usize sub_one underflow" {
    const compiled_plan: program_plan.ProgramPlan = .{
        .label = "interpreter.invalid.sub_one_usize_underflow",
        .ir_hash = 0x308,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .value_codec = .usize,
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
            .instruction_count = 2,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .usize }},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{ .kind = .sub_one, .dst = 0, .operand = 0 },
            .{ .kind = .return_value, .operand = 0 },
        },
    };

    var handlers = struct {}{};
    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try std.testing.expectError(error.ProgramContractViolation, executeDispatch(&runtime, compiled_plan, &handlers, 0, &.{.{ .usize = 0 }}));
}
