// zlinter-disable field_ordering
const std = @import("std");

/// Agent Profile v0 is a construction profile over existing Boundary programs.
pub const profile_format_version: u32 = 0;
/// Fingerprint version for deterministic Agent Profile v0 identity.
pub const profile_fingerprint_version: u32 = 1;

/// Errors raised while consuming Agent budget counters.
pub const BudgetError = error{
    AgentBudgetExhausted,
};

/// Errors raised while recording bounded trace events.
pub const TraceSummaryError = error{
    AgentTraceSummaryFull,
};

/// Errors raised while decoding an Agent action tag.
pub const ActionDecodeError = error{
    MalformedAgentAction,
};

/// Errors raised while validating an Agent action.
pub const ActionValidationError = error{
    AgentActionTooLarge,
    UnknownToolId,
};

/// Errors raised while promoting a tool result into Agent state.
pub const ObservationError = error{
    AgentObservationTooLarge,
    AgentToolResultTooLarge,
    UnknownToolId,
};

/// Errors raised while validating an Agent profile.
pub const ProfileValidationError = anyerror;

/// Errors raised while validating Agent module provenance.
pub const ModuleArtifactValidationError = anyerror;

/// Agent action discriminant encoded as the closed Action sum tag.
pub const ActionTag = enum(u8) {
    final = 0,
    tool = 1,
    fail = 2,
};

/// Terminal status stored in the portable Agent state.
pub const TerminalStatus = enum(u8) {
    completed = 1,
    failed = 2,
    running = 0,
};

const terminal_status_codec = std.fmt.comptimePrint(
    "enum(running={d},completed={d},failed={d})",
    .{
        @intFromEnum(TerminalStatus.running),
        @intFromEnum(TerminalStatus.completed),
        @intFromEnum(TerminalStatus.failed),
    },
);

const action_tag_codec = std.fmt.comptimePrint(
    "sum(final={d}:string,tool={d}:Agent.ToolRequest,fail={d}:string)",
    .{
        @intFromEnum(ActionTag.final),
        @intFromEnum(ActionTag.tool),
        @intFromEnum(ActionTag.fail),
    },
);

/// Role assigned to an Agent-related Certified Boundary Module artifact.
pub const ModuleRole = enum(u8) {
    fixture_model = 2,
    root = 0,
    toolbox = 1,
};

/// Canonical Agent Action variants in portable sum tag order.
pub const canonical_action_variants = [_]ActionTag{ .final, .tool, .fail };

/// Closed tool identifier; `index` is semantic and `diagnostic_label` is diagnostic.
pub const ToolId = struct {
    index: u64,
    diagnostic_label: []const u8,

    /// Compare ToolIds by generated semantic index.
    pub fn eql(self: ToolId, other: ToolId) bool {
        return self.index == other.index;
    }
};

/// Build a closed ToolId set from compile-time diagnostic labels.
pub fn ClosedToolSet(comptime labels: []const []const u8) type {
    comptime {
        if (labels.len == 0) @compileError("Agent ToolId set must contain at least one variant");
        if (labels.len - 1 > std.math.maxInt(u64)) @compileError("Agent ToolId set exceeds u64 variant space");
        for (labels, 0..) |label, index| {
            if (label.len == 0) @compileError("Agent ToolId labels must be non-empty");
            for (labels[0..index]) |prior| {
                if (std.mem.eql(u8, label, prior)) @compileError("Agent ToolId labels must be unique");
            }
        }
    }

    return struct {
        /// Number of closed ToolId variants.
        pub const count = labels.len;

        /// Return the closed ToolId for a compile-time variant index.
        pub fn id(comptime index: usize) ToolId {
            if (index >= labels.len) @compileError("Agent ToolId index out of range");
            return .{ .index = @intCast(index), .diagnostic_label = labels[index] };
        }

        /// Find a ToolId by diagnostic label for builder/test convenience.
        pub fn find(search_label: []const u8) ?ToolId {
            inline for (labels, 0..) |candidate, index| {
                if (std.mem.eql(u8, search_label, candidate)) {
                    return .{ .index = @intCast(index), .diagnostic_label = candidate };
                }
            }
            return null;
        }

        /// Return true when the semantic ToolId index is in the closed set.
        pub fn contains(tool_id: ToolId) bool {
            return tool_id.index < @as(u64, @intCast(labels.len));
        }

        /// Return the diagnostic label for a closed ToolId.
        pub fn label(tool_id: ToolId) ![]const u8 {
            if (!contains(tool_id)) return error.UnknownToolId;
            return labels[@intCast(tool_id.index)];
        }

        /// Return all diagnostic labels in semantic variant order.
        pub fn variants() []const []const u8 {
            return labels;
        }
    };
}

