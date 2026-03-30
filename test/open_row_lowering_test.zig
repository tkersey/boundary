const example_open_row_branching_helper_body = @import("example_open_row_branching_helper_body");
const example_open_row_cross_file_writer = @import("example_open_row_cross_file_writer");
const example_open_row_helper_value_flow = @import("example_open_row_helper_value_flow");
const example_open_row_helper_value_flow_cross = @import("example_open_row_helper_value_flow_cross");
const example_open_row_linear_helper_body = @import("example_open_row_linear_helper_body");
const example_open_row_recursive_cross_writer = @import("example_open_row_recursive_cross_writer");
const example_open_row_recursive_writer = @import("example_open_row_recursive_writer");
const example_open_row_state_writer = @import("example_open_row_state_writer");
const shift = @import("shift");
const std = @import("std");

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
    try std.testing.expectEqual(@as(@TypeOf(helper_body.blocks[0].instructions[0].kind), .call_op), helper_body.blocks[0].instructions[0].kind);
    try std.testing.expectEqual(@as(@TypeOf(helper_body.blocks[0].instructions[1].kind), .compare_eq_zero), helper_body.blocks[0].instructions[1].kind);
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

test "open-row state-writer example stays transcript-backed" {
    var writer_buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buffer);
    try example_open_row_state_writer.run(&writer);
    try std.testing.expectEqualStrings(
        "item=query=artifact-search\nitem=workflow=queued\nfinal_state=6\nvalue=done\n",
        writer.buffered(),
    );
}
