const shift_compile = @import("shift_compile");
const std = @import("std");

const repo_path = "/tmp/source_ref_missing_imported_helper_fails.zig";

const root_source =
    \\const helpers = @import("open_row_helper_value_flow_cross_helpers.zig");
    \\
    \\pub fn runBody(eff: anytype) ![]const u8 {
    \\    return try helpers.classify("caller-owned", 7, eff);
    \\}
;

comptime {
    @setEvalBranchQuota(1_000_000);
    _ = shift_compile.lower(.{
        .repo_path = repo_path,
        .caller_file = repo_path,
        .caller_hash = std.hash.Wyhash.hash(0, root_source),
        .caller_source = root_source,
    }, .{
        .label = "compile_fail.source_ref_missing_imported_helper",
        .entry_symbol = "runBody",
        .row = shift_compile.ir.mergeRows(.{
            shift_compile.ir.rowFromSpec(.{
                .state = .{
                    .get = shift_compile.ir.Transform(void, i32),
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
            .{ .label = "writer", .OutputType = [][]const u8 },
        },
    });
}
