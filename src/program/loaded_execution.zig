// zlinter-disable declaration_naming field_naming field_ordering max_positional_args no_inferred_error_unions no_undefined require_doc_comment
const plan = @import("internal_program_plan");
const std = @import("std");

pub const loaded_value_image_format_version: u32 = 1;
pub const loaded_value_image_fingerprint_version: u32 = 1;
pub const loaded_session_image_format_version: u32 = 1;
pub const loaded_session_image_fingerprint_version: u32 = 1;
pub const loaded_execution_profile_format_version: u32 = 1;
pub const loaded_execution_profile_fingerprint_version: u32 = 1;
pub const executable_plan_image_format_version: u32 = 1;
pub const executable_plan_image_fingerprint_version: u32 = 1;

const max_u32_len = std.math.maxInt(u32);
const max_plan_table_count = std.math.maxInt(u16) + 1;
const max_session_diagnostic_summary_bytes = 4096;
const fingerprint_offset: u64 = 14695981039346656037;
const fingerprint_prime: u64 = 1099511628211;
const executable_plan_domain_name = "boundary.evidence.target.module.executable_plan_image";

pub const ExecutionFailureKind = enum(u16) {
    call_depth_exceeded,
    execution_budget_exceeded,
    integer_overflow,
    invalid_resume,
    invalid_value,
    malformed_plan,
    module_mismatch,
    unsupported_codec,
    unsupported_feature,
};

pub const LoadedSessionStatus = enum(u8) {
    initial,
    request,
    completed,
    failed,
};

pub const LoadedSessionBudgetLedger = struct {
    instructions_consumed: u64 = 0,
    advancements: u64 = 0,
};

pub const LoadedSessionFailure = struct {
    kind: ExecutionFailureKind,
    declared_error_ref: ?u64 = null,
    function_index: u32 = 0,
    block_index: u32 = 0,
    instruction_index: u32 = 0,
    diagnostic_summary: []const u8 = "",

    pub fn fingerprint(self: @This()) u64 {
        var hasher = StableHasher.init("boundary.loaded_session_failure");
        hasher.putU16(@intFromEnum(self.kind));
        hasher.optionalU64(self.declared_error_ref);
        hasher.putU32(self.function_index);
        hasher.putU32(self.block_index);
        hasher.putU32(self.instruction_index);
        hasher.bytes(self.diagnostic_summary);
        return hasher.finish();
    }
};

pub const LoadedSessionPendingRequest = struct {
    residual_site_index: u64,
    residual_site_fingerprint: u64,
    world_port_id: u32,
    payload_ref: LoadedValueRef,
    expected_response_ref: LoadedValueRef,
    canonical_request_fingerprint: u64,
    deterministic_continuation_fingerprint: u64,
    response_local: u16,
    result_local: u16,

    pub fn fingerprint(self: @This()) u64 {
        var hasher = StableHasher.init("boundary.loaded_session_pending_request");
        hasher.putU64(self.residual_site_index);
        hasher.putU64(self.residual_site_fingerprint);
        hasher.putU32(self.world_port_id);
        hasher.putU8(@intFromEnum(self.payload_ref.codec));
        hasher.optionalU16(self.payload_ref.schema_index);
        hasher.putU8(@intFromEnum(self.expected_response_ref.codec));
        hasher.optionalU16(self.expected_response_ref.schema_index);
        hasher.putU64(self.canonical_request_fingerprint);
        hasher.putU64(self.deterministic_continuation_fingerprint);
        hasher.putU16(self.response_local);
        hasher.putU16(self.result_local);
        return hasher.finish();
    }
};

pub const LoadedSessionImage = struct {
    format_version: u32 = loaded_session_image_format_version,
    fingerprint_version: u32 = loaded_session_image_fingerprint_version,
    module_fingerprint: u64,
    executable_plan_fingerprint: u64,
    execution_profile_fingerprint: u64,
    session_fingerprint: u64,
    entry_function: u16,
    budget: LoadedSessionBudgetLedger = .{},
    status: LoadedSessionStatus = .initial,
    pending_request: ?LoadedSessionPendingRequest = null,
    payload_image_bytes: []const u8 = &.{},
    result_image_bytes: []const u8 = &.{},
    result_fingerprint: u64 = 0,
    failure: ?LoadedSessionFailure = null,
    dependency_fingerprint: u64 = 0,
    owns_payload_image_bytes: bool = false,
    owns_result_image_bytes: bool = false,
    owns_failure_summary: bool = false,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        if (self.owns_payload_image_bytes and self.payload_image_bytes.len != 0) allocator.free(self.payload_image_bytes);
        if (self.owns_result_image_bytes and self.result_image_bytes.len != 0) allocator.free(self.result_image_bytes);
        if (self.owns_failure_summary) {
            if (self.failure) |failure| allocator.free(failure.diagnostic_summary);
        }
        self.* = undefined;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var hasher = StableHasher.init("boundary.loaded_session_image");
        hasher.putU32(loaded_session_image_fingerprint_version);
        hasher.putU64(self.module_fingerprint);
        hasher.putU64(self.executable_plan_fingerprint);
        hasher.putU64(self.execution_profile_fingerprint);
        hasher.putU64(self.session_fingerprint);
        hasher.putU16(self.entry_function);
        hasher.putU64(self.budget.instructions_consumed);
        hasher.putU64(self.budget.advancements);
        hasher.putU8(@intFromEnum(self.status));
        if (self.pending_request) |pending_request| {
            hasher.putU8(1);
            hasher.putU64(pending_request.fingerprint());
        } else {
            hasher.putU8(0);
        }
        hasher.bytes(self.payload_image_bytes);
        hasher.bytes(self.result_image_bytes);
        hasher.putU64(self.result_fingerprint);
        if (self.failure) |failure| {
            hasher.putU8(1);
            hasher.putU64(failure.fingerprint());
        } else {
            hasher.putU8(0);
        }
        hasher.putU64(self.dependency_fingerprint);
        return hasher.finish();
    }

    pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]u8 {
        try self.validateState();
        if (self.failure) |failure| {
            if (failure.diagnostic_summary.len > max_session_diagnostic_summary_bytes) return error.InvalidValue;
        }
        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(allocator);
        try writeU32(&out, allocator, self.format_version);
        try writeU32(&out, allocator, self.fingerprint_version);
        try writeU64(&out, allocator, self.module_fingerprint);
        try writeU64(&out, allocator, self.executable_plan_fingerprint);
        try writeU64(&out, allocator, self.execution_profile_fingerprint);
        try writeU64(&out, allocator, self.session_fingerprint);
        try writeU16(&out, allocator, self.entry_function);
        try writeU64(&out, allocator, self.budget.instructions_consumed);
        try writeU64(&out, allocator, self.budget.advancements);
        try out.append(allocator, @intFromEnum(self.status));
        if (self.pending_request) |pending_request| {
            try out.append(allocator, 1);
            try writeU64(&out, allocator, pending_request.residual_site_index);
            try writeU64(&out, allocator, pending_request.residual_site_fingerprint);
            try writeU32(&out, allocator, pending_request.world_port_id);
            try encodeSessionValueRef(&out, allocator, pending_request.payload_ref);
            try encodeSessionValueRef(&out, allocator, pending_request.expected_response_ref);
            try writeU64(&out, allocator, pending_request.canonical_request_fingerprint);
            try writeU64(&out, allocator, pending_request.deterministic_continuation_fingerprint);
            try writeU16(&out, allocator, pending_request.response_local);
            try writeU16(&out, allocator, pending_request.result_local);
        } else {
            try out.append(allocator, 0);
        }
        try writeBytes(&out, allocator, self.payload_image_bytes);
        try writeBytes(&out, allocator, self.result_image_bytes);
        try writeU64(&out, allocator, self.result_fingerprint);
        if (self.failure) |failure| {
            try out.append(allocator, 1);
            try writeU16(&out, allocator, @intFromEnum(failure.kind));
            try encodeOptionalU64(&out, allocator, failure.declared_error_ref);
            try writeU32(&out, allocator, failure.function_index);
            try writeU32(&out, allocator, failure.block_index);
            try writeU32(&out, allocator, failure.instruction_index);
            try writeBytes(&out, allocator, failure.diagnostic_summary);
        } else {
            try out.append(allocator, 0);
        }
        try writeU64(&out, allocator, self.dependency_fingerprint);
        try writeU64(&out, allocator, self.computeFingerprint());
        return out.toOwnedSlice(allocator);
    }

    pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !@This() {
        var cursor = SessionCursor{ .bytes = bytes };
        var image = LoadedSessionImage{
            .format_version = try cursor.readU32(),
            .fingerprint_version = try cursor.readU32(),
            .module_fingerprint = try cursor.readU64(),
            .executable_plan_fingerprint = try cursor.readU64(),
            .execution_profile_fingerprint = try cursor.readU64(),
            .session_fingerprint = try cursor.readU64(),
            .entry_function = try cursor.readU16(),
            .budget = .{
                .instructions_consumed = try cursor.readU64(),
                .advancements = try cursor.readU64(),
            },
            .status = try decodeSessionStatus(try cursor.readU8()),
        };
        errdefer image.deinit(allocator);
        if (image.format_version != loaded_session_image_format_version) return error.UnsupportedVersion;
        if (image.fingerprint_version != loaded_session_image_fingerprint_version) return error.UnsupportedVersion;
        const has_pending_request = switch (try cursor.readU8()) {
            0 => false,
            1 => true,
            else => return error.MalformedSessionImage,
        };
        if (has_pending_request) {
            image.pending_request = .{
                .residual_site_index = try cursor.readU64(),
                .residual_site_fingerprint = try cursor.readU64(),
                .world_port_id = try cursor.readU32(),
                .payload_ref = try cursor.readSessionValueRef(),
                .expected_response_ref = try cursor.readSessionValueRef(),
                .canonical_request_fingerprint = try cursor.readU64(),
                .deterministic_continuation_fingerprint = try cursor.readU64(),
                .response_local = try cursor.readU16(),
                .result_local = try cursor.readU16(),
            };
        }
        image.payload_image_bytes = try cursor.readOwnedBytes(allocator, std.math.maxInt(u32));
        image.owns_payload_image_bytes = true;
        image.result_image_bytes = try cursor.readOwnedBytes(allocator, std.math.maxInt(u32));
        image.owns_result_image_bytes = true;
        image.result_fingerprint = try cursor.readU64();
        const has_failure = switch (try cursor.readU8()) {
            0 => false,
            1 => true,
            else => return error.MalformedSessionImage,
        };
        if (has_failure) {
            const kind = try decodeFailureKind(try cursor.readU16());
            const declared_error_ref = try cursor.readOptionalU64();
            const function_index = try cursor.readU32();
            const block_index = try cursor.readU32();
            const instruction_index = try cursor.readU32();
            const diagnostic_summary = try cursor.readOwnedBytes(allocator, max_session_diagnostic_summary_bytes);
            image.failure = .{
                .kind = kind,
                .declared_error_ref = declared_error_ref,
                .function_index = function_index,
                .block_index = block_index,
                .instruction_index = instruction_index,
                .diagnostic_summary = diagnostic_summary,
            };
            image.owns_failure_summary = true;
        }
        image.dependency_fingerprint = try cursor.readU64();
        const expected_fingerprint = try cursor.readU64();
        if (cursor.remaining() != 0) return error.TrailingBytes;
        try image.validateState();
        if (expected_fingerprint != image.computeFingerprint()) return error.FingerprintMismatch;
        return image;
    }

    fn validateState(self: @This()) !void {
        if (self.status == .failed and self.failure == null) return error.MalformedSessionImage;
        if (self.status != .failed and self.failure != null) return error.MalformedSessionImage;
        if (self.status == .request and self.pending_request == null) return error.MalformedSessionImage;
        if (self.status != .request and self.pending_request != null) return error.MalformedSessionImage;
        if (self.status == .request and self.payload_image_bytes.len == 0) return error.MalformedSessionImage;
        if (self.status != .completed and self.result_image_bytes.len != 0) return error.MalformedSessionImage;
        if (self.status != .completed and self.result_fingerprint != 0) return error.MalformedSessionImage;
        if (self.status == .completed and self.result_image_bytes.len == 0 and self.result_fingerprint != 0) return error.MalformedSessionImage;
    }
};

