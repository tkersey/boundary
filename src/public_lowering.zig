const build_options = @import("authoring_build_options");
const effect_ir = @import("effect_ir");
const helper_body_lowering = @import("internal/helper_body_lowering.zig");
const lowered_machine = @import("lowered_machine");
const program_frontend = @import("program_frontend");
const program_plan = @import("internal_program_plan");
const source_graph_embed = @import("source_graph_embed");
const source_graph_comptime = @import("source_graph_comptime");
const source_graph_engine = @import("source_graph_engine");
const source_lowering = @import("source_lowering");
const std = @import("std");

/// Public support handlers for lowered open-row example runners.
pub const runtime_support = @import("open_row_runtime_support.zig");

/// Public additive spec for one same-module lowering request.
pub const LowerSpec = struct {
    label: []const u8,
    entry_symbol: []const u8,
    row: effect_ir.Row,
    ValueType: type = void,
    outputs: []const effect_ir.OutputSpec = &.{},
};

/// Public caller-owned imported source bytes for out-of-tree lowering.
pub const ImportedSource = source_graph_embed.OwnedSource;

/// Public caller-supplied provenance witness for one lowering request.
pub const SourceRef = struct {
    repo_path: []const u8,
    caller_file: []const u8,
    caller_hash: ?u64 = null,
    caller_source: ?[:0]const u8 = null,
    imported_sources: []const ImportedSource = &.{},
};

/// Public additive validation error surface for file-backed same-module sources.
pub const ValidationError = error{
    EntryMissing,
    OutOfMemory,
    ParseError,
    SourceDrifted,
    SourceUnreadable,
    UnsupportedHelperGraph,
    UnsupportedEffectAccess,
};
/// Public additive lowering error surface.
pub const LowerError = effect_ir.NormalizeError || ValidationError;

fn sentinelBytes(comptime bytes: []const u8) [:0]const u8 {
    const raw = std.fmt.comptimePrint("{s}\x00", .{bytes});
    return raw[0..bytes.len :0];
}

fn entryOutputsForPlan(comptime compiled_plan: program_plan.ProgramPlan) []const program_plan.OutputPlan {
    const entry_function = compiled_plan.functions[compiled_plan.entry_index];
    return compiled_plan.outputs[entry_function.first_output..][0..entry_function.output_count];
}

fn ResultOutputsTypeForPlan(comptime compiled_plan: program_plan.ProgramPlan) type {
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

fn LoweredRunResultTypeForPlan(comptime compiled_plan: program_plan.ProgramPlan) type {
    return struct {
        outputs: ResultOutputsTypeForPlan(compiled_plan),
        value: runtimeValueType(compiled_plan.functions[compiled_plan.entry_index].value_codec),
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

fn assertExecutableCodecSupport(comptime compiled_plan: program_plan.ProgramPlan) void {
    inline for (compiled_plan.functions) |function| switch (function.value_codec) {
        .unit, .bool, .i32, .string, .usize => {},
        .string_list => @compileError("public lowering runtime plan rejected string_list values across executable boundaries"),
    };
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
            buffer[len] = '_';
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

const LoweredOpResume = struct {
    value: lowered_machine.ProgramValue,
    apply_after: bool,
};

const LoweredOpResult = union(enum) {
    resumed: LoweredOpResume,
    terminal: lowered_machine.ProgramValue,
};

const LoweredFunctionResult = union(enum) {
    value: lowered_machine.ProgramValue,
    terminal: lowered_machine.ProgramValue,
};

fn callLoweredOp(
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers_ptr: anytype,
    comptime function_value_codec: program_plan.ValueCodec,
    op_index: u16,
    payload: lowered_machine.ProgramValue,
) anyerror!LoweredOpResult {
    if (compiled_plan.ops.len == 0) return error.ProgramContractViolation;
    return switch (op_index) {
        inline 0...(compiled_plan.ops.len - 1) => |active_index| blk: {
            const op = compiled_plan.ops[active_index];
            const requirement = compiled_plan.requirements[op.requirement_index];
            const handler_ptr = &@field(handlers_ptr.*, requirement.label);
            const HandlerType = @TypeOf(handler_ptr.*);
            const method = @field(HandlerType, op.op_name);
            const ResumeType = runtimeValueType(op.resume_codec);
            const AnswerType = runtimeValueType(function_value_codec);
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
                        .return_now => |answer| .{ .terminal = encodeRuntimeValue(function_value_codec, @as(AnswerType, answer)) },
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
                    break :blk .{ .terminal = encodeRuntimeValue(function_value_codec, @as(AnswerType, answer)) };
                },
            }
        },
        else => error.ProgramContractViolation,
    };
}

fn applyLoweredAfter(
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers_ptr: anytype,
    comptime function_value_codec: program_plan.ValueCodec,
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

            const AnswerType = runtimeValueType(function_value_codec);
            const method = @field(HandlerType, after_name);
            const decoded_answer = decodeRuntimeValue(function_value_codec, answer);
            const transformed_answer = try resolveMaybeError(@call(.auto, method, .{ handler_ptr, @as(AnswerType, decoded_answer) }));
            break :blk encodeRuntimeValue(function_value_codec, @as(AnswerType, transformed_answer));
        },
        else => error.ProgramContractViolation,
    };
}

fn unwindLoweredAfterStack(
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers_ptr: anytype,
    comptime function_value_codec: program_plan.ValueCodec,
    after_stack: *std.ArrayList(u16),
    result: LoweredFunctionResult,
) anyerror!LoweredFunctionResult {
    var final_result = result;
    while (after_stack.items.len != 0) {
        const op_index = after_stack.pop().?;
        final_result = switch (final_result) {
            .value => |typed| .{ .value = try applyLoweredAfter(compiled_plan, handlers_ptr, function_value_codec, op_index, typed) },
            .terminal => |typed| .{ .terminal = try applyLoweredAfter(compiled_plan, handlers_ptr, function_value_codec, op_index, typed) },
        };
    }
    return final_result;
}

