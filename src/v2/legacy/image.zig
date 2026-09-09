// Frozen BPI1 data/validation from Boundary 1.8.2, commit
// 999e936c4a865cd31948b52b2af2baeacf84c9f1. MIT license. No evaluator.
const dynamic_value_v1 = @import("value.zig");
const program_semantics_v1 = @import("contract.zig");
const std = @import("std");

pub const magic = "ABL_BPI1".*;
pub const image_format_version: u16 = 1;
pub const evaluator_semantics_v1: u16 = 1;
pub const evaluator_semantics_v2: u16 = 2;
pub const evaluator_semantics_v3: u16 = 3;
pub const evaluator_semantics_version: u16 = evaluator_semantics_v1;
pub const fixed_prefix_length: u32 = 76;
pub const section_count: u32 = 10;
pub const section_descriptor_length: u32 = 24;
pub const maximum_catalog_entries: u32 = 1280;
pub const maximum_schema_entries: u32 = 1024;
pub const maximum_constant_entries: u32 = 1024;
pub const maximum_effect_entries: u32 = 128;
pub const maximum_function_entries: u32 = 128;
pub const maximum_segment_entries: u32 = 192;
pub const maximum_constructor_entries: u32 = 256;
pub const maximum_transition_entries: u32 = 1024;
pub const segment_prefix_length: u32 = 16;
pub const header_length: u32 = fixed_prefix_length +
    section_count * section_descriptor_length;

pub const Error = error{
    InvalidImage,
    InvalidMagic,
    UnsupportedImageVersion,
    UnsupportedEvaluatorSemantics,
    UnknownFlags,
    InvalidHeaderLength,
    LengthOverflow,
    LengthMismatch,
    InvalidSectionCount,
    InvalidSectionOrder,
    InvalidSectionOffset,
    InvalidSectionLength,
    TrailingBytes,
    LimitExceeded,
    InvalidUtf8,
    InvalidSchema,
    InvalidRoot,
    InvalidFailureMap,
    DuplicateFailureName,
    DuplicateFailureTag,
    InvalidConstant,
    DuplicateConstant,
    InvalidEffect,
    DuplicateEffectIdentity,
    InvalidValue,
    InvalidFunction,
    InvalidSegment,
    InvalidInstruction,
    InvalidTerminator,
    InvalidConstructor,
    InvalidInvariant,
    InvalidTransition,
    UnreachableEntry,
    ScratchRequirementMismatch,
    DigestMismatch,
    ProgramTransitionDigestMismatch,
};

pub const SectionKind = enum(u16) {
    roots = 1,
    schemas = 2,
    failures = 3,
    constants = 4,
    effects = 5,
    values = 6,
    functions = 7,
    segments = 8,
    constructors = 9,
    entry_transitions = 10,
};

pub const Section = struct {
    kind: SectionKind,
    offset: u64,
    length: u64,

    pub fn bytes(self: Section, image: []const u8) []const u8 {
        const start: usize = @intCast(self.offset);
        const end: usize = @intCast(self.offset + self.length);
        return image[start..end];
    }
};

pub const Header = struct {
    evaluator_semantics_version: u16,
    total_length: u64,
    program_transition_digest: [32]u8,
    maximum_kernel_scratch_bytes: u64,
    maximum_single_value_bytes: u32,
};

pub const ValidatedEnvelope = struct {
    image: []const u8,
    header: Header,
    sections: [section_count]Section,

    pub fn section(self: *const ValidatedEnvelope, kind: SectionKind) []const u8 {
        return self.sections[@intFromEnum(kind) - 1].bytes(self.image);
    }
};

pub const ValidationWorkspace = struct {
    schema_nodes: [maximum_schema_entries]dynamic_value_v1.NodeIndex = undefined,
    value_tasks: [2048]dynamic_value_v1.ValueTask = undefined,
    schema_hash_tasks: [8192]dynamic_value_v1.SchemaHashTask = undefined,
    invariant_instruction: [16 + 2 * 1024]u8 = undefined,
    invariant_result: []u8 = &.{},
    catalog_digests: [maximum_catalog_entries][32]u8 = undefined,
    catalog_keys: [maximum_catalog_entries]u32 = undefined,
    catalog_offsets: [maximum_catalog_entries]u32 = undefined,
    catalog_lengths: [maximum_catalog_entries]u32 = undefined,
    constant_used: [maximum_catalog_entries]bool = undefined,
    value_defined: [maximum_catalog_entries]bool = undefined,
    canonical_failure_constant: [maximum_catalog_entries]bool = undefined,
    authored_failure_operand: [maximum_catalog_entries]bool = undefined,
    canonical_schema_seen: [maximum_catalog_entries]bool = undefined,
    canonical_schema_stack: [2048]SchemaOrderTask = undefined,
};

pub const SchemaOrderTask = struct {
    schema_id: u32,
    next_child: u32,
};

pub const Catalogs = struct {
    envelope: ValidatedEnvelope,
    schemas: dynamic_value_v1.Table,
    initial_args_schema_id: u32,
    result_schema_id: u32,
    failure_schema_id: u32,
    value_count: u32,
    function_count: u32,
    effect_count: u32,
    constant_count: u32,
    entry_segment_id: u16,
    initial_constructor_id: u32,
    values_section: []const u8,
    functions_section: []const u8,
    entry_parameter_count: u16,
    entry_parameter_value_id: u16,

    pub fn valueSchemaId(self: Catalogs, value: u16) Error!u32 {
        if (value >= self.value_count) return error.InvalidValue;
        return readInt(u32, self.values_section, 4 + @as(usize, value) * 4);
    }
};

pub const ValidatedImage = struct {
    catalogs: Catalogs,
    segment_count: u32,
    constructor_count: u32,
    artifact_sha256: [32]u8,
};

/// Internal effect descriptor used by fixed image evaluators.
/// The package root intentionally does not expose this byte-level surface.
pub const EvaluatorEffect = struct {
    ordinal: u32,
    semantic_identity: []const u8,
    payload_schema: u32,
    resume_schema: u32,
    semantic_digest: [32]u8,
    ordinal_digest: [32]u8,
};

/// Borrow one validated segment record for an internal evaluator.
pub fn evaluatorSegmentRecord(
    image: ValidatedImage,
    target: u16,
) Error![]const u8 {
    return imageSegmentRecord(image.catalogs, target);
}

/// Borrow one validated constructor record for an internal evaluator.
pub fn evaluatorConstructorRecord(
    image: ValidatedImage,
    target: u32,
) Error![]const u8 {
    return imageConstructorRecord(image.catalogs, target);
}

/// Resolve one validated edge to its canonical continuation constructor.
pub fn evaluatorTransitionConstructor(
    image: ValidatedImage,
    source: u16,
    edge_kind: u8,
    target: u16,
) Error!u32 {
    return transitionConstructorId(image.catalogs, source, edge_kind, target);
}

/// Locate the unique validated suspension constructor of one semantic kind.
pub fn evaluatorSuspensionConstructor(
    image: ValidatedImage,
    source_segment: u16,
    constructor_kind: u8,
) Error!u32 {
    for (0..image.constructor_count) |candidate| {
        const constructor = try imageConstructorRecord(
            image.catalogs,
            @intCast(candidate),
        );
        if (constructor[8] == constructor_kind and
            constructor[9] == 2 and
            readInt(u16, constructor, 12) == source_segment)
        {
            return @intCast(candidate);
        }
    }
    return error.InvalidConstructor;
}

/// Return the terminator offset of one already validated segment record.
pub fn evaluatorSegmentTerminator(segment: []const u8) usize {
    return imageSegmentTerminator(segment);
}

/// Borrow one validated residual-effect descriptor by dense ordinal.
pub fn evaluatorEffect(
    image: ValidatedImage,
    target: u32,
) Error!EvaluatorEffect {
    const bytes = image.catalogs.envelope.section(.effects);
    var cursor: usize = 4;
    for (0..image.catalogs.effect_count) |ordinal| {
        const encoded_ordinal = readInt(u32, bytes, cursor);
        cursor += 4;
        const identity_length = readInt(u32, bytes, cursor);
        cursor += 4;
        const identity_end = cursor + identity_length;
        const identity = bytes[cursor..identity_end];
        cursor = identity_end;
        const payload_schema = readInt(u32, bytes, cursor);
        const resume_schema = readInt(u32, bytes, cursor + 4);
        cursor += 12;
        const semantic_digest = bytes[cursor..][0..32].*;
        cursor += 32;
        const ordinal_digest = bytes[cursor..][0..32].*;
        cursor += 32;
        if (ordinal == target) return .{
            .ordinal = encoded_ordinal,
            .semantic_identity = identity,
            .payload_schema = payload_schema,
            .resume_schema = resume_schema,
            .semantic_digest = semantic_digest,
            .ordinal_digest = ordinal_digest,
        };
    }
    return error.InvalidEffect;
}

pub fn validateEnvelope(image: []const u8) Error!ValidatedEnvelope {
    if (image.len < header_length) return error.InvalidHeaderLength;
    if (!std.mem.eql(u8, image[0..magic.len], &magic)) {
        return error.InvalidMagic;
    }
    if (readInt(u16, image, 8) != image_format_version) {
        return error.UnsupportedImageVersion;
    }
    const evaluator_version = readInt(u16, image, 10);
    if (evaluator_version != evaluator_semantics_v1 and
        evaluator_version != evaluator_semantics_v2 and
        evaluator_version != evaluator_semantics_v3)
    {
        return error.UnsupportedEvaluatorSemantics;
    }
    if (readInt(u32, image, 12) != 0) return error.UnknownFlags;
    if (readInt(u32, image, 16) != header_length) {
        return error.InvalidHeaderLength;
    }
    const declared_total = readInt(u64, image, 24);
    const actual_total = std.math.cast(u64, image.len) orelse
        return error.LengthOverflow;
    if (declared_total < header_length) return error.LengthMismatch;
    if (declared_total < actual_total) return error.TrailingBytes;
    if (declared_total > actual_total) return error.LengthMismatch;
    if (readInt(u32, image, 20) != section_count) {
        return error.InvalidSectionCount;
    }

    var sections: [section_count]Section = undefined;
    var expected_offset: u64 = header_length;
    for (0..section_count) |index| {
        const descriptor_offset = fixed_prefix_length +
            index * section_descriptor_length;
        const raw_kind = readInt(u16, image, descriptor_offset);
        const expected_kind: u16 = @intCast(index + 1);
        if (raw_kind != expected_kind) return error.InvalidSectionOrder;
        if (readInt(u16, image, descriptor_offset + 2) != 1 or
            readInt(u32, image, descriptor_offset + 4) != 0)
        {
            return error.UnknownFlags;
        }
        const offset = readInt(u64, image, descriptor_offset + 8);
        const length = readInt(u64, image, descriptor_offset + 16);
        if (offset != expected_offset) return error.InvalidSectionOffset;
        expected_offset = std.math.add(u64, offset, length) catch
            return error.InvalidSectionLength;
        if (expected_offset > declared_total) {
            return error.InvalidSectionLength;
        }
        sections[index] = .{
            .kind = @enumFromInt(raw_kind),
            .offset = offset,
            .length = length,
        };
    }
    if (expected_offset != declared_total) return error.InvalidSectionLength;

    return .{
        .image = image,
        .header = .{
            .evaluator_semantics_version = evaluator_version,
            .total_length = declared_total,
            .program_transition_digest = image[32..64].*,
            .maximum_kernel_scratch_bytes = readInt(u64, image, 64),
            .maximum_single_value_bytes = readInt(u32, image, 72),
        },
        .sections = sections,
    };
}

/// Validate the BPI1 type and static catalog frontier before executable graph
/// validation. No image instruction or effect is evaluated.
pub fn validateCatalogs(
    image: []const u8,
    workspace: *ValidationWorkspace,
) Error!Catalogs {
    if (rangesOverlap(image, std.mem.asBytes(workspace))) {
        return error.InvalidImage;
    }
    const envelope = try validateEnvelope(image);
    const schemas = dynamic_value_v1.validateSchemaSection(
        envelope.section(.schemas),
        &workspace.schema_nodes,
    ) catch |err| return mapDynamicSchemaError(err);
    if (envelope.header.maximum_single_value_bytes !=
        try maximumSingleValueBytes(schemas))
    {
        return error.ScratchRequirementMismatch;
    }
    const roots = try validateRoots(envelope.section(.roots), schemas);
    try validateFailures(
        envelope.section(.failures),
        schemas,
        roots.failure_schema_id,
        workspace,
    );
    const constant_count = try validateConstants(
        envelope.section(.constants),
        schemas,
        &workspace.value_tasks,
        workspace,
    );
    const effect_count = try validateEffects(
        envelope.section(.effects),
        schemas,
        &workspace.schema_hash_tasks,
        workspace,
    );
    const values = try validateValues(envelope.section(.values), schemas);
    if (envelope.header.maximum_kernel_scratch_bytes !=
        try deriveKernelScratch(schemas, values))
    {
        return error.ScratchRequirementMismatch;
    }
    if (roots.entry_parameter_count == 1) {
        if (roots.entry_parameter_value_id >= values.count or
            values.schemaId(roots.entry_parameter_value_id) !=
                roots.initial_args_schema_id)
        {
            return error.InvalidRoot;
        }
    }
    const function_count = try validateFunctions(
        envelope.section(.functions),
        schemas,
    );
    return .{
        .envelope = envelope,
        .schemas = schemas,
        .initial_args_schema_id = roots.initial_args_schema_id,
        .result_schema_id = roots.result_schema_id,
        .failure_schema_id = roots.failure_schema_id,
        .value_count = values.count,
        .function_count = function_count,
        .effect_count = effect_count,
        .constant_count = constant_count,
        .entry_segment_id = roots.entry_segment_id,
        .initial_constructor_id = roots.initial_constructor_id,
        .values_section = envelope.section(.values),
        .functions_section = envelope.section(.functions),
        .entry_parameter_count = roots.entry_parameter_count,
        .entry_parameter_value_id = roots.entry_parameter_value_id,
    };
}

pub fn validateImage(
    image: []const u8,
    workspace: *ValidationWorkspace,
) Error!ValidatedImage {
    const catalogs = try validateCatalogs(image, workspace);
    try validateCanonicalSchemaOrder(catalogs, workspace);
    @memset(workspace.constant_used[0..catalogs.constant_count], false);
    @memset(workspace.value_defined[0..catalogs.value_count], false);
    @memset(
        workspace.canonical_failure_constant[0..catalogs.value_count],
        false,
    );
    @memset(
        workspace.authored_failure_operand[0..catalogs.value_count],
        false,
    );
    var next_constant: u32 = 0;
    var next_value: u32 = 0;
    var v3_operation_used = false;
    const segment_count = try validateSegments(
        catalogs,
        &workspace.constant_used,
        &next_constant,
        &workspace.value_defined,
        &workspace.canonical_failure_constant,
        &workspace.authored_failure_operand,
        &next_value,
        &v3_operation_used,
    );
    var authored_failure_used = false;
    for (workspace.authored_failure_operand[0..catalogs.value_count], 0..) |used, value| {
        if (!used) continue;
        authored_failure_used = true;
        if (!workspace.canonical_failure_constant[value]) {
            return error.InvalidFailureMap;
        }
    }
    if (catalogs.envelope.header.evaluator_semantics_version ==
        evaluator_semantics_v2 and !authored_failure_used)
    {
        return error.InvalidFailureMap;
    }
    if (catalogs.envelope.header.evaluator_semantics_version ==
        evaluator_semantics_v3 and !v3_operation_used)
    {
        return error.InvalidInstruction;
    }
    for (workspace.constant_used[0..catalogs.constant_count]) |used| {
        if (!used) return error.InvalidConstant;
    }
    for (workspace.value_defined[0..catalogs.value_count]) |defined| {
        if (!defined) return error.InvalidValue;
    }
    if (next_value != catalogs.value_count) return error.InvalidValue;
    try validateCatalogUse(catalogs, segment_count);
    try validateFunctionEntries(catalogs, segment_count);
    const constructor_count = try validateConstructors(
        catalogs,
        segment_count,
    );
    try validateTransitions(catalogs, segment_count, constructor_count);
    if (catalogs.entry_segment_id >= segment_count or
        catalogs.initial_constructor_id >= constructor_count)
    {
        return error.UnreachableEntry;
    }
    try validateInitialTuple(catalogs);
    try validateConstructorExecution(catalogs, segment_count, constructor_count);
    try validateDirectBranchInvariants(catalogs);
    try validateConsumedParametersRetained(catalogs, segment_count);
    try validateSegmentReachability(catalogs, segment_count);
    const program_digest = try computeProgramTransitionDigest(
        catalogs,
        &workspace.schema_hash_tasks,
    );
    if (!std.mem.eql(
        u8,
        &program_digest,
        &catalogs.envelope.header.program_transition_digest,
    )) {
        return error.ProgramTransitionDigestMismatch;
    }
    return .{
        .catalogs = catalogs,
        .segment_count = segment_count,
        .constructor_count = constructor_count,
        .artifact_sha256 = imageArtifactDigest(image),
    };
}

