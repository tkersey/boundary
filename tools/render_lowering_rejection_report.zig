const source_lowering = @import("source_lowering");
const std = @import("std");

const dead_code_source =
    \\/// Stable source-lowering case id.
    \\pub const source_case_id = "source.branch_resume";
    \\/// Embedded source text consumed by the source-validated source-lowering checker.
    \\pub const source = @embedFile("branch_resume.zig");
    \\
    \\/// Run the branch case with source-lowering control flow.
    \\pub fn run(writer: anytype) anyerror!void {
    \\    try writer.writeAll("branch=before\n");
    \\    return;
    \\    var answer: i32 = 0;
    \\    const take_branch = true;
    \\    if (take_branch) {
    \\        try writer.writeAll("branch=taken\n");
    \\        const resumed: i32 = 41;
    \\        try writer.print("resume={d}\n", .{resumed});
    \\        answer = resumed + 1;
    \\    }
    \\    try writer.writeAll("branch=after\n");
    \\    try writer.print("final={d}\n", .{answer});
    \\}
;

const dynamic_callee_source =
    \\/// Stable source-lowering case id.
    \\pub const source_case_id = "source.helper_call_resume";
    \\/// Embedded source text consumed by the source-validated source-lowering checker.
    \\pub const source = @embedFile("helper_call_resume.zig");
    \\
    \\fn helper(writer: anytype) anyerror!i32 {
    \\    try writer.writeAll("helper=enter\n");
    \\    const resumed: i32 = 41;
    \\    try writer.print("resume={d}\n", .{resumed});
    \\    try writer.writeAll("helper=exit\n");
    \\    return resumed + 1;
    \\}
    \\
    \\/// Run the helper-call case with source-lowering control flow.
    \\pub fn run(writer: anytype) anyerror!void {
    \\    const callee = helper;
    \\    const answer = try callee(writer);
    \\    try writer.print("final={d}\n", .{answer});
    \\}
;

const renamed_helper_source =
    \\/// Stable source-lowering case id.
    \\pub const source_case_id = "source.helper_call_resume";
    \\/// Embedded source text consumed by the source-validated source-lowering checker.
    \\pub const source = @embedFile("helper_call_resume.zig");
    \\
    \\fn helper(writer: anytype) anyerror!i32 {
    \\    try writer.writeAll("helper=enter\n");
    \\    const resumed: i32 = 41;
    \\    try writer.print("resume={d}\n", .{resumed});
    \\    try writer.writeAll("helper=exit\n");
    \\    return resumed + 1;
    \\}
    \\
    \\fn alternate(writer: anytype) anyerror!i32 {
    \\    return helper(writer);
    \\}
    \\
    \\/// Run the helper-call case with source-lowering control flow.
    \\pub fn run(writer: anytype) anyerror!void {
    \\    const answer = try alternate(writer);
    \\    try writer.print("final={d}\n", .{answer});
    \\}
;

fn outputPath() []const u8 {
    return "docs/lowering_rejection_report.json";
}

fn usage() noreturn {
    std.debug.print("usage: shift-lowering-rejection-report <write|check>\n", .{});
    std.process.exit(1);
}

fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |byte| switch (byte) {
        '"' => try writer.writeAll("\\\""),
        '\\' => try writer.writeAll("\\\\"),
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        '\t' => try writer.writeAll("\\t"),
        else => try writer.writeByte(byte),
    };
    try writer.writeByte('"');
}

const InlineRowInput = struct {
    label: []const u8,
    spec: source_lowering.Spec,
    source_text: []const u8,
};

fn appendInlineRow(
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    input: InlineRowInput,
    first: *bool,
) !void {
    var lowered = try source_lowering.inspectInlineSource(allocator, input.spec, input.source_text);
    defer lowered.deinit(allocator);
    if (lowered.isAccepted() or lowered.diagnostics.len == 0) {
        std.debug.print("lowering rejection row unexpectedly accepted: {s}\n", .{input.label});
        return error.RejectionRowAccepted;
    }
    if (!first.*) try list.appendSlice(allocator, ",\n");
    first.* = false;
    var line: std.io.Writer.Allocating = .init(allocator);
    defer line.deinit();
    try line.writer.writeAll("    {\"label\":");
    try writeJsonString(&line.writer, input.label);
    try line.writer.writeAll(",\"case_id\":");
    try writeJsonString(&line.writer, input.spec.case_id);
    try line.writer.writeAll(",\"diagnostic_code\":");
    try writeJsonString(&line.writer, lowered.diagnostics[0].code);
    try line.writer.writeAll(",\"source_path\":");
    try writeJsonString(&line.writer, lowered.diagnostics[0].path);
    try line.writer.print(",\"line\":{},\"column\":{}}}", .{
        lowered.diagnostics[0].line,
        lowered.diagnostics[0].column,
    });
    const owned = try line.toOwnedSlice();
    defer allocator.free(owned);
    try list.appendSlice(allocator, owned);
}

