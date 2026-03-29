const example_open_row_state_writer = @import("example_open_row_state_writer");
const shift = @import("shift");
const std = @import("std");

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

test "open-row state-writer example stays transcript-backed" {
    var writer_buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&writer_buffer);
    try example_open_row_state_writer.run(&writer);
    try std.testing.expectEqualStrings(
        "item=query=artifact-search\nitem=workflow=queued\nfinal_state=6\nvalue=done\n",
        writer.buffered(),
    );
}
