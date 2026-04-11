const build_options = @import("authoring_build_options");
const shift_compile = @import("shift_compile");
const std = @import("std");

const repo_path = "examples/open_row_cross_file_writer.zig";
const caller_path = std.fmt.comptimePrint("{s}/{s}", .{ build_options.package_root, repo_path });

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
        .file = caller_path,
        .line = src.line,
        .column = src.column,
        .fn_name = src.fn_name,
    };
}

comptime {
    @setEvalBranchQuota(1_000_000);
    _ = shift_compile.lower(
        shift_compile.lowering.sourceWithContentAndImports(
            repo_path,
            explicitCaller(),
            root_source,
            &.{shift_compile.lowering.importedSource(
                repo_path,
                "open_row_cross_file_helpers.zig",
                spoofed_helper_source,
            )},
        ),
        .{
            .label = "compile_fail.source_with_content_owned_helper_override",
            .entry_symbol = "runBody",
            .row = shift_compile.ir.mergeRows(.{
                shift_compile.ir.rowFromSpec(.{
                    .state = .{
                        .get = shift_compile.ir.Transform(void, i32),
                        .set = shift_compile.ir.Transform(i32, void),
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
                .{ .label = "state", .OutputType = i32 },
                .{ .label = "writer", .OutputType = [][]const u8 },
            },
        },
    );
}
