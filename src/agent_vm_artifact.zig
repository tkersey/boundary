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
    durable_state = 3,
    model = 1,
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
    global_op_name: []const u8,
    payload_codec: CapabilityCodecV1,
    result_codec: CapabilityCodecV1,
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

/// Public in-memory representation of one decoded ArtifactV1 payload.
pub const ArtifactV1 = struct {
    semantic_ir_hash64: u64,
    artifact_hash_blake3_256: [32]u8,
    build_fingerprint_blake3_256: [32]u8,
    entry_function_index: u16,
    capabilities: []CapabilityV1,
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
    pub fn validate(self: @This()) anyerror!void {
        try validateManifest(self.build_fingerprint_blake3_256, self.capabilities);
        const plan = try self.toProgramPlan(std.heap.page_allocator);
        defer deepFreeProgramPlan(std.heap.page_allocator, plan);
        try plan.validate();
    }

    /// Rebuild one runtime-owned ProgramPlan from this artifact payload.
    pub fn toProgramPlan(self: @This(), allocator: std.mem.Allocator) anyerror!program_plan.ProgramPlan {
        return .{
            .label = try allocator.dupe(u8, "artifact_v1"),
            .ir_hash = self.semantic_ir_hash64,
            .entry_index = self.entry_function_index,
            .functions = try deepCloneFunctionPlans(allocator, self.functions),
            .requirements = try deepCloneRequirementPlans(allocator, self.requirements),
            .ops = try deepCloneOpPlans(allocator, self.ops),
            .outputs = try deepCloneOutputPlans(allocator, self.outputs),
            .locals = try allocator.dupe(program_plan.LocalPlan, self.locals),
            .call_args = try allocator.dupe(u16, self.call_args),
            .blocks = try allocator.dupe(program_plan.BlockPlan, self.blocks),
            .terminators = try allocator.dupe(program_plan.Terminator, self.terminators),
            .instructions = try deepCloneInstructions(allocator, self.instructions),
        };
    }

    /// Release all allocator-owned memory held by this artifact.
    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        deepFreeCapabilities(allocator, self.capabilities);
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
    DuplicateCapabilityId,
    DuplicateCapabilityOpId,
    DuplicateDirectorySection,
    InvalidDirectoryBounds,
    InvalidEntryFunctionIndex,
    InvalidHashKind,
    InvalidRequiredSection,
    NonZeroReserved,
    StringRefOutOfBounds,
    UnsupportedVersion,
    ArtifactHashMismatch,
};

/// Build one exact-build fingerprint from an arbitrary seed string.
pub fn buildFingerprintFromSeed(seed: []const u8) [32]u8 {
    var digest = std.mem.zeroes([32]u8);
    std.crypto.hash.Blake3.hash(seed, &digest, .{});
    return digest;
}

/// Map one ProgramPlan codec into the external capability codec surface.
pub fn mapPlanCodecToCapabilityCodec(codec: program_plan.ValueCodec) CapabilityCodecV1 {
    return switch (codec) {
        .unit => .unit,
        .bool => .bool,
        .i32 => .i32,
        .string => .string,
        .string_list => .data_value,
        .usize => .i32,
    };
}

/// Derive one default tool capability manifest from ProgramPlan requirements.
pub fn deriveToolCapabilitiesFromPlan(
    allocator: std.mem.Allocator,
    plan: program_plan.ProgramPlan,
) anyerror![]CapabilityV1 {
    const capabilities = try allocator.alloc(CapabilityV1, plan.requirements.len);
    errdefer allocator.free(capabilities);

    for (plan.requirements, 0..) |requirement, index| {
        const label = try std.fmt.allocPrint(allocator, "generated/{s}@v1", .{requirement.label});
        errdefer allocator.free(label);
        const ops = try allocator.alloc(CapabilityOpV1, requirement.op_count);
        errdefer allocator.free(ops);
        const op_start = requirement.first_op;
        const op_end = op_start + requirement.op_count;
        for (plan.ops[op_start..op_end], 0..) |op, op_index| {
            ops[op_index] = .{
                .capability_id = @intCast(index),
                .op_id = @intCast(op_index),
                .global_op_name = try allocator.dupe(u8, "tool.call"),
                .payload_codec = mapPlanCodecToCapabilityCodec(op.payload_codec),
                .result_codec = mapPlanCodecToCapabilityCodec(op.resume_codec),
            };
        }
        capabilities[index] = .{
            .capability_id = @intCast(index),
            .kind = .tool,
            .required = true,
            .label = label,
            .ops = ops,
        };
    }
    return capabilities;
}

