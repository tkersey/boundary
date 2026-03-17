const bridge_manifest = @import("direct_style_bridge_manifest");
const ordinary = @import("ordinary_zig_registry");
const program_frontend = @import("program_frontend");
const replacements = @import("surface_replacement_registry");
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

fn appendCaseIdsByStatus(
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    status: bridge_manifest.Status,
) !void {
    try list.appendSlice(allocator, "[");
    var first = true;
    for (bridge_manifest.cases) |case| {
        if (case.status != status) continue;
        if (!first) try list.appendSlice(allocator, ",");
        first = false;
        const rendered = try std.fmt.allocPrint(allocator, "\"{s}\"", .{case.case_id});
        defer allocator.free(rendered);
        try list.appendSlice(allocator, rendered);
    }
    try list.appendSlice(allocator, "]");
}

fn ordinaryStatus() []const u8 {
    for (ordinary.cases) |case| {
        if (case.status != .parity_green and case.status != .canonical) return "partial";
    }
    const promoted_ids = [_][]const u8{
        "example.early_exit",
        "example.resume_or_return",
        "example.nested_workflow",
        "example.state_basic",
        "example.reader_basic",
        "example.optional_basic",
        "example.exception_basic",
        "built_in.state",
        "built_in.reader",
        "built_in.optional",
        "built_in.exception",
    };
    outer: for (promoted_ids) |id| {
        for (replacements.rows) |row| {
            if (!std.mem.eql(u8, row.replacement_id, id)) continue;
            if (row.status != .parity_green and row.status != .canonical) return "parity_backed_wave_one";
            continue :outer;
        }
        return "parity_backed_wave_one";
    }
    return "promoted_cohort_a";
}

fn render(list: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    const has_blocked_cases = bridge_manifest.blockedCount() != 0;
    try list.appendSlice(allocator, "{\n");
    try list.appendSlice(allocator, "  \"public_surface\": {\n");
    try list.appendSlice(allocator, "    \"contract\": \"lexical effect/algebraic shift.with(...) surface\",\n");
    try list.appendSlice(allocator, "    \"status\": \"canonical\"\n");
    try list.appendSlice(allocator, "  },\n");
    try list.appendSlice(allocator, "  \"benchmark_stability\": {\n");
    try list.appendSlice(allocator, "    \"harness_step\": \"bench-effect-matrix-stability\",\n");
    try list.appendSlice(allocator, "    \"lane_policy\": \"evidence-backed retiering only\",\n");
    try list.appendSlice(allocator, "    \"status\": \"published_clean_refresh\"\n");
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
    try list.appendSlice(allocator, "  \"ordinary_experimental_surface\": {\n");
    try list.appendSlice(allocator, "    \"contract\": \"public experimental source-validated lowering for the wave-one ordinary-Zig subset plus the promoted Cohort A example/effect rows\",\n");
    try list.appendSlice(allocator, "    \"status\": \"");
    try list.appendSlice(allocator, ordinaryStatus());
    try list.appendSlice(allocator, "\"\n");
    try list.appendSlice(allocator, "  },\n");
    try list.appendSlice(allocator, "  \"direct_style_bridge\": {\n");
    try list.appendSlice(allocator, "    \"supported_cases\": ");
    try appendCaseIdsByStatus(list, allocator, .supported);
    try list.appendSlice(allocator, ",\n");
    try list.appendSlice(allocator, "    \"blocked_cases\": ");
    try appendCaseIdsByStatus(list, allocator, .blocked);
    try list.appendSlice(allocator, ",\n");
    try list.appendSlice(allocator, if (has_blocked_cases) "    \"status\": \"partial\"\n" else "    \"status\": \"supported_core_examples\"\n");
    try list.appendSlice(allocator, "  },\n");
    try list.appendSlice(allocator, "  \"private_lowered_runtime_seam\": {\n");
    try list.appendSlice(allocator, if (has_blocked_cases) "    \"decision\": \"not_worth_finishing\",\n" else "    \"decision\": \"worth_finishing\",\n");
    try list.appendSlice(allocator, if (has_blocked_cases) "    \"status\": \"not_started\",\n" else "    \"status\": \"implemented_for_supported_bridge_cases\",\n");
    try list.appendSlice(allocator, if (has_blocked_cases)
        "    \"rationale\": \"unchanged-body bridge coverage is still incomplete\"\n"
    else
        "    \"rationale\": \"supported bridge cases now execute through src/private_lowered_runtime.zig without public API changes\"\n");
    try list.appendSlice(allocator, "  }\n");
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
