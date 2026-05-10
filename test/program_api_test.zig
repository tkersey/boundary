// zlinter-disable declaration_naming no_inferred_error_unions no_swallow_error require_doc_comment
const ability = @import("ability");
const plan_native_resource = @import("plan_native_resource");
const std = @import("std");

const interpreter_step_budget = 10_000;

fn expectRuntimeParked(runtime: *const ability.Runtime) !void {
    try std.testing.expectEqual(@as(usize, 0), runtime.core.active_reset_count);
}

fn expectLiveSessions(runtime: *const ability.Runtime, expected: usize) !void {
    try std.testing.expectEqual(expected, runtime.core.live_session_count);
}

const CountingAllocator = struct {
    child: std.mem.Allocator,
    alloc_calls: usize = 0,
    resize_calls: usize = 0,
    remap_calls: usize = 0,
    free_calls: usize = 0,
    total_allocated_bytes: usize = 0,
    largest_allocation_request: usize = 0,
    u16_aligned_alloc_calls: usize = 0,
    u16_aligned_allocated_bytes: usize = 0,
    largest_u16_alloc_request: usize = 0,

    fn init(child: std.mem.Allocator) @This() {
        return .{ .child = child };
    }

    fn allocator(self: *@This()) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.alloc_calls += 1;
        self.recordAllocationRequest(len, alignment);
        return self.child.rawAlloc(len, alignment, ret_addr);
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.resize_calls += 1;
        return self.child.rawResize(memory, alignment, new_len, ret_addr);
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.remap_calls += 1;
        self.recordAllocationRequest(new_len, alignment);
        return self.child.rawRemap(memory, alignment, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.free_calls += 1;
        self.child.rawFree(memory, alignment, ret_addr);
    }

    fn allocationEvents(self: @This()) usize {
        return self.alloc_calls + self.resize_calls + self.remap_calls;
    }

    fn recordAllocationRequest(self: *@This(), len: usize, alignment: std.mem.Alignment) void {
        self.total_allocated_bytes += len;
        self.largest_allocation_request = @max(self.largest_allocation_request, len);
        if (alignment == std.mem.Alignment.of(u16)) {
            self.u16_aligned_alloc_calls += 1;
            self.u16_aligned_allocated_bytes += len;
            self.largest_u16_alloc_request = @max(self.largest_u16_alloc_request, len);
        }
    }
};

fn compiledTransformPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const resume_local = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, resume_local, ability.ir.builder.op(root, 0), null) catch unreachable,
        ability.ir.builder.returnValue(root, resume_local) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
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
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "authored",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "dispatch",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .i32,
        .has_after = true,
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 1,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn choiceReturnNowPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const resume_local = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, resume_local, ability.ir.builder.op(root, 0), null) catch unreachable,
        ability.ir.builder.returnValue(root, resume_local) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
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
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "authored",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "dispatch",
        .mode = .choice,
        .payload_codec = .unit,
        .resume_codec = .i32,
        .has_after = true,
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 11,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn twoAfterPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const value = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, value, ability.ir.builder.op(root, 0), null) catch unreachable,
        ability.ir.builder.callOp(root, value, ability.ir.builder.op(root, 1), null) catch unreachable,
        ability.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 2,
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
    const requirements = [_]ability.ir.plan.Requirement{
        .{ .label = "first", .first_op = 0, .op_count = 1 },
        .{ .label = "second", .first_op = 1, .op_count = 1 },
    };
    const ops = [_]ability.ir.plan.Op{
        .{
            .requirement_index = 0,
            .op_name = "first",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .i32,
            .has_after = true,
        },
        .{
            .requirement_index = 1,
            .op_name = "second",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .i32,
            .has_after = true,
        },
    };
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 12,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn sessionChoicePlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const resume_local = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, resume_local, ability.ir.builder.op(root, 0), null) catch unreachable,
        ability.ir.builder.returnValue(root, resume_local) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
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
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "authored",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "choose",
        .mode = .choice,
        .payload_codec = .unit,
        .resume_codec = .i32,
        .has_after = false,
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 12,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn parameterizedIdentityPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const arg = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.returnValue(root, arg) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
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
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 21,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn stackedAfterPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const outer_resume = ability.ir.builder.local(root, 0);
    const inner_resume = ability.ir.builder.local(root, 1);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, outer_resume, ability.ir.builder.op(root, 0), null) catch unreachable,
        ability.ir.builder.callOp(root, inner_resume, ability.ir.builder.op(root, 1), null) catch unreachable,
        ability.ir.builder.returnValue(root, inner_resume) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .string,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 2,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{
        .{ .label = "outer", .first_op = 0, .op_count = 1 },
        .{ .label = "inner", .first_op = 1, .op_count = 1 },
    };
    const ops = [_]ability.ir.plan.Op{
        .{
            .requirement_index = 0,
            .op_name = "outer",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .i32,
            .has_after = true,
        },
        .{
            .requirement_index = 1,
            .op_name = "inner",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .i32,
            .has_after = true,
        },
    };
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 18,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn terminalBypassesAfterPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const resume_value = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, resume_value, ability.ir.builder.op(root, 0), null) catch unreachable,
        ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 1), null) catch unreachable,
        ability.ir.builder.returnValue(root, resume_value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .string,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 2,
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
    const requirements = [_]ability.ir.plan.Requirement{
        .{ .label = "outer", .first_op = 0, .op_count = 1 },
        .{ .label = "abort", .first_op = 1, .op_count = 1 },
    };
    const ops = [_]ability.ir.plan.Op{
        .{
            .requirement_index = 0,
            .op_name = "outer",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .i32,
            .has_after = true,
        },
        .{
            .requirement_index = 1,
            .op_name = "abort",
            .mode = .abort,
            .payload_codec = .unit,
            .resume_codec = .unit,
        },
    };
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 33,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn exceptionScalarThrowPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_i32, .dst = payload.index, .operand = 40 },
        ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 0), payload) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .result_codec = .i32,
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
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "exception",
        .first_op = 0,
        .op_count = 1,
        .lifecycle_tag = .abort_catch,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "throw",
        .mode = .abort,
        .payload_codec = .i32,
        .resume_codec = .unit,
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_unit }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 66,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn exceptionProductThrowPlan(comptime Payload: type, comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 0), payload) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .result_codec = .product,
        .result_schema_index = 0,
        .parameter_count = 1,
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
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "exception",
        .first_op = 0,
        .op_count = 1,
        .lifecycle_tag = .abort_catch,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "throw",
        .mode = .abort,
        .payload_codec = .product,
        .payload_schema_index = 0,
        .resume_codec = .unit,
    }};
    const schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Payload),
        .codec = .product,
        .first_field = 0,
        .field_count = 1,
    }};
    const fields = [_]ability.ir.ValueFieldPlan{.{
        .name = "amount",
        .codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_unit }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 67,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &schemas,
        .value_fields = &fields,
        .value_variants = &.{},
        .locals = &.{.{ .codec = .product, .schema_index = 0 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn exceptionSumThrowPlan(comptime Payload: type, comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 0), payload) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .result_codec = .i32,
        .parameter_count = 1,
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
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "exception",
        .first_op = 0,
        .op_count = 1,
        .lifecycle_tag = .abort_catch,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "throw",
        .mode = .abort,
        .payload_codec = .sum,
        .payload_schema_index = 0,
        .resume_codec = .unit,
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Payload),
        .codec = .sum,
        .first_variant = 0,
        .variant_count = 2,
    }};
    const value_variants = [_]ability.ir.ValueVariantPlan{
        .{ .name = "none", .codec = .unit },
        .{ .name = "some", .codec = .i32 },
    };
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_unit }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 68,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &.{},
        .value_variants = &value_variants,
        .locals = &.{.{ .codec = .sum, .schema_index = 0 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn nestedExceptionThrowPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const helper = ability.ir.builder.function(1);
    const root_value = ability.ir.builder.local(root, 0);
    const payload = ability.ir.builder.local(helper, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callHelper(root, root_value, helper, null) catch unreachable,
        ability.ir.builder.returnValue(root, root_value) catch unreachable,
        .{ .kind = .const_i32, .dst = payload.index, .operand = 70 },
        ability.ir.builder.callOp(helper, null, ability.ir.builder.op(helper, 0), payload) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
            .result_codec = .i32,
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
            .symbol_name = "helper",
            .value_codec = .unit,
            .result_codec = .i32,
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
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "exception",
        .first_op = 0,
        .op_count = 1,
        .lifecycle_tag = .abort_catch,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "throw",
        .mode = .abort,
        .payload_codec = .i32,
        .resume_codec = .unit,
    }};
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_unit },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 69,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn duplicateOperationNamesPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const left_value = ability.ir.builder.local(root, 0);
    const right_value = ability.ir.builder.local(root, 1);
    const total = ability.ir.builder.local(root, 2);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, left_value, ability.ir.builder.op(root, 0), null) catch unreachable,
        ability.ir.builder.callOp(root, right_value, ability.ir.builder.op(root, 1), null) catch unreachable,
        .{ .kind = .add_i32, .dst = total.index, .operand = left_value.index, .aux = right_value.index },
        ability.ir.builder.returnValue(root, total) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 2,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 3,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{
        .{ .label = "left", .first_op = 0, .op_count = 1 },
        .{ .label = "right", .first_op = 1, .op_count = 1 },
    };
    const ops = [_]ability.ir.plan.Op{
        .{ .requirement_index = 0, .op_name = "get", .mode = .transform, .payload_codec = .unit, .resume_codec = .i32 },
        .{ .requirement_index = 1, .op_name = "get", .mode = .transform, .payload_codec = .unit, .resume_codec = .i32 },
    };
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 34,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn invalidUnitPayloadOperandPlan(comptime label: []const u8) !ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const value = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .call_op, .dst = value.index, .operand = 0, .aux = 99 },
        ability.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
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
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "source", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "get",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 35,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    });
}

fn invalidUnitHelperDestinationPlan(comptime label: []const u8) !ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const helper = ability.ir.builder.function(1);
    const instructions = [_]ability.ir.plan.Instruction{.{ .kind = .call_helper, .dst = 99, .operand = helper.index }};
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
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
        },
        .{
            .symbol_name = "helper",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 1,
            .instruction_count = 0,
        },
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 0, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 36,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    });
}

const AuthoredHandlers = struct {
    base: i32,

    pub fn dispatch(self: *const @This()) !i32 {
        return self.base + 1;
    }

    pub fn afterDispatch(_: *const @This(), value: i32) !i32 {
        return value + 10;
    }
};

const Handlers = struct {
    authored: AuthoredHandlers,
};

const BoolHandlers = struct {
    probe: struct {
        pub fn dispatch(_: *const @This()) !bool {
            return false;
        }
    },
};

const UnitHandlers = struct {
    touch: struct {
        calls: *usize,

        pub fn dispatch(self: *const @This(), _: i32) !void {
            self.calls.* += 1;
        }
    },
};

const CompiledBody = struct {
    pub const compiled_plan = compiledTransformPlan("compiled-body");
};

fn voidReturnPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
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
    }};
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_unit }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 82,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &.{},
    }) catch unreachable;
}

fn stringLiteralPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const value = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_string, .dst = value.index, .string_literal = "scalar string" },
        ability.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .string,
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
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 83,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .string }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn overflowArithmeticPlan(comptime label: []const u8, comptime use_binary_add: bool) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const value = ability.ir.builder.local(root, 0);
    const rhs = ability.ir.builder.local(root, 1);
    const instructions = comptime if (use_binary_add) [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, value, ability.ir.builder.op(root, 0), null) catch unreachable,
        .{ .kind = .const_i32, .dst = rhs.index, .operand = 1 },
        .{ .kind = .add_i32, .dst = value.index, .operand = value.index, .aux = rhs.index },
        ability.ir.builder.returnValue(root, value) catch unreachable,
    } else [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, value, ability.ir.builder.op(root, 0), null) catch unreachable,
        .{ .kind = .add_const_i32, .dst = value.index, .operand = value.index, .aux = 1 },
        ability.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = if (use_binary_add) 2 else 1,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "source",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "source",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};
    const locals = comptime if (use_binary_add)
        [_]ability.ir.plan.Local{ .{ .codec = .i32 }, .{ .codec = .i32 } }
    else
        [_]ability.ir.plan.Local{.{ .codec = .i32 }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = if (use_binary_add) 17 else 16,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &locals,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn subOneOverflowPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const value = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, value, ability.ir.builder.op(root, 0), null) catch unreachable,
        .{ .kind = .sub_one, .dst = value.index, .operand = value.index },
        ability.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
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
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "source",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "source",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 19,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn unsupportedStructuredPayloadPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 0), payload) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
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
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "structured",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "structured",
        .mode = .transform,
        .payload_codec = .product,
        .payload_schema_index = 0,
        .resume_codec = .unit,
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = "Payload",
        .codec = .product,
        .first_field = 0,
        .field_count = 1,
    }};
    const value_fields = [_]ability.ir.ValueFieldPlan{.{
        .name = "amount",
        .codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_unit }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 15,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &value_fields,
        .value_variants = &.{},
        .locals = &.{.{ .codec = .product, .schema_index = 0 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn scalarPlanWithUnreachableStructuredSchema(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const helper = ability.ir.builder.function(1);
    const helper_value = ability.ir.builder.local(helper, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.returnValue(helper, helper_value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
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
        },
        .{
            .symbol_name = "dead_helper",
            .value_codec = .product,
            .value_schema_index = 0,
            .parameter_count = 0,
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
            .instruction_count = @intCast(instructions.len),
        },
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 },
        .{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_value },
    };
    const value_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = "DeadPayload",
        .codec = .product,
        .first_field = 0,
        .field_count = 1,
    }};
    const value_fields = [_]ability.ir.ValueFieldPlan{.{
        .name = "amount",
        .codec = .i32,
    }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 90,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &value_fields,
        .value_variants = &.{},
        .locals = &.{.{ .codec = .product, .schema_index = 0 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn productIdentityPlan(comptime Payload: type, comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.returnValue(root, payload) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .product,
        .value_schema_index = 0,
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
        .instruction_count = @intCast(instructions.len),
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Payload),
        .codec = .product,
        .first_field = 0,
        .field_count = 1,
    }};
    const value_fields = [_]ability.ir.ValueFieldPlan{.{
        .name = "amount",
        .codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 23,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &value_fields,
        .value_variants = &.{},
        .locals = &.{.{ .codec = .product, .schema_index = 0 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn sumIdentityPlan(comptime Payload: type, comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.returnValue(root, payload) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .sum,
        .value_schema_index = 0,
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
        .instruction_count = @intCast(instructions.len),
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Payload),
        .codec = .sum,
        .first_variant = 0,
        .variant_count = 2,
    }};
    const value_variants = [_]ability.ir.ValueVariantPlan{
        .{ .name = "none", .codec = .unit },
        .{ .name = "some", .codec = .i32 },
    };
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 24,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &.{},
        .value_variants = &value_variants,
        .locals = &.{.{ .codec = .sum, .schema_index = 0 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn sumVariantBranchPlan(comptime Payload: type, comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const condition = ability.ir.builder.local(root, 1);
    const result = ability.ir.builder.local(root, 2);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.sumVariantIs(root, condition, payload, 1) catch unreachable,
        .{ .kind = .const_i32, .dst = result.index, .operand = 11 },
        ability.ir.builder.returnValue(root, result) catch unreachable,
        .{ .kind = .const_i32, .dst = result.index, .operand = 22 },
        ability.ir.builder.returnValue(root, result) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 3,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 3,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Payload),
        .codec = .sum,
        .first_variant = 0,
        .variant_count = 2,
    }};
    const value_variants = [_]ability.ir.ValueVariantPlan{
        .{ .name = "none", .codec = .unit },
        .{ .name = "some", .codec = .i32 },
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 2, .terminator_index = 1 },
        .{ .first_instruction = 3, .instruction_count = 2, .terminator_index = 2 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 34,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &.{},
        .value_variants = &value_variants,
        .locals = &.{ .{ .codec = .sum, .schema_index = 0 }, .{ .codec = .bool }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn sumPayloadExtractionPlan(comptime Payload: type, comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const extracted = ability.ir.builder.local(root, 1);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.sumExtractPayload(root, extracted, payload, 1) catch unreachable,
        ability.ir.builder.returnValue(root, extracted) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Payload),
        .codec = .sum,
        .first_variant = 0,
        .variant_count = 2,
    }};
    const value_variants = [_]ability.ir.ValueVariantPlan{
        .{ .name = "none", .codec = .unit },
        .{ .name = "some", .codec = .i32 },
    };
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 35,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &.{},
        .value_variants = &value_variants,
        .locals = &.{ .{ .codec = .sum, .schema_index = 0 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn enumVariantBranchPlan(comptime Payload: type, comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const condition = ability.ir.builder.local(root, 1);
    const result = ability.ir.builder.local(root, 2);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.sumVariantIs(root, condition, payload, 1) catch unreachable,
        .{ .kind = .const_i32, .dst = result.index, .operand = 11 },
        ability.ir.builder.returnValue(root, result) catch unreachable,
        .{ .kind = .const_i32, .dst = result.index, .operand = 22 },
        ability.ir.builder.returnValue(root, result) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 3,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 3,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Payload),
        .codec = .sum,
        .first_variant = 0,
        .variant_count = 2,
    }};
    const value_variants = [_]ability.ir.ValueVariantPlan{
        .{ .name = "none", .codec = .unit },
        .{ .name = "yes", .codec = .unit },
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 2, .terminator_index = 1 },
        .{ .first_instruction = 3, .instruction_count = 2, .terminator_index = 2 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 37,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &.{},
        .value_variants = &value_variants,
        .locals = &.{ .{ .codec = .sum, .schema_index = 0 }, .{ .codec = .bool }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn taggedUnionPayloadExtractionPlan(comptime Payload: type, comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const extracted = ability.ir.builder.local(root, 1);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.sumExtractPayload(root, extracted, payload, 1) catch unreachable,
        ability.ir.builder.returnValue(root, extracted) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Payload),
        .codec = .sum,
        .first_variant = 0,
        .variant_count = 2,
    }};
    const value_variants = [_]ability.ir.ValueVariantPlan{
        .{ .name = "none", .codec = .unit },
        .{ .name = "yes", .codec = .i32 },
    };
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 38,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &.{},
        .value_variants = &value_variants,
        .locals = &.{ .{ .codec = .sum, .schema_index = 0 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn validateSingleSumInstruction(
    comptime instruction: ability.ir.plan.Instruction,
    comptime locals: []const ability.ir.plan.Local,
) !ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const instructions = [_]ability.ir.plan.Instruction{instruction};
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 0,
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
    const value_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = "?i32",
        .codec = .sum,
        .first_variant = 0,
        .variant_count = 2,
    }};
    const value_variants = [_]ability.ir.ValueVariantPlan{
        .{ .name = "none", .codec = .unit },
        .{ .name = "some", .codec = .i32 },
    };
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_unit }};

    return ability.ir.builder.finish(.{
        .label = "single-sum-instruction",
        .ir_hash = 36,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &.{},
        .value_variants = &value_variants,
        .locals = locals,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    });
}

fn duplicateSchemaIdentityPlan(comptime Payload: type, comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.returnValue(root, payload) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .product,
        .value_schema_index = 1,
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
        .instruction_count = @intCast(instructions.len),
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{
        .{
            .label = @typeName(Payload),
            .codec = .product,
            .first_field = 0,
            .field_count = 1,
        },
        .{
            .label = @typeName(Payload),
            .codec = .product,
            .first_field = 1,
            .field_count = 1,
        },
    };
    const value_fields = [_]ability.ir.ValueFieldPlan{
        .{ .name = "amount", .codec = .i32 },
        .{ .name = "amount", .codec = .i32 },
    };
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 31,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &value_fields,
        .value_variants = &.{},
        .locals = &.{.{ .codec = .product, .schema_index = 1 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn duplicateSchemaSumPayloadExtractionPlan(comptime SumPayload: type, comptime Item: type, comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const extracted = ability.ir.builder.local(root, 1);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.sumExtractPayload(root, extracted, payload, 1) catch unreachable,
        ability.ir.builder.returnValue(root, extracted) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .product,
        .value_schema_index = 2,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{
        .{
            .label = @typeName(SumPayload),
            .codec = .sum,
            .first_variant = 0,
            .variant_count = 2,
        },
        .{
            .label = @typeName(Item),
            .codec = .product,
            .first_field = 0,
            .field_count = 1,
            .first_variant = 2,
        },
        .{
            .label = @typeName(Item),
            .codec = .product,
            .first_field = 1,
            .field_count = 1,
            .first_variant = 2,
        },
    };
    const value_fields = [_]ability.ir.ValueFieldPlan{
        .{ .name = "amount", .codec = .i32 },
        .{ .name = "amount", .codec = .i32 },
    };
    const value_variants = [_]ability.ir.ValueVariantPlan{
        .{ .name = "none", .codec = .unit },
        .{ .name = "some", .codec = .product, .schema_index = 2 },
    };
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 39,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &value_fields,
        .value_variants = &value_variants,
        .locals = &.{ .{ .codec = .sum, .schema_index = 0 }, .{ .codec = .product, .schema_index = 2 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn duplicateSchemaAbortResultPlan(comptime Payload: type, comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 0), null) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .product,
        .value_schema_index = 1,
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
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "structured",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "structured",
        .mode = .abort,
        .payload_codec = .unit,
        .resume_codec = .unit,
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{
        .{
            .label = @typeName(Payload),
            .codec = .product,
            .first_field = 0,
            .field_count = 1,
        },
        .{
            .label = @typeName(Payload),
            .codec = .product,
            .first_field = 1,
            .field_count = 1,
        },
    };
    const value_fields = [_]ability.ir.ValueFieldPlan{
        .{ .name = "amount", .codec = .i32 },
        .{ .name = "amount", .codec = .i32 },
    };
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_unit }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 32,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &value_fields,
        .value_variants = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn duplicateSchemaPayloadPlan(comptime Payload: type, comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 0), payload) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .parameter_count = 1,
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
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "structured",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "payload",
        .mode = .transform,
        .payload_codec = .product,
        .payload_schema_index = 1,
        .resume_codec = .unit,
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{
        .{
            .label = @typeName(Payload),
            .codec = .product,
            .first_field = 0,
            .field_count = 1,
        },
        .{
            .label = @typeName(Payload),
            .codec = .product,
            .first_field = 1,
            .field_count = 1,
        },
    };
    const value_fields = [_]ability.ir.ValueFieldPlan{
        .{ .name = "amount", .codec = .i32 },
        .{ .name = "amount", .codec = .i32 },
    };
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_unit }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 34,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &value_fields,
        .value_variants = &.{},
        .locals = &.{.{ .codec = .product, .schema_index = 1 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn duplicateSchemaAfterResultPlan(comptime Payload: type, comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const resumed = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, resumed, ability.ir.builder.op(root, 0), null) catch unreachable,
        ability.ir.builder.returnValue(root, resumed) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .product,
        .value_schema_index = 1,
        .result_codec = .product,
        .result_schema_index = 1,
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
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "structured",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "structured",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .product,
        .resume_schema_index = 1,
        .has_after = true,
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{
        .{
            .label = @typeName(Payload),
            .codec = .product,
            .first_field = 0,
            .field_count = 1,
        },
        .{
            .label = @typeName(Payload),
            .codec = .product,
            .first_field = 1,
            .field_count = 1,
        },
    };
    const value_fields = [_]ability.ir.ValueFieldPlan{
        .{ .name = "amount", .codec = .i32 },
        .{ .name = "amount", .codec = .i32 },
    };
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 33,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &value_fields,
        .value_variants = &.{},
        .locals = &.{.{ .codec = .product, .schema_index = 1 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn structuredPayloadOpPlan(comptime Payload: type, comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 0), payload) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .parameter_count = 1,
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
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "structured",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "structured",
        .mode = .transform,
        .payload_codec = .product,
        .payload_schema_index = 0,
        .resume_codec = .unit,
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Payload),
        .codec = .product,
        .first_field = 0,
        .field_count = 1,
    }};
    const value_fields = [_]ability.ir.ValueFieldPlan{.{
        .name = "amount",
        .codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_unit }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 24,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &value_fields,
        .value_variants = &.{},
        .locals = &.{.{ .codec = .product, .schema_index = 0 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn structuredHelperPlan(comptime Payload: type, comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const helper = ability.ir.builder.function(1);
    const root_arg = ability.ir.builder.local(root, 0);
    const root_result = ability.ir.builder.local(root, 1);
    const helper_arg = ability.ir.builder.local(helper, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callHelper(root, root_result, helper, 0) catch unreachable,
        ability.ir.builder.returnValue(root, root_result) catch unreachable,
        ability.ir.builder.returnValue(helper, helper_arg) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .product,
            .value_schema_index = 0,
            .parameter_count = 1,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 2,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        },
        .{
            .symbol_name = "helper",
            .value_codec = .product,
            .value_schema_index = 0,
            .parameter_count = 1,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 2,
            .local_count = 1,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 2,
            .instruction_count = 1,
        },
    };
    const value_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Payload),
        .codec = .product,
        .first_field = 0,
        .field_count = 1,
    }};
    const value_fields = [_]ability.ir.ValueFieldPlan{.{
        .name = "amount",
        .codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 25,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &value_fields,
        .value_variants = &.{},
        .locals = &.{
            .{ .codec = .product, .schema_index = 0 },
            .{ .codec = .product, .schema_index = 0 },
            .{ .codec = .product, .schema_index = 0 },
        },
        .call_args = &.{root_arg.index},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn parameterizedHelperPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const helper = ability.ir.builder.function(1);
    const root_arg = ability.ir.builder.local(root, 0);
    const root_result = ability.ir.builder.local(root, 1);
    const helper_arg = ability.ir.builder.local(helper, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callHelper(root, root_result, helper, 0) catch unreachable,
        ability.ir.builder.returnValue(root, root_result) catch unreachable,
        ability.ir.builder.returnValue(helper, helper_arg) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
            .parameter_count = 1,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 2,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        },
        .{
            .symbol_name = "helper",
            .value_codec = .i32,
            .parameter_count = 1,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 2,
            .local_count = 1,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 2,
            .instruction_count = 1,
        },
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };
    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 49,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 }, .{ .codec = .i32 } },
        .call_args = &.{root_arg.index},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn recursiveCountdownHelperPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const helper = ability.ir.builder.function(1);
    const root_arg = ability.ir.builder.local(root, 0);
    const root_result = ability.ir.builder.local(root, 1);
    const helper_arg = ability.ir.builder.local(helper, 0);
    const helper_next = ability.ir.builder.local(helper, 1);
    const helper_cond = ability.ir.builder.local(helper, 2);
    const helper_result = ability.ir.builder.local(helper, 3);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callHelper(root, root_result, helper, 0) catch unreachable,
        ability.ir.builder.returnValue(root, root_result) catch unreachable,
        .{ .kind = .compare_eq_zero, .dst = helper_cond.index, .operand = helper_arg.index },
        ability.ir.builder.returnValue(helper, helper_arg) catch unreachable,
        .{ .kind = .sub_one, .dst = helper_next.index, .operand = helper_arg.index },
        ability.ir.builder.callHelper(helper, helper_result, helper, 1) catch unreachable,
        ability.ir.builder.returnValue(helper, helper_result) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
            .parameter_count = 1,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 2,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        },
        .{
            .symbol_name = "countdown",
            .value_codec = .i32,
            .parameter_count = 1,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 2,
            .local_count = 4,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 3,
            .first_instruction = 2,
            .instruction_count = 5,
        },
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 1, .terminator_index = 1 },
        .{ .first_instruction = 3, .instruction_count = 1, .terminator_index = 2 },
        .{ .first_instruction = 4, .instruction_count = 3, .terminator_index = 3 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .branch_if, .primary = 2, .secondary = 3 },
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 27,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{
            .{ .codec = .i32 },
            .{ .codec = .i32 },
            .{ .codec = .i32 },
            .{ .codec = .i32 },
            .{ .codec = .bool },
            .{ .codec = .i32 },
        },
        .call_args = &.{ root_arg.index, helper_next.index },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn unboundedHelperCyclePlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const helper = ability.ir.builder.function(1);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callHelper(root, null, helper, null) catch unreachable,
        ability.ir.builder.callHelper(helper, null, helper, null) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
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
        },
        .{
            .symbol_name = "loop",
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 0,
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
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 28,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

const nested_with_metadata = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi";

fn resolvedNestedWithPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const nested = ability.ir.builder.function(1);
    const root_value = ability.ir.builder.local(root, 0);
    const nested_value = ability.ir.builder.local(nested, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        .{
            .kind = .call_nested_with,
            .dst = root_value.index,
            .aux = @intFromEnum(ability.ir.ValueCodec.i32),
            .string_literal = nested_with_metadata,
        },
        ability.ir.builder.returnValue(root, root_value) catch unreachable,
        .{ .kind = .const_i32, .dst = nested_value.index, .operand = 42 },
        ability.ir.builder.returnValue(nested, nested_value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
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
        },
        .{
            .symbol_name = "nested",
            .value_codec = .i32,
            .parameter_count = 0,
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
            .instruction_count = 2,
        },
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 29,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn resolvedNestedWithStringListPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const nested = ability.ir.builder.function(1);
    const root_value = ability.ir.builder.local(root, 0);
    const nested_value = ability.ir.builder.local(nested, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        .{
            .kind = .call_nested_with,
            .dst = root_value.index,
            .aux = @intFromEnum(ability.ir.ValueCodec.string_list),
            .string_literal = nested_with_metadata,
        },
        ability.ir.builder.returnValue(root, root_value) catch unreachable,
        ability.ir.builder.callOp(nested, nested_value, ability.ir.builder.op(nested, 0), null) catch unreachable,
        ability.ir.builder.returnValue(nested, nested_value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
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
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "authored",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "dispatch",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .string_list,
    }};
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 49,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .string_list }, .{ .codec = .string_list } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn stringListIdentityPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const value = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .string_list,
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
    }};
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 51,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .string_list }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn resolvedNestedWithSplitCompletionPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const nested = ability.ir.builder.function(1);
    const root_value = ability.ir.builder.local(root, 0);
    const nested_value = ability.ir.builder.local(nested, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        .{
            .kind = .call_nested_with,
            .dst = root_value.index,
            .aux = @intFromEnum(ability.ir.ValueCodec.i32),
            .string_literal = nested_with_metadata,
        },
        ability.ir.builder.returnValue(root, root_value) catch unreachable,
        .{ .kind = .const_i32, .dst = nested_value.index, .operand = 42 },
        ability.ir.builder.returnValue(nested, nested_value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
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
            .value_codec = .i32,
            .result_codec = .string,
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
            .instruction_count = 2,
        },
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 48,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn resolvedNestedWithAfterCompletionPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const nested = ability.ir.builder.function(1);
    const root_value = ability.ir.builder.local(root, 0);
    const nested_value = ability.ir.builder.local(nested, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        .{
            .kind = .call_nested_with,
            .dst = root_value.index,
            .aux = @intFromEnum(ability.ir.ValueCodec.string),
            .string_literal = nested_with_metadata,
        },
        ability.ir.builder.returnValue(root, root_value) catch unreachable,
        ability.ir.builder.callOp(nested, nested_value, ability.ir.builder.op(nested, 0), null) catch unreachable,
        ability.ir.builder.returnValue(nested, nested_value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .string,
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
            .value_codec = .i32,
            .result_codec = .string,
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
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "authored",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "dispatch",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .i32,
        .has_after = true,
    }};
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 50,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .string }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn terminalNestedWithSplitResultPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const nested = ability.ir.builder.function(1);
    const instructions = [_]ability.ir.plan.Instruction{
        .{
            .kind = .call_nested_with,
            .aux = @intFromEnum(ability.ir.ValueCodec.unit),
            .string_literal = nested_with_metadata,
        },
        ability.ir.builder.callOp(nested, null, ability.ir.builder.op(nested, 0), null) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
            .result_codec = .string,
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
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "abort",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "dispatch",
        .mode = .abort,
        .payload_codec = .unit,
        .resume_codec = .unit,
    }};
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
    };

    const targets = .{ability.ir.NestedWithTarget{
        .metadata = nested_with_metadata,
        .function_index = nested.index,
    }};
    return ability.ir.builder.finishWithNestedTargets(.{
        .label = label,
        .ir_hash = 51,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }, targets) catch unreachable;
}