/// Encode one validated ProgramPlan into canonical ArtifactV1 bytes.
pub fn encodeProgramPlan(
    allocator: std.mem.Allocator,
    plan: program_plan.ProgramPlan,
    manifest: CapabilityManifestV1,
) anyerror![]u8 {
    try plan.validate();
    try validateManifest(manifest.build_fingerprint_blake3_256, manifest.capabilities);

    var strings = StringTable.init(allocator);
    defer strings.deinit();

    const capability_manifest = try encodeCapabilityManifest(allocator, &strings, manifest);
    defer allocator.free(capability_manifest);
    const requirement_table = try encodeRequirementTable(allocator, &strings, plan.requirements);
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
    const instruction_table = try encodeInstructionTable(allocator, &strings, plan.instructions);
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

    const header_len: usize = 72;
    const directory_entry_len: usize = 32;
    const directory_offset = header_len;
    const payload_offset_base = directory_offset + directory_entry_len * payloads.len;

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

    try out.appendSlice(allocator, "SFTARTV1");
    try appendU16(&out, allocator, @intCast(header_len));
    try appendU16(&out, allocator, 1);
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
    if (bytes.len < 72) return error.InvalidDirectoryBounds;
    if (!std.mem.eql(u8, bytes[0..8], "SFTARTV1")) return error.BadMagic;
    if (readU16(bytes, 8) != 72) return error.UnsupportedVersion;
    if (readU16(bytes, 10) != 1) return error.UnsupportedVersion;
    const directory_offset = readU64(bytes, 12);
    const directory_count = readU16(bytes, 20);
    const entry_index = readU16(bytes, 22);
    const ir_hash = readU64(bytes, 24);
    if (bytes[32] != @intFromEnum(HashKind.blake3_256)) return error.InvalidHashKind;
    if (bytes[33] != 0) return error.NonZeroReserved;
    for (bytes[34..40]) |byte| if (byte != 0) return error.NonZeroReserved;
    const expected_hash = bytes[40..72];

    if (directory_offset != 72) return error.InvalidDirectoryBounds;
    const directory_bytes_len = @as(usize, directory_count) * 32;
    if (directory_offset + directory_bytes_len > bytes.len) return error.InvalidDirectoryBounds;

    var hash_input = try allocator.dupe(u8, bytes);
    defer allocator.free(hash_input);
    @memset(hash_input[40..72], 0);
    var actual_hash = std.mem.zeroes([32]u8);
    std.crypto.hash.Blake3.hash(hash_input, &actual_hash, .{});
    if (!std.mem.eql(u8, expected_hash, &actual_hash)) return error.ArtifactHashMismatch;

    var required_seen = std.EnumSet(SectionId).initEmpty();
    var directories = std.ArrayList(SectionDirectoryEntryV1).empty;
    defer directories.deinit(allocator);

    var cursor: usize = @intCast(directory_offset);
    while (cursor < directory_offset + directory_bytes_len) : (cursor += 32) {
        const section_id = std.enums.fromInt(SectionId, readU16(bytes, cursor)) orelse return error.InvalidRequiredSection;
        if (required_seen.contains(section_id)) return error.DuplicateDirectorySection;
        required_seen.insert(section_id);
        const flags = readU16(bytes, cursor + 2);
        if (readU32(bytes, cursor + 4) != 0) return error.NonZeroReserved;
        const offset = readU64(bytes, cursor + 8);
        const size = readU64(bytes, cursor + 16);
        const entry_count = readU32(bytes, cursor + 24);
        if (readU32(bytes, cursor + 28) != 0) return error.NonZeroReserved;
        if (offset + size > bytes.len or offset < directory_offset + directory_bytes_len) return error.InvalidDirectoryBounds;
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
    const capability_result = try decodeCapabilityManifest(allocator, string_bytes, sectionBytes(bytes, directories.items, .capability_manifest));
    errdefer deepFreeCapabilities(allocator, capability_result.capabilities);

    var artifact = ArtifactV1{
        .semantic_ir_hash64 = ir_hash,
        .artifact_hash_blake3_256 = std.mem.zeroes([32]u8),
        .build_fingerprint_blake3_256 = capability_result.build_fingerprint_blake3_256,
        .entry_function_index = entry_index,
        .capabilities = capability_result.capabilities,
        .functions = try decodeFunctionTable(allocator, string_bytes, sectionBytes(bytes, directories.items, .function_table)),
        .requirements = try decodeRequirementTable(allocator, string_bytes, sectionBytes(bytes, directories.items, .requirement_table)),
        .ops = try decodeOpTable(allocator, string_bytes, sectionBytes(bytes, directories.items, .op_table)),
        .outputs = try decodeOutputTable(allocator, string_bytes, sectionBytes(bytes, directories.items, .output_table)),
        .locals = try decodeLocalTable(allocator, sectionBytes(bytes, directories.items, .local_table)),
        .call_args = try decodeCallArgTable(allocator, sectionBytes(bytes, directories.items, .call_arg_table)),
        .blocks = try decodeBlockTable(allocator, sectionBytes(bytes, directories.items, .block_table)),
        .terminators = try decodeTerminatorTable(allocator, sectionBytes(bytes, directories.items, .terminator_table)),
        .instructions = try decodeInstructionTable(allocator, string_bytes, sectionBytes(bytes, directories.items, .instruction_table)),
    };
    @memcpy(&artifact.artifact_hash_blake3_256, expected_hash);
    if (artifact.entry_function_index >= artifact.functions.len) return error.InvalidEntryFunctionIndex;
    try artifact.validate();
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
            try appendFmt(&out, allocator, "  op id={d} name={s} payload={s} result={s}\n", .{
                op.op_id,
                op.global_op_name,
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
        var expected_next: ?u16 = null;
        for (capability.ops, 0..) |op, op_index| {
            if (op.capability_id != capability.capability_id) return error.DuplicateCapabilityOpId;
            if (expected_next) |expected| {
                if (op.op_id != expected) return error.DuplicateCapabilityOpId;
            }
            expected_next = op.op_id + 1;
            for (capability.ops[(op_index + 1)..]) |other_op| {
                if (op.op_id == other_op.op_id) return error.DuplicateCapabilityOpId;
            }
        }
    }
}

const DecodedManifest = struct {
    build_fingerprint_blake3_256: [32]u8,
    capabilities: []CapabilityV1,
};

fn decodeCapabilityManifest(allocator: std.mem.Allocator, string_bytes: []const u8, bytes: []const u8) !DecodedManifest {
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
    errdefer allocator.free(capabilities);

    var capability_cursor: usize = 0;
    for (capabilities) |*capability| {
        const capability_id = readU16(capability_bytes, capability_cursor);
        const kind = std.enums.fromInt(CapabilityKind, capability_bytes[capability_cursor + 2]) orelse return error.UnsupportedVersion;
        const flags = capability_bytes[capability_cursor + 3];
        const label = try readStringRefDup(allocator, string_bytes, capability_bytes[capability_cursor + 4 .. capability_cursor + 12]);
        const first_op = readU16(capability_bytes, capability_cursor + 12);
        const op_count_for_capability = readU16(capability_bytes, capability_cursor + 14);
        const ops = try allocator.alloc(CapabilityOpV1, op_count_for_capability);

        var op_cursor = @as(usize, first_op) * 16;
        for (ops) |*op| {
            if (op_cursor + 16 > op_bytes.len) return error.InvalidDirectoryBounds;
            op.* = .{
                .capability_id = readU16(op_bytes, op_cursor),
                .op_id = readU16(op_bytes, op_cursor + 2),
                .global_op_name = try readStringRefDup(allocator, string_bytes, op_bytes[op_cursor + 4 .. op_cursor + 12]),
                .payload_codec = std.enums.fromInt(CapabilityCodecV1, op_bytes[op_cursor + 12]) orelse return error.UnsupportedVersion,
                .result_codec = std.enums.fromInt(CapabilityCodecV1, op_bytes[op_cursor + 13]) orelse return error.UnsupportedVersion,
            };
            if (readU16(op_bytes, op_cursor + 14) != 0) return error.NonZeroReserved;
            op_cursor += 16;
        }

        capability.* = .{
            .capability_id = capability_id,
            .kind = kind,
            .required = (flags & 0x1) != 0,
            .label = label,
            .ops = ops,
        };
        capability_cursor += 16;
    }

    try validateManifest(fingerprint, capabilities);
    return .{
        .build_fingerprint_blake3_256 = fingerprint,
        .capabilities = capabilities,
    };
}

fn encodeCapabilityManifest(allocator: std.mem.Allocator, strings: *StringTable, manifest: CapabilityManifestV1) ![]u8 {
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
            const op_name_ref = try strings.add(op.global_op_name);
            try appendU16(&out, allocator, op.capability_id);
            try appendU16(&out, allocator, op.op_id);
            try encodeStringRef(&out, allocator, op_name_ref);
            try out.append(allocator, @intFromEnum(op.payload_codec));
            try out.append(allocator, @intFromEnum(op.result_codec));
            try appendU16(&out, allocator, 0);
        }
    }
    return out.toOwnedSlice(allocator);
}