fn validateCanonicalSchemaOrder(
    catalogs: Catalogs,
    workspace: *ValidationWorkspace,
) Error!void {
    @memset(
        workspace.canonical_schema_seen[0..catalogs.schemas.count()],
        false,
    );
    var next_schema: u32 = 0;
    try visitCanonicalSchema(
        catalogs.schemas,
        catalogs.initial_args_schema_id,
        workspace,
        &next_schema,
    );
    try visitCanonicalSchema(
        catalogs.schemas,
        catalogs.result_schema_id,
        workspace,
        &next_schema,
    );
    try visitCanonicalSchema(
        catalogs.schemas,
        catalogs.failure_schema_id,
        workspace,
        &next_schema,
    );

    const effects = catalogs.envelope.section(.effects);
    var effect_cursor: usize = 4;
    for (0..catalogs.effect_count) |_| {
        effect_cursor += 4;
        const identity_length = readInt(u32, effects, effect_cursor);
        effect_cursor += 4 + identity_length;
        try visitCanonicalSchema(
            catalogs.schemas,
            readInt(u32, effects, effect_cursor),
            workspace,
            &next_schema,
        );
        try visitCanonicalSchema(
            catalogs.schemas,
            readInt(u32, effects, effect_cursor + 4),
            workspace,
            &next_schema,
        );
        effect_cursor += 8 + 4 + 64;
    }
    for (0..catalogs.value_count) |value| {
        try visitCanonicalSchema(
            catalogs.schemas,
            try catalogs.valueSchemaId(@intCast(value)),
            workspace,
            &next_schema,
        );
    }
    const functions = catalogs.functions_section;
    for (0..catalogs.function_count) |function| {
        try visitCanonicalSchema(
            catalogs.schemas,
            readInt(u32, functions, 4 + function * 8 + 4),
            workspace,
            &next_schema,
        );
    }
    const constants = catalogs.envelope.section(.constants);
    var constant_cursor: usize = 4;
    for (0..catalogs.constant_count) |_| {
        try visitCanonicalSchema(
            catalogs.schemas,
            readInt(u32, constants, constant_cursor),
            workspace,
            &next_schema,
        );
        const length = readInt(u32, constants, constant_cursor + 4);
        constant_cursor += 8 + length;
    }
    if (next_schema != catalogs.schemas.count()) return error.InvalidSchema;
}

fn visitCanonicalSchema(
    schemas: dynamic_value_v1.Table,
    root: u32,
    workspace: *ValidationWorkspace,
    next_schema: *u32,
) Error!void {
    var stack_length: usize = 0;
    try pushSchemaOrderTask(workspace, &stack_length, root);
    while (stack_length != 0) {
        const task = &workspace.canonical_schema_stack[stack_length - 1];
        if (workspace.canonical_schema_seen[task.schema_id]) {
            stack_length -= 1;
            continue;
        }
        const node = schemas.node(task.schema_id) catch return error.InvalidSchema;
        const child_count = schemaChildCount(node);
        if (task.next_child < child_count) {
            const child = schemaChildId(node, task.next_child);
            task.next_child += 1;
            if (!workspace.canonical_schema_seen[child]) {
                try pushSchemaOrderTask(workspace, &stack_length, child);
            }
            continue;
        }
        if (task.schema_id != next_schema.*) return error.InvalidSchema;
        workspace.canonical_schema_seen[task.schema_id] = true;
        next_schema.* += 1;
        stack_length -= 1;
    }
}

fn schemaChildCount(node: dynamic_value_v1.Node) u32 {
    return switch (node.kind) {
        .array, .vector, .optional => 1,
        .product => readInt(u32, node.payload, 0),
        .sum => 1 + readInt(u32, node.payload, 4),
        else => 0,
    };
}

fn schemaChildId(node: dynamic_value_v1.Node, index: u32) u32 {
    return switch (node.kind) {
        .array, .vector => readInt(u32, node.payload, 4),
        .optional => readInt(u32, node.payload, 0),
        .product => readInt(u32, node.payload, 4 + @as(usize, index) * 4),
        .sum => if (index == 0)
            readInt(u32, node.payload, 0)
        else
            readInt(u32, node.payload, 12 + @as(usize, index - 1) * 8),
        else => unreachable,
    };
}

fn pushSchemaOrderTask(
    workspace: *ValidationWorkspace,
    stack_length: *usize,
    schema_id: u32,
) Error!void {
    if (schema_id >= workspace.canonical_schema_seen.len or
        stack_length.* == workspace.canonical_schema_stack.len)
    {
        return error.InvalidSchema;
    }
    workspace.canonical_schema_stack[stack_length.*] = .{
        .schema_id = schema_id,
        .next_child = 0,
    };
    stack_length.* += 1;
}

/// Re-encode a fully validated canonical image into caller-owned storage.
/// Structural validation has already rejected alternate encodings.
pub fn reencodeValidated(
    image: ValidatedImage,
    output: []u8,
) Error!usize {
    const source = image.catalogs.envelope.image;
    if (output.len < source.len) return error.LengthMismatch;
    if (!std.mem.eql(
        u8,
        &image.artifact_sha256,
        &imageArtifactDigest(source),
    )) return error.InvalidImage;
    const target = output[0..source.len];
    if (source.ptr == target.ptr) return source.len;
    if (rangesOverlap(source, target)) return error.InvalidImage;
    @memcpy(target, source);
    return source.len;
}

fn imageArtifactDigest(bytes: []const u8) [32]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return digest;
}

const Roots = struct {
    initial_args_schema_id: u32,
    result_schema_id: u32,
    failure_schema_id: u32,
    entry_parameter_count: u16,
    entry_parameter_value_id: u16,
    entry_segment_id: u16,
    initial_constructor_id: u32,
};

fn validateRoots(bytes: []const u8, schemas: dynamic_value_v1.Table) Error!Roots {
    if (bytes.len != 28) return error.InvalidRoot;
    const initial_args = readInt(u32, bytes, 0);
    const result = readInt(u32, bytes, 4);
    const failure = readInt(u32, bytes, 8);
    _ = schemas.node(initial_args) catch return error.InvalidRoot;
    _ = schemas.node(result) catch return error.InvalidRoot;
    _ = schemas.node(failure) catch return error.InvalidRoot;
    const parameter_count = readInt(u16, bytes, 14);
    if (parameter_count > 1 or readInt(u16, bytes, 20) != 0 or
        readInt(u16, bytes, 22) != 0 or readInt(u16, bytes, 26) != 0)
    {
        return error.InvalidRoot;
    }
    const parameter_value = readInt(u16, bytes, 24);
    if (parameter_count == 0) {
        if (parameter_value != std.math.maxInt(u16) or
            (schemas.node(initial_args) catch return error.InvalidRoot).kind !=
                .unit)
        {
            return error.InvalidRoot;
        }
    } else if (parameter_value == std.math.maxInt(u16)) {
        return error.InvalidRoot;
    }
    return .{
        .initial_args_schema_id = initial_args,
        .result_schema_id = result,
        .failure_schema_id = failure,
        .entry_parameter_count = parameter_count,
        .entry_parameter_value_id = parameter_value,
        .entry_segment_id = readInt(u16, bytes, 12),
        .initial_constructor_id = readInt(u32, bytes, 16),
    };
}

fn validateFailures(
    bytes: []const u8,
    schemas: dynamic_value_v1.Table,
    failure_schema_id: u32,
    workspace: *ValidationWorkspace,
) Error!void {
    if (bytes.len < 4) return error.InvalidFailureMap;
    const failure_schema = schemas.node(failure_schema_id) catch
        return error.InvalidFailureMap;
    if (failure_schema.kind != .@"enum") return error.InvalidFailureMap;
    const count = readInt(u32, bytes, 0);
    if (count > maximum_catalog_entries or
        count != readInt(u32, failure_schema.payload, 0))
    {
        return error.InvalidFailureMap;
    }
    var cursor: usize = 4;
    for (0..count) |index| {
        if (bytes.len - cursor < 8) return error.InvalidFailureMap;
        const tag = readInt(u32, bytes, cursor);
        if (tag != readInt(u32, failure_schema.payload, 4 + index * 4)) {
            return error.InvalidFailureMap;
        }
        cursor += 4;
        const name_length = readInt(u32, bytes, cursor);
        cursor += 4;
        const name = takeCatalogSlice(bytes, &cursor, name_length) catch
            return error.InvalidFailureMap;
        if (name.len == 0 or !std.unicode.utf8ValidateSlice(name)) {
            return error.InvalidUtf8;
        }
        std.crypto.hash.sha2.Sha256.hash(
            name,
            &workspace.catalog_digests[index],
            .{},
        );
        for (0..index) |prior| {
            if (workspace.catalog_keys[prior] == tag) {
                return error.DuplicateFailureTag;
            }
            const prior_offset: usize = workspace.catalog_offsets[prior];
            const prior_length: usize = workspace.catalog_lengths[prior];
            if (std.mem.eql(
                u8,
                &workspace.catalog_digests[prior],
                &workspace.catalog_digests[index],
            ) and std.mem.eql(
                u8,
                bytes[prior_offset..][0..prior_length],
                name,
            )) {
                return error.DuplicateFailureName;
            }
        }
        workspace.catalog_keys[index] = tag;
        workspace.catalog_offsets[index] = @intCast(cursor - name.len);
        workspace.catalog_lengths[index] = @intCast(name.len);
    }
    if (cursor != bytes.len) return error.InvalidFailureMap;
}

fn validateConstants(
    bytes: []const u8,
    schemas: dynamic_value_v1.Table,
    tasks: []dynamic_value_v1.ValueTask,
    workspace: *ValidationWorkspace,
) Error!u32 {
    if (bytes.len < 4) return error.InvalidConstant;
    const count = readInt(u32, bytes, 0);
    if (count > maximum_constant_entries) return error.InvalidConstant;
    var cursor: usize = 4;
    for (0..count) |index| {
        if (bytes.len - cursor < 8) return error.InvalidConstant;
        const record_start = cursor;
        const schema_id = readInt(u32, bytes, cursor);
        cursor += 4;
        const length = readInt(u32, bytes, cursor);
        cursor += 4;
        const value = takeCatalogSlice(bytes, &cursor, length) catch
            return error.InvalidConstant;
        dynamic_value_v1.validateValue(schemas, schema_id, value, tasks) catch
            return error.InvalidConstant;
        std.crypto.hash.sha2.Sha256.hash(
            bytes[record_start..cursor],
            &workspace.catalog_digests[index],
            .{},
        );
        for (0..index) |prior| {
            const prior_offset: usize = workspace.catalog_offsets[prior];
            const prior_length: usize = workspace.catalog_lengths[prior];
            if (std.mem.eql(
                u8,
                &workspace.catalog_digests[prior],
                &workspace.catalog_digests[index],
            ) and std.mem.eql(
                u8,
                bytes[prior_offset..][0..prior_length],
                bytes[record_start..cursor],
            )) {
                return error.DuplicateConstant;
            }
        }
        workspace.catalog_offsets[index] = @intCast(record_start);
        workspace.catalog_lengths[index] = @intCast(cursor - record_start);
    }
    if (cursor != bytes.len) return error.InvalidConstant;
    return count;
}

fn validateEffects(
    bytes: []const u8,
    schemas: dynamic_value_v1.Table,
    hash_tasks: []dynamic_value_v1.SchemaHashTask,
    workspace: *ValidationWorkspace,
) Error!u32 {
    if (bytes.len < 4) return error.InvalidEffect;
    const count = readInt(u32, bytes, 0);
    if (count > maximum_effect_entries) return error.InvalidEffect;
    var cursor: usize = 4;
    for (0..count) |ordinal| {
        if (bytes.len - cursor < 84) return error.InvalidEffect;
        if (readInt(u32, bytes, cursor) != ordinal) return error.InvalidEffect;
        cursor += 4;
        const identity_length = readInt(u32, bytes, cursor);
        cursor += 4;
        if (identity_length > bytes.len - cursor or
            bytes.len - cursor - identity_length < 76)
        {
            return error.InvalidEffect;
        }
        const identity = takeCatalogSlice(
            bytes,
            &cursor,
            identity_length,
        ) catch return error.InvalidEffect;
        if (identity.len == 0 or !std.unicode.utf8ValidateSlice(identity)) {
            return error.InvalidUtf8;
        }
        std.crypto.hash.sha2.Sha256.hash(
            identity,
            &workspace.catalog_digests[ordinal],
            .{},
        );
        for (0..ordinal) |prior| {
            const prior_offset: usize = workspace.catalog_offsets[prior];
            const prior_length: usize = workspace.catalog_lengths[prior];
            if (std.mem.eql(
                u8,
                &workspace.catalog_digests[prior],
                &workspace.catalog_digests[ordinal],
            ) and std.mem.eql(
                u8,
                bytes[prior_offset..][0..prior_length],
                identity,
            )) return error.DuplicateEffectIdentity;
        }
        workspace.catalog_offsets[ordinal] = @intCast(cursor - identity.len);
        workspace.catalog_lengths[ordinal] = @intCast(identity.len);
        const payload_schema = readInt(u32, bytes, cursor);
        _ = schemas.node(payload_schema) catch
            return error.InvalidEffect;
        cursor += 4;
        const resume_schema = readInt(u32, bytes, cursor);
        _ = schemas.node(resume_schema) catch
            return error.InvalidEffect;
        cursor += 4;
        if (bytes[cursor] != 0 or !allZero(bytes[cursor + 1 .. cursor + 4])) {
            return error.InvalidEffect;
        }
        cursor += 4;
        const semantic_digest = try effectDigest(
            schemas,
            hash_tasks,
            null,
            identity,
            payload_schema,
            resume_schema,
        );
        if (!std.mem.eql(u8, &semantic_digest, bytes[cursor..][0..32])) {
            return error.DigestMismatch;
        }
        cursor += 32;
        const ordinal_digest = try effectDigest(
            schemas,
            hash_tasks,
            @intCast(ordinal),
            identity,
            payload_schema,
            resume_schema,
        );
        if (!std.mem.eql(u8, &ordinal_digest, bytes[cursor..][0..32])) {
            return error.DigestMismatch;
        }
        cursor += 32;
    }
    if (cursor != bytes.len) return error.InvalidEffect;
    return count;
}

