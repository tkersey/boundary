const effect_ir = @import("effect_ir");
const program_frontend = @import("program_frontend");
const std = @import("std");

/// Serializable value codecs admitted by the first redesign wave.
pub const ValueCodec = enum {
    bool,
    i32,
    string,
    string_list,
    unit,
    usize,
};

/// Return whether this codec carries a runtime payload.
pub fn hasPayload(codec: ValueCodec) bool {
    return codec != .unit;
}

/// Runtime-owned control-mode tag for executable plan ops.
pub const ControlMode = enum {
    abort,
    choice,
    transform,
};

fn controlModeFromIr(mode: effect_ir.ControlMode) ControlMode {
    return switch (mode) {
        .abort => .abort,
        .choice => .choice,
        .transform => .transform,
    };
}

/// One lowered output descriptor in the runtime-owned executable plan.
pub const OutputPlan = struct {
    label: []const u8,
    codec: ValueCodec,
};

/// One lowered local slot descriptor in the runtime-owned executable plan.
pub const LocalPlan = struct {
    codec: ValueCodec,
};

/// One lowered operation descriptor in the runtime-owned executable plan.
pub const OpPlan = struct {
    requirement_index: u16,
    op_name: []const u8,
    mode: ControlMode,
    payload_codec: ValueCodec,
    resume_codec: ValueCodec,
    has_after: bool = false,
};

/// One lowered requirement descriptor in the runtime-owned executable plan.
pub const RequirementPlan = struct {
    label: []const u8,
    first_op: u16,
    op_count: u16,
};

/// One lowered function descriptor in the runtime-owned executable plan.
pub const FunctionPlan = struct {
    symbol_name: []const u8,
    value_codec: ValueCodec = .unit,
    parameter_count: u16 = 0,
    first_requirement: u16,
    requirement_count: u16,
    first_output: u16,
    output_count: u16,
    first_local: u16 = 0,
    local_count: u16 = 0,
    first_block: u16 = 0,
    entry_block: u16 = 0,
    block_count: u16 = 0,
    first_instruction: u16,
    instruction_count: u16,
};

/// Serializable instruction tags carried by the runtime-owned plan.
pub const InstructionKind = enum {
    add_const_i32,
    call_helper,
    call_op,
    compare_eq_zero,
    const_i32,
    const_string,
    return_value,
    sub_one,
};

/// One serializable placeholder instruction in the runtime-owned executable plan.
pub const Instruction = struct {
    kind: InstructionKind,
    dst: u16 = 0,
    operand: u16 = 0,
    aux: u16 = 0,
    string_literal: []const u8 = "",
};

/// Serializable block terminator tags carried by the runtime-owned plan.
pub const TerminatorKind = enum {
    branch_if,
    jump,
    return_unit,
    return_value,
};

/// One serializable block terminator in the runtime-owned executable plan.
pub const Terminator = struct {
    kind: TerminatorKind,
    primary: u16 = 0,
    secondary: u16 = 0,
};

/// One lowered basic-block descriptor in the runtime-owned executable plan.
pub const BlockPlan = struct {
    first_instruction: u16,
    instruction_count: u16,
    terminator_index: u16,
};