fn continueLoweredFunction(
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers_ptr: anytype,
    comptime function_index: usize,
    locals: []lowered_machine.ProgramValue,
    after_stack: *std.ArrayList(u16),
    initial_block_index: u16,
    initial_instruction_index: u16,
    initial_return_local: ?u16,
) anyerror!LoweredFunctionResult {
    const function = compiled_plan.functions[function_index];
    var current_block_index = initial_block_index;
    var instruction_index = initial_instruction_index;
    var return_local = initial_return_local;

    while (true) {
        const block = compiled_plan.blocks[current_block_index];
        const instruction_end = block.first_instruction + block.instruction_count;
        while (instruction_index < instruction_end) : (instruction_index += 1) {
            const instruction = compiled_plan.instructions[instruction_index];
            switch (instruction.kind) {
                .add_const_i32 => setLocal(locals, instruction.dst, switch (getLocal(locals, instruction.operand)) {
                    .i32 => |typed| .{ .i32 = typed + @as(i32, @intCast(instruction.aux)) },
                    else => unreachable,
                }),
                .call_helper => {
                    const callee = compiled_plan.functions[instruction.operand];
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
                    const result = try executeLoweredDispatch(compiled_plan, handlers_ptr, instruction.operand, helper_args);
                    switch (result) {
                        .value => |typed| {
                            if (instruction.dst < locals.len and compiled_plan.functions[instruction.operand].value_codec != .unit) {
                                setLocal(locals, instruction.dst, typed);
                            }
                        },
                        .terminal => |terminal| return unwindLoweredAfterStack(
                            compiled_plan,
                            handlers_ptr,
                            function.value_codec,
                            after_stack,
                            .{ .terminal = terminal },
                        ),
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
                    const result = try callLoweredOp(compiled_plan, handlers_ptr, function.value_codec, instruction.operand, payload);
                    switch (result) {
                        .resumed => |resumed_value| {
                            if (instruction.dst < locals.len and op.resume_codec != .unit) {
                                setLocal(locals, instruction.dst, resumed_value.value);
                            }
                            if (resumed_value.apply_after) {
                                try after_stack.append(std.heap.page_allocator, instruction.operand);
                            }
                        },
                        .terminal => |terminal| return unwindLoweredAfterStack(
                            compiled_plan,
                            handlers_ptr,
                            function.value_codec,
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
                .const_i32 => setLocal(locals, instruction.dst, .{ .i32 = @as(i32, @intCast(instruction.operand)) }),
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
            .return_unit => return unwindLoweredAfterStack(
                compiled_plan,
                handlers_ptr,
                function.value_codec,
                after_stack,
                .{ .value = .none },
            ),
            .return_value => return unwindLoweredAfterStack(
                compiled_plan,
                handlers_ptr,
                function.value_codec,
                after_stack,
                .{ .value = getLocal(locals, return_local orelse return error.ProgramContractViolation) },
            ),
        }
    }
}

fn executeLoweredFunction(
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers_ptr: anytype,
    comptime function_index: usize,
    args: []const lowered_machine.ProgramValue,
) anyerror!LoweredFunctionResult {
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
    return continueLoweredFunction(
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

fn executeLoweredDispatch(
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers_ptr: anytype,
    function_index: u16,
    args: []const lowered_machine.ProgramValue,
) anyerror!LoweredFunctionResult {
    if (compiled_plan.functions.len == 0) return error.ProgramContractViolation;
    return switch (function_index) {
        inline 0...(compiled_plan.functions.len - 1) => |active_index| executeLoweredFunction(compiled_plan, handlers_ptr, active_index, args),
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

fn collectLoweredOutputsForPlan(comptime compiled_plan: program_plan.ProgramPlan, handlers_ptr: anytype) anyerror!ResultOutputsTypeForPlan(compiled_plan) {
    const outputs = comptime entryOutputsForPlan(compiled_plan);
    var value: ResultOutputsTypeForPlan(compiled_plan) = std.mem.zeroInit(ResultOutputsTypeForPlan(compiled_plan), .{});
    inline for (outputs) |output| {
        const handler_ptr = &@field(handlers_ptr.*, output.label);
        @field(value, output.label) = try resolveMaybeError(handler_ptr.finish());
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

fn cloneBytes(comptime bytes: []const u8) []const u8 {
    comptime {
        @setEvalBranchQuota(20_000);
    }
    return std.fmt.comptimePrint("{s}", .{bytes});
}

fn pathEquals(comptime lhs: []const u8, comptime rhs: []const u8) bool {
    if (lhs.len != rhs.len) return false;
    const case_insensitive = comptime pathsUseCaseInsensitiveComparison(lhs, rhs);
    inline for (rhs, 0..) |expected, index| {
        const actual = lhs[index];
        if (expected == '/' or expected == '\\') {
            if (actual != '/' and actual != '\\') return false;
            continue;
        }
        if (case_insensitive) {
            if (asciiLowerPathByte(actual) != asciiLowerPathByte(expected)) return false;
            continue;
        }
        if (actual != expected) return false;
    }
    return true;
}

fn pathStartsWithRoot(comptime path: []const u8, comptime root: []const u8) bool {
    if (path.len < root.len) return false;
    const case_insensitive = comptime pathsUseCaseInsensitiveComparison(path, root);
    inline for (root, 0..) |expected, index| {
        const actual = path[index];
        if (expected == '/' or expected == '\\') {
            if (actual != '/' and actual != '\\') return false;
            continue;
        }
        if (case_insensitive) {
            if (asciiLowerPathByte(actual) != asciiLowerPathByte(expected)) return false;
            continue;
        }
        if (actual != expected) return false;
    }
    return path.len == root.len or path[root.len] == '/' or path[root.len] == '\\';
}

fn pathStartsWithRootRuntime(path: []const u8, root: []const u8) bool {
    if (path.len < root.len) return false;
    const case_insensitive = pathsUseCaseInsensitiveComparison(path, root);
    for (root, 0..) |expected, index| {
        const actual = path[index];
        if (expected == '/' or expected == '\\') {
            if (actual != '/' and actual != '\\') return false;
            continue;
        }
        if (case_insensitive) {
            if (asciiLowerPathByte(actual) != asciiLowerPathByte(expected)) return false;
            continue;
        }
        if (actual != expected) return false;
    }
    return path.len == root.len or path[root.len] == '/' or path[root.len] == '\\';
}

fn pathEqualsRuntime(lhs: []const u8, rhs: []const u8) bool {
    if (lhs.len != rhs.len) return false;
    const case_insensitive = pathsUseCaseInsensitiveComparison(lhs, rhs);
    for (rhs, 0..) |expected, index| {
        const actual = lhs[index];
        if (expected == '/' or expected == '\\') {
            if (actual != '/' and actual != '\\') return false;
            continue;
        }
        if (case_insensitive) {
            if (asciiLowerPathByte(actual) != asciiLowerPathByte(expected)) return false;
            continue;
        }
        if (actual != expected) return false;
    }
    return true;
}

fn asciiLowerPathByte(byte: u8) u8 {
    return if (byte >= 'A' and byte <= 'Z') byte + ('a' - 'A') else byte;
}

fn pathUsesWindowsCaseFolding(path: []const u8) bool {
    if (path.len >= 2 and std.ascii.isAlphabetic(path[0]) and path[1] == ':') return true;
    return path.len >= 2 and ((path[0] == '\\' and path[1] == '\\') or (path[0] == '/' and path[1] == '/'));
}

fn pathsUseCaseInsensitiveComparison(lhs: []const u8, rhs: []const u8) bool {
    return pathUsesWindowsCaseFolding(lhs) and pathUsesWindowsCaseFolding(rhs);
}

fn pathUsesCheckoutRoot(comptime caller_file: []const u8) bool {
    if (!std.fs.path.isAbsolute(caller_file)) return false;
    return pathStartsWithRoot(caller_file, build_options.package_root);
}

fn pathUsesPackageRootAlias(comptime caller_file: []const u8) bool {
    if (!build_options.package_root_alias_available) return false;
    if (!std.fs.path.isAbsolute(caller_file)) return false;
    return pathStartsWithRoot(caller_file, build_options.package_root_alias);
}

fn ownedRootRelativeSlice(comptime path: []const u8, comptime root: []const u8) ?[]const u8 {
    if (!pathStartsWithRoot(path, root)) return null;
    if (path.len <= root.len) return null;
    const separator = path[root.len];
    if (separator != '/' and separator != '\\') return null;
    return path[root.len + 1 ..];
}

fn pathMatchesOwnedRootRelative(
    comptime caller_file: []const u8,
    comptime root: []const u8,
    comptime repo_path: []const u8,
) bool {
    const relative_path = comptime ownedRootRelativeSlice(caller_file, root) orelse return false;
    return pathEquals(relative_path, repo_path);
}

fn absoluteOwnedRepoRelativePath(comptime absolute_path: []const u8) ?[]const u8 {
    if (pathUsesCheckoutRoot(absolute_path)) {
        return ownedRootRelativeSlice(absolute_path, build_options.package_root);
    }
    if (pathUsesPackageRootAlias(absolute_path)) {
        return ownedRootRelativeSlice(absolute_path, build_options.package_root_alias);
    }
    return null;
}

fn absoluteOwnedRepoPathMatches(comptime source_ref: SourceRef) bool {
    if (std.fs.path.isAbsolute(source_ref.repo_path)) return false;
    if (!std.fs.path.isAbsolute(source_ref.caller_file)) return false;
    return comptime blk: {
        const caller_repo_path = absoluteOwnedRepoRelativePath(source_ref.caller_file) orelse break :blk false;
        if (pathUsesPackageRootAlias(source_ref.caller_file) and
            (source_ref.caller_hash == null or source_ref.caller_source == null))
        {
            break :blk false;
        }
        break :blk pathEquals(caller_repo_path, source_ref.repo_path);
    };
}

fn sourceOwnershipMatches(comptime source_ref: SourceRef) bool {
    if (source_ref.caller_hash != null or source_ref.caller_source != null) {
        return sourceHashMatches(source_ref);
    }
    return absoluteOwnedRepoPathMatches(source_ref);
}

fn hashSourceBytes(comptime bytes: []const u8) u64 {
    comptime {
        @setEvalBranchQuota(1_000_000);
    }
    return std.hash.Wyhash.hash(0, bytes);
}

fn sourceHashMatches(comptime source_ref: SourceRef) bool {
    if (source_ref.caller_source) |caller_source| {
        const caller_hash = source_ref.caller_hash orelse return false;
        if (std.fs.path.isAbsolute(source_ref.caller_file)) {
            if (std.fs.path.isAbsolute(source_ref.repo_path)) {
                if (!pathEquals(source_ref.caller_file, source_ref.repo_path)) return false;
                const absolute_owned_repo_match: ?bool = comptime blk: {
                    const owned_repo_path = absoluteOwnedRepoRelativePath(source_ref.repo_path) orelse break :blk null;
                    if (!repoPathIsOwned(owned_repo_path)) break :blk false;
                    const repo_source = source_graph_embed.embeddedSource(owned_repo_path);
                    break :blk std.mem.eql(u8, caller_source, repo_source);
                };
                if (absolute_owned_repo_match) |matches_repo| {
                    if (!matches_repo) return false;
                }
            } else {
                if (!absoluteOwnedSourceMatchesRepo(source_ref, caller_source)) return false;
            }
        } else {
            if (!relativeOwnedSourceMatchesRepo(source_ref, caller_source)) return false;
        }
        if (caller_hash != hashSourceBytes(caller_source)) return false;
        return true;
    }
    const caller_hash = source_ref.caller_hash orelse return false;
    const owned_repo_path = comptime repoPathIsOwned(source_ref.repo_path);
    if (!owned_repo_path) return false;
    if (!std.fs.path.isAbsolute(source_ref.caller_file)) return false;
    const repo_source = comptime source_graph_embed.embeddedSource(source_ref.repo_path);
    if (!absoluteOwnedRepoPathMatches(source_ref)) return false;
    return caller_hash == hashSourceBytes(repo_source);
}

fn relativeOwnedSourceMatchesRepo(comptime source_ref: SourceRef, comptime caller_source: []const u8) bool {
    if (std.fs.path.isAbsolute(source_ref.repo_path)) return false;
    if (!pathEquals(source_ref.caller_file, source_ref.repo_path)) return false;
    return comptime blk: {
        if (!repoPathIsOwned(source_ref.repo_path)) break :blk false;
        const repo_source = source_graph_embed.embeddedSource(source_ref.repo_path);
        break :blk std.mem.eql(u8, caller_source, repo_source);
    };
}

fn absoluteOwnedSourceMatchesRepo(comptime source_ref: SourceRef, comptime caller_source: []const u8) bool {
    if (std.fs.path.isAbsolute(source_ref.repo_path)) return false;
    if (!absoluteOwnedRepoPathMatches(source_ref)) return false;
    return comptime blk: {
        if (!repoPathIsOwned(source_ref.repo_path)) break :blk false;
        const repo_source = source_graph_embed.embeddedSource(source_ref.repo_path);
        break :blk std.mem.eql(u8, caller_source, repo_source);
    };
}

fn sourcePathForLowering(comptime source_ref: SourceRef) []const u8 {
    if (std.fs.path.isAbsolute(source_ref.caller_file) and !absoluteOwnedRepoPathMatches(source_ref)) {
        return cloneBytes(source_ref.caller_file);
    }
    return source_ref.repo_path;
}

fn repoPathIsOwned(comptime repo_path: []const u8) bool {
    return registryContainsLine(build_options.repo_zig_paths, repo_path);
}

fn registryContainsLine(comptime registry: []const u8, comptime candidate: []const u8) bool {
    comptime {
        @setEvalBranchQuota(50_000);
    }
    var start: usize = 0;
    while (start < registry.len) {
        var end = start;
        while (end < registry.len and registry[end] != '\n') : (end += 1) {}
        const line = registry[start..end];
        if (line.len != 0 and pathEquals(line, candidate)) return true;
        start = end + 1;
    }
    return false;
}

fn pathHasSeparator(comptime path: []const u8) bool {
    inline for (path) |byte| {
        if (byte == '/' or byte == '\\') return true;
    }
    return false;
}

fn assertSourceOwnership(comptime source_ref: SourceRef) void {
    if (source_ref.repo_path.len == 0) @compileError("public lowering source ownership requires a non-empty repo_path");
    if (source_ref.caller_file.len == 0) @compileError("public lowering source ownership requires a non-empty caller_file");
    if (!sourceOwnershipMatches(source_ref)) {
        @compileError("public lowering source ownership requires caller_file to end with repo_path");
    }
}

/// Build one caller-owned lowering provenance witness from an explicit repo path plus `@src()`.
pub fn source(comptime repo_path: []const u8, comptime caller: std.builtin.SourceLocation) SourceRef {
    if (repo_path.len == 0) @compileError("public lowering source helper requires a non-empty repo path");
    if (caller.file.len == 0) @compileError("public lowering source helper requires a non-empty caller source file");
    return .{
        .repo_path = cloneBytes(repo_path),
        .caller_file = cloneBytes(caller.file),
        .caller_hash = null,
        .caller_source = null,
    };
}

/// Build one caller-owned lowering provenance witness from an explicit repo path or caller-owned absolute path, `@src()`, and caller-supplied source bytes.
pub fn sourceWithContent(
    comptime repo_path: []const u8,
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source: []const u8,
) SourceRef {
    return sourceWithContentAndImports(repo_path, caller, caller_source, &.{});
}

/// Build one caller-owned imported source witness relative to the explicit root source path.
pub fn importedSource(
    comptime root_source_path: []const u8,
    comptime import_path: []const u8,
    comptime source_bytes: []const u8,
) ImportedSource {
    const resolved_path = source_graph_embed.resolveImportPathAt(root_source_path, import_path) catch |err| switch (err) {
        error.UnsupportedImportPath => @compileError("public lowering imported source helper requires a non-escaping relative .zig import path"),
        error.TooManyImports => @compileError("public lowering imported source helper exceeded the supported segment budget"),
        else => @compileError("public lowering imported source helper could not resolve the imported source path"),
    };
    return .{
        .path = cloneBytes(resolved_path),
        .content = sentinelBytes(source_bytes),
    };
}

/// Build one caller-owned lowering provenance witness with explicit imported helper bytes for either an owned repo path or a caller-owned absolute path.
pub fn sourceWithContentAndImports(
    comptime repo_path: []const u8,
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source: []const u8,
    comptime imported_sources: []const ImportedSource,
) SourceRef {
    if (repo_path.len == 0) @compileError("public lowering source helper requires a non-empty repo path");
    if (caller.file.len == 0) @compileError("public lowering source helper requires a non-empty caller source file");
    return .{
        .repo_path = cloneBytes(repo_path),
        .caller_file = cloneBytes(caller.file),
        .caller_hash = hashSourceBytes(caller_source),
        .caller_source = sentinelBytes(caller_source),
        .imported_sources = imported_sources,
    };
}

fn cloneOutputSpecs(comptime outputs: []const effect_ir.OutputSpec) []const effect_ir.OutputSpec {
    return comptime blk: {
        var buffer: [outputs.len]effect_ir.OutputSpec = undefined;
        for (outputs, 0..) |output, index| {
            buffer[index] = .{
                .label = cloneBytes(output.label),
                .OutputType = output.OutputType,
            };
        }
        break :blk &buffer;
    };
}

fn cloneRow(comptime row: effect_ir.Row) effect_ir.Row {
    const requirements = comptime blk: {
        var requirement_buffer: [row.requirements.len]effect_ir.Requirement = undefined;
        for (row.requirements, 0..) |requirement, requirement_index| {
            var op_buffer: [requirement.ops.len]effect_ir.OpSpec = undefined;
            for (requirement.ops, 0..) |op, op_index| {
                op_buffer[op_index] = .{
                    .requirement_label = cloneBytes(op.requirement_label),
                    .op_name = cloneBytes(op.op_name),
                    .mode = op.mode,
                    .PayloadType = op.PayloadType,
                    .ResumeType = op.ResumeType,
                };
            }
            requirement_buffer[requirement_index] = .{
                .label = cloneBytes(requirement.label),
                .ops = &op_buffer,
            };
        }
        break :blk requirement_buffer;
    };
    return .{ .requirements = &requirements };
}

fn cloneFunction(comptime function: effect_ir.Function) effect_ir.Function {
    return .{
        .symbol = .{
            .module_path = cloneBytes(function.symbol.module_path),
            .symbol_name = cloneBytes(function.symbol.symbol_name),
        },
        .row = cloneRow(function.row),
        .parameter_codecs = cloneLocalCodecs(function.parameter_codecs),
        .ValueType = function.ValueType,
        .outputs = cloneOutputSpecs(function.outputs),
    };
}

fn cloneProgram(comptime program: effect_ir.Program) effect_ir.Program {
    const functions = comptime blk: {
        var buffer: [program.functions.len]effect_ir.Function = undefined;
        for (program.functions, 0..) |function, index| {
            buffer[index] = cloneFunction(function);
        }
        break :blk buffer;
    };
    return .{
        .entry_index = program.entry_index,
        .functions = &functions,
        .call_edges = cloneCallEdges(program.call_edges),
        .function_bodies = cloneFunctionBodies(program.function_bodies),
    };
}

fn cloneCallEdges(comptime call_edges: []const effect_ir.CallEdge) []const effect_ir.CallEdge {
    return comptime blk: {
        var buffer: [call_edges.len]effect_ir.CallEdge = undefined;
        for (call_edges, 0..) |edge, index| {
            buffer[index] = .{
                .caller = .{
                    .module_path = cloneBytes(edge.caller.module_path),
                    .symbol_name = cloneBytes(edge.caller.symbol_name),
                },
                .callee = .{
                    .module_path = cloneBytes(edge.callee.module_path),
                    .symbol_name = cloneBytes(edge.callee.symbol_name),
                },
            };
        }
        break :blk &buffer;
    };
}

fn explicitEntryIndex(
    comptime functions: []const effect_ir.Function,
    comptime entry_symbol: []const u8,
    comptime entry_module_path: ?[]const u8,
) u16 {
    for (functions, 0..) |function, index| {
        if (!std.mem.eql(u8, function.symbol.symbol_name, entry_symbol)) continue;
        if (entry_module_path) |module_path| {
            if (!std.mem.eql(u8, function.symbol.module_path, module_path)) continue;
        }
        return @intCast(index);
    }
    @compileError("public lowering could not find the requested entry symbol in the explicit effect-ir program");
}

fn cloneBodyInstructions(comptime instructions: []const effect_ir.Instruction) []const effect_ir.Instruction {
    return comptime blk: {
        var buffer: [instructions.len]effect_ir.Instruction = undefined;
        for (instructions, 0..) |instruction, index| buffer[index] = instruction;
        break :blk &buffer;
    };
}

fn cloneBodyBlocks(comptime blocks: []const effect_ir.Block) []const effect_ir.Block {
    return comptime blk: {
        var buffer: [blocks.len]effect_ir.Block = undefined;
        for (blocks, 0..) |block, index| {
            buffer[index] = .{
                .instructions = cloneBodyInstructions(block.instructions),
                .terminator = block.terminator,
            };
        }
        break :blk &buffer;
    };
}

fn cloneLocalCodecs(comptime codecs: []const effect_ir.LocalCodec) []const effect_ir.LocalCodec {
    return comptime blk: {
        var buffer: [codecs.len]effect_ir.LocalCodec = undefined;
        for (codecs, 0..) |codec, index| buffer[index] = codec;
        break :blk &buffer;
    };
}

fn cloneLocalIds(comptime local_ids: []const effect_ir.LocalId) []const effect_ir.LocalId {
    return comptime blk: {
        var buffer: [local_ids.len]effect_ir.LocalId = undefined;
        for (local_ids, 0..) |local_id, index| buffer[index] = local_id;
        break :blk &buffer;
    };
}

fn cloneFunctionBodies(comptime function_bodies: []const effect_ir.FunctionBody) []const effect_ir.FunctionBody {
    return comptime blk: {
        var buffer: [function_bodies.len]effect_ir.FunctionBody = undefined;
        for (function_bodies, 0..) |body, index| {
            buffer[index] = .{
                .local_codecs = cloneLocalCodecs(body.local_codecs),
                .call_arg_locals = cloneLocalIds(body.call_arg_locals),
                .entry_block = body.entry_block,
                .blocks = cloneBodyBlocks(body.blocks),
            };
        }
        break :blk &buffer;
    };
}

const FlatOp = struct {
    requirement_label: []const u8,
    op_name: []const u8,
    mode: effect_ir.ControlMode,
    PayloadType: type,
    ResumeType: type,
};

fn flatOpsForRow(comptime row: effect_ir.Row) []const FlatOp {
    return comptime blk: {
        const total = count: {
            var count_ops: usize = 0;
            for (row.requirements) |requirement| count_ops += requirement.ops.len;
            break :count count_ops;
        };
        var buffer: [total]FlatOp = undefined;
        var index: usize = 0;
        for (row.requirements) |requirement| {
            for (requirement.ops) |op| {
                buffer[index] = .{
                    .requirement_label = cloneBytes(requirement.label),
                    .op_name = cloneBytes(op.op_name),
                    .mode = op.mode,
                    .PayloadType = op.PayloadType,
                    .ResumeType = op.ResumeType,
                };
                index += 1;
            }
        }
        break :blk &buffer;
    };
}

fn reachableFunctions(comptime graph: source_graph_embed.ProgramGraph) [graph.functions.len]bool {
    var reachable = [_]bool{false} ** graph.functions.len;
    reachable[graph.entry_index] = true;

    var changed = true;
    while (changed) {
        changed = false;
        for (graph.helper_edges) |edge| {
            if (!reachable[edge.caller_index] or reachable[edge.callee_index]) continue;
            reachable[edge.callee_index] = true;
            changed = true;
        }
    }

    return reachable;
}

fn loweredFunctionIndexMap(comptime graph: source_graph_embed.ProgramGraph) [graph.functions.len]u16 {
    const reachable = reachableFunctions(graph);
    return comptime blk: {
        var buffer: [graph.functions.len]u16 = [_]u16{std.math.maxInt(u16)} ** graph.functions.len;
        var next_index: u16 = 0;
        buffer[graph.entry_index] = next_index;
        next_index += 1;
        for (graph.functions, 0..) |_, function_index| {
            if (!reachable[function_index] or function_index == graph.entry_index) continue;
            buffer[function_index] = next_index;
            next_index += 1;
        }
        break :blk buffer;
    };
}

fn analyzeProgramGraphAt(comptime source_path: []const u8, comptime entry_symbol: []const u8) source_graph_embed.ProgramGraph {
    return analyzeProgramGraphWithRootSource(source_path, null, &.{}, entry_symbol);
}

fn analyzeProgramGraphWithRootSource(
    comptime source_path: []const u8,
    comptime root_source: ?[:0]const u8,
    comptime imported_sources: []const ImportedSource,
    comptime entry_symbol: []const u8,
) source_graph_embed.ProgramGraph {
    return source_graph_embed.analyzeProgramWithRootSource(source_path, root_source, imported_sources, entry_symbol) catch |err| switch (err) {
        error.ParseError => @compileError("public lowering rejected source text that does not parse as Zig"),
        error.EntryMissing => @compileError("public lowering could not find the requested entry symbol in the embedded source"),
        error.MissingImport => @compileError("public lowering could not resolve one imported helper module or helper symbol"),
        error.RecursiveHelpers => @compileError("public lowering encountered an unexpected recursive helper analysis failure"),
        error.TooManyFunctions => @compileError("public lowering source graph exceeded the supported function limit"),
        error.TooManyFunctionParams => @compileError("public lowering source graph exceeded the supported helper parameter limit"),
        error.TooManyImports => @compileError("public lowering source graph exceeded the supported import limit"),
        error.TooManyHelperUses => @compileError("public lowering source graph exceeded the supported helper-use limit"),
        error.TooManyHelperEdges => @compileError("public lowering source graph exceeded the supported helper-edge limit"),
        error.TooManyOpUses => @compileError("public lowering source graph exceeded the supported op-use limit"),
        error.UnsupportedEffectAccess => @compileError("public lowering helper inference supports only the retained direct and alias-based effect access patterns"),
        error.UnsupportedImportPath => @compileError("public lowering supports only non-escaping .zig imports for cross-file helpers"),
    };
}

fn inferUsedOps(
    comptime graph: source_graph_embed.ProgramGraph,
    comptime flat_ops: []const FlatOp,
) [graph.functions.len][flat_ops.len]bool {
    var used = [_][flat_ops.len]bool{[_]bool{false} ** flat_ops.len} ** graph.functions.len;

    for (graph.direct_op_uses) |direct_use| {
        for (flat_ops, 0..) |op, op_index| {
            if (!std.mem.eql(u8, op.requirement_label, direct_use.requirement_label)) continue;
            if (!std.mem.eql(u8, op.op_name, direct_use.op_name)) continue;
            used[direct_use.function_index][op_index] = true;
        }
    }

    var changed = true;
    while (changed) {
        changed = false;
        for (graph.helper_edges) |edge| {
            for (flat_ops, 0..) |_, op_index| {
                if (used[edge.caller_index][op_index] or !used[edge.callee_index][op_index]) continue;
                used[edge.caller_index][op_index] = true;
                changed = true;
            }
        }
    }

    return used;
}

fn helperRowFromUsage(
    comptime row: effect_ir.Row,
    comptime flat_ops: []const FlatOp,
    comptime used_ops: []const bool,
) effect_ir.Row {
    return comptime blk: {
        var requirement_buffer: [row.requirements.len]effect_ir.Requirement = undefined;
        var requirement_count: usize = 0;
        var flat_index: usize = 0;

        for (row.requirements) |requirement| {
            var op_buffer: [requirement.ops.len]effect_ir.OpSpec = undefined;
            var op_count: usize = 0;
            for (requirement.ops) |_| {
                if (used_ops[flat_index]) {
                    const flat_op = flat_ops[flat_index];
                    op_buffer[op_count] = .{
                        .requirement_label = flat_op.requirement_label,
                        .op_name = flat_op.op_name,
                        .mode = flat_op.mode,
                        .PayloadType = flat_op.PayloadType,
                        .ResumeType = flat_op.ResumeType,
                    };
                    op_count += 1;
                }
                flat_index += 1;
            }

            if (op_count != 0) {
                const exact_ops = exact: {
                    var exact_buffer: [op_count]effect_ir.OpSpec = undefined;
                    for (0..op_count) |index| exact_buffer[index] = op_buffer[index];
                    break :exact exact_buffer;
                };
                requirement_buffer[requirement_count] = .{
                    .label = cloneBytes(requirement.label),
                    .ops = &exact_ops,
                };
                requirement_count += 1;
            }
        }

        const exact_requirements = exact: {
            var exact_buffer: [requirement_count]effect_ir.Requirement = undefined;
            for (0..requirement_count) |index| exact_buffer[index] = requirement_buffer[index];
            break :exact exact_buffer;
        };
        break :blk .{ .requirements = &exact_requirements };
    };
}

fn buildFunctionsForGraph(comptime graph: source_graph_embed.ProgramGraph, comptime spec: LowerSpec) []const effect_ir.Function {
    const reachable = reachableFunctions(graph);
    const flat_ops = flatOpsForRow(spec.row);
    const used_ops = inferUsedOps(graph, flat_ops);
    const entry_function = graph.functions[graph.entry_index];

    if (entry_function.value_param_count != 0) {
        @compileError("public lowering rejected entry functions with value parameters because run(runtime, handlers) cannot supply entry arguments");
    }

    const function_count = count: {
        var count_functions: usize = 0;
        for (reachable) |is_reachable| {
            if (is_reachable) count_functions += 1;
        }
        break :count count_functions;
    };

    return comptime blk: {
        var buffer: [function_count]effect_ir.Function = undefined;
        var index: usize = 0;

        buffer[index] = .{
            .symbol = .{
                .module_path = cloneBytes(entry_function.module_path),
                .symbol_name = cloneBytes(entry_function.name),
            },
            .row = cloneRow(spec.row),
            .ValueType = spec.ValueType,
            .outputs = cloneOutputSpecs(spec.outputs),
        };
        index += 1;

        for (graph.functions, 0..) |function, function_index| {
            if (!reachable[function_index] or function_index == graph.entry_index) continue;
            const parameter_codecs = parameter_codecs: {
                if (function.value_param_count == 0) break :parameter_codecs &.{};
                var codec_buffer: [function.value_param_count]effect_ir.LocalCodec = undefined;
                for (0..function.value_param_count) |param_index| {
                    codec_buffer[param_index] = switch (function.value_param_shapes[param_index]) {
                        .bool => .bool,
                        .i32 => .i32,
                        .string => .string,
                        .usize => .usize,
                    };
                }
                break :parameter_codecs &codec_buffer;
            };
            const value_type = if (function.return_shape) |shape|
                switch (shape) {
                    .bool => bool,
                    .i32 => i32,
                    .string => []const u8,
                    .usize => usize,
                }
            else
                void;
            buffer[index] = .{
                .symbol = .{
                    .module_path = cloneBytes(function.module_path),
                    .symbol_name = cloneBytes(function.name),
                },
                .row = helperRowFromUsage(spec.row, flat_ops, &used_ops[function_index]),
                .parameter_codecs = parameter_codecs,
                .ValueType = value_type,
                .outputs = &.{},
            };
            index += 1;
        }

        break :blk &buffer;
    };
}

fn buildFunctionsAt(comptime source_path: []const u8, comptime spec: LowerSpec) []const effect_ir.Function {
    return buildFunctionsForGraph(analyzeProgramGraphAt(source_path, spec.entry_symbol), spec);
}

fn buildCallEdgesForGraph(comptime graph: source_graph_embed.ProgramGraph) []const effect_ir.CallEdge {
    const reachable = reachableFunctions(graph);
    const edge_count = comptime count: {
        var count_edges: usize = 0;
        for (graph.helper_edges) |edge| {
            if (reachable[edge.caller_index] and reachable[edge.callee_index]) count_edges += 1;
        }
        break :count count_edges;
    };

    return comptime blk: {
        var buffer: [edge_count]effect_ir.CallEdge = undefined;
        var index: usize = 0;
        for (graph.helper_edges) |edge| {
            if (!reachable[edge.caller_index] or !reachable[edge.callee_index]) continue;
            buffer[index] = .{
                .caller = .{
                    .module_path = cloneBytes(graph.functions[edge.caller_index].module_path),
                    .symbol_name = cloneBytes(graph.functions[edge.caller_index].name),
                },
                .callee = .{
                    .module_path = cloneBytes(graph.functions[edge.callee_index].module_path),
                    .symbol_name = cloneBytes(graph.functions[edge.callee_index].name),
                },
            };
            index += 1;
        }
        break :blk &buffer;
    };
}

fn buildCallEdgesAt(comptime source_path: []const u8, comptime spec: LowerSpec) []const effect_ir.CallEdge {
    return buildCallEdgesForGraph(analyzeProgramGraphAt(source_path, spec.entry_symbol));
}

fn instructionLocationLess(
    comptime left_line: usize,
    comptime left_column: usize,
    comptime right_line: usize,
    comptime right_column: usize,
) bool {
    if (left_line < right_line) return true;
    if (left_line > right_line) return false;
    return left_column < right_column;
}

fn opIndexForFunctionUse(
    comptime functions: []const effect_ir.Function,
    comptime function_index: usize,
    comptime requirement_label: []const u8,
    comptime op_name: []const u8,
) u16 {
    var op_index: u16 = 0;
    for (functions, 0..) |function, active_function_index| {
        for (function.row.requirements) |requirement| {
            for (requirement.ops) |op| {
                if (active_function_index == function_index and
                    std.mem.eql(u8, requirement.label, requirement_label) and
                    std.mem.eql(u8, op.op_name, op_name))
                {
                    return op_index;
                }
                op_index += 1;
            }
        }
    }
    @compileError("public lowering could not map one direct effect-op use into the lowered function row");
}

fn buildFunctionBodiesForGraph(
    comptime graph: source_graph_embed.ProgramGraph,
    comptime functions: []const effect_ir.Function,
    comptime root_source_path: ?[]const u8,
    comptime root_source: ?[:0]const u8,
    comptime imported_sources: []const ImportedSource,
) []const program_frontend.FunctionBody {
    const reachable = reachableFunctions(graph);
    const lowered_index_map = loweredFunctionIndexMap(graph);
    return helper_body_lowering.buildFunctionBodiesForGraph(
        graph,
        functions,
        reachable,
        lowered_index_map,
        .{
            .path = root_source_path,
            .content = root_source,
            .imported_sources = imported_sources,
        },
    );
}

fn buildValidationSnapshotImportedSources(
    comptime graph: source_graph_embed.ProgramGraph,
    comptime source_path: []const u8,
) []const ImportedSource {
    const reachable = reachableFunctions(graph);

    return comptime blk: {
        var module_paths: [graph.functions.len][]const u8 = undefined;
        var count: usize = 0;

        for (graph.functions, 0..) |function, function_index| {
            if (!reachable[function_index]) continue;
            if (pathEquals(function.module_path, source_path)) continue;

            var seen = false;
            for (module_paths[0..count]) |existing| {
                if (pathEquals(existing, function.module_path)) {
                    seen = true;
                    break;
                }
            }
            if (seen) continue;

            module_paths[count] = function.module_path;
            count += 1;
        }

        const exact_imported_sources = exact: {
            var imported_sources: [count]ImportedSource = undefined;
            for (module_paths[0..count], 0..) |module_path, index| {
                imported_sources[index] = .{
                    .path = cloneBytes(module_path),
                    .content = source_graph_embed.embeddedSource(module_path),
                };
            }
            break :exact imported_sources;
        };
        break :blk &exact_imported_sources;
    };
}

/// Build one explicit-path open-row payload with a caller-visible source path.
fn openRowAt(comptime source_path: []const u8, comptime spec: LowerSpec) program_frontend.OpenRowProgram {
    return openRowWithRootSource(source_path, null, &.{}, spec);
}

fn openRowWithRootSource(
    comptime source_path: []const u8,
    comptime root_source: ?[:0]const u8,
    comptime imported_sources: []const ImportedSource,
    comptime spec: LowerSpec,
) program_frontend.OpenRowProgram {
    const graph = analyzeProgramGraphWithRootSource(source_path, root_source, imported_sources, spec.entry_symbol);
    const functions = buildFunctionsForGraph(graph, spec);
    return .{
        .label = spec.label,
        .entry_symbol = spec.entry_symbol,
        .entry_module_path = graph.functions[graph.entry_index].module_path,
        .functions = functions,
        .call_edges = buildCallEdgesForGraph(graph),
        .function_bodies = buildFunctionBodiesForGraph(
            graph,
            functions,
            if (root_source != null) source_path else null,
            root_source,
            imported_sources,
        ),
    };
}

/// Lower one explicit-path open-row payload into the retained effect-ir shell.
pub fn lowerOpenRowAt(comptime source_path: []const u8, comptime spec: LowerSpec) LowerError!source_lowering.OpenRowGeneratedProgram {
    return try source_lowering.lowerOpenRowProgram(openRowAt(source_path, spec));
}

/// Rebuild the public effect-ir program view for one additive lowering request.
pub fn irProgramAt(comptime source_path: []const u8, comptime spec: LowerSpec) effect_ir.Program {
    const payload = openRowAt(source_path, spec);
    return .{
        .entry_index = explicitEntryIndex(payload.functions, spec.entry_symbol, payload.entry_module_path),
        .functions = payload.functions,
        .call_edges = payload.call_edges,
        .function_bodies = payload.function_bodies,
    };
}

const max_validation_modules = 64;
const max_validation_functions = 256;
const max_validation_helper_edges = 1024;
const max_validation_direct_op_uses = 2048;

const ValidationFunction = struct {
    name: []u8,
};

const ValidationImport = struct {
    name: []u8,
    import_path: []u8,
};

const ValidationHelperUse = struct {
    caller_index: usize,
    callee_name: []u8,
    import_alias: ?[]u8,
};

const ValidationHelperEdge = struct {
    caller_index: usize,
    callee_index: usize,
};

const ValidationOwnedSource = struct {
    path: []u8,
    content: [:0]const u8,
};

const ValidationSourceGraph = struct {
    allocator: std.mem.Allocator,
    root_path: []const u8,
    owned_sources: []ValidationOwnedSource,

    fn init(
        allocator: std.mem.Allocator,
        source_path: []const u8,
        root_source: [:0]const u8,
        imported_sources: []const ImportedSource,
        mirror_repo_sources: bool,
    ) ValidationError!@This() {
        var owned_sources = std.ArrayList(ValidationOwnedSource).empty;
        errdefer {
            for (owned_sources.items) |owned_source| allocator.free(owned_source.path);
            owned_sources.deinit(allocator);
        }

        const normalized_root_path = try normalizeValidationOwnedPathAlloc(allocator, source_path);
        var root_path_owned_by_list = false;
        errdefer if (!root_path_owned_by_list) allocator.free(normalized_root_path);
        try owned_sources.append(allocator, .{
            .path = normalized_root_path,
            .content = if (mirror_repo_sources)
                try validationOwnedSourceContent(allocator, normalized_root_path, root_source)
            else
                root_source,
        });
        root_path_owned_by_list = true;

        for (imported_sources) |imported_source| {
            const normalized_path = try normalizeValidationOwnedPathAlloc(allocator, imported_source.path);
            var path_owned_by_list = false;
            errdefer if (!path_owned_by_list) allocator.free(normalized_path);
            try owned_sources.append(allocator, .{
                .path = normalized_path,
                .content = if (mirror_repo_sources)
                    try validationOwnedSourceContent(allocator, normalized_path, imported_source.content)
                else
                    imported_source.content,
            });
            path_owned_by_list = true;
        }

        const slice = try owned_sources.toOwnedSlice(allocator);
        return .{
            .allocator = allocator,
            .root_path = slice[0].path,
            .owned_sources = slice,
        };
    }

    fn deinit(self: *@This()) void {
        for (self.owned_sources) |owned_source| self.allocator.free(owned_source.path);
        self.allocator.free(self.owned_sources);
    }

    fn contentForPath(self: *const @This(), source_path: []const u8) ?[:0]const u8 {
        for (self.owned_sources) |owned_source| {
            if (std.mem.eql(u8, owned_source.path, source_path)) return owned_source.content;
        }
        return null;
    }
};

const ValidationModule = struct {
    path: []u8,
    absolute_entry_tree_root: ?[]u8,
    functions: []ValidationFunction,
    imports: []ValidationImport,
    helper_uses: []ValidationHelperUse,
    helper_edges: []ValidationHelperEdge,
    reachable_functions: []bool,
    expanded_helper_uses: []bool,
    helper_edge_count: usize,
    direct_op_use_count: usize,
};

const ValidationState = struct {
    allocator: std.mem.Allocator,
    modules: std.ArrayList(ValidationModule) = .empty,
    function_count: usize = 0,
    helper_edge_count: usize = 0,
    direct_op_use_count: usize = 0,

    fn deinit(self: *@This()) void {
        for (self.modules.items) |*module| {
            self.allocator.free(module.path);
            if (module.absolute_entry_tree_root) |tree_root| self.allocator.free(tree_root);
            for (module.functions) |function| self.allocator.free(function.name);
            self.allocator.free(module.functions);
            for (module.imports) |import_alias| {
                self.allocator.free(import_alias.name);
                self.allocator.free(import_alias.import_path);
            }
            self.allocator.free(module.imports);
            for (module.helper_uses) |helper_use| {
                self.allocator.free(helper_use.callee_name);
                if (helper_use.import_alias) |import_alias| self.allocator.free(import_alias);
            }
            self.allocator.free(module.helper_uses);
            self.allocator.free(module.helper_edges);
            self.allocator.free(module.reachable_functions);
            self.allocator.free(module.expanded_helper_uses);
        }
        self.modules.deinit(self.allocator);
    }

    fn findModuleIndex(self: *const @This(), source_path: []const u8) ?usize {
        for (self.modules.items, 0..) |module, index| {
            if (std.mem.eql(u8, module.path, source_path)) return index;
        }
        return null;
    }
};

const ResolvedOwnedValidationImport = struct {
    path: []u8,
    absolute_entry_tree_root: ?[]u8,
};

fn freeValidationGraphBuffers(allocator: std.mem.Allocator, graph: source_graph_engine.ModuleGraph) void {
    allocator.free(graph.functions);
    allocator.free(graph.imports);
    allocator.free(graph.helper_uses);
    allocator.free(graph.helper_edges);
    allocator.free(graph.direct_op_uses);
}

fn deinitValidationGraph(allocator: std.mem.Allocator, graph: source_graph_engine.ModuleGraph) void {
    for (graph.functions) |function| allocator.free(function.name);
    allocator.free(graph.functions);
    for (graph.imports) |import_alias| {
        allocator.free(import_alias.name);
        allocator.free(import_alias.import_path);
    }
    allocator.free(graph.imports);
    for (graph.helper_uses) |helper_use| {
        allocator.free(helper_use.callee_name);
        if (helper_use.import_alias) |import_alias| allocator.free(import_alias);
    }
    allocator.free(graph.helper_uses);
    for (graph.helper_edges) |edge| {
        allocator.free(edge.caller_name);
        allocator.free(edge.callee_name);
    }
    allocator.free(graph.helper_edges);
    for (graph.direct_op_uses) |direct_op_use| {
        allocator.free(direct_op_use.requirement_label);
        allocator.free(direct_op_use.op_name);
    }
    allocator.free(graph.direct_op_uses);
}

fn cloneValidationGraphAlloc(
    allocator: std.mem.Allocator,
    graph: source_graph_engine.ModuleGraph,
) !source_graph_engine.ModuleGraph {
    var owned_functions = try allocator.alloc(source_graph_engine.FunctionNode, graph.functions.len);
    errdefer allocator.free(owned_functions);
    for (graph.functions, 0..) |function, index| {
        errdefer for (owned_functions[0..index]) |owned| allocator.free(owned.name);
        owned_functions[index] = function;
        owned_functions[index].name = try allocator.dupe(u8, function.name);
    }

    var owned_imports = try allocator.alloc(source_graph_engine.ImportAlias, graph.imports.len);
    errdefer allocator.free(owned_imports);
    for (graph.imports, 0..) |import_alias, index| {
        errdefer for (owned_imports[0..index]) |owned| {
            allocator.free(owned.name);
            allocator.free(owned.import_path);
        };
        owned_imports[index] = .{
            .name = try allocator.dupe(u8, import_alias.name),
            .import_path = try allocator.dupe(u8, import_alias.import_path),
        };
    }

    var owned_helper_uses = try allocator.alloc(source_graph_engine.HelperUse, graph.helper_uses.len);
    errdefer allocator.free(owned_helper_uses);
    for (graph.helper_uses, 0..) |helper_use, index| {
        errdefer for (owned_helper_uses[0..index]) |owned| {
            allocator.free(owned.callee_name);
            if (owned.import_alias) |import_alias| allocator.free(import_alias);
        };
        owned_helper_uses[index] = helper_use;
        owned_helper_uses[index].callee_name = try allocator.dupe(u8, helper_use.callee_name);
        owned_helper_uses[index].import_alias = if (helper_use.import_alias) |import_alias|
            try allocator.dupe(u8, import_alias)
        else
            null;
    }

    var owned_helper_edges = try allocator.alloc(source_graph_engine.HelperEdge, graph.helper_edges.len);
    errdefer allocator.free(owned_helper_edges);
    for (graph.helper_edges, 0..) |edge, index| {
        errdefer for (owned_helper_edges[0..index]) |owned| {
            allocator.free(owned.caller_name);
            allocator.free(owned.callee_name);
        };
        owned_helper_edges[index] = edge;
        owned_helper_edges[index].caller_name = try allocator.dupe(u8, edge.caller_name);
        owned_helper_edges[index].callee_name = try allocator.dupe(u8, edge.callee_name);
    }

    var owned_direct_op_uses = try allocator.alloc(source_graph_engine.DirectOpUse, graph.direct_op_uses.len);
    errdefer allocator.free(owned_direct_op_uses);
    for (graph.direct_op_uses, 0..) |direct_op_use, index| {
        errdefer for (owned_direct_op_uses[0..index]) |owned| {
            allocator.free(owned.requirement_label);
            allocator.free(owned.op_name);
        };
        owned_direct_op_uses[index] = direct_op_use;
        owned_direct_op_uses[index].requirement_label = try allocator.dupe(u8, direct_op_use.requirement_label);
        owned_direct_op_uses[index].op_name = try allocator.dupe(u8, direct_op_use.op_name);
    }

    return .{
        .entry_index = graph.entry_index,
        .functions = owned_functions,
        .imports = owned_imports,
        .helper_uses = owned_helper_uses,
        .helper_edges = owned_helper_edges,
        .direct_op_uses = owned_direct_op_uses,
    };
}

fn cloneValidationFunctionsAlloc(
    allocator: std.mem.Allocator,
    functions: []const source_graph_engine.FunctionNode,
) ![]ValidationFunction {
    const out = try allocator.alloc(ValidationFunction, functions.len);
    errdefer allocator.free(out);
    for (functions, 0..) |function, index| {
        errdefer for (out[0..index]) |owned| allocator.free(owned.name);
        out[index] = .{
            .name = try allocator.dupe(u8, function.name),
        };
    }
    return out;
}

fn cloneValidationImportsAlloc(
    allocator: std.mem.Allocator,
    imports: []const source_graph_engine.ImportAlias,
) ![]ValidationImport {
    const out = try allocator.alloc(ValidationImport, imports.len);
    errdefer allocator.free(out);
    for (imports, 0..) |import_alias, index| {
        errdefer for (out[0..index]) |owned| {
            allocator.free(owned.name);
            allocator.free(owned.import_path);
        };
        out[index] = .{
            .name = try allocator.dupe(u8, import_alias.name),
            .import_path = try allocator.dupe(u8, import_alias.import_path),
        };
    }
    return out;
}

fn cloneValidationHelperUsesAlloc(
    allocator: std.mem.Allocator,
    helper_uses: []const source_graph_engine.HelperUse,
) ![]ValidationHelperUse {
    const out = try allocator.alloc(ValidationHelperUse, helper_uses.len);
    errdefer allocator.free(out);
    for (helper_uses, 0..) |helper_use, index| {
        errdefer for (out[0..index]) |owned| {
            allocator.free(owned.callee_name);
            if (owned.import_alias) |import_alias| allocator.free(import_alias);
        };
        out[index] = .{
            .caller_index = helper_use.caller_index,
            .callee_name = try allocator.dupe(u8, helper_use.callee_name),
            .import_alias = if (helper_use.import_alias) |import_alias| try allocator.dupe(u8, import_alias) else null,
        };
    }
    return out;
}

fn cloneValidationHelperEdgesAlloc(
    allocator: std.mem.Allocator,
    helper_edges: []const source_graph_engine.HelperEdge,
) ![]ValidationHelperEdge {
    const out = try allocator.alloc(ValidationHelperEdge, helper_edges.len);
    errdefer allocator.free(out);
    for (helper_edges, 0..) |helper_edge, index| {
        out[index] = .{
            .caller_index = helper_edge.caller_index,
            .callee_index = helper_edge.callee_index,
        };
    }
    return out;
}

fn findValidationFunctionIndex(functions: []const ValidationFunction, name: []const u8) ?usize {
    for (functions, 0..) |function, index| {
        if (std.mem.eql(u8, function.name, name)) return index;
    }
    return null;
}

fn findValidationImport(imports: []const ValidationImport, name: []const u8) ?ValidationImport {
    for (imports) |import_alias| {
        if (std.mem.eql(u8, import_alias.name, name)) return import_alias;
    }
    return null;
}

fn packageRootRelativeSlice(source_path: []const u8) ?[]const u8 {
    return runtimeRootRelativeSlice(source_path, build_options.package_root);
}

fn runtimeRootRelativeSlice(path: []const u8, root: []const u8) ?[]const u8 {
    if (!pathStartsWithRootRuntime(path, root)) return null;
    if (path.len <= root.len) return null;
    const separator = path[root.len];
    if (separator != '/' and separator != '\\') return null;
    return path[root.len + 1 ..];
}

fn runtimeRegistryContainsLine(registry: []const u8, candidate: []const u8) bool {
    var start: usize = 0;
    while (start < registry.len) {
        var end = start;
        while (end < registry.len and registry[end] != '\n') : (end += 1) {}
        const line = registry[start..end];
        if (line.len != 0 and pathEqualsRuntime(line, candidate)) return true;
        start = end + 1;
    }
    return false;
}

fn validationOwnedRepoCanonicalPathAlloc(allocator: std.mem.Allocator, source_path: []const u8) ValidationError!?[]u8 {
    if (!std.fs.path.isAbsolute(source_path)) {
        const repo_path = try normalizeRelativeRepoPathAlloc(allocator, source_path);
        errdefer allocator.free(repo_path);
        if (!runtimeRegistryContainsLine(build_options.repo_zig_paths, repo_path)) {
            allocator.free(repo_path);
            return null;
        }
        const canonical_repo_path = try canonicalPackageRootRelativePathAlloc(allocator, repo_path);
        allocator.free(repo_path);
        return canonical_repo_path;
    }

    const canonical_source_path = canonicalValidationSourcePathAlloc(allocator, source_path) catch |err| switch (err) {
        error.UnsupportedHelperGraph => return null,
        else => return err,
    };
    errdefer allocator.free(canonical_source_path);

    const repo_path = packageRootRelativeSlice(canonical_source_path) orelse return null;
    const normalized_repo_path = try normalizeRelativeRepoPathAlloc(allocator, repo_path);
    errdefer allocator.free(normalized_repo_path);
    if (!runtimeRegistryContainsLine(build_options.repo_zig_paths, normalized_repo_path)) {
        allocator.free(normalized_repo_path);
        allocator.free(canonical_source_path);
        return null;
    }
    allocator.free(normalized_repo_path);
    return canonical_source_path;
}

fn validationOwnedSourceContent(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    source_content: [:0]const u8,
) ValidationError![:0]const u8 {
    const canonical_repo_path = try validationOwnedRepoCanonicalPathAlloc(allocator, source_path);
    defer if (canonical_repo_path) |repo_path| allocator.free(repo_path);

    const disk_path = canonical_repo_path orelse if (std.fs.path.isAbsolute(source_path))
        source_path
    else
        return source_content;

    const repo_file = std.fs.openFileAbsolute(disk_path, .{}) catch return error.SourceUnreadable;
    defer repo_file.close();
    const repo_source = repo_file.readToEndAllocOptions(
        allocator,
        std.math.maxInt(usize),
        null,
        .of(u8),
        0,
    ) catch return error.SourceUnreadable;
    defer allocator.free(repo_source);
    if (!std.mem.eql(u8, repo_source, source_content)) {
        return error.SourceDrifted;
    }
    return source_content;
}

fn normalizeRelativeRepoPathAlloc(allocator: std.mem.Allocator, source_path: []const u8) ValidationError![]u8 {
    var segments = std.ArrayList([]const u8).empty;
    defer segments.deinit(allocator);

    var start: usize = 0;
    var index: usize = 0;
    while (index <= source_path.len) : (index += 1) {
        if (index != source_path.len and source_path[index] != '/' and source_path[index] != '\\') continue;
        const segment = source_path[start..index];
        start = index + 1;
        if (segment.len == 0 or std.mem.eql(u8, segment, ".")) continue;
        if (std.mem.eql(u8, segment, "..")) {
            if (segments.items.len == 0) return error.UnsupportedHelperGraph;
            _ = segments.pop();
            continue;
        }
        try segments.append(allocator, segment);
    }
    if (segments.items.len == 0) return error.UnsupportedHelperGraph;

    return std.fs.path.join(allocator, segments.items) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => unreachable,
    };
}

fn canonicalPackageRootRelativePathAlloc(allocator: std.mem.Allocator, repo_path: []const u8) ValidationError![]u8 {
    const normalized_repo_path = try normalizeRelativeRepoPathAlloc(allocator, repo_path);
    defer allocator.free(normalized_repo_path);

    const package_root_candidate = std.fs.path.join(allocator, &.{ build_options.package_root, normalized_repo_path }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => unreachable,
    };
    defer allocator.free(package_root_candidate);

    const canonical_path = std.fs.realpathAlloc(allocator, package_root_candidate) catch return error.UnsupportedHelperGraph;
    errdefer allocator.free(canonical_path);
    if (!pathStartsWithRootRuntime(canonical_path, build_options.package_root)) {
        return error.UnsupportedHelperGraph;
    }
    return canonical_path;
}

fn lexicalPackageRootRelativePathAlloc(allocator: std.mem.Allocator, repo_path: []const u8) ValidationError![]u8 {
    const normalized_repo_path = try normalizeRelativeRepoPathAlloc(allocator, repo_path);
    defer allocator.free(normalized_repo_path);

    const package_root_candidate = std.fs.path.join(allocator, &.{ build_options.package_root, normalized_repo_path }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => unreachable,
    };
    defer allocator.free(package_root_candidate);

    return std.fs.path.resolve(allocator, &.{package_root_candidate}) catch return error.OutOfMemory;
}

fn canonicalValidationSourcePathAlloc(allocator: std.mem.Allocator, source_path: []const u8) ValidationError![]u8 {
    if (source_path.len == 0) return error.UnsupportedHelperGraph;

    var owned_canonical_path: ?[]u8 = null;
    defer if (owned_canonical_path) |canonical_path| allocator.free(canonical_path);

    if (packageRootRelativeSlice(source_path)) |repo_path| {
        owned_canonical_path = try canonicalPackageRootRelativePathAlloc(allocator, repo_path);
        return allocator.dupe(u8, owned_canonical_path.?) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
    }

    if (!std.fs.path.isAbsolute(source_path)) {
        owned_canonical_path = canonicalPackageRootRelativePathAlloc(allocator, source_path) catch |err| switch (err) {
            error.UnsupportedHelperGraph => null,
            error.OutOfMemory => return error.OutOfMemory,
            else => return err,
        };
        if (owned_canonical_path) |canonical_path| {
            return allocator.dupe(u8, canonical_path) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
            };
        }

        owned_canonical_path = std.fs.cwd().realpathAlloc(allocator, source_path) catch return error.UnsupportedHelperGraph;
        if (!pathStartsWithRootRuntime(owned_canonical_path.?, build_options.package_root)) {
            return error.UnsupportedHelperGraph;
        }
        return allocator.dupe(u8, owned_canonical_path.?) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
    }

    owned_canonical_path = std.fs.realpathAlloc(allocator, source_path) catch return error.UnsupportedHelperGraph;
    if (!pathStartsWithRootRuntime(owned_canonical_path.?, build_options.package_root)) {
        return error.UnsupportedHelperGraph;
    }
    return allocator.dupe(u8, owned_canonical_path.?) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
    };
}

fn normalizeValidationOwnedPathAlloc(allocator: std.mem.Allocator, source_path: []const u8) ValidationError![]u8 {
    if (source_path.len == 0) return error.UnsupportedHelperGraph;

    if (packageRootRelativeSlice(source_path)) |repo_path| {
        return lexicalPackageRootRelativePathAlloc(allocator, repo_path);
    }
    if (!std.fs.path.isAbsolute(source_path)) {
        return lexicalPackageRootRelativePathAlloc(allocator, source_path);
    }
    return std.fs.path.resolve(allocator, &.{source_path}) catch return error.OutOfMemory;
}

fn absoluteOwnedImportTreeRootAlloc(
    allocator: std.mem.Allocator,
    base_dir: []const u8,
    boundary: source_graph_embed.AbsoluteOwnedImportBoundary,
) ValidationError![]u8 {
    return switch (boundary.leading_parent_count) {
        0 => allocator.dupe(u8, base_dir) catch return error.OutOfMemory,
        1 => std.fs.path.resolve(allocator, &.{ base_dir, "..", boundary.first_segment }) catch return error.OutOfMemory,
        else => unreachable,
    };
}

fn resolveValidationImportPathAlloc(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    import_path: []const u8,
) ValidationError![]u8 {
    var decoded_import_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const decoded_import_path = source_graph_engine.decodeImportPathLiteral(
        import_path,
        &decoded_import_path_buffer,
    ) orelse return error.UnsupportedHelperGraph;
    if (source_graph_embed.pathIsAbsoluteCrossPlatform(decoded_import_path)) return error.UnsupportedHelperGraph;
    if (!std.mem.endsWith(u8, decoded_import_path, ".zig")) return error.UnsupportedHelperGraph;

    if (packageRootRelativeSlice(source_path)) |repo_source_path| {
        const normalized_repo_source_path = try normalizeRelativeRepoPathAlloc(allocator, repo_source_path);
        defer allocator.free(normalized_repo_source_path);
        const base_dir = std.fs.path.dirname(normalized_repo_source_path) orelse "";

        var joined = std.ArrayList(u8).empty;
        defer joined.deinit(allocator);
        if (base_dir.len != 0) {
            try joined.appendSlice(allocator, base_dir);
            try joined.append(allocator, '/');
        }
        try joined.appendSlice(allocator, decoded_import_path);
        const imported_repo_path = try normalizeRelativeRepoPathAlloc(allocator, joined.items);
        defer allocator.free(imported_repo_path);
        return try canonicalPackageRootRelativePathAlloc(allocator, imported_repo_path);
    }

    if (!std.fs.path.isAbsolute(source_path)) return error.UnsupportedHelperGraph;
    const canonical_source_path = try canonicalValidationSourcePathAlloc(allocator, source_path);
    defer allocator.free(canonical_source_path);
    const repo_source_path = packageRootRelativeSlice(canonical_source_path) orelse return error.UnsupportedHelperGraph;
    return try resolveValidationImportPathAlloc(allocator, repo_source_path, decoded_import_path);
}

fn resolveOwnedValidationImportPathAlloc(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    import_path: []const u8,
    absolute_entry_tree_root: ?[]const u8,
) ValidationError!ResolvedOwnedValidationImport {
    var decoded_import_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const decoded_import_path = source_graph_engine.decodeImportPathLiteral(
        import_path,
        &decoded_import_path_buffer,
    ) orelse return error.UnsupportedHelperGraph;
    if (source_graph_embed.pathIsAbsoluteCrossPlatform(decoded_import_path)) return error.UnsupportedHelperGraph;
    if (!std.mem.endsWith(u8, decoded_import_path, ".zig")) return error.UnsupportedHelperGraph;

    if (packageRootRelativeSlice(source_path)) |repo_source_path| {
        const normalized_repo_source_path = try normalizeRelativeRepoPathAlloc(allocator, repo_source_path);
        defer allocator.free(normalized_repo_source_path);
        const base_dir = std.fs.path.dirname(normalized_repo_source_path) orelse "";

        var joined = std.ArrayList(u8).empty;
        defer joined.deinit(allocator);
        if (base_dir.len != 0) {
            try joined.appendSlice(allocator, base_dir);
            try joined.append(allocator, '/');
        }
        try joined.appendSlice(allocator, decoded_import_path);
        const imported_repo_path = try normalizeRelativeRepoPathAlloc(allocator, joined.items);
        defer allocator.free(imported_repo_path);
        return .{
            .path = try lexicalPackageRootRelativePathAlloc(allocator, imported_repo_path),
            .absolute_entry_tree_root = null,
        };
    }

    if (!std.fs.path.isAbsolute(source_path)) return error.UnsupportedHelperGraph;
    const boundary = source_graph_embed.absoluteOwnedImportBoundary(decoded_import_path) orelse return error.UnsupportedHelperGraph;
    const base_dir = std.fs.path.dirname(source_path) orelse return error.UnsupportedHelperGraph;
    const joined_path = std.fs.path.join(allocator, &.{ base_dir, decoded_import_path }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => unreachable,
    };
    defer allocator.free(joined_path);
    const resolved_path = std.fs.path.resolve(allocator, &.{joined_path}) catch return error.OutOfMemory;
    errdefer allocator.free(resolved_path);
    const next_absolute_entry_tree_root = if (absolute_entry_tree_root) |tree_root| blk: {
        if (!pathStartsWithRootRuntime(resolved_path, tree_root)) return error.UnsupportedHelperGraph;
        break :blk allocator.dupe(u8, tree_root) catch return error.OutOfMemory;
    } else try absoluteOwnedImportTreeRootAlloc(allocator, base_dir, boundary);
    errdefer allocator.free(next_absolute_entry_tree_root);
    return .{
        .path = resolved_path,
        .absolute_entry_tree_root = next_absolute_entry_tree_root,
    };
}

fn analyzeValidationModuleGraph(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    entry_symbol: ?[]const u8,
    source_graph: ?*const ValidationSourceGraph,
    expected_graph: ?*const ValidationSourceGraph,
) ValidationError!source_graph_engine.ModuleGraph {
    if (source_graph) |owned_graph| {
        if (owned_graph.contentForPath(source_path)) |source_bytes| {
            const graph = source_graph_engine.analyzeRuntime(allocator, source_bytes, .{
                .entry_symbol = entry_symbol,
                .reject_indirect_effect_access = true,
            }) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.EntryMissing => return error.EntryMissing,
                error.ParseError => return error.ParseError,
                error.MissingImport => return error.UnsupportedHelperGraph,
                error.RecursiveHelpers => return error.UnsupportedHelperGraph,
                error.TooManyFunctions => return error.UnsupportedHelperGraph,
                error.TooManyFunctionParams => return error.UnsupportedHelperGraph,
                error.TooManyImports => return error.UnsupportedHelperGraph,
                error.TooManyHelperUses => return error.UnsupportedHelperGraph,
                error.TooManyHelperEdges => return error.UnsupportedHelperGraph,
                error.TooManyOpUses => return error.UnsupportedHelperGraph,
                error.UnsupportedEffectAccess => return error.UnsupportedEffectAccess,
                error.UnsupportedImportPath => return error.UnsupportedHelperGraph,
            };
            defer freeValidationGraphBuffers(allocator, graph);
            return cloneValidationGraphAlloc(allocator, graph) catch return error.OutOfMemory;
        }

        return error.UnsupportedHelperGraph;
    }

    var analysis = source_lowering.analyzeFileBackedSource(allocator, source_path) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.ParseError => return error.ParseError,
        error.SourceUnreadable => return error.SourceUnreadable,
        error.TooManyFunctions,
        error.TooManyFunctionParams,
        error.TooManyImports,
        error.TooManyHelperUses,
        error.TooManyHelperEdges,
        error.TooManyOpUses,
        => return error.UnsupportedHelperGraph,
        error.UnsupportedEffectAccess => return error.UnsupportedEffectAccess,
        else => unreachable,
    };
    defer analysis.deinit(allocator);
    if (expected_graph) |expected| {
        const expected_source = expected.contentForPath(source_path) orelse return error.SourceDrifted;
        if (!std.mem.eql(u8, expected_source, analysis.parsed.source_z)) return error.SourceDrifted;
    }

    if (!analysis.isParseClean()) return error.ParseError;
    const graph = source_graph_engine.analyzeRuntime(allocator, analysis.parsed.source_z, .{
        .entry_symbol = entry_symbol,
        .reject_indirect_effect_access = true,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.EntryMissing => return error.EntryMissing,
        error.ParseError => return error.ParseError,
        error.MissingImport => return error.UnsupportedHelperGraph,
        error.RecursiveHelpers => return error.UnsupportedHelperGraph,
        error.TooManyFunctions => return error.UnsupportedHelperGraph,
        error.TooManyFunctionParams => return error.UnsupportedHelperGraph,
        error.TooManyImports => return error.UnsupportedHelperGraph,
        error.TooManyHelperUses => return error.UnsupportedHelperGraph,
        error.TooManyHelperEdges => return error.UnsupportedHelperGraph,
        error.TooManyOpUses => return error.UnsupportedHelperGraph,
        error.UnsupportedEffectAccess => return error.UnsupportedEffectAccess,
        error.UnsupportedImportPath => return error.UnsupportedHelperGraph,
    };
    defer freeValidationGraphBuffers(allocator, graph);
    return cloneValidationGraphAlloc(allocator, graph) catch return error.OutOfMemory;
}

fn markValidationReachableFunctions(
    module: *ValidationModule,
    root_index: usize,
) void {
    if (root_index >= module.reachable_functions.len) return;
    if (!module.reachable_functions[root_index]) module.reachable_functions[root_index] = true;

    var changed = true;
    while (changed) {
        changed = false;
        for (module.helper_edges) |edge| {
            if (!module.reachable_functions[edge.caller_index] or module.reachable_functions[edge.callee_index]) continue;
            module.reachable_functions[edge.callee_index] = true;
            changed = true;
        }
    }
}

fn expandValidationModuleImports(
    state: *ValidationState,
    module_index: usize,
    source_graph: ?*const ValidationSourceGraph,
    expected_graph: ?*const ValidationSourceGraph,
) ValidationError!void {
    var helper_use_index: usize = 0;
    while (helper_use_index < state.modules.items[module_index].helper_uses.len) : (helper_use_index += 1) {
        const module = state.modules.items[module_index];
        const helper_use = module.helper_uses[helper_use_index];
        if (!module.reachable_functions[helper_use.caller_index] or module.expanded_helper_uses[helper_use_index]) continue;

        state.modules.items[module_index].expanded_helper_uses[helper_use_index] = true;
        const import_alias = helper_use.import_alias orelse continue;

        const import_row = findValidationImport(module.imports, import_alias) orelse return error.UnsupportedHelperGraph;
        const imported_path: ResolvedOwnedValidationImport = if (source_graph != null)
            try resolveOwnedValidationImportPathAlloc(
                state.allocator,
                module.path,
                import_row.import_path,
                module.absolute_entry_tree_root,
            )
        else
            .{
                .path = try resolveValidationImportPathAlloc(state.allocator, module.path, import_row.import_path),
                .absolute_entry_tree_root = null,
            };
        defer state.allocator.free(imported_path.path);
        defer if (imported_path.absolute_entry_tree_root) |tree_root| state.allocator.free(tree_root);

        _ = collectValidationModule(
            state,
            imported_path.path,
            helper_use.callee_name,
            source_graph,
            expected_graph,
            imported_path.absolute_entry_tree_root,
        ) catch |err| switch (err) {
            error.EntryMissing => return error.UnsupportedHelperGraph,
            else => return err,
        };

        state.helper_edge_count += 1;
        if (state.helper_edge_count > max_validation_helper_edges) return error.UnsupportedHelperGraph;
    }
}

fn collectValidationModule(
    state: *ValidationState,
    source_path: []const u8,
    required_symbol: ?[]const u8,
    source_graph: ?*const ValidationSourceGraph,
    expected_graph: ?*const ValidationSourceGraph,
    absolute_entry_tree_root: ?[]const u8,
) ValidationError!usize {
    if (state.findModuleIndex(source_path)) |existing_index| {
        const existing_absolute_entry_tree_root = state.modules.items[existing_index].absolute_entry_tree_root;
        if ((absolute_entry_tree_root == null) != (existing_absolute_entry_tree_root == null)) {
            return error.UnsupportedHelperGraph;
        }
        if (absolute_entry_tree_root) |tree_root| {
            if (!std.mem.eql(u8, tree_root, existing_absolute_entry_tree_root.?)) {
                return error.UnsupportedHelperGraph;
            }
        }
        if (required_symbol) |required_entry| {
            const required_index = findValidationFunctionIndex(state.modules.items[existing_index].functions, required_entry) orelse {
                return error.EntryMissing;
            };
            markValidationReachableFunctions(&state.modules.items[existing_index], required_index);
            try expandValidationModuleImports(state, existing_index, source_graph, expected_graph);
        }
        return existing_index;
    }

    const graph = try analyzeValidationModuleGraph(state.allocator, source_path, required_symbol, source_graph, expected_graph);
    defer deinitValidationGraph(state.allocator, graph);

    var module_owned_by_state = false;
    const owned_path = try state.allocator.dupe(u8, source_path);
    errdefer if (!module_owned_by_state) state.allocator.free(owned_path);
    const owned_absolute_entry_tree_root = if (absolute_entry_tree_root) |tree_root|
        try state.allocator.dupe(u8, tree_root)
    else
        null;
    errdefer if (!module_owned_by_state) if (owned_absolute_entry_tree_root) |tree_root| state.allocator.free(tree_root);
    const owned_functions = try cloneValidationFunctionsAlloc(state.allocator, graph.functions);
    errdefer if (!module_owned_by_state) {
        for (owned_functions) |function| state.allocator.free(function.name);
        state.allocator.free(owned_functions);
    };
    const owned_imports = try cloneValidationImportsAlloc(state.allocator, graph.imports);
    errdefer if (!module_owned_by_state) {
        for (owned_imports) |import_alias| {
            state.allocator.free(import_alias.name);
            state.allocator.free(import_alias.import_path);
        }
        state.allocator.free(owned_imports);
    };
    const owned_helper_uses = try cloneValidationHelperUsesAlloc(state.allocator, graph.helper_uses);
    errdefer if (!module_owned_by_state) {
        for (owned_helper_uses) |helper_use| {
            state.allocator.free(helper_use.callee_name);
            if (helper_use.import_alias) |import_alias| state.allocator.free(import_alias);
        }
        state.allocator.free(owned_helper_uses);
    };
    const owned_helper_edges = try cloneValidationHelperEdgesAlloc(state.allocator, graph.helper_edges);
    errdefer if (!module_owned_by_state) state.allocator.free(owned_helper_edges);
    const reachable_functions = try state.allocator.alloc(bool, graph.functions.len);
    errdefer if (!module_owned_by_state) state.allocator.free(reachable_functions);
    @memset(reachable_functions, false);
    const expanded_helper_uses = try state.allocator.alloc(bool, graph.helper_uses.len);
    errdefer if (!module_owned_by_state) state.allocator.free(expanded_helper_uses);
    @memset(expanded_helper_uses, false);

    if (state.modules.items.len >= max_validation_modules) return error.UnsupportedHelperGraph;
    try state.modules.append(state.allocator, .{
        .path = owned_path,
        .absolute_entry_tree_root = owned_absolute_entry_tree_root,
        .functions = owned_functions,
        .imports = owned_imports,
        .helper_uses = owned_helper_uses,
        .helper_edges = owned_helper_edges,
        .reachable_functions = reachable_functions,
        .expanded_helper_uses = expanded_helper_uses,
        .helper_edge_count = graph.helper_edges.len,
        .direct_op_use_count = graph.direct_op_uses.len,
    });
    module_owned_by_state = true;
    const module_index = state.modules.items.len - 1;
    const module = state.modules.items[module_index];

    state.function_count += module.functions.len;
    if (state.function_count > max_validation_functions) return error.UnsupportedHelperGraph;

    state.helper_edge_count += module.helper_edge_count;
    if (state.helper_edge_count > max_validation_helper_edges) return error.UnsupportedHelperGraph;

    state.direct_op_use_count += module.direct_op_use_count;
    if (state.direct_op_use_count > max_validation_direct_op_uses) return error.UnsupportedHelperGraph;

    if (required_symbol) |required_entry| {
        const required_index = findValidationFunctionIndex(state.modules.items[module_index].functions, required_entry) orelse {
            return error.EntryMissing;
        };
        markValidationReachableFunctions(&state.modules.items[module_index], required_index);
        try expandValidationModuleImports(state, module_index, source_graph, expected_graph);
    }

    return module_index;
}

/// Validate one explicit-path source file and entry symbol for the additive lowerer.
pub fn validateFileBackedOpenRowAt(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    entry_symbol: []const u8,
) ValidationError!void {
    const canonical_source_path = try canonicalValidationSourcePathAlloc(allocator, source_path);
    defer allocator.free(canonical_source_path);

    var validation = ValidationState{ .allocator = allocator };
    defer validation.deinit();
    _ = try collectValidationModule(&validation, canonical_source_path, entry_symbol, null, null, null);
}

fn validateFileBackedOpenRowAgainstSnapshot(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    root_source: [:0]const u8,
    imported_sources: []const ImportedSource,
    entry_symbol: []const u8,
) ValidationError!void {
    const canonical_source_path = try canonicalValidationSourcePathAlloc(allocator, source_path);
    defer allocator.free(canonical_source_path);

    var expected_graph = try ValidationSourceGraph.init(allocator, canonical_source_path, root_source, imported_sources, false);
    defer expected_graph.deinit();

    var validation = ValidationState{ .allocator = allocator };
    defer validation.deinit();
    _ = try collectValidationModule(&validation, canonical_source_path, entry_symbol, null, &expected_graph, null);
}

fn validateOwnedOpenRowAt(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    root_source: [:0]const u8,
    imported_sources: []const ImportedSource,
    entry_symbol: []const u8,
) ValidationError!void {
    var source_graph = try ValidationSourceGraph.init(allocator, source_path, root_source, imported_sources, true);
    defer source_graph.deinit();

    var validation = ValidationState{ .allocator = allocator };
    defer validation.deinit();
    _ = try collectValidationModule(&validation, source_graph.root_path, entry_symbol, &source_graph, null, null);
}

const ValidationSpec = struct {
    source_path: []const u8,
    entry_symbol: []const u8,
    root_source: ?[:0]const u8 = null,
    imported_sources: []const ImportedSource = &.{},
    snapshot_root_source: ?[:0]const u8 = null,
    snapshot_imported_sources: []const ImportedSource = &.{},
};

fn GeneratedProgramType(
    comptime label_value: []const u8,
    comptime source_path_value: []const u8,
    comptime entry_symbol_value: []const u8,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime supports_run: bool,
    comptime validate_spec: ?ValidationSpec,
) type {
    return struct {
        const RunResult = if (supports_run) LoweredRunResultTypeForPlan(compiled_plan) else void;
        /// Stable label for this compiled additive lowering request.
        pub const label = label_value;
        /// Caller-visible source path for this compiled additive lowering request.
        pub const source_path = source_path_value;
        /// Top-level entry symbol requested by this compiled additive lowering request.
        pub const entry_symbol = entry_symbol_value;
        /// Stable IR hash mirrored into the runtime-owned executable plan.
        pub const ir_hash = compiled_plan.ir_hash;
        /// Runtime-owned executable plan alias retained for the additive bridge.
        pub const runtime_plan = compiled_plan;

        /// Validate the named source file and entry symbol for this compiled additive lowering request.
        pub fn validate(allocator: std.mem.Allocator) ValidationError!void {
            const active_spec = validate_spec orelse return;
            if (active_spec.root_source) |root_source| {
                return try validateOwnedOpenRowAt(
                    allocator,
                    active_spec.source_path,
                    root_source,
                    active_spec.imported_sources,
                    active_spec.entry_symbol,
                );
            }
            if (active_spec.snapshot_root_source) |root_source| {
                return try validateFileBackedOpenRowAgainstSnapshot(
                    allocator,
                    active_spec.source_path,
                    root_source,
                    active_spec.snapshot_imported_sources,
                    active_spec.entry_symbol,
                );
            }
            return try validateFileBackedOpenRowAt(allocator, active_spec.source_path, active_spec.entry_symbol);
        }

        /// Execute this lowered program through its runtime_plan using explicit handler objects.
        pub fn run(runtime: *lowered_machine.Runtime, handlers: anytype) anyerror!RunResult {
            if (!supports_run) {
                @compileError("public lowered-program execution is available only when the entry function has no value parameters");
            }
            try lowered_machine.beginExecution(runtime);
            defer lowered_machine.endExecution(runtime);
            const outcome = try executeLoweredDispatch(compiled_plan, handlers, compiled_plan.entry_index, &.{});
            const value = switch (outcome) {
                .value => |typed| typed,
                .terminal => |typed| typed,
            };
            return .{
                .outputs = try collectLoweredOutputsForPlan(compiled_plan, handlers),
                .value = decodeRuntimeValue(compiled_plan.functions[compiled_plan.entry_index].value_codec, value),
            };
        }
    };
}

fn ensureAbsoluteTestDir(path: []const u8) !void {
    if (path.len == 0 or std.mem.eql(u8, path, "/")) return;
    const parent = std.fs.path.dirname(path) orelse return;
    if (!std.mem.eql(u8, parent, path)) try ensureAbsoluteTestDir(parent);
    std.fs.makeDirAbsolute(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

fn writeAbsoluteTestFile(path: []const u8, data: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return error.UnsupportedHelperGraph;
    try ensureAbsoluteTestDir(parent);
    const file = try std.fs.createFileAbsolute(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(data);
}

fn LowerAt(comptime source_path: []const u8, comptime spec: LowerSpec) type {
    comptime {
        @setEvalBranchQuota(1_000_000);
    }
    const graph = analyzeProgramGraphAt(source_path, spec.entry_symbol);
    const lowered_program = source_lowering.lowerOpenRowProgram(openRowAt(source_path, spec)) catch |err| switch (err) {
        error.DuplicateRequirementLabel => @compileError("public lowering rejected duplicate requirement labels"),
        error.DuplicateOpName => @compileError("public lowering rejected duplicate op names"),
        error.DuplicateOutputLabel => @compileError("public lowering rejected duplicate output labels"),
        error.EmptyRequirementLabel => @compileError("public lowering rejected an empty requirement label"),
        error.EmptyOpName => @compileError("public lowering rejected an empty op name"),
        error.InvalidProgramBodyShape => @compileError("public lowering rejected a helper-body payload that does not align to its function list"),
        error.InvalidRequirementShape => @compileError("public lowering rejected an invalid requirement shape"),
        error.InvalidRowShape => @compileError("public lowering rejected an invalid row shape"),
        error.OutputWithoutRequirement => @compileError("public lowering rejected outputs without matching requirements"),
        error.DuplicateSymbol => @compileError("public lowering rejected duplicate function symbols"),
        error.UnknownSymbol => @compileError("public lowering rejected an unknown function symbol"),
        error.UnsupportedHelperCallEdge => @compileError("public lowering rejected helper call edges outside the retained open-row shell"),
        error.OutOfMemory => @compileError("public lowering ran out of memory at comptime"),
    };
    const compiled_plan = program_plan.planFromOpenRowProgram(spec.label, lowered_program.program) catch |err| switch (err) {
        error.DuplicateRequirementLabel => @compileError("public lowering rejected duplicate requirement labels"),
        error.DuplicateOpName => @compileError("public lowering rejected duplicate op names"),
        error.DuplicateOutputLabel => @compileError("public lowering rejected duplicate output labels"),
        error.EmptyProgram => @compileError("public lowering rejected an empty effect-ir program"),
        error.EmptyRequirementLabel => @compileError("public lowering rejected an empty requirement label"),
        error.EmptyOpName => @compileError("public lowering rejected an empty op name"),
        error.InvalidProgramBodyShape => @compileError("public lowering rejected a helper-body payload that does not align to its function list"),
        error.InvalidRequirementShape => @compileError("public lowering rejected an invalid requirement shape"),
        error.InvalidRowShape => @compileError("public lowering rejected an invalid row shape"),
        error.OutputWithoutRequirement => @compileError("public lowering rejected outputs without matching requirements"),
        error.DuplicateSymbol => @compileError("public lowering rejected duplicate function symbols"),
        error.UnknownSymbol => @compileError("public lowering rejected an unknown function symbol"),
        error.UnsupportedHelperCallEdge => @compileError("public lowering runtime plan rejected helper call edges outside the retained open-row shell"),
        error.UnsupportedCodecType => @compileError("public lowering runtime plan rejected a type outside the first-wave codec set"),
        error.OutOfMemory => @compileError("public lowering ran out of memory at comptime"),
    };
    assertExecutableCodecSupport(compiled_plan);
    return GeneratedProgramType(
        spec.label,
        source_path,
        spec.entry_symbol,
        compiled_plan,
        true,
        .{
            .source_path = source_path,
            .entry_symbol = spec.entry_symbol,
            .snapshot_root_source = source_graph_embed.embeddedSource(source_path),
            .snapshot_imported_sources = buildValidationSnapshotImportedSources(graph, source_path),
        },
    );
}

fn Lower(comptime source_ref: SourceRef, comptime spec: LowerSpec) type {
    assertSourceOwnership(source_ref);
    if (source_ref.caller_source != null) {
        const caller_source = source_ref.caller_source.?;
        const source_path = sourcePathForLowering(source_ref);
        comptime {
            @setEvalBranchQuota(20_000);
        }
        const lowered_program = source_lowering.lowerOpenRowProgram(openRowWithRootSource(source_path, caller_source, source_ref.imported_sources, spec)) catch |err| switch (err) {
            error.DuplicateRequirementLabel => @compileError("public lowering rejected duplicate requirement labels"),
            error.DuplicateOpName => @compileError("public lowering rejected duplicate op names"),
            error.DuplicateOutputLabel => @compileError("public lowering rejected duplicate output labels"),
            error.EmptyRequirementLabel => @compileError("public lowering rejected an empty requirement label"),
            error.EmptyOpName => @compileError("public lowering rejected an empty op name"),
            error.InvalidProgramBodyShape => @compileError("public lowering rejected one helper body outside the retained lowered-body subset"),
            error.InvalidRequirementShape => @compileError("public lowering rejected a requirement shape produced by source lowering"),
            error.InvalidRowShape => @compileError("public lowering rejected a row shape produced by source lowering"),
            error.OutputWithoutRequirement => @compileError("public lowering rejected source-lowered outputs without matching requirements"),
            error.DuplicateSymbol => @compileError("public lowering rejected duplicate function symbols"),
            error.UnknownSymbol => @compileError("public lowering rejected an unknown function symbol"),
            error.UnsupportedHelperCallEdge => @compileError("public lowering rejected helper call edges outside the retained open-row shell"),
            error.OutOfMemory => @compileError("public lowering ran out of memory at comptime"),
        };
        const compiled_plan = program_plan.planFromOpenRowProgram(spec.label, lowered_program.program) catch |err| switch (err) {
            error.DuplicateRequirementLabel => @compileError("public lowering rejected duplicate requirement labels"),
            error.DuplicateOpName => @compileError("public lowering rejected duplicate op names"),
            error.DuplicateOutputLabel => @compileError("public lowering rejected duplicate output labels"),
            error.EmptyProgram => @compileError("public lowering rejected an empty effect-ir program"),
            error.EmptyRequirementLabel => @compileError("public lowering rejected an empty requirement label"),
            error.EmptyOpName => @compileError("public lowering rejected an empty op name"),
            error.InvalidProgramBodyShape => @compileError("public lowering rejected a helper-body payload that does not align to its function list"),
            error.InvalidRequirementShape => @compileError("public lowering rejected an invalid requirement shape"),
            error.InvalidRowShape => @compileError("public lowering rejected an invalid row shape"),
            error.OutputWithoutRequirement => @compileError("public lowering rejected outputs without matching requirements"),
            error.DuplicateSymbol => @compileError("public lowering rejected duplicate function symbols"),
            error.UnknownSymbol => @compileError("public lowering rejected an unknown function symbol"),
            error.UnsupportedHelperCallEdge => @compileError("public lowering runtime plan rejected helper call edges outside the retained open-row shell"),
            error.UnsupportedCodecType => @compileError("public lowering runtime plan rejected a type outside the first-wave codec set"),
            error.OutOfMemory => @compileError("public lowering ran out of memory at comptime"),
        };
        assertExecutableCodecSupport(compiled_plan);
        return GeneratedProgramType(
            spec.label,
            source_path,
            spec.entry_symbol,
            compiled_plan,
            true,
            .{
                .source_path = source_path,
                .entry_symbol = spec.entry_symbol,
                .root_source = caller_source,
                .imported_sources = source_ref.imported_sources,
            },
        );
    }
    return LowerAt(sourcePathForLowering(source_ref), spec);
}

/// Compile one lowering request from an explicit caller-owned provenance witness.
pub const lower = Lower;

/// Compile one explicit-path lowering request into a generated type using a caller-visible source path.
pub const lowerAt = LowerAt;

/// Execute one generated lowered program through its runtime_plan.
pub fn run(runtime: *lowered_machine.Runtime, comptime LoweredProgramType: type, handlers: anytype) anyerror!LoweredProgramType.RunResult {
    return try LoweredProgramType.run(runtime, handlers);
}

fn CompileIrType(comptime label: []const u8, comptime program: effect_ir.Program) type {
    comptime {
        @setEvalBranchQuota(20_000);
    }
    if (program.functions.len == 0) @compileError("public lowering cannot compile an empty effect-ir program");
    if (program.entry_index >= program.functions.len) {
        @compileError("public lowering rejected an effect-ir program with an out-of-range entry_index");
    }
    const entry_function = program.functions[program.entry_index];
    const stable_ir_program = cloneProgram(program);
    const compiled_plan = program_plan.planFromProgram(label, stable_ir_program) catch |err| switch (err) {
        error.DuplicateRequirementLabel => @compileError("public lowering rejected duplicate requirement labels"),
        error.DuplicateOpName => @compileError("public lowering rejected duplicate op names"),
        error.DuplicateOutputLabel => @compileError("public lowering rejected duplicate output labels"),
        error.EmptyProgram => @compileError("public lowering rejected an empty effect-ir program"),
        error.EmptyRequirementLabel => @compileError("public lowering rejected an empty requirement label"),
        error.EmptyOpName => @compileError("public lowering rejected an empty op name"),
        error.InvalidProgramBodyShape => @compileError("public lowering rejected an effect-ir program whose helper-body payload does not align to its function list"),
        error.InvalidRequirementShape => @compileError("public lowering rejected an invalid requirement shape"),
        error.InvalidRowShape => @compileError("public lowering rejected an invalid row shape"),
        error.OutputWithoutRequirement => @compileError("public lowering rejected outputs without matching requirements"),
        error.DuplicateSymbol => @compileError("public lowering rejected duplicate function symbols"),
        error.UnknownSymbol => @compileError("public lowering rejected an unknown function symbol"),
        error.UnsupportedHelperCallEdge => @compileError("public lowering runtime plan rejected helper call edges outside the retained open-row shell"),
        error.UnsupportedCodecType => @compileError("public lowering runtime plan rejected a type outside the first-wave codec set"),
        error.OutOfMemory => @compileError("public lowering ran out of memory at comptime"),
    };
    assertExecutableCodecSupport(compiled_plan);
    return GeneratedProgramType(
        label,
        "<ir>",
        entry_function.symbol.symbol_name,
        compiled_plan,
        entry_function.parameter_codecs.len == 0,
        null,
    );
}

/// Compile one explicit public effect-ir program into the same runtime-owned plan shape.
pub const CompileIr = CompileIrType;

test "same-module lowerAt preserves caller-provided source ownership" {
    const ProgramType = lowerAt("examples/open_row_state_writer.zig", .{
        .label = "public_lowering.self",
        .entry_symbol = "runBody",
        .row = effect_ir.mergeRows(.{
            effect_ir.rowFromSpec(.{
                .state = .{
                    .get = effect_ir.Transform(void, i32),
                    .set = effect_ir.Transform(i32, void),
                },
            }),
            effect_ir.rowFromSpec(.{
                .writer = .{
                    .tell = effect_ir.Transform([]const u8, void),
                },
            }),
        }),
        .ValueType = []const u8,
        .outputs = &.{
            .{ .label = "state", .OutputType = i32 },
            .{ .label = "writer", .OutputType = [][]const u8 },
        },
    });

    try std.testing.expectEqualStrings("examples/open_row_state_writer.zig", ProgramType.source_path);
    try std.testing.expectEqualStrings("runBody", ProgramType.entry_symbol);
    try std.testing.expectEqual(@as(usize, 3), ProgramType.runtime_plan.functions.len);
    try std.testing.expectEqual(program_plan.ValueCodec.string, ProgramType.runtime_plan.functions[ProgramType.runtime_plan.entry_index].value_codec);
    try std.testing.expectEqual(@as(usize, 2), ProgramType.runtime_plan.outputs.len);
}

test "absolute caller-owned helper regression: lowering accepts normalized sibling-tree imports" {
    try writeAbsoluteTestFile(
        "/tmp/shift-owned-open-row/nested/entry.zig",
        \\const other = @import("../helpers/../other/util.zig");
        \\
        \\pub fn runBody(eff: anytype) !void {
        \\    try other.emit(eff);
        \\}
        ,
    );
    try writeAbsoluteTestFile(
        "/tmp/shift-owned-open-row/other/util.zig",
        \\pub fn emit(eff: anytype) !void {
        \\    try eff.writer.tell("normalized");
        \\}
        ,
    );

    const current_src = @src();
    const caller: std.builtin.SourceLocation = .{
        .module = current_src.module,
        .file = "/tmp/shift-owned-open-row/nested/entry.zig",
        .line = 1,
        .column = 1,
        .fn_name = "normalizedSiblingLoweringCaller",
    };
    const ProgramType = lower(sourceWithContentAndImports(
        "/tmp/shift-owned-open-row/nested/entry.zig",
        caller,
        \\const other = @import("../helpers/../other/util.zig");
        \\
        \\pub fn runBody(eff: anytype) !void {
        \\    try other.emit(eff);
        \\}
    ,
        &.{importedSource(
            "/tmp/shift-owned-open-row/nested/entry.zig",
            "../helpers/../other/util.zig",
            \\pub fn emit(eff: anytype) !void {
            \\    try eff.writer.tell("normalized");
            \\}
            ,
        )},
    ), .{
        .label = "public_lowering.normalized_sibling_helper",
        .entry_symbol = "runBody",
        .row = effect_ir.rowFromSpec(.{
            .writer = .{
                .tell = effect_ir.Transform([]const u8, void),
            },
        }),
    });

    try std.testing.expectEqual(@as(usize, 2), ProgramType.runtime_plan.functions.len);
    try ProgramType.validate(std.testing.allocator);
}

test "absolute caller-owned helper regression: lowering accepts shared helper subtrees" {
    try writeAbsoluteTestFile(
        "/tmp/shift-owned-open-row/nested/entry.zig",
        \\const direct = @import("helpers/sub/b.zig");
        \\const helpers = @import("helpers/a.zig");
        \\
        \\pub fn runBody(eff: anytype) !void {
        \\    try direct.emit(eff);
        \\    try helpers.emit(eff);
        \\}
        ,
    );
    try writeAbsoluteTestFile(
        "/tmp/shift-owned-open-row/nested/helpers/a.zig",
        \\const shared = @import("sub/b.zig");
        \\
        \\pub fn emit(eff: anytype) !void {
        \\    try shared.emit(eff);
        \\}
        ,
    );
    try writeAbsoluteTestFile(
        "/tmp/shift-owned-open-row/nested/helpers/sub/b.zig",
        \\pub fn emit(eff: anytype) !void {
        \\    try eff.writer.tell("shared");
        \\}
        ,
    );

    const current_src = @src();
    const caller: std.builtin.SourceLocation = .{
        .module = current_src.module,
        .file = "/tmp/shift-owned-open-row/nested/entry.zig",
        .line = 1,
        .column = 1,
        .fn_name = "sharedHelperSubtreeLoweringCaller",
    };
    const ProgramType = lower(sourceWithContentAndImports(
        "/tmp/shift-owned-open-row/nested/entry.zig",
        caller,
        \\const direct = @import("helpers/sub/b.zig");
        \\const helpers = @import("helpers/a.zig");
        \\
        \\pub fn runBody(eff: anytype) !void {
        \\    try direct.emit(eff);
        \\    try helpers.emit(eff);
        \\}
    ,
        &.{
            importedSource(
                "/tmp/shift-owned-open-row/nested/entry.zig",
                "helpers/a.zig",
                \\const shared = @import("sub/b.zig");
                \\
                \\pub fn emit(eff: anytype) !void {
                \\    try shared.emit(eff);
                \\}
                ,
            ),
            importedSource(
                "/tmp/shift-owned-open-row/nested/entry.zig",
                "helpers/sub/b.zig",
                \\pub fn emit(eff: anytype) !void {
                \\    try eff.writer.tell("shared");
                \\}
                ,
            ),
        },
    ), .{
        .label = "public_lowering.shared_helper_subtree",
        .entry_symbol = "runBody",
        .row = effect_ir.rowFromSpec(.{
            .writer = .{
                .tell = effect_ir.Transform([]const u8, void),
            },
        }),
    });

    try std.testing.expectEqual(@as(usize, 3), ProgramType.runtime_plan.functions.len);
    try ProgramType.validate(std.testing.allocator);
}

test "source ownership rejects relative no-content repo-path witnesses and basename-only mismatches" {
    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = "examples/open_row_state_writer.zig",
    }));
    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = "/tmp/open_row_state_writer.zig",
    }));
}

test "source ownership accepts canonical absolute paths and requires content witnesses for package-root aliases" {
    const canonical_owned = comptime std.fmt.comptimePrint(
        "{s}/examples/open_row_state_writer.zig",
        .{build_options.package_root},
    );
    const alias_owned = comptime std.fmt.comptimePrint(
        "{s}/examples/open_row_state_writer.zig",
        .{build_options.package_root_alias},
    );

    try std.testing.expect(sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = canonical_owned,
    }));
    if (build_options.package_root_alias_available) {
        try std.testing.expect(!sourceOwnershipMatches(.{
            .repo_path = "examples/open_row_state_writer.zig",
            .caller_file = alias_owned,
        }));
        try std.testing.expect(!sourceOwnershipMatches(.{
            .repo_path = "examples/open_row_state_writer.zig",
            .caller_file = alias_owned,
            .caller_hash = hashSourceBytes(source_graph_embed.embeddedSource("examples/open_row_state_writer.zig")),
        }));
        try std.testing.expect(sourceOwnershipMatches(.{
            .repo_path = "examples/open_row_state_writer.zig",
            .caller_file = alias_owned,
            .caller_hash = hashSourceBytes(source_graph_embed.embeddedSource("examples/open_row_state_writer.zig")),
            .caller_source = source_graph_embed.embeddedSource("examples/open_row_state_writer.zig"),
        }));
    }
    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = "/tmp/foreign/examples/open_row_state_writer.zig",
    }));
}

