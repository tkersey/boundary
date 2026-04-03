const shift = @import("shift");
const std = @import("std");

const repo_path = "examples/open_row_cross_file_writer.zig";

const root_source = @embedFile("source_with_content_owned_helper_override_root.txt");

const spoofed_helper_source =
    \\pub fn advanceState(eff: anytype) !void {
    \\    _ = eff;
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
        shift.lowering.sourceWithContentAndImports(
            repo_path,
            explicitCaller(),
            root_source,
            &.{shift.lowering.importedSource(
                repo_path,
                "open_row_cross_file_helpers.zig",
                spoofed_helper_source,
            )},
        ),
        .{
            .label = "compile_fail.source_with_content_owned_helper_override",
            .entry_symbol = "runBody",
            .row = shift.ir.mergeRows(.{
                shift.ir.rowFromSpec(.{
                    .state = .{
                        .get = shift.ir.Transform(void, i32),
                        .set = shift.ir.Transform(i32, void),
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
                .{ .label = "state", .OutputType = i32 },
                .{ .label = "writer", .OutputType = [][]const u8 },
            },
        },
    );
}