/// Agent execution budget and remaining counters.
pub const Budget = struct {
    max_iterations: u32,
    max_model_calls: u32,
    max_tool_calls: u32,
    remaining_iterations: u32,
    remaining_model_calls: u32,
    remaining_tool_calls: u32,

    /// Initialize remaining counters from profile configuration limits.
    pub fn init(config: Config) Budget {
        return .{
            .max_iterations = config.max_iterations,
            .max_model_calls = config.max_model_calls,
            .max_tool_calls = config.max_tool_calls,
            .remaining_iterations = config.max_iterations,
            .remaining_model_calls = config.max_model_calls,
            .remaining_tool_calls = config.max_tool_calls,
        };
    }

    /// Consume one loop iteration budget unit.
    pub fn consumeIteration(self: *Budget) BudgetError!void {
        if (self.remaining_iterations == 0) return error.AgentBudgetExhausted;
        self.remaining_iterations -= 1;
    }

    /// Consume one model-decision budget unit.
    pub fn consumeModelCall(self: *Budget) BudgetError!void {
        if (self.remaining_model_calls == 0) return error.AgentBudgetExhausted;
        self.remaining_model_calls -= 1;
    }

    /// Consume one tool-call budget unit.
    pub fn consumeToolCall(self: *Budget) BudgetError!void {
        if (self.remaining_tool_calls == 0) return error.AgentBudgetExhausted;
        self.remaining_tool_calls -= 1;
    }
};

/// Static Agent Profile v0 capacity limits.
pub const Config = struct {
    max_iterations: u32,
    max_model_calls: u32,
    max_tool_calls: u32,
    max_observation_bytes: u32,
    max_action_bytes: u32,
    max_tool_result_bytes: u32,
    max_trace_entries: u32,
};

/// Bounded summary of the latest trace event.
pub const TraceSummary = struct {
    entry_count: u32 = 0,
    last_event: []const u8 = "",
    last_fingerprint: u64 = 0,

    /// Record one trace event if capacity remains.
    pub fn record(self: *TraceSummary, max_trace_entries: u32, event: []const u8, fingerprint: u64) TraceSummaryError!void {
        if (self.entry_count >= max_trace_entries) return error.AgentTraceSummaryFull;
        self.entry_count += 1;
        self.last_event = event;
        self.last_fingerprint = fingerprint;
    }
};

/// Portable Agent loop state shape.
pub const State = struct {
    goal: []const u8,
    current_observation: []const u8,
    prior_observation_summary: []const u8 = "",
    iteration_index: u32 = 0,
    remaining_budget: Budget,
    model_call_count: u32 = 0,
    tool_call_count: u32 = 0,
    terminal_status: TerminalStatus = .running,
    trace_summary: TraceSummary = .{},

    /// Initialize state from a goal, initial observation, and config.
    pub fn init(goal: []const u8, initial_observation: []const u8, config: Config) ObservationError!State {
        if (initial_observation.len > config.max_observation_bytes) return error.AgentObservationTooLarge;
        return .{
            .goal = goal,
            .current_observation = initial_observation,
            .remaining_budget = Budget.init(config),
        };
    }

    /// Begin a model decision step, consuming iteration and model budgets.
    pub fn beginModelDecision(self: *State) BudgetError!void {
        if (self.remaining_budget.remaining_iterations == 0) return error.AgentBudgetExhausted;
        if (self.remaining_budget.remaining_model_calls == 0) return error.AgentBudgetExhausted;
        self.remaining_budget.remaining_iterations -= 1;
        self.remaining_budget.remaining_model_calls -= 1;
        self.iteration_index += 1;
        self.model_call_count += 1;
    }

    /// Begin a tool call step, consuming tool-call budget.
    pub fn beginToolCall(self: *State) BudgetError!void {
        try self.remaining_budget.consumeToolCall();
        self.tool_call_count += 1;
    }

    /// Mark the agent state as completed.
    pub fn complete(self: *State) void {
        self.terminal_status = .completed;
    }

    /// Mark the agent state as failed.
    pub fn fail(self: *State) void {
        self.terminal_status = .failed;
    }
};

/// Portable Agent goal bytes.
pub const Goal = struct {
    bytes: []const u8,
};

/// Portable Agent observation bytes.
pub const Observation = struct {
    bytes: []const u8,
};

/// Portable Agent tool payload bytes.
pub const ToolPayload = struct {
    bytes: []const u8,
};

/// Request to call a closed Agent tool with portable payload bytes.
pub const ToolRequest = struct {
    tool_id: ToolId,
    payload: []const u8,
};

/// Result returned by a closed Agent tool.
pub const ToolResult = struct {
    tool_id: ToolId,
    bytes: []const u8,
};

/// Closed Agent action sum returned by the decision boundary.
pub const Action = union(ActionTag) {
    final: []const u8,
    tool: ToolRequest,
    fail: []const u8,
};

/// Decode a portable Action tag byte, failing closed on unknown tags.
pub fn decodeActionTag(tag: u8) ActionDecodeError!ActionTag {
    return switch (tag) {
        @intFromEnum(ActionTag.final) => .final,
        @intFromEnum(ActionTag.tool) => .tool,
        @intFromEnum(ActionTag.fail) => .fail,
        else => error.MalformedAgentAction,
    };
}

/// Validate an Agent action against capacity limits and closed ToolIds.
pub fn validateAction(comptime ToolSet: type, config: Config, action: Action) ActionValidationError!void {
    switch (action) {
        .final => |text| if (text.len > config.max_action_bytes) return error.AgentActionTooLarge,
        .fail => |reason| if (reason.len > config.max_action_bytes) return error.AgentActionTooLarge,
        .tool => |request| {
            if (!ToolSet.contains(request.tool_id)) return error.UnknownToolId;
            if (exceedsCombinedByteLimit(request.tool_id.diagnostic_label.len, request.payload.len, config.max_action_bytes)) return error.AgentActionTooLarge;
        },
    }
}

