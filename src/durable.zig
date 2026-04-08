const kernel = @import("internal_kernel");
const scenarios = @import("parity_scenarios");
const std = @import("std");

const current_manifest_schema: u32 = 5;
const current_plan_schema: u32 = 4;
const current_event_schema: u32 = 1;
const current_artifact_schema: u32 = 1;

/// Stable executable kernel artifact used by durable replay.
pub const ProgramArtifact = struct {
    label: []const u8,
    program_hash: u64,
    steps: []const kernel.Step,
    plan: ?kernel.ProgramPlan = null,

    /// Durable identity hash for this artifact. Plan-backed artifacts key to IR identity.
    pub fn identityHash(self: @This()) u64 {
        return if (self.plan) |plan| plan.ir_hash else self.program_hash;
    }

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
    schema_version: u32 = current_manifest_schema,
    scenario_id: ?kernel.ScenarioId = null,
    /// Durable program identity. Plan-backed artifacts persist `ProgramPlan.ir_hash`.
    program_hash: u64,
    artifact_hash: ?u64 = null,
    artifact_schema_version: ?u32 = null,
    plan_hash: ?u64 = null,
    plan_schema_version: ?u32 = null,
    event_schema_version: ?u32 = null,
    last_seq: usize,
    restore_status: RestoreStatus = .exact_replay,
};

/// Versioned durable artifact envelope for non-scenario executable provenance.
pub const ArtifactFile = struct {
    schema_version: u32 = current_artifact_schema,
    identity_hash: u64,
    label: []const u8,
    steps: []const kernel.Step,
};

/// Versioned durable plan file envelope.
pub const PlanFile = struct {
    schema_version: u32 = current_plan_schema,
    plan_hash: u64,
    plan: kernel.ProgramPlan,
};

/// One append-only persisted event row.
pub const EventRecord = struct {
    schema_version: u32 = current_event_schema,
    seq: usize,
    event: kernel.Event,
};

fn isPlanReplayRebuildError(err: anyerror) bool {
    return switch (err) {
        error.EmptyFunctionSymbol,
        error.EmptyLabel,
        error.EmptyOpName,
        error.EmptyOutputLabel,
        error.EmptyProgram,
        error.EmptyRequirementLabel,
        error.InvalidCallHelperTarget,
        error.InvalidCallHelperArgSpan,
        error.InvalidCallOpTarget,
        error.InvalidBlockInstructionSpan,
        error.InvalidBlockTerminatorIndex,
        error.InvalidEntryIndex,
        error.InvalidFunctionBlockSpan,
        error.InvalidFunctionEntryBlock,
        error.InvalidFunctionInstructionSpan,
        error.InvalidFunctionLocalSpan,
        error.InvalidFunctionOutputSpan,
        error.InvalidFunctionRequirementSpan,
        error.InvalidInstructionLocalIndex,
        error.InvalidOpRequirementIndex,
        error.InvalidRequirementOpSpan,
        error.InvalidReturnValueIndex,
        error.InvalidTerminatorInstruction,
        error.InvalidTerminatorTarget,
        error.FileNotFound,
        error.UnsupportedPlanSchema,
        error.UnsupportedSchemaVersion,
        => true,
        else => false,
    };
}

fn isArtifactReplayRebuildError(err: anyerror) bool {
    return switch (err) {
        error.FileNotFound,
        error.UnsupportedArtifactSchema,
        => true,
        else => false,
    };
}

fn isEventReplayRebuildError(err: anyerror) bool {
    return switch (err) {
        error.FileNotFound,
        error.UnsupportedEventSchema,
        => true,
        else => false,
    };
}

/// Restore result for one durable session replay attempt.
pub const RestoreResult = struct {
    status: RestoreStatus,
    manifest: SessionManifest,
    state: ?kernel.State = null,
};

const ReadArtifactFileResult = struct {
    stored_schema_version: u32,
    artifact: ProgramArtifact,
};

