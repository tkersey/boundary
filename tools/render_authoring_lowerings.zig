const program_frontend = @import("program_frontend");
const std = @import("std");

fn loweringPath() []const u8 {
    return "test/authoring_lowerings/structured_programs.txt";
}

fn usage() noreturn {
    std.debug.print("usage: shift-authoring-lowering-render <write|check>\n", .{});
    std.process.exit(1);
}

fn render(list: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    for (program_frontend.corpus) |program| {
        const lowered = program_frontend.lower(program);
        const line = try std.fmt.allocPrint(
            allocator,
            "label={s}\nscenario={s}\nsurface={s}\nstep_count={d}\ncheckpoint_count={d}\nfixture={s}\n---\n",
            .{
                lowered.label,
                lowered.scenario.case_id,
                @tagName(lowered.scenario.surface),
                lowered.scenario.steps.len,
                lowered.scenario.trace_checkpoints.len,
                lowered.scenario.fixture_name orelse "",
            },
        );
        defer allocator.free(line);
        try list.appendSlice(allocator, line);
    }
}

/// Render or check lowering snapshots for the internal structured-program front end.
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
        try std.fs.cwd().makePath("test/authoring_lowerings");
        try std.fs.cwd().writeFile(.{
            .sub_path = loweringPath(),
            .data = rendered.items,
        });
        return;
    }

    const actual = try std.fs.cwd().readFileAlloc(allocator, loweringPath(), std.math.maxInt(usize));
    defer allocator.free(actual);
    if (!std.mem.eql(u8, actual, rendered.items)) {
        std.debug.print("authoring lowering drift: {s}\n", .{loweringPath()});
        return error.LoweringDrift;
    }
}
