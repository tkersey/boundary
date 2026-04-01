const shift = @import("shift");
const std = @import("std");

const TestPaths = struct {
    artifact_path: []u8,
    dir_path: []u8,
    manifest_path: []u8,
    events_path: []u8,
    plan_path: []u8,

    fn init(tmp: *std.testing.TmpDir) !TestPaths {
        return try initNamed(tmp, "session");
    }

    fn initNamed(tmp: *std.testing.TmpDir, session_name: []const u8) !TestPaths {
        const dir_path = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
        errdefer std.testing.allocator.free(dir_path);
        const manifest_name = try std.fmt.allocPrint(std.testing.allocator, "{s}.manifest.json", .{session_name});
        defer std.testing.allocator.free(manifest_name);
        const manifest_path = try std.fs.path.join(std.testing.allocator, &.{ dir_path, manifest_name });
        errdefer std.testing.allocator.free(manifest_path);
        const events_name = try std.fmt.allocPrint(std.testing.allocator, "{s}.events.jsonl", .{session_name});
        defer std.testing.allocator.free(events_name);
        const events_path = try std.fs.path.join(std.testing.allocator, &.{ dir_path, events_name });
        errdefer std.testing.allocator.free(events_path);
        const plan_name = try std.fmt.allocPrint(std.testing.allocator, "{s}.plan.json", .{session_name});
        defer std.testing.allocator.free(plan_name);
        const plan_path = try std.fs.path.join(std.testing.allocator, &.{ dir_path, plan_name });
        errdefer std.testing.allocator.free(plan_path);
        const artifact_name = try std.fmt.allocPrint(std.testing.allocator, "{s}.artifact.json", .{session_name});
        defer std.testing.allocator.free(artifact_name);
        const artifact_path = try std.fs.path.join(std.testing.allocator, &.{ dir_path, artifact_name });
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
                .value_codec = .i32,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 1,
                .first_local = 0,
                .local_count = 1,
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
            .locals = &.{.{ .codec = .i32 }},
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

fn legacyPlanPathAlloc(allocator: std.mem.Allocator, manifest_path: []const u8) ![]u8 {
    const dir_path = std.fs.path.dirname(manifest_path) orelse "";
    if (dir_path.len != 0) return try std.fs.path.join(allocator, &.{ dir_path, "plan.json" });
    return try allocator.dupe(u8, "plan.json");
}

fn allocRepeatedNoteSteps(allocator: std.mem.Allocator, count: usize) ![]shift.interpreter.Step {
    const steps = try allocator.alloc(shift.interpreter.Step, count);
    for (steps) |*step| {
        step.* = .{ .emit = .{ .note = "queued" } };
    }
    return steps;
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

test "durable restore replays owned string event payloads" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const artifact: shift.durable.ProgramArtifact = .{
        .label = "string_events",
        .program_hash = 0x7a11,
        .steps = &.{
            .{ .emit = .{ .note = "plan-backed" } },
            .{ .emit = .{ .final_string = "done" } },
        },
    };

    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    _ = try store.saveArtifact(artifact, null);

    const restored = try store.restoreArtifact(artifact);
    try std.testing.expectEqual(shift.durable.RestoreStatus.exact_replay, restored.status);
    try std.testing.expectEqual(@as(?shift.durable.MigrationReport, null), restored.migration_report);
    const events = shift.interpreter.events(&restored.state.?);
    try std.testing.expectEqual(@as(usize, 2), events.len);
    try std.testing.expectEqualStrings("plan-backed", switch (events[0]) {
        .note => |value| value,
        else => return error.TestExpectedEqual,
    });
    try std.testing.expectEqualStrings("done", switch (events[1]) {
        .final_string => |value| value,
        else => return error.TestExpectedEqual,
    });
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

test "durable saveArtifact rejects structurally invalid plan-backed artifacts" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const invalid_artifact: shift.durable.ProgramArtifact = .{
        .label = "invalid_plan_backed",
        .program_hash = 0x1234,
        .steps = &.{
            .{ .emit = .{ .note = "plan-backed" } },
            .{ .emit = .{ .final_i32 = 7 } },
        },
        .plan = .{
            .label = "invalid.plan",
            .ir_hash = 0x1234,
            .entry_index = 0,
            .functions = &.{.{
                .symbol_name = "runBody",
                .value_codec = .i32,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 1,
                .first_local = 0,
                .local_count = 1,
                .first_block = 0,
                .block_count = 0,
                .first_instruction = 0,
                .instruction_count = 1,
            }},
            .requirements = &.{},
            .ops = &.{},
            .outputs = &.{.{ .label = "result", .codec = .i32 }},
            .locals = &.{.{ .codec = .i32 }},
            .blocks = &.{},
            .terminators = &.{},
            .instructions = &.{.{ .kind = .return_value, .operand = 0 }},
        },
    };

    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    try std.testing.expectError(error.InvalidFunctionEntryBlock, store.saveArtifact(invalid_artifact, null));
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().statFile(paths.manifest_path));
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().statFile(paths.artifact_path));
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().statFile(paths.plan_path));
}

