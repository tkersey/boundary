const authoring_build_options = @import("authoring_build_options");
const example_open_row_branching_helper_body = @import("example_open_row_branching_helper_body");
const example_open_row_cross_file_writer = @import("example_open_row_cross_file_writer");
const example_open_row_escaped_string_helper_body = @import("example_open_row_escaped_string_helper_body");
const example_open_row_helper_bool_flow = @import("example_open_row_helper_bool_flow");
const example_open_row_helper_value_flow = @import("example_open_row_helper_value_flow");
const example_open_row_helper_value_flow_cross = @import("example_open_row_helper_value_flow_cross");
const example_open_row_linear_helper_body = @import("example_open_row_linear_helper_body");
const example_open_row_recursive_cross_writer = @import("example_open_row_recursive_cross_writer");
const example_open_row_recursive_writer = @import("example_open_row_recursive_writer");
const example_open_row_state_writer = @import("example_open_row_state_writer");
const shift = @import("shift");
const std = @import("std");

fn symlinkAliasPath(
    allocator: std.mem.Allocator,
    tmp: *std.testing.TmpDir,
    target_path: []const u8,
    alias_name: []const u8,
) ![]u8 {
    try tmp.dir.symLink(target_path, alias_name, .{});
    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    return try std.fmt.allocPrint(allocator, "{s}{c}{s}", .{ tmp_path, std.fs.path.sep, alias_name });
}

const LoweredStateHandler = struct {
    value: i32,

    /// Return the current state value through the lowered runner harness.
    pub fn get(self: *@This()) anyerror!i32 {
        return self.value;
    }

    /// Update the current state value through the lowered runner harness.
    pub fn set(self: *@This(), value: i32) anyerror!void {
        self.value = value;
    }

    /// Finish state collection for one lowered runner execution.
    pub fn finish(self: *@This()) i32 {
        return self.value;
    }
};

const LoweredWriterHandler = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList([]const u8) = .empty,

    /// Record one writer payload for the lowered runner harness.
    pub fn tell(self: *@This(), value: []const u8) anyerror!void {
        try self.items.append(self.allocator, value);
    }

    /// Finish writer collection for one lowered runner execution.
    pub fn finish(self: *@This()) anyerror![][]const u8 {
        return try self.items.toOwnedSlice(self.allocator);
    }

    /// Release any retained writer items after one lowered runner execution.
    pub fn deinit(self: *@This()) void {
        self.items.deinit(self.allocator);
    }
};

const LoweredStateWriterHandlers = struct {
    state: LoweredStateHandler,
    writer: LoweredWriterHandler,
};

const LoweredWriterOnlyHandlers = struct {
    writer: LoweredWriterHandler,
};

const LoweredApprovalHandler = struct {
    allowed: bool,

    /// Return the preconfigured approval bit for the lowered test handler.
    pub fn ask(self: *@This()) anyerror!bool {
        return self.allowed;
    }
};

const LoweredApprovalHandlers = struct {
    approval: LoweredApprovalHandler,
};

test "open-row state-writer workflow lowers through the public same-module path" {
    const lowered = try example_open_row_state_writer.loweredProgram();

    try std.testing.expectEqualStrings("example.open_row_state_writer", lowered.label);
    try std.testing.expectEqual(@as(usize, 3), lowered.program.functions.len);
    try std.testing.expectEqual(@as(usize, 2), lowered.program.call_edges.len);
    try std.testing.expectEqualStrings("runBody", lowered.program.functions[lowered.program.entry_index].symbol.symbol_name);
    try std.testing.expect(std.mem.endsWith(u8, lowered.program.functions[lowered.program.entry_index].symbol.module_path, "open_row_state_writer.zig"));
    try std.testing.expectEqual(@as(usize, 2), lowered.normalization.requirement_count);
    try std.testing.expectEqual(@as(usize, 3), lowered.normalization.op_count);
    try std.testing.expectEqual(@as(usize, 2), lowered.normalization.output_count);
}

test "public lowered runner executes same-file lowered program through runtime_plan" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var handlers: LoweredStateWriterHandlers = .{
        .state = LoweredStateHandler{ .value = 5 },
        .writer = LoweredWriterHandler{ .allocator = std.testing.allocator },
    };
    defer handlers.writer.deinit();

    const result = try example_open_row_state_writer.CompiledProgram.run(&runtime, &handlers);
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(i32, 6), result.outputs.state);
    try std.testing.expectEqual(@as(usize, 2), result.outputs.writer.len);
    try std.testing.expectEqualStrings("query=artifact-search", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("workflow=queued", result.outputs.writer[1]);
    try std.testing.expectEqualStrings("done", result.value);
}

test "public lowered runner executes recursive same-file lowered program" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var handlers: LoweredStateWriterHandlers = .{
        .state = LoweredStateHandler{ .value = 3 },
        .writer = LoweredWriterHandler{ .allocator = std.testing.allocator },
    };
    defer handlers.writer.deinit();

    const result = try example_open_row_recursive_writer.CompiledProgram.run(&runtime, &handlers);
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(i32, 0), result.outputs.state);
    try std.testing.expectEqual(@as(usize, 3), result.outputs.writer.len);
    try std.testing.expectEqualStrings("tick", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("tick", result.outputs.writer[1]);
    try std.testing.expectEqualStrings("tick", result.outputs.writer[2]);
    try std.testing.expectEqualStrings("done", result.value);
}

test "public lowered runner executes cross-file lowered program" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var handlers: LoweredStateWriterHandlers = .{
        .state = LoweredStateHandler{ .value = 5 },
        .writer = LoweredWriterHandler{ .allocator = std.testing.allocator },
    };
    defer handlers.writer.deinit();

    const result = try example_open_row_cross_file_writer.CompiledProgram.run(&runtime, &handlers);
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(i32, 7), result.outputs.state);
    try std.testing.expectEqual(@as(usize, 2), result.outputs.writer.len);
    try std.testing.expectEqualStrings("query=cross-file-artifact-search", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("workflow=cross-file-queued", result.outputs.writer[1]);
    try std.testing.expectEqualStrings("done", result.value);
}