/// Runtime-owned serializable executable plan for lowered or explicit IR programs.
pub const ProgramPlan = struct {
    /// Stable schema version for JSON-serialized runtime plans.
    pub const current_schema_version: u32 = 4;

    schema_version: u32 = current_schema_version,
    label: []const u8,
    ir_hash: u64,
    entry_index: u16,
    functions: []const FunctionPlan,
    requirements: []const RequirementPlan,
    ops: []const OpPlan,
    outputs: []const OutputPlan,
    locals: []const LocalPlan = &.{},
    call_args: []const u16 = &.{},
    blocks: []const BlockPlan = &.{},
    terminators: []const Terminator = &.{},
    instructions: []const Instruction,

    /// Validate that this runtime-owned plan is structurally self-contained.
    pub fn validate(self: @This()) ValidationError!void {
        if (self.schema_version != current_schema_version) return error.UnsupportedSchemaVersion;
        if (self.label.len == 0) return error.EmptyLabel;
        if (self.functions.len == 0) return error.EmptyProgram;
        if (self.entry_index >= self.functions.len) return error.InvalidEntryIndex;
        var reachable_blocks = [_]bool{false} ** (std.math.maxInt(u16) + 1);
        var terminal_reachability = [_]bool{false} ** (std.math.maxInt(u16) + 1);

        for (self.functions) |function| {
            if (function.symbol_name.len == 0) return error.EmptyFunctionSymbol;
            if (function.parameter_count > function.local_count) return error.InvalidFunctionLocalSpan;
            if (function.block_count == 0 or function.entry_block >= function.block_count) return error.InvalidFunctionEntryBlock;
            const requirement_end = rangeEnd(function.first_requirement, function.requirement_count) orelse return error.InvalidFunctionRequirementSpan;
            if (requirement_end > self.requirements.len) return error.InvalidFunctionRequirementSpan;
            const output_end = rangeEnd(function.first_output, function.output_count) orelse return error.InvalidFunctionOutputSpan;
            if (output_end > self.outputs.len) return error.InvalidFunctionOutputSpan;
            const local_end = rangeEnd(function.first_local, function.local_count) orelse return error.InvalidFunctionLocalSpan;
            if (local_end > self.locals.len) return error.InvalidFunctionLocalSpan;
            const block_end = rangeEnd(function.first_block, function.block_count) orelse return error.InvalidFunctionBlockSpan;
            if (block_end > self.blocks.len) return error.InvalidFunctionBlockSpan;
            const instruction_end = rangeEnd(function.first_instruction, function.instruction_count) orelse return error.InvalidFunctionInstructionSpan;
            if (instruction_end > self.instructions.len) return error.InvalidFunctionInstructionSpan;
        }

        for (self.requirements) |requirement| {
            if (requirement.label.len == 0) return error.EmptyRequirementLabel;
            const op_end = rangeEnd(requirement.first_op, requirement.op_count) orelse return error.InvalidRequirementOpSpan;
            if (op_end > self.ops.len) return error.InvalidRequirementOpSpan;
        }

        for (self.ops, 0..) |op, op_index| {
            if (op.requirement_index >= self.requirements.len) return error.InvalidOpRequirementIndex;
            if (!opBelongsToRequirement(self, @intCast(op_index), op.requirement_index)) return error.InvalidOpRequirementOwnership;
            if (op.op_name.len == 0) return error.EmptyOpName;
            if (op.has_after and op.mode == .abort) return error.InvalidAfterHookMode;
        }

        for (self.outputs) |output| {
            if (output.label.len == 0) return error.EmptyOutputLabel;
        }

        for (self.blocks) |block| {
            const instruction_end = rangeEnd(block.first_instruction, block.instruction_count) orelse return error.InvalidBlockInstructionSpan;
            if (instruction_end > self.instructions.len) return error.InvalidBlockInstructionSpan;
            if (block.terminator_index >= self.terminators.len) return error.InvalidBlockTerminatorIndex;
        }

        for (self.functions) |function| {
            try markFunctionReachableBlocks(self, function, &reachable_blocks);
        }

        var changed = true;
        while (changed) {
            changed = false;
            for (self.functions, 0..) |function, function_index| {
                if (terminal_reachability[function_index]) continue;
                const block_end = rangeEnd(function.first_block, function.block_count) orelse return error.InvalidFunctionBlockSpan;
                for (self.blocks[function.first_block..block_end], 0..) |block, relative_block_index| {
                    const block_index = @as(usize, function.first_block) + relative_block_index;
                    if (!reachable_blocks[block_index]) continue;
                    const instruction_end = rangeEnd(block.first_instruction, block.instruction_count) orelse return error.InvalidBlockInstructionSpan;
                    for (self.instructions[block.first_instruction..instruction_end]) |instruction| {
                        switch (instruction.kind) {
                            .call_helper => {
                                if (instruction.operand >= self.functions.len) return error.InvalidCallHelperTarget;
                                if (terminal_reachability[instruction.operand]) {
                                    terminal_reachability[function_index] = true;
                                    changed = true;
                                    break;
                                }
                            },
                            .call_op => {
                                if (instruction.operand >= self.ops.len or !functionOwnsOpTarget(self, function, instruction.operand)) {
                                    return error.InvalidCallOpTarget;
                                }
                                if (self.ops[instruction.operand].mode != .transform) {
                                    terminal_reachability[function_index] = true;
                                    changed = true;
                                    break;
                                }
                            },
                            else => {},
                        }
                    }
                    if (terminal_reachability[function_index]) break;
                }
            }
        }

        for (self.functions) |function| {
            const block_end = rangeEnd(function.first_block, function.block_count) orelse return error.InvalidFunctionBlockSpan;
            const function_instruction_end = rangeEnd(function.first_instruction, function.instruction_count) orelse return error.InvalidFunctionInstructionSpan;
            const function_returns_value = function.value_codec != .unit;
            var covered_instruction_end: usize = function.first_instruction;
            for (self.blocks[function.first_block..block_end], 0..) |block, relative_block_index| {
                if (block.first_instruction != covered_instruction_end) return error.InvalidFunctionInstructionSpan;
                const instruction_end = rangeEnd(block.first_instruction, block.instruction_count) orelse return error.InvalidBlockInstructionSpan;
                if (instruction_end > function_instruction_end) return error.InvalidFunctionInstructionSpan;
                covered_instruction_end = instruction_end;
                const block_index = @as(usize, function.first_block) + relative_block_index;
                const block_is_reachable = reachable_blocks[block_index];
                var block_has_return_value = false;
                for (self.instructions[block.first_instruction..instruction_end], 0..) |instruction, relative_index| switch (instruction.kind) {
                    .call_helper => {
                        if (instruction.operand >= self.functions.len) return error.InvalidCallHelperTarget;
                        const callee = self.functions[instruction.operand];
                        if (block_is_reachable and callee.value_codec != function.value_codec and terminal_reachability[instruction.operand]) {
                            return error.InvalidInstructionLocalIndex;
                        }
                        if (callee.value_codec != .unit and
                            !functionLocalHasCodec(self, function, instruction.dst, callee.value_codec))
                        {
                            return error.InvalidInstructionLocalIndex;
                        }
                        const target_parameter_count = callee.parameter_count;
                        if (target_parameter_count != 0) {
                            const call_arg_end = rangeEnd(instruction.aux, target_parameter_count) orelse return error.InvalidCallHelperArgSpan;
                            if (call_arg_end > self.call_args.len) return error.InvalidCallHelperArgSpan;
                            for (self.call_args[instruction.aux..call_arg_end], 0..) |local_id, parameter_index| {
                                if (!isValidFunctionLocal(function.local_count, local_id)) return error.InvalidCallHelperArgSpan;
                                const expected_codec = functionLocalCodec(self, callee, @intCast(parameter_index)) orelse
                                    return error.InvalidFunctionLocalSpan;
                                if (!functionLocalHasCodec(self, function, local_id, expected_codec)) {
                                    return error.InvalidInstructionLocalIndex;
                                }
                            }
                        }
                    },
                    .call_op => {
                        if (instruction.operand >= self.ops.len or !functionOwnsOpTarget(self, function, instruction.operand)) {
                            return error.InvalidCallOpTarget;
                        }
                        if (self.ops[instruction.operand].resume_codec != .unit and
                            !functionLocalHasCodec(self, function, instruction.dst, self.ops[instruction.operand].resume_codec))
                        {
                            return error.InvalidInstructionLocalIndex;
                        }
                        if (self.ops[instruction.operand].payload_codec != .unit and
                            !functionLocalHasCodec(self, function, instruction.aux, self.ops[instruction.operand].payload_codec))
                        {
                            return error.InvalidInstructionLocalIndex;
                        }
                    },
                    .const_string => {
                        if (!functionLocalHasCodec(self, function, instruction.dst, .string)) return error.InvalidInstructionLocalIndex;
                    },
                    .add_const_i32, .compare_eq_zero, .const_i32, .sub_one => {
                        switch (instruction.kind) {
                            .add_const_i32 => {
                                if (!functionLocalHasCodec(self, function, instruction.dst, .i32) or
                                    !functionLocalHasCodec(self, function, instruction.operand, .i32))
                                {
                                    return error.InvalidInstructionLocalIndex;
                                }
                            },
                            .compare_eq_zero => {
                                const operand_codec = functionLocalCodec(self, function, instruction.operand) orelse
                                    return error.InvalidInstructionLocalIndex;
                                if (operand_codec != .i32 and operand_codec != .usize) return error.InvalidInstructionLocalIndex;
                                if (!functionLocalHasCodec(self, function, instruction.dst, .bool)) return error.InvalidInstructionLocalIndex;
                            },
                            .const_i32 => {
                                if (!functionLocalHasCodec(self, function, instruction.dst, .i32)) return error.InvalidInstructionLocalIndex;
                            },
                            .sub_one => {
                                const operand_codec = functionLocalCodec(self, function, instruction.operand) orelse
                                    return error.InvalidInstructionLocalIndex;
                                if (operand_codec != .i32 and operand_codec != .usize) return error.InvalidInstructionLocalIndex;
                                if (!functionLocalHasCodec(self, function, instruction.dst, operand_codec)) {
                                    return error.InvalidInstructionLocalIndex;
                                }
                            },
                            else => unreachable,
                        }
                    },
                    .return_value => {
                        block_has_return_value = true;
                        if (!function_returns_value) return error.InvalidTerminatorInstruction;
                        if (relative_index + 1 != block.instruction_count) return error.InvalidTerminatorInstruction;
                        if (!functionLocalHasCodec(self, function, instruction.operand, function.value_codec)) {
                            return error.InvalidInstructionLocalIndex;
                        }
                    },
                };

                const terminator = self.terminators[block.terminator_index];
                switch (terminator.kind) {
                    .branch_if => {
                        if (!isOwnedBlockTarget(function.first_block, block_end, terminator.primary)) return error.InvalidTerminatorTarget;
                        if (!isOwnedBlockTarget(function.first_block, block_end, terminator.secondary)) return error.InvalidTerminatorTarget;
                        if (instruction_end == block.first_instruction or
                            self.instructions[instruction_end - 1].kind != .compare_eq_zero)
                        {
                            return error.InvalidTerminatorInstruction;
                        }
                    },
                    .jump => {
                        if (!isOwnedBlockTarget(function.first_block, block_end, terminator.primary)) return error.InvalidTerminatorTarget;
                    },
                    .return_unit => {
                        if (function_returns_value) return error.InvalidTerminatorInstruction;
                    },
                    .return_value => {
                        if (!function_returns_value or !block_has_return_value) return error.InvalidTerminatorInstruction;
                    },
                }
            }
            if (covered_instruction_end != function_instruction_end) return error.InvalidFunctionInstructionSpan;
        }
    }

    /// Compute a stable hash over the runtime-owned plan payload.
    pub fn hash(self: @This()) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&self.schema_version));
        hashBytes(&hasher, self.label);
        hasher.update(std.mem.asBytes(&self.ir_hash));
        hasher.update(std.mem.asBytes(&self.entry_index));
        for (self.functions) |function| {
            hashBytes(&hasher, function.symbol_name);
            hashBytes(&hasher, @tagName(function.value_codec));
            hasher.update(std.mem.asBytes(&function.parameter_count));
            hasher.update(std.mem.asBytes(&function.first_requirement));
            hasher.update(std.mem.asBytes(&function.requirement_count));
            hasher.update(std.mem.asBytes(&function.first_output));
            hasher.update(std.mem.asBytes(&function.output_count));
            hasher.update(std.mem.asBytes(&function.first_local));
            hasher.update(std.mem.asBytes(&function.local_count));
            hasher.update(std.mem.asBytes(&function.first_block));
            hasher.update(std.mem.asBytes(&function.entry_block));
            hasher.update(std.mem.asBytes(&function.block_count));
            hasher.update(std.mem.asBytes(&function.first_instruction));
            hasher.update(std.mem.asBytes(&function.instruction_count));
        }
        for (self.requirements) |requirement| {
            hashBytes(&hasher, requirement.label);
            hasher.update(std.mem.asBytes(&requirement.first_op));
            hasher.update(std.mem.asBytes(&requirement.op_count));
        }
        for (self.ops) |op| {
            hasher.update(std.mem.asBytes(&op.requirement_index));
            hashBytes(&hasher, op.op_name);
            hashBytes(&hasher, @tagName(op.mode));
            hashBytes(&hasher, @tagName(op.payload_codec));
            hashBytes(&hasher, @tagName(op.resume_codec));
            hasher.update(&[_]u8{@intFromBool(op.has_after)});
        }
        for (self.outputs) |output| {
            hashBytes(&hasher, output.label);
            hashBytes(&hasher, @tagName(output.codec));
        }
        for (self.locals) |local| {
            hashBytes(&hasher, @tagName(local.codec));
        }
        for (self.call_args) |local_id| hasher.update(std.mem.asBytes(&local_id));
        for (self.blocks) |block| {
            hasher.update(std.mem.asBytes(&block.first_instruction));
            hasher.update(std.mem.asBytes(&block.instruction_count));
            hasher.update(std.mem.asBytes(&block.terminator_index));
        }
        for (self.terminators) |terminator| {
            hashBytes(&hasher, @tagName(terminator.kind));
            hasher.update(std.mem.asBytes(&terminator.primary));
            hasher.update(std.mem.asBytes(&terminator.secondary));
        }
        for (self.instructions) |instruction| {
            hashBytes(&hasher, @tagName(instruction.kind));
            hasher.update(std.mem.asBytes(&instruction.dst));
            hasher.update(std.mem.asBytes(&instruction.operand));
            hasher.update(std.mem.asBytes(&instruction.aux));
            hashBytes(&hasher, instruction.string_literal);
        }
        return hasher.final();
    }
};

/// Error set for runtime-plan codec lowering.
pub const CodecError = error{UnsupportedCodecType};
/// Error set for runtime-plan structural validation.
pub const ValidationError = error{
    EmptyFunctionSymbol,
    EmptyLabel,
    EmptyOpName,
    EmptyOutputLabel,
    EmptyProgram,
    EmptyRequirementLabel,
    InvalidCallHelperTarget,
    InvalidCallHelperArgSpan,
    InvalidCallOpTarget,
    InvalidBlockInstructionSpan,
    InvalidBlockTerminatorIndex,
    InvalidEntryIndex,
    InvalidFunctionBlockSpan,
    InvalidFunctionEntryBlock,
    InvalidFunctionInstructionSpan,
    InvalidFunctionLocalSpan,
    InvalidFunctionOutputSpan,
    InvalidFunctionRequirementSpan,
    InvalidInstructionLocalIndex,
    InvalidAfterHookMode,
    InvalidOpRequirementIndex,
    InvalidOpRequirementOwnership,
    InvalidRequirementOpSpan,
    InvalidReturnValueIndex,
    InvalidTerminatorInstruction,
    InvalidTerminatorTarget,
    UnsupportedSchemaVersion,
};
/// Error set for lowering comptime IR into a runtime-owned plan.
pub const PlanError = CodecError || effect_ir.NormalizeError || error{EmptyProgram};
/// Error set for upgrading legacy runtime-plan schemas in place.
pub const LegacySchemaError = std.mem.Allocator.Error || error{UnsupportedSchemaVersion};

