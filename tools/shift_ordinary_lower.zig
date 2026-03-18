const lowered_machine = @import("lowered_machine");
const ordinary = @import("ordinary_zig_lowering");
const std = @import("std");

const EmitMode = enum {
    json,
    zig,
};

fn usage() noreturn {
    std.debug.print(
        "usage: shift-ordinary-lower --id <ordinary.case> --source <path> --entry <symbol> --surface <ordinary_case|example|effect|user_defined_effect|witness> --emit <json|zig> --out <path>\n",
        .{},
    );
    std.process.exit(1);
}

fn parseSurface(value: []const u8) ?ordinary.SurfaceKind {
    if (std.mem.eql(u8, value, "ordinary_case")) return .ordinary_case;
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

fn writeZigStringArray(writer: anytype, values: []const []const u8) !void {
    try writer.writeAll("&.{");
    for (values, 0..) |value, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try writeZigStringLiteral(writer, value);
    }
    try writer.writeByte('}');
}

fn writeZigWitnessDiagnostics(writer: anytype, diagnostics: anytype) !void {
    try writer.writeAll("&.{");
    for (diagnostics, 0..) |diag, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try writer.writeAll(".{ .code = ");
        try writeZigStringLiteral(writer, diag.code);
        try writer.writeAll(", .message = ");
        try writeZigStringLiteral(writer, diag.message);
        try writer.writeAll(", .path = ");
        try writeZigStringLiteral(writer, diag.path);
        try writer.print(", .line = {d}, .column = {d} }}", .{ diag.line, diag.column });
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

fn writeJson(program: ordinary.GeneratedProgram, writer: anytype) !void {
    try writer.writeAll("{\"case_id\":");
    try writeJsonStringLiteral(writer, program.case_id);
    try writer.writeAll(",\"surface_kind\":");
    try writeJsonStringLiteral(writer, @tagName(program.surface_kind));
    try writer.writeAll(",\"status\":");
    try writeJsonStringLiteral(writer, @tagName(program.status));
    try writer.writeAll(",\"canonical_scenario_id\":");
    if (program.canonical_scenario_id) |id| {
        try writeJsonStringLiteral(writer, @tagName(id));
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"feature_flags\":[");
    for (program.feature_flags, 0..) |flag, idx| {
        if (idx != 0) try writer.writeAll(",");
        try writer.print("\"{s}\"", .{flag});
    }
    try writer.writeAll("],\"error_witness\":{");
    try writer.print("\"schema_version\":{d},\"surface\":\"{s}\",\"support_status\":\"{s}\",", .{
        program.error_witness.schema_version,
        @tagName(program.error_witness.surface),
        @tagName(program.error_witness.support_status),
    });
    try writer.writeAll("\"public_runtime_errors\":[");
    for (program.error_witness.public_runtime_errors, 0..) |tag, idx| {
        if (idx != 0) try writer.writeAll(",");
        try writeJsonStringLiteral(writer, @tagName(tag));
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

fn writeZig(program: ordinary.GeneratedProgram, writer: anytype) !void {
    try writer.writeAll(
        "const shift = @import(\"shift\");\n" ++
            "const std = @import(\"std\");\n\n",
    );
    try writer.writeAll("const generated_program_steps = [_]shift.ordinary.Step{\n");
    for (program.steps) |step| try writeStepLiteral(writer, step);
    try writer.writeAll("};\n");
    try writer.writeAll("\nconst generated_program_feature_flags = [_][]const u8{");
    for (program.feature_flags, 0..) |flag, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try writeZigStringLiteral(writer, flag);
    }
    try writer.writeAll("};\n");
    try writer.writeAll("\nconst generated_program_diagnostics = [_]shift.ordinary.Diagnostic{");
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
    try writer.writeAll("const WitnessDiagnostic = @typeInfo(@TypeOf((@as(shift.ordinary.GeneratedProgram, undefined)).error_witness.diagnostics)).pointer.child;\n");
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
    try writer.writeAll("pub fn initGeneratedProgram(allocator: std.mem.Allocator) !shift.ordinary.GeneratedProgram {\n");
    try writer.writeAll("    return .{\n");
    try writer.writeAll("        .case_id = ");
    try writeZigStringLiteral(writer, program.case_id);
    try writer.writeAll(",\n");
    try writer.writeAll("        .label = ");
    try writeZigStringLiteral(writer, program.label);
    try writer.writeAll(",\n");
    try writer.writeAll("        .source_path = try allocator.dupe(u8, ");
    try writeZigStringLiteral(writer, program.source_path);
    try writer.writeAll("),\n");
    try writer.print("        .surface_kind = .{s},\n", .{@tagName(program.surface_kind)});
    try writer.print("        .status = .{s},\n", .{@tagName(program.status)});
    if (program.canonical_scenario_id) |id| {
        try writer.print("        .canonical_scenario_id = .{s},\n", .{@tagName(id)});
    } else {
        try writer.writeAll("        .canonical_scenario_id = null,\n");
    }
    try writer.writeAll("        .expected_transcript = ");
    try writeZigStringLiteral(writer, program.expected_transcript);
    try writer.writeAll(",\n");
    try writer.writeAll("        .steps = try allocator.dupe(shift.ordinary.Step, &generated_program_steps),\n");
    try writer.writeAll("        .feature_flags = try allocator.dupe([]const u8, &generated_program_feature_flags),\n");
    try writer.writeAll("        .diagnostics = try allocator.dupe(shift.ordinary.Diagnostic, &generated_program_diagnostics),\n");
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
    if (program.error_witness.diagnostics.len == 0) {
        try writer.writeAll(", .diagnostics = &.{}");
    } else {
        try writer.writeAll(", .diagnostics = try allocator.dupe(WitnessDiagnostic, &generated_program_witness_diagnostics)");
    }
    try writer.writeAll(" },\n");
    try writer.writeAll("    };\n");
    try writer.writeAll("}\n\n");
    try writer.writeAll(
        "pub fn runLowered(writer: anytype) !void {\n" ++
            "    const allocator = std.heap.page_allocator;\n" ++
            "    var generated_program = try initGeneratedProgram(allocator);\n" ++
            "    defer generated_program.deinit(allocator);\n" ++
            "    try shift.ordinary.runLowered(writer, &generated_program);\n" ++
            "}\n",
    );
}

/// Build or inspect one public experimental ordinary-Zig lowering artifact.
pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    if (args.len != 13) usage();

    var program_id: ?[]const u8 = null;
    var source_path: ?[]const u8 = null;
    var entry_symbol: ?[]const u8 = null;
    var surface_kind: ?ordinary.SurfaceKind = null;
    var emit: ?EmitMode = null;
    var out_path: ?[]const u8 = null;

    var idx: usize = 1;
    while (idx < args.len) : (idx += 2) {
        const flag = args[idx];
        const value = args[idx + 1];
        if (std.mem.eql(u8, flag, "--id")) {
            program_id = value;
        } else if (std.mem.eql(u8, flag, "--source")) {
            source_path = value;
        } else if (std.mem.eql(u8, flag, "--entry")) {
            entry_symbol = value;
        } else if (std.mem.eql(u8, flag, "--surface")) {
            surface_kind = parseSurface(value) orelse usage();
        } else if (std.mem.eql(u8, flag, "--emit")) {
            emit = parseEmit(value) orelse usage();
        } else if (std.mem.eql(u8, flag, "--out")) {
            out_path = value;
        } else {
            usage();
        }
    }

    var program = try ordinary.inspectSource(allocator, .{
        .case_id = program_id orelse usage(),
        .source_path = source_path orelse usage(),
        .entry_symbol = entry_symbol orelse usage(),
        .surface_kind = surface_kind orelse usage(),
    });
    defer program.deinit(allocator);

    var output: std.io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    switch (emit orelse usage()) {
        .json => try writeJson(program, &output.writer),
        .zig => try writeZig(program, &output.writer),
    }
    const bytes = try output.toOwnedSlice();
    defer allocator.free(bytes);
    try std.fs.cwd().writeFile(.{
        .sub_path = out_path orelse usage(),
        .data = bytes,
    });

    if (!program.isAccepted()) return error.RejectedGeneratedProgram;
}
