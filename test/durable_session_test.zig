const shift = @import("shift");
const std = @import("std");

const TestPaths = struct {
    artifact_path: []u8,
    dir_path: []u8,
    manifest_path: []u8,
    events_path: []u8,
    plan_path: []u8,

    fn init(tmp: *std.testing.TmpDir) !TestPaths {
        const dir_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
        errdefer std.testing.allocator.free(dir_path);
        const manifest_path = try std.fs.path.join(std.testing.allocator, &.{ dir_path, "session.manifest.json" });
        errdefer std.testing.allocator.free(manifest_path);
        const events_path = try std.fs.path.join(std.testing.allocator, &.{ dir_path, "events.jsonl" });
        errdefer std.testing.allocator.free(events_path);
        const plan_path = try std.fs.path.join(std.testing.allocator, &.{ dir_path, "plan.json" });
        errdefer std.testing.allocator.free(plan_path);
        const artifact_path = try std.fs.path.join(std.testing.allocator, &.{ dir_path, "artifact.json" });
        errdefer std.testing.allocator.free(artifact_path);
        return .{
            .artifact_path = artifact_path,
            .dir_path = dir_path,
            .manifest_path = manifest_path,
            .events_path = events_path,
            .plan_path = plan_path,
        };
    }

    fn deinit(self: *const TestPaths) void {
        std.testing.allocator.free(self.artifact_path);
        std.testing.allocator.free(self.plan_path);
        std.testing.allocator.free(self.events_path);
        std.testing.allocator.free(self.manifest_path);
        std.testing.allocator.free(self.dir_path);
    }
};

