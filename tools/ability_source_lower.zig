const builtin = @import("builtin");
const error_witness = @import("error_witness");
const lowered_machine = @import("lowered_machine");
const source_lowering = @import("source_lowering");
const std = @import("std");
const tool_build_options = @import("tool_build_options");

const EmitMode = enum {
    json,
    zig,
};

const usage_text = "usage: ability-source-lower --id <source.case> --source <path> --entry <symbol> --surface <source_case|example|effect|user_defined_effect|witness> --emit <json|zig> --out <path>\n";
const expected_flag_value_pair_count = 6;
const expected_arg_count = 1 + expected_flag_value_pair_count * 2;
const generated_output_roots = [_][]const u8{
    "zig-out",
    ".zig-cache",
    "zig-cache",
};

const CliShapeIssue = union(enum) {
    missing_value: []const u8,
    unexpected_arg_count: usize,
    unknown_flag: []const u8,
};

const ParsedCliOptions = struct {
    program_id: ?[]const u8 = null,
    source_path: ?[]const u8 = null,
    entry_symbol: ?[]const u8 = null,
    surface_kind: ?source_lowering.SurfaceKind = null,
    emit_mode: ?EmitMode = null,
    output_path: ?[]const u8 = null,
};

const RequiredCliOptions = struct {
    program_id: []const u8,
    source_path: []const u8,
    entry_symbol: []const u8,
    surface_kind: source_lowering.SurfaceKind,
    emit_mode: EmitMode,
    output_path: []const u8,
};

const MissingRequiredFlag = enum {
    emit,
    entry,
    flag_id,
    out,
    source,
    surface,
};

const RequiredCliOptionsResult = union(enum) {
    config: RequiredCliOptions,
    missing: MissingRequiredFlag,
};

fn usage() noreturn {
    std.debug.print(usage_text, .{});
    std.process.exit(1);
}

fn usageError(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print("ability-source-lower: " ++ fmt ++ "\n", args);
    usage();
}

fn writeUsage(writer: anytype) !void {
    try writer.writeAll(usage_text);
}

fn isKnownFlag(flag: []const u8) bool {
    return std.mem.eql(u8, flag, "--id") or
        std.mem.eql(u8, flag, "--source") or
        std.mem.eql(u8, flag, "--entry") or
        std.mem.eql(u8, flag, "--surface") or
        std.mem.eql(u8, flag, "--emit") or
        std.mem.eql(u8, flag, "--out");
}

fn cliShapeIssue(args: []const []const u8) ?CliShapeIssue {
    var idx: usize = 1;
    while (idx < args.len) : (idx += 2) {
        const flag = args[idx];
        if (!isKnownFlag(flag)) return .{ .unknown_flag = flag };
        if (idx + 1 >= args.len) return .{ .missing_value = flag };
    }
    if (args.len > expected_arg_count) return .{ .unexpected_arg_count = args.len - 1 };
    return null;
}

fn requiredCliOptions(options: ParsedCliOptions) RequiredCliOptionsResult {
    const program_id = options.program_id orelse return .{ .missing = .flag_id };
    const source_path = options.source_path orelse return .{ .missing = .source };
    const entry_symbol = options.entry_symbol orelse return .{ .missing = .entry };
    const surface_kind = options.surface_kind orelse return .{ .missing = .surface };
    const emit_mode = options.emit_mode orelse return .{ .missing = .emit };
    const output_path = options.output_path orelse return .{ .missing = .out };

    return .{ .config = .{
        .program_id = program_id,
        .source_path = source_path,
        .entry_symbol = entry_symbol,
        .surface_kind = surface_kind,
        .emit_mode = emit_mode,
        .output_path = output_path,
    } };
}

fn missingRequiredFlagName(flag: MissingRequiredFlag) []const u8 {
    return switch (flag) {
        .emit => "--emit",
        .entry => "--entry",
        .flag_id => "--id",
        .out => "--out",
        .source => "--source",
        .surface => "--surface",
    };
}

fn missingRequiredFlag(flag: MissingRequiredFlag) noreturn {
    usageError("missing required {s}", .{missingRequiredFlagName(flag)});
}

fn parseSurface(value: []const u8) ?source_lowering.SurfaceKind {
    if (std.mem.eql(u8, value, "source_case")) return .source_case;
    if (std.mem.eql(u8, value, "example")) return .example;
    if (std.mem.eql(u8, value, "effect")) return .effect;
    if (std.mem.eql(u8, value, "user_defined_effect")) return .user_defined_effect;
    if (std.mem.eql(u8, value, "witness")) return .witness;
    return null;
}

fn parseEmit(value: []const u8) ?EmitMode {
    if (std.mem.eql(u8, value, "json")) return .json;
    if (std.mem.eql(u8, value, "zig")) return .zig;
    return null;
}

fn pathIsAbsoluteCrossPlatform(path: []const u8) bool {
    if (std.Io.Dir.path.isAbsolute(path)) return true;
    if (std.mem.startsWith(u8, path, "/") or std.mem.startsWith(u8, path, "\\")) return true;
    return path.len >= 3 and
        std.ascii.isAlphabetic(path[0]) and
        path[1] == ':' and
        (path[2] == '/' or path[2] == '\\');
}

fn generatedOutputPathAllowed(path: []const u8) bool {
    if (path.len == 0 or pathIsAbsoluteCrossPlatform(path)) return false;
    if (generatedOutputRoot(path) == null) return false;

    var start: usize = 0;
    var index: usize = 0;
    while (index <= path.len) : (index += 1) {
        if (index != path.len and path[index] != '/' and path[index] != '\\') continue;
        const segment = path[start..index];
        start = index + 1;
        if (segment.len == 0 or std.mem.eql(u8, segment, ".") or std.mem.eql(u8, segment, "..")) return false;
    }
    return true;
}

