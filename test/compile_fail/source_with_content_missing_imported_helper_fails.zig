const shift = @import("shift");
const std = @import("std");

const repo_path = "/tmp/source_with_content_missing_imported_helper_fails.zig";

const root_source =
    \\const helpers = @import("open_row_helper_value_flow_cross_helpers.zig");
    \\
    \\pub fn runBody(eff: anytype) ![]const u8 {
    \\    return try helpers.classify("caller-owned", 7, eff);
    \\}
;

fn explicitCaller() std.builtin.SourceLocation {
    const src = @src();
    return .{
        .module = src.module,
        .file = repo_path,
        .line = src.line,
        .column = src.column,
        .fn_name = src.fn_name,
    };
}

comptime {
    @setEvalBranchQuota(1_000_000);
    _ = shift.lower(
        shift.lowering.sourceWithContent(
            repo_path,
            explicitCaller(),
            root_source,
        ),
        .{
            .label = "compile_fail.source_with_content_missing_imported_helper",
            .entry_symbol = "runBody",
            .row = shift.ir.mergeRows(.{
                shift.ir.rowFromSpec(.{
                    .state = .{
                        .get = shift.ir.Transform(void, i32),
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
                .{ .label = "writer", .OutputType = [][]const u8 },
            },
        },
    );
}
