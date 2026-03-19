const bridge_manifest = @import("direct_style_bridge_manifest");
const lowered_machine = @import("lowered_machine");
const parity_scenarios = @import("parity_scenarios");
const program_bridge = @import("program_bridge");
const source_lowering = @import("source_lowering");
const std = @import("std");

const ReportSpec = struct {
    case_id: []const u8,
    source_path: []const u8,
    entry_symbol: []const u8 = "run",
    surface_kind: source_lowering.SurfaceKind,
};

const source_specs = [_]ReportSpec{
    .{ .case_id = "source.local_mutation_resume", .source_path = "test/source_lowering_corpus/fixtures/local_mutation_resume.zig", .surface_kind = .source_case },
    .{ .case_id = "source.branch_resume", .source_path = "test/source_lowering_corpus/fixtures/branch_resume.zig", .surface_kind = .source_case },
    .{ .case_id = "source.loop_resume", .source_path = "test/source_lowering_corpus/fixtures/loop_resume.zig", .surface_kind = .source_case },
    .{ .case_id = "source.helper_call_resume", .source_path = "test/source_lowering_corpus/fixtures/helper_call_resume.zig", .surface_kind = .source_case },
    .{ .case_id = "source.nested_prompt_static_redelim", .source_path = "test/source_lowering_corpus/fixtures/nested_prompt_static_redelim.zig", .surface_kind = .source_case },
    .{ .case_id = "source.typed_error_try", .source_path = "test/source_lowering_corpus/fixtures/typed_error_try.zig", .surface_kind = .source_case },
    .{ .case_id = "source.defer_resume", .source_path = "test/source_lowering_corpus/fixtures/defer_resume.zig", .surface_kind = .source_case },
    .{ .case_id = "source.errdefer_error", .source_path = "test/source_lowering_corpus/fixtures/errdefer_error.zig", .surface_kind = .source_case },
};

const promoted_specs = [_]ReportSpec{
    .{ .case_id = "example.define_basic", .source_path = "examples/define_basic.zig", .surface_kind = .example },
    .{ .case_id = "example.define_choice_basic", .source_path = "examples/define_choice_basic.zig", .surface_kind = .example },
    .{ .case_id = "example.define_abort_basic", .source_path = "examples/define_abort_basic.zig", .surface_kind = .example },
    .{ .case_id = "example.early_exit", .source_path = "examples/early_exit.zig", .surface_kind = .example },
    .{ .case_id = "example.resume_or_return", .source_path = "examples/resume_or_return.zig", .surface_kind = .example },
    .{ .case_id = "example.front_door_workflow", .source_path = "examples/front_door_workflow.zig", .surface_kind = .example },
    .{ .case_id = "example.nested_workflow", .source_path = "examples/nested_workflow.zig", .surface_kind = .example },
    .{ .case_id = "example.state_basic", .source_path = "examples/state_basic.zig", .surface_kind = .example },
    .{ .case_id = "example.reader_basic", .source_path = "examples/reader_basic.zig", .surface_kind = .example },
    .{ .case_id = "example.optional_basic", .source_path = "examples/optional_basic.zig", .surface_kind = .example },
    .{ .case_id = "example.exception_basic", .source_path = "examples/exception_basic.zig", .surface_kind = .example },
    .{ .case_id = "example.resource_basic", .source_path = "examples/resource_basic.zig", .surface_kind = .example },
    .{ .case_id = "example.writer_basic", .source_path = "examples/writer_basic.zig", .surface_kind = .example },
    .{ .case_id = "example.algebraic_abortive_validation", .source_path = "examples/algebraic_abortive_validation.zig", .surface_kind = .example },
    .{ .case_id = "example.algebraic_artifact_search", .source_path = "examples/algebraic_artifact_search.zig", .surface_kind = .example },
    .{ .case_id = "effect.state_basic", .source_path = "examples/state_basic.zig", .surface_kind = .effect },
    .{ .case_id = "effect.reader_basic", .source_path = "examples/reader_basic.zig", .surface_kind = .effect },
    .{ .case_id = "effect.optional_basic", .source_path = "examples/optional_basic.zig", .surface_kind = .effect },
    .{ .case_id = "effect.exception_basic", .source_path = "examples/exception_basic.zig", .surface_kind = .effect },
    .{ .case_id = "effect.resource_basic", .source_path = "examples/resource_basic.zig", .surface_kind = .effect },
    .{ .case_id = "effect.writer_basic", .source_path = "examples/writer_basic.zig", .surface_kind = .effect },
    .{ .case_id = "user_defined.transform", .source_path = "examples/define_basic.zig", .surface_kind = .user_defined_effect },
    .{ .case_id = "user_defined.choice", .source_path = "examples/define_choice_basic.zig", .surface_kind = .user_defined_effect },
    .{ .case_id = "user_defined.abort", .source_path = "examples/define_abort_basic.zig", .surface_kind = .user_defined_effect },
    .{ .case_id = "witness.atm_resume_transform", .source_path = "src/witness_sources.zig", .entry_symbol = "runAtmResumeTransform", .surface_kind = .witness },
    .{ .case_id = "witness.direct_return", .source_path = "src/witness_sources.zig", .entry_symbol = "runDirectReturn", .surface_kind = .witness },
    .{ .case_id = "witness.resume_or_return_return_now", .source_path = "src/witness_sources.zig", .entry_symbol = "runResumeOrReturnReturnNow", .surface_kind = .witness },
    .{ .case_id = "witness.resume_or_return_resume", .source_path = "src/witness_sources.zig", .entry_symbol = "runResumeOrReturnResume", .surface_kind = .witness },
    .{ .case_id = "witness.static_redelim", .source_path = "src/witness_sources.zig", .entry_symbol = "runStaticRedelim", .surface_kind = .witness },
    .{ .case_id = "witness.multi_prompt", .source_path = "src/witness_sources.zig", .entry_symbol = "runMultiPrompt", .surface_kind = .witness },
    .{ .case_id = "witness.generator", .source_path = "src/witness_sources.zig", .entry_symbol = "runGenerator", .surface_kind = .witness },
};