fn generatedOutputRoot(path: []const u8) ?[]const u8 {
    for (generated_output_roots) |root| {
        if (path.len > root.len and
            std.mem.startsWith(u8, path, root) and
            isPathSeparator(path[root.len]))
        {
            return root;
        }
    }
    return null;
}

fn isPathSeparator(byte: u8) bool {
    return byte == '/' or byte == '\\';
}

fn containsPathSeparator(path: []const u8) bool {
    for (path) |byte| {
        if (isPathSeparator(byte)) return true;
    }
    return false;
}

fn lastPathSeparatorIndex(path: []const u8) ?usize {
    var index = path.len;
    while (index > 0) {
        index -= 1;
        if (isPathSeparator(path[index])) return index;
    }
    return null;
}

fn generatedOutputRootBound(allocator: std.mem.Allocator, io: std.Io, package_root: []const u8, path: []const u8) !bool {
    const root = generatedOutputRoot(path) orelse return false;
    var package_dir = std.Io.Dir.openDirAbsolute(io, package_root, .{}) catch return false;
    defer package_dir.close(io);
    package_dir.createDirPath(io, root) catch return false;

    const root_real = package_dir.realPathFileAlloc(io, root, allocator) catch return false;
    defer allocator.free(root_real);
    const package_root_real = std.Io.Dir.realPathFileAbsoluteAlloc(io, package_root, allocator) catch return false;
    defer allocator.free(package_root_real);
    const expected_root = try std.Io.Dir.path.join(allocator, &.{ package_root_real, root });
    defer allocator.free(expected_root);
    return std.mem.eql(u8, root_real, expected_root);
}

const BoundOutputPath = struct {
    dir: std.Io.Dir,
    io: std.Io,
    basename: []const u8,

    fn close(self: *BoundOutputPath) void {
        self.dir.close(self.io);
    }
};

fn bindGeneratedOutputPath(io: std.Io, package_root: []const u8, path: []const u8) !BoundOutputPath {
    const root = generatedOutputRoot(path) orelse return error.BadPathName;
    const file_separator = lastPathSeparatorIndex(path) orelse return error.BadPathName;
    if (file_separator < root.len) return error.BadPathName;

    const basename = path[file_separator + 1 ..];
    if (basename.len == 0 or containsPathSeparator(basename)) return error.BadPathName;

    var current = current: {
        var package_dir = try std.Io.Dir.openDirAbsolute(io, package_root, .{});
        defer package_dir.close(io);
        break :current try package_dir.openDir(io, root, .{ .follow_symlinks = false });
    };
    errdefer current.close(io);

    var segment_start: usize = root.len + 1;
    while (segment_start < file_separator) {
        var segment_end = segment_start;
        while (segment_end < file_separator and !isPathSeparator(path[segment_end])) : (segment_end += 1) {}

        const segment = path[segment_start..segment_end];
        const next = try current.openDir(io, segment, .{ .follow_symlinks = false });
        current.close(io);
        current = next;
        segment_start = segment_end + 1;
    }

    return .{
        .dir = current,
        .io = io,
        .basename = basename,
    };
}

fn writeZigStringLiteral(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    try std.zig.stringEscape(value, writer);
    try writer.writeByte('"');
}

fn writeJsonStringLiteral(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |byte| switch (byte) {
        '"' => try writer.writeAll("\\\""),
        '\\' => try writer.writeAll("\\\\"),
        '\x08' => try writer.writeAll("\\b"),
        '\x0c' => try writer.writeAll("\\f"),
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        '\t' => try writer.writeAll("\\t"),
        0...7, 11, 14...0x1f => try writer.print("\\u00{x:0>2}", .{byte}),
        else => try writer.writeByte(byte),
    };
    try writer.writeByte('"');
}

fn writeJsonStringArray(writer: anytype, values: []const []const u8) !void {
    try writer.writeByte('[');
    for (values, 0..) |value, idx| {
        if (idx != 0) try writer.writeAll(",");
        try writeJsonStringLiteral(writer, value);
    }
    try writer.writeByte(']');
}

fn writeJsonWitnessDiagnostics(writer: anytype, diagnostics: anytype) !void {
    try writer.writeByte('[');
    for (diagnostics, 0..) |diag, idx| {
        if (idx != 0) try writer.writeAll(",");
        try writer.writeAll("{\"code\":");
        try writeJsonStringLiteral(writer, diag.code);
        try writer.writeAll(",\"message\":");
        try writeJsonStringLiteral(writer, diag.message);
        try writer.writeAll(",\"path\":");
        try writeJsonStringLiteral(writer, diag.path);
        try writer.print(",\"line\":{d},\"column\":{d}}}", .{ diag.line, diag.column });
    }
    try writer.writeByte(']');
}

fn writeJsonContributors(writer: anytype, contributors: anytype) !void {
    try writer.writeByte('[');
    for (contributors, 0..) |contributor, idx| {
        if (idx != 0) try writer.writeAll(",");
        try writer.writeAll("{\"kind\":");
        try writeJsonStringLiteral(writer, @tagName(contributor.kind));
        try writer.writeAll(",\"surface\":");
        try writeJsonStringLiteral(writer, @tagName(contributor.surface));
        try writer.writeAll(",\"symbol\":");
        try writeJsonStringLiteral(writer, contributor.symbol);
        try writer.writeAll(",\"error_names\":");
        try writeJsonStringArray(writer, contributor.error_names);
        try writer.writeByte('}');
    }
    try writer.writeByte(']');
}