fn helperNestedWithPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const helper = ability.ir.builder.function(1);
    const nested = ability.ir.builder.function(2);
    const root_value = ability.ir.builder.local(root, 0);
    const helper_value = ability.ir.builder.local(helper, 0);
    const nested_value = ability.ir.builder.local(nested, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callHelper(root, root_value, helper, null) catch unreachable,
        ability.ir.builder.returnValue(root, root_value) catch unreachable,
        .{
            .kind = .call_nested_with,
            .dst = helper_value.index,
            .aux = @intFromEnum(ability.ir.ValueCodec.i32),
            .string_literal = nested_with_metadata,
        },
        ability.ir.builder.returnValue(helper, helper_value) catch unreachable,
        .{ .kind = .const_i32, .dst = nested_value.index, .operand = 64 },
        ability.ir.builder.returnValue(nested, nested_value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
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
            .symbol_name = "helper",
            .value_codec = .i32,
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
            .instruction_count = 2,
        },
        .{
            .symbol_name = "nested",
            .value_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 2,
            .local_count = 1,
            .first_block = 2,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 4,
            .instruction_count = 2,
        },
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
        .{ .first_instruction = 4, .instruction_count = 2, .terminator_index = 2 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 62,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn terminalNestedWithProductResultPlan(comptime Payload: type, comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const nested = ability.ir.builder.function(1);
    const instructions = [_]ability.ir.plan.Instruction{
        .{
            .kind = .call_nested_with,
            .aux = @intFromEnum(ability.ir.ValueCodec.unit),
            .string_literal = nested_with_metadata,
        },
        ability.ir.builder.callOp(nested, null, ability.ir.builder.op(nested, 0), null) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .result_codec = .product,
            .result_schema_index = 0,
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
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "abort",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "dispatch",
        .mode = .abort,
        .payload_codec = .unit,
        .resume_codec = .unit,
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Payload),
        .codec = .product,
        .first_field = 0,
        .field_count = 1,
    }};
    const value_fields = [_]ability.ir.ValueFieldPlan{.{
        .name = "amount",
        .codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
    };
    const targets = .{ability.ir.NestedWithTarget{
        .metadata = nested_with_metadata,
        .function_index = nested.index,
    }};

    return ability.ir.builder.finishWithNestedTargets(.{
        .label = label,
        .ir_hash = 63,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &value_fields,
        .value_variants = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }, targets) catch unreachable;
}

fn terminalNestedWithSumResultPlan(comptime Payload: type, comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const nested = ability.ir.builder.function(1);
    const instructions = [_]ability.ir.plan.Instruction{
        .{
            .kind = .call_nested_with,
            .aux = @intFromEnum(ability.ir.ValueCodec.unit),
            .string_literal = nested_with_metadata,
        },
        ability.ir.builder.callOp(nested, null, ability.ir.builder.op(nested, 0), null) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .unit,
            .result_codec = .sum,
            .result_schema_index = 0,
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
            .result_codec = .sum,
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
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "abort",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "dispatch",
        .mode = .abort,
        .payload_codec = .unit,
        .resume_codec = .unit,
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Payload),
        .codec = .sum,
        .first_variant = 0,
        .variant_count = 2,
    }};
    const value_variants = [_]ability.ir.ValueVariantPlan{
        .{ .name = "none", .codec = .unit },
        .{ .name = "some", .codec = .i32 },
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
    };
    const targets = .{ability.ir.NestedWithTarget{
        .metadata = nested_with_metadata,
        .function_index = nested.index,
    }};

    return ability.ir.builder.finishWithNestedTargets(.{
        .label = label,
        .ir_hash = 64,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &.{},
        .value_variants = &value_variants,
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }, targets) catch unreachable;
}

fn nestedWithOutputCollectionPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const nested = ability.ir.builder.function(1);
    const instructions = [_]ability.ir.plan.Instruction{
        .{
            .kind = .call_nested_with,
            .aux = @intFromEnum(ability.ir.ValueCodec.unit),
            .string_literal = nested_with_metadata,
        },
        ability.ir.builder.callOp(nested, null, ability.ir.builder.op(nested, 0), null) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 1,
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
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "observe",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "dispatch",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .unit,
    }};
    const outputs = [_]ability.ir.plan.Output{.{
        .label = "observed",
        .codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 65,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &outputs,
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn outputMetadataPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 1,
        .first_local = 0,
        .local_count = 0,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = 0,
    }};
    const outputs = [_]ability.ir.plan.Output{.{
        .label = "writer",
        .codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = 0,
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_unit }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 26,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &outputs,
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &.{},
    }) catch unreachable;
}

fn writerAccumulatorPlan(comptime label: []const u8, comptime values: []const i32) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const instruction_count = values.len * 2;
    const instructions = comptime blk: {
        var buffer: [instruction_count]ability.ir.plan.Instruction = undefined;
        for (values, 0..) |value, index| {
            const payload = ability.ir.builder.local(root, @intCast(index));
            buffer[index * 2] = .{ .kind = .const_i32, .dst = payload.index, .operand = @intCast(value) };
            buffer[index * 2 + 1] = ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 0), payload) catch unreachable;
        }
        break :blk buffer;
    };
    const locals = comptime blk: {
        var buffer: [values.len]ability.ir.plan.Local = undefined;
        for (&buffer) |*local_plan| local_plan.* = .{ .codec = .i32 };
        break :blk buffer;
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 1,
        .first_local = 0,
        .local_count = @intCast(values.len),
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "writer",
        .first_op = 0,
        .op_count = 1,
        .lifecycle_tag = .writer_accumulator,
        .output_tag = .accumulator,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "tell",
        .mode = .transform,
        .payload_codec = .i32,
        .resume_codec = .unit,
    }};
    const outputs = [_]ability.ir.plan.Output{.{
        .label = "writer",
        .codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_unit }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 61,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &outputs,
        .locals = &locals,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

test "ability.program exposes scalar ProgramPlan contract metadata" {
    const Body = struct {
        pub const compiled_plan = pureArithmeticPlan("contract-scalar-plan");
    };
    const Program = ability.program("contract-scalar", struct {}, Body);

    try std.testing.expectEqualStrings("contract-scalar", Program.contract.label);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, Program.contract.result_codec);
    try std.testing.expectEqual(@as(?u16, null), Program.contract.result_schema_index);
    try std.testing.expectEqual(i32, Program.contract.ResultType);
    try std.testing.expectEqual(void, Program.contract.OutputsType);
    try std.testing.expect(!Program.contract.has_typed_result_schema);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.outputs.len);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.value_schemas.len);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.value_fields.len);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.value_variants.len);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.entry_parameters.len);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.nested_with_targets.len);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.requirements.len);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.ops.len);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.return_errors.len);
    try std.testing.expect(Program.contract.executable.supported);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.executable.blocker_count);
    try std.testing.expectEqualStrings("capability ledger: blockers=0 truncated=false", Program.contract.executable.summary);
    try std.testing.expect(Program.contract.session.supported);
    try std.testing.expect(Program.contract.session.trace_supported);
    try std.testing.expect(Program.contract.session.value_fingerprint_supported);
    try std.testing.expectEqual(@as(u32, 2), Program.contract.session.fingerprint_version);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.session.yield_sites.len);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.session.after_sites.len);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.session.blocker_count);
    try std.testing.expectEqualStrings("session capability ledger: blockers=0 truncated=false", Program.contract.session.summary);
    try std.testing.expect(!@hasDecl(Program.contract, "functions"));
    try std.testing.expect(!@hasDecl(Program.contract, "instructions"));
    try std.testing.expect(!@hasDecl(Program.contract, "ArtifactV1"));
    try std.testing.expect(!@hasDecl(Program.contract, "VM"));
}

test "ability.program exposes product result contract metadata" {
    const Payload = struct {
        amount: i32,
    };
    const Body = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = productIdentityPlan(Payload, "contract-product-plan");

        pub fn encodeArgs(_: struct {}) @TypeOf(.{Payload{ .amount = 7 }}) {
            return .{Payload{ .amount = 7 }};
        }
    };
    const Program = ability.program("contract-product", struct {}, Body);

    try std.testing.expectEqual(ability.ir.ValueCodec.product, Program.contract.result_ref.codec);
    try std.testing.expectEqual(@as(?u16, 0), Program.contract.result_ref.schema_index);
    try std.testing.expect(Program.contract.has_typed_result_schema);
    try std.testing.expectEqual(Payload, Program.contract.ResultType);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.value_schemas.len);
    try std.testing.expectEqualStrings(@typeName(Payload), Program.contract.value_schemas[0].label);
    try std.testing.expectEqual(ability.ir.ValueCodec.product, Program.contract.value_schemas[0].codec);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.value_fields.len);
    try std.testing.expectEqualStrings("amount", Program.contract.value_fields[0].name);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, Program.contract.value_fields[0].ref.codec);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.entry_parameters.len);
    try std.testing.expectEqual(ability.ir.ValueCodec.product, Program.contract.entry_parameters[0].ref.codec);
    try std.testing.expectEqual(@as(?u16, 0), Program.contract.entry_parameters[0].ref.schema_index);
}

test "ability.program exposes sum result contract metadata" {
    const Payload = ?i32;
    const Body = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = sumIdentityPlan(Payload, "contract-sum-plan");

        pub fn encodeArgs(_: struct {}) @TypeOf(.{@as(Payload, 7)}) {
            return .{@as(Payload, 7)};
        }
    };
    const Program = ability.program("contract-sum", struct {}, Body);

    try std.testing.expectEqual(ability.ir.ValueCodec.sum, Program.contract.result_ref.codec);
    try std.testing.expectEqual(@as(?u16, 0), Program.contract.result_ref.schema_index);
    try std.testing.expect(Program.contract.has_typed_result_schema);
    try std.testing.expectEqual(Payload, Program.contract.ResultType);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.value_schemas.len);
    try std.testing.expectEqual(ability.ir.ValueCodec.sum, Program.contract.value_schemas[0].codec);
    try std.testing.expectEqual(@as(usize, 2), Program.contract.value_variants.len);
    try std.testing.expectEqualStrings("none", Program.contract.value_variants[0].name);
    try std.testing.expectEqual(ability.ir.ValueCodec.unit, Program.contract.value_variants[0].ref.codec);
    try std.testing.expectEqualStrings("some", Program.contract.value_variants[1].name);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, Program.contract.value_variants[1].ref.codec);
}

test "ability.program exposes output contract metadata" {
    const Body = struct {
        pub const Outputs = []const i32;
        pub const compiled_plan = outputMetadataPlan("contract-output-plan");

        pub fn collectOutputs(_: std.mem.Allocator, _: *struct {}) !Outputs {
            return &[_]i32{};
        }
    };
    const Program = ability.program("contract-output", struct {}, Body);

    try std.testing.expectEqual(@as(usize, 1), Program.contract.outputs.len);
    try std.testing.expectEqualStrings("writer", Program.contract.outputs[0].label);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, Program.contract.outputs[0].codec);
    try std.testing.expectEqual(@as(?u16, null), Program.contract.outputs[0].schema_index);
}

test "ability.program exposes nested-with target declaration metadata" {
    const Body = struct {
        pub const compiled_plan = resolvedNestedWithPlan("contract-nested-plan");
        pub const nested_with_targets = .{ability.ir.NestedWithTarget{
            .metadata = nested_with_metadata,
            .function_index = 1,
        }};
    };
    const Program = ability.program("contract-nested", struct {}, Body);

    try std.testing.expect(Program.contract.has_nested_with_targets);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.nested_with_targets.len);
    try std.testing.expectEqualStrings(nested_with_metadata, Program.contract.nested_with_targets[0].metadata);
    try std.testing.expectEqual(@as(u16, 1), Program.contract.nested_with_targets[0].function_index);
    try std.testing.expect(Program.contract.executable.supported);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.executable.blocker_count);
}

test "ability.program exposes transform choice and abort op metadata" {
    const TransformBody = struct {
        pub const compiled_plan = matrixPlan(.transform, .string, .i32);
    };
    const ChoiceBody = struct {
        pub const compiled_plan = matrixPlan(.choice, .unit, .i32);
    };
    const AbortBody = struct {
        pub const compiled_plan = matrixPlan(.abort, .unit, .unit);
    };
    const TransformProgram = ability.program("contract-transform", struct {}, TransformBody);
    const ChoiceProgram = ability.program("contract-choice", struct {}, ChoiceBody);
    const AbortProgram = ability.program("contract-abort", struct {}, AbortBody);

    try std.testing.expectEqual(@as(usize, 1), TransformProgram.contract.requirements.len);
    try std.testing.expectEqualStrings("matrix", TransformProgram.contract.requirements[0].label);
    try std.testing.expectEqual(@as(@TypeOf(TransformProgram.contract.requirements[0].lifecycle_tag), .plain_transform), TransformProgram.contract.requirements[0].lifecycle_tag);
    try std.testing.expectEqual(@as(@TypeOf(TransformProgram.contract.requirements[0].output_tag), .none), TransformProgram.contract.requirements[0].output_tag);
    try std.testing.expectEqual(@as(usize, 1), TransformProgram.contract.ops.len);
    try std.testing.expectEqualStrings("authored", TransformProgram.contract.ops[0].op_name);
    try std.testing.expectEqualStrings("matrix", TransformProgram.contract.ops[0].requirement_label);
    try std.testing.expectEqual(@as(@TypeOf(TransformProgram.contract.ops[0].mode), .transform), TransformProgram.contract.ops[0].mode);
    try std.testing.expectEqual(ability.ir.ValueCodec.string, TransformProgram.contract.ops[0].payload_ref.codec);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, TransformProgram.contract.ops[0].resume_ref.codec);
    try std.testing.expect(TransformProgram.contract.ops[0].has_after);
    try std.testing.expect(TransformProgram.contract.session.supported);
    try std.testing.expect(TransformProgram.contract.session.parks_runtime);
    try std.testing.expect(TransformProgram.contract.session.requires_runtime_lifetime);
    try std.testing.expect(TransformProgram.contract.session.trace_supported);
    try std.testing.expect(TransformProgram.contract.session.value_fingerprint_supported);
    try std.testing.expectEqual(@as(u32, 2), TransformProgram.contract.session.fingerprint_version);
    try std.testing.expectEqual(@as(usize, 1), TransformProgram.contract.session.yield_sites.len);
    try std.testing.expectEqual(@as(usize, 1), TransformProgram.contract.session.after_sites.len);
    try std.testing.expectEqual(@as(usize, 0), TransformProgram.contract.session.yield_sites[0].index);
    try std.testing.expect(TransformProgram.contract.session.yield_sites[0].fingerprint != 0);
    try std.testing.expectEqual(@as(usize, 0), TransformProgram.contract.session.yield_sites[0].function_index);
    try std.testing.expectEqualStrings("run", TransformProgram.contract.session.yield_sites[0].function_symbol_name);
    try std.testing.expectEqual(@as(usize, 0), TransformProgram.contract.session.yield_sites[0].block_index);
    try std.testing.expectEqual(@as(usize, 1), TransformProgram.contract.session.yield_sites[0].instruction_index);
    try std.testing.expectEqual(@as(u16, 0), TransformProgram.contract.session.yield_sites[0].requirement_index);
    try std.testing.expectEqualStrings("matrix", TransformProgram.contract.session.yield_sites[0].requirement_label);
    try std.testing.expectEqual(@as(u16, 0), TransformProgram.contract.session.yield_sites[0].op_index);
    try std.testing.expectEqualStrings("authored", TransformProgram.contract.session.yield_sites[0].op_name);
    try std.testing.expectEqual(ability.ir.ValueCodec.string, TransformProgram.contract.session.yield_sites[0].payload_ref.codec);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, TransformProgram.contract.session.yield_sites[0].resume_ref.codec);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, TransformProgram.contract.session.yield_sites[0].result_ref.codec);
    try std.testing.expect(TransformProgram.contract.session.yield_sites[0].has_after);
    try std.testing.expect(TransformProgram.contract.session.yield_sites[0].host_may_resume);
    try std.testing.expect(!TransformProgram.contract.session.yield_sites[0].host_may_return_now);
    try std.testing.expect(TransformProgram.contract.session.yield_sites[0].can_yield_after);
    try std.testing.expectEqual(@as(usize, 0), TransformProgram.contract.session.after_sites[0].index);
    try std.testing.expect(TransformProgram.contract.session.after_sites[0].fingerprint != 0);
    try std.testing.expectEqual(@as(usize, 0), TransformProgram.contract.session.after_sites[0].source_operation_site_index);
    try std.testing.expectEqual(TransformProgram.contract.session.yield_sites[0].fingerprint, TransformProgram.contract.session.after_sites[0].source_operation_site_fingerprint);
    try std.testing.expectEqual(@as(usize, 0), TransformProgram.contract.session.after_sites[0].source_function_index);
    try std.testing.expectEqual(@as(usize, 0), TransformProgram.contract.session.after_sites[0].source_block_index);
    try std.testing.expectEqual(@as(usize, 1), TransformProgram.contract.session.after_sites[0].source_instruction_index);
    try std.testing.expectEqual(@as(u16, 0), TransformProgram.contract.session.after_sites[0].original_op_index);
    try std.testing.expectEqual(@as(usize, 0), TransformProgram.contract.session.blocker_count);
    try std.testing.expectEqual(@as(@TypeOf(TransformProgram.contract.session.first_blocker_tag), null), TransformProgram.contract.session.first_blocker_tag);

    try std.testing.expectEqual(@as(@TypeOf(ChoiceProgram.contract.ops[0].mode), .choice), ChoiceProgram.contract.ops[0].mode);
    try std.testing.expect(ChoiceProgram.contract.ops[0].has_after);

    try std.testing.expectEqual(@as(@TypeOf(AbortProgram.contract.ops[0].mode), .abort), AbortProgram.contract.ops[0].mode);
    try std.testing.expectEqual(ability.ir.ValueCodec.unit, AbortProgram.contract.ops[0].resume_ref.codec);
    try std.testing.expect(!AbortProgram.contract.ops[0].has_after);
    try std.testing.expect(AbortProgram.contract.session.supported);
}

test "Program.contract.session exposes transform operation yield site and request trace maps to it" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = sessionStringOpPlan(.transform, "session-site-transform");
    };
    const Program = ability.program("session-site-transform", struct {}, Body);

    try std.testing.expectEqual(@as(u32, 2), Program.contract.session.fingerprint_version);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.session.yield_sites.len);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.session.after_sites.len);
    const site = Program.contract.session.yield_sites[0];
    try std.testing.expectEqual(@as(usize, 0), site.index);
    try std.testing.expect(site.fingerprint != 0);
    try std.testing.expectEqual(@as(usize, 0), site.function_index);
    try std.testing.expectEqualStrings("run", site.function_symbol_name);
    try std.testing.expectEqual(@as(usize, 0), site.block_index);
    try std.testing.expectEqual(@as(usize, 1), site.instruction_index);
    try std.testing.expectEqual(@as(u16, 0), site.requirement_index);
    try std.testing.expectEqualStrings("session", site.requirement_label);
    try std.testing.expectEqual(@as(u16, 0), site.op_index);
    try std.testing.expectEqualStrings("decide", site.op_name);
    try std.testing.expectEqual(@as(@TypeOf(site.op_mode), .transform), site.op_mode);
    try std.testing.expectEqual(ability.ir.ValueCodec.string, site.payload_ref.codec);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, site.resume_ref.codec);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, site.result_ref.codec);
    try std.testing.expect(!site.has_after);
    try std.testing.expect(site.host_may_resume);
    try std.testing.expect(!site.host_may_return_now);
    try std.testing.expect(!site.can_yield_after);

    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();
    const request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    const trace = request.trace();
    try std.testing.expectEqual(site.index, trace.operation_site_index);
    try std.testing.expectEqual(site.fingerprint, trace.operation_site_fingerprint);
    try std.testing.expectEqual(site.function_index, trace.function_index);
    try std.testing.expectEqual(site.block_index, trace.block_index);
    try std.testing.expectEqual(site.instruction_index, trace.instruction_index);
    try std.testing.expectEqual(site.requirement_index, trace.requirement_index);
    try std.testing.expectEqual(site.op_index, trace.op_index);
}

test "Program.Session request fingerprint disambiguates same op from different call sites" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = repeatedCallSiteSameOpPlan("session-site-same-op", false);
    };
    const Program = ability.program("session-site-same-op", struct {}, Body);
    try std.testing.expectEqual(@as(usize, 2), Program.contract.session.yield_sites.len);
    try std.testing.expectEqual(@as(u16, 0), Program.contract.session.yield_sites[0].op_index);
    try std.testing.expectEqual(@as(u16, 0), Program.contract.session.yield_sites[1].op_index);
    try std.testing.expect(Program.contract.session.yield_sites[0].fingerprint != Program.contract.session.yield_sites[1].fingerprint);

    var first_session = try Program.Session.start(&runtime, .{});
    defer first_session.deinit();
    const first_request = switch (try first_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try first_session.@"resume"(first_request, @as(i32, 10));
    const second_request = switch (try first_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqual(@as(usize, 0), first_request.trace().operation_site_index);
    try std.testing.expectEqual(@as(usize, 1), second_request.trace().operation_site_index);
    try std.testing.expectEqual(first_request.trace().payload_value_fingerprint, second_request.trace().payload_value_fingerprint);
    try std.testing.expect(first_request.fingerprint() != second_request.fingerprint());
    try first_session.@"resume"(second_request, @as(i32, 11));
    var result = switch (try first_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();

    var replay_session = try Program.Session.start(&runtime, .{});
    defer replay_session.deinit();
    const replay_first = switch (try replay_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try replay_session.@"resume"(replay_first, @as(i32, 10));
    const replay_second = switch (try replay_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqual(first_request.fingerprint(), replay_first.fingerprint());
    try std.testing.expectEqual(second_request.fingerprint(), replay_second.fingerprint());
}

test "Program.Session request fingerprint changes for different sites at same turn" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const BranchHandlers = struct {
        choose_right: bool,
    };
    const Body = struct {
        pub const compiled_plan = branchedSameOpCallSitePlan("session-site-same-turn");

        pub fn encodeArgs(handlers: BranchHandlers) struct { bool } {
            return .{handlers.choose_right};
        }
    };
    const Program = ability.program("session-site-same-turn", BranchHandlers, Body);
    try std.testing.expectEqual(@as(usize, 2), Program.contract.session.yield_sites.len);
    try std.testing.expectEqual(@as(u16, 0), Program.contract.session.yield_sites[0].op_index);
    try std.testing.expectEqual(@as(u16, 0), Program.contract.session.yield_sites[1].op_index);

    var left_session = try Program.Session.start(&runtime, .{ .choose_right = false });
    defer left_session.deinit();
    const left_request = switch (try left_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };

    var right_session = try Program.Session.start(&runtime, .{ .choose_right = true });
    defer right_session.deinit();
    const right_request = switch (try right_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };

    try std.testing.expectEqual(@as(usize, 0), left_request.trace().turn_index);
    try std.testing.expectEqual(@as(usize, 0), right_request.trace().turn_index);
    try std.testing.expectEqual(@as(u16, 0), left_request.trace().op_index);
    try std.testing.expectEqual(@as(u16, 0), right_request.trace().op_index);
    try std.testing.expectEqual(left_request.trace().payload_value_fingerprint, right_request.trace().payload_value_fingerprint);
    try std.testing.expect(left_request.trace().operation_site_index != right_request.trace().operation_site_index);
    try std.testing.expect(left_request.trace().operation_site_fingerprint != right_request.trace().operation_site_fingerprint);
    try std.testing.expect(left_request.fingerprint() != right_request.fingerprint());
}

test "Program.Session looped operation reuses static site and advances turns" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = loopedOperationSitePlan("session-site-loop");
    };
    const Program = ability.program("session-site-loop", struct {}, Body);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.session.yield_sites.len);
    const site = Program.contract.session.yield_sites[0];
    try std.testing.expectEqual(@as(usize, 1), site.block_index);
    try std.testing.expectEqual(@as(usize, 2), site.instruction_index);

    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();
    var previous_fingerprint: u64 = 0;
    for (0..3) |turn_index| {
        const request = switch (try session.next()) {
            .request => |request| request,
            .done => return error.ExpectedRequest,
            .after => return error.UnexpectedAfter,
        };
        const trace = request.trace();
        try std.testing.expectEqual(site.index, trace.operation_site_index);
        try std.testing.expectEqual(site.fingerprint, trace.operation_site_fingerprint);
        try std.testing.expectEqual(turn_index, trace.turn_index);
        if (turn_index != 0) try std.testing.expect(previous_fingerprint != trace.fingerprint);
        previous_fingerprint = trace.fingerprint;
        try session.@"resume"(request, @as(i32, @intCast(turn_index)));
    }
    var result = switch (try session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 2), result.value);
}