test "straight-line helper bodies lower real source-owned call_op and call_helper instructions" {
    const lowered = try example_open_row_linear_helper_body.loweredProgram();

    const helper_index = comptime blk: {
        for (lowered.program.functions, 0..) |function, function_index| {
            if (std.mem.eql(u8, function.symbol.symbol_name, "helper")) break :blk function_index;
        }
        unreachable;
    };
    const leaf_index = comptime blk: {
        for (lowered.program.functions, 0..) |function, function_index| {
            if (std.mem.eql(u8, function.symbol.symbol_name, "leaf")) break :blk function_index;
        }
        unreachable;
    };

    const helper_body = lowered.program.function_bodies[helper_index];
    const leaf_body = lowered.program.function_bodies[leaf_index];

    try std.testing.expectEqual(@as(usize, 3), helper_body.blocks[0].instructions.len);
    try std.testing.expectEqual(@as(@TypeOf(helper_body.blocks[0].terminator.kind), .return_unit), helper_body.blocks[0].terminator.kind);
    try std.testing.expectEqual(@as(@TypeOf(helper_body.blocks[0].instructions[0].kind), .const_string), helper_body.blocks[0].instructions[0].kind);
    try std.testing.expectEqual(@as(@TypeOf(helper_body.blocks[0].instructions[1].kind), .call_op), helper_body.blocks[0].instructions[1].kind);
    try std.testing.expectEqual(@as(@TypeOf(helper_body.blocks[0].instructions[2].kind), .call_helper), helper_body.blocks[0].instructions[2].kind);
    try std.testing.expectEqual(@as(u16, @intCast(leaf_index)), helper_body.blocks[0].instructions[2].operand);

    try std.testing.expectEqual(@as(usize, 2), leaf_body.blocks[0].instructions.len);
    try std.testing.expectEqual(@as(@TypeOf(leaf_body.blocks[0].instructions[0].kind), .const_string), leaf_body.blocks[0].instructions[0].kind);
    try std.testing.expectEqual(@as(@TypeOf(leaf_body.blocks[0].instructions[1].kind), .call_op), leaf_body.blocks[0].instructions[1].kind);
    try std.testing.expectEqual(@as(@TypeOf(leaf_body.blocks[0].terminator.kind), .return_unit), leaf_body.blocks[0].terminator.kind);
}

test "escaped helper string literals decode before const_string emission" {
    const lowered = try example_open_row_escaped_string_helper_body.loweredProgram();

    const helper_index = comptime blk: {
        for (lowered.program.functions, 0..) |function, function_index| {
            if (std.mem.eql(u8, function.symbol.symbol_name, "helper")) break :blk function_index;
        }
        unreachable;
    };

    const helper_body = lowered.program.function_bodies[helper_index];
    try std.testing.expectEqual(@as(usize, 4), helper_body.blocks[0].instructions.len);
    try std.testing.expectEqualStrings("line\n", helper_body.blocks[0].instructions[0].string_literal);
    try std.testing.expectEqualStrings("\"", helper_body.blocks[0].instructions[2].string_literal);
}

test "public lowered runner preserves escaped helper string literal semantics" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var handlers: LoweredStateWriterHandlers = .{
        .state = LoweredStateHandler{ .value = 0 },
        .writer = LoweredWriterHandler{ .allocator = std.testing.allocator },
    };
    defer handlers.writer.deinit();

    const result = try example_open_row_escaped_string_helper_body.CompiledProgram.run(&runtime, &handlers);
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(usize, 2), result.outputs.writer.len);
    try std.testing.expectEqualStrings("line\n", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("\"", result.outputs.writer[1]);
    try std.testing.expectEqualStrings("done", result.value);
}

test "branching helper body lowers a real if-else control-flow body" {
    const lowered = try example_open_row_branching_helper_body.loweredProgram();

    const helper_index = comptime blk: {
        for (lowered.program.functions, 0..) |function, function_index| {
            if (std.mem.eql(u8, function.symbol.symbol_name, "choose")) break :blk function_index;
        }
        unreachable;
    };

    const helper_body = lowered.program.function_bodies[helper_index];
    try std.testing.expectEqual(@as(usize, 3), helper_body.blocks.len);
    try std.testing.expectEqual(@as(@TypeOf(helper_body.blocks[0].terminator.kind), .branch_if), helper_body.blocks[0].terminator.kind);
    try std.testing.expectEqual(@as(@TypeOf(helper_body.blocks[1].instructions[0].kind), .const_string), helper_body.blocks[1].instructions[0].kind);
    try std.testing.expectEqual(@as(@TypeOf(helper_body.blocks[1].instructions[1].kind), .call_op), helper_body.blocks[1].instructions[1].kind);
    try std.testing.expectEqual(@as(@TypeOf(helper_body.blocks[2].instructions[0].kind), .const_string), helper_body.blocks[2].instructions[0].kind);
    try std.testing.expectEqual(@as(@TypeOf(helper_body.blocks[2].instructions[1].kind), .call_op), helper_body.blocks[2].instructions[1].kind);
}

test "public lowered runner executes both branches of the branching helper body" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var zero_handlers: LoweredStateWriterHandlers = .{
        .state = LoweredStateHandler{ .value = 0 },
        .writer = LoweredWriterHandler{ .allocator = std.testing.allocator },
    };
    defer zero_handlers.writer.deinit();
    const zero_result = try example_open_row_branching_helper_body.CompiledProgram.run(&runtime, &zero_handlers);
    defer std.testing.allocator.free(zero_result.outputs.writer);
    try std.testing.expectEqual(@as(usize, 1), zero_result.outputs.writer.len);
    try std.testing.expectEqualStrings("zero", zero_result.outputs.writer[0]);
    try std.testing.expectEqualStrings("done", zero_result.value);

    var nonzero_handlers: LoweredStateWriterHandlers = .{
        .state = LoweredStateHandler{ .value = 2 },
        .writer = LoweredWriterHandler{ .allocator = std.testing.allocator },
    };
    defer nonzero_handlers.writer.deinit();
    const nonzero_result = try example_open_row_branching_helper_body.CompiledProgram.run(&runtime, &nonzero_handlers);
    defer std.testing.allocator.free(nonzero_result.outputs.writer);
    try std.testing.expectEqual(@as(usize, 1), nonzero_result.outputs.writer.len);
    try std.testing.expectEqualStrings("nonzero", nonzero_result.outputs.writer[0]);
    try std.testing.expectEqualStrings("done", nonzero_result.value);
}

test "helper value-flow lowering exposes a multi-parameter helper ABI and local return" {
    const lowered = try example_open_row_helper_value_flow.loweredProgram();

    const helper_index = comptime blk: {
        for (lowered.program.functions, 0..) |function, function_index| {
            if (std.mem.eql(u8, function.symbol.symbol_name, "classify")) break :blk function_index;
        }
        unreachable;
    };
    const helper_function = lowered.program.functions[helper_index];
    const helper_body = lowered.program.function_bodies[helper_index];
    const entry_body = lowered.program.function_bodies[lowered.program.entry_index];

    try std.testing.expectEqual(@as(usize, 2), helper_function.parameter_codecs.len);
    try std.testing.expectEqual(@as(@TypeOf(helper_function.parameter_codecs[0]), .string), helper_function.parameter_codecs[0]);
    try std.testing.expectEqual(@as(@TypeOf(helper_function.parameter_codecs[1]), .i32), helper_function.parameter_codecs[1]);
    try std.testing.expectEqual(@as(usize, 2), helper_body.local_codecs.len);
    try std.testing.expectEqual(@as(usize, 1), helper_body.blocks[0].instructions.len);
    try std.testing.expectEqual(@as(@TypeOf(helper_body.blocks[0].instructions[0].kind), .return_value), helper_body.blocks[0].instructions[0].kind);
    try std.testing.expectEqual(@as(u16, 0), helper_body.blocks[0].instructions[0].operand);
    try std.testing.expectEqual(@as(usize, 2), entry_body.call_arg_locals.len);
}

