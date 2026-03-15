const frontend_features = @import("frontend_feature_registry");
const std = @import("std");

fn outputPath() []const u8 {
    return "docs/frontend_feature_matrix.json";
}

fn usage() noreturn {
    std.debug.print("usage: shift-frontend-feature-matrix <write|check>\n", .{});
    std.process.exit(1);
}

fn render(list: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    try list.appendSlice(allocator, "{\n");
    try list.appendSlice(allocator, "  \"features\": [\n");
    for (frontend_features.features, 0..) |feature, idx| {
        if (idx != 0) try list.appendSlice(allocator, ",\n");
        const line = try std.fmt.allocPrint(
            allocator,
            "    {{\"feature_id\":\"{s}\",\"surface\":\"{s}\",\"status\":\"{s}\",\"source\":\"{s}\",\"note\":\"{s}\"}}",
            .{
                feature.feature_id,
                feature.surface,
                @tagName(feature.status),
                feature.source,
                feature.note,
            },
        );
        defer allocator.free(line);
        try list.appendSlice(allocator, line);
    }
    try list.appendSlice(allocator, "\n  ]\n}\n");
}

/// Render or check the frontend-feature matrix artifact.
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
        std.debug.print("frontend feature matrix drift: {s}\n", .{outputPath()});
        return error.FrontendFeatureMatrixDrift;
    }
}