pub fn loadedSessionFingerprint(module_fingerprint: u64, executable_plan_fingerprint: u64, execution_profile_fingerprint: u64, entry_function: u16) u64 {
    var hasher = StableHasher.init("boundary.loaded_session");
    hasher.putU32(loaded_session_image_fingerprint_version);
    hasher.putU64(module_fingerprint);
    hasher.putU64(executable_plan_fingerprint);
    hasher.putU64(execution_profile_fingerprint);
    hasher.putU16(entry_function);
    return hasher.finish();
}

pub const ArithmeticSemantics = enum(u8) {
    checked_twos_complement,
};

pub const IntegerWidthSemantics = enum(u8) {
    portable_u64_word,
};

pub const RecursionPolicy = enum(u8) {
    reject_without_static_witness,
    allow_with_static_bound,
};

pub const HostIntrinsicPolicy = enum(u8) {
    reject,
    residualize_as_world_port,
};

pub const NestedModuleCallPolicy = enum(u8) {
    module_local_only,
    sealed_module_export,
};

pub const ErrorTablePolicy = enum(u8) {
    stable_declared_errors_only,
};

pub const Limits = struct {
    maximum_call_depth: u32 = 64,
    maximum_value_nesting_depth: u32 = 32,
    maximum_locals_per_frame: u32 = 256,
    maximum_frames: u32 = 256,
    maximum_instructions_per_advancement: u32 = 100_000,
    maximum_owned_value_bytes: u32 = 1 << 20,
    maximum_string_bytes: u32 = 64 << 10,
    maximum_aggregate_elements: u32 = 4096,
};

pub const InstructionFeatureSet = packed struct(u64) {
    @"const": bool = false,
    copy_local: bool = false,
    call_op: bool = false,
    call_helper: bool = false,
    call_nested_with: bool = false,
    compare: bool = false,
    return_value: bool = false,
    return_error: bool = false,
    const_i32: bool = false,
    const_usize: bool = false,
    const_bool: bool = false,
    const_string: bool = false,
    get_product_field: bool = false,
    make_product: bool = false,
    make_sum: bool = false,
    match_sum_variant: bool = false,
    get_sum_payload: bool = false,
    _reserved: u47 = 0,
};

pub const TerminatorFeatureSet = packed struct(u64) {
    return_unit: bool = false,
    return_value: bool = false,
    branch: bool = false,
    branch_if: bool = false,
    _reserved: u60 = 0,
};

pub const ValueCodecFeatureSet = packed struct(u16) {
    unit: bool = false,
    bool: bool = false,
    i32: bool = false,
    word_u64: bool = false,
    bytes: bool = false,
    byte_string_list: bool = false,
    product: bool = false,
    sum: bool = false,
    _reserved: u8 = 0,
};