/// Return the first-wave runtime codec for one supported Zig type.
pub fn codecForType(comptime T: type) CodecError!ValueCodec {
    if (T == void) return .unit;
    if (T == bool) return .bool;
    if (T == i32) return .i32;
    if (T == usize) return .usize;
    if (T == []const u8) return .string;
    if (T == [][]const u8) return .string_list;
    return error.UnsupportedCodecType;
}

fn hashBytes(hasher: *std.hash.Wyhash, value: []const u8) void {
    hasher.update(value);
    hasher.update(&.{0});
}

fn codecFromEffectIrBody(codec: effect_ir.LocalCodec) ValueCodec {
    return switch (codec) {
        .bool => .bool,
        .i32 => .i32,
        .string => .string,
        .string_list => .string_list,
        .unit => .unit,
        .usize => .usize,
    };
}

fn valueCodecFromEffectType(comptime T: type) CodecError!ValueCodec {
    return try codecForType(T);
}

fn instructionKindFromEffectIrBody(kind: effect_ir.InstructionKind) InstructionKind {
    return switch (kind) {
        .add_const_i32 => .add_const_i32,
        .call_helper => .call_helper,
        .call_op => .call_op,
        .compare_eq_zero => .compare_eq_zero,
        .const_i32 => .const_i32,
        .const_string => .const_string,
        .return_value => .return_value,
        .sub_one => .sub_one,
    };
}

fn terminatorKindFromEffectIrBody(kind: effect_ir.TerminatorKind) TerminatorKind {
    return switch (kind) {
        .branch_if => .branch_if,
        .jump => .jump,
        .return_unit => .return_unit,
        .return_value => .return_value,
    };
}

/// Upgrade a legacy plan in place up to the current schema.
pub fn upgradeLegacyProgramPlan(allocator: std.mem.Allocator, plan: *ProgramPlan) LegacySchemaError!void {
    if (plan.schema_version == ProgramPlan.current_schema_version) return;
    if (plan.schema_version == 1) {
        const functions = try allocator.alloc(FunctionPlan, plan.functions.len);
        errdefer allocator.free(functions);
        const locals = try allocator.dupe(LocalPlan, plan.locals);
        errdefer allocator.free(locals);
        const preserve_existing_blocks = plan.blocks.len != 0 or plan.terminators.len != 0;
        const blocks = if (preserve_existing_blocks)
            try allocator.dupe(BlockPlan, plan.blocks)
        else
            try allocator.alloc(BlockPlan, plan.functions.len);
        errdefer allocator.free(blocks);
        const terminators = if (preserve_existing_blocks)
            try allocator.dupe(Terminator, plan.terminators)
        else
            try allocator.alloc(Terminator, plan.functions.len);
        errdefer allocator.free(terminators);

        for (plan.functions, 0..) |function, index| {
            functions[index] = function;
            if (!preserve_existing_blocks) {
                functions[index].first_block = @intCast(index);
                functions[index].entry_block = 0;
                functions[index].block_count = 1;
                blocks[index] = .{
                    .first_instruction = function.first_instruction,
                    .instruction_count = function.instruction_count,
                    .terminator_index = @intCast(index),
                };
                terminators[index] = .{
                    .kind = if (function.value_codec == .unit) .return_unit else .return_value,
                    .primary = 0,
                    .secondary = 0,
                };
            }
        }

        allocator.free(plan.functions);
        allocator.free(plan.locals);
        allocator.free(plan.blocks);
        allocator.free(plan.terminators);
        plan.functions = functions;
        plan.locals = locals;
        plan.blocks = blocks;
        plan.terminators = terminators;
        plan.schema_version = 2;
    }

    if (plan.schema_version == 2) {
        const instructions = try allocator.alloc(Instruction, plan.instructions.len);
        errdefer allocator.free(instructions);
        for (plan.instructions, 0..) |instruction, index| {
            instructions[index] = .{
                .kind = instruction.kind,
                .dst = 0,
                .operand = instruction.operand,
                .aux = 0,
            };
        }
        allocator.free(plan.instructions);
        plan.instructions = instructions;
        plan.schema_version = ProgramPlan.current_schema_version;
        return;
    }

    if (plan.schema_version == 3) {
        plan.schema_version = ProgramPlan.current_schema_version;
        return;
    }

    if (plan.schema_version != ProgramPlan.current_schema_version) return error.UnsupportedSchemaVersion;
}

fn rangeEnd(start: u16, len: u16) ?usize {
    const wide_start: usize = start;
    const wide_len: usize = len;
    return std.math.add(usize, wide_start, wide_len) catch null;
}

fn isValidFunctionLocal(local_count: u16, local_id: u16) bool {
    return local_id < local_count;
}

fn functionLocalCodec(self: ProgramPlan, function: FunctionPlan, local_id: u16) ?ValueCodec {
    if (!isValidFunctionLocal(function.local_count, local_id)) return null;
    return self.locals[function.first_local + local_id].codec;
}

fn functionLocalHasCodec(self: ProgramPlan, function: FunctionPlan, local_id: u16, expected: ValueCodec) bool {
    return functionLocalCodec(self, function, local_id) == expected;
}

fn isOwnedBlockTarget(first_block: u16, block_end: usize, target: u16) bool {
    const target_index: usize = target;
    return target_index >= first_block and target_index < block_end;
}

fn markFunctionReachableBlocks(
    self: ProgramPlan,
    function: FunctionPlan,
    reachable_blocks: *[std.math.maxInt(u16) + 1]bool,
) ValidationError!void {
    const block_end = rangeEnd(function.first_block, function.block_count) orelse return error.InvalidFunctionBlockSpan;
    const entry_block_index = @as(usize, function.first_block) + function.entry_block;
    reachable_blocks[entry_block_index] = true;

    var changed = true;
    while (changed) {
        changed = false;
        for (self.blocks[function.first_block..block_end], 0..) |block, relative_block_index| {
            const block_index = @as(usize, function.first_block) + relative_block_index;
            if (!reachable_blocks[block_index]) continue;
            const terminator = self.terminators[block.terminator_index];
            switch (terminator.kind) {
                .branch_if => {
                    if (isOwnedBlockTarget(function.first_block, block_end, terminator.primary) and
                        !reachable_blocks[terminator.primary])
                    {
                        reachable_blocks[terminator.primary] = true;
                        changed = true;
                    }
                    if (isOwnedBlockTarget(function.first_block, block_end, terminator.secondary) and
                        !reachable_blocks[terminator.secondary])
                    {
                        reachable_blocks[terminator.secondary] = true;
                        changed = true;
                    }
                },
                .jump => {
                    if (isOwnedBlockTarget(function.first_block, block_end, terminator.primary) and
                        !reachable_blocks[terminator.primary])
                    {
                        reachable_blocks[terminator.primary] = true;
                        changed = true;
                    }
                },
                .return_unit, .return_value => {},
            }
        }
    }
}

fn functionOwnsOpTarget(self: ProgramPlan, function: FunctionPlan, target: u16) bool {
    const requirement_end = rangeEnd(function.first_requirement, function.requirement_count) orelse return false;
    for (self.requirements[function.first_requirement..requirement_end]) |requirement| {
        const op_end = rangeEnd(requirement.first_op, requirement.op_count) orelse return false;
        if (target >= requirement.first_op and target < op_end) return true;
    }
    return false;
}

fn opBelongsToRequirement(self: ProgramPlan, op_index: u16, requirement_index: u16) bool {
    if (requirement_index >= self.requirements.len) return false;
    const requirement = self.requirements[requirement_index];
    const op_end = rangeEnd(requirement.first_op, requirement.op_count) orelse return false;
    return op_index >= requirement.first_op and op_index < op_end;
}

fn validateFunctionBodyParameterPrefix(
    comptime function: effect_ir.Function,
    comptime body: effect_ir.FunctionBody,
) PlanError!void {
    if (body.local_codecs.len < function.parameter_codecs.len) return error.InvalidProgramBodyShape;
    for (function.parameter_codecs, 0..) |codec, parameter_index| {
        if (body.local_codecs[parameter_index] != codec) return error.InvalidProgramBodyShape;
    }
}

fn symbolIndex(comptime program: effect_ir.Program, comptime symbol: effect_ir.SymbolRef) ?u16 {
    for (program.functions, 0..) |function, index| {
        if (function.symbol.eql(symbol)) return @intCast(index);
    }
    return null;
}

fn countBodyLocals(comptime program: program_frontend.LoweredOpenRowProgram) usize {
    var total: usize = 0;
    for (program.function_bodies) |body| total += body.local_codecs.len;
    return total;
}

fn countBodyCallArgs(comptime program: program_frontend.LoweredOpenRowProgram) usize {
    var total: usize = 0;
    for (program.function_bodies) |body| total += body.call_arg_locals.len;
    return total;
}

fn countBodyBlocks(comptime program: program_frontend.LoweredOpenRowProgram) usize {
    var total: usize = 0;
    for (program.function_bodies) |body| total += body.blocks.len;
    return total;
}

fn countBodyTerminators(comptime program: program_frontend.LoweredOpenRowProgram) usize {
    var total: usize = 0;
    for (program.function_bodies) |body| total += body.blocks.len;
    return total;
}