test "Program.contract.session site catalog follows helper nested-with and omits unreachable call_op" {
    const HelperBody = struct {
        pub const compiled_plan = sessionHelperYieldPlan("session-site-helper");
    };
    const HelperProgram = ability.program("session-site-helper", struct {}, HelperBody);
    try std.testing.expectEqual(@as(usize, 1), HelperProgram.contract.session.yield_sites.len);
    try std.testing.expectEqual(@as(usize, 1), HelperProgram.contract.session.yield_sites[0].function_index);
    try std.testing.expectEqualStrings("helper", HelperProgram.contract.session.yield_sites[0].function_symbol_name);
    try std.testing.expectEqual(@as(usize, 1), HelperProgram.contract.session.yield_sites[0].block_index);
    try std.testing.expectEqual(@as(usize, 3), HelperProgram.contract.session.yield_sites[0].instruction_index);

    const NestedBody = struct {
        pub const compiled_plan = resolvedNestedWithStringListPlan("session-site-nested");
        pub const nested_with_targets = .{ability.ir.NestedWithTarget{
            .metadata = nested_with_metadata,
            .function_index = 1,
        }};
    };
    const NestedProgram = ability.program("session-site-nested", struct {}, NestedBody);
    try std.testing.expectEqual(@as(usize, 1), NestedProgram.contract.session.yield_sites.len);
    try std.testing.expectEqual(@as(usize, 1), NestedProgram.contract.session.yield_sites[0].function_index);
    try std.testing.expectEqualStrings("nested", NestedProgram.contract.session.yield_sites[0].function_symbol_name);
    try std.testing.expectEqual(@as(usize, 1), NestedProgram.contract.session.yield_sites[0].block_index);
    try std.testing.expectEqual(@as(usize, 2), NestedProgram.contract.session.yield_sites[0].instruction_index);

    const DeadBody = struct {
        pub const compiled_plan = unreachableCallOpPlan("session-site-unreachable");
    };
    const DeadProgram = ability.program("session-site-unreachable", struct {}, DeadBody);
    try std.testing.expectEqual(@as(usize, 1), DeadProgram.contract.ops.len);
    try std.testing.expectEqual(@as(usize, 0), DeadProgram.contract.session.yield_sites.len);
    try std.testing.expectEqual(@as(usize, 0), DeadProgram.contract.session.after_sites.len);
}

test "Program.contract.session after sites map dynamic after traces to source operation sites" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = compiledTransformPlan("session-site-after");
    };
    const Program = ability.program("session-site-after", struct {}, Body);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.session.yield_sites.len);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.session.after_sites.len);
    const operation_site = Program.contract.session.yield_sites[0];
    const after_site = Program.contract.session.after_sites[0];
    try std.testing.expectEqual(@as(usize, 0), after_site.index);
    try std.testing.expect(after_site.fingerprint != 0);
    try std.testing.expectEqual(operation_site.index, after_site.source_operation_site_index);
    try std.testing.expectEqual(operation_site.function_index, after_site.source_function_index);
    try std.testing.expectEqual(operation_site.block_index, after_site.source_block_index);
    try std.testing.expectEqual(operation_site.instruction_index, after_site.source_instruction_index);
    try std.testing.expectEqual(operation_site.requirement_index, after_site.original_requirement_index);
    try std.testing.expectEqual(operation_site.op_index, after_site.original_op_index);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, after_site.current_value_ref.codec);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, after_site.expected_output_ref.codec);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, after_site.result_ref.codec);

    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();
    const request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqual(operation_site.index, request.trace().operation_site_index);
    try session.@"resume"(request, @as(i32, 30));
    const after = switch (try session.next()) {
        .after => |after| after,
        .request => return error.ExpectedAfter,
        .done => return error.ExpectedAfter,
    };
    const trace = after.trace();
    try std.testing.expectEqual(after_site.index, trace.after_site_index);
    try std.testing.expectEqual(after_site.fingerprint, trace.after_site_fingerprint);
    try std.testing.expectEqual(operation_site.index, trace.source_operation_site_index);
    try std.testing.expectEqual(after_site.source_function_index, trace.function_index);
    try std.testing.expectEqual(after_site.source_block_index, trace.block_index);
    try std.testing.expectEqual(after_site.source_instruction_index, trace.instruction_index);

    const RepeatedAfterBody = struct {
        pub const compiled_plan = repeatedCallSiteSameOpPlan("session-site-after-same-op", true);
    };
    const RepeatedAfterProgram = ability.program("session-site-after-same-op", struct {}, RepeatedAfterBody);
    try std.testing.expectEqual(@as(usize, 2), RepeatedAfterProgram.contract.session.yield_sites.len);
    try std.testing.expectEqual(@as(usize, 2), RepeatedAfterProgram.contract.session.after_sites.len);
    try std.testing.expectEqual(@as(u16, 0), RepeatedAfterProgram.contract.session.after_sites[0].original_op_index);
    try std.testing.expectEqual(@as(u16, 0), RepeatedAfterProgram.contract.session.after_sites[1].original_op_index);
    try std.testing.expectEqual(@as(usize, 0), RepeatedAfterProgram.contract.session.after_sites[0].source_operation_site_index);
    try std.testing.expectEqual(@as(usize, 1), RepeatedAfterProgram.contract.session.after_sites[1].source_operation_site_index);
    try std.testing.expect(RepeatedAfterProgram.contract.session.after_sites[0].fingerprint != RepeatedAfterProgram.contract.session.after_sites[1].fingerprint);
}

test "Program.Session yields transform request data and resumes to completion" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = sessionStringOpPlan(.transform, "session-transform-request");
    };
    const Program = ability.program("session-transform-request", struct {}, Body);
    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);

    const request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.UnexpectedDone,
        .after => return error.UnexpectedAfter,
    };
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);
    try std.testing.expectEqual(@as(u16, 0), request.requirement_index);
    try std.testing.expectEqualStrings("session", request.requirement_label);
    try std.testing.expectEqual(@as(u16, 0), request.op_index);
    try std.testing.expectEqualStrings("decide", request.op_name);
    try std.testing.expectEqual(@as(@TypeOf(request.mode), .transform), request.mode);
    try std.testing.expectEqual(ability.ir.ValueCodec.string, request.payload_ref.codec);
    try std.testing.expectEqualStrings("payload", try request.payload([]const u8));
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, request.resume_ref.codec);
    try std.testing.expect(!request.has_after);

    try session.@"resume"(request, @as(i32, 41));
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);
    var result = switch (try session.next()) {
        .done => |result| result,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 41), result.value);
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 0);
}

test "Program.Session decodes string-list payloads as immutable views only" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const StringListPayloadHandlers = struct {
        items: []const []const u8,
    };
    const StringListPayloadArgs = struct { []const []const u8 };
    const Body = struct {
        pub const compiled_plan = sessionStringListPayloadPlan("session-string-list-payload");

        pub fn encodeArgs(handlers: StringListPayloadHandlers) StringListPayloadArgs {
            return .{handlers.items};
        }
    };
    const Program = ability.program("session-string-list-payload", StringListPayloadHandlers, Body);
    var strings = [_][]const u8{ "left", "right" };
    var session = try Program.Session.start(&runtime, .{ .items = strings[0..] });
    defer session.deinit();

    const request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.UnexpectedDone,
        .after => return error.UnexpectedAfter,
    };
    const payload = try request.payload([]const []const u8);
    try std.testing.expectEqual(@as(usize, 2), payload.len);
    try std.testing.expectEqualStrings("left", payload[0]);
    try std.testing.expectEqualStrings("right", payload[1]);
    try std.testing.expectError(error.ProgramContractViolation, request.payload([][]const u8));

    try session.@"resume"(request, @as(i32, 55));
    var result = switch (try session.next()) {
        .done => |result| result,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 55), result.value);
}

test "Program.Session yields choice request and resumes branch" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = sessionStringOpPlan(.choice, "session-choice-resume");
    };
    const Program = ability.program("session-choice-resume", struct {}, Body);
    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();

    const request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.UnexpectedDone,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqual(@as(@TypeOf(request.mode), .choice), request.mode);
    try std.testing.expectEqualStrings("payload", try request.payload([]const u8));
    try session.@"resume"(request, @as(i32, 42));
    var result = switch (try session.next()) {
        .done => |result| result,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 42), result.value);
}

test "Program.Session yields choice request and return-now branch" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = sessionStringOpPlan(.choice, "session-choice-return-now");
    };
    const Program = ability.program("session-choice-return-now", struct {}, Body);
    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();

    const request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.UnexpectedDone,
        .after => return error.UnexpectedAfter,
    };
    try session.returnNow(request, @as(i32, 77));
    var result = switch (try session.next()) {
        .done => |result| result,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 77), result.value);
}

test "Program.Session yields abort request and completes terminally" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = abortPlan("session-abort-terminal");
    };
    const Program = ability.program("session-abort-terminal", struct {}, Body);
    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();

    const request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.UnexpectedDone,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqual(@as(@TypeOf(request.mode), .abort), request.mode);
    try session.returnNow(request, @as(i32, 55));
    var result = switch (try session.next()) {
        .done => |result| result,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 55), result.value);
}

test "Program.Session yields from inside helper call and resumes caller frame" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = sessionHelperYieldPlan("session-helper-yield");
    };
    const Program = ability.program("session-helper-yield", struct {}, Body);
    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();

    const request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.UnexpectedDone,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqualStrings("helper", request.requirement_label);
    try std.testing.expectEqualStrings("yield", request.op_name);
    try session.@"resume"(request, @as(i32, 40));
    var result = switch (try session.next()) {
        .done => |result| result,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 41), result.value);
}

test "Program.Session yields from nested-with target and resumes enclosing frame" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = resolvedNestedWithStringListPlan("session-nested-with-yield");
        pub const nested_with_targets = .{ability.ir.NestedWithTarget{
            .metadata = nested_with_metadata,
            .function_index = 1,
        }};
    };
    const Program = ability.program("session-nested-with-yield", struct {}, Body);
    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();

    const request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.UnexpectedDone,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqualStrings("authored", request.requirement_label);
    var strings = [_][]const u8{ "left", "right" };
    try session.@"resume"(request, @as([]const []const u8, strings[0..]));
    var result = switch (try session.next()) {
        .done => |result| result,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 2), result.value.len);
    try std.testing.expectEqualStrings("left", result.value[0]);
    try std.testing.expectEqualStrings("right", result.value[1]);
}

test "Program.Session rejects wrong resume type without consuming request" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = sessionStringOpPlan(.transform, "session-wrong-resume-type");
    };
    const Program = ability.program("session-wrong-resume-type", struct {}, Body);
    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();

    const request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.UnexpectedDone,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectError(error.ProgramContractViolation, session.@"resume"(request, true));
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);
    try session.@"resume"(request, @as(i32, 6));
    try std.testing.expectError(error.ProgramContractViolation, session.@"resume"(request, @as(i32, 7)));
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);
    var result = switch (try session.next()) {
        .done => |result| result,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 6), result.value);
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 0);
}

test "Program.Session supports typed product payload and resume values" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = struct {
        amount: i32,
    };
    const ProductHandlers = struct {};
    const Body = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = sessionProductTransformPlan(Payload, "session-product-round-trip");

        pub fn encodeArgs(_: ProductHandlers) @TypeOf(.{Payload{ .amount = 3 }}) {
            return .{Payload{ .amount = 3 }};
        }
    };
    const Program = ability.program("session-product-round-trip", ProductHandlers, Body);
    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();

    const request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.UnexpectedDone,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqual(@as(i32, 3), (try request.payload(Payload)).amount);
    try session.@"resume"(request, Payload{ .amount = 9 });
    var result = switch (try session.next()) {
        .done => |result| result,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 9), result.value.amount);
}

test "Program.Session supports typed sum payload and resume values" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = ?i32;
    const SumHandlers = struct {};
    const Body = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = sessionSumTransformPlan(Payload, "session-sum-round-trip");

        pub fn encodeArgs(_: SumHandlers) @TypeOf(.{@as(Payload, 4)}) {
            return .{@as(Payload, 4)};
        }
    };
    const Program = ability.program("session-sum-round-trip", SumHandlers, Body);
    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();

    const request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.UnexpectedDone,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqual(@as(i32, 4), (try request.payload(Payload)).?);
    try session.@"resume"(request, @as(Payload, 8));
    var result = switch (try session.next()) {
        .done => |result| result,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 8), result.value.?);
}

test "Program.Session structured request payloads survive session deinit" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const ProductPayload = struct {
        amount: i32,
    };
    const ProductHandlers = struct {};
    const ProductBody = struct {
        pub const value_schema_types = .{ProductPayload};
        pub const compiled_plan = sessionProductTransformPlan(ProductPayload, "session-stale-product-payload");

        pub fn encodeArgs(_: ProductHandlers) @TypeOf(.{ProductPayload{ .amount = 13 }}) {
            return .{ProductPayload{ .amount = 13 }};
        }
    };
    const ProductProgram = ability.program("session-stale-product-payload", ProductHandlers, ProductBody);
    var product_session = try ProductProgram.Session.start(&runtime, .{});
    var product_session_active = true;
    defer if (product_session_active) product_session.deinit();

    const product_request = switch (try product_session.next()) {
        .request => |request| request,
        .done => return error.UnexpectedDone,
        .after => return error.UnexpectedAfter,
    };
    product_session.deinit();
    product_session_active = false;
    try std.testing.expectEqual(@as(i32, 13), (try product_request.payload(ProductPayload)).amount);

    const SumPayload = ?i32;
    const SumHandlers = struct {};
    const SumBody = struct {
        pub const value_schema_types = .{SumPayload};
        pub const compiled_plan = sessionSumTransformPlan(SumPayload, "session-stale-sum-payload");

        pub fn encodeArgs(_: SumHandlers) @TypeOf(.{@as(SumPayload, 21)}) {
            return .{@as(SumPayload, 21)};
        }
    };
    const SumProgram = ability.program("session-stale-sum-payload", SumHandlers, SumBody);
    var sum_session = try SumProgram.Session.start(&runtime, .{});
    var sum_session_active = true;
    defer if (sum_session_active) sum_session.deinit();

    const sum_request = switch (try sum_session.next()) {
        .request => |request| request,
        .done => return error.UnexpectedDone,
        .after => return error.UnexpectedAfter,
    };
    sum_session.deinit();
    sum_session_active = false;
    try std.testing.expectEqual(@as(i32, 21), (try sum_request.payload(SumPayload)).?);
}

fn pureArithmeticPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const value = ability.ir.builder.local(root, 0);
    const rhs = ability.ir.builder.local(root, 1);
    const sum = ability.ir.builder.local(root, 2);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_i32, .dst = value.index, .operand = 4 },
        .{ .kind = .add_const_i32, .dst = value.index, .operand = value.index, .aux = 1 },
        .{ .kind = .const_i32, .dst = rhs.index, .operand = 2 },
        .{ .kind = .add_i32, .dst = sum.index, .operand = value.index, .aux = rhs.index },
        ability.ir.builder.returnValue(root, sum) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 3,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 2,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn budgetSizedStraightLinePlan(comptime label: []const u8) ability.ir.ProgramPlan {
    @setEvalBranchQuota(80_000);
    const instruction_count = interpreter_step_budget / 2 + 100;
    const root = ability.ir.builder.function(0);
    const value = ability.ir.builder.local(root, 0);
    const instructions = comptime blk: {
        var buf = [_]ability.ir.plan.Instruction{.{ .kind = .return_value }} ** instruction_count;
        buf[0] = .{ .kind = .const_i32, .dst = value.index, .operand = 7 };
        for (1..instruction_count - 1) |index| {
            buf[index] = .{ .kind = .add_const_i32, .dst = value.index, .operand = value.index, .aux = 0 };
        }
        buf[instruction_count - 1] = ability.ir.builder.returnValue(root, value) catch unreachable;
        break :blk buf;
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
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
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 84,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn usizeLiteralPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const value = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_usize, .dst = value.index, .string_literal = "0xff" },
        ability.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
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
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 13,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .usize }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn boolComparePlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const flag = ability.ir.builder.local(root, 0);
    const result = ability.ir.builder.local(root, 1);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, flag, ability.ir.builder.op(root, 0), null) catch unreachable,
        .{ .kind = .compare_eq_zero, .dst = result.index, .operand = flag.index },
        ability.ir.builder.returnValue(root, result) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .bool,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "bool", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "probe",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .bool,
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 14,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .bool }, .{ .codec = .bool } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn usizeSubOnePlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const value = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_usize, .dst = value.index, .string_literal = "3" },
        .{ .kind = .sub_one, .dst = value.index, .operand = value.index },
        ability.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
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
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 15,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .usize }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn helperUsizeLocalOffsetPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const helper = ability.ir.builder.function(1);
    const root_result = ability.ir.builder.local(root, 1);
    const helper_value = ability.ir.builder.local(helper, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callHelper(root, root_result, helper, null) catch unreachable,
        ability.ir.builder.returnValue(root, root_result) catch unreachable,
        .{ .kind = .const_usize, .dst = helper_value.index, .string_literal = "2" },
        .{ .kind = .sub_one, .dst = helper_value.index, .operand = helper_value.index },
        ability.ir.builder.returnValue(helper, helper_value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .usize,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 2,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        },
        .{
            .symbol_name = "helper",
            .value_codec = .usize,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 2,
            .local_count = 1,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 2,
            .instruction_count = 3,
        },
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 3, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 16,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .bool }, .{ .codec = .usize }, .{ .codec = .usize } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn zeroArgHelperLegacyAuxPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const helper = ability.ir.builder.function(1);
    const root_value = ability.ir.builder.local(root, 0);
    const helper_value = ability.ir.builder.local(helper, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .call_helper, .dst = root_value.index, .operand = helper.index, .aux = 0 },
        ability.ir.builder.returnValue(root, root_value) catch unreachable,
        .{ .kind = .const_i32, .dst = helper_value.index, .operand = 12 },
        ability.ir.builder.returnValue(helper, helper_value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
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
        },
        .{
            .symbol_name = "helper",
            .value_codec = .i32,
            .parameter_count = 0,
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
            .instruction_count = 2,
        },
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 17,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn unitResumeKeepsLocalPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const value = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_i32, .dst = value.index, .operand = 7 },
        .{ .kind = .call_op, .dst = value.index, .operand = 0, .aux = value.index },
        ability.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
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
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "unit", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "touch",
        .mode = .transform,
        .payload_codec = .i32,
        .resume_codec = .unit,
    }};
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 18,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn helperPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const helper = ability.ir.builder.function(1);
    const root_value = ability.ir.builder.local(root, 0);
    const helper_value = ability.ir.builder.local(helper, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callHelper(root, root_value, helper, null) catch unreachable,
        ability.ir.builder.returnValue(root, root_value) catch unreachable,
        .{ .kind = .const_i32, .dst = helper_value.index, .operand = 9 },
        ability.ir.builder.returnValue(helper, helper_value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
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
        },
        .{
            .symbol_name = "helper",
            .value_codec = .i32,
            .parameter_count = 0,
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
            .instruction_count = 2,
        },
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 3,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn abortPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const value = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 0), null) catch unreachable,
        .{ .kind = .const_i32, .dst = value.index, .operand = 999 },
        ability.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
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
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "authored", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "abort",
        .mode = .abort,
        .payload_codec = .unit,
        .resume_codec = .unit,
        .has_after = false,
    }};
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 4,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn sessionStringOpPlan(comptime mode: ability.ir.PlanControlMode, comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const resumed = ability.ir.builder.local(root, 1);
    const tail = ability.ir.builder.local(root, 2);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_string, .dst = payload.index, .string_literal = "payload" },
        ability.ir.builder.callOp(root, resumed, ability.ir.builder.op(root, 0), payload) catch unreachable,
        .{ .kind = .const_i32, .dst = tail.index, .operand = 999 },
        ability.ir.builder.returnValue(root, resumed) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 3,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "session", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "decide",
        .mode = mode,
        .payload_codec = .string,
        .resume_codec = .i32,
        .has_after = false,
    }};
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 101,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .string }, .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn repeatedCallSiteSameOpPlan(comptime label: []const u8, comptime has_after: bool) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const resumed = ability.ir.builder.local(root, 1);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_string, .dst = payload.index, .string_literal = "same" },
        ability.ir.builder.callOp(root, resumed, ability.ir.builder.op(root, 0), payload) catch unreachable,
        ability.ir.builder.callOp(root, resumed, ability.ir.builder.op(root, 0), payload) catch unreachable,
        ability.ir.builder.returnValue(root, resumed) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "session", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "same_op",
        .mode = .transform,
        .payload_codec = .string,
        .resume_codec = .i32,
        .has_after = has_after,
    }};
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = if (has_after) 121 else 120,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .string }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn branchedSameOpCallSitePlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const choose_right = ability.ir.builder.local(root, 0);
    const left_payload = ability.ir.builder.local(root, 1);
    const right_payload = ability.ir.builder.local(root, 2);
    const resumed = ability.ir.builder.local(root, 3);
    const choose_left = ability.ir.builder.local(root, 4);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .compare_eq_zero, .dst = choose_left.index, .operand = choose_right.index },
        .{ .kind = .const_string, .dst = left_payload.index, .string_literal = "same" },
        ability.ir.builder.callOp(root, resumed, ability.ir.builder.op(root, 0), left_payload) catch unreachable,
        ability.ir.builder.returnValue(root, resumed) catch unreachable,
        .{ .kind = .const_string, .dst = right_payload.index, .string_literal = "same" },
        ability.ir.builder.callOp(root, resumed, ability.ir.builder.op(root, 0), right_payload) catch unreachable,
        ability.ir.builder.returnValue(root, resumed) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 5,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 3,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "session", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "same_op",
        .mode = .transform,
        .payload_codec = .string,
        .resume_codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 3, .terminator_index = 1 },
        .{ .first_instruction = 4, .instruction_count = 3, .terminator_index = 2 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 124,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .bool }, .{ .codec = .string }, .{ .codec = .string }, .{ .codec = .i32 }, .{ .codec = .bool } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn loopedOperationSitePlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const counter = ability.ir.builder.local(root, 0);
    const payload = ability.ir.builder.local(root, 1);
    const resumed = ability.ir.builder.local(root, 2);
    const done = ability.ir.builder.local(root, 3);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_usize, .dst = counter.index, .string_literal = "3" },
        .{ .kind = .const_string, .dst = payload.index, .string_literal = "loop" },
        ability.ir.builder.callOp(root, resumed, ability.ir.builder.op(root, 0), payload) catch unreachable,
        .{ .kind = .sub_one, .dst = counter.index, .operand = counter.index },
        .{ .kind = .compare_eq_zero, .dst = done.index, .operand = counter.index },
        ability.ir.builder.returnValue(root, resumed) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 4,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 3,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "session", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "loop_op",
        .mode = .transform,
        .payload_codec = .string,
        .resume_codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 3, .terminator_index = 1 },
        .{ .first_instruction = 5, .instruction_count = 1, .terminator_index = 2 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .jump, .primary = 1 },
        .{ .kind = .branch_if, .primary = 2, .secondary = 1 },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 122,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .usize }, .{ .codec = .string }, .{ .codec = .i32 }, .{ .codec = .bool } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn unreachableCallOpPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const helper = ability.ir.builder.function(1);
    const root_value = ability.ir.builder.local(root, 0);
    const helper_value = ability.ir.builder.local(helper, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_i32, .dst = root_value.index, .operand = 7 },
        ability.ir.builder.returnValue(root, root_value) catch unreachable,
        ability.ir.builder.callOp(helper, helper_value, ability.ir.builder.op(helper, 0), null) catch unreachable,
        ability.ir.builder.returnValue(helper, helper_value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
            .result_codec = .i32,
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
        },
        .{
            .symbol_name = "dead_helper",
            .value_codec = .i32,
            .result_codec = .i32,
            .parameter_count = 0,
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
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "dead", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "dead_op",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 123,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn sessionStringPayloadPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const resumed = ability.ir.builder.local(root, 1);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, resumed, ability.ir.builder.op(root, 0), payload) catch unreachable,
        ability.ir.builder.returnValue(root, resumed) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "session", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "string_payload",
        .mode = .transform,
        .payload_codec = .string,
        .resume_codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 113,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .string }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn sessionStringListPayloadPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const resumed = ability.ir.builder.local(root, 1);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, resumed, ability.ir.builder.op(root, 0), payload) catch unreachable,
        ability.ir.builder.returnValue(root, resumed) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "session", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "string_list_payload",
        .mode = .transform,
        .payload_codec = .string_list,
        .resume_codec = .i32,
        .has_after = false,
    }};
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 112,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .string_list }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn sessionHelperYieldPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const helper = ability.ir.builder.function(1);
    const root_value = ability.ir.builder.local(root, 0);
    const helper_value = ability.ir.builder.local(helper, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callHelper(root, root_value, helper, null) catch unreachable,
        .{ .kind = .add_const_i32, .dst = root_value.index, .operand = root_value.index, .aux = 1 },
        ability.ir.builder.returnValue(root, root_value) catch unreachable,
        ability.ir.builder.callOp(helper, helper_value, ability.ir.builder.op(helper, 0), null) catch unreachable,
        ability.ir.builder.returnValue(helper, helper_value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
            .result_codec = .i32,
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
            .instruction_count = 3,
        },
        .{
            .symbol_name = "helper",
            .value_codec = .i32,
            .result_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 1,
            .local_count = 1,
            .first_block = 1,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 3,
            .instruction_count = 2,
        },
    };
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "helper", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "yield",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 3, .terminator_index = 0 },
        .{ .first_instruction = 3, .instruction_count = 2, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 102,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn sameOpTwoSiteAfterPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const first = ability.ir.builder.local(root, 0);
    const second = ability.ir.builder.local(root, 1);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, first, ability.ir.builder.op(root, 0), null) catch unreachable,
        ability.ir.builder.callOp(root, second, ability.ir.builder.op(root, 0), null) catch unreachable,
        ability.ir.builder.returnValue(root, second) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "same", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "dispatch",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .i32,
        .has_after = true,
    }};
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 114,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn unreachableSessionSitePlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const value = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_i32, .dst = value.index, .operand = 7 },
        ability.ir.builder.returnValue(root, value) catch unreachable,
        ability.ir.builder.callOp(root, value, ability.ir.builder.op(root, 0), null) catch unreachable,
        ability.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
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
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "dead", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "unreachable",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .i32,
    }};
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 115,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn sessionProductTransformPlan(comptime Payload: type, comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const resumed = ability.ir.builder.local(root, 1);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, resumed, ability.ir.builder.op(root, 0), payload) catch unreachable,
        ability.ir.builder.returnValue(root, resumed) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .product,
        .value_schema_index = 0,
        .result_codec = .product,
        .result_schema_index = 0,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "structured", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "round_trip",
        .mode = .transform,
        .payload_codec = .product,
        .payload_schema_index = 0,
        .resume_codec = .product,
        .resume_schema_index = 0,
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Payload),
        .codec = .product,
        .first_field = 0,
        .field_count = 1,
    }};
    const value_fields = [_]ability.ir.ValueFieldPlan{.{ .name = "amount", .codec = .i32 }};
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 103,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &value_fields,
        .value_variants = &.{},
        .locals = &.{ .{ .codec = .product, .schema_index = 0 }, .{ .codec = .product, .schema_index = 0 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn sessionSumTransformPlan(comptime Payload: type, comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const resumed = ability.ir.builder.local(root, 1);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, resumed, ability.ir.builder.op(root, 0), payload) catch unreachable,
        ability.ir.builder.returnValue(root, resumed) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .sum,
        .value_schema_index = 0,
        .result_codec = .sum,
        .result_schema_index = 0,
        .parameter_count = 1,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "structured", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "round_trip",
        .mode = .transform,
        .payload_codec = .sum,
        .payload_schema_index = 0,
        .resume_codec = .sum,
        .resume_schema_index = 0,
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Payload),
        .codec = .sum,
        .first_variant = 0,
        .variant_count = 2,
    }};
    const value_variants = [_]ability.ir.ValueVariantPlan{
        .{ .name = "none", .codec = .unit },
        .{ .name = "some", .codec = .i32 },
    };
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 104,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &.{},
        .value_variants = &value_variants,
        .locals = &.{ .{ .codec = .sum, .schema_index = 0 }, .{ .codec = .sum, .schema_index = 0 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn sumAfterResultPlan(comptime Payload: type, comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const resumed = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callOp(root, resumed, ability.ir.builder.op(root, 0), null) catch unreachable,
        ability.ir.builder.returnValue(root, resumed) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .sum,
        .value_schema_index = 0,
        .result_codec = .sum,
        .result_schema_index = 0,
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
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "structured", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "structured",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .sum,
        .resume_schema_index = 0,
        .has_after = true,
    }};
    const value_schemas = [_]ability.ir.ValueSchemaPlan{.{
        .label = @typeName(Payload),
        .codec = .sum,
        .first_variant = 0,
        .variant_count = 2,
    }};
    const value_variants = [_]ability.ir.ValueVariantPlan{
        .{ .name = "none", .codec = .unit },
        .{ .name = "some", .codec = .i32 },
    };
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 105,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &.{},
        .value_variants = &value_variants,
        .locals = &.{.{ .codec = .sum, .schema_index = 0 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn helperAbortPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const helper = ability.ir.builder.function(1);
    const root_value = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callHelper(root, root_value, helper, null) catch unreachable,
        .{ .kind = .const_i32, .dst = root_value.index, .operand = 999 },
        ability.ir.builder.returnValue(root, root_value) catch unreachable,
        ability.ir.builder.callOp(helper, null, ability.ir.builder.op(helper, 0), null) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
            .result_codec = .i32,
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
            .instruction_count = 3,
        },
        .{
            .symbol_name = "abort_helper",
            .value_codec = .i32,
            .result_codec = .i32,
            .parameter_count = 0,
            .first_requirement = 0,
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
    };
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "authored", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "abort",
        .mode = .abort,
        .payload_codec = .unit,
        .resume_codec = .unit,
        .has_after = false,
    }};
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 3, .terminator_index = 0 },
        .{ .first_instruction = 3, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_unit },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 14,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn helperTransformPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const helper = ability.ir.builder.function(1);
    const root_value = ability.ir.builder.local(root, 0);
    const helper_value = ability.ir.builder.local(helper, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callHelper(root, root_value, helper, null) catch unreachable,
        ability.ir.builder.returnValue(root, root_value) catch unreachable,
        ability.ir.builder.callOp(helper, helper_value, ability.ir.builder.op(helper, 0), null) catch unreachable,
        ability.ir.builder.returnValue(helper, helper_value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
            .result_codec = .i32,
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
        },
        .{
            .symbol_name = "transform_helper",
            .value_codec = .i32,
            .result_codec = .i32,
            .parameter_count = 0,
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
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "authored", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "helper_value",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .i32,
        .has_after = false,
    }};
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 15,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn helperAfterTransformPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const helper = ability.ir.builder.function(1);
    const root_value = ability.ir.builder.local(root, 0);
    const helper_value = ability.ir.builder.local(helper, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callHelper(root, root_value, helper, null) catch unreachable,
        ability.ir.builder.returnValue(root, root_value) catch unreachable,
        ability.ir.builder.callOp(helper, helper_value, ability.ir.builder.op(helper, 0), null) catch unreachable,
        ability.ir.builder.returnValue(helper, helper_value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
            .result_codec = .i32,
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
            .symbol_name = "transform_helper",
            .value_codec = .i32,
            .result_codec = .i32,
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
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "authored", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "helper_value",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .i32,
        .has_after = true,
    }};
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 16,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn helperNormalValueWithTerminalResultCodecPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const helper = ability.ir.builder.function(1);
    const root_value = ability.ir.builder.local(root, 0);
    const helper_value = ability.ir.builder.local(helper, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callHelper(root, root_value, helper, null) catch unreachable,
        ability.ir.builder.returnValue(root, root_value) catch unreachable,
        .{ .kind = .const_i32, .dst = helper_value.index, .operand = 5 },
        ability.ir.builder.returnValue(helper, helper_value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
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
        },
        .{
            .symbol_name = "helper",
            .value_codec = .i32,
            .result_codec = .string,
            .parameter_count = 0,
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
            .instruction_count = 2,
        },
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 20,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn entryNormalValueWithDistinctResultCodecPlan(comptime label: []const u8) !ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const value = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_i32, .dst = value.index, .operand = 5 },
        ability.ir.builder.returnValue(root, value) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .string,
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
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 33,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    });
}