test "public lowered runner executes helper value flow through one helper parameter and return" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var handlers: LoweredStateWriterHandlers = .{
        .state = LoweredStateHandler{ .value = 5 },
        .writer = LoweredWriterHandler{ .allocator = std.testing.allocator },
    };
    defer handlers.writer.deinit();

    const result = try example_open_row_helper_value_flow.CompiledProgram.run(&runtime, &handlers);
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(usize, 1), result.outputs.writer.len);
    try std.testing.expectEqualStrings("selected", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("done", result.value);
}

test "cross-file helper value-flow lowering carries the same helper ABI through imported modules" {
    const lowered = try example_open_row_helper_value_flow_cross.loweredProgram();

    const helper_index = comptime blk: {
        for (lowered.program.functions, 0..) |function, function_index| {
            if (std.mem.eql(u8, function.symbol.symbol_name, "classify")) break :blk function_index;
        }
        unreachable;
    };
    const helper_function = lowered.program.functions[helper_index];
    const helper_body = lowered.program.function_bodies[helper_index];
    const entry_body = lowered.program.function_bodies[lowered.program.entry_index];

    try std.testing.expectEqual(@as(usize, 2), helper_function.parameter_codecs.len);
    try std.testing.expectEqual(@as(@TypeOf(helper_function.parameter_codecs[0]), .string), helper_function.parameter_codecs[0]);
    try std.testing.expectEqual(@as(@TypeOf(helper_function.parameter_codecs[1]), .i32), helper_function.parameter_codecs[1]);
    try std.testing.expectEqual(@as(usize, 1), helper_body.blocks[0].instructions.len);
    try std.testing.expectEqual(@as(@TypeOf(helper_body.blocks[0].instructions[0].kind), .return_value), helper_body.blocks[0].instructions[0].kind);
    try std.testing.expectEqual(@as(usize, 2), entry_body.call_arg_locals.len);
}

test "public lowered runner executes cross-file helper value flow through the multi-parameter helper ABI" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var handlers: LoweredStateWriterHandlers = .{
        .state = LoweredStateHandler{ .value = 5 },
        .writer = LoweredWriterHandler{ .allocator = std.testing.allocator },
    };
    defer handlers.writer.deinit();

    const result = try example_open_row_helper_value_flow_cross.CompiledProgram.run(&runtime, &handlers);
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(usize, 1), result.outputs.writer.len);
    try std.testing.expectEqualStrings("cross-selected", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("done", result.value);
}

test "bool helper lowering preserves helper parameter and return codecs" {
    const lowered = try example_open_row_helper_bool_flow.loweredProgram();

    const helper_index = comptime blk: {
        for (lowered.program.functions, 0..) |function, function_index| {
            if (std.mem.eql(u8, function.symbol.symbol_name, "preserve")) break :blk function_index;
        }
        unreachable;
    };
    const helper_function = lowered.program.functions[helper_index];
    const helper_body = lowered.program.function_bodies[helper_index];

    try std.testing.expectEqual(@as(usize, 1), helper_function.parameter_codecs.len);
    try std.testing.expectEqual(@as(@TypeOf(helper_function.parameter_codecs[0]), .bool), helper_function.parameter_codecs[0]);
    try std.testing.expectEqual(bool, helper_function.ValueType);
    try std.testing.expectEqual(@as(usize, 1), helper_body.local_codecs.len);
    try std.testing.expectEqual(@as(@TypeOf(helper_body.local_codecs[0]), .bool), helper_body.local_codecs[0]);
    try std.testing.expectEqual(@as(@TypeOf(helper_body.blocks[0].instructions[0].kind), .return_value), helper_body.blocks[0].instructions[0].kind);
}

test "public lowered runner executes bool helper flow through the helper ABI" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var allowed_handlers: LoweredApprovalHandlers = .{
        .approval = .{ .allowed = true },
    };
    const allowed = try example_open_row_helper_bool_flow.CompiledProgram.run(&runtime, &allowed_handlers);
    try std.testing.expectEqual(true, allowed.value);

    var denied_handlers: LoweredApprovalHandlers = .{
        .approval = .{ .allowed = false },
    };
    const denied = try example_open_row_helper_bool_flow.CompiledProgram.run(&runtime, &denied_handlers);
    try std.testing.expectEqual(false, denied.value);
}

test "open-row state-writer workflow exposes the generated same-module runtime plan" {
    try std.testing.expectEqualStrings("example.open_row_state_writer", example_open_row_state_writer.CompiledProgram.label);
    try std.testing.expect(std.mem.endsWith(u8, example_open_row_state_writer.CompiledProgram.source_path, "open_row_state_writer.zig"));
    try std.testing.expectEqualStrings("runBody", example_open_row_state_writer.CompiledProgram.entry_symbol);
    try std.testing.expectEqual(@as(usize, 3), example_open_row_state_writer.CompiledProgram.runtime_plan.functions.len);
    try std.testing.expectEqual(@as(usize, 5), example_open_row_state_writer.CompiledProgram.runtime_plan.requirements.len);
    try std.testing.expectEqual(@as(usize, 7), example_open_row_state_writer.CompiledProgram.runtime_plan.ops.len);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try example_open_row_state_writer.CompiledProgram.validate(arena.allocator());
}

test "generated cross-file lowered programs validate through imported helper modules" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try example_open_row_cross_file_writer.CompiledProgram.validate(arena.allocator());
    try example_open_row_helper_value_flow_cross.CompiledProgram.validate(arena.allocator());
}

test "generated lowered programs validate repo-relative source paths from outside the repo root" {
    const original_cwd = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(original_cwd);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const external_cwd = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(external_cwd);

    try std.posix.chdir(external_cwd);
    defer std.posix.chdir(original_cwd) catch unreachable;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try example_open_row_state_writer.CompiledProgram.validate(arena.allocator());
}

test "explicit ir compilation matches the generated runtime plan shape" {
    const ExplicitIrProgramType = shift.ir.compile(
        "example.open_row_state_writer",
        example_open_row_state_writer.irProgram(),
    );

    try std.testing.expectEqual(example_open_row_state_writer.CompiledProgram.ir_hash, ExplicitIrProgramType.ir_hash);
    try std.testing.expectEqual(@as(usize, 3), ExplicitIrProgramType.runtime_plan.functions.len);
    try std.testing.expectEqual(@as(usize, 5), ExplicitIrProgramType.runtime_plan.requirements.len);
    try std.testing.expectEqual(@as(usize, 7), ExplicitIrProgramType.runtime_plan.ops.len);
}

