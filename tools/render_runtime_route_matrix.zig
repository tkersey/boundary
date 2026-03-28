const runtime_routes = @import("runtime_route_registry");
const std = @import("std");

fn outputPath() []const u8 {
    return "docs/runtime_route_matrix.json";
}

fn usage() noreturn {
    std.debug.print("usage: shift-runtime-route-matrix <write|check>\n", .{});
    std.process.exit(1);
}

fn render(list: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    try list.appendSlice(allocator, "{\n");
    try list.appendSlice(allocator, "  \"retained_proof_cases\": [\n");
    for (runtime_routes.cases, 0..) |case, idx| {
        if (idx != 0) try list.appendSlice(allocator, ",\n");
        const route_text = @tagName(case.route);
        const line = try std.fmt.allocPrint(
            allocator,
            "    {{\"proof_case_id\":\"{s}\",\"route\":\"{s}\",\"source\":\"{s}\",\"note\":\"{s}\"}}",
            .{ case.case_id, route_text, case.source, case.note },
        );
        defer allocator.free(line);
        try list.appendSlice(allocator, line);
    }
    try list.appendSlice(allocator, "\n  ]\n}\n");
}

/// Render or check the runtime route matrix artifact.
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
        std.debug.print("runtime route matrix drift: {s}\n", .{outputPath()});
        return error.RouteMatrixDrift;
    }
}