fn returnErrorPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const instructions = [_]ability.ir.plan.Instruction{.{
        .kind = .return_error,
        .string_literal = "Rejected",
    }};
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
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
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_unit }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 31,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn errorOnlyHelperPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const helper = ability.ir.builder.function(1);
    const value = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        ability.ir.builder.callHelperDiscardingResult(root, std.math.maxInt(u16), helper, null),
        .{ .kind = .const_i32, .dst = value.index, .operand = 5 },
        ability.ir.builder.returnValue(root, value) catch unreachable,
        .{ .kind = .return_error, .string_literal = "Rejected" },
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
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
            .instruction_count = 3,
        },
        .{
            .symbol_name = "error_helper",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 0,
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
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 3, .terminator_index = 0 },
        .{ .first_instruction = 3, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_unit },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 35,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn unreachableHelperReturnErrorPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const value = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_i32, .dst = value.index, .operand = 5 },
        ability.ir.builder.returnValue(root, value) catch unreachable,
        .{ .kind = .return_error, .string_literal = "Rejected" },
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
            .value_codec = .i32,
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
        },
        .{
            .symbol_name = "unreachable_error_helper",
            .value_codec = .unit,
            .parameter_count = 0,
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
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_unit },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 52,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn postTerminalReturnErrorPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const value = ability.ir.builder.local(root, 0);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_i32, .dst = value.index, .operand = 6 },
        ability.ir.builder.returnValue(root, value) catch unreachable,
        .{ .kind = .return_error, .string_literal = "Rejected" },
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 1,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 2,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_value },
        .{ .kind = .return_unit },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 53,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn duplicateReachableReturnErrorPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const condition = ability.ir.builder.local(root, 0);
    const value = ability.ir.builder.local(root, 1);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_i32, .dst = value.index, .operand = 0 },
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = value.index },
        .{ .kind = .return_error, .string_literal = "Rejected" },
        .{ .kind = .return_error, .string_literal = "Rejected" },
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 3,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 1, .terminator_index = 1 },
        .{ .first_instruction = 3, .instruction_count = 1, .terminator_index = 2 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 54,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .bool }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn nestedReturnErrorPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const nested = ability.ir.builder.function(1);
    const instructions = [_]ability.ir.plan.Instruction{
        .{
            .kind = .call_nested_with,
            .aux = @intFromEnum(ability.ir.ValueCodec.unit),
            .string_literal = nested_with_metadata,
        },
        .{ .kind = .return_error, .string_literal = "Rejected" },
    };
    const functions = [_]ability.ir.plan.Function{
        .{
            .symbol_name = "run",
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
        },
        .{
            .symbol_name = "nested_error",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 0,
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
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 1, .terminator_index = 1 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .return_unit },
        .{ .kind = .return_unit },
    };
    const targets = .{ability.ir.NestedWithTarget{
        .metadata = nested_with_metadata,
        .function_index = nested.index,
    }};

    return ability.ir.builder.finishWithNestedTargets(.{
        .label = label,
        .ir_hash = 55,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }, targets) catch unreachable;
}

fn entryMixedNormalAndTerminalResultCodecPlan(comptime label: []const u8) !ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const condition = ability.ir.builder.local(root, 0);
    const value = ability.ir.builder.local(root, 1);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_i32, .dst = value.index, .operand = 0 },
        .{ .kind = .compare_eq_zero, .dst = condition.index, .operand = value.index },
        .{ .kind = .const_i32, .dst = value.index, .operand = 5 },
        ability.ir.builder.returnValue(root, value) catch unreachable,
        ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 0), null) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .string,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 3,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "abort", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "abort",
        .mode = .abort,
        .payload_codec = .unit,
        .resume_codec = .unit,
        .has_after = false,
    }};
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
        .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
        .{ .first_instruction = 4, .instruction_count = 1, .terminator_index = 2 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
        .{ .kind = .return_value },
        .{ .kind = .return_unit },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 32,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .bool }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    });
}

fn matrixPlan(
    comptime mode: ability.ir.PlanControlMode,
    comptime payload_codec: ability.ir.ValueCodec,
    comptime resume_codec: ability.ir.ValueCodec,
) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const payload = ability.ir.builder.local(root, 0);
    const resume_value = ability.ir.builder.local(root, 1);
    const payload_ref = if (payload_codec == .unit) null else payload;
    const dst_ref = if (resume_codec == .unit) null else resume_value;
    const instructions = comptime blk: {
        if (payload_codec == .unit and resume_codec == .unit) break :blk [_]ability.ir.plan.Instruction{
            ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 0), null) catch unreachable,
        };
        if (payload_codec == .unit) break :blk [_]ability.ir.plan.Instruction{
            ability.ir.builder.callOp(root, dst_ref, ability.ir.builder.op(root, 0), null) catch unreachable,
            ability.ir.builder.returnValue(root, resume_value) catch unreachable,
        };
        if (resume_codec == .unit) break :blk [_]ability.ir.plan.Instruction{
            .{ .kind = .const_string, .dst = payload.index, .string_literal = "payload" },
            ability.ir.builder.callOp(root, null, ability.ir.builder.op(root, 0), payload_ref) catch unreachable,
        };
        break :blk [_]ability.ir.plan.Instruction{
            .{ .kind = .const_string, .dst = payload.index, .string_literal = "payload" },
            ability.ir.builder.callOp(root, dst_ref, ability.ir.builder.op(root, 0), payload_ref) catch unreachable,
            ability.ir.builder.returnValue(root, resume_value) catch unreachable,
        };
    };
    const function_value_codec = if (resume_codec == .unit) ability.ir.ValueCodec.unit else resume_codec;
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = function_value_codec,
        .result_codec = if (mode == .abort) null else function_value_codec,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 2,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{.{ .label = "matrix", .first_op = 0, .op_count = 1 }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "authored",
        .mode = mode,
        .payload_codec = payload_codec,
        .resume_codec = if (mode == .abort) .unit else resume_codec,
        .has_after = mode != .abort,
    }};
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = if (resume_codec == .unit) .return_unit else .return_value }};

    return ability.ir.builder.finish(.{
        .label = "matrix",
        .ir_hash = 12,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .string }, .{ .codec = .i32 } },
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn repeatedI32Locals(comptime count: usize) [count]ability.ir.plan.Local {
    return [_]ability.ir.plan.Local{.{ .codec = .i32 }} ** count;
}

fn wideLocalPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    @setEvalBranchQuota(200_000);
    const local_count = 257;
    const root = ability.ir.builder.function(0);
    const target = ability.ir.builder.local(root, local_count - 1);
    const instructions = [_]ability.ir.plan.Instruction{
        .{ .kind = .const_i32, .dst = target.index, .operand = 123 },
        ability.ir.builder.returnValue(root, target) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = local_count,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};
    const locals = repeatedI32Locals(local_count);

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 79,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &locals,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn manyAfterPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    @setEvalBranchQuota(200_000);
    const after_count = 65;
    const root = ability.ir.builder.function(0);
    const resume_local = ability.ir.builder.local(root, 0);
    const requirements = comptime blk: {
        var buf = [_]ability.ir.plan.Requirement{.{ .label = "authored", .first_op = 0, .op_count = 0 }} ** after_count;
        for (0..after_count) |index| {
            buf[index] = .{
                .label = "authored",
                .first_op = @intCast(index),
                .op_count = 1,
            };
        }
        break :blk buf;
    };
    const ops = comptime blk: {
        var buf = [_]ability.ir.plan.Op{.{
            .requirement_index = 0,
            .op_name = "dispatch",
            .mode = .transform,
            .payload_codec = .unit,
            .resume_codec = .i32,
            .has_after = true,
        }} ** after_count;
        for (0..after_count) |index| {
            buf[index] = .{
                .requirement_index = @intCast(index),
                .op_name = "dispatch",
                .mode = .transform,
                .payload_codec = .unit,
                .resume_codec = .i32,
                .has_after = true,
            };
        }
        break :blk buf;
    };
    const instructions = comptime blk: {
        var buf = [_]ability.ir.plan.Instruction{.{ .kind = .return_value }} ** (after_count + 1);
        for (0..after_count) |index| {
            buf[index] = ability.ir.builder.callOp(
                root,
                resume_local,
                ability.ir.builder.op(root, @intCast(index)),
                null,
            ) catch unreachable;
        }
        buf[after_count] = ability.ir.builder.returnValue(root, resume_local) catch unreachable;
        break :blk buf;
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = after_count,
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
    const blocks = [_]ability.ir.plan.Block{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }};

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 80,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn loopedAfterPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const counter = ability.ir.builder.local(root, 0);
    const resume_local = ability.ir.builder.local(root, 1);
    const done = ability.ir.builder.local(root, 2);
    const instructions = [_]ability.ir.plan.Instruction{
        .{
            .kind = .const_usize,
            .dst = counter.index,
            .string_literal = "8",
        },
        ability.ir.builder.callOp(root, resume_local, ability.ir.builder.op(root, 0), null) catch unreachable,
        .{
            .kind = .sub_one,
            .dst = counter.index,
            .operand = counter.index,
        },
        .{
            .kind = .compare_eq_zero,
            .dst = done.index,
            .operand = counter.index,
        },
        ability.ir.builder.returnValue(root, resume_local) catch unreachable,
    };
    const functions = [_]ability.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .i32,
        .result_codec = .i32,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 1,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 3,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 3,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]ability.ir.plan.Requirement{.{
        .label = "authored",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]ability.ir.plan.Op{.{
        .requirement_index = 0,
        .op_name = "dispatch",
        .mode = .transform,
        .payload_codec = .unit,
        .resume_codec = .i32,
        .has_after = true,
    }};
    const locals = [_]ability.ir.plan.Local{
        .{ .codec = .usize },
        .{ .codec = .i32 },
        .{ .codec = .bool },
    };
    const blocks = [_]ability.ir.plan.Block{
        .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 },
        .{ .first_instruction = 1, .instruction_count = 3, .terminator_index = 1 },
        .{ .first_instruction = 4, .instruction_count = 1, .terminator_index = 2 },
    };
    const terminators = [_]ability.ir.plan.Terminator{
        .{ .kind = .jump, .primary = 1 },
        .{ .kind = .branch_if, .primary = 2, .secondary = 1 },
        .{ .kind = .return_value },
    };

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 83,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .locals = &locals,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

fn deepHelperPlan(comptime label: []const u8) ability.ir.ProgramPlan {
    @setEvalBranchQuota(200_000);
    const function_count = 66;
    const entry = ability.ir.builder.function(0);
    const functions = comptime blk: {
        var buf = [_]ability.ir.plan.Function{.{
            .symbol_name = "helper",
            .value_codec = .i32,
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
        }} ** function_count;
        for (0..function_count) |index| {
            buf[index] = .{
                .symbol_name = "helper",
                .value_codec = .i32,
                .parameter_count = 0,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = @intCast(index),
                .local_count = 1,
                .first_block = @intCast(index),
                .entry_block = 0,
                .block_count = 1,
                .first_instruction = @intCast(index * 2),
                .instruction_count = 2,
            };
        }
        break :blk buf;
    };
    const blocks = comptime blk: {
        var buf = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 }} ** function_count;
        for (0..function_count) |index| {
            buf[index] = .{
                .first_instruction = @intCast(index * 2),
                .instruction_count = 2,
                .terminator_index = @intCast(index),
            };
        }
        break :blk buf;
    };
    const terminators = comptime blk: {
        var buf = [_]ability.ir.plan.Terminator{.{ .kind = .return_value }} ** function_count;
        for (0..function_count) |index| {
            buf[index] = .{ .kind = .return_value };
        }
        break :blk buf;
    };
    const instructions = comptime blk: {
        var buf = [_]ability.ir.plan.Instruction{.{ .kind = .return_value }} ** (function_count * 2);
        for (0..function_count) |index| {
            const function_ref = ability.ir.builder.function(@intCast(index));
            const local = ability.ir.builder.local(function_ref, 0);
            buf[index * 2] = if (index + 1 == function_count)
                .{ .kind = .const_i32, .dst = local.index, .operand = 7 }
            else
                ability.ir.builder.callHelper(
                    function_ref,
                    local,
                    ability.ir.builder.function(@intCast(index + 1)),
                    null,
                ) catch unreachable;
            buf[index * 2 + 1] = ability.ir.builder.returnValue(function_ref, local) catch unreachable;
        }
        break :blk buf;
    };
    const locals = repeatedI32Locals(function_count);

    return ability.ir.builder.finish(.{
        .label = label,
        .ir_hash = 81,
        .entry = entry,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &locals,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;
}

test "ability.program executes a builder-backed ProgramPlan" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Program = ability.program("compiled", Handlers, CompiledBody);
    var first = try Program.run(&runtime, .{ .authored = .{ .base = 30 } });
    defer first.deinit();
    try std.testing.expectEqual(@as(i32, 41), first.value);
    try std.testing.expectEqual({}, first.outputs);

    var second = try Program.run(&runtime, .{ .authored = .{ .base = 1 } });
    defer second.deinit();
    try std.testing.expectEqual(@as(i32, 12), second.value);
}

test "Program.Session yields transform requests and parks runtime while live" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = overflowArithmeticPlan("session-transform", false);
    };
    const Program = ability.program("session-transform", struct {}, Body);
    try std.testing.expect(Program.contract.session.supported);

    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);
    try std.testing.expectError(error.RuntimeBusy, runtime.deinitChecked());

    const request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);
    try std.testing.expectError(error.RuntimeBusy, runtime.deinitChecked());
    try std.testing.expectEqual(@as(@TypeOf(request.mode), .transform), request.mode);
    try std.testing.expectEqualStrings("source", request.requirement_label);
    try std.testing.expectEqualStrings("source", request.op_name);
    try request.payload(void);

    try session.@"resume"(request, @as(i32, 40));
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);
    var result = switch (try session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 41), result.value);
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 0);
}

test "Program.Session parked request interleaves Program.run on same runtime" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const ParkedBody = struct {
        pub const compiled_plan = sessionStringOpPlan(.transform, "session-parked-interleave-run");
    };
    const ParkedProgram = ability.program("session-parked-interleave-run", struct {}, ParkedBody);
    var session = try ParkedProgram.Session.start(&runtime, .{});
    defer session.deinit();
    const request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);

    const PureBody = struct {
        pub const compiled_plan = pureArithmeticPlan("session-parked-interleave-run-pure");
    };
    const PureProgram = ability.program("session-parked-interleave-run-pure", struct {}, PureBody);
    var other = try PureProgram.run(&runtime, .{});
    defer other.deinit();
    try std.testing.expectEqual(@as(i32, 7), other.value);
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);

    try session.@"resume"(request, @as(i32, 23));
    var result = switch (try session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 23), result.value);
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 0);
}

test "Program.Session parked request interleaves another session on same runtime" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const FirstBody = struct {
        pub const compiled_plan = sessionStringOpPlan(.transform, "session-parked-interleave-first");
    };
    const SecondBody = struct {
        pub const compiled_plan = sessionStringOpPlan(.transform, "session-parked-interleave-second");
    };
    const FirstProgram = ability.program("session-parked-interleave-first", struct {}, FirstBody);
    const SecondProgram = ability.program("session-parked-interleave-second", struct {}, SecondBody);

    var first_session = try FirstProgram.Session.start(&runtime, .{});
    defer first_session.deinit();
    const first_request = switch (try first_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);

    var second_session = try SecondProgram.Session.start(&runtime, .{});
    defer second_session.deinit();
    const second_request = switch (try second_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 2);

    try second_session.@"resume"(second_request, @as(i32, 44));
    var second_result = switch (try second_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer second_result.deinit();
    try std.testing.expectEqual(@as(i32, 44), second_result.value);
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);

    try first_session.@"resume"(first_request, @as(i32, 33));
    var first_result = switch (try first_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer first_result.deinit();
    try std.testing.expectEqual(@as(i32, 33), first_result.value);
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 0);
}

test "Program.Session rejects destroyed runtime before parking lifecycle starts" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    try runtime.deinitChecked();

    const Body = struct {
        pub const compiled_plan = sessionStringOpPlan(.transform, "session-destroyed-runtime");
    };
    const Program = ability.program("session-destroyed-runtime", struct {}, Body);
    try std.testing.expectError(error.RuntimeDestroyed, Program.Session.start(&runtime, .{}));
}

test "Program.Session rejects cross-thread and out-of-order close before mutating core" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = sessionChoicePlan("session-cross-thread-affinity");
    };
    const Program = ability.program("session-cross-thread-affinity", struct {}, Body);
    const Workers = struct {
        fn next(session: *Program.Session, err: *?anyerror) void {
            _ = session.next() catch |caught| {
                err.* = caught;
                return;
            };
            err.* = null;
        }

        fn @"resume"(session: *Program.Session, request: Program.Session.Request, err: *?anyerror) void {
            session.@"resume"(request, @as(i32, 13)) catch |caught| {
                err.* = caught;
                return;
            };
            err.* = null;
        }

        fn returnNow(session: *Program.Session, request: Program.Session.Request, err: *?anyerror) void {
            session.returnNow(request, @as(i32, 99)) catch |caught| {
                err.* = caught;
                return;
            };
            err.* = null;
        }

        fn deinitChecked(session: *Program.Session, err: *?anyerror) void {
            session.deinitChecked() catch |caught| {
                err.* = caught;
                return;
            };
            err.* = null;
        }

        fn expectCrossThread(err: ?anyerror) !void {
            const caught = err orelse return error.ExpectedCrossThread;
            try std.testing.expect(caught == error.CrossThread);
        }
    };

    var next_session = try Program.Session.start(&runtime, .{});
    defer next_session.deinit();
    var next_err: ?anyerror = null;
    const next_thread = try std.Thread.spawn(.{}, Workers.next, .{ &next_session, &next_err });
    next_thread.join();
    try Workers.expectCrossThread(next_err);
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);
    const next_request = switch (try next_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try next_session.@"resume"(next_request, @as(i32, 10));
    var next_result = switch (try next_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer next_result.deinit();
    try std.testing.expectEqual(@as(i32, 10), next_result.value);

    var resume_session = try Program.Session.start(&runtime, .{});
    defer resume_session.deinit();
    const resume_request = switch (try resume_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    var resume_err: ?anyerror = null;
    const resume_thread = try std.Thread.spawn(.{}, Workers.@"resume", .{ &resume_session, resume_request, &resume_err });
    resume_thread.join();
    try Workers.expectCrossThread(resume_err);
    try resume_session.@"resume"(resume_request, @as(i32, 12));
    var resume_result = switch (try resume_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer resume_result.deinit();
    try std.testing.expectEqual(@as(i32, 12), resume_result.value);

    var return_session = try Program.Session.start(&runtime, .{});
    defer return_session.deinit();
    const return_request = switch (try return_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    var return_err: ?anyerror = null;
    const return_thread = try std.Thread.spawn(.{}, Workers.returnNow, .{ &return_session, return_request, &return_err });
    return_thread.join();
    try Workers.expectCrossThread(return_err);
    try return_session.returnNow(return_request, @as(i32, 88));
    var return_result = switch (try return_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer return_result.deinit();
    try std.testing.expectEqual(@as(i32, 88), return_result.value);

    var close_session = try Program.Session.start(&runtime, .{});
    defer close_session.deinit();
    var close_err: ?anyerror = null;
    const close_thread = try std.Thread.spawn(.{}, Workers.deinitChecked, .{ &close_session, &close_err });
    close_thread.join();
    try Workers.expectCrossThread(close_err);
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);
    const close_request = switch (try close_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try close_session.@"resume"(close_request, @as(i32, 14));
    var close_result = switch (try close_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer close_result.deinit();
    try std.testing.expectEqual(@as(i32, 14), close_result.value);

    var pending_next_session = try Program.Session.start(&runtime, .{});
    defer pending_next_session.deinit();
    const pending_next_request = switch (try pending_next_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectError(error.ProgramContractViolation, pending_next_session.next());
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);
    try pending_next_session.@"resume"(pending_next_request, @as(i32, 15));
    var pending_next_result = switch (try pending_next_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer pending_next_result.deinit();
    try std.testing.expectEqual(@as(i32, 15), pending_next_result.value);

    var first_owner_session = try Program.Session.start(&runtime, .{});
    defer first_owner_session.deinit();
    const first_owner_request = switch (try first_owner_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    var second_owner_session = try Program.Session.start(&runtime, .{});
    defer second_owner_session.deinit();
    const second_owner_request = switch (try second_owner_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };

    try std.testing.expectError(error.ProgramContractViolation, second_owner_session.@"resume"(first_owner_request, @as(i32, 18)));
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 2);
    try second_owner_session.@"resume"(second_owner_request, @as(i32, 19));
    var second_owner_result = switch (try second_owner_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer second_owner_result.deinit();
    try std.testing.expectEqual(@as(i32, 19), second_owner_result.value);
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);

    try first_owner_session.@"resume"(first_owner_request, @as(i32, 18));
    var first_owner_result = switch (try first_owner_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer first_owner_result.deinit();
    try std.testing.expectEqual(@as(i32, 18), first_owner_result.value);
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 0);

    var outer_runtime = ability.Runtime.init(std.testing.allocator);
    defer outer_runtime.deinit();
    var inner_runtime = ability.Runtime.init(std.testing.allocator);
    defer inner_runtime.deinit();

    var outer_session = try Program.Session.start(&outer_runtime, .{});
    defer outer_session.deinit();
    var inner_session = try Program.Session.start(&inner_runtime, .{});
    defer inner_session.deinit();

    const outer_request = switch (try outer_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try expectRuntimeParked(&outer_runtime);
    try expectLiveSessions(&outer_runtime, 1);
    try expectRuntimeParked(&inner_runtime);
    try expectLiveSessions(&inner_runtime, 1);

    const inner_request = switch (try inner_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try expectRuntimeParked(&outer_runtime);
    try expectRuntimeParked(&inner_runtime);
    try outer_session.@"resume"(outer_request, @as(i32, 16));
    var outer_result = switch (try outer_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer outer_result.deinit();
    try std.testing.expectEqual(@as(i32, 16), outer_result.value);
    try expectRuntimeParked(&outer_runtime);
    try expectLiveSessions(&outer_runtime, 0);
    try expectLiveSessions(&inner_runtime, 1);

    try inner_session.@"resume"(inner_request, @as(i32, 20));
    var inner_result = switch (try inner_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer inner_result.deinit();
    try std.testing.expectEqual(@as(i32, 20), inner_result.value);
    try expectRuntimeParked(&inner_runtime);
    try expectLiveSessions(&inner_runtime, 0);

    var outer_pending_session = try Program.Session.start(&outer_runtime, .{});
    defer outer_pending_session.deinit();
    const outer_pending_request = switch (try outer_pending_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    var inner_pending_session = try Program.Session.start(&inner_runtime, .{});
    defer inner_pending_session.deinit();

    try expectRuntimeParked(&outer_runtime);
    try expectLiveSessions(&outer_runtime, 1);
    try expectRuntimeParked(&inner_runtime);
    try expectLiveSessions(&inner_runtime, 1);

    try outer_pending_session.@"resume"(outer_pending_request, @as(i32, 17));
    var outer_pending_result = switch (try outer_pending_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer outer_pending_result.deinit();
    try std.testing.expectEqual(@as(i32, 17), outer_pending_result.value);
    try expectLiveSessions(&outer_runtime, 0);
    try inner_pending_session.deinitChecked();
    try expectLiveSessions(&inner_runtime, 0);
}

test "Program.contract treats reachable after hooks as session-supported" {
    const Body = struct {
        pub const compiled_plan = compiledTransformPlan("session-after-hook-supported");
    };
    const Program = ability.program("session-after-hook-supported", struct {}, Body);

    try std.testing.expect(Program.contract.session.supported);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.session.blocker_count);
    try std.testing.expectEqual(@as(@TypeOf(Program.contract.session.first_blocker_tag), null), Program.contract.session.first_blocker_tag);
    try std.testing.expect(std.mem.find(u8, Program.contract.session.summary, "blockers=0") != null);
}

test "Program.Session parks runtime on transform after hook" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = compiledTransformPlan("session-transform-after");
    };
    const Program = ability.program("session-transform-after", struct {}, Body);
    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();

    const request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);
    try std.testing.expect(request.has_after);
    try session.@"resume"(request, @as(i32, 10));
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);

    const after = switch (try session.next()) {
        .after => |after| after,
        .request => return error.ExpectedAfter,
        .done => return error.ExpectedAfter,
    };
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);
    try std.testing.expectEqual(@as(u16, 0), after.requirement_index);
    try std.testing.expectEqualStrings("authored", after.requirement_label);
    try std.testing.expectEqual(@as(u16, 0), after.op_index);
    try std.testing.expectEqualStrings("dispatch", after.op_name);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, after.value_ref.codec);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, after.output_ref.codec);
    try std.testing.expectEqual(@as(i32, 10), try after.value(i32));
    try session.resumeAfter(after, @as(i32, 15));
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);

    var result = switch (try session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 15), result.value);
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 0);
}

test "Program.Session supports choice after hook on resumed path and skips return-now path" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = choiceReturnNowPlan("session-choice-after");
    };
    const Program = ability.program("session-choice-after", struct {}, Body);

    var resume_session = try Program.Session.start(&runtime, .{});
    defer resume_session.deinit();
    const resume_request = switch (try resume_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqual(@as(@TypeOf(resume_request.mode), .choice), resume_request.mode);
    try resume_session.@"resume"(resume_request, @as(i32, 21));
    const after = switch (try resume_session.next()) {
        .after => |after| after,
        .request => return error.ExpectedAfter,
        .done => return error.ExpectedAfter,
    };
    try std.testing.expectEqual(@as(i32, 21), try after.value(i32));
    try resume_session.resumeAfter(after, @as(i32, 22));
    var resumed = switch (try resume_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer resumed.deinit();
    try std.testing.expectEqual(@as(i32, 22), resumed.value);

    var return_session = try Program.Session.start(&runtime, .{});
    defer return_session.deinit();
    const return_request = switch (try return_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try return_session.returnNow(return_request, @as(i32, 99));
    var returned = switch (try return_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer returned.deinit();
    try std.testing.expectEqual(@as(i32, 99), returned.value);
}

test "Program.Session yields multiple after hooks in reverse order" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = twoAfterPlan("session-two-after");
    };
    const Program = ability.program("session-two-after", struct {}, Body);
    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();

    const first = switch (try session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqualStrings("first", first.requirement_label);
    try session.@"resume"(first, @as(i32, 10));
    const second = switch (try session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqualStrings("second", second.requirement_label);
    try session.@"resume"(second, @as(i32, 20));

    const second_after = switch (try session.next()) {
        .after => |after| after,
        .request => return error.ExpectedAfter,
        .done => return error.ExpectedAfter,
    };
    try std.testing.expectEqualStrings("second", second_after.requirement_label);
    try std.testing.expectEqual(@as(i32, 20), try second_after.value(i32));
    try session.resumeAfter(second_after, @as(i32, 21));
    const first_after = switch (try session.next()) {
        .after => |after| after,
        .request => return error.ExpectedAfter,
        .done => return error.ExpectedAfter,
    };
    try std.testing.expectEqualStrings("first", first_after.requirement_label);
    try std.testing.expectEqual(@as(i32, 21), try first_after.value(i32));
    try session.resumeAfter(first_after, @as(i32, 22));

    var result = switch (try session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 22), result.value);
}

test "Program.Session yields heterogeneous stacked after output refs" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const StackedHandlers = struct {
        outer: struct {
            pub fn dispatch(_: *const @This()) !i32 {
                return 1;
            }

            pub fn afterDispatch(_: *const @This(), value: bool) ![]const u8 {
                try std.testing.expect(value);
                return "outer:true";
            }
        },
        inner: struct {
            pub fn dispatch(_: *const @This()) !i32 {
                return 7;
            }

            pub fn afterDispatch(_: *const @This(), value: i32) !bool {
                try std.testing.expectEqual(@as(i32, 7), value);
                return true;
            }
        },
    };
    const Body = struct {
        pub const compiled_plan = stackedAfterPlan("session-stacked-after-heterogeneous");
    };
    const Program = ability.program("session-stacked-after-heterogeneous", StackedHandlers, Body);
    var session = try Program.Session.start(&runtime, .{ .outer = .{}, .inner = .{} });
    defer session.deinit();

    const outer_request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqualStrings("outer", outer_request.op_name);
    try session.@"resume"(outer_request, @as(i32, 1));

    const inner_request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqualStrings("inner", inner_request.op_name);
    try session.@"resume"(inner_request, @as(i32, 7));

    const inner_after = switch (try session.next()) {
        .after => |after| after,
        .request => return error.ExpectedAfter,
        .done => return error.ExpectedAfter,
    };
    try std.testing.expectEqualStrings("inner", inner_after.op_name);
    try std.testing.expectEqual(@as(@TypeOf(inner_after.value_ref.codec), .i32), inner_after.value_ref.codec);
    try std.testing.expectEqual(@as(@TypeOf(inner_after.output_ref.codec), .bool), inner_after.output_ref.codec);
    try std.testing.expectEqual(@as(i32, 7), try inner_after.value(i32));
    try session.resumeAfter(inner_after, true);

    const outer_after = switch (try session.next()) {
        .after => |after| after,
        .request => return error.ExpectedAfter,
        .done => return error.ExpectedAfter,
    };
    try std.testing.expectEqualStrings("outer", outer_after.op_name);
    try std.testing.expectEqual(@as(@TypeOf(outer_after.value_ref.codec), .bool), outer_after.value_ref.codec);
    try std.testing.expectEqual(@as(@TypeOf(outer_after.output_ref.codec), .string), outer_after.output_ref.codec);
    try std.testing.expect(try outer_after.value(bool));
    try session.resumeAfter(outer_after, @as([]const u8, "outer:true"));

    var result = switch (try session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try std.testing.expectEqualStrings("outer:true", result.value);
}

test "Program.Session after hook inside helper resumes caller" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = helperAfterTransformPlan("session-helper-after");
    };
    const Program = ability.program("session-helper-after", struct {}, Body);
    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();

    const request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqualStrings("helper_value", request.op_name);
    try session.@"resume"(request, @as(i32, 64));
    const after = switch (try session.next()) {
        .after => |after| after,
        .request => return error.ExpectedAfter,
        .done => return error.ExpectedAfter,
    };
    try std.testing.expectEqual(@as(i32, 64), try after.value(i32));
    try session.resumeAfter(after, @as(i32, 65));
    var result = switch (try session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 65), result.value);
}

