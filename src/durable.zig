const kernel = @import("internal_kernel");
const scenarios = @import("parity_scenarios");
const std = @import("std");

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
    schema_version: u32 = 2,
    scenario_id: ?kernel.ScenarioId = null,
    /// Durable program identity. Plan-backed artifacts persist `ProgramPlan.ir_hash`.
    program_hash: u64,
    plan_hash: ?u64 = null,
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
        const plan_path = try derivedPlanPath(self.allocator, self.manifest_path);
        defer self.allocator.free(plan_path);
        const manifest = SessionManifest{
            .scenario_id = scenario_id,
            .program_hash = artifact.identityHash(),
            .plan_hash = if (artifact.plan) |plan| hashPlan(plan) else null,
            .last_seq = kernel.events(&state).len,
        };
        try writeManifest(self.manifest_path, manifest);
        if (artifact.plan) |plan| try writePlan(plan_path, plan);
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
        if (manifest.program_hash != artifact.identityHash()) {
            return .{
                .status = .rebuild_required,
                .manifest = manifest,
                .state = null,
            };
        }
        const plan_path = try derivedPlanPath(self.allocator, self.manifest_path);
        defer self.allocator.free(plan_path);
        if (manifest.plan_hash) |expected_plan_hash| {
            const plan = readPlan(self.allocator, plan_path) catch {
                return .{
                    .status = .failed,
                    .manifest = manifest,
                    .state = null,
                };
            };
            defer freePlan(self.allocator, &plan);
            if (hashPlan(plan) != expected_plan_hash or plan.ir_hash != manifest.program_hash) {
                return .{
                    .status = .failed,
                    .manifest = manifest,
                    .state = null,
                };
            }
            if (artifact.plan) |current_plan| {
                if (current_plan.ir_hash != manifest.program_hash or hashPlan(current_plan) != expected_plan_hash) {
                    return .{
                        .status = .rebuild_required,
                        .manifest = manifest,
                        .state = null,
                    };
                }
            }
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

fn derivedPlanPath(allocator: std.mem.Allocator, manifest_path: []const u8) ![]u8 {
    if (std.fs.path.dirname(manifest_path)) |dir_name| {
        if (dir_name.len != 0) return try std.fs.path.join(allocator, &.{ dir_name, "plan.json" });
    }
    return try allocator.dupe(u8, "plan.json");
}

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

fn hashPlan(plan: kernel.ProgramPlan) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(plan.label);
    hasher.update(std.mem.asBytes(&plan.ir_hash));
    for (plan.functions) |function| {
        hasher.update(function.symbol_name);
        hasher.update(std.mem.asBytes(&function.first_requirement));
        hasher.update(std.mem.asBytes(&function.requirement_count));
        hasher.update(std.mem.asBytes(&function.first_output));
        hasher.update(std.mem.asBytes(&function.output_count));
        hasher.update(std.mem.asBytes(&function.first_instruction));
        hasher.update(std.mem.asBytes(&function.instruction_count));
    }
    for (plan.requirements) |requirement| {
        hasher.update(requirement.label);
        hasher.update(std.mem.asBytes(&requirement.first_op));
        hasher.update(std.mem.asBytes(&requirement.op_count));
    }
    for (plan.ops) |op| {
        hasher.update(std.mem.asBytes(&op.requirement_index));
        hasher.update(op.op_name);
        hasher.update(@tagName(op.mode));
        hasher.update(@tagName(op.payload_codec));
        hasher.update(@tagName(op.resume_codec));
    }
    for (plan.outputs) |output| {
        hasher.update(output.label);
        hasher.update(@tagName(output.codec));
    }
    for (plan.instructions) |instruction| switch (instruction.kind) {
        .call_op => {
            hasher.update("call_op");
            hasher.update(std.mem.asBytes(&instruction.index));
        },
        .call_helper => {
            hasher.update("call_helper");
            hasher.update(std.mem.asBytes(&instruction.index));
        },
        .return_value => {
            hasher.update("return_value");
            hasher.update(std.mem.asBytes(&instruction.index));
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

fn writePlan(path: []const u8, plan: kernel.ProgramPlan) !void {
    const file = if (std.fs.path.isAbsolute(path))
        try std.fs.createFileAbsolute(path, .{ .truncate = true })
    else
        try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(&buffer);
    try std.json.Stringify.value(plan, .{}, &writer.interface);
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

fn readPlan(allocator: std.mem.Allocator, path: []const u8) !kernel.ProgramPlan {
    const bytes = if (std.fs.path.isAbsolute(path)) blk: {
        const file = try std.fs.openFileAbsolute(path, .{});
        defer file.close();
        var buffer: [4096]u8 = undefined;
        var reader = file.reader(&buffer);
        break :blk try reader.interface.allocRemaining(allocator, .limited(std.math.maxInt(usize)));
    } else try std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
    defer allocator.free(bytes);
    const parsed = try std.json.parseFromSlice(kernel.ProgramPlan, allocator, bytes, .{});
    defer parsed.deinit();
    return try clonePlan(allocator, parsed.value);
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

    const instructions = try allocator.dupe(kernel.Instruction, plan.instructions);
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
    allocator.free(plan.instructions);
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