fn countBodyInstructions(comptime program: program_frontend.LoweredOpenRowProgram) usize {
    var total: usize = 0;
    for (program.function_bodies) |body| {
        for (body.blocks) |block| total += block.instructions.len;
    }
    return total;
}

fn invalidGeneratedPlan(err: ValidationError) noreturn {
    @compileError(switch (err) {
        error.EmptyFunctionSymbol => "runtime plan generator produced an empty function symbol",
        error.EmptyLabel => "runtime plan generator produced an empty label",
        error.EmptyOpName => "runtime plan generator produced an empty op name",
        error.EmptyOutputLabel => "runtime plan generator produced an empty output label",
        error.EmptyProgram => "runtime plan generator produced an empty program",
        error.EmptyRequirementLabel => "runtime plan generator produced an empty requirement label",
        error.InvalidCallHelperArgSpan => "runtime plan generator produced an invalid helper call argument span",
        error.InvalidCallHelperTarget => "runtime plan generator produced an out-of-range helper target",
        error.InvalidCallOpTarget => "runtime plan generator produced an out-of-range or foreign-row op target",
        error.InvalidBlockInstructionSpan => "runtime plan generator produced an invalid block instruction span",
        error.InvalidBlockTerminatorIndex => "runtime plan generator produced an invalid block terminator index",
        error.InvalidEntryIndex => "runtime plan generator produced an invalid entry index",
        error.InvalidFunctionBlockSpan => "runtime plan generator produced an invalid function block span",
        error.InvalidFunctionEntryBlock => "runtime plan generator produced an invalid function entry block",
        error.InvalidFunctionInstructionSpan => "runtime plan generator produced an invalid function instruction span",
        error.InvalidFunctionLocalSpan => "runtime plan generator produced an invalid function local span",
        error.InvalidFunctionOutputSpan => "runtime plan generator produced an invalid function output span",
        error.InvalidFunctionRequirementSpan => "runtime plan generator produced an invalid function requirement span",
        error.InvalidInstructionLocalIndex => "runtime plan generator produced an instruction with an out-of-range function-local reference",
        error.InvalidAfterHookMode => "runtime plan generator marked an abort op as requiring an after hook",
        error.InvalidOpRequirementIndex => "runtime plan generator produced an op with an invalid requirement index",
        error.InvalidOpRequirementOwnership => "runtime plan generator produced an op whose requirement index does not own its op span",
        error.InvalidRequirementOpSpan => "runtime plan generator produced an invalid requirement op span",
        error.InvalidReturnValueIndex => "runtime plan generator produced a return instruction with a non-zero index",
        error.InvalidTerminatorInstruction => "runtime plan generator produced a block terminator without its required producer instruction",
        error.InvalidTerminatorTarget => "runtime plan generator produced an invalid block terminator target",
        error.UnsupportedSchemaVersion => "runtime plan generator produced an unsupported schema version",
    });
}

const RowOnlyFunctionSynthesis = struct {
    helper_call_count: usize,
    forwarded_arg_count: usize,
    local_count: usize,
    value_result_local: ?u16,
    return_local: ?u16,
    value_result_codec: ?ValueCodec,
};

fn validateRowOnlyCallGraph(comptime program: effect_ir.Program) PlanError!void {
    var successors: [program.functions.len]?usize = [_]?usize{null} ** program.functions.len;
    for (program.call_edges) |edge| {
        const caller_index = symbolIndex(program, edge.caller) orelse return error.UnknownSymbol;
        const callee_index = symbolIndex(program, edge.callee) orelse return error.UnknownSymbol;
        if (successors[caller_index] != null) return error.InvalidProgramBodyShape;
        successors[caller_index] = callee_index;
    }

    for (program.functions, 0..) |_, start_index| {
        var visited: [program.functions.len]bool = [_]bool{false} ** program.functions.len;
        var current_index: ?usize = start_index;
        while (current_index) |index| {
            if (visited[index]) return error.InvalidProgramBodyShape;
            visited[index] = true;
            current_index = successors[index];
        }
    }
}

fn rowOnlyFunctionSynthesis(
    comptime program: effect_ir.Program,
    comptime function_index: usize,
) PlanError!RowOnlyFunctionSynthesis {
    const function = program.functions[function_index];
    const function_value_codec: ?ValueCodec = if (function.ValueType == void)
        null
    else
        try valueCodecFromEffectType(function.ValueType);

    var helper_call_count: usize = 0;
    var forwarded_arg_count: usize = 0;
    var value_returning_helper_count: usize = 0;
    var value_result_codec: ?ValueCodec = null;
    for (program.call_edges) |edge| {
        if (!edge.caller.eql(function.symbol)) continue;
        helper_call_count += 1;

        const callee_index = symbolIndex(program, edge.callee) orelse return error.UnknownSymbol;
        const callee = program.functions[callee_index];
        if (callee.parameter_codecs.len > function.parameter_codecs.len) return error.InvalidProgramBodyShape;
        for (callee.parameter_codecs, 0..) |codec, parameter_index| {
            if (function.parameter_codecs[parameter_index] != codec) return error.InvalidProgramBodyShape;
        }
        forwarded_arg_count += callee.parameter_codecs.len;

        if (callee.ValueType == void) continue;
        value_returning_helper_count += 1;
        const callee_value_codec = try valueCodecFromEffectType(callee.ValueType);
        if (value_result_codec == null) {
            value_result_codec = callee_value_codec;
        } else if (value_result_codec.? != callee_value_codec) {
            return error.InvalidProgramBodyShape;
        }
    }

    const value_result_local: ?u16 = if (value_result_codec == null)
        null
    else
        @intCast(function.parameter_codecs.len);
    const local_count = function.parameter_codecs.len + @intFromBool(value_result_local != null);
    const return_local: ?u16 = if (function_value_codec == null) blk: {
        break :blk null;
    } else if (value_result_local) |local_id| blk: {
        if (value_returning_helper_count > 1) return error.InvalidProgramBodyShape;
        if (value_result_codec.? != function_value_codec.?) return error.InvalidProgramBodyShape;
        break :blk local_id;
    } else blk: {
        if (function.parameter_codecs.len != 1) return error.InvalidProgramBodyShape;
        if (codecFromEffectIrBody(function.parameter_codecs[0]) != function_value_codec.?) {
            return error.InvalidProgramBodyShape;
        }
        break :blk 0;
    };

    return .{
        .helper_call_count = helper_call_count,
        .forwarded_arg_count = forwarded_arg_count,
        .local_count = local_count,
        .value_result_local = value_result_local,
        .return_local = return_local,
        .value_result_codec = value_result_codec,
    };
}

/// Compute a stable hash for the full normalized IR program identity.
pub fn irHashForProgram(comptime program: effect_ir.Program) PlanError!u64 {
    if (program.entry_index >= program.functions.len) return error.UnknownSymbol;
    if (program.function_bodies.len != 0 and program.function_bodies.len != program.functions.len) {
        return error.InvalidProgramBodyShape;
    }
    const symbols = comptime blk: {
        var buffer: [program.functions.len]effect_ir.SymbolRef = undefined;
        for (program.functions, 0..) |function, index| {
            buffer[index] = function.symbol;
        }
        break :blk buffer;
    };

    try effect_ir.validateGraph(.{
        .symbols = &symbols,
        .edges = program.call_edges,
    });

    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.asBytes(&program.entry_index));
    for (program.functions) |function| {
        const digest = try effect_ir.rowDigest(function.row, function.outputs);
        hashBytes(&hasher, function.symbol.module_path);
        hashBytes(&hasher, function.symbol.symbol_name);
        for (function.parameter_codecs) |codec| hashBytes(&hasher, @tagName(codec));
        hashBytes(&hasher, @typeName(function.ValueType));
        hasher.update(std.mem.asBytes(&digest.hash));
        hasher.update(std.mem.asBytes(&digest.requirement_count));
        hasher.update(std.mem.asBytes(&digest.op_count));
        hasher.update(std.mem.asBytes(&digest.output_count));
    }
    for (program.call_edges) |edge| {
        hashBytes(&hasher, edge.caller.module_path);
        hashBytes(&hasher, edge.caller.symbol_name);
        hashBytes(&hasher, edge.callee.module_path);
        hashBytes(&hasher, edge.callee.symbol_name);
    }
    for (program.function_bodies) |body| {
        for (body.local_codecs) |codec| hashBytes(&hasher, @tagName(codec));
        for (body.call_arg_locals) |local_id| hasher.update(std.mem.asBytes(&local_id));
        hasher.update(std.mem.asBytes(&body.entry_block));
        for (body.blocks) |block| {
            for (block.instructions) |instruction| {
                hashBytes(&hasher, @tagName(instruction.kind));
                hasher.update(std.mem.asBytes(&instruction.dst));
                hasher.update(std.mem.asBytes(&instruction.operand));
                hasher.update(std.mem.asBytes(&instruction.aux));
                hashBytes(&hasher, instruction.string_literal);
            }
            hashBytes(&hasher, @tagName(block.terminator.kind));
            hasher.update(std.mem.asBytes(&block.terminator.primary));
            hasher.update(std.mem.asBytes(&block.terminator.secondary));
        }
    }
    return hasher.final();
}