test "Program.Session supports nested-with after completion" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = resolvedNestedWithAfterCompletionPlan("session-nested-with-after-completion");
        pub const nested_with_targets = .{ability.ir.NestedWithTarget{
            .metadata = nested_with_metadata,
            .function_index = 1,
        }};
    };
    const Program = ability.program("session-nested-with-after-completion", struct {}, Body);
    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();

    const request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try session.@"resume"(request, @as(i32, 7));
    const after = switch (try session.next()) {
        .after => |after| after,
        .request => return error.ExpectedAfter,
        .done => return error.ExpectedAfter,
    };
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, after.value_ref.codec);
    try std.testing.expectEqual(ability.ir.ValueCodec.string, after.output_ref.codec);
    try std.testing.expectEqual(@as(i32, 7), try after.value(i32));
    try session.resumeAfter(after, @as([]const u8, "nested=7"));
    var result = switch (try session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try std.testing.expectEqualStrings("nested=7", result.value);
}

test "Program.Session after hook supports product and sum values" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = struct {
        amount: i32,
    };
    const ProductBody = struct {
        pub const value_schema_types = .{ Payload, Payload };
        pub const compiled_plan = duplicateSchemaAfterResultPlan(Payload, "session-product-after");
    };
    const ProductProgram = ability.program("session-product-after", struct {}, ProductBody);
    var product_session = try ProductProgram.Session.start(&runtime, .{});
    defer product_session.deinit();
    const product_request = switch (try product_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try product_session.@"resume"(product_request, Payload{ .amount = 7 });
    const product_after = switch (try product_session.next()) {
        .after => |after| after,
        .request => return error.ExpectedAfter,
        .done => return error.ExpectedAfter,
    };
    try std.testing.expectEqual(@as(i32, 7), (try product_after.value(Payload)).amount);
    try product_session.resumeAfter(product_after, Payload{ .amount = 8 });
    var product_result = switch (try product_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer product_result.deinit();
    try std.testing.expectEqual(@as(i32, 8), product_result.value.amount);

    const SumPayload = ?i32;
    const SumBody = struct {
        pub const value_schema_types = .{SumPayload};
        pub const compiled_plan = sumAfterResultPlan(SumPayload, "session-sum-after");
    };
    const SumProgram = ability.program("session-sum-after", struct {}, SumBody);
    var sum_session = try SumProgram.Session.start(&runtime, .{});
    defer sum_session.deinit();
    const sum_request = switch (try sum_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try sum_session.@"resume"(sum_request, @as(SumPayload, 5));
    const sum_after = switch (try sum_session.next()) {
        .after => |after| after,
        .request => return error.ExpectedAfter,
        .done => return error.ExpectedAfter,
    };
    try std.testing.expectEqual(@as(i32, 5), (try sum_after.value(SumPayload)).?);
    try sum_session.resumeAfter(sum_after, @as(SumPayload, 6));
    var sum_result = switch (try sum_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer sum_result.deinit();
    try std.testing.expectEqual(@as(i32, 6), sum_result.value.?);
}

test "Program.Session rejects wrong typed and stale after resumes" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = compiledTransformPlan("session-after-misuse");
    };
    const Program = ability.program("session-after-misuse", struct {}, Body);

    var first_session = try Program.Session.start(&runtime, .{});
    defer first_session.deinit();
    const first_request = switch (try first_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try first_session.@"resume"(first_request, @as(i32, 30));
    const first_after = switch (try first_session.next()) {
        .after => |after| after,
        .request => return error.ExpectedAfter,
        .done => return error.ExpectedAfter,
    };
    try std.testing.expectError(error.ProgramContractViolation, first_session.resumeAfter(first_after, true));
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);

    var second_session = try Program.Session.start(&runtime, .{});
    defer second_session.deinit();
    const second_request = switch (try second_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try second_session.@"resume"(second_request, @as(i32, 40));
    const second_after = switch (try second_session.next()) {
        .after => |after| after,
        .request => return error.ExpectedAfter,
        .done => return error.ExpectedAfter,
    };
    try std.testing.expectError(error.ProgramContractViolation, second_session.resumeAfter(first_after, @as(i32, 31)));
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 2);
    try second_session.resumeAfter(second_after, @as(i32, 41));
    var second_result = switch (try second_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer second_result.deinit();
    try std.testing.expectEqual(@as(i32, 41), second_result.value);
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);

    try first_session.resumeAfter(first_after, @as(i32, 31));
    try std.testing.expectError(error.ProgramContractViolation, first_session.resumeAfter(first_after, @as(i32, 32)));
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 1);
    var first_result = switch (try first_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer first_result.deinit();
    try std.testing.expectEqual(@as(i32, 31), first_result.value);
    try std.testing.expectError(error.ProgramContractViolation, first_session.next());
    try expectRuntimeParked(&runtime);
    try expectLiveSessions(&runtime, 0);
}

test "Program.Session supports choice resume and returnNow" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = sessionChoicePlan("session-choice");
    };
    const Program = ability.program("session-choice", struct {}, Body);

    var resume_session = try Program.Session.start(&runtime, .{});
    defer resume_session.deinit();
    const resume_request = switch (try resume_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqual(@as(@TypeOf(resume_request.mode), .choice), resume_request.mode);
    try resume_session.@"resume"(resume_request, @as(i32, 12));
    var resumed = switch (try resume_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer resumed.deinit();
    try std.testing.expectEqual(@as(i32, 12), resumed.value);

    var return_session = try Program.Session.start(&runtime, .{});
    defer return_session.deinit();
    const return_request = switch (try return_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try return_session.returnNow(return_request, @as(i32, 99));
    var returned = switch (try return_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer returned.deinit();
    try std.testing.expectEqual(@as(i32, 99), returned.value);
}

test "Program.Session yields abort payloads and rejects wrong typed resumes" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = exceptionScalarThrowPlan("session-abort-payload");
    };
    const Program = ability.program("session-abort-payload", struct {}, Body);

    var wrong_session = try Program.Session.start(&runtime, .{});
    defer wrong_session.deinit();
    const wrong_request = switch (try wrong_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqual(@as(i32, 40), try wrong_request.payload(i32));
    try std.testing.expectError(error.ProgramContractViolation, wrong_session.@"resume"(wrong_request, true));

    var return_session = try Program.Session.start(&runtime, .{});
    defer return_session.deinit();
    const request = switch (try return_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try return_session.returnNow(request, @as(i32, 77));
    var result = switch (try return_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 77), result.value);
}

test "Program.Session decodes duplicate schema payloads by request ref" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = struct {
        amount: i32,
    };
    const EmptyHandlers = struct {};
    const Body = struct {
        pub const value_schema_types = .{ Payload, Payload };
        pub const compiled_plan = duplicateSchemaPayloadPlan(Payload, "session-duplicate-schema-payload");

        pub fn encodeArgs(_: EmptyHandlers) struct { Payload } {
            return .{.{ .amount = 123 }};
        }
    };
    const Program = ability.program("session-duplicate-schema-payload", EmptyHandlers, Body);
    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();

    const request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqual(ability.ir.ValueCodec.product, request.payload_ref.codec);
    try std.testing.expectEqual(@as(?u16, 1), request.payload_ref.schema_index);
    const payload = try request.payload(Payload);
    try std.testing.expectEqual(@as(i32, 123), payload.amount);

    try session.@"resume"(request, {});
    var result = switch (try session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
}

test "Program.Session trace operation metadata and replay fingerprint helpers" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = sessionStringOpPlan(.transform, "session-trace-operation");
    };
    const Program = ability.program("session-trace-operation", struct {}, Body);

    var first_session = try Program.Session.start(&runtime, .{});
    defer first_session.deinit();
    const first_request = switch (try first_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try expectRuntimeParked(&runtime);
    const first_trace = first_request.trace();
    try std.testing.expectEqual(@as(u32, 2), first_trace.fingerprint_version);
    try std.testing.expectEqualStrings("session-trace-operation", first_trace.program_label);
    try std.testing.expectEqualStrings("session-trace-operation", first_trace.plan_label);
    try std.testing.expectEqual(Program.compiled_plan.hash(), first_trace.plan_hash);
    try std.testing.expectEqual(@as(usize, 0), first_trace.turn_index);
    try std.testing.expectEqual(Program.Session.Trace.RequestKind.operation, first_trace.kind);
    try std.testing.expectEqual(@as(usize, 0), first_trace.operation_site_index);
    try std.testing.expectEqual(Program.contract.session.yield_sites[0].fingerprint, first_trace.operation_site_fingerprint);
    try std.testing.expectEqual(@as(usize, 0), first_trace.function_index);
    try std.testing.expectEqual(@as(usize, 0), first_trace.block_index);
    try std.testing.expectEqual(@as(usize, 1), first_trace.instruction_index);
    try std.testing.expectEqual(@as(u16, 0), first_trace.requirement_index);
    try std.testing.expectEqualStrings("session", first_trace.requirement_label);
    try std.testing.expectEqual(@as(u16, 0), first_trace.op_index);
    try std.testing.expectEqualStrings("decide", first_trace.op_name);
    try std.testing.expectEqual(ability.ir.PlanControlMode.transform, first_trace.mode);
    try std.testing.expectEqual(ability.ir.ValueCodec.string, first_trace.payload_ref.codec);
    try std.testing.expect(first_trace.has_payload);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, first_trace.resume_ref.codec);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, first_trace.result_ref.codec);
    try std.testing.expect(!first_trace.has_after);
    try std.testing.expectEqual(first_request.fingerprint(), first_trace.fingerprint);
    try std.testing.expect(first_trace.eql(first_request.fingerprint()));
    try first_request.expectFingerprint(first_request.fingerprint());
    try std.testing.expectError(error.TraceFingerprintMismatch, first_request.expectFingerprint(first_request.fingerprint() ^ 1));

    const response_trace = try first_request.responseTrace(.@"resume", @as(i32, 41));
    try std.testing.expectEqual(first_request.fingerprint(), response_trace.request_fingerprint);
    try std.testing.expectEqual(Program.Session.Trace.ResponseKind.@"resume", response_trace.kind);
    try expectRuntimeParked(&runtime);
    try first_session.@"resume"(first_request, @as(i32, 41));
    var first_result = switch (try first_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer first_result.deinit();
    try std.testing.expectEqual(@as(i32, 41), first_result.value);

    var second_session = try Program.Session.start(&runtime, .{});
    defer second_session.deinit();
    const second_request = switch (try second_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqual(first_request.fingerprint(), second_request.fingerprint());
}

test "Program.Session trace after metadata and current value fingerprint stability" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = compiledTransformPlan("session-trace-after");
    };
    const Program = ability.program("session-trace-after", struct {}, Body);

    var first_session = try Program.Session.start(&runtime, .{});
    defer first_session.deinit();
    const first_request = switch (try first_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try first_session.@"resume"(first_request, @as(i32, 30));
    const first_after = switch (try first_session.next()) {
        .after => |after| after,
        .request => return error.ExpectedAfter,
        .done => return error.ExpectedAfter,
    };
    const first_trace = first_after.trace();
    try std.testing.expectEqual(Program.Session.Trace.RequestKind.after, first_trace.kind);
    try std.testing.expectEqual(@as(usize, 1), first_trace.turn_index);
    try std.testing.expectEqual(@as(usize, 0), first_trace.after_site_index);
    try std.testing.expectEqual(Program.contract.session.after_sites[0].fingerprint, first_trace.after_site_fingerprint);
    try std.testing.expectEqual(@as(usize, 0), first_trace.source_operation_site_index);
    try std.testing.expectEqual(Program.contract.session.yield_sites[0].fingerprint, first_trace.source_operation_site_fingerprint);
    try std.testing.expectEqual(@as(usize, 0), first_trace.function_index);
    try std.testing.expectEqual(@as(usize, 0), first_trace.block_index);
    try std.testing.expectEqual(@as(usize, 0), first_trace.instruction_index);
    try std.testing.expectEqual(@as(u16, 0), first_trace.original_requirement_index);
    try std.testing.expectEqualStrings("authored", first_trace.original_requirement_label);
    try std.testing.expectEqual(@as(u16, 0), first_trace.original_op_index);
    try std.testing.expectEqualStrings("dispatch", first_trace.original_op_name);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, first_trace.current_value_ref.codec);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, first_trace.expected_output_ref.codec);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, first_trace.result_ref.codec);
    try std.testing.expectEqual(first_after.fingerprint(), first_trace.fingerprint);
    try first_after.expectFingerprint(first_after.fingerprint());
    try std.testing.expectError(error.TraceFingerprintMismatch, first_after.expectFingerprint(first_after.fingerprint() ^ 1));
    const after_response_trace = try first_after.responseTrace(.resume_after, @as(i32, 42));
    try std.testing.expectEqual(first_after.fingerprint(), after_response_trace.request_fingerprint);
    try std.testing.expectEqual(Program.Session.Trace.ResponseKind.resume_after, after_response_trace.kind);
    try std.testing.expectEqual(ability.ir.ValueCodec.i32, after_response_trace.response_ref.codec);
    try std.testing.expectError(error.ProgramContractViolation, first_after.responseTrace(.@"resume", @as(i32, 42)));

    var second_session = try Program.Session.start(&runtime, .{});
    defer second_session.deinit();
    const second_request = switch (try second_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try second_session.@"resume"(second_request, @as(i32, 30));
    const second_after = switch (try second_session.next()) {
        .after => |after| after,
        .request => return error.ExpectedAfter,
        .done => return error.ExpectedAfter,
    };
    try std.testing.expectEqual(first_after.fingerprint(), second_after.fingerprint());
    try std.testing.expectEqual(first_trace.current_value_fingerprint, second_after.trace().current_value_fingerprint);

    var third_session = try Program.Session.start(&runtime, .{});
    defer third_session.deinit();
    const third_request = switch (try third_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try third_session.@"resume"(third_request, @as(i32, 31));
    const third_after = switch (try third_session.next()) {
        .after => |after| after,
        .request => return error.ExpectedAfter,
        .done => return error.ExpectedAfter,
    };
    try std.testing.expect(first_after.fingerprint() != third_after.fingerprint());
    try std.testing.expect(first_trace.current_value_fingerprint != third_after.trace().current_value_fingerprint);
}

test "Program.Session site catalog omits unreachable call sites" {
    const Body = struct {
        pub const compiled_plan = unreachableSessionSitePlan("session-unreachable-site");
    };
    const Program = ability.program("session-unreachable-site", struct {}, Body);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.ops.len);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.session.yield_sites.len);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.session.after_sites.len);
}

test "Program.Session same op from different call sites has distinct site identity" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = sameOpTwoSiteAfterPlan("session-same-op-two-sites");
    };
    const Program = ability.program("session-same-op-two-sites", struct {}, Body);
    try std.testing.expectEqual(@as(usize, 2), Program.contract.session.yield_sites.len);
    try std.testing.expectEqual(@as(usize, 2), Program.contract.session.after_sites.len);
    try std.testing.expectEqual(@as(u16, 0), Program.contract.session.yield_sites[0].op_index);
    try std.testing.expectEqual(@as(u16, 0), Program.contract.session.yield_sites[1].op_index);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.session.yield_sites[0].instruction_index);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.session.yield_sites[1].instruction_index);
    try std.testing.expect(Program.contract.session.yield_sites[0].fingerprint != Program.contract.session.yield_sites[1].fingerprint);
    try std.testing.expectEqual(Program.contract.session.yield_sites[0].fingerprint, Program.contract.session.after_sites[0].source_operation_site_fingerprint);
    try std.testing.expectEqual(Program.contract.session.yield_sites[1].fingerprint, Program.contract.session.after_sites[1].source_operation_site_fingerprint);

    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();
    const first_request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    const first_trace = first_request.trace();
    try std.testing.expectEqual(@as(usize, 0), first_trace.operation_site_index);
    try std.testing.expectEqual(Program.contract.session.yield_sites[0].fingerprint, first_trace.operation_site_fingerprint);
    try session.@"resume"(first_request, @as(i32, 10));

    const second_request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    const second_trace = second_request.trace();
    try std.testing.expectEqual(@as(usize, 1), second_trace.operation_site_index);
    try std.testing.expectEqual(Program.contract.session.yield_sites[1].fingerprint, second_trace.operation_site_fingerprint);
    try std.testing.expect(first_request.fingerprint() != second_request.fingerprint());
    try session.@"resume"(second_request, @as(i32, 20));

    const first_after = switch (try session.next()) {
        .after => |after| after,
        .request => return error.ExpectedAfter,
        .done => return error.ExpectedAfter,
    };
    try std.testing.expectEqual(@as(usize, 1), first_after.trace().source_operation_site_index);
    try std.testing.expectEqual(Program.contract.session.yield_sites[1].fingerprint, first_after.trace().source_operation_site_fingerprint);
    try session.resumeAfter(first_after, @as(i32, 21));

    const second_after = switch (try session.next()) {
        .after => |after| after,
        .request => return error.ExpectedAfter,
        .done => return error.ExpectedAfter,
    };
    try std.testing.expectEqual(@as(usize, 0), second_after.trace().source_operation_site_index);
    try std.testing.expectEqual(Program.contract.session.yield_sites[0].fingerprint, second_after.trace().source_operation_site_fingerprint);
    try session.resumeAfter(second_after, @as(i32, 11));
}

test "Program.Session looped operation keeps static site and changes turn" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = loopedAfterPlan("session-loop-site-turn");
    };
    const Program = ability.program("session-loop-site-turn", struct {}, Body);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.session.yield_sites.len);

    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();
    const first_request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try session.@"resume"(first_request, @as(i32, 1));
    const second_request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqual(first_request.trace().operation_site_index, second_request.trace().operation_site_index);
    try std.testing.expectEqual(first_request.trace().operation_site_fingerprint, second_request.trace().operation_site_fingerprint);
    try std.testing.expectEqual(@as(usize, 0), first_request.trace().turn_index);
    try std.testing.expectEqual(@as(usize, 1), second_request.trace().turn_index);
    try std.testing.expect(first_request.fingerprint() != second_request.fingerprint());
}

test "Program.Session site coordinates include helper and nested-with target functions" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const HelperBody = struct {
        pub const compiled_plan = sessionHelperYieldPlan("session-helper-site");
    };
    const HelperProgram = ability.program("session-helper-site", struct {}, HelperBody);
    try std.testing.expectEqual(@as(usize, 1), HelperProgram.contract.session.yield_sites.len);
    try std.testing.expectEqual(@as(usize, 1), HelperProgram.contract.session.yield_sites[0].function_index);
    try std.testing.expectEqualStrings("helper", HelperProgram.contract.session.yield_sites[0].function_symbol_name);
    try std.testing.expectEqual(@as(usize, 1), HelperProgram.contract.session.yield_sites[0].block_index);
    try std.testing.expectEqual(@as(usize, 3), HelperProgram.contract.session.yield_sites[0].instruction_index);
    var helper_session = try HelperProgram.Session.start(&runtime, .{});
    defer helper_session.deinit();
    const helper_request = switch (try helper_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqual(@as(usize, 1), helper_request.trace().function_index);
    try std.testing.expectEqual(@as(usize, 3), helper_request.trace().instruction_index);

    const NestedBody = struct {
        pub const compiled_plan = resolvedNestedWithStringListPlan("session-nested-site");
        pub const nested_with_targets = .{ability.ir.NestedWithTarget{
            .metadata = nested_with_metadata,
            .function_index = 1,
        }};
    };
    const NestedProgram = ability.program("session-nested-site", struct {}, NestedBody);
    try std.testing.expectEqual(@as(usize, 1), NestedProgram.contract.session.yield_sites.len);
    try std.testing.expectEqual(@as(usize, 1), NestedProgram.contract.session.yield_sites[0].function_index);
    try std.testing.expectEqualStrings("nested", NestedProgram.contract.session.yield_sites[0].function_symbol_name);
    try std.testing.expectEqual(@as(usize, 1), NestedProgram.contract.session.yield_sites[0].block_index);
    try std.testing.expectEqual(@as(usize, 2), NestedProgram.contract.session.yield_sites[0].instruction_index);
    var nested_session = try NestedProgram.Session.start(&runtime, .{});
    defer nested_session.deinit();
    const nested_request = switch (try nested_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqual(@as(usize, 1), nested_request.trace().function_index);
    try std.testing.expectEqual(@as(usize, 2), nested_request.trace().instruction_index);
}

test "Program.Session response fingerprint changes with response value and kind" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = sessionChoicePlan("session-response-fingerprint");
    };
    const Program = ability.program("session-response-fingerprint", struct {}, Body);

    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();
    const request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    const resume_12 = try request.responseTrace(.@"resume", @as(i32, 12));
    const resume_13 = try request.responseTrace(.@"resume", @as(i32, 13));
    const return_12 = try request.responseTrace(.return_now, @as(i32, 12));
    try std.testing.expect(resume_12.fingerprint != resume_13.fingerprint);
    try std.testing.expect(resume_12.response_value_fingerprint != resume_13.response_value_fingerprint);
    try std.testing.expect(resume_12.fingerprint != return_12.fingerprint);
    try std.testing.expectEqual(request.fingerprint(), return_12.request_fingerprint);
}

