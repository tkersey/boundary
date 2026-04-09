const shift_compile = @import("shift_compile");

fn loweringSpec() shift_compile.lowering.LowerSpec {
    return .{
        .label = "compile_fail.entry_path_escape_lower_at",
        .entry_symbol = "runBody",
        .row = shift_compile.ir.mergeRows(.{
            shift_compile.ir.rowFromSpec(.{
                .state = .{
                    .get = shift_compile.ir.Transform(void, i32),
                    .set = shift_compile.ir.Transform(i32, void),
                },
            }),
            shift_compile.ir.rowFromSpec(.{
                .writer = .{
                    .tell = shift_compile.ir.Transform([]const u8, void),
                },
            }),
        }),
        .ValueType = []const u8,
        .outputs = &.{
            .{ .label = "state", .OutputType = i32 },
            .{ .label = "writer", .OutputType = [][]const u8 },
        },
    };
}

comptime {
    _ = shift_compile.lowering.lowerAt("../shift/examples/open_row_state_writer.zig", loweringSpec());
}