const EventsMatchResult = struct { matches: bool };

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
        if (scenario_id) |id| {
            if (!artifactMatchesCanonicalScenario(artifact, ProgramArtifact.fromScenario(id))) {
                return error.ScenarioArtifactMismatch;
            }
        }
        if (artifact.plan) |plan| try plan.validate();
        try kernel.validateStepCapacity(artifact.steps);
        const state = kernel.runSteps(artifact.steps);
        const plan_path = try derivedPlanPath(self.allocator, self.manifest_path);
        defer self.allocator.free(plan_path);
        const artifact_path = try derivedArtifactPath(self.allocator, self.manifest_path);
        defer self.allocator.free(artifact_path);
        var manifest_snapshot = try captureFileSnapshot(self.allocator, self.manifest_path);
        defer manifest_snapshot.deinit(self.allocator);
        errdefer {
            restoreFileSnapshot(manifest_snapshot, self.manifest_path) catch |restore_err| {
                std.log.err("durable rollback failed for manifest: {s}", .{@errorName(restore_err)});
            };
        }
        var artifact_snapshot: ?FileSnapshot = null;
        defer if (artifact_snapshot) |*snapshot| snapshot.deinit(self.allocator);
        errdefer {
            if (artifact_snapshot) |snapshot| restoreFileSnapshot(snapshot, artifact_path) catch |restore_err| {
                std.log.err("durable rollback failed for artifact.json: {s}", .{@errorName(restore_err)});
            };
        }
        if (scenario_id == null) {
            artifact_snapshot = try captureFileSnapshot(self.allocator, artifact_path);
        }
        var plan_snapshot: ?FileSnapshot = null;
        defer if (plan_snapshot) |*snapshot| snapshot.deinit(self.allocator);
        errdefer {
            if (plan_snapshot) |snapshot| restoreFileSnapshot(snapshot, plan_path) catch |restore_err| {
                std.log.err("durable rollback failed for plan.json: {s}", .{@errorName(restore_err)});
            };
        }
        if (artifact.plan != null) {
            plan_snapshot = try captureFileSnapshot(self.allocator, plan_path);
        }
        var events_snapshot = try captureFileSnapshot(self.allocator, self.events_path);
        defer events_snapshot.deinit(self.allocator);
        errdefer {
            restoreFileSnapshot(events_snapshot, self.events_path) catch |restore_err| {
                std.log.err("durable rollback failed for events.jsonl: {s}", .{@errorName(restore_err)});
            };
        }
        const manifest = SessionManifest{
            .scenario_id = scenario_id,
            .program_hash = artifact.identityHash(),
            .artifact_hash = hashProgram(artifact.label, artifact.steps),
            .artifact_schema_version = if (scenario_id == null) current_artifact_schema else null,
            .plan_hash = if (artifact.plan) |plan| hashPlan(plan) else null,
            .plan_schema_version = if (artifact.plan != null) current_plan_schema else null,
            .event_schema_version = current_event_schema,
            .last_seq = kernel.events(&state).len,
        };
        if (scenario_id == null) try writeArtifact(artifact_path, artifact);
        if (artifact.plan) |plan| try writePlan(plan_path, plan);
        try writeEvents(self.events_path, &state);
        try writeManifest(self.manifest_path, manifest);
        return manifest;
    }

    /// Restore one persisted session by replaying the canonical scenario and checking the event log.
    pub fn restore(self: @This()) anyerror!RestoreResult {
        const manifest = readManifest(self.allocator, self.manifest_path) catch |err| switch (err) {
            error.UnsupportedManifestSchema => return .{
                .status = .rebuild_required,
                .manifest = .{
                    .schema_version = 0,
                    .program_hash = 0,
                    .last_seq = 0,
                },
                .state = null,
            },
            else => return err,
        };
        if (manifest.scenario_id) |id| {
            return try self.restoreArtifactInternal(ProgramArtifact.fromScenario(id));
        }
        const expected_artifact_schema = manifest.artifact_schema_version orelse return .{
            .status = .rebuild_required,
            .manifest = manifest,
            .state = null,
        };
        if (expected_artifact_schema != current_artifact_schema) {
            return .{
                .status = .rebuild_required,
                .manifest = manifest,
                .state = null,
            };
        }
        const artifact_path = try derivedArtifactPath(self.allocator, self.manifest_path);
        defer self.allocator.free(artifact_path);
        const artifact_file = readArtifactFile(self.allocator, artifact_path) catch |err| {
            if (isArtifactReplayRebuildError(err)) {
                return .{
                    .status = .rebuild_required,
                    .manifest = manifest,
                    .state = null,
                };
            }
            return .{
                .status = .failed,
                .manifest = manifest,
                .state = null,
            };
        };
        defer freeArtifact(self.allocator, &artifact_file.artifact);
        if (artifact_file.stored_schema_version != expected_artifact_schema) {
            return .{
                .status = .rebuild_required,
                .manifest = manifest,
                .state = null,
            };
        }
        return try self.restoreArtifactInternal(artifact_file.artifact);
    }

    /// Inspect one persisted session restore without mutating durable files.
    pub fn inspectRestore(self: @This()) anyerror!RestoreResult {
        return try self.restore();
    }

    /// Restore one persisted session by replaying the supplied artifact and checking the event log.
    pub fn restoreArtifact(self: @This(), artifact: ProgramArtifact) anyerror!RestoreResult {
        return try self.restoreArtifactInternal(artifact);
    }

    /// Inspect one persisted artifact restore without mutating durable files.
    pub fn inspectRestoreArtifact(self: @This(), artifact: ProgramArtifact) anyerror!RestoreResult {
        return try self.restoreArtifactInternal(artifact);
    }

    fn restoreArtifactInternal(self: @This(), artifact: ProgramArtifact) anyerror!RestoreResult {
        const manifest = readManifest(self.allocator, self.manifest_path) catch |err| switch (err) {
            error.UnsupportedManifestSchema => return .{
                .status = .rebuild_required,
                .manifest = .{
                    .schema_version = 0,
                    .program_hash = 0,
                    .last_seq = 0,
                },
                .state = null,
            },
            else => return err,
        };
        if (manifest.artifact_hash) |expected_artifact_hash| {
            if (hashProgram(artifact.label, artifact.steps) != expected_artifact_hash) {
                return .{
                    .status = .rebuild_required,
                    .manifest = manifest,
                    .state = null,
                };
            }
        }
        if (manifest.program_hash != if (artifact.plan) |plan| plan.ir_hash else artifact.identityHash()) {
            return .{
                .status = .rebuild_required,
                .manifest = manifest,
                .state = null,
            };
        }
        const plan_path = try derivedPlanPath(self.allocator, self.manifest_path);
        defer self.allocator.free(plan_path);
        var loaded_plan: ?kernel.ProgramPlan = null;
        defer if (loaded_plan) |plan| freePlan(self.allocator, &plan);
        if (manifest.plan_hash) |expected_plan_hash| {
            const plan_file = readPlanFile(self.allocator, plan_path) catch |err| {
                if (isPlanReplayRebuildError(err)) {
                    return .{
                        .status = .rebuild_required,
                        .manifest = manifest,
                        .state = null,
                    };
                }
                return .{
                    .status = .failed,
                    .manifest = manifest,
                    .state = null,
                };
            };
            loaded_plan = plan_file.plan;
            if (manifest.plan_schema_version) |expected_plan_schema| {
                if (plan_file.stored_schema_version != expected_plan_schema) {
                    return .{
                        .status = .rebuild_required,
                        .manifest = manifest,
                        .state = null,
                    };
                }
            }
            const stored_plan = loaded_plan.?;
            if (plan_file.comparison_plan_hash != expected_plan_hash or stored_plan.ir_hash != manifest.program_hash) {
                return .{
                    .status = .failed,
                    .manifest = manifest,
                    .state = null,
                };
            }
            if (artifact.plan) |current_plan| {
                if (current_plan.ir_hash != stored_plan.ir_hash or hashPlan(current_plan) != hashPlan(stored_plan)) {
                    return .{
                        .status = .rebuild_required,
                        .manifest = manifest,
                        .state = null,
                    };
                }
            }
        }
        const expected_program_hash = if (loaded_plan) |plan| plan.ir_hash else if (artifact.plan) |plan| plan.ir_hash else artifact.identityHash();
        if (manifest.program_hash != expected_program_hash) {
            return .{
                .status = .rebuild_required,
                .manifest = manifest,
                .state = null,
            };
        }

        const expected_event_schema = manifest.event_schema_version orelse return .{
            .status = .rebuild_required,
            .manifest = manifest,
            .state = null,
        };
        if (!isSupportedEventSchema(expected_event_schema)) {
            return .{
                .status = .rebuild_required,
                .manifest = manifest,
                .state = null,
            };
        }
        try kernel.validateStepCapacity(artifact.steps);
        const state = kernel.runSteps(artifact.steps);
        const event_match = eventsMatch(self.allocator, self.events_path, expected_event_schema, &state, manifest.last_seq) catch |err| {
            if (isEventReplayRebuildError(err)) {
                return .{
                    .status = .rebuild_required,
                    .manifest = manifest,
                    .state = null,
                };
            }
            return err;
        };
        if (!event_match.matches) {
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

fn sidecarBasenameAlloc(allocator: std.mem.Allocator, manifest_path: []const u8, sidecar_kind: []const u8) ![]u8 {
    const manifest_name = std.fs.path.basename(manifest_path);
    const stem = if (std.mem.endsWith(u8, manifest_name, ".manifest.json"))
        manifest_name[0 .. manifest_name.len - ".manifest.json".len]
    else if (std.mem.endsWith(u8, manifest_name, ".json"))
        manifest_name[0 .. manifest_name.len - ".json".len]
    else
        manifest_name;
    return try std.fmt.allocPrint(allocator, "{s}.{s}.json", .{ stem, sidecar_kind });
}

fn derivedSidecarPath(allocator: std.mem.Allocator, manifest_path: []const u8, sidecar_kind: []const u8) ![]u8 {
    const sidecar_name = try sidecarBasenameAlloc(allocator, manifest_path, sidecar_kind);
    defer allocator.free(sidecar_name);
    if (std.fs.path.dirname(manifest_path)) |dir_name| {
        if (dir_name.len != 0) return try std.fs.path.join(allocator, &.{ dir_name, sidecar_name });
    }
    return try allocator.dupe(u8, sidecar_name);
}

fn derivedPlanPath(allocator: std.mem.Allocator, manifest_path: []const u8) ![]u8 {
    return try derivedSidecarPath(allocator, manifest_path, "plan");
}

fn derivedArtifactPath(allocator: std.mem.Allocator, manifest_path: []const u8) ![]u8 {
    return try derivedSidecarPath(allocator, manifest_path, "artifact");
}

fn isSupportedEventSchema(schema_version: u32) bool {
    return schema_version == current_event_schema;
}

fn hashBytes(hasher: *std.hash.Wyhash, value: []const u8) void {
    var encoded_len = std.mem.nativeToLittle(u64, @as(u64, @intCast(value.len)));
    hasher.update(std.mem.asBytes(&encoded_len));
    hasher.update(value);
}

fn hashTag(hasher: *std.hash.Wyhash, tag: []const u8) void {
    hashBytes(hasher, tag);
}

fn hashValue(hasher: *std.hash.Wyhash, value: kernel.Value) void {
    switch (value) {
        .none => hashTag(hasher, "none"),
        .bool => |flag| {
            hashTag(hasher, "bool");
            hasher.update(std.mem.asBytes(&flag));
        },
        .i32 => |number| {
            hashTag(hasher, "i32");
            hasher.update(std.mem.asBytes(&number));
        },
        .string => |line| {
            hashTag(hasher, "string");
            hashBytes(hasher, line);
        },
    }
}

fn hashEvent(hasher: *std.hash.Wyhash, event: kernel.Event) void {
    hashTag(hasher, "emit");
    switch (event) {
        .note => |line| {
            hashTag(hasher, "note");
            hashBytes(hasher, line);
        },
        .final_i32 => |value| {
            hashTag(hasher, "final_i32");
            hasher.update(std.mem.asBytes(&value));
        },
        .final_string => |value| {
            hashTag(hasher, "final_string");
            hashBytes(hasher, value);
        },
    }
}

fn hashOptionalPrompt(hasher: *std.hash.Wyhash, prompt: ?kernel.PromptId) void {
    if (prompt) |id| {
        hashTag(hasher, @tagName(id));
    } else {
        hashTag(hasher, "null");
    }
}

fn hashStep(hasher: *std.hash.Wyhash, step: kernel.Step) void {
    switch (step) {
        .checkpoint => |tag| {
            hashTag(hasher, "checkpoint");
            hashTag(hasher, @tagName(tag));
        },
        .emit => |event| hashEvent(hasher, event),
        .pop_pending => hashTag(hasher, "pop_pending"),
        .push_pending => |frame| {
            hashTag(hasher, "push_pending");
            hashTag(hasher, @tagName(frame.kind));
            hashTag(hasher, @tagName(frame.prompt));
            hashValue(hasher, frame.resume_value);
        },
        .set_active_prompt => |prompt| {
            hashTag(hasher, "set_active_prompt");
            hashOptionalPrompt(hasher, prompt);
        },
        .set_final => |value| {
            hashTag(hasher, "set_final");
            hashValue(hasher, value);
        },
    }
}

fn hashProgram(label: []const u8, steps: []const kernel.Step) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, label);
    for (steps) |step| hashStep(&hasher, step);
    return hasher.final();
}