test "durable saveArtifact rejects non-scenario artifacts when scenario_id is set" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const artifact = makePlanBackedArtifact(99, 0x1234, "demo.plan", "runBody");
    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);

    try std.testing.expectError(error.ScenarioArtifactMismatch, store.saveArtifact(artifact, .direct_return));
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().statFile(paths.manifest_path));
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().statFile(paths.artifact_path));
}

test "durable restore rejects tampered plan-backed artifact payloads even when events match" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const artifact = makePlanBackedArtifact(0x2234, 0x2234, "demo.plan", "runBody");
    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    _ = try store.saveArtifact(artifact, null);

    {
        const file = try std.fs.cwd().createFile(paths.artifact_path, .{ .truncate = true });
        defer file.close();
        var buffer: [1024]u8 = undefined;
        var writer = file.writer(&buffer);
        try std.json.Stringify.value(shift.durable.ArtifactFile{
            .schema_version = 1,
            .identity_hash = artifact.identityHash(),
            .label = artifact.label,
            .steps = &.{
                .{ .emit = .{ .note = "tampered" } },
                .{ .emit = .{ .final_i32 = 9 } },
            },
        }, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }
    {
        const file = try std.fs.cwd().createFile(paths.events_path, .{ .truncate = true });
        defer file.close();
        var buffer: [1024]u8 = undefined;
        var writer = file.writer(&buffer);
        try std.json.Stringify.value(shift.durable.EventRecord{
            .schema_version = 1,
            .seq = 0,
            .event = .{ .note = "tampered" },
        }, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
        try std.json.Stringify.value(shift.durable.EventRecord{
            .schema_version = 1,
            .seq = 1,
            .event = .{ .final_i32 = 9 },
        }, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }

    const restored = try store.restore();
    try std.testing.expectEqual(shift.durable.RestoreStatus.rebuild_required, restored.status);
}

test "durable saveArtifact restores the previous checkpoint when a later write fails" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const baseline_artifact = makePlanBackedArtifact(0x9911, 0x1234, "baseline.plan", "runBody");
    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    _ = try store.saveArtifact(baseline_artifact, null);

    const bad_events_path = try std.fs.path.join(std.testing.allocator, &.{ paths.dir_path, "missing", "events.jsonl" });
    defer std.testing.allocator.free(bad_events_path);
    const failing_store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, bad_events_path);
    const replacement_artifact = makePlanBackedArtifact(0x8822, 0x5678, "replacement.plan", "replacementBody");
    try std.testing.expectError(error.FileNotFound, failing_store.saveArtifact(replacement_artifact, null));

    const artifact_bytes = try std.fs.cwd().readFileAlloc(std.testing.allocator, paths.artifact_path, std.math.maxInt(usize));
    defer std.testing.allocator.free(artifact_bytes);
    const parsed_artifact = try std.json.parseFromSlice(shift.durable.ArtifactFile, std.testing.allocator, artifact_bytes, .{});
    defer parsed_artifact.deinit();
    try std.testing.expectEqual(@as(u64, 0x1234), parsed_artifact.value.identity_hash);

    const manifest_bytes = try std.fs.cwd().readFileAlloc(std.testing.allocator, paths.manifest_path, std.math.maxInt(usize));
    defer std.testing.allocator.free(manifest_bytes);
    const parsed_manifest = try std.json.parseFromSlice(shift.durable.SessionManifest, std.testing.allocator, manifest_bytes, .{});
    defer parsed_manifest.deinit();
    try std.testing.expectEqual(@as(u64, 0x1234), parsed_manifest.value.program_hash);

    const plan_bytes = try std.fs.cwd().readFileAlloc(std.testing.allocator, paths.plan_path, std.math.maxInt(usize));
    defer std.testing.allocator.free(plan_bytes);
    const parsed_plan = try std.json.parseFromSlice(shift.durable.PlanFile, std.testing.allocator, plan_bytes, .{});
    defer parsed_plan.deinit();
    try std.testing.expectEqual(@as(u64, 0x1234), parsed_plan.value.plan.ir_hash);

    const restored = try store.restore();
    try std.testing.expectEqual(shift.durable.RestoreStatus.exact_replay, restored.status);
    try std.testing.expectEqual(@as(?shift.durable.MigrationReport, null), restored.migration_report);
}