fn writeRejectedProgramDiagnostics(writer: anytype, program: source_lowering.GeneratedProgram) !void {
    if (program.diagnostics.len == 0) {
        try writer.print(
            "ability-source-lower: rejected {s}: no source diagnostic was emitted\n",
            .{program.case_id},
        );
        return;
    }
    for (program.diagnostics) |diagnostic| {
        try writer.print(
            "ability-source-lower: {s}:{d}:{d}: {s}: {s}\n",
            .{
                diagnostic.path,
                diagnostic.line,
                diagnostic.column,
                diagnostic.code,
                diagnostic.message,
            },
        );
    }
}

fn deleteRejectedProgramOutput(dir: std.Io.Dir, io: std.Io, out_path: []const u8) !void {
    dir.deleteFile(io, out_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
}

fn writeJsonKernelProgramArtifact(
    writer: anytype,
    artifact: source_lowering.KernelProgramArtifact,
) !void {
    try writer.writeAll("{\"executable\":");
    try writer.writeAll(if (artifact.isExecutable()) "true" else "false");
    try writer.writeAll(",\"canonical_scenario_id\":");
    if (artifact.canonical_scenario_id) |id| {
        try writeJsonStringLiteral(writer, @tagName(id));
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"expected_transcript\":");
    try writeJsonStringLiteral(writer, artifact.expected_transcript);
    try writer.writeAll(",\"step_count\":");
    try writer.print("{d}", .{artifact.steps.len});
    try writer.writeByte('}');
}

fn writeZigStringArray(writer: anytype, values: []const []const u8) !void {
    try writer.writeAll("&.{");
    for (values, 0..) |value, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try writeZigStringLiteral(writer, value);
    }
    try writer.writeByte('}');
}

fn writeZigContributors(writer: anytype, contributors: anytype) !void {
    try writer.writeAll("&.{");
    for (contributors, 0..) |contributor, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try writer.writeAll(".{ .kind = .");
        try writer.writeAll(@tagName(contributor.kind));
        try writer.writeAll(", .surface = .");
        try writer.writeAll(@tagName(contributor.surface));
        try writer.writeAll(", .symbol = ");
        try writeZigStringLiteral(writer, contributor.symbol);
        try writer.writeAll(", .error_names = ");
        try writeZigStringArray(writer, contributor.error_names);
        try writer.writeByte('}');
    }
    try writer.writeByte('}');
}

fn writeJson(program: source_lowering.GeneratedProgram, writer: anytype) !void {
    const artifact = program.kernelProgramArtifact();
    try writer.writeAll("{\"case_id\":");
    try writeJsonStringLiteral(writer, program.case_id);
    try writer.writeAll(",\"surface_kind\":");
    try writeJsonStringLiteral(writer, @tagName(program.surface_kind));
    try writer.writeAll(",\"status\":");
    try writeJsonStringLiteral(writer, @tagName(artifact.status));
    try writer.writeAll(",\"canonical_scenario_id\":");
    if (artifact.canonical_scenario_id) |id| {
        try writeJsonStringLiteral(writer, @tagName(id));
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"feature_flags\":[");
    for (artifact.feature_flags, 0..) |flag, idx| {
        if (idx != 0) try writer.writeAll(",");
        try writeJsonStringLiteral(writer, flag);
    }
    try writer.writeAll("],\"kernel_program_artifact\":");
    try writeJsonKernelProgramArtifact(writer, artifact);
    try writer.writeAll(",\"error_witness\":{");
    try writer.print("\"schema_version\":{d},\"surface\":\"{s}\",\"support_status\":\"{s}\",", .{
        program.error_witness.schema_version,
        @tagName(program.error_witness.surface),
        @tagName(program.error_witness.support_status),
    });
    try writer.writeAll("\"public_runtime_errors\":[");
    for (program.error_witness.public_runtime_errors, 0..) |tag, idx| {
        if (idx != 0) try writer.writeAll(",");
        try writeJsonStringLiteral(writer, error_witness.runtimeErrorTagName(tag));
    }
    try writer.writeAll("],\"setup_error_names\":");
    try writeJsonStringArray(writer, program.error_witness.setup_error_names);
    try writer.writeAll(",\"semantic_error_names\":");
    try writeJsonStringArray(writer, program.error_witness.semantic_error_names);
    try writer.writeAll(",\"contributors\":");
    try writeJsonContributors(writer, program.error_witness.contributors);
    try writer.writeAll(",\"diagnostics\":");
    try writeJsonWitnessDiagnostics(writer, program.error_witness.diagnostics);
    try writer.writeAll("},\"diagnostics\":[");
    for (program.diagnostics, 0..) |diag, idx| {
        if (idx != 0) try writer.writeAll(",");
        try writer.writeAll("{\"code\":");
        try writeJsonStringLiteral(writer, diag.code);
        try writer.writeAll(",\"message\":");
        try writeJsonStringLiteral(writer, diag.message);
        try writer.writeAll(",\"path\":");
        try writeJsonStringLiteral(writer, diag.path);
        try writer.print(",\"line\":{d},\"column\":{d}}}", .{ diag.line, diag.column });
    }
    try writer.writeAll("]}\n");
}

