const shift_compile = @import("shift_compile");
const std = @import("std");

fn explicitCaller() std.builtin.SourceLocation {
    const src = @src();
    return .{
        .module = src.module,
        .file = "open_row_state_writer.zig",
        .line = src.line,
        .column = src.column,
        .fn_name = src.fn_name,
    };
}

comptime {
    _ = shift_compile.lower(
        shift_compile.lowering.source("examples/open_row_state_writer.zig", explicitCaller()),
        .{
            .label = "compile_fail.source_ownership_relative_no_content",
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
        },
    );
}