test "explicit ir compilation respects an explicit non-zero entry index" {
    const row = shift.ir.rowFromSpec(.{
        .writer = .{
            .tell = shift.ir.Transform([]const u8, void),
        },
    });
    const helper_symbol: shift.ir.SymbolRef = .{
        .module_path = "examples/hand_authored.zig",
        .symbol_name = "helper",
    };
    const root_symbol: shift.ir.SymbolRef = .{
        .module_path = "examples/hand_authored.zig",
        .symbol_name = "root",
    };
    const HandAuthoredProgram: shift.ir.Program = .{
        .entry_index = 1,
        .functions = &.{
            .{
                .symbol = helper_symbol,
                .row = row,
                .ValueType = void,
            },
            .{
                .symbol = root_symbol,
                .row = row,
                .ValueType = []const u8,
                .outputs = &.{.{ .label = "writer", .OutputType = [][]const u8 }},
            },
        },
        .call_edges = &.{.{
            .caller = root_symbol,
            .callee = helper_symbol,
        }},
        .function_bodies = &.{
            .{
                .local_codecs = &.{.string},
                .entry_block = 0,
                .blocks = &.{.{
                    .instructions = &.{.{
                        .kind = .call_op,
                        .dst = 0,
                        .operand = 0,
                    }},
                    .terminator = .{ .kind = .return_unit },
                }},
            },
            .{
                .local_codecs = &.{.string},
                .entry_block = 0,
                .blocks = &.{.{
                    .instructions = &.{
                        .{
                            .kind = .call_helper,
                            .dst = 0,
                            .operand = 0,
                            .aux = std.math.maxInt(u16),
                        },
                        .{
                            .kind = .const_string,
                            .dst = 0,
                            .string_literal = "done",
                        },
                        .{
                            .kind = .return_value,
                            .operand = 0,
                        },
                    },
                    .terminator = .{ .kind = .return_value },
                }},
            },
        },
    };

    const ProgramType = shift.ir.compile("example.hand_authored_ir", HandAuthoredProgram);

    try std.testing.expectEqualStrings("root", ProgramType.entry_symbol);
    try std.testing.expectEqual(@as(u16, 1), ProgramType.runtime_plan.entry_index);
}

test "root lowerAt matches the example-owned same-module lowering" {
    const ExplicitProgramType = shift.lowerAt(
        example_open_row_state_writer.loweringSourcePath(),
        example_open_row_state_writer.loweringSpec(),
    );

    try std.testing.expectEqualStrings(
        example_open_row_state_writer.CompiledProgram.source_path,
        ExplicitProgramType.source_path,
    );
    try std.testing.expectEqual(example_open_row_state_writer.CompiledProgram.ir_hash, ExplicitProgramType.ir_hash);
    try std.testing.expectEqual(
        @as(usize, example_open_row_state_writer.CompiledProgram.runtime_plan.functions.len),
        ExplicitProgramType.runtime_plan.functions.len,
    );
}

test "root lower matches the example-owned same-module lowering" {
    const ExplicitProgramType = shift.lower(
        example_open_row_state_writer.loweringSource(),
        example_open_row_state_writer.loweringSpec(),
    );

    try std.testing.expectEqualStrings(
        example_open_row_state_writer.CompiledProgram.source_path,
        ExplicitProgramType.source_path,
    );
    try std.testing.expectEqual(example_open_row_state_writer.CompiledProgram.ir_hash, ExplicitProgramType.ir_hash);
    try std.testing.expectEqual(
        @as(usize, example_open_row_state_writer.CompiledProgram.runtime_plan.functions.len),
        ExplicitProgramType.runtime_plan.functions.len,
    );
}

test "sourceWithContent normalizes basename-only caller files to the explicit repo path" {
    const source_ref = example_open_row_state_writer.loweringSource();

    try std.testing.expectEqualStrings(example_open_row_state_writer.loweringSourcePath(), source_ref.caller_file);
}

test "explicit IR compilation preserves non-zero helper-body entry blocks in the runtime plan" {
    const entry_symbol: shift.ir.SymbolRef = .{
        .module_path = "test/open_row_lowering_test.zig",
        .symbol_name = "entryBlockRoot",
    };
    const HandAuthoredProgram: shift.ir.Program = .{
        .entry_index = 0,
        .functions = &.{.{
            .symbol = entry_symbol,
            .row = shift.ir.rowFromSpec(.{}),
            .ValueType = i32,
        }},
        .call_edges = &.{},
        .function_bodies = &.{.{
            .local_codecs = &.{.i32},
            .entry_block = 1,
            .blocks = &.{
                .{
                    .instructions = &.{
                        .{ .kind = .const_i32, .dst = 0, .operand = 1 },
                        .{ .kind = .return_value, .operand = 0 },
                    },
                    .terminator = .{ .kind = .return_value },
                },
                .{
                    .instructions = &.{
                        .{ .kind = .const_i32, .dst = 0, .operand = 2 },
                        .{ .kind = .return_value, .operand = 0 },
                    },
                    .terminator = .{ .kind = .return_value },
                },
            },
        }},
    };

    const ExplicitProgramType = shift.ir.compile("example.entry_block_root", HandAuthoredProgram);
    try std.testing.expectEqual(@as(u16, 1), ExplicitProgramType.runtime_plan.functions[0].entry_block);
    try std.testing.expectEqual(@as(u16, 0), ExplicitProgramType.runtime_plan.functions[0].first_block);
}

test "example module proves why root shift.lower requires explicit caller participation" {
    try std.testing.expectEqualStrings("open_row_state_writer.zig", example_open_row_state_writer.callerSourceFile());
    try std.testing.expect(!std.mem.eql(
        u8,
        example_open_row_state_writer.callerSourceFile(),
        example_open_row_state_writer.loweringSourcePath(),
    ));
}

test "same-module validation accepts helper graphs for explicit-path lowering" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "helper_case.zig",
        .data =
        \\fn helper() void {}
        \\pub fn runBody() void {
        \\    helper();
        \\}
        ,
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, "helper_case.zig");
    defer std.testing.allocator.free(tmp_path);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try shift.lowering.validateFileBackedOpenRowAt(arena.allocator(), tmp_path, "runBody");
}

test "same-module validation accepts alias-based effect access for explicit-path lowering" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "alias_effect_access.zig",
        .data =
        \\fn helper(eff: anytype) !void {
        \\    const writer = eff.writer;
        \\    try writer.tell("queued");
        \\}
        \\pub fn runBody(eff: anytype) !void {
        \\    const e = eff;
        \\    const state = e.state;
        \\    _ = try state.get();
        \\    try helper(eff);
        \\}
        ,
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, "alias_effect_access.zig");
    defer std.testing.allocator.free(tmp_path);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try shift.lowering.validateFileBackedOpenRowAt(arena.allocator(), tmp_path, "runBody");
}

test "same-module validation rejects unsupported effect access for explicit-path lowering" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "unsupported_effect_access.zig",
        .data =
        \\fn consume(_: anytype) void {}
        \\pub fn runBody(eff: anytype) void {
        \\    consume(eff.state);
        \\}
        ,
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, "unsupported_effect_access.zig");
    defer std.testing.allocator.free(tmp_path);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(
        error.UnsupportedEffectAccess,
        shift.lowering.validateFileBackedOpenRowAt(arena.allocator(), tmp_path, "runBody"),
    );
}