/// Promote a tool result into the next observation.
pub fn observeToolResult(comptime ToolSet: type, config: Config, state: *State, result: ToolResult) ObservationError!void {
    if (!ToolSet.contains(result.tool_id)) return error.UnknownToolId;
    if (exceedsCombinedByteLimit(result.tool_id.diagnostic_label.len, result.bytes.len, config.max_tool_result_bytes)) return error.AgentToolResultTooLarge;
    if (result.bytes.len > config.max_observation_bytes) return error.AgentObservationTooLarge;
    state.prior_observation_summary = state.current_observation;
    state.current_observation = result.bytes;
}

fn exceedsCombinedByteLimit(first_len: usize, second_len: usize, limit: u32) bool {
    const limit_usize: usize = @intCast(limit);
    return first_len > limit_usize or second_len > limit_usize - first_len;
}

/// Prompt payload sent to the model-decision boundary.
pub const DecisionPrompt = struct {
    goal: []const u8,
    observation: []const u8,
    trace_summary: TraceSummary,
    budget: Budget,
};

/// Model-decision request wrapper.
pub const DecisionRequest = struct {
    prompt: DecisionPrompt,
};

/// Model-decision response wrapper.
pub const DecisionResponse = struct {
    action: Action,
};

/// Successful Agent final result.
pub const FinalResult = struct {
    text: []const u8,
};

/// Deterministic Agent failure result.
pub const Failure = struct {
    reason: []const u8,
};

/// Agent Program handle tying a profile to ordinary Boundary program bytes.
pub const Program = struct {
    profile: Profile,
};

/// Agent-owned portable value schema identity.
pub const ValueSchema = struct {
    name: []const u8,
    codec: []const u8,
    fingerprint: u64,
};

/// Canonical Agent Profile v0 value schemas.
pub const canonical_value_schemas = [_]ValueSchema{
    schema("Agent.Goal", "string"),
    schema("Agent.Observation", "string"),
    schema("Agent.Budget", "product(max_iterations:u32,max_model_calls:u32,max_tool_calls:u32,remaining_iterations:u32,remaining_model_calls:u32,remaining_tool_calls:u32)"),
    schema("Agent.TraceSummary", "product(entry_count:u32,last_event:string,last_fingerprint:u64)"),
    schema("Agent.State", "product(goal:string,current_observation:string,prior_observation_summary:string,iteration_index:u32,remaining_budget:Agent.Budget,model_call_count:u32,tool_call_count:u32,terminal_status:" ++ terminal_status_codec ++ ",trace_summary:Agent.TraceSummary)"),
    schema("Agent.DecisionPrompt", "product(goal:string,observation:string,trace_summary:Agent.TraceSummary,budget:Agent.Budget)"),
    schema("Agent.Action", action_tag_codec),
    schema("Agent.ToolId", "product(index:u64,diagnostic_label:string)"),
    schema("Agent.ToolPayload", "string"),
    schema("Agent.ToolRequest", "product(tool_id:Agent.ToolId,payload:Agent.ToolPayload)"),
    schema("Agent.ToolResult", "product(tool_id:Agent.ToolId,bytes:string)"),
    schema("Agent.FinalResult", "product(text:string)"),
    schema("Agent.Failure", "product(reason:string)"),
};

/// Fingerprints for `canonical_value_schemas`, in schema order.
pub const canonical_schema_fingerprints = blk: {
    var fingerprints = [_]u64{0} ** canonical_value_schemas.len;
    for (canonical_value_schemas, 0..) |value_schema, index| {
        fingerprints[index] = value_schema.fingerprint;
    }
    break :blk fingerprints;
};

/// Return canonical Agent value-schema fingerprints for Profile construction.
pub fn canonicalValueSchemaFingerprints() []const u64 {
    return &canonical_schema_fingerprints;
}