pub const LoadedExecutionProfile = struct {
    format_version: u32 = loaded_execution_profile_format_version,
    fingerprint_version: u32 = loaded_execution_profile_fingerprint_version,
    instruction_kinds: InstructionFeatureSet = portable_v1_instruction_kinds,
    terminator_kinds: TerminatorFeatureSet = portable_v1_terminator_kinds,
    value_codecs: ValueCodecFeatureSet = portable_v1_value_codecs,
    arithmetic_semantics: ArithmeticSemantics = .checked_twos_complement,
    integer_width_semantics: IntegerWidthSemantics = .portable_u64_word,
    limits: Limits = .{},
    recursion_policy: RecursionPolicy = .reject_without_static_witness,
    host_intrinsic_policy: HostIntrinsicPolicy = .residualize_as_world_port,
    nested_module_call_policy: NestedModuleCallPolicy = .sealed_module_export,
    error_table_policy: ErrorTablePolicy = .stable_declared_errors_only,

    pub const portable_v1_instruction_kinds = InstructionFeatureSet{
        .@"const" = true,
        .copy_local = true,
        .call_op = true,
        .call_helper = true,
        .call_nested_with = true,
        .compare = true,
        .return_value = true,
        .return_error = true,
        .const_i32 = true,
        .const_usize = true,
        .const_bool = true,
        .const_string = true,
        .get_product_field = true,
        .make_product = true,
        .make_sum = true,
        .match_sum_variant = true,
        .get_sum_payload = true,
    };
    pub const portable_v1_terminator_kinds = TerminatorFeatureSet{
        .return_unit = true,
        .return_value = true,
        .branch = true,
        .branch_if = true,
    };
    pub const portable_v1_value_codecs = ValueCodecFeatureSet{
        .unit = true,
        .bool = true,
        .i32 = true,
        .word_u64 = true,
        .bytes = true,
        .byte_string_list = true,
        .product = true,
        .sum = true,
    };

    pub fn portableV1() @This() {
        return .{};
    }

    pub fn compatibleWith(self: @This(), required: @This()) bool {
        if (required.format_version != loaded_execution_profile_format_version) return false;
        if (required.fingerprint_version != loaded_execution_profile_fingerprint_version) return false;
        if (!instructionSubset(required.instruction_kinds, self.instruction_kinds)) return false;
        if (!terminatorSubset(required.terminator_kinds, self.terminator_kinds)) return false;
        if (!codecSubset(required.value_codecs, self.value_codecs)) return false;
        if (required.arithmetic_semantics != self.arithmetic_semantics) return false;
        if (required.integer_width_semantics != self.integer_width_semantics) return false;
        if (required.recursion_policy != self.recursion_policy) return false;
        if (required.host_intrinsic_policy != self.host_intrinsic_policy) return false;
        if (required.nested_module_call_policy != self.nested_module_call_policy) return false;
        if (required.error_table_policy != self.error_table_policy) return false;
        return self.limits.maximum_call_depth >= required.limits.maximum_call_depth and
            self.limits.maximum_value_nesting_depth >= required.limits.maximum_value_nesting_depth and
            self.limits.maximum_locals_per_frame >= required.limits.maximum_locals_per_frame and
            self.limits.maximum_frames >= required.limits.maximum_frames and
            self.limits.maximum_instructions_per_advancement >= required.limits.maximum_instructions_per_advancement and
            self.limits.maximum_owned_value_bytes >= required.limits.maximum_owned_value_bytes and
            self.limits.maximum_string_bytes >= required.limits.maximum_string_bytes and
            self.limits.maximum_aggregate_elements >= required.limits.maximum_aggregate_elements;
    }

    pub fn encode(self: @This(), allocator: std.mem.Allocator) ![]u8 {
        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(allocator);
        try writeU32(&out, allocator, self.format_version);
        try writeU32(&out, allocator, self.fingerprint_version);
        try writeU64(&out, allocator, @as(u64, @bitCast(self.instruction_kinds)));
        try writeU64(&out, allocator, @as(u64, @bitCast(self.terminator_kinds)));
        try writeU16(&out, allocator, @as(u16, @bitCast(self.value_codecs)));
        try out.append(allocator, @intFromEnum(self.arithmetic_semantics));
        try out.append(allocator, @intFromEnum(self.integer_width_semantics));
        try writeU32(&out, allocator, self.limits.maximum_call_depth);
        try writeU32(&out, allocator, self.limits.maximum_value_nesting_depth);
        try writeU32(&out, allocator, self.limits.maximum_locals_per_frame);
        try writeU32(&out, allocator, self.limits.maximum_frames);
        try writeU32(&out, allocator, self.limits.maximum_instructions_per_advancement);
        try writeU32(&out, allocator, self.limits.maximum_owned_value_bytes);
        try writeU32(&out, allocator, self.limits.maximum_string_bytes);
        try writeU32(&out, allocator, self.limits.maximum_aggregate_elements);
        try out.append(allocator, @intFromEnum(self.recursion_policy));
        try out.append(allocator, @intFromEnum(self.host_intrinsic_policy));
        try out.append(allocator, @intFromEnum(self.nested_module_call_policy));
        try out.append(allocator, @intFromEnum(self.error_table_policy));
        return out.toOwnedSlice(allocator);
    }

    pub fn fingerprint(self: @This(), allocator: std.mem.Allocator) !u64 {
        _ = allocator;
        return self.computeFingerprint();
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var hasher = StableHasher.init("boundary.loaded_execution_profile");
        hasher.putU32(loaded_execution_profile_fingerprint_version);
        hasher.putU32(self.format_version);
        hasher.putU32(self.fingerprint_version);
        hasher.putU64(@as(u64, @bitCast(self.instruction_kinds)));
        hasher.putU64(@as(u64, @bitCast(self.terminator_kinds)));
        hasher.putU16(@as(u16, @bitCast(self.value_codecs)));
        hasher.putU8(@intFromEnum(self.arithmetic_semantics));
        hasher.putU8(@intFromEnum(self.integer_width_semantics));
        hasher.putU32(self.limits.maximum_call_depth);
        hasher.putU32(self.limits.maximum_value_nesting_depth);
        hasher.putU32(self.limits.maximum_locals_per_frame);
        hasher.putU32(self.limits.maximum_frames);
        hasher.putU32(self.limits.maximum_instructions_per_advancement);
        hasher.putU32(self.limits.maximum_owned_value_bytes);
        hasher.putU32(self.limits.maximum_string_bytes);
        hasher.putU32(self.limits.maximum_aggregate_elements);
        hasher.putU8(@intFromEnum(self.recursion_policy));
        hasher.putU8(@intFromEnum(self.host_intrinsic_policy));
        hasher.putU8(@intFromEnum(self.nested_module_call_policy));
        hasher.putU8(@intFromEnum(self.error_table_policy));
        return hasher.finish();
    }
};

