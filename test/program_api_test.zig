// zlinter-disable declaration_naming no_inferred_error_unions no_swallow_error require_doc_comment
const ability = @import("ability");
const std = @import("std");

const CountingAllocator = struct {
    child: std.mem.Allocator,
    alloc_calls: usize = 0,
    resize_calls: usize = 0,
    remap_calls: usize = 0,
    free_calls: usize = 0,

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
        return self.child.rawRemap(memory, alignment, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        self.free_calls += 1;
        self.child.rawFree(memory, alignment, ret_addr);
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
