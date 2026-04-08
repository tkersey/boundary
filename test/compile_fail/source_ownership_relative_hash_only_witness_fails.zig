const shift = @import("shift");
const std = @import("std");

comptime {
    _ = shift.lower(.{
        .repo_path = "test/compile_fail/source_ownership_relative_hash_only_witness_fails.zig",
        .caller_file = "test/compile_fail/source_ownership_relative_hash_only_witness_fails.zig",
        .caller_hash = std.hash.Wyhash.hash(
            0,
            @embedFile("source_ownership_relative_hash_only_witness_fails.zig"),
        ),
    }, .{
        .label = "compile_fail.source_ownership_relative_hash_only",
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