fn makePlanBackedArtifact(
    artifact_hash: u64,
    plan_ir_hash: u64,
    comptime plan_label: []const u8,
    comptime function_symbol: []const u8,
) shift.durable.ProgramArtifact {
    return .{
        .label = "plan_backed",
        .program_hash = artifact_hash,
        .steps = &.{
            .{ .emit = .{ .note = "plan-backed" } },
            .{ .emit = .{ .final_i32 = 7 } },
        },
        .plan = .{
            .label = plan_label,
            .ir_hash = plan_ir_hash,
            .entry_index = 0,
            .functions = &.{.{
                .symbol_name = function_symbol,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 1,
                .first_local = 0,
                .local_count = 0,
                .first_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 1,
            }},
            .requirements = &.{},
            .ops = &.{},
            .outputs = &.{.{
                .label = "result",
                .codec = .i32,
            }},
            .locals = &.{},
            .blocks = &.{.{
                .first_instruction = 0,
                .instruction_count = 1,
                .terminator_index = 0,
            }},
            .terminators = &.{.{
                .kind = .return_value,
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

test "durable store replays the canonical event log exactly" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    const manifest = try store.saveScenario(.direct_return);
    try std.testing.expectEqual(@as(usize, 2), manifest.last_seq);
    try std.testing.expect(manifest.program_hash != 0);
    const restored = try store.restore();
    try std.testing.expectEqual(shift.durable.RestoreStatus.exact_replay, restored.status);
    try std.testing.expectEqual(@as(?shift.durable.MigrationReport, null), restored.migration_report);
    try std.testing.expectEqual(@as(usize, 2), shift.interpreter.events(&restored.state.?).len);
}

test "durable restore reports rebuild required on schema mismatch" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const manifest = shift.durable.SessionManifest{
        .schema_version = 999,
        .scenario_id = .direct_return,
        .program_hash = 1,
        .last_seq = 1,
    };

    {
        const file = try tmp.dir.createFile("session.manifest.json", .{ .truncate = true });
        defer file.close();
        var buffer: [1024]u8 = undefined;
        var writer = file.writer(&buffer);
        try std.json.Stringify.value(manifest, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }
    {
        const file = try tmp.dir.createFile("events.jsonl", .{ .truncate = true });
        defer file.close();
    }

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    const restored = try store.restore();
    try std.testing.expectEqual(shift.durable.RestoreStatus.rebuild_required, restored.status);
}

test "durable restore reports rebuild required on artifact mismatch" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    _ = try store.saveScenario(.direct_return);

    const artifact = shift.durable.ProgramArtifact{
        .label = "direct_return",
        .program_hash = 42,
        .steps = &.{},
    };
    const restored = try store.restoreArtifact(artifact);
    try std.testing.expectEqual(shift.durable.RestoreStatus.rebuild_required, restored.status);
}

test "durable restore fails when the event log is tampered" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    _ = try store.saveScenario(.direct_return);

    {
        const file = try std.fs.cwd().createFile(paths.events_path, .{ .truncate = true });
        defer file.close();
        var buffer: [1024]u8 = undefined;
        var writer = file.writer(&buffer);
        try std.json.Stringify.value(shift.durable.EventRecord{
            .seq = 0,
            .event = .{ .note = "tampered" },
        }, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }

    const restored = try store.restore();
    try std.testing.expectEqual(shift.durable.RestoreStatus.failed, restored.status);
}

test "durable saveArtifact persists plan-backed identity and plan.json" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const artifact = makePlanBackedArtifact(99, 0x1234, "demo.plan", "runBody");
    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    const manifest = try store.saveArtifact(artifact, null);

    try std.testing.expectEqual(@as(u64, 0x1234), manifest.program_hash);
    try std.testing.expect(manifest.plan_hash != null);
    try std.testing.expectEqual(@as(?u32, 1), manifest.artifact_schema_version);
    try std.testing.expectEqual(@as(?u32, 4), manifest.plan_schema_version);
    try std.testing.expectEqual(@as(?u32, 1), manifest.event_schema_version);
    _ = try std.fs.cwd().statFile(paths.plan_path);
    _ = try std.fs.cwd().statFile(paths.artifact_path);

    const artifact_bytes = try std.fs.cwd().readFileAlloc(std.testing.allocator, paths.artifact_path, std.math.maxInt(usize));
    defer std.testing.allocator.free(artifact_bytes);
    const parsed_artifact = try std.json.parseFromSlice(shift.durable.ArtifactFile, std.testing.allocator, artifact_bytes, .{});
    defer parsed_artifact.deinit();
    try std.testing.expectEqual(@as(u32, 1), parsed_artifact.value.schema_version);
    try std.testing.expectEqual(@as(u64, 0x1234), parsed_artifact.value.identity_hash);
    try std.testing.expectEqualStrings("plan_backed", parsed_artifact.value.label);

    const restored = try store.restoreArtifact(artifact);
    try std.testing.expectEqual(shift.durable.RestoreStatus.exact_replay, restored.status);
    try std.testing.expectEqual(@as(?shift.durable.MigrationReport, null), restored.migration_report);
}

test "durable restore and inspect use persisted non-scenario artifact provenance" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const artifact = makePlanBackedArtifact(0x9234, 0x9234, "demo.plan", "runBody");
    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    _ = try store.saveArtifact(artifact, null);

    const inspected = try store.inspectRestore();
    try std.testing.expectEqual(shift.durable.RestoreStatus.exact_replay, inspected.status);
    try std.testing.expectEqual(@as(?shift.durable.MigrationReport, null), inspected.migration_report);

    const restored = try store.restore();
    try std.testing.expectEqual(shift.durable.RestoreStatus.exact_replay, restored.status);
    try std.testing.expectEqual(@as(?shift.durable.MigrationReport, null), restored.migration_report);
}

test "durable restore accepts a matching step bridge when persisted plan.json is valid" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const artifact = makePlanBackedArtifact(0x2234, 0x2234, "demo.plan", "runBody");
    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    _ = try store.saveArtifact(artifact, null);

    var stripped = artifact;
    stripped.plan = null;

    const restored = try store.restoreArtifact(stripped);
    try std.testing.expectEqual(shift.durable.RestoreStatus.exact_replay, restored.status);
    try std.testing.expectEqual(@as(?shift.durable.MigrationReport, null), restored.migration_report);
}