pub const DecodedExecutablePlan = struct {
    arena: std.heap.ArenaAllocator,
    image_fingerprint: u64,
    body_fingerprint: u64,
    feature_bitmap: u64,
    stable_error_count: u64,
    nested_ref_count: u64,
    program_plan: plan.ProgramPlan,

    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub fn decodeExecutablePlanImage(
    allocator: std.mem.Allocator,
    payload: []const u8,
    expected_image_fingerprint: u64,
    expected_plan_hash: u64,
    limits: Limits,
) !DecodedExecutablePlan {
    _ = limits;
    var envelope = PlanCursor{ .bytes = payload };
    const format_version = try envelope.readU32();
    if (format_version != executable_plan_image_format_version) return error.UnsupportedVersion;
    const image_fingerprint = try envelope.readU64();
    const body_bytes = try envelope.readBytes();
    if (envelope.remaining() != 0) return error.TrailingBytes;
    if (image_fingerprint != expected_image_fingerprint) return error.FingerprintMismatch;
    const body_fingerprint = executablePlanBodyFingerprint(body_bytes);
    if (body_fingerprint != image_fingerprint) return error.FingerprintMismatch;

    var decoded = DecodedExecutablePlan{
        .arena = std.heap.ArenaAllocator.init(allocator),
        .image_fingerprint = image_fingerprint,
        .body_fingerprint = body_fingerprint,
        .feature_bitmap = 0,
        .stable_error_count = 0,
        .nested_ref_count = 0,
        .program_plan = undefined,
    };
    errdefer decoded.deinit();
    const arena = decoded.arena.allocator();

    var body = PlanCursor{ .bytes = body_bytes };
    const label = try arena.dupe(u8, try body.readBytes());
    const plan_hash = try body.readU64();
    const ir_hash = try body.readU64();
    const entry_index = try body.readU16();
    const feature_bitmap = try body.readU64();
    const function_count = try readPlanCount(&body, max_plan_table_count);
    const requirement_count = try readPlanCount(&body, max_plan_table_count);
    const op_count = try readPlanCount(&body, max_plan_table_count);
    const output_count = try readPlanCount(&body, max_plan_table_count);
    const value_schema_count = try readPlanCount(&body, max_plan_table_count);
    const value_field_count = try readPlanCount(&body, max_plan_table_count);
    const value_variant_count = try readPlanCount(&body, max_plan_table_count);
    const local_count = try readPlanCount(&body, max_plan_table_count);
    const call_arg_count = try readPlanCount(&body, max_plan_table_count);
    const block_count = try readPlanCount(&body, max_plan_table_count);
    const terminator_count = try readPlanCount(&body, max_plan_table_count);
    const instruction_count = try readPlanCount(&body, max_plan_table_count);
    const string_literal_count = try readPlanCount(&body, max_plan_table_count);
    const stable_error_count = try body.readU64();
    const nested_ref_count = try readPlanCount(&body, max_plan_table_count);
    if (plan_hash != expected_plan_hash) return error.FingerprintMismatch;
    if (entry_index >= function_count) return error.MalformedPlan;

    const functions = try arena.alloc(plan.FunctionPlan, function_count);
    for (functions) |*function| {
        const symbol_name = try arena.dupe(u8, try body.readBytes());
        const value_ref = try body.readWireValueRef();
        const result_ref = try body.readOptionalWireValueRef();
        function.* = .{
            .symbol_name = symbol_name,
            .value_codec = value_ref.codec,
            .value_schema_index = value_ref.schema_index,
            .result_codec = if (result_ref) |ref| ref.codec else null,
            .result_schema_index = if (result_ref) |ref| ref.schema_index else null,
            .parameter_count = try body.readU16(),
            .first_requirement = try body.readU16(),
            .requirement_count = try body.readU16(),
            .first_output = try body.readU16(),
            .output_count = try body.readU16(),
            .first_local = try body.readU16(),
            .local_count = try body.readU16(),
            .first_block = try body.readU16(),
            .entry_block = try body.readU16(),
            .block_count = try body.readU16(),
            .first_instruction = try body.readU16(),
            .instruction_count = try body.readU16(),
        };
    }

    const requirements = try arena.alloc(plan.RequirementPlan, requirement_count);
    for (requirements) |*requirement| {
        requirement.* = .{
            .label = try arena.dupe(u8, try body.readBytes()),
            .first_op = try body.readU16(),
            .op_count = try body.readU16(),
            .lifecycle_tag = try body.readEnum(plan.RequirementLifecycleTag),
            .output_tag = try body.readEnum(plan.RequirementOutputTag),
        };
    }

    const ops = try arena.alloc(plan.OpPlan, op_count);
    for (ops) |*op| {
        const requirement_index = try body.readU16();
        const op_name = try arena.dupe(u8, try body.readBytes());
        const mode = try body.readEnum(plan.ControlMode);
        const payload_ref = try body.readWireValueRef();
        const resume_ref = try body.readWireValueRef();
        op.* = .{
            .requirement_index = requirement_index,
            .op_name = op_name,
            .mode = mode,
            .payload_codec = payload_ref.codec,
            .payload_schema_index = payload_ref.schema_index,
            .resume_codec = resume_ref.codec,
            .resume_schema_index = resume_ref.schema_index,
            .has_after = try body.readBool(),
        };
    }

    const outputs = try arena.alloc(plan.OutputPlan, output_count);
    for (outputs) |*output| {
        const output_ref = try body.readWireValueRefAfterBytes(arena);
        output.* = .{
            .label = output_ref.label,
            .codec = output_ref.ref.codec,
            .schema_index = output_ref.ref.schema_index,
        };
    }

    const value_schemas = try arena.alloc(plan.ValueSchemaPlan, value_schema_count);
    for (value_schemas) |*schema| {
        schema.* = .{
            .label = try arena.dupe(u8, try body.readBytes()),
            .codec = try body.readEnum(plan.ValueCodec),
            .first_field = try body.readU16(),
            .field_count = try body.readU16(),
            .first_variant = try body.readU16(),
            .variant_count = try body.readU16(),
        };
    }

    const value_fields = try arena.alloc(plan.ValueFieldPlan, value_field_count);
    for (value_fields) |*field| {
        const field_ref = try body.readWireValueRefAfterBytes(arena);
        field.* = .{
            .name = field_ref.label,
            .codec = field_ref.ref.codec,
            .schema_index = field_ref.ref.schema_index,
        };
    }

    const value_variants = try arena.alloc(plan.ValueVariantPlan, value_variant_count);
    for (value_variants) |*variant| {
        const variant_ref = try body.readWireValueRefAfterBytes(arena);
        variant.* = .{
            .name = variant_ref.label,
            .codec = variant_ref.ref.codec,
            .schema_index = variant_ref.ref.schema_index,
        };
    }

    const locals = try arena.alloc(plan.LocalPlan, local_count);
    for (locals) |*local| {
        const local_ref = try body.readWireValueRef();
        local.* = .{ .codec = local_ref.codec, .schema_index = local_ref.schema_index };
    }

    const call_args = try arena.alloc(u16, call_arg_count);
    for (call_args) |*call_arg| call_arg.* = try body.readU16();

    const blocks = try arena.alloc(plan.BlockPlan, block_count);
    for (blocks) |*block| {
        block.* = .{
            .first_instruction = try body.readU16(),
            .instruction_count = try body.readU16(),
            .terminator_index = try body.readU16(),
        };
    }

    const terminators = try arena.alloc(plan.Terminator, terminator_count);
    for (terminators) |*terminator| {
        terminator.* = .{
            .kind = try body.readEnum(plan.TerminatorKind),
            .primary = try body.readU16(),
            .secondary = try body.readU16(),
        };
    }

    const instructions = try arena.alloc(plan.Instruction, instruction_count);
    var actual_string_literal_count: usize = 0;
    var actual_nested_ref_count: usize = 0;
    for (instructions) |*instruction| {
        const kind = try body.readEnum(plan.InstructionKind);
        const dst = try body.readU16();
        const operand = try body.readU16();
        const aux = try body.readU16();
        const literal = try arena.dupe(u8, try body.readBytes());
        if (literal.len != 0) actual_string_literal_count += 1;
        if (kind == .call_nested_with) actual_nested_ref_count += 1;
        instruction.* = .{
            .kind = kind,
            .dst = dst,
            .operand = operand,
            .aux = aux,
            .string_literal = literal,
        };
    }
    if (actual_string_literal_count != string_literal_count or actual_nested_ref_count != nested_ref_count) return error.MalformedPlan;
    for (0..string_literal_count) |_| _ = try body.readBytes();
    for (0..nested_ref_count) |_| {
        _ = try body.readU16();
        _ = try body.readU16();
    }
    if (body.remaining() != 0) return error.TrailingBytes;

    decoded.feature_bitmap = feature_bitmap;
    decoded.stable_error_count = stable_error_count;
    decoded.nested_ref_count = nested_ref_count;
    decoded.program_plan = .{
        .label = label,
        .ir_hash = ir_hash,
        .entry_index = entry_index,
        .functions = functions,
        .requirements = requirements,
        .ops = ops,
        .outputs = outputs,
        .value_schemas = value_schemas,
        .value_fields = value_fields,
        .value_variants = value_variants,
        .locals = locals,
        .call_args = call_args,
        .blocks = blocks,
        .terminators = terminators,
        .instructions = instructions,
    };
    try decoded.program_plan.validate();
    if (decoded.program_plan.hash() != expected_plan_hash) return error.FingerprintMismatch;
    return decoded;
}

pub fn executablePlanImageFingerprint(payload: []const u8) !u64 {
    var envelope = PlanCursor{ .bytes = payload };
    const format_version = try envelope.readU32();
    if (format_version != executable_plan_image_format_version) return error.UnsupportedVersion;
    return try envelope.readU64();
}

fn instructionSubset(required: InstructionFeatureSet, supported: InstructionFeatureSet) bool {
    return (@as(u64, @bitCast(required)) & ~@as(u64, @bitCast(supported))) == 0;
}

fn terminatorSubset(required: TerminatorFeatureSet, supported: TerminatorFeatureSet) bool {
    return (@as(u64, @bitCast(required)) & ~@as(u64, @bitCast(supported))) == 0;
}

fn codecSubset(required: ValueCodecFeatureSet, supported: ValueCodecFeatureSet) bool {
    return (@as(u16, @bitCast(required)) & ~@as(u16, @bitCast(supported))) == 0;
}

pub const LoadedValueRef = plan.ValueRef;

pub const LoadedValueError = error{
    OutOfMemory,
    InvalidValue,
    UnsupportedCodec,
    UnsupportedVersion,
    SchemaIndexRequired,
    SchemaIndexOutOfRange,
    SchemaCodecMismatch,
    SchemaFieldOutOfRange,
    SchemaVariantOutOfRange,
    NestingDepthExceeded,
    AggregateElementLimitExceeded,
    OwnedValueBytesLimitExceeded,
    StringBytesLimitExceeded,
    TrailingBytes,
    TruncatedImage,
    FingerprintMismatch,
    MalformedValueImage,
    IntegerOverflow,
};

pub const SchemaSet = struct {
    schemas: []const plan.ValueSchemaPlan = &.{},
    fields: []const plan.ValueFieldPlan = &.{},
    variants: []const plan.ValueVariantPlan = &.{},

    pub fn schemaFingerprint(self: @This()) u64 {
        var hasher = StableHasher.init("boundary.loaded_value_schema");
        hasher.putU32(loaded_value_image_fingerprint_version);
        hasher.putU32(@intCast(self.schemas.len));
        for (self.schemas) |schema| {
            hasher.bytes(schema.label);
            hasher.putU8(@intFromEnum(schema.codec));
            hasher.putU16(schema.first_field);
            hasher.putU16(schema.field_count);
            hasher.putU16(schema.first_variant);
            hasher.putU16(schema.variant_count);
        }
        hasher.putU32(@intCast(self.fields.len));
        for (self.fields) |field| {
            hasher.bytes(field.name);
            hasher.putU8(@intFromEnum(field.codec));
            hasher.optionalU16(field.schema_index);
        }
        hasher.putU32(@intCast(self.variants.len));
        for (self.variants) |variant| {
            hasher.bytes(variant.name);
            hasher.putU8(@intFromEnum(variant.codec));
            hasher.optionalU16(variant.schema_index);
        }
        return hasher.finish();
    }

    fn requireValueRef(self: @This(), ref: LoadedValueRef) LoadedValueError!void {
        switch (ref.codec) {
            .product, .sum => {
                const index = ref.schema_index orelse return error.SchemaIndexRequired;
                if (index >= self.schemas.len) return error.SchemaIndexOutOfRange;
                const schema = self.schemas[index];
                if (schema.codec != ref.codec) return error.SchemaCodecMismatch;
                if (schema.first_field > self.fields.len) return error.SchemaFieldOutOfRange;
                if (@as(usize, schema.first_field) + schema.field_count > self.fields.len) return error.SchemaFieldOutOfRange;
                if (schema.first_variant > self.variants.len) return error.SchemaVariantOutOfRange;
                if (@as(usize, schema.first_variant) + schema.variant_count > self.variants.len) return error.SchemaVariantOutOfRange;
            },
            else => if (ref.schema_index != null) return error.SchemaCodecMismatch,
        }
    }
};

pub const LoadedValue = union(enum) {
    unit,
    boolean: bool,
    i32: i32,
    word_u64: u64,
    bytes: []const u8,
    list: []const []const u8,
    product: []const LoadedValue,
    sum: Sum,

    pub const Sum = struct {
        variant_index: u32,
        payload: ?*const LoadedValue = null,
    };
};

pub const LoadedValueArena = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init(backing_allocator: std.mem.Allocator) @This() {
        return .{ .arena = std.heap.ArenaAllocator.init(backing_allocator) };
    }

    pub fn deinit(self: *@This()) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn allocator(self: *@This()) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn dupeBytes(self: *@This(), bytes: []const u8) ![]const u8 {
        return try self.allocator().dupe(u8, bytes);
    }

    pub fn dupeByteList(self: *@This(), values: []const []const u8) ![]const []const u8 {
        const out = try self.allocator().alloc([]const u8, values.len);
        for (values, 0..) |value, index| out[index] = try self.dupeBytes(value);
        return out;
    }

    pub fn dupeValues(self: *@This(), values: []const LoadedValue) ![]const LoadedValue {
        return try self.allocator().dupe(LoadedValue, values);
    }

    pub fn createValue(self: *@This(), value: LoadedValue) !*const LoadedValue {
        const out = try self.allocator().create(LoadedValue);
        out.* = value;
        return out;
    }
};

