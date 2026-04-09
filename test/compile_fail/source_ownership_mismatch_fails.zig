const shift_compile = @import("shift_compile");

fn callerFile() []const u8 {
    return @src().file;
}

comptime {
    _ = shift_compile.lower(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = callerFile(),
    }, .{
        .label = "compile_fail.source_ownership",
        .entry_symbol = "runBody",
        .row = shift_compile.ir.rowFromSpec(.{
            .state = .{
                .get = shift_compile.ir.Transform(void, i32),
                .set = shift_compile.ir.Transform(i32, void),
            },
            .writer = .{
                .tell = shift_compile.ir.Transform([]const u8, void),
            },
        }),
        .outputs = &.{
            .{ .label = "state", .OutputType = i32 },
            .{ .label = "writer", .OutputType = [][]const u8 },
        },
    });
}
