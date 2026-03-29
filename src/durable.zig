const kernel = @import("internal_kernel");
const scenarios = @import("parity_scenarios");
const std = @import("std");

/// Stable executable kernel artifact used by durable replay.
pub const ProgramArtifact = struct {
    label: []const u8,
    program_hash: u64,
    steps: []const kernel.Step,

    /// Build one executable artifact from a canonical scenario.
    pub fn fromScenario(id: kernel.ScenarioId) @This() {
        const scenario = scenarios.byId(id);
        return .{
            .label = scenario.case_id,
            .program_hash = hashProgram(scenario.case_id, scenario.steps),
            .steps = scenario.steps,
        };
    }
};

/// Restore outcomes for append-only durable session artifacts.
pub const RestoreStatus = enum {
    exact_replay,
    failed,
    rebuild_required,
};

/// Manifest persisted alongside an append-only event log.
pub const SessionManifest = struct {
    schema_version: u32 = 2,
    scenario_id: ?kernel.ScenarioId = null,
    program_hash: u64,
    last_seq: usize,
    restore_status: RestoreStatus = .exact_replay,
};

/// One append-only persisted event row.
pub const EventRecord = struct {
    seq: usize,
    event: kernel.Event,
};

/// Restore result for one durable session replay attempt.
pub const RestoreResult = struct {
    status: RestoreStatus,
    manifest: SessionManifest,
    state: ?kernel.State = null,
};

/// Local append-only store for one durable interpreter session.
pub const Store = struct {
    allocator: std.mem.Allocator,
    manifest_path: []const u8,
    events_path: []const u8,

    /// Build one store rooted at the supplied manifest and event paths.
    pub fn init(allocator: std.mem.Allocator, manifest_path: []const u8, events_path: []const u8) @This() {
        return .{
            .allocator = allocator,
            .manifest_path = manifest_path,
            .events_path = events_path,
        };
    }

    /// Persist one scenario execution into local append-only artifacts.
    pub fn saveScenario(self: @This(), scenario_id: kernel.ScenarioId) anyerror!SessionManifest {
        return try self.saveArtifact(ProgramArtifact.fromScenario(scenario_id), scenario_id);
    }

    /// Persist one executable kernel artifact into local append-only artifacts.
    pub fn saveArtifact(self: @This(), artifact: ProgramArtifact, scenario_id: ?kernel.ScenarioId) anyerror!SessionManifest {
        const state = kernel.runSteps(artifact.steps);
        const manifest = SessionManifest{
            .scenario_id = scenario_id,
            .program_hash = artifact.program_hash,
            .last_seq = kernel.events(&state).len,
        };
        try writeManifest(self.manifest_path, manifest);
        try writeEvents(self.events_path, &state);
        return manifest;
    }

    /// Restore one persisted session by replaying the canonical scenario and checking the event log.
    pub fn restore(self: @This()) anyerror!RestoreResult {
        const manifest = try readManifest(self.allocator, self.manifest_path);
        if (manifest.schema_version != 2) {
            return .{
                .status = .rebuild_required,
                .manifest = manifest,
                .state = null,
            };
        }

        const scenario_id = manifest.scenario_id orelse return .{
            .status = .rebuild_required,
            .manifest = manifest,
            .state = null,
        };
        return try self.restoreArtifact(ProgramArtifact.fromScenario(scenario_id));
    }

    /// Restore one persisted session by replaying the supplied artifact and checking the event log.
    pub fn restoreArtifact(self: @This(), artifact: ProgramArtifact) anyerror!RestoreResult {
        const manifest = try readManifest(self.allocator, self.manifest_path);
        if (manifest.schema_version != 2) {
            return .{
                .status = .rebuild_required,
                .manifest = manifest,
                .state = null,
            };
        }
        if (manifest.program_hash != artifact.program_hash) {
            return .{
                .status = .rebuild_required,
                .manifest = manifest,
                .state = null,
            };
        }

        const state = kernel.runSteps(artifact.steps);
        if (!try eventsMatch(self.allocator, self.events_path, &state, manifest.last_seq)) {
            return .{
                .status = .failed,
                .manifest = manifest,
                .state = null,
            };
        }
        return .{
            .status = .exact_replay,
            .manifest = manifest,
            .state = state,
        };
    }
};