test "source ownership rejects forged caller_source for owned absolute repo paths" {
    const forged_source =
        \\pub fn runBody() void {}
    ;
    const canonical_owned = comptime std.fmt.comptimePrint(
        "{s}/examples/open_row_state_writer.zig",
        .{build_options.package_root},
    );

    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = canonical_owned,
        .caller_hash = hashSourceBytes(forged_source),
        .caller_source = forged_source,
    }));
    if (build_options.package_root_alias_available) {
        const alias_owned = comptime std.fmt.comptimePrint(
            "{s}/examples/open_row_state_writer.zig",
            .{build_options.package_root_alias},
        );
        try std.testing.expect(!sourceOwnershipMatches(.{
            .repo_path = "examples/open_row_state_writer.zig",
            .caller_file = alias_owned,
            .caller_hash = hashSourceBytes(forged_source),
            .caller_source = forged_source,
        }));
    }
}

test "source ownership rejects absolute paths whose root only shares a prefix with the checkout root" {
    const prefixed_checkout_root = comptime std.fmt.comptimePrint(
        "{s}x/examples/open_row_state_writer.zig",
        .{build_options.package_root},
    );
    const prefixed_alias_root = comptime std.fmt.comptimePrint(
        "{s}x/examples/open_row_state_writer.zig",
        .{build_options.package_root_alias},
    );

    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = prefixed_checkout_root,
    }));
    if (build_options.package_root_alias_available) {
        try std.testing.expect(!sourceOwnershipMatches(.{
            .repo_path = "examples/open_row_state_writer.zig",
            .caller_file = prefixed_alias_root,
        }));
    }
}