fn effectDigest(
    schemas: dynamic_value_v1.Table,
    hash_tasks: []dynamic_value_v1.SchemaHashTask,
    ordinal: ?u32,
    identity: []const u8,
    payload_schema: u32,
    resume_schema: u32,
) Error![32]u8 {
    const payload_digest = dynamic_value_v1.schemaDigest(
        schemas,
        payload_schema,
        hash_tasks,
    ) catch return error.InvalidSchema;
    const resume_digest = dynamic_value_v1.schemaDigest(
        schemas,
        resume_schema,
        hash_tasks,
    ) catch return error.InvalidSchema;
    if (ordinal == null) {
        return effectSemanticDigest(identity, payload_digest, resume_digest);
    }
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    semanticHashBytes(&hasher, "boundary-effect-site-contract-v1");
    semanticHashU32(&hasher, ordinal.?);
    semanticHashBytes(&hasher, identity);
    hasher.update(&payload_digest);
    hasher.update(&resume_digest);
    semanticHashBytes(&hasher, "single-resume");
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

/// Derive the stable semantic contract identity carried by one effect site.
pub fn effectSemanticDigest(
    semantic_identity: []const u8,
    payload_schema_digest: [32]u8,
    resume_schema_digest: [32]u8,
) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    semanticHashBytes(&hasher, "boundary-effect-site-semantic-contract-v1");
    semanticHashBytes(&hasher, semantic_identity);
    hasher.update(&payload_schema_digest);
    hasher.update(&resume_schema_digest);
    semanticHashBytes(&hasher, "single-resume");
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

const Values = struct {
    bytes: []const u8,
    count: u32,

    fn schemaId(self: Values, value: u16) u32 {
        return readInt(u32, self.bytes, 4 + @as(usize, value) * 4);
    }
};

fn validateValues(
    bytes: []const u8,
    schemas: dynamic_value_v1.Table,
) Error!Values {
    if (bytes.len < 4) return error.InvalidValue;
    const count = readInt(u32, bytes, 0);
    if (count > maximum_catalog_entries or
        bytes.len != 4 + @as(usize, count) * 4)
    {
        return error.InvalidValue;
    }
    for (0..count) |index| {
        _ = schemas.node(readInt(u32, bytes, 4 + index * 4)) catch
            return error.InvalidValue;
    }
    return .{ .bytes = bytes, .count = count };
}

fn deriveKernelScratch(
    schemas: dynamic_value_v1.Table,
    values: Values,
) Error!u64 {
    var value_bytes: u64 = 0;
    for (0..values.count) |value| {
        const schema_id = values.schemaId(@intCast(value));
        const node = schemas.node(schema_id) catch return error.InvalidSchema;
        value_bytes = std.math.add(
            u64,
            value_bytes,
            node.maximum_encoded_size,
        ) catch return error.LengthOverflow;
    }
    const value_metadata = std.math.mul(u64, values.count, 16) catch
        return error.LengthOverflow;
    const schema_stack = std.math.mul(u64, schemas.count(), 16) catch
        return error.LengthOverflow;
    var maximum_single: u64 = 0;
    for (schemas.nodes) |node| {
        maximum_single = @max(maximum_single, node.maximum_encoded_size);
    }
    const framing = std.math.add(
        u64,
        std.math.mul(u64, maximum_single, 3) catch
            return error.LengthOverflow,
        176,
    ) catch return error.LengthOverflow;
    return std.math.add(
        u64,
        std.math.add(u64, value_bytes, value_metadata) catch
            return error.LengthOverflow,
        std.math.add(u64, schema_stack, framing) catch
            return error.LengthOverflow,
    ) catch error.LengthOverflow;
}

fn validateFunctions(
    bytes: []const u8,
    schemas: dynamic_value_v1.Table,
) Error!u32 {
    if (bytes.len < 4) return error.InvalidFunction;
    const count = readInt(u32, bytes, 0);
    if (count == 0 or count > maximum_function_entries) {
        return error.InvalidFunction;
    }
    const records_length = std.math.mul(usize, count, 8) catch
        return error.InvalidFunction;
    const expected_length = std.math.add(usize, 4, records_length) catch
        return error.InvalidFunction;
    if (bytes.len != expected_length) {
        return error.InvalidFunction;
    }
    for (0..count) |index| {
        const offset = 4 + index * 8;
        if (readInt(u16, bytes, offset) != index) {
            return error.InvalidFunction;
        }
        _ = schemas.node(readInt(u32, bytes, offset + 4)) catch
            return error.InvalidFunction;
    }
    return count;
}

fn validateCatalogUse(catalogs: Catalogs, segment_count: u32) Error!void {
    var function_seen = [_]bool{false} ** maximum_function_entries;
    var effect_used = [_]bool{false} ** maximum_effect_entries;
    var next_function: u32 = 0;
    const segments = catalogs.envelope.section(.segments);
    var segment_cursor: usize = 4;
    for (0..segment_count) |segment_id| {
        const end = recordEnd(
            segments,
            segment_cursor,
            segment_prefix_length,
        ) catch return error.InvalidSegment;
        const function_id = readInt(u16, segments, segment_cursor + 6);
        if (!function_seen[function_id]) {
            if (function_id != next_function or
                functionEntrySegment(catalogs, function_id) != segment_id)
            {
                return error.InvalidFunction;
            }
            function_seen[function_id] = true;
            next_function += 1;
        }
        var terminator = segment_cursor + segment_prefix_length +
            @as(usize, readInt(u16, segments, segment_cursor + 10)) * 2;
        for (0..readInt(u32, segments, segment_cursor + 12)) |_| {
            terminator = recordEnd(segments, terminator, 16) catch
                return error.InvalidSegment;
        }
        if (segments[terminator + 4] == 2) {
            const payload = terminator + 8;
            switch (segments[payload]) {
                0 => effect_used[readInt(u32, segments, payload + 4)] = true,
                1 => {
                    const callee = readInt(u16, segments, payload + 8);
                    if (callee == 0) return error.InvalidFunction;
                },
                2 => {},
                else => return error.InvalidTerminator,
            }
        }
        segment_cursor = end;
    }
    if (next_function != catalogs.function_count) return error.InvalidFunction;
    for (effect_used[0..catalogs.effect_count]) |used| {
        if (!used) return error.InvalidEffect;
    }
}

fn validateSegments(
    catalogs: Catalogs,
    constant_used: *[maximum_catalog_entries]bool,
    next_constant: *u32,
    value_defined: *[maximum_catalog_entries]bool,
    canonical_failure_constant: *[maximum_catalog_entries]bool,
    authored_failure_operand: *[maximum_catalog_entries]bool,
    next_value: *u32,
    v3_operation_used: *bool,
) Error!u32 {
    const bytes = catalogs.envelope.section(.segments);
    if (bytes.len < 4) return error.InvalidSegment;
    const count = readInt(u32, bytes, 0);
    if (count == 0 or count > maximum_segment_entries) return error.InvalidSegment;
    var cursor: usize = 4;
    for (0..count) |segment_id| {
        if (bytes.len - cursor < segment_prefix_length) return error.InvalidSegment;
        const end = recordEnd(bytes, cursor, segment_prefix_length) catch
            return error.InvalidSegment;
        if (readInt(u16, bytes, cursor + 4) != segment_id or
            readInt(u16, bytes, cursor + 6) >= catalogs.function_count or
            bytes[cursor + 8] > 4 or bytes[cursor + 9] != 0)
        {
            return error.InvalidSegment;
        }
        if (segment_id == catalogs.entry_segment_id and bytes[cursor + 8] != 0) {
            return error.InvalidSegment;
        }
        const parameter_count = readInt(u16, bytes, cursor + 10);
        const instruction_count = readInt(u32, bytes, cursor + 12);
        const function_id = readInt(u16, bytes, cursor + 6);
        var available = [_]bool{false} ** maximum_catalog_entries;
        for (0..catalogs.value_count) |value| {
            const schema = catalogs.schemas.node(
                try catalogs.valueSchemaId(@intCast(value)),
            ) catch return error.InvalidSegment;
            if (schema.maximum_encoded_size == 0) available[value] = true;
        }
        try addGuaranteedConstructorValues(
            catalogs,
            @intCast(segment_id),
            &available,
        );
        cursor += segment_prefix_length;
        for (0..parameter_count) |index| {
            if (end - cursor < 2) return error.InvalidSegment;
            const value = readInt(u16, bytes, cursor);
            if (value >= catalogs.value_count) return error.InvalidSegment;
            if (value != next_value.*) return error.InvalidValue;
            if (value_defined[value]) return error.InvalidValue;
            var prior = cursor - index * 2;
            while (prior < cursor) : (prior += 2) {
                if (readInt(u16, bytes, prior) == value) {
                    return error.InvalidSegment;
                }
            }
            available[value] = true;
            value_defined[value] = true;
            next_value.* += 1;
            cursor += 2;
        }
        for (0..instruction_count) |_| {
            cursor = try validateInstruction(
                catalogs,
                bytes,
                cursor,
                end,
                constant_used,
                next_constant,
                &available,
                value_defined,
                canonical_failure_constant,
                authored_failure_operand,
                next_value,
                v3_operation_used,
            );
        }
        cursor = try validateTerminator(
            catalogs,
            bytes,
            cursor,
            end,
            function_id,
            &available,
        );
        if (cursor != end) return error.InvalidSegment;
    }
    if (cursor != bytes.len) return error.InvalidSegment;
    return count;
}

fn addGuaranteedConstructorValues(
    catalogs: Catalogs,
    segment_id: u16,
    available: *[maximum_catalog_entries]bool,
) Error!void {
    const bytes = catalogs.envelope.section(.constructors);
    if (bytes.len < 4) return error.InvalidConstructor;
    const count = readInt(u32, bytes, 0);
    if (count == 0 or count > maximum_constructor_entries) return error.InvalidConstructor;
    var guaranteed = [_]bool{false} ** maximum_catalog_entries;
    var found = false;
    var cursor: usize = 4;
    for (0..count) |_| {
        const end = recordEnd(bytes, cursor, 24) catch
            return error.InvalidConstructor;
        const kind = bytes[cursor + 8];
        const origin = bytes[cursor + 9];
        if (readInt(u16, bytes, cursor + 12) == segment_id and
            kind != 3 and !(kind == 4 and origin == 2))
        {
            var activation_seen = [_]bool{false} ** maximum_catalog_entries;
            var environment_seen = [_]bool{false} ** maximum_catalog_entries;
            var retained = [_]bool{false} ** maximum_catalog_entries;
            const activation_count = readInt(u16, bytes, cursor + 16);
            const environment_count = readInt(u16, bytes, cursor + 18);
            var field_cursor = cursor + 24;
            for (0..@as(u32, activation_count) + environment_count) |index| {
                if (end - field_cursor < 8) return error.InvalidConstructor;
                const value = readInt(u16, bytes, field_cursor);
                if (value >= catalogs.value_count) {
                    return error.InvalidConstructor;
                }
                const seen = if (index < activation_count)
                    &activation_seen
                else
                    &environment_seen;
                if (seen[value]) return error.InvalidConstructor;
                seen[value] = true;
                retained[value] = true;
                field_cursor += 8;
            }
            if (!found) {
                guaranteed = retained;
                found = true;
            } else {
                for (0..catalogs.value_count) |value| {
                    guaranteed[value] = guaranteed[value] and retained[value];
                }
            }
        }
        cursor = end;
    }
    if (!found) return error.InvalidSegment;
    for (0..catalogs.value_count) |value| {
        available[value] = available[value] or guaranteed[value];
    }
}

fn validateInstruction(
    catalogs: Catalogs,
    bytes: []const u8,
    start: usize,
    segment_end: usize,
    constant_used: *[maximum_catalog_entries]bool,
    next_constant: *u32,
    available: *[maximum_catalog_entries]bool,
    value_defined: *[maximum_catalog_entries]bool,
    canonical_failure_constant: *[maximum_catalog_entries]bool,
    authored_failure_operand: *[maximum_catalog_entries]bool,
    next_value: *u32,
    v3_operation_used: *bool,
) Error!usize {
    if (segment_end - start < 16) return error.InvalidInstruction;
    const end = recordEnd(bytes, start, 16) catch
        return error.InvalidInstruction;
    if (end > segment_end) return error.InvalidInstruction;
    const kind = bytes[start + 4];
    const operation = readInt(u16, bytes, start + 6);
    const result = readInt(u16, bytes, start + 8);
    const operand_count = readInt(u16, bytes, start + 10);
    const immediate = readInt(u32, bytes, start + 12);
    const wire_operation = std.enums.fromInt(
        program_semantics_v1.WireOperation,
        operation,
    ) orelse return error.InvalidInstruction;
    const expected_kind: u8 = if (operation <= 2) @intCast(operation) else 3;
    if (bytes[start + 5] != 0 or operation > 59 or kind != expected_kind or
        result >= catalogs.value_count or
        end != start + 16 + @as(usize, operand_count) * 2)
    {
        return error.InvalidInstruction;
    }
    if (wire_operation == .text_byte_at or wire_operation == .bytes_byte_at) {
        if (catalogs.envelope.header.evaluator_semantics_version !=
            evaluator_semantics_v3)
        {
            return error.InvalidInstruction;
        }
        v3_operation_used.* = true;
    }
    if (operation == 0) {
        if (immediate >= catalogs.constant_count) return error.InvalidInstruction;
        if (!constant_used[immediate]) {
            if (immediate != next_constant.*) return error.InvalidConstant;
            next_constant.* += 1;
        }
        constant_used[immediate] = true;
    } else if (operation < 25 or operation > 29) {
        if (immediate != 0) return error.InvalidInstruction;
    }
    if (result != next_value.* or value_defined[result]) {
        return error.InvalidValue;
    }
    var cursor = start + 16;
    for (0..operand_count) |_| {
        const operand = readInt(u16, bytes, cursor);
        if (operand >= catalogs.value_count or !available[operand]) {
            return error.InvalidInstruction;
        }
        cursor += 2;
    }
    try validateInstructionSchemas(
        catalogs,
        wire_operation,
        result,
        bytes[start + 16 .. end],
        operand_count,
        immediate,
    );
    canonical_failure_constant[result] = operation == 0 and
        try catalogs.valueSchemaId(result) == catalogs.failure_schema_id;
    const failure_roles = program_semantics_v1.failureRolesForWire(
        wire_operation,
    );
    const base_operand_count = program_semantics_v1.fixedOperandCount(
        wire_operation,
    );
    const authored_failures = base_operand_count != null and
        catalogs.envelope.header.evaluator_semantics_version >=
            evaluator_semantics_v2 and
        failure_roles.len != 0 and
        operand_count == base_operand_count.? + failure_roles.len;
    if (authored_failures) {
        for (0..failure_roles.len) |index| {
            const failure_value = readInt(
                u16,
                bytes,
                start + 16 + (base_operand_count.? + index) * 2,
            );
            if (try catalogs.valueSchemaId(failure_value) !=
                catalogs.failure_schema_id)
            {
                return error.InvalidFailureMap;
            }
            authored_failure_operand[failure_value] = true;
        }
    } else for (failure_roles) |role| {
        if (!failureNameExists(
            catalogs,
            program_semantics_v1.failureRoleName(role),
        )) return error.InvalidFailureMap;
    }
    available[result] = true;
    value_defined[result] = true;
    next_value.* += 1;
    return end;
}

fn validateInstructionSchemas(
    catalogs: Catalogs,
    operation: program_semantics_v1.WireOperation,
    result: u16,
    operand_bytes: []const u8,
    operand_count: u16,
    immediate: u32,
) Error!void {
    if (program_semantics_v1.fixedOperandCount(operation)) |expected| {
        const failure_count = program_semantics_v1.failureRolesForWire(
            operation,
        ).len;
        const authored = catalogs.envelope.header.evaluator_semantics_version >=
            evaluator_semantics_v2 and failure_count != 0 and
            operand_count == expected + failure_count;
        if (operand_count != expected and !authored) {
            return error.InvalidInstruction;
        }
    }
    const result_schema = valueSchema(catalogs, result);
    const result_node = catalogs.schemas.node(result_schema) catch
        return error.InvalidInstruction;
    const Operand = struct {
        fn id(bytes: []const u8, index: usize) u16 {
            return readInt(u16, bytes, index * 2);
        }
        fn schema(c: Catalogs, bytes: []const u8, index: usize) u32 {
            return valueSchema(c, id(bytes, index));
        }
        fn node(
            c: Catalogs,
            bytes: []const u8,
            index: usize,
        ) Error!dynamic_value_v1.Node {
            return c.schemas.node(schema(c, bytes, index)) catch
                error.InvalidInstruction;
        }
    };
    const bool_schema = result_node.kind == .bool;
    const u32_result = result_node.kind == .u32;
    switch (operation) {
        .constant => if (result_schema != try constantSchema(
            catalogs,
            immediate,
        )) return error.InvalidInstruction,
        .copy => if (result_schema != Operand.schema(
            catalogs,
            operand_bytes,
            0,
        )) return error.InvalidInstruction,
        .compare_eq_zero => {
            if (!isIntegerKind((try Operand.node(
                catalogs,
                operand_bytes,
                0,
            )).kind) or !bool_schema) return error.InvalidInstruction;
        },
        .integer_add,
        .integer_subtract,
        .integer_multiply,
        .integer_divide,
        .integer_remainder,
        .integer_bit_and,
        .integer_bit_or,
        .integer_bit_xor,
        => {
            if (!isIntegerKind(result_node.kind) or
                result_schema != Operand.schema(catalogs, operand_bytes, 0) or
                result_schema != Operand.schema(catalogs, operand_bytes, 1))
            {
                return error.InvalidInstruction;
            }
        },
        .integer_negate => {
            if (!isSignedIntegerKind(result_node.kind) or
                result_schema != Operand.schema(catalogs, operand_bytes, 0))
            {
                return error.InvalidInstruction;
            }
        },
        .integer_equal,
        .integer_not_equal,
        .integer_less_than,
        .integer_less_equal,
        .integer_greater_than,
        .integer_greater_equal,
        => {
            const left = Operand.schema(catalogs, operand_bytes, 0);
            if (!bool_schema or left != Operand.schema(
                catalogs,
                operand_bytes,
                1,
            ) or !isIntegerKind((try catalogs.schemas.node(left)).kind)) {
                return error.InvalidInstruction;
            }
        },
        .integer_bit_not => {
            if (!isIntegerKind(result_node.kind) or
                result_schema != Operand.schema(catalogs, operand_bytes, 0))
            {
                return error.InvalidInstruction;
            }
        },
        .integer_convert => if (!isIntegerKind(result_node.kind) or
            !isIntegerKind((try Operand.node(
                catalogs,
                operand_bytes,
                0,
            )).kind)) return error.InvalidInstruction,
        .boolean_not => if (!bool_schema or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .bool)
            return error.InvalidInstruction,
        .boolean_and, .boolean_or => if (!bool_schema or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .bool or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .bool)
            return error.InvalidInstruction,
        .select => if ((try Operand.node(
            catalogs,
            operand_bytes,
            0,
        )).kind != .bool or
            result_schema != Operand.schema(catalogs, operand_bytes, 1) or
            result_schema != Operand.schema(catalogs, operand_bytes, 2))
            return error.InvalidInstruction,
        .product_construct => {
            if (result_node.kind != .product or
                readInt(u32, result_node.payload, 0) != operand_count)
            {
                return error.InvalidInstruction;
            }
            for (0..operand_count) |index| {
                if (readInt(u32, result_node.payload, 4 + index * 4) !=
                    Operand.schema(catalogs, operand_bytes, index))
                {
                    return error.InvalidInstruction;
                }
            }
        },
        .product_extract, .product_replace => {
            const product_schema = Operand.schema(catalogs, operand_bytes, 0);
            const product = catalogs.schemas.node(product_schema) catch
                return error.InvalidInstruction;
            if (product.kind != .product or
                immediate >= readInt(u32, product.payload, 0))
            {
                return error.InvalidInstruction;
            }
            const field_schema = readInt(
                u32,
                product.payload,
                4 + @as(usize, immediate) * 4,
            );
            if (operation == .product_extract) {
                if (result_schema != field_schema) return error.InvalidInstruction;
            } else if (result_schema != product_schema or
                Operand.schema(catalogs, operand_bytes, 1) != field_schema)
            {
                return error.InvalidInstruction;
            }
        },
        .sum_construct => {
            if (result_node.kind != .sum or
                immediate >= readInt(u32, result_node.payload, 4))
            {
                return error.InvalidInstruction;
            }
            const payload_schema = readInt(
                u32,
                result_node.payload,
                12 + @as(usize, immediate) * 8,
            );
            const payload_node = catalogs.schemas.node(payload_schema) catch
                return error.InvalidInstruction;
            const expected: u16 = if (payload_node.kind == .unit) 0 else 1;
            if (operand_count != expected or (expected == 1 and
                Operand.schema(catalogs, operand_bytes, 0) != payload_schema))
            {
                return error.InvalidInstruction;
            }
        },
        .sum_tag_is, .sum_extract => {
            const sum = try Operand.node(catalogs, operand_bytes, 0);
            if (sum.kind != .sum or immediate >= readInt(u32, sum.payload, 4)) {
                return error.InvalidInstruction;
            }
            if (operation == .sum_tag_is) {
                if (!bool_schema) return error.InvalidInstruction;
            } else if (result_schema != readInt(
                u32,
                sum.payload,
                12 + @as(usize, immediate) * 8,
            ) or result_node.kind == .unit) return error.InvalidInstruction;
        },
        .optional_none => if (result_node.kind != .optional)
            return error.InvalidInstruction,
        .optional_some => if (result_node.kind != .optional or
            readInt(u32, result_node.payload, 0) != Operand.schema(
                catalogs,
                operand_bytes,
                0,
            )) return error.InvalidInstruction,
        .optional_is_some => if (!bool_schema or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .optional)
            return error.InvalidInstruction,
        .vector_empty => if (result_node.kind != .vector)
            return error.InvalidInstruction,
        .vector_length => if (!u32_result or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .vector)
            return error.InvalidInstruction,
        .vector_get, .vector_set, .vector_push, .vector_truncate, .vector_clear => {
            const vector_schema = Operand.schema(catalogs, operand_bytes, 0);
            const vector = catalogs.schemas.node(vector_schema) catch
                return error.InvalidInstruction;
            if (vector.kind != .vector) return error.InvalidInstruction;
            const element_schema = readInt(u32, vector.payload, 4);
            switch (operation) {
                .vector_get => if (result_schema != element_schema or
                    (try Operand.node(catalogs, operand_bytes, 1)).kind != .u32)
                    return error.InvalidInstruction,
                .vector_set => if (result_schema != vector_schema or
                    (try Operand.node(catalogs, operand_bytes, 1)).kind != .u32 or
                    Operand.schema(catalogs, operand_bytes, 2) != element_schema)
                    return error.InvalidInstruction,
                .vector_push => if (result_schema != vector_schema or
                    Operand.schema(catalogs, operand_bytes, 1) != element_schema)
                    return error.InvalidInstruction,
                .vector_truncate => if (result_schema != vector_schema or
                    (try Operand.node(catalogs, operand_bytes, 1)).kind != .u32)
                    return error.InvalidInstruction,
                .vector_clear => if (result_schema != vector_schema)
                    return error.InvalidInstruction,
                else => unreachable,
            }
        },
        .vector_pop => {
            const vector_schema = Operand.schema(catalogs, operand_bytes, 0);
            const vector = catalogs.schemas.node(vector_schema) catch
                return error.InvalidInstruction;
            if (vector.kind != .vector or result_node.kind != .product or
                readInt(u32, result_node.payload, 0) != 2 or
                readInt(u32, result_node.payload, 4) != vector_schema)
            {
                return error.InvalidInstruction;
            }
            const optional_schema = readInt(u32, result_node.payload, 8);
            const optional = catalogs.schemas.node(optional_schema) catch
                return error.InvalidInstruction;
            if (optional.kind != .optional or
                readInt(u32, optional.payload, 0) !=
                    readInt(u32, vector.payload, 4))
            {
                return error.InvalidInstruction;
            }
        },
        .text_empty => if (result_node.kind != .text)
            return error.InvalidInstruction,
        .text_append => if (result_schema != Operand.schema(
            catalogs,
            operand_bytes,
            0,
        ) or (try Operand.node(catalogs, operand_bytes, 0)).kind != .text or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .text)
            return error.InvalidInstruction,
        .text_append_scalar => if (result_schema != Operand.schema(
            catalogs,
            operand_bytes,
            0,
        ) or (try Operand.node(catalogs, operand_bytes, 0)).kind != .text or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .u32)
            return error.InvalidInstruction,
        .text_append_unsigned, .text_append_signed => {
            const integer = (try Operand.node(catalogs, operand_bytes, 1)).kind;
            if (result_schema != Operand.schema(catalogs, operand_bytes, 0) or
                (try Operand.node(catalogs, operand_bytes, 0)).kind != .text or
                !isIntegerKind(integer) or
                (operation == .text_append_unsigned and
                    isSignedIntegerKind(integer)) or
                (operation == .text_append_signed and
                    !isSignedIntegerKind(integer)))
            {
                return error.InvalidInstruction;
            }
        },
        .text_copy => if (result_node.kind != .text or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .text or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .u32 or
            (try Operand.node(catalogs, operand_bytes, 2)).kind != .u32)
            return error.InvalidInstruction,
        .text_byte_at => if (result_node.kind != .u8 or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .text or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .u32)
            return error.InvalidInstruction,
        .bytes_byte_at => if (result_node.kind != .u8 or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .bytes or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .u32)
            return error.InvalidInstruction,
        .text_compare => if (result_node.kind != .i8 or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .text or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .text)
            return error.InvalidInstruction,
        .text_join => if (result_schema != Operand.schema(
            catalogs,
            operand_bytes,
            0,
        ) or (try Operand.node(catalogs, operand_bytes, 0)).kind != .text or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .text or
            (try Operand.node(catalogs, operand_bytes, 2)).kind != .text)
            return error.InvalidInstruction,
        .bytes_empty => if (result_node.kind != .bytes)
            return error.InvalidInstruction,
        .bytes_append => if (result_schema != Operand.schema(
            catalogs,
            operand_bytes,
            0,
        ) or (try Operand.node(catalogs, operand_bytes, 0)).kind != .bytes or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .bytes)
            return error.InvalidInstruction,
        .bytes_append_scalar => if (result_schema != Operand.schema(
            catalogs,
            operand_bytes,
            0,
        ) or (try Operand.node(catalogs, operand_bytes, 0)).kind != .bytes or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .u8)
            return error.InvalidInstruction,
        .bytes_copy => if (result_node.kind != .bytes or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .bytes or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .u32 or
            (try Operand.node(catalogs, operand_bytes, 2)).kind != .u32)
            return error.InvalidInstruction,
        .bytes_compare => if (result_node.kind != .i8 or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .bytes or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .bytes)
            return error.InvalidInstruction,
        .bytes_join => if (result_schema != Operand.schema(
            catalogs,
            operand_bytes,
            0,
        ) or (try Operand.node(catalogs, operand_bytes, 0)).kind != .bytes or
            (try Operand.node(catalogs, operand_bytes, 1)).kind != .bytes or
            (try Operand.node(catalogs, operand_bytes, 2)).kind != .bytes)
            return error.InvalidInstruction,
        .text_length => if (!u32_result or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .text)
            return error.InvalidInstruction,
        .bytes_length => if (!u32_result or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .bytes)
            return error.InvalidInstruction,
        .enum_to_u32 => if (!u32_result or
            (try Operand.node(catalogs, operand_bytes, 0)).kind != .@"enum")
            return error.InvalidInstruction,
    }
}

fn constantSchema(catalogs: Catalogs, target: u32) Error!u32 {
    const bytes = catalogs.envelope.section(.constants);
    var cursor: usize = 4;
    for (0..catalogs.constant_count) |constant| {
        const schema = readInt(u32, bytes, cursor);
        const length = readInt(u32, bytes, cursor + 4);
        cursor += 8;
        if (constant == target) return schema;
        cursor += length;
    }
    return error.InvalidInstruction;
}

fn valueNodeKind(catalogs: Catalogs, value: u16) dynamic_value_v1.Kind {
    const schema = valueSchema(catalogs, value);
    return (catalogs.schemas.node(schema) catch unreachable).kind;
}

fn functionResultSchema(catalogs: Catalogs, function_id: u16) u32 {
    return readInt(
        u32,
        catalogs.functions_section,
        4 + @as(usize, function_id) * 8 + 4,
    );
}

fn functionEntrySegment(catalogs: Catalogs, function_id: u16) u16 {
    return readInt(
        u16,
        catalogs.functions_section,
        4 + @as(usize, function_id) * 8 + 2,
    );
}

fn failureTagExists(catalogs: Catalogs, target: u32) bool {
    const bytes = catalogs.envelope.section(.failures);
    const count = readInt(u32, bytes, 0);
    var cursor: usize = 4;
    for (0..count) |_| {
        const tag = readInt(u32, bytes, cursor);
        const length = readInt(u32, bytes, cursor + 4);
        if (tag == target) return true;
        cursor += 8 + length;
    }
    return false;
}

fn failureNameExists(catalogs: Catalogs, target: []const u8) bool {
    const bytes = catalogs.envelope.section(.failures);
    const count = readInt(u32, bytes, 0);
    var cursor: usize = 4;
    for (0..count) |_| {
        cursor += 4;
        const length = readInt(u32, bytes, cursor);
        cursor += 4;
        if (std.mem.eql(u8, bytes[cursor..][0..length], target)) return true;
        cursor += length;
    }
    return false;
}

fn isIntegerKind(kind: dynamic_value_v1.Kind) bool {
    return @intFromEnum(kind) >= @intFromEnum(dynamic_value_v1.Kind.i8) and
        @intFromEnum(kind) <= @intFromEnum(dynamic_value_v1.Kind.u64);
}

fn isSignedIntegerKind(kind: dynamic_value_v1.Kind) bool {
    return kind == .i8 or kind == .i16 or kind == .i32 or kind == .i64;
}

fn validateTerminator(
    catalogs: Catalogs,
    bytes: []const u8,
    start: usize,
    segment_end: usize,
    function_id: u16,
    available: *const [maximum_catalog_entries]bool,
) Error!usize {
    if (segment_end - start < 8) return error.InvalidTerminator;
    const end = recordEnd(bytes, start, 8) catch
        return error.InvalidTerminator;
    if (end > segment_end or bytes[start + 4] > 6 or
        bytes[start + 5] != 0 or readInt(u16, bytes, start + 6) != 0)
    {
        return error.InvalidTerminator;
    }
    var cursor = start + 8;
    switch (bytes[start + 4]) {
        0 => try validateEdge(
            catalogs,
            bytes,
            &cursor,
            end,
            null,
            available,
            function_id,
            null,
            0,
        ),
        1 => {
            if (end - cursor < 4) return error.InvalidTerminator;
            const condition = readInt(u16, bytes, cursor);
            if (condition >= catalogs.value_count or !available[condition] or
                valueNodeKind(catalogs, condition) != .bool or
                readInt(u16, bytes, cursor + 2) != 0)
            {
                return error.InvalidTerminator;
            }
            cursor += 4;
            try validateEdge(
                catalogs,
                bytes,
                &cursor,
                end,
                null,
                available,
                function_id,
                null,
                0,
            );
            try validateEdge(
                catalogs,
                bytes,
                &cursor,
                end,
                null,
                available,
                function_id,
                null,
                0,
            );
        },
        2 => try validateSuspension(
            catalogs,
            bytes,
            &cursor,
            end,
            available,
            function_id,
        ),
        3 => {
            if (function_id != 0 or end - cursor != 4 or bytes[cursor] > 1 or
                bytes[cursor + 1] != 0)
            {
                return error.InvalidTerminator;
            }
            const value = readInt(u16, bytes, cursor + 2);
            if ((bytes[cursor] == 0 and value != std.math.maxInt(u16)) or
                (bytes[cursor] == 0 and
                    (catalogs.schemas.node(
                        functionResultSchema(catalogs, function_id),
                    ) catch return error.InvalidTerminator).kind != .unit) or
                (bytes[cursor] == 1 and
                    (value >= catalogs.value_count or !available[value] or
                        valueSchema(catalogs, value) !=
                            functionResultSchema(catalogs, function_id))))
            {
                return error.InvalidTerminator;
            }
            cursor += 4;
        },
        4 => {
            if (function_id == 0 or end - cursor != 4) {
                return error.InvalidTerminator;
            }
            const value = readInt(u16, bytes, cursor);
            if (value >= catalogs.value_count or !available[value] or
                valueSchema(catalogs, value) !=
                    functionResultSchema(catalogs, function_id) or
                readInt(u16, bytes, cursor + 2) != 0)
            {
                return error.InvalidTerminator;
            }
            cursor += 4;
        },
        5 => {
            if (end - cursor != 4) return error.InvalidTerminator;
            const tag = readInt(u32, bytes, cursor);
            if (tag > std.math.maxInt(u16) or
                !failureTagExists(catalogs, tag))
            {
                return error.InvalidTerminator;
            }
            cursor += 4;
        },
        6 => {
            if (end - cursor != 4) return error.InvalidTerminator;
            const value = readInt(u16, bytes, cursor);
            if (value >= catalogs.value_count or !available[value] or
                valueSchema(catalogs, value) != catalogs.failure_schema_id or
                readInt(u16, bytes, cursor + 2) != 0)
            {
                return error.InvalidTerminator;
            }
            cursor += 4;
        },
        else => unreachable,
    }
    if (cursor != end) return error.InvalidTerminator;
    return end;
}

fn validateSuspension(
    catalogs: Catalogs,
    bytes: []const u8,
    cursor: *usize,
    end: usize,
    available: *const [maximum_catalog_entries]bool,
    function_id: u16,
) Error!void {
    if (end - cursor.* < 20) return error.InvalidTerminator;
    const kind = bytes[cursor.*];
    if (kind > 2 or bytes[cursor.* + 1] != 0 or
        readInt(u16, bytes, cursor.* + 2) != 0)
    {
        return error.InvalidTerminator;
    }
    const site = readInt(u32, bytes, cursor.* + 4);
    const callee = readInt(u16, bytes, cursor.* + 8);
    const request_count = readInt(u16, bytes, cursor.* + 10);
    cursor.* += 12;
    if ((kind == 0 and site >= catalogs.effect_count) or
        (kind != 0 and site != std.math.maxInt(u32)) or
        (kind == 1 and callee >= catalogs.function_count) or
        (kind != 1 and callee != std.math.maxInt(u16)))
    {
        return error.InvalidTerminator;
    }
    if ((kind == 0 and request_count != 1) or
        (kind != 0 and request_count != 0))
    {
        return error.InvalidTerminator;
    }
    const request_values_start = cursor.*;
    for (0..request_count) |_| {
        if (end - cursor.* < 2 or
            readInt(u16, bytes, cursor.*) >= catalogs.value_count or
            !available[readInt(u16, bytes, cursor.*)])
        {
            return error.InvalidTerminator;
        }
        cursor.* += 2;
    }
    const declared_resume_schema = readInt(u32, bytes, end - 4);
    if (kind == 0) {
        const schemas = try effectSchemas(catalogs, site);
        const request_value = readInt(u16, bytes, request_values_start);
        if (valueSchema(catalogs, request_value) != schemas.payload or
            declared_resume_schema != schemas.resume_schema)
        {
            return error.InvalidTerminator;
        }
    } else if (kind == 1) {
        if (declared_resume_schema != functionResultSchema(catalogs, callee)) {
            return error.InvalidTerminator;
        }
    } else if (declared_resume_schema != std.math.maxInt(u32)) {
        return error.InvalidTerminator;
    }
    if (end - cursor.* < 4) return error.InvalidTerminator;
    const callee_present = bytes[cursor.*];
    if (callee_present > 1 or !allZero(bytes[cursor.* + 1 .. cursor.* + 4]) or
        (callee_present == 1) != (kind == 1))
    {
        return error.InvalidTerminator;
    }
    cursor.* += 4;
    if (callee_present == 1) {
        try validateEdge(
            catalogs,
            bytes,
            cursor,
            end,
            null,
            available,
            callee,
            functionEntrySegment(catalogs, callee),
            0,
        );
    }
    try validateEdge(
        catalogs,
        bytes,
        cursor,
        end,
        if (declared_resume_schema == std.math.maxInt(u32))
            null
        else
            declared_resume_schema,
        available,
        function_id,
        null,
        if (kind == 2) 0 else 1,
    );
    if (end - cursor.* != 4) return error.InvalidTerminator;
    const resume_schema = readInt(u32, bytes, cursor.*);
    if (resume_schema != std.math.maxInt(u32)) {
        _ = catalogs.schemas.node(resume_schema) catch
            return error.InvalidTerminator;
    }
    cursor.* += 4;
}

fn validateEdge(
    catalogs: Catalogs,
    bytes: []const u8,
    cursor: *usize,
    end: usize,
    resume_schema: ?u32,
    available: *const [maximum_catalog_entries]bool,
    expected_function: u16,
    expected_target: ?u16,
    required_resume_count: u16,
) Error!void {
    if (end - cursor.* < 4) return error.InvalidTerminator;
    const target = readInt(u16, bytes, cursor.*);
    const count = readInt(u16, bytes, cursor.* + 2);
    if (target >= readInt(u32, catalogs.envelope.section(.segments), 0)) {
        return error.InvalidTerminator;
    }
    const target_segment = imageSegmentRecord(catalogs, target) catch
        return error.InvalidTerminator;
    if (count != readInt(u16, target_segment, 10) or
        readInt(u16, target_segment, 6) != expected_function or
        (expected_target != null and target != expected_target.?))
    {
        return error.InvalidTerminator;
    }
    cursor.* += 4;
    var resume_count: u16 = 0;
    for (0..count) |index| {
        if (end - cursor.* < 4 or bytes[cursor.*] > 1 or
            bytes[cursor.* + 1] != 0)
        {
            return error.InvalidTerminator;
        }
        const value = readInt(u16, bytes, cursor.* + 2);
        if ((bytes[cursor.*] == 0 and
            (value >= catalogs.value_count or !available[value])) or
            (bytes[cursor.*] == 1 and value != std.math.maxInt(u16)))
        {
            return error.InvalidTerminator;
        }
        const target_value = readInt(
            u16,
            target_segment,
            segment_prefix_length + index * 2,
        );
        if (target_value >= catalogs.value_count) {
            return error.InvalidTerminator;
        }
        if (bytes[cursor.*] == 0) {
            if (valueSchema(catalogs, value) !=
                valueSchema(catalogs, target_value))
            {
                return error.InvalidTerminator;
            }
        } else if (resume_schema == null or
            resume_schema.? != valueSchema(catalogs, target_value))
        {
            return error.InvalidTerminator;
        } else {
            resume_count += 1;
        }
        cursor.* += 4;
    }
    if (resume_count != required_resume_count) {
        return error.InvalidTerminator;
    }
}

fn effectSchemas(
    catalogs: Catalogs,
    target: u32,
) Error!struct { payload: u32, resume_schema: u32 } {
    const bytes = catalogs.envelope.section(.effects);
    var cursor: usize = 4;
    for (0..catalogs.effect_count) |ordinal| {
        cursor += 4;
        const identity_length = readInt(u32, bytes, cursor);
        cursor += 4 + identity_length;
        const payload = readInt(u32, bytes, cursor);
        const resume_schema = readInt(u32, bytes, cursor + 4);
        if (ordinal == target) return .{
            .payload = payload,
            .resume_schema = resume_schema,
        };
        cursor += 8 + 4 + 64;
    }
    return error.InvalidTerminator;
}

fn validateFunctionEntries(catalogs: Catalogs, segment_count: u32) Error!void {
    for (0..catalogs.function_count) |index| {
        const offset = 4 + index * 8;
        if (readInt(u16, catalogs.functions_section, offset + 2) >= segment_count) {
            return error.InvalidFunction;
        }
    }
}

fn validateConstructors(catalogs: Catalogs, segment_count: u32) Error!u32 {
    _ = try validateTransitionShape(catalogs);
    const bytes = catalogs.envelope.section(.constructors);
    if (bytes.len < 4) return error.InvalidConstructor;
    const count = readInt(u32, bytes, 0);
    if (count == 0 or count > maximum_constructor_entries) return error.InvalidConstructor;
    var cursor: usize = 4;
    for (0..count) |constructor_id| {
        if (bytes.len - cursor < 24) return error.InvalidConstructor;
        const end = recordEnd(bytes, cursor, 24) catch
            return error.InvalidConstructor;
        if (readInt(u32, bytes, cursor + 4) != constructor_id or
            bytes[cursor + 8] > 7 or bytes[cursor + 9] > 2 or
            readInt(u16, bytes, cursor + 10) & ~@as(u16, 1) != 0 or
            readInt(u16, bytes, cursor + 12) >= segment_count or
            readInt(u16, bytes, cursor + 22) != 0)
        {
            return error.InvalidConstructor;
        }
        if (bytes[cursor + 8] != try expectedConstructorKind(
            catalogs,
            @intCast(constructor_id),
            bytes[cursor + 9],
            readInt(u16, bytes, cursor + 12),
        )) {
            return error.InvalidConstructor;
        }
        const source_segment = imageSegmentRecord(
            catalogs,
            readInt(u16, bytes, cursor + 12),
        ) catch return error.InvalidConstructor;
        const has_activation_context =
            readInt(u16, bytes, cursor + 10) & 1 != 0;
        if (has_activation_context !=
            (readInt(u16, source_segment, 6) != 0))
        {
            return error.InvalidConstructor;
        }
        const resume_target = readInt(u16, bytes, cursor + 14);
        if (resume_target != std.math.maxInt(u16) and
            resume_target >= segment_count)
        {
            return error.InvalidConstructor;
        }
        const activation_count = readInt(u16, bytes, cursor + 16);
        const environment_count = readInt(u16, bytes, cursor + 18);
        const invariant_count = readInt(u16, bytes, cursor + 20);
        if (!has_activation_context and activation_count != 0) {
            return error.InvalidConstructor;
        }
        cursor += 24;
        const field_count = @as(u32, activation_count) + environment_count;
        var activation_seen = [_]bool{false} ** maximum_catalog_entries;
        var environment_seen = [_]bool{false} ** maximum_catalog_entries;
        var retained = [_]bool{false} ** maximum_catalog_entries;
        for (0..field_count) |index| {
            if (end - cursor < 8) return error.InvalidConstructor;
            const value = readInt(u16, bytes, cursor);
            const seen = if (index < activation_count)
                &activation_seen
            else
                &environment_seen;
            if (value >= catalogs.value_count or
                seen[value] or
                readInt(u16, bytes, cursor + 2) != 0 or
                readInt(u32, bytes, cursor + 4) != valueSchema(catalogs, value))
            {
                return error.InvalidConstructor;
            }
            seen[value] = true;
            retained[value] = true;
            cursor += 8;
        }
        for (0..invariant_count) |_| {
            const invariant_start = cursor;
            cursor = try validateInvariant(catalogs, bytes, cursor, end);
            try validateInvariantRetention(
                catalogs,
                bytes[invariant_start..cursor],
                &retained,
            );
        }
        if (cursor != end) return error.InvalidConstructor;
    }
    if (cursor != bytes.len) return error.InvalidConstructor;
    return count;
}

fn expectedConstructorKind(
    catalogs: Catalogs,
    constructor_id: u32,
    origin: u8,
    source_segment: u16,
) Error!u8 {
    if (constructor_id == catalogs.initial_constructor_id) return 0;
    if (origin == 0 or origin == 1) {
        const segment = try imageSegmentRecord(catalogs, source_segment);
        return switch (segment[8]) {
            0 => 1,
            1 => 2,
            2 => 4,
            3 => 5,
            4 => 7,
            else => error.InvalidConstructor,
        };
    }
    if (origin != 2) return error.InvalidConstructor;
    var suspension_source = source_segment;
    const transitions = catalogs.envelope.section(.entry_transitions);
    for (0..readInt(u32, transitions, 0)) |index| {
        const offset = 4 + index * 12;
        if (transitions[offset + 2] == 4 and
            readInt(u32, transitions, offset + 8) == constructor_id)
        {
            suspension_source = readInt(u16, transitions, offset);
            break;
        }
    }
    const segment = try imageSegmentRecord(catalogs, suspension_source);
    const terminator = imageSegmentTerminator(segment);
    if (segment[terminator + 4] != 2) return error.InvalidConstructor;
    return switch (segment[terminator + 8]) {
        0 => 3,
        1 => 4,
        2, 3 => 6,
        else => error.InvalidConstructor,
    };
}

fn imageSegmentRecord(catalogs: Catalogs, target: u16) Error![]const u8 {
    const bytes = catalogs.envelope.section(.segments);
    var cursor: usize = 4;
    for (0..readInt(u32, bytes, 0)) |id| {
        const end = try recordEnd(bytes, cursor, segment_prefix_length);
        if (id == target) return bytes[cursor..end];
        cursor = end;
    }
    return error.InvalidConstructor;
}

fn imageSegmentTerminator(segment: []const u8) usize {
    var cursor: usize = segment_prefix_length +
        @as(usize, readInt(u16, segment, 10)) * 2;
    for (0..readInt(u32, segment, 12)) |_| {
        cursor += readInt(u32, segment, cursor);
    }
    return cursor;
}

fn validateInvariant(
    catalogs: Catalogs,
    bytes: []const u8,
    start: usize,
    constructor_end: usize,
) Error!usize {
    if (constructor_end - start < 8) return error.InvalidInvariant;
    const end = recordEnd(bytes, start, 8) catch return error.InvalidInvariant;
    if (end > constructor_end or bytes[start + 4] > 20 or
        bytes[start + 5] != 0 or readInt(u16, bytes, start + 6) != 0)
    {
        return error.InvalidInvariant;
    }
    const payload_length = end - start - 8;
    const expected: usize = switch (bytes[start + 4]) {
        0, 1, 2, 5, 11, 15, 16 => 4,
        3, 4, 7, 9, 10, 12, 13, 14, 17, 18, 19, 20 => 8,
        6 => 20,
        8 => blk: {
            if (payload_length < 8) return error.InvalidInvariant;
            break :blk 8 + @as(usize, readInt(u16, bytes, start + 12)) * 2;
        },
        else => unreachable,
    };
    if (payload_length != expected) return error.InvalidInvariant;
    const value_slots: usize = switch (bytes[start + 4]) {
        0, 15, 19 => 1,
        1, 2, 5, 6, 9, 10, 11, 12, 14, 16, 20 => 2,
        3, 13, 18 => 3,
        4, 7 => 4,
        8 => 2,
        17 => 2,
        else => 0,
    };
    for (0..value_slots) |index| {
        if (readInt(u16, bytes, start + 8 + index * 2) >= catalogs.value_count) {
            return error.InvalidInvariant;
        }
    }
    if (bytes[start + 4] == 8) {
        const operand_count = readInt(u16, bytes, start + 12);
        for (0..operand_count) |index| {
            if (readInt(u16, bytes, start + 16 + index * 2) >=
                catalogs.value_count)
            {
                return error.InvalidInvariant;
            }
        }
    }
    const payload = start + 8;
    switch (bytes[start + 4]) {
        0 => if (bytes[payload + 2] > 1 or bytes[payload + 3] != 0)
            return error.InvalidInvariant,
        3 => if (bytes[payload + 6] > 1 or bytes[payload + 7] != 0)
            return error.InvalidInvariant,
        6 => {
            const kind = bytes[payload + 4];
            const value = readInt(u64, bytes, payload + 12);
            if (!allZero(bytes[payload + 2 .. payload + 4]) or kind > 3 or
                !allZero(bytes[payload + 5 .. payload + 12]) or
                (kind == 0 and value > 1) or
                (kind == 3 and value > std.math.maxInt(u16)))
            {
                return error.InvalidInvariant;
            }
        },
        8 => if (readInt(u16, bytes, payload + 6) != 0)
            return error.InvalidInvariant,
        9, 10, 20 => if (readInt(u16, bytes, payload + 6) != 0)
            return error.InvalidInvariant,
        12 => if (bytes[payload + 4] > 1 or
            !isScalarSchemaTag(bytes[payload + 5]) or
            readInt(u16, bytes, payload + 6) != 0)
            return error.InvalidInvariant,
        13 => if (bytes[payload + 6] > 7 or
            !isScalarSchemaTag(bytes[payload + 7]))
            return error.InvalidInvariant,
        14 => if (!isScalarSchemaTag(bytes[payload + 4]) or
            !allZero(bytes[payload + 5 .. payload + 8]))
            return error.InvalidInvariant,
        15 => if (bytes[payload + 2] > 1 or bytes[payload + 3] != 0)
            return error.InvalidInvariant,
        17 => if (bytes[payload + 4] > 5 or bytes[payload + 5] > 1 or
            readInt(u16, bytes, payload + 6) != 0)
            return error.InvalidInvariant,
        18 => if (bytes[payload + 6] > 5 or bytes[payload + 7] != 0)
            return error.InvalidInvariant,
        19 => if (bytes[payload + 4] > 1 or
            !allZero(bytes[payload + 5 .. payload + 8]))
            return error.InvalidInvariant,
        else => {},
    }
    try validateInvariantSchemas(catalogs, bytes[start..end]);
    return end;
}

fn validateInvariantRetention(
    catalogs: Catalogs,
    invariant: []const u8,
    retained: *const [maximum_catalog_entries]bool,
) Error!void {
    const tag = invariant[4];
    const payload = 8;
    switch (tag) {
        0, 6, 15, 19 => try requireRetainedInvariantValue(
            catalogs,
            retained,
            readInt(u16, invariant, payload),
        ),
        1, 2, 5, 9, 10, 11, 12, 14, 16, 17, 20 => {
            try requireRetainedInvariantValue(
                catalogs,
                retained,
                readInt(u16, invariant, payload),
            );
            try requireRetainedInvariantValue(
                catalogs,
                retained,
                readInt(u16, invariant, payload + 2),
            );
        },
        3, 13, 18 => {
            for (0..3) |index| try requireRetainedInvariantValue(
                catalogs,
                retained,
                readInt(u16, invariant, payload + index * 2),
            );
        },
        4, 7 => {
            for (0..4) |index| try requireRetainedInvariantValue(
                catalogs,
                retained,
                readInt(u16, invariant, payload + index * 2),
            );
        },
        8 => {
            try requireRetainedInvariantValue(
                catalogs,
                retained,
                readInt(u16, invariant, payload),
            );
            const operand_count = readInt(u16, invariant, payload + 4);
            for (0..operand_count) |index| try requireRetainedInvariantValue(
                catalogs,
                retained,
                readInt(u16, invariant, payload + 8 + index * 2),
            );
        },
        else => return error.InvalidInvariant,
    }
}

fn requireRetainedInvariantValue(
    catalogs: Catalogs,
    retained: *const [maximum_catalog_entries]bool,
    value: u16,
) Error!void {
    if (value >= catalogs.value_count) return error.InvalidInvariant;
    const schema = catalogs.schemas.node(valueSchema(catalogs, value)) catch
        return error.InvalidInvariant;
    if (!retained[value] and schema.maximum_encoded_size != 0) {
        return error.InvalidInvariant;
    }
}

fn validateInvariantSchemas(
    catalogs: Catalogs,
    invariant: []const u8,
) Error!void {
    const tag = invariant[4];
    const payload = 8;
    const result = readInt(u16, invariant, payload);
    switch (tag) {
        0 => try requireInvariantKind(catalogs, result, .bool),
        1 => {
            try requireInvariantKind(catalogs, result, .bool);
            try validateInvariantOperation(
                catalogs,
                1,
                result,
                0,
                &.{readInt(u16, invariant, payload + 2)},
            );
        },
        2 => try validateInvariantOperation(
            catalogs,
            20,
            result,
            0,
            &.{readInt(u16, invariant, payload + 2)},
        ),
        3 => try validateInvariantOperation(
            catalogs,
            21 + invariant[payload + 6],
            result,
            0,
            &.{
                readInt(u16, invariant, payload + 2),
                readInt(u16, invariant, payload + 4),
            },
        ),
        4 => {
            try requireInvariantKind(catalogs, result, .bool);
            try validateInvariantOperation(
                catalogs,
                23,
                result,
                0,
                &.{
                    readInt(u16, invariant, payload + 2),
                    readInt(u16, invariant, payload + 4),
                    readInt(u16, invariant, payload + 6),
                },
            );
        },
        5 => try validateInvariantOperation(
            catalogs,
            1,
            result,
            0,
            &.{readInt(u16, invariant, payload + 2)},
        ),
        6 => try validateInvariantConstantSchema(
            catalogs,
            result,
            invariant[payload + 4],
            readInt(u64, invariant, payload + 12),
        ),
        7 => try validateInvariantOperation(
            catalogs,
            23,
            result,
            0,
            &.{
                readInt(u16, invariant, payload + 2),
                readInt(u16, invariant, payload + 4),
                readInt(u16, invariant, payload + 6),
            },
        ),
        8 => try validateInstructionResultInvariant(catalogs, invariant),
        9 => try validateInvariantOperation(
            catalogs,
            25,
            result,
            readInt(u16, invariant, payload + 4),
            &.{readInt(u16, invariant, payload + 2)},
        ),
        10 => try validateInvariantOperation(
            catalogs,
            29,
            result,
            readInt(u16, invariant, payload + 4),
            &.{readInt(u16, invariant, payload + 2)},
        ),
        11 => {
            const bounded = readInt(u16, invariant, payload + 2);
            const operation: u16 = switch (try invariantKind(catalogs, bounded)) {
                .vector => 34,
                .text => 53,
                .bytes => 54,
                else => return error.InvalidInvariant,
            };
            try validateInvariantOperation(
                catalogs,
                operation,
                result,
                0,
                &.{bounded},
            );
        },
        12 => {
            const operand = readInt(u16, invariant, payload + 2);
            const scalar_tag = invariant[payload + 5];
            try requireInvariantScalarTag(catalogs, result, scalar_tag);
            try requireInvariantScalarTag(catalogs, operand, scalar_tag);
            try validateInvariantOperation(
                catalogs,
                if (invariant[payload + 4] == 0) 8 else 15,
                result,
                0,
                &.{operand},
            );
        },
        13 => {
            const left = readInt(u16, invariant, payload + 2);
            const right = readInt(u16, invariant, payload + 4);
            const scalar_tag = invariant[payload + 7];
            try requireInvariantScalarTag(catalogs, result, scalar_tag);
            try requireInvariantScalarTag(catalogs, left, scalar_tag);
            try requireInvariantScalarTag(catalogs, right, scalar_tag);
            const operations = [_]u16{ 3, 4, 5, 6, 7, 16, 17, 18 };
            try validateInvariantOperation(
                catalogs,
                operations[invariant[payload + 6]],
                result,
                0,
                &.{ left, right },
            );
        },
        14 => {
            const operand = readInt(u16, invariant, payload + 2);
            try requireInvariantScalarTag(
                catalogs,
                result,
                invariant[payload + 4],
            );
            if (!isIntegerKind(try invariantKind(catalogs, operand))) {
                return error.InvalidInvariant;
            }
            try validateInvariantOperation(
                catalogs,
                19,
                result,
                0,
                &.{operand},
            );
        },
        15 => if (!isIntegerKind(try invariantKind(catalogs, result)))
            return error.InvalidInvariant,
        16 => try validateInvariantOperation(
            catalogs,
            2,
            result,
            0,
            &.{readInt(u16, invariant, payload + 2)},
        ),
        17 => {
            const right = readInt(u16, invariant, payload + 2);
            if (valueSchema(catalogs, result) != valueSchema(catalogs, right) or
                !isIntegerKind(try invariantKind(catalogs, result)))
            {
                return error.InvalidInvariant;
            }
        },
        18 => try validateInvariantOperation(
            catalogs,
            9 + invariant[payload + 6],
            result,
            0,
            &.{
                readInt(u16, invariant, payload + 2),
                readInt(u16, invariant, payload + 4),
            },
        ),
        19 => try requireInvariantSumCase(
            catalogs,
            result,
            readInt(u16, invariant, payload + 2),
        ),
        20 => try validateInvariantOperation(
            catalogs,
            28,
            result,
            readInt(u16, invariant, payload + 4),
            &.{readInt(u16, invariant, payload + 2)},
        ),
        else => return error.InvalidInvariant,
    }
}

fn validateInstructionResultInvariant(
    catalogs: Catalogs,
    invariant: []const u8,
) Error!void {
    const payload = 8;
    const result = readInt(u16, invariant, payload);
    const definition = readInt(u16, invariant, payload + 2);
    const operand_count = readInt(u16, invariant, payload + 4);
    const instruction = try imageDefiningInstruction(catalogs, definition);
    if (valueSchema(catalogs, result) != valueSchema(catalogs, definition) or
        operand_count != readInt(u16, instruction, 10))
    {
        return error.InvalidInvariant;
    }
    const operand_bytes = invariant[payload + 8 ..][0 .. @as(usize, operand_count) * 2];
    for (0..operand_count) |index| {
        const operand = readInt(u16, operand_bytes, index * 2);
        const definition_operand = readInt(u16, instruction, 16 + index * 2);
        if (valueSchema(catalogs, operand) !=
            valueSchema(catalogs, definition_operand))
        {
            return error.InvalidInvariant;
        }
    }
    try validateInvariantOperationEncoded(
        catalogs,
        readInt(u16, instruction, 6),
        result,
        readInt(u32, instruction, 12),
        operand_bytes,
        operand_count,
    );
}

fn imageDefiningInstruction(
    catalogs: Catalogs,
    definition: u16,
) Error![]const u8 {
    const segments = catalogs.envelope.section(.segments);
    var segment_cursor: usize = 4;
    for (0..readInt(u32, segments, 0)) |_| {
        const segment_end = try recordEnd(
            segments,
            segment_cursor,
            segment_prefix_length,
        );
        var cursor = segment_cursor + segment_prefix_length +
            @as(usize, readInt(u16, segments, segment_cursor + 10)) * 2;
        for (0..readInt(u32, segments, segment_cursor + 12)) |_| {
            const instruction_end = try recordEnd(segments, cursor, 16);
            if (readInt(u16, segments, cursor + 8) == definition) {
                return segments[cursor..instruction_end];
            }
            cursor = instruction_end;
        }
        segment_cursor = segment_end;
    }
    return error.InvalidInvariant;
}

fn validateInvariantOperation(
    catalogs: Catalogs,
    operation_tag: u16,
    result: u16,
    immediate: u32,
    operands: []const u16,
) Error!void {
    var operand_bytes: [6]u8 = undefined;
    if (operands.len > operand_bytes.len / 2) return error.InvalidInvariant;
    for (operands, 0..) |operand, index| {
        std.mem.writeInt(
            u16,
            operand_bytes[index * 2 ..][0..2],
            operand,
            .little,
        );
    }
    try validateInvariantOperationEncoded(
        catalogs,
        operation_tag,
        result,
        immediate,
        operand_bytes[0 .. operands.len * 2],
        @intCast(operands.len),
    );
}

fn validateInvariantOperationEncoded(
    catalogs: Catalogs,
    operation_tag: u16,
    result: u16,
    immediate: u32,
    operand_bytes: []const u8,
    operand_count: u16,
) Error!void {
    if (operand_bytes.len != @as(usize, operand_count) * 2) {
        return error.InvalidInvariant;
    }
    const operation = std.enums.fromInt(
        program_semantics_v1.WireOperation,
        operation_tag,
    ) orelse return error.InvalidInvariant;
    validateInstructionSchemas(
        catalogs,
        operation,
        result,
        operand_bytes,
        operand_count,
        immediate,
    ) catch return error.InvalidInvariant;
}

fn validateInvariantConstantSchema(
    catalogs: Catalogs,
    result: u16,
    kind: u8,
    payload: u64,
) Error!void {
    const result_kind = try invariantKind(catalogs, result);
    switch (kind) {
        0 => if (result_kind != .bool or payload > 1)
            return error.InvalidInvariant,
        1 => if (!isSignedIntegerKind(result_kind) or
            !invariantConstantFitsKind(result_kind, payload))
            return error.InvalidInvariant,
        2 => if (!isIntegerKind(result_kind) or
            isSignedIntegerKind(result_kind) or
            !invariantConstantFitsKind(result_kind, payload))
            return error.InvalidInvariant,
        3 => try requireInvariantSumCase(catalogs, result, payload),
        else => return error.InvalidInvariant,
    }
}

fn invariantConstantFitsKind(
    kind: dynamic_value_v1.Kind,
    payload: u64,
) bool {
    const signed: i64 = @bitCast(payload);
    return switch (kind) {
        .bool => payload <= 1,
        .i8 => std.math.cast(i8, signed) != null,
        .i16 => std.math.cast(i16, signed) != null,
        .i32 => std.math.cast(i32, signed) != null,
        .i64 => true,
        .u8 => std.math.cast(u8, payload) != null,
        .u16 => std.math.cast(u16, payload) != null,
        .u32 => std.math.cast(u32, payload) != null,
        .u64 => true,
        else => false,
    };
}

test "invariant scalar constants fit their canonical schema widths" {
    try std.testing.expect(invariantConstantFitsKind(.bool, 0));
    try std.testing.expect(invariantConstantFitsKind(.bool, 1));
    try std.testing.expect(!invariantConstantFitsKind(.bool, 2));
    try std.testing.expect(invariantConstantFitsKind(.i8, @bitCast(@as(i64, -128))));
    try std.testing.expect(invariantConstantFitsKind(.i8, 127));
    try std.testing.expect(!invariantConstantFitsKind(.i8, 128));
    try std.testing.expect(!invariantConstantFitsKind(.i8, 0xff));
    try std.testing.expect(invariantConstantFitsKind(.i16, @bitCast(@as(i64, -32768))));
    try std.testing.expect(!invariantConstantFitsKind(.i16, 32768));
    try std.testing.expect(invariantConstantFitsKind(.i32, @bitCast(@as(i64, std.math.minInt(i32)))));
    try std.testing.expect(!invariantConstantFitsKind(.i32, @as(u64, std.math.maxInt(i32)) + 1));
    try std.testing.expect(invariantConstantFitsKind(.i64, std.math.maxInt(u64)));
    try std.testing.expect(invariantConstantFitsKind(.u8, std.math.maxInt(u8)));
    try std.testing.expect(!invariantConstantFitsKind(.u8, @as(u64, std.math.maxInt(u8)) + 1));
    try std.testing.expect(invariantConstantFitsKind(.u16, std.math.maxInt(u16)));
    try std.testing.expect(!invariantConstantFitsKind(.u16, @as(u64, std.math.maxInt(u16)) + 1));
    try std.testing.expect(invariantConstantFitsKind(.u32, std.math.maxInt(u32)));
    try std.testing.expect(!invariantConstantFitsKind(.u32, @as(u64, std.math.maxInt(u32)) + 1));
    try std.testing.expect(invariantConstantFitsKind(.u64, std.math.maxInt(u64)));
}

fn requireInvariantSumCase(
    catalogs: Catalogs,
    value: u16,
    case_index: u64,
) Error!void {
    const schema = catalogs.schemas.node(valueSchema(catalogs, value)) catch
        return error.InvalidInvariant;
    const case_count: u64 = switch (schema.kind) {
        .optional => 2,
        .sum => readInt(u32, schema.payload, 4),
        else => return error.InvalidInvariant,
    };
    if (case_index >= case_count) return error.InvalidInvariant;
}

fn requireInvariantKind(
    catalogs: Catalogs,
    value: u16,
    expected: dynamic_value_v1.Kind,
) Error!void {
    if (try invariantKind(catalogs, value) != expected) {
        return error.InvalidInvariant;
    }
}

fn requireInvariantScalarTag(
    catalogs: Catalogs,
    value: u16,
    expected: u8,
) Error!void {
    if (@intFromEnum(try invariantKind(catalogs, value)) != expected) {
        return error.InvalidInvariant;
    }
}

fn invariantKind(catalogs: Catalogs, value: u16) Error!dynamic_value_v1.Kind {
    return (catalogs.schemas.node(valueSchema(catalogs, value)) catch
        return error.InvalidInvariant).kind;
}

fn isScalarSchemaTag(tag: u8) bool {
    return tag >= @intFromEnum(dynamic_value_v1.Kind.i8) and
        tag <= @intFromEnum(dynamic_value_v1.Kind.u64);
}

fn validateTransitions(
    catalogs: Catalogs,
    segment_count: u32,
    constructor_count: u32,
) Error!void {
    const bytes = catalogs.envelope.section(.entry_transitions);
    const count = try validateTransitionShape(catalogs);
    var previous: ?[3]u32 = null;
    for (0..count) |index| {
        const offset = 4 + index * 12;
        const source = readInt(u16, bytes, offset);
        const edge = bytes[offset + 2];
        const target = readInt(u16, bytes, offset + 4);
        const constructor = readInt(u32, bytes, offset + 8);
        if (edge > 4 or bytes[offset + 3] != 0 or
            readInt(u16, bytes, offset + 6) != 0 or
            source >= segment_count or target >= segment_count or
            constructor >= constructor_count)
        {
            return error.InvalidTransition;
        }
        const constructor_record = imageConstructorRecord(
            catalogs,
            constructor,
        ) catch return error.InvalidTransition;
        const expected_origin: u8 = if (edge == 3)
            1
        else if (edge == 4) blk: {
            const source_segment = imageSegmentRecord(catalogs, source) catch
                return error.InvalidTransition;
            const terminator = imageSegmentTerminator(source_segment);
            break :blk if (source_segment[terminator + 4] == 2 and
                source_segment[terminator + 8] >= 2)
                2
            else
                0;
        } else 0;
        if (constructor_record[9] != expected_origin or
            readInt(u16, constructor_record, 12) != target)
        {
            return error.InvalidTransition;
        }
        const key = [3]u32{ source, edge, target };
        if (previous) |prior| {
            if (!lexicographicallyLess(prior, key)) {
                return error.InvalidTransition;
            }
        }
        previous = key;
    }
    try validateTransitionCompleteness(catalogs, bytes, count);
}

fn validateTransitionShape(catalogs: Catalogs) Error!u32 {
    const bytes = catalogs.envelope.section(.entry_transitions);
    if (bytes.len < 4) return error.InvalidTransition;
    const count = readInt(u32, bytes, 0);
    if (count > maximum_transition_entries) return error.InvalidTransition;
    const records_length = std.math.mul(usize, count, 12) catch
        return error.InvalidTransition;
    const expected_length = std.math.add(usize, 4, records_length) catch
        return error.InvalidTransition;
    if (bytes.len != expected_length) return error.InvalidTransition;
    return count;
}

fn validateInitialTuple(catalogs: Catalogs) Error!void {
    if (catalogs.function_count == 0 or
        readInt(u16, catalogs.functions_section, 6) != catalogs.entry_segment_id or
        readInt(u32, catalogs.functions_section, 8) != catalogs.result_schema_id)
    {
        return error.InvalidRoot;
    }
    const entry = imageSegmentRecord(catalogs, catalogs.entry_segment_id) catch
        return error.InvalidRoot;
    if (readInt(u16, entry, 6) != 0) return error.InvalidRoot;
    const parameter_count = readInt(u16, entry, 10);
    if (parameter_count != catalogs.entry_parameter_count) {
        return error.InvalidRoot;
    }
    if (parameter_count == 0) {
        if (catalogs.entry_parameter_value_id != std.math.maxInt(u16)) {
            return error.InvalidRoot;
        }
    } else if (readInt(u16, entry, segment_prefix_length) !=
        catalogs.entry_parameter_value_id)
    {
        return error.InvalidRoot;
    }

    const constructor = imageConstructorRecord(
        catalogs,
        catalogs.initial_constructor_id,
    ) catch return error.InvalidRoot;
    if (constructor[8] != 0 or constructor[9] != 0 or
        readInt(u16, constructor, 10) != 0 or
        readInt(u16, constructor, 12) != catalogs.entry_segment_id or
        readInt(u16, constructor, 14) != catalogs.entry_segment_id or
        readInt(u16, constructor, 16) != 0)
    {
        return error.InvalidRoot;
    }
    const environment_count = readInt(u16, constructor, 18);
    if (environment_count > parameter_count) return error.InvalidRoot;
    var cursor: usize = 24;
    for (0..environment_count) |_| {
        if (readInt(u16, constructor, cursor) !=
            catalogs.entry_parameter_value_id)
        {
            return error.InvalidRoot;
        }
        cursor += 8;
    }
}

fn validateConstructorExecution(
    catalogs: Catalogs,
    segment_count: u32,
    constructor_count: u32,
) Error!void {
    var transition_role = [_]bool{false} ** maximum_constructor_entries;
    var suspension_role = [_]bool{false} ** maximum_constructor_entries;
    const transitions = catalogs.envelope.section(.entry_transitions);
    const transition_count = readInt(u32, transitions, 0);
    for (0..transition_count) |index| {
        const offset = 4 + index * 12;
        const source = readInt(u16, transitions, offset);
        const edge_kind = transitions[offset + 2];
        const target = readInt(u16, transitions, offset + 4);
        const constructor_id = readInt(u32, transitions, offset + 8);
        transition_role[constructor_id] = true;
        const constructor = imageConstructorRecord(
            catalogs,
            constructor_id,
        ) catch return error.InvalidConstructor;
        const edge = imageTransitionEdge(
            catalogs,
            source,
            edge_kind,
            target,
        ) catch return error.InvalidTransition;
        try validateTransitionConstructorFields(
            catalogs,
            constructor,
            source,
            target,
            edge,
        );
    }

    for (0..segment_count) |source| {
        const segment = imageSegmentRecord(catalogs, @intCast(source)) catch
            return error.InvalidSegment;
        const terminator = imageSegmentTerminator(segment);
        if (segment[terminator + 4] != 2) continue;
        const suspension_kind = segment[terminator + 8];
        const expected_kind: u8 = switch (suspension_kind) {
            0 => 3,
            1 => 4,
            2 => continue,
            else => return error.InvalidTerminator,
        };
        var matched: ?u32 = null;
        for (0..constructor_count) |constructor_id| {
            const constructor = imageConstructorRecord(
                catalogs,
                @intCast(constructor_id),
            ) catch return error.InvalidConstructor;
            if (constructor[8] != expected_kind or constructor[9] != 2 or
                readInt(u16, constructor, 12) != source)
            {
                continue;
            }
            if (matched != null) return error.InvalidConstructor;
            matched = @intCast(constructor_id);
            try validateSuspensionConstructorFields(
                catalogs,
                constructor,
                @intCast(source),
            );
        }
        const constructor_id = matched orelse return error.InvalidConstructor;
        suspension_role[constructor_id] = true;
    }

    for (0..constructor_count) |constructor_id| {
        const is_initial = constructor_id == catalogs.initial_constructor_id;
        const role_count = @intFromBool(is_initial) +
            @intFromBool(transition_role[constructor_id]) +
            @intFromBool(suspension_role[constructor_id]);
        if (role_count != 1) return error.InvalidConstructor;
    }
}

fn validateConsumedParametersRetained(
    catalogs: Catalogs,
    segment_count: u32,
) Error!void {
    for (0..segment_count) |segment_id| {
        const segment = imageSegmentRecord(catalogs, @intCast(segment_id)) catch
            return error.InvalidSegment;
        var required = [_]bool{false} ** maximum_catalog_entries;
        const parameter_count = readInt(u16, segment, 10);
        var cursor = segment_prefix_length + @as(usize, parameter_count) * 2;
        for (0..readInt(u32, segment, 12)) |_| {
            const end = recordEnd(segment, cursor, 16) catch
                return error.InvalidInstruction;
            const operand_count = readInt(u16, segment, cursor + 10);
            for (0..operand_count) |index| {
                required[readInt(u16, segment, cursor + 16 + index * 2)] = true;
            }
            cursor = end;
        }
        try markTerminatorConsumedValues(
            catalogs,
            @intCast(segment_id),
            segment,
            cursor,
            &required,
        );
        var guaranteed = [_]bool{false} ** maximum_catalog_entries;
        try addGuaranteedConstructorValues(
            catalogs,
            @intCast(segment_id),
            &guaranteed,
        );
        for (0..parameter_count) |index| {
            const parameter = readInt(
                u16,
                segment,
                segment_prefix_length + index * 2,
            );
            const schema = catalogs.schemas.node(
                valueSchema(catalogs, parameter),
            ) catch return error.InvalidSegment;
            if (required[parameter] and !guaranteed[parameter] and
                schema.maximum_encoded_size != 0)
            {
                return error.InvalidConstructor;
            }
        }
    }
}

fn markTerminatorConsumedValues(
    catalogs: Catalogs,
    source: u16,
    segment: []const u8,
    terminator: usize,
    required: *[maximum_catalog_entries]bool,
) Error!void {
    const kind = segment[terminator + 4];
    const payload = terminator + 8;
    switch (kind) {
        0 => try markEdgeConsumedValues(
            catalogs,
            source,
            0,
            segment[payload..],
            required,
        ),
        1 => {
            required[readInt(u16, segment, payload)] = true;
            const then_edge = payload + 4;
            try markEdgeConsumedValues(
                catalogs,
                source,
                1,
                segment[then_edge..],
                required,
            );
            const else_edge = then_edge + imageEdgeLength(segment[then_edge..]);
            try markEdgeConsumedValues(
                catalogs,
                source,
                2,
                segment[else_edge..],
                required,
            );
        },
        2 => {
            const request_count = readInt(u16, segment, payload + 10);
            for (0..request_count) |index| {
                required[readInt(u16, segment, payload + 12 + index * 2)] = true;
            }
            var edge_cursor = payload + 12 + @as(usize, request_count) * 2;
            const callee_present = segment[edge_cursor] == 1;
            edge_cursor += 4;
            if (callee_present) {
                try markEdgeConsumedValues(
                    catalogs,
                    source,
                    3,
                    segment[edge_cursor..],
                    required,
                );
                edge_cursor += imageEdgeLength(segment[edge_cursor..]);
            }
            try markEdgeConsumedValues(
                catalogs,
                source,
                4,
                segment[edge_cursor..],
                required,
            );
        },
        3 => {
            if (segment[payload] == 1) {
                required[readInt(u16, segment, payload + 2)] = true;
            }
        },
        4, 6 => {
            required[readInt(u16, segment, payload)] = true;
        },
        5 => {},
        else => return error.InvalidTerminator,
    }
}

fn markEdgeConsumedValues(
    catalogs: Catalogs,
    source: u16,
    edge_kind: u8,
    edge: []const u8,
    required: *[maximum_catalog_entries]bool,
) Error!void {
    const target = readInt(u16, edge, 0);
    const constructor_id = transitionConstructorId(
        catalogs,
        source,
        edge_kind,
        target,
    ) catch return error.InvalidTransition;
    const constructor = imageConstructorRecord(catalogs, constructor_id) catch
        return error.InvalidConstructor;
    const target_segment = imageSegmentRecord(catalogs, target) catch
        return error.InvalidTransition;
    const argument_count = readInt(u16, edge, 2);
    for (0..argument_count) |index| {
        const argument = 4 + index * 4;
        if (edge[argument] != 0) continue;
        const target_parameter = readInt(
            u16,
            target_segment,
            segment_prefix_length + index * 2,
        );
        if (!constructorRetainsField(constructor, target_parameter)) continue;
        required[readInt(u16, edge, argument + 2)] = true;
    }
}

fn transitionConstructorId(
    catalogs: Catalogs,
    source: u16,
    edge_kind: u8,
    target: u16,
) Error!u32 {
    const transitions = catalogs.envelope.section(.entry_transitions);
    for (0..readInt(u32, transitions, 0)) |index| {
        const offset = 4 + index * 12;
        if (readInt(u16, transitions, offset) == source and
            transitions[offset + 2] == edge_kind and
            readInt(u16, transitions, offset + 4) == target)
        {
            return readInt(u32, transitions, offset + 8);
        }
    }
    return error.InvalidTransition;
}

fn constructorRetainsField(constructor: []const u8, value: u16) bool {
    var cursor: usize = 24;
    const field_count = @as(u32, readInt(u16, constructor, 16)) +
        readInt(u16, constructor, 18);
    for (0..field_count) |_| {
        if (readInt(u16, constructor, cursor) == value) return true;
        cursor += 8;
    }
    return false;
}

fn validateTransitionConstructorFields(
    catalogs: Catalogs,
    constructor: []const u8,
    source: u16,
    target: u16,
    edge: []const u8,
) Error!void {
    const target_segment = imageSegmentRecord(catalogs, target) catch
        return error.InvalidConstructor;
    const parameter_count = readInt(u16, target_segment, 10);
    if (readInt(u16, edge, 2) != parameter_count) {
        return error.InvalidConstructor;
    }
    var cursor: usize = 24;
    const field_count = @as(u32, readInt(u16, constructor, 16)) +
        readInt(u16, constructor, 18);
    for (0..field_count) |_| {
        const value = readInt(u16, constructor, cursor);
        if (!try constructorFieldMaterializable(
            catalogs,
            source,
            target_segment,
            edge,
            value,
        )) return error.InvalidConstructor;
        cursor += 8;
    }
}

fn validateDirectBranchInvariants(catalogs: Catalogs) Error!void {
    const transitions = catalogs.envelope.section(.entry_transitions);
    for (0..readInt(u32, transitions, 0)) |index| {
        const offset = 4 + index * 12;
        const source = readInt(u16, transitions, offset);
        const edge_kind = transitions[offset + 2];
        if (edge_kind != 1 and edge_kind != 2) continue;
        const target = readInt(u16, transitions, offset + 4);
        const constructor = imageConstructorRecord(
            catalogs,
            readInt(u32, transitions, offset + 8),
        ) catch return error.InvalidConstructor;
        const edge = imageTransitionEdge(
            catalogs,
            source,
            edge_kind,
            target,
        ) catch return error.InvalidTransition;
        const target_segment = imageSegmentRecord(catalogs, target) catch
            return error.InvalidSegment;
        try validateDirectBranchInvariant(
            catalogs,
            constructor,
            source,
            edge_kind,
            target_segment,
            edge,
        );
    }
}

fn validateDirectBranchInvariant(
    catalogs: Catalogs,
    constructor: []const u8,
    source: u16,
    edge_kind: u8,
    target_segment: []const u8,
    edge: []const u8,
) Error!void {
    if (edge_kind != 1 and edge_kind != 2) return;
    const source_segment = imageSegmentRecord(catalogs, source) catch
        return error.InvalidConstructor;
    const terminator = imageSegmentTerminator(source_segment);
    if (source_segment[terminator + 4] != 1) {
        return error.InvalidConstructor;
    }
    const condition = readInt(u16, source_segment, terminator + 8);
    const expected = edge_kind == 1;
    const field_count = @as(usize, readInt(u16, constructor, 16)) +
        readInt(u16, constructor, 18);
    var condition_retained = false;
    var field_cursor: usize = 24;
    for (0..field_count) |_| {
        if (try edgeSourceValue(
            target_segment,
            edge,
            readInt(u16, constructor, field_cursor),
        ) == condition) condition_retained = true;
        field_cursor += 8;
    }
    var witness_present = false;
    var cursor: usize = 24 + field_count * 8;
    for (0..readInt(u16, constructor, 20)) |_| {
        const end = recordEnd(constructor, cursor, 8) catch
            return error.InvalidInvariant;
        if (constructor[cursor + 4] == 0) {
            const value = readInt(u16, constructor, cursor + 8);
            const source_value = try edgeSourceValue(
                target_segment,
                edge,
                value,
            );
            if (source_value == condition) {
                if ((constructor[cursor + 10] == 1) != expected) {
                    return error.InvalidInvariant;
                }
                witness_present = true;
            }
        }
        cursor = end;
    }
    if (condition_retained and !witness_present) {
        return error.InvalidInvariant;
    }
}

fn edgeSourceValue(
    target_segment: []const u8,
    edge: []const u8,
    value: u16,
) Error!u16 {
    for (0..readInt(u16, target_segment, 10)) |index| {
        if (readInt(
            u16,
            target_segment,
            segment_prefix_length + index * 2,
        ) != value) continue;
        const argument = 4 + index * 4;
        if (edge[argument] != 0) return error.InvalidInvariant;
        return readInt(u16, edge, argument + 2);
    }
    return value;
}

fn constructorFieldMaterializable(
    catalogs: Catalogs,
    source: u16,
    target_segment: []const u8,
    edge: []const u8,
    value: u16,
) Error!bool {
    const schema = catalogs.schemas.node(valueSchema(catalogs, value)) catch
        return error.InvalidConstructor;
    if (schema.maximum_encoded_size == 0) return true;
    const parameter_count = readInt(u16, target_segment, 10);
    for (0..parameter_count) |index| {
        if (readInt(
            u16,
            target_segment,
            segment_prefix_length + index * 2,
        ) != value) continue;
        const argument = 4 + index * 4;
        if (edge[argument] == 1) return true;
        return segmentValueAvailableAtTerminator(
            catalogs,
            source,
            readInt(u16, edge, argument + 2),
        );
    }
    return segmentValueAvailableAtTerminator(catalogs, source, value);
}

fn validateSuspensionConstructorFields(
    catalogs: Catalogs,
    constructor: []const u8,
    source: u16,
) Error!void {
    var cursor: usize = 24;
    const field_count = @as(u32, readInt(u16, constructor, 16)) +
        readInt(u16, constructor, 18);
    for (0..field_count) |_| {
        const value = readInt(u16, constructor, cursor);
        if (!try segmentValueAvailableAtTerminator(catalogs, source, value)) {
            return error.InvalidConstructor;
        }
        cursor += 8;
    }
}

fn segmentValueAvailableAtTerminator(
    catalogs: Catalogs,
    segment_id: u16,
    value: u16,
) Error!bool {
    if (value >= catalogs.value_count) return false;
    const schema = catalogs.schemas.node(valueSchema(catalogs, value)) catch
        return error.InvalidConstructor;
    if (schema.maximum_encoded_size == 0) return true;
    var available = [_]bool{false} ** maximum_catalog_entries;
    try addGuaranteedConstructorValues(catalogs, segment_id, &available);
    const segment = imageSegmentRecord(catalogs, segment_id) catch
        return error.InvalidConstructor;
    var cursor = segment_prefix_length +
        @as(usize, readInt(u16, segment, 10)) * 2;
    for (0..readInt(u32, segment, 12)) |_| {
        const end = recordEnd(segment, cursor, 16) catch
            return error.InvalidConstructor;
        available[readInt(u16, segment, cursor + 8)] = true;
        cursor = end;
    }
    return available[value];
}

fn imageTransitionEdge(
    catalogs: Catalogs,
    source: u16,
    edge_kind: u8,
    target: u16,
) Error![]const u8 {
    const segment = try imageSegmentRecord(catalogs, source);
    const terminator = imageSegmentTerminator(segment);
    const kind = segment[terminator + 4];
    const payload = terminator + 8;
    const edge = switch (edge_kind) {
        0 => if (kind == 0) segment[payload..] else return error.InvalidTransition,
        1 => if (kind == 1) segment[payload + 4 ..] else return error.InvalidTransition,
        2 => blk: {
            if (kind != 1) return error.InvalidTransition;
            const then_edge = payload + 4;
            break :blk segment[then_edge + imageEdgeLength(segment[then_edge..]) ..];
        },
        3, 4 => blk: {
            if (kind != 2) return error.InvalidTransition;
            const request_count = readInt(u16, segment, payload + 10);
            var cursor = payload + 12 + @as(usize, request_count) * 2;
            const callee_present = segment[cursor] == 1;
            cursor += 4;
            if (edge_kind == 3) {
                if (!callee_present) return error.InvalidTransition;
                break :blk segment[cursor..];
            }
            if (callee_present) cursor += imageEdgeLength(segment[cursor..]);
            break :blk segment[cursor..];
        },
        else => return error.InvalidTransition,
    };
    if (readInt(u16, edge, 0) != target) return error.InvalidTransition;
    return edge;
}

fn validateSegmentReachability(
    catalogs: Catalogs,
    segment_count: u32,
) Error!void {
    var reachable = [_]bool{false} ** maximum_segment_entries;
    var worklist: [maximum_segment_entries]u16 = undefined;
    var head: usize = 0;
    var tail: usize = 1;
    reachable[catalogs.entry_segment_id] = true;
    worklist[0] = catalogs.entry_segment_id;

    const transitions = catalogs.envelope.section(.entry_transitions);
    const transition_count = readInt(u32, transitions, 0);
    while (head < tail) : (head += 1) {
        const source = worklist[head];
        for (0..transition_count) |index| {
            const offset = 4 + index * 12;
            if (readInt(u16, transitions, offset) != source) continue;
            const target = readInt(u16, transitions, offset + 4);
            if (reachable[target]) continue;
            reachable[target] = true;
            worklist[tail] = target;
            tail += 1;
        }
    }
    for (reachable[0..segment_count]) |is_reachable| {
        if (!is_reachable) return error.UnreachableEntry;
    }
}

fn validateTransitionCompleteness(
    catalogs: Catalogs,
    transitions: []const u8,
    transition_count: u32,
) Error!void {
    const segments = catalogs.envelope.section(.segments);
    const segment_count = readInt(u32, segments, 0);
    var required_count: u32 = 0;
    for (0..segment_count) |source| {
        const segment = imageSegmentRecord(catalogs, @intCast(source)) catch
            return error.InvalidTransition;
        const terminator = imageSegmentTerminator(segment);
        const kind = segment[terminator + 4];
        const payload = terminator + 8;
        switch (kind) {
            0 => try requireTransition(
                transitions,
                transition_count,
                @intCast(source),
                0,
                readInt(u16, segment, payload),
                &required_count,
            ),
            1 => {
                const then_edge = payload + 4;
                const else_edge = then_edge + imageEdgeLength(segment[then_edge..]);
                try requireTransition(
                    transitions,
                    transition_count,
                    @intCast(source),
                    1,
                    readInt(u16, segment, then_edge),
                    &required_count,
                );
                try requireTransition(
                    transitions,
                    transition_count,
                    @intCast(source),
                    2,
                    readInt(u16, segment, else_edge),
                    &required_count,
                );
            },
            2 => {
                const request_count = readInt(u16, segment, payload + 10);
                var edge_cursor = payload + 12 + @as(usize, request_count) * 2;
                const callee_present = segment[edge_cursor] == 1;
                edge_cursor += 4;
                if (callee_present) {
                    try requireTransition(
                        transitions,
                        transition_count,
                        @intCast(source),
                        3,
                        readInt(u16, segment, edge_cursor),
                        &required_count,
                    );
                    edge_cursor += imageEdgeLength(segment[edge_cursor..]);
                }
                try requireTransition(
                    transitions,
                    transition_count,
                    @intCast(source),
                    4,
                    readInt(u16, segment, edge_cursor),
                    &required_count,
                );
            },
            else => {},
        }
    }
    if (required_count != transition_count) return error.InvalidTransition;
}

fn requireTransition(
    transitions: []const u8,
    count: u32,
    source: u16,
    edge: u8,
    target: u16,
    required_count: *u32,
) Error!void {
    for (0..count) |index| {
        const offset = 4 + index * 12;
        if (readInt(u16, transitions, offset) == source and
            transitions[offset + 2] == edge and
            readInt(u16, transitions, offset + 4) == target)
        {
            required_count.* += 1;
            return;
        }
    }
    return error.InvalidTransition;
}

fn imageConstructorRecord(
    catalogs: Catalogs,
    target: u32,
) Error![]const u8 {
    const bytes = catalogs.envelope.section(.constructors);
    var cursor: usize = 4;
    for (0..readInt(u32, bytes, 0)) |constructor| {
        const end = try recordEnd(bytes, cursor, segment_prefix_length);
        if (constructor == target) return bytes[cursor..end];
        cursor = end;
    }
    return error.InvalidTransition;
}

fn imageEdgeLength(edge: []const u8) usize {
    return 4 + @as(usize, readInt(u16, edge, 2)) * 4;
}

fn valueSchema(catalogs: Catalogs, value: u16) u32 {
    return readInt(u32, catalogs.values_section, 4 + @as(usize, value) * 4);
}

fn lexicographicallyLess(left: [3]u32, right: [3]u32) bool {
    for (left, right) |left_item, right_item| {
        if (left_item != right_item) return left_item < right_item;
    }
    return false;
}

fn recordEnd(bytes: []const u8, start: usize, minimum: usize) Error!usize {
    if (bytes.len - start < 4) return error.LengthMismatch;
    const length = readInt(u32, bytes, start);
    if (length < minimum) return error.LengthMismatch;
    const end = std.math.add(usize, start, length) catch
        return error.LengthOverflow;
    if (end > bytes.len) return error.LengthMismatch;
    return end;
}

fn takeCatalogSlice(
    bytes: []const u8,
    cursor: *usize,
    length: usize,
) Error![]const u8 {
    const end = std.math.add(usize, cursor.*, length) catch
        return error.LengthOverflow;
    if (end > bytes.len) return error.LengthMismatch;
    defer cursor.* = end;
    return bytes[cursor.*..end];
}

fn mapDynamicSchemaError(err: dynamic_value_v1.Error) Error {
    return switch (err) {
        error.LengthOverflow => error.LengthOverflow,
        error.LimitExceeded => error.LimitExceeded,
        else => error.InvalidSchema,
    };
}

fn maximumSingleValueBytes(schemas: dynamic_value_v1.Table) Error!u32 {
    var maximum: u64 = 0;
    for (schemas.nodes) |node| {
        maximum = @max(maximum, node.maximum_encoded_size);
    }
    return std.math.cast(u32, maximum) orelse error.LimitExceeded;
}

test "BPI1 rejects a schema maximum that its u32 header cannot represent" {
    var schema_bytes = [_]u8{0} ** 16;
    std.mem.writeInt(u32, schema_bytes[0..4], 1, .little);
    std.mem.writeInt(u32, schema_bytes[4..8], 12, .little);
    schema_bytes[8] = @intFromEnum(dynamic_value_v1.Kind.bytes);
    std.mem.writeInt(
        u32,
        schema_bytes[12..16],
        std.math.maxInt(u32),
        .little,
    );
    var nodes: [1]dynamic_value_v1.NodeIndex = undefined;
    const schemas = try dynamic_value_v1.validateSchemaSection(
        &schema_bytes,
        &nodes,
    );
    try std.testing.expectError(
        error.LimitExceeded,
        maximumSingleValueBytes(schemas),
    );
}

pub const SemanticHasher = std.crypto.hash.sha2.Sha256;

fn computeProgramTransitionDigest(
    catalogs: Catalogs,
    schema_tasks: []dynamic_value_v1.SchemaHashTask,
) Error![32]u8 {
    var hasher = SemanticHasher.init(.{});
    semanticHashBytes(&hasher, "boundary-program-transition-v1");
    try semanticHashSchema(
        &hasher,
        catalogs,
        catalogs.initial_args_schema_id,
        schema_tasks,
    );
    try semanticHashSchema(
        &hasher,
        catalogs,
        catalogs.result_schema_id,
        schema_tasks,
    );
    try semanticHashSchema(
        &hasher,
        catalogs,
        catalogs.failure_schema_id,
        schema_tasks,
    );
    try hashFailures(&hasher, catalogs.envelope.section(.failures));
    semanticHashU32(&hasher, catalogs.effect_count);
    try hashEffectContracts(&hasher, catalogs.envelope.section(.effects));
    semanticHashU32(&hasher, catalogs.value_count);
    for (0..catalogs.value_count) |value| {
        try semanticHashSchema(
            &hasher,
            catalogs,
            valueSchema(catalogs, @intCast(value)),
            schema_tasks,
        );
    }
    semanticHashU16(&hasher, catalogs.entry_segment_id);
    try semanticHashSchema(
        &hasher,
        catalogs,
        catalogs.result_schema_id,
        schema_tasks,
    );
    semanticHashU32(&hasher, catalogs.function_count);
    for (0..catalogs.function_count) |function| {
        const offset = 4 + function * 8;
        semanticHashU16(
            &hasher,
            readInt(u16, catalogs.functions_section, offset),
        );
        semanticHashU16(
            &hasher,
            readInt(u16, catalogs.functions_section, offset + 2),
        );
        try semanticHashSchema(
            &hasher,
            catalogs,
            readInt(u32, catalogs.functions_section, offset + 4),
            schema_tasks,
        );
    }
    try hashSegments(&hasher, catalogs, schema_tasks);
    try hashConstructors(&hasher, catalogs, schema_tasks);
    hashTransitions(&hasher, catalogs.envelope.section(.entry_transitions));
    semanticHashU32(&hasher, 0);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

pub fn semanticHashSchema(
    hasher: *SemanticHasher,
    catalogs: Catalogs,
    schema_id: u32,
    tasks: []dynamic_value_v1.SchemaHashTask,
) Error!void {
    const digest = dynamic_value_v1.schemaDigest(
        catalogs.schemas,
        schema_id,
        tasks,
    ) catch return error.InvalidSchema;
    hasher.update(&digest);
}

pub fn hashFailures(hasher: *SemanticHasher, bytes: []const u8) Error!void {
    semanticHashBytes(hasher, "failure-name-tag-map-v1");
    const count = readInt(u32, bytes, 0);
    semanticHashU32(hasher, count);
    var cursor: usize = 4;
    for (0..count) |_| {
        const tag = readInt(u32, bytes, cursor);
        cursor += 4;
        const length = readInt(u32, bytes, cursor);
        cursor += 4;
        const name = try takeCatalogSlice(bytes, &cursor, length);
        semanticHashBytes(hasher, name);
        semanticHashU32(hasher, tag);
    }
}

pub fn hashEffectContracts(hasher: *SemanticHasher, bytes: []const u8) Error!void {
    const count = readInt(u32, bytes, 0);
    var cursor: usize = 4;
    for (0..count) |_| {
        cursor += 4;
        const length = readInt(u32, bytes, cursor);
        cursor += 4 + length + 8 + 4 + 32;
        hasher.update(bytes[cursor..][0..32]);
        cursor += 32;
    }
}

fn hashSegments(
    hasher: *SemanticHasher,
    catalogs: Catalogs,
    schema_tasks: []dynamic_value_v1.SchemaHashTask,
) Error!void {
    const bytes = catalogs.envelope.section(.segments);
    const count = readInt(u32, bytes, 0);
    semanticHashU32(hasher, count);
    var cursor: usize = 4;
    for (0..count) |_| {
        const end = try recordEnd(bytes, cursor, segment_prefix_length);
        semanticHashU16(hasher, readInt(u16, bytes, cursor + 4));
        semanticHashU16(hasher, readInt(u16, bytes, cursor + 6));
        const parameter_count = readInt(u16, bytes, cursor + 10);
        const instruction_count = readInt(u32, bytes, cursor + 12);
        semanticHashU32(hasher, parameter_count);
        cursor += segment_prefix_length;
        for (0..parameter_count) |_| {
            semanticHashU16(hasher, readInt(u16, bytes, cursor));
            cursor += 2;
        }
        semanticHashU32(hasher, instruction_count);
        for (0..instruction_count) |_| {
            cursor = try hashInstruction(
                hasher,
                catalogs,
                schema_tasks,
                bytes,
                cursor,
            );
        }
        cursor = try hashTerminator(
            hasher,
            catalogs,
            schema_tasks,
            bytes,
            cursor,
        );
        if (cursor != end) return error.InvalidSegment;
    }
}

pub fn hashInstruction(
    hasher: *SemanticHasher,
    catalogs: Catalogs,
    schema_tasks: []dynamic_value_v1.SchemaHashTask,
    bytes: []const u8,
    start: usize,
) Error!usize {
    const end = try recordEnd(bytes, start, 16);
    semanticHashU8(hasher, bytes[start + 4]);
    semanticHashU16(hasher, readInt(u16, bytes, start + 8));
    const operand_count = readInt(u16, bytes, start + 10);
    semanticHashU32(hasher, operand_count);
    var cursor = start + 16;
    for (0..operand_count) |_| {
        semanticHashU16(hasher, readInt(u16, bytes, cursor));
        cursor += 2;
    }
    const wire: program_semantics_v1.WireOperation = @enumFromInt(
        readInt(u16, bytes, start + 6),
    );
    semanticHashU8(
        hasher,
        program_semantics_v1.currentSemanticTagForWire(wire),
    );
    const immediate = readInt(u32, bytes, start + 12);
    switch (wire) {
        .constant => try hashConstant(
            hasher,
            catalogs,
            schema_tasks,
            immediate,
        ),
        .product_extract,
        .product_replace,
        .sum_construct,
        .sum_tag_is,
        .sum_extract,
        => semanticHashU16(hasher, @intCast(immediate)),
        else => {},
    }
    return end;
}

fn hashConstant(
    hasher: *SemanticHasher,
    catalogs: Catalogs,
    schema_tasks: []dynamic_value_v1.SchemaHashTask,
    target: u32,
) Error!void {
    const bytes = catalogs.envelope.section(.constants);
    var cursor: usize = 4;
    for (0..catalogs.constant_count) |index| {
        const schema_id = readInt(u32, bytes, cursor);
        cursor += 4;
        const length = readInt(u32, bytes, cursor);
        cursor += 4;
        const value = try takeCatalogSlice(bytes, &cursor, length);
        if (index != target) continue;
        try semanticHashSchema(hasher, catalogs, schema_id, schema_tasks);
        semanticHashBytes(hasher, value);
        return;
    }
    return error.InvalidConstant;
}

pub fn hashTerminator(
    hasher: *SemanticHasher,
    catalogs: Catalogs,
    schema_tasks: []dynamic_value_v1.SchemaHashTask,
    bytes: []const u8,
    start: usize,
) Error!usize {
    const end = try recordEnd(bytes, start, 8);
    const kind = bytes[start + 4];
    semanticHashU8(hasher, kind);
    var cursor = start + 8;
    switch (kind) {
        0 => try hashEdge(hasher, bytes, &cursor),
        1 => {
            semanticHashU16(hasher, readInt(u16, bytes, cursor));
            cursor += 4;
            try hashEdge(hasher, bytes, &cursor);
            try hashEdge(hasher, bytes, &cursor);
        },
        2 => try hashSuspension(
            hasher,
            catalogs,
            schema_tasks,
            bytes,
            &cursor,
        ),
        3 => {
            const present = bytes[cursor] == 1;
            semanticHashBool(hasher, present);
            if (present) {
                semanticHashU16(hasher, readInt(u16, bytes, cursor + 2));
            }
            cursor += 4;
        },
        4, 6 => {
            semanticHashU16(hasher, readInt(u16, bytes, cursor));
            cursor += 4;
        },
        5 => {
            semanticHashU16(
                hasher,
                @intCast(readInt(u32, bytes, cursor)),
            );
            cursor += 4;
        },
        else => return error.InvalidTerminator,
    }
    if (cursor != end) return error.InvalidTerminator;
    return end;
}

fn hashSuspension(
    hasher: *SemanticHasher,
    catalogs: Catalogs,
    schema_tasks: []dynamic_value_v1.SchemaHashTask,
    bytes: []const u8,
    cursor: *usize,
) Error!void {
    const kind = bytes[cursor.*];
    const site = readInt(u32, bytes, cursor.* + 4);
    const callee_function = readInt(u16, bytes, cursor.* + 8);
    const request_count = readInt(u16, bytes, cursor.* + 10);
    const requests_start = cursor.* + 12;
    var edge_cursor = requests_start + @as(usize, request_count) * 2;
    const callee_present = bytes[edge_cursor] == 1;
    edge_cursor += 4;

    semanticHashU8(hasher, kind);
    semanticHashBool(hasher, site != std.math.maxInt(u32));
    if (site != std.math.maxInt(u32)) semanticHashU32(hasher, site);
    semanticHashBool(hasher, callee_function != std.math.maxInt(u16));
    if (callee_function != std.math.maxInt(u16)) {
        semanticHashU16(hasher, callee_function);
    }
    semanticHashBool(hasher, callee_present);
    if (callee_present) try hashEdge(hasher, bytes, &edge_cursor);
    semanticHashU32(hasher, request_count);
    var request_cursor = requests_start;
    for (0..request_count) |_| {
        semanticHashU16(hasher, readInt(u16, bytes, request_cursor));
        request_cursor += 2;
    }
    try hashEdge(hasher, bytes, &edge_cursor);
    const resume_schema = readInt(u32, bytes, edge_cursor);
    semanticHashBool(hasher, resume_schema != std.math.maxInt(u32));
    if (resume_schema != std.math.maxInt(u32)) {
        try semanticHashSchema(
            hasher,
            catalogs,
            resume_schema,
            schema_tasks,
        );
    }
    cursor.* = edge_cursor + 4;
}

pub fn hashEdge(
    hasher: *SemanticHasher,
    bytes: []const u8,
    cursor: *usize,
) Error!void {
    semanticHashU16(hasher, readInt(u16, bytes, cursor.*));
    const count = readInt(u16, bytes, cursor.* + 2);
    semanticHashU32(hasher, count);
    cursor.* += 4;
    for (0..count) |_| {
        const kind = bytes[cursor.*];
        semanticHashU8(hasher, kind);
        if (kind == 0) {
            semanticHashU16(hasher, readInt(u16, bytes, cursor.* + 2));
        } else if (kind != 1) {
            return error.InvalidTerminator;
        }
        cursor.* += 4;
    }
}

fn hashConstructors(
    hasher: *SemanticHasher,
    catalogs: Catalogs,
    schema_tasks: []dynamic_value_v1.SchemaHashTask,
) Error!void {
    const bytes = catalogs.envelope.section(.constructors);
    const count = readInt(u32, bytes, 0);
    semanticHashU32(hasher, count);
    var cursor: usize = 4;
    for (0..count) |_| {
        const end = try recordEnd(bytes, cursor, 24);
        semanticHashU32(hasher, readInt(u32, bytes, cursor + 4));
        semanticHashU8(hasher, bytes[cursor + 9]);
        semanticHashU16(hasher, readInt(u16, bytes, cursor + 12));
        const resume_target = readInt(u16, bytes, cursor + 14);
        semanticHashBool(hasher, resume_target != std.math.maxInt(u16));
        if (resume_target != std.math.maxInt(u16)) {
            semanticHashU16(hasher, resume_target);
        }
        semanticHashBool(
            hasher,
            readInt(u16, bytes, cursor + 10) & 1 == 1,
        );
        const activation_count = readInt(u16, bytes, cursor + 16);
        const environment_count = readInt(u16, bytes, cursor + 18);
        const invariant_count = readInt(u16, bytes, cursor + 20);
        semanticHashU32(hasher, activation_count);
        cursor += 24;
        for (0..activation_count) |_| {
            try hashEnvironmentField(
                hasher,
                catalogs,
                schema_tasks,
                bytes,
                &cursor,
            );
        }
        semanticHashU32(hasher, environment_count);
        for (0..environment_count) |_| {
            try hashEnvironmentField(
                hasher,
                catalogs,
                schema_tasks,
                bytes,
                &cursor,
            );
        }
        semanticHashU32(hasher, invariant_count);
        for (0..invariant_count) |_| {
            cursor = try hashInvariant(hasher, bytes, cursor);
        }
        if (cursor != end) return error.InvalidConstructor;
    }
}

pub fn hashEnvironmentField(
    hasher: *SemanticHasher,
    catalogs: Catalogs,
    schema_tasks: []dynamic_value_v1.SchemaHashTask,
    bytes: []const u8,
    cursor: *usize,
) Error!void {
    semanticHashU16(hasher, readInt(u16, bytes, cursor.*));
    try semanticHashSchema(
        hasher,
        catalogs,
        readInt(u32, bytes, cursor.* + 4),
        schema_tasks,
    );
    cursor.* += 8;
}

pub fn hashInvariant(
    hasher: *SemanticHasher,
    bytes: []const u8,
    start: usize,
) Error!usize {
    const end = try recordEnd(bytes, start, 8);
    const tag = bytes[start + 4];
    const payload = start + 8;
    semanticHashU8(hasher, tag);
    switch (tag) {
        0 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashBool(hasher, bytes[payload + 2] == 1);
        },
        1, 2, 5, 11, 16 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
        },
        3 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 4));
            semanticHashU8(hasher, bytes[payload + 6]);
        },
        4, 7 => {
            for (0..4) |index| {
                semanticHashU16(
                    hasher,
                    readInt(u16, bytes, payload + index * 2),
                );
            }
        },
        6 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            const value_kind = bytes[payload + 4];
            semanticHashU8(hasher, value_kind);
            const value = readInt(u64, bytes, payload + 12);
            switch (value_kind) {
                0 => semanticHashBool(hasher, value == 1),
                1, 2 => semanticHashU64(hasher, value),
                3 => semanticHashU16(hasher, @truncate(value)),
                else => return error.InvalidInvariant,
            }
        },
        8 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
            const operand_count = readInt(u16, bytes, payload + 4);
            semanticHashU16(hasher, operand_count);
            for (0..operand_count) |index| {
                semanticHashU16(
                    hasher,
                    readInt(u16, bytes, payload + 8 + index * 2),
                );
            }
        },
        9, 10 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 4));
        },
        12 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
            semanticHashU8(hasher, bytes[payload + 4]);
            semanticHashU8(hasher, bytes[payload + 5]);
        },
        13 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 4));
            semanticHashU8(hasher, bytes[payload + 6]);
            semanticHashU8(hasher, bytes[payload + 7]);
        },
        14 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
            semanticHashU8(hasher, bytes[payload + 4]);
        },
        15 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashBool(hasher, bytes[payload + 2] == 1);
        },
        17 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
            semanticHashU8(hasher, bytes[payload + 4]);
            semanticHashBool(hasher, bytes[payload + 5] == 1);
        },
        18 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 4));
            semanticHashU8(hasher, bytes[payload + 6]);
        },
        19 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
            semanticHashBool(hasher, bytes[payload + 4] == 1);
        },
        20 => {
            semanticHashU16(hasher, readInt(u16, bytes, payload));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 2));
            semanticHashU16(hasher, readInt(u16, bytes, payload + 4));
        },
        else => return error.InvalidInvariant,
    }
    return end;
}