fn writeStepLiteral(writer: anytype, step: lowered_machine.Step) !void {
    switch (step) {
        .checkpoint => |tag| try writer.print("    .{{ .checkpoint = .{s} }},\n", .{@tagName(tag)}),
        .emit => |event| switch (event) {
            .note => |line| {
                try writer.writeAll("    .{ .emit = .{ .note = ");
                try writeZigStringLiteral(writer, line);
                try writer.writeAll(" } },\n");
            },
            .final_i32 => |value| try writer.print("    .{{ .emit = .{{ .final_i32 = {d} }} }},\n", .{value}),
            .final_string => |value| {
                try writer.writeAll("    .{ .emit = .{ .final_string = ");
                try writeZigStringLiteral(writer, value);
                try writer.writeAll(" } },\n");
            },
        },
        .pop_pending => try writer.writeAll("    .pop_pending,\n"),
        .push_pending => |frame| {
            try writer.print(
                "    .{{ .push_pending = .{{ .kind = .{s}, .prompt = .{s}, .resume_value = ",
                .{ @tagName(frame.kind), @tagName(frame.prompt) },
            );
            switch (frame.resume_value) {
                .none => try writer.writeAll(".none"),
                .bool => |value| try writer.print(".{{ .bool = {} }}", .{value}),
                .i32 => |value| try writer.print(".{{ .i32 = {d} }}", .{value}),
                .string => |value| {
                    try writer.writeAll(".{ .string = ");
                    try writeZigStringLiteral(writer, value);
                    try writer.writeByte('}');
                },
            }
            try writer.writeAll(" } },\n");
        },
        .set_active_prompt => |prompt| {
            if (prompt) |value| {
                try writer.print("    .{{ .set_active_prompt = .{s} }},\n", .{@tagName(value)});
            } else {
                try writer.writeAll("    .{ .set_active_prompt = null },\n");
            }
        },
        .set_final => |value| switch (value) {
            .none => try writer.writeAll("    .{ .set_final = .none },\n"),
            .bool => |typed| try writer.print("    .{{ .set_final = .{{ .bool = {} }} }},\n", .{typed}),
            .i32 => |typed| try writer.print("    .{{ .set_final = .{{ .i32 = {d} }} }},\n", .{typed}),
            .string => |typed| {
                try writer.writeAll("    .{ .set_final = .{ .string = ");
                try writeZigStringLiteral(writer, typed);
                try writer.writeAll(" } },\n");
            },
        },
    }
}

fn writeZig(program: source_lowering.GeneratedProgram, writer: anytype) !void {
    const artifact = program.kernelProgramArtifact();
    try writer.writeAll(
        "const source_lowering = @import(\"source_lowering\");\n" ++
            "const std = @import(\"std\");\n\n" ++
            "// Executable kernel program artifact emitted by ability-source-lower.\n\n",
    );
    try writer.writeAll("const generated_program_steps = [_]source_lowering.Step{\n");
    for (artifact.steps) |step| try writeStepLiteral(writer, step);
    try writer.writeAll("};\n");
    try writer.writeAll("\nconst generated_program_feature_flags = [_][]const u8{");
    for (artifact.feature_flags, 0..) |flag, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try writeZigStringLiteral(writer, flag);
    }
    try writer.writeAll("};\n");
    try writer.writeAll("\nconst generated_program_diagnostics = [_]source_lowering.Diagnostic{");
    for (program.diagnostics, 0..) |diag, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try writer.writeAll(".{ .code = ");
        try writeZigStringLiteral(writer, diag.code);
        try writer.writeAll(", .message = ");
        try writeZigStringLiteral(writer, diag.message);
        try writer.writeAll(", .path = ");
        try writeZigStringLiteral(writer, diag.path);
        try writer.print(", .line = {d}, .column = {d} }}", .{ diag.line, diag.column });
    }
    try writer.writeAll("};\n\n");
    try writer.writeAll("const WitnessDiagnostic = @typeInfo(@TypeOf((@as(source_lowering.GeneratedProgram, undefined)).error_witness.diagnostics)).pointer.child;\n");
    try writer.writeAll("const generated_program_witness_diagnostics = [_]WitnessDiagnostic{");
    for (program.error_witness.diagnostics, 0..) |diag, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try writer.writeAll(".{ .code = ");
        try writeZigStringLiteral(writer, diag.code);
        try writer.writeAll(", .message = ");
        try writeZigStringLiteral(writer, diag.message);
        try writer.writeAll(", .path = ");
        try writeZigStringLiteral(writer, diag.path);
        try writer.print(", .line = {d}, .column = {d} }}", .{ diag.line, diag.column });
    }
    try writer.writeAll("};\n\n");
    try writer.writeAll("pub fn initGeneratedProgram(allocator: std.mem.Allocator) !source_lowering.GeneratedProgram {\n");
    try writer.writeAll("    const source_path = try allocator.dupe(u8, ");
    try writeZigStringLiteral(writer, program.source_path);
    try writer.writeAll(");\n");
    try writer.writeAll("    errdefer allocator.free(source_path);\n");
    try writer.writeAll("    const steps = try allocator.dupe(source_lowering.Step, &generated_program_steps);\n");
    try writer.writeAll("    errdefer allocator.free(steps);\n");
    try writer.writeAll("    const feature_flags = try allocator.dupe([]const u8, &generated_program_feature_flags);\n");
    try writer.writeAll("    errdefer allocator.free(feature_flags);\n");
    try writer.writeAll("    const diagnostics = try allocator.dupe(source_lowering.Diagnostic, &generated_program_diagnostics);\n");
    try writer.writeAll("    errdefer allocator.free(diagnostics);\n");
    try writer.writeAll("    const witness_diagnostics: []const WitnessDiagnostic = if (generated_program_witness_diagnostics.len == 0)\n");
    try writer.writeAll("        &.{}\n");
    try writer.writeAll("    else\n");
    try writer.writeAll("        try allocator.dupe(WitnessDiagnostic, &generated_program_witness_diagnostics);\n");
    try writer.writeAll("    errdefer if (witness_diagnostics.len != 0) allocator.free(witness_diagnostics);\n\n");
    try writer.writeAll("    return .{\n");
    try writer.writeAll("        .case_id = ");
    try writeZigStringLiteral(writer, program.case_id);
    try writer.writeAll(",\n");
    try writer.writeAll("        .label = ");
    try writeZigStringLiteral(writer, program.label);
    try writer.writeAll(",\n");
    try writer.writeAll("        .source_path = source_path,\n");
    try writer.print("        .surface_kind = .{s},\n", .{@tagName(program.surface_kind)});
    try writer.print("        .status = .{s},\n", .{@tagName(artifact.status)});
    if (artifact.canonical_scenario_id) |id| {
        try writer.print("        .canonical_scenario_id = .{s},\n", .{@tagName(id)});
    } else {
        try writer.writeAll("        .canonical_scenario_id = null,\n");
    }
    try writer.writeAll("        .expected_transcript = ");
    try writeZigStringLiteral(writer, artifact.expected_transcript);
    try writer.writeAll(",\n");
    try writer.writeAll("        .steps = steps,\n");
    try writer.writeAll("        .feature_flags = feature_flags,\n");
    try writer.writeAll("        .diagnostics = diagnostics,\n");
    try writer.print("        .error_witness = .{{ .schema_version = {d}, .surface = .{s}, .support_status = .{s}, .public_runtime_errors = &.{{", .{
        program.error_witness.schema_version,
        @tagName(program.error_witness.surface),
        @tagName(program.error_witness.support_status),
    });
    for (program.error_witness.public_runtime_errors) |tag| {
        try writer.print(".{s},", .{@tagName(tag)});
    }
    try writer.writeAll("}, .setup_error_names = ");
    try writeZigStringArray(writer, program.error_witness.setup_error_names);
    try writer.writeAll(", .semantic_error_names = ");
    try writeZigStringArray(writer, program.error_witness.semantic_error_names);
    try writer.writeAll(", .contributors = ");
    try writeZigContributors(writer, program.error_witness.contributors);
    try writer.writeAll(", .diagnostics = witness_diagnostics");
    try writer.writeAll(" },\n");
    try writer.writeAll("    };\n");
    try writer.writeAll("}\n\n");
    try writer.writeAll(
        "pub fn runLowered(writer: anytype) !void {\n" ++
            "    const allocator = std.heap.page_allocator;\n" ++
            "    var generated_program = try initGeneratedProgram(allocator);\n" ++
            "    defer generated_program.deinit(allocator);\n" ++
            "    try source_lowering.runLowered(writer, &generated_program);\n" ++
            "}\n",
    );
}

