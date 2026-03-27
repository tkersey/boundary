const bridge_manifest = @import("direct_style_bridge_manifest");
const lowered_machine = @import("lowered_machine");
const parity_scenarios = @import("parity_scenarios");
const program_bridge = @import("program_bridge");
const source_coverage = @import("source_lowering_coverage_registry");
const source_lowering = @import("source_lowering");
const source_registry = @import("source_lowering_registry");
const std = @import("std");

const ReportSpec = struct {
    case_id: []const u8,
    source_path: []const u8,
    entry_symbol: []const u8 = "run",
    surface_kind: source_lowering.SurfaceKind,
};

const WitnessStatus = enum {
    not_applicable,
    supported,
    unsupported,
};

const ProofSpec = struct {
    case_id: []const u8,
    source_path: []const u8,
    entry_symbol: []const u8,
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
    std.debug.print("usage: shift-lowering-admission-report <write|check>\n", .{});
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

fn containsSourceSpec(case_id: []const u8) bool {
    for (source_specs) |spec| {
        if (std.mem.eql(u8, spec.case_id, case_id)) return true;
    }
    return false;
}

fn containsPromotedSpec(case_id: []const u8) bool {
    for (promoted_specs) |spec| {
        if (std.mem.eql(u8, spec.case_id, case_id)) return true;
    }
    return false;
}

fn mappedCoverageCaseId(row: source_coverage.Row) ?[]const u8 {
    if (row.coverage_status != .covered) return null;
    switch (row.category) {
        .example, .user_defined_effect, .witness => return row.coverage_id,
        .built_in_effect => {
            if (std.mem.eql(u8, row.coverage_id, "built_in.state")) return "effect.state_basic";
            if (std.mem.eql(u8, row.coverage_id, "built_in.reader")) return "effect.reader_basic";
            if (std.mem.eql(u8, row.coverage_id, "built_in.optional")) return "effect.optional_basic";
            if (std.mem.eql(u8, row.coverage_id, "built_in.exception")) return "effect.exception_basic";
            if (std.mem.eql(u8, row.coverage_id, "built_in.resource")) return "effect.resource_basic";
            if (std.mem.eql(u8, row.coverage_id, "built_in.writer")) return "effect.writer_basic";
            return null;
        },
    }
}

fn isExpectedPromotedCaseId(case_id: []const u8) bool {
    for (source_coverage.rows) |row| {
        const mapped = mappedCoverageCaseId(row) orelse continue;
        if (std.mem.eql(u8, mapped, case_id)) return true;
    }
    return false;
}

fn verifyReportSpecCoverage() !void {
    for (source_registry.cases) |case| {
        if (containsSourceSpec(case.case_id)) continue;
        std.debug.print("lowering admission report missing source row: {s}\n", .{case.case_id});
        return error.MissingSourceAdmissionRow;
    }
    for (source_specs) |spec| {
        if (source_registry.find(spec.case_id) != null) continue;
        std.debug.print("lowering admission report includes unknown source row: {s}\n", .{spec.case_id});
        return error.UnknownSourceAdmissionRow;
    }

    for (source_coverage.rows) |row| {
        const mapped = mappedCoverageCaseId(row) orelse continue;
        if (containsPromotedSpec(mapped)) continue;
        std.debug.print("lowering admission report missing covered row: {s}\n", .{mapped});
        return error.MissingCoveredAdmissionRow;
    }
    for (promoted_specs) |spec| {
        if (isExpectedPromotedCaseId(spec.case_id)) continue;
        std.debug.print("lowering admission report includes untracked covered row: {s}\n", .{spec.case_id});
        return error.UnknownCoveredAdmissionRow;
    }
}

fn bridgeProofSpec(allocator: std.mem.Allocator, case: bridge_manifest.Case) !?ProofSpec {
    switch (case.source_kind) {
        .witness => return .{
            .case_id = try std.fmt.allocPrint(allocator, "witness.{s}", .{case.case_id}),
            .source_path = "src/witness_sources.zig",
            .entry_symbol = case.entry_symbol,
            .surface_kind = .witness,
        },
        .example => {
            if (std.mem.eql(u8, case.case_id, "generator")) {
                return .{
                    .case_id = try allocator.dupe(u8, "witness.generator"),
                    .source_path = "src/witness_sources.zig",
                    .entry_symbol = "runGenerator",
                    .surface_kind = .witness,
                };
            }
            return .{
                .case_id = try std.fmt.allocPrint(allocator, "example.{s}", .{case.case_id}),
                .source_path = case.source_module,
                .entry_symbol = case.entry_symbol,
                .surface_kind = .example,
            };
        },
    }
}

fn witnessStatus(lowered: *const source_lowering.GeneratedProgram) WitnessStatus {
    if (!lowered.isAccepted()) return .unsupported;
    if (lowered.error_witness.support_status != .supported) return .unsupported;
    if (lowered.error_witness.diagnostics.len != 0) return .unsupported;
    return .supported;
}

fn bridgeWitnessStatus(allocator: std.mem.Allocator, case: bridge_manifest.Case) !WitnessStatus {
    const proof = try bridgeProofSpec(allocator, case) orelse return .not_applicable;
    defer allocator.free(proof.case_id);

    var lowered = try source_lowering.inspectSource(allocator, .{
        .case_id = proof.case_id,
        .source_path = proof.source_path,
        .entry_symbol = proof.entry_symbol,
        .surface_kind = proof.surface_kind,
    });
    defer lowered.deinit(allocator);
    return witnessStatus(&lowered);
}

fn bridgeRowWitnessStatus(
    allocator: std.mem.Allocator,
    case: bridge_manifest.Case,
    lowered: anytype,
) !WitnessStatus {
    return switch (case.source_kind) {
        .witness => if (lowered.status == .rejected) .unsupported else try bridgeWitnessStatus(allocator, case),
        .example => try bridgeWitnessStatus(allocator, case),
    };
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
    try line.writer.print(",\"lower_status\":\"{s}\",\"canonical_replay_matches_expected\":{},\"error_witness_status\":\"{s}\",\"diagnostic_count\":{},\"feature_flags\":", .{
        @tagName(lowered.status),
        std.mem.eql(u8, transcript_writer.buffered(), scenario.expected_transcript),
        @tagName(witnessStatus(&lowered)),
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
        try line.writer.print(",\"lower_status\":\"{s}\",\"canonical_replay_matches_expected\":{},\"error_witness_status\":\"{s}\",\"diagnostic_count\":{},\"feature_flags\":", .{
            @tagName(lowered.status),
            std.mem.eql(u8, transcript_writer.buffered(), scenario.expected_transcript),
            @tagName(try bridgeRowWitnessStatus(allocator, case, &lowered)),
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
    try verifyReportSpecCoverage();
    try list.appendSlice(allocator, "{\n");
    try list.appendSlice(allocator, "  \"scope\": \"lowering_admission_replay\",\n");
    try list.appendSlice(allocator, "  \"rows\": [\n");
    var first = true;
    for (source_specs) |spec| try renderSourceRow(list, allocator, spec, &first);
    for (promoted_specs) |spec| try renderSourceRow(list, allocator, spec, &first);
    try renderBridgeRows(list, allocator, &first);
    try list.appendSlice(allocator, "\n  ]\n}\n");
}

/// Render or check the legacy-named lowering admission report artifact.
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
        std.debug.print("lowering admission report drift: {s}\n", .{outputPath()});
        return error.LoweringAdmissionReportDrift;
    }
}
