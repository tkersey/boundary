const artifact_build_options = @import("artifact_build_options");
const program_plan = @import("internal_program_plan");
const std = @import("std");

/// Stable section ids used by the ArtifactV1 binary layout.
pub const SectionId = enum(u16) {
    block_table = 0x0009,
    call_arg_table = 0x0007,
    capability_manifest = 0x0001,
    function_table = 0x0008,
    instruction_table = 0x000b,
    local_table = 0x0006,
    op_table = 0x0004,
    output_table = 0x0005,
    requirement_table = 0x0003,
    string_table = 0x0002,
    terminator_table = 0x000a,
};

/// Hash algorithm ids admitted by ArtifactV1.
pub const HashKind = enum(u8) {
    blake3_256 = 1,
};

/// External capability kinds declared by ArtifactV1.
pub const CapabilityKind = enum(u8) {
    tool = 2,
};

/// Canonical capability codecs admitted by ArtifactV1.
pub const CapabilityCodecV1 = enum(u8) {
    bool = 2,
    bytes = 5,
    data_value = 6,
    i32 = 3,
    string = 4,
    unit = 1,
    usize = 7,
};

/// Structural host operation kind carried by ArtifactV1 capability rows.
pub const HostOpKind = enum(u8) {
    after_call = 2,
    call = 1,
};

/// One string-table reference inside ArtifactV1.
pub const StringRef = struct {
    offset: u32,
    len: u32,
};

/// One section directory entry inside ArtifactV1.
pub const SectionDirectoryEntryV1 = struct {
    section_id: SectionId,
    flags: u16 = 0,
    offset: u64,
    size: u64,
    entry_count: u32,
};

/// One capability operation declared in ArtifactV1.
pub const CapabilityOpV1 = struct {
    capability_id: u16,
    op_id: u16,
    host_op_kind: HostOpKind,
    payload_codec: CapabilityCodecV1,
    result_codec: CapabilityCodecV1,
    plan_op_ordinal: u16,
};

/// One external capability declared in ArtifactV1.
pub const CapabilityV1 = struct {
    capability_id: u16,
    kind: CapabilityKind,
    required: bool = true,
    label: []const u8,
    ops: []const CapabilityOpV1,
};

/// Exact-build capability manifest carried by ArtifactV1.
pub const CapabilityManifestV1 = struct {
    build_fingerprint_blake3_256: [32]u8,
    capabilities: []const CapabilityV1,
};

const cap_fp_domain_v2 = "ability-artifact-v1-capability-fingerprint-v2";
const cap_fp_domain_v3 = "ability-artifact-v1-capability-fingerprint-v3";
const capability_global_tool_after = "tool.after";
const capability_global_tool_call = "tool.call";

const artifact_magic = "SFTARTV1";
const artifact_header_len: usize = 72;
const artifact_directory_entry_len: usize = 32;
const artifact_format_version_v1: u16 = 1;
const artifact_format_version_v2: u16 = 2;
const artifact_format_version_v3: u16 = 3;
const artifact_version_current: u16 = artifact_format_version_v3;

const section_optional_flag: u16 = 0x1;
const capability_required_flag: u8 = 0x1;

/// Public in-memory representation of one decoded ArtifactV1 payload.
pub const ArtifactV1 = struct {
    artifact_version: u16 = artifact_version_current,
    semantic_ir_hash64: u64,
    artifact_hash_blake3_256: [32]u8,
    manifest_build_fingerprint: [32]u8 = std.mem.zeroes([32]u8),
    build_fingerprint_blake3_256: [32]u8,
    entry_function_index: u16,
    capabilities: []CapabilityV1,
    requirement_capability_ids: []u16,
    functions: []program_plan.FunctionPlan,
    requirements: []program_plan.RequirementPlan,
    ops: []program_plan.OpPlan,
    outputs: []program_plan.OutputPlan,
    locals: []program_plan.LocalPlan,
    call_args: []u16,
    blocks: []program_plan.BlockPlan,
    terminators: []program_plan.Terminator,
    instructions: []program_plan.Instruction,

    /// Validate that the artifact manifest and rebuilt program plan are self-consistent.
    pub fn validate(self: @This(), allocator: std.mem.Allocator) anyerror!void {
        try validateManifest(self.manifest_build_fingerprint, self.capabilities);
        const recomputed_build_fingerprint = try buildFingerprintForCapabilitiesForArtifactVersion(
            allocator,
            self.artifact_version,
            self.manifest_build_fingerprint,
            self.capabilities,
        );
        if (!std.mem.eql(u8, &recomputed_build_fingerprint, &self.build_fingerprint_blake3_256)) {
            return error.BuildFingerprintMismatch;
        }
        if (self.entry_function_index >= self.functions.len) return error.InvalidEntryFunctionIndex;
        if (self.functions[self.entry_function_index].parameter_count != 0) return error.UnsupportedEntryParameters;
        const plan = try self.toProgramPlan(allocator);
        defer deepFreeProgramPlan(allocator, plan);
        try plan.validate();
        try validateExecutableCodecSupport(plan);
        try validateExecutableInstructionSupport(plan);
        try validateRequirementCapabilityMappings(plan, self.requirement_capability_ids, self.capabilities);
    }

    /// Rebuild one runtime-owned ProgramPlan from this artifact payload.
    pub fn toProgramPlan(self: @This(), allocator: std.mem.Allocator) anyerror!program_plan.ProgramPlan {
        const label = try allocator.dupe(u8, "artifact_v1");
        errdefer allocator.free(label);
        const functions = try deepCloneFunctionPlans(allocator, self.functions);
        errdefer deepFreeFunctionPlansConst(allocator, functions);
        const requirements = try deepCloneRequirementPlans(allocator, self.requirements);
        errdefer deepFreeRequirementPlansConst(allocator, requirements);
        const ops = try deepCloneOpPlans(allocator, self.ops);
        errdefer deepFreeOpPlansConst(allocator, ops);
        const outputs = try deepCloneOutputPlans(allocator, self.outputs);
        errdefer deepFreeOutputPlansConst(allocator, outputs);
        const locals = try allocator.dupe(program_plan.LocalPlan, self.locals);
        errdefer allocator.free(locals);
        const call_args = try allocator.dupe(u16, self.call_args);
        errdefer allocator.free(call_args);
        const blocks = try allocator.dupe(program_plan.BlockPlan, self.blocks);
        errdefer allocator.free(blocks);
        const terminators = try allocator.dupe(program_plan.Terminator, self.terminators);
        errdefer allocator.free(terminators);
        const instructions = try deepCloneInstructions(allocator, self.instructions);
        errdefer deepFreeInstructionsConst(allocator, instructions);

        return .{
            .label = label,
            .ir_hash = self.semantic_ir_hash64,
            .entry_index = self.entry_function_index,
            .functions = functions,
            .requirements = requirements,
            .ops = ops,
            .outputs = outputs,
            .locals = locals,
            .call_args = call_args,
            .blocks = blocks,
            .terminators = terminators,
            .instructions = instructions,
        };
    }

    /// Release all allocator-owned memory held by this artifact.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        deepFreeCapabilities(allocator, self.capabilities);
        allocator.free(self.requirement_capability_ids);
        deepFreeFunctionPlans(allocator, self.functions);
        deepFreeRequirementPlans(allocator, self.requirements);
        deepFreeOpPlans(allocator, self.ops);
        deepFreeOutputPlans(allocator, self.outputs);
        allocator.free(self.locals);
        allocator.free(self.call_args);
        allocator.free(self.blocks);
        allocator.free(self.terminators);
        deepFreeInstructions(allocator, self.instructions);
        self.* = undefined;
    }
};

/// Decode-time failures for ArtifactV1 binary payloads.
pub const DecodeError = error{
    BadMagic,
    BuildFingerprintMismatch,
    DuplicateCapabilityId,
    DuplicateCapabilityOpId,
    DuplicateDirectorySection,
    InvalidToolId,
    InvalidDirectoryBounds,
    InvalidEntryFunctionIndex,
    InvalidHashKind,
    InvalidRequiredSection,
    NonZeroReserved,
    StringRefOutOfBounds,
    UnsortedDirectorySection,
    UnsupportedEntryParameters,
    UnsupportedVersion,
    ArtifactHashMismatch,
    UnsupportedExecutableCodec,
    UnsupportedExecInstruction,
};

fn isReservedOptionalSectionId(raw_section_id: u16) bool {
    return switch (raw_section_id) {
        0x1000...0x10ff, 0x1100...0x11ff, 0x1200...0x12ff => true,
        else => false,
    };
}

fn supportedArtifactVersion(version: u16) bool {
    return switch (version) {
        artifact_format_version_v1, artifact_format_version_v2, artifact_format_version_v3 => true,
        else => false,
    };
}

fn hostOpKindName(kind: HostOpKind) []const u8 {
    return switch (kind) {
        .call => "call",
        .after_call => "after_call",
    };
}

fn capabilityFingerprintDomain(artifact_version: u16) ![]const u8 {
    return switch (artifact_version) {
        artifact_format_version_v1, artifact_format_version_v2 => cap_fp_domain_v2,
        artifact_format_version_v3 => cap_fp_domain_v3,
        else => error.UnsupportedVersion,
    };
}

fn capabilityGlobalNameForHostOpKind(kind: HostOpKind) []const u8 {
    return switch (kind) {
        .call => capability_global_tool_call,
        .after_call => capability_global_tool_after,
    };
}

fn decodeLegacyCapabilityHostOpKind(global_op_name: []const u8) !HostOpKind {
    if (std.mem.eql(u8, global_op_name, capability_global_tool_call)) return .call;
    if (std.mem.eql(u8, global_op_name, capability_global_tool_after)) return .after_call;
    return error.UnsupportedVersion;
}

/// Build one exact-build fingerprint from an arbitrary seed string.
pub fn buildFingerprintFromSeed(seed: []const u8) [32]u8 {
    var digest = std.mem.zeroes([32]u8);
    std.crypto.hash.Blake3.hash(seed, &digest, .{});
    return digest;
}

/// Fold one caller seed into one build-derived exact-build fingerprint.
pub fn buildFingerprintWithSeed(base_fingerprint: [32]u8, seed: []const u8) [32]u8 {
    var hasher = std.crypto.hash.Blake3.init(.{});
    var len_bytes = std.mem.zeroes([8]u8);

    hasher.update("ability-artifact-v1-build-fingerprint-seed-v1");
    hasher.update(&base_fingerprint);
    std.mem.writeInt(u64, &len_bytes, seed.len, .little);
    hasher.update(&len_bytes);
    hasher.update(seed);

    var digest = std.mem.zeroes([32]u8);
    hasher.final(&digest);
    return digest;
}

/// Return the current build-derived exact-build fingerprint used by default ArtifactV1 emission.
pub fn defaultBuildFingerprint() [32]u8 {
    return artifact_build_options.default_artifact_build_fingerprint;
}

/// Bind one exact-build fingerprint to the current build plus one explicit capability manifest.
pub fn buildFingerprintForCapabilities(
    allocator: std.mem.Allocator,
    base_fingerprint: [32]u8,
    capabilities: []const CapabilityV1,
) ![32]u8 {
    return buildFingerprintForCapabilitiesForArtifactVersion(
        allocator,
        artifact_version_current,
        base_fingerprint,
        capabilities,
    );
}

/// Bind one exact-build fingerprint to one explicit capability manifest using a specific retained ArtifactV1 wire version.
pub fn buildFingerprintForCapabilitiesForArtifactVersion(
    allocator: std.mem.Allocator,
    artifact_version: u16,
    base_fingerprint: [32]u8,
    capabilities: []const CapabilityV1,
) ![32]u8 {
    try validateManifest(base_fingerprint, capabilities);

    var strings = StringTable.init(allocator);
    defer strings.deinit();

    const encoded_manifest = try encodeCapabilityManifestVersioned(allocator, artifact_version, &strings, .{
        .build_fingerprint_blake3_256 = base_fingerprint,
        .capabilities = capabilities,
    });
    defer allocator.free(encoded_manifest);
    const string_bytes = try strings.toOwnedBytes(allocator);
    defer allocator.free(string_bytes);

    return try hashCapabilityFingerprintSectionsVersioned(artifact_version, encoded_manifest, string_bytes);
}

/// Map one ProgramPlan codec into the external capability codec surface.
pub fn mapPlanCodecToCapabilityCodec(codec: program_plan.ValueCodec) CapabilityCodecV1 {
    return switch (codec) {
        .unit => .unit,
        .bool => .bool,
        .i32 => .i32,
        .string => .string,
        .string_list => .data_value,
        .usize => .usize,
    };
}

/// Derive one default tool capability manifest from ProgramPlan requirements.
pub fn deriveToolCapabilitiesFromPlan(
    allocator: std.mem.Allocator,
    plan: program_plan.ProgramPlan,
) anyerror![]CapabilityV1 {
    const capabilities = try allocator.alloc(CapabilityV1, plan.requirements.len);
    var initialized_capabilities: usize = 0;
    errdefer deepFreeCapabilitiesPrefix(allocator, capabilities, initialized_capabilities);

    for (plan.requirements, 0..) |requirement, index| {
        const normalized_requirement_label = try normalizeToolIdRequirementLabel(allocator, requirement.label);
        defer allocator.free(normalized_requirement_label);
        const label = try std.fmt.allocPrint(allocator, "generated/{s}@v1", .{normalized_requirement_label});
        errdefer allocator.free(label);
        const op_start = requirement.first_op;
        const op_end = op_start + requirement.op_count;
        var extra_after_ops: usize = 0;
        after_count_loop: for (plan.ops[op_start..op_end], 0..) |op, op_index| {
            if (!op.has_after) continue :after_count_loop;
            if (op.mode == .abort) return error.InvalidRequiredSection;
            _ = afterCapabilityPayloadCodecForOp(plan, @intCast(op_start + op_index)) orelse return error.InvalidRequiredSection;
            _ = afterCapabilityResultCodecForOp(plan, @intCast(op_start + op_index)) orelse return error.InvalidRequiredSection;
            extra_after_ops += 1;
        }
        const ops = try allocator.alloc(CapabilityOpV1, requirement.op_count + extra_after_ops);
        var initialized_ops: usize = 0;
        errdefer deepFreeCapabilityOpsPrefix(allocator, ops, initialized_ops);
        for (plan.ops[op_start..op_end], 0..) |op, op_index| {
            ops[op_index] = .{
                .capability_id = @intCast(index),
                .op_id = @intCast(op_index),
                .host_op_kind = .call,
                .payload_codec = mapPlanCodecToCapabilityCodec(op.payload_codec),
                .result_codec = mapPlanCodecToCapabilityCodec(try capabilityResultCodecForOp(plan, op_start + op_index)),
                .plan_op_ordinal = @intCast(op_index),
            };
            initialized_ops = op_index + 1;
        }
        var next_after_op_id: usize = requirement.op_count;
        after_emit_loop: for (plan.ops[op_start..op_end], 0..) |op, op_index| {
            if (!op.has_after) continue :after_emit_loop;
            if (op.mode == .abort) return error.InvalidRequiredSection;
            const after_payload_codec = afterCapabilityPayloadCodecForOp(plan, @intCast(op_start + op_index)) orelse return error.InvalidRequiredSection;
            const after_result_codec = afterCapabilityResultCodecForOp(plan, @intCast(op_start + op_index)) orelse return error.InvalidRequiredSection;
            ops[initialized_ops] = .{
                .capability_id = @intCast(index),
                .op_id = @intCast(next_after_op_id),
                .host_op_kind = .after_call,
                .payload_codec = mapPlanCodecToCapabilityCodec(after_payload_codec),
                .result_codec = mapPlanCodecToCapabilityCodec(after_result_codec),
                .plan_op_ordinal = @intCast(op_index),
            };
            initialized_ops += 1;
            next_after_op_id += 1;
        }
        capabilities[index] = .{
            .capability_id = @intCast(index),
            .kind = .tool,
            .required = true,
            .label = label,
            .ops = ops,
        };
        initialized_capabilities = index + 1;
    }
    return capabilities;
}

fn normalizeToolIdRequirementLabel(allocator: std.mem.Allocator, label: []const u8) ![]u8 {
    var normalized = std.ArrayList(u8).empty;
    errdefer normalized.deinit(allocator);
    const hex = "0123456789abcdef";
    for (label) |byte| {
        switch (byte) {
            'a'...'z', '0'...'9', '.', '-' => try normalized.append(allocator, byte),
            '_' => try normalized.appendSlice(allocator, "__"),
            else => {
                try normalized.append(allocator, '_');
                try normalized.append(allocator, hex[byte >> 4]);
                try normalized.append(allocator, hex[byte & 0x0f]);
            },
        }
    }
    return normalized.toOwnedSlice(allocator);
}

/// Encode one validated ProgramPlan into canonical ArtifactV1 bytes.
pub fn encodeProgramPlan(
    allocator: std.mem.Allocator,
    plan: program_plan.ProgramPlan,
    manifest: CapabilityManifestV1,
) anyerror![]u8 {
    return encodeProgramPlanVersioned(
        allocator,
        artifact_version_current,
        plan,
        manifest,
    );
}

fn encodeProgramPlanVersioned(
    allocator: std.mem.Allocator,
    artifact_version: u16,
    plan: program_plan.ProgramPlan,
    manifest: CapabilityManifestV1,
) anyerror![]u8 {
    try plan.validate();
    try validateExecutableCodecSupport(plan);
    try validateExecutableInstructionSupport(plan);
    if (plan.functions[plan.entry_index].parameter_count != 0) return error.UnsupportedEntryParameters;
    try validateManifest(manifest.build_fingerprint_blake3_256, manifest.capabilities);
    try validateRequirementCapabilityOpNameDisambiguation(plan, manifest.capabilities);

    var strings = StringTable.init(allocator);
    defer strings.deinit();

    const capability_manifest = try encodeCapabilityManifestVersioned(allocator, artifact_version, &strings, manifest);
    defer allocator.free(capability_manifest);
    const requirement_table = try encodeRequirementTable(allocator, &strings, plan, manifest.capabilities);
    defer allocator.free(requirement_table);
    const op_table = try encodeOpTable(allocator, &strings, plan.ops);
    defer allocator.free(op_table);
    const output_table = try encodeOutputTable(allocator, &strings, plan.outputs);
    defer allocator.free(output_table);
    const local_table = try encodeLocalTable(allocator, plan.locals);
    defer allocator.free(local_table);
    const call_arg_table = try encodeCallArgTable(allocator, plan.call_args);
    defer allocator.free(call_arg_table);
    const function_table = try encodeFunctionTable(allocator, &strings, plan.functions);
    defer allocator.free(function_table);
    const block_table = try encodeBlockTable(allocator, plan.blocks);
    defer allocator.free(block_table);
    const terminator_table = try encodeTerminatorTable(allocator, plan.terminators);
    defer allocator.free(terminator_table);
    const instruction_table = try encodeInstructionTable(allocator, artifact_version, &strings, plan);
    defer allocator.free(instruction_table);
    const string_table = try strings.toOwnedBytes(allocator);
    defer allocator.free(string_table);

    const payloads = [_]struct {
        section_id: SectionId,
        bytes: []const u8,
        entry_count: u32,
    }{
        .{ .section_id = .capability_manifest, .bytes = capability_manifest, .entry_count = @intCast(manifest.capabilities.len) },
        .{ .section_id = .string_table, .bytes = string_table, .entry_count = @intCast(strings.items.items.len) },
        .{ .section_id = .requirement_table, .bytes = requirement_table, .entry_count = @intCast(plan.requirements.len) },
        .{ .section_id = .op_table, .bytes = op_table, .entry_count = @intCast(plan.ops.len) },
        .{ .section_id = .output_table, .bytes = output_table, .entry_count = @intCast(plan.outputs.len) },
        .{ .section_id = .local_table, .bytes = local_table, .entry_count = @intCast(plan.locals.len) },
        .{ .section_id = .call_arg_table, .bytes = call_arg_table, .entry_count = @intCast(plan.call_args.len) },
        .{ .section_id = .function_table, .bytes = function_table, .entry_count = @intCast(plan.functions.len) },
        .{ .section_id = .block_table, .bytes = block_table, .entry_count = @intCast(plan.blocks.len) },
        .{ .section_id = .terminator_table, .bytes = terminator_table, .entry_count = @intCast(plan.terminators.len) },
        .{ .section_id = .instruction_table, .bytes = instruction_table, .entry_count = @intCast(plan.instructions.len) },
    };

    const directory_offset = artifact_header_len;
    const payload_offset_base = directory_offset + artifact_directory_entry_len * payloads.len;

    var directories = [_]SectionDirectoryEntryV1{.{
        .section_id = .capability_manifest,
        .offset = 0,
        .size = 0,
        .entry_count = 0,
    }} ** payloads.len;
    var payload_offset: usize = payload_offset_base;
    for (payloads, 0..) |payload, index| {
        directories[index] = .{
            .section_id = payload.section_id,
            .offset = @intCast(payload_offset),
            .size = payload.bytes.len,
            .entry_count = payload.entry_count,
        };
        payload_offset += payload.bytes.len;
    }

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, payload_offset);

    try out.appendSlice(allocator, artifact_magic);
    try appendU16(&out, allocator, artifact_header_len);
    try appendU16(&out, allocator, artifact_version);
    try appendU64(&out, allocator, @intCast(directory_offset));
    try appendU16(&out, allocator, @intCast(payloads.len));
    try appendU16(&out, allocator, plan.entry_index);
    try appendU64(&out, allocator, plan.ir_hash);
    try out.append(allocator, @intFromEnum(HashKind.blake3_256));
    try out.append(allocator, 0);
    try out.appendNTimes(allocator, 0, 6);
    const hash_offset = out.items.len;
    try out.appendNTimes(allocator, 0, 32);

    for (directories) |directory| try encodeDirectoryEntry(&out, allocator, directory);
    for (payloads) |payload| try out.appendSlice(allocator, payload.bytes);

    var hash_input = try allocator.dupe(u8, out.items);
    defer allocator.free(hash_input);
    @memset(hash_input[hash_offset .. hash_offset + 32], 0);
    var digest = std.mem.zeroes([32]u8);
    std.crypto.hash.Blake3.hash(hash_input, &digest, .{});
    @memcpy(out.items[hash_offset .. hash_offset + 32], &digest);

    return out.toOwnedSlice(allocator);
}