const OutputWriteSpec = struct {
    dir: std.Io.Dir,
    io: std.Io,
    allocator: std.mem.Allocator,
    emit_mode: EmitMode,
    out_path: []const u8,
    program: *const source_lowering.GeneratedProgram,
};

fn writeAcceptedProgramOutput(spec: OutputWriteSpec) !void {
    const dir = spec.dir;
    const io = spec.io;
    const allocator = spec.allocator;
    const out_path = spec.out_path;
    const program = spec.program;

    if (containsPathSeparator(out_path)) return error.BadPathName;

    if (!program.isAccepted()) {
        try deleteRejectedProgramOutput(dir, io, out_path);
        return error.RejectedGeneratedProgram;
    }

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    switch (spec.emit_mode) {
        .json => try writeJson(program.*, &output.writer),
        .zig => try writeZig(program.*, &output.writer),
    }
    const bytes = try output.toOwnedSlice();
    defer allocator.free(bytes);
    dir.deleteFile(io, out_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
    try dir.writeFile(io, .{
        .sub_path = out_path,
        .data = bytes,
        .flags = .{ .exclusive = true },
    });
}

/// Build or inspect one internal source-lowering kernel program artifact.
pub fn main(init: std.process.Init) anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try init.minimal.args.toSlice(allocator);
    if (args.len == 2) {
        if (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
            var stdout_buffer: [512]u8 = undefined;
            var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
            const stdout = &stdout_writer.interface;
            try writeUsage(stdout);
            try stdout.flush();
            return;
        }
        if (std.mem.eql(u8, args[1], "--version")) {
            var stdout_buffer: [64]u8 = undefined;
            var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
            const stdout = &stdout_writer.interface;
            try stdout.print("ability-source-lower {s}\n", .{tool_build_options.version});
            try stdout.flush();
            return;
        }
    }
    if (cliShapeIssue(args)) |issue| {
        switch (issue) {
            .missing_value => |flag| usageError("missing value for flag '{s}'", .{flag}),
            .unexpected_arg_count => |count| usageError("expected exactly six flag/value pairs, got {d} argument(s)", .{count}),
            .unknown_flag => |flag| usageError("unknown flag '{s}'", .{flag}),
        }
    }

    var parsed: ParsedCliOptions = .{};

    var idx: usize = 1;
    while (idx < args.len) : (idx += 2) {
        const flag = args[idx];
        const value = args[idx + 1];
        if (std.mem.eql(u8, flag, "--id")) {
            parsed.program_id = value;
        } else if (std.mem.eql(u8, flag, "--source")) {
            parsed.source_path = value;
        } else if (std.mem.eql(u8, flag, "--entry")) {
            parsed.entry_symbol = value;
        } else if (std.mem.eql(u8, flag, "--surface")) {
            parsed.surface_kind = parseSurface(value) orelse usageError("unsupported --surface value '{s}'", .{value});
        } else if (std.mem.eql(u8, flag, "--emit")) {
            parsed.emit_mode = parseEmit(value) orelse usageError("unsupported --emit value '{s}'", .{value});
        } else if (std.mem.eql(u8, flag, "--out")) {
            parsed.output_path = value;
        } else {
            usageError("unknown flag '{s}'", .{flag});
        }
    }

    const cli_options = switch (requiredCliOptions(parsed)) {
        .config => |config| config,
        .missing => |flag| missingRequiredFlag(flag),
    };

    const output_path = cli_options.output_path;
    if (!generatedOutputPathAllowed(output_path)) {
        usageError("--out must be a generated relative path under zig-out/, .zig-cache/, or zig-cache/: '{s}'", .{output_path});
    }
    if (!(try generatedOutputRootBound(allocator, init.io, tool_build_options.package_root, output_path))) {
        usageError("--out generated root must be a real directory owned by the current checkout: '{s}'", .{output_path});
    }
    var bound_output_path = bindGeneratedOutputPath(init.io, tool_build_options.package_root, output_path) catch |err| {
        switch (err) {
            error.FileNotFound => usageError("--out parent directory does not exist under generated root: '{s}'", .{output_path}),
            error.BadPathName => usageError("--out parent path must stay inside real generated directories: '{s}'", .{output_path}),
            else => usageError("--out parent path could not be opened ({s}): '{s}'", .{ @errorName(err), output_path }),
        }
    };
    defer bound_output_path.close();

    var program = try source_lowering.inspectSource(allocator, .{
        .case_id = cli_options.program_id,
        .source_path = cli_options.source_path,
        .entry_symbol = cli_options.entry_symbol,
        .surface_kind = cli_options.surface_kind,
    });
    defer program.deinit(allocator);

    if (!program.isAccepted()) {
        try deleteRejectedProgramOutput(bound_output_path.dir, init.io, bound_output_path.basename);
        var stderr_buffer: [1024]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buffer);
        const stderr = &stderr_writer.interface;
        try writeRejectedProgramDiagnostics(stderr, program);
        try stderr.flush();
        return error.RejectedGeneratedProgram;
    }

    try writeAcceptedProgramOutput(.{
        .dir = bound_output_path.dir,
        .io = init.io,
        .allocator = allocator,
        .emit_mode = cli_options.emit_mode,
        .out_path = bound_output_path.basename,
        .program = &program,
    });
}

