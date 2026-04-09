const authoring_build_options = @import("authoring_build_options");
const shift_compile = @import("shift_compile");
const std = @import("std");

comptime {
    const spoofed_path = std.fmt.comptimePrint(
        "{s}/vendor/mirror/examples/open_row_state_writer.zig",
        .{authoring_build_options.package_root},
    );
    _ = shift_compile.lower(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = spoofed_path,
    }, .{
        .label = "compile_fail.source_ownership_owned_root_suffix_spoof",
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
