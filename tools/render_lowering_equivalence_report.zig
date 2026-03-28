const bridge_manifest = @import("direct_style_bridge_manifest");
const lowered_machine = @import("lowered_machine");
const parity_scenarios = @import("parity_scenarios");
const program_bridge = @import("program_bridge");
const source_coverage = @import("source_lowering_coverage_registry");
const source_lowering = @import("source_lowering");
const source_registry = @import("source_lowering_registry");
const std = @import("std");

const WitnessStatus = enum {
    not_applicable,
    supported,
    unsupported,
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

fn surfaceKind(surface: anytype) source_lowering.SurfaceKind {
    return std.meta.stringToEnum(source_lowering.SurfaceKind, @tagName(surface)).?;
}

fn verifyRegistryTruth() !void {
    for (source_registry.cases) |case| {
        const kernel = source_registry.loweringKernelCase(case);
        if (source_coverage.findLoweringKernelCase(kernel.case_id) != null) {
            std.debug.print("lowering admission report overlaps source and coverage kernel rows: {s}\n", .{kernel.case_id});
            return error.OverlappingLoweringKernelRow;
        }
    }

    for (source_coverage.rows, 0..) |row, idx| {
        const kernel = row.lowering_kernel orelse continue;
        if (row.coverage_status != .covered) {
            std.debug.print("lowering admission report includes uncovered kernel row: {s}\n", .{kernel.case_id});
            return error.UncoveredLoweringKernelRow;
        }
        if (row.lowering_rank == null) {
            std.debug.print("lowering admission report includes unranked kernel row: {s}\n", .{kernel.case_id});
            return error.UnrankedLoweringKernelRow;
        }
        for (source_coverage.rows[(idx + 1)..]) |other| {
            const other_kernel = other.lowering_kernel orelse continue;
            if (std.mem.eql(u8, kernel.case_id, other_kernel.case_id)) {
                std.debug.print("lowering admission report includes duplicate coverage kernel row: {s}\n", .{kernel.case_id});
                return error.DuplicateCoverageKernelRow;
            }
            if (row.lowering_rank == other.lowering_rank) {
                std.debug.print("lowering admission report includes duplicate coverage kernel rank: {}\n", .{row.lowering_rank.?});
                return error.DuplicateCoverageKernelRank;
            }
        }
    }
}

fn bridgeProofCase(allocator: std.mem.Allocator, case: bridge_manifest.Case) !?source_registry.KernelCase {
    switch (case.source_kind) {
        .witness => return .{
            .case_id = try std.fmt.allocPrint(allocator, "witness.{s}", .{case.case_id}),
            .source_path = "src/witness_sources.zig",
            .entry_symbol = case.entry_symbol,
            .surface = .witness,
        },
        .example => {
            if (std.mem.eql(u8, case.case_id, "open_row_generator")) {
                return .{
                    .case_id = try allocator.dupe(u8, "witness.generator"),
                    .source_path = "src/witness_sources.zig",
                    .entry_symbol = "runGenerator",
                    .surface = .witness,
                };
            }
            return .{
                .case_id = try std.fmt.allocPrint(allocator, "example.{s}", .{case.case_id}),
                .source_path = case.source_module,
                .entry_symbol = case.entry_symbol,
                .surface = .example,
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
    const proof = try bridgeProofCase(allocator, case) orelse return .not_applicable;
    defer allocator.free(proof.case_id);

    var lowered = try source_lowering.inspectSource(allocator, .{
        .case_id = proof.case_id,
        .source_path = proof.source_path,
        .entry_symbol = proof.entry_symbol,
        .surface_kind = surfaceKind(proof.surface),
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

fn renderKernelRow(list: *std.ArrayList(u8), allocator: std.mem.Allocator, kernel: anytype, first: *bool) !void {
    const kind = surfaceKind(kernel.surface);
    var lowered = try source_lowering.inspectSource(allocator, .{
        .case_id = kernel.case_id,
        .source_path = kernel.source_path,
        .entry_symbol = kernel.entry_symbol,
        .surface_kind = kind,
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
    try writeJsonString(&line.writer, kernel.case_id);
    try line.writer.writeAll(",\"surface_kind\":");
    try writeJsonString(&line.writer, @tagName(kind));
    try line.writer.writeAll(",\"source_path\":");
    try writeJsonString(&line.writer, kernel.source_path);
    try line.writer.writeAll(",\"entry_symbol\":");
    try writeJsonString(&line.writer, kernel.entry_symbol);
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
    try verifyRegistryTruth();
    try list.appendSlice(allocator, "{\n");
    try list.appendSlice(allocator, "  \"scope\": \"lowering_admission_replay\",\n");
    try list.appendSlice(allocator, "  \"rows\": [\n");
    var first = true;
    for (source_registry.cases) |case| {
        try renderKernelRow(list, allocator, source_registry.loweringKernelCase(case), &first);
    }
    for (0..source_coverage.rows.len) |rank| {
        const kernel = source_coverage.findLoweringKernelByRank(@intCast(rank)) orelse continue;
        try renderKernelRow(list, allocator, kernel, &first);
    }
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