fn artifactMatchesCanonicalScenario(artifact: ProgramArtifact, canonical: ProgramArtifact) bool {
    if (artifact.plan != null) return false;
    if (!std.mem.eql(u8, artifact.label, canonical.label)) return false;
    if (artifact.program_hash != canonical.program_hash) return false;
    return std.meta.eql(artifact.steps, canonical.steps);
}

fn hashPlan(plan: kernel.ProgramPlan) u64 {
    return plan.hash();
}

const FileSnapshot = struct {
    existed: bool,
    bytes: ?[]u8 = null,

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        if (self.bytes) |bytes| allocator.free(bytes);
    }
};

fn captureFileSnapshot(allocator: std.mem.Allocator, path: []const u8) !FileSnapshot {
    const bytes = if (std.fs.path.isAbsolute(path))
        readAbsoluteFileAlloc(allocator, path) catch |err| switch (err) {
            error.FileNotFound => return .{ .existed = false },
            else => return err,
        }
    else
        std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize)) catch |err| switch (err) {
            error.FileNotFound => return .{ .existed = false },
            else => return err,
        };
    return .{
        .existed = true,
        .bytes = bytes,
    };
}

fn restoreFileSnapshot(snapshot: FileSnapshot, path: []const u8) !void {
    if (snapshot.existed) {
        try writeRawFile(path, snapshot.bytes.?);
        return;
    }
    deleteFileIfExists(path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
}

fn ensureParentPath(path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    if (parent.len == 0) return;
    try std.fs.cwd().makePath(parent);
}

fn writeRawFile(path: []const u8, bytes: []const u8) !void {
    try ensureParentPath(path);
    const file = if (std.fs.path.isAbsolute(path))
        try std.fs.createFileAbsolute(path, .{ .truncate = true })
    else
        try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(&buffer);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}

fn deleteFileIfExists(path: []const u8) !void {
    if (std.fs.path.isAbsolute(path))
        try std.fs.deleteFileAbsolute(path)
    else
        try std.fs.cwd().deleteFile(path);
}

fn writeManifest(path: []const u8, manifest: SessionManifest) !void {
    try ensureParentPath(path);
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

fn writeArtifact(path: []const u8, artifact: ProgramArtifact) !void {
    try ensureParentPath(path);
    const file = if (std.fs.path.isAbsolute(path))
        try std.fs.createFileAbsolute(path, .{ .truncate = true })
    else
        try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(&buffer);
    try std.json.Stringify.value(ArtifactFile{
        .schema_version = current_artifact_schema,
        .identity_hash = artifact.identityHash(),
        .label = artifact.label,
        .steps = artifact.steps,
    }, .{}, &writer.interface);
    try writer.interface.writeByte('\n');
    try writer.interface.flush();
}

fn writePlan(path: []const u8, plan: kernel.ProgramPlan) !void {
    try plan.validate();
    try ensureParentPath(path);
    const file = if (std.fs.path.isAbsolute(path))
        try std.fs.createFileAbsolute(path, .{ .truncate = true })
    else
        try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(&buffer);
    try std.json.Stringify.value(PlanFile{
        .schema_version = current_plan_schema,
        .plan_hash = hashPlan(plan),
        .plan = plan,
    }, .{}, &writer.interface);
    try writer.interface.writeByte('\n');
    try writer.interface.flush();
}

fn writeEvents(path: []const u8, state: *const kernel.State) !void {
    try ensureParentPath(path);
    const file = if (std.fs.path.isAbsolute(path))
        try std.fs.createFileAbsolute(path, .{ .truncate = true })
    else
        try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(&buffer);
    for (kernel.events(state), 0..) |event, seq| {
        try std.json.Stringify.value(EventRecord{
            .schema_version = current_event_schema,
            .seq = seq,
            .event = event,
        }, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
    }
    try writer.interface.flush();
}

fn readManifest(allocator: std.mem.Allocator, path: []const u8) !SessionManifest {
    const bytes = if (std.fs.path.isAbsolute(path)) blk: {
        break :blk try readAbsoluteFileAlloc(allocator, path);
    } else try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(SessionManifest, allocator, bytes, .{});
    defer parsed.deinit();
    if (parsed.value.schema_version != current_manifest_schema) return error.UnsupportedManifestSchema;
    return parsed.value;
}

fn readAbsoluteFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    var buffer: [4096]u8 = undefined;
    var reader = file.reader(&buffer);
    return try reader.interface.allocRemaining(allocator, .limited(std.math.maxInt(usize)));
}

const ReadPlanFileResult = struct {
    stored_schema_version: u32,
    comparison_plan_hash: u64,
    plan: kernel.ProgramPlan,
};

const PlanFileSchemaProbe = struct {
    schema_version: u32 = current_plan_schema,
    plan: ?PlanSchemaProbe = null,
};

const PlanSchemaProbe = struct {
    schema_version: u32 = kernel.ProgramPlan.current_schema_version,
};

fn readArtifactFile(allocator: std.mem.Allocator, path: []const u8) !ReadArtifactFileResult {
    const bytes = if (std.fs.path.isAbsolute(path)) blk: {
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();
        var buffer: [4096]u8 = undefined;
        var reader = file.reader(&buffer);
        break :blk try reader.interface.allocRemaining(allocator, .limited(std.math.maxInt(usize)));
    } else try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
    defer allocator.free(bytes);

    const parsed = try std.json.parseFromSlice(ArtifactFile, allocator, bytes, .{});
    defer parsed.deinit();
    if (parsed.value.schema_version != current_artifact_schema) return error.UnsupportedArtifactSchema;
    return .{
        .stored_schema_version = parsed.value.schema_version,
        .artifact = try cloneArtifact(allocator, parsed.value),
    };
}

fn readPlanFile(allocator: std.mem.Allocator, path: []const u8) !ReadPlanFileResult {
    const bytes = if (std.fs.path.isAbsolute(path)) blk: {
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();
        var buffer: [4096]u8 = undefined;
        var reader = file.reader(&buffer);
        break :blk try reader.interface.allocRemaining(allocator, .limited(std.math.maxInt(usize)));
    } else try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
    defer allocator.free(bytes);

    const schema_probe = try std.json.parseFromSlice(PlanFileSchemaProbe, allocator, bytes, .{
        .ignore_unknown_fields = true,
    });
    defer schema_probe.deinit();
    if (schema_probe.value.schema_version != current_plan_schema) return error.UnsupportedPlanSchema;
    if (schema_probe.value.plan) |plan_probe| {
        if (plan_probe.schema_version != kernel.ProgramPlan.current_schema_version) return error.UnsupportedPlanSchema;
    }

    const parsed = try std.json.parseFromSlice(PlanFile, allocator, bytes, .{});
    defer parsed.deinit();
    if (parsed.value.schema_version != current_plan_schema) return error.UnsupportedPlanSchema;
    var cloned = try clonePlan(allocator, parsed.value.plan);
    errdefer freePlan(allocator, &cloned);
    try cloned.validate();
    return .{
        .stored_schema_version = parsed.value.schema_version,
        .comparison_plan_hash = parsed.value.plan_hash,
        .plan = cloned,
    };
}

fn cloneArtifact(allocator: std.mem.Allocator, artifact: ArtifactFile) !ProgramArtifact {
    return .{
        .label = try allocator.dupe(u8, artifact.label),
        .program_hash = artifact.identity_hash,
        .steps = try cloneSteps(allocator, artifact.steps),
        .plan = null,
    };
}

fn cloneSteps(allocator: std.mem.Allocator, steps: []const kernel.Step) ![]kernel.Step {
    var cloned = try allocator.alloc(kernel.Step, steps.len);
    var count: usize = 0;
    errdefer {
        freeSteps(allocator, cloned[0..count]);
        allocator.free(cloned);
    }
    for (steps, 0..) |step, idx| {
        cloned[idx] = try cloneStep(allocator, step);
        count += 1;
    }
    return cloned;
}

fn cloneStep(allocator: std.mem.Allocator, step: kernel.Step) !kernel.Step {
    return switch (step) {
        .checkpoint => |value| .{ .checkpoint = value },
        .emit => |event| .{ .emit = try cloneEvent(allocator, event) },
        .pop_pending => .pop_pending,
        .push_pending => |frame| .{ .push_pending = frame },
        .set_active_prompt => |prompt| .{ .set_active_prompt = prompt },
        .set_final => |value| .{ .set_final = try cloneValue(allocator, value) },
    };
}

fn cloneEvent(allocator: std.mem.Allocator, event: kernel.Event) !kernel.Event {
    return switch (event) {
        .note => |value| .{ .note = try allocator.dupe(u8, value) },
        .final_i32 => |value| .{ .final_i32 = value },
        .final_string => |value| .{ .final_string = try allocator.dupe(u8, value) },
    };
}

fn freeEvent(allocator: std.mem.Allocator, event: kernel.Event) void {
    switch (event) {
        .note => |value| allocator.free(value),
        .final_i32 => {},
        .final_string => |value| allocator.free(value),
    }
}

fn cloneValue(allocator: std.mem.Allocator, value: kernel.Value) !kernel.Value {
    return switch (value) {
        .none => .none,
        .bool => |flag| .{ .bool = flag },
        .i32 => |number| .{ .i32 = number },
        .string => |line| .{ .string = try allocator.dupe(u8, line) },
    };
}

fn instructionOwnsStringLiteral(instruction: kernel.Instruction) bool {
    return instruction.kind == .const_string or instruction.string_literal.len != 0;
}

fn cloneInstruction(allocator: std.mem.Allocator, instruction: kernel.Instruction) !kernel.Instruction {
    var cloned = instruction;
    if (instructionOwnsStringLiteral(instruction)) {
        cloned.string_literal = try allocator.dupe(u8, instruction.string_literal);
    }
    return cloned;
}

fn freeInstruction(allocator: std.mem.Allocator, instruction: kernel.Instruction) void {
    if (instructionOwnsStringLiteral(instruction)) allocator.free(instruction.string_literal);
}

fn clonePlan(allocator: std.mem.Allocator, plan: kernel.ProgramPlan) !kernel.ProgramPlan {
    var cloned = kernel.ProgramPlan{
        .schema_version = plan.schema_version,
        .label = try allocator.dupe(u8, plan.label),
        .ir_hash = plan.ir_hash,
        .entry_index = plan.entry_index,
        .functions = try allocator.alloc(kernel.FunctionPlan, 0),
        .requirements = try allocator.alloc(kernel.RequirementPlan, 0),
        .ops = try allocator.alloc(kernel.OpPlan, 0),
        .outputs = try allocator.alloc(kernel.OutputPlan, 0),
        .locals = try allocator.alloc(kernel.LocalPlan, 0),
        .call_args = try allocator.alloc(u16, 0),
        .blocks = try allocator.alloc(kernel.BlockPlan, 0),
        .terminators = try allocator.alloc(kernel.Terminator, 0),
        .instructions = try allocator.alloc(kernel.Instruction, 0),
    };
    errdefer freePlan(allocator, &cloned);

    var functions = try allocator.alloc(kernel.FunctionPlan, plan.functions.len);
    errdefer allocator.free(functions);
    var function_count: usize = 0;
    errdefer {
        for (functions[0..function_count]) |function| allocator.free(function.symbol_name);
    }
    for (plan.functions, 0..) |function, index| {
        functions[index] = .{
            .symbol_name = try allocator.dupe(u8, function.symbol_name),
            .value_codec = function.value_codec,
            .parameter_count = function.parameter_count,
            .first_requirement = function.first_requirement,
            .requirement_count = function.requirement_count,
            .first_output = function.first_output,
            .output_count = function.output_count,
            .first_local = function.first_local,
            .local_count = function.local_count,
            .first_block = function.first_block,
            .entry_block = function.entry_block,
            .block_count = function.block_count,
            .first_instruction = function.first_instruction,
            .instruction_count = function.instruction_count,
        };
        function_count += 1;
    }
    allocator.free(cloned.functions);
    cloned.functions = functions;

    var requirements = try allocator.alloc(kernel.RequirementPlan, plan.requirements.len);
    errdefer allocator.free(requirements);
    var requirement_count: usize = 0;
    errdefer {
        for (requirements[0..requirement_count]) |requirement| allocator.free(requirement.label);
    }
    for (plan.requirements, 0..) |requirement, index| {
        requirements[index] = .{
            .label = try allocator.dupe(u8, requirement.label),
            .first_op = requirement.first_op,
            .op_count = requirement.op_count,
        };
        requirement_count += 1;
    }
    allocator.free(cloned.requirements);
    cloned.requirements = requirements;

    var ops = try allocator.alloc(kernel.OpPlan, plan.ops.len);
    errdefer allocator.free(ops);
    var op_count: usize = 0;
    errdefer {
        for (ops[0..op_count]) |op| allocator.free(op.op_name);
    }
    for (plan.ops, 0..) |op, index| {
        ops[index] = .{
            .requirement_index = op.requirement_index,
            .op_name = try allocator.dupe(u8, op.op_name),
            .mode = op.mode,
            .payload_codec = op.payload_codec,
            .resume_codec = op.resume_codec,
        };
        op_count += 1;
    }
    allocator.free(cloned.ops);
    cloned.ops = ops;

    var outputs = try allocator.alloc(kernel.OutputPlan, plan.outputs.len);
    errdefer allocator.free(outputs);
    var output_count: usize = 0;
    errdefer {
        for (outputs[0..output_count]) |output| allocator.free(output.label);
    }
    for (plan.outputs, 0..) |output, index| {
        outputs[index] = .{
            .label = try allocator.dupe(u8, output.label),
            .codec = output.codec,
        };
        output_count += 1;
    }
    allocator.free(cloned.outputs);
    cloned.outputs = outputs;

    const locals = try allocator.dupe(kernel.LocalPlan, plan.locals);
    allocator.free(cloned.locals);
    cloned.locals = locals;

    const call_args = try allocator.dupe(u16, plan.call_args);
    allocator.free(cloned.call_args);
    cloned.call_args = call_args;

    const blocks = try allocator.dupe(kernel.BlockPlan, plan.blocks);
    allocator.free(cloned.blocks);
    cloned.blocks = blocks;

    const terminators = try allocator.dupe(kernel.Terminator, plan.terminators);
    allocator.free(cloned.terminators);
    cloned.terminators = terminators;

    var instructions = try allocator.alloc(kernel.Instruction, plan.instructions.len);
    errdefer allocator.free(instructions);
    var instruction_count: usize = 0;
    errdefer {
        for (instructions[0..instruction_count]) |instruction| freeInstruction(allocator, instruction);
    }
    for (plan.instructions, 0..) |instruction, index| {
        instructions[index] = try cloneInstruction(allocator, instruction);
        instruction_count += 1;
    }
    allocator.free(cloned.instructions);
    cloned.instructions = instructions;
    return cloned;
}

fn freePlan(allocator: std.mem.Allocator, plan: *const kernel.ProgramPlan) void {
    allocator.free(plan.label);
    for (plan.functions) |function| allocator.free(function.symbol_name);
    allocator.free(plan.functions);
    for (plan.requirements) |requirement| allocator.free(requirement.label);
    allocator.free(plan.requirements);
    for (plan.ops) |op| allocator.free(op.op_name);
    allocator.free(plan.ops);
    for (plan.outputs) |output| allocator.free(output.label);
    allocator.free(plan.outputs);
    allocator.free(plan.locals);
    allocator.free(plan.call_args);
    allocator.free(plan.blocks);
    allocator.free(plan.terminators);
    for (plan.instructions) |instruction| freeInstruction(allocator, instruction);
    allocator.free(plan.instructions);
}

fn freeArtifact(allocator: std.mem.Allocator, artifact: *const ProgramArtifact) void {
    allocator.free(artifact.label);
    freeSteps(allocator, artifact.steps);
    allocator.free(artifact.steps);
}

fn freeSteps(allocator: std.mem.Allocator, steps: []const kernel.Step) void {
    for (steps) |step| switch (step) {
        .emit => |event| freeEvent(allocator, event),
        .set_final => |value| switch (value) {
            .string => |line| allocator.free(line),
            else => {},
        },
        else => {},
    };
}

fn readEventRecord(allocator: std.mem.Allocator, line: []const u8, schema_version: u32) !EventRecord {
    const parsed = try std.json.parseFromSlice(EventRecord, allocator, line, .{});
    defer parsed.deinit();
    if (parsed.value.schema_version != schema_version) return error.UnsupportedEventSchema;
    return .{
        .schema_version = parsed.value.schema_version,
        .seq = parsed.value.seq,
        .event = try cloneEvent(allocator, parsed.value.event),
    };
}

fn eventsMatch(
    allocator: std.mem.Allocator,
    path: []const u8,
    schema_version: u32,
    state: *const kernel.State,
    expected_len: usize,
) !EventsMatchResult {
    const bytes = if (std.fs.path.isAbsolute(path)) blk: {
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();
        var buffer: [4096]u8 = undefined;
        var reader = file.reader(&buffer);
        break :blk try reader.interface.allocRemaining(allocator, .limited(std.math.maxInt(usize)));
    } else try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
    defer allocator.free(bytes);

    const expected_events = kernel.events(state);
    if (expected_events.len != expected_len) return .{ .matches = false };

    var line_iter = std.mem.splitScalar(u8, bytes, '\n');
    var seq: usize = 0;
    while (line_iter.next()) |line| {
        if (line.len == 0) continue;
        if (seq >= expected_events.len) return .{ .matches = false };

        const parsed = try readEventRecord(allocator, line, schema_version);
        defer freeEvent(allocator, parsed.event);
        if (parsed.seq != seq) return .{ .matches = false };
        if (!eventEql(parsed.event, expected_events[seq])) return .{ .matches = false };
        seq += 1;
    }
    return .{ .matches = seq == expected_events.len };
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

test "clonePlan owns const_string literals before parse teardown" {
    const allocator = std.testing.allocator;
    const plan_file: PlanFile = .{
        .plan_hash = 0,
        .plan = .{
            .label = "persisted.plan",
            .ir_hash = 0x1234,
            .entry_index = 0,
            .functions = &.{.{
                .symbol_name = "runBody",
                .value_codec = .string,
                .parameter_count = 0,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 1,
                .first_local = 0,
                .local_count = 1,
                .first_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 2,
                .entry_block = 0,
            }},
            .requirements = &.{},
            .ops = &.{},
            .outputs = &.{.{
                .label = "result",
                .codec = .string,
            }},
            .locals = &.{.{ .codec = .string }},
            .call_args = &.{},
            .blocks = &.{.{
                .first_instruction = 0,
                .instruction_count = 2,
                .terminator_index = 0,
            }},
            .terminators = &.{.{
                .kind = .return_value,
                .primary = 0,
            }},
            .instructions = &.{
                .{
                    .kind = .const_string,
                    .dst = 0,
                    .string_literal = "persisted literal",
                },
                .{
                    .kind = .return_value,
                    .operand = 0,
                },
            },
        },
    };
    var json: std.io.Writer.Allocating = .init(allocator);
    defer json.deinit();
    try std.json.Stringify.value(plan_file, .{}, &json.writer);

    const cloned = blk: {
        const parsed = try std.json.parseFromSlice(PlanFile, allocator, json.written(), .{});
        defer parsed.deinit();
        const parsed_literal = parsed.value.plan.instructions[0].string_literal;

        const cloned = try clonePlan(allocator, parsed.value.plan);
        try std.testing.expect(cloned.instructions[0].string_literal.ptr != parsed_literal.ptr);
        break :blk cloned;
    };
    defer freePlan(allocator, &cloned);

    const clobber = try allocator.alloc(u8, cloned.instructions[0].string_literal.len);
    defer allocator.free(clobber);
    @memset(clobber, 'x');

    try std.testing.expectEqualStrings("persisted literal", cloned.instructions[0].string_literal);
}

test "readPlanFile rejects wrapped schema-3 plans" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    const dir_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    const plan_path = try std.fs.path.join(allocator, &.{ dir_path, "legacy.plan.json" });
    defer allocator.free(plan_path);

    const legacy_plan_file = .{
        .schema_version = 3,
        .plan_hash = 0x5678,
        .plan = .{
            .schema_version = 2,
            .label = "legacy.function.metadata",
            .ir_hash = 2,
            .entry_index = 0,
            .functions = &.{.{
                .symbol_name = "root",
                .value_codec = .i32,
                .parameter_count = 2,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 3,
                .first_block = 0,
                .entry_block = 1,
                .block_count = 2,
                .first_instruction = 0,
                .instruction_count = 1,
            }},
            .requirements = &.{},
            .ops = &.{},
            .outputs = &.{},
            .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 }, .{ .codec = .i32 } },
            .blocks = &.{
                .{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 },
                .{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 1 },
            },
            .terminators = &.{
                .{ .kind = .jump, .primary = 1 },
                .{ .kind = .return_value },
            },
            .instructions = &.{.{ .kind = .return_value, .index = 2 }},
        },
    };

    const file = try std.fs.createFileAbsolute(plan_path, .{ .truncate = true });
    defer file.close();
    var buffer: [1024]u8 = undefined;
    var writer = file.writer(&buffer);
    try std.json.Stringify.value(legacy_plan_file, .{}, &writer.interface);
    try writer.interface.writeByte('\n');
    try writer.interface.flush();

    try std.testing.expectError(error.UnsupportedPlanSchema, readPlanFile(allocator, plan_path));
}

