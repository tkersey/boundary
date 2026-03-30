const shift = @import("shift");
const std = @import("std");

const Command = enum {
    inspect,
    seed,
    seed_plan_backed,
    upgrade,
};

fn usage() noreturn {
    std.debug.print(
        "usage: shift-durable-migrate <seed|seed-plan-backed|inspect|upgrade> --manifest <path> --events <path> [--scenario <id>]\n",
        .{},
    );
    std.process.exit(1);
}

fn parseCommand(value: []const u8) ?Command {
    if (std.mem.eql(u8, value, "inspect")) return .inspect;
    if (std.mem.eql(u8, value, "seed")) return .seed;
    if (std.mem.eql(u8, value, "seed-plan-backed")) return .seed_plan_backed;
    if (std.mem.eql(u8, value, "upgrade")) return .upgrade;
    return null;
}

fn makeDemoPlanBackedArtifact() shift.durable.ProgramArtifact {
    return .{
        .label = "plan_backed",
        .program_hash = 0xdead,
        .steps = &.{
            .{ .emit = .{ .note = "plan-backed" } },
            .{ .emit = .{ .final_i32 = 7 } },
        },
        .plan = .{
            .label = "demo.plan",
            .ir_hash = 0x9234,
            .entry_index = 0,
            .functions = &.{.{
                .symbol_name = "runBody",
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 1,
                .first_instruction = 0,
                .instruction_count = 1,
            }},
            .requirements = &.{},
            .ops = &.{},
            .outputs = &.{.{
                .label = "result",
                .codec = .i32,
            }},
            .instructions = &.{.{
                .kind = .return_value,
                .dst = 0,
                .operand = 0,
                .aux = 0,
            }},
        },
    };
}

fn parseScenarioId(value: []const u8) ?shift.interpreter.ScenarioId {
    return std.meta.stringToEnum(shift.interpreter.ScenarioId, value);
}

fn writeString(writer: anytype, value: []const u8) !void {
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

fn writeOptionalHop(writer: anytype, hop: ?shift.durable.VersionHop) !void {
    if (hop) |value| {
        try writer.print("{{\"from\":{d},\"to\":{d}}}", .{ value.from, value.to_schema });
    } else {
        try writer.writeAll("null");
    }
}

fn writeMigrationReport(writer: anytype, report: ?shift.durable.MigrationReport) !void {
    if (report) |value| {
        try writer.writeAll("{\"event_schema\":");
        try writeOptionalHop(writer, value.event_schema);
        try writer.writeAll(",\"manifest_schema\":");
        try writeOptionalHop(writer, value.manifest_schema);
        try writer.writeAll(",\"plan_file_schema\":");
        try writeOptionalHop(writer, value.plan_file_schema);
        try writer.print(
            ",\"rewrote_events\":{},\"rewrote_manifest\":{},\"rewrote_plan_file\":{}}}",
            .{ value.rewrote_events, value.rewrote_manifest, value.rewrote_plan_file },
        );
    } else {
        try writer.writeAll("null");
    }
}

fn writeResultJson(
    writer: anytype,
    command: Command,
    scenario_id: ?shift.interpreter.ScenarioId,
    result: shift.durable.RestoreResult,
) !void {
    try writer.writeAll("{\"command\":");
    try writeString(writer, @tagName(command));
    try writer.writeAll(",\"status\":");
    try writeString(writer, @tagName(result.status));
    try writer.writeAll(",\"scenario_id\":");
    if (scenario_id) |value| {
        try writeString(writer, @tagName(value));
    } else {
        try writer.writeAll("null");
    }
    try writer.print(
        ",\"manifest\":{{\"schema_version\":{d},\"program_hash\":{d},\"plan_schema_version\":",
        .{ result.manifest.schema_version, result.manifest.program_hash },
    );
    if (result.manifest.plan_schema_version) |value| {
        try writer.print("{d}", .{value});
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"event_schema_version\":");
    if (result.manifest.event_schema_version) |value| {
        try writer.print("{d}", .{value});
    } else {
        try writer.writeAll("null");
    }
    try writer.print(",\"last_seq\":{d}}},\"migration_report\":", .{result.manifest.last_seq});
    try writeMigrationReport(writer, result.migration_report);
    try writer.writeAll("}\n");
}

fn ensureParentDir(allocator: std.mem.Allocator, path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir_name| {
        if (dir_name.len == 0) return;
        const resolved = try allocator.dupe(u8, dir_name);
        defer allocator.free(resolved);
        if (std.fs.path.isAbsolute(resolved)) {
            std.fs.makeDirAbsolute(resolved) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
        } else {
            try std.fs.cwd().makePath(resolved);
        }
    }
}

/// Run this durable migration tool entrypoint.
pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next();
    const command = parseCommand(args.next() orelse usage()) orelse usage();

    var manifest_path: ?[]const u8 = null;
    var events_path: ?[]const u8 = null;
    var scenario_id: ?shift.interpreter.ScenarioId = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--manifest")) {
            manifest_path = args.next() orelse usage();
        } else if (std.mem.eql(u8, arg, "--events")) {
            events_path = args.next() orelse usage();
        } else if (std.mem.eql(u8, arg, "--scenario")) {
            scenario_id = parseScenarioId(args.next() orelse usage()) orelse usage();
        } else {
            usage();
        }
    }

    const manifest = manifest_path orelse usage();
    const events = events_path orelse usage();
    try ensureParentDir(allocator, manifest);
    try ensureParentDir(allocator, events);

    const store = shift.durable.Store.init(allocator, manifest, events);
    const result = switch (command) {
        .seed => blk: {
            const concrete_scenario = scenario_id orelse usage();
            _ = try store.saveScenario(concrete_scenario);
            break :blk try store.inspectRestore();
        },
        .seed_plan_backed => blk: {
            _ = try store.saveArtifact(makeDemoPlanBackedArtifact(), null);
            break :blk try store.inspectRestore();
        },
        .inspect => if (scenario_id) |value|
            try store.inspectRestoreArtifact(shift.durable.ProgramArtifact.fromScenario(value))
        else
            try store.inspectRestore(),
        .upgrade => if (scenario_id) |value|
            try store.restoreArtifact(shift.durable.ProgramArtifact.fromScenario(value))
        else
            try store.restore(),
    };

    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    try writeResultJson(&stdout_writer.interface, command, scenario_id orelse result.manifest.scenario_id, result);
    try stdout_writer.interface.flush();
}