/// Decode canonical ArtifactV1 bytes into the in-memory artifact surface.
pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) anyerror!ArtifactV1 {
    if (bytes.len < artifact_header_len) return error.InvalidDirectoryBounds;
    if (!std.mem.eql(u8, bytes[0..8], artifact_magic)) return error.BadMagic;
    if (readU16(bytes, 8) != artifact_header_len) return error.UnsupportedVersion;
    const artifact_version = readU16(bytes, 10);
    if (!supportedArtifactVersion(artifact_version)) return error.UnsupportedVersion;
    const directory_offset = readU64(bytes, 12);
    const directory_count = readU16(bytes, 20);
    const entry_index = readU16(bytes, 22);
    const ir_hash = readU64(bytes, 24);
    if (bytes[32] != @intFromEnum(HashKind.blake3_256)) return error.InvalidHashKind;
    if (bytes[33] != 0) return error.NonZeroReserved;
    for (bytes[34..40]) |byte| if (byte != 0) return error.NonZeroReserved;
    const expected_hash = bytes[40..72];

    if (directory_offset != artifact_header_len) return error.InvalidDirectoryBounds;
    const directory_bytes_len = @as(usize, directory_count) * artifact_directory_entry_len;
    const bytes_len_u64: u64 = @intCast(bytes.len);
    const directory_end = checkedSectionEnd(directory_offset, directory_bytes_len) orelse return error.InvalidDirectoryBounds;
    if (directory_end > bytes_len_u64) return error.InvalidDirectoryBounds;

    var hash_input = try allocator.dupe(u8, bytes);
    defer allocator.free(hash_input);
    @memset(hash_input[40..72], 0);
    var actual_hash = std.mem.zeroes([32]u8);
    std.crypto.hash.Blake3.hash(hash_input, &actual_hash, .{});
    if (!std.mem.eql(u8, expected_hash, &actual_hash)) return error.ArtifactHashMismatch;

    var required_seen = std.EnumSet(SectionId).empty;
    var directories = std.ArrayList(SectionDirectoryEntryV1).empty;
    defer directories.deinit(allocator);
    const SectionRange = struct {
        offset: u64,
        end: u64,
    };
    var section_ranges = std.ArrayList(SectionRange).empty;
    defer section_ranges.deinit(allocator);

    var cursor: usize = @intCast(directory_offset);
    var previous_section_id: ?u16 = null;
    while (@as(u64, @intCast(cursor)) < directory_end) : (cursor += artifact_directory_entry_len) {
        const raw_section_id = readU16(bytes, cursor);
        if (previous_section_id) |previous| {
            if (raw_section_id < previous) return error.UnsortedDirectorySection;
            if (raw_section_id == previous) return error.DuplicateDirectorySection;
        }
        previous_section_id = raw_section_id;
        const flags = readU16(bytes, cursor + 2);
        if ((flags & ~section_optional_flag) != 0) return error.UnsupportedVersion;
        const optional_section = (flags & section_optional_flag) != 0;
        if (readU32(bytes, cursor + 4) != 0) return error.NonZeroReserved;
        const offset = readU64(bytes, cursor + 8);
        const size = readU64(bytes, cursor + 16);
        const entry_count = readU32(bytes, cursor + 24);
        if (readU32(bytes, cursor + 28) != 0) return error.NonZeroReserved;
        const section_end = checkedSectionEnd(offset, size) orelse return error.InvalidDirectoryBounds;
        if (section_end > bytes_len_u64 or offset < directory_end) return error.InvalidDirectoryBounds;
        for (section_ranges.items) |existing| {
            if (offset < existing.end and existing.offset < section_end) return error.InvalidDirectoryBounds;
        }
        try section_ranges.append(allocator, .{ .offset = offset, .end = section_end });
        const section_id = std.enums.fromInt(SectionId, raw_section_id) orelse {
            if (optional_section and isReservedOptionalSectionId(raw_section_id)) continue;
            return error.InvalidRequiredSection;
        };
        if (required_seen.contains(section_id)) return error.DuplicateDirectorySection;
        required_seen.insert(section_id);
        try directories.append(allocator, .{
            .section_id = section_id,
            .flags = flags,
            .offset = offset,
            .size = size,
            .entry_count = entry_count,
        });
    }

    inline for (std.meta.fields(SectionId)) |field| {
        if (!required_seen.contains(@field(SectionId, field.name))) return error.InvalidRequiredSection;
    }

    const string_bytes = sectionBytes(bytes, directories.items, .string_table);
    const decoded_manifest = try decodeCapabilityManifest(
        allocator,
        artifact_version,
        string_bytes,
        sectionBytes(bytes, directories.items, .capability_manifest),
    );
    const manifest_build_fingerprint = decoded_manifest.build_fingerprint_blake3_256;
    var capabilities = decoded_manifest.capabilities;
    errdefer if (capabilities.len != 0) deepFreeCapabilities(allocator, capabilities);
    const build_fingerprint = try buildFingerprintForCapabilitiesForArtifactVersion(
        allocator,
        artifact_version,
        manifest_build_fingerprint,
        capabilities,
    );

    var decoded_requirements = try decodeRequirementTable(allocator, string_bytes, sectionBytes(bytes, directories.items, .requirement_table));
    errdefer {
        if (decoded_requirements.capability_ids.len != 0) allocator.free(decoded_requirements.capability_ids);
        if (decoded_requirements.items.len != 0) deepFreeRequirementPlans(allocator, decoded_requirements.items);
    }

    var functions = try decodeFunctionTable(allocator, artifact_version, string_bytes, sectionBytes(bytes, directories.items, .function_table));
    errdefer if (functions.len != 0) deepFreeFunctionPlans(allocator, functions);

    var ops = try decodeOpTable(allocator, string_bytes, sectionBytes(bytes, directories.items, .op_table));
    errdefer if (ops.len != 0) deepFreeOpPlans(allocator, ops);

    var outputs = try decodeOutputTable(allocator, string_bytes, sectionBytes(bytes, directories.items, .output_table));
    errdefer if (outputs.len != 0) deepFreeOutputPlans(allocator, outputs);

    var locals = try decodeLocalTable(allocator, sectionBytes(bytes, directories.items, .local_table));
    errdefer if (locals.len != 0) allocator.free(locals);

    var call_args = try decodeCallArgTable(allocator, sectionBytes(bytes, directories.items, .call_arg_table));
    errdefer if (call_args.len != 0) allocator.free(call_args);

    var blocks = try decodeBlockTable(allocator, sectionBytes(bytes, directories.items, .block_table));
    errdefer if (blocks.len != 0) allocator.free(blocks);

    var terminators = try decodeTerminatorTable(allocator, sectionBytes(bytes, directories.items, .terminator_table));
    errdefer if (terminators.len != 0) allocator.free(terminators);

    var instructions = try decodeInstructionTable(allocator, artifact_version, string_bytes, sectionBytes(bytes, directories.items, .instruction_table));
    errdefer if (instructions.len != 0) deepFreeInstructions(allocator, instructions);

    var artifact = ArtifactV1{
        .artifact_version = artifact_version,
        .semantic_ir_hash64 = ir_hash,
        .artifact_hash_blake3_256 = std.mem.zeroes([32]u8),
        .manifest_build_fingerprint = manifest_build_fingerprint,
        .build_fingerprint_blake3_256 = build_fingerprint,
        .entry_function_index = entry_index,
        .capabilities = capabilities,
        .requirement_capability_ids = decoded_requirements.capability_ids,
        .functions = functions,
        .requirements = decoded_requirements.items,
        .ops = ops,
        .outputs = outputs,
        .locals = locals,
        .call_args = call_args,
        .blocks = blocks,
        .terminators = terminators,
        .instructions = instructions,
    };
    capabilities = &.{};
    decoded_requirements = .{ .items = &.{}, .capability_ids = &.{} };
    functions = &.{};
    ops = &.{};
    outputs = &.{};
    locals = &.{};
    call_args = &.{};
    blocks = &.{};
    terminators = &.{};
    instructions = &.{};
    errdefer artifact.deinit(allocator);
    @memcpy(&artifact.artifact_hash_blake3_256, expected_hash);
    if (artifact.entry_function_index >= artifact.functions.len) return error.InvalidEntryFunctionIndex;
    try artifact.validate(allocator);
    return artifact;
}

/// Render one readable ArtifactV1 disassembly into allocator-owned text.
pub fn disasmAlloc(allocator: std.mem.Allocator, bytes: []const u8) anyerror![]u8 {
    var artifact = try decode(allocator, bytes);
    defer artifact.deinit(allocator);

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try appendFmt(&out, allocator, "ArtifactV1 ir_hash={d} entry={d}\n", .{ artifact.semantic_ir_hash64, artifact.entry_function_index });
    try appendFmt(&out, allocator, "build_fingerprint_bytes={d}\n", .{artifact.build_fingerprint_blake3_256.len});
    try appendFmt(&out, allocator, "artifact_hash_bytes={d}\n", .{artifact.artifact_hash_blake3_256.len});
    try appendFmt(&out, allocator, "capabilities={d}\n", .{artifact.capabilities.len});
    for (artifact.capabilities) |capability| {
        try appendFmt(&out, allocator, "capability id={d} kind={s} required={any} label={s}\n", .{
            capability.capability_id,
            @tagName(capability.kind),
            capability.required,
            capability.label,
        });
        for (capability.ops) |op| {
            try appendFmt(&out, allocator, "  op id={d} ordinal={d} name={s} payload={s} result={s}\n", .{
                op.op_id,
                op.plan_op_ordinal,
                hostOpKindName(op.host_op_kind),
                @tagName(op.payload_codec),
                @tagName(op.result_codec),
            });
        }
    }
    try appendFmt(&out, allocator, "functions={d} requirements={d} ops={d} outputs={d} locals={d} blocks={d} terminators={d} instructions={d}\n", .{
        artifact.functions.len,
        artifact.requirements.len,
        artifact.ops.len,
        artifact.outputs.len,
        artifact.locals.len,
        artifact.blocks.len,
        artifact.terminators.len,
        artifact.instructions.len,
    });
    return out.toOwnedSlice(allocator);
}

fn appendFmt(list: *std.ArrayList(u8), allocator: std.mem.Allocator, comptime format: []const u8, args: anytype) !void {
    const rendered = try std.fmt.allocPrint(allocator, format, args);
    defer allocator.free(rendered);
    try list.appendSlice(allocator, rendered);
}

fn validateManifest(build_fingerprint: [32]u8, capabilities: []const CapabilityV1) !void {
    var has_non_zero = false;
    for (build_fingerprint) |byte| if (byte != 0) {
        has_non_zero = true;
        break;
    };
    if (!has_non_zero) return error.NonZeroReserved;

    for (capabilities, 0..) |capability, index| {
        for (capabilities[(index + 1)..]) |other| {
            if (capability.capability_id == other.capability_id) return error.DuplicateCapabilityId;
        }
        if (capability.kind != .tool) return error.UnsupportedVersion;
        if (!capability.required) return error.InvalidRequiredSection;
        try validateToolIdV1(capability.label);
        for (capability.ops, 0..) |op, op_index| {
            if (op.capability_id != capability.capability_id) return error.DuplicateCapabilityOpId;
            if (op.plan_op_ordinal >= capability.ops.len) return error.InvalidRequiredSection;
            for (capability.ops[(op_index + 1)..]) |other_op| {
                if (op.op_id == other_op.op_id) return error.DuplicateCapabilityOpId;
                if (op.plan_op_ordinal == other_op.plan_op_ordinal and
                    op.host_op_kind == other_op.host_op_kind)
                {
                    return error.InvalidRequiredSection;
                }
            }
        }
    }
}

fn validateExecutableCodecSupport(plan: program_plan.ProgramPlan) !void {
    for (plan.functions) |function| {
        if (!executableCodecSupported(program_plan.functionResultCodec(function))) return error.UnsupportedExecutableCodec;
    }
    for (plan.ops) |op| {
        if (!executableCodecSupported(op.payload_codec)) return error.UnsupportedExecutableCodec;
        if (!executableCodecSupported(op.resume_codec)) return error.UnsupportedExecutableCodec;
    }
}

fn validateExecutableInstructionSupport(plan: program_plan.ProgramPlan) !void {
    for (plan.instructions) |instruction| switch (instruction.kind) {
        .call_nested_with, .return_error => return error.UnsupportedExecInstruction,
        .add_const_i32,
        .add_i32,
        .call_helper,
        .call_op,
        .compare_eq_zero,
        .const_i32,
        .const_string,
        .const_usize,
        .return_value,
        .sub_one,
        => {},
    };
}

fn executableCodecSupported(codec: program_plan.ValueCodec) bool {
    return switch (codec) {
        .unit, .bool, .i32, .string, .usize => true,
        .string_list => false,
    };
}

fn validateToolIdV1(tool_id: []const u8) !void {
    const slash_index = std.mem.findScalar(u8, tool_id, '/') orelse return error.InvalidToolId;
    if (slash_index == 0) return error.InvalidToolId;
    if (std.mem.findScalarPos(u8, tool_id, slash_index + 1, '/') != null) return error.InvalidToolId;

    const version_index = std.mem.findLast(u8, tool_id, "@v") orelse return error.InvalidToolId;
    if (version_index <= slash_index + 1) return error.InvalidToolId;
    if (version_index + 2 >= tool_id.len) return error.InvalidToolId;

    try validateToolIdSegment(tool_id[0..slash_index]);
    try validateToolIdSegment(tool_id[slash_index + 1 .. version_index]);

    const major = tool_id[version_index + 2 ..];
    var has_digit = false;
    var has_non_zero = false;
    for (major) |byte| {
        if (byte < '0' or byte > '9') return error.InvalidToolId;
        has_digit = true;
        if (byte != '0') has_non_zero = true;
    }
    if (!has_digit or !has_non_zero) return error.InvalidToolId;
}

fn validateToolIdSegment(segment: []const u8) !void {
    if (segment.len == 0) return error.InvalidToolId;
    for (segment) |byte| {
        const is_lower = byte >= 'a' and byte <= 'z';
        const is_digit = byte >= '0' and byte <= '9';
        const is_punct = byte == '.' or byte == '_' or byte == '-';
        if (!is_lower and !is_digit and !is_punct) return error.InvalidToolId;
    }
}

const DecodedManifest = struct {
    build_fingerprint_blake3_256: [32]u8,
    capabilities: []CapabilityV1,
};

fn decodeCapabilityManifest(
    allocator: std.mem.Allocator,
    artifact_version: u16,
    string_bytes: []const u8,
    bytes: []const u8,
) !DecodedManifest {
    if (bytes.len < 52) return error.InvalidDirectoryBounds;
    if (readU16(bytes, 0) != 1) return error.UnsupportedVersion;
    if (readU16(bytes, 2) != 0) return error.NonZeroReserved;
    var fingerprint = std.mem.zeroes([32]u8);
    @memcpy(&fingerprint, bytes[4..36]);
    const capability_count = readU16(bytes, 36);
    const op_count = readU16(bytes, 38);
    for (bytes[40..52]) |byte| if (byte != 0) return error.NonZeroReserved;

    const capability_bytes_len = @as(usize, capability_count) * 16;
    if (52 + capability_bytes_len > bytes.len) return error.InvalidDirectoryBounds;
    const capability_bytes = bytes[52 .. 52 + capability_bytes_len];
    const op_bytes = bytes[52 + capability_bytes_len ..];
    if (op_bytes.len != @as(usize, op_count) * 16) return error.InvalidDirectoryBounds;

    const capabilities = try allocator.alloc(CapabilityV1, capability_count);
    var initialized_capability_count: usize = 0;
    errdefer {
        deepFreeCapabilityPrefix(allocator, capabilities[0..initialized_capability_count]);
        allocator.free(capabilities);
    }

    var capability_cursor: usize = 0;
    for (capabilities) |*capability| {
        const capability_id = readU16(capability_bytes, capability_cursor);
        const kind = std.enums.fromInt(CapabilityKind, capability_bytes[capability_cursor + 2]) orelse return error.UnsupportedVersion;
        const flags = capability_bytes[capability_cursor + 3];
        if ((flags & ~capability_required_flag) != 0) return error.UnsupportedVersion;
        const label = try readStringRefDup(allocator, string_bytes, capability_bytes[capability_cursor + 4 .. capability_cursor + 12]);
        errdefer allocator.free(label);
        const first_op = readU16(capability_bytes, capability_cursor + 12);
        const op_count_for_capability = readU16(capability_bytes, capability_cursor + 14);
        const ops = try allocator.alloc(CapabilityOpV1, op_count_for_capability);
        errdefer allocator.free(ops);
        var initialized_op_count: usize = 0;
        var op_cursor = @as(usize, first_op) * 16;
        for (ops) |*op| {
            if (op_cursor + 16 > op_bytes.len) return error.InvalidDirectoryBounds;
            const plan_op_ordinal = readU16(op_bytes, op_cursor + 14);
            const host_op_kind = switch (artifact_version) {
                artifact_format_version_v1, artifact_format_version_v2 => blk: {
                    const global_op_name = try readStringRefDup(
                        allocator,
                        string_bytes,
                        op_bytes[op_cursor + 4 .. op_cursor + 12],
                    );
                    defer allocator.free(global_op_name);
                    break :blk try decodeLegacyCapabilityHostOpKind(global_op_name);
                },
                artifact_format_version_v3 => blk: {
                    for (op_bytes[op_cursor + 5 .. op_cursor + 12]) |byte| if (byte != 0) return error.NonZeroReserved;
                    break :blk std.enums.fromInt(HostOpKind, op_bytes[op_cursor + 4]) orelse return error.UnsupportedVersion;
                },
                else => return error.UnsupportedVersion,
            };
            op.* = .{
                .capability_id = readU16(op_bytes, op_cursor),
                .op_id = readU16(op_bytes, op_cursor + 2),
                .host_op_kind = host_op_kind,
                .payload_codec = std.enums.fromInt(CapabilityCodecV1, op_bytes[op_cursor + 12]) orelse return error.UnsupportedVersion,
                .result_codec = std.enums.fromInt(CapabilityCodecV1, op_bytes[op_cursor + 13]) orelse return error.UnsupportedVersion,
                .plan_op_ordinal = plan_op_ordinal,
            };
            initialized_op_count += 1;
            op_cursor += 16;
        }

        capability.* = .{
            .capability_id = capability_id,
            .kind = kind,
            .required = (flags & capability_required_flag) != 0,
            .label = label,
            .ops = ops,
        };
        initialized_capability_count += 1;
        capability_cursor += 16;
    }

    try validateManifest(fingerprint, capabilities);
    return .{
        .build_fingerprint_blake3_256 = fingerprint,
        .capabilities = capabilities,
    };
}

