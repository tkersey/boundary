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
    migrated_replay,
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

const LegacySessionManifestV2 = struct {
    schema_version: u32 = 2,
    scenario_id: ?kernel.ScenarioId = null,
    program_hash: u64,
    plan_hash: ?u64 = null,
    last_seq: usize,
    restore_status: RestoreStatus = .exact_replay,
};

const LegacySessionManifestV3 = struct {
    schema_version: u32 = 3,
    scenario_id: ?kernel.ScenarioId = null,
    program_hash: u64,
    plan_hash: ?u64 = null,
    plan_schema_version: ?u32 = null,
    last_seq: usize,
    restore_status: RestoreStatus = .exact_replay,
};

const SessionManifestState = struct {
    schema_version: u32,
    scenario_id: ?kernel.ScenarioId,
    program_hash: u64,
    artifact_hash: ?u64,
    artifact_schema_version: ?u32,
    plan_hash: ?u64,
    plan_schema_version: ?u32,
    event_schema_version: ?u32,
    last_seq: usize,
    restore_status: RestoreStatus,
};

const LegacyPlanFileV1 = struct {
    schema_version: u32 = 1,
    plan: kernel.ProgramPlan,
};

const LegacyInstructionV2 = struct {
    kind: kernel.InstructionKind,
    index: u16,
};

const LegacyProgramPlanV2 = struct {
    schema_version: u32 = 2,
    label: []const u8,
    ir_hash: u64,
    entry_index: u16,
    functions: []const kernel.FunctionPlan,
    requirements: []const kernel.RequirementPlan,
    ops: []const kernel.OpPlan,
    outputs: []const kernel.OutputPlan,
    locals: []const kernel.LocalPlan = &.{},
    blocks: []const kernel.BlockPlan = &.{},
    terminators: []const kernel.Terminator = &.{},
    instructions: []const LegacyInstructionV2,
};

const LegacyPlanFileV3 = struct {
    schema_version: u32 = 3,
    plan_hash: u64,
    plan: LegacyProgramPlanV2,
};

const LegacyEventRecordV0 = struct {
    seq: usize,
    event: kernel.Event,
};

const PlanFileState = struct {
    schema_version: u32,
    plan_hash: ?u64,
    plan: kernel.ProgramPlan,
};