test "same-module validation accepts recursive helper graphs for explicit-path lowering" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "recursive_helpers.zig",
        .data =
        \\fn helper() void {
        \\    runBody();
        \\}
        \\pub fn runBody() void {
        \\    helper();
        \\}
        ,
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, "recursive_helpers.zig");
    defer std.testing.allocator.free(tmp_path);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try shift.lowering.validateFileBackedOpenRowAt(arena.allocator(), tmp_path, "runBody");
}

test "file-backed validation resolves cross-file helper imports for explicit-path lowering" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{
        .sub_path = "helpers.zig",
        .data =
        \\pub fn helper(eff: anytype) !void {
        \\    try eff.writer.tell("cross-file");
        \\}
        ,
    });
    try tmp.dir.writeFile(.{
        .sub_path = "entry.zig",
        .data =
        \\const helpers = @import("helpers.zig");
        \\
        \\pub fn runBody(eff: anytype) !void {
        \\    try helpers.helper(eff);
        \\}
        ,
    });

    const tmp_path = try tmp.dir.realpathAlloc(std.testing.allocator, "entry.zig");
    defer std.testing.allocator.free(tmp_path);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try shift.lowering.validateFileBackedOpenRowAt(arena.allocator(), tmp_path, "runBody");
}

test "file-backed validation resolves cross-file helper imports from checkout aliases" {
    const original_cwd = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(original_cwd);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const checkout_alias = try symlinkAliasPath(std.testing.allocator, &tmp, original_cwd, "shift_repo_alias");
    defer std.testing.allocator.free(checkout_alias);

    const entry_path = try std.fs.path.join(
        std.testing.allocator,
        &.{ checkout_alias, "examples", "open_row_cross_file_writer.zig" },
    );
    defer std.testing.allocator.free(entry_path);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try shift.lowering.validateFileBackedOpenRowAt(arena.allocator(), entry_path, "runBody");
}

test "file-backed validation rejects helper imports that escape the package root" {
    const entry_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "test/open_row_validation_boundary/entry_escape_import.zig");
    defer std.testing.allocator.free(entry_path);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(
        error.UnsupportedHelperGraph,
        shift.lowering.validateFileBackedOpenRowAt(arena.allocator(), entry_path, "runBody"),
    );
}

test "file-backed validation accepts repo-local relative entry paths from subdirectories" {
    const original_cwd = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(original_cwd);

    try std.posix.chdir("examples");
    defer std.posix.chdir(original_cwd) catch unreachable;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try shift.lowering.validateFileBackedOpenRowAt(arena.allocator(), "open_row_cross_file_writer.zig", "runBody");
}

test "file-backed validation rejects relative entry paths that escape the package root" {
    const original_cwd = try std.fs.cwd().realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(original_cwd);

    const external_root = try std.fmt.allocPrint(
        std.testing.allocator,
        "/tmp/shift-open-row-validation-{d}",
        .{std.time.nanoTimestamp()},
    );
    defer std.testing.allocator.free(external_root);
    std.fs.deleteTreeAbsolute(external_root) catch {};
    try std.fs.makeDirAbsolute(external_root);
    defer std.fs.deleteTreeAbsolute(external_root) catch unreachable;

    var external_dir = try std.fs.openDirAbsolute(external_root, .{});
    defer external_dir.close();
    try external_dir.makeDir("inside");
    try external_dir.writeFile(.{
        .sub_path = "outside.zig",
        .data =
        \\pub fn runBody() void {}
        ,
    });

    const inside_path = try std.fs.path.join(std.testing.allocator, &.{ external_root, "inside" });
    defer std.testing.allocator.free(inside_path);

    try std.posix.chdir(inside_path);
    defer std.posix.chdir(original_cwd) catch unreachable;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(
        error.UnsupportedHelperGraph,
        shift.lowering.validateFileBackedOpenRowAt(arena.allocator(), "../outside.zig", "runBody"),
    );
}

test "recursive same-file workflow lowers through the public root surface" {
    const lowered = try example_open_row_recursive_writer.loweredProgram();

    try std.testing.expectEqualStrings("example.open_row_recursive_writer", lowered.label);
    try std.testing.expectEqual(@as(usize, 2), lowered.program.functions.len);
    try std.testing.expectEqual(@as(usize, 2), lowered.program.call_edges.len);
    try std.testing.expectEqualStrings("runBody", lowered.program.functions[lowered.program.entry_index].symbol.symbol_name);
    try std.testing.expectEqual(@as(usize, 2), lowered.normalization.requirement_count);
    try std.testing.expectEqual(@as(usize, 3), lowered.normalization.op_count);
    try std.testing.expectEqual(@as(usize, 2), lowered.normalization.output_count);
}

test "recursive same-file helper lowers into a real guarded control-flow body" {
    const lowered = try example_open_row_recursive_writer.loweredProgram();

    const countdown_index = comptime blk: {
        for (lowered.program.functions, 0..) |function, function_index| {
            if (std.mem.eql(u8, function.symbol.symbol_name, "countdown")) break :blk function_index;
        }
        unreachable;
    };
    const countdown_body = lowered.program.function_bodies[countdown_index];

    try std.testing.expectEqual(@as(usize, 4), countdown_body.local_codecs.len);
    try std.testing.expectEqual(@as(usize, 3), countdown_body.blocks.len);
    try std.testing.expectEqual(@as(@TypeOf(countdown_body.blocks[0].instructions[0].kind), .call_op), countdown_body.blocks[0].instructions[0].kind);
    try std.testing.expectEqual(@as(@TypeOf(countdown_body.blocks[0].instructions[1].kind), .compare_eq_zero), countdown_body.blocks[0].instructions[1].kind);
    try std.testing.expectEqual(@as(@TypeOf(countdown_body.blocks[0].terminator.kind), .branch_if), countdown_body.blocks[0].terminator.kind);
}

test "recursive same-file helper runtime plan preserves full instruction operands" {
    const runtime_plan = example_open_row_recursive_writer.CompiledProgram.runtime_plan;
    const countdown_index = comptime blk: {
        for (runtime_plan.functions, 0..) |function, function_index| {
            if (std.mem.eql(u8, function.symbol_name, "countdown")) break :blk function_index;
        }
        unreachable;
    };
    const countdown = runtime_plan.functions[countdown_index];

    try std.testing.expectEqual(@as(u32, 4), runtime_plan.schema_version);
    try std.testing.expectEqual(@as(u16, 4), countdown.local_count);
    try std.testing.expectEqual(@as(u16, 3), countdown.block_count);
    try std.testing.expectEqual(@as(u16, 7), countdown.instruction_count);
    try std.testing.expectEqual(@as(@TypeOf(runtime_plan.instructions[countdown.first_instruction].kind), .call_op), runtime_plan.instructions[countdown.first_instruction].kind);
    try std.testing.expectEqual(@as(u16, 0), runtime_plan.instructions[countdown.first_instruction].dst);
    try std.testing.expectEqual(@as(@TypeOf(runtime_plan.instructions[countdown.first_instruction + 1].kind), .compare_eq_zero), runtime_plan.instructions[countdown.first_instruction + 1].kind);
    try std.testing.expectEqual(@as(u16, 1), runtime_plan.instructions[countdown.first_instruction + 1].dst);
    try std.testing.expectEqual(@as(u16, 0), runtime_plan.instructions[countdown.first_instruction + 1].operand);
    try std.testing.expectEqual(@as(usize, runtime_plan.instructions.len - countdown.first_instruction), countdown.instruction_count);
}

