// zlinter-disable declaration_naming field_naming field_ordering function_naming max_positional_args no_empty_block no_undefined no_swallow_error require_doc_comment
const lowered_machine = @import("lowered_machine");
const lowering_api = @import("lowering_api");
const plan_types = @import("internal_program_plan");
const std = @import("std");

fn hasDeclSafe(comptime T: type, comptime name: []const u8) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, name),
        else => false,
    };
}

fn dummyPointer(comptime PtrType: type) PtrType {
    const pointer = @typeInfo(PtrType).pointer;
    const Child = std.meta.Child(PtrType);
    if (pointer.size == .slice) {
        const many = @as([*]Child, @ptrFromInt(std.mem.alignForward(usize, 1, @alignOf(Child))));
        const slice = if (comptime pointer.sentinel()) |sentinel| many[0..1 :sentinel] else many[0..1];
        if (pointer.is_const) return @as(PtrType, slice);
        return @as(PtrType, @constCast(slice));
    }
    return @as(PtrType, @ptrFromInt(std.mem.alignForward(usize, 1, @alignOf(Child))));
}

fn dummyValue(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .pointer => dummyPointer(T),
        .optional => |optional| dummyValue(optional.child),
        .void => {},
        .@"struct" => |info| blk: {
            var value: T = undefined;
            inline for (info.fields) |field| {
                @field(value, field.name) = dummyValue(field.type);
            }
            break :blk value;
        },
        else => dummyPointer(*T).*,
    };
}

fn ProgramPlanForBody(comptime Body: type) lowering_api.ProgramPlan {
    if (!hasDeclSafe(Body, "compiled_plan")) {
        @compileError("ability.program bodies must declare pub const compiled_plan: ability.ir.ProgramPlan");
    }
    const plan = Body.compiled_plan;
    if (@TypeOf(plan) != lowering_api.ProgramPlan) {
        @compileError("Body.compiled_plan must have type ability.ir.ProgramPlan");
    }
    comptime {
        @setEvalBranchQuota(100_000);
        const nested_with_targets = BodyNestedWithTargets(Body).values;
        plan.validateWithNestedTargets(nested_with_targets) catch |err| {
            @compileError("Body.compiled_plan failed ProgramPlan.validate: " ++ @errorName(err));
        };
        validateBodyValueSchemaTypes(plan, Body, nested_with_targets);
        const schema_types = BodyValueSchemaTypes(Body).values;
        lowering_api.validateTypedExecutablePlanSupportWithNestedTargets(plan, schema_types, nested_with_targets) catch |err| {
            @compileError("Body.compiled_plan is not supported by ability.program: " ++ @errorName(err) ++ "\n" ++
                lowering_api.executableCapabilitySummary(plan, schema_types, nested_with_targets));
        };
        validatePlanReturnErrors(plan, nested_with_targets, BodyErrorSet(Body));
    }
    return plan;
}

fn BodyValueSchemaTypes(comptime Body: type) type {
    if (comptime hasDeclSafe(Body, "value_schema_types")) {
        return struct {
            /// Exact Zig type tuple matching ProgramPlan product and sum schema tables.
            pub const values = Body.value_schema_types;
        };
    }
    return struct {
        /// Empty schema registry for scalar-only plans.
        pub const values = .{};
    };
}

fn BodyNestedWithTargets(comptime Body: type) type {
    if (comptime hasDeclSafe(Body, "nested_with_targets")) {
        return struct {
            /// Exact metadata-to-function resolver rows for executable nested lexical-with instructions.
            pub const values = Body.nested_with_targets;
        };
    }
    return struct {
        /// No nested lexical-with rows are executable unless the body opts in with targets.
        pub const values = .{};
    };
}

fn BodySiteMetadata(comptime Body: type) type {
    if (comptime hasDeclSafe(Body, "site_metadata")) {
        return struct {
            /// Optional display/debug labels for lowered semantic operation sites.
            pub const values = Body.site_metadata;
        };
    }
    return struct {
        /// Raw ProgramPlan construction has no semantic site labels by default.
        pub const values = .{};
    };
}

fn schemaIndexLabel(comptime index: usize) []const u8 {
    return std.fmt.comptimePrint("{d}", .{index});
}

fn valueSchemaPlansEqual(comptime actual: anytype, comptime expected: anytype) bool {
    return std.mem.eql(u8, actual.label, expected.label) and
        actual.codec == expected.codec and
        actual.first_field == expected.first_field and
        actual.field_count == expected.field_count and
        actual.first_variant == expected.first_variant and
        actual.variant_count == expected.variant_count;
}

fn schemaRefsMatch(comptime schema_types: anytype, actual: ?u16, expected: ?u16) bool {
    if (actual == expected) return true;
    const actual_index = actual orelse return false;
    const expected_index = expected orelse return false;
    if (actual_index >= schema_types.len or expected_index >= schema_types.len) return false;
    return schema_types[actual_index] == schema_types[expected_index];
}

fn valueFieldPlansEqual(comptime schema_types: anytype, comptime actual: anytype, comptime expected: anytype) bool {
    return std.mem.eql(u8, actual.name, expected.name) and
        actual.codec == expected.codec and
        schemaRefsMatch(schema_types, actual.schema_index, expected.schema_index);
}

fn valueVariantPlansEqual(comptime schema_types: anytype, comptime actual: anytype, comptime expected: anytype) bool {
    return std.mem.eql(u8, actual.name, expected.name) and
        actual.codec == expected.codec and
        schemaRefsMatch(schema_types, actual.schema_index, expected.schema_index);
}

fn validateBodyValueSchemaTypes(
    comptime plan: lowering_api.ProgramPlan,
    comptime Body: type,
    comptime nested_with_targets: anytype,
) void {
    const plan_schema_count = plan.value_schemas.len;
    if (comptime !hasDeclSafe(Body, "value_schema_types")) {
        if (lowering_api.executablePlanNeedsBodyValueSchemaTypes(plan, nested_with_targets)) {
            @compileError("Body.value_schema_types is required when reachable Body.compiled_plan execution uses product or sum value schemas");
        }
        return;
    }

    const schema_types = Body.value_schema_types;
    if (schema_types.len != plan_schema_count) {
        @compileError(std.fmt.comptimePrint(
            "Body.value_schema_types length mismatch: expected {d}, found {d}",
            .{ plan_schema_count, schema_types.len },
        ));
    }

    const registry = lowering_api.ValueSchemaRegistryForTypes(schema_types);
    if (registry.value_fields.len != plan.value_fields.len) {
        @compileError(std.fmt.comptimePrint(
            "Body.value_schema_types field table length mismatch: expected {d}, found {d}",
            .{ plan.value_fields.len, registry.value_fields.len },
        ));
    }
    if (registry.value_variants.len != plan.value_variants.len) {
        @compileError(std.fmt.comptimePrint(
            "Body.value_schema_types variant table length mismatch: expected {d}, found {d}",
            .{ plan.value_variants.len, registry.value_variants.len },
        ));
    }

    inline for (registry.value_schemas, 0..) |expected, index| {
        if (!valueSchemaPlansEqual(plan.value_schemas[index], expected)) {
            @compileError("Body.value_schema_types does not match Body.compiled_plan.value_schemas[" ++ schemaIndexLabel(index) ++ "]");
        }
    }
    inline for (registry.value_fields, 0..) |expected, index| {
        if (!valueFieldPlansEqual(schema_types, plan.value_fields[index], expected)) {
            @compileError("Body.value_schema_types does not match Body.compiled_plan.value_fields[" ++ schemaIndexLabel(index) ++ "]");
        }
    }
    inline for (registry.value_variants, 0..) |expected, index| {
        if (!valueVariantPlansEqual(schema_types, plan.value_variants[index], expected)) {
            @compileError("Body.value_schema_types does not match Body.compiled_plan.value_variants[" ++ schemaIndexLabel(index) ++ "]");
        }
    }
}

fn BodyErrorSet(comptime Body: type) type {
    if (comptime !hasDeclSafe(Body, "Error")) return error{};
    if (@typeInfo(Body.Error) != .error_set) @compileError("Body.Error must be an error set");
    return Body.Error;
}

fn errorSetContains(comptime ErrorSet: type, literal: []const u8) bool {
    return switch (@typeInfo(ErrorSet)) {
        .error_set => |errors| blk: {
            if (errors) |decls| {
                inline for (decls) |decl| {
                    if (std.mem.eql(u8, decl.name, literal)) break :blk true;
                }
            } else {
                break :blk true;
            }
            break :blk false;
        },
        else => @compileError("Body.Error must be an error set"),
    };
}

fn validatePlanReturnErrors(
    comptime plan: lowering_api.ProgramPlan,
    comptime nested_targets: anytype,
    comptime ErrorSet: type,
) void {
    const analysis = comptime plan_types.entryExecutionAnalysisWithNestedTargets(plan, nested_targets) catch |err|
        @compileError("Body.compiled_plan entry execution analysis failed: " ++ @errorName(err));
    for (plan.instructions, 0..) |instruction, instruction_index| {
        if (!analysis.reachable_instructions[instruction_index] or instruction.kind != .return_error) continue;
        if (!errorSetContains(ErrorSet, instruction.string_literal)) {
            @compileError("Body.compiled_plan reachable return_error is not declared in Body.Error: " ++ instruction.string_literal);
        }
    }
}

fn ProgramValueTypeForRef(
    comptime plan: lowering_api.ProgramPlan,
    comptime schema_types: anytype,
    comptime ref: lowering_api.ValueRef,
) type {
    _ = plan;
    return switch (ref.codec) {
        .unit => void,
        .bool => bool,
        .i32 => i32,
        .product => schema_types[ref.schema_index orelse @compileError("product ProgramPlan result is missing a schema index")],
        .usize => usize,
        .string => []const u8,
        .string_list => []const []const u8,
        .sum => schema_types[ref.schema_index orelse @compileError("sum ProgramPlan result is missing a schema index")],
    };
}

fn maxProgramValueStorageSize(comptime schema_types: anytype) comptime_int {
    var max_size: comptime_int = 1;
    inline for (.{ void, bool, i32, usize, []const u8, []const []const u8 }) |T| {
        max_size = @max(max_size, @sizeOf(T));
    }
    inline for (schema_types) |T| {
        max_size = @max(max_size, @sizeOf(T));
    }
    return max_size;
}

fn maxProgramValueStorageAlign(comptime schema_types: anytype) comptime_int {
    var max_align: comptime_int = 1;
    inline for (.{ void, bool, i32, usize, []const u8, []const []const u8 }) |T| {
        max_align = @max(max_align, @alignOf(T));
    }
    inline for (schema_types) |T| {
        max_align = @max(max_align, @alignOf(T));
    }
    return max_align;
}

fn ProgramValueRefForType(comptime schema_types: anytype, comptime ValueType: type) lowering_api.ValueRef {
    if (ValueType == void) return .{ .codec = .unit };
    if (ValueType == bool) return .{ .codec = .bool };
    if (ValueType == i32) return .{ .codec = .i32 };
    if (ValueType == usize) return .{ .codec = .usize };
    if (ValueType == []const u8) return .{ .codec = .string };
    if (ValueType == []const []const u8 or ValueType == [][]const u8) return .{ .codec = .string_list };

    inline for (schema_types, 0..) |SchemaType, schema_index| {
        if (ValueType == SchemaType) {
            return switch (@typeInfo(ValueType)) {
                .@"struct" => .{ .codec = .product, .schema_index = @intCast(schema_index) },
                .@"enum", .@"union", .optional => .{ .codec = .sum, .schema_index = @intCast(schema_index) },
                else => @compileError("Program.Handler value schema type must be product or sum: " ++ @typeName(ValueType)),
            };
        }
    }

    @compileError("Program.Handler value type is not representable by this Program: " ++ @typeName(ValueType));
}

fn ProgramValueCodecForType(comptime ValueType: type) lowering_api.ValueCodec {
    if (ValueType == void) return .unit;
    if (ValueType == bool) return .bool;
    if (ValueType == i32) return .i32;
    if (ValueType == usize) return .usize;
    if (ValueType == []const u8) return .string;
    if (ValueType == []const []const u8 or ValueType == [][]const u8) return .string_list;
    return switch (@typeInfo(ValueType)) {
        .@"struct" => .product,
        .@"enum", .@"union", .optional => .sum,
        else => @compileError("Program.Handler value type is not representable by Program values: " ++ @typeName(ValueType)),
    };
}

fn ProgramValueRefCompatibleWithType(ref: lowering_api.ValueRef, comptime ValueType: type) bool {
    const codec = comptime ProgramValueCodecForType(ValueType);
    if (ref.codec != codec) return false;
    return switch (codec) {
        .product, .sum => true,
        else => ref.schema_index == null,
    };
}

fn ProgramValueStandaloneRefForType(comptime ValueType: type) lowering_api.ValueRef {
    const codec = comptime ProgramValueCodecForType(ValueType);
    return .{ .codec = codec };
}

fn ProgramErrorSet(comptime Body: type) type {
    if (comptime hasDeclSafe(Body, "Error")) return lowered_machine.ResetError(Body.Error);
    return lowered_machine.ResetError(error{});
}

const ContractOutputView = struct {
    label: []const u8,
    codec: lowering_api.ValueCodec,
    schema_index: ?u16 = null,
};

const ContractValueSchemaView = struct {
    label: []const u8,
    codec: lowering_api.ValueCodec,
    first_field: u16,
    field_count: u16,
    first_variant: u16,
    variant_count: u16,
};

const ContractValueFieldView = struct {
    name: []const u8,
    ref: lowering_api.ValueRef,
};

const ContractValueVariantView = struct {
    name: []const u8,
    ref: lowering_api.ValueRef,
};

const ContractEntryParameterView = struct {
    local_index: u16,
    ref: lowering_api.ValueRef,
};

const ContractNestedWithTargetView = struct {
    metadata: []const u8,
    function_index: u16,
};

const ContractRequirementView = struct {
    label: []const u8,
    first_op: u16,
    op_count: u16,
    lifecycle_tag: @TypeOf(@as(plan_types.RequirementPlan, undefined).lifecycle_tag),
    output_tag: @TypeOf(@as(plan_types.RequirementPlan, undefined).output_tag),
};

const ContractOpView = struct {
    requirement_index: u16,
    requirement_label: []const u8,
    op_name: []const u8,
    mode: plan_types.ControlMode,
    payload_ref: lowering_api.ValueRef,
    resume_ref: lowering_api.ValueRef,
    has_after: bool,
};

fn contractOutputs(comptime plan: lowering_api.ProgramPlan) [plan.outputs.len]ContractOutputView {
    var views: [plan.outputs.len]ContractOutputView = undefined;
    for (plan.outputs, 0..) |output, index| {
        views[index] = .{
            .label = output.label,
            .codec = output.codec,
            .schema_index = output.schema_index,
        };
    }
    return views;
}

fn contractValueSchemas(comptime plan: lowering_api.ProgramPlan) [plan.value_schemas.len]ContractValueSchemaView {
    var views: [plan.value_schemas.len]ContractValueSchemaView = undefined;
    for (plan.value_schemas, 0..) |schema, index| {
        views[index] = .{
            .label = schema.label,
            .codec = schema.codec,
            .first_field = schema.first_field,
            .field_count = schema.field_count,
            .first_variant = schema.first_variant,
            .variant_count = schema.variant_count,
        };
    }
    return views;
}

fn contractValueFields(comptime plan: lowering_api.ProgramPlan) [plan.value_fields.len]ContractValueFieldView {
    var views: [plan.value_fields.len]ContractValueFieldView = undefined;
    for (plan.value_fields, 0..) |field, index| {
        views[index] = .{
            .name = field.name,
            .ref = .{ .codec = field.codec, .schema_index = field.schema_index },
        };
    }
    return views;
}

fn contractValueVariants(comptime plan: lowering_api.ProgramPlan) [plan.value_variants.len]ContractValueVariantView {
    var views: [plan.value_variants.len]ContractValueVariantView = undefined;
    for (plan.value_variants, 0..) |variant, index| {
        views[index] = .{
            .name = variant.name,
            .ref = .{ .codec = variant.codec, .schema_index = variant.schema_index },
        };
    }
    return views;
}

fn contractEntryParameters(comptime plan: lowering_api.ProgramPlan) [plan.functions[plan.entry_index].parameter_count]ContractEntryParameterView {
    const entry = plan.functions[plan.entry_index];
    var views: [entry.parameter_count]ContractEntryParameterView = undefined;
    for (0..entry.parameter_count) |parameter_index| {
        const local = plan.locals[entry.first_local + parameter_index];
        views[parameter_index] = .{
            .local_index = @intCast(parameter_index),
            .ref = .{ .codec = local.codec, .schema_index = local.schema_index },
        };
    }
    return views;
}

fn contractNestedWithTargets(comptime nested_with_targets: anytype) [nested_with_targets.len]ContractNestedWithTargetView {
    var views: [nested_with_targets.len]ContractNestedWithTargetView = undefined;
    for (nested_with_targets, 0..) |target, index| {
        views[index] = .{
            .metadata = target.metadata,
            .function_index = target.function_index,
        };
    }
    return views;
}

fn contractRequirements(comptime plan: lowering_api.ProgramPlan) [plan.requirements.len]ContractRequirementView {
    var views: [plan.requirements.len]ContractRequirementView = undefined;
    for (plan.requirements, 0..) |requirement, index| {
        views[index] = .{
            .label = requirement.label,
            .first_op = requirement.first_op,
            .op_count = requirement.op_count,
            .lifecycle_tag = requirement.lifecycle_tag,
            .output_tag = requirement.output_tag,
        };
    }
    return views;
}

fn contractOps(comptime plan: lowering_api.ProgramPlan) [plan.ops.len]ContractOpView {
    var views: [plan.ops.len]ContractOpView = undefined;
    for (plan.ops, 0..) |op, index| {
        const requirement = plan.requirements[op.requirement_index];
        views[index] = .{
            .requirement_index = op.requirement_index,
            .requirement_label = requirement.label,
            .op_name = op.op_name,
            .mode = op.mode,
            .payload_ref = .{ .codec = op.payload_codec, .schema_index = op.payload_schema_index },
            .resume_ref = .{ .codec = op.resume_codec, .schema_index = op.resume_schema_index },
            .has_after = op.has_after,
        };
    }
    return views;
}

fn contractReturnErrorSeen(comptime values: []const []const u8, comptime len: usize, comptime literal: []const u8) bool {
    for (values[0..len]) |value| {
        if (std.mem.eql(u8, value, literal)) return true;
    }
    return false;
}

fn contractReturnErrorCount(comptime plan: lowering_api.ProgramPlan, comptime nested_targets: anytype) usize {
    const analysis = comptime plan_types.entryExecutionAnalysisWithNestedTargets(plan, nested_targets) catch |err|
        @compileError("Body.compiled_plan entry execution analysis failed: " ++ @errorName(err));
    var values: [plan.instructions.len][]const u8 = undefined;
    var count: usize = 0;
    for (plan.instructions, 0..) |instruction, instruction_index| {
        if (!analysis.reachable_instructions[instruction_index] or instruction.kind != .return_error) continue;
        if (contractReturnErrorSeen(values[0..], count, instruction.string_literal)) continue;
        values[count] = instruction.string_literal;
        count += 1;
    }
    return count;
}

fn contractReturnErrors(
    comptime plan: lowering_api.ProgramPlan,
    comptime nested_targets: anytype,
) [contractReturnErrorCount(plan, nested_targets)][]const u8 {
    const analysis = comptime plan_types.entryExecutionAnalysisWithNestedTargets(plan, nested_targets) catch |err|
        @compileError("Body.compiled_plan entry execution analysis failed: " ++ @errorName(err));
    var views: [contractReturnErrorCount(plan, nested_targets)][]const u8 = undefined;
    var count: usize = 0;
    for (plan.instructions, 0..) |instruction, instruction_index| {
        if (!analysis.reachable_instructions[instruction_index] or instruction.kind != .return_error) continue;
        if (contractReturnErrorSeen(views[0..], count, instruction.string_literal)) continue;
        views[count] = instruction.string_literal;
        count += 1;
    }
    return views;
}

fn ProgramContractFor(
    comptime program_label: []const u8,
    comptime plan: lowering_api.ProgramPlan,
    comptime ResultValue: type,
    comptime OutputsValue: type,
    comptime schema_types: anytype,
    comptime nested_targets: anytype,
    comptime site_metadata: anytype,
) type {
    const contract_result_ref = lowering_api.executableResultRefForPlan(plan);
    const output_views = contractOutputs(plan);
    const value_schema_views = contractValueSchemas(plan);
    const value_field_views = contractValueFields(plan);
    const value_variant_views = contractValueVariants(plan);
    const entry_parameter_views = contractEntryParameters(plan);
    const nested_with_target_views = contractNestedWithTargets(nested_targets);
    const requirement_views = contractRequirements(plan);
    const op_views = contractOps(plan);
    const return_error_views = contractReturnErrors(plan, nested_targets);
    const session_yield_site_views = lowering_api.sessionOperationYieldSitesForPlanWithMetadata(plan, nested_targets, site_metadata);
    const session_after_site_views = lowering_api.sessionAfterYieldSitesForPlanWithMetadata(plan, nested_targets, site_metadata);
    const Ledger = lowering_api.ExecutableCapabilityLedgerForPlan(plan, schema_types, nested_targets);
    const first_blocker: ?lowering_api.CapabilityBlocker = if (Ledger.blockers.len == 0) null else Ledger.blockers[0];
    const SessionLedger = lowering_api.TypedSessionCapabilityLedgerForPlan(plan, schema_types, nested_targets);
    const first_session_blocker: ?lowering_api.SessionBlocker = if (SessionLedger.blockers.len == 0) null else SessionLedger.blockers[0];

    return struct {
        /// Public program label passed to ability.program.
        pub const label = program_label;
        /// Result value reference declared by the entry ProgramPlan function.
        pub const result_ref = contract_result_ref;
        /// Result codec declared by the entry ProgramPlan function.
        pub const result_codec = contract_result_ref.codec;
        /// Result schema index when the result is product or sum typed.
        pub const result_schema_index = contract_result_ref.schema_index;
        /// Zig value type produced by Program.run.
        pub const ResultType = ResultValue;
        /// Zig outputs type produced by Program.run.
        pub const OutputsType = OutputsValue;
        /// Whether ResultType is backed by a typed ProgramPlan schema entry.
        pub const has_typed_result_schema = contract_result_ref.schema_index != null;
        /// Output declarations visible to callers without exposing mutable plan tables.
        pub const outputs = &output_views;
        /// Value schema declarations visible to callers without exposing mutable plan tables.
        pub const value_schemas = &value_schema_views;
        /// Product field declarations visible to callers without exposing mutable plan tables.
        pub const value_fields = &value_field_views;
        /// Sum variant declarations visible to callers without exposing mutable plan tables.
        pub const value_variants = &value_variant_views;
        /// Entry parameter declarations visible to callers without exposing mutable plan tables.
        pub const entry_parameters = &entry_parameter_views;
        /// Declared nested lexical-with resolver rows visible to callers.
        pub const nested_with_targets = &nested_with_target_views;
        /// Requirement declarations visible to callers without exposing mutable plan tables.
        pub const requirements = &requirement_views;
        /// Operation declarations visible to callers without exposing mutable plan tables.
        pub const ops = &op_views;
        /// Unique return_error literals declared by the compiled plan.
        pub const return_errors = &return_error_views;
        /// Whether the body declared explicit nested lexical-with resolver rows.
        pub const has_nested_with_targets = nested_targets.len != 0;
        /// Executable support ledger summary for the validated plan.
        pub const executable = struct {
            /// Whether the validated ProgramPlan has no executable capability blockers.
            pub const supported = Ledger.blockers.len == 0;
            /// Number of blockers retained in the capped executable ledger.
            pub const blocker_count = Ledger.blockers.len;
            /// Maximum blocker records retained by the executable ledger.
            pub const blocker_cap = lowering_api.max_capability_blockers;
            /// Whether executable ledger diagnostics were truncated at blocker_cap.
            pub const truncated = Ledger.truncated;
            /// Stable human-readable executable capability summary.
            pub const summary = lowering_api.executableCapabilitySummary(plan, schema_types, nested_targets);
            /// First blocker tag, if the executable ledger is non-empty.
            pub const first_blocker_tag: ?lowering_api.CapabilityBlockerTag = if (first_blocker) |blocker| blocker.tag else null;
            /// First blocker function index, if the executable ledger is non-empty.
            pub const first_blocker_function: ?u16 = if (first_blocker) |blocker| blocker.function_index else null;
            /// First blocker instruction index, if the executable ledger is non-empty.
            pub const first_blocker_instruction: ?u32 = if (first_blocker) |blocker| blocker.instruction_index else null;
        };
        /// Session-execution support summary for the validated plan.
        pub const session = struct {
            /// Whether Program.Session can start for this plan.
            pub const supported = SessionLedger.blockers.len == 0;
            /// Whether yielded requests park runtime active execution before returning to the host.
            pub const parks_runtime = true;
            /// Whether the owning Runtime must outlive all live sessions.
            pub const requires_runtime_lifetime = true;
            /// Whether yielded session requests expose deterministic trace metadata.
            pub const trace_supported = true;
            /// Stable fingerprint algorithm version mixed into all session trace hashes.
            pub const fingerprint_version = lowering_api.trace_fingerprint_version;
            /// Whether typed Program.Session values can be fingerprinted for trace/audit metadata.
            pub const value_fingerprint_supported = true;
            /// Entry-reachable operation yield sites exposed by Program.Session.
            pub const yield_sites = &session_yield_site_views;
            /// Entry-reachable after-continuation sites exposed by Program.Session.
            pub const after_sites = &session_after_site_views;
            /// Number of retained blockers for session execution.
            pub const blocker_count = SessionLedger.blockers.len;
            /// Maximum blocker records retained by the session ledger.
            pub const blocker_cap = lowering_api.max_capability_blockers;
            /// Whether session ledger diagnostics were truncated at blocker_cap.
            pub const truncated = SessionLedger.truncated;
            /// Stable human-readable session capability summary.
            pub const summary = lowering_api.typedSessionCapabilitySummary(plan, schema_types, nested_targets);
            /// First blocker tag, if the session ledger is non-empty.
            pub const first_blocker_tag: ?lowering_api.SessionBlockerTag = if (first_session_blocker) |blocker| blocker.tag else null;
            /// First blocker function index, if the session ledger is non-empty.
            pub const first_blocker_function: ?u16 = if (first_session_blocker) |blocker| blocker.function_index else null;
            /// First blocker instruction index, if the session ledger is non-empty.
            pub const first_blocker_instruction: ?u32 = if (first_session_blocker) |blocker| blocker.instruction_index else null;
            /// First blocker op index, if the session ledger is non-empty.
            pub const first_blocker_op: ?u16 = if (first_session_blocker) |blocker| blocker.op_index else null;
        };
    };
}