pub const LoadedValueImage = struct {
    format_version: u32 = loaded_value_image_format_version,
    fingerprint_version: u32 = loaded_value_image_fingerprint_version,
    schema_fingerprint: u64,
    value_ref: LoadedValueRef,
    value_fingerprint: u64,
    body_bytes: []const u8,

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.body_bytes);
        self.* = undefined;
    }

    pub fn imageFingerprint(self: @This()) u64 {
        return fingerprintImage(self.schema_fingerprint, self.value_ref, self.body_bytes);
    }
};

pub fn encodeLoadedValueImage(
    allocator: std.mem.Allocator,
    schemas: SchemaSet,
    ref: LoadedValueRef,
    value: LoadedValue,
    limits: Limits,
) LoadedValueError!LoadedValueImage {
    try schemas.requireValueRef(ref);
    var body = std.ArrayList(u8).empty;
    errdefer body.deinit(allocator);
    var ledger = ValueLedger{ .limits = limits };
    try encodeValueBody(&body, allocator, schemas, ref, value, limits, &ledger, 0);
    const body_bytes = try body.toOwnedSlice(allocator);
    errdefer allocator.free(body_bytes);
    const schema_fingerprint = schemas.schemaFingerprint();
    return .{
        .schema_fingerprint = schema_fingerprint,
        .value_ref = ref,
        .value_fingerprint = fingerprintImage(schema_fingerprint, ref, body_bytes),
        .body_bytes = body_bytes,
    };
}

pub fn encodeLoadedValueImageBytes(
    allocator: std.mem.Allocator,
    schemas: SchemaSet,
    ref: LoadedValueRef,
    value: LoadedValue,
    limits: Limits,
) LoadedValueError![]u8 {
    var image = try encodeLoadedValueImage(allocator, schemas, ref, value, limits);
    defer image.deinit(allocator);
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try writeU32(&out, allocator, image.format_version);
    try writeU32(&out, allocator, image.fingerprint_version);
    try writeU64(&out, allocator, image.schema_fingerprint);
    try encodeValueRef(&out, allocator, image.value_ref);
    try writeU64(&out, allocator, image.value_fingerprint);
    try writeBytes(&out, allocator, image.body_bytes);
    return out.toOwnedSlice(allocator);
}

pub fn decodeLoadedValueImage(
    allocator: std.mem.Allocator,
    arena: *LoadedValueArena,
    schemas: SchemaSet,
    expected_ref: LoadedValueRef,
    bytes: []const u8,
    limits: Limits,
) LoadedValueError!LoadedValue {
    _ = allocator;
    var cursor = Cursor{ .bytes = bytes };
    const format_version = try cursor.readU32();
    if (format_version != loaded_value_image_format_version) return error.UnsupportedVersion;
    const fingerprint_version = try cursor.readU32();
    if (fingerprint_version != loaded_value_image_fingerprint_version) return error.UnsupportedVersion;
    const schema_fingerprint = try cursor.readU64();
    if (schema_fingerprint != schemas.schemaFingerprint()) return error.FingerprintMismatch;
    const image_ref = try decodeValueRef(&cursor);
    if (!image_ref.eql(expected_ref)) return error.InvalidValue;
    try schemas.requireValueRef(image_ref);
    const value_fingerprint = try cursor.readU64();
    const body_bytes = try cursor.readBoundedBytes(limits.maximum_owned_value_bytes);
    if (cursor.remaining() != 0) return error.TrailingBytes;
    if (value_fingerprint != fingerprintImage(schema_fingerprint, image_ref, body_bytes)) return error.FingerprintMismatch;
    var body = Cursor{ .bytes = body_bytes };
    var ledger = ValueLedger{ .limits = limits };
    const value = try decodeValueBody(arena, schemas, image_ref, limits, &ledger, &body, 0);
    if (body.remaining() != 0) return error.TrailingBytes;
    return value;
}

pub fn loadedValueImageFingerprint(bytes: []const u8) LoadedValueError!u64 {
    var cursor = Cursor{ .bytes = bytes };
    const format_version = try cursor.readU32();
    if (format_version != loaded_value_image_format_version) return error.UnsupportedVersion;
    const fingerprint_version = try cursor.readU32();
    if (fingerprint_version != loaded_value_image_fingerprint_version) return error.UnsupportedVersion;
    _ = try cursor.readU64();
    _ = try decodeValueRef(&cursor);
    return try cursor.readU64();
}

const ValueLedger = struct {
    limits: Limits,
    owned_value_bytes: u64 = 0,

    fn addOwned(self: *@This(), amount: usize) LoadedValueError!void {
        self.owned_value_bytes = std.math.add(u64, self.owned_value_bytes, amount) catch return error.IntegerOverflow;
        if (self.owned_value_bytes > self.limits.maximum_owned_value_bytes) return error.OwnedValueBytesLimitExceeded;
    }
};