test "explicit IR compilation matches recursive same-file lowered runtime plan" {
    const ExplicitProgramType = shift.ir.compile(
        "example.open_row_recursive_writer",
        example_open_row_recursive_writer.irProgram(),
    );

    try std.testing.expectEqualDeep(example_open_row_recursive_writer.CompiledProgram.runtime_plan.functions, ExplicitProgramType.runtime_plan.functions);
    try std.testing.expectEqualDeep(example_open_row_recursive_writer.CompiledProgram.runtime_plan.requirements, ExplicitProgramType.runtime_plan.requirements);
    try std.testing.expectEqualDeep(example_open_row_recursive_writer.CompiledProgram.runtime_plan.ops, ExplicitProgramType.runtime_plan.ops);
    try std.testing.expectEqualDeep(example_open_row_recursive_writer.CompiledProgram.runtime_plan.outputs, ExplicitProgramType.runtime_plan.outputs);
    try std.testing.expectEqualDeep(example_open_row_recursive_writer.CompiledProgram.runtime_plan.locals, ExplicitProgramType.runtime_plan.locals);
    try std.testing.expectEqualDeep(example_open_row_recursive_writer.CompiledProgram.runtime_plan.blocks, ExplicitProgramType.runtime_plan.blocks);
    try std.testing.expectEqualDeep(example_open_row_recursive_writer.CompiledProgram.runtime_plan.terminators, ExplicitProgramType.runtime_plan.terminators);
    try std.testing.expectEqualDeep(example_open_row_recursive_writer.CompiledProgram.runtime_plan.instructions, ExplicitProgramType.runtime_plan.instructions);
}

test "hand-authored explicit IR matches recursive same-file lowered runtime plan" {
    const row = shift.ir.mergeRows(.{
        shift.ir.rowFromSpec(.{
            .state = .{
                .get = shift.ir.Transform(void, i32),
                .set = shift.ir.Transform(i32, void),
            },
        }),
        shift.ir.rowFromSpec(.{
            .writer = .{
                .tell = shift.ir.Transform([]const u8, void),
            },
        }),
    });
    const countdown_symbol: shift.ir.SymbolRef = .{
        .module_path = "examples/open_row_recursive_writer.zig",
        .symbol_name = "countdown",
    };
    const run_body_symbol: shift.ir.SymbolRef = .{
        .module_path = "examples/open_row_recursive_writer.zig",
        .symbol_name = "runBody",
    };
    const HandAuthoredProgram: shift.ir.Program = .{
        .entry_index = 0,
        .functions = &.{
            .{
                .symbol = run_body_symbol,
                .row = row,
                .ValueType = []const u8,
                .outputs = &.{
                    .{ .label = "state", .OutputType = i32 },
                    .{ .label = "writer", .OutputType = [][]const u8 },
                },
            },
            .{
                .symbol = countdown_symbol,
                .row = row,
                .ValueType = void,
            },
        },
        .call_edges = &.{
            .{ .caller = run_body_symbol, .callee = countdown_symbol },
            .{ .caller = countdown_symbol, .callee = countdown_symbol },
        },
        .function_bodies = &.{
            .{
                .local_codecs = &.{.string},
                .entry_block = 0,
                .blocks = &.{.{
                    .instructions = &.{
                        .{
                            .kind = .call_helper,
                            .operand = 1,
                            .aux = std.math.maxInt(u16),
                        },
                        .{
                            .kind = .const_string,
                            .dst = 0,
                            .string_literal = "done",
                        },
                        .{
                            .kind = .return_value,
                            .operand = 0,
                        },
                    },
                    .terminator = .{ .kind = .return_value },
                }},
            },
            .{
                .local_codecs = &.{ .i32, .bool, .i32, .string },
                .entry_block = 0,
                .blocks = &.{
                    .{
                        .instructions = &.{
                            .{ .kind = .call_op, .dst = 0, .operand = 3, .aux = std.math.maxInt(u16) },
                            .{ .kind = .compare_eq_zero, .dst = 1, .operand = 0 },
                        },
                        .terminator = .{ .kind = .branch_if, .primary = 1, .secondary = 2 },
                    },
                    .{
                        .instructions = &.{},
                        .terminator = .{ .kind = .return_unit },
                    },
                    .{
                        .instructions = &.{
                            .{ .kind = .const_string, .dst = 3, .string_literal = "tick" },
                            .{ .kind = .call_op, .dst = 0, .operand = 5, .aux = 3 },
                            .{ .kind = .sub_one, .dst = 2, .operand = 0 },
                            .{ .kind = .call_op, .operand = 4, .aux = 2 },
                            .{ .kind = .call_helper, .operand = 1, .aux = std.math.maxInt(u16) },
                        },
                        .terminator = .{ .kind = .return_unit },
                    },
                },
            },
        },
    };

    const ExplicitProgramType = shift.ir.compile("example.open_row_recursive_writer", HandAuthoredProgram);

    try std.testing.expectEqualDeep(example_open_row_recursive_writer.CompiledProgram.runtime_plan.functions, ExplicitProgramType.runtime_plan.functions);
    try std.testing.expectEqualDeep(example_open_row_recursive_writer.CompiledProgram.runtime_plan.requirements, ExplicitProgramType.runtime_plan.requirements);
    try std.testing.expectEqualDeep(example_open_row_recursive_writer.CompiledProgram.runtime_plan.ops, ExplicitProgramType.runtime_plan.ops);
    try std.testing.expectEqualDeep(example_open_row_recursive_writer.CompiledProgram.runtime_plan.outputs, ExplicitProgramType.runtime_plan.outputs);
    try std.testing.expectEqualDeep(example_open_row_recursive_writer.CompiledProgram.runtime_plan.locals, ExplicitProgramType.runtime_plan.locals);
    try std.testing.expectEqualDeep(example_open_row_recursive_writer.CompiledProgram.runtime_plan.blocks, ExplicitProgramType.runtime_plan.blocks);
    try std.testing.expectEqualDeep(example_open_row_recursive_writer.CompiledProgram.runtime_plan.terminators, ExplicitProgramType.runtime_plan.terminators);
    try std.testing.expectEqualDeep(example_open_row_recursive_writer.CompiledProgram.runtime_plan.instructions, ExplicitProgramType.runtime_plan.instructions);
}