test "json output escapes feature flags" {
    const feature_flags = [_][]const u8{ "plain", "quote\"slash\\newline\n" };
    const program = source_lowering.GeneratedProgram{
        .case_id = "source.test",
        .label = "source.test",
        .source_path = "test.zig",
        .surface_kind = .source_case,
        .status = .canonical,
        .canonical_scenario_id = null,
        .expected_transcript = "",
        .steps = &.{},
        .feature_flags = &feature_flags,
        .diagnostics = &.{},
        .error_witness = error_witness.ErrorWitnessV1.empty(.ordinary),
    };

    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try writeJson(program, &output.writer);
    const bytes = try output.toOwnedSlice();
    defer std.testing.allocator.free(bytes);

    try std.testing.expect(std.mem.find(u8, bytes, "\"feature_flags\":[\"plain\",\"quote\\\"slash\\\\newline\\n\"]") != null);
}

test "cli shape reports unknown flags before arity" {
    const args = [_][]const u8{ "ability-source-lower", "--bad-flag" };
    const issue = cliShapeIssue(&args).?;
    try std.testing.expectEqualStrings("--bad-flag", issue.unknown_flag);
}

test "cli shape reports missing values before arity" {
    const args = [_][]const u8{ "ability-source-lower", "--id" };
    const issue = cliShapeIssue(&args).?;
    try std.testing.expectEqualStrings("--id", issue.missing_value);
}

test "cli shape lets missing required flags reach named diagnostics" {
    const args = [_][]const u8{
        "ability-source-lower",
        "--id",
        "source.branch_resume",
        "--source",
        "test/source_lowering_corpus/fixtures/branch_resume.zig",
        "--entry",
        "run",
        "--surface",
        "source_case",
        "--emit",
        "json",
    };
    try std.testing.expectEqual(@as(?CliShapeIssue, null), cliShapeIssue(&args));
}

test "required cli options reports missing emit before output validation" {
    const result = requiredCliOptions(.{
        .program_id = "source.branch_resume",
        .source_path = "test/source_lowering_corpus/fixtures/branch_resume.zig",
        .entry_symbol = "wrong",
        .surface_kind = .source_case,
        .output_path = "zig-out/source-lower/out.json",
    });
    try std.testing.expectEqual(MissingRequiredFlag.emit, result.missing);
}

test "required cli options resolve all required flags before side effects" {
    const result = requiredCliOptions(.{
        .program_id = "source.branch_resume",
        .source_path = "test/source_lowering_corpus/fixtures/branch_resume.zig",
        .entry_symbol = "run",
        .surface_kind = .source_case,
        .emit_mode = .json,
        .output_path = "zig-out/source-lower/out.json",
    });
    const config = result.config;
    try std.testing.expectEqualStrings("source.branch_resume", config.program_id);
    try std.testing.expectEqual(EmitMode.json, config.emit_mode);
    try std.testing.expectEqualStrings("zig-out/source-lower/out.json", config.output_path);
}

