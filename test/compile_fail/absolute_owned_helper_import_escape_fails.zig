const shift = @import("shift");
const std = @import("std");

const entry_path = "/tmp/shift-owned-open-row/nested/deeper/entry.zig";

const root_source =
    \\const helpers = @import("../../outside_helper.zig");
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
    _ = shift.lower(
        shift.lowering.sourceWithContentAndImports(
            entry_path,
            explicitCaller(),
            root_source,
            &.{shift.lowering.importedSource(
                entry_path,
                "../../outside_helper.zig",
                helper_source,
            )},
        ),
        .{
            .label = "compile_fail.absolute_owned_helper_import_escape",
            .entry_symbol = "runBody",
            .row = shift.ir.rowFromSpec(.{
                .writer = .{
                    .tell = shift.ir.Transform([]const u8, void),
                },
            }),
            .outputs = &.{
                .{ .label = "writer", .OutputType = [][]const u8 },
            },
        },
    );
}
