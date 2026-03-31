const shift = @import("shift");

fn loweringSpec() shift.lowering.LowerSpec {
    return .{
        .label = "compile_fail.entry_path_escape_lower_at",
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
}

comptime {
    _ = shift.lowerAt("../shift/examples/open_row_state_writer.zig", loweringSpec());
}