test "cli output path guard admits only generated relative paths" {
    try std.testing.expect(generatedOutputPathAllowed("zig-out/source-lower/out.json"));
    try std.testing.expect(generatedOutputPathAllowed("zig-out\\source-lower\\out.json"));
    try std.testing.expect(generatedOutputPathAllowed(".zig-cache/ability-source-lower/out.zig"));
    try std.testing.expect(generatedOutputPathAllowed(".zig-cache\\ability-source-lower\\out.zig"));
    try std.testing.expect(generatedOutputPathAllowed("zig-cache/ability-source-lower/out.zig"));
    try std.testing.expect(generatedOutputPathAllowed("zig-cache\\ability-source-lower\\out.zig"));

    try std.testing.expect(!generatedOutputPathAllowed(""));
    try std.testing.expect(!generatedOutputPathAllowed("out.json"));
    try std.testing.expect(!generatedOutputPathAllowed("README.md"));
    try std.testing.expect(!generatedOutputPathAllowed("/tmp/ability-source-lower.json"));
    try std.testing.expect(!generatedOutputPathAllowed("C:\\tmp\\ability-source-lower.json"));
    try std.testing.expect(!generatedOutputPathAllowed("zig-outsource-lower\\out.json"));
    try std.testing.expect(!generatedOutputPathAllowed("zig-out/../README.md"));
    try std.testing.expect(!generatedOutputPathAllowed("zig-out\\..\\README.md"));
    try std.testing.expect(!generatedOutputPathAllowed("zig-out//out.json"));
    try std.testing.expect(!generatedOutputPathAllowed("zig-out\\\\out.json"));
}

test "cli output root guard rejects symlinked generated root" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const original_cwd = try std.process.currentPathAlloc(std.testing.io, std.testing.allocator);
    defer std.testing.allocator.free(original_cwd);
    const tmp_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_path);

    try tmp.dir.createDirPath(std.testing.io, "outside");
    const outside_path = try tmp.dir.realPathFileAlloc(std.testing.io, "outside", std.testing.allocator);
    defer std.testing.allocator.free(outside_path);
    const link_path = try std.Io.Dir.path.join(std.testing.allocator, &.{ tmp_path, "zig-out" });
    defer std.testing.allocator.free(link_path);
    try std.Io.Dir.symLinkAbsolute(std.testing.io, outside_path, link_path, .{});

    try std.process.setCurrentPath(std.testing.io, tmp_path);
    defer std.process.setCurrentPath(std.testing.io, original_cwd) catch unreachable;

    try std.testing.expect(!try generatedOutputRootBound(
        std.testing.allocator,
        std.testing.io,
        tmp_path,
        "zig-out/source-lower/out.json",
    ));
}

test "cli output path binder accepts native separators under generated roots" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const original_cwd = try std.process.currentPathAlloc(std.testing.io, std.testing.allocator);
    defer std.testing.allocator.free(original_cwd);
    const tmp_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_path);

    try tmp.dir.createDirPath(std.testing.io, "zig-out/source-lower");

    try std.process.setCurrentPath(std.testing.io, tmp_path);
    defer std.process.setCurrentPath(std.testing.io, original_cwd) catch unreachable;

    try std.testing.expect(try generatedOutputRootBound(
        std.testing.allocator,
        std.testing.io,
        tmp_path,
        "zig-out\\source-lower\\out.json",
    ));

    var bound_output_path = try bindGeneratedOutputPath(std.testing.io, tmp_path, "zig-out\\source-lower\\out.json");
    defer bound_output_path.close();
    try bound_output_path.dir.writeFile(std.testing.io, .{
        .sub_path = bound_output_path.basename,
        .data = "ok",
    });

    const generated_bytes = try tmp.dir.readFileAlloc(std.testing.io, "zig-out/source-lower/out.json", std.testing.allocator, .limited(16));
    defer std.testing.allocator.free(generated_bytes);
    try std.testing.expectEqualStrings("ok", generated_bytes);
}

test "cli output path binder anchors generated roots to package root from subdirectories" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const original_cwd = try std.process.currentPathAlloc(std.testing.io, std.testing.allocator);
    defer std.testing.allocator.free(original_cwd);
    const tmp_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_path);

    try tmp.dir.createDirPath(std.testing.io, "examples");
    const examples_path = try tmp.dir.realPathFileAlloc(std.testing.io, "examples", std.testing.allocator);
    defer std.testing.allocator.free(examples_path);

    try std.process.setCurrentPath(std.testing.io, examples_path);
    defer std.process.setCurrentPath(std.testing.io, original_cwd) catch unreachable;

    try std.testing.expect(try generatedOutputRootBound(
        std.testing.allocator,
        std.testing.io,
        tmp_path,
        "zig-out/out.json",
    ));

    var bound_output_path = try bindGeneratedOutputPath(std.testing.io, tmp_path, "zig-out/out.json");
    defer bound_output_path.close();
    try bound_output_path.dir.writeFile(std.testing.io, .{
        .sub_path = bound_output_path.basename,
        .data = "root",
    });

    const root_generated_bytes = try tmp.dir.readFileAlloc(std.testing.io, "zig-out/out.json", std.testing.allocator, .limited(16));
    defer std.testing.allocator.free(root_generated_bytes);
    try std.testing.expectEqualStrings("root", root_generated_bytes);
    try std.testing.expectError(
        error.FileNotFound,
        tmp.dir.readFileAlloc(std.testing.io, "examples/zig-out/out.json", std.testing.allocator, .limited(16)),
    );
}

