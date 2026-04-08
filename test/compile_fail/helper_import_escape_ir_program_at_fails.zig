const shift = @import("shift");

comptime {
    _ = shift.lowering.irProgramAt("test/compile_fail_inputs/helper_import_escape_source.zig", .{
        .label = "compile_fail.helper_import_escape_ir_program_at",
        .entry_symbol = "runBody",
        .row = shift.ir.rowFromSpec(.{
            .writer = .{
                .tell = shift.ir.Transform([]const u8, void),
            },
        }),
        .outputs = &.{
            .{ .label = "writer", .OutputType = [][]const u8 },
        },
    });
}
