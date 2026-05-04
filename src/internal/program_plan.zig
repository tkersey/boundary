// zlinter-disable no_undefined require_doc_comment require_exhaustive_enum_switch
const effect_ir = @import("effect_ir");
const program_frontend = @import("program_frontend");
const std = @import("std");

const source_path_compat_mode = @hasDecl(@import("root"), "source_path_compat_mode");
const nested_with_metadata_delimiter = "\x1f";
/// Maximum declared outputs accepted for one executable ProgramPlan function.
pub const max_validated_function_outputs = 4096;
const max_indexed_table_len = std.math.maxInt(u16) + 1;
const small_output_scan_limit = 8;

/// Serializable value codecs admitted by the first redesign wave.
///
/// Numeric tags are persisted in `Instruction.aux` for legacy
/// `call_nested_with` rows, so append new codecs without renumbering old tags.
pub const ValueCodec = enum(u8) {
    bool = 0,
    i32 = 1,
    product = 6,
    string = 2,
    string_list = 3,
    sum = 7,
    unit = 4,
    usize = 5,
};

/// Return whether this codec carries a runtime payload.
pub fn hasPayload(codec: ValueCodec) bool {
    return codec != .unit;
}

fn valueCodecNeedsSchema(codec: ValueCodec) bool {
    return switch (codec) {
        .product, .sum => true,
        else => false,
    };
}

/// One product field descriptor in the runtime-owned value-schema table.
pub const ValueFieldPlan = struct {
    name: []const u8,
    codec: ValueCodec,
    schema_index: ?u16 = null,
};

/// One sum variant descriptor in the runtime-owned value-schema table.
pub const ValueVariantPlan = struct {
    name: []const u8,
    codec: ValueCodec = .unit,
    schema_index: ?u16 = null,
};

/// One resolved value-codec reference, including schema identity for structured values.
pub const ValueRef = struct {
    codec: ValueCodec,
    schema_index: ?u16 = null,

    pub fn eql(self: @This(), other: @This()) bool {
        return self.codec == other.codec and self.schema_index == other.schema_index;
    }
};

/// One runtime-owned value schema for product and sum codecs.
pub const ValueSchemaPlan = struct {
    label: []const u8,
    codec: ValueCodec,
    first_field: u16 = 0,
    field_count: u16 = 0,
    first_variant: u16 = 0,
    variant_count: u16 = 0,
};

/// Runtime-owned control-mode tag for executable plan ops.
pub const ControlMode = enum {
    abort,
    choice,
    transform,
};

/// Lifecycle semantics carried by one requirement plan.
pub const RequirementLifecycleTag = enum {
    abort_catch,
    choice_policy,
    generated_family,
    plain_transform,
    reader_environment,
    resource_bracket,
    state_cell,
    writer_accumulator,
};

/// Output semantics carried by one requirement plan.
pub const RequirementOutputTag = enum {
    accumulator,
    custom_finalizer,
    final_state,
    none,
};

fn controlModeFromIr(mode: effect_ir.ControlMode) ControlMode {
    return switch (mode) {
        .abort => .abort,
        .choice => .choice,
        .transform => .transform,
    };
}

fn namedNestedWithMetadataIsComplete(encoded: []const u8) bool {
    var part_count: usize = 0;
    var start: usize = 0;
    var index: usize = 0;
    while (index <= encoded.len) : (index += 1) {
        const is_delimiter = index == encoded.len or std.mem.startsWith(u8, encoded[index..], nested_with_metadata_delimiter);
        if (!is_delimiter) continue;
        if (part_count >= 9 or start == index) return false;
        part_count += 1;
        if (index != encoded.len) {
            index += nested_with_metadata_delimiter.len - 1;
            start = index + 1;
        }
    }
    return part_count == 9;
}

/// One lowered output descriptor in the runtime-owned executable plan.
pub const OutputPlan = struct {
    label: []const u8,
    codec: ValueCodec,
    schema_index: ?u16 = null,
};

/// One lowered local slot descriptor in the runtime-owned executable plan.
pub const LocalPlan = struct {
    codec: ValueCodec,
    schema_index: ?u16 = null,
};

/// One lowered operation descriptor in the runtime-owned executable plan.
pub const OpPlan = struct {
    requirement_index: u16,
    op_name: []const u8,
    mode: ControlMode,
    payload_codec: ValueCodec,
    payload_schema_index: ?u16 = null,
    resume_codec: ValueCodec,
    resume_schema_index: ?u16 = null,
    has_after: bool = false,
};

/// One lowered requirement descriptor in the runtime-owned executable plan.
pub const RequirementPlan = struct {
    label: []const u8,
    first_op: u16,
    op_count: u16,
    lifecycle_tag: RequirementLifecycleTag = .plain_transform,
    output_tag: RequirementOutputTag = .none,
};