/// Lower one comptime effect-ir program into a runtime-owned executable plan shape.
pub fn planFromProgram(comptime label: []const u8, comptime program: effect_ir.Program) PlanError!ProgramPlan {
    if (program.functions.len == 0) return error.EmptyProgram;
    if (program.entry_index >= program.functions.len) return error.UnknownSymbol;
    if (program.function_bodies.len != 0) {
        if (program.function_bodies.len != program.functions.len) return error.InvalidProgramBodyShape;
        return try planFromOpenRowProgram(label, .{
            .entry_index = program.entry_index,
            .functions = program.functions,
            .call_edges = program.call_edges,
            .function_bodies = program.function_bodies,
        });
    }

    const symbols = comptime blk: {
        var buffer: [program.functions.len]effect_ir.SymbolRef = undefined;
        for (program.functions, 0..) |function, index| {
            buffer[index] = function.symbol;
        }
        break :blk buffer;
    };
    try effect_ir.validateGraph(.{
        .symbols = &symbols,
        .edges = program.call_edges,
    });
    try validateRowOnlyCallGraph(program);

    const requirement_total = comptime blk: {
        var total: usize = 0;
        for (program.functions) |function| total += function.row.requirements.len;
        break :blk total;
    };
    const op_total = comptime blk: {
        var total: usize = 0;
        for (program.functions) |function| {
            for (function.row.requirements) |requirement| total += requirement.ops.len;
        }
        break :blk total;
    };
    const output_total = comptime blk: {
        var total: usize = 0;
        for (program.functions) |function| total += function.outputs.len;
        break :blk total;
    };
    const local_total = comptime blk: {
        var total: usize = 0;
        for (program.functions, 0..) |_, function_index| {
            total += (try rowOnlyFunctionSynthesis(program, function_index)).local_count;
        }
        break :blk total;
    };
    const call_arg_total = comptime blk: {
        var total: usize = 0;
        for (program.functions, 0..) |_, function_index| {
            total += (try rowOnlyFunctionSynthesis(program, function_index)).forwarded_arg_count;
        }
        break :blk total;
    };
    const instruction_total = comptime blk: {
        var total: usize = 0;
        for (program.functions, 0..) |_, function_index| {
            const synthesis = try rowOnlyFunctionSynthesis(program, function_index);
            total += synthesis.helper_call_count + @intFromBool(synthesis.return_local != null);
        }
        break :blk total;
    };
    const ir_hash = try irHashForProgram(program);

    const functions = comptime blk: {
        var buf: [program.functions.len]FunctionPlan = undefined;
        var requirement_index: u16 = 0;
        var output_index: u16 = 0;
        var local_index: u16 = 0;
        var instruction_index: u16 = 0;
        for (program.functions, 0..) |function, index| {
            const synthesis = try rowOnlyFunctionSynthesis(program, index);
            buf[index] = .{
                .symbol_name = function.symbol.symbol_name,
                .value_codec = try valueCodecFromEffectType(function.ValueType),
                .parameter_count = @intCast(function.parameter_codecs.len),
                .first_requirement = requirement_index,
                .requirement_count = @intCast(function.row.requirements.len),
                .first_output = output_index,
                .output_count = @intCast(function.outputs.len),
                .first_local = local_index,
                .local_count = @intCast(synthesis.local_count),
                .first_block = @intCast(index),
                .block_count = 1,
                .first_instruction = instruction_index,
                .instruction_count = @intCast(synthesis.helper_call_count + @intFromBool(synthesis.return_local != null)),
            };
            requirement_index += @intCast(function.row.requirements.len);
            output_index += @intCast(function.outputs.len);
            local_index += @intCast(synthesis.local_count);
            instruction_index += @intCast(synthesis.helper_call_count + @intFromBool(synthesis.return_local != null));
        }
        break :blk buf;
    };

    const requirements = comptime blk: {
        var buf: [requirement_total]RequirementPlan = undefined;
        var requirement_index: usize = 0;
        var op_index: u16 = 0;
        for (program.functions) |function| {
            for (function.row.requirements) |requirement| {
                buf[requirement_index] = .{
                    .label = requirement.label,
                    .first_op = op_index,
                    .op_count = @intCast(requirement.ops.len),
                };
                op_index += @intCast(requirement.ops.len);
                requirement_index += 1;
            }
        }
        break :blk buf;
    };

    const ops = comptime blk: {
        var buf: [op_total]OpPlan = undefined;
        var op_index: usize = 0;
        var requirement_index: u16 = 0;
        for (program.functions) |function| {
            for (function.row.requirements) |requirement| {
                for (requirement.ops) |op| {
                    buf[op_index] = .{
                        .requirement_index = requirement_index,
                        .op_name = op.op_name,
                        .mode = controlModeFromIr(op.mode),
                        .payload_codec = try codecForType(op.PayloadType),
                        .resume_codec = try codecForType(op.ResumeType),
                        .has_after = op.has_after,
                    };
                    op_index += 1;
                }
                requirement_index += 1;
            }
        }
        break :blk buf;
    };

    const outputs = comptime blk: {
        var buf: [output_total]OutputPlan = undefined;
        var output_index: usize = 0;
        for (program.functions) |function| {
            for (function.outputs) |output| {
                buf[output_index] = .{
                    .label = output.label,
                    .codec = try codecForType(output.OutputType),
                };
                output_index += 1;
            }
        }
        break :blk buf;
    };

    const locals = comptime blk: {
        var buf: [local_total]LocalPlan = undefined;
        var local_index: usize = 0;
        for (program.functions, 0..) |function, function_index| {
            for (function.parameter_codecs) |codec| {
                buf[local_index] = .{ .codec = codecFromEffectIrBody(codec) };
                local_index += 1;
            }
            const synthesis = try rowOnlyFunctionSynthesis(program, function_index);
            if (synthesis.value_result_codec) |codec| {
                buf[local_index] = .{ .codec = codec };
                local_index += 1;
            }
        }
        break :blk buf;
    };

    const call_args = comptime blk: {
        var buf: [call_arg_total]u16 = undefined;
        var call_arg_index: usize = 0;
        for (program.functions) |function| {
            for (program.call_edges) |edge| {
                if (!edge.caller.eql(function.symbol)) continue;
                const callee_index = symbolIndex(program, edge.callee) orelse return error.UnknownSymbol;
                const callee = program.functions[callee_index];
                for (callee.parameter_codecs, 0..) |_, parameter_index| {
                    buf[call_arg_index] = @intCast(parameter_index);
                    call_arg_index += 1;
                }
            }
        }
        break :blk buf;
    };

    const blocks = comptime blk: {
        var buf: [program.functions.len]BlockPlan = undefined;
        for (functions, 0..) |function, index| {
            buf[index] = .{
                .first_instruction = function.first_instruction,
                .instruction_count = function.instruction_count,
                .terminator_index = @intCast(index),
            };
        }
        break :blk buf;
    };

    const terminators = comptime blk: {
        var buf: [program.functions.len]Terminator = undefined;
        for (&buf, functions) |*terminator, function| {
            terminator.* = .{
                .kind = if (function.value_codec == .unit) .return_unit else .return_value,
                .primary = 0,
                .secondary = 0,
            };
        }
        break :blk buf;
    };

    const instructions = comptime blk: {
        var buf: [instruction_total]Instruction = undefined;
        var instruction_index: usize = 0;
        var call_arg_base: u16 = 0;
        for (program.functions, 0..) |function, function_index| {
            const synthesis = try rowOnlyFunctionSynthesis(program, function_index);
            for (program.call_edges) |edge| {
                if (!edge.caller.eql(function.symbol)) continue;
                const callee_index = symbolIndex(program, edge.callee) orelse return error.UnknownSymbol;
                const callee = program.functions[callee_index];
                buf[instruction_index] = .{
                    .kind = .call_helper,
                    .dst = if (callee.ValueType == void)
                        0
                    else
                        synthesis.value_result_local orelse return error.InvalidProgramBodyShape,
                    .operand = callee_index,
                    .aux = call_arg_base,
                    .string_literal = "",
                };
                instruction_index += 1;
                call_arg_base += @intCast(callee.parameter_codecs.len);
            }
            if (synthesis.return_local) |return_local| {
                buf[instruction_index] = .{
                    .kind = .return_value,
                    .dst = 0,
                    .operand = return_local,
                    .aux = 0,
                    .string_literal = "",
                };
                instruction_index += 1;
            }
        }
        break :blk buf;
    };

    const plan: ProgramPlan = .{
        .label = label,
        .ir_hash = ir_hash,
        .entry_index = program.entry_index,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &outputs,
        .locals = &locals,
        .call_args = &call_args,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    };
    if (plan.validate()) {
        // The generated payload is internally consistent.
    } else |err| invalidGeneratedPlan(err);
    return plan;
}