test "recursive imported-helper workflow lowers through the public root surface" {
    const lowered = try example_open_row_recursive_cross_writer.loweredProgram();

    try std.testing.expectEqualStrings("example.open_row_recursive_cross_writer", lowered.label);
    try std.testing.expectEqual(@as(usize, 2), lowered.program.functions.len);
    try std.testing.expectEqual(@as(usize, 2), lowered.program.call_edges.len);
    try std.testing.expectEqualStrings("runBody", lowered.program.functions[lowered.program.entry_index].symbol.symbol_name);
    try std.testing.expectEqual(@as(usize, 2), lowered.normalization.requirement_count);
    try std.testing.expectEqual(@as(usize, 3), lowered.normalization.op_count);
    try std.testing.expectEqual(@as(usize, 2), lowered.normalization.output_count);
}

test "recursive imported helper lowers into a real guarded control-flow body" {
    const lowered = try example_open_row_recursive_cross_writer.loweredProgram();

    const countdown_index = comptime blk: {
        for (lowered.program.functions, 0..) |function, function_index| {
            if (std.mem.eql(u8, function.symbol.symbol_name, "countdown")) break :blk function_index;
        }
        unreachable;
    };
    const countdown_body = lowered.program.function_bodies[countdown_index];

    try std.testing.expectEqual(@as(usize, 4), countdown_body.local_codecs.len);
    try std.testing.expectEqual(@as(usize, 3), countdown_body.blocks.len);
    try std.testing.expectEqual(@as(@TypeOf(countdown_body.blocks[0].instructions[0].kind), .call_op), countdown_body.blocks[0].instructions[0].kind);
    try std.testing.expectEqual(@as(@TypeOf(countdown_body.blocks[0].instructions[1].kind), .compare_eq_zero), countdown_body.blocks[0].instructions[1].kind);
    try std.testing.expectEqual(@as(@TypeOf(countdown_body.blocks[0].terminator.kind), .branch_if), countdown_body.blocks[0].terminator.kind);
}

test "recursive imported helper runtime plan preserves full instruction operands" {
    const runtime_plan = example_open_row_recursive_cross_writer.CompiledProgram.runtime_plan;
    const countdown_index = comptime blk: {
        for (runtime_plan.functions, 0..) |function, function_index| {
            if (std.mem.eql(u8, function.symbol_name, "countdown")) break :blk function_index;
        }
        unreachable;
    };
    const countdown = runtime_plan.functions[countdown_index];

    try std.testing.expectEqual(@as(u32, 4), runtime_plan.schema_version);
    try std.testing.expectEqual(@as(u16, 4), countdown.local_count);
    try std.testing.expectEqual(@as(u16, 3), countdown.block_count);
    try std.testing.expectEqual(@as(@TypeOf(runtime_plan.instructions[countdown.first_instruction + 1].kind), .compare_eq_zero), runtime_plan.instructions[countdown.first_instruction + 1].kind);
    try std.testing.expectEqual(@as(u16, 1), runtime_plan.instructions[countdown.first_instruction + 1].dst);
    try std.testing.expectEqual(@as(usize, runtime_plan.instructions.len - countdown.first_instruction), countdown.instruction_count);
}

test "explicit IR compilation matches recursive imported-helper lowered runtime plan" {
    const ExplicitProgramType = shift.ir.compile(
        "example.open_row_recursive_cross_writer",
        example_open_row_recursive_cross_writer.irProgram(),
    );

    try std.testing.expectEqual(example_open_row_recursive_cross_writer.CompiledProgram.ir_hash, ExplicitProgramType.ir_hash);
    try std.testing.expectEqualDeep(example_open_row_recursive_cross_writer.CompiledProgram.runtime_plan.functions, ExplicitProgramType.runtime_plan.functions);
    try std.testing.expectEqualDeep(example_open_row_recursive_cross_writer.CompiledProgram.runtime_plan.requirements, ExplicitProgramType.runtime_plan.requirements);
    try std.testing.expectEqualDeep(example_open_row_recursive_cross_writer.CompiledProgram.runtime_plan.ops, ExplicitProgramType.runtime_plan.ops);
    try std.testing.expectEqualDeep(example_open_row_recursive_cross_writer.CompiledProgram.runtime_plan.outputs, ExplicitProgramType.runtime_plan.outputs);
    try std.testing.expectEqualDeep(example_open_row_recursive_cross_writer.CompiledProgram.runtime_plan.locals, ExplicitProgramType.runtime_plan.locals);
    try std.testing.expectEqualDeep(example_open_row_recursive_cross_writer.CompiledProgram.runtime_plan.blocks, ExplicitProgramType.runtime_plan.blocks);
    try std.testing.expectEqualDeep(example_open_row_recursive_cross_writer.CompiledProgram.runtime_plan.terminators, ExplicitProgramType.runtime_plan.terminators);
    try std.testing.expectEqualDeep(example_open_row_recursive_cross_writer.CompiledProgram.runtime_plan.instructions, ExplicitProgramType.runtime_plan.instructions);
}

test "recursive same-file example stays transcript-backed" {
    var writer_buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buffer);
    try example_open_row_recursive_writer.run(&writer);
    try std.testing.expectEqualStrings(
        "item=tick\nitem=tick\nitem=tick\nfinal_state=0\nvalue=done\n",
        writer.buffered(),
    );
}

test "recursive imported-helper example stays transcript-backed" {
    var writer_buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buffer);
    try example_open_row_recursive_cross_writer.run(&writer);
    try std.testing.expectEqualStrings(
        "item=cross\nitem=cross\nfinal_state=0\nvalue=done\n",
        writer.buffered(),
    );
}

test "public lowered runner executes recursive imported-helper lowered program" {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var handlers: LoweredStateWriterHandlers = .{
        .state = LoweredStateHandler{ .value = 2 },
        .writer = LoweredWriterHandler{ .allocator = std.testing.allocator },
    };
    defer handlers.writer.deinit();

    const result = try shift.lowering.run(&runtime, example_open_row_recursive_cross_writer.CompiledProgram, &handlers);
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(i32, 0), result.outputs.state);
    try std.testing.expectEqual(@as(usize, 2), result.outputs.writer.len);
    try std.testing.expectEqualStrings("cross", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("cross", result.outputs.writer[1]);
    try std.testing.expectEqualStrings("done", result.value);
}

