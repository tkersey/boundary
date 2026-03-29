const effect_ir = @import("effect_ir");
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

/// One lowered operation descriptor in the runtime-owned executable plan.
pub const OpPlan = struct {
    requirement_index: u16,
    op_name: []const u8,
    mode: ControlMode,
    payload_codec: ValueCodec,
    resume_codec: ValueCodec,
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
    first_requirement: u16,
    requirement_count: u16,
    first_output: u16,
    output_count: u16,
    first_instruction: u16,
    instruction_count: u16,
};

/// Serializable instruction tags carried by the runtime-owned plan.
pub const InstructionKind = enum {
    call_helper,
    call_op,
    return_value,
};

/// One serializable placeholder instruction in the runtime-owned executable plan.
pub const Instruction = struct {
    kind: InstructionKind,
    index: u16,
};

/// Runtime-owned serializable executable plan for lowered or explicit IR programs.
pub const ProgramPlan = struct {
    /// Stable schema version for JSON-serialized runtime plans.
    pub const current_schema_version: u32 = 1;

    schema_version: u32 = current_schema_version,
    label: []const u8,
    ir_hash: u64,
    entry_index: u16,
    functions: []const FunctionPlan,
    requirements: []const RequirementPlan,
    ops: []const OpPlan,
    outputs: []const OutputPlan,
    instructions: []const Instruction,

    /// Validate that this runtime-owned plan is structurally self-contained.
    pub fn validate(self: @This()) ValidationError!void {
        if (self.schema_version != current_schema_version) return error.UnsupportedSchemaVersion;
        if (self.label.len == 0) return error.EmptyLabel;
        if (self.functions.len == 0) return error.EmptyProgram;
        if (self.entry_index >= self.functions.len) return error.InvalidEntryIndex;

        for (self.functions) |function| {
            if (function.symbol_name.len == 0) return error.EmptyFunctionSymbol;
            const requirement_end = rangeEnd(function.first_requirement, function.requirement_count) orelse return error.InvalidFunctionRequirementSpan;
            if (requirement_end > self.requirements.len) return error.InvalidFunctionRequirementSpan;
            const output_end = rangeEnd(function.first_output, function.output_count) orelse return error.InvalidFunctionOutputSpan;
            if (output_end > self.outputs.len) return error.InvalidFunctionOutputSpan;
            const instruction_end = rangeEnd(function.first_instruction, function.instruction_count) orelse return error.InvalidFunctionInstructionSpan;
            if (instruction_end > self.instructions.len) return error.InvalidFunctionInstructionSpan;
        }

        for (self.requirements) |requirement| {
            if (requirement.label.len == 0) return error.EmptyRequirementLabel;
            const op_end = rangeEnd(requirement.first_op, requirement.op_count) orelse return error.InvalidRequirementOpSpan;
            if (op_end > self.ops.len) return error.InvalidRequirementOpSpan;
        }

        for (self.ops) |op| {
            if (op.requirement_index >= self.requirements.len) return error.InvalidOpRequirementIndex;
            if (op.op_name.len == 0) return error.EmptyOpName;
        }

        for (self.outputs) |output| {
            if (output.label.len == 0) return error.EmptyOutputLabel;
        }

        for (self.instructions) |instruction| switch (instruction.kind) {
            .call_helper => {
                if (instruction.index >= self.functions.len) return error.InvalidCallHelperTarget;
            },
            .call_op => {
                if (instruction.index >= self.ops.len) return error.InvalidCallOpTarget;
            },
            .return_value => {
                if (instruction.index != 0) return error.InvalidReturnValueIndex;
            },
        };
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
            hasher.update(std.mem.asBytes(&function.first_requirement));
            hasher.update(std.mem.asBytes(&function.requirement_count));
            hasher.update(std.mem.asBytes(&function.first_output));
            hasher.update(std.mem.asBytes(&function.output_count));
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
        }
        for (self.outputs) |output| {
            hashBytes(&hasher, output.label);
            hashBytes(&hasher, @tagName(output.codec));
        }
        for (self.instructions) |instruction| {
            hashBytes(&hasher, @tagName(instruction.kind));
            hasher.update(std.mem.asBytes(&instruction.index));
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
    InvalidCallOpTarget,
    InvalidEntryIndex,
    InvalidFunctionInstructionSpan,
    InvalidFunctionOutputSpan,
    InvalidFunctionRequirementSpan,
    InvalidOpRequirementIndex,
    InvalidRequirementOpSpan,
    InvalidReturnValueIndex,
    UnsupportedSchemaVersion,
};
/// Error set for lowering comptime IR into a runtime-owned plan.
pub const PlanError = CodecError || effect_ir.NormalizeError || error{EmptyProgram};

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

fn rangeEnd(start: u16, len: u16) ?usize {
    const wide_start: usize = start;
    const wide_len: usize = len;
    return std.math.add(usize, wide_start, wide_len) catch null;
}

fn symbolIndex(comptime program: effect_ir.Program, comptime symbol: effect_ir.SymbolRef) ?u16 {
    for (program.functions, 0..) |function, index| {
        if (function.symbol.eql(symbol)) return @intCast(index);
    }
    return null;
}

fn invalidGeneratedPlan(err: ValidationError) noreturn {
    @compileError(switch (err) {
        error.EmptyFunctionSymbol => "runtime plan generator produced an empty function symbol",
        error.EmptyLabel => "runtime plan generator produced an empty label",
        error.EmptyOpName => "runtime plan generator produced an empty op name",
        error.EmptyOutputLabel => "runtime plan generator produced an empty output label",
        error.EmptyProgram => "runtime plan generator produced an empty program",
        error.EmptyRequirementLabel => "runtime plan generator produced an empty requirement label",
        error.InvalidCallHelperTarget => "runtime plan generator produced an out-of-range helper target",
        error.InvalidCallOpTarget => "runtime plan generator produced an out-of-range op target",
        error.InvalidEntryIndex => "runtime plan generator produced an invalid entry index",
        error.InvalidFunctionInstructionSpan => "runtime plan generator produced an invalid function instruction span",
        error.InvalidFunctionOutputSpan => "runtime plan generator produced an invalid function output span",
        error.InvalidFunctionRequirementSpan => "runtime plan generator produced an invalid function requirement span",
        error.InvalidOpRequirementIndex => "runtime plan generator produced an op with an invalid requirement index",
        error.InvalidRequirementOpSpan => "runtime plan generator produced an invalid requirement op span",
        error.InvalidReturnValueIndex => "runtime plan generator produced a return instruction with a non-zero index",
        error.UnsupportedSchemaVersion => "runtime plan generator produced an unsupported schema version",
    });
}

/// Compute a stable hash for the full normalized IR program identity.
pub fn irHashForProgram(comptime program: effect_ir.Program) PlanError!u64 {
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
    for (program.functions) |function| {
        const digest = try effect_ir.rowDigest(function.row, function.outputs);
        hashBytes(&hasher, function.symbol.module_path);
        hashBytes(&hasher, function.symbol.symbol_name);
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
    return hasher.final();
}

/// Lower one comptime effect-ir program into a runtime-owned executable plan shape.
pub fn planFromProgram(comptime label: []const u8, comptime program: effect_ir.Program) PlanError!ProgramPlan {
    if (program.functions.len == 0) return error.EmptyProgram;

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
    const instruction_total = comptime blk: {
        var total: usize = 0;
        for (program.functions) |function| {
            var helper_call_count: usize = 0;
            for (program.call_edges) |edge| {
                if (edge.caller.eql(function.symbol)) helper_call_count += 1;
            }
            total += helper_call_count + 1;
        }
        break :blk total;
    };
    const ir_hash = try irHashForProgram(program);

    const functions = comptime blk: {
        var buf: [program.functions.len]FunctionPlan = undefined;
        var requirement_index: u16 = 0;
        var output_index: u16 = 0;
        var instruction_index: u16 = 0;
        for (program.functions, 0..) |function, index| {
            var helper_call_count: usize = 0;
            for (program.call_edges) |edge| {
                if (edge.caller.eql(function.symbol)) helper_call_count += 1;
            }
            buf[index] = .{
                .symbol_name = function.symbol.symbol_name,
                .first_requirement = requirement_index,
                .requirement_count = @intCast(function.row.requirements.len),
                .first_output = output_index,
                .output_count = @intCast(function.outputs.len),
                .first_instruction = instruction_index,
                .instruction_count = @intCast(helper_call_count + 1),
            };
            requirement_index += @intCast(function.row.requirements.len);
            output_index += @intCast(function.outputs.len);
            instruction_index += @intCast(helper_call_count + 1);
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

    const instructions = comptime blk: {
        var buf: [instruction_total]Instruction = undefined;
        var instruction_index: usize = 0;
        for (program.functions) |function| {
            for (program.call_edges) |edge| {
                if (!edge.caller.eql(function.symbol)) continue;
                const callee_index = symbolIndex(program, edge.callee) orelse return error.UnknownSymbol;
                buf[instruction_index] = .{
                    .kind = .call_helper,
                    .index = callee_index,
                };
                instruction_index += 1;
            }
            buf[instruction_index] = .{
                .kind = .return_value,
                .index = 0,
            };
            instruction_index += 1;
        }
        break :blk buf;
    };

    const plan: ProgramPlan = .{
        .label = label,
        .ir_hash = ir_hash,
        .entry_index = 0,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &outputs,
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
    const plan = try planFromProgram("example.open_row_state_writer", program);

    try std.testing.expectEqual(@as(u16, 0), plan.entry_index);
    try std.testing.expectEqual(@as(usize, 1), plan.functions.len);
    try std.testing.expectEqual(@as(usize, 2), plan.requirements.len);
    try std.testing.expectEqual(@as(usize, 3), plan.ops.len);
    try std.testing.expectEqual(@as(usize, 2), plan.outputs.len);
    try std.testing.expectEqual(@as(usize, 1), plan.instructions.len);
    try std.testing.expectEqual(InstructionKind.return_value, plan.instructions[0].kind);
    try plan.validate();
}

test "planFromProgram hashes the whole program and makes helper calls self-contained" {
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

    const plan = try planFromProgram("example.workflow", program);
    const first_row_only_hash = try effect_ir.rowDigest(program.functions[0].row, program.functions[0].outputs);

    try std.testing.expect(plan.ir_hash != first_row_only_hash.hash);
    try std.testing.expectEqual(@as(usize, 3), plan.instructions.len);
    try std.testing.expectEqual(@as(u16, 0), plan.functions[0].first_instruction);
    try std.testing.expectEqual(@as(u16, 2), plan.functions[0].instruction_count);
    try std.testing.expectEqual(InstructionKind.call_helper, plan.instructions[0].kind);
    try std.testing.expectEqual(@as(u16, 1), plan.instructions[0].index);
    try std.testing.expectEqual(InstructionKind.return_value, plan.instructions[1].kind);
    try std.testing.expectEqual(InstructionKind.return_value, plan.instructions[2].kind);
    try plan.validate();
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
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .instructions = &.{.{
            .kind = .call_helper,
            .index = 1,
        }},
    };

    try std.testing.expectError(error.InvalidCallHelperTarget, plan.validate());
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
        .instructions = &.{.{
            .kind = .return_value,
            .index = 0,
        }},
    };

    const json = try std.json.stringifyAlloc(std.testing.allocator, plan, .{});
    defer std.testing.allocator.free(json);

    const parsed = try std.json.parseFromSlice(ProgramPlan, std.testing.allocator, json, .{});
    defer parsed.deinit();

    try parsed.value.validate();
    try std.testing.expectEqual(plan.hash(), parsed.value.hash());
}