test "cli output path binder rejects symlinked child directories" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const original_cwd = try std.process.currentPathAlloc(std.testing.io, std.testing.allocator);
    defer std.testing.allocator.free(original_cwd);
    const tmp_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_path);

    try tmp.dir.createDirPath(std.testing.io, "zig-out");
    try tmp.dir.createDirPath(std.testing.io, "outside");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "outside/out.json",
        .data = "outside",
    });
    const outside_path = try tmp.dir.realPathFileAlloc(std.testing.io, "outside", std.testing.allocator);
    defer std.testing.allocator.free(outside_path);
    const link_path = try std.Io.Dir.path.join(std.testing.allocator, &.{ tmp_path, "zig-out", "hop" });
    defer std.testing.allocator.free(link_path);
    try std.Io.Dir.symLinkAbsolute(std.testing.io, outside_path, link_path, .{});

    try std.process.setCurrentPath(std.testing.io, tmp_path);
    defer std.process.setCurrentPath(std.testing.io, original_cwd) catch unreachable;

    try std.testing.expect(try generatedOutputRootBound(
        std.testing.allocator,
        std.testing.io,
        tmp_path,
        "zig-out/hop/out.json",
    ));
    const rejected = if (bindGeneratedOutputPath(std.testing.io, tmp_path, "zig-out/hop/out.json")) |bound_value| rejected: {
        var bound = bound_value;
        bound.close();
        break :rejected false;
    } else |_| true;
    try std.testing.expect(rejected);

    const outside_bytes = try tmp.dir.readFileAlloc(std.testing.io, "outside/out.json", std.testing.allocator, .limited(32));
    defer std.testing.allocator.free(outside_bytes);
    try std.testing.expectEqualStrings("outside", outside_bytes);
}

test "cli output path binder distinguishes missing parent directories" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_path);

    try tmp.dir.createDirPath(std.testing.io, "zig-out");

    try std.testing.expectError(
        error.FileNotFound,
        bindGeneratedOutputPath(std.testing.io, tmp_path, "zig-out/missing/out.json"),
    );
}

test "accepted source-lower output replaces final symlink instead of following it" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const original_cwd = try std.process.currentPathAlloc(std.testing.io, std.testing.allocator);
    defer std.testing.allocator.free(original_cwd);
    const tmp_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_path);

    try tmp.dir.createDirPath(std.testing.io, "zig-out/safe");
    try tmp.dir.createDirPath(std.testing.io, "outside");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "outside/out.json",
        .data = "outside",
    });
    const outside_file_path = try tmp.dir.realPathFileAlloc(std.testing.io, "outside/out.json", std.testing.allocator);
    defer std.testing.allocator.free(outside_file_path);
    const link_path = try std.Io.Dir.path.join(std.testing.allocator, &.{ tmp_path, "zig-out", "safe", "out.json" });
    defer std.testing.allocator.free(link_path);
    try std.Io.Dir.symLinkAbsolute(std.testing.io, outside_file_path, link_path, .{});

    try std.process.setCurrentPath(std.testing.io, tmp_path);
    defer std.process.setCurrentPath(std.testing.io, original_cwd) catch unreachable;

    var bound_output_path = try bindGeneratedOutputPath(std.testing.io, tmp_path, "zig-out/safe/out.json");
    defer bound_output_path.close();
    const program = source_lowering.GeneratedProgram{
        .case_id = "source.test",
        .label = "source.test",
        .source_path = "test.zig",
        .surface_kind = .source_case,
        .status = .canonical,
        .canonical_scenario_id = null,
        .expected_transcript = "",
        .steps = &.{},
        .feature_flags = &.{},
        .diagnostics = &.{},
        .error_witness = error_witness.ErrorWitnessV1.empty(.ordinary),
    };
    try writeAcceptedProgramOutput(.{
        .dir = bound_output_path.dir,
        .io = std.testing.io,
        .allocator = std.testing.allocator,
        .emit_mode = .json,
        .out_path = bound_output_path.basename,
        .program = &program,
    });

    const outside_bytes = try tmp.dir.readFileAlloc(std.testing.io, "outside/out.json", std.testing.allocator, .limited(32));
    defer std.testing.allocator.free(outside_bytes);
    try std.testing.expectEqualStrings("outside", outside_bytes);

    const generated_bytes = try tmp.dir.readFileAlloc(std.testing.io, "zig-out/safe/out.json", std.testing.allocator, .limited(1024));
    defer std.testing.allocator.free(generated_bytes);
    try std.testing.expect(std.mem.find(u8, generated_bytes, "\"case_id\":\"source.test\"") != null);
}

test "rejected source-lower programs remove stale output artifacts" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "out.json",
        .data = "keep",
    });

    var program = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = "source.branch_resume",
        .source_path = "test/source_lowering_corpus/fixtures/branch_resume.zig",
        .entry_symbol = "wrong",
        .surface_kind = .source_case,
    });
    defer program.deinit(std.testing.allocator);
    try std.testing.expect(!program.isAccepted());

    try std.testing.expectError(
        error.RejectedGeneratedProgram,
        writeAcceptedProgramOutput(.{
            .dir = tmp.dir,
            .io = std.testing.io,
            .allocator = std.testing.allocator,
            .emit_mode = .json,
            .out_path = "out.json",
            .program = &program,
        }),
    );

    try std.testing.expectError(
        error.FileNotFound,
        tmp.dir.readFileAlloc(std.testing.io, "out.json", std.testing.allocator, .limited(16)),
    );
}

test "rejected source-lower programs print structured diagnostics" {
    var program = try source_lowering.inspectSource(std.testing.allocator, .{
        .case_id = "source.branch_resume",
        .source_path = "test/source_lowering_corpus/fixtures/branch_resume.zig",
        .entry_symbol = "wrong",
        .surface_kind = .source_case,
    });
    defer program.deinit(std.testing.allocator);
    try std.testing.expect(!program.isAccepted());

    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try writeRejectedProgramDiagnostics(&output.writer, program);
    const bytes = try output.toOwnedSlice();
    defer std.testing.allocator.free(bytes);

    try std.testing.expect(std.mem.find(u8, bytes, "ability-source-lower:") != null);
    try std.testing.expect(std.mem.find(u8, bytes, "unsupported_shape") != null);
    try std.testing.expect(std.mem.find(u8, bytes, "canonical entry symbol") != null);
}
