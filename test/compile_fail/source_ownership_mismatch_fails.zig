const shift = @import("shift");

fn callerFile() []const u8 {
    return @src().file;
}

comptime {
    _ = shift.lower(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = callerFile(),
    }, .{
        .label = "compile_fail.source_ownership",
        .entry_symbol = "runBody",
        .row = shift.ir.rowFromSpec(.{
            .state = .{
                .get = shift.ir.Transform(void, i32),
                .set = shift.ir.Transform(i32, void),
            },
            .writer = .{
                .tell = shift.ir.Transform([]const u8, void),
            },
        }),
        .outputs = &.{
            .{ .label = "state", .OutputType = i32 },
            .{ .label = "writer", .OutputType = [][]const u8 },
        },
    });
}