/// Provenance record for an Agent-related Certified Boundary Module.
pub const ModuleArtifact = struct {
    const DecodedFacts = struct {
        module_fingerprint: u64,
        manifest_fingerprint: u64,
        world_surface_fingerprint: u64,
        import_count: usize,
        export_result_fingerprint: u64,
    };

    /// Arguments for validating an Agent module artifact against decoded target bytes.
    pub fn ValidateArgs(comptime Target: type) type {
        _ = Target;
        return struct {
            allocator: std.mem.Allocator,
            profile: Profile,
            expected_role: ModuleRole,
            bytes: []const u8,
        };
    }

    role: ModuleRole,
    profile_fingerprint: u64,
    module_fingerprint: u64,
    manifest_fingerprint: u64,
    world_surface_fingerprint: u64,
    import_count: u32,
    export_result_fingerprint: u64,
    byte_len: u64,
    byte_fingerprint: u64,

    /// Construct provenance from a profile, decoded module facts, and bytes.
    pub fn init(args: struct {
        role: ModuleRole,
        profile: Profile,
        module_fingerprint: u64,
        manifest_fingerprint: u64,
        world_surface_fingerprint: u64,
        import_count: usize,
        export_result_fingerprint: u64,
        bytes: []const u8,
    }) ModuleArtifact {
        return .{
            .role = args.role,
            .profile_fingerprint = args.profile.profile_fingerprint,
            .module_fingerprint = args.module_fingerprint,
            .manifest_fingerprint = args.manifest_fingerprint,
            .world_surface_fingerprint = args.world_surface_fingerprint,
            .import_count = @intCast(args.import_count),
            .export_result_fingerprint = args.export_result_fingerprint,
            .byte_len = args.bytes.len,
            .byte_fingerprint = fingerprintBytes(args.bytes),
        };
    }

    /// Validate that the module artifact matches the expected profile, role, bytes, and decoded module facts.
    pub fn validate(
        self: ModuleArtifact,
        comptime Target: type,
        args: ValidateArgs(Target),
    ) ModuleArtifactValidationError!void {
        var loaded = try Target.Module.decode(args.allocator, args.bytes);
        defer loaded.deinit();
        try self.validateDecodedFacts(args.profile, args.expected_role, args.bytes, .{
            .module_fingerprint = loaded.moduleFingerprint(),
            .manifest_fingerprint = loaded.manifest().manifest_fingerprint,
            .world_surface_fingerprint = loaded.worldSurfaceFingerprint(),
            .import_count = loaded.imports().len,
            .export_result_fingerprint = valueRefFingerprint(loaded.exportMain().result_ref),
        });
    }

    fn validateDecodedFacts(self: ModuleArtifact, profile: Profile, expected_role: ModuleRole, bytes: []const u8, facts: DecodedFacts) ModuleArtifactValidationError!void {
        try profile.validate();
        if (self.role != expected_role) return error.AgentModuleRoleMismatch;
        if (self.profile_fingerprint != profile.profile_fingerprint) return error.AgentProfileFingerprintMismatch;
        if (self.module_fingerprint == 0) return error.AgentModuleFingerprintMissing;
        if (self.manifest_fingerprint == 0) return error.AgentModuleFingerprintMissing;
        if (self.world_surface_fingerprint == 0) return error.AgentModuleFingerprintMissing;
        if (self.export_result_fingerprint == 0) return error.AgentModuleFingerprintMissing;
        if (self.byte_len == 0) return error.AgentModuleBytesEmpty;
        if (self.byte_fingerprint == 0) return error.AgentModuleFingerprintMissing;
        if (self.byte_len != bytes.len) return error.AgentModuleByteLengthMismatch;
        if (self.byte_fingerprint != fingerprintBytes(bytes)) return error.AgentModuleByteFingerprintMismatch;
        if (self.module_fingerprint != facts.module_fingerprint) return error.AgentModuleFingerprintMismatch;
        if (self.manifest_fingerprint != facts.manifest_fingerprint) return error.AgentModuleManifestFingerprintMismatch;
        if (self.world_surface_fingerprint != facts.world_surface_fingerprint) return error.AgentModuleWorldSurfaceFingerprintMismatch;
        if (self.import_count != facts.import_count) return error.AgentModuleImportCountMismatch;
        if (self.export_result_fingerprint != facts.export_result_fingerprint) return error.AgentModuleExportResultFingerprintMismatch;
    }
};

/// Owned module bytes plus their Agent provenance record.
pub const BuiltModule = struct {
    artifact: ModuleArtifact,
    bytes: []u8,

    /// Release owned module bytes.
    pub fn deinit(self: *BuiltModule, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes);
        self.bytes = &.{};
    }
};

/// Build Agent root full-module bytes for an existing Boundary target.
pub fn buildRootModule(comptime Target: type, allocator: std.mem.Allocator, profile: Profile) anyerror!BuiltModule {
    return buildModule(.root, Target, allocator, profile);
}

/// Build Agent toolbox provider full-module bytes for an existing Boundary target.
pub fn buildToolboxModule(comptime Target: type, allocator: std.mem.Allocator, profile: Profile) anyerror!BuiltModule {
    return buildModule(.toolbox, Target, allocator, profile);
}

/// Build fixture model full-module bytes for conformance-only targets.
pub fn buildFixtureModelModule(comptime Target: type, allocator: std.mem.Allocator, profile: Profile) anyerror!BuiltModule {
    return buildModule(.fixture_model, Target, allocator, profile);
}

fn buildModule(comptime role: ModuleRole, comptime Target: type, allocator: std.mem.Allocator, profile: Profile) !BuiltModule {
    const bytes = try Target.Module.fullImage(allocator);
    errdefer allocator.free(bytes);

    var loaded = try Target.Module.decode(allocator, bytes);
    defer loaded.deinit();

    const artifact = ModuleArtifact.init(.{
        .role = role,
        .profile = profile,
        .module_fingerprint = loaded.moduleFingerprint(),
        .manifest_fingerprint = loaded.manifest().manifest_fingerprint,
        .world_surface_fingerprint = loaded.worldSurfaceFingerprint(),
        .import_count = loaded.imports().len,
        .export_result_fingerprint = valueRefFingerprint(loaded.exportMain().result_ref),
        .bytes = bytes,
    });
    try artifact.validate(Target, .{
        .allocator = allocator,
        .profile = profile,
        .expected_role = role,
        .bytes = bytes,
    });

    return .{
        .artifact = artifact,
        .bytes = bytes,
    };
}

/// Fingerprint a loaded module value reference for Agent provenance.
pub fn valueRefFingerprint(ref: anytype) u64 {
    var hasher = std.hash.Wyhash.init(0x4147454e545f5256);
    hashBytes(&hasher, ref.codec);
    if (ref.schema_index) |index| {
        hashInt(&hasher, @as(u8, 1));
        hashInt(&hasher, index);
    } else {
        hashInt(&hasher, @as(u8, 0));
    }
    return hasher.final();
}