test "durable restore accepts legacy schema manifest and raw plan.json" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const artifact = makePlanBackedArtifact(0x5234, 0x5234, "demo.plan", "runBody");
    const legacy_manifest = shift.durable.SessionManifest{
        .schema_version = 2,
        .scenario_id = null,
        .program_hash = artifact.plan.?.ir_hash,
        .plan_hash = 0x0,
        .plan_schema_version = null,
        .last_seq = 2,
    };

    const raw_plan_hash = artifact.plan.?.hash();

    {
        const file = try std.fs.cwd().createFile(paths.manifest_path, .{ .truncate = true });
        defer file.close();
        var buffer: [1024]u8 = undefined;
        var writer = file.writer(&buffer);
        var manifest = legacy_manifest;
        manifest.plan_hash = raw_plan_hash;
        try std.json.Stringify.value(manifest, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }
    {
        const file = try std.fs.cwd().createFile(paths.plan_path, .{ .truncate = true });
        defer file.close();
        var buffer: [1024]u8 = undefined;
        var writer = file.writer(&buffer);
        try std.json.Stringify.value(artifact.plan.?, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }
    {
        const file = try std.fs.cwd().createFile(paths.events_path, .{ .truncate = true });
        defer file.close();
        var buffer: [1024]u8 = undefined;
        var writer = file.writer(&buffer);
        const LegacyEventRecord = struct {
            seq: usize,
            event: shift.interpreter.Event,
        };
        try std.json.Stringify.value(LegacyEventRecord{ .seq = 0, .event = .{ .note = "plan-backed" } }, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
        try std.json.Stringify.value(LegacyEventRecord{ .seq = 1, .event = .{ .final_i32 = 7 } }, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }

    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    var stripped = artifact;
    stripped.plan = null;

    const inspected = try store.inspectRestoreArtifact(stripped);
    try std.testing.expectEqual(shift.durable.RestoreStatus.migrated_replay, inspected.status);
    const inspected_report = inspected.migration_report orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(u32, 0), inspected_report.event_schema.?.from);
    try std.testing.expectEqual(@as(u32, 1), inspected_report.event_schema.?.to_schema);
    try std.testing.expectEqual(@as(u32, 2), inspected_report.manifest_schema.?.from);
    try std.testing.expectEqual(@as(u32, 5), inspected_report.manifest_schema.?.to_schema);
    try std.testing.expectEqual(@as(u32, 0), inspected_report.plan_file_schema.?.from);
    try std.testing.expectEqual(@as(u32, 4), inspected_report.plan_file_schema.?.to_schema);
    try std.testing.expect(!inspected_report.rewrote_events);
    try std.testing.expect(!inspected_report.rewrote_manifest);
    try std.testing.expect(!inspected_report.rewrote_plan_file);

    const restored = try store.restoreArtifact(stripped);
    try std.testing.expectEqual(shift.durable.RestoreStatus.migrated_replay, restored.status);
    const report = restored.migration_report orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(u32, 0), report.event_schema.?.from);
    try std.testing.expectEqual(@as(u32, 1), report.event_schema.?.to_schema);
    try std.testing.expectEqual(@as(u32, 2), report.manifest_schema.?.from);
    try std.testing.expectEqual(@as(u32, 5), report.manifest_schema.?.to_schema);
    try std.testing.expectEqual(@as(u32, 0), report.plan_file_schema.?.from);
    try std.testing.expectEqual(@as(u32, 4), report.plan_file_schema.?.to_schema);
    try std.testing.expect(report.rewrote_events);
    try std.testing.expect(report.rewrote_manifest);
    try std.testing.expect(report.rewrote_plan_file);

    const rewritten_manifest_bytes = try std.fs.cwd().readFileAlloc(std.testing.allocator, paths.manifest_path, std.math.maxInt(usize));
    defer std.testing.allocator.free(rewritten_manifest_bytes);
    const rewritten_manifest = try std.json.parseFromSlice(shift.durable.SessionManifest, std.testing.allocator, rewritten_manifest_bytes, .{});
    defer rewritten_manifest.deinit();
    try std.testing.expectEqual(@as(u32, 5), rewritten_manifest.value.schema_version);
    try std.testing.expectEqual(@as(?u32, 4), rewritten_manifest.value.plan_schema_version);
    try std.testing.expectEqual(@as(?u32, 1), rewritten_manifest.value.event_schema_version);

    const rewritten_plan_bytes = try std.fs.cwd().readFileAlloc(std.testing.allocator, paths.plan_path, std.math.maxInt(usize));
    defer std.testing.allocator.free(rewritten_plan_bytes);
    const rewritten_plan = try std.json.parseFromSlice(shift.durable.PlanFile, std.testing.allocator, rewritten_plan_bytes, .{});
    defer rewritten_plan.deinit();
    try std.testing.expectEqual(@as(u32, 4), rewritten_plan.value.schema_version);

    const restored_again = try store.restoreArtifact(stripped);
    try std.testing.expectEqual(shift.durable.RestoreStatus.exact_replay, restored_again.status);
    try std.testing.expectEqual(@as(?shift.durable.MigrationReport, null), restored_again.migration_report);
}

test "durable saveArtifact writes versioned event rows" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    _ = try store.saveScenario(.direct_return);

    const bytes = try std.fs.cwd().readFileAlloc(std.testing.allocator, paths.events_path, std.math.maxInt(usize));
    defer std.testing.allocator.free(bytes);
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    const first = lines.next() orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(shift.durable.EventRecord, std.testing.allocator, first, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 1), parsed.value.schema_version);
}