fn outputPath() []const u8 {
    return "docs/lowering_equivalence_report.json";
}

fn usage() noreturn {
    std.debug.print("usage: shift-lowering-equivalence-report <write|check>\n", .{});
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

fn writeFeatureFlags(writer: anytype, flags: []const []const u8) !void {
    try writer.writeByte('[');
    for (flags, 0..) |flag, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writeJsonString(writer, flag);
    }
    try writer.writeByte(']');
}

fn bridgeProofCaseId(allocator: std.mem.Allocator, case: bridge_manifest.Case) !?[]const u8 {
    var buffer = std.ArrayList(u8).empty;
    errdefer buffer.deinit(allocator);
    switch (case.source_kind) {
        .witness => {
            try buffer.appendSlice(allocator, "witness.");
            try buffer.appendSlice(allocator, case.case_id);
            return try buffer.toOwnedSlice(allocator);
        },
        .example => {
            if (std.mem.eql(u8, case.case_id, "generator")) return null;
            try buffer.appendSlice(allocator, "example.");
            try buffer.appendSlice(allocator, case.case_id);
            return try buffer.toOwnedSlice(allocator);
        },
    }
}

fn bridgeWitnessEquivalence(allocator: std.mem.Allocator, case: bridge_manifest.Case) !bool {
    const proof_case_id = try bridgeProofCaseId(allocator, case) orelse return false;
    defer allocator.free(proof_case_id);

    var lowered = try source_lowering.inspectSource(allocator, .{
        .case_id = proof_case_id,
        .source_path = case.source_module,
        .entry_symbol = case.entry_symbol,
        .surface_kind = switch (case.source_kind) {
            .witness => .witness,
            .example => .example,
        },
    });
    defer lowered.deinit(allocator);
    return lowered.isAccepted() and lowered.error_witness.support_status == .supported and lowered.error_witness.diagnostics.len == 0;
}