test "Program.Session string fingerprint uses contents not pointer identity" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const TraceStringHandlers = struct {
        payload: []const u8,
    };
    const Body = struct {
        pub const compiled_plan = sessionStringPayloadPlan("session-string-content-fingerprint");

        pub fn encodeArgs(handlers: TraceStringHandlers) struct { []const u8 } {
            return .{handlers.payload};
        }
    };
    const Program = ability.program("session-string-content-fingerprint", TraceStringHandlers, Body);

    var first_buffer = [_]u8{ 's', 'a', 'm', 'e' };
    var first_session = try Program.Session.start(&runtime, .{ .payload = first_buffer[0..] });
    defer first_session.deinit();
    const first_request = switch (try first_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };

    var second_buffer = [_]u8{ 's', 'a', 'm', 'e' };
    var second_session = try Program.Session.start(&runtime, .{ .payload = second_buffer[0..] });
    defer second_session.deinit();
    const second_request = switch (try second_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expect(@intFromPtr(first_buffer[0..].ptr) != @intFromPtr(second_buffer[0..].ptr));
    try std.testing.expectEqual(first_request.trace().payload_value_fingerprint, second_request.trace().payload_value_fingerprint);
    try std.testing.expectEqual(first_request.fingerprint(), second_request.fingerprint());

    var third_buffer = [_]u8{ 'd', 'i', 'f', 'f' };
    var third_session = try Program.Session.start(&runtime, .{ .payload = third_buffer[0..] });
    defer third_session.deinit();
    const third_request = switch (try third_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expect(first_request.trace().payload_value_fingerprint != third_request.trace().payload_value_fingerprint);
    try std.testing.expect(first_request.fingerprint() != third_request.fingerprint());
}

test "Program.Session product payload fingerprint is stable and field-sensitive" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = struct {
        amount: i32,
    };
    const TraceProductHandlers = struct {
        amount: i32,
    };
    const Body = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = sessionProductTransformPlan(Payload, "session-product-fingerprint");

        pub fn encodeArgs(handlers: TraceProductHandlers) struct { Payload } {
            return .{.{ .amount = handlers.amount }};
        }
    };
    const Program = ability.program("session-product-fingerprint", TraceProductHandlers, Body);

    var first_session = try Program.Session.start(&runtime, .{ .amount = 3 });
    defer first_session.deinit();
    const first_request = switch (try first_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    var second_session = try Program.Session.start(&runtime, .{ .amount = 3 });
    defer second_session.deinit();
    const second_request = switch (try second_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqual(first_request.trace().payload_value_fingerprint, second_request.trace().payload_value_fingerprint);
    try std.testing.expectEqual(first_request.fingerprint(), second_request.fingerprint());

    var third_session = try Program.Session.start(&runtime, .{ .amount = 4 });
    defer third_session.deinit();
    const third_request = switch (try third_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expect(first_request.trace().payload_value_fingerprint != third_request.trace().payload_value_fingerprint);
    try std.testing.expect(first_request.fingerprint() != third_request.fingerprint());
}

test "Program.Session sum payload fingerprint is stable and variant-sensitive" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = ?i32;
    const TraceSumHandlers = struct {
        payload: Payload,
    };
    const Body = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = sessionSumTransformPlan(Payload, "session-sum-fingerprint");

        pub fn encodeArgs(handlers: TraceSumHandlers) struct { Payload } {
            return .{handlers.payload};
        }
    };
    const Program = ability.program("session-sum-fingerprint", TraceSumHandlers, Body);

    var first_session = try Program.Session.start(&runtime, .{ .payload = @as(Payload, 5) });
    defer first_session.deinit();
    const first_request = switch (try first_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    var second_session = try Program.Session.start(&runtime, .{ .payload = @as(Payload, 5) });
    defer second_session.deinit();
    const second_request = switch (try second_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqual(first_request.trace().payload_value_fingerprint, second_request.trace().payload_value_fingerprint);
    try std.testing.expectEqual(first_request.fingerprint(), second_request.fingerprint());

    var none_session = try Program.Session.start(&runtime, .{ .payload = @as(Payload, null) });
    defer none_session.deinit();
    const none_request = switch (try none_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expect(first_request.trace().payload_value_fingerprint != none_request.trace().payload_value_fingerprint);
    try std.testing.expect(first_request.fingerprint() != none_request.fingerprint());
}

test "Program.Session helper-yield request fingerprint is stable across runs" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = sessionHelperYieldPlan("session-helper-fingerprint");
    };
    const Program = ability.program("session-helper-fingerprint", struct {}, Body);

    var first_session = try Program.Session.start(&runtime, .{});
    defer first_session.deinit();
    const first_request = switch (try first_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    var second_session = try Program.Session.start(&runtime, .{});
    defer second_session.deinit();
    const second_request = switch (try second_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqualStrings("helper", first_request.requirement_label);
    try std.testing.expectEqualStrings("yield", first_request.op_name);
    try std.testing.expectEqual(first_request.fingerprint(), second_request.fingerprint());
}

test "Program.Session deinit cleans completed unconsumed result" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = struct {
        amount: i32,
    };
    const CleanupState = struct {
        var result_deinit_called = false;
    };
    const Body = struct {
        pub const value_schema_types = .{ Payload, Payload };
        pub const compiled_plan = duplicateSchemaAbortResultPlan(Payload, "session-completed-result-cleanup");

        pub fn deinitResult(_: std.mem.Allocator, value: Payload) void {
            CleanupState.result_deinit_called = value.amount == 66;
        }
    };
    const Program = ability.program("session-completed-result-cleanup", struct {}, Body);
    CleanupState.result_deinit_called = false;
    var session = try Program.Session.start(&runtime, .{});
    var session_active = true;
    defer if (session_active) session.deinit();

    const request = switch (try session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try session.returnNow(request, Payload{ .amount = 66 });
    try std.testing.expect(!CleanupState.result_deinit_called);
    session.deinit();
    session_active = false;

    try std.testing.expect(CleanupState.result_deinit_called);
    try std.testing.expectEqual(@as(usize, 0), runtime.core.active_reset_count);
}

test "Program.Session preserves helper and nested-with frames across yields" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const HelperBody = struct {
        pub const compiled_plan = helperTransformPlan("session-helper-transform");
    };
    const HelperProgram = ability.program("session-helper-transform", struct {}, HelperBody);
    var helper_session = try HelperProgram.Session.start(&runtime, .{});
    defer helper_session.deinit();
    const helper_request = switch (try helper_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    try std.testing.expectEqualStrings("helper_value", helper_request.op_name);
    try helper_session.@"resume"(helper_request, @as(i32, 64));
    var helper_result = switch (try helper_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer helper_result.deinit();
    try std.testing.expectEqual(@as(i32, 64), helper_result.value);

    const NestedBody = struct {
        pub const compiled_plan = resolvedNestedWithStringListPlan("session-nested-with-string-list");
        pub const nested_with_targets = .{ability.ir.NestedWithTarget{
            .metadata = nested_with_metadata,
            .function_index = 1,
        }};
    };
    const NestedProgram = ability.program("session-nested-with-string-list", struct {}, NestedBody);
    var nested_session = try NestedProgram.Session.start(&runtime, .{});
    defer nested_session.deinit();
    const nested_request = switch (try nested_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    var strings = [_][]const u8{ "alpha", "beta" };
    try nested_session.@"resume"(nested_request, @as([]const []const u8, strings[0..]));
    var nested_result = switch (try nested_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer nested_result.deinit();
    try std.testing.expectEqual(@as(usize, 2), nested_result.value.len);
    try std.testing.expectEqualStrings("alpha", nested_result.value[0]);
    try std.testing.expectEqualStrings("beta", nested_result.value[1]);
}

test "Program.Session materializes outputs and cleans result when output collection fails" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const OutputHandlers = struct {
        value: i32,
    };
    const OutputBody = struct {
        pub const Outputs = []i32;
        pub const compiled_plan = outputMetadataPlan("session-output-metadata");

        pub fn collectOutputs(allocator: std.mem.Allocator, handlers: *OutputHandlers) !Outputs {
            const outputs = try allocator.alloc(i32, 1);
            outputs[0] = handlers.value;
            return outputs;
        }

        pub fn deinitOutputs(allocator: std.mem.Allocator, outputs: Outputs) void {
            allocator.free(outputs);
        }
    };
    const OutputProgram = ability.program("session-output-metadata", OutputHandlers, OutputBody);
    var output_session = try OutputProgram.Session.start(&runtime, .{ .value = 91 });
    defer output_session.deinit();
    var output_result = switch (try output_session.next()) {
        .done => |done| done,
        .request => return error.ExpectedDone,
        .after => return error.UnexpectedAfter,
    };
    defer output_result.deinit();
    try std.testing.expectEqual(@as(i32, 91), output_result.outputs[0]);

    const Payload = struct {
        amount: i32,
    };
    const SessionEmptyHandlers = struct {};
    const CleanupState = struct {
        var result_deinit_called = false;
    };
    const FailingOutputBody = struct {
        pub const Error = error{OutputFailed};
        pub const Outputs = []i32;
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = productIdentityPlan(Payload, "session-output-failure-cleans-result");

        pub fn encodeArgs(_: SessionEmptyHandlers) struct { Payload } {
            return .{.{ .amount = 42 }};
        }

        pub fn collectOutputs(_: std.mem.Allocator, _: *SessionEmptyHandlers) Error!Outputs {
            return error.OutputFailed;
        }

        pub fn deinitResult(_: std.mem.Allocator, value: Payload) void {
            CleanupState.result_deinit_called = value.amount == 42;
        }
    };
    const FailingProgram = ability.program("session-output-failure-cleans-result", SessionEmptyHandlers, FailingOutputBody);
    CleanupState.result_deinit_called = false;
    var failing_session = try FailingProgram.Session.start(&runtime, .{});
    defer failing_session.deinit();
    try std.testing.expectError(error.OutputFailed, failing_session.next());
    try std.testing.expect(CleanupState.result_deinit_called);
}

test "ability.program preserves pointer handler bundle dispatch" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var handlers: Handlers = .{ .authored = .{ .base = 30 } };
    const Program = ability.program("compiled-pointer-handlers", *Handlers, CompiledBody);
    var result = try Program.run(&runtime, &handlers);
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 41), result.value);
}

test "ability.program preserves const pointer handler bundle dispatch" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const handlers: Handlers = .{ .authored = .{ .base = 30 } };
    const Program = ability.program("compiled-const-pointer-handlers", *const Handlers, CompiledBody);
    var result = try Program.run(&runtime, &handlers);
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 41), result.value);
}

test "ability.program preserves pointer-valued handler field dispatch" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var authored: AuthoredHandlers = .{ .base = 30 };
    const PointerFieldHandlers = struct {
        authored: *AuthoredHandlers,
    };
    const Program = ability.program("compiled-pointer-handler-field", PointerFieldHandlers, CompiledBody);
    var result = try Program.run(&runtime, .{ .authored = &authored });
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 41), result.value);
}

test "ability.program executes plans beyond legacy interpreter scratch caps" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const WideLocalBody = struct {
        pub const compiled_plan = wideLocalPlan("wide-local-plan");
    };
    const WideLocalProgram = ability.program("wide-local-plan", struct {}, WideLocalBody);
    var wide_local_result = try WideLocalProgram.run(&runtime, .{});
    defer wide_local_result.deinit();
    try std.testing.expectEqual(@as(i32, 123), wide_local_result.value);

    const DeepHelperBody = struct {
        pub const compiled_plan = deepHelperPlan("deep-helper-plan");
    };
    const DeepHelperProgram = ability.program("deep-helper-plan", struct {}, DeepHelperBody);
    var deep_helper_result = try DeepHelperProgram.run(&runtime, .{});
    defer deep_helper_result.deinit();
    try std.testing.expectEqual(@as(i32, 7), deep_helper_result.value);
}

test "ability.program uses shared interpreter scratch for helper frames and after stack" {
    var counting = CountingAllocator.init(std.testing.allocator);
    var runtime = ability.Runtime.init(counting.allocator());
    defer runtime.deinit();

    const DeepHelperBody = struct {
        pub const compiled_plan = deepHelperPlan("deep-helper-shared-scratch");
    };
    const DeepHelperProgram = ability.program("deep-helper-shared-scratch", struct {}, DeepHelperBody);
    var deep_helper_result = try DeepHelperProgram.run(&runtime, .{});
    defer deep_helper_result.deinit();
    try std.testing.expectEqual(@as(i32, 7), deep_helper_result.value);
    try std.testing.expect(counting.alloc_calls <= 2);
    try std.testing.expect(counting.largest_allocation_request < 64 * 1024);

    const after_deep_helper_allocs = counting.alloc_calls;
    const ManyAfterHandlers = struct {
        authored: struct {
            pub fn dispatch(_: *const @This()) !i32 {
                return 0;
            }

            pub fn afterDispatch(_: *const @This(), value: i32) !i32 {
                return value + 1;
            }
        },
    };
    const ManyAfterBody = struct {
        pub const compiled_plan = manyAfterPlan("many-after-shared-scratch");
    };
    const ManyAfterProgram = ability.program("many-after-shared-scratch", ManyAfterHandlers, ManyAfterBody);
    var many_after_result = try ManyAfterProgram.run(&runtime, .{ .authored = .{} });
    defer many_after_result.deinit();
    try std.testing.expectEqual(@as(i32, 65), many_after_result.value);
    try std.testing.expect(counting.alloc_calls - after_deep_helper_allocs <= 3);

    const before_looped_after_events = counting.allocationEvents();
    const LoopedAfterBody = struct {
        pub const compiled_plan = loopedAfterPlan("looped-after-shared-scratch");
    };
    const LoopedAfterProgram = ability.program("looped-after-shared-scratch", ManyAfterHandlers, LoopedAfterBody);
    var looped_after_result = try LoopedAfterProgram.run(&runtime, .{ .authored = .{} });
    defer looped_after_result.deinit();
    try std.testing.expectEqual(@as(i32, 8), looped_after_result.value);
    try std.testing.expect(counting.allocationEvents() - before_looped_after_events <= 3);
}

test "ability.program does not reserve after stack for plans without after hooks" {
    var counting = CountingAllocator.init(std.testing.allocator);
    var runtime = ability.Runtime.init(counting.allocator());
    defer runtime.deinit();

    const before_u16_allocs = counting.u16_aligned_alloc_calls;
    const NoAfterBody = struct {
        pub const compiled_plan = wideLocalPlan("no-after-allocation");
    };
    const NoAfterProgram = ability.program("no-after-allocation", struct {}, NoAfterBody);
    var result = try NoAfterProgram.run(&runtime, .{});
    defer result.deinit();

    try std.testing.expectEqual(@as(i32, 123), result.value);
    try std.testing.expectEqual(before_u16_allocs, counting.u16_aligned_alloc_calls);
}

test "ability.program does not heap allocate after stack for one reachable after hook" {
    var counting = CountingAllocator.init(std.testing.allocator);
    var runtime = ability.Runtime.init(counting.allocator());
    defer runtime.deinit();

    const OneAfterHandlers = struct {
        authored: struct {
            pub fn dispatch(_: *const @This()) !i32 {
                return 40;
            }

            pub fn afterDispatch(_: *const @This(), value: i32) !i32 {
                return value + 2;
            }
        },
    };
    const OneAfterBody = struct {
        pub const compiled_plan = compiledTransformPlan("one-after-lazy-allocation");
    };
    const OneAfterProgram = ability.program("one-after-lazy-allocation", OneAfterHandlers, OneAfterBody);
    var result = try OneAfterProgram.run(&runtime, .{ .authored = .{} });
    defer result.deinit();

    const full_after_stack_reservation = interpreter_step_budget * @sizeOf(u16);
    try std.testing.expectEqual(@as(i32, 42), result.value);
    try std.testing.expectEqual(@as(usize, 0), counting.u16_aligned_alloc_calls);
    try std.testing.expect(counting.largest_u16_alloc_request < full_after_stack_reservation);
}

test "ability.program applies after stack without post-dispatch allocation failure" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var runtime = ability.Runtime.init(failing.allocator());
    defer runtime.deinit();

    var dispatch_count: usize = 0;
    var after_count: usize = 0;
    const SideEffectHandlers = struct {
        authored: struct {
            dispatch_count: *usize,
            after_count: *usize,

            pub fn dispatch(self: *const @This()) !i32 {
                self.dispatch_count.* += 1;
                return 40;
            }

            pub fn afterDispatch(self: *const @This(), value: i32) !i32 {
                self.after_count.* += 1;
                return value + 2;
            }
        },
    };
    const SideEffectBody = struct {
        pub const compiled_plan = compiledTransformPlan("after-stack-oom-before-dispatch");
    };
    const SideEffectProgram = ability.program("after-stack-oom-before-dispatch", SideEffectHandlers, SideEffectBody);

    var result = try SideEffectProgram.run(&runtime, .{
        .authored = .{
            .dispatch_count = &dispatch_count,
            .after_count = &after_count,
        },
    });
    defer result.deinit();

    try std.testing.expectEqual(@as(i32, 42), result.value);
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 1), dispatch_count);
    try std.testing.expectEqual(@as(usize, 1), after_count);
}

test "ability.program return-now choice does not allocate unused after stack" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var runtime = ability.Runtime.init(failing.allocator());
    defer runtime.deinit();

    var dispatch_count: usize = 0;
    var after_count: usize = 0;
    const ReturnNowHandlers = struct {
        authored: struct {
            dispatch_count: *usize,
            after_count: *usize,

            pub fn dispatch(self: *const @This()) !ability.effect.choice.Decision(i32, i32) {
                self.dispatch_count.* += 1;
                return ability.effect.choice.Decision(i32, i32).returnNow(99);
            }

            pub fn afterDispatch(self: *const @This(), value: i32) !i32 {
                self.after_count.* += 1;
                return value + 1;
            }
        },
    };
    const ReturnNowBody = struct {
        pub const compiled_plan = choiceReturnNowPlan("choice-return-now-no-after-allocation");
    };
    const ReturnNowProgram = ability.program("choice-return-now-no-after-allocation", ReturnNowHandlers, ReturnNowBody);

    var result = try ReturnNowProgram.run(&runtime, .{
        .authored = .{
            .dispatch_count = &dispatch_count,
            .after_count = &after_count,
        },
    });
    defer result.deinit();

    try std.testing.expectEqual(@as(i32, 99), result.value);
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 1), dispatch_count);
    try std.testing.expectEqual(@as(usize, 0), after_count);
}

test "ability.program looped after pushes beyond static reachable after count" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const LoopedAfterHandlers = struct {
        authored: struct {
            pub fn dispatch(_: *const @This()) !i32 {
                return 0;
            }

            pub fn afterDispatch(_: *const @This(), value: i32) !i32 {
                return value + 1;
            }
        },
    };
    const LoopedAfterBody = struct {
        pub const compiled_plan = loopedAfterPlan("looped-after-dynamic-depth");
    };
    const LoopedAfterProgram = ability.program("looped-after-dynamic-depth", LoopedAfterHandlers, LoopedAfterBody);
    var result = try LoopedAfterProgram.run(&runtime, .{ .authored = .{} });
    defer result.deinit();

    try std.testing.expectEqual(@as(i32, 8), result.value);
}

test "ability.program accepts public ProgramValue entry args" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const EmptyHandlers = struct {};
    const ParameterizedBody = struct {
        pub const compiled_plan = parameterizedIdentityPlan("parameterized-identity");

        pub fn encodeArgs(_: EmptyHandlers) []const ability.ir.ProgramValue {
            return &.{.{ .i32 = 42 }};
        }
    };
    const Program = ability.program("parameterized-identity", EmptyHandlers, ParameterizedBody);
    var result = try Program.run(&runtime, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 42), result.value);
}

test "ability.program accepts inferred public ProgramValue entry arg arrays" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const EmptyHandlers = struct {};
    const ParameterizedBody = struct {
        pub const compiled_plan = parameterizedIdentityPlan("inferred-program-value-array-args");

        pub fn encodeArgs(_: EmptyHandlers) *const [1]ability.ir.ProgramValue {
            return &.{ability.ir.ProgramValue{ .i32 = 42 }};
        }
    };
    const Program = ability.program("inferred-program-value-array-args", EmptyHandlers, ParameterizedBody);
    var result = try Program.run(&runtime, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 42), result.value);
}

test "ability.program rejects public ProgramValue entry arg length mismatches" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const EmptyHandlers = struct {};
    const TooManyArgsBody = struct {
        pub const compiled_plan = parameterizedIdentityPlan("too-many-parameterized-identity");

        pub fn encodeArgs(_: EmptyHandlers) []const ability.ir.ProgramValue {
            return &.{ .{ .i32 = 42 }, .{ .i32 = 43 } };
        }
    };
    const MissingArgsBody = struct {
        pub const compiled_plan = parameterizedIdentityPlan("missing-parameterized-identity");

        pub fn encodeArgs(_: EmptyHandlers) []const ability.ir.ProgramValue {
            return &.{};
        }
    };
    const TooManyProgram = ability.program("too-many-parameterized-identity", EmptyHandlers, TooManyArgsBody);
    const MissingProgram = ability.program("missing-parameterized-identity", EmptyHandlers, MissingArgsBody);

    try std.testing.expectError(error.ProgramContractViolation, TooManyProgram.run(&runtime, .{}));
    try std.testing.expectError(error.ProgramContractViolation, MissingProgram.run(&runtime, .{}));
}

test "ability.program accepts typed product entry args and result" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = struct {
        amount: i32,
    };
    const EmptyHandlers = struct {};
    const ProductBody = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = productIdentityPlan(Payload, "typed-product-identity");

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{Payload{ .amount = 42 }}) {
            return .{Payload{ .amount = 42 }};
        }
    };
    const Program = ability.program("typed-product-identity", EmptyHandlers, ProductBody);
    var result = try Program.run(&runtime, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 42), result.value.amount);
}

test "ability.program executes typed sum variant predicates" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = ?i32;
    const EmptyHandlers = struct {};
    const SomeBody = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = sumVariantBranchPlan(Payload, "typed-sum-variant-some");

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{@as(Payload, 9)}) {
            return .{@as(Payload, 9)};
        }
    };
    const NoneBody = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = sumVariantBranchPlan(Payload, "typed-sum-variant-none");

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{@as(Payload, null)}) {
            return .{@as(Payload, null)};
        }
    };
    const SomeProgram = ability.program("typed-sum-variant-some", EmptyHandlers, SomeBody);
    const NoneProgram = ability.program("typed-sum-variant-none", EmptyHandlers, NoneBody);

    var some_result = try SomeProgram.run(&runtime, .{});
    defer some_result.deinit();
    var none_result = try NoneProgram.run(&runtime, .{});
    defer none_result.deinit();

    try std.testing.expectEqual(@as(i32, 11), some_result.value);
    try std.testing.expectEqual(@as(i32, 22), none_result.value);
}

test "ability.program executes typed enum variant predicates" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = enum { none, yes };
    const EmptyHandlers = struct {};
    const YesBody = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = enumVariantBranchPlan(Payload, "typed-enum-variant-yes");

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{Payload.yes}) {
            return .{Payload.yes};
        }
    };
    const NoBody = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = enumVariantBranchPlan(Payload, "typed-enum-variant-no");

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{Payload.none}) {
            return .{Payload.none};
        }
    };
    const YesProgram = ability.program("typed-enum-variant-yes", EmptyHandlers, YesBody);
    const NoProgram = ability.program("typed-enum-variant-no", EmptyHandlers, NoBody);

    var yes_result = try YesProgram.run(&runtime, .{});
    defer yes_result.deinit();
    var no_result = try NoProgram.run(&runtime, .{});
    defer no_result.deinit();

    try std.testing.expectEqual(@as(i32, 11), yes_result.value);
    try std.testing.expectEqual(@as(i32, 22), no_result.value);
}

test "ability.program extracts typed sum payloads and rejects wrong variants" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = ?i32;
    const EmptyHandlers = struct {};
    const SomeBody = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = sumPayloadExtractionPlan(Payload, "typed-sum-extract-some");

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{@as(Payload, 31)}) {
            return .{@as(Payload, 31)};
        }
    };
    const NoneBody = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = sumPayloadExtractionPlan(Payload, "typed-sum-extract-none");

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{@as(Payload, null)}) {
            return .{@as(Payload, null)};
        }
    };
    const SomeProgram = ability.program("typed-sum-extract-some", EmptyHandlers, SomeBody);
    const NoneProgram = ability.program("typed-sum-extract-none", EmptyHandlers, NoneBody);

    var some_result = try SomeProgram.run(&runtime, .{});
    defer some_result.deinit();

    try std.testing.expectEqual(@as(i32, 31), some_result.value);
    try std.testing.expectError(error.ProgramContractViolation, NoneProgram.run(&runtime, .{}));
}

test "ability.program extracts tagged-union sum payloads" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = union(enum) {
        none,
        yes: i32,
    };
    const EmptyHandlers = struct {};
    const YesBody = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = taggedUnionPayloadExtractionPlan(Payload, "typed-union-extract-yes");

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{Payload{ .yes = 41 }}) {
            return .{Payload{ .yes = 41 }};
        }
    };
    const NoBody = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = taggedUnionPayloadExtractionPlan(Payload, "typed-union-extract-no");

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{Payload{ .none = {} }}) {
            return .{Payload{ .none = {} }};
        }
    };
    const YesProgram = ability.program("typed-union-extract-yes", EmptyHandlers, YesBody);
    const NoProgram = ability.program("typed-union-extract-no", EmptyHandlers, NoBody);

    var yes_result = try YesProgram.run(&runtime, .{});
    defer yes_result.deinit();

    try std.testing.expectEqual(@as(i32, 41), yes_result.value);
    try std.testing.expectError(error.ProgramContractViolation, NoProgram.run(&runtime, .{}));
}

test "ProgramPlan validation enforces exact typed sum instruction refs" {
    const valid_sum_locals = &[_]ability.ir.plan.Local{
        .{ .codec = .sum, .schema_index = 0 },
        .{ .codec = .bool },
        .{ .codec = .i32 },
    };
    try std.testing.expectError(error.InvalidSumSourceRef, validateSingleSumInstruction(
        .{ .kind = .sum_variant_is, .dst = 1, .operand = 2, .aux = 1 },
        valid_sum_locals,
    ));
    try std.testing.expectError(error.InvalidSumVariantDestination, validateSingleSumInstruction(
        .{ .kind = .sum_variant_is, .dst = 2, .operand = 0, .aux = 1 },
        valid_sum_locals,
    ));
    try std.testing.expectError(error.InvalidSumVariantOrdinal, validateSingleSumInstruction(
        .{ .kind = .sum_variant_is, .dst = 1, .operand = 0, .aux = 2 },
        valid_sum_locals,
    ));
    try std.testing.expectError(error.InvalidSumPayloadVariant, validateSingleSumInstruction(
        .{ .kind = .sum_extract_payload, .dst = 2, .operand = 0, .aux = 0 },
        valid_sum_locals,
    ));
    try std.testing.expectError(error.InvalidSumPayloadDestination, validateSingleSumInstruction(
        .{ .kind = .sum_extract_payload, .dst = 1, .operand = 0, .aux = 1 },
        valid_sum_locals,
    ));
}

test "ability.ir.builder.typed product identity matches raw contract metadata" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = struct {
        amount: i32,
    };
    const EmptyHandlers = struct {};
    const RawBody = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = productIdentityPlan(Payload, "raw-builder-product");

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{Payload{ .amount = 5 }}) {
            return .{Payload{ .amount = 5 }};
        }
    };
    const BuiltBody = struct {
        const product_fields = [_]ability.ir.ValueFieldPlan{
            ability.ir.value.field("amount", i32),
        };
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = ability.ir.builder.typed.productIdentity(
            Payload,
            "typed-builder-product",
            &product_fields,
        );

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{Payload{ .amount = 5 }}) {
            return .{Payload{ .amount = 5 }};
        }
    };
    const RawProgram = ability.program("raw-builder-product", EmptyHandlers, RawBody);
    const BuiltProgram = ability.program("typed-builder-product", EmptyHandlers, BuiltBody);

    try std.testing.expectEqual(RawProgram.contract.result_ref.codec, BuiltProgram.contract.result_ref.codec);
    try std.testing.expectEqual(RawProgram.contract.result_ref.schema_index, BuiltProgram.contract.result_ref.schema_index);
    try std.testing.expectEqual(RawProgram.contract.entry_parameters.len, BuiltProgram.contract.entry_parameters.len);
    try std.testing.expectEqual(RawProgram.contract.value_schemas.len, BuiltProgram.contract.value_schemas.len);
    try std.testing.expectEqual(RawProgram.contract.value_fields.len, BuiltProgram.contract.value_fields.len);
    try std.testing.expectEqualStrings(RawProgram.contract.value_fields[0].name, BuiltProgram.contract.value_fields[0].name);

    var raw_result = try RawProgram.run(&runtime, .{});
    defer raw_result.deinit();
    var built_result = try BuiltProgram.run(&runtime, .{});
    defer built_result.deinit();
    try std.testing.expectEqual(raw_result.value.amount, built_result.value.amount);
}

test "ability.ir.builder.typed sum branch and payload extraction match raw behavior" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const OptionalPayload = ?i32;
    const TaggedPayload = union(enum) {
        none,
        yes: i32,
    };
    const EmptyHandlers = struct {};
    const RawBranchBody = struct {
        pub const value_schema_types = .{OptionalPayload};
        pub const compiled_plan = sumVariantBranchPlan(OptionalPayload, "raw-sum-branch");

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{@as(OptionalPayload, 9)}) {
            return .{@as(OptionalPayload, 9)};
        }
    };
    const BuiltBranchBody = struct {
        const optional_variants = [_]ability.ir.ValueVariantPlan{
            ability.ir.value.unitVariant("none"),
            ability.ir.value.variant("some", i32),
        };
        pub const value_schema_types = .{OptionalPayload};
        pub const compiled_plan = ability.ir.builder.typed.sumVariantI32Branch(
            OptionalPayload,
            .{
                .label = "typed-sum-branch",
                .variants = &optional_variants,
                .variant_ordinal = 1,
                .matched_value = 11,
                .fallback_value = 22,
            },
        );

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{@as(OptionalPayload, 9)}) {
            return .{@as(OptionalPayload, 9)};
        }
    };
    const RawExtractBody = struct {
        pub const value_schema_types = .{TaggedPayload};
        pub const compiled_plan = taggedUnionPayloadExtractionPlan(TaggedPayload, "raw-sum-extract");

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{TaggedPayload{ .yes = 41 }}) {
            return .{TaggedPayload{ .yes = 41 }};
        }
    };
    const BuiltExtractBody = struct {
        const tagged_variants = [_]ability.ir.ValueVariantPlan{
            ability.ir.value.unitVariant("none"),
            ability.ir.value.variant("yes", i32),
        };
        pub const value_schema_types = .{TaggedPayload};
        pub const compiled_plan = ability.ir.builder.typed.sumExtractI32Payload(
            TaggedPayload,
            "typed-sum-extract",
            &tagged_variants,
            1,
        );

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{TaggedPayload{ .yes = 41 }}) {
            return .{TaggedPayload{ .yes = 41 }};
        }
    };
    const RawBranchProgram = ability.program("raw-sum-branch", EmptyHandlers, RawBranchBody);
    const BuiltBranchProgram = ability.program("typed-sum-branch", EmptyHandlers, BuiltBranchBody);
    const RawExtractProgram = ability.program("raw-sum-extract", EmptyHandlers, RawExtractBody);
    const BuiltExtractProgram = ability.program("typed-sum-extract", EmptyHandlers, BuiltExtractBody);

    try std.testing.expectEqual(RawBranchProgram.contract.value_variants.len, BuiltBranchProgram.contract.value_variants.len);
    try std.testing.expectEqualStrings(RawBranchProgram.contract.value_variants[1].name, BuiltBranchProgram.contract.value_variants[1].name);
    try std.testing.expectEqual(RawExtractProgram.contract.value_variants.len, BuiltExtractProgram.contract.value_variants.len);
    try std.testing.expectEqualStrings(RawExtractProgram.contract.value_variants[1].name, BuiltExtractProgram.contract.value_variants[1].name);

    var raw_branch = try RawBranchProgram.run(&runtime, .{});
    defer raw_branch.deinit();
    var built_branch = try BuiltBranchProgram.run(&runtime, .{});
    defer built_branch.deinit();
    var raw_extract = try RawExtractProgram.run(&runtime, .{});
    defer raw_extract.deinit();
    var built_extract = try BuiltExtractProgram.run(&runtime, .{});
    defer built_extract.deinit();

    try std.testing.expectEqual(raw_branch.value, built_branch.value);
    try std.testing.expectEqual(raw_extract.value, built_extract.value);
}