test "windows ownership portability accepts separator-normalized owned repo paths" {
    try std.testing.expect(comptime repoPathIsOwned("examples\\open_row_state_writer.zig"));
}

test "windows ownership portability accepts separator-normalized owned repo paths at runtime" {
    try std.testing.expect(runtimeRegistryContainsLine(
        build_options.repo_zig_paths,
        "examples\\open_row_state_writer.zig",
    ));
}

test "windows ownership portability matches Windows checkout roots case-insensitively" {
    try std.testing.expect(pathEquals(
        "C:\\Repo\\Examples\\Open_Row_State_Writer.zig",
        "c:/repo/examples/open_row_state_writer.zig",
    ));
    try std.testing.expect(pathEqualsRuntime(
        "C:\\Repo\\Examples\\Open_Row_State_Writer.zig",
        "c:/repo/examples/open_row_state_writer.zig",
    ));
    try std.testing.expect(pathStartsWithRoot(
        "C:\\Repo\\Examples\\Open_Row_State_Writer.zig",
        "c:/repo",
    ));
    try std.testing.expect(pathStartsWithRootRuntime(
        "C:\\Repo\\Examples\\Open_Row_State_Writer.zig",
        "c:/repo",
    ));
    try std.testing.expect(!pathStartsWithRoot(
        "C:\\Repox\\Examples\\Open_Row_State_Writer.zig",
        "c:/repo",
    ));
}