/// Lower one body-bearing open-row program into a runtime-owned executable plan shape.
pub fn planFromOpenRowProgram(
    comptime label: []const u8,
    comptime program: program_frontend.LoweredOpenRowProgram,
) PlanError!ProgramPlan {
    if (program.function_bodies.len == 0) {
        return try planFromProgram(label, program.asEffectProgram());
    }
    for (program.functions, program.function_bodies) |function, body| {
        try validateFunctionBodyParameterPrefix(function, body);
    }
    const summary_program = program.asEffectProgram();
    const requirement_total = comptime blk: {
        var total: usize = 0;
        for (program.functions) |function| total += function.row.requirements.len;
        break :blk total;
    };
    const op_total = comptime blk: {
        var total: usize = 0;
        for (program.functions) |function| {
            for (function.row.requirements) |requirement| total += requirement.ops.len;
        }
        break :blk total;
    };
    const output_total = comptime blk: {
        var total: usize = 0;
        for (program.functions) |function| total += function.outputs.len;
        break :blk total;
    };
    const local_total = countBodyLocals(program);
    const call_arg_total = countBodyCallArgs(program);
    const block_total = countBodyBlocks(program);
    const terminator_total = countBodyTerminators(program);
    const instruction_total = countBodyInstructions(program);
    const ir_hash = try irHashForProgram(summary_program);

    const functions = comptime blk: {
        var buf: [program.functions.len]FunctionPlan = undefined;
        var requirement_index: u16 = 0;
        var output_index: u16 = 0;
        var local_index: u16 = 0;
        var block_index: u16 = 0;
        var instruction_index: u16 = 0;
        for (program.functions, 0..) |function, index| {
            const body = program.function_bodies[index];
            const instruction_count = count: {
                var total: usize = 0;
                for (body.blocks) |block| total += block.instructions.len;
                break :count total;
            };
            buf[index] = .{
                .symbol_name = function.symbol.symbol_name,
                .value_codec = try valueCodecFromEffectType(function.ValueType),
                .parameter_count = @intCast(function.parameter_codecs.len),
                .first_requirement = requirement_index,
                .requirement_count = @intCast(function.row.requirements.len),
                .first_output = output_index,
                .output_count = @intCast(function.outputs.len),
                .first_local = local_index,
                .local_count = @intCast(body.local_codecs.len),
                .first_block = block_index,
                .entry_block = body.entry_block,
                .block_count = @intCast(body.blocks.len),
                .first_instruction = instruction_index,
                .instruction_count = @intCast(instruction_count),
            };
            requirement_index += @intCast(function.row.requirements.len);
            output_index += @intCast(function.outputs.len);
            local_index += @intCast(body.local_codecs.len);
            block_index += @intCast(body.blocks.len);
            instruction_index += @intCast(instruction_count);
        }
        break :blk buf;
    };

    const requirements = comptime blk: {
        var buf: [requirement_total]RequirementPlan = undefined;
        var requirement_index: usize = 0;
        var op_index: u16 = 0;
        for (program.functions) |function| {
            for (function.row.requirements) |requirement| {
                buf[requirement_index] = .{
                    .label = requirement.label,
                    .first_op = op_index,
                    .op_count = @intCast(requirement.ops.len),
                };
                op_index += @intCast(requirement.ops.len);
                requirement_index += 1;
            }
        }
        break :blk buf;
    };

    const ops = comptime blk: {
        var buf: [op_total]OpPlan = undefined;
        var op_index: usize = 0;
        var requirement_index: u16 = 0;
        for (program.functions) |function| {
            for (function.row.requirements) |requirement| {
                for (requirement.ops) |op| {
                    buf[op_index] = .{
                        .requirement_index = requirement_index,
                        .op_name = op.op_name,
                        .mode = controlModeFromIr(op.mode),
                        .payload_codec = try codecForType(op.PayloadType),
                        .resume_codec = try codecForType(op.ResumeType),
                        .has_after = op.has_after,
                    };
                    op_index += 1;
                }
                requirement_index += 1;
            }
        }
        break :blk buf;
    };

    const outputs = comptime blk: {
        var buf: [output_total]OutputPlan = undefined;
        var output_index: usize = 0;
        for (program.functions) |function| {
            for (function.outputs) |output| {
                buf[output_index] = .{
                    .label = output.label,
                    .codec = try codecForType(output.OutputType),
                };
                output_index += 1;
            }
        }
        break :blk buf;
    };

    const locals = comptime blk: {
        var buf: [local_total]LocalPlan = undefined;
        var local_index: usize = 0;
        for (program.function_bodies) |body| {
            for (body.local_codecs) |codec| {
                buf[local_index] = .{ .codec = codecFromEffectIrBody(codec) };
                local_index += 1;
            }
        }
        break :blk buf;
    };

    const call_args = comptime blk: {
        var buf: [call_arg_total]u16 = undefined;
        var call_arg_index: usize = 0;
        for (program.function_bodies) |body| {
            for (body.call_arg_locals) |local_id| {
                buf[call_arg_index] = local_id;
                call_arg_index += 1;
            }
        }
        break :blk buf;
    };

    const blocks = comptime blk: {
        var buf: [block_total]BlockPlan = undefined;
        var block_index: usize = 0;
        var instruction_index: u16 = 0;
        var terminator_index: u16 = 0;
        for (program.function_bodies) |body| {
            for (body.blocks) |block| {
                buf[block_index] = .{
                    .first_instruction = instruction_index,
                    .instruction_count = @intCast(block.instructions.len),
                    .terminator_index = terminator_index,
                };
                instruction_index += @intCast(block.instructions.len);
                terminator_index += 1;
                block_index += 1;
            }
        }
        break :blk buf;
    };

    const terminators = comptime blk: {
        var buf: [terminator_total]Terminator = undefined;
        var terminator_index: usize = 0;
        var block_base: u16 = 0;
        for (program.function_bodies) |body| {
            for (body.blocks) |block| {
                buf[terminator_index] = .{
                    .kind = terminatorKindFromEffectIrBody(block.terminator.kind),
                    .primary = if (block.terminator.kind == .jump or block.terminator.kind == .branch_if)
                        block_base + block.terminator.primary
                    else
                        block.terminator.primary,
                    .secondary = if (block.terminator.kind == .branch_if)
                        block_base + block.terminator.secondary
                    else
                        block.terminator.secondary,
                };
                terminator_index += 1;
            }
            block_base += @intCast(body.blocks.len);
        }
        break :blk buf;
    };

    const instructions = comptime blk: {
        var buf: [instruction_total]Instruction = undefined;
        var instruction_index: usize = 0;
        var call_arg_base: u16 = 0;
        for (program.function_bodies) |body| {
            for (body.blocks) |block| {
                for (block.instructions) |instruction| {
                    if (instruction.kind == .call_helper and instruction.operand >= program.functions.len) {
                        invalidGeneratedPlan(error.InvalidCallHelperTarget);
                    }
                    const target_parameter_count: u16 = if (instruction.kind == .call_helper)
                        @intCast(program.functions[instruction.operand].parameter_codecs.len)
                    else
                        0;
                    const target_returns_value = instruction.kind == .call_helper and
                        program.functions[instruction.operand].ValueType != void;
                    buf[instruction_index] = .{
                        .kind = instructionKindFromEffectIrBody(instruction.kind),
                        .dst = if (instruction.kind == .call_helper and !target_returns_value)
                            std.math.maxInt(u16)
                        else
                            instruction.dst,
                        .operand = instruction.operand,
                        .aux = if (instruction.kind != .call_helper)
                            instruction.aux
                        else if (target_parameter_count == 0)
                            std.math.maxInt(u16)
                        else
                            call_arg_base + instruction.aux,
                        .string_literal = instruction.string_literal,
                    };
                    instruction_index += 1;
                }
            }
            call_arg_base += @intCast(body.call_arg_locals.len);
        }
        break :blk buf;
    };

    const plan: ProgramPlan = .{
        .label = label,
        .ir_hash = ir_hash,
        .entry_index = @intCast(program.entry_index),
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &outputs,
        .locals = &locals,
        .call_args = &call_args,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    };
    if (plan.validate()) {
        // The generated payload is internally consistent.
    } else |err| invalidGeneratedPlan(err);
    return plan;
}

test "codecForType covers the retained public scalar and string shapes" {
    try std.testing.expectEqual(ValueCodec.unit, try codecForType(void));
    try std.testing.expectEqual(ValueCodec.bool, try codecForType(bool));
    try std.testing.expectEqual(ValueCodec.i32, try codecForType(i32));
    try std.testing.expectEqual(ValueCodec.usize, try codecForType(usize));
    try std.testing.expectEqual(ValueCodec.string, try codecForType([]const u8));
    try std.testing.expectEqual(ValueCodec.string_list, try codecForType([][]const u8));
    try std.testing.expect(!hasPayload(.unit));
    try std.testing.expect(hasPayload(.string));
}

test "planFromProgram lowers one simple state-writer IR shell into a runtime-owned plan" {
    comptime {
        @setEvalBranchQuota(20_000);
    }
    const row = effect_ir.mergeRows(.{
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
    });
    const program = effect_ir.Program{
        .functions = &.{.{
            .symbol = .{
                .module_path = "examples/open_row_state_writer.zig",
                .symbol_name = "runBody",
            },
            .row = row,
            .outputs = &.{
                .{ .label = "state", .OutputType = i32 },
                .{ .label = "writer", .OutputType = [][]const u8 },
            },
        }},
        .call_edges = &.{},
    };
    const plan = comptime try planFromProgram("example.open_row_state_writer", program);

    try std.testing.expectEqual(@as(u16, 0), plan.entry_index);
    try std.testing.expectEqual(@as(usize, 1), plan.functions.len);
    try std.testing.expectEqual(@as(usize, 2), plan.requirements.len);
    try std.testing.expectEqual(@as(usize, 3), plan.ops.len);
    try std.testing.expectEqual(@as(usize, 2), plan.outputs.len);
    try std.testing.expectEqual(@as(usize, 0), plan.locals.len);
    try std.testing.expectEqual(@as(usize, 1), plan.blocks.len);
    try std.testing.expectEqual(@as(usize, 1), plan.terminators.len);
    try std.testing.expectEqual(@as(usize, 0), plan.instructions.len);
    try std.testing.expectEqual(TerminatorKind.return_unit, plan.terminators[0].kind);
    try plan.validate();
}

