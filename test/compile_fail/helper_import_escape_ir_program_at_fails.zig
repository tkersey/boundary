const shift_compile = @import("shift_compile");

comptime {
    _ = shift_compile.lowering.irProgramAt("test/compile_fail_inputs/helper_import_escape_source.zig", .{
        .label = "compile_fail.helper_import_escape_ir_program_at",
        .entry_symbol = "runBody",
        .row = shift_compile.ir.rowFromSpec(.{
            .writer = .{
                .tell = shift_compile.ir.Transform([]const u8, void),
            },
        }),
        .outputs = &.{
            .{ .label = "writer", .OutputType = [][]const u8 },
        },
    });
}