fn hashProgram(label: []const u8, steps: []const kernel.Step) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(label);
    hasher.update(&.{0});
    for (steps) |step| switch (step) {
        .checkpoint => |tag| hasher.update(@tagName(tag)),
        .emit => |event| switch (event) {
            .note => |line| {
                hasher.update("note");
                hasher.update(line);
            },
            .final_i32 => |value| {
                hasher.update("final_i32");
                hasher.update(std.mem.asBytes(&value));
            },
            .final_string => |value| {
                hasher.update("final_string");
                hasher.update(value);
            },
        },
        .pop_pending => hasher.update("pop_pending"),
        .push_pending => |frame| {
            hasher.update("push_pending");
            hasher.update(@tagName(frame.kind));
            hasher.update(@tagName(frame.prompt));
        },
        .set_active_prompt => |prompt| {
            hasher.update("set_active_prompt");
            if (prompt) |id| hasher.update(@tagName(id)) else hasher.update("null");
        },
        .set_final => |value| switch (value) {
            .none => hasher.update("none"),
            .bool => |flag| {
                hasher.update("bool");
                hasher.update(std.mem.asBytes(&flag));
            },
            .i32 => |number| {
                hasher.update("i32");
                hasher.update(std.mem.asBytes(&number));
            },
            .string => |line| {
                hasher.update("string");
                hasher.update(line);
            },
        },
    };
    return hasher.final();
}

fn writeManifest(path: []const u8, manifest: SessionManifest) !void {
    const file = if (std.fs.path.isAbsolute(path))
        try std.fs.createFileAbsolute(path, .{ .truncate = true })
    else
        try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(&buffer);
    try std.json.Stringify.value(manifest, .{}, &writer.interface);
    try writer.interface.writeByte('\n');
    try writer.interface.flush();
}

fn writeEvents(path: []const u8, state: *const kernel.State) !void {
    const file = if (std.fs.path.isAbsolute(path))
        try std.fs.createFileAbsolute(path, .{ .truncate = true })
    else
        try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(&buffer);
    for (kernel.events(state), 0..) |event, seq| {
        try std.json.Stringify.value(EventRecord{
            .seq = seq,
            .event = event,
        }, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
    }
    try writer.interface.flush();
}

fn readManifest(allocator: std.mem.Allocator, path: []const u8) !SessionManifest {
    const bytes = if (std.fs.path.isAbsolute(path)) blk: {
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();
        var buffer: [4096]u8 = undefined;
        var reader = file.reader(&buffer);
        break :blk try reader.interface.allocRemaining(allocator, .limited(std.math.maxInt(usize)));
    } else try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(SessionManifest, allocator, bytes, .{});
    defer parsed.deinit();
    return parsed.value;
}

fn eventsMatch(allocator: std.mem.Allocator, path: []const u8, state: *const kernel.State, expected_len: usize) !bool {
    const bytes = if (std.fs.path.isAbsolute(path)) blk: {
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();
        var buffer: [4096]u8 = undefined;
        var reader = file.reader(&buffer);
        break :blk try reader.interface.allocRemaining(allocator, .limited(std.math.maxInt(usize)));
    } else try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
    defer allocator.free(bytes);

    const expected_events = kernel.events(state);
    if (expected_events.len != expected_len) return false;

    var line_iter = std.mem.splitScalar(u8, bytes, '\n');
    var seq: usize = 0;
    while (line_iter.next()) |line| {
        if (line.len == 0) continue;
        if (seq >= expected_events.len) return false;

        const parsed = try std.json.parseFromSlice(EventRecord, allocator, line, .{});
        defer parsed.deinit();
        if (parsed.value.seq != seq) return false;
        if (!eventEql(parsed.value.event, expected_events[seq])) return false;
        seq += 1;
    }
    return seq == expected_events.len;
}

fn eventEql(lhs: kernel.Event, rhs: kernel.Event) bool {
    return switch (lhs) {
        .note => |value| switch (rhs) {
            .note => |other| std.mem.eql(u8, value, other),
            else => false,
        },
        .final_i32 => |value| switch (rhs) {
            .final_i32 => |other| value == other,
            else => false,
        },
        .final_string => |value| switch (rhs) {
            .final_string => |other| std.mem.eql(u8, value, other),
            else => false,
        },
    };
}
