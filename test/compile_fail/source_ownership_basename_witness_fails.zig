const shift_compile = @import("shift_compile");
const std = @import("std");

comptime {
    const source_text =
        \\pub fn runBody(eff: anytype) ![]const u8 {
        \\    _ = eff;
        \\    return "spoofed";
        \\}
    ;

    _ = shift_compile.lower(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = "open_row_state_writer.zig",
        .caller_hash = std.hash.Wyhash.hash(0, source_text),
        .caller_source = source_text,
    }, .{
        .label = "compile_fail.source_ownership_basename_witness",
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