test "readPlanFile rejects raw schema-2 plans" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    const dir_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    const plan_path = try std.fs.path.join(allocator, &.{ dir_path, "legacy-raw.plan.json" });
    defer allocator.free(plan_path);

    const file = try std.fs.createFileAbsolute(plan_path, .{ .truncate = true });
    defer file.close();
    var buffer: [1024]u8 = undefined;
    var writer = file.writer(&buffer);
    try writer.interface.writeAll(
        \\{"schema_version":2,"label":"legacy.raw.function.metadata","ir_hash":3,"entry_index":0,"functions":[{"symbol_name":"root","value_codec":"i32","parameter_count":1,"first_requirement":0,"requirement_count":0,"first_output":0,"output_count":0,"first_local":0,"local_count":2,"first_block":0,"entry_block":1,"block_count":2,"first_instruction":0,"instruction_count":1}],"requirements":[],"ops":[],"outputs":[],"locals":[{"codec":"i32"},{"codec":"i32"}],"blocks":[{"first_instruction":0,"instruction_count":0,"terminator_index":0},{"first_instruction":0,"instruction_count":1,"terminator_index":1}],"terminators":[{"kind":"jump","primary":1},{"kind":"return_value"}],"instructions":[{"kind":"return_value","index":1}]}
    );
    try writer.interface.writeByte('\n');
    try writer.interface.flush();

    try std.testing.expectError(error.UnsupportedPlanSchema, readPlanFile(allocator, plan_path));
}

test "readPlanFile rejects raw schema-3 plans" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    const dir_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    const plan_path = try std.fs.path.join(allocator, &.{ dir_path, "legacy-raw-schema3.plan.json" });
    defer allocator.free(plan_path);

    const legacy_plan = kernel.ProgramPlan{
        .schema_version = 3,
        .label = "legacy.raw.schema3.hash",
        .ir_hash = 4,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "root",
            .value_codec = .i32,
            .parameter_count = 1,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 2,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .i32 }, .{ .codec = .i32 } },
        .call_args = &.{0},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{.{ .kind = .return_value, .dst = 1, .operand = 1, .aux = 0 }},
    };

    const file = try std.fs.createFileAbsolute(plan_path, .{ .truncate = true });
    defer file.close();
    var buffer: [1024]u8 = undefined;
    var writer = file.writer(&buffer);
    try std.json.Stringify.value(legacy_plan, .{}, &writer.interface);
    try writer.interface.writeByte('\n');
    try writer.interface.flush();

    try std.testing.expectError(error.UnsupportedPlanSchema, readPlanFile(allocator, plan_path));
}