test "ability.ir.builder.typed preserves full i32 constant range" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const EmptyHandlers = struct {};
    const NegativeBody = struct {
        pub const compiled_plan = ability.ir.builder.typed.scalarConstI32("typed-negative-i32", -1);
    };
    const NegativeProgram = ability.program("typed-negative-i32", EmptyHandlers, NegativeBody);

    var negative = try NegativeProgram.run(&runtime, .{});
    defer negative.deinit();
    try std.testing.expectEqual(@as(i32, -1), negative.value);

    const OptionalPayload = ?i32;
    const MatchedBody = struct {
        const optional_variants = [_]ability.ir.ValueVariantPlan{
            ability.ir.value.unitVariant("none"),
            ability.ir.value.variant("some", i32),
        };
        pub const value_schema_types = .{OptionalPayload};
        pub const compiled_plan = ability.ir.builder.typed.sumVariantI32Branch(
            OptionalPayload,
            .{
                .label = "typed-wide-i32-branch-matched",
                .variants = &optional_variants,
                .variant_ordinal = 1,
                .matched_value = std.math.maxInt(i32),
                .fallback_value = std.math.minInt(i32),
            },
        );

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{@as(OptionalPayload, 9)}) {
            return .{@as(OptionalPayload, 9)};
        }
    };
    const FallbackBody = struct {
        const optional_variants = [_]ability.ir.ValueVariantPlan{
            ability.ir.value.unitVariant("none"),
            ability.ir.value.variant("some", i32),
        };
        pub const value_schema_types = .{OptionalPayload};
        pub const compiled_plan = ability.ir.builder.typed.sumVariantI32Branch(
            OptionalPayload,
            .{
                .label = "typed-wide-i32-branch-fallback",
                .variants = &optional_variants,
                .variant_ordinal = 1,
                .matched_value = std.math.maxInt(i32),
                .fallback_value = std.math.minInt(i32),
            },
        );

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{@as(OptionalPayload, null)}) {
            return .{@as(OptionalPayload, null)};
        }
    };
    const MatchedProgram = ability.program("typed-wide-i32-branch-matched", EmptyHandlers, MatchedBody);
    const FallbackProgram = ability.program("typed-wide-i32-branch-fallback", EmptyHandlers, FallbackBody);

    var matched = try MatchedProgram.run(&runtime, .{});
    defer matched.deinit();
    try std.testing.expectEqual(@as(i32, std.math.maxInt(i32)), matched.value);

    var fallback = try FallbackProgram.run(&runtime, .{});
    defer fallback.deinit();
    try std.testing.expectEqual(@as(i32, std.math.minInt(i32)), fallback.value);
}

test "ability.program preserves expected schema index for duplicate typed product entry args" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = struct {
        amount: i32,
    };
    const EmptyHandlers = struct {};
    const ProductBody = struct {
        pub const value_schema_types = .{ Payload, Payload };
        pub const compiled_plan = duplicateSchemaIdentityPlan(Payload, "duplicate-schema-typed-product-identity");

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{Payload{ .amount = 43 }}) {
            return .{Payload{ .amount = 43 }};
        }
    };
    const Program = ability.program("duplicate-schema-typed-product-identity", EmptyHandlers, ProductBody);
    var result = try Program.run(&runtime, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 43), result.value.amount);
}

test "ability.program preserves expected schema index for duplicate typed sum payload extraction" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Item = struct {
        amount: i32,
    };
    const Payload = ?Item;
    const EmptyHandlers = struct {};
    const ProductBody = struct {
        pub const value_schema_types = .{ Payload, Item, Item };
        pub const compiled_plan = duplicateSchemaSumPayloadExtractionPlan(Payload, Item, "duplicate-schema-typed-sum-payload");

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{@as(Payload, Item{ .amount = 57 })}) {
            return .{@as(Payload, Item{ .amount = 57 })};
        }
    };
    const Program = ability.program("duplicate-schema-typed-sum-payload", EmptyHandlers, ProductBody);
    var result = try Program.run(&runtime, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 57), result.value.amount);
}

test "ability.program preserves expected schema index for duplicate typed op results" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = struct {
        amount: i32,
    };
    const StructuredHandlers = struct {
        structured: struct {
            pub fn dispatch(_: *const @This()) !Payload {
                return .{ .amount = 64 };
            }
        },
    };
    const ProductBody = struct {
        pub const value_schema_types = .{ Payload, Payload };
        pub const compiled_plan = duplicateSchemaAbortResultPlan(Payload, "duplicate-schema-typed-product-op-result");
    };
    const Program = ability.program("duplicate-schema-typed-product-op-result", StructuredHandlers, ProductBody);
    var result = try Program.run(&runtime, .{ .structured = .{} });
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 64), result.value.amount);
}

test "ability.program preallocates typed product op result before handler dispatch" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var runtime = ability.Runtime.init(failing.allocator());
    defer runtime.deinit();

    const Payload = struct {
        amount: i32,
    };
    const StructuredHandlers = struct {
        structured: struct {
            dispatch_count: *usize,

            pub fn dispatch(self: *const @This()) !Payload {
                self.dispatch_count.* += 1;
                return .{ .amount = 64 };
            }
        },
    };
    const ProductBody = struct {
        pub const value_schema_types = .{ Payload, Payload };
        pub const compiled_plan = duplicateSchemaAbortResultPlan(Payload, "typed-product-op-result-prealloc");
    };
    const Program = ability.program("typed-product-op-result-prealloc", StructuredHandlers, ProductBody);
    var dispatch_count: usize = 0;

    try std.testing.expectError(error.OutOfMemory, Program.run(&runtime, .{ .structured = .{ .dispatch_count = &dispatch_count } }));
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 0), dispatch_count);
}

test "ability.program preserves expected schema index for duplicate typed after results" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = struct {
        amount: i32,
    };
    const StructuredHandlers = struct {
        structured: struct {
            pub fn dispatch(_: *const @This()) !Payload {
                return .{ .amount = 70 };
            }

            pub fn afterDispatch(_: *const @This(), value: Payload) !Payload {
                return .{ .amount = value.amount + 1 };
            }
        },
    };
    const ProductBody = struct {
        pub const value_schema_types = .{ Payload, Payload };
        pub const compiled_plan = duplicateSchemaAfterResultPlan(Payload, "duplicate-schema-typed-product-after-result");
    };
    const Program = ability.program("duplicate-schema-typed-product-after-result", StructuredHandlers, ProductBody);
    var result = try Program.run(&runtime, .{ .structured = .{} });
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 71), result.value.amount);
}

test "ability.program preallocates typed product after result before afterDispatch" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 3 });
    var runtime = ability.Runtime.init(failing.allocator());
    defer runtime.deinit();

    const Payload = struct {
        amount: i32,
    };
    const StructuredHandlers = struct {
        structured: struct {
            dispatch_count: *usize,
            after_count: *usize,

            pub fn dispatch(self: *const @This()) !Payload {
                self.dispatch_count.* += 1;
                return .{ .amount = 70 };
            }

            pub fn afterDispatch(self: *const @This(), value: Payload) !Payload {
                self.after_count.* += 1;
                return .{ .amount = value.amount + 1 };
            }
        },
    };
    const ProductBody = struct {
        pub const value_schema_types = .{ Payload, Payload };
        pub const compiled_plan = duplicateSchemaAfterResultPlan(Payload, "typed-product-after-result-prealloc");
    };
    const Program = ability.program("typed-product-after-result-prealloc", StructuredHandlers, ProductBody);
    var dispatch_count: usize = 0;
    var after_count: usize = 0;

    try std.testing.expectError(error.OutOfMemory, Program.run(&runtime, .{
        .structured = .{
            .dispatch_count = &dispatch_count,
            .after_count = &after_count,
        },
    }));
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(@as(usize, 1), dispatch_count);
    try std.testing.expectEqual(@as(usize, 0), after_count);
}

test "ability.program preserves OOM while encoding typed product entry args" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    var runtime = ability.Runtime.init(failing.allocator());
    defer runtime.deinit();

    const Payload = struct {
        amount: i32,
    };
    const EmptyHandlers = struct {};
    const ProductBody = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = productIdentityPlan(Payload, "typed-product-arg-oom");

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{Payload{ .amount = 42 }}) {
            return .{Payload{ .amount = 42 }};
        }
    };
    const Program = ability.program("typed-product-arg-oom", EmptyHandlers, ProductBody);
    try std.testing.expectError(error.OutOfMemory, Program.run(&runtime, .{}));
    try std.testing.expect(failing.has_induced_failure);
}

test "ability.program passes typed product op payloads to handlers" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = struct {
        amount: i32,
    };
    const StructuredHandlers = struct {
        structured: struct {
            seen: *i32,

            pub fn dispatch(self: *const @This(), payload: Payload) !void {
                self.seen.* = payload.amount;
            }
        },
    };
    const ProductBody = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = structuredPayloadOpPlan(Payload, "typed-product-payload");

        pub fn encodeArgs(_: StructuredHandlers) @TypeOf(.{Payload{ .amount = 77 }}) {
            return .{Payload{ .amount = 77 }};
        }
    };
    const Program = ability.program("typed-product-payload", StructuredHandlers, ProductBody);
    var seen: i32 = 0;
    var result = try Program.run(&runtime, .{ .structured = .{ .seen = &seen } });
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 77), seen);
}

test "ability.program carries typed products through helper calls" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = struct {
        amount: i32,
    };
    const EmptyHandlers = struct {};
    const ProductBody = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = structuredHelperPlan(Payload, "typed-product-helper");

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{Payload{ .amount = 88 }}) {
            return .{Payload{ .amount = 88 }};
        }
    };
    const Program = ability.program("typed-product-helper", EmptyHandlers, ProductBody);
    var result = try Program.run(&runtime, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 88), result.value.amount);
}

test "ability.program executes recursive helpers through interpreter frame stack" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const EmptyHandlers = struct {};
    const RecursiveBody = struct {
        pub const compiled_plan = recursiveCountdownHelperPlan("recursive-countdown-helper");

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{@as(i32, 7)}) {
            return .{@as(i32, 7)};
        }
    };
    const Program = ability.program("recursive-countdown-helper", EmptyHandlers, RecursiveBody);
    var result = try Program.run(&runtime, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 0), result.value);
}

test "ability.program charges one budget unit per straight-line instruction" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const EmptyHandlers = struct {};
    const StraightLineBody = struct {
        pub const compiled_plan = budgetSizedStraightLinePlan("budget-sized-straight-line");
    };
    const Program = ability.program("budget-sized-straight-line", EmptyHandlers, StraightLineBody);
    var result = try Program.run(&runtime, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 7), result.value);
}

test "ability.program bounds unbounded helper cycles by interpreter budget" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const EmptyHandlers = struct {};
    const CycleBody = struct {
        pub const Error = error{ExecutionBudgetExceeded};
        pub const compiled_plan = unboundedHelperCyclePlan("unbounded-helper-cycle");
    };
    const Program = ability.program("unbounded-helper-cycle", EmptyHandlers, CycleBody);
    try std.testing.expectError(error.ExecutionBudgetExceeded, Program.run(&runtime, .{}));
}

test "ability.program reuses scratch storage for parameterized helper args" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 2 });
    var runtime = ability.Runtime.init(failing.allocator());
    defer runtime.deinit();

    const EmptyHandlers = struct {};
    const HelperBody = struct {
        pub const compiled_plan = parameterizedHelperPlan("parameterized-helper-no-arg-copy-alloc");

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{@as(i32, 42)}) {
            return .{@as(i32, 42)};
        }
    };
    const Program = ability.program("parameterized-helper-no-arg-copy-alloc", EmptyHandlers, HelperBody);
    var result = try Program.run(&runtime, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 42), result.value);
    try std.testing.expect(!failing.has_induced_failure);
}

test "ability.program executes resolver-backed nested-with rows" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const EmptyHandlers = struct {};
    const NestedBody = struct {
        pub const compiled_plan = resolvedNestedWithPlan("resolved-nested-with");
        pub const nested_with_targets = .{ability.ir.NestedWithTarget{
            .metadata = nested_with_metadata,
            .function_index = 1,
        }};
    };
    const Program = ability.program("resolved-nested-with", EmptyHandlers, NestedBody);
    var result = try Program.run(&runtime, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 42), result.value);
}

test "ability.program executes resolver-backed nested-with string-list rows" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const NestedHandlers = struct {
        authored: struct {
            items: [][]const u8,

            pub fn dispatch(self: *const @This()) ![][]const u8 {
                return self.items;
            }
        },
    };
    const NestedBody = struct {
        pub const compiled_plan = resolvedNestedWithStringListPlan("resolved-nested-with-string-list");
        pub const nested_with_targets = .{ability.ir.NestedWithTarget{
            .metadata = nested_with_metadata,
            .function_index = 1,
        }};
    };
    const Program = ability.program("resolved-nested-with-string-list", NestedHandlers, NestedBody);
    var strings = [_][]const u8{ "alpha", "beta" };
    var result = try Program.run(&runtime, .{ .authored = .{ .items = strings[0..] } });
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 2), result.value.len);
    try std.testing.expectEqualStrings("alpha", result.value[0]);
    try std.testing.expectEqualStrings("beta", result.value[1]);
}

test "ability.program accepts string-list typed args with mutable outer carrier" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const StringListHandlers = struct {
        items: [][]const u8,
    };
    const StringListArgs = struct { [][]const u8 };
    const StringListBody = struct {
        pub const compiled_plan = stringListIdentityPlan("string-list-typed-args");

        pub fn encodeArgs(handlers: StringListHandlers) StringListArgs {
            return .{handlers.items};
        }
    };
    const Program = ability.program("string-list-typed-args", StringListHandlers, StringListBody);
    var strings = [_][]const u8{ "left", "right" };
    var result = try Program.run(&runtime, .{ .items = strings[0..] });
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 2), result.value.len);
    try std.testing.expectEqualStrings("left", result.value[0]);
    try std.testing.expectEqualStrings("right", result.value[1]);
}

test "ability.program validates nested-with completion codec instead of terminal result codec" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const EmptyHandlers = struct {};
    const NestedBody = struct {
        pub const compiled_plan = resolvedNestedWithSplitCompletionPlan("resolved-nested-with-split-completion");
        pub const nested_with_targets = .{ability.ir.NestedWithTarget{
            .metadata = nested_with_metadata,
            .function_index = 1,
        }};
    };
    const Program = ability.program("resolved-nested-with-split-completion", EmptyHandlers, NestedBody);
    var result = try Program.run(&runtime, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 42), result.value);
}

test "ability.program validates nested-with after completion codec" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const NestedAfterHandlers = struct {
        authored: struct {
            pub fn dispatch(_: *const @This()) !i32 {
                return 42;
            }

            pub fn afterDispatch(_: *const @This(), value: i32) ![]const u8 {
                try std.testing.expectEqual(@as(i32, 42), value);
                return "forty-two";
            }
        },
    };
    const NestedBody = struct {
        pub const compiled_plan = resolvedNestedWithAfterCompletionPlan("resolved-nested-with-after-completion");
        pub const nested_with_targets = .{ability.ir.NestedWithTarget{
            .metadata = nested_with_metadata,
            .function_index = 1,
        }};
    };
    const Program = ability.program("resolved-nested-with-after-completion", NestedAfterHandlers, NestedBody);
    var result = try Program.run(&runtime, .{ .authored = .{} });
    defer result.deinit();
    try std.testing.expectEqualStrings("forty-two", result.value);
}

test "ability.program validates terminal nested-with targets before return_unit" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const TerminalHandlers = struct {
        abort: struct {
            pub fn dispatch(_: *const @This()) ![]const u8 {
                return "terminal";
            }
        },
    };
    const NestedBody = struct {
        pub const compiled_plan = terminalNestedWithSplitResultPlan("terminal-nested-with-split-result");
        pub const nested_with_targets = .{ability.ir.NestedWithTarget{
            .metadata = nested_with_metadata,
            .function_index = 1,
        }};
    };
    const Program = ability.program("terminal-nested-with-split-result", TerminalHandlers, NestedBody);
    var result = try Program.run(&runtime, .{ .abort = .{} });
    defer result.deinit();
    try std.testing.expectEqualStrings("terminal", result.value);
}

test "ability.program executes nested-with inside helper frames" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const EmptyHandlers = struct {};
    const NestedBody = struct {
        pub const compiled_plan = helperNestedWithPlan("nested-with-inside-helper");
        pub const nested_with_targets = .{ability.ir.NestedWithTarget{
            .metadata = nested_with_metadata,
            .function_index = 2,
        }};
    };
    const Program = ability.program("nested-with-inside-helper", EmptyHandlers, NestedBody);
    var result = try Program.run(&runtime, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 64), result.value);
}

test "ability.program supports terminal nested-with product result targets" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = struct {
        amount: i32,
    };
    const ProductHandlers = struct {
        abort: struct {
            pub fn dispatch(_: *const @This()) !Payload {
                return .{ .amount = 81 };
            }
        },
    };
    const NestedBody = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = terminalNestedWithProductResultPlan(Payload, "terminal-nested-with-product-result");
        pub const nested_with_targets = .{ability.ir.NestedWithTarget{
            .metadata = nested_with_metadata,
            .function_index = 1,
        }};
    };
    const Program = ability.program("terminal-nested-with-product-result", ProductHandlers, NestedBody);
    var result = try Program.run(&runtime, .{ .abort = .{} });
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 81), result.value.amount);
}

test "ability.program supports terminal nested-with sum result targets" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = ?i32;
    const SumHandlers = struct {
        abort: struct {
            pub fn dispatch(_: *const @This()) !Payload {
                return @as(Payload, 82);
            }
        },
    };
    const NestedBody = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = terminalNestedWithSumResultPlan(Payload, "terminal-nested-with-sum-result");
        pub const nested_with_targets = .{ability.ir.NestedWithTarget{
            .metadata = nested_with_metadata,
            .function_index = 1,
        }};
    };
    const Program = ability.program("terminal-nested-with-sum-result", SumHandlers, NestedBody);
    var result = try Program.run(&runtime, .{ .abort = .{} });
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 82), result.value.?);
}

test "ability.program collects outputs after nested-with execution" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Observe = struct {
        seen: bool = false,

        pub fn dispatch(self: *@This()) !void {
            self.seen = true;
        }
    };
    const NestedHandlers = struct {
        observe: Observe,
    };
    const NestedBody = struct {
        pub const Outputs = []i32;
        pub const compiled_plan = nestedWithOutputCollectionPlan("nested-with-output-collection");
        pub const nested_with_targets = .{ability.ir.NestedWithTarget{
            .metadata = nested_with_metadata,
            .function_index = 1,
        }};

        pub fn collectOutputs(allocator: std.mem.Allocator, handlers: *NestedHandlers) !Outputs {
            try std.testing.expect(handlers.observe.seen);
            const outputs = try allocator.alloc(i32, 1);
            outputs[0] = 83;
            return outputs;
        }

        pub fn deinitOutputs(allocator: std.mem.Allocator, outputs: Outputs) void {
            allocator.free(outputs);
        }
    };
    const Program = ability.program("nested-with-output-collection", NestedHandlers, NestedBody);
    var result = try Program.run(&runtime, .{ .observe = .{} });
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 83), result.outputs[0]);
    try std.testing.expectEqualStrings("observed", Program.contract.outputs[0].label);
}

test "ability.program materializes outputs through body collector and deinit hook" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Writer = struct {
        value: i32,

        fn finish(self: *@This(), allocator: std.mem.Allocator) ![]i32 {
            const outputs = try allocator.alloc(i32, 1);
            outputs[0] = self.value;
            return outputs;
        }
    };
    const OutputHandlers = struct {
        writer: Writer,
    };
    const OutputBody = struct {
        pub const Outputs = []i32;
        pub const compiled_plan = outputMetadataPlan("output-metadata");

        pub fn collectOutputs(allocator: std.mem.Allocator, handlers: *OutputHandlers) !Outputs {
            return handlers.writer.finish(allocator);
        }

        pub fn deinitOutputs(allocator: std.mem.Allocator, outputs: Outputs) void {
            allocator.free(outputs);
        }
    };
    const Program = ability.program("output-metadata", OutputHandlers, OutputBody);
    var result = try Program.run(&runtime, .{ .writer = .{ .value = 91 } });
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 1), result.outputs.len);
    try std.testing.expectEqual(@as(i32, 91), result.outputs[0]);
}

test "ability.program deinitializes result value when output collection fails" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = struct {
        amount: i32,
    };
    const CleanupState = struct {
        var deinit_called = false;
    };
    const EmptyHandlers = struct {};
    const FailingOutputBody = struct {
        pub const Error = error{OutputFailed};
        pub const Outputs = []i32;
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = productIdentityPlan(Payload, "output-failure-cleans-result");

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{Payload{ .amount = 93 }}) {
            return .{Payload{ .amount = 93 }};
        }

        pub fn collectOutputs(_: std.mem.Allocator, _: *EmptyHandlers) Error!Outputs {
            return error.OutputFailed;
        }

        pub fn deinitResult(_: std.mem.Allocator, value: Payload) void {
            std.debug.assert(value.amount == 93);
            CleanupState.deinit_called = true;
        }
    };
    const Program = ability.program("output-failure-cleans-result", EmptyHandlers, FailingOutputBody);
    CleanupState.deinit_called = false;
    try std.testing.expectError(error.OutputFailed, Program.run(&runtime, .{}));
    try std.testing.expect(CleanupState.deinit_called);
}

test "ability.program deinitializes outputs without result cleanup hook" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CleanupState = struct {
        var outputs_deinit_called = false;
    };
    const EmptyHandlers = struct {};
    const OutputBody = struct {
        pub const Outputs = []i32;
        pub const compiled_plan = outputMetadataPlan("output-only-cleanup");

        pub fn collectOutputs(allocator: std.mem.Allocator, _: *EmptyHandlers) !Outputs {
            const outputs = try allocator.alloc(i32, 1);
            outputs[0] = 7;
            return outputs;
        }

        pub fn deinitOutputs(allocator: std.mem.Allocator, outputs: Outputs) void {
            CleanupState.outputs_deinit_called = true;
            allocator.free(outputs);
        }
    };
    const Program = ability.program("output-only-cleanup", EmptyHandlers, OutputBody);
    CleanupState.outputs_deinit_called = false;
    var result = try Program.run(&runtime, .{});
    try std.testing.expectEqual(@as(i32, 7), result.outputs[0]);
    try std.testing.expect(!CleanupState.outputs_deinit_called);
    result.deinit();
    try std.testing.expect(CleanupState.outputs_deinit_called);
}

test "ability.program deinitializes result and outputs independently" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = struct {
        amount: i32,
    };
    const CleanupState = struct {
        var result_deinit_called = false;
        var outputs_deinit_called = false;
    };
    const EmptyHandlers = struct {};
    const CleanupBody = struct {
        pub const Outputs = []i32;
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = productIdentityPlan(Payload, "result-and-output-cleanup");

        pub fn encodeArgs(_: EmptyHandlers) @TypeOf(.{Payload{ .amount = 13 }}) {
            return .{Payload{ .amount = 13 }};
        }

        pub fn collectOutputs(allocator: std.mem.Allocator, _: *EmptyHandlers) !Outputs {
            const outputs = try allocator.alloc(i32, 1);
            outputs[0] = 21;
            return outputs;
        }

        pub fn deinitResult(_: std.mem.Allocator, value: Payload) void {
            std.debug.assert(value.amount == 13);
            CleanupState.result_deinit_called = true;
        }

        pub fn deinitOutputs(allocator: std.mem.Allocator, outputs: Outputs) void {
            CleanupState.outputs_deinit_called = true;
            allocator.free(outputs);
        }
    };
    const Program = ability.program("result-and-output-cleanup", EmptyHandlers, CleanupBody);
    CleanupState.result_deinit_called = false;
    CleanupState.outputs_deinit_called = false;
    var result = try Program.run(&runtime, .{});
    try std.testing.expectEqual(@as(i32, 21), result.outputs[0]);
    result.deinit();
    try std.testing.expect(CleanupState.result_deinit_called);
    try std.testing.expect(CleanupState.outputs_deinit_called);
}

test "ability.program materializes plan-native writer accumulator outputs" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const WriterHandlers = struct {
        tell: struct {
            values: *[8]i32,
            count: *usize,

            pub fn dispatch(self: *const @This(), value: i32) !void {
                self.values[self.count.*] = value;
                self.count.* += 1;
            }
        },
    };
    const CleanupState = struct {
        var outputs_deinit_called = false;
    };
    const TestState = struct {
        fn collect(allocator: std.mem.Allocator, handlers: *WriterHandlers) ![]i32 {
            const outputs = try allocator.alloc(i32, handlers.tell.count.*);
            @memcpy(outputs, handlers.tell.values[0..handlers.tell.count.*]);
            return outputs;
        }

        fn deinit(allocator: std.mem.Allocator, outputs: []i32) void {
            CleanupState.outputs_deinit_called = true;
            allocator.free(outputs);
        }
    };
    const EmptyBody = struct {
        pub const Outputs = []i32;
        pub const compiled_plan = writerAccumulatorPlan("writer-empty", &.{});

        pub fn collectOutputs(allocator: std.mem.Allocator, handlers: *WriterHandlers) !Outputs {
            return TestState.collect(allocator, handlers);
        }

        pub fn deinitOutputs(allocator: std.mem.Allocator, outputs: Outputs) void {
            TestState.deinit(allocator, outputs);
        }
    };
    const OneBody = struct {
        pub const Outputs = []i32;
        pub const compiled_plan = writerAccumulatorPlan("writer-one", &.{7});

        pub fn collectOutputs(allocator: std.mem.Allocator, handlers: *WriterHandlers) !Outputs {
            return TestState.collect(allocator, handlers);
        }

        pub fn deinitOutputs(allocator: std.mem.Allocator, outputs: Outputs) void {
            TestState.deinit(allocator, outputs);
        }
    };
    const ManyBody = struct {
        pub const Outputs = []i32;
        pub const compiled_plan = writerAccumulatorPlan("writer-many", &.{ 1, 2, 3 });

        pub fn collectOutputs(allocator: std.mem.Allocator, handlers: *WriterHandlers) !Outputs {
            return TestState.collect(allocator, handlers);
        }

        pub fn deinitOutputs(allocator: std.mem.Allocator, outputs: Outputs) void {
            TestState.deinit(allocator, outputs);
        }
    };
    const EmptyProgram = ability.program("writer-empty", WriterHandlers, EmptyBody);
    const OneProgram = ability.program("writer-one", WriterHandlers, OneBody);
    const ManyProgram = ability.program("writer-many", WriterHandlers, ManyBody);

    var values = [_]i32{0} ** 8;
    var count: usize = 0;
    CleanupState.outputs_deinit_called = false;
    var empty = try EmptyProgram.run(&runtime, .{ .tell = .{ .values = &values, .count = &count } });
    try std.testing.expectEqual(@as(usize, 0), empty.outputs.len);
    empty.deinit();
    try std.testing.expect(CleanupState.outputs_deinit_called);

    values = [_]i32{0} ** 8;
    count = 0;
    var one = try OneProgram.run(&runtime, .{ .tell = .{ .values = &values, .count = &count } });
    defer one.deinit();
    try std.testing.expectEqualSlices(i32, &.{7}, one.outputs);

    values = [_]i32{0} ** 8;
    count = 0;
    var many = try ManyProgram.run(&runtime, .{ .tell = .{ .values = &values, .count = &count } });
    defer many.deinit();
    try std.testing.expectEqualSlices(i32, &.{ 1, 2, 3 }, many.outputs);
    try std.testing.expectEqualStrings("writer", ManyProgram.contract.outputs[0].label);
    try std.testing.expectEqual(@as(@TypeOf(ManyProgram.contract.requirements[0].lifecycle_tag), .writer_accumulator), ManyProgram.contract.requirements[0].lifecycle_tag);
}

