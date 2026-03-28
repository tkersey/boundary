const example_open_row_state_writer = @import("example_open_row_state_writer");
const program_frontend = @import("program_frontend");
const source_lowering = @import("source_lowering");
const std = @import("std");

test "open-row state-writer workflow lowers through the new source-lowering path" {
    const program = program_frontend.open_rows.stateWriterWorkflow();
    const lowered = try source_lowering.lowerOpenRowProgram(program);

    try std.testing.expectEqualStrings("example.open_row_state_writer", lowered.label);
    try std.testing.expectEqual(@as(usize, 1), lowered.program.functions.len);
    try std.testing.expectEqualStrings("run", lowered.program.functions[0].symbol.symbol_name);
    try std.testing.expectEqual(@as(usize, 2), lowered.normalization.requirement_count);
    try std.testing.expectEqual(@as(usize, 3), lowered.normalization.op_count);
    try std.testing.expectEqual(@as(usize, 2), lowered.normalization.output_count);
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
