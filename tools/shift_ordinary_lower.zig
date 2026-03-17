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

fn writeJson(program: ordinary.GeneratedProgram, writer: anytype) !void {
    try writer.print(
        "{{\"case_id\":\"{s}\",\"surface_kind\":\"{s}\",\"status\":\"{s}\",\"canonical_scenario_id\":",
        .{ program.case_id, @tagName(program.surface_kind), @tagName(program.status) },
    );
    if (program.canonical_scenario_id) |id| {
        try writer.print("\"{s}\"", .{@tagName(id)});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"feature_flags\":[");
    for (program.feature_flags, 0..) |flag, idx| {
        if (idx != 0) try writer.writeAll(",");
        try writer.print("\"{s}\"", .{flag});
    }
    try writer.writeAll("],\"diagnostics\":[");
    for (program.diagnostics, 0..) |diag, idx| {
        if (idx != 0) try writer.writeAll(",");
        try writer.print(
            "{{\"code\":\"{s}\",\"message\":\"{s}\",\"path\":\"{s}\",\"line\":{d},\"column\":{d}}}",
            .{ diag.code, diag.message, diag.path, diag.line, diag.column },
        );
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
        "const ordinary = @import(\"ordinary_zig_lowering\");\n" ++
            "const lowered_machine = @import(\"lowered_machine\");\n\n",
    );
    try writer.print("pub const generated_program = ordinary.GeneratedProgram{{\n", .{});
    try writer.writeAll("    .case_id = ");
    try writeZigStringLiteral(writer, program.case_id);
    try writer.writeAll(",\n");
    try writer.writeAll("    .label = ");
    try writeZigStringLiteral(writer, program.label);
    try writer.writeAll(",\n");
    try writer.writeAll("    .source_path = ");
    try writeZigStringLiteral(writer, program.source_path);
    try writer.writeAll(",\n");
    try writer.print("    .surface_kind = .{s},\n", .{@tagName(program.surface_kind)});
    try writer.print("    .status = .{s},\n", .{@tagName(program.status)});
    if (program.canonical_scenario_id) |id| {
        try writer.print("    .canonical_scenario_id = .{s},\n", .{@tagName(id)});
    } else {
        try writer.writeAll("    .canonical_scenario_id = null,\n");
    }
    try writer.writeAll("    .expected_transcript = ");
    try writeZigStringLiteral(writer, program.expected_transcript);
    try writer.writeAll(",\n");
    try writer.writeAll("    .steps = &[_]lowered_machine.Step{\n");
    for (program.steps) |step| try writeStepLiteral(writer, step);
    try writer.writeAll("    },\n");
    try writer.writeAll("    .feature_flags = &.{");
    for (program.feature_flags, 0..) |flag, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try writeZigStringLiteral(writer, flag);
    }
    try writer.writeAll("},\n");
    try writer.writeAll("    .diagnostics = &.{");
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
    try writer.writeAll("},\n");
    try writer.writeAll("};\n\n");
    try writer.writeAll(
        "pub fn runLowered(writer: anytype) !void {\n" ++
            "    try ordinary.runLowered(writer, &generated_program);\n" ++
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