test "explicit-path lowering supports cross-file helper modules" {
    const spec: shift.lowering.LowerSpec = .{
        .label = "example.open_row_cross_file_writer",
        .entry_symbol = "runBody",
        .row = shift.ir.mergeRows(.{
            shift.ir.rowFromSpec(.{
                .state = .{
                    .get = shift.ir.Transform(void, i32),
                    .set = shift.ir.Transform(i32, void),
                },
            }),
            shift.ir.rowFromSpec(.{
                .writer = .{
                    .tell = shift.ir.Transform([]const u8, void),
                },
            }),
        }),
        .ValueType = []const u8,
        .outputs = &.{
            .{ .label = "state", .OutputType = i32 },
            .{ .label = "writer", .OutputType = [][]const u8 },
        },
    };

    const Lowered = shift.lowerAt("examples/open_row_cross_file_writer.zig", spec);
    const Explicit = shift.ir.compile(spec.label, shift.lowering.irProgramAt("examples/open_row_cross_file_writer.zig", spec));

    try std.testing.expectEqualStrings("example.open_row_cross_file_writer", Lowered.label);
    try std.testing.expectEqual(@as(usize, 3), Lowered.runtime_plan.functions.len);
    try std.testing.expectEqual(@as(usize, 5), Lowered.runtime_plan.requirements.len);
    try std.testing.expectEqual(@as(usize, 7), Lowered.runtime_plan.ops.len);
    try std.testing.expectEqual(Lowered.ir_hash, Explicit.ir_hash);
}

test "explicit-path lowering accepts checkout-alias absolute paths" {
    if (!authoring_build_options.package_root_alias_available) return error.SkipZigTest;
    const spec: shift.lowering.LowerSpec = .{
        .label = "example.open_row_cross_file_writer.alias",
        .entry_symbol = "runBody",
        .row = shift.ir.mergeRows(.{
            shift.ir.rowFromSpec(.{
                .state = .{
                    .get = shift.ir.Transform(void, i32),
                    .set = shift.ir.Transform(i32, void),
                },
            }),
            shift.ir.rowFromSpec(.{
                .writer = .{
                    .tell = shift.ir.Transform([]const u8, void),
                },
            }),
        }),
        .ValueType = []const u8,
        .outputs = &.{
            .{ .label = "state", .OutputType = i32 },
            .{ .label = "writer", .OutputType = [][]const u8 },
        },
    };
    const alias_source_path = comptime std.fmt.comptimePrint(
        "{s}/examples/open_row_cross_file_writer.zig",
        .{authoring_build_options.package_root_alias},
    );

    const Lowered = shift.lowerAt(alias_source_path, spec);
    const Canonical = shift.lowerAt("examples/open_row_cross_file_writer.zig", spec);

    try std.testing.expectEqualStrings(alias_source_path, Lowered.source_path);
    try std.testing.expectEqualDeep(Canonical.runtime_plan.functions, Lowered.runtime_plan.functions);
    try std.testing.expectEqualDeep(Canonical.runtime_plan.requirements, Lowered.runtime_plan.requirements);
    try std.testing.expectEqualDeep(Canonical.runtime_plan.ops, Lowered.runtime_plan.ops);
    try std.testing.expectEqualDeep(Canonical.runtime_plan.outputs, Lowered.runtime_plan.outputs);
    try std.testing.expectEqualDeep(Canonical.runtime_plan.locals, Lowered.runtime_plan.locals);
    try std.testing.expectEqualDeep(Canonical.runtime_plan.blocks, Lowered.runtime_plan.blocks);
    try std.testing.expectEqualDeep(Canonical.runtime_plan.terminators, Lowered.runtime_plan.terminators);
    try std.testing.expectEqualDeep(Canonical.runtime_plan.instructions, Lowered.runtime_plan.instructions);
}

test "explicit-path lowering disambiguates imported helpers by alias" {
    const spec: shift.lowering.LowerSpec = .{
        .label = "test.open_row_helper_alias",
        .entry_symbol = "runBody",
        .row = shift.ir.rowFromSpec(.{
            .writer = .{
                .tell = shift.ir.Transform([]const u8, void),
            },
        }),
        .outputs = &.{
            .{ .label = "writer", .OutputType = [][]const u8 },
        },
    };

    const Lowered = shift.lowerAt("test/open_row_helper_alias/entry.zig", spec);

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var handlers = LoweredWriterOnlyHandlers{
        .writer = .{ .allocator = std.testing.allocator },
    };
    defer handlers.writer.deinit();

    const result = try Lowered.run(&runtime, &handlers);
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(usize, 2), result.outputs.writer.len);
    try std.testing.expectEqualStrings("a", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("b", result.outputs.writer[1]);
}

test "explicit-path lowering preserves the entry module when helpers share the entry symbol name" {
    const spec: shift.lowering.LowerSpec = .{
        .label = "test.open_row_entry_symbol_alias",
        .entry_symbol = "runBody",
        .row = shift.ir.rowFromSpec(.{
            .writer = .{
                .tell = shift.ir.Transform([]const u8, void),
            },
        }),
        .outputs = &.{
            .{ .label = "writer", .OutputType = [][]const u8 },
        },
    };

    const lowered = shift.lowerAt("test/open_row_entry_symbol_alias/entry.zig", spec);
    const ir_program = shift.lowering.irProgramAt("test/open_row_entry_symbol_alias/entry.zig", spec);

    try std.testing.expectEqualStrings(
        "test/open_row_entry_symbol_alias/entry.zig",
        ir_program.functions[ir_program.entry_index].symbol.module_path,
    );

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();

    var handlers = LoweredWriterOnlyHandlers{
        .writer = .{ .allocator = std.testing.allocator },
    };
    defer handlers.writer.deinit();

    const result = try lowered.run(&runtime, &handlers);
    defer std.testing.allocator.free(result.outputs.writer);

    try std.testing.expectEqual(@as(usize, 2), result.outputs.writer.len);
    try std.testing.expectEqualStrings("helper", result.outputs.writer[0]);
    try std.testing.expectEqualStrings("entry", result.outputs.writer[1]);
}

test "open-row state-writer example stays transcript-backed" {
    var writer_buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buffer);
    try example_open_row_state_writer.run(&writer);
    try std.testing.expectEqualStrings(
        "item=query=artifact-search\nitem=workflow=queued\nfinal_state=6\nvalue=done\n",
        writer.buffered(),
    );
}
{"id":"lrn-20260401T204604Z-e4d853ac","captured_at":"2026-04-01T20:46:04Z","status":"codify_now","learning":"When shift public lowering accepts caller-owned source bytes for an internal repo path, require the witness to match embedded repo bytes and reject basename-only hashed refs, because self-consistent basename witnesses otherwise bypass ownership checks; also make ProgramPlan.validate reject value-producing helper/op destinations and terminators without their required producer instructions so malformed public helper-body IR fails at compile time.","evidence":["src/public_lowering.zig:382-426 tightened hash-backed ownership admission; zig build test --summary none -> ok","src/internal/program_plan.zig:195-257 validates helper/op dst slots and terminator producers; zig build compile-fail -> ok","zig build lint -- --max-warnings 0 -> ok"],"application":"Use this on public lowering and explicit IR review fixes to fail closed at validation/compile time instead of relying on runtime ProgramContractViolation or silent dropped values.","context":{"repo":"tkersey/shift","branch":"feature/binding-packet-portability","paths":["build.zig","src/durable.zig","src/internal/program_plan.zig","src/public_lowering.zig","test/open_row_lowering_test.zig"]},"source":"codex","fingerprint":"e4d853acbebc6144","tags":["zig","shift","lowering","ownership","validation"]}
