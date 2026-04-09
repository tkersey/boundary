const shift_compile = @import("shift_compile");
const std = @import("std");

const entry_path = "/tmp/shift-owned-open-row/nested/deeper/entry.zig";

const root_source =
    \\const helpers = @import("C:/tmp/outside_helper.zig");
    \\
    \\pub fn runBody(eff: anytype) !void {
    \\    try helpers.helper(eff);
    \\}
;

const helper_source =
    \\pub fn helper(eff: anytype) !void {
    \\    try eff.writer.tell("escaped");
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
    _ = shift_compile.lower(
        shift_compile.lowering.sourceWithContentAndImports(
            entry_path,
            explicitCaller(),
            root_source,
            &.{shift_compile.lowering.importedSource(
                entry_path,
                "C:/tmp/outside_helper.zig",
                helper_source,
            )},
        ),
        .{
            .label = "compile_fail.absolute_owned_helper_import_windows_absolute_path",
            .entry_symbol = "runBody",
            .row = shift_compile.ir.rowFromSpec(.{
                .writer = .{
                    .tell = shift_compile.ir.Transform([]const u8, void),
                },
            }),
            .outputs = &.{
                .{ .label = "writer", .OutputType = [][]const u8 },
            },
        },
    );
}