/// Fingerprint an Agent value schema name and portable codec description.
pub fn schemaFingerprint(name: []const u8, codec: []const u8) u64 {
    var hasher = std.hash.Wyhash.init(0x4147454e545f5343);
    hashBytes(&hasher, name);
    hashBytes(&hasher, codec);
    return hasher.final();
}

fn schema(comptime name: []const u8, comptime codec: []const u8) ValueSchema {
    @setEvalBranchQuota(4000);
    return .{
        .name = name,
        .codec = codec,
        .fingerprint = schemaFingerprint(name, codec),
    };
}

/// Agent Profile v0 capacity, schema, variant, and metadata identity.
pub const Profile = struct {
    format_version: u32 = profile_format_version,
    fingerprint_version: u32 = profile_fingerprint_version,
    profile_fingerprint: u64 = 0,
    max_iterations: u32,
    max_model_calls: u32,
    max_tool_calls: u32,
    max_observation_bytes: u32,
    max_action_bytes: u32,
    max_tool_result_bytes: u32,
    max_trace_entries: u32,
    supported_action_variants: []const ActionTag,
    supported_tool_variants: []const ToolId,
    value_schema_fingerprints: []const u64,
    metadata_bytes: []const u8 = "",

    /// Construct a Profile from config, closed ToolIds, schema fingerprints, and metadata.
    pub fn fromConfig(
        config: Config,
        supported_tool_variants: []const ToolId,
        value_schema_fingerprints: []const u64,
        metadata_bytes: []const u8,
    ) Profile {
        var profile = Profile{
            .max_iterations = config.max_iterations,
            .max_model_calls = config.max_model_calls,
            .max_tool_calls = config.max_tool_calls,
            .max_observation_bytes = config.max_observation_bytes,
            .max_action_bytes = config.max_action_bytes,
            .max_tool_result_bytes = config.max_tool_result_bytes,
            .max_trace_entries = config.max_trace_entries,
            .supported_action_variants = &canonical_action_variants,
            .supported_tool_variants = supported_tool_variants,
            .value_schema_fingerprints = value_schema_fingerprints,
            .metadata_bytes = metadata_bytes,
        };
        profile.profile_fingerprint = profile.computeFingerprint();
        return profile;
    }

    /// Compute the deterministic Agent Profile fingerprint.
    pub fn computeFingerprint(self: Profile) u64 {
        var hasher = std.hash.Wyhash.init(0x4147454e545f7630);
        hashInt(&hasher, self.format_version);
        hashInt(&hasher, self.fingerprint_version);
        hashInt(&hasher, self.max_iterations);
        hashInt(&hasher, self.max_model_calls);
        hashInt(&hasher, self.max_tool_calls);
        hashInt(&hasher, self.max_observation_bytes);
        hashInt(&hasher, self.max_action_bytes);
        hashInt(&hasher, self.max_tool_result_bytes);
        hashInt(&hasher, self.max_trace_entries);
        hashInt(&hasher, @as(u32, @intCast(self.supported_action_variants.len)));
        for (self.supported_action_variants) |variant| hashInt(&hasher, @intFromEnum(variant));
        hashInt(&hasher, @as(u32, @intCast(self.supported_tool_variants.len)));
        for (self.supported_tool_variants) |tool_id| {
            hashInt(&hasher, tool_id.index);
            hashBytes(&hasher, tool_id.diagnostic_label);
        }
        hashInt(&hasher, @as(u32, @intCast(self.value_schema_fingerprints.len)));
        for (self.value_schema_fingerprints) |fingerprint| hashInt(&hasher, fingerprint);
        hashBytes(&hasher, self.metadata_bytes);
        return hasher.final();
    }

    /// Validate profile format, fingerprint, and required non-empty capacities.
    pub fn validate(self: Profile) ProfileValidationError!void {
        if (self.format_version != profile_format_version) return error.UnsupportedAgentProfileFormat;
        if (self.fingerprint_version != profile_fingerprint_version) return error.UnsupportedAgentProfileFingerprint;
        if (self.profile_fingerprint != self.computeFingerprint()) return error.AgentProfileFingerprintMismatch;
        if (self.max_iterations == 0) return error.AgentProfileEmptyBudget;
        if (self.max_model_calls == 0) return error.AgentProfileEmptyBudget;
        if (self.max_tool_calls == 0) return error.AgentProfileEmptyBudget;
        if (self.max_observation_bytes == 0) return error.AgentProfileEmptyCapacity;
        if (self.max_action_bytes == 0) return error.AgentProfileEmptyCapacity;
        if (self.max_tool_result_bytes == 0) return error.AgentProfileEmptyCapacity;
        if (self.max_trace_entries == 0) return error.AgentProfileEmptyTrace;
        if (!std.mem.eql(ActionTag, self.supported_action_variants, &canonical_action_variants)) {
            return error.AgentProfileActionSurfaceMismatch;
        }
        if (self.supported_tool_variants.len == 0) return error.AgentProfileToolSurfaceMismatch;
        for (self.supported_tool_variants, 0..) |tool_id, index| {
            if (tool_id.index != @as(u64, @intCast(index))) return error.AgentProfileToolSurfaceMismatch;
            if (tool_id.diagnostic_label.len == 0) return error.AgentProfileToolSurfaceMismatch;
            for (self.supported_tool_variants[0..index]) |prior| {
                if (std.mem.eql(u8, tool_id.diagnostic_label, prior.diagnostic_label)) return error.AgentProfileToolSurfaceMismatch;
            }
        }
        if (!std.mem.eql(u64, self.value_schema_fingerprints, &canonical_schema_fingerprints)) {
            return error.AgentProfileSchemaSurfaceMismatch;
        }
    }
};