test "runtime root relative slice normalizes Windows checkout roots" {
    try std.testing.expectEqualStrings(
        "Examples\\Open_Row_State_Writer.zig",
        runtimeRootRelativeSlice(
            "C:\\Repo\\Examples\\Open_Row_State_Writer.zig",
            "c:/repo",
        ).?,
    );
    try std.testing.expect(runtimeRootRelativeSlice(
        "C:\\Repox\\Examples\\Open_Row_State_Writer.zig",
        "c:/repo",
    ) == null);
}

test "source ownership accepts helper-authored content witnesses when caller bytes match their explicit witness" {
    try std.testing.expect(sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = "examples/open_row_state_writer.zig",
        .caller_hash = hashSourceBytes(source_graph_embed.embeddedSource("examples/open_row_state_writer.zig")),
        .caller_source = source_graph_embed.embeddedSource("examples/open_row_state_writer.zig"),
    }));
    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = "examples/open_row_state_writer.zig",
        .caller_hash = hashSourceBytes("different bytes"),
        .caller_source = "not the repo source",
    }));
}

test "source ownership rejects relative content witnesses for non-repo paths" {
    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = "examples/not_in_repo.zig",
        .caller_file = "examples/not_in_repo.zig",
        .caller_hash = hashSourceBytes(
            \\pub fn runBody() void {}
        ),
        .caller_source =
        \\pub fn runBody() void {}
        ,
    }));
}