const EventRecordState = struct {
    schema_version: u32,
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

const SessionManifestMigrator = struct {
    from: u32,
    to_schema: u32,
    migrate: *const fn (*SessionManifestState) void,
};

const PlanFileMigrator = struct {
    from: u32,
    to_schema: u32,
    migrate: *const fn (std.mem.Allocator, *PlanFileState) anyerror!void,
};

const EventRecordMigrator = struct {
    from: u32,
    to_schema: u32,
    migrate: *const fn (*EventRecordState) void,
};

const session_manifest_migrators = [_]SessionManifestMigrator{
    .{
        .from = 2,
        .to_schema = 3,
        .migrate = struct {
            fn run(state: *SessionManifestState) void {
                state.plan_schema_version = null;
                state.schema_version = 3;
            }
        }.run,
    },
    .{
        .from = 3,
        .to_schema = 4,
        .migrate = struct {
            fn run(state: *SessionManifestState) void {
                state.event_schema_version = 0;
                state.schema_version = 4;
            }
        }.run,
    },
    .{
        .from = 4,
        .to_schema = 5,
        .migrate = struct {
            fn run(state: *SessionManifestState) void {
                state.artifact_schema_version = if (state.scenario_id == null)
                    state.artifact_schema_version orelse current_artifact_schema
                else
                    null;
                state.schema_version = 5;
            }
        }.run,
    },
};

const plan_file_migrators = [_]PlanFileMigrator{
    .{
        .from = 0,
        .to_schema = 1,
        .migrate = struct {
            fn run(_: std.mem.Allocator, state: *PlanFileState) !void {
                state.schema_version = 1;
            }
        }.run,
    },
    .{
        .from = 1,
        .to_schema = 2,
        .migrate = struct {
            fn run(_: std.mem.Allocator, state: *PlanFileState) !void {
                state.plan_hash = hashPlan(state.plan);
                state.schema_version = 2;
            }
        }.run,
    },
    .{
        .from = 2,
        .to_schema = 3,
        .migrate = struct {
            fn run(allocator: std.mem.Allocator, state: *PlanFileState) !void {
                try kernel.upgradeLegacyProgramPlan(allocator, &state.plan);
                state.plan_hash = hashPlan(state.plan);
                state.schema_version = 3;
            }
        }.run,
    },
    .{
        .from = 3,
        .to_schema = 4,
        .migrate = struct {
            fn run(allocator: std.mem.Allocator, state: *PlanFileState) !void {
                try kernel.upgradeLegacyProgramPlan(allocator, &state.plan);
                state.plan_hash = hashPlan(state.plan);
                state.schema_version = 4;
            }
        }.run,
    },
};

const event_record_migrators = [_]EventRecordMigrator{
    .{
        .from = 0,
        .to_schema = 1,
        .migrate = struct {
            fn run(state: *EventRecordState) void {
                state.schema_version = 1;
            }
        }.run,
    },
};

/// Restore result for one durable session replay attempt.
pub const VersionHop = struct {
    from: u32,
    to_schema: u32,
};

/// Detailed schema-hop and rewriteback facts for one migrated restore.
pub const MigrationReport = struct {
    event_schema: ?VersionHop = null,
    manifest_schema: ?VersionHop = null,
    plan_file_schema: ?VersionHop = null,
    rewrote_events: bool = false,
    rewrote_manifest: bool = false,
    rewrote_plan_file: bool = false,
};

/// Restore result for one durable session replay attempt, including optional migration provenance.
pub const RestoreResult = struct {
    migration_report: ?MigrationReport = null,
    status: RestoreStatus,
    manifest: SessionManifest,
    state: ?kernel.State = null,
};

const ReadManifestResult = struct {
    stored_schema_version: u32,
    manifest: SessionManifest,
};

const ReadArtifactFileResult = struct {
    stored_schema_version: u32,
    artifact: ProgramArtifact,
};

const ReadEventRecordResult = struct {
    stored_schema_version: u32,
    record: EventRecord,
};

const EventsMatchResult = struct {
    matches: bool,
    migrated: bool,
};

const RestoreRewriteMode = enum {
    inspect_only,
    rewriteback,
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
        const read_manifest = readManifest(self.allocator, self.manifest_path) catch |err| switch (err) {
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
        const manifest = read_manifest.manifest;
        if (!isSupportedManifestSchema(manifest.schema_version)) {
            return .{
                .status = .rebuild_required,
                .manifest = manifest,
                .state = null,
            };
        }
        if (manifest.scenario_id) |id| {
            return try self.restoreArtifactInternal(ProgramArtifact.fromScenario(id), .rewriteback);
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
        const legacy_artifact_path = try legacyArtifactPath(self.allocator, self.manifest_path);
        defer self.allocator.free(legacy_artifact_path);
        const artifact_file = readArtifactFileWithLegacyFallback(self.allocator, artifact_path, legacy_artifact_path) catch |err| {
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
        return try self.restoreArtifactInternal(artifact_file.artifact, .rewriteback);
    }

    /// Inspect one persisted session restore without rewriting migrated artifacts back to disk.
    pub fn inspectRestore(self: @This()) anyerror!RestoreResult {
        const read_manifest = readManifest(self.allocator, self.manifest_path) catch |err| switch (err) {
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
        const manifest = read_manifest.manifest;
        if (!isSupportedManifestSchema(manifest.schema_version)) {
            return .{
                .status = .rebuild_required,
                .manifest = manifest,
                .state = null,
            };
        }

        if (manifest.scenario_id) |id| {
            return try self.restoreArtifactInternal(ProgramArtifact.fromScenario(id), .inspect_only);
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
        const legacy_artifact_path = try legacyArtifactPath(self.allocator, self.manifest_path);
        defer self.allocator.free(legacy_artifact_path);
        const artifact_file = readArtifactFileWithLegacyFallback(self.allocator, artifact_path, legacy_artifact_path) catch |err| {
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
        return try self.restoreArtifactInternal(artifact_file.artifact, .inspect_only);
    }

    /// Restore one persisted session by replaying the supplied artifact and checking the event log.
    pub fn restoreArtifact(self: @This(), artifact: ProgramArtifact) anyerror!RestoreResult {
        return try self.restoreArtifactInternal(artifact, .rewriteback);
    }

    /// Inspect one persisted artifact restore without rewriting migrated artifacts back to disk.
    pub fn inspectRestoreArtifact(self: @This(), artifact: ProgramArtifact) anyerror!RestoreResult {
        return try self.restoreArtifactInternal(artifact, .inspect_only);
    }

    fn restoreArtifactInternal(self: @This(), artifact: ProgramArtifact, rewrite_mode: RestoreRewriteMode) anyerror!RestoreResult {
        const read_manifest = readManifest(self.allocator, self.manifest_path) catch |err| switch (err) {
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
        const manifest = read_manifest.manifest;
        if (!isSupportedManifestSchema(manifest.schema_version)) {
            return .{
                .status = .rebuild_required,
                .manifest = manifest,
                .state = null,
            };
        }
        var manifest_migrated = read_manifest.stored_schema_version != current_manifest_schema;
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
        const legacy_plan_path = try legacyPlanPath(self.allocator, self.manifest_path);
        defer self.allocator.free(legacy_plan_path);
        var loaded_plan: ?kernel.ProgramPlan = null;
        defer if (loaded_plan) |plan| freePlan(self.allocator, &plan);
        var plan_migrated = false;
        if (manifest.plan_hash) |expected_plan_hash| {
            const plan_file = readPlanFileWithLegacyFallback(self.allocator, plan_path, legacy_plan_path) catch |err| {
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
            plan_migrated = plan_file.stored_schema_version != current_plan_schema;
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
            const migrated_plan_hash = hashPlan(stored_plan);
            if (plan_file.comparison_plan_hash != expected_plan_hash or stored_plan.ir_hash != manifest.program_hash) {
                return .{
                    .status = .failed,
                    .manifest = manifest,
                    .state = null,
                };
            }
            if (artifact.plan) |current_plan| {
                if (current_plan.ir_hash != stored_plan.ir_hash or hashPlan(current_plan) != migrated_plan_hash) {
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

        const expected_event_schema = manifest.event_schema_version orelse 0;
        if (!isSupportedEventSchema(expected_event_schema)) {
            return .{
                .status = .rebuild_required,
                .manifest = manifest,
                .state = null,
            };
        }
        try kernel.validateStepCapacity(artifact.steps);
        const state = kernel.runSteps(artifact.steps);
        const event_match = eventsMatch(self.allocator, self.events_path, expected_event_schema, &state, manifest.last_seq) catch |err| switch (err) {
            error.UnsupportedEventSchema => return .{
                .status = .rebuild_required,
                .manifest = manifest,
                .state = null,
            },
            else => return err,
        };
        if (!event_match.matches) {
            return .{
                .status = .failed,
                .manifest = manifest,
                .state = null,
            };
        }
        if (manifest.plan_hash != null and manifest.plan_schema_version != current_plan_schema) manifest_migrated = true;
        if (expected_event_schema != current_event_schema) manifest_migrated = true;
        if (manifest_migrated or plan_migrated or event_match.migrated) {
            const migration_report = MigrationReport{
                .event_schema = versionHopIfMigrated(expected_event_schema, current_event_schema, event_match.migrated),
                .manifest_schema = versionHopIfMigrated(read_manifest.stored_schema_version, current_manifest_schema, read_manifest.stored_schema_version != current_manifest_schema),
                .plan_file_schema = if (manifest.plan_hash != null)
                    versionHopIfMigrated(manifest.plan_schema_version orelse 0, current_plan_schema, plan_migrated)
                else
                    null,
                .rewrote_events = rewrite_mode == .rewriteback and event_match.migrated,
                .rewrote_manifest = rewrite_mode == .rewriteback,
                .rewrote_plan_file = rewrite_mode == .rewriteback and plan_migrated,
            };
            const current_plan_hash = if (loaded_plan) |plan| hashPlan(plan) else null;
            var persisted_manifest = SessionManifest{
                .schema_version = current_manifest_schema,
                .scenario_id = manifest.scenario_id,
                .program_hash = manifest.program_hash,
                .artifact_hash = manifest.artifact_hash orelse hashProgram(artifact.label, artifact.steps),
                .artifact_schema_version = if (manifest.scenario_id == null) current_artifact_schema else null,
                .plan_hash = current_plan_hash,
                .plan_schema_version = if (current_plan_hash != null) current_plan_schema else null,
                .event_schema_version = current_event_schema,
                .last_seq = kernel.events(&state).len,
                .restore_status = .exact_replay,
            };
            if (rewrite_mode == .rewriteback) {
                var manifest_snapshot = try captureFileSnapshot(self.allocator, self.manifest_path);
                defer manifest_snapshot.deinit(self.allocator);
                errdefer {
                    restoreFileSnapshot(manifest_snapshot, self.manifest_path) catch |restore_err| {
                        std.log.err("durable rollback failed for manifest rewriteback: {s}", .{@errorName(restore_err)});
                    };
                }
                var plan_snapshot: ?FileSnapshot = null;
                defer if (plan_snapshot) |*snapshot| snapshot.deinit(self.allocator);
                errdefer {
                    if (plan_snapshot) |snapshot| restoreFileSnapshot(snapshot, plan_path) catch |restore_err| {
                        std.log.err("durable rollback failed for plan rewriteback: {s}", .{@errorName(restore_err)});
                    };
                }
                if (plan_migrated) {
                    plan_snapshot = try captureFileSnapshot(self.allocator, plan_path);
                }
                var events_snapshot: ?FileSnapshot = null;
                defer if (events_snapshot) |*snapshot| snapshot.deinit(self.allocator);
                errdefer {
                    if (events_snapshot) |snapshot| restoreFileSnapshot(snapshot, self.events_path) catch |restore_err| {
                        std.log.err("durable rollback failed for events rewriteback: {s}", .{@errorName(restore_err)});
                    };
                }
                if (event_match.migrated) {
                    events_snapshot = try captureFileSnapshot(self.allocator, self.events_path);
                }
                if (plan_migrated) try writePlan(plan_path, loaded_plan.?);
                if (event_match.migrated) try writeEvents(self.events_path, &state);
                try writeManifest(self.manifest_path, persisted_manifest);
            } else {
                persisted_manifest = manifest;
            }

            persisted_manifest.restore_status = .migrated_replay;
            return .{
                .migration_report = migration_report,
                .status = .migrated_replay,
                .manifest = persisted_manifest,
                .state = state,
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

fn legacySidecarPath(allocator: std.mem.Allocator, manifest_path: []const u8, sidecar_name: []const u8) ![]u8 {
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

fn legacyPlanPath(allocator: std.mem.Allocator, manifest_path: []const u8) ![]u8 {
    return try legacySidecarPath(allocator, manifest_path, "plan.json");
}

fn legacyArtifactPath(allocator: std.mem.Allocator, manifest_path: []const u8) ![]u8 {
    return try legacySidecarPath(allocator, manifest_path, "artifact.json");
}

fn isSupportedManifestSchema(schema_version: u32) bool {
    return schema_version >= 2 and schema_version <= current_manifest_schema;
}

fn isSupportedEventSchema(schema_version: u32) bool {
    return schema_version == 0 or schema_version == current_event_schema;
}

fn versionHopIfMigrated(from: u32, to_schema: u32, migrated: bool) ?VersionHop {
    if (!migrated) return null;
    return .{
        .from = from,
        .to_schema = to_schema,
    };
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

fn writeRawFile(path: []const u8, bytes: []const u8) !void {
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

fn readManifest(allocator: std.mem.Allocator, path: []const u8) !ReadManifestResult {
    const bytes = if (std.fs.path.isAbsolute(path)) blk: {
        break :blk try readAbsoluteFileAlloc(allocator, path);
    } else try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
    defer allocator.free(bytes);
    const state = if (std.json.parseFromSlice(SessionManifest, allocator, bytes, .{})) |parsed| blk: {
        defer parsed.deinit();
        break :blk SessionManifestState{
            .schema_version = parsed.value.schema_version,
            .scenario_id = parsed.value.scenario_id,
            .program_hash = parsed.value.program_hash,
            .artifact_hash = parsed.value.artifact_hash,
            .artifact_schema_version = parsed.value.artifact_schema_version,
            .plan_hash = parsed.value.plan_hash,
            .plan_schema_version = parsed.value.plan_schema_version,
            .event_schema_version = parsed.value.event_schema_version,
            .last_seq = parsed.value.last_seq,
            .restore_status = parsed.value.restore_status,
        };
    } else |_| if (std.json.parseFromSlice(LegacySessionManifestV3, allocator, bytes, .{})) |parsed| blk: {
        defer parsed.deinit();
        break :blk SessionManifestState{
            .schema_version = parsed.value.schema_version,
            .scenario_id = parsed.value.scenario_id,
            .program_hash = parsed.value.program_hash,
            .artifact_hash = null,
            .artifact_schema_version = null,
            .plan_hash = parsed.value.plan_hash,
            .plan_schema_version = parsed.value.plan_schema_version,
            .event_schema_version = null,
            .last_seq = parsed.value.last_seq,
            .restore_status = parsed.value.restore_status,
        };
    } else |_| blk: {
        const parsed = try std.json.parseFromSlice(LegacySessionManifestV2, allocator, bytes, .{});
        defer parsed.deinit();
        break :blk SessionManifestState{
            .schema_version = parsed.value.schema_version,
            .scenario_id = parsed.value.scenario_id,
            .program_hash = parsed.value.program_hash,
            .artifact_hash = null,
            .artifact_schema_version = null,
            .plan_hash = parsed.value.plan_hash,
            .plan_schema_version = null,
            .event_schema_version = null,
            .last_seq = parsed.value.last_seq,
            .restore_status = parsed.value.restore_status,
        };
    };

    const stored_schema_version = state.schema_version;
    var migrated = state;
    try migrateSessionManifest(&migrated);
    return .{
        .stored_schema_version = stored_schema_version,
        .manifest = .{
            .schema_version = migrated.schema_version,
            .scenario_id = migrated.scenario_id,
            .program_hash = migrated.program_hash,
            .artifact_hash = migrated.artifact_hash,
            .artifact_schema_version = migrated.artifact_schema_version,
            .plan_hash = migrated.plan_hash,
            .plan_schema_version = migrated.plan_schema_version,
            .event_schema_version = migrated.event_schema_version,
            .last_seq = migrated.last_seq,
            .restore_status = migrated.restore_status,
        },
    };
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

fn readArtifactFileWithLegacyFallback(
    allocator: std.mem.Allocator,
    path: []const u8,
    legacy_path: []const u8,
) !ReadArtifactFileResult {
    return readArtifactFile(allocator, path) catch |err| switch (err) {
        error.FileNotFound => try readArtifactFile(allocator, legacy_path),
        else => return err,
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
    const state = if (std.json.parseFromSlice(PlanFile, allocator, bytes, .{})) |parsed| blk: {
        defer parsed.deinit();
        break :blk PlanFileState{
            .schema_version = parsed.value.schema_version,
            .plan_hash = parsed.value.plan_hash,
            .plan = try clonePlan(allocator, parsed.value.plan),
        };
    } else |_| if (std.json.parseFromSlice(LegacyPlanFileV3, allocator, bytes, .{})) |parsed| blk: {
        defer parsed.deinit();
        break :blk PlanFileState{
            .schema_version = parsed.value.schema_version,
            .plan_hash = parsed.value.plan_hash,
            .plan = try cloneLegacyProgramPlanV2(allocator, parsed.value.plan),
        };
    } else |_| if (std.json.parseFromSlice(LegacyPlanFileV1, allocator, bytes, .{})) |parsed| blk: {
        defer parsed.deinit();
        break :blk PlanFileState{
            .schema_version = parsed.value.schema_version,
            .plan_hash = null,
            .plan = try clonePlan(allocator, parsed.value.plan),
        };
    } else |_| blk: {
        if (std.json.parseFromSlice(LegacyProgramPlanV2, allocator, bytes, .{})) |legacy_v2| {
            defer legacy_v2.deinit();
            break :blk PlanFileState{
                .schema_version = 0,
                .plan_hash = null,
                .plan = try cloneLegacyProgramPlanV2(allocator, legacy_v2.value),
            };
        } else |_| {
            const legacy = try std.json.parseFromSlice(kernel.ProgramPlan, allocator, bytes, .{});
            defer legacy.deinit();
            break :blk PlanFileState{
                .schema_version = 0,
                .plan_hash = null,
                .plan = try clonePlan(allocator, legacy.value),
            };
        }
    };
    const comparison_plan_hash = state.plan_hash orelse hashPlan(state.plan);

    var migrated = state;
    errdefer freePlan(allocator, &migrated.plan);
    const stored_schema_version = migrated.schema_version;
    try migratePlanFile(allocator, &migrated);
    if (migrated.schema_version != current_plan_schema) return error.UnsupportedPlanSchema;
    try migrated.plan.validate();
    return .{
        .stored_schema_version = stored_schema_version,
        .comparison_plan_hash = comparison_plan_hash,
        .plan = migrated.plan,
    };
}

fn readPlanFileWithLegacyFallback(
    allocator: std.mem.Allocator,
    path: []const u8,
    legacy_path: []const u8,
) !ReadPlanFileResult {
    return readPlanFile(allocator, path) catch |err| switch (err) {
        error.FileNotFound => try readPlanFile(allocator, legacy_path),
        else => return err,
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

fn cloneLegacyInstructionV2IntoCurrent(instruction: LegacyInstructionV2) kernel.Instruction {
    return .{
        .kind = instruction.kind,
        .dst = 0,
        .operand = instruction.index,
        .aux = 0,
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

fn cloneLegacyProgramPlanV2(allocator: std.mem.Allocator, plan: LegacyProgramPlanV2) !kernel.ProgramPlan {
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
            .first_requirement = function.first_requirement,
            .requirement_count = function.requirement_count,
            .first_output = function.first_output,
            .output_count = function.output_count,
            .first_local = function.first_local,
            .local_count = function.local_count,
            .first_block = function.first_block,
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

    const blocks = try allocator.dupe(kernel.BlockPlan, plan.blocks);
    allocator.free(cloned.blocks);
    cloned.blocks = blocks;

    const terminators = try allocator.dupe(kernel.Terminator, plan.terminators);
    allocator.free(cloned.terminators);
    cloned.terminators = terminators;

    var instructions = try allocator.alloc(kernel.Instruction, plan.instructions.len);
    errdefer allocator.free(instructions);
    for (plan.instructions, 0..) |instruction, index| {
        instructions[index] = cloneLegacyInstructionV2IntoCurrent(instruction);
    }
    allocator.free(cloned.instructions);
    cloned.instructions = instructions;
    return cloned;
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

fn migrateSessionManifest(state: *SessionManifestState) !void {
    while (state.schema_version < current_manifest_schema) {
        var advanced = false;
        for (session_manifest_migrators) |migrator| {
            if (migrator.from != state.schema_version) continue;
            migrator.migrate(state);
            advanced = true;
            break;
        }
        if (!advanced) return error.UnsupportedManifestSchema;
    }
    if (state.schema_version != current_manifest_schema) return error.UnsupportedManifestSchema;
}

fn migratePlanFile(allocator: std.mem.Allocator, state: *PlanFileState) !void {
    while (state.schema_version < current_plan_schema) {
        var advanced = false;
        for (plan_file_migrators) |migrator| {
            if (migrator.from != state.schema_version) continue;
            try migrator.migrate(allocator, state);
            advanced = true;
            break;
        }
        if (!advanced) return error.UnsupportedPlanSchema;
    }
    if (state.schema_version != current_plan_schema) return error.UnsupportedPlanSchema;
}

fn migrateEventRecord(state: *EventRecordState) !void {
    while (state.schema_version < current_event_schema) {
        var advanced = false;
        for (event_record_migrators) |migrator| {
            if (migrator.from != state.schema_version) continue;
            migrator.migrate(state);
            advanced = true;
            break;
        }
        if (!advanced) return error.UnsupportedEventSchema;
    }
    if (state.schema_version != current_event_schema) return error.UnsupportedEventSchema;
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

fn readEventRecord(allocator: std.mem.Allocator, line: []const u8, schema_version: u32) !ReadEventRecordResult {
    var state = if (schema_version == 0) blk: {
        const parsed = try std.json.parseFromSlice(LegacyEventRecordV0, allocator, line, .{});
        defer parsed.deinit();
        break :blk EventRecordState{
            .schema_version = 0,
            .seq = parsed.value.seq,
            .event = try cloneEvent(allocator, parsed.value.event),
        };
    } else blk: {
        const parsed = try std.json.parseFromSlice(EventRecord, allocator, line, .{});
        defer parsed.deinit();
        if (parsed.value.schema_version != schema_version) return error.UnsupportedEventSchema;
        break :blk EventRecordState{
            .schema_version = parsed.value.schema_version,
            .seq = parsed.value.seq,
            .event = try cloneEvent(allocator, parsed.value.event),
        };
    };
    errdefer freeEvent(allocator, state.event);
    const stored_schema_version = state.schema_version;
    try migrateEventRecord(&state);
    return .{
        .stored_schema_version = stored_schema_version,
        .record = .{
            .schema_version = state.schema_version,
            .seq = state.seq,
            .event = state.event,
        },
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
    if (expected_events.len != expected_len) return .{ .matches = false, .migrated = false };

    var line_iter = std.mem.splitScalar(u8, bytes, '\n');
    var seq: usize = 0;
    var migrated = false;
    while (line_iter.next()) |line| {
        if (line.len == 0) continue;
        if (seq >= expected_events.len) return .{ .matches = false, .migrated = migrated };

        const parsed = try readEventRecord(allocator, line, schema_version);
        defer freeEvent(allocator, parsed.record.event);
        if (parsed.stored_schema_version != current_event_schema) migrated = true;
        if (parsed.record.seq != seq) return .{ .matches = false, .migrated = migrated };
        if (!eventEql(parsed.record.event, expected_events[seq])) return .{ .matches = false, .migrated = migrated };
        seq += 1;
    }
    return .{
        .matches = seq == expected_events.len,
        .migrated = migrated,
    };
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

test "readPlanFile frees migrated legacy plan ownership when validation fails" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const allocator = std.testing.allocator;
    const dir_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dir_path);
    const plan_path = try std.fs.path.join(allocator, &.{ dir_path, "invalid-legacy.plan.json" });
    defer allocator.free(plan_path);

    const legacy_plan_file = LegacyPlanFileV3{
        .schema_version = 3,
        .plan_hash = 0x1234,
        .plan = .{
            .schema_version = 2,
            .label = "invalid.legacy.plan",
            .ir_hash = 1,
            .entry_index = 0,
            .functions = &.{.{
                .symbol_name = "root",
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 0,
                .first_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 1,
            }},
            .requirements = &.{},
            .ops = &.{},
            .outputs = &.{},
            .locals = &.{},
            .blocks = &.{.{
                .first_instruction = 0,
                .instruction_count = 1,
                .terminator_index = 0,
            }},
            .terminators = &.{.{ .kind = .return_unit }},
            .instructions = &.{.{
                .kind = .return_value,
                .index = 0,
            }},
        },
    };

    const file = try std.fs.createFileAbsolute(plan_path, .{ .truncate = true });
    defer file.close();
    var buffer: [1024]u8 = undefined;
    var writer = file.writer(&buffer);
    try std.json.Stringify.value(legacy_plan_file, .{}, &writer.interface);
    try writer.interface.writeByte('\n');
    try writer.interface.flush();

    try std.testing.expectError(error.InvalidTerminatorInstruction, readPlanFile(allocator, plan_path));
}