fn hashBytes(hasher: *std.hash.Wyhash, bytes: []const u8) void {
    hashInt(hasher, @as(u64, bytes.len));
    hasher.update(bytes);
}

/// Fingerprint arbitrary Agent-owned bytes.
pub fn fingerprintBytes(bytes: []const u8) u64 {
    var hasher = std.hash.Wyhash.init(0x4147454e545f4d4f);
    hashBytes(&hasher, bytes);
    return hasher.final();
}

fn hashInt(hasher: *std.hash.Wyhash, value: anytype) void {
    var buffer: [@sizeOf(@TypeOf(value))]u8 = undefined;
    std.mem.writeInt(@TypeOf(value), &buffer, value, .little);
    hasher.update(&buffer);
}

test "Agent Profile v0 fingerprint is deterministic and bound to tool variants" {
    const tools = ClosedToolSet(&.{ "read_file", "write_file" });
    const tool_ids = [_]ToolId{ tools.id(0), tools.id(1) };
    const config = Config{
        .max_iterations = 4,
        .max_model_calls = 4,
        .max_tool_calls = 3,
        .max_observation_bytes = 1024,
        .max_action_bytes = 256,
        .max_tool_result_bytes = 1024,
        .max_trace_entries = 8,
    };
    const profile = Profile.fromConfig(config, &tool_ids, canonicalValueSchemaFingerprints(), "fixture-agent");
    try profile.validate();
    try std.testing.expectEqual(profile.profile_fingerprint, profile.computeFingerprint());

    const shorter_tool_ids = [_]ToolId{tools.id(0)};
    const changed = Profile.fromConfig(config, &shorter_tool_ids, canonicalValueSchemaFingerprints(), "fixture-agent");
    try std.testing.expect(profile.profile_fingerprint != changed.profile_fingerprint);
}

test "ClosedToolSet variants exposes diagnostic labels in order" {
    const tools = ClosedToolSet(&.{ "actuate", "read_file", "write_file" });
    const variants = tools.variants();
    try std.testing.expectEqual(@as(usize, 3), variants.len);
    try std.testing.expectEqualStrings("actuate", variants[0]);
    try std.testing.expectEqualStrings("read_file", variants[1]);
    try std.testing.expectEqualStrings("write_file", variants[2]);
}

test "Agent canonical value schema fingerprints are stable profile inputs" {
    try std.testing.expect(canonicalValueSchemaFingerprints().len >= 11);
    try std.testing.expectEqualStrings("Agent.Goal", canonical_value_schemas[0].name);
    try std.testing.expectEqualStrings("Agent.Budget", canonical_value_schemas[2].name);
    try std.testing.expectEqualStrings("Agent.State", canonical_value_schemas[4].name);
    try std.testing.expect(std.mem.find(u8, canonical_value_schemas[4].codec, "terminal_status:enum(running=0,completed=1,failed=2)") != null);
    try std.testing.expect(canonical_value_schemas[4].fingerprint != schemaFingerprint("Agent.State", "product(goal:string,current_observation:string,prior_observation_summary:string,iteration_index:u32,remaining_budget:Agent.Budget,model_call_count:u32,tool_call_count:u32,terminal_status:u8,trace_summary:Agent.TraceSummary)"));
    try std.testing.expectEqualStrings("Agent.Action", canonical_value_schemas[6].name);
    try std.testing.expect(std.mem.find(u8, canonical_value_schemas[6].codec, "sum(final=0:string,tool=1:Agent.ToolRequest,fail=2:string)") != null);
    try std.testing.expect(canonical_value_schemas[6].fingerprint != schemaFingerprint("Agent.Action", "sum(final:string,tool:Agent.ToolRequest,fail:string)"));
    try std.testing.expectEqualStrings("Agent.ToolPayload", canonical_value_schemas[8].name);
    try std.testing.expectEqualStrings("Agent.ToolRequest", canonical_value_schemas[9].name);
    try std.testing.expect(canonical_value_schemas[0].fingerprint != schemaFingerprint("Agent.Goal", "bytes"));

    const tools = ClosedToolSet(&.{"actuate"});
    const tool_ids = [_]ToolId{tools.id(0)};
    const config = Config{
        .max_iterations = 2,
        .max_model_calls = 2,
        .max_tool_calls = 2,
        .max_observation_bytes = 128,
        .max_action_bytes = 128,
        .max_tool_result_bytes = 128,
        .max_trace_entries = 2,
    };
    const profile = Profile.fromConfig(config, &tool_ids, canonicalValueSchemaFingerprints(), "canonical-schema-test");
    try profile.validate();
    try std.testing.expectEqual(canonical_value_schemas.len, profile.value_schema_fingerprints.len);
}

