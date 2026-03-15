const program_bridge = @import("program_bridge");
const program_frontend = @import("program_frontend");
const std = @import("std");

fn scorecardPath() []const u8 {
    return "docs/surface_truth_scorecard.json";
}

fn usage() noreturn {
    std.debug.print("usage: shift-surface-truth-scorecard <write|check>\n", .{});
    std.process.exit(1);
}

fn appendStringList(list: *std.ArrayList(u8), allocator: std.mem.Allocator, items: []const []const u8) !void {
    try list.appendSlice(allocator, "[");
    for (items, 0..) |item, idx| {
        if (idx != 0) try list.appendSlice(allocator, ",");
        const rendered = try std.fmt.allocPrint(allocator, "\"{s}\"", .{item});
        defer allocator.free(rendered);
        try list.appendSlice(allocator, rendered);
    }
    try list.appendSlice(allocator, "]");
}

fn render(list: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    try list.appendSlice(allocator, "{\n");
    try list.appendSlice(allocator, "  \"public_surface\": {\n");
    try list.appendSlice(allocator, "    \"contract\": \"prompt-value direct-style shift/reset\",\n");
    try list.appendSlice(allocator, "    \"status\": \"canonical\"\n");
    try list.appendSlice(allocator, "  },\n");
    try list.appendSlice(allocator, "  \"benchmark_stability\": {\n");
    try list.appendSlice(allocator, "    \"harness_step\": \"bench-effect-matrix-stability\",\n");
    try list.appendSlice(allocator, "    \"lane_policy\": \"evidence-backed retiering only\",\n");
    try list.appendSlice(allocator, "    \"status\": \"pending_clean_commit_refresh\"\n");
    try list.appendSlice(allocator, "  },\n");
    try list.appendSlice(allocator, "  \"lowered_engine\": {\n");
    try list.appendSlice(allocator, "    \"surface\": \"parity_scenarios + parity_kernel\",\n");
    try list.appendSlice(allocator, "    \"status\": \"candidate_backed\"\n");
    try list.appendSlice(allocator, "  },\n");
    try list.appendSlice(allocator, "  \"structured_programs\": {\n");
    try list.appendSlice(allocator, "    \"role\": \"internal_scaffolding\",\n");
    try list.appendSlice(allocator, "    \"labels\": ");
    var labels = std.ArrayList([]const u8).empty;
    defer labels.deinit(std.heap.page_allocator);
    for (program_frontend.corpus) |program| try labels.append(std.heap.page_allocator, program_frontend.label(program));
    try appendStringList(list, allocator, labels.items);
    try list.appendSlice(allocator, ",\n");
    try list.appendSlice(allocator, "    \"status\": \"implemented\"\n");
    try list.appendSlice(allocator, "  },\n");
    try list.appendSlice(allocator, "  \"direct_style_bridge\": {\n");
    try list.appendSlice(allocator, "    \"supported_cases\": ");
    try appendStringList(list, allocator, &program_bridge.supported_cases);
    try list.appendSlice(allocator, ",\n");
    try list.appendSlice(allocator, "    \"blocked_cases\": [\"nested_workflow\"],\n");
    try list.appendSlice(allocator, "    \"status\": \"partial\"\n");
    try list.appendSlice(allocator, "  },\n");
    try list.appendSlice(allocator, "  \"hidden_backend_recommendation\": \"blocked\"\n");
    try list.appendSlice(allocator, "}\n");
}

/// Render or check the machine-readable surface-truth scorecard.
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
            .sub_path = scorecardPath(),
            .data = rendered.items,
        });
        return;
    }

    const actual = try std.fs.cwd().readFileAlloc(allocator, scorecardPath(), std.math.maxInt(usize));
    defer allocator.free(actual);
    if (!std.mem.eql(u8, actual, rendered.items)) {
        std.debug.print("surface truth scorecard drift: {s}\n", .{scorecardPath()});
        return error.ScorecardDrift;
    }
}