test "durable restore accepts legacy raw event rows" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const artifact = makePlanBackedArtifact(0x7234, 0x7234, "demo.plan", "runBody");
    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    var manifest = try store.saveArtifact(artifact, null);
    manifest.event_schema_version = 0;

    {
        const file = try std.fs.cwd().createFile(paths.manifest_path, .{ .truncate = true });
        defer file.close();
        var buffer: [1024]u8 = undefined;
        var writer = file.writer(&buffer);
        try std.json.Stringify.value(manifest, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }
    {
        const file = try std.fs.cwd().createFile(paths.events_path, .{ .truncate = true });
        defer file.close();
        var buffer: [1024]u8 = undefined;
        var writer = file.writer(&buffer);
        const LegacyEventRecord = struct {
            seq: usize,
            event: shift.interpreter.Event,
        };
        try std.json.Stringify.value(LegacyEventRecord{
            .seq = 0,
            .event = .{ .note = "plan-backed" },
        }, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
        try std.json.Stringify.value(LegacyEventRecord{
            .seq = 1,
            .event = .{ .final_i32 = 7 },
        }, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }

    const inspected = try store.inspectRestoreArtifact(artifact);
    try std.testing.expectEqual(shift.durable.RestoreStatus.migrated_replay, inspected.status);
    const inspected_report = inspected.migration_report orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(u32, 0), inspected_report.event_schema.?.from);
    try std.testing.expectEqual(@as(u32, 1), inspected_report.event_schema.?.to_schema);
    try std.testing.expectEqual(@as(?shift.durable.VersionHop, null), inspected_report.manifest_schema);
    try std.testing.expectEqual(@as(?shift.durable.VersionHop, null), inspected_report.plan_file_schema);
    try std.testing.expect(!inspected_report.rewrote_events);
    try std.testing.expect(!inspected_report.rewrote_manifest);
    try std.testing.expect(!inspected_report.rewrote_plan_file);

    const restored = try store.restoreArtifact(artifact);
    try std.testing.expectEqual(shift.durable.RestoreStatus.migrated_replay, restored.status);
    const report = restored.migration_report orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(u32, 0), report.event_schema.?.from);
    try std.testing.expectEqual(@as(u32, 1), report.event_schema.?.to_schema);
    try std.testing.expectEqual(@as(?shift.durable.VersionHop, null), report.manifest_schema);
    try std.testing.expectEqual(@as(?shift.durable.VersionHop, null), report.plan_file_schema);
    try std.testing.expect(report.rewrote_events);
    try std.testing.expect(report.rewrote_manifest);
    try std.testing.expect(!report.rewrote_plan_file);

    const rewritten_manifest_bytes = try std.fs.cwd().readFileAlloc(std.testing.allocator, paths.manifest_path, std.math.maxInt(usize));
    defer std.testing.allocator.free(rewritten_manifest_bytes);
    const rewritten_manifest = try std.json.parseFromSlice(shift.durable.SessionManifest, std.testing.allocator, rewritten_manifest_bytes, .{});
    defer rewritten_manifest.deinit();
    try std.testing.expectEqual(@as(?u32, 1), rewritten_manifest.value.event_schema_version);

    const events_bytes = try std.fs.cwd().readFileAlloc(std.testing.allocator, paths.events_path, std.math.maxInt(usize));
    defer std.testing.allocator.free(events_bytes);
    var lines = std.mem.splitScalar(u8, events_bytes, '\n');
    const first = lines.next() orelse return error.TestExpectedEqual;
    const parsed = try std.json.parseFromSlice(shift.durable.EventRecord, std.testing.allocator, first, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 1), parsed.value.schema_version);

    const restored_again = try store.restoreArtifact(artifact);
    try std.testing.expectEqual(shift.durable.RestoreStatus.exact_replay, restored_again.status);
    try std.testing.expectEqual(@as(?shift.durable.MigrationReport, null), restored_again.migration_report);
}

test "durable restore reports rebuild required on unknown event schema" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const artifact = makePlanBackedArtifact(0x8234, 0x8234, "demo.plan", "runBody");
    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    var manifest = try store.saveArtifact(artifact, null);
    manifest.event_schema_version = 999;

    {
        const file = try std.fs.cwd().createFile(paths.manifest_path, .{ .truncate = true });
        defer file.close();
        var buffer: [1024]u8 = undefined;
        var writer = file.writer(&buffer);
        try std.json.Stringify.value(manifest, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }

    const restored = try store.restoreArtifact(artifact);
    try std.testing.expectEqual(shift.durable.RestoreStatus.rebuild_required, restored.status);
}