test "Agent profile validation requires the exact closed action surface" {
    const tools = ClosedToolSet(&.{"actuate"});
    const tool_ids = [_]ToolId{tools.id(0)};
    const config = Config{
        .max_iterations = 2,
        .max_model_calls = 2,
        .max_tool_calls = 2,
        .max_observation_bytes = 128,
        .max_action_bytes = 128,
        .max_tool_result_bytes = 128,
        .max_trace_entries = 2,
    };
    var profile = Profile.fromConfig(config, &tool_ids, canonicalValueSchemaFingerprints(), "action-surface-test");
    profile.supported_action_variants = &.{ .final, .final, .final };
    profile.profile_fingerprint = profile.computeFingerprint();
    try std.testing.expectError(error.AgentProfileActionSurfaceMismatch, profile.validate());

    profile.supported_action_variants = &.{ .tool, .final, .fail };
    profile.profile_fingerprint = profile.computeFingerprint();
    try std.testing.expectError(error.AgentProfileActionSurfaceMismatch, profile.validate());
}

test "Agent profile validation requires complete tool and schema surfaces" {
    const tools = ClosedToolSet(&.{ "actuate", "read_file" });
    const tool_ids = [_]ToolId{ tools.id(0), tools.id(1) };
    const config = Config{
        .max_iterations = 2,
        .max_model_calls = 2,
        .max_tool_calls = 2,
        .max_observation_bytes = 128,
        .max_action_bytes = 128,
        .max_tool_result_bytes = 128,
        .max_trace_entries = 2,
    };
    var profile = Profile.fromConfig(config, &.{}, canonicalValueSchemaFingerprints(), "profile-surface-test");
    try std.testing.expectError(error.AgentProfileToolSurfaceMismatch, profile.validate());

    profile = Profile.fromConfig(config, &tool_ids, &.{}, "profile-surface-test");
    profile.profile_fingerprint = profile.computeFingerprint();
    try std.testing.expectError(error.AgentProfileSchemaSurfaceMismatch, profile.validate());

    profile = Profile.fromConfig(config, &.{ tools.id(1), tools.id(0) }, canonicalValueSchemaFingerprints(), "profile-surface-test");
    try std.testing.expectError(error.AgentProfileToolSurfaceMismatch, profile.validate());

    profile = Profile.fromConfig(config, &.{ tools.id(0), .{ .index = 1, .diagnostic_label = "actuate" } }, canonicalValueSchemaFingerprints(), "profile-surface-test");
    profile.profile_fingerprint = profile.computeFingerprint();
    try std.testing.expectError(error.AgentProfileToolSurfaceMismatch, profile.validate());
}

test "Agent closed ToolId set dispatches by generated index, not diagnostic labels" {
    const tools = ClosedToolSet(&.{ "actuate", "read_file", "write_file" });
    const actuate = tools.find("actuate") orelse return error.MissingToolId;
    try std.testing.expect(tools.contains(actuate));
    try std.testing.expectEqualStrings("actuate", try tools.label(actuate));
    try std.testing.expect(tools.find("shell") == null);
    try std.testing.expect(tools.contains(.{ .index = 0, .diagnostic_label = "shell" }));
    try std.testing.expectEqualStrings("actuate", try tools.label(.{ .index = 0, .diagnostic_label = "shell" }));
    try std.testing.expectError(error.UnknownToolId, tools.label(.{ .index = 9, .diagnostic_label = "shell" }));
}

test "Agent action validation rejects malformed tags, unknown tools, and oversized payloads" {
    const tools = ClosedToolSet(&.{"actuate"});
    const config = Config{
        .max_iterations = 2,
        .max_model_calls = 2,
        .max_tool_calls = 2,
        .max_observation_bytes = 128,
        .max_action_bytes = 8,
        .max_tool_result_bytes = 128,
        .max_trace_entries = 2,
    };
    try std.testing.expectError(error.MalformedAgentAction, decodeActionTag(99));
    try validateAction(tools, config, .{ .tool = .{ .tool_id = tools.id(0), .payload = "" } });
    try std.testing.expectError(error.UnknownToolId, validateAction(tools, config, .{
        .tool = .{ .tool_id = .{ .index = 4, .diagnostic_label = "shell" }, .payload = "" },
    }));
    try std.testing.expectError(error.AgentActionTooLarge, validateAction(tools, config, .{ .final = "too-large" }));
    try std.testing.expectError(error.AgentActionTooLarge, validateAction(tools, config, .{
        .tool = .{ .tool_id = .{ .index = 0, .diagnostic_label = "too-large" }, .payload = "" },
    }));
    try std.testing.expectError(error.AgentActionTooLarge, validateAction(tools, config, .{
        .tool = .{ .tool_id = tools.id(0), .payload = "xx" },
    }));
}