test "source ownership rejects basename-only content witnesses even when their bytes match" {
    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = "open_row_state_writer.zig",
        .caller_hash = hashSourceBytes(source_graph_embed.embeddedSource("examples/open_row_state_writer.zig")),
        .caller_source = source_graph_embed.embeddedSource("examples/open_row_state_writer.zig"),
    }));
}

test "source ownership rejects basename-only content witnesses for non-owned roots" {
    const downstream_source =
        \\pub fn runBody() void {}
    ;

    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = "downstream_public_lowering_test.zig",
        .caller_file = "downstream_public_lowering_test.zig",
        .caller_hash = hashSourceBytes(downstream_source),
        .caller_source = downstream_source,
    }));
}

test "source ownership accepts repo-owned relative content witnesses only when bytes mirror the repo source" {
    const repo_source = comptime source_graph_embed.embeddedSource("examples/open_row_state_writer.zig");

    try std.testing.expect(sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = "examples/open_row_state_writer.zig",
        .caller_hash = hashSourceBytes(repo_source),
        .caller_source = repo_source,
    }));
    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = "examples/open_row_state_writer.zig",
        .caller_hash = hashSourceBytes(
            \\pub fn runBody() void {}
        ),
        .caller_source =
        \\pub fn runBody() void {}
        ,
    }));
}

test "validation owned source content reports SourceDrifted for repo-owned witness drift" {
    try std.testing.expectError(
        error.SourceDrifted,
        validationOwnedSourceContent(
            std.testing.allocator,
            "examples/open_row_state_writer.zig",
            \\pub fn runBody() void {}
        ),
    );
}

test "importedSource preserves parent-directory helpers for absolute caller-owned roots" {
    const imported = comptime importedSource("/tmp/shift-owned-open-row/nested/entry.zig", "../helpers/util.zig",
        \\pub fn emit(eff: anytype) !void {
        \\    _ = eff;
        \\}
    );

    try std.testing.expectEqualStrings("/tmp/shift-owned-open-row/helpers/util.zig", imported.path);
}

test "source helper preserves basename-only callers so ownership still fails closed" {
    const current_src = @src();
    const unique_caller: std.builtin.SourceLocation = .{
        .module = current_src.module,
        .file = "open_row_state_writer.zig",
        .line = 1,
        .column = 1,
        .fn_name = "uniqueCaller",
    };
    const ambiguous_caller: std.builtin.SourceLocation = .{
        .module = current_src.module,
        .file = "entry.zig",
        .line = 1,
        .column = 1,
        .fn_name = "ambiguousCaller",
    };

    const unique_source = comptime source("examples/open_row_state_writer.zig", unique_caller);
    try std.testing.expectEqualStrings("open_row_state_writer.zig", unique_source.caller_file);
    try std.testing.expect(!comptime sourceOwnershipMatches(unique_source));

    const ambiguous_source = comptime source("test/open_row_entry_symbol_alias/entry.zig", ambiguous_caller);
    try std.testing.expectEqualStrings("entry.zig", ambiguous_source.caller_file);
    try std.testing.expect(!comptime sourceOwnershipMatches(ambiguous_source));
}