fn renderSourceRow(list: *std.ArrayList(u8), allocator: std.mem.Allocator, spec: ReportSpec, first: *bool) !void {
    var lowered = try source_lowering.inspectSource(allocator, .{
        .case_id = spec.case_id,
        .source_path = spec.source_path,
        .entry_symbol = spec.entry_symbol,
        .surface_kind = spec.surface_kind,
    });
    defer lowered.deinit(allocator);

    var transcript_buffer: [4096]u8 = undefined;
    var transcript_writer = std.Io.Writer.fixed(&transcript_buffer);
    try source_lowering.runLowered(&transcript_writer, &lowered);
    const scenario = parity_scenarios.byId(lowered.canonical_scenario_id.?);
    if (!first.*) try list.appendSlice(allocator, ",\n");
    first.* = false;
    var line: std.io.Writer.Allocating = .init(allocator);
    defer line.deinit();
    try line.writer.writeAll("    {\"case_id\":");
    try writeJsonString(&line.writer, spec.case_id);
    try line.writer.writeAll(",\"surface_kind\":");
    try writeJsonString(&line.writer, @tagName(spec.surface_kind));
    try line.writer.writeAll(",\"source_path\":");
    try writeJsonString(&line.writer, spec.source_path);
    try line.writer.writeAll(",\"entry_symbol\":");
    try writeJsonString(&line.writer, spec.entry_symbol);
    try line.writer.writeAll(",\"canonical_scenario_id\":");
    try writeJsonString(&line.writer, @tagName(lowered.canonical_scenario_id.?));
    try line.writer.print(",\"lower_status\":\"{s}\",\"transcript_equivalence\":{},\"error_witness_equivalence\":{},\"diagnostic_count\":{},\"feature_flags\":", .{
        @tagName(lowered.status),
        std.mem.eql(u8, transcript_writer.buffered(), scenario.expected_transcript),
        lowered.error_witness.support_status == .supported and lowered.error_witness.diagnostics.len == 0,
        lowered.diagnostics.len,
    });
    try writeFeatureFlags(&line.writer, lowered.feature_flags);
    try line.writer.writeByte('}');
    const owned = try line.toOwnedSlice();
    defer allocator.free(owned);
    try list.appendSlice(allocator, owned);
}

fn renderBridgeRows(list: *std.ArrayList(u8), allocator: std.mem.Allocator, first: *bool) !void {
    for (bridge_manifest.cases) |case| {
        if (case.status != .supported) continue;
        var lowered = try program_bridge.lowerCaseId(allocator, case.case_id);
        defer lowered.deinit(allocator);
        const scenario = parity_scenarios.byId(lowered.canonical_scenario_id.?);
        const state = lowered_machine.runSteps(lowered.steps);
        var transcript_buffer: [4096]u8 = undefined;
        var transcript_writer = std.Io.Writer.fixed(&transcript_buffer);
        try lowered_machine.writeTranscript(&transcript_writer, &state);
        if (!first.*) try list.appendSlice(allocator, ",\n");
        first.* = false;
        var line: std.io.Writer.Allocating = .init(allocator);
        defer line.deinit();
        try line.writer.writeAll("    {\"case_id\":");
        try writeJsonString(&line.writer, case.case_id);
        try line.writer.writeAll(",\"surface_kind\":\"bridge\",\"source_path\":");
        try writeJsonString(&line.writer, case.source_module);
        try line.writer.writeAll(",\"entry_symbol\":");
        try writeJsonString(&line.writer, case.entry_symbol);
        try line.writer.writeAll(",\"canonical_scenario_id\":");
        try writeJsonString(&line.writer, @tagName(lowered.canonical_scenario_id.?));
        try line.writer.print(",\"lower_status\":\"{s}\",\"transcript_equivalence\":{},\"error_witness_equivalence\":{},\"diagnostic_count\":{},\"feature_flags\":", .{
            @tagName(lowered.status),
            std.mem.eql(u8, transcript_writer.buffered(), scenario.expected_transcript),
            try bridgeWitnessEquivalence(allocator, case),
            lowered.diagnostics.len,
        });
        try writeFeatureFlags(&line.writer, lowered.feature_flags);
        try line.writer.writeByte('}');
        const owned = try line.toOwnedSlice();
        defer allocator.free(owned);
        try list.appendSlice(allocator, owned);
    }
}

fn render(list: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    try list.appendSlice(allocator, "{\n");
    try list.appendSlice(allocator, "  \"scope\": \"lowering_equivalence\",\n");
    try list.appendSlice(allocator, "  \"rows\": [\n");
    var first = true;
    for (source_specs) |spec| try renderSourceRow(list, allocator, spec, &first);
    for (promoted_specs) |spec| try renderSourceRow(list, allocator, spec, &first);
    try renderBridgeRows(list, allocator, &first);
    try list.appendSlice(allocator, "\n  ]\n}\n");
}

/// Render or check the lowering equivalence report artifact.
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
        std.debug.print("lowering equivalence report drift: {s}\n", .{outputPath()});
        return error.LoweringEquivalenceReportDrift;
    }
}