fn encodeRequirementTable(allocator: std.mem.Allocator, strings: *StringTable, requirements: []const program_plan.RequirementPlan) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    for (requirements) |requirement| {
        const label_ref = try strings.add(requirement.label);
        try encodeStringRef(&out, allocator, label_ref);
        try appendU16(&out, allocator, requirement.first_op);
        try appendU16(&out, allocator, requirement.op_count);
        try appendU32(&out, allocator, 0);
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
        try out.append(allocator, 0);
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
        try out.appendNTimes(allocator, 0, 3);
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

fn encodeInstructionTable(allocator: std.mem.Allocator, strings: *StringTable, instructions: []const program_plan.Instruction) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    for (instructions) |instruction| {
        const string_ref = try strings.add(instruction.string_literal);
        try out.append(allocator, @intFromEnum(instruction.kind));
        try out.append(allocator, 0);
        try appendU16(&out, allocator, instruction.dst);
        try appendU16(&out, allocator, instruction.operand);
        try appendU16(&out, allocator, instruction.aux);
        try encodeStringRef(&out, allocator, string_ref);
    }
    return out.toOwnedSlice(allocator);
}

fn decodeRequirementTable(allocator: std.mem.Allocator, string_bytes: []const u8, bytes: []const u8) ![]program_plan.RequirementPlan {
    if (bytes.len % 16 != 0) return error.InvalidDirectoryBounds;
    const items = try allocator.alloc(program_plan.RequirementPlan, bytes.len / 16);
    errdefer allocator.free(items);
    var cursor: usize = 0;
    for (items) |*item| {
        item.* = .{
            .label = try readStringRefDup(allocator, string_bytes, bytes[cursor .. cursor + 8]),
            .first_op = readU16(bytes, cursor + 8),
            .op_count = readU16(bytes, cursor + 10),
        };
        if (readU32(bytes, cursor + 12) != 0) return error.NonZeroReserved;
        cursor += 16;
    }
    return items;
}