test "sourceWithContent preserves basename-only callers instead of rewriting them to repo paths" {
    const current_src = @src();
    const unique_caller: std.builtin.SourceLocation = .{
        .module = current_src.module,
        .file = "open_row_state_writer.zig",
        .line = 1,
        .column = 1,
        .fn_name = "uniqueContentCaller",
    };
    const ambiguous_caller: std.builtin.SourceLocation = .{
        .module = current_src.module,
        .file = "entry.zig",
        .line = 1,
        .column = 1,
        .fn_name = "ambiguousContentCaller",
    };
    const unique_source = comptime sourceWithContent(
        "examples/open_row_state_writer.zig",
        unique_caller,
        source_graph_embed.embeddedSource("examples/open_row_state_writer.zig"),
    );
    const ambiguous_source = comptime sourceWithContent(
        "test/open_row_entry_symbol_alias/entry.zig",
        ambiguous_caller,
        source_graph_embed.embeddedSource("test/open_row_entry_symbol_alias/entry.zig"),
    );

    try std.testing.expectEqualStrings("open_row_state_writer.zig", unique_source.caller_file);
    try std.testing.expect(!comptime sourceOwnershipMatches(unique_source));
    try std.testing.expectEqualStrings("entry.zig", ambiguous_source.caller_file);
    try std.testing.expect(!comptime sourceOwnershipMatches(ambiguous_source));
}

test "source ownership rejects hash-only witnesses for non-repo paths" {
    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = "examples/not_in_repo.zig",
        .caller_file = "examples/not_in_repo.zig",
        .caller_hash = hashSourceBytes(
            \\pub fn runBody() void {}
        ),
    }));
}

test "source ownership rejects hash-only witnesses for repo-owned relative paths" {
    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = "examples/open_row_state_writer.zig",
        .caller_hash = hashSourceBytes(source_graph_embed.embeddedSource("examples/open_row_state_writer.zig")),
    }));
}

test "source ownership rejects matching-byte witnesses from a different caller path" {
    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = "/tmp/other_module.zig",
        .caller_hash = hashSourceBytes(source_graph_embed.embeddedSource("examples/open_row_state_writer.zig")),
    }));
    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = "other_module.zig",
        .caller_hash = hashSourceBytes(source_graph_embed.embeddedSource("examples/open_row_state_writer.zig")),
    }));
}

test "source ownership rejects mirrored relative paths outside the repo root" {
    const mirrored_relative = "vendor/mirror/examples/open_row_state_writer.zig";

    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = mirrored_relative,
    }));
    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = mirrored_relative,
        .caller_hash = hashSourceBytes(source_graph_embed.embeddedSource("examples/open_row_state_writer.zig")),
        .caller_source = source_graph_embed.embeddedSource("examples/open_row_state_writer.zig"),
    }));
}

test "source ownership accepts absolute caller-owned content witnesses inside owned roots" {
    const caller_path = comptime std.fmt.comptimePrint(
        "{s}/examples/open_row_state_writer.zig",
        .{build_options.package_root},
    );
    const caller_source = comptime source_graph_embed.embeddedSource("examples/open_row_state_writer.zig");

    try std.testing.expect(sourceOwnershipMatches(.{
        .repo_path = caller_path,
        .caller_file = caller_path,
        .caller_hash = hashSourceBytes(caller_source),
        .caller_source = caller_source,
    }));
    if (build_options.package_root_alias_available) {
        const alias_caller_path = comptime std.fmt.comptimePrint(
            "{s}/examples/open_row_state_writer.zig",
            .{build_options.package_root_alias},
        );
        try std.testing.expect(sourceOwnershipMatches(.{
            .repo_path = alias_caller_path,
            .caller_file = alias_caller_path,
            .caller_hash = hashSourceBytes(caller_source),
            .caller_source = caller_source,
        }));
    }
}

test "source ownership rejects forged absolute caller-owned content witnesses inside owned roots" {
    const caller_path = comptime std.fmt.comptimePrint(
        "{s}/examples/open_row_state_writer.zig",
        .{build_options.package_root},
    );
    const forged_source =
        \\pub fn runBody() void {}
    ;

    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = caller_path,
        .caller_file = caller_path,
        .caller_hash = hashSourceBytes(forged_source),
        .caller_source = forged_source,
    }));
    if (build_options.package_root_alias_available) {
        const alias_caller_path = comptime std.fmt.comptimePrint(
            "{s}/examples/open_row_state_writer.zig",
            .{build_options.package_root_alias},
        );
        try std.testing.expect(!sourceOwnershipMatches(.{
            .repo_path = alias_caller_path,
            .caller_file = alias_caller_path,
            .caller_hash = hashSourceBytes(forged_source),
            .caller_source = forged_source,
        }));
    }
}

test "source ownership accepts absolute caller-owned content witnesses outside owned roots when the caller proves both path and bytes" {
    const caller_path = "/tmp/downstream_public_lowering_test.zig";
    const caller_source =
        \\pub fn runBody() void {}
    ;

    try std.testing.expect(sourceOwnershipMatches(.{
        .repo_path = caller_path,
        .caller_file = caller_path,
        .caller_hash = hashSourceBytes(caller_source),
        .caller_source = caller_source,
    }));
    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = "/tmp/other_downstream_public_lowering_test.zig",
        .caller_file = caller_path,
        .caller_hash = hashSourceBytes(caller_source),
        .caller_source = caller_source,
    }));
}

test "owned validation resolves parent-directory helpers for absolute caller-owned roots" {
    const resolved = try resolveOwnedValidationImportPathAlloc(
        std.testing.allocator,
        "/tmp/shift-owned-open-row/nested/entry.zig",
        "../helpers/util.zig",
        null,
    );
    defer std.testing.allocator.free(resolved.path);
    defer if (resolved.absolute_entry_tree_root) |tree_root| std.testing.allocator.free(tree_root);

    try std.testing.expectEqualStrings("/tmp/shift-owned-open-row/helpers/util.zig", resolved.path);
}

test "absolute caller-owned helper regression: validation accepts normalized sibling-tree imports" {
    const resolved = try resolveOwnedValidationImportPathAlloc(
        std.testing.allocator,
        "/tmp/shift-owned-open-row/nested/entry.zig",
        "../helpers/../other/util.zig",
        null,
    );
    defer std.testing.allocator.free(resolved.path);
    defer if (resolved.absolute_entry_tree_root) |tree_root| std.testing.allocator.free(tree_root);

    try std.testing.expectEqualStrings("/tmp/shift-owned-open-row/other/util.zig", resolved.path);
}

test "owned validation rejects helper imports that climb above the admitted absolute entry tree" {
    try std.testing.expectError(
        error.UnsupportedHelperGraph,
        resolveOwnedValidationImportPathAlloc(
            std.testing.allocator,
            "/tmp/shift-owned-open-row/nested/deeper/entry.zig",
            "../../outside_helper.zig",
            null,
        ),
    );
    try std.testing.expectError(
        error.UnsupportedHelperGraph,
        resolveOwnedValidationImportPathAlloc(
            std.testing.allocator,
            "/tmp/shift-owned-open-row/nested/entry.zig",
            "helpers/../../outside_helper.zig",
            null,
        ),
    );
}

test "owned validation rejects Windows absolute helper imports" {
    try std.testing.expectError(
        error.UnsupportedHelperGraph,
        resolveOwnedValidationImportPathAlloc(
            std.testing.allocator,
            "/tmp/shift-owned-open-row/nested/entry.zig",
            "C:/tmp/helper.zig",
            null,
        ),
    );
    try std.testing.expectError(
        error.UnsupportedHelperGraph,
        resolveOwnedValidationImportPathAlloc(
            std.testing.allocator,
            "/tmp/shift-owned-open-row/nested/entry.zig",
            "\\\\server\\share\\helper.zig",
            null,
        ),
    );
}

test "file-backed validation rejects Windows absolute helper imports" {
    try std.testing.expectError(
        error.UnsupportedHelperGraph,
        resolveValidationImportPathAlloc(
            std.testing.allocator,
            "examples/open_row_state_writer.zig",
            "C:/tmp/helper.zig",
        ),
    );
    try std.testing.expectError(
        error.UnsupportedHelperGraph,
        resolveValidationImportPathAlloc(
            std.testing.allocator,
            "examples/open_row_state_writer.zig",
            "\\\\server\\share\\helper.zig",
        ),
    );
}

test "after hook naming preserves underscore boundaries" {
    comptime {
        const foo_bar = afterMethodName("foo_bar");
        const foo__bar = afterMethodName("foo__bar");
        const _foo_bar = afterMethodName("_foo_bar");

        if (!std.mem.eql(u8, foo_bar, "afterFoo_Bar")) {
            @compileError("after hook naming must preserve single underscore boundaries");
        }
        if (!std.mem.eql(u8, foo__bar, "afterFoo__Bar")) {
            @compileError("after hook naming must preserve repeated underscore boundaries");
        }
        if (!std.mem.eql(u8, _foo_bar, "after_Foo_Bar")) {
            @compileError("after hook naming must preserve leading underscore boundaries");
        }
        if (std.mem.eql(u8, foo_bar, foo__bar) or
            std.mem.eql(u8, foo_bar, _foo_bar) or
            std.mem.eql(u8, foo__bar, _foo_bar))
        {
            @compileError("after hook naming must keep underscored op names distinct");
        }
    }
}

test "after hook naming supports long operation names" {
    comptime {
        var long_name_buffer: [124]u8 = undefined;
        long_name_buffer[0] = 'a';
        for (1..long_name_buffer.len) |index| long_name_buffer[index] = 'x';
        const long_name = long_name_buffer[0..];

        var expected_buffer: [129]u8 = undefined;
        expected_buffer[0..6].* = "afterA".*;
        for (6..expected_buffer.len) |index| expected_buffer[index] = 'x';
        const expected = expected_buffer[0..];

        const after_name = afterMethodName(long_name);
        if (!std.mem.eql(u8, after_name, expected)) {
            @compileError("after hook naming must support long operation names without truncation");
        }
    }
}

test "owned-source validation rejects helper imports that are missing from caller-supplied sources" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const root_source =
        \\const helper = @import("helper.zig");
        \\
        \\pub fn runBody(eff: anytype) ![]const u8 {
        \\    try helper.emit(eff);
        \\    return "done";
        \\}
    ;

    try tmp.dir.writeFile(.{
        .sub_path = "entry.zig",
        .data = root_source,
    });
    try tmp.dir.writeFile(.{
        .sub_path = "helper.zig",
        .data =
        \\pub fn emit(eff: anytype) !void {
        \\    try eff.writer.tell("queued");
        \\}
        ,
    });

    const entry_path = try tmp.dir.realpathAlloc(std.testing.allocator, "entry.zig");
    defer std.testing.allocator.free(entry_path);

    try std.testing.expectError(
        error.UnsupportedHelperGraph,
        validateOwnedOpenRowAt(std.testing.allocator, entry_path, root_source, &.{}, "runBody"),
    );
}

test "owned-source validation rejects absolute helper imports that climb outside the entry tree" {
    const external_root = try std.fmt.allocPrint(
        std.testing.allocator,
        "/tmp/shift-owned-open-row-absolute-helper-import-{d}",
        .{std.time.nanoTimestamp()},
    );
    defer std.testing.allocator.free(external_root);
    std.fs.deleteTreeAbsolute(external_root) catch {};
    try std.fs.makeDirAbsolute(external_root);
    defer std.fs.deleteTreeAbsolute(external_root) catch unreachable;

    var external_dir = try std.fs.openDirAbsolute(external_root, .{});
    defer external_dir.close();
    try external_dir.makePath("nested/deeper");
    try external_dir.writeFile(.{
        .sub_path = "outside_helper.zig",
        .data =
        \\pub fn helper(eff: anytype) !void {
        \\    try eff.writer.tell("escaped");
        \\}
        ,
    });
    try external_dir.writeFile(.{
        .sub_path = "nested/deeper/entry.zig",
        .data =
        \\const helpers = @import("../../outside_helper.zig");
        \\
        \\pub fn runBody(eff: anytype) !void {
        \\    try helpers.helper(eff);
        \\}
        ,
    });

    const entry_path = try std.fs.path.join(
        std.testing.allocator,
        &.{ external_root, "nested", "deeper", "entry.zig" },
    );
    defer std.testing.allocator.free(entry_path);
    const helper_path = try std.fs.path.join(
        std.testing.allocator,
        &.{ external_root, "outside_helper.zig" },
    );
    defer std.testing.allocator.free(helper_path);

    const root_file = try std.fs.openFileAbsolute(entry_path, .{});
    defer root_file.close();
    const root_source = try root_file.readToEndAllocOptions(
        std.testing.allocator,
        std.math.maxInt(usize),
        null,
        .of(u8),
        0,
    );
    defer std.testing.allocator.free(root_source);
    const helper_file = try std.fs.openFileAbsolute(helper_path, .{});
    defer helper_file.close();
    const helper_source = try helper_file.readToEndAllocOptions(
        std.testing.allocator,
        std.math.maxInt(usize),
        null,
        .of(u8),
        0,
    );
    defer std.testing.allocator.free(helper_source);

    try std.testing.expectError(
        error.UnsupportedHelperGraph,
        validateOwnedOpenRowAt(std.testing.allocator, entry_path, root_source, &.{.{
            .path = helper_path,
            .content = helper_source,
        }}, "runBody"),
    );
}

test "owned-source validation rejects transitive helper imports that leave the first admitted absolute helper tree" {
    const entry_path = "/tmp/shift-owned-open-row/nested/entry.zig";
    const helper_path = "/tmp/shift-owned-open-row/helpers/a.zig";
    const escaped_helper_path = "/tmp/shift-owned-open-row/other/b.zig";

    try writeAbsoluteTestFile(
        entry_path,
        \\const helpers = @import("../helpers/a.zig");
        \\
        \\pub fn runBody(eff: anytype) !void {
        \\    try helpers.emit(eff);
        \\}
        ,
    );
    try writeAbsoluteTestFile(
        helper_path,
        \\const other = @import("../other/b.zig");
        \\
        \\pub fn emit(eff: anytype) !void {
        \\    try other.emit(eff);
        \\}
        ,
    );
    try writeAbsoluteTestFile(
        escaped_helper_path,
        \\pub fn emit(eff: anytype) !void {
        \\    try eff.writer.tell("escaped");
        \\}
        ,
    );

    try std.testing.expectError(
        error.UnsupportedHelperGraph,
        validateOwnedOpenRowAt(
            std.testing.allocator,
            entry_path,
            \\const helpers = @import("../helpers/a.zig");
            \\
            \\pub fn runBody(eff: anytype) !void {
            \\    try helpers.emit(eff);
            \\}
        ,
            &.{
                .{
                    .path = helper_path,
                    .content =
                    \\const other = @import("../other/b.zig");
                    \\
                    \\pub fn emit(eff: anytype) !void {
                    \\    try other.emit(eff);
                    \\}
                    ,
                },
                .{
                    .path = escaped_helper_path,
                    .content =
                    \\pub fn emit(eff: anytype) !void {
                    \\    try eff.writer.tell("escaped");
                    \\}
                    ,
                },
            },
            "runBody",
        ),
    );
}

test "owned validation rejects repo-resolving absolute helper overrides for external roots" {
    const repo_parent = comptime std.fs.path.dirname(build_options.package_root) orelse
        @compileError("package_root must have a parent directory");
    const root_path = comptime std.fmt.comptimePrint("{s}/shift-external-entry/entry.zig", .{repo_parent});
    const helper_path = comptime std.fmt.comptimePrint(
        "{s}/examples/open_row_cross_file_helpers.zig",
        .{build_options.package_root},
    );

    try writeAbsoluteTestFile(
        root_path,
        \\const helpers = @import("../shift/examples/open_row_cross_file_helpers.zig");
        \\
        \\pub fn runBody(eff: anytype) !void {
        \\    try helpers.advanceState(eff);
        \\}
        ,
    );

    try std.testing.expectError(
        error.SourceDrifted,
        validateOwnedOpenRowAt(
            std.testing.allocator,
            root_path,
            \\const helpers = @import("../shift/examples/open_row_cross_file_helpers.zig");
            \\
            \\pub fn runBody(eff: anytype) !void {
            \\    try helpers.advanceState(eff);
            \\}
        ,
            &.{.{
                .path = helper_path,
                .content =
                \\pub fn advanceState(eff: anytype) !void {
                \\    _ = eff;
                \\}
                ,
            }},
            "runBody",
        ),
    );
}

test "absolute caller-owned helper regression: validation accepts shared helper subtrees" {
    try writeAbsoluteTestFile(
        "/tmp/shift-owned-open-row/nested/entry.zig",
        \\const direct = @import("helpers/sub/b.zig");
        \\const helpers = @import("helpers/a.zig");
        \\
        \\pub fn runBody(eff: anytype) !void {
        \\    try direct.emit(eff);
        \\    try helpers.emit(eff);
        \\}
        ,
    );
    try writeAbsoluteTestFile(
        "/tmp/shift-owned-open-row/nested/helpers/a.zig",
        \\const shared = @import("sub/b.zig");
        \\
        \\pub fn emit(eff: anytype) !void {
        \\    try shared.emit(eff);
        \\}
        ,
    );
    try writeAbsoluteTestFile(
        "/tmp/shift-owned-open-row/nested/helpers/sub/b.zig",
        \\pub fn emit(eff: anytype) !void {
        \\    try eff.writer.tell("shared");
        \\}
        ,
    );

    try validateOwnedOpenRowAt(
        std.testing.allocator,
        "/tmp/shift-owned-open-row/nested/entry.zig",
        \\const direct = @import("helpers/sub/b.zig");
        \\const helpers = @import("helpers/a.zig");
        \\
        \\pub fn runBody(eff: anytype) !void {
        \\    try direct.emit(eff);
        \\    try helpers.emit(eff);
        \\}
    ,
        &.{
            .{
                .path = "/tmp/shift-owned-open-row/nested/helpers/a.zig",
                .content =
                \\const shared = @import("sub/b.zig");
                \\
                \\pub fn emit(eff: anytype) !void {
                \\    try shared.emit(eff);
                \\}
                ,
            },
            .{
                .path = "/tmp/shift-owned-open-row/nested/helpers/sub/b.zig",
                .content =
                \\pub fn emit(eff: anytype) !void {
                \\    try eff.writer.tell("shared");
                \\}
                ,
            },
        },
        "runBody",
    );
}