/// One lowered function descriptor in the runtime-owned executable plan.
pub const FunctionPlan = struct {
    symbol_name: []const u8,
    value_codec: ValueCodec = .unit,
    value_schema_index: ?u16 = null,
    result_codec: ?ValueCodec = null,
    result_schema_index: ?u16 = null,
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
    add_i32,
    call_helper,
    call_nested_with,
    call_op,
    compare_eq_zero,
    const_i32,
    const_string,
    const_usize,
    return_error,
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
    pub const current_schema_version: u32 = 8;

    schema_version: u32 = current_schema_version,
    label: []const u8,
    ir_hash: u64,
    entry_index: u16,
    functions: []const FunctionPlan,
    requirements: []const RequirementPlan,
    ops: []const OpPlan,
    outputs: []const OutputPlan,
    value_schemas: []const ValueSchemaPlan = &.{},
    value_fields: []const ValueFieldPlan = &.{},
    value_variants: []const ValueVariantPlan = &.{},
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
        try self.validateAddressableTableLengths();
        if (self.entry_index >= self.functions.len) return error.InvalidEntryIndex;
        var reachable_blocks = [_]bool{false} ** max_indexed_table_len;
        var terminal_reachability = [_]bool{false} ** max_indexed_table_len;
        var completion_reachability = [_]bool{false} ** max_indexed_table_len;

        for (self.functions) |function| {
            if (function.symbol_name.len == 0) return error.EmptyFunctionSymbol;
            try self.validateValueSchemaRef(function.value_codec, function.value_schema_index);
            if (function.result_codec) |codec| {
                try self.validateValueSchemaRef(codec, function.result_schema_index);
            } else if (function.result_schema_index != null) {
                return error.InvalidValueSchemaIndex;
            }
            if (function.parameter_count > function.local_count) return error.InvalidFunctionLocalSpan;
            if (function.block_count == 0 or function.entry_block >= function.block_count) return error.InvalidFunctionEntryBlock;
            const requirement_end = rangeEnd(function.first_requirement, function.requirement_count) orelse return error.InvalidFunctionRequirementSpan;
            if (requirement_end > self.requirements.len) return error.InvalidFunctionRequirementSpan;
            const output_end = rangeEnd(function.first_output, function.output_count) orelse return error.InvalidFunctionOutputSpan;
            if (output_end > self.outputs.len) return error.InvalidFunctionOutputSpan;
            try self.validateFunctionOutputLabels(function);
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
            try self.validateValueSchemaRef(op.payload_codec, op.payload_schema_index);
            try self.validateValueSchemaRef(op.resume_codec, op.resume_schema_index);
            if (op.has_after and op.mode == .abort) return error.InvalidAfterHookMode;
        }

        for (self.outputs) |output| {
            if (output.label.len == 0) return error.EmptyOutputLabel;
            try self.validateValueSchemaRef(output.codec, output.schema_index);
        }

        for (self.locals) |local| {
            try self.validateValueSchemaRef(local.codec, local.schema_index);
        }

        for (self.value_schemas) |schema| {
            if (schema.label.len == 0) return error.EmptyValueSchemaLabel;
            switch (schema.codec) {
                .product => {
                    if (schema.variant_count != 0) return error.InvalidValueSchemaSpan;
                    const field_end = rangeEnd(schema.first_field, schema.field_count) orelse return error.InvalidValueSchemaSpan;
                    if (field_end > self.value_fields.len) return error.InvalidValueSchemaSpan;
                },
                .sum => {
                    if (schema.field_count != 0) return error.InvalidValueSchemaSpan;
                    const variant_end = rangeEnd(schema.first_variant, schema.variant_count) orelse return error.InvalidValueSchemaSpan;
                    if (variant_end > self.value_variants.len) return error.InvalidValueSchemaSpan;
                },
                else => return error.InvalidValueSchemaCodec,
            }
        }

        for (self.value_fields) |field| {
            if (field.name.len == 0) return error.EmptyValueFieldName;
            try self.validateValueSchemaRef(field.codec, field.schema_index);
        }

        for (self.value_variants) |variant| {
            if (variant.name.len == 0) return error.EmptyValueVariantName;
            try self.validateValueSchemaRef(variant.codec, variant.schema_index);
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
        var executable_blocks = [_]bool{false} ** max_indexed_table_len;
        while (changed) {
            changed = false;
            function_completion_scan: for (self.functions, 0..) |function, function_index| {
                if (completion_reachability[function_index]) continue :function_completion_scan;
                const block_end = rangeEnd(function.first_block, function.block_count) orelse return error.InvalidFunctionBlockSpan;
                @memset(executable_blocks[function.first_block..block_end], false);
                try markFunctionExecutableBlocks(self, function, &completion_reachability, &executable_blocks);
                executable_block_completion_scan: for (self.blocks[function.first_block..block_end], 0..) |block, relative_block_index| {
                    const block_index = @as(usize, function.first_block) + relative_block_index;
                    if (!executable_blocks[block_index]) continue :executable_block_completion_scan;
                    const instruction_end = rangeEnd(block.first_instruction, block.instruction_count) orelse return error.InvalidBlockInstructionSpan;
                    if (!try blockCanResumeToTerminator(self, function, block.first_instruction, instruction_end, &completion_reachability)) continue :executable_block_completion_scan;
                    const terminator = self.terminators[block.terminator_index];
                    const block_completes = switch (terminator.kind) {
                        .return_unit, .return_value => true,
                        .jump => completion_reachability[terminator.primary],
                        .branch_if => completion_reachability[terminator.primary] or completion_reachability[terminator.secondary],
                    };
                    if (block_completes) {
                        completion_reachability[function_index] = true;
                        changed = true;
                        break;
                    }
                }
            }
        }

        changed = true;
        while (changed) {
            changed = false;
            function_terminal_scan: for (self.functions, 0..) |function, function_index| {
                if (terminal_reachability[function_index]) continue :function_terminal_scan;
                const block_end = rangeEnd(function.first_block, function.block_count) orelse return error.InvalidFunctionBlockSpan;
                @memset(executable_blocks[function.first_block..block_end], false);
                try markFunctionExecutableBlocks(self, function, &completion_reachability, &executable_blocks);
                executable_block_terminal_scan: for (self.blocks[function.first_block..block_end], 0..) |block, relative_block_index| {
                    const block_index = @as(usize, function.first_block) + relative_block_index;
                    if (!executable_blocks[block_index]) continue :executable_block_terminal_scan;
                    const instruction_end = rangeEnd(block.first_instruction, block.instruction_count) orelse return error.InvalidBlockInstructionSpan;
                    if (try blockCanEscapeTerminally(
                        self,
                        function,
                        block.first_instruction,
                        instruction_end,
                        .{
                            .completion = &completion_reachability,
                            .terminal = &terminal_reachability,
                        },
                    )) {
                        terminal_reachability[function_index] = true;
                        changed = true;
                        break;
                    }
                }
            }
        }

        for (self.functions) |function| {
            const result_codec = function.result_codec orelse continue;
            if (valueRefsEqual(
                .{ .codec = result_codec, .schema_index = function.result_schema_index },
                .{ .codec = function.value_codec, .schema_index = function.value_schema_index },
            )) continue;
            const completion_codecs = try functionCompletionCodecReachability(self, function, &completion_reachability);
            if (completion_codecs.value_codec and completion_codecs.result_codec) return error.InvalidFunctionResultCodec;
        }

        const entry = self.functions[self.entry_index];
        if (entry.result_codec) |entry_result_codec| {
            if (!valueRefsEqual(
                .{ .codec = entry_result_codec, .schema_index = entry.result_schema_index },
                .{ .codec = entry.value_codec, .schema_index = entry.value_schema_index },
            )) {
                const entry_completion_codecs = try functionCompletionCodecReachability(self, entry, &completion_reachability);
                if (entry_completion_codecs.value_codec and terminal_reachability[self.entry_index]) {
                    return error.InvalidFunctionResultCodec;
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
                        const helper_result_ref = functionResultRef(callee);
                        if (block_is_reachable and
                            !valueRefsEqual(helper_result_ref, functionResultRef(function)) and
                            terminal_reachability[instruction.operand])
                        {
                            return error.InvalidInstructionLocalIndex;
                        }
                        const helper_completion_ref = try functionCompletionValueRef(self, callee, &completion_reachability);
                        if (helper_completion_ref.codec != .unit and
                            completion_reachability[instruction.operand] and
                            !functionLocalHasValueRef(self, function, instruction.dst, helper_completion_ref))
                        {
                            return error.InvalidInstructionLocalIndex;
                        }
                        const target_parameter_count = callee.parameter_count;
                        if (target_parameter_count != 0) {
                            const call_arg_end = rangeEnd(instruction.aux, target_parameter_count) orelse return error.InvalidCallHelperArgSpan;
                            if (call_arg_end > self.call_args.len) return error.InvalidCallHelperArgSpan;
                            for (self.call_args[instruction.aux..call_arg_end], 0..) |local_id, parameter_index| {
                                if (!isValidFunctionLocal(function.local_count, local_id)) return error.InvalidCallHelperArgSpan;
                                const expected_ref = functionLocalValueRef(self, callee, @intCast(parameter_index)) orelse
                                    return error.InvalidFunctionLocalSpan;
                                if (!functionLocalHasValueRef(self, function, local_id, expected_ref)) {
                                    return error.InvalidInstructionLocalIndex;
                                }
                            }
                        }
                    },
                    .call_nested_with => {
                        const result_codec = try valueCodecFromInstructionAux(instruction.aux);
                        if (result_codec != .unit and !functionLocalHasCodec(self, function, instruction.dst, result_codec)) {
                            return error.InvalidInstructionLocalIndex;
                        }
                        if (instruction.string_literal.len == 0) return error.InvalidInstructionLocalIndex;
                        if (!namedNestedWithMetadataIsComplete(instruction.string_literal)) return error.InvalidNestedWithMetadata;
                    },
                    .call_op => {
                        if (instruction.operand >= self.ops.len or !functionOwnsOpTarget(self, function, instruction.operand)) {
                            return error.InvalidCallOpTarget;
                        }
                        if (self.ops[instruction.operand].resume_codec != .unit and
                            !functionLocalHasValueRef(self, function, instruction.dst, .{
                                .codec = self.ops[instruction.operand].resume_codec,
                                .schema_index = self.ops[instruction.operand].resume_schema_index,
                            }))
                        {
                            return error.InvalidInstructionLocalIndex;
                        }
                        if (self.ops[instruction.operand].payload_codec != .unit and
                            !functionLocalHasValueRef(self, function, instruction.aux, .{
                                .codec = self.ops[instruction.operand].payload_codec,
                                .schema_index = self.ops[instruction.operand].payload_schema_index,
                            }))
                        {
                            return error.InvalidInstructionLocalIndex;
                        }
                    },
                    .const_string => {
                        if (!functionLocalHasCodec(self, function, instruction.dst, .string)) return error.InvalidInstructionLocalIndex;
                    },
                    .const_usize => {
                        if (!functionLocalHasCodec(self, function, instruction.dst, .usize)) return error.InvalidInstructionLocalIndex;
                        _ = std.fmt.parseUnsigned(usize, instruction.string_literal, 0) catch
                            return error.InvalidInstructionLocalIndex;
                    },
                    .return_error => {
                        if (instruction.string_literal.len == 0) return error.InvalidInstructionLocalIndex;
                        if (relative_index + 1 != block.instruction_count) return error.InvalidTerminatorInstruction;
                    },
                    .add_i32, .add_const_i32, .compare_eq_zero, .const_i32, .sub_one => {
                        if (instruction.kind == .add_i32) {
                            if (!functionLocalHasCodec(self, function, instruction.dst, .i32) or
                                !functionLocalHasCodec(self, function, instruction.operand, .i32) or
                                !functionLocalHasCodec(self, function, instruction.aux, .i32))
                            {
                                return error.InvalidInstructionLocalIndex;
                            }
                        } else if (instruction.kind == .add_const_i32) {
                            if (!functionLocalHasCodec(self, function, instruction.dst, .i32) or
                                !functionLocalHasCodec(self, function, instruction.operand, .i32))
                            {
                                return error.InvalidInstructionLocalIndex;
                            }
                        } else if (instruction.kind == .compare_eq_zero) {
                            const operand_codec = functionLocalCodec(self, function, instruction.operand) orelse
                                return error.InvalidInstructionLocalIndex;
                            if (operand_codec != .bool and operand_codec != .i32 and operand_codec != .usize) return error.InvalidInstructionLocalIndex;
                            if (!functionLocalHasCodec(self, function, instruction.dst, .bool)) return error.InvalidInstructionLocalIndex;
                        } else if (instruction.kind == .const_i32) {
                            const dst_codec = functionLocalCodec(self, function, instruction.dst) orelse
                                return error.InvalidInstructionLocalIndex;
                            if (dst_codec != .i32) return error.InvalidInstructionLocalIndex;
                        } else if (instruction.kind == .sub_one) {
                            const operand_codec = functionLocalCodec(self, function, instruction.operand) orelse
                                return error.InvalidInstructionLocalIndex;
                            if (operand_codec != .i32 and operand_codec != .usize) return error.InvalidInstructionLocalIndex;
                            if (!functionLocalHasCodec(self, function, instruction.dst, operand_codec)) {
                                return error.InvalidInstructionLocalIndex;
                            }
                        } else {
                            return error.InvalidInstructionLocalIndex;
                        }
                    },
                    .return_value => {
                        block_has_return_value = true;
                        if (!function_returns_value) return error.InvalidTerminatorInstruction;
                        if (relative_index + 1 != block.instruction_count) return error.InvalidTerminatorInstruction;
                        if (!functionLocalHasValueRef(self, function, instruction.operand, .{
                            .codec = function.value_codec,
                            .schema_index = function.value_schema_index,
                        })) {
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
                        if (function_returns_value) {
                            if (instruction_end == block.first_instruction) return error.InvalidTerminatorInstruction;
                            if (!terminalAbortInstruction(
                                self,
                                function,
                                instruction_end - 1,
                                .{
                                    .completion = &completion_reachability,
                                    .terminal = &terminal_reachability,
                                },
                            )) return error.InvalidTerminatorInstruction;
                        }
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
            hashOptionalU16(&hasher, function.value_schema_index);
            hasher.update(&[_]u8{@intFromBool(function.result_codec != null)});
            if (function.result_codec) |codec| hashBytes(&hasher, @tagName(codec));
            hashOptionalU16(&hasher, function.result_schema_index);
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
            hashBytes(&hasher, @tagName(requirement.lifecycle_tag));
            hashBytes(&hasher, @tagName(requirement.output_tag));
        }
        for (self.ops) |op| {
            hasher.update(std.mem.asBytes(&op.requirement_index));
            hashBytes(&hasher, op.op_name);
            hashBytes(&hasher, @tagName(op.mode));
            hashBytes(&hasher, @tagName(op.payload_codec));
            hashOptionalU16(&hasher, op.payload_schema_index);
            hashBytes(&hasher, @tagName(op.resume_codec));
            hashOptionalU16(&hasher, op.resume_schema_index);
            hasher.update(&[_]u8{@intFromBool(op.has_after)});
        }
        for (self.outputs) |output| {
            hashBytes(&hasher, output.label);
            hashBytes(&hasher, @tagName(output.codec));
            hashOptionalU16(&hasher, output.schema_index);
        }
        for (self.value_schemas) |schema| {
            hashBytes(&hasher, schema.label);
            hashBytes(&hasher, @tagName(schema.codec));
            hasher.update(std.mem.asBytes(&schema.first_field));
            hasher.update(std.mem.asBytes(&schema.field_count));
            hasher.update(std.mem.asBytes(&schema.first_variant));
            hasher.update(std.mem.asBytes(&schema.variant_count));
        }
        for (self.value_fields) |field| {
            hashBytes(&hasher, field.name);
            hashBytes(&hasher, @tagName(field.codec));
            hashOptionalU16(&hasher, field.schema_index);
        }
        for (self.value_variants) |variant| {
            hashBytes(&hasher, variant.name);
            hashBytes(&hasher, @tagName(variant.codec));
            hashOptionalU16(&hasher, variant.schema_index);
        }
        for (self.locals) |local| {
            hashBytes(&hasher, @tagName(local.codec));
            hashOptionalU16(&hasher, local.schema_index);
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

    fn validateFunctionOutputLabels(self: @This(), function: FunctionPlan) ValidationError!void {
        const output_start = function.first_output;
        const output_end = rangeEnd(output_start, function.output_count) orelse return error.InvalidFunctionOutputSpan;
        const outputs = self.outputs[output_start..output_end];
        if (outputs.len <= 1) return;
        if (outputs.len > max_validated_function_outputs) return error.TooManyFunctionOutputs;

        if (outputs.len <= small_output_scan_limit) {
            for (outputs[0 .. outputs.len - 1], 0..) |output, output_index| {
                for (outputs[output_index + 1 ..]) |other_output| {
                    if (std.mem.eql(u8, output.label, other_output.label)) return error.DuplicateOutputLabel;
                }
            }
            return;
        }

        var sort_keys = [_]OutputLabelSortKey{.{ .hash = 0, .index = 0 }} ** max_validated_function_outputs;
        const keys = sort_keys[0..outputs.len];
        for (outputs, 0..) |output, output_index| {
            keys[output_index] = .{
                .hash = std.hash.Wyhash.hash(0, output.label),
                .index = @intCast(output_index),
            };
        }
        std.mem.sort(OutputLabelSortKey, keys, OutputLabelSortContext{ .outputs = outputs }, outputLabelSortKeyLessThan);

        for (keys[1..], 1..) |key, key_index| {
            const previous_key = keys[key_index - 1];
            if (previous_key.hash != key.hash) continue;
            if (std.mem.eql(u8, outputs[previous_key.index].label, outputs[key.index].label)) return error.DuplicateOutputLabel;
        }
    }

    fn validateAddressableTableLengths(self: @This()) ValidationError!void {
        if (self.functions.len > max_indexed_table_len) return error.ProgramPlanTableTooLarge;
        if (self.requirements.len > max_indexed_table_len) return error.ProgramPlanTableTooLarge;
        if (self.ops.len > max_indexed_table_len) return error.ProgramPlanTableTooLarge;
        if (self.outputs.len > max_indexed_table_len) return error.ProgramPlanTableTooLarge;
        if (self.value_schemas.len > max_indexed_table_len) return error.ProgramPlanTableTooLarge;
        if (self.value_fields.len > max_indexed_table_len) return error.ProgramPlanTableTooLarge;
        if (self.value_variants.len > max_indexed_table_len) return error.ProgramPlanTableTooLarge;
        if (self.locals.len > max_indexed_table_len) return error.ProgramPlanTableTooLarge;
        if (self.call_args.len > max_indexed_table_len) return error.ProgramPlanTableTooLarge;
        if (self.blocks.len > max_indexed_table_len) return error.ProgramPlanTableTooLarge;
        if (self.terminators.len > max_indexed_table_len) return error.ProgramPlanTableTooLarge;
        if (self.instructions.len > max_indexed_table_len) return error.ProgramPlanTableTooLarge;
    }

    fn validateValueSchemaRef(self: @This(), codec: ValueCodec, schema_index: ?u16) ValidationError!void {
        switch (codec) {
            .product, .sum => {
                const index = schema_index orelse return error.InvalidValueSchemaIndex;
                if (index >= self.value_schemas.len) return error.InvalidValueSchemaIndex;
                if (self.value_schemas[index].codec != codec) return error.InvalidValueSchemaCodec;
            },
            else => {
                if (schema_index != null) return error.InvalidValueSchemaIndex;
            },
        }
    }
};

const OutputLabelSortKey = struct {
    hash: u64,
    index: u16,
};

const OutputLabelSortContext = struct {
    outputs: []const OutputPlan,
};

fn outputLabelSortKeyLessThan(context: OutputLabelSortContext, lhs: OutputLabelSortKey, rhs: OutputLabelSortKey) bool {
    if (lhs.hash != rhs.hash) return lhs.hash < rhs.hash;
    return std.mem.lessThan(u8, context.outputs[lhs.index].label, context.outputs[rhs.index].label);
}

/// Internal construction kernel for compiler-produced runtime plans.
///
/// The serialized ProgramPlan stays intentionally plain. Generated lowering code
/// uses these refs while assembling instructions so local/op ownership mistakes
/// fail before the final wire-shaped plan escapes.
pub const program_plan_builder = struct {
    /// Opaque function handle used while assembling generated plans.
    pub const FunctionRef = struct {
        index: u16,
    };

    /// Function-owned local handle.
    pub const LocalRef = struct {
        function: FunctionRef,
        index: u16,
    };

    /// Function-owned op target handle.
    pub const OpRef = struct {
        function: FunctionRef,
        index: u16,
    };

    /// Final materialization payload for a wire-shaped ProgramPlan.
    pub const FinishSpec = struct {
        schema_version: u32 = ProgramPlan.current_schema_version,
        label: []const u8,
        ir_hash: u64,
        entry: FunctionRef,
        functions: []const FunctionPlan,
        requirements: []const RequirementPlan,
        ops: []const OpPlan,
        outputs: []const OutputPlan,
        value_schemas: []const ValueSchemaPlan = &.{},
        value_fields: []const ValueFieldPlan = &.{},
        value_variants: []const ValueVariantPlan = &.{},
        locals: []const LocalPlan = &.{},
        call_args: []const u16 = &.{},
        blocks: []const BlockPlan = &.{},
        terminators: []const Terminator = &.{},
        instructions: []const Instruction,
    };

    /// Create a function handle from the generated function table ordinal.
    pub fn function(index: u16) FunctionRef {
        return .{ .index = index };
    }

    /// Create a local handle scoped to one function.
    pub fn local(function_ref: FunctionRef, index: u16) LocalRef {
        return .{ .function = function_ref, .index = index };
    }

    /// Create an op handle scoped to one function.
    pub fn op(function_ref: FunctionRef, index: u16) OpRef {
        return .{ .function = function_ref, .index = index };
    }

    /// Build a helper call whose destination is owned by the caller.
    pub fn callHelper(
        caller: FunctionRef,
        dst: ?LocalRef,
        callee: FunctionRef,
        call_arg_base: ?u16,
    ) ValidationError!Instruction {
        if (dst) |local_ref| try expectLocalOwnedBy(caller, local_ref);
        return .{
            .kind = .call_helper,
            .dst = if (dst) |local_ref| local_ref.index else std.math.maxInt(u16),
            .operand = callee.index,
            .aux = call_arg_base orelse std.math.maxInt(u16),
        };
    }

    /// Build a helper call whose destination is semantically ignored.
    pub fn callHelperDiscardingResult(
        caller: FunctionRef,
        dst_index: u16,
        callee: FunctionRef,
        call_arg_base: ?u16,
    ) Instruction {
        _ = caller;
        return .{
            .kind = .call_helper,
            .dst = dst_index,
            .operand = callee.index,
            .aux = call_arg_base orelse std.math.maxInt(u16),
        };
    }

    /// Build an effect op call whose op and local refs are owned by the caller.
    pub fn callOp(
        caller: FunctionRef,
        dst: ?LocalRef,
        op_ref: OpRef,
        payload: ?LocalRef,
    ) ValidationError!Instruction {
        if (caller.index != op_ref.function.index) return error.InvalidCallOpTarget;
        if (dst) |local_ref| try expectLocalOwnedBy(caller, local_ref);
        if (payload) |local_ref| try expectLocalOwnedBy(caller, local_ref);
        return .{
            .kind = .call_op,
            .dst = if (dst) |local_ref| local_ref.index else std.math.maxInt(u16),
            .operand = op_ref.index,
            .aux = if (payload) |local_ref| local_ref.index else std.math.maxInt(u16),
        };
    }

    /// Build a return-value instruction from a caller-owned local.
    pub fn returnValue(caller: FunctionRef, local_ref: LocalRef) ValidationError!Instruction {
        try expectLocalOwnedBy(caller, local_ref);
        return .{
            .kind = .return_value,
            .operand = local_ref.index,
        };
    }

    /// Materialize and validate the final ProgramPlan.
    pub fn finish(spec: FinishSpec) ValidationError!ProgramPlan {
        const plan: ProgramPlan = .{
            .schema_version = spec.schema_version,
            .label = spec.label,
            .ir_hash = spec.ir_hash,
            .entry_index = spec.entry.index,
            .functions = spec.functions,
            .requirements = spec.requirements,
            .ops = spec.ops,
            .outputs = spec.outputs,
            .value_schemas = spec.value_schemas,
            .value_fields = spec.value_fields,
            .value_variants = spec.value_variants,
            .locals = spec.locals,
            .call_args = spec.call_args,
            .blocks = spec.blocks,
            .terminators = spec.terminators,
            .instructions = spec.instructions,
        };
        try plan.validate();
        return plan;
    }

    /// Route an existing hand-written positive fixture through builder validation.
    pub fn fromValidatedPlan(plan: ProgramPlan) ValidationError!ProgramPlan {
        return finish(.{
            .schema_version = plan.schema_version,
            .label = plan.label,
            .ir_hash = plan.ir_hash,
            .entry = function(plan.entry_index),
            .functions = plan.functions,
            .requirements = plan.requirements,
            .ops = plan.ops,
            .outputs = plan.outputs,
            .value_schemas = plan.value_schemas,
            .value_fields = plan.value_fields,
            .value_variants = plan.value_variants,
            .locals = plan.locals,
            .call_args = plan.call_args,
            .blocks = plan.blocks,
            .terminators = plan.terminators,
            .instructions = plan.instructions,
        });
    }

    fn expectLocalOwnedBy(function_ref: FunctionRef, local_ref: LocalRef) ValidationError!void {
        if (function_ref.index != local_ref.function.index) return error.InvalidInstructionLocalIndex;
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
    EmptyValueFieldName,
    EmptyValueSchemaLabel,
    EmptyValueVariantName,
    DuplicateOutputLabel,
    TooManyFunctionOutputs,
    ProgramPlanTableTooLarge,
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
    InvalidFunctionResultCodec,
    InvalidInstructionLocalIndex,
    InvalidAfterHookMode,
    InvalidOpRequirementIndex,
    InvalidOpRequirementOwnership,
    InvalidRequirementOpSpan,
    InvalidReturnValueIndex,
    InvalidTerminatorInstruction,
    InvalidTerminatorTarget,
    UnsupportedSchemaVersion,
    InvalidInstructionCodec,
    InvalidNestedWithMetadata,
    InvalidValueSchemaCodec,
    InvalidValueSchemaIndex,
    InvalidValueSchemaSpan,
};
/// Error set for lowering comptime IR into a runtime-owned plan.
pub const PlanError = CodecError || effect_ir.NormalizeError || error{EmptyProgram};
/// Error set for upgrading legacy runtime-plan schemas in place.
pub const LegacySchemaError = std.mem.Allocator.Error || error{UnsupportedSchemaVersion};

/// Return the first-wave runtime codec for one supported Zig type.
pub fn codecForType(comptime T: type) CodecError!ValueCodec {
    if (T == void) return .unit;
    if (T == noreturn) return .unit;
    if (T == bool) return .bool;
    if (T == i32) return .i32;
    if (T == usize) return .usize;
    if (T == []const u8) return .string;
    if (T == [][]const u8) return .string_list;
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            inline for (info.fields) |field| {
                _ = try codecForType(field.type);
            }
            return .product;
        },
        .@"enum" => return .sum,
        .@"union" => |info| {
            if (info.tag_type == null) return error.UnsupportedCodecType;
            inline for (info.fields) |field| {
                _ = try codecForType(field.type);
            }
            return .sum;
        },
        .optional => |info| {
            _ = try codecForType(info.child);
            return .sum;
        },
        else => {},
    }
    return error.UnsupportedCodecType;
}

/// Return how many product fields a supported Zig type contributes.
pub fn fieldCountForType(comptime T: type) CodecError!usize {
    return switch (@typeInfo(T)) {
        .@"struct" => |info| blk: {
            if (try codecForType(T) != .product) return error.UnsupportedCodecType;
            break :blk info.fields.len;
        },
        else => error.UnsupportedCodecType,
    };
}

/// Return how many sum variants a supported Zig type contributes.
pub fn variantCountForType(comptime T: type) CodecError!usize {
    return switch (@typeInfo(T)) {
        .@"enum" => |info| info.fields.len,
        .@"union" => |info| blk: {
            if (info.tag_type == null) return error.UnsupportedCodecType;
            _ = try codecForType(T);
            break :blk info.fields.len;
        },
        .optional => |info| blk: {
            _ = try codecForType(info.child);
            break :blk 2;
        },
        else => error.UnsupportedCodecType,
    };
}

const ValueSchemaEntryCounts = struct {
    schemas: usize = 0,
    fields: usize = 0,
    variants: usize = 0,

    fn add(self: *ValueSchemaEntryCounts, other: ValueSchemaEntryCounts) void {
        self.schemas += other.schemas;
        self.fields += other.fields;
        self.variants += other.variants;
    }
};

fn countValueSchemaEntries(comptime T: type) CodecError!ValueSchemaEntryCounts {
    const codec = try codecForType(T);
    return switch (codec) {
        .product => switch (@typeInfo(T)) {
            .@"struct" => |info| blk: {
                var counts = ValueSchemaEntryCounts{
                    .schemas = 1,
                    .fields = info.fields.len,
                };
                inline for (info.fields) |field| counts.add(try countValueSchemaEntries(field.type));
                break :blk counts;
            },
            else => error.UnsupportedCodecType,
        },
        .sum => switch (@typeInfo(T)) {
            .@"enum" => |info| .{
                .schemas = 1,
                .variants = info.fields.len,
            },
            .@"union" => |info| blk: {
                if (info.tag_type == null) return error.UnsupportedCodecType;
                var counts = ValueSchemaEntryCounts{
                    .schemas = 1,
                    .variants = info.fields.len,
                };
                inline for (info.fields) |field| counts.add(try countValueSchemaEntries(field.type));
                break :blk counts;
            },
            .optional => |info| blk: {
                var counts = ValueSchemaEntryCounts{
                    .schemas = 1,
                    .variants = 2,
                };
                counts.add(try countValueSchemaEntries(info.child));
                break :blk counts;
            },
            else => error.UnsupportedCodecType,
        },
        else => .{},
    };
}

fn ValueSchemaBuildState(
    comptime schema_count: usize,
    comptime field_count: usize,
    comptime variant_count: usize,
) type {
    return struct {
        schemas: [schema_count]ValueSchemaPlan = undefined,
        fields: [field_count]ValueFieldPlan = undefined,
        variants: [variant_count]ValueVariantPlan = undefined,
        next_schema: u16 = 0,
        next_field: u16 = 0,
        next_variant: u16 = 0,
    };
}

fn fillValueSchemaForType(
    comptime T: type,
    state: anytype,
) CodecError!ValueRef {
    const codec = try codecForType(T);
    switch (codec) {
        .product => switch (@typeInfo(T)) {
            .@"struct" => |info| {
                const schema_index = state.next_schema;
                state.next_schema += 1;
                const first_field = state.next_field;
                state.next_field += @intCast(info.fields.len);
                state.schemas[schema_index] = .{
                    .label = @typeName(T),
                    .codec = .product,
                    .first_field = first_field,
                    .field_count = @intCast(info.fields.len),
                };
                inline for (info.fields, 0..) |field, field_index| {
                    const field_ref = try fillValueSchemaForType(field.type, state);
                    state.fields[first_field + field_index] = .{
                        .name = field.name,
                        .codec = field_ref.codec,
                        .schema_index = field_ref.schema_index,
                    };
                }
                return .{ .codec = .product, .schema_index = schema_index };
            },
            else => return error.UnsupportedCodecType,
        },
        .sum => switch (@typeInfo(T)) {
            .@"enum" => |info| {
                const schema_index = state.next_schema;
                state.next_schema += 1;
                const first_variant = state.next_variant;
                state.next_variant += @intCast(info.fields.len);
                state.schemas[schema_index] = .{
                    .label = @typeName(T),
                    .codec = .sum,
                    .first_variant = first_variant,
                    .variant_count = @intCast(info.fields.len),
                };
                inline for (info.fields, 0..) |field, field_index| {
                    state.variants[first_variant + field_index] = .{
                        .name = field.name,
                        .codec = .unit,
                    };
                }
                return .{ .codec = .sum, .schema_index = schema_index };
            },
            .@"union" => |info| {
                if (info.tag_type == null) return error.UnsupportedCodecType;
                const schema_index = state.next_schema;
                state.next_schema += 1;
                const first_variant = state.next_variant;
                state.next_variant += @intCast(info.fields.len);
                state.schemas[schema_index] = .{
                    .label = @typeName(T),
                    .codec = .sum,
                    .first_variant = first_variant,
                    .variant_count = @intCast(info.fields.len),
                };
                inline for (info.fields, 0..) |field, field_index| {
                    const variant_ref = try fillValueSchemaForType(field.type, state);
                    state.variants[first_variant + field_index] = .{
                        .name = field.name,
                        .codec = variant_ref.codec,
                        .schema_index = variant_ref.schema_index,
                    };
                }
                return .{ .codec = .sum, .schema_index = schema_index };
            },
            .optional => |info| {
                const schema_index = state.next_schema;
                state.next_schema += 1;
                const first_variant = state.next_variant;
                state.next_variant += 2;
                state.schemas[schema_index] = .{
                    .label = @typeName(T),
                    .codec = .sum,
                    .first_variant = first_variant,
                    .variant_count = 2,
                };
                state.variants[first_variant] = .{ .name = "none" };
                const child_ref = try fillValueSchemaForType(info.child, state);
                state.variants[first_variant + 1] = .{
                    .name = "some",
                    .codec = child_ref.codec,
                    .schema_index = child_ref.schema_index,
                };
                return .{ .codec = .sum, .schema_index = schema_index };
            },
            else => return error.UnsupportedCodecType,
        },
        else => return .{ .codec = codec },
    }
}

/// Return a comptime value-schema namespace for one supported scalar/product/sum type.
pub fn ValueSchemaForType(comptime T: type) type {
    const counts = countValueSchemaEntries(T) catch |err| unsupportedValueSchemaType(T, err);
    const State = ValueSchemaBuildState(counts.schemas, counts.fields, counts.variants);
    const built = comptime blk: {
        var state = State{};
        const ref = fillValueSchemaForType(T, &state) catch |err| unsupportedValueSchemaType(T, err);
        break :blk struct {
            const value_ref = ref;
            const schemas = state.schemas;
            const fields = state.fields;
            const variants = state.variants;
        };
    };
    return struct {
        pub const codec = built.value_ref.codec;
        pub const schema_index = built.value_ref.schema_index;
        pub const value_schemas = built.schemas[0..];
        pub const value_fields = built.fields[0..];
        pub const value_variants = built.variants[0..];
    };
}

fn directValueSchemaFieldCount(comptime T: type) CodecError!usize {
    return switch (try codecForType(T)) {
        .product => switch (@typeInfo(T)) {
            .@"struct" => |info| info.fields.len,
            else => error.UnsupportedCodecType,
        },
        else => 0,
    };
}

fn directValueSchemaVariantCount(comptime T: type) CodecError!usize {
    return switch (try codecForType(T)) {
        .sum => switch (@typeInfo(T)) {
            .@"enum" => |info| info.fields.len,
            .@"union" => |info| blk: {
                if (info.tag_type == null) return error.UnsupportedCodecType;
                break :blk info.fields.len;
            },
            .optional => 2,
            else => error.UnsupportedCodecType,
        },
        else => 0,
    };
}

fn schemaTypeAlreadyAdded(comptime max_schema_types: usize, types: *const [max_schema_types]type, count: usize, comptime T: type) bool {
    for (types[0..count]) |SchemaType| {
        if (SchemaType == T) return true;
    }
    return false;
}

fn countPotentialSchemaTypesForType(comptime T: type) CodecError!usize {
    return switch (try codecForType(T)) {
        .product => switch (@typeInfo(T)) {
            .@"struct" => |info| blk: {
                var total: usize = 1;
                inline for (info.fields) |field| total += try countPotentialSchemaTypesForType(field.type);
                break :blk total;
            },
            else => error.UnsupportedCodecType,
        },
        .sum => switch (@typeInfo(T)) {
            .@"enum" => 1,
            .@"union" => |info| blk: {
                if (info.tag_type == null) return error.UnsupportedCodecType;
                var total: usize = 1;
                inline for (info.fields) |field| total += try countPotentialSchemaTypesForType(field.type);
                break :blk total;
            },
            .optional => |info| 1 + try countPotentialSchemaTypesForType(info.child),
            else => error.UnsupportedCodecType,
        },
        else => 0,
    };
}

fn countPotentialSchemaTypesForFunctions(comptime functions: anytype) CodecError!usize {
    var total: usize = 0;
    inline for (functions) |function| {
        total += try countPotentialSchemaTypesForType(function.ValueType);
        inline for (function.outputs) |output| total += try countPotentialSchemaTypesForType(output.OutputType);
        inline for (function.row.requirements) |requirement| {
            inline for (requirement.ops) |op| {
                total += try countPotentialSchemaTypesForType(op.PayloadType);
                total += try countPotentialSchemaTypesForType(op.ResumeType);
            }
        }
    }
    return total;
}

fn addSchemaTypesForType(
    comptime max_schema_types: usize,
    types: *[max_schema_types]type,
    count: *usize,
    comptime T: type,
) CodecError!void {
    switch (try codecForType(T)) {
        .product => switch (@typeInfo(T)) {
            .@"struct" => |info| {
                if (!schemaTypeAlreadyAdded(max_schema_types, types, count.*, T)) {
                    types[count.*] = T;
                    count.* += 1;
                }
                inline for (info.fields) |field| try addSchemaTypesForType(max_schema_types, types, count, field.type);
            },
            else => return error.UnsupportedCodecType,
        },
        .sum => switch (@typeInfo(T)) {
            .@"enum" => {
                if (!schemaTypeAlreadyAdded(max_schema_types, types, count.*, T)) {
                    types[count.*] = T;
                    count.* += 1;
                }
            },
            .@"union" => |info| {
                if (info.tag_type == null) return error.UnsupportedCodecType;
                if (!schemaTypeAlreadyAdded(max_schema_types, types, count.*, T)) {
                    types[count.*] = T;
                    count.* += 1;
                }
                inline for (info.fields) |field| try addSchemaTypesForType(max_schema_types, types, count, field.type);
            },
            .optional => |info| {
                if (!schemaTypeAlreadyAdded(max_schema_types, types, count.*, T)) {
                    types[count.*] = T;
                    count.* += 1;
                }
                try addSchemaTypesForType(max_schema_types, types, count, info.child);
            },
            else => return error.UnsupportedCodecType,
        },
        else => {},
    }
}

fn valueSchemaIndexForType(comptime schema_types: anytype, comptime T: type) CodecError!u16 {
    inline for (schema_types, 0..) |SchemaType, index| {
        if (SchemaType == T) return @intCast(index);
    }
    return error.UnsupportedCodecType;
}

fn valueRefForTypeInRegistry(comptime schema_types: anytype, comptime T: type) CodecError!ValueRef {
    const codec = try codecForType(T);
    return .{
        .codec = codec,
        .schema_index = if (valueCodecNeedsSchema(codec)) try valueSchemaIndexForType(schema_types, T) else null,
    };
}

fn buildFlatValueSchemas(comptime schema_types: anytype) CodecError![schema_types.len]ValueSchemaPlan {
    var schemas: [schema_types.len]ValueSchemaPlan = undefined;
    var first_field: u16 = 0;
    var first_variant: u16 = 0;
    inline for (schema_types, 0..) |SchemaType, index| {
        const codec = try codecForType(SchemaType);
        const field_count = try directValueSchemaFieldCount(SchemaType);
        const variant_count = try directValueSchemaVariantCount(SchemaType);
        schemas[index] = .{
            .label = @typeName(SchemaType),
            .codec = codec,
            .first_field = first_field,
            .field_count = @intCast(field_count),
            .first_variant = first_variant,
            .variant_count = @intCast(variant_count),
        };
        first_field += @intCast(field_count);
        first_variant += @intCast(variant_count);
    }
    return schemas;
}

fn countFlatValueFields(comptime schema_types: anytype) CodecError!usize {
    var total: usize = 0;
    inline for (schema_types) |SchemaType| total += try directValueSchemaFieldCount(SchemaType);
    return total;
}

fn countFlatValueVariants(comptime schema_types: anytype) CodecError!usize {
    var total: usize = 0;
    inline for (schema_types) |SchemaType| total += try directValueSchemaVariantCount(SchemaType);
    return total;
}

fn buildFlatValueFields(
    comptime schema_types: anytype,
    comptime field_count: usize,
) CodecError![field_count]ValueFieldPlan {
    var fields: [field_count]ValueFieldPlan = undefined;
    var field_index: usize = 0;
    inline for (schema_types) |SchemaType| {
        if ((try codecForType(SchemaType)) != .product) continue;
        switch (@typeInfo(SchemaType)) {
            .@"struct" => |info| inline for (info.fields) |field| {
                const field_ref = try valueRefForTypeInRegistry(schema_types, field.type);
                fields[field_index] = .{
                    .name = field.name,
                    .codec = field_ref.codec,
                    .schema_index = field_ref.schema_index,
                };
                field_index += 1;
            },
            else => return error.UnsupportedCodecType,
        }
    }
    return fields;
}

fn buildFlatValueVariants(
    comptime schema_types: anytype,
    comptime variant_count: usize,
) CodecError![variant_count]ValueVariantPlan {
    var variants: [variant_count]ValueVariantPlan = undefined;
    var variant_index: usize = 0;
    inline for (schema_types) |SchemaType| {
        if ((try codecForType(SchemaType)) != .sum) continue;
        switch (@typeInfo(SchemaType)) {
            .@"enum" => |info| inline for (info.fields) |field| {
                variants[variant_index] = .{
                    .name = field.name,
                    .codec = .unit,
                };
                variant_index += 1;
            },
            .@"union" => |info| {
                if (info.tag_type == null) return error.UnsupportedCodecType;
                inline for (info.fields) |field| {
                    const variant_ref = try valueRefForTypeInRegistry(schema_types, field.type);
                    variants[variant_index] = .{
                        .name = field.name,
                        .codec = variant_ref.codec,
                        .schema_index = variant_ref.schema_index,
                    };
                    variant_index += 1;
                }
            },
            .optional => |info| {
                variants[variant_index] = .{ .name = "none" };
                variant_index += 1;
                const child_ref = try valueRefForTypeInRegistry(schema_types, info.child);
                variants[variant_index] = .{
                    .name = "some",
                    .codec = child_ref.codec,
                    .schema_index = child_ref.schema_index,
                };
                variant_index += 1;
            },
            else => return error.UnsupportedCodecType,
        }
    }
    return variants;
}

fn ValueSchemaRegistryForFunctions(comptime functions: anytype) type {
    const max_schema_types = countPotentialSchemaTypesForFunctions(functions) catch |err| unsupportedValueSchemaType(void, err);
    const schema_types = comptime blk: {
        var max_types: [max_schema_types]type = undefined;
        var count: usize = 0;
        for (functions) |function| {
            addSchemaTypesForType(max_schema_types, &max_types, &count, function.ValueType) catch |err| unsupportedValueSchemaType(function.ValueType, err);
            for (function.outputs) |output| {
                addSchemaTypesForType(max_schema_types, &max_types, &count, output.OutputType) catch |err| unsupportedValueSchemaType(output.OutputType, err);
            }
            for (function.row.requirements) |requirement| {
                for (requirement.ops) |op| {
                    addSchemaTypesForType(max_schema_types, &max_types, &count, op.PayloadType) catch |err| unsupportedValueSchemaType(op.PayloadType, err);
                    addSchemaTypesForType(max_schema_types, &max_types, &count, op.ResumeType) catch |err| unsupportedValueSchemaType(op.ResumeType, err);
                }
            }
        }
        var exact: [count]type = undefined;
        for (max_types[0..count], 0..) |SchemaType, index| exact[index] = SchemaType;
        break :blk exact;
    };
    const field_count = countFlatValueFields(schema_types[0..]) catch |err| unsupportedValueSchemaType(void, err);
    const variant_count = countFlatValueVariants(schema_types[0..]) catch |err| unsupportedValueSchemaType(void, err);
    const schemas = buildFlatValueSchemas(schema_types[0..]) catch |err| unsupportedValueSchemaType(void, err);
    const fields = buildFlatValueFields(schema_types[0..], field_count) catch |err| unsupportedValueSchemaType(void, err);
    const variants = buildFlatValueVariants(schema_types[0..], variant_count) catch |err| unsupportedValueSchemaType(void, err);
    return struct {
        pub const registered_schema_types = schema_types;
        pub const value_schemas = schemas;
        pub const value_fields = fields;
        pub const value_variants = variants;
    };
}

fn unsupportedValueSchemaType(comptime T: type, comptime err: CodecError) noreturn {
    @compileError(std.fmt.comptimePrint(
        "unsupported ProgramPlan value schema type '{s}': {s}",
        .{ @typeName(T), @errorName(err) },
    ));
}

fn hashAuthoredBoundPlan(
    comptime label: []const u8,
    comptime payload_codec: ValueCodec,
    comptime resume_codec: ValueCodec,
    comptime result_codec: ValueCodec,
    comptime control_mode: ControlMode,
) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, "authored.bound_program");
    hashBytes(&hasher, label);
    hashBytes(&hasher, @tagName(payload_codec));
    hashBytes(&hasher, @tagName(resume_codec));
    hashBytes(&hasher, @tagName(result_codec));
    hashBytes(&hasher, @tagName(control_mode));
    return hasher.final();
}

/// Build the minimal direct ProgramPlan for one explicit authored operation.
pub fn authoredBoundPlan(
    comptime label: []const u8,
    comptime PayloadType: type,
    comptime ResumeType: type,
    comptime ResultType: type,
    comptime control_mode: ControlMode,
) ?ProgramPlan {
    const payload_codec = comptime codecForType(PayloadType) catch return null;
    const resume_codec = comptime switch (control_mode) {
        .abort => ValueCodec.unit,
        .transform, .choice => codecForType(ResumeType) catch return null,
    };
    const result_codec = comptime codecForType(ResultType) catch return null;
    if (!codecSupportedByAuthoredScalarRunner(payload_codec) or
        !codecSupportedByAuthoredScalarRunner(resume_codec) or
        !codecSupportedByAuthoredScalarRunner(result_codec))
    {
        return null;
    }

    const locals = comptime switch (control_mode) {
        .abort => if (payload_codec == .unit)
            [0]LocalPlan{}
        else
            [1]LocalPlan{.{ .codec = payload_codec }},
        .transform, .choice => switch (payload_codec == .unit) {
            true => if (resume_codec == .unit)
                [0]LocalPlan{}
            else
                [1]LocalPlan{.{ .codec = resume_codec }},
            false => if (resume_codec == .unit)
                [1]LocalPlan{.{ .codec = payload_codec }}
            else blk: {
                break :blk [2]LocalPlan{
                    .{ .codec = payload_codec },
                    .{ .codec = resume_codec },
                };
            },
        },
    };
    const entry_function = program_plan_builder.function(0);
    const payload_local: ?program_plan_builder.LocalRef = if (payload_codec == .unit) null else program_plan_builder.local(entry_function, 0);
    const resume_local: ?program_plan_builder.LocalRef = if (resume_codec == .unit) null else program_plan_builder.local(entry_function, if (payload_codec == .unit) 0 else 1);
    const instructions = comptime switch (control_mode) {
        .abort => [1]Instruction{
            program_plan_builder.callOp(
                entry_function,
                null,
                program_plan_builder.op(entry_function, 0),
                payload_local,
            ) catch |err| invalidGeneratedPlan(err),
        },
        .transform, .choice => if (resume_codec == .unit) blk: {
            break :blk [1]Instruction{
                program_plan_builder.callOp(
                    entry_function,
                    null,
                    program_plan_builder.op(entry_function, 0),
                    payload_local,
                ) catch |err| invalidGeneratedPlan(err),
            };
        } else blk: {
            break :blk [2]Instruction{
                program_plan_builder.callOp(
                    entry_function,
                    resume_local,
                    program_plan_builder.op(entry_function, 0),
                    payload_local,
                ) catch |err| invalidGeneratedPlan(err),
                program_plan_builder.returnValue(entry_function, resume_local.?) catch |err| invalidGeneratedPlan(err),
            };
        },
    };
    const terminator_kind: TerminatorKind = switch (control_mode) {
        .abort => .return_unit,
        .transform, .choice => if (resume_codec == .unit) .return_unit else .return_value,
    };
    const functions = [_]FunctionPlan{.{
        .symbol_name = "runAuthored",
        .value_codec = switch (control_mode) {
            .abort => .unit,
            .transform, .choice => resume_codec,
        },
        .result_codec = result_codec,
        .parameter_count = if (payload_codec == .unit) 0 else 1,
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
    }};
    const requirements = [_]RequirementPlan{.{
        .label = "authored",
        .first_op = 0,
        .op_count = 1,
        .lifecycle_tag = .generated_family,
        .output_tag = .none,
    }};
    const ops = [_]OpPlan{.{
        .requirement_index = 0,
        .op_name = "dispatch",
        .mode = control_mode,
        .payload_codec = payload_codec,
        .resume_codec = resume_codec,
        .has_after = control_mode != .abort,
    }};
    const blocks = [_]BlockPlan{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]Terminator{.{ .kind = terminator_kind }};
    const plan = program_plan_builder.finish(.{
        .label = label,
        .ir_hash = hashAuthoredBoundPlan(label, payload_codec, resume_codec, result_codec, control_mode),
        .entry = entry_function,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &locals,
        .call_args = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch return null;
    return plan;
}

/// Return the externally observable result codec for one function plan.
pub fn functionResultCodec(function: FunctionPlan) ValueCodec {
    return function.result_codec orelse function.value_codec;
}

pub fn functionResultRef(function: FunctionPlan) ValueRef {
    if (function.result_codec) |codec| {
        return .{
            .codec = codec,
            .schema_index = function.result_schema_index,
        };
    }
    return .{
        .codec = function.value_codec,
        .schema_index = function.value_schema_index,
    };
}

fn valueRefsEqual(lhs: ValueRef, rhs: ValueRef) bool {
    return lhs.codec == rhs.codec and lhs.schema_index == rhs.schema_index;
}

fn codecSupportedByAuthoredScalarRunner(codec: ValueCodec) bool {
    return switch (codec) {
        .bool, .i32, .string, .unit, .usize => true,
        .product, .string_list, .sum => false,
    };
}

fn functionCompletionValueRef(
    self: ProgramPlan,
    function: FunctionPlan,
    completion_reachability: *const [std.math.maxInt(u16) + 1]bool,
) ValidationError!ValueRef {
    const result_codec = function.result_codec orelse return .{
        .codec = function.value_codec,
        .schema_index = function.value_schema_index,
    };
    if (valueRefsEqual(
        .{ .codec = result_codec, .schema_index = function.result_schema_index },
        .{ .codec = function.value_codec, .schema_index = function.value_schema_index },
    )) return .{
        .codec = function.value_codec,
        .schema_index = function.value_schema_index,
    };
    const completion_codecs = try functionCompletionCodecReachability(self, function, completion_reachability);
    if (completion_codecs.value_codec and completion_codecs.result_codec) return error.InvalidFunctionResultCodec;
    if (!completion_codecs.result_codec) return .{
        .codec = function.value_codec,
        .schema_index = function.value_schema_index,
    };
    return .{
        .codec = result_codec,
        .schema_index = function.result_schema_index,
    };
}

const FunctionCompletionCodecs = struct {
    value_codec: bool = false,
    result_codec: bool = false,
};

fn markFunctionCompletionState(
    states: *[std.math.maxInt(u16) + 1]bool,
    target: u16,
) bool {
    if (states[target]) return false;
    states[target] = true;
    return true;
}

fn blockAppliesAfterOnCompletion(
    self: ProgramPlan,
    function: FunctionPlan,
    first_instruction: u16,
    instruction_end: usize,
) ValidationError!bool {
    for (self.instructions[first_instruction..instruction_end]) |instruction| {
        if (instruction.kind == .call_op and
            instruction.operand < self.ops.len and
            functionOwnsOpTarget(self, function, instruction.operand) and
            self.ops[instruction.operand].has_after)
        {
            return true;
        }
    }
    return false;
}

fn functionCompletionCodecReachability(
    self: ProgramPlan,
    function: FunctionPlan,
    completion_reachability: *const [std.math.maxInt(u16) + 1]bool,
) ValidationError!FunctionCompletionCodecs {
    var plain_blocks = [_]bool{false} ** (std.math.maxInt(u16) + 1);
    var after_blocks = [_]bool{false} ** (std.math.maxInt(u16) + 1);
    const block_end = rangeEnd(function.first_block, function.block_count) orelse return error.InvalidFunctionBlockSpan;
    const entry_block_index = @as(usize, function.first_block) + function.entry_block;
    plain_blocks[entry_block_index] = true;

    var completion_codecs = FunctionCompletionCodecs{};
    var changed = true;
    while (changed) {
        changed = false;
        completion_block_scan: for (self.blocks[function.first_block..block_end], 0..) |block, relative_block_index| {
            const block_index = @as(usize, function.first_block) + relative_block_index;
            if (!plain_blocks[block_index] and !after_blocks[block_index]) continue :completion_block_scan;
            const instruction_end = rangeEnd(block.first_instruction, block.instruction_count) orelse return error.InvalidBlockInstructionSpan;
            if (!try blockCanResumeToTerminator(self, function, block.first_instruction, instruction_end, completion_reachability)) continue :completion_block_scan;

            const block_applies_after = try blockAppliesAfterOnCompletion(self, function, block.first_instruction, instruction_end);
            const completes_plain = plain_blocks[block_index] and !block_applies_after;
            const completes_after = after_blocks[block_index] or (plain_blocks[block_index] and block_applies_after);
            const terminator = self.terminators[block.terminator_index];
            switch (terminator.kind) {
                .return_unit, .return_value => {
                    completion_codecs.value_codec = completion_codecs.value_codec or completes_plain;
                    completion_codecs.result_codec = completion_codecs.result_codec or completes_after;
                },
                .jump => {
                    if (!isOwnedBlockTarget(function.first_block, block_end, terminator.primary)) return error.InvalidTerminatorTarget;
                    if (completes_plain) changed = markFunctionCompletionState(&plain_blocks, terminator.primary) or changed;
                    if (completes_after) changed = markFunctionCompletionState(&after_blocks, terminator.primary) or changed;
                },
                .branch_if => {
                    if (!isOwnedBlockTarget(function.first_block, block_end, terminator.primary)) return error.InvalidTerminatorTarget;
                    if (!isOwnedBlockTarget(function.first_block, block_end, terminator.secondary)) return error.InvalidTerminatorTarget;
                    if (completes_plain) {
                        changed = markFunctionCompletionState(&plain_blocks, terminator.primary) or changed;
                        changed = markFunctionCompletionState(&plain_blocks, terminator.secondary) or changed;
                    }
                    if (completes_after) {
                        changed = markFunctionCompletionState(&after_blocks, terminator.primary) or changed;
                        changed = markFunctionCompletionState(&after_blocks, terminator.secondary) or changed;
                    }
                },
            }
        }
    }
    return completion_codecs;
}

fn hashBytes(hasher: *std.hash.Wyhash, value: []const u8) void {
    hasher.update(value);
    hasher.update(&.{0});
}

fn hashOptionalU16(hasher: *std.hash.Wyhash, value: ?u16) void {
    hasher.update(&[_]u8{@intFromBool(value != null)});
    if (value) |unwrapped| hasher.update(std.mem.asBytes(&unwrapped));
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

fn instructionKindFromEffectIrBody(kind: effect_ir.InstructionKind) InstructionKind {
    return switch (kind) {
        .add_i32 => .add_i32,
        .add_const_i32 => .add_const_i32,
        .call_helper => .call_helper,
        .call_nested_with => .call_nested_with,
        .call_op => .call_op,
        .compare_eq_zero => .compare_eq_zero,
        .const_i32 => .const_i32,
        .const_usize => .const_usize,
        .const_string => .const_string,
        .return_error => .return_error,
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

    if (plan.schema_version == 4) {
        plan.schema_version = 5;
    }

    if (plan.schema_version == 5) {
        plan.schema_version = ProgramPlan.current_schema_version;
        return;
    }

    if (plan.schema_version == 6) {
        plan.schema_version = ProgramPlan.current_schema_version;
        return;
    }

    if (plan.schema_version == 7) {
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

/// Decode a serialized instruction aux field as a full-width ValueCodec tag.
pub fn valueCodecFromInstructionAux(aux: u16) ValidationError!ValueCodec {
    inline for (@typeInfo(ValueCodec).@"enum".fields) |field| {
        if (aux == field.value) return @enumFromInt(field.value);
    }
    return error.InvalidInstructionCodec;
}

fn functionLocalCodec(self: ProgramPlan, function: FunctionPlan, local_id: u16) ?ValueCodec {
    if (!isValidFunctionLocal(function.local_count, local_id)) return null;
    return self.locals[function.first_local + local_id].codec;
}

fn functionLocalValueRef(self: ProgramPlan, function: FunctionPlan, local_id: u16) ?ValueRef {
    if (!isValidFunctionLocal(function.local_count, local_id)) return null;
    const local = self.locals[function.first_local + local_id];
    return .{
        .codec = local.codec,
        .schema_index = local.schema_index,
    };
}

fn functionLocalHasCodec(self: ProgramPlan, function: FunctionPlan, local_id: u16, expected: ValueCodec) bool {
    return functionLocalCodec(self, function, local_id) == expected;
}

fn functionLocalHasValueRef(self: ProgramPlan, function: FunctionPlan, local_id: u16, expected: ValueRef) bool {
    const actual = functionLocalValueRef(self, function, local_id) orelse return false;
    return valueRefsEqual(actual, expected);
}

fn terminalAbortInstruction(
    self: ProgramPlan,
    function: FunctionPlan,
    instruction_index: usize,
    reachability: FunctionControlReachability,
) bool {
    const instruction_span_end = @as(usize, function.first_instruction) + function.instruction_count;
    if (instruction_index < function.first_instruction or instruction_index >= instruction_span_end) return false;
    const instruction = self.instructions[instruction_index];
    if (instruction.kind == .return_error) return instruction.string_literal.len != 0;
    if (instruction.kind == .call_helper) {
        return instruction.operand < self.functions.len and
            reachability.terminal[instruction.operand] and
            !reachability.completion[instruction.operand];
    }
    if (instruction.kind == .call_op) {
        return instruction.operand < self.ops.len and self.ops[instruction.operand].mode == .abort;
    }
    return false;
}

const FunctionControlReachability = struct {
    completion: *const [std.math.maxInt(u16) + 1]bool,
    terminal: *const [std.math.maxInt(u16) + 1]bool,
};

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
        reachable_block_scan: for (self.blocks[function.first_block..block_end], 0..) |block, relative_block_index| {
            const block_index = @as(usize, function.first_block) + relative_block_index;
            if (!reachable_blocks[block_index]) continue :reachable_block_scan;
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

fn blockCanResumeToTerminator(
    self: ProgramPlan,
    function: FunctionPlan,
    first_instruction: u16,
    instruction_end: usize,
    completion_reachability: *const [std.math.maxInt(u16) + 1]bool,
) ValidationError!bool {
    for (self.instructions[first_instruction..instruction_end]) |instruction| {
        if (instruction.kind == .return_error) {
            return false;
        } else if (instruction.kind == .call_helper) {
            if (instruction.operand >= self.functions.len) return error.InvalidCallHelperTarget;
            if (!completion_reachability[instruction.operand]) return false;
        } else if (instruction.kind == .call_op) {
            if (instruction.operand >= self.ops.len or !functionOwnsOpTarget(self, function, instruction.operand)) {
                return error.InvalidCallOpTarget;
            }
            if (self.ops[instruction.operand].mode == .abort) return false;
        }
    }
    return true;
}

fn blockCanEscapeTerminally(
    self: ProgramPlan,
    function: FunctionPlan,
    first_instruction: u16,
    instruction_end: usize,
    reachability: FunctionControlReachability,
) ValidationError!bool {
    for (self.instructions[first_instruction..instruction_end]) |instruction| {
        if (instruction.kind == .return_error) {
            return true;
        } else if (instruction.kind == .call_helper) {
            if (instruction.operand >= self.functions.len) return error.InvalidCallHelperTarget;
            if (reachability.terminal[instruction.operand]) return true;
            if (!reachability.completion[instruction.operand]) return false;
        } else if (instruction.kind == .call_op) {
            if (instruction.operand >= self.ops.len or !functionOwnsOpTarget(self, function, instruction.operand)) {
                return error.InvalidCallOpTarget;
            }
            if (self.ops[instruction.operand].mode != .transform) return true;
        }
    }
    return false;
}

fn markFunctionExecutableBlocks(
    self: ProgramPlan,
    function: FunctionPlan,
    completion_reachability: *const [std.math.maxInt(u16) + 1]bool,
    executable_blocks: *[std.math.maxInt(u16) + 1]bool,
) ValidationError!void {
    const block_end = rangeEnd(function.first_block, function.block_count) orelse return error.InvalidFunctionBlockSpan;
    const entry_block_index = @as(usize, function.first_block) + function.entry_block;
    executable_blocks[entry_block_index] = true;

    var changed = true;
    while (changed) {
        changed = false;
        executable_block_scan: for (self.blocks[function.first_block..block_end], 0..) |block, relative_block_index| {
            const block_index = @as(usize, function.first_block) + relative_block_index;
            if (!executable_blocks[block_index]) continue :executable_block_scan;
            const instruction_end = rangeEnd(block.first_instruction, block.instruction_count) orelse return error.InvalidBlockInstructionSpan;
            if (!try blockCanResumeToTerminator(self, function, block.first_instruction, instruction_end, completion_reachability)) continue :executable_block_scan;
            const terminator = self.terminators[block.terminator_index];
            switch (terminator.kind) {
                .branch_if => {
                    if (isOwnedBlockTarget(function.first_block, block_end, terminator.primary) and
                        !executable_blocks[terminator.primary])
                    {
                        executable_blocks[terminator.primary] = true;
                        changed = true;
                    }
                    if (isOwnedBlockTarget(function.first_block, block_end, terminator.secondary) and
                        !executable_blocks[terminator.secondary])
                    {
                        executable_blocks[terminator.secondary] = true;
                        changed = true;
                    }
                },
                .jump => {
                    if (isOwnedBlockTarget(function.first_block, block_end, terminator.primary) and
                        !executable_blocks[terminator.primary])
                    {
                        executable_blocks[terminator.primary] = true;
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

fn loweredFunctionOp(
    comptime program: program_frontend.LoweredOpenRowProgram,
    comptime function_index: usize,
    comptime op_index: u16,
) PlanError!?effect_ir.OpSpec {
    var current_op_index: u16 = 0;
    for (program.functions, 0..) |function, owner_index| {
        for (function.row.requirements) |requirement| {
            for (requirement.ops) |op| {
                if (current_op_index == op_index) {
                    if (owner_index != function_index) return error.InvalidProgramBodyShape;
                    return op;
                }
                current_op_index += 1;
            }
        }
    }
    return error.InvalidProgramBodyShape;
}

fn loweredBlockCanResumeToTerminator(
    comptime program: program_frontend.LoweredOpenRowProgram,
    comptime function_index: usize,
    comptime block: effect_ir.Block,
    completion_reachability: *const [program.functions.len]bool,
) PlanError!bool {
    for (block.instructions) |instruction| {
        if (instruction.kind == .call_helper) {
            if (instruction.operand >= program.functions.len) return error.InvalidProgramBodyShape;
            if (!completion_reachability[instruction.operand]) return false;
        } else if (instruction.kind == .call_op) {
            const plan_op = (try loweredFunctionOp(program, function_index, instruction.operand)).?;
            if (plan_op.mode == .abort) return false;
        }
    }
    return true;
}

fn markLoweredFunctionExecutableBlocks(
    comptime program: program_frontend.LoweredOpenRowProgram,
    comptime function_index: usize,
    completion_reachability: *const [program.functions.len]bool,
    executable_blocks: *[program.function_bodies[function_index].blocks.len]bool,
) PlanError!void {
    const body = program.function_bodies[function_index];
    if (body.blocks.len == 0 or body.entry_block >= body.blocks.len) return error.InvalidProgramBodyShape;
    executable_blocks[body.entry_block] = true;

    var changed = true;
    while (changed) {
        changed = false;
        executable_block_scan: for (body.blocks, 0..) |block, block_index| {
            if (!executable_blocks[block_index]) continue :executable_block_scan;
            if (!try loweredBlockCanResumeToTerminator(program, function_index, block, completion_reachability)) continue :executable_block_scan;
            switch (block.terminator.kind) {
                .branch_if => {
                    if (block.terminator.primary >= body.blocks.len or block.terminator.secondary >= body.blocks.len) {
                        return error.InvalidProgramBodyShape;
                    }
                    if (!executable_blocks[block.terminator.primary]) {
                        executable_blocks[block.terminator.primary] = true;
                        changed = true;
                    }
                    if (!executable_blocks[block.terminator.secondary]) {
                        executable_blocks[block.terminator.secondary] = true;
                        changed = true;
                    }
                },
                .jump => {
                    if (block.terminator.primary >= body.blocks.len) return error.InvalidProgramBodyShape;
                    if (!executable_blocks[block.terminator.primary]) {
                        executable_blocks[block.terminator.primary] = true;
                        changed = true;
                    }
                },
                .return_unit, .return_value => {},
            }
        }
    }
}

fn loweredFunctionCanComplete(
    comptime program: program_frontend.LoweredOpenRowProgram,
    comptime function_index: usize,
    completion_reachability: *const [program.functions.len]bool,
) PlanError!bool {
    const body = program.function_bodies[function_index];
    var executable_blocks = [_]bool{false} ** body.blocks.len;
    try markLoweredFunctionExecutableBlocks(program, function_index, completion_reachability, &executable_blocks);
    for (body.blocks, 0..) |block, block_index| {
        if (!executable_blocks[block_index]) continue;
        if (!try loweredBlockCanResumeToTerminator(program, function_index, block, completion_reachability)) continue;
        switch (block.terminator.kind) {
            .return_unit, .return_value => return true,
            .branch_if, .jump => {},
        }
    }
    return false;
}

fn loweredBlockCanEscapeTerminally(
    comptime program: program_frontend.LoweredOpenRowProgram,
    comptime function_index: usize,
    comptime block: effect_ir.Block,
    completion_reachability: *const [program.functions.len]bool,
    terminal_reachability: *const [program.functions.len]bool,
) PlanError!bool {
    for (block.instructions) |instruction| {
        if (instruction.kind == .call_helper) {
            if (instruction.operand >= program.functions.len) return error.InvalidProgramBodyShape;
            if (terminal_reachability[instruction.operand]) return true;
            if (!completion_reachability[instruction.operand]) return false;
        } else if (instruction.kind == .call_op) {
            const plan_op = (try loweredFunctionOp(program, function_index, instruction.operand)).?;
            if (plan_op.mode != .transform) return true;
        }
    }
    return false;
}

fn loweredFunctionCanEscapeTerminally(
    comptime program: program_frontend.LoweredOpenRowProgram,
    comptime function_index: usize,
    completion_reachability: *const [program.functions.len]bool,
    terminal_reachability: *const [program.functions.len]bool,
) PlanError!bool {
    const body = program.function_bodies[function_index];
    var executable_blocks = [_]bool{false} ** body.blocks.len;
    try markLoweredFunctionExecutableBlocks(program, function_index, completion_reachability, &executable_blocks);
    for (body.blocks, 0..) |block, block_index| {
        if (!executable_blocks[block_index]) continue;
        if (try loweredBlockCanEscapeTerminally(program, function_index, block, completion_reachability, terminal_reachability)) return true;
    }
    return false;
}

fn loweredFunctionCompletionCodecReachability(
    comptime program: program_frontend.LoweredOpenRowProgram,
    comptime function_index: usize,
    completion_reachability: *const [program.functions.len]bool,
) PlanError!LoweredCompletionCodecs {
    const body = program.function_bodies[function_index];
    var plain_blocks = [_]bool{false} ** body.blocks.len;
    var after_blocks = [_]bool{false} ** body.blocks.len;
    plain_blocks[body.entry_block] = true;

    var completion_codecs = LoweredCompletionCodecs{};
    var changed = true;
    while (changed) {
        changed = false;
        completion_block_scan: for (body.blocks, 0..) |block, block_index| {
            if (!plain_blocks[block_index] and !after_blocks[block_index]) continue :completion_block_scan;
            if (!try loweredBlockCanResumeToTerminator(program, function_index, block, completion_reachability)) continue :completion_block_scan;
            const block_applies_after = try loweredBlockAppliesAfterOnCompletion(program, function_index, block);
            const completes_plain = plain_blocks[block_index] and !block_applies_after;
            const completes_after = after_blocks[block_index] or (plain_blocks[block_index] and block_applies_after);
            switch (block.terminator.kind) {
                .return_unit, .return_value => {
                    completion_codecs.value_codec = completion_codecs.value_codec or completes_plain;
                    completion_codecs.result_codec = completion_codecs.result_codec or completes_after;
                },
                .jump => {
                    if (completes_plain) changed = try markLoweredCompletionState(body.blocks.len, &plain_blocks, block.terminator.primary) or changed;
                    if (completes_after) changed = try markLoweredCompletionState(body.blocks.len, &after_blocks, block.terminator.primary) or changed;
                },
                .branch_if => {
                    if (completes_plain) {
                        changed = try markLoweredCompletionState(body.blocks.len, &plain_blocks, block.terminator.primary) or changed;
                        changed = try markLoweredCompletionState(body.blocks.len, &plain_blocks, block.terminator.secondary) or changed;
                    }
                    if (completes_after) {
                        changed = try markLoweredCompletionState(body.blocks.len, &after_blocks, block.terminator.primary) or changed;
                        changed = try markLoweredCompletionState(body.blocks.len, &after_blocks, block.terminator.secondary) or changed;
                    }
                },
            }
        }
    }
    return completion_codecs;
}

const LoweredCompletionCodecs = struct {
    value_codec: bool = false,
    result_codec: bool = false,
};

fn markLoweredCompletionState(
    comptime block_count: usize,
    states: *[block_count]bool,
    target: u16,
) PlanError!bool {
    if (target >= block_count) return error.InvalidProgramBodyShape;
    if (states[target]) return false;
    states[target] = true;
    return true;
}

fn loweredBlockAppliesAfterOnCompletion(
    comptime program: program_frontend.LoweredOpenRowProgram,
    comptime function_index: usize,
    comptime block: effect_ir.Block,
) PlanError!bool {
    for (block.instructions) |instruction| {
        if (instruction.kind != .call_op) continue;
        const plan_op = (try loweredFunctionOp(program, function_index, instruction.operand)).?;
        if (plan_op.has_after) return true;
    }
    return false;
}

fn loweredFunctionResultCodecReachability(
    comptime program: program_frontend.LoweredOpenRowProgram,
    comptime schema_types: anytype,
) PlanError![program.functions.len]bool {
    const program_result_ref = try valueRefForTypeInRegistry(schema_types, program.functions[program.entry_index].ValueType);
    var completion_reachability = [_]bool{false} ** program.functions.len;
    var terminal_reachability = [_]bool{false} ** program.functions.len;

    var changed = true;
    while (changed) {
        changed = false;
        function_completion_scan: for (program.functions, 0..) |_, function_index| {
            if (completion_reachability[function_index]) continue :function_completion_scan;
            if (try loweredFunctionCanComplete(program, function_index, &completion_reachability)) {
                completion_reachability[function_index] = true;
                changed = true;
            }
        }
    }

    changed = true;
    while (changed) {
        changed = false;
        function_terminal_scan: for (program.functions, 0..) |_, function_index| {
            if (terminal_reachability[function_index]) continue :function_terminal_scan;
            if (try loweredFunctionCanEscapeTerminally(program, function_index, &completion_reachability, &terminal_reachability)) {
                terminal_reachability[function_index] = true;
                changed = true;
            }
        }
    }

    var result_codec_reachability = [_]bool{false} ** program.functions.len;
    for (program.functions, 0..) |function, function_index| {
        const value_ref = try valueRefForTypeInRegistry(schema_types, function.ValueType);
        const completion_codecs = try loweredFunctionCompletionCodecReachability(program, function_index, &completion_reachability);
        if (!valueRefsEqual(value_ref, program_result_ref) and completion_codecs.value_codec and completion_codecs.result_codec) {
            return error.InvalidProgramBodyShape;
        }
        result_codec_reachability[function_index] =
            terminal_reachability[function_index] or completion_codecs.result_codec;
    }
    return result_codec_reachability;
}

fn invalidGeneratedPlan(err: ValidationError) noreturn {
    @compileError(switch (err) {
        error.EmptyFunctionSymbol => "runtime plan generator produced an empty function symbol",
        error.EmptyLabel => "runtime plan generator produced an empty label",
        error.EmptyOpName => "runtime plan generator produced an empty op name",
        error.EmptyOutputLabel => "runtime plan generator produced an empty output label",
        error.EmptyProgram => "runtime plan generator produced an empty program",
        error.EmptyRequirementLabel => "runtime plan generator produced an empty requirement label",
        error.EmptyValueFieldName => "runtime plan generator produced an empty value-schema field name",
        error.EmptyValueSchemaLabel => "runtime plan generator produced an empty value-schema label",
        error.EmptyValueVariantName => "runtime plan generator produced an empty value-schema variant name",
        error.DuplicateOutputLabel => "runtime plan generator produced duplicate output labels in one function",
        error.TooManyFunctionOutputs => "runtime plan generator produced too many outputs in one function",
        error.ProgramPlanTableTooLarge => "runtime plan generator produced a table larger than the u16-indexed executable profile",
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
        error.InvalidFunctionResultCodec => "runtime plan generator produced a function with mixed completion result codecs",
        error.InvalidInstructionCodec => "runtime plan generator produced an instruction whose encoded codec is invalid",
        error.InvalidInstructionLocalIndex => "runtime plan generator produced an instruction with an out-of-range function-local reference",
        error.InvalidNestedWithMetadata => "runtime plan generator produced an incomplete nested lexical-with metadata packet",
        error.InvalidValueSchemaCodec => "runtime plan generator produced a mismatched value-schema codec",
        error.InvalidValueSchemaIndex => "runtime plan generator produced an invalid value-schema index",
        error.InvalidValueSchemaSpan => "runtime plan generator produced an invalid value-schema table span",
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
    value_result_ref: ?ValueRef,
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
    comptime schema_types: anytype,
) PlanError!RowOnlyFunctionSynthesis {
    const function = program.functions[function_index];
    const function_value_ref: ?ValueRef = if (function.ValueType == void)
        null
    else
        try valueRefForTypeInRegistry(schema_types, function.ValueType);

    var helper_call_count: usize = 0;
    var forwarded_arg_count: usize = 0;
    var value_returning_helper_count: usize = 0;
    var value_result_ref: ?ValueRef = null;
    call_edge_scan: for (program.call_edges) |edge| {
        if (!edge.caller.eql(function.symbol)) continue :call_edge_scan;
        helper_call_count += 1;

        const callee_index = symbolIndex(program, edge.callee) orelse return error.UnknownSymbol;
        const callee = program.functions[callee_index];
        if (callee.parameter_codecs.len > function.parameter_codecs.len) return error.InvalidProgramBodyShape;
        for (callee.parameter_codecs, 0..) |codec, parameter_index| {
            if (function.parameter_codecs[parameter_index] != codec) return error.InvalidProgramBodyShape;
        }
        forwarded_arg_count += callee.parameter_codecs.len;

        if (callee.ValueType == void) continue :call_edge_scan;
        value_returning_helper_count += 1;
        const callee_value_ref = try valueRefForTypeInRegistry(schema_types, callee.ValueType);
        if (value_result_ref == null) {
            value_result_ref = callee_value_ref;
        } else if (!valueRefsEqual(value_result_ref.?, callee_value_ref)) {
            return error.InvalidProgramBodyShape;
        }
    }

    const value_result_local: ?u16 = if (value_result_ref == null)
        null
    else
        @intCast(function.parameter_codecs.len);
    const local_count = function.parameter_codecs.len + @intFromBool(value_result_local != null);
    const return_local: ?u16 = if (function_value_ref == null) blk: {
        break :blk null;
    } else if (value_result_local) |local_id| blk: {
        if (value_returning_helper_count > 1) return error.InvalidProgramBodyShape;
        if (!valueRefsEqual(value_result_ref.?, function_value_ref.?)) return error.InvalidProgramBodyShape;
        break :blk local_id;
    } else blk: {
        if (function.parameter_codecs.len != 1) return error.InvalidProgramBodyShape;
        if (!valueRefsEqual(
            .{ .codec = codecFromEffectIrBody(function.parameter_codecs[0]) },
            function_value_ref.?,
        )) {
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
        .value_result_ref = value_result_ref,
    };
}

fn countRowOnlyLocals(comptime program: effect_ir.Program, comptime schema_types: anytype) PlanError!usize {
    var total: usize = 0;
    for (program.functions, 0..) |_, function_index| {
        total += (try rowOnlyFunctionSynthesis(program, function_index, schema_types)).local_count;
    }
    return total;
}

fn countRowOnlyCallArgs(comptime program: effect_ir.Program, comptime schema_types: anytype) PlanError!usize {
    var total: usize = 0;
    for (program.functions, 0..) |_, function_index| {
        total += (try rowOnlyFunctionSynthesis(program, function_index, schema_types)).forwarded_arg_count;
    }
    return total;
}

fn countRowOnlyInstructions(comptime program: effect_ir.Program, comptime schema_types: anytype) PlanError!usize {
    var total: usize = 0;
    for (program.functions, 0..) |_, function_index| {
        const synthesis = try rowOnlyFunctionSynthesis(program, function_index, schema_types);
        total += synthesis.helper_call_count + @intFromBool(synthesis.return_local != null);
    }
    return total;
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
    const ir_hash = try irHashForProgram(program);
    const value_schema_registry = ValueSchemaRegistryForFunctions(program.functions);
    const schema_types = value_schema_registry.registered_schema_types[0..];
    const local_total = try countRowOnlyLocals(program, schema_types);
    const call_arg_total = try countRowOnlyCallArgs(program, schema_types);
    const instruction_total = try countRowOnlyInstructions(program, schema_types);

    const functions = comptime blk: {
        var buf: [program.functions.len]FunctionPlan = undefined;
        var requirement_index: u16 = 0;
        var output_index: u16 = 0;
        var local_index: u16 = 0;
        var instruction_index: u16 = 0;
        for (program.functions, 0..) |function, index| {
            const synthesis = try rowOnlyFunctionSynthesis(program, index, schema_types);
            const value_ref = try valueRefForTypeInRegistry(schema_types, function.ValueType);
            buf[index] = .{
                .symbol_name = function.symbol.symbol_name,
                .value_codec = value_ref.codec,
                .value_schema_index = value_ref.schema_index,
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
                    const payload_ref = try valueRefForTypeInRegistry(schema_types, op.PayloadType);
                    const resume_ref = try valueRefForTypeInRegistry(schema_types, op.ResumeType);
                    buf[op_index] = .{
                        .requirement_index = requirement_index,
                        .op_name = op.op_name,
                        .mode = controlModeFromIr(op.mode),
                        .payload_codec = payload_ref.codec,
                        .payload_schema_index = payload_ref.schema_index,
                        .resume_codec = resume_ref.codec,
                        .resume_schema_index = resume_ref.schema_index,
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
                const output_ref = try valueRefForTypeInRegistry(schema_types, output.OutputType);
                buf[output_index] = .{
                    .label = output.label,
                    .codec = output_ref.codec,
                    .schema_index = output_ref.schema_index,
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
            const synthesis = try rowOnlyFunctionSynthesis(program, function_index, schema_types);
            if (synthesis.value_result_ref) |value_ref| {
                buf[local_index] = .{
                    .codec = value_ref.codec,
                    .schema_index = value_ref.schema_index,
                };
                local_index += 1;
            }
        }
        break :blk buf;
    };

    const call_args = comptime blk: {
        var buf: [call_arg_total]u16 = undefined;
        var call_arg_index: usize = 0;
        for (program.functions) |function| {
            call_arg_edge_scan: for (program.call_edges) |edge| {
                if (!edge.caller.eql(function.symbol)) continue :call_arg_edge_scan;
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
            const caller_ref = program_plan_builder.function(@intCast(function_index));
            const synthesis = try rowOnlyFunctionSynthesis(program, function_index, schema_types);
            instruction_edge_scan: for (program.call_edges) |edge| {
                if (!edge.caller.eql(function.symbol)) continue :instruction_edge_scan;
                const callee_index = symbolIndex(program, edge.callee) orelse return error.UnknownSymbol;
                const callee = program.functions[callee_index];
                if (callee.ValueType == void) {
                    buf[instruction_index] = program_plan_builder.callHelperDiscardingResult(
                        caller_ref,
                        0,
                        program_plan_builder.function(@intCast(callee_index)),
                        call_arg_base,
                    );
                } else {
                    buf[instruction_index] = program_plan_builder.callHelper(
                        caller_ref,
                        program_plan_builder.local(caller_ref, synthesis.value_result_local orelse return error.InvalidProgramBodyShape),
                        program_plan_builder.function(@intCast(callee_index)),
                        call_arg_base,
                    ) catch |err| invalidGeneratedPlan(err);
                }
                instruction_index += 1;
                call_arg_base += @intCast(callee.parameter_codecs.len);
            }
            if (synthesis.return_local) |return_local| {
                buf[instruction_index] = program_plan_builder.returnValue(
                    caller_ref,
                    program_plan_builder.local(caller_ref, return_local),
                ) catch |err| invalidGeneratedPlan(err);
                instruction_index += 1;
            }
        }
        break :blk buf;
    };

    const plan = program_plan_builder.finish(.{
        .label = label,
        .ir_hash = ir_hash,
        .entry = program_plan_builder.function(@intCast(program.entry_index)),
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &outputs,
        .value_schemas = value_schema_registry.value_schemas[0..],
        .value_fields = value_schema_registry.value_fields[0..],
        .value_variants = value_schema_registry.value_variants[0..],
        .locals = &locals,
        .call_args = &call_args,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| invalidGeneratedPlan(err);
    return plan;
}

fn BindingSchemaFamily(comptime BindingSchema: type) type {
    if (@hasDecl(BindingSchema, "family")) return BindingSchema.family;
    if (@hasDecl(BindingSchema, "Family")) return BindingSchema.Family;
    @compileError("binding schema must declare family or Family");
}

fn bindingSchemaFamilyIfLabelMatches(comptime BindingSchema: type, comptime label: []const u8) ?type {
    if (std.mem.eql(u8, BindingSchema.requirement_label, label)) return BindingSchemaFamily(BindingSchema);
    return null;
}

fn bindingFamilyForLabelFromTupleType(comptime BindingSchemasType: type, comptime label: []const u8) ?type {
    inline for (@typeInfo(BindingSchemasType).@"struct".fields) |field| {
        if (bindingSchemaFamilyIfLabelMatches(field.type, label)) |family_schema| return family_schema;
    }
    return null;
}

fn bindingFamilyForLabel(comptime binding_schemas: anytype, comptime label: []const u8) ?type {
    if (@TypeOf(binding_schemas) == type) return bindingFamilyForLabelFromTupleType(binding_schemas, label);

    switch (@typeInfo(@TypeOf(binding_schemas))) {
        .@"struct" => |info| {
            inline for (info.fields) |field| {
                const BindingSchemaType = if (field.type == type) @field(binding_schemas, field.name) else field.type;
                if (bindingSchemaFamilyIfLabelMatches(BindingSchemaType, label)) |family_schema| return family_schema;
            }
        },
        .array => {
            inline for (binding_schemas) |BindingSchemaType| {
                if (bindingSchemaFamilyIfLabelMatches(BindingSchemaType, label)) |family_schema| return family_schema;
            }
        },
        .pointer => |pointer| {
            if (pointer.size != .one) {
                @compileError("binding schema pointers must point to a comptime tuple or array value");
            }
            return bindingFamilyForLabel(binding_schemas.*, label);
        },
        else => @compileError("binding schemas must be a tuple type, tuple value, array value, or pointer to one"),
    }
    return null;
}

fn requirementLifecycleFromBindingSchema(comptime FamilySchema: type) RequirementLifecycleTag {
    return std.meta.stringToEnum(RequirementLifecycleTag, @tagName(FamilySchema.lifecycle_tag)) orelse
        @compileError("binding schema lifecycle_tag must map to RequirementLifecycleTag");
}

fn requirementOutputFromBindingSchema(comptime FamilySchema: type) RequirementOutputTag {
    return std.meta.stringToEnum(RequirementOutputTag, @tagName(FamilySchema.output)) orelse
        @compileError("binding schema output tag must map to RequirementOutputTag");
}

const BindingSchemaEnrichmentMode = enum {
    exact,
    permissive,
};

fn enrichPlanWithBindingSchemasMode(
    comptime base_plan: ProgramPlan,
    comptime binding_schemas: anytype,
    comptime mode: BindingSchemaEnrichmentMode,
) ProgramPlan {
    const enriched_requirements = comptime blk: {
        var buffer: [base_plan.requirements.len]RequirementPlan = undefined;
        for (base_plan.requirements, 0..) |requirement, index| {
            const family_schema = bindingFamilyForLabel(binding_schemas, requirement.label);
            if (family_schema == null and mode == .exact) {
                @compileError(std.fmt.comptimePrint(
                    "exact ProgramPlan binding enrichment missing schema for requirement '{s}'",
                    .{requirement.label},
                ));
            }
            buffer[index] = .{
                .label = requirement.label,
                .first_op = requirement.first_op,
                .op_count = requirement.op_count,
                .lifecycle_tag = if (family_schema) |schema| requirementLifecycleFromBindingSchema(schema) else .plain_transform,
                .output_tag = if (family_schema) |schema| requirementOutputFromBindingSchema(schema) else .none,
            };
        }
        break :blk buffer;
    };

    return .{
        .schema_version = base_plan.schema_version,
        .label = base_plan.label,
        .ir_hash = base_plan.ir_hash,
        .entry_index = base_plan.entry_index,
        .functions = base_plan.functions,
        .requirements = &enriched_requirements,
        .ops = base_plan.ops,
        .outputs = base_plan.outputs,
        .value_schemas = base_plan.value_schemas,
        .value_fields = base_plan.value_fields,
        .value_variants = base_plan.value_variants,
        .locals = base_plan.locals,
        .call_args = base_plan.call_args,
        .blocks = base_plan.blocks,
        .terminators = base_plan.terminators,
        .instructions = base_plan.instructions,
    };
}

/// Attach binding-derived lifecycle and output metadata where matching schemas exist.
pub fn enrichPlanWithBindingSchemas(
    comptime base_plan: ProgramPlan,
    comptime binding_schemas: anytype,
) ProgramPlan {
    return enrichPlanWithBindingSchemasMode(base_plan, binding_schemas, .permissive);
}

/// Attach binding-derived lifecycle and output metadata, rejecting any unmatched requirement.
pub fn enrichPlanWithBindingSchemasExact(
    comptime base_plan: ProgramPlan,
    comptime binding_schemas: anytype,
) ProgramPlan {
    return enrichPlanWithBindingSchemasMode(base_plan, binding_schemas, .exact);
}

const source_path_compat_excluded_binding_tests = if (source_path_compat_mode) struct {} else struct {
    fn expectBindingSchemaEnrichmentPreservesPlanShape() !void {
        const base_plan = comptime ProgramPlan{
            .label = "effect_schema.enrichment",
            .ir_hash = 1,
            .entry_index = 0,
            .functions = &.{.{
                .symbol_name = "runBody",
                .value_codec = .string,
                .first_requirement = 0,
                .requirement_count = 2,
                .first_output = 0,
                .output_count = 2,
                .first_local = 0,
                .local_count = 0,
                .first_block = 0,
                .entry_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 0,
            }},
            .requirements = &.{
                .{ .label = "state", .first_op = 0, .op_count = 0 },
                .{ .label = "writer", .first_op = 0, .op_count = 0 },
            },
            .ops = &.{},
            .outputs = &.{
                .{ .label = "state", .codec = .i32 },
                .{ .label = "writer", .codec = .string_list },
            },
            .locals = &.{},
            .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
            .terminators = &.{.{ .kind = .return_value }},
            .instructions = &.{},
        };
        const state_family = struct {
            const lifecycle_tag = enum {
                abort_catch,
                choice_policy,
                generated_family,
                plain_transform,
                reader_environment,
                resource_bracket,
                state_cell,
                writer_accumulator,
            }.state_cell;
            const output = enum {
                accumulator,
                custom_finalizer,
                final_state,
                none,
            }.final_state;
        };
        const writer_family = struct {
            const lifecycle_tag = enum {
                abort_catch,
                choice_policy,
                generated_family,
                plain_transform,
                reader_environment,
                resource_bracket,
                state_cell,
                writer_accumulator,
            }.writer_accumulator;
            const output = enum {
                accumulator,
                custom_finalizer,
                final_state,
                none,
            }.accumulator;
        };
        const enriched = enrichPlanWithBindingSchemas(base_plan, .{
            struct {
                const requirement_label = "state";
                const family = state_family;
            },
            struct {
                const requirement_label = "writer";
                const family = writer_family;
            },
        });

        try std.testing.expectEqual(base_plan.requirements.len, enriched.requirements.len);
        try std.testing.expectEqual(RequirementLifecycleTag.state_cell, enriched.requirements[0].lifecycle_tag);
        try std.testing.expectEqual(RequirementOutputTag.final_state, enriched.requirements[0].output_tag);
        try std.testing.expectEqual(RequirementLifecycleTag.writer_accumulator, enriched.requirements[1].lifecycle_tag);
        try std.testing.expectEqual(RequirementOutputTag.accumulator, enriched.requirements[1].output_tag);

        const exact = enrichPlanWithBindingSchemasExact(base_plan, .{
            struct {
                const requirement_label = "state";
                const family = state_family;
            },
            struct {
                const requirement_label = "writer";
                const family = writer_family;
            },
        });
        try std.testing.expectEqual(RequirementLifecycleTag.state_cell, exact.requirements[0].lifecycle_tag);
        try std.testing.expectEqual(RequirementOutputTag.accumulator, exact.requirements[1].output_tag);

        const array_exact = enrichPlanWithBindingSchemasExact(base_plan, [_]type{
            struct {
                const requirement_label = "state";
                const family = state_family;
            },
            struct {
                const requirement_label = "writer";
                const family = writer_family;
            },
        });
        try std.testing.expectEqual(RequirementLifecycleTag.state_cell, array_exact.requirements[0].lifecycle_tag);
        try std.testing.expectEqual(RequirementOutputTag.accumulator, array_exact.requirements[1].output_tag);

        const pointer_exact = enrichPlanWithBindingSchemasExact(base_plan, &.{
            struct {
                const requirement_label = "state";
                const family = state_family;
            },
            struct {
                const requirement_label = "writer";
                const family = writer_family;
            },
        });
        try std.testing.expectEqual(RequirementLifecycleTag.state_cell, pointer_exact.requirements[0].lifecycle_tag);
        try std.testing.expectEqual(RequirementOutputTag.accumulator, pointer_exact.requirements[1].output_tag);
    }

    test "binding schema enrichment preserves plan shape while attaching lifecycle metadata" {
        try expectBindingSchemaEnrichmentPreservesPlanShape();
    }
};
comptime {
    _ = source_path_compat_excluded_binding_tests;
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
    const value_schema_registry = ValueSchemaRegistryForFunctions(program.functions);
    const schema_types = value_schema_registry.registered_schema_types[0..];
    const program_result_ref = try valueRefForTypeInRegistry(schema_types, program.functions[program.entry_index].ValueType);
    const result_codec_reachability = try loweredFunctionResultCodecReachability(program, schema_types);

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
            const value_ref = try valueRefForTypeInRegistry(schema_types, function.ValueType);
            buf[index] = .{
                .symbol_name = function.symbol.symbol_name,
                .value_codec = value_ref.codec,
                .value_schema_index = value_ref.schema_index,
                .result_codec = if (!valueRefsEqual(value_ref, program_result_ref) and result_codec_reachability[index])
                    program_result_ref.codec
                else
                    null,
                .result_schema_index = if (!valueRefsEqual(value_ref, program_result_ref) and result_codec_reachability[index])
                    program_result_ref.schema_index
                else
                    null,
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
                    const payload_ref = try valueRefForTypeInRegistry(schema_types, op.PayloadType);
                    const resume_ref = try valueRefForTypeInRegistry(schema_types, op.ResumeType);
                    buf[op_index] = .{
                        .requirement_index = requirement_index,
                        .op_name = op.op_name,
                        .mode = controlModeFromIr(op.mode),
                        .payload_codec = payload_ref.codec,
                        .payload_schema_index = payload_ref.schema_index,
                        .resume_codec = resume_ref.codec,
                        .resume_schema_index = resume_ref.schema_index,
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
                const output_ref = try valueRefForTypeInRegistry(schema_types, output.OutputType);
                buf[output_index] = .{
                    .label = output.label,
                    .codec = output_ref.codec,
                    .schema_index = output_ref.schema_index,
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
        for (program.function_bodies, 0..) |body, function_index| {
            const caller_ref = program_plan_builder.function(@intCast(function_index));
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
                    buf[instruction_index] = switch (instruction.kind) {
                        .call_helper => helper_call: {
                            if (target_returns_value) {
                                break :helper_call program_plan_builder.callHelper(
                                    caller_ref,
                                    program_plan_builder.local(caller_ref, instruction.dst),
                                    program_plan_builder.function(instruction.operand),
                                    if (target_parameter_count == 0) null else call_arg_base + instruction.aux,
                                ) catch |err| invalidGeneratedPlan(err);
                            }
                            break :helper_call program_plan_builder.callHelperDiscardingResult(
                                caller_ref,
                                std.math.maxInt(u16),
                                program_plan_builder.function(instruction.operand),
                                if (target_parameter_count == 0) null else call_arg_base + instruction.aux,
                            );
                        },
                        .call_op => call_op: {
                            if (instruction.operand >= ops.len) invalidGeneratedPlan(error.InvalidCallOpTarget);
                            const target_op = ops[instruction.operand];
                            break :call_op program_plan_builder.callOp(
                                caller_ref,
                                if (target_op.resume_codec == .unit) null else program_plan_builder.local(caller_ref, instruction.dst),
                                program_plan_builder.op(caller_ref, instruction.operand),
                                if (instruction.aux == std.math.maxInt(u16)) null else program_plan_builder.local(caller_ref, instruction.aux),
                            ) catch |err| invalidGeneratedPlan(err);
                        },
                        .return_value => program_plan_builder.returnValue(
                            caller_ref,
                            program_plan_builder.local(caller_ref, instruction.operand),
                        ) catch |err| invalidGeneratedPlan(err),
                        .add_const_i32, .add_i32, .call_nested_with, .compare_eq_zero, .const_i32, .const_string, .const_usize, .return_error, .sub_one => .{
                            .kind = instructionKindFromEffectIrBody(instruction.kind),
                            .dst = instruction.dst,
                            .operand = instruction.operand,
                            .aux = instruction.aux,
                            .string_literal = instruction.string_literal,
                        },
                    };
                    instruction_index += 1;
                }
            }
            call_arg_base += @intCast(body.call_arg_locals.len);
        }
        break :blk buf;
    };

    const plan = program_plan_builder.finish(.{
        .label = label,
        .ir_hash = ir_hash,
        .entry = program_plan_builder.function(@intCast(program.entry_index)),
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &outputs,
        .value_schemas = value_schema_registry.value_schemas[0..],
        .value_fields = value_schema_registry.value_fields[0..],
        .value_variants = value_schema_registry.value_variants[0..],
        .locals = &locals,
        .call_args = &call_args,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch |err| invalidGeneratedPlan(err);
    return plan;
}

test "codecForType covers scalar product and sum shapes" {
    const Product = struct {
        amount: i32,
        label: []const u8,
    };
    const Sum = union(enum) {
        accept: i32,
        reject,
    };
    const BareEnum = enum {
        first,
        second,
    };

    try std.testing.expectEqual(ValueCodec.unit, try codecForType(void));
    try std.testing.expectEqual(ValueCodec.bool, try codecForType(bool));
    try std.testing.expectEqual(ValueCodec.i32, try codecForType(i32));
    try std.testing.expectEqual(ValueCodec.usize, try codecForType(usize));
    try std.testing.expectEqual(ValueCodec.string, try codecForType([]const u8));
    try std.testing.expectEqual(ValueCodec.string_list, try codecForType([][]const u8));
    try std.testing.expectEqual(ValueCodec.product, try codecForType(Product));
    try std.testing.expectEqual(ValueCodec.sum, try codecForType(Sum));
    try std.testing.expectEqual(ValueCodec.sum, try codecForType(BareEnum));
    try std.testing.expectEqual(@as(usize, 2), try fieldCountForType(Product));
    try std.testing.expectEqual(@as(usize, 2), try variantCountForType(Sum));
    try std.testing.expectEqual(@as(usize, 2), try variantCountForType(BareEnum));
    try std.testing.expectError(error.UnsupportedCodecType, codecForType(*const i32));
    try std.testing.expect(!hasPayload(.unit));
    try std.testing.expect(hasPayload(.string));
}

test "ValueCodec preserves legacy serialized numeric tags" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ValueCodec.bool));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(ValueCodec.i32));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(ValueCodec.string));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(ValueCodec.string_list));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(ValueCodec.unit));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(ValueCodec.usize));
    try std.testing.expectEqual(@as(u8, 6), @intFromEnum(ValueCodec.product));
    try std.testing.expectEqual(@as(u8, 7), @intFromEnum(ValueCodec.sum));
    try std.testing.expectEqual(ValueCodec.string, try valueCodecFromInstructionAux(2));
    try std.testing.expectEqual(ValueCodec.string_list, try valueCodecFromInstructionAux(3));
    try std.testing.expectEqual(ValueCodec.unit, try valueCodecFromInstructionAux(4));
    try std.testing.expectEqual(ValueCodec.usize, try valueCodecFromInstructionAux(5));
}

test "planFromProgram derives product and sum schema refs for ops and outputs" {
    const Product = struct {
        amount: i32,
        label: []const u8,
    };
    const Decision = enum {
        accept,
        reject,
    };
    const row = comptime effect_ir.rowFromSpec(.{
        .approval = .{
            .request = effect_ir.Transform(Product, Decision),
        },
    });
    const program = effect_ir.Program{
        .functions = &.{.{
            .symbol = .{
                .module_path = "test/program_plan_codecs.zig",
                .symbol_name = "runBody",
            },
            .row = row,
            .ValueType = void,
            .outputs = &.{.{ .label = "approval", .OutputType = Product }},
        }},
        .call_edges = &.{},
    };
    const plan = comptime planFromProgram("codec.derived.product_sum", program) catch unreachable;

    try std.testing.expectEqual(@as(usize, 2), plan.value_schemas.len);
    try std.testing.expectEqual(ValueCodec.unit, plan.functions[0].value_codec);
    try std.testing.expectEqual(@as(?u16, null), plan.functions[0].value_schema_index);
    try std.testing.expectEqual(ValueCodec.product, plan.ops[0].payload_codec);
    try std.testing.expectEqual(@as(u16, 0), plan.ops[0].payload_schema_index.?);
    try std.testing.expectEqual(ValueCodec.sum, plan.ops[0].resume_codec);
    try std.testing.expectEqual(@as(u16, 1), plan.ops[0].resume_schema_index.?);
    try std.testing.expectEqual(ValueCodec.product, plan.outputs[0].codec);
    try std.testing.expectEqual(@as(u16, 0), plan.outputs[0].schema_index.?);
    try std.testing.expectEqual(@as(u16, 0), plan.value_schemas[0].first_field);
    try std.testing.expectEqual(@as(u16, 2), plan.value_schemas[0].field_count);
    try std.testing.expectEqual(@as(u16, 0), plan.value_schemas[1].first_variant);
    try std.testing.expectEqual(@as(u16, 2), plan.value_schemas[1].variant_count);
    try plan.validate();
}

test "program_plan_builder rejects cross-function refs before materializing a plan" {
    const root = program_plan_builder.function(0);
    const helper = program_plan_builder.function(1);

    try std.testing.expectError(
        error.InvalidInstructionLocalIndex,
        program_plan_builder.returnValue(root, program_plan_builder.local(helper, 0)),
    );
    try std.testing.expectError(
        error.InvalidInstructionLocalIndex,
        program_plan_builder.callHelper(root, program_plan_builder.local(helper, 0), helper, null),
    );
    try std.testing.expectError(
        error.InvalidCallOpTarget,
        program_plan_builder.callOp(root, null, program_plan_builder.op(helper, 0), null),
    );
}

test "planFromProgram lowers one simple state-writer IR shell into a runtime-owned plan" {
    comptime {
        @setEvalBranchQuota(20_000);
    }
    const row = comptime effect_ir.mergeRows(.{
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
    const shared_row = comptime effect_ir.rowFromSpec(.{
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
    const program = comptime effect_ir.Program{
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
    const shared_row = comptime effect_ir.rowFromSpec(.{
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
    const lowered = comptime program_frontend.LoweredOpenRowProgram{
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

    try std.testing.expectEqual(row_only_plan.schema_version, open_row_plan.schema_version);
    try std.testing.expectEqual(row_only_plan.ir_hash, open_row_plan.ir_hash);
    try std.testing.expectEqual(row_only_plan.entry_index, open_row_plan.entry_index);
    try std.testing.expectEqual(row_only_plan.functions.len, open_row_plan.functions.len);
    try std.testing.expectEqual(row_only_plan.requirements.len, open_row_plan.requirements.len);
    try std.testing.expectEqual(row_only_plan.ops.len, open_row_plan.ops.len);
    try std.testing.expectEqual(row_only_plan.outputs.len, open_row_plan.outputs.len);
    try std.testing.expectEqual(row_only_plan.locals.len, open_row_plan.locals.len);
    try std.testing.expectEqual(row_only_plan.call_args.len, open_row_plan.call_args.len);
    try std.testing.expectEqual(row_only_plan.blocks.len, open_row_plan.blocks.len);
    try std.testing.expectEqual(row_only_plan.terminators.len, open_row_plan.terminators.len);
    try std.testing.expectEqual(row_only_plan.instructions.len, open_row_plan.instructions.len);
    try std.testing.expectEqualStrings(row_only_plan.functions[0].symbol_name, open_row_plan.functions[0].symbol_name);
    try std.testing.expectEqual(row_only_plan.functions[0].instruction_count, open_row_plan.functions[0].instruction_count);
    try std.testing.expectEqual(row_only_plan.instructions[0].kind, open_row_plan.instructions[0].kind);
    try std.testing.expectEqualStrings(row_only_plan.ops[0].op_name, open_row_plan.ops[0].op_name);
}

test "planFromOpenRowProgram drops destinations for unit-resume ops" {
    const row = comptime effect_ir.rowFromSpec(.{
        .state = .{
            .set = effect_ir.Transform(i32, void),
        },
    });
    const root_symbol = effect_ir.SymbolRef{
        .module_path = "examples/unit_resume.zig",
        .symbol_name = "root",
    };
    const lowered = comptime program_frontend.LoweredOpenRowProgram{
        .entry_index = 0,
        .functions = &.{.{
            .symbol = root_symbol,
            .row = row,
            .ValueType = i32,
        }},
        .call_edges = &.{},
        .function_bodies = &.{.{
            .local_codecs = &.{.i32},
            .call_arg_locals = &.{},
            .entry_block = 0,
            .blocks = &.{.{
                .instructions = &.{
                    .{ .kind = .call_op, .dst = 0, .operand = 0, .aux = 0 },
                    .{ .kind = .return_value, .operand = 0 },
                },
                .terminator = .{ .kind = .return_value },
            }},
        }},
    };

    const plan = comptime try planFromOpenRowProgram("unit-resume", lowered);
    try std.testing.expectEqual(InstructionKind.call_op, plan.instructions[0].kind);
    try std.testing.expectEqual(std.math.maxInt(u16), plan.instructions[0].dst);
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

test "ProgramPlan.validate rejects duplicate output labels within one function" {
    const plan = ProgramPlan{
        .label = "invalid.duplicate_outputs",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 2,
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
        .outputs = &.{
            .{ .label = "result", .codec = .string },
            .{ .label = "result", .codec = .string },
        },
        .locals = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };

    try std.testing.expectError(error.DuplicateOutputLabel, plan.validate());
}

test "ProgramPlan.validate rejects too many outputs before label sorting" {
    const allocator = std.testing.allocator;
    const output_count = max_validated_function_outputs + 1;
    const outputs = try allocator.alloc(OutputPlan, output_count);
    defer allocator.free(outputs);
    for (outputs) |*output| {
        output.* = .{ .label = "result", .codec = .string };
    }

    const plan = ProgramPlan{
        .label = "invalid.too_many_outputs",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = @intCast(output_count),
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
        .outputs = outputs,
        .locals = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };

    try std.testing.expectError(error.TooManyFunctionOutputs, plan.validate());
}

test "ProgramPlan.validate rejects tables outside the u16-indexed profile" {
    const allocator = std.testing.allocator;
    const functions = try allocator.alloc(FunctionPlan, max_indexed_table_len + 1);
    defer allocator.free(functions);

    const plan = ProgramPlan{
        .label = "invalid.too_many_functions",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &.{},
        .terminators = &.{},
        .instructions = &.{},
    };

    try std.testing.expectError(error.ProgramPlanTableTooLarge, plan.validate());
}

test "upgradeLegacyProgramPlan preserves schema-1 function metadata when present" {
    const allocator = std.testing.allocator;
    var plan = ProgramPlan{
        .schema_version = 1,
        .label = "legacy.schema1.metadata",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = try allocator.dupe(FunctionPlan, &.{.{
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
        }}),
        .requirements = try allocator.dupe(RequirementPlan, &.{}),
        .ops = try allocator.dupe(OpPlan, &.{}),
        .outputs = try allocator.dupe(OutputPlan, &.{.{ .label = "result", .codec = .i32 }}),
        .locals = try allocator.dupe(LocalPlan, &.{ .{ .codec = .i32 }, .{ .codec = .i32 }, .{ .codec = .i32 } }),
        .call_args = try allocator.dupe(u16, &.{}),
        .blocks = try allocator.dupe(BlockPlan, &.{
            .{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 },
            .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 1 },
        }),
        .terminators = try allocator.dupe(Terminator, &.{
            .{ .kind = .jump, .primary = 1 },
            .{ .kind = .return_value },
        }),
        .instructions = try allocator.dupe(Instruction, &.{.{ .kind = .return_value, .dst = 0, .operand = 2, .aux = 0 }}),
    };

    var release_on_error = true;
    errdefer if (release_on_error) {
        allocator.free(plan.functions);
        allocator.free(plan.requirements);
        allocator.free(plan.ops);
        allocator.free(plan.outputs);
        allocator.free(plan.locals);
        allocator.free(plan.call_args);
        allocator.free(plan.blocks);
        allocator.free(plan.terminators);
        allocator.free(plan.instructions);
    };
    try upgradeLegacyProgramPlan(allocator, &plan);
    release_on_error = false;
    defer {
        allocator.free(plan.functions);
        allocator.free(plan.requirements);
        allocator.free(plan.ops);
        allocator.free(plan.outputs);
        allocator.free(plan.locals);
        allocator.free(plan.call_args);
        allocator.free(plan.blocks);
        allocator.free(plan.terminators);
        allocator.free(plan.instructions);
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

test "program_plan_builder.fromValidatedPlan preserves schema validation boundary" {
    const plan = ProgramPlan{
        .schema_version = 1,
        .label = "legacy.builder.validation",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
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
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };

    try std.testing.expectError(error.UnsupportedSchemaVersion, program_plan_builder.fromValidatedPlan(plan));
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
    try std.testing.expectError(error.InvalidFunctionEntryBlock, zero_block_plan.validate());

    const uncovered_instruction_plan = ProgramPlan{
        .label = "invalid.unowned_instruction_span.uncovered",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
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

test "ProgramPlan.validate accepts hexadecimal const_usize literals" {
    const plan = try program_plan_builder.fromValidatedPlan(.{
        .label = "valid.const_usize_hex",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .value_codec = .usize,
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
        .blocks = &.{.{
            .first_instruction = 0,
            .instruction_count = 2,
            .terminator_index = 0,
        }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{
                .kind = .const_usize,
                .dst = 0,
                .string_literal = "0xff",
            },
            .{
                .kind = .return_value,
                .operand = 0,
            },
        },
    });

    try plan.validate();
}

test "ProgramPlan.validate rejects const_i32 instructions targeting usize locals" {
    const plan = ProgramPlan{
        .label = "invalid.const_i32_into_usize",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .value_codec = .usize,
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
        .blocks = &.{.{
            .first_instruction = 0,
            .instruction_count = 2,
            .terminator_index = 0,
        }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{
                .kind = .const_i32,
                .dst = 0,
                .operand = @as(u16, @bitCast(@as(i16, -1))),
                .aux = @as(u16, @bitCast(@as(i16, -1))),
            },
            .{
                .kind = .return_value,
                .operand = 0,
            },
        },
    };

    try std.testing.expectError(error.InvalidInstructionLocalIndex, plan.validate());
}

test "ProgramPlan hash survives JSON roundtrip" {
    const plan = ProgramPlan{
        .label = "roundtrip",
        .ir_hash = 42,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .value_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 2,
            .first_local = 0,
            .local_count = 1,
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
        .outputs = &.{ .{
            .label = "writer",
            .codec = .string_list,
        }, .{
            .label = "approval",
            .codec = .product,
            .schema_index = 0,
        } },
        .value_schemas = &.{ .{
            .label = "Approval",
            .codec = .product,
            .first_field = 0,
            .field_count = 2,
        }, .{
            .label = "Decision",
            .codec = .sum,
            .first_variant = 0,
            .variant_count = 2,
        } },
        .value_fields = &.{ .{
            .name = "amount",
            .codec = .i32,
        }, .{
            .name = "label",
            .codec = .string,
        } },
        .value_variants = &.{ .{
            .name = "reject",
        }, .{
            .name = "accept",
            .codec = .i32,
        } },
        .locals = &.{.{ .codec = .i32 }},
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

test "ProgramPlan hash includes requirement semantics" {
    const base = ProgramPlan{
        .label = "hash.requirement_semantics",
        .ir_hash = 42,
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
            .instruction_count = 0,
        }},
        .requirements = &.{.{
            .label = "state",
            .first_op = 0,
            .op_count = 0,
            .lifecycle_tag = .plain_transform,
            .output_tag = .none,
        }},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };
    const enriched = ProgramPlan{
        .label = base.label,
        .ir_hash = base.ir_hash,
        .entry_index = base.entry_index,
        .functions = base.functions,
        .requirements = &.{.{
            .label = "state",
            .first_op = 0,
            .op_count = 0,
            .lifecycle_tag = .state_cell,
            .output_tag = .final_state,
        }},
        .ops = base.ops,
        .outputs = base.outputs,
        .locals = base.locals,
        .blocks = base.blocks,
        .terminators = base.terminators,
        .instructions = base.instructions,
    };

    try std.testing.expect(base.hash() != enriched.hash());
}