test "durable stores keep manifest-scoped sidecars when two sessions share one directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const first_paths = try TestPaths.initNamed(&tmp, "first");
    defer first_paths.deinit();
    const second_paths = try TestPaths.initNamed(&tmp, "second");
    defer second_paths.deinit();

    const first_artifact = makePlanBackedArtifact(11, 0x1111, "first.plan", "runBody");
    const second_artifact = makePlanBackedArtifact(22, 0x2222, "second.plan", "runBody");

    const first_store = shift.durable.Store.init(std.testing.allocator, first_paths.manifest_path, first_paths.events_path);
    const second_store = shift.durable.Store.init(std.testing.allocator, second_paths.manifest_path, second_paths.events_path);

    _ = try first_store.saveArtifact(first_artifact, null);
    _ = try second_store.saveArtifact(second_artifact, null);

    _ = try std.fs.cwd().statFile(first_paths.plan_path);
    _ = try std.fs.cwd().statFile(first_paths.artifact_path);
    _ = try std.fs.cwd().statFile(second_paths.plan_path);
    _ = try std.fs.cwd().statFile(second_paths.artifact_path);

    const restored_first = try first_store.restoreArtifact(first_artifact);
    try std.testing.expectEqual(shift.durable.RestoreStatus.exact_replay, restored_first.status);
    const restored_second = try second_store.restoreArtifact(second_artifact);
    try std.testing.expectEqual(shift.durable.RestoreStatus.exact_replay, restored_second.status);
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