test "file-backed validation detects drift in nested imported pure helper chains" {
    const root_source =
        \\const helpers = @import("helpers/a.zig");
        \\
        \\pub fn runBody(eff: anytype) ![]const u8 {
        \\    const count = try eff.state.get();
        \\    const label = try helpers.classify("nested-selected", count);
        \\    try eff.writer.tell(label);
        \\    return "done";
        \\}
    ;
    const helper_source =
        \\const nested = @import("sub/b.zig");
        \\
        \\pub fn classify(label: []const u8, count: i32) ![]const u8 {
        \\    return try nested.classify(label, count);
        \\}
    ;
    const nested_source =
        \\pub fn classify(label: []const u8, _: i32) ![]const u8 {
        \\    return label;
        \\}
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("helpers/sub");
    try tmp.dir.writeFile(.{
        .sub_path = "entry.zig",
        .data = root_source,
    });
    try tmp.dir.writeFile(.{
        .sub_path = "helpers/a.zig",
        .data = helper_source,
    });
    try tmp.dir.writeFile(.{
        .sub_path = "helpers/sub/b.zig",
        .data = nested_source,
    });

    const root_path = try tmp.dir.realpathAlloc(std.testing.allocator, "entry.zig");
    defer std.testing.allocator.free(root_path);
    const helper_path = try tmp.dir.realpathAlloc(std.testing.allocator, "helpers/a.zig");
    defer std.testing.allocator.free(helper_path);
    const nested_path = try tmp.dir.realpathAlloc(std.testing.allocator, "helpers/sub/b.zig");
    defer std.testing.allocator.free(nested_path);
    const imported_sources = [_]ImportedSource{
        .{ .path = helper_path, .content = helper_source },
        .{ .path = nested_path, .content = nested_source },
    };

    try validateFileBackedOpenRowAt(std.testing.allocator, root_path, "runBody");
    try validateFileBackedOpenRowAgainstSnapshot(
        std.testing.allocator,
        root_path,
        root_source,
        &imported_sources,
        "runBody",
    );

    try tmp.dir.writeFile(.{
        .sub_path = "helpers/sub/b.zig",
        .data =
        \\pub fn renamed(label: []const u8, _: i32) ![]const u8 {
        \\    _ = label;
        \\    return "drifted";
        \\}
        ,
    });

    try std.testing.expectError(
        error.UnsupportedHelperGraph,
        validateFileBackedOpenRowAt(std.testing.allocator, root_path, "runBody"),
    );
    try std.testing.expectError(
        error.SourceDrifted,
        validateFileBackedOpenRowAgainstSnapshot(
            std.testing.allocator,
            root_path,
            root_source,
            &imported_sources,
            "runBody",
        ),
    );
}

test "executeLoweredDispatch runs choice ops across resume and return-now branches" {
    const plan: program_plan.ProgramPlan = .{
        .label = "example.choice_root",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "choiceRoot",
            .value_codec = .string,
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
        }},
        .requirements = &.{.{
            .label = "picker",
            .first_op = 0,
            .op_count = 1,
        }},
        .ops = &.{.{
            .requirement_index = 0,
            .op_name = "pick",
            .mode = .choice,
            .payload_codec = .unit,
            .resume_codec = .string,
        }},
        .outputs = &.{},
        .locals = &.{.{ .codec = .string }},
        .blocks = &.{.{
            .first_instruction = 0,
            .instruction_count = 2,
            .terminator_index = 0,
        }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{
                .kind = .call_op,
                .dst = 0,
                .operand = 0,
            },
            .{
                .kind = .return_value,
                .operand = 0,
            },
        },
    };
    const PickerHandler = struct {
        branch: enum { resume_with, return_now },
        after_calls: usize = 0,

        pub fn pick(self: *@This()) anyerror!@import("root.zig").Decision([]const u8, []const u8) {
            return switch (self.branch) {
                .resume_with => @import("root.zig").Decision([]const u8, []const u8).resumeWith("answer=42"),
                .return_now => @import("root.zig").Decision([]const u8, []const u8).returnNow("result=early"),
            };
        }

        pub fn afterPick(self: *@This(), answer: []const u8) anyerror![]const u8 {
            self.after_calls += 1;
            try std.testing.expectEqualStrings("answer=42", answer);
            return "after=42";
        }
    };
    const Handlers = struct {
        picker: PickerHandler,
    };

    var resumed_handlers: Handlers = .{
        .picker = .{ .branch = .resume_with },
    };
    const resumed = try executeLoweredDispatch(plan, &resumed_handlers, 0, &.{});
    switch (resumed) {
        .value => |answer| try std.testing.expectEqualStrings("after=42", decodeRuntimeValue(.string, answer)),
        .terminal => |_| return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 1), resumed_handlers.picker.after_calls);

    var early_handlers: Handlers = .{
        .picker = .{ .branch = .return_now },
    };
    const early = try executeLoweredDispatch(plan, &early_handlers, 0, &.{});
    switch (early) {
        .terminal => |answer| try std.testing.expectEqualStrings("result=early", decodeRuntimeValue(.string, answer)),
        .value => |_| return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 0), early_handlers.picker.after_calls);
}

test "executeLoweredDispatch applies after handlers for repeated loop resumes" {
    const plan: program_plan.ProgramPlan = .{
        .label = "example.loop_after_root",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "loopAfterRoot",
            .value_codec = .i32,
            .parameter_count = 1,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 3,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 2,
            .first_instruction = 0,
            .instruction_count = 4,
        }},
        .requirements = &.{.{
            .label = "counter",
            .first_op = 0,
            .op_count = 1,
        }},
        .ops = &.{.{
            .requirement_index = 0,
            .op_name = "step",
            .mode = .transform,
            .payload_codec = .i32,
            .resume_codec = .i32,
        }},
        .outputs = &.{},
        .locals = &.{
            .{ .codec = .i32 },
            .{ .codec = .bool },
            .{ .codec = .i32 },
        },
        .blocks = &.{
            .{
                .first_instruction = 0,
                .instruction_count = 2,
                .terminator_index = 0,
            },
            .{
                .first_instruction = 2,
                .instruction_count = 2,
                .terminator_index = 1,
            },
        },
        .terminators = &.{
            .{ .kind = .branch_if, .primary = 1, .secondary = 0 },
            .{ .kind = .return_value },
        },
        .instructions = &.{
            .{
                .kind = .call_op,
                .dst = 0,
                .operand = 0,
                .aux = 0,
            },
            .{
                .kind = .compare_eq_zero,
                .dst = 1,
                .operand = 0,
            },
            .{
                .kind = .const_i32,
                .dst = 2,
                .operand = 7,
            },
            .{
                .kind = .return_value,
                .operand = 2,
            },
        },
    };
    const Handlers = struct {
        counter: struct {
            step_calls: usize = 0,
            after_calls: usize = 0,

            pub fn step(self: *@This(), remaining: i32) anyerror!i32 {
                self.step_calls += 1;
                return remaining - 1;
            }

            pub fn afterStep(self: *@This(), answer: i32) anyerror!i32 {
                self.after_calls += 1;
                return answer + 100;
            }
        } = .{},
    };

    var handlers: Handlers = .{};
    const result = try executeLoweredDispatch(plan, &handlers, 0, &.{.{ .i32 = 5 }});
    switch (result) {
        .value => |answer| try std.testing.expectEqual(@as(i32, 507), decodeRuntimeValue(.i32, answer)),
        .terminal => |_| return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 5), handlers.counter.step_calls);
    try std.testing.expectEqual(@as(usize, 5), handlers.counter.after_calls);
}

test "executeLoweredDispatch unwinds after handlers iteratively across large loops review regression" {
    const plan: program_plan.ProgramPlan = .{
        .label = "example.loop_after_large",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "loopAfterRoot",
            .value_codec = .i32,
            .parameter_count = 1,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 3,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 2,
            .first_instruction = 0,
            .instruction_count = 4,
        }},
        .requirements = &.{.{
            .label = "counter",
            .first_op = 0,
            .op_count = 1,
        }},
        .ops = &.{.{
            .requirement_index = 0,
            .op_name = "step",
            .mode = .transform,
            .payload_codec = .i32,
            .resume_codec = .i32,
        }},
        .outputs = &.{},
        .locals = &.{
            .{ .codec = .i32 },
            .{ .codec = .bool },
            .{ .codec = .i32 },
        },
        .blocks = &.{
            .{
                .first_instruction = 0,
                .instruction_count = 2,
                .terminator_index = 0,
            },
            .{
                .first_instruction = 2,
                .instruction_count = 2,
                .terminator_index = 1,
            },
        },
        .terminators = &.{
            .{ .kind = .branch_if, .primary = 1, .secondary = 0 },
            .{ .kind = .return_value },
        },
        .instructions = &.{
            .{
                .kind = .call_op,
                .dst = 0,
                .operand = 0,
                .aux = 0,
            },
            .{
                .kind = .compare_eq_zero,
                .dst = 1,
                .operand = 0,
            },
            .{
                .kind = .const_i32,
                .dst = 2,
                .operand = 7,
            },
            .{
                .kind = .return_value,
                .operand = 2,
            },
        },
    };
    const Handlers = struct {
        counter: struct {
            step_calls: usize = 0,
            after_calls: usize = 0,

            pub fn step(self: *@This(), remaining: i32) anyerror!i32 {
                self.step_calls += 1;
                return remaining - 1;
            }

            pub fn afterStep(self: *@This(), answer: i32) anyerror!i32 {
                self.after_calls += 1;
                return answer + 100;
            }
        } = .{},
    };

    const loop_count: i32 = 100_000;
    var handlers: Handlers = .{};
    const result = try executeLoweredDispatch(plan, &handlers, 0, &.{.{ .i32 = loop_count }});
    switch (result) {
        .value => |answer| try std.testing.expectEqual(@as(i32, 10_000_007), decodeRuntimeValue(.i32, answer)),
        .terminal => |_| return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, loop_count), handlers.counter.step_calls);
    try std.testing.expectEqual(@as(usize, loop_count), handlers.counter.after_calls);
}

test "CompileIr run applies after handlers for repeated loop resumes" {
    const symbol: effect_ir.SymbolRef = .{
        .module_path = "test/public_ir_loop_after.zig",
        .symbol_name = "loopAfterRoot",
    };
    const ProgramType = CompileIr("example.public_ir_loop_after", .{
        .entry_index = 0,
        .functions = &.{.{
            .symbol = symbol,
            .row = effect_ir.rowFromSpec(.{
                .counter = .{
                    .step = effect_ir.Transform(i32, i32),
                },
            }),
            .ValueType = i32,
        }},
        .call_edges = &.{},
        .function_bodies = &.{.{
            .local_codecs = &.{ .i32, .bool, .i32 },
            .entry_block = 0,
            .blocks = &.{
                .{
                    .instructions = &.{.{
                        .kind = .const_i32,
                        .dst = 0,
                        .operand = 6,
                    }},
                    .terminator = .{ .kind = .jump, .primary = 1 },
                },
                .{
                    .instructions = &.{
                        .{ .kind = .call_op, .dst = 0, .operand = 0, .aux = 0 },
                        .{ .kind = .compare_eq_zero, .dst = 1, .operand = 0 },
                    },
                    .terminator = .{ .kind = .branch_if, .primary = 2, .secondary = 1 },
                },
                .{
                    .instructions = &.{
                        .{ .kind = .const_i32, .dst = 2, .operand = 7 },
                        .{ .kind = .return_value, .operand = 2 },
                    },
                    .terminator = .{ .kind = .return_value },
                },
            },
        }},
    });
    const Handlers = struct {
        counter: struct {
            step_calls: usize = 0,
            after_calls: usize = 0,

            pub fn step(self: *@This(), remaining: i32) anyerror!i32 {
                self.step_calls += 1;
                return remaining - 1;
            }

            pub fn afterStep(self: *@This(), answer: i32) anyerror!i32 {
                self.after_calls += 1;
                return answer + 100;
            }
        } = .{},
    };

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var handlers: Handlers = .{};
    const result = try ProgramType.run(&runtime, &handlers);
    try std.testing.expectEqual(@as(i32, 607), result.value);
    try std.testing.expectEqual(@as(usize, 6), handlers.counter.step_calls);
    try std.testing.expectEqual(@as(usize, 6), handlers.counter.after_calls);
}

test "executeLoweredDispatch returns abort answers through terminal control" {
    const plan: program_plan.ProgramPlan = .{
        .label = "example.abort_root",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "abortRoot",
            .value_codec = .string,
            .parameter_count = 1,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
        }},
        .requirements = &.{.{
            .label = "guard",
            .first_op = 0,
            .op_count = 1,
        }},
        .ops = &.{.{
            .requirement_index = 0,
            .op_name = "fail",
            .mode = .abort,
            .payload_codec = .string,
            .resume_codec = .unit,
        }},
        .outputs = &.{},
        .locals = &.{.{ .codec = .string }},
        .blocks = &.{.{
            .first_instruction = 0,
            .instruction_count = 1,
            .terminator_index = 0,
        }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{.{
            .kind = .call_op,
            .operand = 0,
            .aux = 0,
        }},
    };
    const Handlers = struct {
        guard: struct {
            payload: []const u8 = "",

            pub fn fail(self: *@This(), payload: []const u8) anyerror![]const u8 {
                self.payload = payload;
                return "error=missing-name";
            }
        } = .{},
    };
    var handlers: Handlers = .{};
    const payload = lowered_machine.ProgramValue{ .string = "missing-name" };

    const result = try executeLoweredDispatch(plan, &handlers, 0, &.{payload});
    switch (result) {
        .terminal => |answer| try std.testing.expectEqualStrings("error=missing-name", decodeRuntimeValue(.string, answer)),
        .value => |_| return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("missing-name", handlers.guard.payload);
}

test "executeLoweredDispatch unwinds caller after handlers across terminal helper returns" {
    const plan: program_plan.ProgramPlan = .{
        .label = "example.helper_terminal_after_root",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{
            .{
                .symbol_name = "root",
                .value_codec = .string,
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
                .instruction_count = 3,
            },
            .{
                .symbol_name = "helper",
                .value_codec = .string,
                .parameter_count = 0,
                .first_requirement = 1,
                .requirement_count = 1,
                .first_output = 0,
                .output_count = 0,
                .first_local = 1,
                .local_count = 0,
                .first_block = 1,
                .entry_block = 0,
                .block_count = 1,
                .first_instruction = 3,
                .instruction_count = 1,
            },
        },
        .requirements = &.{
            .{
                .label = "picker",
                .first_op = 0,
                .op_count = 1,
            },
            .{
                .label = "guard",
                .first_op = 1,
                .op_count = 1,
            },
        },
        .ops = &.{
            .{
                .requirement_index = 0,
                .op_name = "pick",
                .mode = .choice,
                .payload_codec = .unit,
                .resume_codec = .string,
            },
            .{
                .requirement_index = 1,
                .op_name = "fail",
                .mode = .abort,
                .payload_codec = .unit,
                .resume_codec = .unit,
            },
        },
        .outputs = &.{},
        .locals = &.{.{ .codec = .string }},
        .call_args = &.{},
        .blocks = &.{
            .{
                .first_instruction = 0,
                .instruction_count = 3,
                .terminator_index = 0,
            },
            .{
                .first_instruction = 3,
                .instruction_count = 1,
                .terminator_index = 1,
            },
        },
        .terminators = &.{
            .{ .kind = .return_value },
            .{ .kind = .return_unit },
        },
        .instructions = &.{
            .{
                .kind = .call_op,
                .dst = 0,
                .operand = 0,
            },
            .{
                .kind = .call_helper,
                .operand = 1,
                .aux = std.math.maxInt(u16),
            },
            .{
                .kind = .return_value,
                .operand = 0,
            },
            .{
                .kind = .call_op,
                .operand = 1,
            },
        },
    };
    const Handlers = struct {
        picker: struct {
            after_calls: usize = 0,

            pub fn pick(_: *@This()) anyerror!@import("root.zig").Decision([]const u8, []const u8) {
                return @import("root.zig").Decision([]const u8, []const u8).resumeWith("answer=42");
            }

            pub fn afterPick(self: *@This(), answer: []const u8) anyerror![]const u8 {
                self.after_calls += 1;
                try std.testing.expectEqualStrings("result=early", answer);
                return "wrapped-early";
            }
        } = .{},
        guard: struct {
            pub fn fail(_: *@This()) anyerror![]const u8 {
                return "result=early";
            }
        } = .{},
    };

    var handlers: Handlers = .{};
    const result = try executeLoweredDispatch(plan, &handlers, 0, &.{});
    switch (result) {
        .terminal => |answer| try std.testing.expectEqualStrings("wrapped-early", decodeRuntimeValue(.string, answer)),
        .value => |_| return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(@as(usize, 1), handlers.picker.after_calls);
}

test "executeLoweredDispatch rejects return-value terminators without a return instruction" {
    const plan: program_plan.ProgramPlan = .{
        .label = "example.invalid_return_root",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "invalidReturnRoot",
            .value_codec = .i32,
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
            .instruction_count = 1,
        }},
        .requirements = &.{.{
            .label = "writer",
            .first_op = 0,
            .op_count = 1,
        }},
        .ops = &.{.{
            .requirement_index = 0,
            .op_name = "tell",
            .mode = .transform,
            .payload_codec = .string,
            .resume_codec = .unit,
        }},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &.{.{
            .first_instruction = 0,
            .instruction_count = 1,
            .terminator_index = 0,
        }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{.{
            .kind = .const_i32,
            .dst = 0,
            .operand = 1,
        }},
    };
    const Handlers = struct {
        writer: struct {
            pub fn tell(_: *@This(), _: []const u8) anyerror!void {}
        } = .{},
    };
    var handlers: Handlers = .{};

    try std.testing.expectError(error.ProgramContractViolation, executeLoweredDispatch(plan, &handlers, 0, &.{}));
}