test "ability.program preserves plan-native writer collection failure" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const WriterHandlers = struct {
        tell: struct {
            count: *usize,

            pub fn dispatch(self: *const @This(), _: i32) !void {
                self.count.* += 1;
            }
        },
    };
    const FailingBody = struct {
        pub const Error = error{OutputFailed};
        pub const Outputs = []i32;
        pub const compiled_plan = writerAccumulatorPlan("writer-collection-failure", &.{9});

        pub fn collectOutputs(_: std.mem.Allocator, _: *WriterHandlers) Error!Outputs {
            return error.OutputFailed;
        }
    };
    const Program = ability.program("writer-collection-failure", WriterHandlers, FailingBody);
    var count: usize = 0;
    try std.testing.expectError(error.OutputFailed, Program.run(&runtime, .{ .tell = .{ .count = &count } }));
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "ability.program enters runtime execution before encoding entry args" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const EncodeGuardHandlers = struct {
        runtime: *ability.Runtime,
    };
    const ParameterizedBody = struct {
        pub const compiled_plan = parameterizedIdentityPlan("guarded-parameterized-identity");

        pub fn encodeArgs(handlers: EncodeGuardHandlers) []const ability.ir.ProgramValue {
            std.testing.expectError(error.RuntimeBusy, handlers.runtime.deinitChecked()) catch unreachable;
            return &.{.{ .i32 = 42 }};
        }
    };
    const Program = ability.program("guarded-parameterized-identity", EncodeGuardHandlers, ParameterizedBody);
    var result = try Program.run(&runtime, .{ .runtime = &runtime });
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 42), result.value);
}

test "ability.program rejects destroyed runtime before encoding entry args" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    try runtime.deinitChecked();

    var encode_calls: usize = 0;
    const EncodeHandlers = struct {
        calls: *usize,
    };
    const ParameterizedBody = struct {
        pub const compiled_plan = parameterizedIdentityPlan("destroyed-before-parameterized-identity");

        pub fn encodeArgs(handlers: EncodeHandlers) []const ability.ir.ProgramValue {
            handlers.calls.* += 1;
            return &.{.{ .i32 = 42 }};
        }
    };
    const Program = ability.program("destroyed-before-parameterized-identity", EncodeHandlers, ParameterizedBody);

    try std.testing.expectError(error.RuntimeDestroyed, Program.run(&runtime, .{ .calls = &encode_calls }));
    try std.testing.expectEqual(@as(usize, 0), encode_calls);
}

test "ability.program enters runtime execution for compiled plans" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const GuardHandlers = struct {
        authored: struct {
            runtime: *ability.Runtime,

            pub fn dispatch(self: *const @This()) !i32 {
                try std.testing.expectError(error.RuntimeBusy, self.runtime.deinitChecked());
                return 1;
            }

            pub fn afterDispatch(_: *const @This(), value: i32) !i32 {
                return value;
            }
        },
    };

    const Program = ability.program("runtime-guard", GuardHandlers, CompiledBody);
    var result = try Program.run(&runtime, .{ .authored = .{ .runtime = &runtime } });
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 1), result.value);
}

test "ability.program rejects destroyed runtime before compiled execution" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    try runtime.deinitChecked();

    const Program = ability.program("destroyed-runtime", Handlers, CompiledBody);
    try std.testing.expectError(error.RuntimeDestroyed, Program.run(&runtime, .{ .authored = .{ .base = 1 } }));
}

test "ability.program interprets pure arithmetic and helper ProgramPlan instructions" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const PureBody = struct {
        pub const compiled_plan = pureArithmeticPlan("pure-arithmetic");
    };
    const PureProgram = ability.program("pure", Handlers, PureBody);
    var pure_result = try PureProgram.run(&runtime, .{ .authored = .{ .base = 0 } });
    defer pure_result.deinit();
    try std.testing.expectEqual(@as(i32, 7), pure_result.value);

    const HelperBody = struct {
        pub const compiled_plan = helperPlan("helper-plan");
    };
    const HelperProgram = ability.program("helper", Handlers, HelperBody);
    var helper_result = try HelperProgram.run(&runtime, .{ .authored = .{ .base = 0 } });
    defer helper_result.deinit();
    try std.testing.expectEqual(@as(i32, 9), helper_result.value);

    const UsizeBody = struct {
        pub const compiled_plan = usizeLiteralPlan("usize-literal");
    };
    const UsizeProgram = ability.program("usize-literal", Handlers, UsizeBody);
    var usize_result = try UsizeProgram.run(&runtime, .{ .authored = .{ .base = 0 } });
    defer usize_result.deinit();
    try std.testing.expectEqual(@as(usize, 0xff), usize_result.value);

    const BoolCompareBody = struct {
        pub const compiled_plan = boolComparePlan("bool-compare");
    };
    const BoolCompareProgram = ability.program("bool-compare", BoolHandlers, BoolCompareBody);
    var bool_compare_result = try BoolCompareProgram.run(&runtime, .{ .probe = .{} });
    defer bool_compare_result.deinit();
    try std.testing.expectEqual(true, bool_compare_result.value);

    const UsizeSubOneBody = struct {
        pub const compiled_plan = usizeSubOnePlan("usize-sub-one");
    };
    const UsizeSubOneProgram = ability.program("usize-sub-one", Handlers, UsizeSubOneBody);
    var usize_sub_one_result = try UsizeSubOneProgram.run(&runtime, .{ .authored = .{ .base = 0 } });
    defer usize_sub_one_result.deinit();
    try std.testing.expectEqual(@as(usize, 2), usize_sub_one_result.value);

    const HelperUsizeOffsetBody = struct {
        pub const compiled_plan = helperUsizeLocalOffsetPlan("helper-usize-local-offset");
    };
    const HelperUsizeOffsetProgram = ability.program("helper-usize-local-offset", Handlers, HelperUsizeOffsetBody);
    var helper_usize_offset_result = try HelperUsizeOffsetProgram.run(&runtime, .{ .authored = .{ .base = 0 } });
    defer helper_usize_offset_result.deinit();
    try std.testing.expectEqual(@as(usize, 1), helper_usize_offset_result.value);

    const ZeroArgLegacyAuxBody = struct {
        pub const compiled_plan = zeroArgHelperLegacyAuxPlan("zero-arg-helper-legacy-aux");
    };
    const ZeroArgLegacyAuxProgram = ability.program("zero-arg-helper-legacy-aux", Handlers, ZeroArgLegacyAuxBody);
    var zero_arg_legacy_aux_result = try ZeroArgLegacyAuxProgram.run(&runtime, .{ .authored = .{ .base = 0 } });
    defer zero_arg_legacy_aux_result.deinit();
    try std.testing.expectEqual(@as(i32, 12), zero_arg_legacy_aux_result.value);

    var touch_calls: usize = 0;
    const UnitResumeKeepsLocalBody = struct {
        pub const compiled_plan = unitResumeKeepsLocalPlan("unit-resume-keeps-local");
    };
    const UnitResumeKeepsLocalProgram = ability.program("unit-resume-keeps-local", UnitHandlers, UnitResumeKeepsLocalBody);
    var unit_resume_keeps_local_result = try UnitResumeKeepsLocalProgram.run(&runtime, .{ .touch = .{ .calls = &touch_calls } });
    defer unit_resume_keeps_local_result.deinit();
    try std.testing.expectEqual(@as(i32, 7), unit_resume_keeps_local_result.value);
    try std.testing.expectEqual(@as(usize, 1), touch_calls);
}

test "ability.program executes the public scalar ProgramPlan subset" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const VoidBody = struct {
        pub const compiled_plan = voidReturnPlan("scalar-void");
    };
    const VoidProgram = ability.program("scalar-void", struct {}, VoidBody);
    var void_result = try VoidProgram.run(&runtime, .{});
    defer void_result.deinit();
    try std.testing.expectEqual({}, void_result.value);

    const BoolBody = struct {
        pub const compiled_plan = boolComparePlan("scalar-bool");
    };
    const BoolProgram = ability.program("scalar-bool", BoolHandlers, BoolBody);
    var bool_result = try BoolProgram.run(&runtime, .{ .probe = .{} });
    defer bool_result.deinit();
    try std.testing.expectEqual(true, bool_result.value);

    const I32Body = struct {
        pub const compiled_plan = pureArithmeticPlan("scalar-i32");
    };
    const I32Program = ability.program("scalar-i32", struct {}, I32Body);
    var i32_result = try I32Program.run(&runtime, .{});
    defer i32_result.deinit();
    try std.testing.expectEqual(@as(i32, 7), i32_result.value);

    const UsizeBody = struct {
        pub const compiled_plan = usizeLiteralPlan("scalar-usize");
    };
    const UsizeProgram = ability.program("scalar-usize", struct {}, UsizeBody);
    var usize_result = try UsizeProgram.run(&runtime, .{});
    defer usize_result.deinit();
    try std.testing.expectEqual(@as(usize, 0xff), usize_result.value);

    const StringBody = struct {
        pub const compiled_plan = stringLiteralPlan("scalar-string");
    };
    const StringProgram = ability.program("scalar-string", struct {}, StringBody);
    var string_result = try StringProgram.run(&runtime, .{});
    defer string_result.deinit();
    try std.testing.expectEqualStrings("scalar string", string_result.value);
}

test "ability.program allows scalar plans with unreachable structured schemas" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Body = struct {
        pub const compiled_plan = scalarPlanWithUnreachableStructuredSchema("scalar-unreachable-schema");
    };
    const Program = ability.program("scalar-unreachable-schema", struct {}, Body);
    var result = try Program.run(&runtime, .{});
    defer result.deinit();
    try std.testing.expectEqual({}, result.value);
}

test "ability.program applies after continuation exactly once" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const CountingHandlers = struct {
        authored: struct {
            count: *usize,

            pub fn dispatch(_: *const @This()) !i32 {
                return 5;
            }

            pub fn afterDispatch(self: *const @This(), value: i32) !i32 {
                self.count.* += 1;
                return value + 1;
            }
        },
    };

    var count: usize = 0;
    const Program = ability.program("one-shot-after", CountingHandlers, CompiledBody);
    var result = try Program.run(&runtime, .{ .authored = .{ .count = &count } });
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 6), result.value);
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "ability.program unwinds more after continuations than helper call budget" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const ManyAfterHandlers = struct {
        authored: struct {
            pub fn dispatch(_: *const @This()) !i32 {
                return 0;
            }

            pub fn afterDispatch(_: *const @This(), value: i32) !i32 {
                return value + 1;
            }
        },
    };
    const ManyAfterBody = struct {
        pub const compiled_plan = manyAfterPlan("many-after-plan");
    };
    const ManyAfterProgram = ability.program("many-after-plan", ManyAfterHandlers, ManyAfterBody);
    var result = try ManyAfterProgram.run(&runtime, .{ .authored = .{} });
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 65), result.value);
}

test "ability.program unwinds stacked after continuations with current answer codec" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const StackedHandlers = struct {
        outer: struct {
            count: *usize,

            pub fn dispatch(_: *const @This()) !i32 {
                return 1;
            }

            pub fn afterDispatch(self: *const @This(), value: bool) ![]const u8 {
                self.count.* += 1;
                try std.testing.expect(value);
                return "outer:true";
            }
        },
        inner: struct {
            count: *usize,

            pub fn dispatch(_: *const @This()) !i32 {
                return 7;
            }

            pub fn afterDispatch(self: *const @This(), value: i32) !bool {
                self.count.* += 1;
                try std.testing.expectEqual(@as(i32, 7), value);
                return true;
            }
        },
    };
    const StackedBody = struct {
        pub const compiled_plan = stackedAfterPlan("stacked-after");
    };

    var outer_count: usize = 0;
    var inner_count: usize = 0;
    const Program = ability.program("stacked-after", StackedHandlers, StackedBody);
    var result = try Program.run(&runtime, .{
        .outer = .{ .count = &outer_count },
        .inner = .{ .count = &inner_count },
    });
    defer result.deinit();
    try std.testing.expectEqualStrings("outer:true", result.value);
    try std.testing.expectEqual(@as(usize, 1), outer_count);
    try std.testing.expectEqual(@as(usize, 1), inner_count);
}

test "ability.program skips after continuations for terminal escapes" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const TerminalHandlers = struct {
        outer: struct {
            count: *usize,

            pub fn dispatch(_: *const @This()) !i32 {
                return 7;
            }

            pub fn afterDispatch(self: *const @This(), value: i32) ![]const u8 {
                self.count.* += 1;
                try std.testing.expectEqual(@as(i32, 7), value);
                return "normal";
            }
        },
        abort: struct {
            pub fn dispatch(_: *const @This()) ![]const u8 {
                return "terminal";
            }
        },
    };
    const TerminalBody = struct {
        pub const compiled_plan = terminalBypassesAfterPlan("terminal-bypasses-after");
    };

    var after_count: usize = 0;
    const Program = ability.program("terminal-bypasses-after", TerminalHandlers, TerminalBody);
    var result = try Program.run(&runtime, .{
        .outer = .{ .count = &after_count },
        .abort = .{},
    });
    defer result.deinit();
    try std.testing.expectEqualStrings("terminal", result.value);
    try std.testing.expectEqual(@as(usize, 0), after_count);
}

test "ability.program executes plan-native exception scalar throw catch" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const ExceptionHandlers = struct {
        throw: struct {
            pub fn dispatch(_: *const @This(), payload: i32) !i32 {
                return payload + 1;
            }
        },
    };
    const ExceptionBody = struct {
        pub const compiled_plan = exceptionScalarThrowPlan("plan-native-exception-scalar-test");
    };
    const Program = ability.program("plan-native-exception-scalar-test", ExceptionHandlers, ExceptionBody);
    var result = try Program.run(&runtime, .{ .throw = .{} });
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 41), result.value);
    try std.testing.expectEqual(@as(@TypeOf(Program.contract.ops[0].mode), .abort), Program.contract.ops[0].mode);
    try std.testing.expectEqual(@as(@TypeOf(Program.contract.requirements[0].lifecycle_tag), .abort_catch), Program.contract.requirements[0].lifecycle_tag);
}

test "ability.program executes plan-native exception product throw catch" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = struct {
        amount: i32,
    };
    const ExceptionHandlers = struct {
        throw: struct {
            pub fn dispatch(_: *const @This(), payload: Payload) !Payload {
                return .{ .amount = payload.amount + 1 };
            }
        },
    };
    const ExceptionBody = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = exceptionProductThrowPlan(Payload, "plan-native-exception-product-test");

        pub fn encodeArgs(_: ExceptionHandlers) @TypeOf(.{Payload{ .amount = 50 }}) {
            return .{Payload{ .amount = 50 }};
        }
    };
    const Program = ability.program("plan-native-exception-product-test", ExceptionHandlers, ExceptionBody);
    var result = try Program.run(&runtime, .{ .throw = .{} });
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 51), result.value.amount);
    try std.testing.expectEqual(ability.ir.ValueCodec.product, Program.contract.ops[0].payload_ref.codec);
    try std.testing.expectEqual(@as(?u16, 0), Program.contract.ops[0].payload_ref.schema_index);
}

test "ability.program executes plan-native exception sum throw catch" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const Payload = ?i32;
    const ExceptionHandlers = struct {
        throw: struct {
            pub fn dispatch(_: *const @This(), payload: Payload) !i32 {
                return (payload orelse 0) + 1;
            }
        },
    };
    const ExceptionBody = struct {
        pub const value_schema_types = .{Payload};
        pub const compiled_plan = exceptionSumThrowPlan(Payload, "plan-native-exception-sum-test");

        pub fn encodeArgs(_: ExceptionHandlers) @TypeOf(.{@as(Payload, 60)}) {
            return .{@as(Payload, 60)};
        }
    };
    const Program = ability.program("plan-native-exception-sum-test", ExceptionHandlers, ExceptionBody);
    var result = try Program.run(&runtime, .{ .throw = .{} });
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 61), result.value);
    try std.testing.expectEqual(ability.ir.ValueCodec.sum, Program.contract.ops[0].payload_ref.codec);
    try std.testing.expectEqual(@as(usize, 2), Program.contract.value_variants.len);
}

test "ability.program executes nested plan-native exception terminal escape" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const ExceptionHandlers = struct {
        throw: struct {
            pub fn dispatch(_: *const @This(), payload: i32) !i32 {
                return payload + 1;
            }
        },
    };
    const ExceptionBody = struct {
        pub const compiled_plan = nestedExceptionThrowPlan("plan-native-exception-nested-test");
    };
    const Program = ability.program("plan-native-exception-nested-test", ExceptionHandlers, ExceptionBody);
    var result = try Program.run(&runtime, .{ .throw = .{} });
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 71), result.value);
}

test "ability.program executes plan-native resource LIFO release" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const summary = try plan_native_resource.runNormal(&runtime);
    try std.testing.expectEqual(@as(i32, 12), summary.value);
    try std.testing.expectEqual(@as(usize, 4), summary.count);
    try std.testing.expectEqual(@as(i32, 1), summary.events[0]);
    try std.testing.expectEqual(@as(i32, 2), summary.events[1]);
    try std.testing.expectEqual(@as(i32, -2), summary.events[2]);
    try std.testing.expectEqual(@as(i32, -1), summary.events[3]);
}

test "ability.program releases plan-native resources before exception terminal escape" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const summary = try plan_native_resource.runExceptionEscape(&runtime);
    try std.testing.expectEqual(@as(i32, 80), summary.value);
    try std.testing.expectEqual(@as(usize, 4), summary.count);
    try std.testing.expectEqual(@as(i32, -2), summary.events[2]);
    try std.testing.expectEqual(@as(i32, -1), summary.events[3]);
}

test "ability.program releases plan-native resources before optional return-now escape" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const summary = try plan_native_resource.runOptionalEscape(&runtime);
    try std.testing.expectEqual(@as(i32, 90), summary.value);
    try std.testing.expectEqual(@as(usize, 4), summary.count);
    try std.testing.expectEqual(@as(i32, -2), summary.events[2]);
    try std.testing.expectEqual(@as(i32, -1), summary.events[3]);
}

test "ability.program surfaces plan-native resource release failure" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    try std.testing.expectError(error.ReleaseFailed, plan_native_resource.runReleaseFailure(&runtime));
}

test "ability.program dispatches duplicate op names by requirement namespace" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const NamespacedHandlers = struct {
        left: struct {
            get: struct {
                pub fn dispatch(_: *const @This()) !i32 {
                    return 10;
                }
            },
        },
        right: struct {
            get: struct {
                pub fn dispatch(_: *const @This()) !i32 {
                    return 32;
                }
            },
        },
    };
    const NamespacedBody = struct {
        pub const compiled_plan = duplicateOperationNamesPlan("duplicate-op-names");
    };

    const Program = ability.program("duplicate-op-names", NamespacedHandlers, NamespacedBody);
    var result = try Program.run(&runtime, .{ .left = .{ .get = .{} }, .right = .{ .get = .{} } });
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 42), result.value);
}

test "ability.program ignores unchecked unit operands" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const UnitPayloadBody = struct {
        pub const compiled_plan = invalidUnitPayloadOperandPlan("ignored-unit-payload-operand") catch unreachable;
    };
    const UnitPayloadHandlers = struct {
        source: struct {
            pub fn dispatch(_: *const @This()) !i32 {
                return 7;
            }
        },
    };
    const UnitPayloadProgram = ability.program("ignored-unit-payload-operand", UnitPayloadHandlers, UnitPayloadBody);
    var unit_payload_result = try UnitPayloadProgram.run(&runtime, .{ .source = .{} });
    defer unit_payload_result.deinit();
    try std.testing.expectEqual(@as(i32, 7), unit_payload_result.value);

    const UnitHelperBody = struct {
        pub const compiled_plan = invalidUnitHelperDestinationPlan("ignored-unit-helper-destination") catch unreachable;
    };
    const UnitHelperProgram = ability.program("ignored-unit-helper-destination", struct {}, UnitHelperBody);
    var unit_helper_result = try UnitHelperProgram.run(&runtime, .{});
    defer unit_helper_result.deinit();
}

test "ability.program abort op completes without running body tail" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const AbortBody = struct {
        pub const compiled_plan = abortPlan("abort-plan");
    };
    const AbortHandlers = struct {
        authored: struct {
            pub fn dispatch(_: *const @This()) !i32 {
                return 7;
            }
        },
    };
    const Program = ability.program("abort", AbortHandlers, AbortBody);
    var result = try Program.run(&runtime, .{ .authored = .{} });
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 7), result.value);
}

test "ability.program propagates terminal helper results to the caller" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const HelperAbortBody = struct {
        pub const compiled_plan = helperAbortPlan("helper-abort-plan");
    };
    const AbortHandlers = struct {
        abort: struct {
            pub fn dispatch(_: *const @This()) !i32 {
                return 7;
            }
        },
    };
    const Program = ability.program("helper-abort", AbortHandlers, HelperAbortBody);
    var result = try Program.run(&runtime, .{ .abort = .{} });
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 7), result.value);
}

test "ability.program preserves normal helper value when result codec covers terminal escapes" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const HelperBody = struct {
        pub const compiled_plan = helperNormalValueWithTerminalResultCodecPlan("helper-normal-terminal-result-codec");
    };
    const Program = ability.program("helper-normal-terminal-result-codec", struct {}, HelperBody);
    var result = try Program.run(&runtime, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 5), result.value);
}

test "ability.program surfaces declared ProgramPlan return_error values" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const ErrorBody = struct {
        pub const Error = error{Rejected};
        pub const compiled_plan = returnErrorPlan("return-error");
    };
    const Program = ability.program("return-error", struct {}, ErrorBody);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.return_errors.len);
    try std.testing.expectEqualStrings("Rejected", Program.contract.return_errors[0]);
    try std.testing.expectError(error.Rejected, Program.run(&runtime, .{}));
}

test "ability.program omits unreachable helper return_error values" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const ErrorBody = struct {
        pub const compiled_plan = unreachableHelperReturnErrorPlan("unreachable-helper-return-error");
    };
    const Program = ability.program("unreachable-helper-return-error", struct {}, ErrorBody);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.return_errors.len);

    var result = try Program.run(&runtime, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 5), result.value);
}

test "ability.program omits post-terminal return_error values" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const ErrorBody = struct {
        pub const compiled_plan = postTerminalReturnErrorPlan("post-terminal-return-error");
    };
    const Program = ability.program("post-terminal-return-error", struct {}, ErrorBody);
    try std.testing.expectEqual(@as(usize, 0), Program.contract.return_errors.len);

    var result = try Program.run(&runtime, .{});
    defer result.deinit();
    try std.testing.expectEqual(@as(i32, 6), result.value);
}

test "ability.program exposes unique reachable return_error values" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const ErrorBody = struct {
        pub const Error = error{Rejected};
        pub const compiled_plan = duplicateReachableReturnErrorPlan("duplicate-reachable-return-error");
    };
    const Program = ability.program("duplicate-reachable-return-error", struct {}, ErrorBody);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.return_errors.len);
    try std.testing.expectEqualStrings("Rejected", Program.contract.return_errors[0]);
    try std.testing.expectError(error.Rejected, Program.run(&runtime, .{}));
}

test "ability.program allows anyerror ProgramPlan return_error values" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const ErrorBody = struct {
        pub const Error = anyerror;
        pub const compiled_plan = returnErrorPlan("anyerror-return-error");
    };
    const Program = ability.program("anyerror-return-error", struct {}, ErrorBody);
    try std.testing.expectError(error.Rejected, Program.run(&runtime, .{}));
}

test "ability.program propagates error-only helper without result-codec match" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const ErrorBody = struct {
        pub const Error = error{Rejected};
        pub const compiled_plan = errorOnlyHelperPlan("error-only-helper");
    };
    const Program = ability.program("error-only-helper", struct {}, ErrorBody);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.return_errors.len);
    try std.testing.expectEqualStrings("Rejected", Program.contract.return_errors[0]);
    try std.testing.expectError(error.Rejected, Program.run(&runtime, .{}));
}

test "ability.program propagates reachable nested-with return_error" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const ErrorBody = struct {
        pub const Error = error{Rejected};
        pub const compiled_plan = nestedReturnErrorPlan("nested-return-error");
        pub const nested_with_targets = .{ability.ir.NestedWithTarget{
            .metadata = nested_with_metadata,
            .function_index = 1,
        }};
    };
    const Program = ability.program("nested-return-error", struct {}, ErrorBody);
    try std.testing.expectEqual(@as(usize, 1), Program.contract.return_errors.len);
    try std.testing.expectEqualStrings("Rejected", Program.contract.return_errors[0]);
    try std.testing.expectError(error.Rejected, Program.run(&runtime, .{}));
}

test "ability.program maps undeclared handler errors to ProgramContractViolation" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const RejectingHandlers = struct {
        authored: struct {
            pub fn dispatch(_: *const @This()) !i32 {
                return error.HandlerRejected;
            }

            pub fn afterDispatch(_: *const @This(), value: i32) !i32 {
                return value;
            }
        },
    };
    const Program = ability.program("undeclared-handler-error", RejectingHandlers, CompiledBody);
    try std.testing.expectError(error.ProgramContractViolation, Program.run(&runtime, .{ .authored = .{} }));
}

test "ability.program preserves declared handler errors" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const RejectingHandlers = struct {
        authored: struct {
            pub fn dispatch(_: *const @This()) !i32 {
                return error.HandlerRejected;
            }

            pub fn afterDispatch(_: *const @This(), value: i32) !i32 {
                return value;
            }
        },
    };
    const ErrorBody = struct {
        pub const Error = error{HandlerRejected};
        pub const compiled_plan = compiledTransformPlan("declared-handler-error");
    };
    const Program = ability.program("declared-handler-error", RejectingHandlers, ErrorBody);
    try std.testing.expectError(error.HandlerRejected, Program.run(&runtime, .{ .authored = .{} }));
}

test "ability.ir rejects entry plans that mix normal value and terminal result codecs" {
    try std.testing.expectError(
        error.InvalidFunctionResultCodec,
        entryMixedNormalAndTerminalResultCodecPlan("entry-mixed-normal-terminal-result-codec"),
    );
}

test "ability.ir rejects entry plans with normal value completion and distinct result codec" {
    try std.testing.expectError(
        error.InvalidFunctionResultCodec,
        entryNormalValueWithDistinctResultCodecPlan("entry-normal-value-distinct-result-codec"),
    );
}

test "ability.ir can describe structured op payload metadata outside the executable subset" {
    const plan = unsupportedStructuredPayloadPlan("unsupported-structured-payload");
    try std.testing.expectEqual(ability.ir.ValueCodec.product, plan.ops[0].payload_codec);
    try std.testing.expectEqual(@as(?u16, 0), plan.ops[0].payload_schema_index);
}

test "ability.program rejects i32 arithmetic overflow without trapping" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const OverflowHandlers = struct {
        source: struct {
            pub fn dispatch(_: *const @This()) !i32 {
                return std.math.maxInt(i32);
            }
        },
    };
    const AddConstOverflowBody = struct {
        pub const compiled_plan = overflowArithmeticPlan("add-const-overflow", false);
    };
    const AddConstOverflowProgram = ability.program("add-const-overflow", OverflowHandlers, AddConstOverflowBody);
    try std.testing.expectError(error.ProgramContractViolation, AddConstOverflowProgram.run(&runtime, .{ .source = .{} }));

    const AddOverflowBody = struct {
        pub const compiled_plan = overflowArithmeticPlan("add-overflow", true);
    };
    const AddOverflowProgram = ability.program("add-overflow", OverflowHandlers, AddOverflowBody);
    try std.testing.expectError(error.ProgramContractViolation, AddOverflowProgram.run(&runtime, .{ .source = .{} }));
}

test "ability.program rejects i32 sub_one underflow without trapping" {
    var runtime = ability.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    const UnderflowHandlers = struct {
        source: struct {
            pub fn dispatch(_: *const @This()) !i32 {
                return std.math.minInt(i32);
            }
        },
    };
    const SubOneOverflowBody = struct {
        pub const compiled_plan = subOneOverflowPlan("sub-one-overflow");
    };
    const SubOneOverflowProgram = ability.program("sub-one-overflow", UnderflowHandlers, SubOneOverflowBody);
    try std.testing.expectError(error.ProgramContractViolation, SubOneOverflowProgram.run(&runtime, .{ .source = .{} }));
}

test "ability.ir builder validates supported scalar GAE matrix" {
    const payload_codecs = .{ ability.ir.ValueCodec.unit, ability.ir.ValueCodec.string };
    const resume_codecs = .{ ability.ir.ValueCodec.unit, ability.ir.ValueCodec.i32 };
    comptime {
        @setEvalBranchQuota(20_000);
        for (payload_codecs) |payload_codec| {
            for (resume_codecs) |resume_codec| {
                _ = matrixPlan(.transform, payload_codec, resume_codec);
                _ = matrixPlan(.choice, payload_codec, resume_codec);
            }
            _ = matrixPlan(.abort, payload_codec, .unit);
        }
    }
}