test "planFromProgram hashes the whole program and makes helper calls self-contained" {
    comptime {
        @setEvalBranchQuota(20_000);
    }
    const shared_row = effect_ir.rowFromSpec(.{
        .state = .{
            .get = effect_ir.Transform(void, i32),
        },
    });
    const helper_symbol = effect_ir.SymbolRef{
        .module_path = "examples/workflow.zig",
        .symbol_name = "helper",
    };
    const root_symbol = effect_ir.SymbolRef{
        .module_path = "examples/workflow.zig",
        .symbol_name = "root",
    };
    const program = effect_ir.Program{
        .functions = &.{
            .{
                .symbol = root_symbol,
                .row = shared_row,
                .outputs = &.{.{ .label = "state", .OutputType = i32 }},
            },
            .{
                .symbol = helper_symbol,
                .row = shared_row,
                .outputs = &.{.{ .label = "state", .OutputType = i32 }},
            },
        },
        .call_edges = &.{
            .{
                .caller = root_symbol,
                .callee = helper_symbol,
            },
        },
    };

    const plan = comptime try planFromProgram("example.workflow", program);
    const first_row_only_hash = try effect_ir.rowDigest(program.functions[0].row, program.functions[0].outputs);

    try std.testing.expect(plan.ir_hash != first_row_only_hash.hash);
    try std.testing.expectEqual(@as(usize, 0), plan.locals.len);
    try std.testing.expectEqual(@as(usize, 2), plan.blocks.len);
    try std.testing.expectEqual(@as(usize, 2), plan.terminators.len);
    try std.testing.expectEqual(@as(usize, 1), plan.instructions.len);
    try std.testing.expectEqual(@as(u16, 0), plan.functions[0].first_instruction);
    try std.testing.expectEqual(@as(u16, 1), plan.functions[0].instruction_count);
    try std.testing.expectEqual(@as(u16, 0), plan.functions[0].first_block);
    try std.testing.expectEqual(@as(u16, 1), plan.functions[0].block_count);
    try std.testing.expectEqual(@as(u16, 1), plan.functions[1].first_instruction);
    try std.testing.expectEqual(@as(u16, 0), plan.functions[1].instruction_count);
    try std.testing.expectEqual(InstructionKind.call_helper, plan.instructions[0].kind);
    try std.testing.expectEqual(@as(u16, 1), plan.instructions[0].operand);
    try std.testing.expectEqual(@as(u16, 0), plan.instructions[0].dst);
    try std.testing.expectEqual(@as(u16, 0), plan.instructions[0].aux);
    try std.testing.expectEqual(TerminatorKind.return_unit, plan.terminators[0].kind);
    try std.testing.expectEqual(TerminatorKind.return_unit, plan.terminators[1].kind);
    try plan.validate();
}

test "planFromOpenRowProgram preserves row-only helper call plans" {
    comptime {
        @setEvalBranchQuota(20_000);
    }
    const shared_row = effect_ir.rowFromSpec(.{
        .state = .{
            .get = effect_ir.Transform(void, i32),
        },
    });
    const helper_symbol = effect_ir.SymbolRef{
        .module_path = "examples/workflow.zig",
        .symbol_name = "helper",
    };
    const root_symbol = effect_ir.SymbolRef{
        .module_path = "examples/workflow.zig",
        .symbol_name = "root",
    };
    const lowered = program_frontend.LoweredOpenRowProgram{
        .entry_index = 0,
        .functions = &.{
            .{
                .symbol = root_symbol,
                .row = shared_row,
                .outputs = &.{.{ .label = "state", .OutputType = i32 }},
            },
            .{
                .symbol = helper_symbol,
                .row = shared_row,
                .outputs = &.{.{ .label = "state", .OutputType = i32 }},
            },
        },
        .call_edges = &.{.{
            .caller = root_symbol,
            .callee = helper_symbol,
        }},
        .function_bodies = &.{},
    };

    const row_only_plan = comptime try planFromProgram("example.workflow", lowered.asEffectProgram());
    const open_row_plan = comptime try planFromOpenRowProgram("example.workflow", lowered);

    try std.testing.expectEqualDeep(row_only_plan, open_row_plan);
}

test "ProgramPlan.validate rejects out-of-range helper targets" {
    const plan = ProgramPlan{
        .label = "invalid.helper_target",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &.{.{
            .first_instruction = 0,
            .instruction_count = 1,
            .terminator_index = 0,
        }},
        .terminators = &.{.{
            .kind = .return_value,
        }},
        .instructions = &.{.{
            .kind = .call_helper,
            .dst = 0,
            .operand = 1,
            .aux = 0,
        }},
    };

    try std.testing.expectError(error.InvalidCallHelperTarget, plan.validate());
}

test "ProgramPlan.validate rejects out-of-range helper instruction locals" {
    const base_plan = ProgramPlan{
        .label = "invalid.helper_locals",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &.{.{
            .first_instruction = 0,
            .instruction_count = 1,
            .terminator_index = 0,
        }},
        .terminators = &.{.{
            .kind = .return_unit,
        }},
        .instructions = undefined,
    };

    inline for ([_]Instruction{
        .{ .kind = .add_const_i32, .dst = 1, .operand = 0, .aux = 1 },
        .{ .kind = .compare_eq_zero, .dst = 0, .operand = 1 },
        .{ .kind = .const_i32, .dst = 1, .operand = 1 },
        .{ .kind = .sub_one, .dst = 0, .operand = 1 },
        .{ .kind = .return_value, .operand = 1 },
    }) |instruction| {
        const plan = ProgramPlan{
            .label = base_plan.label,
            .ir_hash = base_plan.ir_hash,
            .entry_index = base_plan.entry_index,
            .functions = base_plan.functions,
            .requirements = base_plan.requirements,
            .ops = base_plan.ops,
            .outputs = base_plan.outputs,
            .locals = base_plan.locals,
            .blocks = base_plan.blocks,
            .terminators = base_plan.terminators,
            .instructions = &.{instruction},
        };

        try std.testing.expectError(error.InvalidInstructionLocalIndex, plan.validate());
    }
}

test "ProgramPlan.validate rejects helper call arguments outside the owning function locals" {
    const plan = ProgramPlan{
        .label = "invalid.helper_call_args",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{
            .{
                .symbol_name = "root",
                .parameter_count = 0,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 1,
                .first_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 1,
            },
            .{
                .symbol_name = "helper",
                .parameter_count = 1,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 1,
                .local_count = 1,
                .first_block = 1,
                .block_count = 1,
                .first_instruction = 1,
                .instruction_count = 0,
            },
        },
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{
            .{ .codec = .i32 },
            .{ .codec = .i32 },
        },
        .call_args = &.{1},
        .blocks = &.{
            .{
                .first_instruction = 0,
                .instruction_count = 1,
                .terminator_index = 0,
            },
            .{
                .first_instruction = 1,
                .instruction_count = 0,
                .terminator_index = 1,
            },
        },
        .terminators = &.{
            .{ .kind = .return_unit },
            .{ .kind = .return_unit },
        },
        .instructions = &.{.{
            .kind = .call_helper,
            .operand = 1,
            .aux = 0,
        }},
    };

    try std.testing.expectError(error.InvalidCallHelperArgSpan, plan.validate());
}

test "ProgramPlan.validate rejects functions without owned blocks" {
    const plan = ProgramPlan{
        .label = "invalid.blockless_function",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
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
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &.{},
        .terminators = &.{},
        .instructions = &.{},
    };

    try std.testing.expectError(error.InvalidFunctionEntryBlock, plan.validate());
}

test "upgradeLegacyProgramPlan preserves schema-1 function metadata when present" {
    var plan = ProgramPlan{
        .schema_version = 1,
        .label = "legacy.schema1.metadata",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .value_codec = .i32,
            .parameter_count = 2,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 1,
            .first_local = 0,
            .local_count = 3,
            .first_block = 0,
            .entry_block = 1,
            .block_count = 2,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{.{ .label = "result", .codec = .i32 }},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 }, .{ .codec = .i32 } },
        .call_args = &.{},
        .blocks = &.{
            .{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 },
            .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 1 },
        },
        .terminators = &.{
            .{ .kind = .jump, .primary = 1 },
            .{ .kind = .return_value },
        },
        .instructions = &.{.{ .kind = .return_value, .dst = 0, .operand = 2, .aux = 0 }},
    };

    try upgradeLegacyProgramPlan(std.testing.allocator, &plan);
    defer {
        std.testing.allocator.free(plan.functions);
        std.testing.allocator.free(plan.requirements);
        std.testing.allocator.free(plan.ops);
        std.testing.allocator.free(plan.outputs);
        std.testing.allocator.free(plan.locals);
        std.testing.allocator.free(plan.call_args);
        std.testing.allocator.free(plan.blocks);
        std.testing.allocator.free(plan.terminators);
        std.testing.allocator.free(plan.instructions);
    }

    try std.testing.expectEqual(ProgramPlan.current_schema_version, plan.schema_version);
    const function = plan.functions[0];
    try std.testing.expectEqual(ValueCodec.i32, function.value_codec);
    try std.testing.expectEqual(@as(u16, 2), function.parameter_count);
    try std.testing.expectEqual(@as(u16, 3), function.local_count);
    try std.testing.expectEqual(@as(u16, 1), function.entry_block);
    try std.testing.expectEqual(@as(usize, 3), plan.locals.len);
    try std.testing.expectEqual(@as(usize, 2), plan.blocks.len);
    try std.testing.expectEqual(TerminatorKind.return_value, plan.terminators[1].kind);
    try plan.validate();
}