fn encodeCapabilityManifest(allocator: std.mem.Allocator, strings: *StringTable, manifest: CapabilityManifestV1) ![]u8 {
    return encodeCapabilityManifestVersioned(allocator, artifact_version_current, strings, manifest);
}

fn encodeCapabilityManifestVersioned(
    allocator: std.mem.Allocator,
    artifact_version: u16,
    strings: *StringTable,
    manifest: CapabilityManifestV1,
) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    try appendU16(&out, allocator, 1);
    try appendU16(&out, allocator, 0);
    try out.appendSlice(allocator, &manifest.build_fingerprint_blake3_256);
    try appendU16(&out, allocator, @intCast(manifest.capabilities.len));
    var total_ops: usize = 0;
    for (manifest.capabilities) |capability| total_ops += capability.ops.len;
    try appendU16(&out, allocator, @intCast(total_ops));
    try out.appendNTimes(allocator, 0, 12);

    var first_op_index: u16 = 0;
    for (manifest.capabilities) |capability| {
        const label_ref = try strings.add(capability.label);
        try appendU16(&out, allocator, capability.capability_id);
        try out.append(allocator, @intFromEnum(capability.kind));
        try out.append(allocator, if (capability.required) 1 else 0);
        try encodeStringRef(&out, allocator, label_ref);
        try appendU16(&out, allocator, first_op_index);
        try appendU16(&out, allocator, @intCast(capability.ops.len));
        first_op_index += @intCast(capability.ops.len);
    }
    for (manifest.capabilities) |capability| {
        for (capability.ops) |op| {
            try appendU16(&out, allocator, op.capability_id);
            try appendU16(&out, allocator, op.op_id);
            switch (artifact_version) {
                artifact_format_version_v1, artifact_format_version_v2 => {
                    const op_name_ref = try strings.add(capabilityGlobalNameForHostOpKind(op.host_op_kind));
                    try encodeStringRef(&out, allocator, op_name_ref);
                },
                artifact_format_version_v3 => {
                    try out.append(allocator, @intFromEnum(op.host_op_kind));
                    try out.appendNTimes(allocator, 0, 7);
                },
                else => return error.UnsupportedVersion,
            }
            try out.append(allocator, @intFromEnum(op.payload_codec));
            try out.append(allocator, @intFromEnum(op.result_codec));
            try appendU16(&out, allocator, op.plan_op_ordinal);
        }
    }
    return out.toOwnedSlice(allocator);
}

fn hashCapabilityFingerprintSectionsVersioned(
    artifact_version: u16,
    manifest_bytes: []const u8,
    string_bytes: []const u8,
) ![32]u8 {
    var hasher = std.crypto.hash.Blake3.init(.{});
    var len_bytes = std.mem.zeroes([8]u8);

    hasher.update(try capabilityFingerprintDomain(artifact_version));
    std.mem.writeInt(u64, &len_bytes, manifest_bytes.len, .little);
    hasher.update(&len_bytes);
    hasher.update(manifest_bytes);
    std.mem.writeInt(u64, &len_bytes, string_bytes.len, .little);
    hasher.update(&len_bytes);
    hasher.update(string_bytes);

    var digest = std.mem.zeroes([32]u8);
    hasher.final(&digest);
    return digest;
}

fn encodeRequirementTable(
    allocator: std.mem.Allocator,
    strings: *StringTable,
    plan: program_plan.ProgramPlan,
    capabilities: []const CapabilityV1,
) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    for (plan.requirements, 0..) |requirement, requirement_index| {
        const label_ref = try strings.add(requirement.label);
        const capability_id = try resolveRequirementCapabilityId(plan, requirement_index, capabilities);
        try encodeStringRef(&out, allocator, label_ref);
        try appendU16(&out, allocator, requirement.first_op);
        try appendU16(&out, allocator, requirement.op_count);
        try appendU16(&out, allocator, capability_id);
        try appendU16(&out, allocator, 0);
    }
    return out.toOwnedSlice(allocator);
}

fn encodeOpTable(allocator: std.mem.Allocator, strings: *StringTable, ops: []const program_plan.OpPlan) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    for (ops) |op| {
        const op_name_ref = try strings.add(op.op_name);
        try appendU16(&out, allocator, op.requirement_index);
        try out.append(allocator, @intFromEnum(op.mode));
        try out.append(allocator, @intFromEnum(op.payload_codec));
        try out.append(allocator, @intFromEnum(op.resume_codec));
        try out.append(allocator, @intFromBool(op.has_after));
        try appendU16(&out, allocator, 0);
        try encodeStringRef(&out, allocator, op_name_ref);
    }
    return out.toOwnedSlice(allocator);
}

fn encodeOutputTable(allocator: std.mem.Allocator, strings: *StringTable, outputs: []const program_plan.OutputPlan) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    for (outputs) |output| {
        const label_ref = try strings.add(output.label);
        try encodeStringRef(&out, allocator, label_ref);
        try out.append(allocator, @intFromEnum(output.codec));
        try out.appendNTimes(allocator, 0, 7);
    }
    return out.toOwnedSlice(allocator);
}

fn encodeLocalTable(allocator: std.mem.Allocator, locals: []const program_plan.LocalPlan) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    for (locals) |local| {
        try out.append(allocator, @intFromEnum(local.codec));
        try out.appendNTimes(allocator, 0, 7);
    }
    return out.toOwnedSlice(allocator);
}

fn encodeCallArgTable(allocator: std.mem.Allocator, call_args: []const u16) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    for (call_args) |call_arg| try appendU16(&out, allocator, call_arg);
    return out.toOwnedSlice(allocator);
}

fn encodeFunctionTable(allocator: std.mem.Allocator, strings: *StringTable, functions: []const program_plan.FunctionPlan) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    for (functions) |function| {
        const symbol_ref = try strings.add(function.symbol_name);
        try encodeStringRef(&out, allocator, symbol_ref);
        try out.append(allocator, @intFromEnum(function.value_codec));
        try out.append(allocator, @intFromBool(function.result_codec != null));
        try out.append(allocator, if (function.result_codec) |codec| @intFromEnum(codec) else 0);
        try out.append(allocator, 0);
        try appendU16(&out, allocator, function.parameter_count);
        try appendU16(&out, allocator, function.first_requirement);
        try appendU16(&out, allocator, function.requirement_count);
        try appendU16(&out, allocator, function.first_output);
        try appendU16(&out, allocator, function.output_count);
        try appendU16(&out, allocator, function.first_local);
        try appendU16(&out, allocator, function.local_count);
        try appendU16(&out, allocator, function.first_block);
        try appendU16(&out, allocator, function.entry_block);
        try appendU16(&out, allocator, function.block_count);
        try appendU16(&out, allocator, function.first_instruction);
        try appendU16(&out, allocator, function.instruction_count);
    }
    return out.toOwnedSlice(allocator);
}

fn encodeBlockTable(allocator: std.mem.Allocator, blocks: []const program_plan.BlockPlan) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    for (blocks) |block| {
        try appendU16(&out, allocator, block.first_instruction);
        try appendU16(&out, allocator, block.instruction_count);
        try appendU16(&out, allocator, block.terminator_index);
        try appendU16(&out, allocator, 0);
    }
    return out.toOwnedSlice(allocator);
}

fn encodeTerminatorTable(allocator: std.mem.Allocator, terminators: []const program_plan.Terminator) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    for (terminators) |terminator| {
        try out.append(allocator, @intFromEnum(terminator.kind));
        try out.append(allocator, 0);
        try appendU16(&out, allocator, terminator.primary);
        try appendU16(&out, allocator, terminator.secondary);
        try appendU16(&out, allocator, 0);
    }
    return out.toOwnedSlice(allocator);
}

fn encodeInstructionTable(
    allocator: std.mem.Allocator,
    artifact_version: u16,
    strings: *StringTable,
    plan: program_plan.ProgramPlan,
) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    for (plan.instructions) |instruction| {
        const canonical = canonicalInstruction(plan, instruction);
        const string_ref = try strings.add(canonical.string_literal);
        try out.append(allocator, encodeInstructionKind(canonical.kind, artifact_version));
        try out.append(allocator, 0);
        try appendU16(&out, allocator, canonical.dst);
        try appendU16(&out, allocator, canonical.operand);
        try appendU16(&out, allocator, canonical.aux);
        try encodeStringRef(&out, allocator, string_ref);
    }
    return out.toOwnedSlice(allocator);
}

fn canonicalInstruction(plan: program_plan.ProgramPlan, instruction: program_plan.Instruction) program_plan.Instruction {
    var canonical = instruction;
    switch (instruction.kind) {
        .add_i32 => canonical.string_literal = "",
        .add_const_i32 => canonical.string_literal = "",
        .call_helper => {
            const callee = plan.functions[instruction.operand];
            if (callee.value_codec == .unit) canonical.dst = 0;
            if (callee.parameter_count == 0) canonical.aux = 0;
            canonical.string_literal = "";
        },
        .call_nested_with => {
            const result_codec: program_plan.ValueCodec = @enumFromInt(@as(u8, @truncate(instruction.aux)));
            if (result_codec == .unit) canonical.dst = 0;
            canonical.operand = 0;
        },
        .call_op => {
            const op = plan.ops[instruction.operand];
            if (op.resume_codec == .unit) canonical.dst = 0;
            if (op.payload_codec == .unit) canonical.aux = 0;
            canonical.string_literal = "";
        },
        .compare_eq_zero => {
            canonical.aux = 0;
            canonical.string_literal = "";
        },
        .const_i32 => canonical.string_literal = "",
        .const_usize => {
            canonical.operand = 0;
            canonical.aux = 0;
        },
        .const_string => {
            canonical.operand = 0;
            canonical.aux = 0;
        },
        .return_error => {
            canonical.dst = 0;
            canonical.operand = 0;
            canonical.aux = 0;
        },
        .return_value => {
            canonical.dst = 0;
            canonical.aux = 0;
            canonical.string_literal = "";
        },
        .sub_one => {
            canonical.aux = 0;
            canonical.string_literal = "";
        },
    }
    return canonical;
}

const DecodedRequirements = struct {
    items: []program_plan.RequirementPlan,
    capability_ids: []u16,
};

fn decodeRequirementTable(allocator: std.mem.Allocator, string_bytes: []const u8, bytes: []const u8) !DecodedRequirements {
    if (bytes.len % 16 != 0) return error.InvalidDirectoryBounds;
    const items = try allocator.alloc(program_plan.RequirementPlan, bytes.len / 16);
    var initialized: usize = 0;
    errdefer deepFreeRequirementPlansPrefix(allocator, items, initialized);
    const capability_ids = try allocator.alloc(u16, items.len);
    errdefer allocator.free(capability_ids);
    var cursor: usize = 0;
    for (items, capability_ids) |*item, *capability_id| {
        const first_op = readU16(bytes, cursor + 8);
        const op_count = readU16(bytes, cursor + 10);
        capability_id.* = readU16(bytes, cursor + 12);
        if (readU16(bytes, cursor + 14) != 0) return error.NonZeroReserved;
        const label = try readStringRefDup(allocator, string_bytes, bytes[cursor .. cursor + 8]);
        item.* = .{
            .label = label,
            .first_op = first_op,
            .op_count = op_count,
        };
        initialized += 1;
        cursor += 16;
    }
    return .{
        .items = items,
        .capability_ids = capability_ids,
    };
}

fn resolveRequirementCapabilityId(plan: program_plan.ProgramPlan, requirement_index: usize, capabilities: []const CapabilityV1) !u16 {
    const requirement = plan.requirements[requirement_index];
    var wanted_ordinal: usize = 0;
    for (plan.requirements[0..requirement_index], 0..) |previous, previous_requirement_index| {
        if (previous.op_count != requirement.op_count) continue;
        if (!std.mem.eql(u8, previous.label, requirement.label)) continue;
        if (!requirementsShareCompatibleCapability(plan, previous_requirement_index, requirement_index, capabilities)) continue;
        if (requirementOpNamesMatch(plan, previous_requirement_index, requirement_index)) {
            return try resolveRequirementCapabilityId(plan, previous_requirement_index, capabilities);
        }
        wanted_ordinal += 1;
    }

    var current_ordinal: usize = 0;
    for (capabilities) |capability| {
        if (!toolCapabilityMatchesRequirement(plan, requirement_index, capability)) continue;
        if (current_ordinal == wanted_ordinal) return capability.capability_id;
        current_ordinal += 1;
    }
    return error.InvalidRequiredSection;
}

fn findCapabilityById(capabilities: []const CapabilityV1, capability_id: u16) ?CapabilityV1 {
    for (capabilities) |capability| {
        if (capability.capability_id == capability_id) return capability;
    }
    return null;
}

fn toolCapabilityMatchesRequirement(plan: program_plan.ProgramPlan, requirement_index: usize, capability: CapabilityV1) bool {
    const requirement = plan.requirements[requirement_index];
    const label_matches = std.mem.eql(u8, capability.label, requirement.label);
    if (capability.kind != .tool) return false;
    if (capability.ops.len < requirement.op_count) return false;
    if (!label_matches) {
        if (!generatedToolIdMatchesRequirementLabel(capability.label, requirement.label)) return false;
    }
    const op_start = requirement.first_op;
    const op_end = op_start + requirement.op_count;
    if (op_end > plan.ops.len) return false;
    for (plan.ops[op_start..op_end], 0..) |plan_op, op_offset| {
        const capability_op = findCapabilityOpByPlanOrdinalAndGlobalName(
            capability.ops,
            @intCast(op_offset),
            .call,
        ) orelse return false;
        if (capability_op.payload_codec != mapPlanCodecToCapabilityCodec(plan_op.payload_codec)) return false;
        const expected_result_codec = capabilityResultCodecForOp(plan, op_start + op_offset) catch return false;
        if (capability_op.result_codec != mapPlanCodecToCapabilityCodec(expected_result_codec)) return false;
        const matched_after_op = findCapabilityOpByPlanOrdinalAndGlobalName(capability.ops, @intCast(op_offset), .after_call);
        if (plan_op.has_after) {
            const after_op = matched_after_op orelse return false;
            const after_payload_codec = afterCapabilityPayloadCodecForOp(plan, @intCast(op_start + op_offset)) orelse return false;
            const after_result_codec = afterCapabilityResultCodecForOp(plan, @intCast(op_start + op_offset)) orelse return false;
            if (after_op.payload_codec != mapPlanCodecToCapabilityCodec(after_payload_codec)) return false;
            if (after_op.result_codec != mapPlanCodecToCapabilityCodec(after_result_codec)) return false;
        } else if (matched_after_op != null) {
            return false;
        }
    }
    return true;
}

fn requirementsShareCompatibleCapability(
    plan: program_plan.ProgramPlan,
    requirement_index: usize,
    other_requirement_index: usize,
    capabilities: []const CapabilityV1,
) bool {
    for (capabilities) |capability| {
        if (toolCapabilityMatchesRequirement(plan, requirement_index, capability) and
            toolCapabilityMatchesRequirement(plan, other_requirement_index, capability))
        {
            return true;
        }
    }
    return false;
}

fn validateRequirementCapabilityOpNameDisambiguation(
    plan: program_plan.ProgramPlan,
    capabilities: []const CapabilityV1,
) !void {
    for (plan.requirements, 0..) |_, requirement_index| {
        other_requirement_loop: for (plan.requirements[requirement_index + 1 ..], requirement_index + 1..) |_, other_requirement_index| {
            if (requirementOpNamesMatch(plan, requirement_index, other_requirement_index)) continue :other_requirement_loop;
            for (capabilities) |capability| {
                if (toolCapabilityMatchesRequirement(plan, requirement_index, capability) and
                    toolCapabilityMatchesRequirement(plan, other_requirement_index, capability))
                {
                    return error.InvalidRequiredSection;
                }
            }
        }
    }
}

fn requirementOpNamesMatch(plan: program_plan.ProgramPlan, requirement_index: usize, other_requirement_index: usize) bool {
    const requirement = plan.requirements[requirement_index];
    const other = plan.requirements[other_requirement_index];
    if (requirement.op_count != other.op_count) return false;
    const requirement_ops = plan.ops[requirement.first_op .. requirement.first_op + requirement.op_count];
    const other_ops = plan.ops[other.first_op .. other.first_op + other.op_count];
    for (requirement_ops, other_ops) |requirement_op, other_op| {
        if (!std.mem.eql(u8, requirement_op.op_name, other_op.op_name)) return false;
    }
    return true;
}

fn generatedToolIdMatchesRequirementLabel(tool_id: []const u8, requirement_label: []const u8) bool {
    const generated_prefix = "generated/";
    const generated_suffix = "@v1";
    if (!std.mem.startsWith(u8, tool_id, generated_prefix)) return false;
    if (!std.mem.endsWith(u8, tool_id, generated_suffix)) return false;
    const inner = tool_id[generated_prefix.len .. tool_id.len - generated_suffix.len];
    const hex = "0123456789abcdef";
    var cursor: usize = 0;
    for (requirement_label) |byte| {
        switch (byte) {
            'a'...'z', '0'...'9', '.', '-' => {
                if (cursor >= inner.len or inner[cursor] != byte) return false;
                cursor += 1;
            },
            '_' => {
                if (cursor + 1 >= inner.len) return false;
                if (inner[cursor] != '_' or inner[cursor + 1] != '_') return false;
                cursor += 2;
            },
            else => {
                if (cursor + 2 >= inner.len) return false;
                if (inner[cursor] != '_') return false;
                if (inner[cursor + 1] != hex[byte >> 4]) return false;
                if (inner[cursor + 2] != hex[byte & 0x0f]) return false;
                cursor += 3;
            },
        }
    }
    return cursor == inner.len;
}

fn findCapabilityOpByPlanOrdinalAndGlobalName(
    ops: []const CapabilityOpV1,
    plan_op_ordinal: u16,
    host_op_kind: HostOpKind,
) ?CapabilityOpV1 {
    for (ops) |op| {
        if (op.plan_op_ordinal == plan_op_ordinal and op.host_op_kind == host_op_kind) return op;
    }
    return null;
}

fn validateRequirementCapabilityMappings(
    plan: program_plan.ProgramPlan,
    capability_ids: []const u16,
    capabilities: []const CapabilityV1,
) !void {
    if (plan.requirements.len != capability_ids.len) return error.InvalidRequiredSection;
    for (capability_ids, 0..) |capability_id, requirement_index| {
        const expected_capability_id = try resolveRequirementCapabilityId(plan, requirement_index, capabilities);
        if (capability_id != expected_capability_id) return error.InvalidRequiredSection;
        const capability = findCapabilityById(capabilities, capability_id) orelse return error.InvalidRequiredSection;
        if (!toolCapabilityMatchesRequirement(plan, requirement_index, capability)) return error.InvalidRequiredSection;
        other_capability_loop: for (capability_ids[requirement_index + 1 ..], requirement_index + 1..) |other_capability_id, other_requirement_index| {
            if (capability_id != other_capability_id) continue :other_capability_loop;
            if (requirementOpNamesMatch(plan, requirement_index, other_requirement_index)) continue :other_capability_loop;
            return error.InvalidRequiredSection;
        }
    }
}

