const shift = @import("shift");
const std = @import("std");

const TestPaths = struct {
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
        return .{
            .dir_path = dir_path,
            .manifest_path = manifest_path,
            .events_path = events_path,
            .plan_path = plan_path,
        };
    }

    fn deinit(self: *const TestPaths) void {
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
                .index = 0,
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
    _ = try std.fs.cwd().statFile(paths.plan_path);

    const restored = try store.restoreArtifact(artifact);
    try std.testing.expectEqual(shift.durable.RestoreStatus.exact_replay, restored.status);
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
        try std.json.Stringify.value(tampered, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }

    const restored = try store.restoreArtifact(artifact);
    try std.testing.expectEqual(shift.durable.RestoreStatus.failed, restored.status);
}