// zlinter-disable require_doc_comment
fn ProgramProtocolFor(
    comptime program_label: []const u8,
    comptime plan: lowering_api.ProgramPlan,
    comptime schema_types: anytype,
    comptime nested_targets: anytype,
    comptime HandlersType: type,
    comptime ProtocolOwner: type,
    comptime site_metadata: anytype,
    comptime InterpreterToken: type,
) type {
    const operation_sites = lowering_api.sessionOperationYieldSitesForPlanWithMetadata(plan, nested_targets, site_metadata);
    const after_sites = lowering_api.sessionAfterYieldSitesForPlanWithMetadata(plan, nested_targets, site_metadata);
    const plan_hash = plan.hash();

    return struct {
        pub const Owner = ProtocolOwner;
        pub const label = program_label;
        pub const hash = plan_hash;
        pub const OwnerHandlers = HandlersType;
        pub const operation_site_count = operation_sites.len;
        pub const after_site_count = after_sites.len;
        pub const operation_site_metadata = &operation_sites;
        pub const after_site_metadata = &after_sites;

        fn operationDescriptor(comptime site: lowering_api.SessionOperationYieldSite) type {
            const PayloadType = ProgramValueTypeForRef(plan, schema_types, site.payload_ref);
            const ResumeType = ProgramValueTypeForRef(plan, schema_types, site.resume_ref);
            const ResultType = ProgramValueTypeForRef(plan, schema_types, site.result_ref);
            return struct {
                pub const kind = .operation;
                pub const Owner = ProtocolOwner;
                pub const owner_label = program_label;
                pub const owner_plan_hash = plan_hash;
                pub const OwnerHandlers = HandlersType;
                pub const Payload = PayloadType;
                pub const Resume = ResumeType;
                pub const Result = ResultType;
                pub const metadata = site;
                pub const index = site.index;
                pub const fingerprint = site.fingerprint;
                pub const semantic_label = site.semantic_label;
                pub const function_index = site.function_index;
                pub const function_symbol_name = site.function_symbol_name;
                pub const block_index = site.block_index;
                pub const instruction_index = site.instruction_index;
                pub const requirement_index = site.requirement_index;
                pub const requirement_label = site.requirement_label;
                pub const op_index = site.op_index;
                pub const op_name = site.op_name;
                pub const op_mode = site.op_mode;
                pub const payload_ref = site.payload_ref;
                pub const resume_ref = site.resume_ref;
                pub const result_ref = site.result_ref;
                pub const has_after = site.has_after;
                pub const may_resume = site.host_may_resume;
                pub const may_return_now = site.host_may_return_now;
                pub const can_yield_after = site.can_yield_after;
            };
        }

        fn afterDescriptor(comptime site: lowering_api.SessionAfterYieldSite) type {
            const operation_site = operation_sites[site.source_operation_site_index];
            const static_input_ref = lowering_api.sessionAfterProtocolInputRefForOperationSite(plan, schema_types, HandlersType, operation_site);
            const static_output_ref = lowering_api.sessionAfterProtocolOutputRefForOperationSite(plan, schema_types, HandlersType, operation_site);
            const OutputType = ProgramValueTypeForRef(plan, schema_types, static_output_ref);
            const ResultType = ProgramValueTypeForRef(plan, schema_types, site.result_ref);
            if (static_input_ref) |static_ref| {
                const InputType = ProgramValueTypeForRef(plan, schema_types, static_ref);
                return struct {
                    pub const kind = .after;
                    pub const Owner = ProtocolOwner;
                    pub const owner_label = program_label;
                    pub const owner_plan_hash = plan_hash;
                    pub const OwnerHandlers = HandlersType;
                    pub const has_static_input_ref = true;
                    pub const Input = InputType;
                    pub const Output = OutputType;
                    pub const Result = ResultType;
                    pub const metadata = site;
                    pub const index = site.index;
                    pub const fingerprint = site.fingerprint;
                    pub const semantic_label = site.semantic_label;
                    pub const source_operation_site_index = site.source_operation_site_index;
                    pub const source_operation_site_fingerprint = site.source_operation_site_fingerprint;
                    pub const source_function_index = site.source_function_index;
                    pub const source_block_index = site.source_block_index;
                    pub const source_instruction_index = site.source_instruction_index;
                    pub const original_requirement_index = site.original_requirement_index;
                    pub const original_requirement_label = site.original_requirement_label;
                    pub const original_op_index = site.original_op_index;
                    pub const original_op_name = site.original_op_name;
                    pub const input_ref: ?lowering_api.ValueRef = static_ref;
                    pub const current_value_ref: ?lowering_api.ValueRef = static_ref;
                    pub const output_ref = static_output_ref;
                    pub const result_ref = site.result_ref;
                };
            }
            return struct {
                pub const kind = .after;
                pub const Owner = ProtocolOwner;
                pub const owner_label = program_label;
                pub const owner_plan_hash = plan_hash;
                pub const OwnerHandlers = HandlersType;
                pub const has_static_input_ref = false;
                pub const Output = OutputType;
                pub const Result = ResultType;
                pub const metadata = site;
                pub const index = site.index;
                pub const fingerprint = site.fingerprint;
                pub const semantic_label = site.semantic_label;
                pub const source_operation_site_index = site.source_operation_site_index;
                pub const source_operation_site_fingerprint = site.source_operation_site_fingerprint;
                pub const source_function_index = site.source_function_index;
                pub const source_block_index = site.source_block_index;
                pub const source_instruction_index = site.source_instruction_index;
                pub const original_requirement_index = site.original_requirement_index;
                pub const original_requirement_label = site.original_requirement_label;
                pub const original_op_index = site.original_op_index;
                pub const original_op_name = site.original_op_name;
                pub const input_ref: ?lowering_api.ValueRef = null;
                pub const current_value_ref: ?lowering_api.ValueRef = null;
                pub const output_ref = static_output_ref;
                pub const result_ref = site.result_ref;
            };
        }

        pub fn operationSite(
            comptime requirement_label: []const u8,
            comptime op_name: []const u8,
            comptime occurrence_index: usize,
        ) type {
            comptime var occurrence: usize = 0;
            inline for (operation_sites) |site| {
                if (std.mem.eql(u8, site.requirement_label, requirement_label) and std.mem.eql(u8, site.op_name, op_name)) {
                    if (occurrence == occurrence_index) return operationDescriptor(site);
                    occurrence += 1;
                }
            }
            @compileError("Program.protocol.operationSite could not find requested operation site");
        }

        pub fn afterSite(
            comptime requirement_label: []const u8,
            comptime op_name: []const u8,
            comptime occurrence_index: usize,
        ) type {
            comptime var occurrence: usize = 0;
            inline for (after_sites) |site| {
                if (std.mem.eql(u8, site.original_requirement_label, requirement_label) and std.mem.eql(u8, site.original_op_name, op_name)) {
                    if (occurrence == occurrence_index) return afterDescriptor(site);
                    occurrence += 1;
                }
            }
            @compileError("Program.protocol.afterSite could not find requested after site");
        }

        pub fn siteByIndex(comptime index: usize) type {
            inline for (operation_sites) |site| {
                if (site.index == index) return operationDescriptor(site);
            }
            @compileError("Program.protocol.siteByIndex could not find requested operation site");
        }

        pub fn afterSiteByIndex(comptime index: usize) type {
            inline for (after_sites) |site| {
                if (site.index == index) return afterDescriptor(site);
            }
            @compileError("Program.protocol.afterSiteByIndex could not find requested after site");
        }

        fn validateProtocolOwner(comptime Site: type) void {
            if (!hasDeclSafe(Site, "Owner")) @compileError("Program.protocol coverage listed non-protocol site descriptor");
            if (!hasDeclSafe(Site, "owner_label") or
                !std.mem.eql(u8, Site.owner_label, program_label) or
                !hasDeclSafe(Site, "owner_plan_hash") or
                Site.owner_plan_hash != plan_hash or
                !hasDeclSafe(Site, "OwnerHandlers") or
                Site.OwnerHandlers != HandlersType or
                Site.Owner != ProtocolOwner)
            {
                @compileError("Program.protocol coverage descriptor belongs to another program");
            }
        }

        fn validateOperationSite(comptime Site: type) void {
            validateProtocolOwner(Site);
            if (!hasDeclSafe(Site, "kind") or Site.kind != .operation) @compileError("Program.protocol coverage listed non-operation site");
        }

        fn validateAfterSite(comptime Site: type) void {
            validateProtocolOwner(Site);
            if (!hasDeclSafe(Site, "kind") or Site.kind != .after) @compileError("Program.protocol coverage listed non-after site");
        }

        pub fn assertOperationSitesCovered(comptime Sites: anytype) void {
            var covered: [operation_sites.len]bool = [_]bool{false} ** operation_sites.len;
            inline for (Sites) |Site| {
                comptime validateOperationSite(Site);
                if (Site.index >= operation_sites.len or operation_sites[Site.index].fingerprint != Site.fingerprint) {
                    @compileError("Program.protocol coverage descriptor belongs to another program");
                }
                if (covered[Site.index]) @compileError("Program.protocol coverage listed duplicate operation site");
                covered[Site.index] = true;
            }
            inline for (covered) |is_covered| {
                if (!is_covered) @compileError("Program.protocol coverage omitted reachable operation site");
            }
        }

        pub fn assertAfterSitesCovered(comptime Sites: anytype) void {
            var covered: [after_sites.len]bool = [_]bool{false} ** after_sites.len;
            inline for (Sites) |Site| {
                comptime validateAfterSite(Site);
                if (Site.index >= after_sites.len or after_sites[Site.index].fingerprint != Site.fingerprint) {
                    @compileError("Program.protocol coverage descriptor belongs to another program");
                }
                if (covered[Site.index]) @compileError("Program.protocol coverage listed duplicate after site");
                covered[Site.index] = true;
            }
            inline for (covered) |is_covered| {
                if (!is_covered) @compileError("Program.protocol coverage omitted reachable after site");
            }
        }

        pub fn assertAllSitesCovered(comptime Sites: anytype) void {
            var operation_covered: [operation_sites.len]bool = [_]bool{false} ** operation_sites.len;
            var after_covered: [after_sites.len]bool = [_]bool{false} ** after_sites.len;
            inline for (Sites) |Site| {
                comptime validateProtocolOwner(Site);
                switch (Site.kind) {
                    .operation => {
                        if (Site.index >= operation_sites.len or operation_sites[Site.index].fingerprint != Site.fingerprint) {
                            @compileError("Program.protocol coverage descriptor belongs to another program");
                        }
                        if (operation_covered[Site.index]) @compileError("Program.protocol coverage listed duplicate operation site");
                        operation_covered[Site.index] = true;
                    },
                    .after => {
                        if (Site.index >= after_sites.len or after_sites[Site.index].fingerprint != Site.fingerprint) {
                            @compileError("Program.protocol coverage descriptor belongs to another program");
                        }
                        if (after_covered[Site.index]) @compileError("Program.protocol coverage listed duplicate after site");
                        after_covered[Site.index] = true;
                    },
                    else => @compileError("Program.protocol coverage listed non-protocol site descriptor"),
                }
            }
            inline for (operation_covered) |is_covered| {
                if (!is_covered) @compileError("Program.protocol coverage omitted reachable operation site");
            }
            inline for (after_covered) |is_covered| {
                if (!is_covered) @compileError("Program.protocol coverage omitted reachable after site");
            }
        }

        pub fn assertAllSitesCoveredBy(comptime InterpreterType: type) void {
            if (!hasDeclSafe(InterpreterType, "InterpreterToken") or
                InterpreterType.InterpreterToken != InterpreterToken or
                !hasDeclSafe(InterpreterType, "assertCoversAll"))
            {
                @compileError("Program.protocol expected a Program.Interpreter type");
            }
            InterpreterType.assertCoversAll();
        }
    };
}
// zlinter-enable require_doc_comment

fn ProgramOutputsType(comptime Body: type) type {
    if (comptime hasDeclSafe(Body, "Outputs")) return Body.Outputs;
    return void;
}

fn collectBodyOutputs(
    comptime Body: type,
    comptime Outputs: type,
    allocator: std.mem.Allocator,
    handlers: anytype,
) anyerror!Outputs {
    if (comptime hasDeclSafe(Body, "collectOutputs")) {
        return try Body.collectOutputs(allocator, handlers);
    }
    if (Outputs != void) @compileError("Body.Outputs requires Body.collectOutputs");
    return {};
}

const DeinitResultMode = enum {
    none,
    value_and_outputs,
    value_only,
};

fn bodyDeinitResultMode(comptime Body: type, comptime Value: type, comptime Outputs: type) DeinitResultMode {
    if (comptime !hasDeclSafe(Body, "deinitResult")) return .none;
    const DeinitFn = @TypeOf(Body.deinitResult);
    if (DeinitFn == fn (std.mem.Allocator, Value) void) return .value_only;
    if (DeinitFn == fn (std.mem.Allocator, Value, Outputs) void) {
        if (Outputs != void) {
            @compileError("Body.deinitResult with Body.Outputs must have type fn (std.mem.Allocator, value) void; release outputs separately with Body.deinitOutputs");
        }
        return .value_and_outputs;
    }
    @compileError("Body.deinitResult must have type fn (std.mem.Allocator, value) void");
}

fn DeinitBodyResultArgs(comptime Value: type, comptime Outputs: type) type {
    return struct {
        allocator: std.mem.Allocator,
        value: Value,
        outputs: ?Outputs,
    };
}

fn deinitBodyResult(
    comptime Body: type,
    comptime Value: type,
    comptime Outputs: type,
    args: DeinitBodyResultArgs(Value, Outputs),
) void {
    switch (comptime bodyDeinitResultMode(Body, Value, Outputs)) {
        .none => {},
        .value_only => Body.deinitResult(args.allocator, args.value),
        .value_and_outputs => Body.deinitResult(args.allocator, args.value, args.outputs orelse {}),
    }
}

fn cloneBodyOwnedStringList(comptime T: type, allocator: std.mem.Allocator, value: T) std.mem.Allocator.Error!T {
    var owned = try allocator.alloc([]const u8, value.len);
    errdefer allocator.free(owned);
    var cloned_len: usize = 0;
    errdefer for (owned[0..cloned_len]) |item| allocator.free(item);
    for (value, 0..) |item, index| {
        owned[index] = try allocator.dupe(u8, item);
        cloned_len += 1;
    }
    return owned;
}

fn deinitBodyOwnedStringList(allocator: std.mem.Allocator, value: anytype) void {
    for (value) |item| allocator.free(item);
    allocator.free(value);
}

fn cloneBodyOwnedResultValue(allocator: std.mem.Allocator, value: anytype) std.mem.Allocator.Error!@TypeOf(value) {
    const Value = @TypeOf(value);
    if (Value == []const u8) return try allocator.dupe(u8, value);
    if (Value == []const []const u8 or Value == [][]const u8) return try cloneBodyOwnedStringList(Value, allocator, value);

    return switch (@typeInfo(Value)) {
        .void, .bool, .int, .@"enum" => value,
        .optional => blk: {
            if (value) |payload| break :blk try cloneBodyOwnedResultValue(allocator, payload);
            break :blk null;
        },
        .@"struct" => |struct_info| blk: {
            var cloned: Value = undefined;
            var initialized_fields: usize = 0;
            errdefer inline for (struct_info.fields, 0..) |field, field_index| {
                if (field_index < initialized_fields) {
                    deinitBodyOwnedResultValue(allocator, @field(cloned, field.name));
                }
            };
            inline for (struct_info.fields) |field| {
                @field(cloned, field.name) = try cloneBodyOwnedResultValue(allocator, @field(value, field.name));
                initialized_fields += 1;
            }
            break :blk cloned;
        },
        .@"union" => |union_info| blk: {
            const Tag = union_info.tag_type orelse @compileError("Program.Session result cleanup requires tagged union values");
            const active_tag = std.meta.activeTag(value);
            inline for (union_info.fields) |field| {
                if (active_tag == @field(Tag, field.name)) {
                    if (field.type == void) break :blk @unionInit(Value, field.name, {});
                    break :blk @unionInit(Value, field.name, try cloneBodyOwnedResultValue(allocator, @field(value, field.name)));
                }
            }
            unreachable;
        },
        else => @compileError("unsupported Program.Session result cleanup value type: " ++ @typeName(Value)),
    };
}

fn deinitBodyOwnedResultValue(allocator: std.mem.Allocator, value: anytype) void {
    const Value = @TypeOf(value);
    if (Value == []const u8) {
        allocator.free(value);
        return;
    }
    if (Value == []const []const u8 or Value == [][]const u8) {
        deinitBodyOwnedStringList(allocator, value);
        return;
    }

    switch (@typeInfo(Value)) {
        .void, .bool, .int, .@"enum" => {},
        .optional => if (value) |payload| deinitBodyOwnedResultValue(allocator, payload),
        .@"struct" => |struct_info| inline for (struct_info.fields) |field| {
            deinitBodyOwnedResultValue(allocator, @field(value, field.name));
        },
        .@"union" => |union_info| {
            const Tag = union_info.tag_type orelse return;
            const active_tag = std.meta.activeTag(value);
            inline for (union_info.fields) |field| {
                if (active_tag == @field(Tag, field.name)) {
                    if (field.type != void) deinitBodyOwnedResultValue(allocator, @field(value, field.name));
                    return;
                }
            }
        },
        else => {},
    }
}

const TrackedAllocation = struct {
    memory: []u8,
    alignment: std.mem.Alignment,
};

const TrackedResultAllocator = struct {
    child: std.mem.Allocator,
    allocations: std.ArrayList(TrackedAllocation) = .empty,

    fn init(child: std.mem.Allocator) @This() {
        return .{ .child = child };
    }

    fn allocator(self: *@This()) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn deinit(self: *@This()) void {
        for (self.allocations.items) |allocation| {
            self.child.rawFree(allocation.memory, allocation.alignment, @returnAddress());
        }
        self.allocations.deinit(self.child);
        self.* = .{ .child = self.child };
    }

    fn findAllocation(self: *@This(), memory: []u8, alignment: std.mem.Alignment) ?usize {
        for (self.allocations.items, 0..) |allocation, index| {
            if (allocation.memory.ptr == memory.ptr and allocation.memory.len == memory.len and allocation.alignment == alignment) {
                return index;
            }
        }
        return null;
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        const ptr = self.child.rawAlloc(len, alignment, ret_addr) orelse return null;
        self.allocations.append(self.child, .{
            .memory = ptr[0..len],
            .alignment = alignment,
        }) catch {
            self.child.rawFree(ptr[0..len], alignment, ret_addr);
            return null;
        };
        return ptr;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        const allocation_index = self.findAllocation(memory, alignment);
        const resized = self.child.rawResize(memory, alignment, new_len, ret_addr);
        if (resized) {
            if (allocation_index) |index| self.allocations.items[index].memory.len = new_len;
        }
        return resized;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        const allocation_index = self.findAllocation(memory, alignment);
        const ptr = self.child.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
        if (allocation_index) |index| {
            self.allocations.items[index].memory = ptr[0..new_len];
        }
        return ptr;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *@This() = @ptrCast(@alignCast(ctx));
        if (self.findAllocation(memory, alignment)) |index| {
            _ = self.allocations.swapRemove(index);
        }
        self.child.rawFree(memory, alignment, ret_addr);
    }
};

const TrackedBodyResultStorage = struct {
    tracker: TrackedResultAllocator,

    fn deinit(self: *@This()) void {
        self.tracker.deinit();
    }
};

fn TrackedBodyResultClone(comptime Value: type) type {
    return struct {
        value: Value,
        storage: ResultOwnedStorage,
        cleanup_allocator: std.mem.Allocator,
    };
}

fn cloneBodyOwnedResultWithTrackedStorage(
    comptime Value: type,
    allocator: std.mem.Allocator,
    value: Value,
) std.mem.Allocator.Error!TrackedBodyResultClone(Value) {
    const boxed = try allocator.create(TrackedBodyResultStorage);
    errdefer allocator.destroy(boxed);
    boxed.* = .{ .tracker = TrackedResultAllocator.init(allocator) };
    errdefer boxed.tracker.deinit();

    const cleanup_allocator = boxed.tracker.allocator();
    const cloned = try cloneBodyOwnedResultValue(cleanup_allocator, value);
    return .{
        .value = cloned,
        .storage = .{
            .allocator = allocator,
            .ptr = boxed,
            .destroy = ResultStorageDestroyer(TrackedBodyResultStorage).destroy,
        },
        .cleanup_allocator = cleanup_allocator,
    };
}

const ResultOwnedStorage = struct {
    allocator: std.mem.Allocator,
    ptr: *anyopaque,
    destroy: *const fn (std.mem.Allocator, *anyopaque) void,

    fn deinit(self: *@This()) void {
        self.destroy(self.allocator, self.ptr);
    }
};

fn ResultStorageDestroyer(comptime Storage: type) type {
    return struct {
        fn destroy(allocator: std.mem.Allocator, ptr: *anyopaque) void {
            const storage: *Storage = @ptrCast(@alignCast(ptr));
            storage.deinit();
            allocator.destroy(storage);
        }
    };
}

fn errorValueInSet(comptime ErrorSet: type, err: anyerror) bool {
    return switch (@typeInfo(ErrorSet)) {
        .error_set => |errors| blk: {
            if (errors) |decls| {
                inline for (decls) |decl| {
                    if (err == @field(ErrorSet, decl.name)) break :blk true;
                }
                break :blk false;
            }
            break :blk true;
        },
        else => @compileError("Program.Error must be an error set"),
    };
}

fn mapProgramRunError(comptime ErrorSet: type, err: anyerror) ErrorSet {
    if (errorValueInSet(ErrorSet, err)) return @errorCast(err);
    return error.ProgramContractViolation;
}