test "Agent module artifact binds profile and full module byte identity" {
    const tools = ClosedToolSet(&.{"actuate"});
    const tool_ids = [_]ToolId{tools.id(0)};
    const config = Config{
        .max_iterations = 2,
        .max_model_calls = 2,
        .max_tool_calls = 2,
        .max_observation_bytes = 128,
        .max_action_bytes = 128,
        .max_tool_result_bytes = 128,
        .max_trace_entries = 2,
    };
    const profile = Profile.fromConfig(config, &tool_ids, canonicalValueSchemaFingerprints(), "module-artifact-test");
    const bytes = "certified-boundary-module-fixture";
    const artifact = ModuleArtifact.init(.{
        .role = .toolbox,
        .profile = profile,
        .module_fingerprint = 0x1111,
        .manifest_fingerprint = 0x2222,
        .world_surface_fingerprint = 0x3333,
        .import_count = 1,
        .export_result_fingerprint = 0x4444,
        .bytes = bytes,
    });
    const facts: ModuleArtifact.DecodedFacts = .{
        .module_fingerprint = artifact.module_fingerprint,
        .manifest_fingerprint = artifact.manifest_fingerprint,
        .world_surface_fingerprint = artifact.world_surface_fingerprint,
        .import_count = artifact.import_count,
        .export_result_fingerprint = artifact.export_result_fingerprint,
    };
    try artifact.validateDecodedFacts(profile, .toolbox, bytes, facts);
    try std.testing.expectEqual(fingerprintBytes(bytes), artifact.byte_fingerprint);
    try std.testing.expectError(error.AgentModuleRoleMismatch, artifact.validateDecodedFacts(profile, .root, bytes, facts));
    try std.testing.expectError(error.AgentModuleByteFingerprintMismatch, artifact.validateDecodedFacts(profile, .toolbox, "certified-boundary-module-forgery", facts));
    try std.testing.expectError(error.AgentModuleFingerprintMismatch, artifact.validateDecodedFacts(profile, .toolbox, bytes, .{
        .module_fingerprint = 0x5555,
        .manifest_fingerprint = artifact.manifest_fingerprint,
        .world_surface_fingerprint = artifact.world_surface_fingerprint,
        .import_count = artifact.import_count,
        .export_result_fingerprint = artifact.export_result_fingerprint,
    }));
}

test "Agent value reference fingerprint binds schema-index presence" {
    const absent = valueRefFingerprint(.{ .codec = "json", .schema_index = @as(?u16, null) });
    const max_index = valueRefFingerprint(.{ .codec = "json", .schema_index = @as(?u16, std.math.maxInt(u16)) });
    try std.testing.expect(absent != max_index);
}

test "Agent state budget fails closed before extra model or tool calls" {
    const config = Config{
        .max_iterations = 1,
        .max_model_calls = 1,
        .max_tool_calls = 1,
        .max_observation_bytes = 128,
        .max_action_bytes = 128,
        .max_tool_result_bytes = 128,
        .max_trace_entries = 2,
    };
    var state = try State.init("goal=fixture", "goal=fixture", config);
    try state.beginModelDecision();
    try std.testing.expectError(error.AgentBudgetExhausted, state.beginModelDecision());
    try state.beginToolCall();
    try std.testing.expectError(error.AgentBudgetExhausted, state.beginToolCall());
}

test "Agent model decision budget failure does not consume iteration" {
    const config = Config{
        .max_iterations = 2,
        .max_model_calls = 1,
        .max_tool_calls = 1,
        .max_observation_bytes = 128,
        .max_action_bytes = 128,
        .max_tool_result_bytes = 128,
        .max_trace_entries = 2,
    };
    var state = try State.init("goal=fixture", "goal=fixture", config);
    try state.beginModelDecision();
    try std.testing.expectEqual(@as(u32, 1), state.remaining_budget.remaining_iterations);
    try std.testing.expectEqual(@as(u32, 0), state.remaining_budget.remaining_model_calls);
    try std.testing.expectError(error.AgentBudgetExhausted, state.beginModelDecision());
    try std.testing.expectEqual(@as(u32, 1), state.remaining_budget.remaining_iterations);
    try std.testing.expectEqual(@as(u32, 0), state.remaining_budget.remaining_model_calls);
    try std.testing.expectEqual(@as(u32, 1), state.iteration_index);
    try std.testing.expectEqual(@as(u32, 1), state.model_call_count);
}

test "Agent tool observations obey the observation byte cap" {
    const tools = ClosedToolSet(&.{"actuate"});
    const config = Config{
        .max_iterations = 2,
        .max_model_calls = 2,
        .max_tool_calls = 2,
        .max_observation_bytes = 4,
        .max_action_bytes = 16,
        .max_tool_result_bytes = 16,
        .max_trace_entries = 2,
    };
    var state = try State.init("goal", "seed", config);
    try std.testing.expectError(error.AgentObservationTooLarge, State.init("goal", "12345", config));
    try std.testing.expectError(error.UnknownToolId, observeToolResult(tools, config, &state, .{
        .tool_id = .{ .index = 9, .diagnostic_label = "shell" },
        .bytes = "1234",
    }));
    try std.testing.expectEqualStrings("seed", state.current_observation);
    try std.testing.expectError(error.AgentToolResultTooLarge, observeToolResult(tools, config, &state, .{
        .tool_id = .{ .index = 0, .diagnostic_label = "tool-label-too-large" },
        .bytes = "",
    }));
    try std.testing.expectEqualStrings("seed", state.current_observation);
    try std.testing.expectError(error.AgentObservationTooLarge, observeToolResult(tools, config, &state, .{
        .tool_id = .{ .index = 0, .diagnostic_label = "actuate" },
        .bytes = "12345",
    }));
    try std.testing.expectEqualStrings("seed", state.current_observation);

    try observeToolResult(tools, config, &state, .{
        .tool_id = .{ .index = 0, .diagnostic_label = "actuate" },
        .bytes = "1234",
    });
    try std.testing.expectEqualStrings("1234", state.current_observation);
}

test "Agent trace summary is bounded" {
    var summary = TraceSummary{};
    try summary.record(1, "model=prompted", 0xabc);
    try std.testing.expectEqual(@as(u32, 1), summary.entry_count);
    try std.testing.expectError(error.AgentTraceSummaryFull, summary.record(1, "tool=called", 0xdef));
}