fn capabilityResultCodecForOp(plan: program_plan.ProgramPlan, op_index: usize) !program_plan.ValueCodec {
    const op = plan.ops[op_index];
    return switch (op.mode) {
        .transform => op.resume_codec,
        .choice => blk: {
            const terminal_codec = try terminalResultCodecForOp(plan, @intCast(op_index));
            if (terminal_codec != op.resume_codec) return error.InvalidRequiredSection;
            break :blk op.resume_codec;
        },
        .abort => try terminalResultCodecForOp(plan, @intCast(op_index)),
    };
}

/// Resolve the unique function answer codec that one transform/choice op would feed into an `after*` hook.
pub fn afterCapabilityResultCodecForOp(plan: program_plan.ProgramPlan, op_index: u16) ?program_plan.ValueCodec {
    if (op_index >= plan.ops.len or !plan.ops[op_index].has_after) return null;
    var resolved: ?program_plan.ValueCodec = null;
    for (plan.functions) |function| {
        const req_start: usize = function.first_requirement;
        const req_end = req_start + function.requirement_count;
        requirement_codec_loop: for (plan.requirements[req_start..req_end]) |requirement| {
            const op_start = requirement.first_op;
            const op_end = op_start + requirement.op_count;
            if (op_index < op_start or op_index >= op_end) continue :requirement_codec_loop;
            if (resolved) |codec| {
                if (codec != program_plan.functionResultCodec(function)) return null;
            } else {
                resolved = program_plan.functionResultCodec(function);
            }
        }
    }
    return resolved;
}

/// Resolve the unique function value codec that one transform/choice op would feed into an `after*` hook.
pub fn afterCapabilityPayloadCodecForOp(plan: program_plan.ProgramPlan, op_index: u16) ?program_plan.ValueCodec {
    if (op_index >= plan.ops.len or !plan.ops[op_index].has_after) return null;
    var resolved: ?program_plan.ValueCodec = null;
    for (plan.functions) |function| {
        const req_start: usize = function.first_requirement;
        const req_end = req_start + function.requirement_count;
        requirement_payload_loop: for (plan.requirements[req_start..req_end]) |requirement| {
            const op_start = requirement.first_op;
            const op_end = op_start + requirement.op_count;
            if (op_index < op_start or op_index >= op_end) continue :requirement_payload_loop;
            if (resolved) |codec| {
                if (codec != function.value_codec) return null;
            } else {
                resolved = function.value_codec;
            }
        }
    }
    return resolved;
}

/// Resolve the terminal result codec for one abort/choice op and reject conflicting owners.
pub fn terminalResultCodecForOp(plan: program_plan.ProgramPlan, op_index: u16) !program_plan.ValueCodec {
    var resolved: ?program_plan.ValueCodec = null;
    for (plan.functions) |function| {
        const req_start: usize = function.first_requirement;
        const req_end = req_start + function.requirement_count;
        requirement_result_loop: for (plan.requirements[req_start..req_end]) |requirement| {
            const op_start = requirement.first_op;
            const op_end = op_start + requirement.op_count;
            if (op_index < op_start or op_index >= op_end) continue :requirement_result_loop;
            if (resolved) |codec| {
                if (codec != program_plan.functionResultCodec(function)) return error.InvalidRequiredSection;
            } else {
                resolved = program_plan.functionResultCodec(function);
            }
        }
    }
    return resolved orelse error.InvalidRequiredSection;
}

fn decodeOpTable(allocator: std.mem.Allocator, string_bytes: []const u8, bytes: []const u8) ![]program_plan.OpPlan {
    if (bytes.len % 16 != 0) return error.InvalidDirectoryBounds;
    const items = try allocator.alloc(program_plan.OpPlan, bytes.len / 16);
    var initialized: usize = 0;
    errdefer deepFreeOpPlansPrefix(allocator, items, initialized);
    var cursor: usize = 0;
    for (items) |*item| {
        const requirement_index = readU16(bytes, cursor);
        const mode = std.enums.fromInt(program_plan.ControlMode, bytes[cursor + 2]) orelse return error.UnsupportedVersion;
        const payload_codec = std.enums.fromInt(program_plan.ValueCodec, bytes[cursor + 3]) orelse return error.UnsupportedVersion;
        const resume_codec = std.enums.fromInt(program_plan.ValueCodec, bytes[cursor + 4]) orelse return error.UnsupportedVersion;
        const flags = bytes[cursor + 5];
        if ((flags & ~@as(u8, 0x1)) != 0 or readU16(bytes, cursor + 6) != 0) return error.NonZeroReserved;
        item.* = .{
            .requirement_index = requirement_index,
            .op_name = try readStringRefDup(allocator, string_bytes, bytes[cursor + 8 .. cursor + 16]),
            .mode = mode,
            .payload_codec = payload_codec,
            .resume_codec = resume_codec,
            .has_after = (flags & 0x1) != 0,
        };
        initialized += 1;
        cursor += 16;
    }
    return items;
}

fn decodeOutputTable(allocator: std.mem.Allocator, string_bytes: []const u8, bytes: []const u8) ![]program_plan.OutputPlan {
    if (bytes.len % 16 != 0) return error.InvalidDirectoryBounds;
    const items = try allocator.alloc(program_plan.OutputPlan, bytes.len / 16);
    var initialized: usize = 0;
    errdefer deepFreeOutputPlansPrefix(allocator, items, initialized);
    var cursor: usize = 0;
    for (items) |*item| {
        const codec = std.enums.fromInt(program_plan.ValueCodec, bytes[cursor + 8]) orelse return error.UnsupportedVersion;
        for (bytes[cursor + 9 .. cursor + 16]) |byte| if (byte != 0) return error.NonZeroReserved;
        item.* = .{
            .label = try readStringRefDup(allocator, string_bytes, bytes[cursor .. cursor + 8]),
            .codec = codec,
        };
        initialized += 1;
        cursor += 16;
    }
    return items;
}

fn decodeLocalTable(allocator: std.mem.Allocator, bytes: []const u8) ![]program_plan.LocalPlan {
    if (bytes.len % 8 != 0) return error.InvalidDirectoryBounds;
    const items = try allocator.alloc(program_plan.LocalPlan, bytes.len / 8);
    errdefer allocator.free(items);
    var cursor: usize = 0;
    for (items) |*item| {
        item.* = .{
            .codec = std.enums.fromInt(program_plan.ValueCodec, bytes[cursor]) orelse return error.UnsupportedVersion,
        };
        for (bytes[cursor + 1 .. cursor + 8]) |byte| if (byte != 0) return error.NonZeroReserved;
        cursor += 8;
    }
    return items;
}

fn decodeCallArgTable(allocator: std.mem.Allocator, bytes: []const u8) ![]u16 {
    if (bytes.len % 2 != 0) return error.InvalidDirectoryBounds;
    const items = try allocator.alloc(u16, bytes.len / 2);
    errdefer allocator.free(items);
    var cursor: usize = 0;
    for (items) |*item| {
        item.* = readU16(bytes, cursor);
        cursor += 2;
    }
    return items;
}

fn decodeFunctionTable(
    allocator: std.mem.Allocator,
    artifact_version: u16,
    string_bytes: []const u8,
    bytes: []const u8,
) ![]program_plan.FunctionPlan {
    if (bytes.len % 36 != 0) return error.InvalidDirectoryBounds;
    const items = try allocator.alloc(program_plan.FunctionPlan, bytes.len / 36);
    var initialized: usize = 0;
    errdefer deepFreeFunctionPlansPrefix(allocator, items, initialized);
    var cursor: usize = 0;
    for (items) |*item| {
        const value_codec = std.enums.fromInt(program_plan.ValueCodec, bytes[cursor + 8]) orelse return error.UnsupportedVersion;
        const result_codec = switch (artifact_version) {
            artifact_format_version_v1 => blk: {
                for (bytes[cursor + 9 .. cursor + 12]) |byte| if (byte != 0) return error.NonZeroReserved;
                break :blk null;
            },
            artifact_format_version_v2, artifact_format_version_v3 => blk: {
                const has_result_codec = switch (bytes[cursor + 9]) {
                    0 => false,
                    1 => true,
                    else => return error.NonZeroReserved,
                };
                const decoded_result_codec = if (has_result_codec)
                    std.enums.fromInt(program_plan.ValueCodec, bytes[cursor + 10]) orelse return error.UnsupportedVersion
                else
                    null;
                if (bytes[cursor + 11] != 0) return error.NonZeroReserved;
                break :blk decoded_result_codec;
            },
            else => return error.UnsupportedVersion,
        };
        item.* = .{
            .symbol_name = try readStringRefDup(allocator, string_bytes, bytes[cursor .. cursor + 8]),
            .value_codec = value_codec,
            .result_codec = result_codec,
            .parameter_count = readU16(bytes, cursor + 12),
            .first_requirement = readU16(bytes, cursor + 14),
            .requirement_count = readU16(bytes, cursor + 16),
            .first_output = readU16(bytes, cursor + 18),
            .output_count = readU16(bytes, cursor + 20),
            .first_local = readU16(bytes, cursor + 22),
            .local_count = readU16(bytes, cursor + 24),
            .first_block = readU16(bytes, cursor + 26),
            .entry_block = readU16(bytes, cursor + 28),
            .block_count = readU16(bytes, cursor + 30),
            .first_instruction = readU16(bytes, cursor + 32),
            .instruction_count = readU16(bytes, cursor + 34),
        };
        initialized += 1;
        cursor += 36;
    }
    return items;
}

fn decodeBlockTable(allocator: std.mem.Allocator, bytes: []const u8) ![]program_plan.BlockPlan {
    if (bytes.len % 8 != 0) return error.InvalidDirectoryBounds;
    const items = try allocator.alloc(program_plan.BlockPlan, bytes.len / 8);
    errdefer allocator.free(items);
    var cursor: usize = 0;
    for (items) |*item| {
        item.* = .{
            .first_instruction = readU16(bytes, cursor),
            .instruction_count = readU16(bytes, cursor + 2),
            .terminator_index = readU16(bytes, cursor + 4),
        };
        if (readU16(bytes, cursor + 6) != 0) return error.NonZeroReserved;
        cursor += 8;
    }
    return items;
}

fn decodeTerminatorTable(allocator: std.mem.Allocator, bytes: []const u8) ![]program_plan.Terminator {
    if (bytes.len % 8 != 0) return error.InvalidDirectoryBounds;
    const items = try allocator.alloc(program_plan.Terminator, bytes.len / 8);
    errdefer allocator.free(items);
    var cursor: usize = 0;
    for (items) |*item| {
        item.* = .{
            .kind = std.enums.fromInt(program_plan.TerminatorKind, bytes[cursor]) orelse return error.UnsupportedVersion,
            .primary = readU16(bytes, cursor + 2),
            .secondary = readU16(bytes, cursor + 4),
        };
        if (bytes[cursor + 1] != 0) return error.NonZeroReserved;
        if (readU16(bytes, cursor + 6) != 0) return error.NonZeroReserved;
        cursor += 8;
    }
    return items;
}

fn decodeInstructionKind(raw_kind: u8, artifact_version: u16) !program_plan.InstructionKind {
    return switch (artifact_version) {
        artifact_format_version_v1 => switch (raw_kind) {
            0 => .add_const_i32,
            1 => .call_helper,
            2 => .call_op,
            3 => .compare_eq_zero,
            4 => .const_i32,
            5 => .const_string,
            6 => .return_value,
            7 => .sub_one,
            else => error.UnsupportedVersion,
        },
        artifact_format_version_v2, artifact_format_version_v3 => switch (raw_kind) {
            0 => .add_const_i32,
            1 => .add_i32,
            2 => .call_helper,
            3 => .call_op,
            4 => .compare_eq_zero,
            5 => .const_i32,
            6 => .const_string,
            7 => .const_usize,
            8 => .return_value,
            9 => .sub_one,
            10 => .call_nested_with,
            11 => .return_error,
            else => error.UnsupportedVersion,
        },
        else => error.UnsupportedVersion,
    };
}

fn encodeInstructionKind(kind: program_plan.InstructionKind, artifact_version: u16) u8 {
    return switch (artifact_version) {
        artifact_format_version_v2, artifact_format_version_v3 => switch (kind) {
            .add_const_i32 => 0,
            .add_i32 => 1,
            .call_helper => 2,
            .call_op => 3,
            .compare_eq_zero => 4,
            .const_i32 => 5,
            .const_string => 6,
            .const_usize => 7,
            .return_value => 8,
            .sub_one => 9,
            .call_nested_with => 10,
            .return_error => 11,
        },
        artifact_format_version_v1 => switch (kind) {
            .add_const_i32 => 0,
            .call_helper => 1,
            .call_op => 2,
            .compare_eq_zero => 3,
            .const_i32 => 4,
            .const_string => 5,
            .return_value => 6,
            .sub_one => 7,
            .add_i32, .const_usize, .call_nested_with, .return_error => unreachable,
        },
        else => unreachable,
    };
}

fn decodeInstructionTable(
    allocator: std.mem.Allocator,
    artifact_version: u16,
    string_bytes: []const u8,
    bytes: []const u8,
) ![]program_plan.Instruction {
    if (bytes.len % 16 != 0) return error.InvalidDirectoryBounds;
    const items = try allocator.alloc(program_plan.Instruction, bytes.len / 16);
    var initialized: usize = 0;
    errdefer deepFreeInstructionsPrefix(allocator, items, initialized);
    var cursor: usize = 0;
    for (items) |*item| {
        const kind = try decodeInstructionKind(bytes[cursor], artifact_version);
        if (bytes[cursor + 1] != 0) return error.NonZeroReserved;
        item.* = .{
            .kind = kind,
            .dst = readU16(bytes, cursor + 2),
            .operand = readU16(bytes, cursor + 4),
            .aux = readU16(bytes, cursor + 6),
            .string_literal = try readStringRefDup(allocator, string_bytes, bytes[cursor + 8 .. cursor + 16]),
        };
        initialized += 1;
        cursor += 16;
    }
    return items;
}

fn appendU16(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u16) !void {
    var buffer: [2]u8 = undefined;
    std.mem.writeInt(u16, &buffer, value, .little);
    try list.appendSlice(allocator, &buffer);
}

fn appendU32(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    var buffer: [4]u8 = undefined;
    std.mem.writeInt(u32, &buffer, value, .little);
    try list.appendSlice(allocator, &buffer);
}

fn appendU64(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u64) !void {
    var buffer: [8]u8 = undefined;
    std.mem.writeInt(u64, &buffer, value, .little);
    try list.appendSlice(allocator, &buffer);
}

fn readU16(bytes: []const u8, offset: usize) u16 {
    return std.mem.readInt(u16, bytes[offset..][0..2], .little);
}

fn readU32(bytes: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, bytes[offset..][0..4], .little);
}

fn readU64(bytes: []const u8, offset: usize) u64 {
    return std.mem.readInt(u64, bytes[offset..][0..8], .little);
}

fn checkedSectionEnd(offset: u64, size: anytype) ?u64 {
    const size_u64: u64 = @intCast(size);
    return std.math.add(u64, offset, size_u64) catch null;
}

fn encodeDirectoryEntry(list: *std.ArrayList(u8), allocator: std.mem.Allocator, directory: SectionDirectoryEntryV1) !void {
    try appendU16(list, allocator, @intFromEnum(directory.section_id));
    try appendU16(list, allocator, directory.flags);
    try appendU32(list, allocator, 0);
    try appendU64(list, allocator, directory.offset);
    try appendU64(list, allocator, directory.size);
    try appendU32(list, allocator, directory.entry_count);
    try appendU32(list, allocator, 0);
}

fn encodeStringRef(list: *std.ArrayList(u8), allocator: std.mem.Allocator, string_ref: StringRef) !void {
    try appendU32(list, allocator, string_ref.offset);
    try appendU32(list, allocator, string_ref.len);
}

fn readStringRefDup(allocator: std.mem.Allocator, string_bytes: []const u8, bytes: []const u8) ![]const u8 {
    const offset = readU32(bytes, 0);
    const len = readU32(bytes, 4);
    const start = std.math.cast(usize, offset) orelse return error.StringRefOutOfBounds;
    const end = checkedStringRefEnd(offset, len) orelse return error.StringRefOutOfBounds;
    if (end > string_bytes.len) return error.StringRefOutOfBounds;
    return allocator.dupe(u8, string_bytes[start..end]);
}

fn checkedStringRefEnd(offset: u32, len: u32) ?usize {
    const end = std.math.add(u32, offset, len) catch return null;
    return std.math.cast(usize, end);
}

fn sectionBytes(bytes: []const u8, directories: []const SectionDirectoryEntryV1, wanted: SectionId) []const u8 {
    for (directories) |directory| {
        if (directory.section_id == wanted) {
            return bytes[@intCast(directory.offset)..][0..@intCast(directory.size)];
        }
    }
    unreachable;
}

const StringTable = struct {
    allocator: std.mem.Allocator,
    bytes: std.ArrayList(u8),
    items: std.ArrayList(StringRef),

    fn init(allocator: std.mem.Allocator) StringTable {
        return .{
            .allocator = allocator,
            .bytes = .empty,
            .items = .empty,
        };
    }

    fn deinit(self: *StringTable) void {
        self.bytes.deinit(self.allocator);
        self.items.deinit(self.allocator);
    }

    fn add(self: *StringTable, value: []const u8) !StringRef {
        for (self.items.items) |existing| {
            const existing_bytes = self.bytes.items[existing.offset..][0..existing.len];
            if (std.mem.eql(u8, existing_bytes, value)) return existing;
        }
        const offset = self.bytes.items.len;
        try self.bytes.appendSlice(self.allocator, value);
        const string_ref = StringRef{
            .offset = @intCast(offset),
            .len = @intCast(value.len),
        };
        try self.items.append(self.allocator, string_ref);
        return string_ref;
    }

    fn toOwnedBytes(self: *StringTable, allocator: std.mem.Allocator) ![]u8 {
        return allocator.dupe(u8, self.bytes.items);
    }
};

fn deepCloneFunctionPlans(allocator: std.mem.Allocator, source: []const program_plan.FunctionPlan) ![]program_plan.FunctionPlan {
    const clone = try allocator.alloc(program_plan.FunctionPlan, source.len);
    var initialized: usize = 0;
    errdefer deepFreeFunctionPlansPrefix(allocator, clone, initialized);
    for (source, 0..) |item, index| {
        clone[index] = item;
        clone[index].symbol_name = try allocator.dupe(u8, item.symbol_name);
        initialized = index + 1;
    }
    return clone;
}

fn deepCloneRequirementPlans(allocator: std.mem.Allocator, source: []const program_plan.RequirementPlan) ![]program_plan.RequirementPlan {
    const clone = try allocator.alloc(program_plan.RequirementPlan, source.len);
    var initialized: usize = 0;
    errdefer deepFreeRequirementPlansPrefix(allocator, clone, initialized);
    for (source, 0..) |item, index| {
        clone[index] = item;
        clone[index].label = try allocator.dupe(u8, item.label);
        initialized = index + 1;
    }
    return clone;
}

fn deepCloneOpPlans(allocator: std.mem.Allocator, source: []const program_plan.OpPlan) ![]program_plan.OpPlan {
    const clone = try allocator.alloc(program_plan.OpPlan, source.len);
    var initialized: usize = 0;
    errdefer deepFreeOpPlansPrefix(allocator, clone, initialized);
    for (source, 0..) |item, index| {
        clone[index] = item;
        clone[index].op_name = try allocator.dupe(u8, item.op_name);
        initialized = index + 1;
    }
    return clone;
}