test "durable restore preserves plan-backed helper ABI fields across persisted plan reload" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const artifact: shift.durable.ProgramArtifact = .{
        .label = "plan_backed_helper_abi",
        .program_hash = 0x9911,
        .steps = &.{
            .{ .emit = .{ .note = "plan-backed" } },
            .{ .emit = .{ .final_i32 = 7 } },
        },
        .plan = .{
            .label = "demo.plan",
            .ir_hash = 0x5511,
            .entry_index = 0,
            .functions = &.{.{
                .symbol_name = "runBody",
                .value_codec = .i32,
                .parameter_count = 1,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 1,
                .first_local = 0,
                .local_count = 1,
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
            .locals = &.{.{ .codec = .i32 }},
            .call_args = &.{0},
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

    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    _ = try store.saveArtifact(artifact, null);

    const restored = try store.restore();
    try std.testing.expectEqual(shift.durable.RestoreStatus.exact_replay, restored.status);
    try std.testing.expectEqual(@as(?shift.durable.MigrationReport, null), restored.migration_report);
}

test "durable restore preserves plan-backed const_string literals across persisted plan reload" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const artifact: shift.durable.ProgramArtifact = .{
        .label = "plan_backed_const_string",
        .program_hash = 0x9912,
        .steps = &.{
            .{ .emit = .{ .note = "plan-backed" } },
            .{ .emit = .{ .final_string = "persisted literal" } },
        },
        .plan = .{
            .label = "demo.plan",
            .ir_hash = 0x5512,
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

    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    _ = try store.saveArtifact(artifact, null);

    const restored = try store.restoreArtifact(artifact);
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
    const legacy_plan_path = try legacyPlanPathAlloc(std.testing.allocator, paths.manifest_path);
    defer std.testing.allocator.free(legacy_plan_path);
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
        const file = try std.fs.cwd().createFile(legacy_plan_path, .{ .truncate = true });
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

test "durable restoreArtifact rolls back migrated plan rewriteback when a later write fails" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const artifact = makePlanBackedArtifact(0x6234, 0x6234, "demo.plan", "runBody");
    const legacy_manifest = shift.durable.SessionManifest{
        .schema_version = 2,
        .scenario_id = null,
        .program_hash = artifact.plan.?.ir_hash,
        .plan_hash = artifact.plan.?.hash(),
        .plan_schema_version = null,
        .last_seq = 2,
    };

    {
        const file = try std.fs.cwd().createFile(paths.manifest_path, .{ .truncate = true });
        defer file.close();
        var buffer: [1024]u8 = undefined;
        var writer = file.writer(&buffer);
        try std.json.Stringify.value(legacy_manifest, .{}, &writer.interface);
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

    const bad_events_path = try std.fs.path.join(std.testing.allocator, &.{ paths.dir_path, "missing", "events.jsonl" });
    defer std.testing.allocator.free(bad_events_path);
    const failing_store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, bad_events_path);
    var stripped = artifact;
    stripped.plan = null;
    try std.testing.expectError(error.FileNotFound, failing_store.restoreArtifact(stripped));

    const manifest_bytes = try std.fs.cwd().readFileAlloc(std.testing.allocator, paths.manifest_path, std.math.maxInt(usize));
    defer std.testing.allocator.free(manifest_bytes);
    const parsed_manifest = try std.json.parseFromSlice(shift.durable.SessionManifest, std.testing.allocator, manifest_bytes, .{});
    defer parsed_manifest.deinit();
    try std.testing.expectEqual(@as(u32, 2), parsed_manifest.value.schema_version);
    try std.testing.expectEqual(@as(?u32, null), parsed_manifest.value.plan_schema_version);
    try std.testing.expectEqual(@as(?u32, null), parsed_manifest.value.event_schema_version);

    const plan_bytes = try std.fs.cwd().readFileAlloc(std.testing.allocator, paths.plan_path, std.math.maxInt(usize));
    defer std.testing.allocator.free(plan_bytes);
    const parsed_plan = try std.json.parseFromSlice(@TypeOf(artifact.plan.?), std.testing.allocator, plan_bytes, .{});
    defer parsed_plan.deinit();
    try std.testing.expectEqualStrings("demo.plan", parsed_plan.value.label);
    try std.testing.expectEqual(@as(u64, 0x6234), parsed_plan.value.ir_hash);
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

test "durable saveArtifact rejects oversized transcripts before replay" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const steps = try allocRepeatedNoteSteps(std.testing.allocator, 17);
    defer std.testing.allocator.free(steps);

    const artifact: shift.durable.ProgramArtifact = .{
        .label = "too_many_events",
        .program_hash = 0x8bad,
        .steps = steps,
    };

    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    try std.testing.expectError(error.TooManyEvents, store.saveArtifact(artifact, null));
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().statFile(paths.manifest_path));
}

test "durable restoreArtifact rejects oversized transcripts before replay" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const steps = try allocRepeatedNoteSteps(std.testing.allocator, 17);
    defer std.testing.allocator.free(steps);

    const artifact: shift.durable.ProgramArtifact = .{
        .label = "too_many_events",
        .program_hash = 0x9bad,
        .steps = steps,
    };

    {
        const file = try std.fs.cwd().createFile(paths.manifest_path, .{ .truncate = true });
        defer file.close();
        var buffer: [1024]u8 = undefined;
        var writer = file.writer(&buffer);
        try std.json.Stringify.value(shift.durable.SessionManifest{
            .program_hash = artifact.identityHash(),
            .event_schema_version = 1,
            .last_seq = steps.len,
        }, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }
    {
        const file = try std.fs.cwd().createFile(paths.events_path, .{ .truncate = true });
        defer file.close();
    }

    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    try std.testing.expectError(error.TooManyEvents, store.restoreArtifact(artifact));
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

test "durable restore rejects structurally invalid but hash-consistent persisted plan sidecars" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const paths = try TestPaths.init(&tmp);
    defer paths.deinit();

    const artifact = makePlanBackedArtifact(0x5235, 0x5235, "demo.plan", "runBody");
    const invalid_plan: @TypeOf(artifact.plan.?) = .{
        .label = artifact.plan.?.label,
        .ir_hash = artifact.plan.?.ir_hash,
        .entry_index = artifact.plan.?.entry_index,
        .functions = &.{.{
            .symbol_name = "runBody",
            .value_codec = .i32,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 1,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .block_count = 0,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{.{ .label = "result", .codec = .i32 }},
        .locals = &.{.{ .codec = .i32 }},
        .blocks = &.{},
        .terminators = &.{},
        .instructions = &.{.{ .kind = .return_value, .operand = 0 }},
    };

    const store = shift.durable.Store.init(std.testing.allocator, paths.manifest_path, paths.events_path);
    _ = try store.saveArtifact(artifact, null);

    {
        const file = try std.fs.cwd().createFile(paths.plan_path, .{ .truncate = true });
        defer file.close();
        var buffer: [1024]u8 = undefined;
        var writer = file.writer(&buffer);
        try std.json.Stringify.value(shift.durable.PlanFile{
            .schema_version = 4,
            .plan_hash = invalid_plan.hash(),
            .plan = invalid_plan,
        }, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }
    {
        const manifest_bytes = try std.fs.cwd().readFileAlloc(std.testing.allocator, paths.manifest_path, std.math.maxInt(usize));
        defer std.testing.allocator.free(manifest_bytes);
        const parsed_manifest = try std.json.parseFromSlice(shift.durable.SessionManifest, std.testing.allocator, manifest_bytes, .{});
        defer parsed_manifest.deinit();

        const file = try std.fs.cwd().createFile(paths.manifest_path, .{ .truncate = true });
        defer file.close();
        var buffer: [1024]u8 = undefined;
        var writer = file.writer(&buffer);
        var tampered_manifest = parsed_manifest.value;
        tampered_manifest.plan_hash = invalid_plan.hash();
        try std.json.Stringify.value(tampered_manifest, .{}, &writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }

    const restored = try store.restore();
    try std.testing.expectEqual(shift.durable.RestoreStatus.rebuild_required, restored.status);
}
