const coverage = @import("source_lowering_coverage_registry");
const std = @import("std");

fn outputPath() []const u8 {
    return "docs/source_lowering_coverage_matrix.json";
}

fn usage() noreturn {
    std.debug.print("usage: shift-source-lowering-coverage-matrix <write|check>\n", .{});
    std.process.exit(1);
}

fn render(list: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    try list.appendSlice(allocator, "{\n");
    try list.appendSlice(allocator, "  \"scope\": \"source_lowering_coverage\",\n");
    try list.appendSlice(allocator, "  \"rows\": [\n");
    for (coverage.rows, 0..) |row, idx| {
        if (idx != 0) try list.appendSlice(allocator, ",\n");
        const line = try std.fmt.allocPrint(
            allocator,
            "    {{\"coverage_id\":\"{s}\",\"category\":\"{s}\",\"proof_label\":\"{s}\",\"current_signal\":\"{s}\",\"law_anchor\":\"{s}\",\"source_label\":\"{s}\",\"coverage_status\":\"{s}\",\"note\":\"{s}\"}}",
            .{
                row.coverage_id,
                @tagName(row.category),
                row.current_surface,
                row.current_signal,
                row.law_anchor,
                row.source_label,
                @tagName(row.coverage_status),
                row.note,
            },
        );
        defer allocator.free(line);
        try list.appendSlice(allocator, line);
    }
    try list.appendSlice(allocator, "\n  ]\n}\n");
}

/// Render or check the source-lowering coverage matrix artifact.
pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    if (args.len != 2) usage();
    const mode = args[1];
    if (!std.mem.eql(u8, mode, "check") and !std.mem.eql(u8, mode, "write")) usage();

    var rendered = std.ArrayList(u8).empty;
    defer rendered.deinit(allocator);
    try render(&rendered, allocator);

    if (std.mem.eql(u8, mode, "write")) {
        try std.fs.cwd().writeFile(.{
            .sub_path = outputPath(),
            .data = rendered.items,
        });
        return;
    }

    const actual = try std.fs.cwd().readFileAlloc(allocator, outputPath(), std.math.maxInt(usize));
    defer allocator.free(actual);
    if (!std.mem.eql(u8, actual, rendered.items)) {
        std.debug.print("source-lowering coverage matrix drift: {s}\n", .{outputPath()});
        return error.SourceLoweringCoverageMatrixDrift;
    }
}