fn deepCloneOutputPlans(allocator: std.mem.Allocator, source: []const program_plan.OutputPlan) ![]program_plan.OutputPlan {
    const clone = try allocator.alloc(program_plan.OutputPlan, source.len);
    var initialized: usize = 0;
    errdefer deepFreeOutputPlansPrefix(allocator, clone, initialized);
    for (source, 0..) |item, index| {
        clone[index] = item;
        clone[index].label = try allocator.dupe(u8, item.label);
        initialized = index + 1;
    }
    return clone;
}

fn deepCloneInstructions(allocator: std.mem.Allocator, source: []const program_plan.Instruction) ![]program_plan.Instruction {
    const clone = try allocator.alloc(program_plan.Instruction, source.len);
    var initialized: usize = 0;
    errdefer deepFreeInstructionsPrefix(allocator, clone, initialized);
    for (source, 0..) |item, index| {
        clone[index] = item;
        clone[index].string_literal = try allocator.dupe(u8, item.string_literal);
        initialized = index + 1;
    }
    return clone;
}

fn deepFreeCapabilityOpsPrefix(allocator: std.mem.Allocator, items: []const CapabilityOpV1, initialized: usize) void {
    _ = initialized;
    allocator.free(@constCast(items));
}

fn deepFreeCapabilitiesPrefix(allocator: std.mem.Allocator, items: []CapabilityV1, initialized: usize) void {
    for (items[0..initialized]) |item| {
        allocator.free(item.label);
        deepFreeCapabilityOpsPrefix(allocator, item.ops, item.ops.len);
    }
    allocator.free(items);
}

fn deepFreeFunctionPlansPrefix(allocator: std.mem.Allocator, items: []program_plan.FunctionPlan, initialized: usize) void {
    for (items[0..initialized]) |item| allocator.free(item.symbol_name);
    allocator.free(items);
}

fn deepFreeRequirementPlansPrefix(allocator: std.mem.Allocator, items: []program_plan.RequirementPlan, initialized: usize) void {
    for (items[0..initialized]) |item| allocator.free(item.label);
    allocator.free(items);
}

fn deepFreeOpPlansPrefix(allocator: std.mem.Allocator, items: []program_plan.OpPlan, initialized: usize) void {
    for (items[0..initialized]) |item| allocator.free(item.op_name);
    allocator.free(items);
}

fn deepFreeOutputPlansPrefix(allocator: std.mem.Allocator, items: []program_plan.OutputPlan, initialized: usize) void {
    for (items[0..initialized]) |item| allocator.free(item.label);
    allocator.free(items);
}

fn deepFreeInstructionsPrefix(allocator: std.mem.Allocator, items: []program_plan.Instruction, initialized: usize) void {
    for (items[0..initialized]) |item| allocator.free(item.string_literal);
    allocator.free(items);
}

fn deepFreeFunctionPlans(allocator: std.mem.Allocator, items: []program_plan.FunctionPlan) void {
    deepFreeFunctionPlansPrefix(allocator, items, items.len);
}

fn deepFreeRequirementPlans(allocator: std.mem.Allocator, items: []program_plan.RequirementPlan) void {
    deepFreeRequirementPlansPrefix(allocator, items, items.len);
}

fn deepFreeOpPlans(allocator: std.mem.Allocator, items: []program_plan.OpPlan) void {
    deepFreeOpPlansPrefix(allocator, items, items.len);
}

fn deepFreeOutputPlans(allocator: std.mem.Allocator, items: []program_plan.OutputPlan) void {
    deepFreeOutputPlansPrefix(allocator, items, items.len);
}

fn deepFreeInstructions(allocator: std.mem.Allocator, items: []program_plan.Instruction) void {
    deepFreeInstructionsPrefix(allocator, items, items.len);
}

fn deepFreeFunctionPlansConst(allocator: std.mem.Allocator, items: []const program_plan.FunctionPlan) void {
    deepFreeFunctionPlansPrefix(allocator, @constCast(items), items.len);
}

fn deepFreeRequirementPlansConst(allocator: std.mem.Allocator, items: []const program_plan.RequirementPlan) void {
    deepFreeRequirementPlansPrefix(allocator, @constCast(items), items.len);
}

fn deepFreeOpPlansConst(allocator: std.mem.Allocator, items: []const program_plan.OpPlan) void {
    deepFreeOpPlansPrefix(allocator, @constCast(items), items.len);
}

fn deepFreeOutputPlansConst(allocator: std.mem.Allocator, items: []const program_plan.OutputPlan) void {
    deepFreeOutputPlansPrefix(allocator, @constCast(items), items.len);
}

fn deepFreeInstructionsConst(allocator: std.mem.Allocator, items: []const program_plan.Instruction) void {
    deepFreeInstructionsPrefix(allocator, @constCast(items), items.len);
}

fn deepFreeProgramPlan(allocator: std.mem.Allocator, plan: program_plan.ProgramPlan) void {
    allocator.free(plan.label);
    deepFreeFunctionPlansConst(allocator, plan.functions);
    deepFreeRequirementPlansConst(allocator, plan.requirements);
    deepFreeOpPlansConst(allocator, plan.ops);
    deepFreeOutputPlansConst(allocator, plan.outputs);
    allocator.free(@constCast(plan.locals));
    allocator.free(@constCast(plan.call_args));
    allocator.free(@constCast(plan.blocks));
    allocator.free(@constCast(plan.terminators));
    deepFreeInstructionsConst(allocator, plan.instructions);
}

/// Release allocator-owned capability manifests produced by ArtifactV1 helpers.
pub fn deepFreeCapabilities(allocator: std.mem.Allocator, items: []CapabilityV1) void {
    deepFreeCapabilitiesPrefix(allocator, items, items.len);
}

fn deepFreeCapabilityPrefix(allocator: std.mem.Allocator, items: []CapabilityV1) void {
    for (items) |item| {
        allocator.free(item.label);
        allocator.free(item.ops);
    }
}

fn recomputeEncodedArtifactHash(bytes: []u8) void {
    @memset(bytes[40..72], 0);
    var digest = std.mem.zeroes([32]u8);
    std.crypto.hash.Blake3.hash(bytes, &digest, .{});
    @memcpy(bytes[40..72], &digest);
}

fn swapDirectoryEntries(bytes: []u8, first_index: usize, second_index: usize) void {
    const directory_offset: usize = 72;
    const entry_len: usize = 32;
    const first_start = directory_offset + first_index * entry_len;
    const second_start = directory_offset + second_index * entry_len;
    var tmp = std.mem.zeroes([entry_len]u8);
    @memcpy(&tmp, bytes[first_start .. first_start + entry_len]);
    @memcpy(bytes[first_start .. first_start + entry_len], bytes[second_start .. second_start + entry_len]);
    @memcpy(bytes[second_start .. second_start + entry_len], &tmp);
    recomputeEncodedArtifactHash(bytes);
}

fn swapCapabilityManifestEntries(bytes: []u8, first_index: usize, second_index: usize) void {
    const capability_manifest_offset = sectionPayloadOffset(bytes, .capability_manifest);
    const entry_len: usize = 16;
    const capability_table_offset = capability_manifest_offset + 52;
    const first_start = capability_table_offset + first_index * entry_len;
    const second_start = capability_table_offset + second_index * entry_len;
    var tmp = std.mem.zeroes([entry_len]u8);
    @memcpy(&tmp, bytes[first_start .. first_start + entry_len]);
    @memcpy(bytes[first_start .. first_start + entry_len], bytes[second_start .. second_start + entry_len]);
    @memcpy(bytes[second_start .. second_start + entry_len], &tmp);
    recomputeEncodedArtifactHash(bytes);
}

fn patchEntryParameterCount(bytes: []u8, parameter_count: u16) void {
    const directory_offset: usize = 72;
    const directory_count = readU16(bytes, 20);
    var cursor: usize = directory_offset;
    while (cursor < directory_offset + @as(usize, directory_count) * 32) : (cursor += 32) {
        if (readU16(bytes, cursor) != @intFromEnum(SectionId.function_table)) continue;
        const function_table_offset: usize = @intCast(readU64(bytes, cursor + 8));
        std.mem.writeInt(u16, bytes[function_table_offset + 12 ..][0..2], parameter_count, .little);
        recomputeEncodedArtifactHash(bytes);
        return;
    }
    unreachable;
}

fn patchFunctionValueCodec(bytes: []u8, function_index: usize, codec: program_plan.ValueCodec) void {
    const directory_offset: usize = 72;
    const directory_count = readU16(bytes, 20);
    var cursor: usize = directory_offset;
    while (cursor < directory_offset + @as(usize, directory_count) * 32) : (cursor += 32) {
        if (readU16(bytes, cursor) != @intFromEnum(SectionId.function_table)) continue;
        const function_table_offset: usize = @intCast(readU64(bytes, cursor + 8));
        const entry_offset = function_table_offset + function_index * 36;
        bytes[entry_offset + 8] = @intFromEnum(codec);
        recomputeEncodedArtifactHash(bytes);
        return;
    }
    unreachable;
}

fn patchDirectoryEntryBounds(bytes: []u8, section_id: SectionId, offset: u64, size: u64) void {
    const directory_offset: usize = 72;
    const directory_count = readU16(bytes, 20);
    var cursor: usize = directory_offset;
    while (cursor < directory_offset + @as(usize, directory_count) * 32) : (cursor += 32) {
        if (readU16(bytes, cursor) != @intFromEnum(section_id)) continue;
        std.mem.writeInt(u64, bytes[cursor + 8 ..][0..8], offset, .little);
        std.mem.writeInt(u64, bytes[cursor + 16 ..][0..8], size, .little);
        recomputeEncodedArtifactHash(bytes);
        return;
    }
    unreachable;
}

fn sectionPayloadOffset(bytes: []const u8, section_id: SectionId) usize {
    const directory_offset: usize = 72;
    const directory_count = readU16(bytes, 20);
    var cursor: usize = directory_offset;
    while (cursor < directory_offset + @as(usize, directory_count) * 32) : (cursor += 32) {
        if (readU16(bytes, cursor) != @intFromEnum(section_id)) continue;
        return @intCast(readU64(bytes, cursor + 8));
    }
    unreachable;
}

fn patchCapabilityManifestPlanOrdinal(bytes: []u8, capability_op_index: usize, ordinal: u16) void {
    const capability_manifest_offset = sectionPayloadOffset(bytes, .capability_manifest);
    const capability_count = readU16(bytes, capability_manifest_offset + 36);
    const op_table_offset = capability_manifest_offset + 52 + @as(usize, capability_count) * 16;
    const op_offset = op_table_offset + capability_op_index * 16;
    std.mem.writeInt(u16, bytes[op_offset + 14 ..][0..2], ordinal, .little);
    recomputeEncodedArtifactHash(bytes);
}

fn patchRequirementCapabilityId(bytes: []u8, requirement_index: usize, capability_id: u16) void {
    const requirement_table_offset = sectionPayloadOffset(bytes, .requirement_table);
    const row_offset = requirement_table_offset + requirement_index * 16;
    std.mem.writeInt(u16, bytes[row_offset + 12 ..][0..2], capability_id, .little);
    recomputeEncodedArtifactHash(bytes);
}

fn patchCapabilityFlags(bytes: []u8, capability_index: usize, flags: u8) void {
    const capability_manifest_offset = sectionPayloadOffset(bytes, .capability_manifest);
    const capability_offset = capability_manifest_offset + 52 + capability_index * 16;
    bytes[capability_offset + 3] = flags;
    recomputeEncodedArtifactHash(bytes);
}

fn patchArtifactVersion(bytes: []u8, version: u16) void {
    std.mem.writeInt(u16, bytes[10..][0..2], version, .little);
    recomputeEncodedArtifactHash(bytes);
}

fn patchSectionReservedByte(bytes: []u8, section_id: SectionId, row_index: usize, byte_offset: usize, value: u8) void {
    const entry_len: usize = blk: {
        if (section_id == .function_table) break :blk 36;
        if (section_id == .requirement_table or
            section_id == .op_table or
            section_id == .output_table or
            section_id == .instruction_table)
        {
            break :blk 16;
        }
        unreachable;
    };
    const section_offset = sectionPayloadOffset(bytes, section_id);
    const row_offset = section_offset + row_index * entry_len;
    bytes[row_offset + byte_offset] = value;
    recomputeEncodedArtifactHash(bytes);
}

fn patchInstructionKind(bytes: []u8, row_index: usize, kind: u8) void {
    const instruction_table_offset = sectionPayloadOffset(bytes, .instruction_table);
    bytes[instruction_table_offset + row_index * 16] = kind;
    recomputeEncodedArtifactHash(bytes);
}

fn patchInstructionStringRefFromRow(bytes: []u8, target_row_index: usize, source_row_index: usize) void {
    const instruction_table_offset = sectionPayloadOffset(bytes, .instruction_table);
    const target_offset = instruction_table_offset + target_row_index * 16;
    const source_offset = instruction_table_offset + source_row_index * 16;
    @memcpy(bytes[target_offset + 8 .. target_offset + 16], bytes[source_offset + 8 .. source_offset + 16]);
    recomputeEncodedArtifactHash(bytes);
}

fn patchTerminatorKind(bytes: []u8, row_index: usize, kind: program_plan.TerminatorKind) void {
    const terminator_table_offset = sectionPayloadOffset(bytes, .terminator_table);
    bytes[terminator_table_offset + row_index * 8] = @intFromEnum(kind);
    recomputeEncodedArtifactHash(bytes);
}

const RawDirectoryEntryPatch = struct {
    raw_section_id: u16,
    flags: u16,
    entry_count: u32,
    payload: []const u8,
};

fn appendRawDirectoryEntry(allocator: std.mem.Allocator, bytes: []const u8, patch: RawDirectoryEntryPatch) ![]u8 {
    const directory_offset: usize = @intCast(readU64(bytes, 12));
    const directory_count = readU16(bytes, 20);
    const old_directory_len = @as(usize, directory_count) * 32;
    const old_directory_end = directory_offset + old_directory_len;
    if (directory_count != 0) {
        const last_section_id = readU16(bytes, old_directory_end - 32);
        std.debug.assert(patch.raw_section_id > last_section_id);
    }

    const directory_shift: usize = 32;
    var updated = try allocator.alloc(u8, bytes.len + directory_shift + patch.payload.len);
    errdefer allocator.free(updated);

    @memcpy(updated[0..old_directory_end], bytes[0..old_directory_end]);
    @memcpy(
        updated[old_directory_end + directory_shift .. old_directory_end + directory_shift + (bytes.len - old_directory_end)],
        bytes[old_directory_end..],
    );
    @memcpy(updated[bytes.len + directory_shift ..], patch.payload);

    std.mem.writeInt(u16, updated[20..][0..2], directory_count + 1, .little);

    var cursor: usize = directory_offset;
    while (cursor < old_directory_end) : (cursor += 32) {
        const offset = readU64(updated, cursor + 8);
        std.mem.writeInt(u64, updated[cursor + 8 ..][0..8], offset + directory_shift, .little);
    }

    const new_entry_offset = old_directory_end;
    std.mem.writeInt(u16, updated[new_entry_offset..][0..2], patch.raw_section_id, .little);
    std.mem.writeInt(u16, updated[new_entry_offset + 2 ..][0..2], patch.flags, .little);
    std.mem.writeInt(u32, updated[new_entry_offset + 4 ..][0..4], 0, .little);
    std.mem.writeInt(u64, updated[new_entry_offset + 8 ..][0..8], bytes.len + directory_shift, .little);
    std.mem.writeInt(u64, updated[new_entry_offset + 16 ..][0..8], patch.payload.len, .little);
    std.mem.writeInt(u32, updated[new_entry_offset + 24 ..][0..4], patch.entry_count, .little);
    std.mem.writeInt(u32, updated[new_entry_offset + 28 ..][0..4], 0, .little);

    recomputeEncodedArtifactHash(updated);
    return updated;
}

test "ArtifactV1 encode/decode preserves plan structure and capability manifest" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-v1-test");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.test",
        .ir_hash = 0x44,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .i32,
            .result_codec = .string,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 1,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "search", .mode = .transform, .payload_codec = .string, .resume_codec = .string }},
        .outputs = &.{.{ .label = "result", .codec = .i32 }},
        .locals = &.{.{ .codec = .i32 }},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{.{ .kind = .return_value, .operand = 0 }},
    };
    const capabilities = [_]CapabilityV1{.{
        .capability_id = 1,
        .kind = .tool,
        .label = "generated/tooling@v1",
        .ops = &.{.{
            .capability_id = 1,
            .op_id = 0,
            .host_op_kind = .call,
            .payload_codec = .string,
            .result_codec = .string,
            .plan_op_ordinal = 0,
        }},
    }};

    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &capabilities,
    });
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqual(artifact_version_current, readU16(encoded, 10));

    var decoded = try decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u64, plan.ir_hash), decoded.semantic_ir_hash64);
    try std.testing.expectEqual(@as(usize, 1), decoded.capabilities.len);
    try std.testing.expectEqualStrings("generated/tooling@v1", decoded.capabilities[0].label);
    try std.testing.expectEqual(.call, decoded.capabilities[0].ops[0].host_op_kind);
    try std.testing.expectEqual(@as(u16, 0), decoded.capabilities[0].ops[0].plan_op_ordinal);
    try std.testing.expectEqual(@as(usize, 1), decoded.functions.len);
    try std.testing.expectEqualStrings("entry", decoded.functions[0].symbol_name);
    try std.testing.expectEqual(program_plan.ValueCodec.string, decoded.functions[0].result_codec.?);
    try std.testing.expectEqual(@as(usize, 1), decoded.instructions.len);
}

test "ArtifactV1 decode preserves legacy v1 artifact versions" {
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.legacy_v1_instruction_tags",
        .ir_hash = 0x45,
        .entry_index = 0,
        .functions = &.{
            .{
                .symbol_name = "entry",
                .value_codec = .string,
                .parameter_count = 0,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 1,
                .first_block = 0,
                .entry_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 2,
            },
            .{
                .symbol_name = "helper",
                .value_codec = .string,
                .parameter_count = 0,
                .first_requirement = 0,
                .requirement_count = 0,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 1,
                .first_block = 1,
                .entry_block = 1,
                .block_count = 1,
                .first_instruction = 2,
                .instruction_count = 2,
            },
        },
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{
            .{ .codec = .string },
            .{ .codec = .string },
        },
        .call_args = &.{},
        .blocks = &.{
            .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
            .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
        },
        .terminators = &.{
            .{ .kind = .return_value },
            .{ .kind = .return_value },
        },
        .instructions = &.{
            .{ .kind = .call_helper, .dst = 0, .operand = 1 },
            .{ .kind = .return_value, .operand = 0 },
            .{ .kind = .const_string, .dst = 1, .string_literal = "legacy" },
            .{ .kind = .return_value, .operand = 1 },
        },
    };

    const encoded = try encodeProgramPlanVersioned(std.testing.allocator, artifact_format_version_v1, plan, .{
        .build_fingerprint_blake3_256 = buildFingerprintFromSeed("artifact-legacy-v1-instruction-tags"),
        .capabilities = &.{},
    });
    defer std.testing.allocator.free(encoded);

    var decoded = try decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqual(artifact_format_version_v1, decoded.artifact_version);
    try std.testing.expectEqual(@as(usize, 2), decoded.functions.len);
    try std.testing.expectEqual(.call_helper, decoded.instructions[0].kind);
    try std.testing.expectEqual(.return_value, decoded.instructions[1].kind);
    try std.testing.expectEqual(.const_string, decoded.instructions[2].kind);
    try std.testing.expectEqual(.return_value, decoded.instructions[3].kind);
}

test "ArtifactV1 decode rejects legacy v1 function rows before row validation" {
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.legacy_v1_function_reserved_bytes",
        .ir_hash = 0x46,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };

    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = buildFingerprintFromSeed("artifact-legacy-v1-function-reserved-bytes"),
        .capabilities = &.{},
    });
    defer std.testing.allocator.free(encoded);

    patchArtifactVersion(encoded, artifact_format_version_v1);
    patchSectionReservedByte(encoded, .function_table, 0, 9, 1);

    try std.testing.expectError(error.UnsupportedVersion, decode(std.testing.allocator, encoded));
}