/// Declare one reusable explicit local effect program.
pub fn program(
    comptime label: []const u8,
    comptime HandlersType: type,
    comptime Body: type,
) type {
    if (label.len == 0) @compileError("ability.program label must be non-empty");
    const body_compiled_plan = ProgramPlanForBody(Body);
    const body_value_schema_types = BodyValueSchemaTypes(Body).values;
    const body_nested_with_targets = BodyNestedWithTargets(Body).values;
    const body_site_metadata = BodySiteMetadata(Body).values;
    const body_compiled_plan_hash = body_compiled_plan.hash();
    const InterpreterAuthenticityToken = opaque {};
    const handler_value_storage_size = maxProgramValueStorageSize(body_value_schema_types);
    const handler_value_storage_align = maxProgramValueStorageAlign(body_value_schema_types);
    const Value = ProgramValueTypeForRef(body_compiled_plan, body_value_schema_types, lowering_api.executableResultRefForPlan(body_compiled_plan));
    const ProgramOutputs = ProgramOutputsType(Body);

    return struct {
        const InterpreterToken = InterpreterAuthenticityToken;

        /// Runtime-owned executable plan for this public program.
        pub const compiled_plan = body_compiled_plan;
        /// Read-only projection of the compiled ProgramPlan contract.
        pub const contract = ProgramContractFor(label, body_compiled_plan, Value, ProgramOutputs, body_value_schema_types, body_nested_with_targets, body_site_metadata);
        /// Typed defunctionalized protocol descriptors derived from Program.Session static sites.
        pub const protocol = ProgramProtocolFor(label, body_compiled_plan, body_value_schema_types, body_nested_with_targets, HandlersType, Body, body_site_metadata, InterpreterAuthenticityToken);
        /// Public execution error for this program.
        pub const Error = ProgramErrorSet(Body);
        /// Separate fingerprint domain for protocol reinterpretation metadata.
        pub const reinterpret_fingerprint_version: u32 = 2;
        /// Separate fingerprint domain for residual ProgramPlan transformation metadata.
        pub const residual_fingerprint_version: u32 = 1;
        /// Separate fingerprint domain for proof-carrying effect pipeline metadata.
        pub const pipeline_fingerprint_version: u32 = 1;

        /// Public result value plus outputs. Cleanup is uniform even for void outputs.
        pub const Result = struct {
            allocator: std.mem.Allocator,
            value: Value,
            outputs: ProgramOutputs,
            _session_storage: ?ResultOwnedStorage = null,
            _result_cleanup_allocator: ?std.mem.Allocator = null,

            /// Release owned result resources declared by the program body.
            pub fn deinit(self: *@This()) void {
                deinitBodyResult(Body, Value, ProgramOutputs, .{
                    .allocator = self._result_cleanup_allocator orelse self.allocator,
                    .value = self.value,
                    .outputs = self.outputs,
                });
                if (comptime hasDeclSafe(Body, "deinitOutputs")) {
                    const DeinitOutputsFn = @TypeOf(Body.deinitOutputs);
                    if (DeinitOutputsFn != fn (std.mem.Allocator, ProgramOutputs) void) {
                        @compileError("Body.deinitOutputs must have type fn (std.mem.Allocator, outputs) void");
                    }
                    Body.deinitOutputs(self.allocator, self.outputs);
                }
                if (self._session_storage) |*storage| storage.deinit();
                self._session_storage = null;
                self._result_cleanup_allocator = null;
            }
        };

        fn finishResultWithStorage(
            allocator: std.mem.Allocator,
            handlers: anytype,
            value: Value,
            session_storage: ?ResultOwnedStorage,
            result_cleanup_allocator: ?std.mem.Allocator,
        ) Error!Result {
            var storage = session_storage;
            const outputs = collectBodyOutputs(Body, ProgramOutputs, allocator, handlers) catch |err| {
                deinitBodyResult(Body, Value, ProgramOutputs, .{
                    .allocator = result_cleanup_allocator orelse allocator,
                    .value = value,
                    .outputs = null,
                });
                if (storage) |*owned| owned.deinit();
                return mapProgramRunError(Error, err);
            };
            return .{
                .allocator = allocator,
                .value = value,
                .outputs = outputs,
                ._session_storage = storage,
                ._result_cleanup_allocator = result_cleanup_allocator,
            };
        }

        fn finishResult(allocator: std.mem.Allocator, handlers: anytype, value: Value) Error!Result {
            return finishResultWithStorage(allocator, handlers, value, null, null);
        }

        /// Execute the compiled ProgramPlan against one caller-owned runtime.
        /// Bodies may provide scalar ProgramValue args, typed tuple args, schema types,
        /// nested-with targets, output collection, and explicit deinit hooks.
        pub fn run(runtime: *lowered_machine.Runtime, handlers: HandlersType) Error!Result {
            var mutable_handlers = handlers;
            lowered_machine.beginExecution(runtime) catch |err| return mapProgramRunError(Error, err);
            defer lowered_machine.endExecution(runtime);
            const args = if (comptime hasDeclSafe(Body, "encodeArgs"))
                Body.encodeArgs(mutable_handlers)
            else
                @as([]const lowered_machine.ProgramValue, &.{});
            const raw = if (comptime @typeInfo(HandlersType) == .pointer)
                lowering_api.runExecutablePlanWithTypedArgsForErrorSetAndNestedTargetsInRuntimeExecution(BodyErrorSet(Body), runtime, compiled_plan, body_value_schema_types, body_nested_with_targets, mutable_handlers, args) catch |err| return mapProgramRunError(Error, err)
            else
                lowering_api.runExecutablePlanWithTypedArgsForErrorSetAndNestedTargetsInRuntimeExecution(BodyErrorSet(Body), runtime, compiled_plan, body_value_schema_types, body_nested_with_targets, &mutable_handlers, args) catch |err| return mapProgramRunError(Error, err);
            const allocator = lowered_machine.runtimeAllocator(runtime);
            if (comptime @typeInfo(HandlersType) == .pointer) {
                return finishResult(allocator, mutable_handlers, raw.value);
            }
            return finishResult(allocator, &mutable_handlers, raw.value);
        }

        /// Host-driven session execution for plans with defunctionalized operation and after-continuation requests.
        pub const Session = struct {
            const Core = lowering_api.ExecutableSessionForPlan(
                BodyErrorSet(Body),
                label,
                body_compiled_plan,
                body_value_schema_types,
                body_nested_with_targets,
                HandlersType,
                Body,
            );

            runtime: *lowered_machine.Runtime,
            handlers: HandlersType,
            core: Core,
            lifecycle: Lifecycle = .ready,
            live_registered: bool = true,

            fn boxResultStorage(
                allocator: std.mem.Allocator,
                session_storage: ?Core.ResultStorage,
            ) Error!?ResultOwnedStorage {
                var storage = session_storage orelse return null;
                errdefer storage.deinit();
                const boxed = allocator.create(Core.ResultStorage) catch |err| return mapProgramRunError(Error, err);
                boxed.* = storage;
                return .{
                    .allocator = allocator,
                    .ptr = boxed,
                    .destroy = ResultStorageDestroyer(Core.ResultStorage).destroy,
                };
            }

            fn finishSessionResult(allocator: std.mem.Allocator, handlers: anytype, raw: *Core.RawResult) Error!Result {
                const result_cleanup = comptime bodyDeinitResultMode(Body, Value, ProgramOutputs);
                if (result_cleanup != .none) {
                    var storage = raw.takeStorage();
                    defer if (storage) |*owned| owned.deinit();
                    if (storage != null) {
                        const owned = cloneBodyOwnedResultWithTrackedStorage(Value, allocator, raw.value) catch |err| return mapProgramRunError(Error, err);
                        return finishResultWithStorage(allocator, handlers, owned.value, owned.storage, owned.cleanup_allocator);
                    }
                    return finishResultWithStorage(allocator, handlers, raw.value, null, null);
                }
                const storage = try boxResultStorage(allocator, raw.takeStorage());
                return finishResultWithStorage(allocator, handlers, raw.value, storage, null);
            }

            const Lifecycle = enum {
                deinitialized,
                done,
                parked_on_after,
                parked_on_request,
                ready,
                running,
            };

            /// Defunctionalized effect operation request yielded by `next`.
            pub const Request = Core.Request;
            /// Defunctionalized after-continuation request yielded by `next`.
            pub const AfterRequest = Core.AfterRequest;
            /// Read-only request/response trace metadata and fingerprint views.
            pub const Trace = Core.Trace;
            /// Read-only continuation capsule metadata.
            pub const CapsuleMetadata = Core.CapsuleMetadata;
            /// Parked continuation kind captured in a capsule.
            pub const ParkedKind = Core.ParkedKind;
            /// Capsule schema version for in-process parked continuation snapshots.
            pub const capsule_version = Core.capsule_version;
            /// Continuation fingerprint version for capsule fingerprints.
            pub const continuation_fingerprint_version = Core.continuation_fingerprint_version;
            /// Current parked request view without advancing the interpreter.
            pub const Current = Core.Current;
            /// First-class in-process snapshot of a parked continuation.
            pub const Capsule = struct {
                _core: Core.Capsule,

                /// Release capsule-owned continuation values.
                pub fn deinit(self: *@This()) void {
                    self._core.deinit();
                }

                /// Return read-only capsule metadata.
                pub fn metadata(self: *const @This()) CapsuleMetadata {
                    return self._core.metadata();
                }

                /// Return the deterministic continuation fingerprint.
                pub fn fingerprint(self: *const @This()) u64 {
                    return self._core.fingerprint();
                }

                /// Return an independent owned copy of this reusable capsule.
                pub fn clone(self: *const @This(), allocator: std.mem.Allocator) Error!@This() {
                    return .{
                        ._core = self._core.clone(allocator) catch |err| return mapProgramRunError(Error, err),
                    };
                }
            };
            /// One session step: either a terminal result, yielded operation request, or yielded after continuation.
            pub const Step = union(enum) {
                after: AfterRequest,
                done: Result,
                request: Request,
            };

            /// Start a host-driven execution session without leaving runtime execution active.
            pub fn start(runtime: *lowered_machine.Runtime, handlers: HandlersType) Error!Session {
                const mutable_handlers = handlers;
                try ensureRuntimeCanEnter(runtime);
                lowered_machine.beginExecution(runtime) catch |err| return mapProgramRunError(Error, err);
                defer lowered_machine.endExecution(runtime);

                const args = if (comptime hasDeclSafe(Body, "encodeArgs"))
                    Body.encodeArgs(mutable_handlers)
                else
                    @as([]const lowered_machine.ProgramValue, &.{});
                var core = Core.start(lowered_machine.runtimeAllocator(runtime), args) catch |err| return mapProgramRunError(Error, err);
                var core_owned = true;
                errdefer if (core_owned) core.deinit();
                lowered_machine.registerLiveSession(runtime) catch |err| return mapProgramRunError(Error, err);
                core_owned = false;
                return .{
                    .runtime = runtime,
                    .handlers = mutable_handlers,
                    .core = core,
                };
            }

            /// Restore a fresh parked session from a reusable capsule for this program.
            pub fn restore(runtime: *lowered_machine.Runtime, handlers: HandlersType, capsule: *const Capsule) Error!Session {
                const mutable_handlers = handlers;
                try ensureRuntimeCanEnter(runtime);
                var core = Core.restore(lowered_machine.runtimeAllocator(runtime), &capsule._core) catch |err| return mapProgramRunError(Error, err);
                errdefer core.deinit();
                const lifecycle: Lifecycle = switch (core.current() catch |err| return mapProgramRunError(Error, err)) {
                    .request => .parked_on_request,
                    .after => .parked_on_after,
                    .none => return error.ProgramContractViolation,
                };
                lowered_machine.registerLiveSession(runtime) catch |err| return mapProgramRunError(Error, err);
                return .{
                    .runtime = runtime,
                    .handlers = mutable_handlers,
                    .core = core,
                    .lifecycle = lifecycle,
                };
            }

            /// Close an unfinished session and release runtime ownership.
            pub fn deinit(self: *Session) void {
                self.deinitChecked() catch |err|
                    std.debug.panic("runtime execution teardown misuse: {s}", .{@errorName(err)});
            }

            /// Close an unfinished session, returning an error on runtime ownership misuse.
            pub fn deinitChecked(self: *Session) Error!void {
                switch (self.lifecycle) {
                    .done, .deinitialized => return,
                    .running => return error.RuntimeBusy,
                    .parked_on_after, .parked_on_request, .ready => {},
                }
                try ensureRuntimeCanEnter(self.runtime);
                try self.closeChecked(.deinitialized);
            }

            /// Capture the currently parked continuation as a reusable capsule.
            pub fn capture(self: *Session, allocator: std.mem.Allocator) Error!Capsule {
                try ensureRuntimeCanEnter(self.runtime);
                switch (self.lifecycle) {
                    .parked_on_after, .parked_on_request => {},
                    .ready, .running, .done, .deinitialized => return error.ProgramContractViolation,
                }
                return .{
                    ._core = self.core.capture(allocator) catch |err| return mapProgramRunError(Error, err),
                };
            }

            /// Return the current parked request without advancing or entering runtime execution.
            pub fn current(self: *Session) Error!Current {
                try ensureRuntimeCanEnter(self.runtime);
                return switch (self.lifecycle) {
                    .ready, .done => .none,
                    .parked_on_after, .parked_on_request => self.core.current() catch |err| return mapProgramRunError(Error, err),
                    .running, .deinitialized => error.ProgramContractViolation,
                };
            }

            /// Advance until the next yielded request or terminal result.
            pub fn next(self: *Session) Error!Step {
                try self.enterRuntimeFrom(.ready);
                defer self.leaveRuntime();

                if (self.core.hasPendingRequest()) return error.ProgramContractViolation;
                const core_step = self.core.next() catch |err| {
                    self.closeAs(.deinitialized);
                    return mapProgramRunError(Error, err);
                };
                return switch (core_step) {
                    .request => |request| request: {
                        self.lifecycle = .parked_on_request;
                        break :request .{ .request = request };
                    },
                    .after => |after| after: {
                        self.lifecycle = .parked_on_after;
                        break :after .{ .after = after };
                    },
                    .done => |raw_result| done: {
                        var raw = raw_result;
                        const allocator = lowered_machine.runtimeAllocator(self.runtime);
                        const result = if (comptime @typeInfo(HandlersType) == .pointer)
                            finishSessionResult(allocator, self.handlers, &raw)
                        else
                            finishSessionResult(allocator, &self.handlers, &raw);
                        const finished = result catch |err| {
                            raw.deinit();
                            self.closeAs(.deinitialized);
                            return err;
                        };
                        self.closeAs(.done);
                        break :done .{ .done = finished };
                    },
                };
            }

            /// Resume a yielded transform or choice request with a typed value.
            pub fn @"resume"(self: *Session, request: Request, value: anytype) Error!void {
                try self.enterRuntimeFrom(.parked_on_request);
                defer self.leaveRuntime();

                self.core.@"resume"(request, value) catch |err| {
                    self.lifecycle = .parked_on_request;
                    return mapProgramRunError(Error, err);
                };
                self.lifecycle = .ready;
            }

            /// Resume a typed operation request view with a value matching its static site descriptor.
            pub fn resumeTyped(self: *Session, typed_request: anytype, value: anytype) Error!void {
                const Site = @TypeOf(typed_request).Descriptor;
                _ = typed_request.request.responseTraceFor(Site, .@"resume", value) catch |err| return mapProgramRunError(Error, err);
                try self.@"resume"(typed_request.request, value);
            }

            /// Resume a yielded after-continuation request with the transformed value.
            pub fn resumeAfter(self: *Session, request: AfterRequest, value: anytype) Error!void {
                try self.enterRuntimeFrom(.parked_on_after);
                defer self.leaveRuntime();

                self.core.resumeAfter(request, value) catch |err| {
                    self.lifecycle = .parked_on_after;
                    return mapProgramRunError(Error, err);
                };
                self.lifecycle = .ready;
            }

            /// Resume a typed after-continuation request view with a value matching the live request output ref.
            pub fn resumeAfterTyped(self: *Session, typed_request: anytype, value: anytype) Error!void {
                const Site = @TypeOf(typed_request).Descriptor;
                _ = typed_request.request.responseTraceFor(Site, value) catch |err| return mapProgramRunError(Error, err);
                try self.resumeAfter(typed_request.request, value);
            }

            /// Complete a yielded choice or abort request with a terminal value.
            pub fn returnNow(self: *Session, request: Request, value: anytype) Error!void {
                try self.enterRuntimeFrom(.parked_on_request);
                defer self.leaveRuntime();

                self.core.returnNow(request, value) catch |err| {
                    self.lifecycle = .parked_on_request;
                    return mapProgramRunError(Error, err);
                };
                self.lifecycle = .ready;
            }

            /// Complete a typed choice or abort request view with a terminal value matching its static site descriptor.
            pub fn returnNowTyped(self: *Session, typed_request: anytype, value: anytype) Error!void {
                const Site = @TypeOf(typed_request).Descriptor;
                _ = typed_request.request.responseTraceFor(Site, .return_now, value) catch |err| return mapProgramRunError(Error, err);
                try self.returnNow(typed_request.request, value);
            }

            fn ensureRuntimeCanEnter(runtime: *lowered_machine.Runtime) Error!void {
                runtime.ensureThread() catch |err| return mapProgramRunError(Error, err);
                if (lowered_machine.activeRuntime() != null) return error.RuntimeBusy;
            }

            fn enterRuntimeFrom(self: *Session, expected: Lifecycle) Error!void {
                try ensureRuntimeCanEnter(self.runtime);
                if (self.lifecycle != expected) return error.ProgramContractViolation;
                lowered_machine.beginExecution(self.runtime) catch |err| return mapProgramRunError(Error, err);
                self.lifecycle = .running;
            }

            fn leaveRuntime(self: *Session) void {
                lowered_machine.endExecution(self.runtime);
            }

            fn close(self: *Session) void {
                self.closeChecked(.deinitialized) catch |err|
                    std.debug.panic("runtime execution teardown misuse: {s}", .{@errorName(err)});
            }

            fn closeAs(self: *Session, final_lifecycle: Lifecycle) void {
                self.closeChecked(final_lifecycle) catch |err|
                    std.debug.panic("runtime execution teardown misuse: {s}", .{@errorName(err)});
            }

            fn closeChecked(self: *Session, final_lifecycle: Lifecycle) Error!void {
                switch (self.lifecycle) {
                    .done, .deinitialized => return,
                    .parked_on_after, .parked_on_request, .ready, .running => {},
                }
                if (self.live_registered) {
                    lowered_machine.unregisterLiveSession(self.runtime) catch |err| return mapProgramRunError(Error, err);
                    self.live_registered = false;
                }
                self.deinitCompletedResult();
                self.core.deinit();
                self.lifecycle = final_lifecycle;
            }

            fn deinitCompletedResult(self: *Session) void {
                const completed = self.core.takeCompleted() catch |err|
                    std.debug.panic("completed session result decode failed during deinit: {s}", .{@errorName(err)});
                if (completed) |raw_result| {
                    var raw = raw_result;
                    defer raw.deinit();
                    const result_cleanup = comptime bodyDeinitResultMode(Body, Value, ProgramOutputs);
                    if (result_cleanup == .none) return;
                    var storage = raw.takeStorage();
                    defer if (storage) |*owned| owned.deinit();
                    const allocator = lowered_machine.runtimeAllocator(self.runtime);
                    if (storage != null) {
                        var owned = cloneBodyOwnedResultWithTrackedStorage(Value, allocator, raw.value) catch |err|
                            std.debug.panic("completed session result clone failed during deinit: {s}", .{@errorName(err)});
                        defer owned.storage.deinit();
                        deinitBodyResult(Body, Value, ProgramOutputs, .{
                            .allocator = owned.cleanup_allocator,
                            .value = owned.value,
                            .outputs = null,
                        });
                        return;
                    }
                    deinitBodyResult(Body, Value, ProgramOutputs, .{
                        .allocator = allocator,
                        .value = raw.value,
                        .outputs = null,
                    });
                }
            }
        };

        // zlinter-disable declaration_naming - Program.Handler is the documented public algebraic-effect namespace.
        fn validateProtocolOperationDescriptor(comptime TargetOp: type) void {
            if (!hasDeclSafe(TargetOp, "kind") or TargetOp.kind != .protocol_operation) {
                @compileError("Program expected a schema.Protocol operation descriptor");
            }
            inline for (.{
                "protocol_label",
                "protocol_lifecycle_tag",
                "protocol_output_tag",
                "op_name",
                "op_mode",
                "Payload",
                "Resume",
                "Result",
                "payload_ref",
                "resume_ref",
                "result_ref",
                "fingerprint",
                "may_resume",
                "may_return_now",
            }) |decl_name| {
                if (!hasDeclSafe(TargetOp, decl_name)) {
                    @compileError("schema.Protocol operation descriptor is missing " ++ decl_name);
                }
            }
        }

        fn validateSourceOperationSite(comptime Site: type) void {
            if (!hasDeclSafe(Site, "kind") or Site.kind != .operation) {
                @compileError("Program expected a Program.protocol operation site descriptor");
            }
            if (!hasDeclSafe(Site, "Owner") or
                Site.Owner != Body or
                !hasDeclSafe(Site, "owner_label") or
                !std.mem.eql(u8, Site.owner_label, label) or
                !hasDeclSafe(Site, "owner_plan_hash") or
                Site.owner_plan_hash != body_compiled_plan_hash or
                !hasDeclSafe(Site, "OwnerHandlers") or
                Site.OwnerHandlers != HandlersType)
            {
                @compileError("Program source operation descriptor belongs to another program");
            }
        }

        fn hashU32(hasher: *std.hash.Wyhash, value: u32) void {
            var bytes: [4]u8 = undefined;
            std.mem.writeInt(u32, &bytes, value, .little);
            hasher.update(&bytes);
        }

        fn hashU16(hasher: *std.hash.Wyhash, value: u16) void {
            var bytes: [2]u8 = undefined;
            std.mem.writeInt(u16, &bytes, value, .little);
            hasher.update(&bytes);
        }

        fn hashI32(hasher: *std.hash.Wyhash, value: i32) void {
            hashU32(hasher, @bitCast(value));
        }

        fn hashU64(hasher: *std.hash.Wyhash, value: u64) void {
            var bytes: [8]u8 = undefined;
            std.mem.writeInt(u64, &bytes, value, .little);
            hasher.update(&bytes);
        }

        fn hashUsize(hasher: *std.hash.Wyhash, value: usize) void {
            hashU64(hasher, @intCast(value));
        }

        fn hashBool(hasher: *std.hash.Wyhash, value: bool) void {
            hasher.update(&[_]u8{@intFromBool(value)});
        }

        fn hashBytes(hasher: *std.hash.Wyhash, bytes: []const u8) void {
            hashUsize(hasher, bytes.len);
            hasher.update(bytes);
        }

        fn hashValueRef(hasher: *std.hash.Wyhash, ref: lowering_api.ValueRef) void {
            hashBytes(hasher, @tagName(ref.codec));
            if (ref.schema_index) |schema_index| {
                const stable_index: u32 = schema_index;
                hashU32(hasher, stable_index);
            } else {
                hashBytes(hasher, "none");
            }
        }

        fn hashProgramValueTypeIdentity(hasher: *std.hash.Wyhash, comptime ValueType: type) void {
            hashBytes(hasher, @typeName(ValueType));
        }

        fn hashTypedPayload(hasher: *std.hash.Wyhash, comptime ref: lowering_api.ValueRef, value: anytype) Error!void {
            const ValueType = @TypeOf(value);
            if (!ref.eql(ProgramValueRefForType(body_value_schema_types, ValueType))) return error.ProgramContractViolation;
            switch (ref.codec) {
                .unit => {},
                .bool => hashBool(hasher, value),
                .i32 => hashI32(hasher, value),
                .usize => hashUsize(hasher, value),
                .string => hashBytes(hasher, value),
                .string_list => {
                    hashUsize(hasher, value.len);
                    for (value) |item| hashBytes(hasher, item);
                },
                .product => {
                    const info = @typeInfo(ValueType).@"struct";
                    inline for (info.fields) |field| {
                        hashBytes(hasher, field.name);
                        const field_ref = ProgramValueRefForType(body_value_schema_types, field.type);
                        hashValueRef(hasher, field_ref);
                        try hashTypedPayload(hasher, field_ref, @field(value, field.name));
                    }
                },
                .sum => switch (@typeInfo(ValueType)) {
                    .@"enum" => hashBytes(hasher, @tagName(value)),
                    .optional => {
                        if (value) |payload| {
                            hashBytes(hasher, "some");
                            const payload_ref = ProgramValueRefForType(body_value_schema_types, @TypeOf(payload));
                            hashValueRef(hasher, payload_ref);
                            try hashTypedPayload(hasher, payload_ref, payload);
                        } else {
                            hashBytes(hasher, "none");
                        }
                    },
                    .@"union" => |union_info| {
                        const tag = std.meta.activeTag(value);
                        hashBytes(hasher, @tagName(tag));
                        inline for (union_info.fields) |field| {
                            if (tag == @field(union_info.tag_type.?, field.name)) {
                                if (field.type == void) return;
                                const payload_ref = ProgramValueRefForType(body_value_schema_types, field.type);
                                hashValueRef(hasher, payload_ref);
                                try hashTypedPayload(hasher, payload_ref, @field(value, field.name));
                                return;
                            }
                        }
                    },
                    else => return error.ProgramContractViolation,
                },
            }
        }

        fn fingerprintTypedProgramValue(comptime ref: lowering_api.ValueRef, value: anytype) Error!u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "ability.session.value");
            hashU32(&hasher, Session.Trace.fingerprint_version);
            hashValueRef(&hasher, ref);
            try hashTypedPayload(&hasher, ref, value);
            return hasher.final();
        }

        fn hashTypedProtocolPayload(hasher: *std.hash.Wyhash, comptime ref: lowering_api.ValueRef, value: anytype) Error!void {
            const ValueType = @TypeOf(value);
            if (comptime !ProgramValueRefCompatibleWithType(ref, ValueType)) return error.ProgramContractViolation;
            hashProgramValueTypeIdentity(hasher, ValueType);
            switch (ref.codec) {
                .unit => {},
                .bool => hashBool(hasher, value),
                .i32 => hashI32(hasher, value),
                .usize => hashUsize(hasher, value),
                .string => hashBytes(hasher, value),
                .string_list => {
                    hashUsize(hasher, value.len);
                    for (value) |item| hashBytes(hasher, item);
                },
                .product => {
                    const info = @typeInfo(ValueType).@"struct";
                    inline for (info.fields) |field| {
                        hashBytes(hasher, field.name);
                        const field_ref = comptime ProgramValueStandaloneRefForType(field.type);
                        hashValueRef(hasher, field_ref);
                        try hashTypedProtocolPayload(hasher, field_ref, @field(value, field.name));
                    }
                },
                .sum => switch (@typeInfo(ValueType)) {
                    .@"enum" => hashBytes(hasher, @tagName(value)),
                    .optional => {
                        if (value) |payload| {
                            hashBytes(hasher, "some");
                            const payload_ref = comptime ProgramValueStandaloneRefForType(@TypeOf(payload));
                            hashValueRef(hasher, payload_ref);
                            try hashTypedProtocolPayload(hasher, payload_ref, payload);
                        } else {
                            hashBytes(hasher, "none");
                        }
                    },
                    .@"union" => |union_info| {
                        const tag = std.meta.activeTag(value);
                        hashBytes(hasher, @tagName(tag));
                        inline for (union_info.fields) |field| {
                            if (tag == @field(union_info.tag_type.?, field.name)) {
                                if (field.type == void) return;
                                const payload_ref = comptime ProgramValueStandaloneRefForType(field.type);
                                hashValueRef(hasher, payload_ref);
                                try hashTypedProtocolPayload(hasher, payload_ref, @field(value, field.name));
                                return;
                            }
                        }
                    },
                    else => return error.ProgramContractViolation,
                },
            }
        }

        fn fingerprintTypedProtocolValue(comptime ref: lowering_api.ValueRef, value: anytype) Error!u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "ability.session.protocol_value");
            hashU32(&hasher, reinterpret_fingerprint_version);
            hashValueRef(&hasher, ref);
            try hashTypedProtocolPayload(&hasher, ref, value);
            return hasher.final();
        }

        fn cloneProgramValue(allocator: std.mem.Allocator, comptime ValueType: type, value: ValueType) Error!ValueType {
            if (ValueType == void or ValueType == bool or ValueType == i32 or ValueType == usize) return value;
            if (ValueType == []const u8) return allocator.dupe(u8, value) catch |err| return mapProgramRunError(Error, err);
            if (ValueType == []const []const u8 or ValueType == [][]const u8) {
                const cloned = allocator.alloc([]const u8, value.len) catch |err| return mapProgramRunError(Error, err);
                var initialized: usize = 0;
                errdefer {
                    for (cloned[0..initialized]) |item| allocator.free(item);
                    allocator.free(cloned);
                }
                for (value, 0..) |item, index| {
                    cloned[index] = allocator.dupe(u8, item) catch |err| return mapProgramRunError(Error, err);
                    initialized += 1;
                }
                return cloned;
            }
            return switch (@typeInfo(ValueType)) {
                .@"enum" => value,
                .optional => |optional| if (value) |payload|
                    try cloneProgramValue(allocator, optional.child, payload)
                else
                    null,
                .@"struct" => |info| blk: {
                    var result: ValueType = undefined;
                    var initialized_fields: usize = 0;
                    errdefer inline for (info.fields, 0..) |field, field_index| {
                        if (field_index < initialized_fields) {
                            deinitProgramValue(allocator, field.type, @field(result, field.name));
                        }
                    };
                    inline for (info.fields) |field| {
                        @field(result, field.name) = try cloneProgramValue(allocator, field.type, @field(value, field.name));
                        initialized_fields += 1;
                    }
                    break :blk result;
                },
                .@"union" => |union_info| blk: {
                    const Tag = union_info.tag_type orelse return error.ProgramContractViolation;
                    const tag = std.meta.activeTag(value);
                    inline for (union_info.fields) |field| {
                        if (tag == @field(Tag, field.name)) {
                            if (field.type == void) break :blk @unionInit(ValueType, field.name, {});
                            const cloned = try cloneProgramValue(allocator, field.type, @field(value, field.name));
                            break :blk @unionInit(ValueType, field.name, cloned);
                        }
                    }
                    return error.ProgramContractViolation;
                },
                else => return error.ProgramContractViolation,
            };
        }

        fn protocolPayloadContainsMutableStringList(comptime Payload: type) bool {
            if (Payload == [][]const u8) return true;
            return switch (@typeInfo(Payload)) {
                .optional => |optional| protocolPayloadContainsMutableStringList(optional.child),
                .@"struct" => |info| {
                    inline for (info.fields) |field| {
                        if (protocolPayloadContainsMutableStringList(field.type)) return true;
                    }
                    return false;
                },
                .@"union" => |info| {
                    inline for (info.fields) |field| {
                        if (protocolPayloadContainsMutableStringList(field.type)) return true;
                    }
                    return false;
                },
                else => false,
            };
        }

        fn ProtocolHandlerPayloadType(comptime Payload: type) type {
            if (Payload == [][]const u8) return []const []const u8;
            if (protocolPayloadContainsMutableStringList(Payload)) {
                @compileError("Program.Handler protocol request payload contains mutable string-list storage");
            }
            return Payload;
        }

        fn protocolHandlerPayloadView(value: anytype) ProtocolHandlerPayloadType(@TypeOf(value)) {
            if (@TypeOf(value) == [][]const u8) return @as([]const []const u8, value);
            return value;
        }

        fn deinitProgramValue(allocator: std.mem.Allocator, comptime ValueType: type, value: ValueType) void {
            if (ValueType == []const u8) {
                allocator.free(value);
                return;
            }
            if (ValueType == []const []const u8 or ValueType == [][]const u8) {
                for (value) |item| allocator.free(item);
                allocator.free(value);
                return;
            }
            switch (@typeInfo(ValueType)) {
                .optional => |optional| if (value) |payload| deinitProgramValue(allocator, optional.child, payload),
                .@"struct" => |info| inline for (info.fields) |field| {
                    deinitProgramValue(allocator, field.type, @field(value, field.name));
                },
                .@"union" => |union_info| {
                    if (union_info.tag_type) |Tag| {
                        const tag = std.meta.activeTag(value);
                        inline for (union_info.fields) |field| {
                            if (tag == @field(Tag, field.name)) {
                                if (field.type != void) deinitProgramValue(allocator, field.type, @field(value, field.name));
                            }
                        }
                    }
                },
                else => {},
            }
        }

        fn reinterpretFingerprint(
            source_request_fingerprint: u64,
            source_capsule_fingerprint: u64,
            target_operation_fingerprint: u64,
            target_payload_fingerprint: u64,
        ) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "ability.session.reinterpret");
            hashU32(&hasher, reinterpret_fingerprint_version);
            hashU64(&hasher, source_request_fingerprint);
            hashU64(&hasher, source_capsule_fingerprint);
            hashU64(&hasher, target_operation_fingerprint);
            hashU64(&hasher, target_payload_fingerprint);
            return hasher.final();
        }

        fn mapperIdentityFingerprint(comptime Mapper: type) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "ability.program.mapper");
            hashU32(&hasher, reinterpret_fingerprint_version);
            hashBytes(&hasher, @typeName(Mapper));
            if (comptime hasDeclSafe(Mapper, "identity_fingerprint")) {
                hashU64(&hasher, Mapper.identity_fingerprint);
            } else if (comptime hasDeclSafe(Mapper, "fingerprint")) {
                hashU64(&hasher, Mapper.fingerprint);
            }
            return hasher.final();
        }

        fn morphismFingerprint(comptime SourceSite: type, comptime TargetOp: type, comptime Mapper: type) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "ability.program.morphism");
            hashU32(&hasher, reinterpret_fingerprint_version);
            hashU64(&hasher, SourceSite.owner_plan_hash);
            hashU64(&hasher, SourceSite.fingerprint);
            hashU64(&hasher, TargetOp.fingerprint);
            hashU64(&hasher, mapperIdentityFingerprint(Mapper));
            return hasher.final();
        }

        /// Static disposition assigned to one source site in a residualization report.
        pub const ResidualDisposition = enum {
            eliminated,
            forwarded,
            reinterpreted,
        };

        /// Supported source-side action emitted by a residual response mapping.
        pub const ResidualActionKind = enum {
            resume_identity,
            resume_const_i32,
            return_const_i32,
            unsupported,
        };

        /// Source-side action descriptor used inside residual response branches.
        pub const ResidualAction = struct {
            kind: ResidualActionKind,
            i32_value: i32 = 0,
            reason: []const u8 = "",

            /// Resume the source site with the target response value unchanged.
            pub fn resumeIdentity() @This() {
                return .{ .kind = .resume_identity };
            }

            /// Resume the source site with a constant i32 value.
            pub fn resumeConstI32(comptime value: i32) @This() {
                return .{ .kind = .resume_const_i32, .i32_value = value };
            }

            /// Return immediately from the source site with a constant i32 result.
            pub fn returnConstI32(comptime value: i32) @This() {
                return .{ .kind = .return_const_i32, .i32_value = value };
            }

            /// Mark this action as statically unsupported for residualization.
            pub fn unsupported(comptime reason: []const u8) @This() {
                return .{ .kind = .unsupported, .reason = reason };
            }
        };

        /// Supported target-response mapping shapes for residualization metadata.
        pub const ResidualResponseKind = enum {
            resume_identity,
            resume_const_i32,
            return_const_i32,
            bool_i32,
            unsupported,
        };

        /// Target-response mapping descriptor for one residual morphism.
        pub const ResidualResponse = struct {
            kind: ResidualResponseKind,
            i32_value: i32 = 0,
            when_true: ResidualAction = ResidualAction.unsupported("missing true branch"),
            when_false: ResidualAction = ResidualAction.unsupported("missing false branch"),
            reason: []const u8 = "",

            /// Resume the source site with the target response value unchanged.
            pub fn resumeIdentity() @This() {
                return .{ .kind = .resume_identity };
            }

            /// Resume the source site with a constant i32 value.
            pub fn resumeConstI32(comptime value: i32) @This() {
                return .{ .kind = .resume_const_i32, .i32_value = value };
            }

            /// Return immediately from the source site with a constant i32 result.
            pub fn returnConstI32(comptime value: i32) @This() {
                return .{ .kind = .return_const_i32, .i32_value = value };
            }

            /// Branch a bool target response into i32 source actions.
            pub fn boolI32(comptime branches: anytype) @This() {
                if (!@hasField(@TypeOf(branches), "when_true")) @compileError("ResidualResponse.boolI32 requires .when_true");
                if (!@hasField(@TypeOf(branches), "when_false")) @compileError("ResidualResponse.boolI32 requires .when_false");
                return .{
                    .kind = .bool_i32,
                    .when_true = branches.when_true,
                    .when_false = branches.when_false,
                };
            }

            /// Mark this response mapping as statically unsupported for residualization.
            pub fn unsupported(comptime reason: []const u8) @This() {
                return .{ .kind = .unsupported, .reason = reason };
            }
        };

        /// Static reason a residual morphism cannot be compiled in this version.
        pub const ResidualBlockerTag = enum {
            unsupported_source_mode,
            unsupported_target_mode,
            unsupported_payload_mapping,
            unsupported_response_mapping,
            source_site_unreachable,
            source_site_foreign_program,
            target_schema_mismatch,
            duplicate_source_site,
            shared_source_operation,
            after_residualization_unsupported,
            nested_with_residualization_unsupported,
            output_residualization_unsupported,
        };

        /// One fail-closed residualization blocker attached to a source site.
        pub const ResidualBlocker = struct {
            tag: ResidualBlockerTag,
            source_site_index: ?usize = null,
            source_site_fingerprint: ?u64 = null,
            target_protocol_op_fingerprint: ?u64 = null,
            message: []const u8 = "",
        };

        /// Static source-to-residual site mapping emitted by a residualization report.
        pub const ResidualSourceMapEntry = struct {
            source_site_index: usize,
            source_site_fingerprint: u64,
            residual_site_index: ?usize,
            residual_site_fingerprint: ?u64,
            disposition: ResidualDisposition,
            target_protocol_label: []const u8,
            target_op_name: []const u8,
            target_protocol_op_fingerprint: u64,
            mapping_label: ?[]const u8,
        };

        /// Static effect-row summary for a residualization report.
        pub const ResidualEffectRow = struct {
            source_program_label: []const u8,
            source_plan_hash: u64,
            residual_program_label: []const u8,
            residual_plan_hash: u64,
            eliminated_source_sites: usize,
            reinterpreted_source_sites: usize,
            emitted_target_protocol_ops: usize,
            residual_operation_sites: usize,
            unsupported_source_sites: usize,
            unsupported_morphisms: usize,
            fingerprint_version: u32 = residual_fingerprint_version,
        };

        fn residualActionFingerprint(hasher: *std.hash.Wyhash, comptime action_value: ResidualAction) void {
            hashBytes(hasher, @tagName(action_value.kind));
            hashI32(hasher, action_value.i32_value);
            hashBytes(hasher, action_value.reason);
        }

        fn residualResponseFingerprint(comptime response: ResidualResponse) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "ability.program.residual.response");
            hashU32(&hasher, residual_fingerprint_version);
            hashBytes(&hasher, @tagName(response.kind));
            hashI32(&hasher, response.i32_value);
            residualActionFingerprint(&hasher, response.when_true);
            residualActionFingerprint(&hasher, response.when_false);
            hashBytes(&hasher, response.reason);
            return hasher.final();
        }

        fn residualExprFingerprint(comptime expression: anytype) u64 {
            if (comptime @hasDecl(@TypeOf(expression), "fingerprint")) return expression.fingerprint();
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "ability.ir.expr");
            if (comptime @hasField(@TypeOf(expression), "kind")) hashBytes(&hasher, @tagName(expression.kind));
            residualExprHashOptionalValueRef(&hasher, comptime if (@hasField(@TypeOf(expression), "value_ref")) expression.value_ref else null);
            if (comptime @hasField(@TypeOf(expression), "name")) hashBytes(&hasher, expression.name);
            if (comptime !@hasField(@TypeOf(expression), "name")) hashBytes(&hasher, "");
            if (comptime @hasField(@TypeOf(expression), "string_value")) hashBytes(&hasher, expression.string_value);
            if (comptime !@hasField(@TypeOf(expression), "string_value")) hashBytes(&hasher, "");
            if (comptime @hasField(@TypeOf(expression), "i32_value")) hashI32(&hasher, expression.i32_value);
            if (comptime !@hasField(@TypeOf(expression), "i32_value")) hashI32(&hasher, 0);
            if (comptime @hasField(@TypeOf(expression), "usize_value")) hashUsize(&hasher, expression.usize_value);
            if (comptime !@hasField(@TypeOf(expression), "usize_value")) hashUsize(&hasher, 0);
            if (comptime @hasField(@TypeOf(expression), "variant_ordinal")) hashU16(&hasher, expression.variant_ordinal);
            if (comptime !@hasField(@TypeOf(expression), "variant_ordinal")) hashU16(&hasher, 0);
            return hasher.final();
        }

        fn residualExprHashOptionalValueRef(hasher: *std.hash.Wyhash, comptime maybe_ref: ?lowering_api.ValueRef) void {
            hashBool(hasher, maybe_ref != null);
            if (maybe_ref) |ref_value| {
                hashBytes(hasher, @tagName(ref_value.codec));
                hashBool(hasher, ref_value.schema_index != null);
                if (ref_value.schema_index) |schema_index| hashU16(hasher, schema_index);
            }
        }

        fn residualMorphismFingerprint(
            comptime SourceSite: type,
            comptime TargetOp: type,
            comptime payload_mapping: anytype,
            comptime response_mapping: ResidualResponse,
            comptime disposition: ResidualDisposition,
            comptime mapping_label: ?[]const u8,
        ) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "ability.program.residual.morphism");
            hashU32(&hasher, residual_fingerprint_version);
            hashU64(&hasher, SourceSite.owner_plan_hash);
            hashU64(&hasher, SourceSite.fingerprint);
            hashU64(&hasher, TargetOp.fingerprint);
            hashU64(&hasher, residualExprFingerprint(payload_mapping));
            hashU64(&hasher, residualResponseFingerprint(response_mapping));
            hashBytes(&hasher, @tagName(disposition));
            if (mapping_label) |label_text| hashBytes(&hasher, label_text);
            return hasher.final();
        }

        /// Static witness that one Program operation site may be reinterpreted as one protocol operation.
        pub fn Morphism(comptime spec: anytype) type {
            const SpecType = @TypeOf(spec);
            if (!@hasField(SpecType, "source")) @compileError("Program.Morphism requires .source");
            if (!@hasField(SpecType, "target")) @compileError("Program.Morphism requires .target");
            if (!@hasField(SpecType, "Mapper")) @compileError("Program.Morphism requires .Mapper");
            const SourceSite = spec.source;
            const TargetOp = spec.target;
            validateSourceOperationSite(SourceSite);
            validateProtocolOperationDescriptor(TargetOp);
            return struct {
                /// Source Program operation site for this morphism.
                pub const source = SourceSite;
                /// Target protocol-level operation emitted by this morphism.
                pub const target = TargetOp;
                /// Comptime mapper from target responses back to source outcomes.
                pub const Mapper = spec.Mapper;
                /// Stable morphism witness fingerprint over source, target, and mapper identity.
                pub const fingerprint: u64 = morphismFingerprint(SourceSite, TargetOp, Mapper);
            };
        }

        /// Static witness that one Program operation site can be compiled into a target protocol operation.
        pub fn ResidualMorphism(comptime spec: anytype) type {
            const SpecType = @TypeOf(spec);
            if (!@hasField(SpecType, "source")) @compileError("Program.ResidualMorphism requires .source");
            if (!@hasField(SpecType, "target")) @compileError("Program.ResidualMorphism requires .target");
            const SourceSite = spec.source;
            const TargetOp = spec.target;
            validateSourceOperationSite(SourceSite);
            validateProtocolOperationDescriptor(TargetOp);
            const payload_mapping = comptime if (@hasField(SpecType, "payload")) spec.payload else .{ .kind = .identity };
            const response_mapping = comptime if (@hasField(SpecType, "response")) spec.response else ResidualResponse.resumeIdentity();
            const disposition_value = comptime if (@hasField(SpecType, "disposition")) spec.disposition else ResidualDisposition.reinterpreted;
            const mapping_label_value: ?[]const u8 = comptime if (@hasField(SpecType, "label")) spec.label else null;
            return struct {
                /// Descriptor tag for residual morphism reflection.
                pub const kind = .residual_morphism;
                /// Source Program operation site consumed by this residual morphism.
                pub const source = SourceSite;
                /// Target protocol operation emitted by this residual morphism.
                pub const target = TargetOp;
                /// Payload expression mapping for the target protocol operation.
                pub const payload = payload_mapping;
                /// Target response mapping back into the source outcome.
                pub const response = response_mapping;
                /// Source-site disposition in the residual effect row.
                pub const disposition = disposition_value;
                /// Optional stable label for report/debug displays.
                pub const mapping_label = mapping_label_value;
                /// Stable residual morphism fingerprint over source, target, and mappings.
                pub const fingerprint: u64 = residualMorphismFingerprint(
                    SourceSite,
                    TargetOp,
                    payload_mapping,
                    response_mapping,
                    disposition_value,
                    mapping_label_value,
                );
            };
        }

        fn validateResidualMorphismDescriptor(comptime Descriptor: type) void {
            if (!hasDeclSafe(Descriptor, "kind") or Descriptor.kind != .residual_morphism) {
                @compileError("Program residualization expected Program.ResidualMorphism descriptor");
            }
            validateSourceOperationSite(Descriptor.source);
            validateProtocolOperationDescriptor(Descriptor.target);
        }

        fn residualPayloadMappingSupported(comptime mapping: anytype) bool {
            if (comptime !@hasField(@TypeOf(mapping), "kind")) return false;
            return switch (mapping.kind) {
                .identity, .payload => true,
                else => false,
            };
        }

        fn residualActionSupported(comptime action_value: ResidualAction) bool {
            return switch (action_value.kind) {
                .resume_identity, .resume_const_i32, .return_const_i32 => true,
                .unsupported => false,
            };
        }

        fn residualResponseMappingSupported(comptime response: ResidualResponse) bool {
            return switch (response.kind) {
                .resume_identity => true,
                .resume_const_i32, .return_const_i32, .bool_i32, .unsupported => false,
            };
        }

        fn residualSourceOpReachableSiteCount(comptime SourceSite: type) usize {
            comptime var count: usize = 0;
            inline for (protocol.operation_site_metadata) |site| {
                if (site.op_index == SourceSite.op_index) count += 1;
            }
            return count;
        }

        fn residualBlockerFor(comptime Descriptor: type) ?ResidualBlocker {
            validateResidualMorphismDescriptor(Descriptor);
            if (Descriptor.disposition != .reinterpreted) {
                return .{
                    .tag = .unsupported_source_mode,
                    .source_site_index = Descriptor.source.index,
                    .source_site_fingerprint = Descriptor.source.fingerprint,
                    .target_protocol_op_fingerprint = Descriptor.target.fingerprint,
                    .message = "residualization first version only supports reinterpreted source-site disposition",
                };
            }
            const source_requirement = body_compiled_plan.requirements[Descriptor.source.requirement_index];
            if (source_requirement.op_count != 1) {
                return .{
                    .tag = .unsupported_source_mode,
                    .source_site_index = Descriptor.source.index,
                    .source_site_fingerprint = Descriptor.source.fingerprint,
                    .target_protocol_op_fingerprint = Descriptor.target.fingerprint,
                    .message = "residualization first version requires the source requirement row to contain exactly one op",
                };
            }
            if (residualSourceOpReachableSiteCount(Descriptor.source) != 1) {
                return .{
                    .tag = .shared_source_operation,
                    .source_site_index = Descriptor.source.index,
                    .source_site_fingerprint = Descriptor.source.fingerprint,
                    .target_protocol_op_fingerprint = Descriptor.target.fingerprint,
                    .message = "residualization first version requires the source op row to have exactly one reachable site",
                };
            }
            if (Descriptor.source.op_mode == .transform and !Descriptor.source.may_resume) {
                return .{
                    .tag = .unsupported_source_mode,
                    .source_site_index = Descriptor.source.index,
                    .source_site_fingerprint = Descriptor.source.fingerprint,
                    .target_protocol_op_fingerprint = Descriptor.target.fingerprint,
                    .message = "source transform site is not resumable",
                };
            }
            if (Descriptor.source.op_mode == .abort) {
                return .{
                    .tag = .unsupported_source_mode,
                    .source_site_index = Descriptor.source.index,
                    .source_site_fingerprint = Descriptor.source.fingerprint,
                    .target_protocol_op_fingerprint = Descriptor.target.fingerprint,
                    .message = "abort source-site residualization is unsupported in this version",
                };
            }
            if (Descriptor.target.op_mode != .transform) {
                return .{
                    .tag = .unsupported_target_mode,
                    .source_site_index = Descriptor.source.index,
                    .source_site_fingerprint = Descriptor.source.fingerprint,
                    .target_protocol_op_fingerprint = Descriptor.target.fingerprint,
                    .message = "residualization first version only targets transform protocol operations",
                };
            }
            if (Descriptor.target.protocol_output_tag != .none) {
                return .{
                    .tag = .output_residualization_unsupported,
                    .source_site_index = Descriptor.source.index,
                    .source_site_fingerprint = Descriptor.source.fingerprint,
                    .target_protocol_op_fingerprint = Descriptor.target.fingerprint,
                    .message = "residualization first version does not emit target protocol output rows",
                };
            }
            if (Descriptor.source.has_after) {
                return .{
                    .tag = .after_residualization_unsupported,
                    .source_site_index = Descriptor.source.index,
                    .source_site_fingerprint = Descriptor.source.fingerprint,
                    .target_protocol_op_fingerprint = Descriptor.target.fingerprint,
                    .message = "after-enabled source sites are not residualized in this version",
                };
            }
            if (!residualPayloadMappingSupported(Descriptor.payload)) {
                return .{
                    .tag = .unsupported_payload_mapping,
                    .source_site_index = Descriptor.source.index,
                    .source_site_fingerprint = Descriptor.source.fingerprint,
                    .target_protocol_op_fingerprint = Descriptor.target.fingerprint,
                    .message = "payload mapping is not ProgramPlan-compatible in this version",
                };
            }
            if (!residualResponseMappingSupported(Descriptor.response)) {
                return .{
                    .tag = .unsupported_response_mapping,
                    .source_site_index = Descriptor.source.index,
                    .source_site_fingerprint = Descriptor.source.fingerprint,
                    .target_protocol_op_fingerprint = Descriptor.target.fingerprint,
                    .message = "response mapping is not ProgramPlan-compatible in this version",
                };
            }
            if (!residualPayloadCompatible(Descriptor.source, Descriptor.target, Descriptor.payload)) {
                return .{
                    .tag = .target_schema_mismatch,
                    .source_site_index = Descriptor.source.index,
                    .source_site_fingerprint = Descriptor.source.fingerprint,
                    .target_protocol_op_fingerprint = Descriptor.target.fingerprint,
                    .message = "value schema mismatch for residual payload mapping",
                };
            }
            if (!residualResponseCompatible(Descriptor.source, Descriptor.target, Descriptor.response)) {
                return .{
                    .tag = .target_schema_mismatch,
                    .source_site_index = Descriptor.source.index,
                    .source_site_fingerprint = Descriptor.source.fingerprint,
                    .target_protocol_op_fingerprint = Descriptor.target.fingerprint,
                    .message = "value schema mismatch for residual response mapping",
                };
            }
            return null;
        }

        fn ResidualReportStorage(comptime config: anytype) type {
            const ConfigType = @TypeOf(config);
            if (!@hasField(ConfigType, "morphisms")) @compileError("Program.residualizationReport requires .morphisms");
            const morphisms = config.morphisms;
            comptime {
                for (morphisms) |Descriptor| {
                    validateResidualMorphismDescriptor(Descriptor);
                }
            }
            comptime var global_blocker_count_value: usize = 0;
            if (body_nested_with_targets.len != 0) global_blocker_count_value += 1;
            if (ProgramOutputs != void or body_compiled_plan.outputs.len != 0) global_blocker_count_value += 1;
            comptime var morphism_blocker_count_value: usize = 0;
            inline for (morphisms) |Descriptor| {
                if (residualBlockerFor(Descriptor) != null) morphism_blocker_count_value += 1;
            }
            comptime var duplicate_blocker_count_value: usize = 0;
            inline for (morphisms, 0..) |Descriptor, index| {
                comptime var has_prior_duplicate = false;
                inline for (morphisms, 0..) |Prior, prior_index| {
                    if (prior_index < index and
                        Prior.source.index == Descriptor.source.index and
                        Prior.source.fingerprint == Descriptor.source.fingerprint)
                    {
                        has_prior_duplicate = true;
                    }
                }
                if (has_prior_duplicate) continue;
                comptime var has_later_duplicate = false;
                inline for (morphisms, 0..) |Other, other_index| {
                    if (other_index > index and
                        Other.source.index == Descriptor.source.index and
                        Other.source.fingerprint == Descriptor.source.fingerprint)
                    {
                        has_later_duplicate = true;
                    }
                }
                if (has_later_duplicate) duplicate_blocker_count_value += 1;
            }
            const blocker_count = global_blocker_count_value + morphism_blocker_count_value + duplicate_blocker_count_value;
            var blocker_table: [blocker_count]ResidualBlocker = undefined;
            var source_map_table: [morphisms.len]ResidualSourceMapEntry = undefined;
            comptime var blocker_index: usize = 0;
            if (body_nested_with_targets.len != 0) {
                blocker_table[blocker_index] = .{
                    .tag = .nested_with_residualization_unsupported,
                    .message = "nested-with residualization is unsupported in this version",
                };
                blocker_index += 1;
            }
            if (ProgramOutputs != void or body_compiled_plan.outputs.len != 0) {
                blocker_table[blocker_index] = .{
                    .tag = .output_residualization_unsupported,
                    .message = "output residualization is unsupported in this version",
                };
                blocker_index += 1;
            }
            inline for (morphisms, 0..) |Descriptor, index| {
                if (residualBlockerFor(Descriptor)) |blocker| {
                    blocker_table[blocker_index] = blocker;
                    blocker_index += 1;
                }
                source_map_table[index] = .{
                    .source_site_index = Descriptor.source.index,
                    .source_site_fingerprint = Descriptor.source.fingerprint,
                    .residual_site_index = null,
                    .residual_site_fingerprint = null,
                    .disposition = Descriptor.disposition,
                    .target_protocol_label = Descriptor.target.protocol_label,
                    .target_op_name = Descriptor.target.op_name,
                    .target_protocol_op_fingerprint = Descriptor.target.fingerprint,
                    .mapping_label = Descriptor.mapping_label,
                };
            }
            inline for (morphisms, 0..) |Descriptor, index| {
                comptime var has_prior_duplicate = false;
                inline for (morphisms, 0..) |Prior, prior_index| {
                    if (prior_index < index and
                        Prior.source.index == Descriptor.source.index and
                        Prior.source.fingerprint == Descriptor.source.fingerprint)
                    {
                        has_prior_duplicate = true;
                    }
                }
                if (has_prior_duplicate) continue;
                inline for (morphisms, 0..) |Other, other_index| {
                    if (other_index > index and
                        Other.source.index == Descriptor.source.index and
                        Other.source.fingerprint == Descriptor.source.fingerprint)
                    {
                        blocker_table[blocker_index] = .{
                            .tag = .duplicate_source_site,
                            .source_site_index = Descriptor.source.index,
                            .source_site_fingerprint = Descriptor.source.fingerprint,
                            .target_protocol_op_fingerprint = Other.target.fingerprint,
                            .message = "duplicate residual morphisms for one source site",
                        };
                        blocker_index += 1;
                        break;
                    }
                }
            }
            const final_blockers = blocker_table;
            const final_source_map = source_map_table;
            return struct {
                /// Statically unsupported residual morphisms.
                pub const blockers = final_blockers;
                /// Body-level residualization blockers that are independent of morphism shape.
                pub const global_blocker_count = global_blocker_count_value;
                /// Per-morphism residualization blockers.
                pub const morphism_blocker_count = morphism_blocker_count_value;
                /// Duplicate source-site blocker records.
                pub const duplicate_blocker_count = duplicate_blocker_count_value;
                /// Source-site to residual-target mapping entries.
                pub const source_map = final_source_map;
            };
        }

        /// Inspect whether a residualization request is statically supported before compiling it.
        pub fn residualizationReport(comptime config: anytype) type {
            const Storage = ResidualReportStorage(config);
            const unsupported_count = Storage.blockers.len;
            const morphism_unsupported_count = Storage.morphism_blocker_count;
            const duplicate_unsupported_count = Storage.duplicate_blocker_count;
            const morphism_count = config.morphisms.len;
            const supported_morphism_count = if (Storage.global_blocker_count == 0 and duplicate_unsupported_count == 0)
                morphism_count - morphism_unsupported_count
            else
                0;
            const unsupported_morphism_count = morphism_unsupported_count + duplicate_unsupported_count;
            return struct {
                /// Residualization fingerprint domain version.
                pub const fingerprint_version = residual_fingerprint_version;
                /// Source Program label.
                pub const source_program_label = label;
                /// Source ProgramPlan hash.
                pub const source_plan_hash = body_compiled_plan_hash;
                /// Unsupported residual morphisms, if any.
                pub const unsupported = &Storage.blockers;
                /// Static mapping from source sites to residual targets.
                pub const source_map = &Storage.source_map;
                /// Static handled/residual effect-row summary.
                pub const effect_row = ResidualEffectRow{
                    .source_program_label = label,
                    .source_plan_hash = body_compiled_plan_hash,
                    .residual_program_label = if (@hasField(@TypeOf(config), "label")) config.label else label ++ ".residual",
                    .residual_plan_hash = 0,
                    .eliminated_source_sites = supported_morphism_count,
                    .reinterpreted_source_sites = supported_morphism_count,
                    .emitted_target_protocol_ops = supported_morphism_count,
                    .residual_operation_sites = protocol.operation_site_count,
                    .unsupported_source_sites = unsupported_morphism_count,
                    .unsupported_morphisms = unsupported_morphism_count,
                };
                /// Whether all requested residual morphisms are supported.
                pub const supported = unsupported_count == 0;
            };
        }

        fn residualizationFingerprint(comptime config: anytype) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "ability.program.residualization");
            hashU32(&hasher, residual_fingerprint_version);
            hashU64(&hasher, body_compiled_plan_hash);
            if (comptime @hasField(@TypeOf(config), "label")) hashBytes(&hasher, config.label);
            inline for (config.morphisms) |Descriptor| hashU64(&hasher, Descriptor.fingerprint);
            return hasher.final();
        }

        fn residualLabel(comptime config: anytype) []const u8 {
            if (comptime @hasField(@TypeOf(config), "label")) return config.label;
            return label ++ ".residual";
        }

        fn residualTargetValueRef(
            comptime source_ref: lowering_api.ValueRef,
            comptime target_ref: lowering_api.ValueRef,
        ) lowering_api.ValueRef {
            return switch (target_ref.codec) {
                .product, .sum => .{ .codec = target_ref.codec, .schema_index = source_ref.schema_index },
                else => target_ref,
            };
        }

        fn residualTargetOpPlan(comptime requirement_index: u16, comptime SourceSite: type, comptime TargetOp: type) plan_types.OpPlan {
            const payload_ref = residualTargetValueRef(SourceSite.payload_ref, TargetOp.payload_ref);
            const resume_ref = residualTargetValueRef(SourceSite.resume_ref, TargetOp.resume_ref);
            return .{
                .requirement_index = requirement_index,
                .op_name = TargetOp.op_name,
                .mode = TargetOp.op_mode,
                .payload_codec = payload_ref.codec,
                .payload_schema_index = payload_ref.schema_index,
                .resume_codec = resume_ref.codec,
                .resume_schema_index = resume_ref.schema_index,
                .has_after = false,
            };
        }

        fn residualPayloadCompatible(comptime SourceSite: type, comptime TargetOp: type, comptime payload_mapping: anytype) bool {
            if (payload_mapping.kind == .unit) return TargetOp.payload_ref.codec == .unit;
            if (payload_mapping.kind == .const_string) return TargetOp.payload_ref.codec == .string;
            if (payload_mapping.kind == .const_i32) return TargetOp.payload_ref.codec == .i32;
            if (payload_mapping.kind == .const_usize) return TargetOp.payload_ref.codec == .usize;
            return residualValueRefCompatible(SourceSite.Payload, SourceSite.payload_ref, TargetOp.Payload, TargetOp.payload_ref);
        }

        fn residualResponseCompatible(comptime SourceSite: type, comptime TargetOp: type, comptime response: ResidualResponse) bool {
            return switch (response.kind) {
                .resume_identity => residualValueRefCompatible(SourceSite.Resume, SourceSite.resume_ref, TargetOp.Resume, TargetOp.resume_ref),
                .resume_const_i32, .return_const_i32 => TargetOp.resume_ref.codec == .i32 and SourceSite.result_ref.codec == .i32,
                .bool_i32 => TargetOp.resume_ref.codec == .bool and SourceSite.result_ref.codec == .i32,
                .unsupported => false,
            };
        }

        fn residualValueRefCompatible(
            comptime SourceValue: type,
            comptime source_ref: lowering_api.ValueRef,
            comptime TargetValue: type,
            comptime target_ref: lowering_api.ValueRef,
        ) bool {
            if (source_ref.codec != target_ref.codec) return false;
            return switch (source_ref.codec) {
                .product, .sum => source_ref.schema_index != null and target_ref.schema_index != null and SourceValue == TargetValue,
                else => source_ref.eql(target_ref),
            };
        }

        fn ResidualPlanStorage(comptime config: anytype) type {
            const Report = residualizationReport(config);
            if (!Report.supported) {
                const first = Report.unsupported[0];
                @compileError("Program.residualize blocked: " ++ @tagName(first.tag) ++ " " ++ first.message);
            }
            if (body_nested_with_targets.len != 0) {
                @compileError("Program.residualize blocked: nested-with residualization is unsupported in this version");
            }
            if (ProgramOutputs != void or body_compiled_plan.outputs.len != 0) {
                @compileError("Program.residualize blocked: output residualization is unsupported in this version");
            }
            comptime {
                for (config.morphisms) |Descriptor| {
                    const source_requirement = body_compiled_plan.requirements[Descriptor.source.requirement_index];
                    if (source_requirement.op_count != 1) {
                        @compileError("Program.residualize first version requires the source requirement row to contain exactly one op");
                    }
                    if (!residualPayloadCompatible(Descriptor.source, Descriptor.target, Descriptor.payload)) {
                        @compileError("Program.residualize blocked: value schema mismatch for residual payload mapping");
                    }
                    if (!residualResponseCompatible(Descriptor.source, Descriptor.target, Descriptor.response)) {
                        @compileError("Program.residualize blocked: value schema mismatch for residual response mapping");
                    }
                    if (Descriptor.response.kind != .resume_identity) {
                        @compileError("Program.residualize first version compiles only identity resume response mappings");
                    }
                    if (Descriptor.payload.kind != .identity and Descriptor.payload.kind != .payload) {
                        @compileError("Program.residualize first version compiles only identity payload mappings");
                    }
                }
            }

            var requirement_table: [body_compiled_plan.requirements.len]plan_types.RequirementPlan = undefined;
            var op_table: [body_compiled_plan.ops.len]plan_types.OpPlan = undefined;
            for (body_compiled_plan.requirements, 0..) |requirement, index| requirement_table[index] = requirement;
            for (body_compiled_plan.ops, 0..) |op, index| op_table[index] = op;
            inline for (config.morphisms) |Descriptor| {
                requirement_table[Descriptor.source.requirement_index] = .{
                    .label = Descriptor.target.protocol_label,
                    .first_op = Descriptor.source.op_index,
                    .op_count = 1,
                    .lifecycle_tag = Descriptor.target.protocol_lifecycle_tag,
                    .output_tag = Descriptor.target.protocol_output_tag,
                };
                op_table[Descriptor.source.op_index] = residualTargetOpPlan(Descriptor.source.requirement_index, Descriptor.source, Descriptor.target);
            }
            const final_requirements = requirement_table;
            const final_ops = op_table;
            return struct {
                /// Residual requirement rows used to finish the compiled plan.
                pub const requirement_rows = final_requirements;
                /// Residual operation rows used to finish the compiled plan.
                pub const op_rows = final_ops;
                /// Validated ordinary ProgramPlan produced by residualization.
                const plan = plan_types.program_plan_builder.finish(.{
                    .schema_version = body_compiled_plan.schema_version,
                    .label = residualLabel(config),
                    .ir_hash = residualizationFingerprint(config),
                    .entry = plan_types.program_plan_builder.function(@intCast(body_compiled_plan.entry_index)),
                    .functions = body_compiled_plan.functions,
                    .requirements = &requirement_rows,
                    .ops = &op_rows,
                    .outputs = body_compiled_plan.outputs,
                    .value_schemas = body_compiled_plan.value_schemas,
                    .value_fields = body_compiled_plan.value_fields,
                    .value_variants = body_compiled_plan.value_variants,
                    .locals = body_compiled_plan.locals,
                    .call_args = body_compiled_plan.call_args,
                    .blocks = body_compiled_plan.blocks,
                    .terminators = body_compiled_plan.terminators,
                    .instructions = body_compiled_plan.instructions,
                }) catch |err| @compileError("Program.residualize produced invalid ProgramPlan: " ++ @errorName(err));
            };
        }

        fn ResidualBodyFor(comptime config: anytype) type {
            const Storage = ResidualPlanStorage(config);
            const ConfigType = @TypeOf(config);
            const ResidualHandlers = comptime if (@hasField(ConfigType, "Handlers")) config.Handlers else HandlersType;
            if (comptime hasDeclSafe(Body, "encodeArgs") and hasDeclSafe(Body, "deinitResult")) {
                return struct {
                    /// Ordinary ProgramPlan compiled from the residualized source plan.
                    pub const compiled_plan = Storage.plan;
                    /// Value schema type metadata inherited from the source Body.
                    pub const value_schema_types = BodyValueSchemaTypes(Body).values;
                    /// Site metadata inherited from the source Body when available.
                    pub const site_metadata = BodySiteMetadata(Body).values;
                    /// Body error set inherited from the source Body.
                    pub const Error = BodyErrorSet(Body);
                    /// Forward source result cleanup because the residual plan preserves the result type.
                    pub const deinitResult = Body.deinitResult;

                    /// Forward source argument encoding because the residual plan preserves entry parameters.
                    pub fn encodeArgs(handlers: ResidualHandlers) @TypeOf(Body.encodeArgs(handlers)) {
                        return Body.encodeArgs(handlers);
                    }
                };
            }
            if (comptime hasDeclSafe(Body, "encodeArgs")) {
                return struct {
                    /// Ordinary ProgramPlan compiled from the residualized source plan.
                    pub const compiled_plan = Storage.plan;
                    /// Value schema type metadata inherited from the source Body.
                    pub const value_schema_types = BodyValueSchemaTypes(Body).values;
                    /// Site metadata inherited from the source Body when available.
                    pub const site_metadata = BodySiteMetadata(Body).values;
                    /// Body error set inherited from the source Body.
                    pub const Error = BodyErrorSet(Body);

                    /// Forward source argument encoding because the residual plan preserves entry parameters.
                    pub fn encodeArgs(handlers: ResidualHandlers) @TypeOf(Body.encodeArgs(handlers)) {
                        return Body.encodeArgs(handlers);
                    }
                };
            }
            if (comptime hasDeclSafe(Body, "deinitResult")) {
                return struct {
                    /// Ordinary ProgramPlan compiled from the residualized source plan.
                    pub const compiled_plan = Storage.plan;
                    /// Value schema type metadata inherited from the source Body.
                    pub const value_schema_types = BodyValueSchemaTypes(Body).values;
                    /// Site metadata inherited from the source Body when available.
                    pub const site_metadata = BodySiteMetadata(Body).values;
                    /// Body error set inherited from the source Body.
                    pub const Error = BodyErrorSet(Body);
                    /// Forward source result cleanup because the residual plan preserves the result type.
                    pub const deinitResult = Body.deinitResult;
                };
            }
            return struct {
                /// Ordinary ProgramPlan compiled from the residualized source plan.
                pub const compiled_plan = Storage.plan;
                /// Value schema type metadata inherited from the source Body.
                pub const value_schema_types = BodyValueSchemaTypes(Body).values;
                /// Site metadata inherited from the source Body when available.
                pub const site_metadata = BodySiteMetadata(Body).values;
                /// Body error set inherited from the source Body.
                pub const Error = BodyErrorSet(Body);
            };
        }

        fn residualSourceMapFor(comptime ResidualProgram: type, comptime config: anytype) type {
            var entry_table: [config.morphisms.len]ResidualSourceMapEntry = undefined;
            for (config.morphisms, 0..) |Descriptor, index| {
                comptime var residual_site_index: ?usize = null;
                comptime var residual_site_fingerprint: ?u64 = null;
                inline for (ResidualProgram.protocol.operation_site_metadata) |site| {
                    if (site.function_index == Descriptor.source.function_index and
                        site.block_index == Descriptor.source.block_index and
                        site.instruction_index == Descriptor.source.instruction_index)
                    {
                        residual_site_index = site.index;
                        residual_site_fingerprint = site.fingerprint;
                    }
                }
                entry_table[index] = .{
                    .source_site_index = Descriptor.source.index,
                    .source_site_fingerprint = Descriptor.source.fingerprint,
                    .residual_site_index = residual_site_index,
                    .residual_site_fingerprint = residual_site_fingerprint,
                    .disposition = Descriptor.disposition,
                    .target_protocol_label = Descriptor.target.protocol_label,
                    .target_op_name = Descriptor.target.op_name,
                    .target_protocol_op_fingerprint = Descriptor.target.fingerprint,
                    .mapping_label = Descriptor.mapping_label,
                };
            }
            const final_entries = entry_table;
            return struct {
                /// Source-to-residual operation site correspondence entries.
                pub const map_entries = final_entries;
            };
        }

        /// Compile supported declarative morphisms into a residual ordinary ProgramPlan.
        pub fn residualize(comptime config: anytype) type {
            const ConfigType = @TypeOf(config);
            const ResidualHandlers = comptime if (@hasField(ConfigType, "Handlers")) config.Handlers else HandlersType;
            if (ResidualHandlers != HandlersType and comptime hasDeclSafe(Body, "encodeArgs")) {
                @compileError("Program.residualize cannot change Handler type while reusing Body.encodeArgs");
            }
            const ResidualBody = ResidualBodyFor(config);
            const Base = program(residualLabel(config), ResidualHandlers, ResidualBody);
            const SourceMapStorage = residualSourceMapFor(Base, config);
            const residual_effect_row = ResidualEffectRow{
                .source_program_label = label,
                .source_plan_hash = body_compiled_plan_hash,
                .residual_program_label = residualLabel(config),
                .residual_plan_hash = Base.compiled_plan.hash(),
                .eliminated_source_sites = config.morphisms.len,
                .reinterpreted_source_sites = config.morphisms.len,
                .emitted_target_protocol_ops = config.morphisms.len,
                .residual_operation_sites = Base.protocol.operation_site_count,
                .unsupported_source_sites = 0,
                .unsupported_morphisms = 0,
            };
            return struct {
                /// Ordinary ProgramPlan emitted by residualization.
                pub const compiled_plan = Base.compiled_plan;
                /// Contract projection for the residual Program.
                pub const contract = Base.contract;
                /// Typed protocol descriptors for the residual Program.
                pub const protocol = Base.protocol;
                /// Error set for executing the residual Program.
                pub const Error = Base.Error;
                /// Result type for executing the residual Program.
                pub const Result = Base.Result;
                /// Primitive host-driven Session type for the residual Program.
                pub const Session = Base.Session;
                /// Handler constructor namespace for the residual Program.
                pub const Handler = Base.Handler;
                /// Interpreter constructor namespace for the residual Program.
                pub const Interpreter = Base.Interpreter;
                /// Protocol request type for residual reinterpretation paths.
                pub const ProtocolRequest = Base.ProtocolRequest;
                /// Dynamic morphism constructor namespace for the residual Program.
                pub const Morphism = Base.Morphism;
                /// Declarative morphism constructor namespace for further residualization.
                pub const ResidualMorphism = Base.ResidualMorphism;
                /// Residualization fingerprint metadata version.
                pub const residual_fingerprint_version = Base.residual_fingerprint_version;
                /// Reinterpretation fingerprint metadata version.
                pub const reinterpret_fingerprint_version = Base.reinterpret_fingerprint_version;
                /// Run the residual Program through ordinary handler dispatch.
                pub const run = Base.run;
                /// Stable fingerprint for this residualization configuration.
                pub const residualization_fingerprint = residualizationFingerprint(config);
                /// Source-to-residual operation site correspondence.
                pub const source_map = &SourceMapStorage.map_entries;
                /// Residual effect-row metadata.
                pub const effect_row = residual_effect_row;
                /// Alias for residual effect-row metadata.
                pub const residual_row = residual_effect_row;
                /// Unsupported blockers for this compiled residual Program.
                pub const unsupported = &[_]ResidualBlocker{};

                /// Find the residual site correspondence for a source Program operation site.
                pub fn residualForSourceSite(comptime SourceSite: type) ?ResidualSourceMapEntry {
                    inline for (SourceMapStorage.map_entries) |entry| {
                        if (entry.source_site_fingerprint == SourceSite.fingerprint) return entry;
                    }
                    return null;
                }

                /// Find the source site correspondence for a residual Program operation site.
                pub fn sourceForResidualSite(comptime ResidualSite: type) ?ResidualSourceMapEntry {
                    inline for (SourceMapStorage.map_entries) |entry| {
                        if (entry.residual_site_fingerprint != null and entry.residual_site_fingerprint.? == ResidualSite.fingerprint) return entry;
                    }
                    return null;
                }

                /// Map a residual dynamic operation trace back to source-site metadata.
                pub fn mapResidualTrace(trace: anytype) ?ResidualSourceMapEntry {
                    inline for (SourceMapStorage.map_entries) |entry| {
                        if (entry.residual_site_fingerprint != null and
                            @hasField(@TypeOf(trace), "operation_site_fingerprint") and
                            entry.residual_site_fingerprint.? == trace.operation_site_fingerprint)
                        {
                            return entry;
                        }
                    }
                    return null;
                }
            };
        }

        fn IdentityPipelinePlanStorage(comptime residual_label: []const u8) type {
            return struct {
                const plan = plan_types.program_plan_builder.finish(.{
                    .schema_version = body_compiled_plan.schema_version,
                    .label = residual_label,
                    .ir_hash = residualizationFingerprint(.{ .label = residual_label, .morphisms = .{} }),
                    .entry = plan_types.program_plan_builder.function(@intCast(body_compiled_plan.entry_index)),
                    .functions = body_compiled_plan.functions,
                    .requirements = body_compiled_plan.requirements,
                    .ops = body_compiled_plan.ops,
                    .outputs = body_compiled_plan.outputs,
                    .value_schemas = body_compiled_plan.value_schemas,
                    .value_fields = body_compiled_plan.value_fields,
                    .value_variants = body_compiled_plan.value_variants,
                    .locals = body_compiled_plan.locals,
                    .call_args = body_compiled_plan.call_args,
                    .blocks = body_compiled_plan.blocks,
                    .terminators = body_compiled_plan.terminators,
                    .instructions = body_compiled_plan.instructions,
                }) catch |err| @compileError("Program.Pipeline identity plan relabel failed: " ++ @errorName(err));
            };
        }

        fn IdentityPipelineBodyFor(comptime residual_label: []const u8) type {
            const Storage = IdentityPipelinePlanStorage(residual_label);
            const BodyOutputs = ProgramOutputs;
            if (comptime hasDeclSafe(Body, "encodeArgs") and hasDeclSafe(Body, "deinitResult")) {
                return struct {
                    const compiled_plan = Storage.plan;
                    const value_schema_types = body_value_schema_types;
                    const nested_with_targets = body_nested_with_targets;
                    const site_metadata = body_site_metadata;
                    const Error = BodyErrorSet(Body);
                    const Outputs = BodyOutputs;
                    const deinitResult = Body.deinitResult;

                    fn collectOutputs(allocator: std.mem.Allocator, handlers: anytype) !BodyOutputs {
                        return try collectBodyOutputs(Body, BodyOutputs, allocator, handlers);
                    }

                    fn deinitOutputs(allocator: std.mem.Allocator, outputs: BodyOutputs) void {
                        if (comptime hasDeclSafe(Body, "deinitOutputs")) Body.deinitOutputs(allocator, outputs);
                    }

                    fn encodeArgs(handlers: HandlersType) @TypeOf(Body.encodeArgs(handlers)) {
                        return Body.encodeArgs(handlers);
                    }
                };
            }
            if (comptime hasDeclSafe(Body, "encodeArgs")) {
                return struct {
                    const compiled_plan = Storage.plan;
                    const value_schema_types = body_value_schema_types;
                    const nested_with_targets = body_nested_with_targets;
                    const site_metadata = body_site_metadata;
                    const Error = BodyErrorSet(Body);
                    const Outputs = BodyOutputs;

                    fn collectOutputs(allocator: std.mem.Allocator, handlers: anytype) !BodyOutputs {
                        return try collectBodyOutputs(Body, BodyOutputs, allocator, handlers);
                    }

                    fn deinitOutputs(allocator: std.mem.Allocator, outputs: BodyOutputs) void {
                        if (comptime hasDeclSafe(Body, "deinitOutputs")) Body.deinitOutputs(allocator, outputs);
                    }

                    fn encodeArgs(handlers: HandlersType) @TypeOf(Body.encodeArgs(handlers)) {
                        return Body.encodeArgs(handlers);
                    }
                };
            }
            if (comptime hasDeclSafe(Body, "deinitResult")) {
                return struct {
                    const compiled_plan = Storage.plan;
                    const value_schema_types = body_value_schema_types;
                    const nested_with_targets = body_nested_with_targets;
                    const site_metadata = body_site_metadata;
                    const Error = BodyErrorSet(Body);
                    const Outputs = BodyOutputs;
                    const deinitResult = Body.deinitResult;

                    fn collectOutputs(allocator: std.mem.Allocator, handlers: anytype) !BodyOutputs {
                        return try collectBodyOutputs(Body, BodyOutputs, allocator, handlers);
                    }

                    fn deinitOutputs(allocator: std.mem.Allocator, outputs: BodyOutputs) void {
                        if (comptime hasDeclSafe(Body, "deinitOutputs")) Body.deinitOutputs(allocator, outputs);
                    }
                };
            }
            return struct {
                const compiled_plan = Storage.plan;
                const value_schema_types = body_value_schema_types;
                const nested_with_targets = body_nested_with_targets;
                const site_metadata = body_site_metadata;
                const Error = BodyErrorSet(Body);
                const Outputs = BodyOutputs;

                fn collectOutputs(allocator: std.mem.Allocator, handlers: anytype) !BodyOutputs {
                    return try collectBodyOutputs(Body, BodyOutputs, allocator, handlers);
                }

                fn deinitOutputs(allocator: std.mem.Allocator, outputs: BodyOutputs) void {
                    if (comptime hasDeclSafe(Body, "deinitOutputs")) Body.deinitOutputs(allocator, outputs);
                }
            };
        }

        fn IdentityResidualProgram(comptime residual_label: []const u8) type {
            const IdentityBody = IdentityPipelineBodyFor(residual_label);
            const Base = program(residual_label, HandlersType, IdentityBody);
            const source_map_entries = [_]ResidualSourceMapEntry{};
            const residual_effect_row = ResidualEffectRow{
                .source_program_label = label,
                .source_plan_hash = body_compiled_plan_hash,
                .residual_program_label = Base.contract.label,
                .residual_plan_hash = Base.compiled_plan.hash(),
                .eliminated_source_sites = 0,
                .reinterpreted_source_sites = 0,
                .emitted_target_protocol_ops = 0,
                .residual_operation_sites = protocol.operation_site_count,
                .unsupported_source_sites = 0,
                .unsupported_morphisms = 0,
            };
            return struct {
                /// Original ProgramPlan used unchanged by an identity pipeline.
                pub const compiled_plan = Base.compiled_plan;
                /// Contract projection for the unchanged Program.
                pub const contract = Base.contract;
                /// Typed protocol descriptors for the unchanged Program.
                pub const protocol = Base.protocol;
                /// Error set for executing the unchanged Program.
                pub const Error = Base.Error;
                /// Result type for executing the unchanged Program.
                pub const Result = Base.Result;
                /// Primitive host-driven Session type for the unchanged Program.
                pub const Session = Base.Session;
                /// Handler constructor namespace for the unchanged Program.
                pub const Handler = Base.Handler;
                /// Interpreter constructor namespace for the unchanged Program.
                pub const Interpreter = Base.Interpreter;
                /// Protocol request type for reinterpretation paths.
                pub const ProtocolRequest = Base.ProtocolRequest;
                /// Dynamic morphism constructor namespace for the unchanged Program.
                pub const Morphism = Base.Morphism;
                /// Declarative morphism constructor namespace for future residualization.
                pub const ResidualMorphism = Base.ResidualMorphism;
                /// Residualization fingerprint metadata version.
                pub const residual_fingerprint_version = Base.residual_fingerprint_version;
                /// Reinterpretation fingerprint metadata version.
                pub const reinterpret_fingerprint_version = Base.reinterpret_fingerprint_version;
                /// Run the unchanged Program through ordinary handler dispatch.
                pub const run = Base.run;
                /// Stable fingerprint for the identity residualization configuration.
                pub const residualization_fingerprint = residualizationFingerprint(.{ .label = residual_label, .morphisms = .{} });
                /// Identity pipelines have no source-to-residual rewrite entries.
                pub const source_map = &source_map_entries;
                /// Residual effect-row metadata.
                pub const effect_row = residual_effect_row;
                /// Alias for residual effect-row metadata.
                pub const residual_row = residual_effect_row;
                /// Unsupported blockers for this identity residual Program.
                pub const unsupported = &[_]ResidualBlocker{};

                /// Identity pipelines do not rewrite source sites.
                pub fn residualForSourceSite(comptime SourceSite: type) ?ResidualSourceMapEntry {
                    _ = SourceSite;
                    return null;
                }

                /// Identity pipelines do not rewrite residual sites.
                pub fn sourceForResidualSite(comptime ResidualSite: type) ?ResidualSourceMapEntry {
                    _ = ResidualSite;
                    return null;
                }

                /// Identity pipelines rely on the pipeline-level owner-aware fallback.
                pub fn mapResidualTrace(trace: anytype) ?ResidualSourceMapEntry {
                    _ = trace;
                    return null;
                }
            };
        }

        /// Goal and strategy vocabulary for proof-carrying effect pipelines.
        pub const pipeline = struct {
            /// Planner route preference. The current pipeline compiler supports residualization only.
            pub const Strategy = enum {
                prefer_residualization,
            };

            /// Static residual-effect goal checked by the pipeline planner.
            pub const GoalKind = enum {
                allow_residuals,
                eliminate_all,
                reject_all_residuals,
            };

            /// Inspectable pipeline goal descriptor.
            pub const Goal = struct {
                kind: GoalKind,
                allow_unhandled_residuals: bool = true,

                /// Allow residual effects to remain exposed to Program.Session.
                pub fn allowResiduals() @This() {
                    return .{ .kind = .allow_residuals, .allow_unhandled_residuals = true };
                }

                /// Require every reachable operation, after site, and emitted protocol op to be eliminated.
                pub fn eliminateAll() @This() {
                    return .{ .kind = .eliminate_all, .allow_unhandled_residuals = false };
                }

                /// Reject exposed residual effects after residualization routes are applied.
                pub fn rejectAllResiduals() @This() {
                    return .{ .kind = .reject_all_residuals, .allow_unhandled_residuals = false };
                }
            };

            /// Default trace policy keeps existing request/response fingerprints unchanged.
            pub const TracePolicy = enum {
                inspectable,
            };
        };

        /// Structured reason a pipeline cannot satisfy its goal or route catalog.
        pub const PipelineBlockerTag = enum {
            missing_handler,
            missing_protocol_handler,
            duplicate_handler,
            ambiguous_route,
            morphism_cycle,
            unsupported_residualization_shape,
            schema_mismatch,
            source_site_unreachable,
            foreign_program_site,
            goal_not_satisfied,
            residual_effect_not_allowed,
            after_site_unsupported,
            output_requirement_unsupported,
        };

        /// One fail-closed pipeline-planning blocker.
        pub const PipelineBlocker = struct {
            tag: PipelineBlockerTag,
            source_site_index: ?usize = null,
            source_site_fingerprint: ?u64 = null,
            target_protocol_op_fingerprint: ?u64 = null,
            morphism_fingerprint: ?u64 = null,
            summary: []const u8 = "",
        };

        /// Route category selected or reported by the pipeline planner.
        pub const PipelineRouteKind = enum {
            source_site_handled,
            source_site_reinterpreted_dynamic,
            source_site_residualized,
            protocol_op_handled,
            after_site_handled,
        };

        /// Static route witness used by certificates and reports.
        pub const PipelineRouteWitness = struct {
            kind: PipelineRouteKind,
            source_site_index: ?usize = null,
            source_site_fingerprint: ?u64 = null,
            after_site_index: ?usize = null,
            after_site_fingerprint: ?u64 = null,
            target_protocol_label: ?[]const u8 = null,
            target_op_name: ?[]const u8 = null,
            target_protocol_op_fingerprint: ?u64 = null,
            morphism_fingerprint: ?u64 = null,
            label: ?[]const u8 = null,
        };

        /// Static effect-row projection for a synthesized effect pipeline.
        pub const PipelineEffectRow = struct {
            source_program_label: []const u8,
            source_plan_hash: u64,
            residual_program_label: []const u8,
            residual_plan_hash: u64 = 0,
            source_operation_sites: usize,
            source_after_sites: usize,
            residualized_sites: usize,
            dynamically_interpreted_sites: usize,
            dynamically_reinterpreted_sites: usize,
            handled_protocol_operations: usize,
            emitted_protocol_operations: usize,
            exposed_residual_operations: usize,
            handled_after_sites: usize,
            residual_after_sites: usize,
            blockers: usize,
            fingerprint_version: u32 = pipeline_fingerprint_version,
        };

        /// Proof-carrying certificate for one planned pipeline.
        pub const PipelineCertificate = struct {
            source_program_label: []const u8,
            source_plan_label: []const u8,
            source_plan_hash: u64,
            residual_program_label: []const u8,
            residual_plan_hash: u64,
            pipeline_label: []const u8,
            pipeline_fingerprint_version: u32 = pipeline_fingerprint_version,
            pipeline_fingerprint: u64,
            residualization_fingerprint: u64,
            dynamic_catalog_fingerprint: u64,
            source_effect_row: PipelineEffectRow,
            target_effect_row: PipelineEffectRow,
            handled_sites: []const PipelineRouteWitness,
            dynamically_interpreted_sites: []const PipelineRouteWitness,
            residualized_sites: []const PipelineRouteWitness,
            reinterpreted_sites: []const PipelineRouteWitness,
            emitted_protocol_operations: []const PipelineRouteWitness,
            exposed_residual_operations: usize,
            blockers: []const PipelineBlocker,
            source_to_residual_site_map: []const ResidualSourceMapEntry,
            residual_to_source_site_map: []const ResidualSourceMapEntry,
            trace_mapping_policy: pipeline.TracePolicy = .inspectable,
            goal_satisfied: bool,

            /// Verify certificate self-consistency and goal satisfaction.
            pub fn check(self: @This()) error{ InvalidPipelineCertificate, PipelineGoalNotSatisfied }!void {
                if (self.source_program_label.len == 0 or self.pipeline_label.len == 0) return error.InvalidPipelineCertificate;
                if (self.pipeline_fingerprint_version != pipeline_fingerprint_version) return error.InvalidPipelineCertificate;
                if (!self.goal_satisfied or self.blockers.len != 0) return error.PipelineGoalNotSatisfied;
                if (self.source_plan_hash == 0 or self.residual_plan_hash == 0) return error.InvalidPipelineCertificate;
                if (self.source_effect_row.source_plan_hash != self.source_plan_hash or
                    self.source_effect_row.residual_plan_hash != self.residual_plan_hash or
                    self.target_effect_row.source_plan_hash != self.source_plan_hash or
                    self.target_effect_row.residual_plan_hash != self.residual_plan_hash)
                {
                    return error.InvalidPipelineCertificate;
                }
                if (!std.mem.eql(u8, self.source_effect_row.source_program_label, self.source_program_label) or
                    !std.mem.eql(u8, self.source_effect_row.residual_program_label, self.residual_program_label) or
                    !std.mem.eql(u8, self.target_effect_row.source_program_label, self.source_program_label) or
                    !std.mem.eql(u8, self.target_effect_row.residual_program_label, self.residual_program_label))
                {
                    return error.InvalidPipelineCertificate;
                }
                for (self.source_to_residual_site_map, 0..) |entry, index| {
                    if (entry.source_site_fingerprint == 0) return error.InvalidPipelineCertificate;
                    var duplicate = false;
                    for (self.source_to_residual_site_map, 0..) |other, other_index| {
                        if (other_index < index and other.source_site_fingerprint == entry.source_site_fingerprint) duplicate = true;
                    }
                    if (duplicate) return error.InvalidPipelineCertificate;
                }
            }
        };

        fn pipelineLabel(comptime config: anytype) []const u8 {
            if (comptime @hasField(@TypeOf(config), "label")) return config.label;
            return label ++ ".pipeline";
        }

        fn pipelineResidualLabel(comptime config: anytype) []const u8 {
            if (comptime @hasField(@TypeOf(config), "residual_label")) return config.residual_label;
            if (comptime @hasField(@TypeOf(config), "label")) return config.label ++ ".residual";
            return label ++ ".pipeline.residual";
        }

        fn pipelineStrategy(comptime config: anytype) pipeline.Strategy {
            if (comptime @hasField(@TypeOf(config), "strategy")) return config.strategy;
            return .prefer_residualization;
        }

        fn pipelineGoal(comptime config: anytype) pipeline.Goal {
            if (comptime @hasField(@TypeOf(config), "goal")) return config.goal;
            return pipeline.Goal.allowResiduals();
        }

        fn pipelineResidualCatalog(comptime config: anytype) @TypeOf(if (@hasField(@TypeOf(config), "residualize")) config.residualize else .{}) {
            return if (comptime @hasField(@TypeOf(config), "residualize")) config.residualize else .{};
        }

        fn pipelineInterpretCatalog(comptime config: anytype) @TypeOf(if (@hasField(@TypeOf(config), "interpret")) config.interpret else .{}) {
            return if (comptime @hasField(@TypeOf(config), "interpret")) config.interpret else .{};
        }

        fn pipelineResidualConfig(comptime config: anytype) @TypeOf(.{
            .label = pipelineResidualLabel(config),
            .morphisms = pipelineResidualCatalog(config),
        }) {
            return .{
                .label = pipelineResidualLabel(config),
                .morphisms = pipelineResidualCatalog(config),
            };
        }

        fn pipelineBlockerTagForResidual(comptime tag_value: ResidualBlockerTag) PipelineBlockerTag {
            return switch (tag_value) {
                .unsupported_source_mode, .unsupported_payload_mapping, .unsupported_response_mapping, .unsupported_target_mode => .unsupported_residualization_shape,
                .source_site_unreachable => .source_site_unreachable,
                .source_site_foreign_program => .foreign_program_site,
                .target_schema_mismatch => .schema_mismatch,
                .duplicate_source_site, .shared_source_operation => .ambiguous_route,
                .after_residualization_unsupported => .after_site_unsupported,
                .nested_with_residualization_unsupported => .unsupported_residualization_shape,
                .output_residualization_unsupported => .output_requirement_unsupported,
            };
        }

        fn pipelineCatalogFingerprint(comptime config: anytype) u64 {
            @setEvalBranchQuota(10000);
            const residual_catalog = pipelineResidualCatalog(config);
            const interpret_catalog = pipelineInterpretCatalog(config);
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "ability.program.pipeline.catalog");
            hashU32(&hasher, pipeline_fingerprint_version);
            inline for (residual_catalog) |Descriptor| hashU64(&hasher, Descriptor.fingerprint);
            hashUsize(&hasher, interpret_catalog.len);
            inline for (interpret_catalog) |Entry| hashPipelineInterpretEntry(&hasher, Entry);
            return hasher.final();
        }

        fn hashPipelineInterpretEntry(hasher: *std.hash.Wyhash, comptime Entry: type) void {
            hashBytes(hasher, @typeName(Entry));
            hashBytes(hasher, @tagName(Entry.kind));
            switch (Entry.kind) {
                .operation => {
                    hashU64(hasher, Entry.Site.fingerprint);
                    if (comptime hasDeclSafe(Entry, "Morphism")) hashU64(hasher, Entry.Morphism.fingerprint);
                },
                .after => hashU64(hasher, Entry.Site.fingerprint),
                .protocol_operation => hashU64(hasher, Entry.TargetOp.fingerprint),
                else => {},
            }
        }

        fn pipelineFingerprint(comptime config: anytype) u64 {
            @setEvalBranchQuota(10000);
            var hasher = std.hash.Wyhash.init(0);
            hashBytes(&hasher, "ability.program.pipeline");
            hashU32(&hasher, pipeline_fingerprint_version);
            hashU64(&hasher, body_compiled_plan_hash);
            hashBytes(&hasher, pipelineLabel(config));
            hashBytes(&hasher, pipelineResidualLabel(config));
            hashBytes(&hasher, @tagName(pipelineStrategy(config)));
            const goal_value = pipelineGoal(config);
            hashBytes(&hasher, @tagName(goal_value.kind));
            hashBool(&hasher, goal_value.allow_unhandled_residuals);
            hashU64(&hasher, pipelineCatalogFingerprint(config));
            return hasher.final();
        }

        fn pipelineResidualDescriptorSupported(comptime Report: type, comptime Descriptor: type) bool {
            if (Report.effect_row.eliminated_source_sites == 0) return false;
            inline for (Report.unsupported) |blocker| {
                if (blocker.source_site_fingerprint != null and blocker.source_site_fingerprint.? == Descriptor.source.fingerprint) {
                    return false;
                }
            }
            return true;
        }

        fn pipelineSupportedSourceResidualized(comptime Report: type, comptime residual_catalog: anytype, comptime source_site_fingerprint: u64) bool {
            inline for (residual_catalog) |Descriptor| {
                if (Descriptor.source.fingerprint == source_site_fingerprint and pipelineResidualDescriptorSupported(Report, Descriptor)) return true;
            }
            return false;
        }

        fn pipelineUnsupportedInterpretCatalogCount(comptime config: anytype) usize {
            if (comptime !@hasField(@TypeOf(config), "interpret")) return 0;
            return if (config.interpret.len == 0) 0 else 1;
        }

        fn pipelineResidualizationReport(comptime config: anytype) type {
            const residual_catalog = pipelineResidualCatalog(config);
            if (residual_catalog.len != 0) return residualizationReport(pipelineResidualConfig(config));
            const IdentityStorage = IdentityPipelinePlanStorage(pipelineResidualLabel(config));
            const source_map_entries = [_]ResidualSourceMapEntry{};
            const residual_effect_row = ResidualEffectRow{
                .source_program_label = label,
                .source_plan_hash = body_compiled_plan_hash,
                .residual_program_label = pipelineResidualLabel(config),
                .residual_plan_hash = IdentityStorage.plan.hash(),
                .eliminated_source_sites = 0,
                .reinterpreted_source_sites = 0,
                .emitted_target_protocol_ops = 0,
                .residual_operation_sites = protocol.operation_site_count,
                .unsupported_source_sites = 0,
                .unsupported_morphisms = 0,
            };
            return struct {
                /// Residualization fingerprint domain version.
                pub const fingerprint_version = residual_fingerprint_version;
                /// Source Program label.
                pub const source_program_label = label;
                /// Source ProgramPlan hash.
                pub const source_plan_hash = body_compiled_plan_hash;
                /// Identity pipelines do not inherit residualization global blockers.
                pub const unsupported = &[_]ResidualBlocker{};
                /// Identity pipelines do not rewrite source sites.
                pub const source_map = &source_map_entries;
                /// Static handled/residual effect-row summary.
                pub const effect_row = residual_effect_row;
                /// Empty residual catalogs are valid pipeline identity plans.
                pub const supported = true;
            };
        }

        fn PipelinePlanStorage(comptime config: anytype) type {
            const residual_catalog = pipelineResidualCatalog(config);
            const Report = pipelineResidualizationReport(config);
            const goal_value = pipelineGoal(config);
            const supported_residual_sites = Report.effect_row.eliminated_source_sites;
            const emitted_protocol_ops = Report.effect_row.emitted_target_protocol_ops;

            const residual_blocker_count: usize = Report.unsupported.len;
            const interpret_blocker_count: usize = pipelineUnsupportedInterpretCatalogCount(config);

            comptime var goal_blocker_count: usize = 0;
            if (!goal_value.allow_unhandled_residuals) {
                inline for (protocol.operation_site_metadata) |site| {
                    if (!pipelineSupportedSourceResidualized(Report, residual_catalog, site.fingerprint)) {
                        goal_blocker_count += 1;
                    }
                }
                inline for (protocol.after_site_metadata) |site| {
                    _ = site;
                    goal_blocker_count += 1;
                }
                goal_blocker_count += supported_residual_sites;
            }

            const blocker_count = residual_blocker_count + interpret_blocker_count + goal_blocker_count;
            var blocker_table: [blocker_count]PipelineBlocker = undefined;
            var route_table: [supported_residual_sites]PipelineRouteWitness = undefined;
            comptime var blocker_index: usize = 0;
            comptime var route_index: usize = 0;

            inline for (Report.unsupported) |blocker| {
                blocker_table[blocker_index] = .{
                    .tag = pipelineBlockerTagForResidual(blocker.tag),
                    .source_site_index = blocker.source_site_index,
                    .source_site_fingerprint = blocker.source_site_fingerprint,
                    .target_protocol_op_fingerprint = blocker.target_protocol_op_fingerprint,
                    .summary = blocker.message,
                };
                blocker_index += 1;
            }

            inline for (residual_catalog) |Descriptor| {
                if (pipelineResidualDescriptorSupported(Report, Descriptor)) {
                    route_table[route_index] = .{
                        .kind = .source_site_residualized,
                        .source_site_index = Descriptor.source.index,
                        .source_site_fingerprint = Descriptor.source.fingerprint,
                        .target_protocol_label = Descriptor.target.protocol_label,
                        .target_op_name = Descriptor.target.op_name,
                        .target_protocol_op_fingerprint = Descriptor.target.fingerprint,
                        .morphism_fingerprint = Descriptor.fingerprint,
                        .label = Descriptor.mapping_label,
                    };
                    route_index += 1;
                }
            }

            if (interpret_blocker_count != 0) {
                blocker_table[blocker_index] = .{
                    .tag = .goal_not_satisfied,
                    .summary = "pipeline interpret catalog entries are not executable by Program.Pipeline; pass residual handlers to Pipeline.Interpreter",
                };
                blocker_index += 1;
            }

            if (!goal_value.allow_unhandled_residuals) {
                inline for (protocol.operation_site_metadata) |site| {
                    if (!pipelineSupportedSourceResidualized(Report, residual_catalog, site.fingerprint)) {
                        blocker_table[blocker_index] = .{
                            .tag = .missing_handler,
                            .source_site_index = site.index,
                            .source_site_fingerprint = site.fingerprint,
                            .summary = "pipeline goal requires every source operation site to be residualized",
                        };
                        blocker_index += 1;
                    }
                }
                inline for (protocol.after_site_metadata) |site| {
                    blocker_table[blocker_index] = .{
                        .tag = .after_site_unsupported,
                        .source_site_index = site.source_operation_site_index,
                        .source_site_fingerprint = site.source_operation_site_fingerprint,
                        .summary = "pipeline goal requires after sites to be residualized",
                    };
                    blocker_index += 1;
                }
                inline for (residual_catalog) |Descriptor| {
                    if (pipelineResidualDescriptorSupported(Report, Descriptor)) {
                        blocker_table[blocker_index] = .{
                            .tag = .missing_protocol_handler,
                            .source_site_index = Descriptor.source.index,
                            .source_site_fingerprint = Descriptor.source.fingerprint,
                            .target_protocol_op_fingerprint = Descriptor.target.fingerprint,
                            .morphism_fingerprint = Descriptor.fingerprint,
                            .summary = "pipeline goal requires emitted protocol operations to be residualized or carried by execution",
                        };
                        blocker_index += 1;
                    }
                }
            }

            const final_blockers = blocker_table;
            const final_routes = route_table;
            return struct {
                /// Residualization report used by the pipeline planner.
                pub const residual_report = Report;
                /// Structured blockers accumulated while planning.
                pub const blockers = final_blockers;
                /// Static route witnesses selected or reported by the planner.
                pub const routes = final_routes;
                /// Whether the configured goal is satisfied by this report.
                pub const goal_satisfied = final_blockers.len == 0;
                /// Source-side effect-row summary before a residual Program is compiled.
                pub const source_effect_row = PipelineEffectRow{
                    .source_program_label = label,
                    .source_plan_hash = body_compiled_plan_hash,
                    .residual_program_label = pipelineResidualLabel(config),
                    .residual_plan_hash = Report.effect_row.residual_plan_hash,
                    .source_operation_sites = protocol.operation_site_count,
                    .source_after_sites = protocol.after_site_count,
                    .residualized_sites = supported_residual_sites,
                    .dynamically_interpreted_sites = 0,
                    .dynamically_reinterpreted_sites = 0,
                    .handled_protocol_operations = 0,
                    .emitted_protocol_operations = emitted_protocol_ops,
                    .exposed_residual_operations = protocol.operation_site_count - supported_residual_sites,
                    .handled_after_sites = 0,
                    .residual_after_sites = protocol.after_site_count,
                    .blockers = final_blockers.len,
                };
            };
        }

        /// Inspect a pipeline catalog and goal without compiling a residual Program.
        pub fn pipelineReport(comptime config: anytype) type {
            const Storage = PipelinePlanStorage(config);
            return struct {
                /// Pipeline label.
                pub const pipeline_label = pipelineLabel(config);
                /// Pipeline fingerprint domain version.
                pub const fingerprint_version = pipeline_fingerprint_version;
                /// Stable fingerprint for this pipeline catalog, goal, and strategy.
                pub const fingerprint = pipelineFingerprint(config);
                /// Route-selection strategy requested by the caller.
                pub const strategy = pipelineStrategy(config);
                /// Static residual-effect goal requested by the caller.
                pub const goal = pipelineGoal(config);
                /// Structured pipeline blockers.
                pub const blockers = &Storage.blockers;
                /// Planned route witnesses.
                pub const routes = &Storage.routes;
                /// Underlying residualization report for declarative morphisms.
                pub const residualization = Storage.residual_report;
                /// Source-side effect-row metadata.
                pub const effect_row = Storage.source_effect_row;
                /// Whether the pipeline report satisfies its goal without blockers.
                pub const supported = Storage.goal_satisfied;
            };
        }

        fn pipelineRoutesWithKind(comptime routes: []const PipelineRouteWitness, comptime route_kind: PipelineRouteKind) type {
            comptime var count: usize = 0;
            inline for (routes) |route| {
                if (route.kind == route_kind) count += 1;
            }
            var table: [count]PipelineRouteWitness = undefined;
            comptime var index: usize = 0;
            inline for (routes) |route| {
                if (route.kind == route_kind) {
                    table[index] = route;
                    index += 1;
                }
            }
            const final_table = table;
            return struct {
                /// Route witnesses with the requested kind.
                pub const values = final_table;
            };
        }

        /// Synthesize a proof-carrying residual Program plus dynamic interpreter adapters.
        pub fn Pipeline(comptime config: anytype) type {
            const Report = pipelineReport(config);
            if (!Report.supported) {
                const first = Report.blockers[0];
                @compileError("Program.Pipeline blocked: " ++ @tagName(first.tag) ++ " " ++ first.summary);
            }
            const residual_config = pipelineResidualConfig(config);
            const ResidualProgram = if (pipelineResidualCatalog(config).len == 0)
                IdentityResidualProgram(pipelineResidualLabel(config))
            else
                residualize(residual_config);
            const ResidualizedRoutes = pipelineRoutesWithKind(Report.routes, .source_site_residualized);
            const HandledRoutes = pipelineRoutesWithKind(Report.routes, .source_site_handled);
            const DynamicRoutes = pipelineRoutesWithKind(Report.routes, .source_site_reinterpreted_dynamic);
            const residual_effect_row = PipelineEffectRow{
                .source_program_label = label,
                .source_plan_hash = body_compiled_plan_hash,
                .residual_program_label = ResidualProgram.contract.label,
                .residual_plan_hash = ResidualProgram.compiled_plan.hash(),
                .source_operation_sites = protocol.operation_site_count,
                .source_after_sites = protocol.after_site_count,
                .residualized_sites = ResidualizedRoutes.values.len,
                .dynamically_interpreted_sites = HandledRoutes.values.len + DynamicRoutes.values.len,
                .dynamically_reinterpreted_sites = DynamicRoutes.values.len,
                .handled_protocol_operations = 0,
                .emitted_protocol_operations = ResidualizedRoutes.values.len,
                .exposed_residual_operations = ResidualProgram.effect_row.residual_operation_sites,
                .handled_after_sites = 0,
                .residual_after_sites = ResidualProgram.protocol.after_site_count,
                .blockers = 0,
            };
            const source_effect_row = PipelineEffectRow{
                .source_program_label = Report.effect_row.source_program_label,
                .source_plan_hash = Report.effect_row.source_plan_hash,
                .residual_program_label = ResidualProgram.contract.label,
                .residual_plan_hash = ResidualProgram.compiled_plan.hash(),
                .source_operation_sites = Report.effect_row.source_operation_sites,
                .source_after_sites = Report.effect_row.source_after_sites,
                .residualized_sites = Report.effect_row.residualized_sites,
                .dynamically_interpreted_sites = Report.effect_row.dynamically_interpreted_sites,
                .dynamically_reinterpreted_sites = Report.effect_row.dynamically_reinterpreted_sites,
                .handled_protocol_operations = Report.effect_row.handled_protocol_operations,
                .emitted_protocol_operations = Report.effect_row.emitted_protocol_operations,
                .exposed_residual_operations = Report.effect_row.exposed_residual_operations,
                .handled_after_sites = Report.effect_row.handled_after_sites,
                .residual_after_sites = Report.effect_row.residual_after_sites,
                .blockers = Report.effect_row.blockers,
            };
            const certificate_value = PipelineCertificate{
                .source_program_label = label,
                .source_plan_label = body_compiled_plan.label,
                .source_plan_hash = body_compiled_plan_hash,
                .residual_program_label = ResidualProgram.contract.label,
                .residual_plan_hash = ResidualProgram.compiled_plan.hash(),
                .pipeline_label = Report.pipeline_label,
                .pipeline_fingerprint = Report.fingerprint,
                .residualization_fingerprint = ResidualProgram.residualization_fingerprint,
                .dynamic_catalog_fingerprint = pipelineCatalogFingerprint(config),
                .source_effect_row = source_effect_row,
                .target_effect_row = residual_effect_row,
                .handled_sites = &HandledRoutes.values,
                .dynamically_interpreted_sites = &DynamicRoutes.values,
                .residualized_sites = &ResidualizedRoutes.values,
                .reinterpreted_sites = &DynamicRoutes.values,
                .emitted_protocol_operations = &ResidualizedRoutes.values,
                .exposed_residual_operations = residual_effect_row.exposed_residual_operations,
                .blockers = Report.blockers,
                .source_to_residual_site_map = ResidualProgram.source_map,
                .residual_to_source_site_map = ResidualProgram.source_map,
                .goal_satisfied = true,
            };
            return struct {
                /// Pipeline label.
                pub const pipeline_label = Report.pipeline_label;
                /// Pipeline fingerprint domain version.
                pub const fingerprint_version = pipeline_fingerprint_version;
                /// Stable fingerprint for the synthesized pipeline.
                pub const fingerprint = Report.fingerprint;
                /// Route-selection strategy used by this pipeline.
                pub const strategy = Report.strategy;
                /// Static residual-effect goal used by this pipeline.
                pub const goal = Report.goal;
                /// Report-only planner output for this pipeline.
                pub const report = Report;
                /// Static route witnesses for this pipeline.
                pub const plan = Report.routes;
                /// Residual-side effect-row metadata.
                pub const effect_row = residual_effect_row;
                /// Alias for the residual Program effect row.
                pub const residual_row = ResidualProgram.residual_row;
                /// Structured blockers. Successful pipelines have none.
                pub const blockers = Report.blockers;
                /// Proof-carrying certificate for this pipeline.
                pub const certificate = certificate_value;
                /// Residual Program produced by the pipeline.
                pub const Residual = ResidualProgram;
                /// Alias for the residual Program produced by the pipeline.
                pub const residual_program = ResidualProgram;

                /// Build a dynamic interpreter for the residual Program.
                pub fn Interpreter(comptime entries: anytype) type {
                    return ResidualProgram.Interpreter(entries);
                }

                /// Alias for callers that want to name the dynamic handler stack explicitly.
                pub fn dynamic_interpreter(comptime entries: anytype) type {
                    return ResidualProgram.Interpreter(entries);
                }

                /// Run the residual Program directly.
                pub const run = ResidualProgram.run;

                /// Start the residual Program's primitive host-driven session.
                pub const start = ResidualProgram.Session.start;

                /// Compile-time assert for callers that demand a fully valid certificate.
                pub fn assertValid() void {
                    comptime {
                        if (certificate.blockers.len != 0 or !certificate.goal_satisfied) {
                            @compileError("Program.Pipeline certificate check failed");
                        }
                    }
                }

                /// Find the residual site corresponding to a source operation site.
                pub fn residualForSourceSite(comptime SourceSite: type) ?ResidualSourceMapEntry {
                    return ResidualProgram.residualForSourceSite(SourceSite);
                }

                /// Find the source site corresponding to a residual operation site.
                pub fn sourceForResidualSite(comptime ResidualSite: type) ?ResidualSourceMapEntry {
                    return ResidualProgram.sourceForResidualSite(ResidualSite);
                }

                /// Map a residual trace back to the source site selected by this pipeline.
                pub fn mapResidualTrace(trace: anytype) ?ResidualSourceMapEntry {
                    if (ResidualProgram.mapResidualTrace(trace)) |entry| return entry;
                    return identityResidualTraceMap(trace);
                }

                /// Alias for residual trace mapping.
                pub fn sourceForResidualTrace(trace: anytype) ?ResidualSourceMapEntry {
                    return mapResidualTrace(trace);
                }

                /// Map a target protocol request emitted by a dynamic stage back to a source site.
                pub fn sourceForTargetProtocolRequest(request: anytype) ?PipelineRouteWitness {
                    if (@hasField(@TypeOf(request), "source_trace")) {
                        if (mapResidualTrace(request.source_trace)) |entry| {
                            inline for (Report.routes) |route| {
                                if (routeMatchesTargetFingerprint(route, request) and
                                    route.source_site_fingerprint != null and
                                    route.source_site_fingerprint.? == entry.source_site_fingerprint)
                                {
                                    return route;
                                }
                            }
                            return .{
                                .kind = .source_site_reinterpreted_dynamic,
                                .source_site_index = entry.source_site_index,
                                .source_site_fingerprint = entry.source_site_fingerprint,
                                .target_protocol_label = if (@hasField(@TypeOf(request), "target_protocol_label")) request.target_protocol_label else null,
                                .target_op_name = if (@hasField(@TypeOf(request), "target_op_name")) request.target_op_name else null,
                                .target_protocol_op_fingerprint = if (@hasField(@TypeOf(request), "target_protocol_op_fingerprint")) request.target_protocol_op_fingerprint else null,
                            };
                        }
                        if (routeForSourceTrace(request.source_trace, request)) |route| return route;
                        return null;
                    }
                    if (@hasField(@TypeOf(request), "source_site_fingerprint")) {
                        inline for (Report.routes) |route| {
                            if (routeMatchesTargetFingerprint(route, request) and
                                routeMatchesRequestSource(route, request))
                            {
                                return route;
                            }
                        }
                        if (dynamicRouteForResidualOwnedValue(request)) |route| return route;
                        return null;
                    }
                    return singleRouteMatchingTargetFingerprint(request);
                }

                /// Map target request traces by the same deterministic protocol-operation fingerprint.
                pub fn mapTargetTrace(trace: anytype) ?PipelineRouteWitness {
                    if (@hasField(@TypeOf(trace), "source_trace")) {
                        if (mapResidualTrace(trace.source_trace)) |entry| {
                            inline for (Report.routes) |route| {
                                if (routeMatchesTargetFingerprint(route, trace) and
                                    route.source_site_fingerprint != null and
                                    route.source_site_fingerprint.? == entry.source_site_fingerprint)
                                {
                                    return route;
                                }
                            }
                            return .{
                                .kind = .source_site_reinterpreted_dynamic,
                                .source_site_index = entry.source_site_index,
                                .source_site_fingerprint = entry.source_site_fingerprint,
                                .target_protocol_label = if (@hasField(@TypeOf(trace), "target_protocol_label")) trace.target_protocol_label else null,
                                .target_op_name = if (@hasField(@TypeOf(trace), "target_op_name")) trace.target_op_name else null,
                                .target_protocol_op_fingerprint = if (@hasField(@TypeOf(trace), "target_protocol_op_fingerprint")) trace.target_protocol_op_fingerprint else null,
                            };
                        }
                        if (routeForSourceTrace(trace.source_trace, trace)) |route| return route;
                        return null;
                    }
                    if (@hasField(@TypeOf(trace), "source_site_fingerprint")) {
                        inline for (Report.routes) |route| {
                            if (routeMatchesTargetFingerprint(route, trace) and
                                routeMatchesRequestSource(route, trace))
                            {
                                return route;
                            }
                        }
                        if (dynamicRouteForResidualOwnedValue(trace)) |route| return route;
                        return null;
                    }
                    return singleRouteMatchingTargetFingerprint(trace);
                }

                fn routeMatchesTargetFingerprint(route: PipelineRouteWitness, value: anytype) bool {
                    return route.target_protocol_op_fingerprint != null and
                        @hasField(@TypeOf(value), "target_protocol_op_fingerprint") and
                        route.target_protocol_op_fingerprint.? == value.target_protocol_op_fingerprint;
                }

                fn routeForSourceTrace(trace: anytype, value: anytype) ?PipelineRouteWitness {
                    inline for (Report.routes) |route| {
                        if (routeMatchesTargetFingerprint(route, value) and route.source_site_fingerprint != null) {
                            inline for (protocol.operation_site_metadata) |site| {
                                if (site.fingerprint == route.source_site_fingerprint.? and traceMatchesProgramSite(trace, site, label, body_compiled_plan_hash)) return route;
                            }
                        }
                    }
                    return null;
                }

                fn singleRouteMatchingTargetFingerprint(value: anytype) ?PipelineRouteWitness {
                    var match_count: usize = 0;
                    var selected: ?PipelineRouteWitness = null;
                    inline for (Report.routes) |route| {
                        if (routeMatchesTargetFingerprint(route, value)) {
                            match_count += 1;
                            selected = route;
                        }
                    }
                    return if (match_count == 1) selected else null;
                }

                fn routeMatchesRequestSource(route: PipelineRouteWitness, value: anytype) bool {
                    if (route.source_site_fingerprint == null or !@hasField(@TypeOf(value), "source_site_fingerprint")) return false;
                    if (sourceIdentityMatchesProgram(value, label, body_compiled_plan_hash) and
                        route.source_site_fingerprint.? == value.source_site_fingerprint)
                    {
                        return true;
                    }
                    if (!sourceIdentityMatchesProgram(value, ResidualProgram.contract.label, ResidualProgram.compiled_plan.hash())) return false;
                    inline for (ResidualProgram.source_map) |entry| {
                        if (entry.residual_site_fingerprint != null and
                            entry.residual_site_fingerprint.? == value.source_site_fingerprint and
                            entry.source_site_fingerprint == route.source_site_fingerprint.?)
                        {
                            return true;
                        }
                    }
                    return false;
                }

                fn dynamicRouteForResidualOwnedValue(value: anytype) ?PipelineRouteWitness {
                    if (residualSourceEntryForValue(value)) |entry| {
                        return .{
                            .kind = .source_site_reinterpreted_dynamic,
                            .source_site_index = entry.source_site_index,
                            .source_site_fingerprint = entry.source_site_fingerprint,
                            .target_protocol_label = if (@hasField(@TypeOf(value), "target_protocol_label")) value.target_protocol_label else null,
                            .target_op_name = if (@hasField(@TypeOf(value), "target_op_name")) value.target_op_name else null,
                            .target_protocol_op_fingerprint = if (@hasField(@TypeOf(value), "target_protocol_op_fingerprint")) value.target_protocol_op_fingerprint else null,
                        };
                    }
                    return null;
                }

                fn residualSourceEntryForValue(value: anytype) ?ResidualSourceMapEntry {
                    if (!@hasField(@TypeOf(value), "source_site_fingerprint") or
                        !sourceIdentityMatchesProgram(value, ResidualProgram.contract.label, ResidualProgram.compiled_plan.hash()))
                    {
                        return null;
                    }
                    inline for (ResidualProgram.source_map) |entry| {
                        if (entry.residual_site_fingerprint != null and entry.residual_site_fingerprint.? == value.source_site_fingerprint) return entry;
                    }
                    return null;
                }

                fn identityResidualTraceMap(trace: anytype) ?ResidualSourceMapEntry {
                    inline for (protocol.operation_site_metadata) |site| {
                        if (comptime !routeResidualizesSource(site.fingerprint)) {
                            if (traceMatchesProgramSite(trace, site, ResidualProgram.contract.label, ResidualProgram.compiled_plan.hash())) {
                                return .{
                                    .source_site_index = site.index,
                                    .source_site_fingerprint = site.fingerprint,
                                    .residual_site_index = if (@hasField(@TypeOf(trace), "operation_site_index")) trace.operation_site_index else site.index,
                                    .residual_site_fingerprint = if (@hasField(@TypeOf(trace), "operation_site_fingerprint")) trace.operation_site_fingerprint else site.fingerprint,
                                    .disposition = .forwarded,
                                    .target_protocol_label = site.requirement_label,
                                    .target_op_name = site.op_name,
                                    .target_protocol_op_fingerprint = if (@hasField(@TypeOf(trace), "operation_site_fingerprint")) trace.operation_site_fingerprint else site.fingerprint,
                                    .mapping_label = site.semantic_label,
                                };
                            }
                        }
                    }
                    return null;
                }

                fn routeResidualizesSource(source_site_fingerprint: u64) bool {
                    inline for (Report.routes) |route| {
                        if (route.kind == .source_site_residualized and
                            route.source_site_fingerprint != null and
                            route.source_site_fingerprint.? == source_site_fingerprint)
                        {
                            return true;
                        }
                    }
                    return false;
                }

                fn traceBelongsToProgram(trace: anytype, comptime expected_label: []const u8, comptime expected_plan_hash: u64) bool {
                    return @hasField(@TypeOf(trace), "program_label") and
                        @hasField(@TypeOf(trace), "plan_hash") and
                        std.mem.eql(u8, trace.program_label, expected_label) and
                        trace.plan_hash == expected_plan_hash;
                }

                fn sourceIdentityMatchesProgram(value: anytype, comptime expected_label: []const u8, comptime expected_plan_hash: u64) bool {
                    const ValueType = @TypeOf(value);
                    if (comptime @hasField(ValueType, "source_program_label") or @hasField(ValueType, "source_plan_hash")) {
                        return @hasField(ValueType, "source_program_label") and
                            @hasField(ValueType, "source_plan_hash") and
                            std.mem.eql(u8, value.source_program_label, expected_label) and
                            value.source_plan_hash == expected_plan_hash;
                    }
                    if (comptime @hasField(ValueType, "program_label") or @hasField(ValueType, "plan_hash")) {
                        return traceBelongsToProgram(value, expected_label, expected_plan_hash);
                    }
                    return true;
                }

                fn traceMatchesProgramSite(trace: anytype, comptime site: anytype, comptime expected_label: []const u8, comptime expected_plan_hash: u64) bool {
                    if (@hasField(@TypeOf(trace), "operation_site_fingerprint") and trace.operation_site_fingerprint == site.fingerprint) {
                        return !@hasField(@TypeOf(trace), "program_label") or traceBelongsToProgram(trace, expected_label, expected_plan_hash);
                    }
                    if (!traceBelongsToProgram(trace, expected_label, expected_plan_hash)) return false;
                    return @hasField(@TypeOf(trace), "function_index") and
                        @hasField(@TypeOf(trace), "block_index") and
                        @hasField(@TypeOf(trace), "instruction_index") and
                        trace.function_index == site.function_index and
                        trace.block_index == site.block_index and
                        trace.instruction_index == site.instruction_index;
                }
            };
        }

        /// Typed request emitted by protocol reinterpretation.
        pub fn ProtocolRequest(comptime SourceSite: type, comptime TargetOp: type) type {
            comptime validateSourceOperationSite(SourceSite);
            comptime validateProtocolOperationDescriptor(TargetOp);
            return struct {
                /// Source Program label.
                source_program_label: []const u8 = label,
                /// Source ProgramPlan label.
                source_plan_label: []const u8 = body_compiled_plan.label,
                /// Source ProgramPlan hash.
                source_plan_hash: u64 = body_compiled_plan_hash,
                /// Source static operation-site index.
                source_site_index: usize,
                /// Source static operation-site fingerprint.
                source_site_fingerprint: u64,
                /// Source dynamic request fingerprint.
                source_request_fingerprint: u64,
                /// Source continuation capsule fingerprint.
                source_capsule_fingerprint: u64,
                /// Owned source continuation capsule.
                source_capsule: Session.Capsule,
                /// Target protocol label.
                target_protocol_label: []const u8 = TargetOp.protocol_label,
                /// Target operation name.
                target_op_name: []const u8 = TargetOp.op_name,
                /// Target operation mode.
                target_op_mode: plan_types.ControlMode = TargetOp.op_mode,
                /// Target protocol-operation fingerprint.
                target_protocol_op_fingerprint: u64 = TargetOp.fingerprint,
                /// Target payload ref.
                target_payload_ref: lowering_api.ValueRef = TargetOp.payload_ref,
                /// Target resume ref.
                target_resume_ref: lowering_api.ValueRef = TargetOp.resume_ref,
                /// Target result ref.
                target_result_ref: lowering_api.ValueRef = TargetOp.result_ref,
                /// Allocator owning cloned target payload values.
                target_payload_allocator: std.mem.Allocator,
                /// Target payload value.
                target_payload: TargetOp.Payload,
                /// Target payload fingerprint.
                target_payload_fingerprint: u64,
                /// Reinterpreted request fingerprint.
                reinterpreted_request_fingerprint: u64,
                /// Optional semantic label for display/debugging.
                semantic_label: ?[]const u8 = null,

                /// Build an owned reinterpreted protocol request.
                pub fn init(
                    allocator: std.mem.Allocator,
                    source_request_fingerprint: u64,
                    source_capsule: *const Session.Capsule,
                    target_payload: TargetOp.Payload,
                    semantic_label: ?[]const u8,
                ) Error!@This() {
                    const source_metadata = source_capsule.metadata();
                    if (!std.mem.eql(u8, source_metadata.program_label, label) or
                        !std.mem.eql(u8, source_metadata.plan_label, body_compiled_plan.label) or
                        source_metadata.plan_hash != body_compiled_plan_hash or
                        source_metadata.parked_kind != .operation or
                        source_metadata.current_operation_site_index == null or
                        source_metadata.current_operation_site_index.? != SourceSite.index or
                        source_metadata.function_index == null or
                        source_metadata.function_index.? != SourceSite.function_index or
                        source_metadata.block_index == null or
                        source_metadata.block_index.? != SourceSite.block_index or
                        source_metadata.instruction_index == null or
                        source_metadata.instruction_index.? != SourceSite.instruction_index or
                        !source_metadata.result_ref.eql(SourceSite.result_ref) or
                        source_metadata.current_request_fingerprint != source_request_fingerprint)
                    {
                        return error.ProgramContractViolation;
                    }
                    const capsule_fingerprint = source_capsule.fingerprint();
                    const payload_fingerprint = try fingerprintTypedProtocolValue(TargetOp.payload_ref, target_payload);
                    const owned_payload = try cloneProgramValue(allocator, TargetOp.Payload, target_payload);
                    errdefer deinitProgramValue(allocator, TargetOp.Payload, owned_payload);
                    var owned_capsule = try source_capsule.clone(allocator);
                    errdefer owned_capsule.deinit();
                    return .{
                        .source_site_index = SourceSite.index,
                        .source_site_fingerprint = SourceSite.fingerprint,
                        .source_request_fingerprint = source_request_fingerprint,
                        .source_capsule_fingerprint = capsule_fingerprint,
                        .source_capsule = owned_capsule,
                        .target_payload_allocator = allocator,
                        .target_payload = owned_payload,
                        .target_payload_fingerprint = payload_fingerprint,
                        .reinterpreted_request_fingerprint = reinterpretFingerprint(
                            source_request_fingerprint,
                            capsule_fingerprint,
                            TargetOp.fingerprint,
                            payload_fingerprint,
                        ),
                        .semantic_label = semantic_label,
                    };
                }

                /// Release the owned source capsule.
                pub fn deinit(self: *@This()) void {
                    deinitProgramValue(self.target_payload_allocator, TargetOp.Payload, self.target_payload);
                    self.source_capsule.deinit();
                }

                /// Return the typed target payload as an immutable protocol-safe view.
                pub fn payload(self: @This()) ProtocolHandlerPayloadType(TargetOp.Payload) {
                    return protocolHandlerPayloadView(self.target_payload);
                }

                /// Return the reinterpreted request fingerprint.
                pub fn fingerprint(self: @This()) u64 {
                    return self.reinterpreted_request_fingerprint;
                }

                /// Return whether this request matches a target protocol op.
                pub fn matches(self: @This(), comptime ExpectedOp: type) bool {
                    comptime validateProtocolOperationDescriptor(ExpectedOp);
                    return self.target_protocol_op_fingerprint == ExpectedOp.fingerprint and
                        self.target_payload_ref.eql(ExpectedOp.payload_ref) and
                        self.target_resume_ref.eql(ExpectedOp.resume_ref) and
                        self.target_result_ref.eql(ExpectedOp.result_ref);
                }
            };
        }

        /// Typed algebraic-effect handler declarations and outcomes for this Program.
        pub const Handler = struct {
            /// Program-representable handler value checked against the live request ref when applied.
            pub const DynamicValue = struct {
                ref: lowering_api.ValueRef,
                type_name: []const u8,
                boxed_ptr: ?*anyopaque = null,
                storage: [handler_value_storage_size]u8 align(handler_value_storage_align) = undefined,

                fn StorageType(comptime ValueType: type) type {
                    if (ValueType == [][]const u8) return []const []const u8;
                    return ValueType;
                }

                fn storageValue(value: anytype) StorageType(@TypeOf(value)) {
                    if (@TypeOf(value) == [][]const u8) return @as([]const []const u8, value);
                    return value;
                }

                fn init(value: anytype) @This() {
                    const ValueType = @TypeOf(value);
                    return initWithRef(ProgramValueRefForType(body_value_schema_types, ValueType), value);
                }

                fn initWithRef(comptime ref: lowering_api.ValueRef, value: anytype) @This() {
                    const ValueType = @TypeOf(value);
                    const StoredType = StorageType(ValueType);
                    if (comptime !ProgramValueRefCompatibleWithType(ref, ValueType)) {
                        @compileError("Program.Handler value ref does not match value type: " ++ @typeName(ValueType));
                    }
                    var result: @This() = .{
                        .ref = ref,
                        .type_name = @typeName(StoredType),
                    };
                    if (StoredType != void) {
                        const destination: *StoredType = @ptrCast(@alignCast(&result.storage));
                        destination.* = storageValue(value);
                    }
                    return result;
                }

                fn initBoxedWithRef(comptime ref: lowering_api.ValueRef, boxed: anytype) @This() {
                    const BoxedType = @TypeOf(boxed);
                    const ValueType = @typeInfo(BoxedType).pointer.child;
                    if (comptime !ProgramValueRefCompatibleWithType(ref, ValueType)) {
                        @compileError("Program.Handler boxed value ref does not match value type: " ++ @typeName(ValueType));
                    }
                    return .{
                        .ref = ref,
                        .type_name = @typeName(ValueType),
                        .boxed_ptr = @ptrCast(boxed),
                    };
                }

                fn as(self: *const @This(), comptime ValueType: type) Error!ValueType {
                    if (!ProgramValueRefCompatibleWithType(self.ref, ValueType)) return error.ProgramContractViolation;
                    if (ValueType == void) return {};
                    const source: *const ValueType = if (self.boxed_ptr) |ptr| boxed: {
                        if (!std.mem.eql(u8, self.type_name, @typeName(ValueType))) return error.ProgramContractViolation;
                        break :boxed @ptrCast(@alignCast(ptr));
                    } else unboxed: {
                        if (ValueType != StorageType(ValueType)) return error.ProgramContractViolation;
                        if (!std.mem.eql(u8, self.type_name, @typeName(ValueType))) return error.ProgramContractViolation;
                        break :unboxed @ptrCast(@alignCast(&self.storage));
                    };
                    return source.*;
                }
            };

            /// Interpreter stop reason for capsule-bearing results.
            pub const StopReason = enum {
                explicit_suspend,
                forwarded_unhandled,
                unhandled,
            };

            /// Trace view for the currently parked operation or after-continuation.
            pub const TraceView = union(enum) {
                after: Session.Trace.AfterRequest,
                operation: Session.Trace.OperationRequest,
            };

            /// Read-only, handler-scoped control over the currently parked continuation boundary.
            pub const Control = struct {
                _capture_context: *anyopaque,
                _current: Session.Current,

                fn init(session: *Session, current: Session.Current) @This() {
                    return .{
                        ._capture_context = session,
                        ._current = current,
                    };
                }

                /// Return the parked kind currently controlled by the handler.
                pub fn parkedKind(self: @This()) Error!Session.ParkedKind {
                    return switch (self._current) {
                        .request => .operation,
                        .after => .after,
                        .none => error.ProgramContractViolation,
                    };
                }

                /// Return the current request or after trace.
                pub fn trace(self: @This()) Error!TraceView {
                    return switch (self._current) {
                        .request => |request| .{ .operation = request.trace() },
                        .after => |after_request| .{ .after = after_request.trace() },
                        .none => error.ProgramContractViolation,
                    };
                }

                /// Return the deterministic fingerprint for the current parked request.
                pub fn requestFingerprint(self: @This()) Error!u64 {
                    return switch (self._current) {
                        .request => |request| request.fingerprint(),
                        .after => |after_request| after_request.fingerprint(),
                        .none => error.ProgramContractViolation,
                    };
                }

                /// Capture the current parked continuation without advancing it.
                pub fn capture(self: @This(), allocator: std.mem.Allocator) Error!Session.Capsule {
                    const session: *Session = @ptrCast(@alignCast(self._capture_context));
                    return session.capture(allocator);
                }
            };

            // zlinter-disable field_ordering - outcome tags stay grouped by handler control action, not alphabetically.
            /// Site-specific handler outcome. Helper constructors enforce site-mode legality at comptime.
            pub fn Outcome(comptime Site: type) type {
                comptime validateAnySite(Site);
                if (comptime Site.kind == .after) {
                    return union(enum) {
                        fail: anyerror,
                        forward,
                        resume_after: DynamicValue,
                        @"suspend",
                    };
                }
                return union(enum) {
                    fail: anyerror,
                    forward,
                    @"resume": Site.Resume,
                    return_now: Site.Result,
                    @"suspend",
                };
            }

            /// Site-specific outcome for handlers declared with an explicit morphism.
            pub fn MorphismOutcome(comptime MorphismType: type) type {
                comptime {
                    validateOperationSite(MorphismType.source);
                    validateProtocolOperationDescriptor(MorphismType.target);
                }
                const Site = MorphismType.source;
                return union(enum) {
                    fail: anyerror,
                    forward,
                    @"resume": Site.Resume,
                    return_now: Site.Result,
                    reinterpret: Reinterpretation(MorphismType),
                    @"suspend",
                };
            }
            // zlinter-enable field_ordering

            /// Outcome vocabulary available to a source-site mapper.
            pub fn SourceOutcome(comptime Site: type) type {
                comptime validateOperationSite(Site);
                return Outcome(Site);
            }

            /// Target protocol operation response vocabulary.
            // zlinter-disable field_ordering - target responses stay grouped by protocol control action.
            pub fn TargetResponse(comptime TargetOp: type) type {
                comptime validateProtocolOperationDescriptor(TargetOp);
                if (comptime TargetOp.may_resume and TargetOp.may_return_now) {
                    return union(enum) {
                        fail: anyerror,
                        forward,
                        return_now: TargetOp.Result,
                        @"resume": TargetOp.Resume,
                    };
                }
                if (comptime TargetOp.may_resume) {
                    return union(enum) {
                        fail: anyerror,
                        forward,
                        @"resume": TargetOp.Resume,
                    };
                }
                if (comptime TargetOp.may_return_now) {
                    return union(enum) {
                        fail: anyerror,
                        forward,
                        return_now: TargetOp.Result,
                    };
                }
                return union(enum) {
                    fail: anyerror,
                    forward,
                };
            }
            // zlinter-enable field_ordering

            /// Type-erased reinterpretation payload carried by a source-site outcome.
            pub fn Reinterpretation(comptime MorphismType: type) type {
                const SourceSite = MorphismType.source;
                const TargetOp = MorphismType.target;
                const Mapper = MorphismType.Mapper;
                comptime {
                    validateOperationSite(SourceSite);
                    validateProtocolOperationDescriptor(TargetOp);
                    MapperFns(SourceSite, TargetOp, Mapper).validate();
                }
                return struct {
                    target_protocol_label: []const u8,
                    target_op_name: []const u8,
                    target_op_mode: plan_types.ControlMode,
                    target_protocol_op_fingerprint: u64,
                    target_payload_ref: lowering_api.ValueRef,
                    target_resume_ref: lowering_api.ValueRef,
                    target_result_ref: lowering_api.ValueRef,
                    target_payload: TargetOp.Payload,
                    target_payload_fingerprint: u64,
                    morphism_fingerprint: u64,

                    /// Decode the target payload.
                    pub fn payload(self: @This(), comptime Payload: type) Error!Payload {
                        if (Payload != TargetOp.Payload) return error.ProgramContractViolation;
                        return self.target_payload;
                    }

                    /// Map a target resume value into a source outcome.
                    pub fn mapResume(self: @This(), value: anytype) Error!Outcome(SourceSite) {
                        _ = self;
                        if (comptime !TargetOp.may_resume) return error.ProgramContractViolation;
                        if (comptime @TypeOf(value) != TargetOp.Resume) return error.ProgramContractViolation;
                        return MapperFns(SourceSite, TargetOp, Mapper).mapResume(value);
                    }

                    /// Map a target return-now value into a source outcome.
                    pub fn mapReturnNow(self: @This(), value: anytype) Error!Outcome(SourceSite) {
                        _ = self;
                        if (comptime !TargetOp.may_return_now) return error.ProgramContractViolation;
                        if (comptime @TypeOf(value) != TargetOp.Result) return error.ProgramContractViolation;
                        return MapperFns(SourceSite, TargetOp, Mapper).mapReturnNow(value);
                    }

                    fn clonePayload(self: @This(), allocator: std.mem.Allocator) Error!DynamicValue {
                        const cloned = try cloneProgramValue(allocator, TargetOp.Payload, self.target_payload);
                        errdefer deinitProgramValue(allocator, TargetOp.Payload, cloned);
                        const boxed = allocator.create(TargetOp.Payload) catch |err| return mapProgramRunError(Error, err);
                        boxed.* = cloned;
                        return DynamicValue.initBoxedWithRef(TargetOp.payload_ref, boxed);
                    }

                    fn fingerprintStoredPayload(stored_payload: *const DynamicValue) Error!u64 {
                        const typed = try stored_payload.as(TargetOp.Payload);
                        return fingerprintTypedProtocolValue(TargetOp.payload_ref, typed);
                    }

                    fn deinitPayload(self: @This(), allocator: std.mem.Allocator, stored_payload: *DynamicValue) void {
                        _ = self;
                        deinitStoredPayload(allocator, stored_payload);
                    }

                    fn deinitStoredPayload(allocator: std.mem.Allocator, stored_payload: *DynamicValue) void {
                        if (stored_payload.boxed_ptr) |ptr| {
                            const boxed: *TargetOp.Payload = @ptrCast(@alignCast(ptr));
                            deinitProgramValue(allocator, TargetOp.Payload, boxed.*);
                            allocator.destroy(boxed);
                            stored_payload.boxed_ptr = null;
                            return;
                        }
                        const typed = stored_payload.as(TargetOp.Payload) catch return;
                        deinitProgramValue(allocator, TargetOp.Payload, typed);
                    }
                };
            }

            /// Declare one operation-site handler.
            pub fn operation(comptime site: type, comptime handler_fn: anytype) type {
                comptime validateOperationSite(site);
                return struct {
                    const kind = .operation;
                    const Site = site;
                    const function = handler_fn;
                };
            }

            /// Declare one after-continuation-site handler.
            pub fn after(comptime site: type, comptime handler_fn: anytype) type {
                comptime validateAfterSite(site);
                return struct {
                    const kind = .after;
                    const Site = site;
                    const function = handler_fn;
                };
            }

            /// Declare one protocol-level operation handler for reinterpreted requests.
            pub fn protocolOperation(comptime target_op: type, comptime handler_fn: anytype) type {
                comptime validateProtocolOperationDescriptor(target_op);
                return struct {
                    const kind = .protocol_operation;
                    const TargetOp = target_op;
                    const function = handler_fn;
                };
            }

            /// Declare a source operation handler with explicit source-to-target morphism metadata.
            pub fn morphism(comptime MorphismType: type, comptime handler_fn: anytype) type {
                comptime {
                    validateSourceOperationSite(MorphismType.source);
                    validateProtocolOperationDescriptor(MorphismType.target);
                }
                return struct {
                    const kind = .operation;
                    const Site = MorphismType.source;
                    const Morphism = MorphismType;
                    const function = handler_fn;
                };
            }

            fn MapperFns(comptime SourceSite: type, comptime TargetOp: type, comptime Mapper: type) type {
                validateOperationSite(SourceSite);
                validateProtocolOperationDescriptor(TargetOp);
                return struct {
                    fn validateUnaryMapper(
                        comptime mapper_name: []const u8,
                        comptime Fn: type,
                        comptime Param: type,
                    ) void {
                        const info = @typeInfo(Fn).@"fn";
                        if (info.params.len != 1 or info.params[0].type == null or info.params[0].type.? != Param) {
                            @compileError("Program.Handler.reinterpret mapper " ++ mapper_name ++ " parameter must match target protocol operation type");
                        }
                    }

                    fn validate() void {
                        if (comptime TargetOp.may_resume) {
                            if (comptime !hasDeclSafe(Mapper, "resume") and !hasDeclSafe(Mapper, "@\"resume\"")) {
                                @compileError("Program.Handler.reinterpret mapper must declare resume for resumable target protocol ops");
                            }
                            const resume_info = @typeInfo(@TypeOf(Mapper.@"resume")).@"fn";
                            validateUnaryMapper("resume", @TypeOf(Mapper.@"resume"), TargetOp.Resume);
                            if (resume_info.return_type == null or resume_info.return_type.? != Outcome(SourceSite)) {
                                @compileError("Program.Handler.reinterpret mapper resume must return Program.Handler.SourceOutcome(SourceSite)");
                            }
                        }
                        if (comptime TargetOp.may_return_now) {
                            if (comptime !hasDeclSafe(Mapper, "returnNow")) {
                                @compileError("Program.Handler.reinterpret mapper must declare returnNow for terminal target protocol ops");
                            }
                            const return_now_info = @typeInfo(@TypeOf(Mapper.returnNow)).@"fn";
                            validateUnaryMapper("returnNow", @TypeOf(Mapper.returnNow), TargetOp.Result);
                            if (return_now_info.return_type == null or return_now_info.return_type.? != Outcome(SourceSite)) {
                                @compileError("Program.Handler.reinterpret mapper returnNow must return Program.Handler.SourceOutcome(SourceSite)");
                            }
                        }
                    }

                    fn mapResume(value: TargetOp.Resume) Error!Outcome(SourceSite) {
                        if (comptime !TargetOp.may_resume) return error.ProgramContractViolation;
                        if (comptime !hasDeclSafe(Mapper, "resume") and !hasDeclSafe(Mapper, "@\"resume\"")) {
                            @compileError("Program.Handler.reinterpret mapper must declare resume for resumable target protocol ops");
                        }
                        const raw = Mapper.@"resume"(value);
                        const RawType = @TypeOf(raw);
                        if (comptime RawType != Outcome(SourceSite)) {
                            @compileError("Program.Handler.reinterpret mapper resume must return Program.Handler.SourceOutcome(SourceSite)");
                        }
                        return raw;
                    }

                    fn mapReturnNow(value: TargetOp.Result) Error!Outcome(SourceSite) {
                        if (comptime !TargetOp.may_return_now) return error.ProgramContractViolation;
                        if (comptime !hasDeclSafe(Mapper, "returnNow")) {
                            @compileError("Program.Handler.reinterpret mapper must declare returnNow for terminal target protocol ops");
                        }
                        const raw = Mapper.returnNow(value);
                        const RawType = @TypeOf(raw);
                        if (comptime RawType != Outcome(SourceSite)) {
                            @compileError("Program.Handler.reinterpret mapper returnNow must return Program.Handler.SourceOutcome(SourceSite)");
                        }
                        return raw;
                    }
                };
            }

            /// Reinterpret a source Program operation as a target protocol operation.
            pub fn reinterpret(
                comptime MorphismType: type,
                target_payload: MorphismType.target.Payload,
            ) MorphismOutcome(MorphismType) {
                const SourceSite = MorphismType.source;
                const TargetOp = MorphismType.target;
                const Mapper = MorphismType.Mapper;
                comptime {
                    validateOperationSite(SourceSite);
                    validateProtocolOperationDescriptor(TargetOp);
                    MapperFns(SourceSite, TargetOp, Mapper).validate();
                }
                return .{ .reinterpret = .{
                    .target_protocol_label = TargetOp.protocol_label,
                    .target_op_name = TargetOp.op_name,
                    .target_op_mode = TargetOp.op_mode,
                    .target_protocol_op_fingerprint = TargetOp.fingerprint,
                    .target_payload_ref = TargetOp.payload_ref,
                    .target_resume_ref = TargetOp.resume_ref,
                    .target_result_ref = TargetOp.result_ref,
                    .target_payload = target_payload,
                    .target_payload_fingerprint = fingerprintTypedProtocolValue(TargetOp.payload_ref, target_payload) catch 0,
                    .morphism_fingerprint = MorphismType.fingerprint,
                } };
            }

            /// Resume a transform or choice operation with a typed value.
            pub fn @"resume"(comptime Descriptor: type, value: SourceSiteForOutcome(Descriptor).Resume) OutcomeForDescriptor(Descriptor) {
                const Site = SourceSiteForOutcome(Descriptor);
                comptime {
                    validateOperationSite(Site);
                    if (!Site.may_resume) @compileError("Program.Handler.resume is invalid for this operation site");
                }
                return .{ .@"resume" = value };
            }

            /// Complete a choice or abort operation with a terminal value.
            pub fn returnNow(comptime Descriptor: type, value: SourceSiteForOutcome(Descriptor).Result) OutcomeForDescriptor(Descriptor) {
                const Site = SourceSiteForOutcome(Descriptor);
                comptime {
                    validateOperationSite(Site);
                    if (!Site.may_return_now) @compileError("Program.Handler.returnNow is invalid for this operation site");
                }
                return .{ .return_now = value };
            }

            /// Resume an after-continuation with a value checked against the live output ref.
            pub fn resumeAfter(comptime Site: type, value: anytype) Outcome(Site) {
                comptime validateAfterSite(Site);
                return .{ .resume_after = DynamicValue.init(value) };
            }

            /// Suspend at the current continuation boundary and return an owned capsule.
            pub fn @"suspend"(comptime Descriptor: type) OutcomeForDescriptor(Descriptor) {
                comptime _ = SourceSiteForOutcome(Descriptor);
                return .@"suspend";
            }

            /// Decline this site so a later composed interpreter can try to handle it.
            pub fn forward(comptime Descriptor: type) OutcomeForDescriptor(Descriptor) {
                comptime _ = SourceSiteForOutcome(Descriptor);
                return .forward;
            }

            /// Fail the interpreter with a handler-provided error.
            pub fn fail(comptime Descriptor: type, err: anyerror) OutcomeForDescriptor(Descriptor) {
                comptime _ = SourceSiteForOutcome(Descriptor);
                return .{ .fail = err };
            }

            fn OutcomeForDescriptor(comptime Descriptor: type) type {
                if (comptime isMorphismDescriptor(Descriptor)) return MorphismOutcome(Descriptor);
                return Outcome(Descriptor);
            }

            fn SourceSiteForOutcome(comptime Descriptor: type) type {
                if (comptime isMorphismDescriptor(Descriptor)) {
                    validateOperationSite(Descriptor.source);
                    validateProtocolOperationDescriptor(Descriptor.target);
                    return Descriptor.source;
                }
                validateAnySite(Descriptor);
                return Descriptor;
            }

            fn isMorphismDescriptor(comptime Descriptor: type) bool {
                return hasDeclSafe(Descriptor, "source") and
                    hasDeclSafe(Descriptor, "target") and
                    hasDeclSafe(Descriptor, "Mapper");
            }

            fn validateAnySite(comptime Site: type) void {
                if (!hasDeclSafe(Site, "kind")) @compileError("Program.Handler expected a Program.protocol site descriptor");
                switch (Site.kind) {
                    .operation => validateOperationSite(Site),
                    .after => validateAfterSite(Site),
                    else => @compileError("Program.Handler expected an operation or after site descriptor"),
                }
            }

            fn validateOwner(comptime Site: type) void {
                if (!hasDeclSafe(Site, "Owner") or
                    Site.Owner != Body or
                    !hasDeclSafe(Site, "owner_label") or
                    !std.mem.eql(u8, Site.owner_label, label) or
                    !hasDeclSafe(Site, "owner_plan_hash") or
                    Site.owner_plan_hash != body_compiled_plan_hash or
                    !hasDeclSafe(Site, "OwnerHandlers") or
                    Site.OwnerHandlers != HandlersType)
                {
                    @compileError("Program.Handler site descriptor belongs to another program");
                }
            }

            fn validateOperationSite(comptime Site: type) void {
                validateOwner(Site);
                if (!hasDeclSafe(Site, "kind") or Site.kind != .operation) {
                    @compileError("Program.Handler.operation expected an operation site descriptor");
                }
            }

            fn validateAfterSite(comptime Site: type) void {
                validateOwner(Site);
                if (!hasDeclSafe(Site, "kind") or Site.kind != .after) {
                    @compileError("Program.Handler.after expected an after site descriptor");
                }
            }
        };
        // zlinter-enable declaration_naming

        /// Build a typed interpreter from operation and after-continuation handlers.
        pub fn Interpreter(comptime entries: anytype) type {
            comptime validateInterpreterEntries(entries);
            const ProgramRunResult = Result;
            return struct {
                const InterpreterToken = InterpreterAuthenticityToken;

                /// Capsule-bearing suspension metadata.
                pub const Suspended = struct {
                    reason: Handler.StopReason,
                    capsule: Session.Capsule,
                    parked_kind: Session.ParkedKind,
                    trace: Handler.TraceView,
                    request_fingerprint: u64,
                    capsule_fingerprint: u64,

                    /// Release the owned capsule.
                    pub fn deinit(self: *@This()) void {
                        self.capsule.deinit();
                    }
                };

                /// Capsule-bearing unhandled-site metadata.
                pub const Unhandled = Suspended;

                /// Capsule-bearing reinterpreted protocol request.
                pub const Reinterpreted = struct {
                    reason: Handler.StopReason,
                    capsule: Session.Capsule,
                    source_trace: Session.Trace.OperationRequest,
                    source_request_fingerprint: u64,
                    source_capsule_fingerprint: u64,
                    target_protocol_label: []const u8,
                    target_op_name: []const u8,
                    target_op_mode: plan_types.ControlMode,
                    target_protocol_op_fingerprint: u64,
                    target_payload_ref: lowering_api.ValueRef,
                    target_resume_ref: lowering_api.ValueRef,
                    target_result_ref: lowering_api.ValueRef,
                    target_payload_allocator: std.mem.Allocator,
                    target_payload: Handler.DynamicValue,
                    target_payload_fingerprint: u64,
                    targetPayloadDeinitFn: *const fn (std.mem.Allocator, *Handler.DynamicValue) void,
                    reinterpreted_request_fingerprint: u64,
                    morphism_fingerprint: u64,
                    semantic_label: ?[]const u8 = null,

                    /// Release the owned source capsule.
                    pub fn deinit(self: *@This()) void {
                        self.targetPayloadDeinitFn(self.target_payload_allocator, &self.target_payload);
                        self.capsule.deinit();
                    }

                    /// Decode the target payload as the expected type with protocol-safe mutability.
                    pub fn payload(self: @This(), comptime Payload: type) Error!ProtocolHandlerPayloadType(Payload) {
                        return protocolHandlerPayloadView(try self.target_payload.as(Payload));
                    }

                    /// Return whether this request matches a target protocol op.
                    pub fn matches(self: @This(), comptime TargetOp: type) bool {
                        comptime validateProtocolOperationDescriptor(TargetOp);
                        return self.target_protocol_op_fingerprint == TargetOp.fingerprint and
                            self.target_payload_ref.eql(TargetOp.payload_ref) and
                            self.target_resume_ref.eql(TargetOp.resume_ref) and
                            self.target_result_ref.eql(TargetOp.result_ref);
                    }
                };

                /// Interpreter execution result.
                pub const ExecutionResult = union(enum) {
                    done: ProgramRunResult,
                    reinterpreted: Reinterpreted,
                    suspended: Suspended,
                    unhandled: Unhandled,
                };
                /// Short alias for the interpreter execution result.
                pub const Result = ExecutionResult;

                /// Drive a fresh Program.Session until done, suspended, unhandled, or error.
                pub fn run(
                    runtime: *lowered_machine.Runtime,
                    handlers: HandlersType,
                    host_ctx: anytype,
                    options: anytype,
                ) Error!ExecutionResult {
                    var session = try Session.start(runtime, handlers);
                    defer session.deinit();
                    return continueSession(&session, host_ctx, options);
                }

                /// Restore a fresh session from a reusable capsule and drive it with this interpreter.
                pub fn restore(
                    runtime: *lowered_machine.Runtime,
                    handlers: HandlersType,
                    host_ctx: anytype,
                    capsule: *const Session.Capsule,
                    options: anytype,
                ) Error!ExecutionResult {
                    var session = try Session.restore(runtime, handlers, capsule);
                    defer session.deinit();
                    return continueSession(&session, host_ctx, options);
                }

                /// Continue an existing session from its current lifecycle state.
                pub fn continueSession(session: *Session, host_ctx: anytype, options: anytype) Error!ExecutionResult {
                    while (true) {
                        switch (try session.current()) {
                            .none => {},
                            .request => |request| {
                                const current = Session.Current{ .request = request };
                                if (try dispatchOperation(session, current, host_ctx, options)) |result| return result;
                                continue;
                            },
                            .after => |after_request| {
                                const current = Session.Current{ .after = after_request };
                                if (try dispatchAfter(session, current, host_ctx, options)) |result| return result;
                                continue;
                            },
                        }
                        switch (try session.next()) {
                            .done => |done| return .{ .done = done },
                            .request => |request| {
                                const current = Session.Current{ .request = request };
                                if (try dispatchOperation(session, current, host_ctx, options)) |result| return result;
                            },
                            .after => |after| {
                                const current = Session.Current{ .after = after };
                                if (try dispatchAfter(session, current, host_ctx, options)) |result| return result;
                            },
                        }
                    }
                }

                /// Assert that this interpreter covers all reachable operation and after sites.
                pub fn assertCoversAll() void {
                    comptime assertInterpreterCoversAll(entries);
                }

                /// Return static coverage counts for this interpreter.
                pub fn coverage() struct { operation_sites: usize, after_sites: usize } {
                    comptime var operation_count: usize = 0;
                    comptime var after_count: usize = 0;
                    inline for (entries) |Entry| switch (Entry.kind) {
                        .operation => operation_count += 1,
                        .after => after_count += 1,
                        else => {},
                    };
                    return .{ .operation_sites = operation_count, .after_sites = after_count };
                }

                fn validateProgramArgument(comptime ProgramType: type) void {
                    if (!hasDeclSafe(ProgramType, "protocol") or
                        !hasDeclSafe(ProgramType.protocol, "Owner") or
                        ProgramType.protocol.Owner != Body or
                        ProgramType.protocol.hash != protocol.hash or
                        !std.mem.eql(u8, ProgramType.protocol.label, protocol.label) or
                        !hasDeclSafe(ProgramType.protocol, "OwnerHandlers") or
                        ProgramType.protocol.OwnerHandlers != HandlersType)
                    {
                        @compileError("Program.Interpreter effectRow expected owning Program type");
                    }
                }

                /// Return static effect-row counts for handled and residual effects.
                pub fn effectRow(comptime ProgramType: type) struct {
                    handled_operation_sites: usize,
                    handled_after_sites: usize,
                    handled_protocol_operations: usize,
                    reinterpreted_source_sites: usize,
                    emitted_protocol_operations: usize,
                    residual_operation_sites: usize,
                    residual_after_sites: usize,
                } {
                    comptime validateProgramArgument(ProgramType);
                    comptime var operation_count: usize = 0;
                    comptime var after_count: usize = 0;
                    comptime var protocol_operation_count: usize = 0;
                    comptime var reinterpreted_count: usize = 0;
                    inline for (entries) |Entry| switch (Entry.kind) {
                        .operation => {
                            operation_count += 1;
                            if (comptime hasDeclSafe(Entry, "Morphism")) reinterpreted_count += 1;
                        },
                        .after => after_count += 1,
                        .protocol_operation => protocol_operation_count += 1,
                        else => {},
                    };
                    return .{
                        .handled_operation_sites = operation_count,
                        .handled_after_sites = after_count,
                        .handled_protocol_operations = protocol_operation_count,
                        .reinterpreted_source_sites = reinterpreted_count,
                        .emitted_protocol_operations = reinterpreted_count,
                        .residual_operation_sites = protocol.operation_site_count - operation_count,
                        .residual_after_sites = protocol.after_site_count - after_count,
                    };
                }

                /// Assert all Program sites and emitted protocol operations are eliminated.
                pub fn assertEliminates(comptime ProgramType: type) void {
                    _ = effectRow(ProgramType);
                    assertCoversAll();
                    comptime {
                        for (entries) |Entry| {
                            if (Entry.kind == .operation and hasDeclSafe(Entry, "Morphism")) {
                                var found_target_handler = false;
                                for (entries) |Candidate| {
                                    if (Candidate.kind == .protocol_operation and Candidate.TargetOp.fingerprint == Entry.Morphism.target.fingerprint) {
                                        found_target_handler = true;
                                    }
                                }
                                if (!found_target_handler) @compileError("Program.Interpreter elimination omitted emitted protocol operation");
                            }
                        }
                    }
                }

                /// Assert this interpreter declares a source-to-target reinterpretation.
                pub fn assertReinterprets(comptime SourceSite: type, comptime TargetOp: type) void {
                    comptime {
                        validateSourceOperationSite(SourceSite);
                        validateProtocolOperationDescriptor(TargetOp);
                        var found = false;
                        for (entries) |Entry| {
                            if (Entry.kind == .operation and hasDeclSafe(Entry, "Morphism") and
                                Entry.Morphism.source.fingerprint == SourceSite.fingerprint and
                                Entry.Morphism.target.fingerprint == TargetOp.fingerprint)
                            {
                                found = true;
                            }
                        }
                        if (!found) @compileError("Program.Interpreter does not declare requested reinterpretation");
                    }
                }

                /// Assert this interpreter handles the listed protocol operations.
                pub fn assertHandlesProtocolOps(comptime TargetOps: anytype) void {
                    comptime {
                        for (TargetOps) |TargetOp| {
                            validateProtocolOperationDescriptor(TargetOp);
                            var found = false;
                            for (entries) |Entry| {
                                if (Entry.kind == .protocol_operation and Entry.TargetOp.fingerprint == TargetOp.fingerprint) {
                                    found = true;
                                }
                            }
                            if (!found) @compileError("Program.Interpreter does not handle requested protocol operation");
                        }
                    }
                }

                /// Assert the exact residual Program operation sites.
                pub fn assertResidualSites(comptime Sites: anytype) void {
                    comptime {
                        var listed: [protocol.operation_site_count]bool = [_]bool{false} ** protocol.operation_site_count;
                        for (Sites) |Site| {
                            validateSourceOperationSite(Site);
                            if (Site.index >= protocol.operation_site_count or protocol.operation_site_metadata[Site.index].fingerprint != Site.fingerprint) {
                                @compileError("Program.Interpreter residual descriptor belongs to another program");
                            }
                            if (listed[Site.index]) @compileError("Program.Interpreter listed duplicate residual operation site");
                            listed[Site.index] = true;
                        }
                        var handled: [protocol.operation_site_count]bool = [_]bool{false} ** protocol.operation_site_count;
                        for (entries) |Entry| {
                            if (Entry.kind == .operation) {
                                handled[Entry.Site.index] = true;
                            }
                        }
                        for (handled, 0..) |is_handled, index| {
                            if (is_handled and listed[index]) @compileError("Program.Interpreter residual list includes handled operation site");
                            if (!is_handled and !listed[index]) @compileError("Program.Interpreter residual list omitted unhandled operation site");
                        }
                    }
                }

                /// Typed request view passed to a protocol-operation handler.
                pub fn ProtocolOperationRequest(comptime TargetOp: type) type {
                    comptime validateProtocolOperationDescriptor(TargetOp);
                    return struct {
                        /// Reinterpreted request being offered to a protocol handler.
                        request: *const Reinterpreted,

                        /// Decode the typed target payload.
                        pub fn payload(self: @This()) Error!ProtocolHandlerPayloadType(TargetOp.Payload) {
                            if (!self.request.matches(TargetOp)) return error.ProgramContractViolation;
                            return protocolHandlerPayloadView(try self.request.payload(TargetOp.Payload));
                        }
                    };
                }

                fn dispatchOperation(
                    session: *Session,
                    current: Session.Current,
                    host_ctx: anytype,
                    options: anytype,
                ) Error!?ExecutionResult {
                    const request = switch (current) {
                        .request => |value| value,
                        else => return error.ProgramContractViolation,
                    };
                    inline for (entries) |Entry| {
                        if (Entry.kind == .operation and request.matches(Entry.Site)) {
                            const typed = try request.as(Entry.Site);
                            const control = Handler.Control.init(session, current);
                            const outcome = try callOperationHandler(Entry, host_ctx, typed, control);
                            return try applyOperationOutcome(Entry, session, current, typed, outcome, host_ctx, options);
                        }
                    }
                    return try buildUnhandled(session, current, .unhandled);
                }

                fn dispatchAfter(
                    session: *Session,
                    current: Session.Current,
                    host_ctx: anytype,
                    options: anytype,
                ) Error!?ExecutionResult {
                    const after_request = switch (current) {
                        .after => |value| value,
                        else => return error.ProgramContractViolation,
                    };
                    inline for (entries) |Entry| {
                        if (Entry.kind == .after and after_request.matches(Entry.Site)) {
                            const typed = try after_request.as(Entry.Site);
                            const control = Handler.Control.init(session, current);
                            const outcome = try callAfterHandler(Entry, host_ctx, typed, control);
                            return try applyAfterOutcome(Entry.Site, session, current, typed, outcome, options);
                        }
                    }
                    return try buildUnhandled(session, current, .unhandled);
                }

                fn OperationOutcomeForEntry(comptime Entry: type) type {
                    if (comptime hasDeclSafe(Entry, "Morphism")) return Handler.MorphismOutcome(Entry.Morphism);
                    return Handler.Outcome(Entry.Site);
                }

                fn callOperationHandler(comptime Entry: type, host_ctx: anytype, typed: anytype, control: Handler.Control) Error!OperationOutcomeForEntry(Entry) {
                    const raw = Entry.function(host_ctx, typed, control);
                    const ExpectedOutcome = OperationOutcomeForEntry(Entry);
                    const RawOutcome = switch (@typeInfo(@TypeOf(raw))) {
                        .error_union => |error_union| error_union.payload,
                        else => @TypeOf(raw),
                    };
                    if (comptime RawOutcome != ExpectedOutcome) {
                        @compileError("Program.Handler.operation cannot return reinterpret; declare Program.Handler.morphism for protocol reinterpretation");
                    }
                    if (comptime @typeInfo(@TypeOf(raw)) == .error_union) {
                        return raw catch |err| return mapProgramRunError(Error, err);
                    }
                    return raw;
                }

                fn callAfterHandler(comptime Entry: type, host_ctx: anytype, typed: anytype, control: Handler.Control) Error!Handler.Outcome(Entry.Site) {
                    const raw = Entry.function(host_ctx, typed, control);
                    if (comptime @typeInfo(@TypeOf(raw)) == .error_union) {
                        return raw catch |err| return mapProgramRunError(Error, err);
                    }
                    return raw;
                }

                fn applySourceOutcome(
                    comptime Site: type,
                    session: *Session,
                    current: Session.Current,
                    typed: anytype,
                    outcome: Handler.Outcome(Site),
                    options: anytype,
                ) Error!?ExecutionResult {
                    return switch (outcome) {
                        .@"resume" => |value| resume_branch: {
                            if (!Site.may_resume) return error.ProgramContractViolation;
                            const response_trace = typed.responseTrace(.@"resume", value) catch |err| return mapProgramRunError(Error, err);
                            try recordTrace(options, (try traceFor(current)).operation, response_trace);
                            try session.resumeTyped(typed, value);
                            break :resume_branch null;
                        },
                        .return_now => |value| return_now: {
                            if (!Site.may_return_now) return error.ProgramContractViolation;
                            const response_trace = typed.responseTrace(.return_now, value) catch |err| return mapProgramRunError(Error, err);
                            try recordTrace(options, (try traceFor(current)).operation, response_trace);
                            try session.returnNowTyped(typed, value);
                            break :return_now null;
                        },
                        .@"suspend" => try buildSuspended(session, current, .explicit_suspend),
                        .forward => try buildUnhandled(session, current, .forwarded_unhandled),
                        .fail => |err| return mapProgramRunError(Error, err),
                    };
                }

                fn applyOperationOutcome(
                    comptime Entry: type,
                    session: *Session,
                    current: Session.Current,
                    typed: anytype,
                    outcome: OperationOutcomeForEntry(Entry),
                    host_ctx: anytype,
                    options: anytype,
                ) Error!?ExecutionResult {
                    const Site = Entry.Site;
                    if (comptime !hasDeclSafe(Entry, "Morphism")) {
                        return applySourceOutcome(Site, session, current, typed, outcome, options);
                    }
                    return switch (outcome) {
                        .@"resume" => |value| resume_branch: {
                            if (!Site.may_resume) return error.ProgramContractViolation;
                            const response_trace = typed.responseTrace(.@"resume", value) catch |err| return mapProgramRunError(Error, err);
                            try recordTrace(options, (try traceFor(current)).operation, response_trace);
                            try session.resumeTyped(typed, value);
                            break :resume_branch null;
                        },
                        .return_now => |value| return_now: {
                            if (!Site.may_return_now) return error.ProgramContractViolation;
                            const response_trace = typed.responseTrace(.return_now, value) catch |err| return mapProgramRunError(Error, err);
                            try recordTrace(options, (try traceFor(current)).operation, response_trace);
                            try session.returnNowTyped(typed, value);
                            break :return_now null;
                        },
                        .@"suspend" => try buildSuspended(session, current, .explicit_suspend),
                        .reinterpret => |reinterpretation| try applyReinterpretation(Site, session, current, typed, reinterpretation, host_ctx, options),
                        .forward => try buildUnhandled(session, current, .forwarded_unhandled),
                        .fail => |err| return mapProgramRunError(Error, err),
                    };
                }

                fn applyReinterpretation(
                    comptime SourceSite: type,
                    session: *Session,
                    current: Session.Current,
                    typed: anytype,
                    reinterpretation: anytype,
                    host_ctx: anytype,
                    options: anytype,
                ) Error!?ExecutionResult {
                    var reinterpreted = try buildReinterpreted(session, current, reinterpretation);
                    errdefer reinterpreted.deinit();
                    var handled = false;
                    const dispatch_result = try dispatchProtocolOperation(SourceSite, session, current, typed, &reinterpreted, reinterpretation, host_ctx, options, &handled);
                    if (handled) {
                        reinterpreted.deinit();
                        return dispatch_result;
                    }
                    return .{ .reinterpreted = reinterpreted };
                }

                fn dispatchProtocolOperation(
                    comptime SourceSite: type,
                    session: *Session,
                    current: Session.Current,
                    typed: anytype,
                    reinterpreted: *Reinterpreted,
                    reinterpretation: anytype,
                    host_ctx: anytype,
                    options: anytype,
                    handled: *bool,
                ) Error!?ExecutionResult {
                    inline for (entries) |Entry| {
                        if (Entry.kind == .protocol_operation and reinterpreted.matches(Entry.TargetOp)) {
                            const protocol_request = ProtocolOperationRequest(Entry.TargetOp){ .request = reinterpreted };
                            const response = try callProtocolHandler(Entry, host_ctx, protocol_request);
                            return try applyTargetResponse(SourceSite, Entry.TargetOp, session, current, typed, reinterpretation, reinterpreted, response, options, handled);
                        }
                    }
                    return null;
                }

                fn applyTargetResponse(
                    comptime SourceSite: type,
                    comptime TargetOp: type,
                    session: *Session,
                    current: Session.Current,
                    typed: anytype,
                    reinterpretation: anytype,
                    reinterpreted: *Reinterpreted,
                    response: Handler.TargetResponse(TargetOp),
                    options: anytype,
                    handled: *bool,
                ) Error!?ExecutionResult {
                    if (comptime TargetOp.may_resume and TargetOp.may_return_now) {
                        return switch (response) {
                            .@"resume" => |value| try applyTargetResume(SourceSite, session, current, typed, reinterpretation, value, options, handled),
                            .return_now => |value| try applyTargetReturnNow(SourceSite, session, current, typed, reinterpretation, value, options, handled),
                            .forward => try applyTargetForward(reinterpretation, reinterpreted),
                            .fail => |err| applyTargetFail(err, handled),
                        };
                    }
                    if (comptime TargetOp.may_resume) {
                        return switch (response) {
                            .@"resume" => |value| try applyTargetResume(SourceSite, session, current, typed, reinterpretation, value, options, handled),
                            .forward => try applyTargetForward(reinterpretation, reinterpreted),
                            .fail => |err| applyTargetFail(err, handled),
                        };
                    }
                    if (comptime TargetOp.may_return_now) {
                        return switch (response) {
                            .return_now => |value| try applyTargetReturnNow(SourceSite, session, current, typed, reinterpretation, value, options, handled),
                            .forward => try applyTargetForward(reinterpretation, reinterpreted),
                            .fail => |err| applyTargetFail(err, handled),
                        };
                    }
                    return switch (response) {
                        .forward => try applyTargetForward(reinterpretation, reinterpreted),
                        .fail => |err| applyTargetFail(err, handled),
                    };
                }

                fn applyTargetResume(
                    comptime SourceSite: type,
                    session: *Session,
                    current: Session.Current,
                    typed: anytype,
                    reinterpretation: anytype,
                    value: anytype,
                    options: anytype,
                    handled: *bool,
                ) Error!?ExecutionResult {
                    handled.* = true;
                    const source_outcome = try reinterpretation.mapResume(value);
                    return try applySourceOutcome(SourceSite, session, current, typed, source_outcome, options);
                }

                fn applyTargetReturnNow(
                    comptime SourceSite: type,
                    session: *Session,
                    current: Session.Current,
                    typed: anytype,
                    reinterpretation: anytype,
                    value: anytype,
                    options: anytype,
                    handled: *bool,
                ) Error!?ExecutionResult {
                    handled.* = true;
                    const source_outcome = try reinterpretation.mapReturnNow(value);
                    return try applySourceOutcome(SourceSite, session, current, typed, source_outcome, options);
                }

                fn applyTargetForward(
                    reinterpretation: anytype,
                    reinterpreted: *Reinterpreted,
                ) Error!?ExecutionResult {
                    reinterpreted.reason = .forwarded_unhandled;
                    const target_payload_fingerprint = try @TypeOf(reinterpretation).fingerprintStoredPayload(&reinterpreted.target_payload);
                    reinterpreted.target_payload_fingerprint = target_payload_fingerprint;
                    reinterpreted.reinterpreted_request_fingerprint = reinterpretFingerprint(
                        reinterpreted.source_request_fingerprint,
                        reinterpreted.source_capsule_fingerprint,
                        reinterpreted.target_protocol_op_fingerprint,
                        target_payload_fingerprint,
                    );
                    return null;
                }

                fn applyTargetFail(err: anyerror, handled: *bool) Error!?ExecutionResult {
                    handled.* = true;
                    return mapProgramRunError(Error, err);
                }

                fn callProtocolHandler(comptime Entry: type, host_ctx: anytype, typed: anytype) Error!Handler.TargetResponse(Entry.TargetOp) {
                    const raw = Entry.function(host_ctx, typed);
                    if (comptime @typeInfo(@TypeOf(raw)) == .error_union) {
                        return raw catch |err| return mapProgramRunError(Error, err);
                    }
                    return raw;
                }

                fn afterResponseTraceForValue(typed: anytype, value: Handler.DynamicValue) Error!Session.Trace.Response {
                    return switch (value.ref.codec) {
                        .unit => try typed.responseTrace(try value.as(void)),
                        .bool => try typed.responseTrace(try value.as(bool)),
                        .i32 => try typed.responseTrace(try value.as(i32)),
                        .usize => try typed.responseTrace(try value.as(usize)),
                        .string => try typed.responseTrace(try value.as([]const u8)),
                        .string_list => try typed.responseTrace(try value.as([]const []const u8)),
                        .product, .sum => schema_trace: {
                            const schema_index = value.ref.schema_index orelse return error.ProgramContractViolation;
                            inline for (body_value_schema_types, 0..) |SchemaType, index| {
                                if (schema_index == index) break :schema_trace try typed.responseTrace(try value.as(SchemaType));
                            }
                            return error.ProgramContractViolation;
                        },
                    };
                }

                fn resumeAfterWithValue(session: *Session, typed: anytype, value: Handler.DynamicValue) Error!void {
                    return switch (value.ref.codec) {
                        .unit => try session.resumeAfterTyped(typed, try value.as(void)),
                        .bool => try session.resumeAfterTyped(typed, try value.as(bool)),
                        .i32 => try session.resumeAfterTyped(typed, try value.as(i32)),
                        .usize => try session.resumeAfterTyped(typed, try value.as(usize)),
                        .string => try session.resumeAfterTyped(typed, try value.as([]const u8)),
                        .string_list => try session.resumeAfterTyped(typed, try value.as([]const []const u8)),
                        .product, .sum => {
                            const schema_index = value.ref.schema_index orelse return error.ProgramContractViolation;
                            inline for (body_value_schema_types, 0..) |SchemaType, index| {
                                if (schema_index == index) return try session.resumeAfterTyped(typed, try value.as(SchemaType));
                            }
                            return error.ProgramContractViolation;
                        },
                    };
                }

                fn applyAfterOutcome(
                    comptime Site: type,
                    session: *Session,
                    current: Session.Current,
                    typed: anytype,
                    outcome: Handler.Outcome(Site),
                    options: anytype,
                ) Error!?ExecutionResult {
                    return switch (outcome) {
                        .resume_after => |value| resume_after: {
                            const response_trace = afterResponseTraceForValue(typed, value) catch |err| return mapProgramRunError(Error, err);
                            try recordTrace(options, (try traceFor(current)).after, response_trace);
                            try resumeAfterWithValue(session, typed, value);
                            break :resume_after null;
                        },
                        .@"suspend" => try buildSuspended(session, current, .explicit_suspend),
                        .forward => try buildUnhandled(session, current, .forwarded_unhandled),
                        .fail => |err| return mapProgramRunError(Error, err),
                    };
                }

                fn recordTrace(options: anytype, request_trace: anytype, response_trace: Session.Trace.Response) Error!void {
                    if (comptime @typeInfo(@TypeOf(options)) == .@"struct" and @hasField(@TypeOf(options), "trace_recorder")) {
                        if (comptime @typeInfo(@TypeOf(options.trace_recorder.record(request_trace, response_trace))) == .error_union) {
                            options.trace_recorder.record(request_trace, response_trace) catch |err| return mapProgramRunError(Error, err);
                        } else {
                            _ = options.trace_recorder.record(request_trace, response_trace);
                        }
                    }
                }

                fn buildReinterpreted(
                    session: *Session,
                    current: Session.Current,
                    reinterpretation: anytype,
                ) Error!Reinterpreted {
                    const trace = (try traceFor(current)).operation;
                    const payload_allocator = lowered_machine.runtimeAllocator(session.runtime);
                    var target_payload = try reinterpretation.clonePayload(payload_allocator);
                    errdefer reinterpretation.deinitPayload(payload_allocator, &target_payload);
                    const target_payload_fingerprint = try @TypeOf(reinterpretation).fingerprintStoredPayload(&target_payload);
                    var capsule = try session.capture(payload_allocator);
                    errdefer capsule.deinit();
                    const capsule_fingerprint = capsule.fingerprint();
                    const request_fingerprint = try fingerprintFor(current);
                    return .{
                        .reason = .unhandled,
                        .capsule = capsule,
                        .source_trace = trace,
                        .source_request_fingerprint = request_fingerprint,
                        .source_capsule_fingerprint = capsule_fingerprint,
                        .target_protocol_label = reinterpretation.target_protocol_label,
                        .target_op_name = reinterpretation.target_op_name,
                        .target_op_mode = reinterpretation.target_op_mode,
                        .target_protocol_op_fingerprint = reinterpretation.target_protocol_op_fingerprint,
                        .target_payload_ref = reinterpretation.target_payload_ref,
                        .target_resume_ref = reinterpretation.target_resume_ref,
                        .target_result_ref = reinterpretation.target_result_ref,
                        .target_payload_allocator = payload_allocator,
                        .target_payload = target_payload,
                        .target_payload_fingerprint = target_payload_fingerprint,
                        .targetPayloadDeinitFn = @TypeOf(reinterpretation).deinitStoredPayload,
                        .reinterpreted_request_fingerprint = reinterpretFingerprint(
                            request_fingerprint,
                            capsule_fingerprint,
                            reinterpretation.target_protocol_op_fingerprint,
                            target_payload_fingerprint,
                        ),
                        .morphism_fingerprint = reinterpretation.morphism_fingerprint,
                        .semantic_label = trace.semantic_label,
                    };
                }

                fn buildSuspended(session: *Session, current: Session.Current, reason: Handler.StopReason) Error!?ExecutionResult {
                    const parked_kind = switch (current) {
                        .request => Session.ParkedKind.operation,
                        .after => Session.ParkedKind.after,
                        .none => return error.ProgramContractViolation,
                    };
                    var capsule = try session.capture(lowered_machine.runtimeAllocator(session.runtime));
                    errdefer capsule.deinit();
                    const capsule_fingerprint = capsule.fingerprint();
                    return .{ .suspended = .{
                        .reason = reason,
                        .capsule = capsule,
                        .parked_kind = parked_kind,
                        .trace = try traceFor(current),
                        .request_fingerprint = try fingerprintFor(current),
                        .capsule_fingerprint = capsule_fingerprint,
                    } };
                }

                fn buildUnhandled(session: *Session, current: Session.Current, reason: Handler.StopReason) Error!?ExecutionResult {
                    const parked_kind = switch (current) {
                        .request => Session.ParkedKind.operation,
                        .after => Session.ParkedKind.after,
                        .none => return error.ProgramContractViolation,
                    };
                    var capsule = try session.capture(lowered_machine.runtimeAllocator(session.runtime));
                    errdefer capsule.deinit();
                    const capsule_fingerprint = capsule.fingerprint();
                    return .{ .unhandled = .{
                        .reason = reason,
                        .capsule = capsule,
                        .parked_kind = parked_kind,
                        .trace = try traceFor(current),
                        .request_fingerprint = try fingerprintFor(current),
                        .capsule_fingerprint = capsule_fingerprint,
                    } };
                }

                fn traceFor(current: Session.Current) Error!Handler.TraceView {
                    return switch (current) {
                        .request => |request| .{ .operation = request.trace() },
                        .after => |after_request| .{ .after = after_request.trace() },
                        .none => error.ProgramContractViolation,
                    };
                }

                fn fingerprintFor(current: Session.Current) Error!u64 {
                    return switch (current) {
                        .request => |request| request.fingerprint(),
                        .after => |after_request| after_request.fingerprint(),
                        .none => error.ProgramContractViolation,
                    };
                }
            };
        }

        fn validateInterpreterEntries(comptime entries: anytype) void {
            inline for (entries, 0..) |Entry, index| {
                if (!hasDeclSafe(Entry, "kind") or !hasDeclSafe(Entry, "function")) {
                    @compileError("Program.Interpreter entries must be Program.Handler declarations");
                }
                switch (Entry.kind) {
                    .operation, .after => {
                        if (!hasDeclSafe(Entry, "Site")) @compileError("Program.Interpreter entries must be Program.Handler declarations");
                        Handler.validateAnySite(Entry.Site);
                        inline for (entries, 0..) |Prior, prior_index| {
                            if (prior_index < index and Prior.kind == Entry.kind and Prior.Site.index == Entry.Site.index and Prior.Site.fingerprint == Entry.Site.fingerprint) {
                                @compileError("Program.Interpreter listed duplicate handler for site");
                            }
                        }
                    },
                    .protocol_operation => {
                        if (!hasDeclSafe(Entry, "TargetOp")) @compileError("Program.Interpreter entries must be Program.Handler declarations");
                        validateProtocolOperationDescriptor(Entry.TargetOp);
                        inline for (entries, 0..) |Prior, prior_index| {
                            if (prior_index < index and Prior.kind == .protocol_operation and Prior.TargetOp.fingerprint == Entry.TargetOp.fingerprint) {
                                @compileError("Program.Interpreter listed duplicate protocol operation handler");
                            }
                        }
                    },
                    else => @compileError("Program.Interpreter entries must be Program.Handler declarations"),
                }
            }
        }

        fn assertInterpreterCoversAll(comptime entries: anytype) void {
            var operation_covered: [protocol.operation_site_count]bool = [_]bool{false} ** protocol.operation_site_count;
            var after_covered: [protocol.after_site_count]bool = [_]bool{false} ** protocol.after_site_count;
            inline for (entries) |Entry| {
                switch (Entry.kind) {
                    .operation, .after => Handler.validateAnySite(Entry.Site),
                    .protocol_operation => continue,
                    else => @compileError("Program.Interpreter entries must be Program.Handler declarations"),
                }
                switch (Entry.kind) {
                    .operation => {
                        if (Entry.Site.index >= protocol.operation_site_count or protocol.operation_site_metadata[Entry.Site.index].fingerprint != Entry.Site.fingerprint) {
                            @compileError("Program.Interpreter coverage descriptor belongs to another program");
                        }
                        if (operation_covered[Entry.Site.index]) @compileError("Program.Interpreter listed duplicate handler for site");
                        operation_covered[Entry.Site.index] = true;
                    },
                    .after => {
                        if (Entry.Site.index >= protocol.after_site_count or protocol.after_site_metadata[Entry.Site.index].fingerprint != Entry.Site.fingerprint) {
                            @compileError("Program.Interpreter coverage descriptor belongs to another program");
                        }
                        if (after_covered[Entry.Site.index]) @compileError("Program.Interpreter listed duplicate handler for site");
                        after_covered[Entry.Site.index] = true;
                    },
                    else => {},
                }
            }
            inline for (operation_covered) |is_covered| {
                if (!is_covered) @compileError("Program.Interpreter coverage omitted reachable operation site");
            }
            inline for (after_covered) |is_covered| {
                if (!is_covered) @compileError("Program.Interpreter coverage omitted reachable after site");
            }
        }
    };
}

