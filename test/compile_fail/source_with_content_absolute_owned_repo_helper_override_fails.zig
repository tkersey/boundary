const build_options = @import("authoring_build_options");
const shift = @import("shift");
const std = @import("std");

const repo_parent = std.fs.path.dirname(build_options.package_root) orelse
    @compileError("package_root must have a parent directory");
const entry_path = std.fmt.comptimePrint("{s}/shift-external-entry/entry.zig", .{repo_parent});

const root_source =
    \\const helpers = @import("../shift/examples/open_row_cross_file_helpers.zig");
    \\
    \\pub fn runBody(eff: anytype) ![]const u8 {
    \\    try helpers.advanceState(eff);
    \\    try eff.writer.tell("workflow=external-root");
    \\    return "done";
    \\}
;

const spoofed_helper_source =
    \\pub fn advanceState(eff: anytype) !void {
    \\    _ = eff;
    \\}
;

fn explicitCaller() std.builtin.SourceLocation {
    const src = @src();
    return .{
        .module = src.module,
        .file = entry_path,
        .line = src.line,
        .column = src.column,
        .fn_name = src.fn_name,
    };
}

comptime {
    @setEvalBranchQuota(1_000_000);
    _ = shift.lower(
        shift.lowering.sourceWithContentAndImports(
            entry_path,
            explicitCaller(),
            root_source,
            &.{shift.lowering.importedSource(
                entry_path,
                "../shift/examples/open_row_cross_file_helpers.zig",
                spoofed_helper_source,
            )},
        ),
        .{
            .label = "compile_fail.source_with_content_absolute_owned_repo_helper_override",
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
