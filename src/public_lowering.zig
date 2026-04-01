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

/// Public caller-supplied provenance witness for one lowering request.
pub const SourceRef = struct {
    repo_path: []const u8,
    caller_file: []const u8,
    caller_hash: ?u64 = null,
    caller_source: ?[:0]const u8 = null,
};

/// Public additive validation error surface for file-backed same-module sources.
pub const ValidationError = error{
    EntryMissing,
    OutOfMemory,
    ParseError,
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

fn ResultOutputsType(comptime outputs: []const effect_ir.OutputSpec) type {
    var fields = [_]std.builtin.Type.StructField{.{
        .name = "",
        .type = void,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = @alignOf(void),
    }} ** outputs.len;
    for (outputs, 0..) |output, index| {
        fields[index] = .{
            .name = sentinelBytes(output.label),
            .type = output.OutputType,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(output.OutputType),
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

fn LoweredRunResultType(comptime value_type: type, comptime outputs: []const effect_ir.OutputSpec) type {
    return struct {
        outputs: ResultOutputsType(outputs),
        value: value_type,
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

fn callLoweredOp(
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers_ptr: anytype,
    op_index: u16,
    payload: lowered_machine.ProgramValue,
) anyerror!lowered_machine.ProgramValue {
    if (compiled_plan.ops.len == 0) return error.ProgramContractViolation;
    return switch (op_index) {
        inline 0...(compiled_plan.ops.len - 1) => |active_index| blk: {
            const op = compiled_plan.ops[active_index];
            const requirement = compiled_plan.requirements[op.requirement_index];
            const handler_ptr = &@field(handlers_ptr.*, requirement.label);
            const HandlerType = @TypeOf(handler_ptr.*);
            const method = @field(HandlerType, op.op_name);
            const ResumeType = runtimeValueType(op.resume_codec);

            if (op.mode != .transform) @compileError("public lowered runner currently supports only transform operations");

            if (op.payload_codec == .unit) {
                const result = try resolveMaybeError(@call(.auto, method, .{handler_ptr}));
                break :blk if (op.resume_codec == .unit)
                    .none
                else
                    encodeRuntimeValue(op.resume_codec, result);
            }

            const PayloadType = runtimeValueType(op.payload_codec);
            const decoded_payload = decodeRuntimeValue(op.payload_codec, payload);
            const result = try resolveMaybeError(@call(.auto, method, .{ handler_ptr, @as(PayloadType, decoded_payload) }));
            break :blk if (op.resume_codec == .unit)
                .none
            else
                encodeRuntimeValue(op.resume_codec, @as(ResumeType, result));
        },
        else => error.ProgramContractViolation,
    };
}

fn executeLoweredFunction(
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers_ptr: anytype,
    comptime function_index: usize,
    args: []const lowered_machine.ProgramValue,
) anyerror!lowered_machine.ProgramValue {
    const function = compiled_plan.functions[function_index];
    var locals_storage: [function.local_count]lowered_machine.ProgramValue = [_]lowered_machine.ProgramValue{.none} ** function.local_count;
    const locals = locals_storage[0..];
    if (args.len != function.parameter_count) return error.ProgramContractViolation;
    for (args, 0..) |arg, arg_index| {
        setLocal(locals, @intCast(arg_index), arg);
    }
    var current_block_index: u16 = function.first_block + function.entry_block;

    while (true) {
        const block = compiled_plan.blocks[current_block_index];
        const instruction_end = block.first_instruction + block.instruction_count;
        var instruction_index = block.first_instruction;
        var return_local: ?u16 = null;
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
                    if (instruction.dst < locals.len and compiled_plan.functions[instruction.operand].value_codec != .unit) {
                        setLocal(locals, instruction.dst, result);
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
                    const result = try callLoweredOp(compiled_plan, handlers_ptr, instruction.operand, payload);
                    if (instruction.dst < locals.len and op.resume_codec != .unit) {
                        setLocal(locals, instruction.dst, result);
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
            },
            .jump => current_block_index = terminator.primary,
            .return_unit => return .none,
            .return_value => return getLocal(locals, return_local orelse return error.ProgramContractViolation),
        }
    }
}

fn executeLoweredDispatch(
    comptime compiled_plan: program_plan.ProgramPlan,
    handlers_ptr: anytype,
    function_index: u16,
    args: []const lowered_machine.ProgramValue,
) anyerror!lowered_machine.ProgramValue {
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

fn collectLoweredOutputs(comptime outputs: []const effect_ir.OutputSpec, handlers_ptr: anytype) anyerror!ResultOutputsType(outputs) {
    var value: ResultOutputsType(outputs) = std.mem.zeroInit(ResultOutputsType(outputs), .{});
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
    return std.fmt.comptimePrint("{s}", .{bytes});
}

fn pathTailMatches(comptime caller_file: []const u8, comptime repo_path: []const u8) bool {
    if (caller_file.len < repo_path.len) return false;
    const start = caller_file.len - repo_path.len;
    inline for (repo_path, 0..) |expected, index| {
        const actual = caller_file[start + index];
        if (expected == '/') {
            if (actual != '/' and actual != '\\') return false;
            continue;
        }
        if (actual != expected) return false;
    }
    return start == 0 or caller_file[start - 1] == '/' or caller_file[start - 1] == '\\';
}

fn pathStartsWithRoot(comptime path: []const u8, comptime root: []const u8) bool {
    if (path.len < root.len) return false;
    inline for (root, 0..) |expected, index| {
        const actual = path[index];
        if (expected == '/' or expected == '\\') {
            if (actual != '/' and actual != '\\') return false;
            continue;
        }
        if (actual != expected) return false;
    }
    return path.len == root.len or path[root.len] == '/' or path[root.len] == '\\';
}

fn pathUsesOwnedRoot(comptime caller_file: []const u8) bool {
    if (!std.fs.path.isAbsolute(caller_file)) return true;
    return pathStartsWithRoot(caller_file, build_options.package_root) or
        pathStartsWithRoot(caller_file, build_options.package_root_alias);
}

fn sourceOwnershipMatches(comptime source_ref: SourceRef) bool {
    return (pathTailMatches(source_ref.caller_file, source_ref.repo_path) and pathUsesOwnedRoot(source_ref.caller_file)) or
        sourceHashMatches(source_ref);
}

fn hashSourceBytes(comptime bytes: []const u8) u64 {
    comptime {
        @setEvalBranchQuota(1_000_000);
    }
    return std.hash.Wyhash.hash(0, bytes);
}

fn sourceHashMatches(comptime source_ref: SourceRef) bool {
    if (source_ref.caller_source) |caller_source| {
        if (std.fs.path.isAbsolute(source_ref.caller_file)) {
            if (!pathTailMatches(source_ref.caller_file, source_ref.repo_path)) return false;
        } else if (!basenameOwnedWitnessMatches(build_options.repo_duplicate_basenames, source_ref.repo_path, source_ref.caller_file)) {
            return false;
        }
        return source_ref.caller_hash == hashSourceBytes(caller_source);
    }
    const caller_hash = source_ref.caller_hash orelse return false;
    if (std.fs.path.isAbsolute(source_ref.caller_file)) {
        if (!pathTailMatches(source_ref.caller_file, source_ref.repo_path)) return false;
        if (!pathUsesOwnedRoot(source_ref.caller_file)) return false;
        return caller_hash == hashSourceBytes(source_graph_embed.embeddedSource(source_ref.repo_path));
    }
    if (!basenameOwnedWitnessMatches(build_options.repo_duplicate_basenames, source_ref.repo_path, source_ref.caller_file)) return false;
    return caller_hash == hashSourceBytes(source_graph_embed.embeddedSource(source_ref.repo_path));
}

fn sourcePathForLowering(comptime source_ref: SourceRef) []const u8 {
    if (std.fs.path.isAbsolute(source_ref.caller_file) and !pathUsesOwnedRoot(source_ref.caller_file)) {
        return cloneBytes(source_ref.caller_file);
    }
    return source_ref.repo_path;
}

fn basenameOwnedWitnessMatches(
    comptime duplicate_registry: []const u8,
    comptime repo_path: []const u8,
    comptime caller_file: []const u8,
) bool {
    if (pathHasSeparator(caller_file)) return false;
    if (!std.mem.eql(u8, pathBasename(repo_path), caller_file)) return false;
    return !basenameIsDuplicated(duplicate_registry, caller_file);
}

fn basenameIsDuplicated(comptime duplicate_registry: []const u8, comptime basename: []const u8) bool {
    comptime {
        @setEvalBranchQuota(50_000);
    }
    var start: usize = 0;
    while (start < duplicate_registry.len) {
        var end = start;
        while (end < duplicate_registry.len and duplicate_registry[end] != '\n') : (end += 1) {}
        const candidate = duplicate_registry[start..end];
        if (candidate.len != 0 and std.mem.eql(u8, candidate, basename)) return true;
        start = end + 1;
    }
    return false;
}

fn pathBasename(path: []const u8) []const u8 {
    var start = path.len;
    while (start != 0) {
        if (path[start - 1] == '/' or path[start - 1] == '\\') break;
        start -= 1;
    }
    return path[start..];
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
    if (repo_path.len == 0) @compileError("public lowering source helper requires a non-empty repo-relative path");
    if (caller.file.len == 0) @compileError("public lowering source helper requires a non-empty caller source file");
    return .{
        .repo_path = cloneBytes(repo_path),
        .caller_file = cloneBytes(caller.file),
        .caller_hash = null,
        .caller_source = null,
    };
}

/// Build one caller-owned lowering provenance witness from an explicit repo path, `@src()`, and caller-supplied source bytes.
pub fn sourceWithContent(
    comptime repo_path: []const u8,
    comptime caller: std.builtin.SourceLocation,
    comptime caller_source: []const u8,
) SourceRef {
    if (repo_path.len == 0) @compileError("public lowering source helper requires a non-empty repo-relative path");
    if (caller.file.len == 0) @compileError("public lowering source helper requires a non-empty caller source file");
    return .{
        .repo_path = cloneBytes(repo_path),
        .caller_file = cloneBytes(caller.file),
        .caller_hash = hashSourceBytes(caller_source),
        .caller_source = sentinelBytes(caller_source),
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

fn explicitEntryIndex(comptime functions: []const effect_ir.Function, comptime entry_symbol: []const u8) u16 {
    for (functions, 0..) |function, index| {
        if (std.mem.eql(u8, function.symbol.symbol_name, entry_symbol)) return @intCast(index);
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
    return analyzeProgramGraphWithRootSource(source_path, null, entry_symbol);
}

fn analyzeProgramGraphWithRootSource(
    comptime source_path: []const u8,
    comptime root_source: ?[:0]const u8,
    comptime entry_symbol: []const u8,
) source_graph_embed.ProgramGraph {
    return source_graph_embed.analyzeProgramWithRootSource(source_path, root_source, entry_symbol) catch |err| switch (err) {
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
        error.UnsupportedImportPath => @compileError("public lowering supports only repo-relative .zig imports for cross-file helpers"),
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

        const entry_function = graph.functions[graph.entry_index];
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
        },
    );
}

/// Build one explicit-path open-row payload with a caller-visible source path.
fn openRowAt(comptime source_path: []const u8, comptime spec: LowerSpec) program_frontend.OpenRowProgram {
    return openRowWithRootSource(source_path, null, spec);
}

fn openRowWithRootSource(
    comptime source_path: []const u8,
    comptime root_source: ?[:0]const u8,
    comptime spec: LowerSpec,
) program_frontend.OpenRowProgram {
    const graph = analyzeProgramGraphWithRootSource(source_path, root_source, spec.entry_symbol);
    const functions = buildFunctionsForGraph(graph, spec);
    return .{
        .label = spec.label,
        .entry_symbol = spec.entry_symbol,
        .functions = functions,
        .call_edges = buildCallEdgesForGraph(graph),
        .function_bodies = buildFunctionBodiesForGraph(
            graph,
            functions,
            if (root_source != null) source_path else null,
            root_source,
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
        .entry_index = explicitEntryIndex(payload.functions, spec.entry_symbol),
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
    effect_param_present: bool,
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

const ValidationModule = struct {
    path: []u8,
    functions: []ValidationFunction,
    imports: []ValidationImport,
    helper_uses: []ValidationHelperUse,
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

fn deinitValidationGraph(allocator: std.mem.Allocator, graph: source_graph_engine.ModuleGraph) void {
    allocator.free(graph.functions);
    allocator.free(graph.imports);
    allocator.free(graph.helper_uses);
    allocator.free(graph.helper_edges);
    allocator.free(graph.direct_op_uses);
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
            .effect_param_present = function.effect_param != null,
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
    if (!std.mem.startsWith(u8, source_path, build_options.package_root)) return null;
    if (source_path.len <= build_options.package_root.len) return null;
    const separator = source_path[build_options.package_root.len];
    if (separator != '/' and separator != '\\') return null;
    return source_path[build_options.package_root.len + 1 ..];
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

fn canonicalValidationSourcePathAlloc(allocator: std.mem.Allocator, source_path: []const u8) ValidationError![]u8 {
    if (source_path.len == 0) return error.UnsupportedHelperGraph;

    var owned_canonical_path: ?[]u8 = null;
    defer if (owned_canonical_path) |canonical_path| allocator.free(canonical_path);

    const repo_source_path = if (packageRootRelativeSlice(source_path)) |repo_path|
        repo_path
    else if (!std.fs.path.isAbsolute(source_path)) blk: {
        const normalized_repo_source_path = try normalizeRelativeRepoPathAlloc(allocator, source_path);
        defer allocator.free(normalized_repo_source_path);

        const package_root_candidate = std.fs.path.join(allocator, &.{ build_options.package_root, normalized_repo_source_path }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => unreachable,
        };
        defer allocator.free(package_root_candidate);

        owned_canonical_path = std.fs.realpathAlloc(allocator, package_root_candidate) catch null;
        if (owned_canonical_path) |canonical_path| {
            break :blk packageRootRelativeSlice(canonical_path) orelse return error.UnsupportedHelperGraph;
        }

        owned_canonical_path = std.fs.cwd().realpathAlloc(allocator, source_path) catch return error.UnsupportedHelperGraph;
        break :blk packageRootRelativeSlice(owned_canonical_path.?) orelse return error.UnsupportedHelperGraph;
    } else blk: {
        owned_canonical_path = std.fs.realpathAlloc(allocator, source_path) catch return error.UnsupportedHelperGraph;
        break :blk packageRootRelativeSlice(owned_canonical_path.?) orelse return error.UnsupportedHelperGraph;
    };

    const normalized_repo_source_path = try normalizeRelativeRepoPathAlloc(allocator, repo_source_path);
    defer allocator.free(normalized_repo_source_path);
    return std.fs.path.join(allocator, &.{ build_options.package_root, normalized_repo_source_path }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => unreachable,
    };
}

fn packageRootRelativePathAlloc(allocator: std.mem.Allocator, source_path: []const u8) ValidationError![]u8 {
    const canonical_source_path = try canonicalValidationSourcePathAlloc(allocator, source_path);
    defer allocator.free(canonical_source_path);
    const repo_source_path = packageRootRelativeSlice(canonical_source_path) orelse return error.UnsupportedHelperGraph;
    return try allocator.dupe(u8, repo_source_path);
}

fn resolveValidationImportPathAlloc(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    import_path: []const u8,
) ValidationError![]u8 {
    if (std.fs.path.isAbsolute(import_path)) return error.UnsupportedHelperGraph;
    if (!std.mem.endsWith(u8, import_path, ".zig")) return error.UnsupportedHelperGraph;

    const repo_source_path = try packageRootRelativePathAlloc(allocator, source_path);
    defer allocator.free(repo_source_path);
    const base_dir = std.fs.path.dirname(repo_source_path) orelse "";

    var joined = std.ArrayList(u8).empty;
    defer joined.deinit(allocator);
    if (base_dir.len != 0) {
        try joined.appendSlice(allocator, base_dir);
        try joined.append(allocator, '/');
    }
    try joined.appendSlice(allocator, import_path);
    return try normalizeRelativeRepoPathAlloc(allocator, joined.items);
}

fn collectValidationModule(
    state: *ValidationState,
    source_path: []const u8,
    entry_symbol: ?[]const u8,
) ValidationError!usize {
    if (state.findModuleIndex(source_path)) |existing_index| {
        if (entry_symbol) |required_entry| {
            if (findValidationFunctionIndex(state.modules.items[existing_index].functions, required_entry) == null) {
                return error.EntryMissing;
            }
        }
        return existing_index;
    }

    var analysis = source_lowering.analyzeFileBackedSource(state.allocator, source_path) catch |err| switch (err) {
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
    defer analysis.deinit(state.allocator);

    if (!analysis.isParseClean()) return error.ParseError;
    const graph = source_graph_engine.analyzeRuntime(state.allocator, analysis.parsed.source_z, .{
        .entry_symbol = entry_symbol,
        .reject_indirect_effect_access = true,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.EntryMissing => return error.EntryMissing,
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
    defer deinitValidationGraph(state.allocator, graph);

    var module_owned_by_state = false;
    const owned_path = try state.allocator.dupe(u8, source_path);
    errdefer if (!module_owned_by_state) state.allocator.free(owned_path);
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

    if (state.modules.items.len >= max_validation_modules) return error.UnsupportedHelperGraph;
    try state.modules.append(state.allocator, .{
        .path = owned_path,
        .functions = owned_functions,
        .imports = owned_imports,
        .helper_uses = owned_helper_uses,
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

    for (module.helper_uses) |helper_use| {
        const import_alias = helper_use.import_alias orelse continue;
        if (!module.functions[helper_use.caller_index].effect_param_present) continue;

        const import_row = findValidationImport(module.imports, import_alias) orelse return error.UnsupportedHelperGraph;
        const imported_repo_path = try resolveValidationImportPathAlloc(state.allocator, source_path, import_row.import_path);
        defer state.allocator.free(imported_repo_path);
        const imported_path = try std.fs.path.join(state.allocator, &.{ build_options.package_root, imported_repo_path });
        defer state.allocator.free(imported_path);

        const imported_index = try collectValidationModule(state, imported_path, null);
        if (findValidationFunctionIndex(state.modules.items[imported_index].functions, helper_use.callee_name) == null) {
            return error.UnsupportedHelperGraph;
        }

        state.helper_edge_count += 1;
        if (state.helper_edge_count > max_validation_helper_edges) return error.UnsupportedHelperGraph;
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
    _ = try collectValidationModule(&validation, canonical_source_path, entry_symbol);
}

const ValidationSpec = struct {
    source_path: []const u8,
    entry_symbol: []const u8,
};

const RunSpec = struct {
    ValueType: type,
    outputs: []const effect_ir.OutputSpec,
};

fn GeneratedProgramType(
    comptime label_value: []const u8,
    comptime source_path_value: []const u8,
    comptime entry_symbol_value: []const u8,
    comptime compiled_plan: program_plan.ProgramPlan,
    comptime run_spec: ?RunSpec,
    comptime validate_spec: ?ValidationSpec,
) type {
    return struct {
        const RunResult = if (run_spec) |active| LoweredRunResultType(active.ValueType, active.outputs) else void;
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
            return try validateFileBackedOpenRowAt(allocator, active_spec.source_path, active_spec.entry_symbol);
        }

        /// Execute this lowered program through its runtime_plan using explicit handler objects.
        pub fn run(runtime: *lowered_machine.Runtime, handlers: anytype) anyerror!RunResult {
            const active_run_spec = run_spec orelse @compileError("public lowered-program execution is available only on source-lowered generated program types");
            try lowered_machine.beginExecution(runtime);
            defer lowered_machine.endExecution(runtime);
            const value = try executeLoweredDispatch(compiled_plan, handlers, compiled_plan.entry_index, &.{});
            return .{
                .outputs = try collectLoweredOutputs(active_run_spec.outputs, handlers),
                .value = decodeRuntimeValue(compiled_plan.functions[compiled_plan.entry_index].value_codec, value),
            };
        }
    };
}

fn LowerAt(comptime source_path: []const u8, comptime spec: LowerSpec) type {
    comptime {
        @setEvalBranchQuota(20_000);
    }
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
    return GeneratedProgramType(spec.label, source_path, spec.entry_symbol, compiled_plan, .{
        .ValueType = spec.ValueType,
        .outputs = spec.outputs,
    }, .{
        .source_path = source_path,
        .entry_symbol = spec.entry_symbol,
    });
}

fn Lower(comptime source_ref: SourceRef, comptime spec: LowerSpec) type {
    assertSourceOwnership(source_ref);
    if (source_ref.caller_source != null) {
        const caller_source = source_ref.caller_source.?;
        const source_path = sourcePathForLowering(source_ref);
        comptime {
            @setEvalBranchQuota(20_000);
        }
        const lowered_program = source_lowering.lowerOpenRowProgram(openRowWithRootSource(source_path, caller_source, spec)) catch |err| switch (err) {
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
        return GeneratedProgramType(spec.label, source_path, spec.entry_symbol, compiled_plan, .{
            .ValueType = spec.ValueType,
            .outputs = spec.outputs,
        }, .{
            .source_path = source_path,
            .entry_symbol = spec.entry_symbol,
        });
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
    if (program.entry_index >= program.functions.len) {
        @compileError("public lowering rejected an effect-ir program with an out-of-range entry_index");
    }
    assertExecutableCodecSupport(compiled_plan);
    return GeneratedProgramType(label, "<ir>", program.functions[program.entry_index].symbol.symbol_name, compiled_plan, null, null);
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
    });

    try std.testing.expectEqualStrings("examples/open_row_state_writer.zig", ProgramType.source_path);
    try std.testing.expectEqualStrings("runBody", ProgramType.entry_symbol);
    try std.testing.expectEqual(@as(usize, 3), ProgramType.runtime_plan.functions.len);
}

test "source ownership requires a true repo-path suffix, not a basename-only match" {
    try std.testing.expect(sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = "examples/open_row_state_writer.zig",
    }));
    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = "/tmp/open_row_state_writer.zig",
    }));
}

test "source ownership accepts only absolute paths rooted at the checkout or package-root alias" {
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
    try std.testing.expect(sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = alias_owned,
    }));
    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = "/tmp/foreign/examples/open_row_state_writer.zig",
    }));
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
    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = prefixed_alias_root,
    }));
}

test "source ownership accepts a helper-authored content witness when caller paths are module-root relative" {
    try std.testing.expect(sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = "open_row_state_writer.zig",
        .caller_hash = hashSourceBytes(source_graph_embed.embeddedSource("examples/open_row_state_writer.zig")),
    }));
    try std.testing.expect(!sourceOwnershipMatches(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = "open_row_state_writer.zig",
        .caller_hash = hashSourceBytes("not the repo source"),
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

test "source ownership rejects basename-only content witnesses when the basename is duplicated" {
    try std.testing.expect(!basenameOwnedWitnessMatches(
        "index.zig\n",
        "foo/index.zig",
        "index.zig",
    ));
}

test "executeLoweredDispatch rejects return-value terminators without a return instruction" {
    const row = effect_ir.rowFromSpec(.{
        .writer = .{
            .tell = effect_ir.Transform([]const u8, void),
        },
    });
    const entry_symbol: effect_ir.SymbolRef = .{
        .module_path = "src/public_lowering.zig",
        .symbol_name = "invalidReturnRoot",
    };
    const plan = comptime try program_plan.planFromProgram("example.invalid_return_root", .{
        .entry_index = 0,
        .functions = &.{.{
            .symbol = entry_symbol,
            .row = row,
            .ValueType = i32,
        }},
        .call_edges = &.{},
        .function_bodies = &.{.{
            .local_codecs = &.{.i32},
            .entry_block = 0,
            .blocks = &.{.{
                .instructions = &.{.{
                    .kind = .const_i32,
                    .dst = 0,
                    .operand = 1,
                }},
                .terminator = .{ .kind = .return_value },
            }},
        }},
    });
    const Handlers = struct {
        writer: struct {
            pub fn tell(_: *@This(), _: []const u8) anyerror!void {}
        } = .{},
    };
    var handlers: Handlers = .{};

    try std.testing.expectError(error.ProgramContractViolation, executeLoweredDispatch(plan, &handlers, 0, &.{}));
}