test "durable restore reports rebuild required on unknown artifact schema" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const artifact = makePlanBackedArtifact(0x8334, 0x8334, "demo.plan", "runBody");
    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    var manifest = try store.saveArtifact(artifact, null);
    manifest.scenario_id = null;
    manifest.artifact_schema_version = 999;

    {
        const file = try std.fs.cwd().createFile(paths.manifest_path, .{ .truncate = true });
        defer file.close();
        var buffer: [1024]u8 = undefined;
        var writer = file.writer(&buffer);
        try std.json.Stringify.value(manifest, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }

    const restored = try store.restore();
    try std.testing.expectEqual(shift.durable.RestoreStatus.rebuild_required, restored.status);
}

test "durable restore reports rebuild required on unknown plan schema" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const artifact = makePlanBackedArtifact(0x6234, 0x6234, "demo.plan", "runBody");
    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    var manifest = try store.saveArtifact(artifact, null);
    manifest.plan_schema_version = 999;

    {
        const file = try std.fs.cwd().createFile(paths.manifest_path, .{ .truncate = true });
        defer file.close();
        var buffer: [1024]u8 = undefined;
        var writer = file.writer(&buffer);
        try std.json.Stringify.value(manifest, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }

    const restored = try store.restoreArtifact(artifact);
    try std.testing.expectEqual(shift.durable.RestoreStatus.rebuild_required, restored.status);
}

test "durable restore reports rebuild required when the current plan drifts" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const saved = makePlanBackedArtifact(0x3234, 0x3234, "demo.plan", "runBody");
    const drifted = makePlanBackedArtifact(0x3234, 0x3234, "demo.plan", "runBodyV2");
    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    _ = try store.saveArtifact(saved, null);

    const restored = try store.restoreArtifact(drifted);
    try std.testing.expectEqual(shift.durable.RestoreStatus.rebuild_required, restored.status);
}

test "durable restore reports rebuild required when only function span layout drifts" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const saved = makePlanBackedArtifact(0x9234, 0x9234, "demo.plan", "runBody");
    const saved_plan = saved.plan.?;
    const drifted = shift.durable.ProgramArtifact{
        .label = saved.label,
        .program_hash = saved.program_hash,
        .steps = saved.steps,
        .plan = .{
            .label = saved_plan.label,
            .ir_hash = saved_plan.ir_hash,
            .entry_index = saved_plan.entry_index,
            .functions = &.{.{
                .symbol_name = saved_plan.functions[0].symbol_name,
                .value_codec = saved_plan.functions[0].value_codec,
                .parameter_count = saved_plan.functions[0].parameter_count,
                .first_requirement = saved_plan.functions[0].first_requirement,
                .requirement_count = saved_plan.functions[0].requirement_count,
                .first_output = saved_plan.functions[0].first_output,
                .output_count = saved_plan.functions[0].output_count,
                .first_local = saved_plan.functions[0].first_local,
                .local_count = 1,
                .first_block = saved_plan.functions[0].first_block,
                .block_count = 2,
                .first_instruction = saved_plan.functions[0].first_instruction,
                .instruction_count = saved_plan.functions[0].instruction_count,
            }},
            .requirements = saved_plan.requirements,
            .ops = saved_plan.ops,
            .outputs = saved_plan.outputs,
            .locals = saved_plan.locals,
            .call_args = saved_plan.call_args,
            .blocks = saved_plan.blocks,
            .terminators = saved_plan.terminators,
            .instructions = saved_plan.instructions,
        },
    };

    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    _ = try store.saveArtifact(saved, null);

    const restored = try store.restoreArtifact(drifted);
    try std.testing.expectEqual(shift.durable.RestoreStatus.rebuild_required, restored.status);
}

test "durable restore fails when plan.json is tampered" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const artifact = makePlanBackedArtifact(0x4234, 0x4234, "demo.plan", "runBody");
    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    _ = try store.saveArtifact(artifact, null);

    {
        const file = try std.fs.cwd().createFile(paths.plan_path, .{ .truncate = true });
        defer file.close();
        var buffer: [1024]u8 = undefined;
        var writer = file.writer(&buffer);
        var tampered = artifact.plan.?;
        tampered.label = "tampered.plan";
        try std.json.Stringify.value(shift.durable.PlanFile{
            .schema_version = 4,
            .plan_hash = 0,
            .plan = tampered,
        }, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }

    const restored = try store.restoreArtifact(artifact);
    try std.testing.expectEqual(shift.durable.RestoreStatus.failed, restored.status);
}
