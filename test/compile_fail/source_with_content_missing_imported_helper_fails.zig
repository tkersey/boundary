const shift_compile = @import("shift_compile");
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
    _ = shift_compile.lower(
        shift_compile.lowering.sourceWithContent(
            repo_path,
            explicitCaller(),
            root_source,
        ),
        .{
            .label = "compile_fail.source_with_content_missing_imported_helper",
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
        },
    );
}