test "ProgramPlan.validate rejects call_op payload locals outside the owning function locals" {
    const plan = ProgramPlan{
        .label = "invalid.call_op_payload_local",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{.{
            .label = "req",
            .first_op = 0,
            .op_count = 1,
        }},
        .ops = &.{.{
            .requirement_index = 0,
            .op_name = "call",
            .mode = .transform,
            .payload_codec = .i32,
            .resume_codec = .unit,
        }},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &.{.{
            .first_instruction = 0,
            .instruction_count = 1,
            .terminator_index = 0,
        }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{.{
            .kind = .call_op,
            .dst = 0,
            .operand = 0,
            .aux = 1,
        }},
    };

    try std.testing.expectError(error.InvalidInstructionLocalIndex, plan.validate());
}

test "ProgramPlan.validate rejects call_op targets outside the owning function row" {
    const plan = ProgramPlan{
        .label = "invalid.call_op_foreign_row",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{
            .{
                .symbol_name = "root",
                .first_requirement = 0,
                .requirement_count = 1,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 0,
                .first_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 0,
            },
            .{
                .symbol_name = "helper",
                .first_requirement = 1,
                .requirement_count = 1,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 1,
                .first_block = 1,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 1,
            },
        },
        .requirements = &.{
            .{
                .label = "state",
                .first_op = 0,
                .op_count = 1,
            },
            .{
                .label = "writer",
                .first_op = 1,
                .op_count = 1,
            },
        },
        .ops = &.{
            .{
                .requirement_index = 0,
                .op_name = "get",
                .mode = .transform,
                .payload_codec = .unit,
                .resume_codec = .i32,
            },
            .{
                .requirement_index = 1,
                .op_name = "tell",
                .mode = .transform,
                .payload_codec = .string,
                .resume_codec = .unit,
            },
        },
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &.{
            .{
                .first_instruction = 0,
                .instruction_count = 0,
                .terminator_index = 0,
            },
            .{
                .first_instruction = 0,
                .instruction_count = 1,
                .terminator_index = 1,
            },
        },
        .terminators = &.{
            .{ .kind = .return_unit },
            .{ .kind = .return_unit },
        },
        .instructions = &.{.{
            .kind = .call_op,
            .dst = 0,
            .operand = 0,
            .aux = std.math.maxInt(u16),
        }},
    };

    try std.testing.expectError(error.InvalidCallOpTarget, plan.validate());
}

test "ProgramPlan.validate rejects ops whose requirement index does not own their op span" {
    const plan = ProgramPlan{
        .label = "invalid.op_requirement_ownership",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .first_requirement = 0,
            .requirement_count = 2,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{
            .{
                .label = "first",
                .first_op = 0,
                .op_count = 1,
            },
            .{
                .label = "second",
                .first_op = 1,
                .op_count = 1,
            },
        },
        .ops = &.{
            .{
                .requirement_index = 0,
                .op_name = "load",
                .mode = .transform,
                .payload_codec = .unit,
                .resume_codec = .unit,
            },
            .{
                .requirement_index = 0,
                .op_name = "echo",
                .mode = .transform,
                .payload_codec = .unit,
                .resume_codec = .unit,
            },
        },
        .outputs = &.{},
        .locals = &.{},
        .blocks = &.{.{
            .first_instruction = 0,
            .instruction_count = 0,
            .terminator_index = 0,
        }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };

    try std.testing.expectError(error.InvalidOpRequirementOwnership, plan.validate());
}

test "ProgramPlan.validate rejects value-producing helper destinations outside the owning function locals" {
    const plan = ProgramPlan{
        .label = "invalid.helper_result_local",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{
            .{
                .symbol_name = "root",
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 0,
                .first_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 1,
            },
            .{
                .symbol_name = "helper",
                .value_codec = .i32,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 1,
                .first_block = 1,
                .block_count = 1,
                .first_instruction = 1,
                .instruction_count = 1,
            },
        },
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &.{
            .{
                .first_instruction = 0,
                .instruction_count = 1,
                .terminator_index = 0,
            },
            .{
                .first_instruction = 1,
                .instruction_count = 1,
                .terminator_index = 1,
            },
        },
        .terminators = &.{
            .{ .kind = .return_unit },
            .{ .kind = .return_value },
        },
        .instructions = &.{
            .{
                .kind = .call_helper,
                .dst = 0,
                .operand = 1,
                .aux = std.math.maxInt(u16),
            },
            .{
                .kind = .return_value,
                .operand = 0,
            },
        },
    };

    try std.testing.expectError(error.InvalidInstructionLocalIndex, plan.validate());
}

test "ProgramPlan.validate rejects value-producing op destinations outside the owning function locals" {
    const plan = ProgramPlan{
        .label = "invalid.call_op_result_local",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{.{
            .label = "req",
            .first_op = 0,
            .op_count = 1,
        }},
        .ops = &.{.{
            .requirement_index = 0,
            .op_name = "get",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .i32,
        }},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &.{.{
            .first_instruction = 0,
            .instruction_count = 1,
            .terminator_index = 0,
        }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{.{
            .kind = .call_op,
            .dst = 0,
            .operand = 0,
            .aux = std.math.maxInt(u16),
        }},
    };

    try std.testing.expectError(error.InvalidInstructionLocalIndex, plan.validate());
}

test "ProgramPlan.validate rejects const_string destinations outside the owning function locals" {
    const plan = ProgramPlan{
        .label = "invalid.const_string_local",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &.{.{
            .first_instruction = 0,
            .instruction_count = 1,
            .terminator_index = 0,
        }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{.{
            .kind = .const_string,
            .dst = 0,
            .string_literal = "persisted literal",
        }},
    };

    try std.testing.expectError(error.InvalidInstructionLocalIndex, plan.validate());
}

test "ProgramPlan.validate rejects terminator targets outside the owning function body" {
    const plan = ProgramPlan{
        .label = "invalid.foreign_block_target",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{
            .{
                .symbol_name = "root",
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 0,
                .first_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 0,
            },
            .{
                .symbol_name = "helper",
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 0,
                .first_block = 1,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 0,
            },
        },
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &.{
            .{
                .first_instruction = 0,
                .instruction_count = 0,
                .terminator_index = 0,
            },
            .{
                .first_instruction = 0,
                .instruction_count = 0,
                .terminator_index = 1,
            },
        },
        .terminators = &.{
            .{ .kind = .jump, .primary = 1 },
            .{ .kind = .return_unit },
        },
        .instructions = &.{},
    };

    try std.testing.expectError(error.InvalidTerminatorTarget, plan.validate());
}

test "ProgramPlan.validate rejects branch_if terminators without a trailing compare instruction" {
    const plan = ProgramPlan{
        .label = "invalid.branch_without_compare",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .block_count = 2,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &.{
            .{
                .first_instruction = 0,
                .instruction_count = 1,
                .terminator_index = 0,
            },
            .{
                .first_instruction = 1,
                .instruction_count = 0,
                .terminator_index = 1,
            },
        },
        .terminators = &.{
            .{ .kind = .branch_if, .primary = 1, .secondary = 1 },
            .{ .kind = .return_unit },
        },
        .instructions = &.{.{
            .kind = .const_i32,
            .dst = 0,
            .operand = 1,
        }},
    };

    try std.testing.expectError(error.InvalidTerminatorInstruction, plan.validate());
}

test "ProgramPlan.validate rejects return_value terminators without a return instruction" {
    const plan = ProgramPlan{
        .label = "invalid.return_without_instruction",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .value_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 1,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{.{ .label = "result", .codec = .i32 }},
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

    try std.testing.expectError(error.InvalidTerminatorInstruction, plan.validate());
}

test "ProgramPlan.validate rejects functions whose instruction span is not attached to owned blocks" {
    const zero_block_plan = ProgramPlan{
        .label = "invalid.unowned_instruction_span.zero_blocks",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .value_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 1,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .block_count = 0,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{.{ .label = "result", .codec = .i32 }},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &.{},
        .terminators = &.{},
        .instructions = &.{.{ .kind = .return_value, .operand = 0 }},
    };
    try std.testing.expectError(error.InvalidFunctionInstructionSpan, zero_block_plan.validate());

    const uncovered_instruction_plan = ProgramPlan{
        .label = "invalid.unowned_instruction_span.uncovered",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .value_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 1,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{.{ .label = "result", .codec = .i32 }},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &.{.{
            .first_instruction = 0,
            .instruction_count = 0,
            .terminator_index = 0,
        }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{.{ .kind = .return_value, .operand = 0 }},
    };
    try std.testing.expectError(error.InvalidFunctionInstructionSpan, uncovered_instruction_plan.validate());
}

test "ProgramPlan hash survives JSON roundtrip" {
    const plan = ProgramPlan{
        .label = "roundtrip",
        .ir_hash = 42,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 1,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
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
        .outputs = &.{.{
            .label = "writer",
            .codec = .string_list,
        }},
        .locals = &.{},
        .blocks = &.{.{
            .first_instruction = 0,
            .instruction_count = 1,
            .terminator_index = 0,
        }},
        .terminators = &.{.{
            .kind = .return_value,
        }},
        .instructions = &.{.{
            .kind = .return_value,
            .dst = 0,
            .operand = 0,
            .aux = 0,
        }},
    };

    const json = try std.json.Stringify.valueAlloc(std.testing.allocator, plan, .{});
    defer std.testing.allocator.free(json);

    const parsed = try std.json.parseFromSlice(ProgramPlan, std.testing.allocator, json, .{});
    defer parsed.deinit();

    try parsed.value.validate();
    try std.testing.expectEqual(plan.hash(), parsed.value.hash());
}