test "ArtifactV1 decode accepts v2 function rows with explicit result_codec bytes" {
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.v2_function_result_codec_bytes",
        .ir_hash = 0x47,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };

    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = buildFingerprintFromSeed("artifact-v2-function-result-codec-bytes"),
        .capabilities = &.{},
    });
    defer std.testing.allocator.free(encoded);

    patchArtifactVersion(encoded, artifact_format_version_v2);
    patchSectionReservedByte(encoded, .function_table, 0, 9, 1);
    patchSectionReservedByte(encoded, .function_table, 0, 10, @intFromEnum(program_plan.ValueCodec.string));

    var decoded = try decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), decoded.functions.len);
    try std.testing.expectEqual(program_plan.ValueCodec.unit, decoded.functions[0].value_codec);
    try std.testing.expectEqual(program_plan.ValueCodec.string, decoded.functions[0].result_codec.?);
}

test "ArtifactV1 decode preserves v2 capability manifests and fingerprint domain" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-v2-capability-manifest");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.v2_capability_manifest",
        .ir_hash = 0x48,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "dispatch", .mode = .transform, .payload_codec = .string, .resume_codec = .string, .has_after = true }},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };

    const capabilities = try deriveToolCapabilitiesFromPlan(std.testing.allocator, plan);
    defer deepFreeCapabilities(std.testing.allocator, capabilities);

    const v2_fingerprint = try buildFingerprintForCapabilitiesForArtifactVersion(
        std.testing.allocator,
        artifact_format_version_v2,
        build_fingerprint,
        capabilities,
    );
    const v3_fingerprint = try buildFingerprintForCapabilitiesForArtifactVersion(
        std.testing.allocator,
        artifact_format_version_v3,
        build_fingerprint,
        capabilities,
    );
    try std.testing.expect(!std.mem.eql(u8, &v2_fingerprint, &v3_fingerprint));

    const encoded = try encodeProgramPlanVersioned(std.testing.allocator, artifact_format_version_v2, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = capabilities,
    });
    defer std.testing.allocator.free(encoded);

    var decoded = try decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqual(artifact_format_version_v2, decoded.artifact_version);
    try std.testing.expectEqual(@as(usize, 1), decoded.capabilities.len);
    try std.testing.expectEqual(@as(usize, 2), decoded.capabilities[0].ops.len);
    try std.testing.expectEqual(.call, decoded.capabilities[0].ops[0].host_op_kind);
    try std.testing.expectEqual(.after_call, decoded.capabilities[0].ops[1].host_op_kind);
    try std.testing.expect(std.mem.eql(u8, &v2_fingerprint, &decoded.build_fingerprint_blake3_256));
    try decoded.validate(std.testing.allocator);
}

test "ArtifactV1 decode preserves v1 capability manifests on the legacy fingerprint domain" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-v1-capability-manifest");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.v1_capability_manifest",
        .ir_hash = 0x49,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "dispatch", .mode = .transform, .payload_codec = .string, .resume_codec = .string, .has_after = true }},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };

    const capabilities = try deriveToolCapabilitiesFromPlan(std.testing.allocator, plan);
    defer deepFreeCapabilities(std.testing.allocator, capabilities);

    const v1_fingerprint = try buildFingerprintForCapabilitiesForArtifactVersion(
        std.testing.allocator,
        artifact_format_version_v1,
        build_fingerprint,
        capabilities,
    );
    const v2_fingerprint = try buildFingerprintForCapabilitiesForArtifactVersion(
        std.testing.allocator,
        artifact_format_version_v2,
        build_fingerprint,
        capabilities,
    );
    try std.testing.expect(std.mem.eql(u8, &v1_fingerprint, &v2_fingerprint));

    const encoded = try encodeProgramPlanVersioned(std.testing.allocator, artifact_format_version_v1, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = capabilities,
    });
    defer std.testing.allocator.free(encoded);

    var decoded = try decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqual(artifact_format_version_v1, decoded.artifact_version);
    try std.testing.expectEqual(@as(usize, 1), decoded.capabilities.len);
    try std.testing.expectEqual(@as(usize, 2), decoded.capabilities[0].ops.len);
    try std.testing.expectEqual(.call, decoded.capabilities[0].ops[0].host_op_kind);
    try std.testing.expectEqual(.after_call, decoded.capabilities[0].ops[1].host_op_kind);
    try std.testing.expect(std.mem.eql(u8, &v1_fingerprint, &decoded.build_fingerprint_blake3_256));
    try decoded.validate(std.testing.allocator);
}

test "ArtifactV1 public versioned fingerprint helper preserves retained legacy artifact digests" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-legacy-public-fingerprint-helper");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.legacy_public_fingerprint_helper",
        .ir_hash = 0x4a,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "dispatch", .mode = .transform, .payload_codec = .string, .resume_codec = .string, .has_after = true }},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };

    const capabilities = try deriveToolCapabilitiesFromPlan(std.testing.allocator, plan);
    defer deepFreeCapabilities(std.testing.allocator, capabilities);

    const encoded_v1 = try encodeProgramPlanVersioned(std.testing.allocator, artifact_format_version_v1, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = capabilities,
    });
    defer std.testing.allocator.free(encoded_v1);
    const encoded_v2 = try encodeProgramPlanVersioned(std.testing.allocator, artifact_format_version_v2, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = capabilities,
    });
    defer std.testing.allocator.free(encoded_v2);

    var decoded_v1 = try decode(std.testing.allocator, encoded_v1);
    defer decoded_v1.deinit(std.testing.allocator);
    var decoded_v2 = try decode(std.testing.allocator, encoded_v2);
    defer decoded_v2.deinit(std.testing.allocator);

    const recomputed_v1 = try buildFingerprintForCapabilitiesForArtifactVersion(
        std.testing.allocator,
        decoded_v1.artifact_version,
        decoded_v1.manifest_build_fingerprint,
        decoded_v1.capabilities,
    );
    const recomputed_v2 = try buildFingerprintForCapabilitiesForArtifactVersion(
        std.testing.allocator,
        decoded_v2.artifact_version,
        decoded_v2.manifest_build_fingerprint,
        decoded_v2.capabilities,
    );

    try std.testing.expect(std.mem.eql(u8, &recomputed_v1, &decoded_v1.build_fingerprint_blake3_256));
    try std.testing.expect(std.mem.eql(u8, &recomputed_v2, &decoded_v2.build_fingerprint_blake3_256));
}

test "ArtifactV1 rejects custom capabilities whose op codecs do not match the compiled plan" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-v1-custom-capability-mismatch");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.test",
        .ir_hash = 0x55,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 2 }},
        .ops = &.{
            .{ .requirement_index = 0, .op_name = "first", .mode = .transform, .payload_codec = .unit, .resume_codec = .string },
            .{ .requirement_index = 0, .op_name = "second", .mode = .transform, .payload_codec = .string, .resume_codec = .unit },
        },
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };
    const capabilities = [_]CapabilityV1{.{
        .capability_id = 9,
        .kind = .tool,
        .label = "generated/tooling@v1",
        .ops = &.{
            .{
                .capability_id = 9,
                .op_id = 0,
                .host_op_kind = .call,
                .payload_codec = .string,
                .result_codec = .unit,
                .plan_op_ordinal = 0,
            },
            .{
                .capability_id = 9,
                .op_id = 1,
                .host_op_kind = .call,
                .payload_codec = .unit,
                .result_codec = .string,
                .plan_op_ordinal = 1,
            },
        },
    }};

    try std.testing.expectError(error.InvalidRequiredSection, encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &capabilities,
    }));
}

test "ArtifactV1 rejects exact-label custom capabilities whose op codecs do not match the compiled plan" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-v1-exact-label-capability-mismatch");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.test",
        .ir_hash = 0x56,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{.{ .label = "repo/tooling@v1", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "first", .mode = .transform, .payload_codec = .unit, .resume_codec = .string }},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };
    const capabilities = [_]CapabilityV1{.{
        .capability_id = 10,
        .kind = .tool,
        .label = "repo/tooling@v1",
        .ops = &.{.{
            .capability_id = 10,
            .op_id = 0,
            .host_op_kind = .call,
            .payload_codec = .string,
            .result_codec = .unit,
            .plan_op_ordinal = 0,
        }},
    }};

    try std.testing.expectError(error.InvalidRequiredSection, encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &capabilities,
    }));
}

test "ArtifactV1 rejects mixed-codec choice manifests" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-v1-choice-mixed-codec");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.choice_resume_codec",
        .ir_hash = 0x57,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .string,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 2,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 3,
        }},
        .requirements = &.{.{ .label = "chooser", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "pick", .mode = .choice, .payload_codec = .unit, .resume_codec = .i32 }},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .string }, .{ .codec = .i32 } },
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 3, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{ .kind = .const_string, .dst = 0, .string_literal = "fallback" },
            .{ .kind = .call_op, .dst = 1, .operand = 0 },
            .{ .kind = .return_value, .operand = 0 },
        },
    };

    try std.testing.expectError(error.InvalidRequiredSection, deriveToolCapabilitiesFromPlan(std.testing.allocator, plan));

    const capabilities = [_]CapabilityV1{.{
        .capability_id = 3,
        .kind = .tool,
        .label = "generated/chooser@v1",
        .ops = &.{.{
            .capability_id = 3,
            .op_id = 0,
            .host_op_kind = .call,
            .payload_codec = .unit,
            .result_codec = .i32,
            .plan_op_ordinal = 0,
        }},
    }};

    try std.testing.expectError(error.InvalidRequiredSection, encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &capabilities,
    }));
}

fn expectDerivedCapabilityCleanupOnAllocationFailure(allocator: std.mem.Allocator) !void {
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.derived_capability_cleanup",
        .ir_hash = 0x911,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 2,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{
            .{ .label = "artifactSearch", .first_op = 0, .op_count = 2 },
            .{ .label = "HTTP", .first_op = 2, .op_count = 1 },
        },
        .ops = &.{
            .{ .requirement_index = 0, .op_name = "search", .mode = .transform, .payload_codec = .unit, .resume_codec = .unit },
            .{ .requirement_index = 0, .op_name = "fetch", .mode = .choice, .payload_codec = .unit, .resume_codec = .i32 },
            .{ .requirement_index = 1, .op_name = "get", .mode = .transform, .payload_codec = .string, .resume_codec = .string },
        },
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };

    const derived = try deriveToolCapabilitiesFromPlan(allocator, plan);
    defer deepFreeCapabilities(allocator, derived);
}

test "ArtifactV1 deriveToolCapabilitiesFromPlan unwinds partially built manifests on allocator failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        expectDerivedCapabilityCleanupOnAllocationFailure,
        .{},
    );
}

test "ArtifactV1 deriveToolCapabilitiesFromPlan omits after rows unless the plan marks them" {
    const without_after: program_plan.ProgramPlan = .{
        .label = "artifact.derived_without_after",
        .ir_hash = 0x932,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .string,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        }},
        .requirements = &.{.{ .label = "picker", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "pick", .mode = .transform, .payload_codec = .unit, .resume_codec = .string }},
        .outputs = &.{},
        .locals = &.{.{ .codec = .string }},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{ .kind = .call_op, .dst = 0, .operand = 0 },
            .{ .kind = .return_value, .operand = 0 },
        },
    };

    const derived_without_after = try deriveToolCapabilitiesFromPlan(std.testing.allocator, without_after);
    defer deepFreeCapabilities(std.testing.allocator, derived_without_after);
    try std.testing.expectEqual(@as(usize, 1), derived_without_after[0].ops.len);
    try std.testing.expectEqual(.call, derived_without_after[0].ops[0].host_op_kind);

    const with_after: program_plan.ProgramPlan = .{
        .label = "artifact.derived_with_after",
        .ir_hash = 0x933,
        .entry_index = 0,
        .functions = without_after.functions,
        .requirements = without_after.requirements,
        .ops = &.{.{ .requirement_index = 0, .op_name = "pick", .mode = .transform, .payload_codec = .unit, .resume_codec = .string, .has_after = true }},
        .outputs = without_after.outputs,
        .locals = without_after.locals,
        .call_args = without_after.call_args,
        .blocks = without_after.blocks,
        .terminators = without_after.terminators,
        .instructions = without_after.instructions,
    };

    const derived_with_after = try deriveToolCapabilitiesFromPlan(std.testing.allocator, with_after);
    defer deepFreeCapabilities(std.testing.allocator, derived_with_after);
    try std.testing.expectEqual(@as(usize, 2), derived_with_after[0].ops.len);
    try std.testing.expectEqual(.call, derived_with_after[0].ops[0].host_op_kind);
    try std.testing.expectEqual(.after_call, derived_with_after[0].ops[1].host_op_kind);
}

test "ArtifactV1 derives injective generated tool ids for valid requirement labels" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-v1-derived-tool-id-normalization");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.derived_tool_id_normalization",
        .ir_hash = 0x302,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 2,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{
            .{ .label = "artifactSearch", .first_op = 0, .op_count = 1 },
            .{ .label = "HTTP", .first_op = 1, .op_count = 1 },
        },
        .ops = &.{
            .{ .requirement_index = 0, .op_name = "fetch", .mode = .transform, .payload_codec = .unit, .resume_codec = .unit },
            .{ .requirement_index = 1, .op_name = "get", .mode = .transform, .payload_codec = .unit, .resume_codec = .unit },
        },
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };

    const derived = try deriveToolCapabilitiesFromPlan(std.testing.allocator, plan);
    defer deepFreeCapabilities(std.testing.allocator, derived);
    try std.testing.expectEqualStrings("generated/artifact_53earch@v1", derived[0].label);
    try std.testing.expectEqualStrings("generated/_48_54_54_50@v1", derived[1].label);

    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = derived,
    });
    defer std.testing.allocator.free(encoded);

    var decoded = try decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("generated/artifact_53earch@v1", decoded.capabilities[0].label);
    try std.testing.expectEqualStrings("generated/_48_54_54_50@v1", decoded.capabilities[1].label);
}

test "ArtifactV1 normalizes derived default tool ids for mixed-case requirement labels" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-v1-default-tool-id-normalization");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.default_tool_id_normalization",
        .ir_hash = 0x58,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 2,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{
            .{ .label = "artifactSearch", .first_op = 0, .op_count = 1 },
            .{ .label = "HTTP", .first_op = 1, .op_count = 1 },
        },
        .ops = &.{
            .{ .requirement_index = 0, .op_name = "search", .mode = .transform, .payload_codec = .unit, .resume_codec = .unit },
            .{ .requirement_index = 1, .op_name = "fetch", .mode = .transform, .payload_codec = .unit, .resume_codec = .unit },
        },
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };

    const derived = try deriveToolCapabilitiesFromPlan(std.testing.allocator, plan);
    defer deepFreeCapabilities(std.testing.allocator, derived);
    try std.testing.expectEqualStrings("generated/artifactsearch@v1", derived[0].label);
    try std.testing.expectEqualStrings("generated/http@v1", derived[1].label);

    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = derived,
    });
    defer std.testing.allocator.free(encoded);
}

fn expectMalformedCapabilityManifestDecodeCleanup(allocator: std.mem.Allocator) !void {
    const build_fingerprint = buildFingerprintFromSeed("artifact-v1-decode-cleanup");
    const manifest = CapabilityManifestV1{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &.{.{
            .capability_id = 7,
            .kind = .tool,
            .label = "generated/tooling@v1",
            .ops = &.{
                .{
                    .capability_id = 7,
                    .op_id = 0,
                    .host_op_kind = .call,
                    .payload_codec = .unit,
                    .result_codec = .string,
                    .plan_op_ordinal = 0,
                },
                .{
                    .capability_id = 7,
                    .op_id = 1,
                    .host_op_kind = .call,
                    .payload_codec = .string,
                    .result_codec = .unit,
                    .plan_op_ordinal = 1,
                },
            },
        }},
    };

    var strings = StringTable.init(allocator);
    defer strings.deinit();
    const manifest_bytes = try encodeCapabilityManifest(allocator, &strings, manifest);
    defer allocator.free(manifest_bytes);
    const string_bytes = try strings.toOwnedBytes(allocator);
    defer allocator.free(string_bytes);

    var corrupted_manifest = try allocator.dupe(u8, manifest_bytes);
    defer allocator.free(corrupted_manifest);
    corrupted_manifest[52 + 16 + 12] = 0xff;

    try std.testing.expectError(
        error.UnsupportedVersion,
        decodeCapabilityManifest(allocator, artifact_version_current, string_bytes, corrupted_manifest),
    );
}

fn expectArtifactToProgramPlanCleanupOnAllocationFailure(allocator: std.mem.Allocator) !void {
    const artifact_value: ArtifactV1 = .{
        .semantic_ir_hash64 = 0x912,
        .artifact_hash_blake3_256 = std.mem.zeroes([32]u8),
        .build_fingerprint_blake3_256 = buildFingerprintFromSeed("artifact-v1-to-program-plan-cleanup"),
        .entry_function_index = 0,
        .capabilities = &.{},
        .requirement_capability_ids = &.{},
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .string,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 1,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "value", .mode = .transform, .payload_codec = .unit, .resume_codec = .string }},
        .outputs = &.{.{ .label = "stdout", .codec = .string }},
        .locals = &.{.{ .codec = .string }},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{ .kind = .const_string, .dst = 0, .string_literal = "fallback" },
            .{ .kind = .return_value, .operand = 0 },
        },
    };

    const plan = try artifact_value.toProgramPlan(allocator);
    defer deepFreeProgramPlan(allocator, plan);
}

fn expectArtifactValidateCleanupOnAllocationFailure(allocator: std.mem.Allocator) !void {
    const build_fingerprint = buildFingerprintFromSeed("artifact-v1-validate-cleanup");
    const artifact_value: ArtifactV1 = .{
        .semantic_ir_hash64 = 0x913,
        .artifact_hash_blake3_256 = std.mem.zeroes([32]u8),
        .build_fingerprint_blake3_256 = build_fingerprint,
        .entry_function_index = 0,
        .capabilities = &.{.{
            .capability_id = 5,
            .kind = .tool,
            .label = "generated/tooling@v1",
            .ops = &.{.{
                .capability_id = 5,
                .op_id = 0,
                .host_op_kind = .call,
                .payload_codec = .unit,
                .result_codec = .string,
                .plan_op_ordinal = 0,
            }},
        }},
        .requirement_capability_ids = &.{5},
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .string,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 1,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "value", .mode = .transform, .payload_codec = .unit, .resume_codec = .string }},
        .outputs = &.{.{ .label = "stdout", .codec = .string }},
        .locals = &.{.{ .codec = .string }},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{ .kind = .const_string, .dst = 0, .string_literal = "fallback" },
            .{ .kind = .return_value, .operand = 0 },
        },
    };

    try artifact_value.validate(allocator);
}