fn decodeOpTable(allocator: std.mem.Allocator, string_bytes: []const u8, bytes: []const u8) ![]program_plan.OpPlan {
    if (bytes.len % 16 != 0) return error.InvalidDirectoryBounds;
    const items = try allocator.alloc(program_plan.OpPlan, bytes.len / 16);
    errdefer allocator.free(items);
    var cursor: usize = 0;
    for (items) |*item| {
        item.* = .{
            .requirement_index = readU16(bytes, cursor),
            .op_name = try readStringRefDup(allocator, string_bytes, bytes[cursor + 8 .. cursor + 16]),
            .mode = std.enums.fromInt(program_plan.ControlMode, bytes[cursor + 2]) orelse return error.UnsupportedVersion,
            .payload_codec = std.enums.fromInt(program_plan.ValueCodec, bytes[cursor + 3]) orelse return error.UnsupportedVersion,
            .resume_codec = std.enums.fromInt(program_plan.ValueCodec, bytes[cursor + 4]) orelse return error.UnsupportedVersion,
        };
        if (bytes[cursor + 5] != 0 or readU16(bytes, cursor + 6) != 0) return error.NonZeroReserved;
        cursor += 16;
    }
    return items;
}

fn decodeOutputTable(allocator: std.mem.Allocator, string_bytes: []const u8, bytes: []const u8) ![]program_plan.OutputPlan {
    if (bytes.len % 16 != 0) return error.InvalidDirectoryBounds;
    const items = try allocator.alloc(program_plan.OutputPlan, bytes.len / 16);
    errdefer allocator.free(items);
    var cursor: usize = 0;
    for (items) |*item| {
        item.* = .{
            .label = try readStringRefDup(allocator, string_bytes, bytes[cursor .. cursor + 8]),
            .codec = std.enums.fromInt(program_plan.ValueCodec, bytes[cursor + 8]) orelse return error.UnsupportedVersion,
        };
        for (bytes[cursor + 9 .. cursor + 16]) |byte| if (byte != 0) return error.NonZeroReserved;
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

fn decodeFunctionTable(allocator: std.mem.Allocator, string_bytes: []const u8, bytes: []const u8) ![]program_plan.FunctionPlan {
    if (bytes.len % 36 != 0) return error.InvalidDirectoryBounds;
    const items = try allocator.alloc(program_plan.FunctionPlan, bytes.len / 36);
    errdefer allocator.free(items);
    var cursor: usize = 0;
    for (items) |*item| {
        item.* = .{
            .symbol_name = try readStringRefDup(allocator, string_bytes, bytes[cursor .. cursor + 8]),
            .value_codec = std.enums.fromInt(program_plan.ValueCodec, bytes[cursor + 8]) orelse return error.UnsupportedVersion,
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
        for (bytes[cursor + 9 .. cursor + 12]) |byte| if (byte != 0) return error.NonZeroReserved;
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

fn decodeInstructionTable(allocator: std.mem.Allocator, string_bytes: []const u8, bytes: []const u8) ![]program_plan.Instruction {
    if (bytes.len % 16 != 0) return error.InvalidDirectoryBounds;
    const items = try allocator.alloc(program_plan.Instruction, bytes.len / 16);
    errdefer allocator.free(items);
    var cursor: usize = 0;
    for (items) |*item| {
        item.* = .{
            .kind = std.enums.fromInt(program_plan.InstructionKind, bytes[cursor]) orelse return error.UnsupportedVersion,
            .dst = readU16(bytes, cursor + 2),
            .operand = readU16(bytes, cursor + 4),
            .aux = readU16(bytes, cursor + 6),
            .string_literal = try readStringRefDup(allocator, string_bytes, bytes[cursor + 8 .. cursor + 16]),
        };
        if (bytes[cursor + 1] != 0) return error.NonZeroReserved;
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
    if (@as(usize, offset) + @as(usize, len) > string_bytes.len) return error.StringRefOutOfBounds;
    return allocator.dupe(u8, string_bytes[offset .. offset + len]);
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
    errdefer allocator.free(clone);
    for (source, 0..) |item, index| {
        clone[index] = item;
        clone[index].symbol_name = try allocator.dupe(u8, item.symbol_name);
    }
    return clone;
}

fn deepCloneRequirementPlans(allocator: std.mem.Allocator, source: []const program_plan.RequirementPlan) ![]program_plan.RequirementPlan {
    const clone = try allocator.alloc(program_plan.RequirementPlan, source.len);
    errdefer allocator.free(clone);
    for (source, 0..) |item, index| {
        clone[index] = item;
        clone[index].label = try allocator.dupe(u8, item.label);
    }
    return clone;
}

fn deepCloneOpPlans(allocator: std.mem.Allocator, source: []const program_plan.OpPlan) ![]program_plan.OpPlan {
    const clone = try allocator.alloc(program_plan.OpPlan, source.len);
    errdefer allocator.free(clone);
    for (source, 0..) |item, index| {
        clone[index] = item;
        clone[index].op_name = try allocator.dupe(u8, item.op_name);
    }
    return clone;
}

fn deepCloneOutputPlans(allocator: std.mem.Allocator, source: []const program_plan.OutputPlan) ![]program_plan.OutputPlan {
    const clone = try allocator.alloc(program_plan.OutputPlan, source.len);
    errdefer allocator.free(clone);
    for (source, 0..) |item, index| {
        clone[index] = item;
        clone[index].label = try allocator.dupe(u8, item.label);
    }
    return clone;
}

fn deepCloneInstructions(allocator: std.mem.Allocator, source: []const program_plan.Instruction) ![]program_plan.Instruction {
    const clone = try allocator.alloc(program_plan.Instruction, source.len);
    errdefer allocator.free(clone);
    for (source, 0..) |item, index| {
        clone[index] = item;
        clone[index].string_literal = try allocator.dupe(u8, item.string_literal);
    }
    return clone;
}

fn deepFreeFunctionPlans(allocator: std.mem.Allocator, items: []program_plan.FunctionPlan) void {
    for (items) |item| allocator.free(item.symbol_name);
    allocator.free(items);
}

fn deepFreeRequirementPlans(allocator: std.mem.Allocator, items: []program_plan.RequirementPlan) void {
    for (items) |item| allocator.free(item.label);
    allocator.free(items);
}

fn deepFreeOpPlans(allocator: std.mem.Allocator, items: []program_plan.OpPlan) void {
    for (items) |item| allocator.free(item.op_name);
    allocator.free(items);
}

fn deepFreeOutputPlans(allocator: std.mem.Allocator, items: []program_plan.OutputPlan) void {
    for (items) |item| allocator.free(item.label);
    allocator.free(items);
}

fn deepFreeInstructions(allocator: std.mem.Allocator, items: []program_plan.Instruction) void {
    for (items) |item| allocator.free(item.string_literal);
    allocator.free(items);
}

fn deepFreeFunctionPlansConst(allocator: std.mem.Allocator, items: []const program_plan.FunctionPlan) void {
    for (items) |item| allocator.free(item.symbol_name);
    allocator.free(@constCast(items));
}

fn deepFreeRequirementPlansConst(allocator: std.mem.Allocator, items: []const program_plan.RequirementPlan) void {
    for (items) |item| allocator.free(item.label);
    allocator.free(@constCast(items));
}

fn deepFreeOpPlansConst(allocator: std.mem.Allocator, items: []const program_plan.OpPlan) void {
    for (items) |item| allocator.free(item.op_name);
    allocator.free(@constCast(items));
}

fn deepFreeOutputPlansConst(allocator: std.mem.Allocator, items: []const program_plan.OutputPlan) void {
    for (items) |item| allocator.free(item.label);
    allocator.free(@constCast(items));
}

fn deepFreeInstructionsConst(allocator: std.mem.Allocator, items: []const program_plan.Instruction) void {
    for (items) |item| allocator.free(item.string_literal);
    allocator.free(@constCast(items));
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
    for (items) |item| {
        allocator.free(item.label);
        for (item.ops) |op| allocator.free(op.global_op_name);
        allocator.free(item.ops);
    }
    allocator.free(items);
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
        .label = "tooling",
        .ops = &.{.{
            .capability_id = 1,
            .op_id = 0,
            .global_op_name = "tool.call",
            .payload_codec = .string,
            .result_codec = .string,
        }},
    }};

    const encoded = try encodeProgramPlan(std.testing.allocator, plan, .{
        .build_fingerprint_blake3_256 = build_fingerprint,
        .capabilities = &capabilities,
    });
    defer std.testing.allocator.free(encoded);

    var decoded = try decode(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u64, plan.ir_hash), decoded.semantic_ir_hash64);
    try std.testing.expectEqual(@as(usize, 1), decoded.capabilities.len);
    try std.testing.expectEqualStrings("tooling", decoded.capabilities[0].label);
    try std.testing.expectEqualStrings("tool.call", decoded.capabilities[0].ops[0].global_op_name);
    try std.testing.expectEqual(@as(usize, 1), decoded.functions.len);
    try std.testing.expectEqualStrings("entry", decoded.functions[0].symbol_name);
    try std.testing.expectEqual(@as(usize, 1), decoded.instructions.len);
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
    try std.testing.expect(std.mem.indexOf(u8, disasm, "ArtifactV1 ir_hash=145") != null);
    try std.testing.expect(std.mem.indexOf(u8, disasm, "functions=1") != null);
}