fn encodeValueBody(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    schemas: SchemaSet,
    ref: LoadedValueRef,
    value: LoadedValue,
    limits: Limits,
    ledger: *ValueLedger,
    depth: u32,
) LoadedValueError!void {
    if (depth > limits.maximum_value_nesting_depth) return error.NestingDepthExceeded;
    try schemas.requireValueRef(ref);
    switch (ref.codec) {
        .unit => if (value != .unit) return error.InvalidValue,
        .bool => switch (value) {
            .boolean => |b| try out.append(allocator, if (b) 1 else 0),
            else => return error.InvalidValue,
        },
        .i32 => switch (value) {
            .i32 => |v| try writeI32(out, allocator, v),
            else => return error.InvalidValue,
        },
        .usize => switch (value) {
            .word_u64 => |v| try writeU64(out, allocator, v),
            else => return error.InvalidValue,
        },
        .string => switch (value) {
            .bytes => |v| {
                if (v.len > limits.maximum_string_bytes) return error.StringBytesLimitExceeded;
                try ledger.addOwned(v.len);
                try writeBytes(out, allocator, v);
            },
            else => return error.InvalidValue,
        },
        .string_list => switch (value) {
            .list => |items| {
                if (items.len > limits.maximum_aggregate_elements) return error.AggregateElementLimitExceeded;
                try writeU32(out, allocator, @intCast(items.len));
                for (items) |item| {
                    if (item.len > limits.maximum_string_bytes) return error.StringBytesLimitExceeded;
                    try ledger.addOwned(item.len);
                    try writeBytes(out, allocator, item);
                }
            },
            else => return error.InvalidValue,
        },
        .product => switch (value) {
            .product => |fields| {
                const schema = schemas.schemas[ref.schema_index.?];
                if (fields.len != schema.field_count) return error.InvalidValue;
                if (fields.len > limits.maximum_aggregate_elements) return error.AggregateElementLimitExceeded;
                try writeU32(out, allocator, @intCast(fields.len));
                for (fields, 0..) |field_value, index| {
                    const field = schemas.fields[@as(usize, schema.first_field) + index];
                    try encodeValueBody(out, allocator, schemas, .{ .codec = field.codec, .schema_index = field.schema_index }, field_value, limits, ledger, depth + 1);
                }
            },
            else => return error.InvalidValue,
        },
        .sum => switch (value) {
            .sum => |sum| {
                const schema = schemas.schemas[ref.schema_index.?];
                if (sum.variant_index >= schema.variant_count) return error.InvalidValue;
                try writeU32(out, allocator, sum.variant_index);
                const variant = schemas.variants[@as(usize, schema.first_variant) + sum.variant_index];
                const payload_required = plan.hasPayload(variant.codec);
                try out.append(allocator, if (payload_required) 1 else 0);
                if (payload_required) {
                    const payload = sum.payload orelse return error.InvalidValue;
                    try encodeValueBody(out, allocator, schemas, .{ .codec = variant.codec, .schema_index = variant.schema_index }, payload.*, limits, ledger, depth + 1);
                } else if (sum.payload != null) {
                    return error.InvalidValue;
                }
            },
            else => return error.InvalidValue,
        },
    }
}

fn decodeValueBody(
    arena: *LoadedValueArena,
    schemas: SchemaSet,
    ref: LoadedValueRef,
    limits: Limits,
    ledger: *ValueLedger,
    cursor: *Cursor,
    depth: u32,
) LoadedValueError!LoadedValue {
    if (depth > limits.maximum_value_nesting_depth) return error.NestingDepthExceeded;
    try schemas.requireValueRef(ref);
    return switch (ref.codec) {
        .unit => .unit,
        .bool => .{ .boolean = switch (try cursor.readU8()) {
            0 => false,
            1 => true,
            else => return error.InvalidValue,
        } },
        .i32 => .{ .i32 = try cursor.readI32() },
        .usize => .{ .word_u64 = try cursor.readU64() },
        .string => blk: {
            const bytes = try cursor.readBoundedBytes(limits.maximum_string_bytes);
            try ledger.addOwned(bytes.len);
            break :blk .{ .bytes = try arena.dupeBytes(bytes) };
        },
        .string_list => blk: {
            const count = try cursor.readBoundedCount(limits.maximum_aggregate_elements);
            const items = try arena.allocator().alloc([]const u8, count);
            for (items) |*item| {
                const bytes = try cursor.readBoundedBytes(limits.maximum_string_bytes);
                try ledger.addOwned(bytes.len);
                item.* = try arena.dupeBytes(bytes);
            }
            break :blk .{ .list = items };
        },
        .product => blk: {
            const schema = schemas.schemas[ref.schema_index.?];
            const count = try cursor.readBoundedCount(limits.maximum_aggregate_elements);
            if (count != schema.field_count) return error.InvalidValue;
            const values = try arena.allocator().alloc(LoadedValue, count);
            for (values, 0..) |*slot, index| {
                const field = schemas.fields[@as(usize, schema.first_field) + index];
                slot.* = try decodeValueBody(arena, schemas, .{ .codec = field.codec, .schema_index = field.schema_index }, limits, ledger, cursor, depth + 1);
            }
            break :blk .{ .product = values };
        },
        .sum => blk: {
            const schema = schemas.schemas[ref.schema_index.?];
            const variant_index = try cursor.readU32();
            if (variant_index >= schema.variant_count) return error.InvalidValue;
            const has_payload = switch (try cursor.readU8()) {
                0 => false,
                1 => true,
                else => return error.InvalidValue,
            };
            const variant = schemas.variants[@as(usize, schema.first_variant) + variant_index];
            if (has_payload != plan.hasPayload(variant.codec)) return error.InvalidValue;
            const payload = if (has_payload) payload: {
                const decoded = try decodeValueBody(arena, schemas, .{ .codec = variant.codec, .schema_index = variant.schema_index }, limits, ledger, cursor, depth + 1);
                break :payload try arena.createValue(decoded);
            } else null;
            break :blk .{ .sum = .{ .variant_index = variant_index, .payload = payload } };
        },
    };
}

fn fingerprintImage(schema_fingerprint: u64, ref: LoadedValueRef, body_bytes: []const u8) u64 {
    var hasher = StableHasher.init("boundary.loaded_value_image");
    hasher.putU32(loaded_value_image_fingerprint_version);
    hasher.putU64(schema_fingerprint);
    hasher.putU8(@intFromEnum(ref.codec));
    hasher.optionalU16(ref.schema_index);
    hasher.bytes(body_bytes);
    return hasher.finish();
}

fn encodeValueRef(out: *std.ArrayList(u8), allocator: std.mem.Allocator, ref: LoadedValueRef) !void {
    try out.append(allocator, @intFromEnum(ref.codec));
    if (ref.schema_index) |index| {
        try out.append(allocator, 1);
        try writeU16(out, allocator, index);
    } else {
        try out.append(allocator, 0);
        try writeU16(out, allocator, 0);
    }
}

fn decodeValueRef(cursor: *Cursor) LoadedValueError!LoadedValueRef {
    const tag = try cursor.readU8();
    const codec = valueCodecFromTag(tag) orelse return error.UnsupportedCodec;
    const has_schema = switch (try cursor.readU8()) {
        0 => false,
        1 => true,
        else => return error.MalformedValueImage,
    };
    const schema_index = try cursor.readU16();
    return .{ .codec = codec, .schema_index = if (has_schema) schema_index else null };
}

fn encodeSessionValueRef(out: *std.ArrayList(u8), allocator: std.mem.Allocator, ref: LoadedValueRef) !void {
    try out.append(allocator, @intFromEnum(ref.codec));
    if (ref.schema_index) |index| {
        try out.append(allocator, 1);
        try writeU16(out, allocator, index);
    } else {
        try out.append(allocator, 0);
        try writeU16(out, allocator, 0);
    }
}

fn valueCodecFromTag(tag: u8) ?plan.ValueCodec {
    inline for (@typeInfo(plan.ValueCodec).@"enum".fields) |field| {
        if (field.value == tag) return @enumFromInt(field.value);
    }
    return null;
}

fn decodeSessionStatus(tag: u8) !LoadedSessionStatus {
    inline for (@typeInfo(LoadedSessionStatus).@"enum".fields) |field| {
        if (field.value == tag) return @enumFromInt(field.value);
    }
    return error.MalformedSessionImage;
}

fn decodeFailureKind(tag: u16) !ExecutionFailureKind {
    inline for (@typeInfo(ExecutionFailureKind).@"enum".fields) |field| {
        if (field.value == tag) return @enumFromInt(field.value);
    }
    return error.MalformedSessionImage;
}