fn expectMalformedStringBearingDecodeCleanup(allocator: std.mem.Allocator) !void {
    const build_fingerprint = buildFingerprintFromSeed("artifact-string-bearing-decode-cleanup");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.string_bearing_decode_cleanup",
        .ir_hash = 0xb3,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .string,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 1,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "call", .mode = .transform, .payload_codec = .unit, .resume_codec = .string }},
        .outputs = &.{.{ .label = "stdout", .codec = .string }},
        .locals = &.{.{ .codec = .string }},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value, .primary = 0, .secondary = 0 }},
        .instructions = &.{
            .{ .kind = .const_string, .dst = 0, .operand = 0, .aux = 0, .string_literal = "fallback" },
            .{ .kind = .return_value, .dst = 0, .operand = 0, .aux = 0, .string_literal = "" },
        },
    };
    const capabilities = [_]CapabilityV1{.{
        .capability_id = 5,
        .kind = .tool,
        .label = "generated/tooling@v1",
        .ops = &.{.{
            .capability_id = 5,
            .op_id = 0,
            .host_op_kind = .call,
            .payload_codec = .unit,
            .result_codec = .string,
            .plan_op_ordinal = 0,
        }},
    }};

    const corruptions = [_]struct {
        section_id: SectionId,
        row_index: usize,
        byte_offset: usize,
    }{
        .{ .section_id = .requirement_table, .row_index = 0, .byte_offset = 14 },
        .{ .section_id = .op_table, .row_index = 0, .byte_offset = 5 },
        .{ .section_id = .output_table, .row_index = 0, .byte_offset = 9 },
        .{ .section_id = .function_table, .row_index = 0, .byte_offset = 9 },
        .{ .section_id = .instruction_table, .row_index = 0, .byte_offset = 1 },
    };

    for (corruptions) |corruption| {
        const encoded = try encodeProgramPlan(allocator, plan, .{
            .build_fingerprint_blake3_256 = build_fingerprint,
            .capabilities = &capabilities,
        });
        defer allocator.free(encoded);

        patchSectionReservedByte(encoded, corruption.section_id, corruption.row_index, corruption.byte_offset, 0xff);
        try std.testing.expectError(error.NonZeroReserved, decode(allocator, encoded));
    }
}

test "ArtifactV1 toProgramPlan unwinds partially cloned plan tables on allocator failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        expectArtifactToProgramPlanCleanupOnAllocationFailure,
        .{},
    );
}

test "ArtifactV1 validate unwinds rebuilt plan tables on allocator failure" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        expectArtifactValidateCleanupOnAllocationFailure,
        .{},
    );
}

test "ArtifactV1 decode frees partially decoded capability manifests on malformed bytes and allocator failure" {
    try expectMalformedCapabilityManifestDecodeCleanup(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        expectMalformedCapabilityManifestDecodeCleanup,
        .{},
    );
}

test "ArtifactV1 decode frees partially decoded string-bearing tables on malformed bytes and allocator failure" {
    try expectMalformedStringBearingDecodeCleanup(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        expectMalformedStringBearingDecodeCleanup,
        .{},
    );
}

test "ArtifactV1 checked string ref ends reject u32 overflow" {
    try std.testing.expect(checkedStringRefEnd(std.math.maxInt(u32), 1) == null);
}

test "ArtifactV1 decode accepts reserved optional sections" {
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.optional_reserved_section",
        .ir_hash = 0x58,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };

    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = buildFingerprintFromSeed("artifact-optional-reserved-section"),
        .capabilities = &.{},
    });
    defer std.testing.allocator.free(encoded);

    const optional_encoded = try appendRawDirectoryEntry(
        std.testing.allocator,
        encoded,
        .{
            .raw_section_id = 0x1001,
            .flags = section_optional_flag,
            .entry_count = 1,
            .payload = "reserved-metadata",
        },
    );
    defer std.testing.allocator.free(optional_encoded);

    var decoded = try decode(std.testing.allocator, optional_encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), decoded.capabilities.len);
}

test "ArtifactV1 decode rejects unknown directory flag bits" {
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.directory_flag_bits",
        .ir_hash = 0x5a,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };

    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = buildFingerprintFromSeed("artifact-directory-flag-bits"),
        .capabilities = &.{},
    });
    defer std.testing.allocator.free(encoded);

    const optional_encoded = try appendRawDirectoryEntry(
        std.testing.allocator,
        encoded,
        .{
            .raw_section_id = 0x1002,
            .flags = 0x2,
            .entry_count = 1,
            .payload = "reserved-metadata",
        },
    );
    defer std.testing.allocator.free(optional_encoded);

    try std.testing.expectError(error.UnsupportedVersion, decode(std.testing.allocator, optional_encoded));
}

test "ArtifactV1 decode rejects unknown capability flag bits" {
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.capability_flag_bits",
        .ir_hash = 0x59,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "call", .mode = .transform, .payload_codec = .unit, .resume_codec = .unit }},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };
    const capabilities = [_]CapabilityV1{.{
        .capability_id = 4,
        .kind = .tool,
        .label = "generated/tooling@v1",
        .ops = &.{.{
            .capability_id = 4,
            .op_id = 0,
            .host_op_kind = .call,
            .payload_codec = .unit,
            .result_codec = .unit,
            .plan_op_ordinal = 0,
        }},
    }};

    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = buildFingerprintFromSeed("artifact-capability-flag-bits"),
        .capabilities = &capabilities,
    });
    defer std.testing.allocator.free(encoded);

    patchCapabilityFlags(encoded, 0, capability_required_flag | 0x2);
    try std.testing.expectError(error.UnsupportedVersion, decode(std.testing.allocator, encoded));
}

test "ArtifactV1 rejects optional capability rows during encode and decode" {
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.optional_capability_rejected",
        .ir_hash = 0x91,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "call", .mode = .transform, .payload_codec = .unit, .resume_codec = .unit }},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };
    const optional_capabilities = [_]CapabilityV1{.{
        .capability_id = 4,
        .kind = .tool,
        .required = false,
        .label = "generated/tooling@v1",
        .ops = &.{.{
            .capability_id = 4,
            .op_id = 0,
            .host_op_kind = .call,
            .payload_codec = .unit,
            .result_codec = .unit,
            .plan_op_ordinal = 0,
        }},
    }};

    try std.testing.expectError(error.InvalidRequiredSection, encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = buildFingerprintFromSeed("artifact-optional-capability-encode"),
        .capabilities = &optional_capabilities,
    }));

    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = buildFingerprintFromSeed("artifact-optional-capability-decode"),
        .capabilities = &.{.{
            .capability_id = 4,
            .kind = .tool,
            .label = "generated/tooling@v1",
            .ops = &.{.{
                .capability_id = 4,
                .op_id = 0,
                .host_op_kind = .call,
                .payload_codec = .unit,
                .result_codec = .unit,
                .plan_op_ordinal = 0,
            }},
        }},
    });
    defer std.testing.allocator.free(encoded);

    patchCapabilityFlags(encoded, 0, 0);
    try std.testing.expectError(error.InvalidRequiredSection, decode(std.testing.allocator, encoded));
}

test "ArtifactV1 advertises usize capability codecs precisely" {
    try std.testing.expectEqual(CapabilityCodecV1.usize, mapPlanCodecToCapabilityCodec(.usize));
}

test "ArtifactV1 exact-build fingerprints include custom capability label contents" {
    const base_fingerprint = buildFingerprintFromSeed("artifact-v1-capability-fingerprint-label-contents");
    const capabilities_alpha = [_]CapabilityV1{.{
        .capability_id = 7,
        .kind = .tool,
        .label = "repo/alpha@v1",
        .ops = &.{.{
            .capability_id = 7,
            .op_id = 0,
            .host_op_kind = .call,
            .payload_codec = .unit,
            .result_codec = .string,
            .plan_op_ordinal = 0,
        }},
    }};
    const capabilities_bravo = [_]CapabilityV1{.{
        .capability_id = 7,
        .kind = .tool,
        .label = "repo/bravo@v1",
        .ops = &.{.{
            .capability_id = 7,
            .op_id = 0,
            .host_op_kind = .call,
            .payload_codec = .unit,
            .result_codec = .string,
            .plan_op_ordinal = 0,
        }},
    }};

    const fingerprint_alpha = try buildFingerprintForCapabilities(
        std.testing.allocator,
        base_fingerprint,
        &capabilities_alpha,
    );
    const fingerprint_bravo = try buildFingerprintForCapabilities(
        std.testing.allocator,
        base_fingerprint,
        &capabilities_bravo,
    );

    try std.testing.expect(!std.mem.eql(u8, &fingerprint_alpha, &fingerprint_bravo));
}

test "ArtifactV1 rejects executable string_list codecs during encode" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-v1-string-list-boundary");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.test",
        .ir_hash = 0x57,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .string_list,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "items", .mode = .transform, .payload_codec = .unit, .resume_codec = .string_list }},
        .outputs = &.{},
        .locals = &.{.{ .codec = .string_list }},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{ .kind = .call_op, .dst = 0, .operand = 0 },
            .{ .kind = .return_value, .operand = 0 },
        },
    };

    try std.testing.expectError(error.UnsupportedExecutableCodec, encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &.{},
    }));
}

test "ArtifactV1 rejects executable string_list result codecs during encode" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-v1-string-list-result-boundary");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.result_codec_string_list",
        .ir_hash = 0x58,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .result_codec = .string_list,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "dispatch", .mode = .transform, .payload_codec = .unit, .resume_codec = .unit, .has_after = true }},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{.{ .kind = .call_op, .operand = 0 }},
    };

    try std.testing.expectError(error.UnsupportedExecutableCodec, encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &.{},
    }));
}

test "ArtifactV1 rejects executable-only interpreter instructions during encode and decode" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-unsupported-interpreter-instructions");
    const base_plan: program_plan.ProgramPlan = .{
        .label = "artifact.unsupported_interpreter_instruction_base",
        .ir_hash = 0x351,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .string,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .string }},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{ .kind = .const_string, .dst = 0, .string_literal = "Boom" },
            .{ .kind = .return_value, .operand = 0 },
        },
    };
    const unsupported_nested_plan: program_plan.ProgramPlan = .{
        .label = "artifact.unsupported_nested_with",
        .ir_hash = 0x352,
        .entry_index = 0,
        .functions = base_plan.functions,
        .requirements = base_plan.requirements,
        .ops = base_plan.ops,
        .outputs = base_plan.outputs,
        .locals = base_plan.locals,
        .call_args = base_plan.call_args,
        .blocks = base_plan.blocks,
        .terminators = base_plan.terminators,
        .instructions = &.{
            .{ .kind = .call_nested_with, .dst = 0, .aux = @intFromEnum(program_plan.ValueCodec.unit), .string_literal = "nested\x1fruntime\x1fptr\x1ffactory\x1fcontainer\x1fhandler\x1fcarrier\x1fsrc.zig\x1fbody" },
            .{ .kind = .return_value, .operand = 0 },
        },
    };
    const unsupported_return_error_plan: program_plan.ProgramPlan = .{
        .label = "artifact.unsupported_return_error",
        .ir_hash = 0x353,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .string,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{.{ .kind = .return_error, .string_literal = "Boom" }},
    };

    try std.testing.expectError(error.UnsupportedExecInstruction, encodeProgramPlan(std.testing.allocator, unsupported_nested_plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &.{},
    }));
    try std.testing.expectError(error.UnsupportedExecInstruction, encodeProgramPlan(std.testing.allocator, unsupported_return_error_plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &.{},
    }));

    const nested_encoded = try encodeProgramPlan(std.testing.allocator, base_plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &.{},
    });
    defer std.testing.allocator.free(nested_encoded);
    patchInstructionKind(nested_encoded, 0, 10);
    try std.testing.expectError(error.UnsupportedExecInstruction, decode(std.testing.allocator, nested_encoded));

    const return_error_encoded = try encodeProgramPlan(std.testing.allocator, base_plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &.{},
    });
    defer std.testing.allocator.free(return_error_encoded);
    patchInstructionKind(return_error_encoded, 1, 11);
    patchInstructionStringRefFromRow(return_error_encoded, 1, 0);
    patchTerminatorKind(return_error_encoded, 0, .return_unit);
    try std.testing.expectError(error.UnsupportedExecInstruction, decode(std.testing.allocator, return_error_encoded));
}

test "ArtifactV1 derives after capability payload and result codecs from function value and result codecs" {
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.after_result_codec_split",
        .ir_hash = 0x59,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .result_codec = .string,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "dispatch", .mode = .transform, .payload_codec = .unit, .resume_codec = .unit, .has_after = true }},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{.{ .kind = .call_op, .operand = 0 }},
    };

    const capabilities = try deriveToolCapabilitiesFromPlan(std.testing.allocator, plan);
    defer deepFreeCapabilities(std.testing.allocator, capabilities);

    try std.testing.expectEqual(@as(usize, 1), capabilities.len);
    try std.testing.expectEqual(@as(usize, 2), capabilities[0].ops.len);
    try std.testing.expectEqual(CapabilityCodecV1.unit, capabilities[0].ops[1].payload_codec);
    try std.testing.expectEqual(CapabilityCodecV1.string, capabilities[0].ops[1].result_codec);
}

test "ArtifactV1 rejects mixed-codec choice result codecs" {
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.choice_result_codec",
        .ir_hash = 0x5a,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .result_codec = .string,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{.{ .label = "chooser", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "pick", .mode = .choice, .payload_codec = .unit, .resume_codec = .unit }},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{.{ .kind = .call_op, .operand = 0 }},
    };

    try std.testing.expectError(error.InvalidRequiredSection, deriveToolCapabilitiesFromPlan(std.testing.allocator, plan));
}

test "ArtifactV1 encoding canonicalizes ignored instruction fields" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-v1-canonical-instruction-fields");
    const base_plan: program_plan.ProgramPlan = .{
        .label = "artifact.canonical_instruction_fields",
        .ir_hash = 0x92,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .string,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .string }},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{ .kind = .const_string, .dst = 0, .string_literal = "done" },
            .{ .kind = .return_value, .operand = 0 },
        },
    };
    const noisy_plan: program_plan.ProgramPlan = .{
        .label = "artifact.canonical_instruction_fields",
        .ir_hash = 0x92,
        .entry_index = 0,
        .functions = base_plan.functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = base_plan.locals,
        .call_args = &.{},
        .blocks = base_plan.blocks,
        .terminators = base_plan.terminators,
        .instructions = &.{
            .{ .kind = .const_string, .dst = 0, .operand = 17, .aux = 23, .string_literal = "done" },
            .{ .kind = .return_value, .dst = 9, .operand = 0, .aux = 11, .string_literal = "ignored" },
        },
    };

    const base_bytes = try encodeProgramPlan(std.testing.allocator, base_plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &.{},
    });
    defer std.testing.allocator.free(base_bytes);

    const noisy_bytes = try encodeProgramPlan(std.testing.allocator, noisy_plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &.{},
    });
    defer std.testing.allocator.free(noisy_bytes);

    try std.testing.expectEqualSlices(u8, base_bytes, noisy_bytes);
}

test "ArtifactV1 encoding canonicalizes add_i32 ignored fields" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-v1-canonical-add-i32");
    const base_plan: program_plan.ProgramPlan = .{
        .label = "artifact.canonical_add_i32",
        .ir_hash = 0x93,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .i32,
            .parameter_count = 2,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 3,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 2,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{
            .{ .codec = .i32 },
            .{ .codec = .i32 },
            .{ .codec = .i32 },
        },
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{
            .{ .kind = .add_i32, .dst = 2, .operand = 0, .aux = 1 },
            .{ .kind = .return_value, .operand = 2 },
        },
    };
    const noisy_plan: program_plan.ProgramPlan = .{
        .label = "artifact.canonical_add_i32",
        .ir_hash = 0x93,
        .entry_index = 0,
        .functions = base_plan.functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = base_plan.locals,
        .call_args = &.{},
        .blocks = base_plan.blocks,
        .terminators = base_plan.terminators,
        .instructions = &.{
            .{ .kind = .add_i32, .dst = 2, .operand = 0, .aux = 1, .string_literal = "ignored" },
            .{ .kind = .return_value, .dst = 9, .operand = 2, .aux = 11, .string_literal = "ignored" },
        },
    };

    const base_bytes = try encodeProgramPlan(std.testing.allocator, base_plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &.{},
    });
    defer std.testing.allocator.free(base_bytes);

    const noisy_bytes = try encodeProgramPlan(std.testing.allocator, noisy_plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &.{},
    });
    defer std.testing.allocator.free(noisy_bytes);

    try std.testing.expectEqualSlices(u8, base_bytes, noisy_bytes);
}

test "ArtifactV1 encoding is deterministic and disasm is readable" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-v1-deterministic");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.test",
        .ir_hash = 0x91,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };
    const encoded_a = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &.{},
    });
    defer std.testing.allocator.free(encoded_a);
    const encoded_b = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &.{},
    });
    defer std.testing.allocator.free(encoded_b);

    try std.testing.expectEqualSlices(u8, encoded_a, encoded_b);

    const disasm = try disasmAlloc(std.testing.allocator, encoded_a);
    defer std.testing.allocator.free(disasm);
    try std.testing.expect(std.mem.find(u8, disasm, "ArtifactV1 ir_hash=145") != null);
    try std.testing.expect(std.mem.find(u8, disasm, "functions=1") != null);
}

test "ArtifactV1 rejects entry functions with parameters during encode" {
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.entry_param",
        .ir_hash = 0xaa,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .i32,
            .parameter_count = 1,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{.{ .kind = .return_value, .operand = 0 }},
    };

    try std.testing.expectError(error.UnsupportedEntryParameters, encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = buildFingerprintFromSeed("artifact-entry-param-encode"),
        .capabilities = &.{},
    }));
}

test "ArtifactV1 decode rejects entry functions with parameters" {
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.entry_param_decode",
        .ir_hash = 0xab,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .i32,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 1,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 1,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{.{ .codec = .i32 }},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 1, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_value }},
        .instructions = &.{.{ .kind = .return_value, .operand = 0 }},
    };
    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = buildFingerprintFromSeed("artifact-entry-param-decode"),
        .capabilities = &.{},
    });
    defer std.testing.allocator.free(encoded);

    patchEntryParameterCount(encoded, 1);
    try std.testing.expectError(error.UnsupportedEntryParameters, decode(std.testing.allocator, encoded));
}

test "ArtifactV1 decode rejects unsorted section directories" {
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.unsorted_dir",
        .ir_hash = 0xac,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };
    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = buildFingerprintFromSeed("artifact-unsorted-dir"),
        .capabilities = &.{},
    });
    defer std.testing.allocator.free(encoded);

    swapDirectoryEntries(encoded, 0, 1);
    try std.testing.expectError(error.UnsortedDirectorySection, decode(std.testing.allocator, encoded));
}

test "ArtifactV1 rejects malformed capability tool ids during encode and decode" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-invalid-tool-id");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.invalid_tool_id",
        .ir_hash = 0xad,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "first", .mode = .transform, .payload_codec = .unit, .resume_codec = .unit }},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };
    const invalid_capabilities = [_]CapabilityV1{.{
        .capability_id = 4,
        .kind = .tool,
        .label = "Generated/tooling@v1",
        .ops = &.{.{
            .capability_id = 4,
            .op_id = 0,
            .host_op_kind = .call,
            .payload_codec = .unit,
            .result_codec = .unit,
            .plan_op_ordinal = 0,
        }},
    }};
    try std.testing.expectError(error.InvalidToolId, encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &invalid_capabilities,
    }));

    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &.{},
    });
    defer std.testing.allocator.free(encoded);

    const label_offset = std.mem.find(u8, encoded, "generated/tooling@v1").?;
    encoded[label_offset] = 'G';
    recomputeEncodedArtifactHash(encoded);
    try std.testing.expectError(error.InvalidToolId, decode(std.testing.allocator, encoded));
}

test "ArtifactV1 encode and decode accept a single capability op at max u16 id" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-max-op-id");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.max_op_id",
        .ir_hash = 0xaf,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "only", .mode = .transform, .payload_codec = .unit, .resume_codec = .unit }},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };
    const capabilities = [_]CapabilityV1{.{
        .capability_id = 5,
        .kind = .tool,
        .label = "generated/tooling@v1",
        .ops = &.{.{
            .capability_id = 5,
            .op_id = std.math.maxInt(u16),
            .host_op_kind = .call,
            .payload_codec = .unit,
            .result_codec = .unit,
            .plan_op_ordinal = 0,
        }},
    }};

    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &capabilities,
    });
    defer std.testing.allocator.free(encoded);

    var decoded = try decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(std.math.maxInt(u16), decoded.capabilities[0].ops[0].op_id);
}