fn appendFileRow(
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    label: []const u8,
    spec: source_lowering.Spec,
    first: *bool,
) !void {
    var lowered = try source_lowering.inspectSource(allocator, spec);
    defer lowered.deinit(allocator);
    if (lowered.isAccepted() or lowered.diagnostics.len == 0) {
        std.debug.print("lowering rejection row unexpectedly accepted: {s}\n", .{label});
        return error.RejectionRowAccepted;
    }
    if (!first.*) try list.appendSlice(allocator, ",\n");
    first.* = false;
    var line: std.io.Writer.Allocating = .init(allocator);
    defer line.deinit();
    try line.writer.writeAll("    {\"label\":");
    try writeJsonString(&line.writer, label);
    try line.writer.writeAll(",\"case_id\":");
    try writeJsonString(&line.writer, spec.case_id);
    try line.writer.writeAll(",\"diagnostic_code\":");
    try writeJsonString(&line.writer, lowered.diagnostics[0].code);
    try line.writer.writeAll(",\"source_path\":");
    try writeJsonString(&line.writer, lowered.diagnostics[0].path);
    try line.writer.print(",\"line\":{},\"column\":{}}}", .{
        lowered.diagnostics[0].line,
        lowered.diagnostics[0].column,
    });
    const owned = try line.toOwnedSlice();
    defer allocator.free(owned);
    try list.appendSlice(allocator, owned);
}

fn render(list: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    try list.appendSlice(allocator, "{\n");
    try list.appendSlice(allocator, "  \"scope\": \"lowering_rejection\",\n");
    try list.appendSlice(allocator, "  \"rows\": [\n");
    var first = true;
    try appendInlineRow(list, allocator, .{
        .label = "source.branch_resume.dead_code",
        .spec = .{
            .case_id = "source.branch_resume",
            .source_path = "test/source_lowering_corpus/fixtures/branch_resume.zig",
            .entry_symbol = "run",
            .surface_kind = .source_case,
        },
        .source_text = dead_code_source,
    }, &first);
    try appendInlineRow(list, allocator, .{
        .label = "source.helper_call_resume.dynamic_callee",
        .spec = .{
            .case_id = "source.helper_call_resume",
            .source_path = "test/source_lowering_corpus/fixtures/helper_call_resume.zig",
            .entry_symbol = "run",
            .surface_kind = .source_case,
        },
        .source_text = dynamic_callee_source,
    }, &first);
    try appendInlineRow(list, allocator, .{
        .label = "source.helper_call_resume.renamed_helper",
        .spec = .{
            .case_id = "source.helper_call_resume",
            .source_path = "test/source_lowering_corpus/fixtures/helper_call_resume.zig",
            .entry_symbol = "run",
            .surface_kind = .source_case,
        },
        .source_text = renamed_helper_source,
    }, &first);
    try appendFileRow(list, allocator, "example.open_row_transform_basic.wrong_entry", .{
        .case_id = "example.open_row_transform_basic",
        .source_path = "examples/open_row_transform_basic.zig",
        .entry_symbol = "run_counter",
        .surface_kind = .example,
    }, &first);
    try list.appendSlice(allocator, "\n  ]\n}\n");
}

/// Render or check the lowering rejection report artifact.
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
        try std.fs.cwd().writeFile(.{ .sub_path = outputPath(), .data = rendered.items });
        return;
    }

    const actual = try std.fs.cwd().readFileAlloc(allocator, outputPath(), std.math.maxInt(usize));
    defer allocator.free(actual);
    if (!std.mem.eql(u8, actual, rendered.items)) {
        std.debug.print("lowering rejection report drift: {s}\n", .{outputPath()});
        return error.LoweringRejectionReportDrift;
    }
}