const Cursor = struct {
    bytes: []const u8,
    index: usize = 0,

    fn remaining(self: @This()) usize {
        return self.bytes.len - self.index;
    }

    fn read(self: *@This(), count: usize) LoadedValueError![]const u8 {
        if (count > self.remaining()) return error.TruncatedImage;
        const start = self.index;
        self.index += count;
        return self.bytes[start..self.index];
    }

    fn readU8(self: *@This()) LoadedValueError!u8 {
        return (try self.read(1))[0];
    }

    fn readU16(self: *@This()) LoadedValueError!u16 {
        return std.mem.readInt(u16, (try self.read(2))[0..2], .little);
    }

    fn readU32(self: *@This()) LoadedValueError!u32 {
        return std.mem.readInt(u32, (try self.read(4))[0..4], .little);
    }

    fn readU64(self: *@This()) LoadedValueError!u64 {
        return std.mem.readInt(u64, (try self.read(8))[0..8], .little);
    }

    fn readI32(self: *@This()) LoadedValueError!i32 {
        return std.mem.readInt(i32, (try self.read(4))[0..4], .little);
    }

    fn readBoundedCount(self: *@This(), limit: u32) LoadedValueError!usize {
        const count = try self.readU32();
        if (count > limit) return error.AggregateElementLimitExceeded;
        return @intCast(count);
    }

    fn readBoundedBytes(self: *@This(), limit: u32) LoadedValueError![]const u8 {
        const len = try self.readU32();
        if (len > limit) return error.StringBytesLimitExceeded;
        return try self.read(len);
    }
};

const SessionCursor = struct {
    bytes: []const u8,
    index: usize = 0,

    fn remaining(self: @This()) usize {
        return self.bytes.len - self.index;
    }

    fn read(self: *@This(), count: usize) ![]const u8 {
        if (count > self.remaining()) return error.TruncatedImage;
        const start = self.index;
        self.index += count;
        return self.bytes[start..self.index];
    }

    fn readU8(self: *@This()) !u8 {
        return (try self.read(1))[0];
    }

    fn readU16(self: *@This()) !u16 {
        return std.mem.readInt(u16, (try self.read(2))[0..2], .little);
    }

    fn readU32(self: *@This()) !u32 {
        return std.mem.readInt(u32, (try self.read(4))[0..4], .little);
    }

    fn readU64(self: *@This()) !u64 {
        return std.mem.readInt(u64, (try self.read(8))[0..8], .little);
    }

    fn readOptionalU64(self: *@This()) !?u64 {
        return switch (try self.readU8()) {
            0 => null,
            1 => try self.readU64(),
            else => error.MalformedSessionImage,
        };
    }

    fn readSessionValueRef(self: *@This()) !LoadedValueRef {
        const tag = try self.readU8();
        const codec = valueCodecFromTag(tag) orelse return error.UnsupportedCodec;
        const has_schema = switch (try self.readU8()) {
            0 => false,
            1 => true,
            else => return error.MalformedSessionImage,
        };
        const schema_index = try self.readU16();
        return .{ .codec = codec, .schema_index = if (has_schema) schema_index else null };
    }

    fn readOwnedBytes(self: *@This(), allocator: std.mem.Allocator, limit: u32) ![]const u8 {
        const len = try self.readU32();
        if (len > limit) return error.StringBytesLimitExceeded;
        return try allocator.dupe(u8, try self.read(len));
    }
};

const PlanCursor = struct {
    bytes: []const u8,
    index: usize = 0,

    const NamedValueRef = struct {
        label: []const u8,
        ref: LoadedValueRef,
    };

    fn remaining(self: @This()) usize {
        return self.bytes.len - self.index;
    }

    fn read(self: *@This(), count: usize) ![]const u8 {
        if (count > self.remaining()) return error.TruncatedImage;
        const start = self.index;
        self.index += count;
        return self.bytes[start..self.index];
    }

    fn readU8(self: *@This()) !u8 {
        return (try self.read(1))[0];
    }

    fn readU16(self: *@This()) !u16 {
        return std.mem.readInt(u16, (try self.read(2))[0..2], .little);
    }

    fn readU32(self: *@This()) !u32 {
        return std.mem.readInt(u32, (try self.read(4))[0..4], .little);
    }

    fn readU64(self: *@This()) !u64 {
        return std.mem.readInt(u64, (try self.read(8))[0..8], .little);
    }

    fn readBool(self: *@This()) !bool {
        return switch (try self.readU8()) {
            0 => false,
            1 => true,
            else => error.MalformedPlan,
        };
    }

    fn readOptionalU64(self: *@This()) !?u64 {
        return if (!(try self.readBool())) null else try self.readU64();
    }

    fn readBytes(self: *@This()) ![]const u8 {
        const len_raw = try self.readU64();
        if (len_raw > std.math.maxInt(usize)) return error.MalformedPlan;
        return try self.read(@intCast(len_raw));
    }

    fn readEnum(self: *@This(), comptime T: type) !T {
        const tag = try self.readU8();
        inline for (@typeInfo(T).@"enum".fields) |field| {
            if (field.value == tag) return @enumFromInt(field.value);
        }
        return error.MalformedPlan;
    }

    fn readWireValueRef(self: *@This()) !LoadedValueRef {
        const codec_name = try self.readBytes();
        const codec = valueCodecFromName(codec_name) orelse return error.MalformedPlan;
        const schema_index_raw = try self.readOptionalU64();
        if (schema_index_raw != null and schema_index_raw.? > std.math.maxInt(u16)) return error.MalformedPlan;
        return .{
            .codec = codec,
            .schema_index = if (schema_index_raw) |value| @intCast(value) else null,
        };
    }

    fn readOptionalWireValueRef(self: *@This()) !?LoadedValueRef {
        return if (!(try self.readBool())) null else try self.readWireValueRef();
    }

    fn readWireValueRefAfterBytes(self: *@This(), allocator: std.mem.Allocator) !NamedValueRef {
        return .{
            .label = try allocator.dupe(u8, try self.readBytes()),
            .ref = try self.readWireValueRef(),
        };
    }
};

fn readPlanCount(cursor: *PlanCursor, limit: usize) !usize {
    const count = try cursor.readU64();
    if (count > std.math.maxInt(usize) or count > limit or count > max_plan_table_count) return error.MalformedPlan;
    return @intCast(count);
}

fn valueCodecFromName(name: []const u8) ?plan.ValueCodec {
    inline for (@typeInfo(plan.ValueCodec).@"enum".fields) |field| {
        if (std.mem.eql(u8, name, field.name)) return @enumFromInt(field.value);
    }
    return null;
}

fn executablePlanBodyFingerprint(body: []const u8) u64 {
    var hasher = std.hash.Wyhash.init(0);
    fingerprintBytes(&hasher, "domain.name", executable_plan_domain_name);
    fingerprintU32(&hasher, "domain.fingerprint_version", executable_plan_image_fingerprint_version);
    fingerprintU32(&hasher, "format_version", executable_plan_image_format_version);
    fingerprintBytes(&hasher, "body", body);
    return hasher.final();
}

fn fingerprintBytes(hasher: *std.hash.Wyhash, label: []const u8, bytes: []const u8) void {
    fingerprintRawBytes(hasher, label);
    fingerprintRawBytes(hasher, bytes);
}

fn fingerprintU32(hasher: *std.hash.Wyhash, label: []const u8, value: u32) void {
    fingerprintRawBytes(hasher, label);
    var raw: [4]u8 = undefined;
    std.mem.writeInt(u32, &raw, value, .little);
    hasher.update(&raw);
}

fn fingerprintRawBytes(hasher: *std.hash.Wyhash, bytes: []const u8) void {
    var len_bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &len_bytes, bytes.len, .little);
    hasher.update(&len_bytes);
    hasher.update(bytes);
}

const StableHasher = struct {
    value: u64 = fingerprint_offset,

    fn init(domain: []const u8) @This() {
        var hasher = StableHasher{};
        hasher.bytes(domain);
        return hasher;
    }

    fn finish(self: @This()) u64 {
        return self.value;
    }

    fn putU8(self: *@This(), value: u8) void {
        self.value ^= value;
        self.value *%= fingerprint_prime;
    }

    fn putU16(self: *@This(), value: u16) void {
        var raw: [2]u8 = undefined;
        std.mem.writeInt(u16, &raw, value, .little);
        self.rawBytes(&raw);
    }

    fn putU32(self: *@This(), value: u32) void {
        var raw: [4]u8 = undefined;
        std.mem.writeInt(u32, &raw, value, .little);
        self.rawBytes(&raw);
    }

    fn putU64(self: *@This(), value: u64) void {
        var raw: [8]u8 = undefined;
        std.mem.writeInt(u64, &raw, value, .little);
        self.rawBytes(&raw);
    }

    fn optionalU16(self: *@This(), value: ?u16) void {
        if (value) |actual| {
            self.putU8(1);
            self.putU16(actual);
        } else {
            self.putU8(0);
            self.putU16(0);
        }
    }

    fn optionalU64(self: *@This(), value: ?u64) void {
        if (value) |actual| {
            self.putU8(1);
            self.putU64(actual);
        } else {
            self.putU8(0);
        }
    }

    fn bytes(self: *@This(), value: []const u8) void {
        self.putU32(@intCast(value.len));
        self.rawBytes(value);
    }

    fn rawBytes(self: *@This(), value: []const u8) void {
        for (value) |byte| self.putU8(byte);
    }
};

