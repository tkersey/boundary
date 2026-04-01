const authoring_build_options = @import("authoring_build_options");
const shift = @import("shift");

comptime {
    _ = shift.lowerAt(authoring_build_options.external_open_row_state_writer_alias_path, .{
        .label = "compile_fail.absolute_entry_alias_lower_at",
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
    });
}