test "ArtifactV1 encode and decode accept sparse explicit capability op ids" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-sparse-op-ids");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.sparse_op_ids",
        .ir_hash = 0xaf1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 2 }},
        .ops = &.{
            .{ .requirement_index = 0, .op_name = "first", .mode = .transform, .payload_codec = .unit, .resume_codec = .unit },
            .{ .requirement_index = 0, .op_name = "second", .mode = .transform, .payload_codec = .unit, .resume_codec = .unit },
        },
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };
    const capabilities = [_]CapabilityV1{.{
        .capability_id = 5,
        .kind = .tool,
        .label = "generated/tooling@v1",
        .ops = &.{
            .{
                .capability_id = 5,
                .op_id = 4,
                .host_op_kind = .call,
                .payload_codec = .unit,
                .result_codec = .unit,
                .plan_op_ordinal = 0,
            },
            .{
                .capability_id = 5,
                .op_id = 6,
                .host_op_kind = .call,
                .payload_codec = .unit,
                .result_codec = .unit,
                .plan_op_ordinal = 1,
            },
        },
    }};

    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &capabilities,
    });
    defer std.testing.allocator.free(encoded);

    var decoded = try decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(u16, &.{ 4, 6 }, &.{
        decoded.capabilities[0].ops[0].op_id,
        decoded.capabilities[0].ops[1].op_id,
    });
}

test "ArtifactV1 decode rejects custom capability manifests with all-zero multi-op ordinals" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-zero-multi-op-ordinals");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.zero_multi_op_ordinals",
        .ir_hash = 0xb0,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 1,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{.{ .label = "tooling", .first_op = 0, .op_count = 2 }},
        .ops = &.{
            .{ .requirement_index = 0, .op_name = "first", .mode = .transform, .payload_codec = .unit, .resume_codec = .string },
            .{ .requirement_index = 0, .op_name = "second", .mode = .transform, .payload_codec = .string, .resume_codec = .unit },
        },
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };
    const capabilities = [_]CapabilityV1{.{
        .capability_id = 7,
        .kind = .tool,
        .label = "generated/tooling@v1",
        .ops = &.{
            .{
                .capability_id = 7,
                .op_id = 0,
                .host_op_kind = .call,
                .payload_codec = .unit,
                .result_codec = .string,
                .plan_op_ordinal = 0,
            },
            .{
                .capability_id = 7,
                .op_id = 1,
                .host_op_kind = .call,
                .payload_codec = .string,
                .result_codec = .unit,
                .plan_op_ordinal = 1,
            },
        },
    }};

    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &capabilities,
    });
    defer std.testing.allocator.free(encoded);

    patchCapabilityManifestPlanOrdinal(encoded, 1, 0);
    try std.testing.expectError(error.InvalidRequiredSection, decode(std.testing.allocator, encoded));
}

test "ArtifactV1 decode rejects repeated requirements that alias one capability binding" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-repeated-requirement-alias");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.repeated_requirement_alias",
        .ir_hash = 0xb1,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 2,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{
            .{ .label = "tooling", .first_op = 0, .op_count = 1 },
            .{ .label = "tooling", .first_op = 1, .op_count = 1 },
        },
        .ops = &.{
            .{ .requirement_index = 0, .op_name = "first", .mode = .transform, .payload_codec = .unit, .resume_codec = .string },
            .{ .requirement_index = 1, .op_name = "second", .mode = .transform, .payload_codec = .unit, .resume_codec = .string },
        },
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };
    const capabilities = [_]CapabilityV1{
        .{
            .capability_id = 11,
            .kind = .tool,
            .label = "generated/tooling@v1",
            .ops = &.{.{
                .capability_id = 11,
                .op_id = 0,
                .host_op_kind = .call,
                .payload_codec = .unit,
                .result_codec = .string,
                .plan_op_ordinal = 0,
            }},
        },
        .{
            .capability_id = 29,
            .kind = .tool,
            .label = "generated/tooling@v1",
            .ops = &.{.{
                .capability_id = 29,
                .op_id = 1,
                .host_op_kind = .call,
                .payload_codec = .unit,
                .result_codec = .string,
                .plan_op_ordinal = 0,
            }},
        },
    };

    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &capabilities,
    });
    defer std.testing.allocator.free(encoded);

    patchRequirementCapabilityId(encoded, 1, 11);
    try std.testing.expectError(error.InvalidRequiredSection, decode(std.testing.allocator, encoded));
}

test "ArtifactV1 decode accepts reordered capability rows when repeated requirement bindings keep their ids" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-repeated-requirement-row-reorder");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.repeated_requirement_row_reorder",
        .ir_hash = 0xb15,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 2,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{
            .{ .label = "tooling", .first_op = 0, .op_count = 1 },
            .{ .label = "tooling", .first_op = 1, .op_count = 1 },
        },
        .ops = &.{
            .{ .requirement_index = 0, .op_name = "first", .mode = .transform, .payload_codec = .unit, .resume_codec = .string },
            .{ .requirement_index = 1, .op_name = "second", .mode = .transform, .payload_codec = .unit, .resume_codec = .string },
        },
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };
    const capabilities = [_]CapabilityV1{
        .{
            .capability_id = 11,
            .kind = .tool,
            .label = "generated/tooling@v1",
            .ops = &.{.{
                .capability_id = 11,
                .op_id = 0,
                .host_op_kind = .call,
                .payload_codec = .unit,
                .result_codec = .string,
                .plan_op_ordinal = 0,
            }},
        },
        .{
            .capability_id = 29,
            .kind = .tool,
            .label = "generated/tooling@v1",
            .ops = &.{.{
                .capability_id = 29,
                .op_id = 1,
                .host_op_kind = .call,
                .payload_codec = .unit,
                .result_codec = .string,
                .plan_op_ordinal = 0,
            }},
        },
    };

    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &capabilities,
    });
    defer std.testing.allocator.free(encoded);

    swapCapabilityManifestEntries(encoded, 0, 1);

    var decoded = try decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(u16, &.{ 11, 29 }, decoded.requirement_capability_ids);
    try decoded.validate(std.testing.allocator);
}

test "ArtifactV1 encode allows repeated identical requirements to share one capability id" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-repeated-identical-requirement-shared-capability");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.repeated_identical_requirement_shared_capability",
        .ir_hash = 0xb17,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 2,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{
            .{ .label = "tooling", .first_op = 0, .op_count = 1 },
            .{ .label = "tooling", .first_op = 1, .op_count = 1 },
        },
        .ops = &.{
            .{ .requirement_index = 0, .op_name = "value", .mode = .transform, .payload_codec = .unit, .resume_codec = .string },
            .{ .requirement_index = 1, .op_name = "value", .mode = .transform, .payload_codec = .unit, .resume_codec = .string },
        },
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };
    const capabilities = [_]CapabilityV1{.{
        .capability_id = 11,
        .kind = .tool,
        .label = "generated/tooling@v1",
        .ops = &.{.{
            .capability_id = 11,
            .op_id = 0,
            .host_op_kind = .call,
            .payload_codec = .unit,
            .result_codec = .string,
            .plan_op_ordinal = 0,
        }},
    }};

    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &capabilities,
    });
    defer std.testing.allocator.free(encoded);

    var decoded = try decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(u16, &.{ 11, 11 }, decoded.requirement_capability_ids);
    try decoded.validate(std.testing.allocator);
}

test "ArtifactV1 decode rejects repeated identical requirements rebound to a different compatible capability id" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-repeated-identical-requirement-rebound-capability");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.repeated_identical_requirement_rebound_capability",
        .ir_hash = 0xb18,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 2,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{
            .{ .label = "tooling", .first_op = 0, .op_count = 1 },
            .{ .label = "tooling", .first_op = 1, .op_count = 1 },
        },
        .ops = &.{
            .{ .requirement_index = 0, .op_name = "value", .mode = .transform, .payload_codec = .unit, .resume_codec = .string },
            .{ .requirement_index = 1, .op_name = "value", .mode = .transform, .payload_codec = .unit, .resume_codec = .string },
        },
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };
    const capabilities = [_]CapabilityV1{
        .{
            .capability_id = 11,
            .kind = .tool,
            .label = "generated/tooling@v1",
            .ops = &.{.{
                .capability_id = 11,
                .op_id = 0,
                .host_op_kind = .call,
                .payload_codec = .unit,
                .result_codec = .string,
                .plan_op_ordinal = 0,
            }},
        },
        .{
            .capability_id = 29,
            .kind = .tool,
            .label = "generated/tooling@v1",
            .ops = &.{.{
                .capability_id = 29,
                .op_id = 1,
                .host_op_kind = .call,
                .payload_codec = .unit,
                .result_codec = .string,
                .plan_op_ordinal = 0,
            }},
        },
    };

    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &capabilities,
    });
    defer std.testing.allocator.free(encoded);

    patchRequirementCapabilityId(encoded, 1, 29);

    try std.testing.expectError(error.InvalidRequiredSection, decode(std.testing.allocator, encoded));
}

test "ArtifactV1 encode accepts repeated requirement labels when codecs choose distinct capabilities" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-repeated-requirement-compatible-codecs");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.repeated_requirement_compatible_codecs",
        .ir_hash = 0xb16,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 2,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{
            .{ .label = "tooling", .first_op = 0, .op_count = 1 },
            .{ .label = "tooling", .first_op = 1, .op_count = 1 },
        },
        .ops = &.{
            .{ .requirement_index = 0, .op_name = "first", .mode = .transform, .payload_codec = .unit, .resume_codec = .string },
            .{ .requirement_index = 1, .op_name = "second", .mode = .transform, .payload_codec = .unit, .resume_codec = .i32 },
        },
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };
    const capabilities = [_]CapabilityV1{
        .{
            .capability_id = 11,
            .kind = .tool,
            .label = "generated/tooling@v1",
            .ops = &.{.{
                .capability_id = 11,
                .op_id = 0,
                .host_op_kind = .call,
                .payload_codec = .unit,
                .result_codec = .string,
                .plan_op_ordinal = 0,
            }},
        },
        .{
            .capability_id = 29,
            .kind = .tool,
            .label = "generated/tooling@v1",
            .ops = &.{.{
                .capability_id = 29,
                .op_id = 1,
                .host_op_kind = .call,
                .payload_codec = .unit,
                .result_codec = .i32,
                .plan_op_ordinal = 0,
            }},
        },
    };

    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &capabilities,
    });
    defer std.testing.allocator.free(encoded);

    var decoded = try decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(u16, &.{ 11, 29 }, decoded.requirement_capability_ids);
    try decoded.validate(std.testing.allocator);
}

test "ArtifactV1 rejects custom capabilities that ambiguously match repeated requirement op names" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-repeated-requirement-op-name-disambiguation");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.repeated_requirement_op_name_disambiguation",
        .ir_hash = 0xb2,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 2,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{
            .{ .label = "tooling", .first_op = 0, .op_count = 1 },
            .{ .label = "tooling", .first_op = 1, .op_count = 1 },
        },
        .ops = &.{
            .{ .requirement_index = 0, .op_name = "first", .mode = .transform, .payload_codec = .unit, .resume_codec = .string },
            .{ .requirement_index = 1, .op_name = "second", .mode = .transform, .payload_codec = .unit, .resume_codec = .string },
        },
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };
    const capabilities = [_]CapabilityV1{
        .{
            .capability_id = 11,
            .kind = .tool,
            .label = "generated/tooling@v1",
            .ops = &.{.{
                .capability_id = 11,
                .op_id = 0,
                .host_op_kind = .call,
                .payload_codec = .unit,
                .result_codec = .string,
                .plan_op_ordinal = 0,
            }},
        },
        .{
            .capability_id = 29,
            .kind = .tool,
            .label = "generated/tooling@v1",
            .ops = &.{.{
                .capability_id = 29,
                .op_id = 1,
                .host_op_kind = .call,
                .payload_codec = .unit,
                .result_codec = .string,
                .plan_op_ordinal = 0,
            }},
        },
    };

    try std.testing.expectError(error.InvalidRequiredSection, encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &capabilities,
    }));
}

test "ArtifactV1 rejects conflicting terminal owner codecs during encode and decode" {
    const build_fingerprint = buildFingerprintFromSeed("artifact-terminal-owner-conflict");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.terminal_owner_conflict",
        .ir_hash = 0xb0,
        .entry_index = 0,
        .functions = &.{
            .{
                .symbol_name = "entry",
                .value_codec = .string,
                .parameter_count = 0,
                .first_requirement = 0,
                .requirement_count = 1,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 1,
                .first_block = 0,
                .entry_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 2,
            },
            .{
                .symbol_name = "helper",
                .value_codec = .i32,
                .parameter_count = 0,
                .first_requirement = 0,
                .requirement_count = 1,
                .first_output = 0,
                .output_count = 0,
                .first_local = 1,
                .local_count = 1,
                .first_block = 1,
                .entry_block = 1,
                .block_count = 1,
                .first_instruction = 2,
                .instruction_count = 2,
            },
        },
        .requirements = &.{.{ .label = "terminal", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "stop", .mode = .abort, .payload_codec = .unit, .resume_codec = .unit }},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .string }, .{ .codec = .i32 } },
        .call_args = &.{},
        .blocks = &.{
            .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
            .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
        },
        .terminators = &.{ .{ .kind = .return_value }, .{ .kind = .return_value } },
        .instructions = &.{
            .{ .kind = .call_op, .dst = 0, .operand = 0 },
            .{ .kind = .return_value, .operand = 0 },
            .{ .kind = .call_op, .dst = 1, .operand = 0 },
            .{ .kind = .return_value, .operand = 1 },
        },
    };

    try std.testing.expectError(error.InvalidRequiredSection, deriveToolCapabilitiesFromPlan(std.testing.allocator, plan));

    const valid_capabilities = [_]CapabilityV1{.{
        .capability_id = 0,
        .kind = .tool,
        .label = "generated/terminal@v1",
        .ops = &.{.{
            .capability_id = 0,
            .op_id = 7,
            .host_op_kind = .call,
            .payload_codec = .unit,
            .result_codec = .string,
            .plan_op_ordinal = 0,
        }},
    }};
    try std.testing.expectError(error.InvalidRequiredSection, encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &valid_capabilities,
    }));

    const single_owner_plan: program_plan.ProgramPlan = .{
        .label = "artifact.terminal_owner_decode_conflict",
        .ir_hash = 0xb1,
        .entry_index = 0,
        .functions = &.{
            .{
                .symbol_name = "entry",
                .value_codec = .string,
                .parameter_count = 0,
                .first_requirement = 0,
                .requirement_count = 1,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 1,
                .first_block = 0,
                .entry_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 2,
            },
            .{
                .symbol_name = "helper",
                .value_codec = .string,
                .parameter_count = 0,
                .first_requirement = 0,
                .requirement_count = 1,
                .first_output = 0,
                .output_count = 0,
                .first_local = 1,
                .local_count = 1,
                .first_block = 1,
                .entry_block = 1,
                .block_count = 1,
                .first_instruction = 2,
                .instruction_count = 2,
            },
        },
        .requirements = plan.requirements,
        .ops = plan.ops,
        .outputs = &.{},
        .locals = &.{ .{ .codec = .string }, .{ .codec = .string } },
        .call_args = &.{},
        .blocks = plan.blocks,
        .terminators = plan.terminators,
        .instructions = &.{
            .{ .kind = .call_op, .dst = 0, .operand = 0 },
            .{ .kind = .return_value, .operand = 0 },
            .{ .kind = .call_op, .dst = 1, .operand = 0 },
            .{ .kind = .return_value, .operand = 1 },
        },
    };

    const encoded = try encodeProgramPlan(std.testing.allocator, single_owner_plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &valid_capabilities,
    });
    defer std.testing.allocator.free(encoded);
    patchFunctionValueCodec(encoded, 1, .i32);
    try std.testing.expectError(error.InvalidRequiredSection, decode(std.testing.allocator, encoded));
}

test "ArtifactV1 decode frees partially built state when validation rejects conflicting terminal codecs" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const build_fingerprint = buildFingerprintFromSeed("artifact-terminal-owner-conflict-leak");
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.terminal_owner_leak",
        .ir_hash = 0xb2,
        .entry_index = 0,
        .functions = &.{
            .{
                .symbol_name = "entry",
                .value_codec = .string,
                .parameter_count = 0,
                .first_requirement = 0,
                .requirement_count = 1,
                .first_output = 0,
                .output_count = 0,
                .first_local = 0,
                .local_count = 1,
                .first_block = 0,
                .entry_block = 0,
                .block_count = 1,
                .first_instruction = 0,
                .instruction_count = 2,
            },
            .{
                .symbol_name = "helper",
                .value_codec = .string,
                .parameter_count = 0,
                .first_requirement = 0,
                .requirement_count = 1,
                .first_output = 0,
                .output_count = 0,
                .first_local = 1,
                .local_count = 1,
                .first_block = 1,
                .entry_block = 1,
                .block_count = 1,
                .first_instruction = 2,
                .instruction_count = 2,
            },
        },
        .requirements = &.{.{ .label = "terminal", .first_op = 0, .op_count = 1 }},
        .ops = &.{.{ .requirement_index = 0, .op_name = "stop", .mode = .abort, .payload_codec = .unit, .resume_codec = .unit }},
        .outputs = &.{},
        .locals = &.{ .{ .codec = .string }, .{ .codec = .string } },
        .call_args = &.{},
        .blocks = &.{
            .{ .first_instruction = 0, .instruction_count = 2, .terminator_index = 0 },
            .{ .first_instruction = 2, .instruction_count = 2, .terminator_index = 1 },
        },
        .terminators = &.{ .{ .kind = .return_value }, .{ .kind = .return_value } },
        .instructions = &.{
            .{ .kind = .call_op, .dst = 0, .operand = 0 },
            .{ .kind = .return_value, .operand = 0 },
            .{ .kind = .call_op, .dst = 1, .operand = 0 },
            .{ .kind = .return_value, .operand = 1 },
        },
    };
    const capabilities = [_]CapabilityV1{.{
        .capability_id = 0,
        .kind = .tool,
        .label = "generated/terminal@v1",
        .ops = &.{.{
            .capability_id = 0,
            .op_id = 7,
            .host_op_kind = .call,
            .payload_codec = .unit,
            .result_codec = .string,
            .plan_op_ordinal = 0,
        }},
    }};

    const encoded = try encodeProgramPlan(allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &capabilities,
    });
    defer allocator.free(encoded);

    patchFunctionValueCodec(encoded, 1, .i32);
    for (0..8) |_| {
        try std.testing.expectError(error.InvalidRequiredSection, decode(allocator, encoded));
    }
}

test "ArtifactV1 decode rejects directory sections whose checked bounds overflow" {
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.directory_overflow",
        .ir_hash = 0xae,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };
    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = buildFingerprintFromSeed("artifact-directory-overflow"),
        .capabilities = &.{},
    });
    defer std.testing.allocator.free(encoded);

    patchDirectoryEntryBounds(encoded, .string_table, std.math.maxInt(u64), 16);
    try std.testing.expectError(error.InvalidDirectoryBounds, decode(std.testing.allocator, encoded));
}

test "ArtifactV1 decode rejects overlapping directory sections" {
    const plan: program_plan.ProgramPlan = .{
        .label = "artifact.directory_overlap",
        .ir_hash = 0xaf,
        .entry_index = 0,
        .functions = &.{.{
            .symbol_name = "entry",
            .value_codec = .unit,
            .parameter_count = 0,
            .first_requirement = 0,
            .requirement_count = 0,
            .first_output = 0,
            .output_count = 0,
            .first_local = 0,
            .local_count = 0,
            .first_block = 0,
            .entry_block = 0,
            .block_count = 1,
            .first_instruction = 0,
            .instruction_count = 0,
        }},
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .call_args = &.{},
        .blocks = &.{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }},
        .terminators = &.{.{ .kind = .return_unit }},
        .instructions = &.{},
    };
    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = buildFingerprintFromSeed("artifact-directory-overlap"),
        .capabilities = &.{},
    });
    defer std.testing.allocator.free(encoded);

    patchDirectoryEntryBounds(encoded, .requirement_table, sectionPayloadOffset(encoded, .string_table), 0);
    try std.testing.expectError(error.InvalidDirectoryBounds, decode(std.testing.allocator, encoded));
}