test "program rejects empty labels" {
    _ = program;
}

test "ability.program preserves bounded error set for bodies without user errors" {
    const program_plan = @import("internal_program_plan");
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "run",
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = 0,
    }};
    const blocks = [_]program_plan.BlockPlan{.{
        .first_instruction = 0,
        .instruction_count = 0,
        .terminator_index = 0,
    }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_unit }};
    const body = struct {
        /// Runtime plan with no user-declared error path.
        pub const compiled_plan = program_plan.ProgramPlan{
            .label = "no-user-error",
            .ir_hash = 1,
            .entry_index = 0,
            .functions = &functions,
            .requirements = &.{},
            .ops = &.{},
            .outputs = &.{},
            .blocks = &blocks,
            .terminators = &terminators,
            .instructions = &.{},
        };
    };
    const program_type = program("no-user-error", struct {}, body);

    try std.testing.expect(program_type.Error == lowered_machine.ResetError(error{}));

    const forwarder = struct {
        fn run(runtime: *lowered_machine.Runtime) lowered_machine.ResetError(error{})!void {
            var result = try program_type.run(runtime, .{});
            defer result.deinit();
        }
    };

    var runtime = lowered_machine.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    try forwarder.run(&runtime);
}

test "Program.contract session support includes executable blockers" {
    const program_plan = @import("internal_program_plan");
    const root = program_plan.program_plan_builder.function(0);
    const payload = program_plan.program_plan_builder.local(root, 0);
    const instructions = [_]program_plan.Instruction{
        program_plan.program_plan_builder.callOp(root, null, program_plan.program_plan_builder.op(root, 0), payload) catch unreachable,
    };
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "run",
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
        .instruction_count = @intCast(instructions.len),
    }};
    const requirements = [_]program_plan.RequirementPlan{.{
        .label = "structured",
        .first_op = 0,
        .op_count = 1,
    }};
    const ops = [_]program_plan.OpPlan{.{
        .requirement_index = 0,
        .op_name = "structured",
        .mode = .transform,
        .payload_codec = .product,
        .payload_schema_index = 0,
        .resume_codec = .unit,
    }};
    const value_schemas = [_]program_plan.ValueSchemaPlan{.{
        .label = "Payload",
        .codec = .product,
        .first_field = 0,
        .field_count = 1,
    }};
    const value_fields = [_]program_plan.ValueFieldPlan{.{ .name = "value", .codec = .i32 }};
    const locals = [_]program_plan.LocalPlan{.{ .codec = .product, .schema_index = 0 }};
    const blocks = [_]program_plan.BlockPlan{.{ .first_instruction = 0, .instruction_count = @intCast(instructions.len), .terminator_index = 0 }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_unit }};
    const plan = program_plan.program_plan_builder.finish(.{
        .label = "contract-session-executable-blocked",
        .ir_hash = 2,
        .entry = root,
        .functions = &functions,
        .requirements = &requirements,
        .ops = &ops,
        .outputs = &.{},
        .value_schemas = &value_schemas,
        .value_fields = &value_fields,
        .value_variants = &.{},
        .locals = &locals,
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    }) catch unreachable;

    const contract = ProgramContractFor("contract-session-executable-blocked", plan, void, void, &.{}, &.{}, .{});
    try std.testing.expect(!contract.executable.supported);
    try std.testing.expectEqual(@as(usize, 1), contract.executable.blocker_count);
    try std.testing.expect(!contract.session.supported);
    try std.testing.expectEqual(@as(usize, 1), contract.session.blocker_count);
    try std.testing.expectEqual(@as(?lowering_api.SessionBlockerTag, .payload_codec), contract.session.first_blocker_tag);
    try std.testing.expectEqualStrings(
        "session capability ledger: blockers=1 truncated=false cap=64 first_tag=payload_codec first_function=0 first_instruction=0 first_op=65535",
        contract.session.summary,
    );
}

test "ability.program executable support rejects nested-with plans" {
    const program_plan = @import("internal_program_plan");
    const instructions = [_]program_plan.Instruction{.{
        .kind = .call_nested_with,
        .aux = @intFromEnum(program_plan.ValueCodec.unit),
        .string_literal = "a\x1fb\x1fc\x1fd\x1fe\x1ff\x1fg\x1fh\x1fi",
    }};
    const functions = [_]program_plan.FunctionPlan{.{
        .symbol_name = "run",
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
    }};
    const blocks = [_]program_plan.BlockPlan{.{
        .first_instruction = 0,
        .instruction_count = @intCast(instructions.len),
        .terminator_index = 0,
    }};
    const terminators = [_]program_plan.Terminator{.{ .kind = .return_unit }};
    const nested_with_plan = program_plan.ProgramPlan{
        .label = "nested-with",
        .ir_hash = 1,
        .entry_index = 0,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &instructions,
    };

    try nested_with_plan.validate();
    try std.testing.expectError(
        error.UnsupportedNestedWith,
        lowering_api.validateExecutablePlanSupport(nested_with_plan),
    );
}
