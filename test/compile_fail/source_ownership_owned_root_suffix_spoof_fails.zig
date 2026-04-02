const authoring_build_options = @import("authoring_build_options");
const shift = @import("shift");
const std = @import("std");

comptime {
    const spoofed_path = std.fmt.comptimePrint(
        "{s}/vendor/mirror/examples/open_row_state_writer.zig",
        .{authoring_build_options.package_root},
    );
    _ = shift.lower(.{
        .repo_path = "examples/open_row_state_writer.zig",
        .caller_file = spoofed_path,
    }, .{
        .label = "compile_fail.source_ownership_owned_root_suffix_spoof",
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