fn writeU16(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u16) !void {
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, value, .little);
    try out.appendSlice(allocator, &bytes);
}

fn writeU32(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .little);
    try out.appendSlice(allocator, &bytes);
}

fn writeI32(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: i32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(i32, &bytes, value, .little);
    try out.appendSlice(allocator, &bytes);
}

fn writeU64(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u64) !void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .little);
    try out.appendSlice(allocator, &bytes);
}

fn encodeOptionalU64(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: ?u64) !void {
    if (value) |actual| {
        try out.append(allocator, 1);
        try writeU64(out, allocator, actual);
    } else {
        try out.append(allocator, 0);
    }
}

fn writeBytes(out: *std.ArrayList(u8), allocator: std.mem.Allocator, bytes: []const u8) !void {
    if (bytes.len > max_u32_len) return error.InvalidValue;
    try writeU32(out, allocator, @intCast(bytes.len));
    try out.appendSlice(allocator, bytes);
}

test "loaded execution profile v1 compatibility is explicit and bounded" {
    const supported = LoadedExecutionProfile.portableV1();
    var required = LoadedExecutionProfile.portableV1();
    try std.testing.expect(supported.compatibleWith(required));
    required.limits.maximum_frames = supported.limits.maximum_frames + 1;
    try std.testing.expect(!supported.compatibleWith(required));
}

test "loaded value image roundtrips canonical scalar values" {
    const allocator = std.testing.allocator;
    const schemas = SchemaSet{};
    const limits = Limits{};

    const encoded = try encodeLoadedValueImageBytes(allocator, schemas, .{ .codec = .usize }, .{ .word_u64 = 0x1_0000_0000 }, limits);
    defer allocator.free(encoded);

    var arena = LoadedValueArena.init(allocator);
    defer arena.deinit();
    const decoded = try decodeLoadedValueImage(allocator, &arena, schemas, .{ .codec = .usize }, encoded, limits);
    try std.testing.expectEqual(@as(u64, 0x1_0000_0000), decoded.word_u64);
}

test "loaded value image validates product and sum schemas" {
    const allocator = std.testing.allocator;
    const fields = [_]plan.ValueFieldPlan{
        .{ .name = "name", .codec = .string },
        .{ .name = "count", .codec = .i32 },
    };
    const variants = [_]plan.ValueVariantPlan{
        .{ .name = "none", .codec = .unit },
        .{ .name = "payload", .codec = .product, .schema_index = 0 },
    };
    const schemas_table = [_]plan.ValueSchemaPlan{
        .{ .label = "Pair", .codec = .product, .first_field = 0, .field_count = fields.len },
        .{ .label = "MaybePair", .codec = .sum, .first_variant = 0, .variant_count = variants.len },
    };
    const schemas = SchemaSet{
        .schemas = &schemas_table,
        .fields = &fields,
        .variants = &variants,
    };
    const product = LoadedValue{ .product = &.{
        .{ .bytes = "alpha" },
        .{ .i32 = 7 },
    } };
    const sum = LoadedValue{ .sum = .{
        .variant_index = 1,
        .payload = &product,
    } };
    const encoded = try encodeLoadedValueImageBytes(allocator, schemas, .{ .codec = .sum, .schema_index = 1 }, sum, .{});
    defer allocator.free(encoded);

    var arena = LoadedValueArena.init(allocator);
    defer arena.deinit();
    const decoded = try decodeLoadedValueImage(allocator, &arena, schemas, .{ .codec = .sum, .schema_index = 1 }, encoded, .{});
    try std.testing.expectEqual(@as(u32, 1), decoded.sum.variant_index);
    try std.testing.expect(decoded.sum.payload != null);
    try std.testing.expectEqualStrings("alpha", decoded.sum.payload.?.product[0].bytes);
    try std.testing.expectEqual(@as(i32, 7), decoded.sum.payload.?.product[1].i32);
}

test "loaded value image rejects trailing bytes and schema drift" {
    const allocator = std.testing.allocator;
    const schemas = SchemaSet{};
    const encoded = try encodeLoadedValueImageBytes(allocator, schemas, .{ .codec = .bool }, .{ .boolean = true }, .{});
    defer allocator.free(encoded);

    var arena = LoadedValueArena.init(allocator);
    defer arena.deinit();
    const extended = try allocator.alloc(u8, encoded.len + 1);
    defer allocator.free(extended);
    @memcpy(extended[0..encoded.len], encoded);
    extended[encoded.len] = 0xff;
    try std.testing.expectError(error.TrailingBytes, decodeLoadedValueImage(
        allocator,
        &arena,
        schemas,
        .{ .codec = .bool },
        extended,
        .{},
    ));

    const fields = [_]plan.ValueFieldPlan{.{ .name = "value", .codec = .bool }};
    const schema_table = [_]plan.ValueSchemaPlan{.{ .label = "Changed", .codec = .product, .first_field = 0, .field_count = 1 }};
    try std.testing.expectError(error.FingerprintMismatch, decodeLoadedValueImage(
        allocator,
        &arena,
        .{ .schemas = &schema_table, .fields = &fields },
        .{ .codec = .bool },
        encoded,
        .{},
    ));
}

test "loaded session image roundtrips failure state and rejects trailing bytes" {
    const allocator = std.testing.allocator;
    const profile = LoadedExecutionProfile.portableV1();
    const profile_fingerprint = profile.computeFingerprint();
    const session_fingerprint = loadedSessionFingerprint(11, 22, profile_fingerprint, 3);
    const image = LoadedSessionImage{
        .module_fingerprint = 11,
        .executable_plan_fingerprint = 22,
        .execution_profile_fingerprint = profile_fingerprint,
        .session_fingerprint = session_fingerprint,
        .entry_function = 3,
        .budget = .{ .advancements = 1 },
        .status = .failed,
        .failure = .{
            .kind = .unsupported_feature,
            .function_index = 3,
            .diagnostic_summary = "loaded interpreter is unavailable",
        },
        .dependency_fingerprint = 44,
    };
    const encoded = try image.encode(allocator);
    defer allocator.free(encoded);

    var decoded = try LoadedSessionImage.decode(allocator, encoded);
    defer decoded.deinit(allocator);
    try std.testing.expectEqual(image.computeFingerprint(), decoded.computeFingerprint());
    try std.testing.expectEqual(LoadedSessionStatus.failed, decoded.status);
    try std.testing.expectEqual(ExecutionFailureKind.unsupported_feature, decoded.failure.?.kind);
    try std.testing.expectEqualStrings("loaded interpreter is unavailable", decoded.failure.?.diagnostic_summary);

    const extended = try allocator.alloc(u8, encoded.len + 1);
    defer allocator.free(extended);
    @memcpy(extended[0..encoded.len], encoded);
    extended[encoded.len] = 0;
    try std.testing.expectError(error.TrailingBytes, LoadedSessionImage.decode(allocator, extended));
}

test "loaded session image binds fingerprinted identity fields" {
    const allocator = std.testing.allocator;
    const profile_fingerprint = LoadedExecutionProfile.portableV1().computeFingerprint();
    const image = LoadedSessionImage{
        .module_fingerprint = 100,
        .executable_plan_fingerprint = 200,
        .execution_profile_fingerprint = profile_fingerprint,
        .session_fingerprint = loadedSessionFingerprint(100, 200, profile_fingerprint, 1),
        .entry_function = 1,
    };
    const encoded = try image.encode(allocator);
    defer allocator.free(encoded);
    const corrupted = try allocator.dupe(u8, encoded);
    defer allocator.free(corrupted);
    corrupted[8] ^= 1;
    try std.testing.expectError(error.FingerprintMismatch, LoadedSessionImage.decode(allocator, corrupted));
}
