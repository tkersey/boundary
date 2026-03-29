const shift = @import("shift");
const std = @import("std");

test "durable store replays the canonical event log exactly" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(dir_path);
    const manifest_path = try std.fs.path.join(std.testing.allocator, &.{ dir_path, "session.manifest.json" });
    defer std.testing.allocator.free(manifest_path);
    const events_path = try std.fs.path.join(std.testing.allocator, &.{ dir_path, "events.jsonl" });
    defer std.testing.allocator.free(events_path);

    const store = shift.durable.Store.init(std.testing.allocator, manifest_path, events_path);
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

    const dir_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(dir_path);
    const manifest_abs = try std.fs.path.join(std.testing.allocator, &.{ dir_path, "session.manifest.json" });
    defer std.testing.allocator.free(manifest_abs);
    const events_abs = try std.fs.path.join(std.testing.allocator, &.{ dir_path, "events.jsonl" });
    defer std.testing.allocator.free(events_abs);

    const store = shift.durable.Store.init(std.testing.allocator, manifest_abs, events_abs);
    const restored = try store.restore();
    try std.testing.expectEqual(shift.durable.RestoreStatus.rebuild_required, restored.status);
}

test "durable restore reports rebuild required on artifact mismatch" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const dir_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(dir_path);
    const manifest_abs = try std.fs.path.join(std.testing.allocator, &.{ dir_path, "session.manifest.json" });
    defer std.testing.allocator.free(manifest_abs);
    const events_abs = try std.fs.path.join(std.testing.allocator, &.{ dir_path, "events.jsonl" });
    defer std.testing.allocator.free(events_abs);

    const store = shift.durable.Store.init(std.testing.allocator, manifest_abs, events_abs);
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

    const dir_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(dir_path);
    const manifest_abs = try std.fs.path.join(std.testing.allocator, &.{ dir_path, "session.manifest.json" });
    defer std.testing.allocator.free(manifest_abs);
    const events_abs = try std.fs.path.join(std.testing.allocator, &.{ dir_path, "events.jsonl" });
    defer std.testing.allocator.free(events_abs);

    const store = shift.durable.Store.init(std.testing.allocator, manifest_abs, events_abs);
    _ = try store.saveScenario(.direct_return);

    {
        const file = try std.fs.cwd().createFile(events_abs, .{ .truncate = true });
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