fn hashTransitions(hasher: *SemanticHasher, bytes: []const u8) void {
    const count = readInt(u32, bytes, 0);
    semanticHashU32(hasher, count);
    for (0..count) |index| {
        const offset = 4 + index * 12;
        semanticHashU16(hasher, readInt(u16, bytes, offset));
        semanticHashU8(hasher, bytes[offset + 2]);
        semanticHashU16(hasher, readInt(u16, bytes, offset + 4));
        semanticHashU32(hasher, readInt(u32, bytes, offset + 8));
    }
}

pub fn semanticHashU32(hasher: anytype, value: u32) void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .little);
    hasher.update(&bytes);
}

pub fn semanticHashU8(hasher: anytype, value: u8) void {
    hasher.update(&.{value});
}

pub fn semanticHashU16(hasher: anytype, value: u16) void {
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, value, .little);
    hasher.update(&bytes);
}

pub fn semanticHashBool(hasher: anytype, value: bool) void {
    semanticHashU8(hasher, @intFromBool(value));
}

pub fn semanticHashU64(hasher: anytype, value: u64) void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .little);
    hasher.update(&bytes);
}

pub fn semanticHashBytes(hasher: anytype, value: []const u8) void {
    semanticHashU64(hasher, value.len);
    hasher.update(value);
}

fn readInt(
    comptime T: type,
    bytes: []const u8,
    offset: usize,
) T {
    return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .little);
}

fn allZero(bytes: []const u8) bool {
    for (bytes) |byte| {
        if (byte != 0) return false;
    }
    return true;
}

fn rangesOverlap(left: []const u8, right: []const u8) bool {
    if (left.len == 0 or right.len == 0) return false;
    const left_start = @intFromPtr(left.ptr);
    const right_start = @intFromPtr(right.ptr);
    const left_end = std.math.add(usize, left_start, left.len) catch return true;
    const right_end = std.math.add(usize, right_start, right.len) catch return true;
    return left_start < right_end and right_start < left_end;
}
