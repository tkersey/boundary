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

fn ProgramValueRefMatchesType(comptime schema_types: anytype, comptime ref: lowering_api.ValueRef, comptime ValueType: type) bool {
    const codec = comptime ProgramValueCodecForType(ValueType);
    if (ref.codec != codec) return false;
    return switch (codec) {
        .product, .sum => {
            const schema_index = ref.schema_index orelse return false;
            if (schema_index >= schema_types.len) return false;
            return schema_types[schema_index] == ValueType;
        },
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

fn typeMayBorrowExchangeStorage(comptime T: type) bool {
    if (T == []const u8 or T == []const []const u8 or T == [][]const u8) return true;
    return switch (@typeInfo(T)) {
        .optional => |optional| typeMayBorrowExchangeStorage(optional.child),
        .@"struct" => |info| {
            inline for (info.fields) |field| {
                if (typeMayBorrowExchangeStorage(field.type)) return true;
            }
            return false;
        },
        .@"union" => |info| {
            inline for (info.fields) |field| {
                if (typeMayBorrowExchangeStorage(field.type)) return true;
            }
            return false;
        },
        else => false,
    };
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
        /// Stable format version for Program.Session.Capsule durable images.
        pub const capsule_image_format_version: u32 = 1;
        /// Stable fingerprint version for Program.Session.Capsule durable images.
        pub const capsule_image_fingerprint_version: u32 = 1;
        /// Stable format version for Program.Session interaction journals.
        pub const journal_format_version: u32 = 2;
        /// Stable fingerprint version for Program.Session interaction journals.
        pub const journal_fingerprint_version: u32 = 1;
        /// Stable format version for Program.Exchange manifest images.
        pub const exchange_manifest_format_version: u32 = 1;
        /// Stable fingerprint version for Program.Exchange manifest images.
        pub const exchange_manifest_fingerprint_version: u32 = 1;
        /// Stable format version for Program.Exchange request envelopes.
        pub const exchange_request_format_version: u32 = 2;
        /// Stable fingerprint version for Program.Exchange request envelopes.
        pub const exchange_request_fingerprint_version: u32 = 1;
        /// Stable format version for Program.Exchange response envelopes.
        pub const exchange_response_format_version: u32 = 1;
        /// Stable fingerprint version for Program.Exchange response envelopes.
        pub const exchange_response_fingerprint_version: u32 = 1;
        /// Stable format version for Program.Exchange provider manifest images.
        pub const exchange_provider_format_version: u32 = 1;
        /// Stable fingerprint version for Program.Exchange provider manifest images.
        pub const exchange_provider_fingerprint_version: u32 = 1;
        /// Stable format version for Program.Exchange capability grant images.
        pub const exchange_capability_format_version: u32 = 1;
        /// Stable fingerprint version for Program.Exchange capability grant images.
        pub const exchange_capability_fingerprint_version: u32 = 1;
        /// Stable fingerprint version for Program.Exchange authorization witnesses.
        pub const exchange_authorization_fingerprint_version: u32 = 1;
        /// Stable fingerprint version for Program.Exchange route witnesses.
        pub const exchange_route_fingerprint_version: u32 = 1;

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
            exchange_response_storage: ?*TrackedBodyResultStorage = null,

            const ExchangeSessionResultStorage = struct {
                allocator: std.mem.Allocator,
                core: ?ResultOwnedStorage,
                exchange: *TrackedBodyResultStorage,

                fn deinit(self: *@This()) void {
                    if (self.core) |*storage| storage.deinit();
                    self.exchange.deinit();
                    self.allocator.destroy(self.exchange);
                }
            };

            fn deinitExchangeResponseStorage(allocator: std.mem.Allocator, storage: *?*TrackedBodyResultStorage) void {
                if (storage.*) |owned| {
                    owned.deinit();
                    allocator.destroy(owned);
                    storage.* = null;
                }
            }

            fn takeExchangeResponseStorage(self: *Session) ?*TrackedBodyResultStorage {
                const storage = self.exchange_response_storage;
                self.exchange_response_storage = null;
                return storage;
            }

            fn attachExchangeResponseStorageToResult(
                allocator: std.mem.Allocator,
                result: *Result,
                storage: *?*TrackedBodyResultStorage,
            ) Error!void {
                const exchange = storage.* orelse return;
                const boxed = allocator.create(ExchangeSessionResultStorage) catch |err| return mapProgramRunError(Error, err);
                boxed.* = .{
                    .allocator = allocator,
                    .core = result._session_storage,
                    .exchange = exchange,
                };
                armExchangeResponseCleanupAllocator(result, exchange);
                result._session_storage = .{
                    .allocator = allocator,
                    .ptr = boxed,
                    .destroy = ResultStorageDestroyer(ExchangeSessionResultStorage).destroy,
                };
                storage.* = null;
            }

            fn armExchangeResponseCleanupAllocator(result: *Result, exchange: *TrackedBodyResultStorage) void {
                if (comptime bodyDeinitResultMode(Body, Value, ProgramOutputs) != .none) {
                    if (result._result_cleanup_allocator == null) {
                        result._result_cleanup_allocator = exchange.tracker.allocator();
                    }
                }
            }

            fn ensureExchangeResponseStorage(self: *Session, allocator: std.mem.Allocator) Error!*TrackedBodyResultStorage {
                if (self.exchange_response_storage) |storage| return storage;
                const storage = allocator.create(TrackedBodyResultStorage) catch |err| return mapProgramRunError(Error, err);
                storage.* = .{ .tracker = TrackedResultAllocator.init(allocator) };
                self.exchange_response_storage = storage;
                return storage;
            }

            fn storeExchangeResponseValue(self: *Session, value: anytype) Error!@TypeOf(value) {
                const ValueType = @TypeOf(value);
                if (comptime !typeMayBorrowExchangeStorage(ValueType)) return value;

                const allocator = lowered_machine.runtimeAllocator(self.runtime);
                const storage = try self.ensureExchangeResponseStorage(allocator);
                const cleanup_allocator = storage.tracker.allocator();
                return cloneBodyOwnedResultValue(cleanup_allocator, value) catch |err| return mapProgramRunError(Error, err);
            }

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

            fn finishSessionResult(
                allocator: std.mem.Allocator,
                handlers: anytype,
                raw: *Core.RawResult,
                result_cleanup_allocator: ?std.mem.Allocator,
            ) Error!Result {
                const result_cleanup = comptime bodyDeinitResultMode(Body, Value, ProgramOutputs);
                if (result_cleanup != .none) {
                    var storage = raw.takeStorage();
                    defer if (storage) |*owned| owned.deinit();
                    if (storage != null) {
                        const owned = cloneBodyOwnedResultWithTrackedStorage(Value, allocator, raw.value) catch |err| return mapProgramRunError(Error, err);
                        return finishResultWithStorage(allocator, handlers, owned.value, owned.storage, owned.cleanup_allocator);
                    }
                    return finishResultWithStorage(allocator, handlers, raw.value, null, result_cleanup_allocator);
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
            /// Durable capsule image format version.
            pub const capsule_image_format_version = Core.capsule_image_format_version;
            /// Durable capsule image fingerprint version.
            pub const capsule_image_fingerprint_version = Core.capsule_image_fingerprint_version;
            const session_journal_format_version: u32 = 2;
            const session_journal_fingerprint_version = Core.journal_fingerprint_version;
            /// Durable interaction journal format version.
            pub const journal_format_version = session_journal_format_version;
            /// Durable interaction journal fingerprint version.
            pub const journal_fingerprint_version = session_journal_fingerprint_version;
            /// Current parked request view without advancing the interpreter.
            pub const Current = Core.Current;
            /// First-class in-process snapshot of a parked continuation.
            pub const Capsule = struct {
                _core: Core.Capsule,

                /// Owned deterministic byte image of a reusable parked continuation capsule.
                pub const Image = struct {
                    allocator: std.mem.Allocator,
                    bytes: []u8,
                    image_fingerprint: u64,
                    image_version: u32 = Core.capsule_image_format_version,
                    capsule_version: u32 = Session.capsule_version,
                    continuation_fingerprint_version: u32 = Session.continuation_fingerprint_version,
                    trace_fingerprint_version: u32 = Trace.fingerprint_version,
                    program_label: []const u8 = label,
                    plan_label: []const u8 = body_compiled_plan.label,
                    plan_hash: u64 = body_compiled_plan_hash,
                    capsule_fingerprint: u64,
                    continuation_fingerprint: u64,
                    parked_kind: ParkedKind,
                    current_request_fingerprint: u64,
                    semantic_label: ?[]const u8 = null,
                    metadata: CapsuleMetadata,

                    /// Encode an owned image from an in-process capsule.
                    pub fn fromCapsule(allocator: std.mem.Allocator, capsule: *const Capsule) Error!@This() {
                        const bytes = capsule._core.encode(allocator) catch |err| return mapProgramRunError(Error, err);
                        errdefer allocator.free(bytes);
                        const capsule_metadata = capsule.metadata();
                        return .{
                            .allocator = allocator,
                            .bytes = bytes,
                            .image_fingerprint = capsuleImageFingerprint(bytes),
                            .capsule_fingerprint = capsule.fingerprint(),
                            .continuation_fingerprint = capsule_metadata.continuation_fingerprint,
                            .parked_kind = capsule_metadata.parked_kind,
                            .current_request_fingerprint = capsule_metadata.current_request_fingerprint,
                            .semantic_label = semanticLabelForCapsuleMetadata(capsule_metadata),
                            .metadata = capsule_metadata,
                        };
                    }

                    /// Release image-owned bytes.
                    pub fn deinit(self: *@This()) void {
                        self.allocator.free(self.bytes);
                        self.bytes = &.{};
                    }
                };

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

                /// Encode this reusable capsule into deterministic owned bytes plus metadata.
                pub fn encode(self: *const @This(), allocator: std.mem.Allocator) Error!Image {
                    return Image.fromCapsule(allocator, self);
                }

                /// Decode deterministic capsule image bytes into an owned reusable capsule.
                pub fn decode(allocator: std.mem.Allocator, image_bytes: []const u8) Error!@This() {
                    return .{
                        ._core = Core.Capsule.decode(allocator, image_bytes) catch |err| return mapProgramRunError(Error, err),
                    };
                }
            };

            fn capsuleImageFingerprint(image_bytes: []const u8) u64 {
                var hasher = std.hash.Wyhash.init(0);
                hashBytes(&hasher, "ability.program.capsule.image");
                hashU32(&hasher, Core.capsule_image_fingerprint_version);
                hashBytes(&hasher, image_bytes);
                return hasher.final();
            }

            fn semanticLabelForCapsuleMetadata(metadata: CapsuleMetadata) ?[]const u8 {
                return switch (metadata.parked_kind) {
                    .operation => blk: {
                        const site_index = metadata.current_operation_site_index orelse break :blk null;
                        inline for (protocol.operation_site_metadata) |site| {
                            if (site.index == site_index) break :blk site.semantic_label;
                        }
                        break :blk null;
                    },
                    .after => blk: {
                        const site_index = metadata.current_after_site_index orelse break :blk null;
                        inline for (protocol.after_site_metadata) |site| {
                            if (site.index == site_index) break :blk site.semantic_label;
                        }
                        break :blk null;
                    },
                };
            }

            /// One session step: either a terminal result, yielded operation request, or yielded after continuation.
            pub const Step = union(enum) {
                after: AfterRequest,
                done: Result,
                request: Request,
            };

            /// Deterministic host-owned interaction transcript for request/response replay validation.
            pub const Journal = struct {
                allocator: std.mem.Allocator,
                entries: std.ArrayList(Entry) = .empty,

                /// Request-side trace entry recorded before a host response.
                pub const RequestTrace = union(enum) {
                    operation: Trace.OperationRequest,
                    after: Trace.AfterRequest,

                    /// Return the request fingerprint for operation or after entries.
                    pub fn fingerprint(self: @This()) u64 {
                        return switch (self) {
                            .operation => |trace| trace.fingerprint,
                            .after => |trace| trace.fingerprint,
                        };
                    }
                };

                /// One deterministic journal entry.
                pub const Entry = union(enum) {
                    request: RequestTrace,
                    response: ResponseEntry,
                    capsule_image: CapsuleImageEntry,
                    exchange_event: ExchangeEvent,
                    done: u64,
                };

                /// Response trace plus an optional replayable typed value image.
                pub const ResponseEntry = struct {
                    trace: Trace.Response,
                    value_image: ?[]u8 = null,
                };

                /// Owned capsule image entry copied into a journal.
                pub const CapsuleImageEntry = struct {
                    image_fingerprint: u64,
                    capsule_fingerprint: u64,
                    current_request_fingerprint: u64,
                    bytes: []u8,
                };

                /// Inspectable Effect Exchange capability/routing ledger entry.
                pub const ExchangeEvent = struct {
                    kind: Kind,
                    provider_fingerprint: ?u64 = null,
                    capability_fingerprint: ?u64 = null,
                    route_fingerprint: ?u64 = null,
                    authorization_fingerprint: ?u64 = null,
                    request_envelope_fingerprint: ?u64 = null,
                    response_envelope_fingerprint: ?u64 = null,
                    blocker_tag: ?[]const u8 = null,

                    /// Exchange ledger event kind.
                    pub const Kind = enum {
                        provider_manifest_recorded,
                        capability_granted,
                        capability_attenuated,
                        route_selected,
                        route_blocked,
                        response_authorized,
                        response_rejected,
                    };
                };

                /// Append-only recorder used by interpreters and host code.
                pub const Recorder = struct {
                    journal: *Journal,

                    /// Record a request/response pair without a typed response value image.
                    pub fn record(self: *@This(), request_trace: anytype, response_trace: Trace.Response) Error!void {
                        const request = requestTraceFromAny(request_trace);
                        try validateJournalResponseForRequest(request, response_trace);
                        const start_len = self.journal.entries.items.len;
                        errdefer self.journal.truncateEntries(start_len);
                        try self.journal.appendRequest(request);
                        try self.journal.appendResponse(response_trace);
                    }

                    /// Record a request/response pair with a replayable typed response value image.
                    pub fn recordValue(self: *@This(), request_trace: anytype, response_trace: Trace.Response, value: anytype) Error!void {
                        const request = requestTraceFromAny(request_trace);
                        try validateJournalResponseForRequest(request, response_trace);
                        const start_len = self.journal.entries.items.len;
                        errdefer self.journal.truncateEntries(start_len);
                        try self.journal.appendRequest(request);
                        try self.journal.appendResponseValue(response_trace, value);
                    }
                };

                /// Cursor that validates fresh yielded requests against recorded journal entries.
                pub const Replayer = struct {
                    journal: *const Journal,
                    index: usize = 0,
                    string_lists: std.ArrayList([]const []const u8) = .empty,

                    /// Release replay-owned decoded slice tables.
                    pub fn deinit(self: *@This()) void {
                        for (self.string_lists.items) |items| self.journal.allocator.free(items);
                        self.string_lists.deinit(self.journal.allocator);
                    }

                    /// Validate the current request and return the matching recorded response trace.
                    pub fn expectCurrent(self: *@This(), current_value: Current) Error!Trace.Response {
                        return (try self.expectCurrentEntry(current_value)).trace;
                    }

                    /// Validate the current request and decode the matching recorded response value.
                    pub fn expectCurrentValue(self: *@This(), current_value: Current, comptime ValueType: type) Error!ValueType {
                        const replayed = try self.expectCurrentResponseValue(current_value, ValueType);
                        return replayed.value;
                    }

                    /// Validate the current request and decode its recorded response trace and value.
                    pub fn expectCurrentResponseValue(
                        self: *@This(),
                        current_value: Current,
                        comptime ValueType: type,
                    ) Error!struct { trace: Trace.Response, value: ValueType } {
                        const response = try self.expectCurrentEntry(current_value);
                        const value_image = response.value_image orelse return error.ProgramContractViolation;
                        return .{
                            .trace = response.trace,
                            .value = decodeJournalResponseValue(self, ValueType, response.trace, value_image) catch |err| return mapProgramRunError(Error, err),
                        };
                    }

                    /// Validate the recorded terminal result fingerprint and require replay EOF.
                    pub fn expectDone(self: *@This(), result_fingerprint: u64) Error!void {
                        const done_entry = self.nextReplayEntry() orelse return error.ProgramContractViolation;
                        const recorded = switch (done_entry) {
                            .done => |recorded_fingerprint| recorded_fingerprint,
                            else => return error.ProgramContractViolation,
                        };
                        if (recorded != result_fingerprint) return error.ProgramContractViolation;
                        try self.drainSkippableReplayEntries();
                        if (self.index != self.journal.entries.items.len) return error.ProgramContractViolation;
                    }

                    fn expectCurrentEntry(self: *@This(), current_value: Current) Error!ResponseEntry {
                        const request_entry = self.nextReplayEntry() orelse return error.ProgramContractViolation;
                        const request_trace = switch (request_entry) {
                            .request => |request_trace| request_trace,
                            else => return error.ProgramContractViolation,
                        };
                        const expected = request_trace.fingerprint();
                        const actual = switch (current_value) {
                            .request => |request| request.fingerprint(),
                            .after => |after_request| after_request.fingerprint(),
                            .none => return error.ProgramContractViolation,
                        };
                        if (actual != expected) return error.ProgramContractViolation;
                        const response_entry = self.nextReplayEntry() orelse return error.ProgramContractViolation;
                        const response = switch (response_entry) {
                            .response => |response| response,
                            else => return error.ProgramContractViolation,
                        };
                        try validateJournalResponseForRequest(request_trace, response.trace);
                        return response;
                    }

                    fn nextReplayEntry(self: *@This()) ?Entry {
                        if (self.index >= self.journal.entries.items.len) return null;
                        while (self.index < self.journal.entries.items.len) {
                            const entry = self.journal.entries.items[self.index];
                            self.index += 1;
                            switch (entry) {
                                .capsule_image => continue,
                                .exchange_event => continue,
                                else => return entry,
                            }
                        }
                        return null;
                    }

                    fn drainSkippableReplayEntries(self: *@This()) Error!void {
                        while (self.index < self.journal.entries.items.len) {
                            switch (self.journal.entries.items[self.index]) {
                                .capsule_image, .exchange_event => self.index += 1,
                                else => return error.ProgramContractViolation,
                            }
                        }
                    }
                };

                fn validateJournalResponseForRequest(request_trace: RequestTrace, response: Trace.Response) Error!void {
                    if (response.request_fingerprint != request_trace.fingerprint()) return error.ProgramContractViolation;
                    try validateJournalResponseTrace(response);
                    switch (request_trace) {
                        .operation => |request| switch (response.kind) {
                            .@"resume" => {
                                if (request.mode == .abort) return error.ProgramContractViolation;
                                if (!response.response_ref.eql(request.resume_ref)) return error.ProgramContractViolation;
                            },
                            .return_now => {
                                if (request.mode == .transform) return error.ProgramContractViolation;
                                if (!response.response_ref.eql(request.result_ref)) return error.ProgramContractViolation;
                            },
                            .resume_after => return error.ProgramContractViolation,
                        },
                        .after => |request| {
                            if (response.kind != .resume_after) return error.ProgramContractViolation;
                            if (!response.response_ref.eql(request.expected_output_ref)) return error.ProgramContractViolation;
                        },
                    }
                }

                fn validateJournalResponseTrace(response: Trace.Response) Error!void {
                    if (response.fingerprint != fingerprintJournalResponseTrace(response)) return error.ProgramContractViolation;
                }

                fn validateJournalCapsuleImage(allocator: std.mem.Allocator, image: Capsule.Image) Error!void {
                    if (image.image_fingerprint != capsuleImageFingerprint(image.bytes)) return error.ProgramContractViolation;
                    var decoded = Core.Capsule.decode(allocator, image.bytes) catch |err| return mapProgramRunError(Error, err);
                    defer decoded.deinit();
                    const metadata = decoded.metadata();
                    if (image.capsule_fingerprint != decoded.fingerprint() or
                        image.current_request_fingerprint != metadata.current_request_fingerprint)
                    {
                        return error.ProgramContractViolation;
                    }
                }

                fn validateJournalRequestTrace(request_trace: RequestTrace) Error!void {
                    switch (request_trace) {
                        .operation => |request| {
                            if (request.has_payload != (request.payload_ref.codec != .unit)) return error.ProgramContractViolation;
                            if (request.fingerprint != fingerprintJournalOperationRequestTrace(request)) return error.ProgramContractViolation;
                        },
                        .after => |request| {
                            if (request.fingerprint != fingerprintJournalAfterRequestTrace(request)) return error.ProgramContractViolation;
                        },
                    }
                }

                /// Create an empty host-owned journal.
                pub fn init(allocator: std.mem.Allocator) @This() {
                    return .{ .allocator = allocator };
                }

                /// Release all journal-owned entries and byte images.
                pub fn deinit(self: *@This()) void {
                    for (self.entries.items) |*entry| deinitJournalEntry(self.allocator, entry);
                    self.entries.deinit(self.allocator);
                }

                fn truncateEntries(self: *@This(), len: usize) void {
                    for (self.entries.items[len..]) |*entry| deinitJournalEntry(self.allocator, entry);
                    self.entries.shrinkRetainingCapacity(len);
                }

                /// Return an interpreter-compatible journal recorder.
                pub fn recorder(self: *@This()) Recorder {
                    return .{ .journal = self };
                }

                /// Return a replay cursor starting at the first entry.
                pub fn replayer(self: *const @This()) Replayer {
                    return .{ .journal = self };
                }

                /// Append an owned copy of a request trace.
                pub fn appendRequest(self: *@This(), trace: RequestTrace) Error!void {
                    try validateJournalRequestTrace(trace);
                    var owned = cloneJournalRequestTrace(self.allocator, trace) catch |err| return mapProgramRunError(Error, err);
                    errdefer deinitJournalRequestTrace(self.allocator, &owned);
                    self.entries.append(self.allocator, .{ .request = owned }) catch |err| return mapProgramRunError(Error, err);
                }

                /// Append a response trace without a typed value image.
                pub fn appendResponse(self: *@This(), trace: Trace.Response) Error!void {
                    try validateJournalResponseTrace(trace);
                    self.entries.append(self.allocator, .{ .response = .{ .trace = trace } }) catch |err| return mapProgramRunError(Error, err);
                }

                /// Append a response trace with a deterministic typed value image.
                pub fn appendResponseValue(self: *@This(), trace: Trace.Response, value: anytype) Error!void {
                    try validateJournalResponseTrace(trace);
                    const value_image = encodeJournalResponseValue(self.allocator, trace, value) catch |err| return mapProgramRunError(Error, err);
                    errdefer self.allocator.free(value_image);
                    self.entries.append(self.allocator, .{ .response = .{
                        .trace = trace,
                        .value_image = value_image,
                    } }) catch |err| return mapProgramRunError(Error, err);
                }

                fn appendValidatedResponseValueImage(self: *@This(), trace: Trace.Response, value_image: []const u8) Error!void {
                    try validateJournalResponseTrace(trace);
                    const owned = self.allocator.dupe(u8, value_image) catch |err| return mapProgramRunError(Error, err);
                    errdefer self.allocator.free(owned);
                    self.entries.append(self.allocator, .{ .response = .{
                        .trace = trace,
                        .value_image = owned,
                    } }) catch |err| return mapProgramRunError(Error, err);
                }

                /// Append an owned copy of a durable capsule image.
                pub fn appendCapsuleImage(self: *@This(), image: Capsule.Image) Error!void {
                    try validateJournalCapsuleImage(self.allocator, image);
                    const bytes = self.allocator.dupe(u8, image.bytes) catch |err| return mapProgramRunError(Error, err);
                    errdefer self.allocator.free(bytes);
                    self.entries.append(self.allocator, .{ .capsule_image = .{
                        .image_fingerprint = image.image_fingerprint,
                        .capsule_fingerprint = image.capsule_fingerprint,
                        .current_request_fingerprint = image.current_request_fingerprint,
                        .bytes = bytes,
                    } }) catch |err| return mapProgramRunError(Error, err);
                }

                /// Append a terminal result fingerprint.
                pub fn appendDone(self: *@This(), result_fingerprint: u64) Error!void {
                    self.entries.append(self.allocator, .{ .done = result_fingerprint }) catch |err| return mapProgramRunError(Error, err);
                }

                /// Append an exchange capability/routing event.
                pub fn appendExchangeEvent(self: *@This(), event: ExchangeEvent) Error!void {
                    const owned_tag = if (event.blocker_tag) |tag| self.allocator.dupe(u8, tag) catch |err| return mapProgramRunError(Error, err) else null;
                    errdefer if (owned_tag) |tag| self.allocator.free(tag);
                    var owned = event;
                    owned.blocker_tag = owned_tag;
                    self.entries.append(self.allocator, .{ .exchange_event = owned }) catch |err| return mapProgramRunError(Error, err);
                }

                /// Record that a provider manifest was observed by the host ledger.
                pub fn appendProviderManifestRecorded(self: *@This(), provider_fingerprint: u64) Error!void {
                    try self.appendExchangeEvent(.{ .kind = .provider_manifest_recorded, .provider_fingerprint = provider_fingerprint });
                }

                /// Record that a capability was granted.
                pub fn appendCapabilityGranted(self: *@This(), capability_fingerprint: u64, provider_fingerprint: u64) Error!void {
                    try self.appendExchangeEvent(.{
                        .kind = .capability_granted,
                        .provider_fingerprint = provider_fingerprint,
                        .capability_fingerprint = capability_fingerprint,
                    });
                }

                /// Record that a capability was attenuated.
                pub fn appendCapabilityAttenuated(self: *@This(), capability_fingerprint: u64, provider_fingerprint: u64) Error!void {
                    try self.appendExchangeEvent(.{
                        .kind = .capability_attenuated,
                        .provider_fingerprint = provider_fingerprint,
                        .capability_fingerprint = capability_fingerprint,
                    });
                }

                /// Encode the journal to deterministic owned bytes.
                pub fn encode(self: *const @This(), allocator: std.mem.Allocator) Error![]u8 {
                    var writer = ExchangeByteWriter.init(allocator);
                    errdefer writer.deinit();
                    writer.writeBytes("ABL_JRN1") catch |err| return mapProgramRunError(Error, err);
                    writer.writeU32(session_journal_format_version) catch |err| return mapProgramRunError(Error, err);
                    writer.writeU32(session_journal_fingerprint_version) catch |err| return mapProgramRunError(Error, err);
                    writer.writeUsize(self.entries.items.len) catch |err| return mapProgramRunError(Error, err);
                    for (self.entries.items) |entry| {
                        writeJournalEntry(&writer, entry) catch |err| return mapProgramRunError(Error, err);
                    }
                    const payload = writer.bytes.items;
                    writer.writeU64(journalFingerprintBytes(payload)) catch |err| return mapProgramRunError(Error, err);
                    return writer.toOwnedSlice() catch |err| return mapProgramRunError(Error, err);
                }

                /// Decode deterministic journal bytes into an owned journal.
                pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) Error!@This() {
                    if (bytes.len < "ABL_JRN1".len + 4 + 4 + 8) return error.ProgramContractViolation;
                    const payload = bytes[0 .. bytes.len - 8];
                    const checksum = std.mem.readInt(u64, bytes[bytes.len - 8 ..][0..8], .little);
                    if (checksum != journalFingerprintBytes(payload)) return error.ProgramContractViolation;
                    var reader = ExchangeByteReader.init(payload);
                    try reader.expectBytes("ABL_JRN1");
                    const format_version = try reader.readU32();
                    if (format_version != 1 and format_version != session_journal_format_version) return error.ProgramContractViolation;
                    if (try reader.readU32() != session_journal_fingerprint_version) return error.ProgramContractViolation;
                    var journal = Journal.init(allocator);
                    errdefer journal.deinit();
                    const count = try reader.readUsize();
                    for (0..count) |_| {
                        var entry = readJournalEntry(&reader, allocator, format_version) catch |err| return mapProgramRunError(Error, err);
                        errdefer deinitJournalEntry(allocator, &entry);
                        journal.entries.append(allocator, entry) catch |err| return mapProgramRunError(Error, err);
                    }
                    if (!reader.eof()) return error.ProgramContractViolation;
                    return journal;
                }

                /// Compute the journal fingerprint from its deterministic byte image.
                pub fn fingerprint(self: *const @This()) Error!u64 {
                    const bytes = try self.encode(self.allocator);
                    defer self.allocator.free(bytes);
                    return journalFingerprintBytes(bytes);
                }
            };

            const ValueImageContext = struct {
                allocator: std.mem.Allocator,
                strings: std.ArrayList([]const u8) = .empty,
                string_lists: std.ArrayList([]const []const u8) = .empty,
                content_canonicalization: bool = false,

                fn init(allocator: std.mem.Allocator) @This() {
                    return .{ .allocator = allocator };
                }

                fn initCanonical(allocator: std.mem.Allocator) @This() {
                    return .{
                        .allocator = allocator,
                        .content_canonicalization = true,
                    };
                }

                fn deinit(self: *@This()) void {
                    self.strings.deinit(self.allocator);
                    self.string_lists.deinit(self.allocator);
                }

                fn stringIndex(self: *const @This(), value: []const u8) ?usize {
                    for (self.strings.items, 0..) |existing, index| {
                        if (self.content_canonicalization) {
                            if (std.mem.eql(u8, existing, value)) return index;
                        } else if (existing.ptr == value.ptr and existing.len == value.len) {
                            return index;
                        }
                    }
                    return null;
                }

                fn stringListIndex(self: *const @This(), value: []const []const u8) ?usize {
                    for (self.string_lists.items, 0..) |existing, index| {
                        if (self.content_canonicalization) {
                            if (stringListsEql(existing, value)) return index;
                        } else if (existing.ptr == value.ptr and existing.len == value.len) {
                            return index;
                        }
                    }
                    return null;
                }
            };

            fn stringListsEql(a: []const []const u8, b: []const []const u8) bool {
                if (a.len != b.len) return false;
                for (a, b) |a_item, b_item| {
                    if (!std.mem.eql(u8, a_item, b_item)) return false;
                }
                return true;
            }

            // Canonical deterministic byte helpers shared by journals and Effect Exchange envelopes.
            const ExchangeByteWriter = struct {
                allocator: std.mem.Allocator,
                bytes: std.ArrayList(u8) = .empty,

                fn init(allocator: std.mem.Allocator) @This() {
                    return .{ .allocator = allocator };
                }

                fn deinit(self: *@This()) void {
                    self.bytes.deinit(self.allocator);
                }

                fn toOwnedSlice(self: *@This()) std.mem.Allocator.Error![]u8 {
                    return self.bytes.toOwnedSlice(self.allocator);
                }

                fn writeBytes(self: *@This(), bytes: []const u8) std.mem.Allocator.Error!void {
                    try self.bytes.appendSlice(self.allocator, bytes);
                }

                fn writeLenBytes(self: *@This(), bytes: []const u8) std.mem.Allocator.Error!void {
                    try self.writeUsize(bytes.len);
                    try self.writeBytes(bytes);
                }

                fn writeBool(self: *@This(), value: bool) std.mem.Allocator.Error!void {
                    try self.bytes.append(self.allocator, @intFromBool(value));
                }

                fn writeU8(self: *@This(), value: u8) std.mem.Allocator.Error!void {
                    try self.bytes.append(self.allocator, value);
                }

                fn writeU16(self: *@This(), value: u16) std.mem.Allocator.Error!void {
                    var buffer: [2]u8 = undefined;
                    std.mem.writeInt(u16, &buffer, value, .little);
                    try self.writeBytes(&buffer);
                }

                fn writeU32(self: *@This(), value: u32) std.mem.Allocator.Error!void {
                    var buffer: [4]u8 = undefined;
                    std.mem.writeInt(u32, &buffer, value, .little);
                    try self.writeBytes(&buffer);
                }

                fn writeU64(self: *@This(), value: u64) std.mem.Allocator.Error!void {
                    var buffer: [8]u8 = undefined;
                    std.mem.writeInt(u64, &buffer, value, .little);
                    try self.writeBytes(&buffer);
                }

                fn writeUsize(self: *@This(), value: usize) std.mem.Allocator.Error!void {
                    try self.writeU64(@intCast(value));
                }
            };

            const ExchangeByteReader = struct {
                bytes: []const u8,
                index: usize = 0,

                fn init(bytes: []const u8) @This() {
                    return .{ .bytes = bytes };
                }

                fn eof(self: @This()) bool {
                    return self.index == self.bytes.len;
                }

                fn remaining(self: @This()) usize {
                    return self.bytes.len - self.index;
                }

                fn readBytes(self: *@This(), len: usize) error{ProgramContractViolation}![]const u8 {
                    const end = std.math.add(usize, self.index, len) catch return error.ProgramContractViolation;
                    if (end > self.bytes.len) return error.ProgramContractViolation;
                    const slice = self.bytes[self.index..end];
                    self.index = end;
                    return slice;
                }

                fn expectBytes(self: *@This(), expected: []const u8) error{ProgramContractViolation}!void {
                    if (!std.mem.eql(u8, try self.readBytes(expected.len), expected)) return error.ProgramContractViolation;
                }

                fn readLenBytes(self: *@This()) error{ProgramContractViolation}![]const u8 {
                    return self.readBytes(try self.readUsize());
                }

                fn readBool(self: *@This()) error{ProgramContractViolation}!bool {
                    return switch (try self.readU8()) {
                        0 => false,
                        1 => true,
                        else => error.ProgramContractViolation,
                    };
                }

                fn readU8(self: *@This()) error{ProgramContractViolation}!u8 {
                    return (try self.readBytes(1))[0];
                }

                fn readU16(self: *@This()) error{ProgramContractViolation}!u16 {
                    return std.mem.readInt(u16, (try self.readBytes(2))[0..2], .little);
                }

                fn readU32(self: *@This()) error{ProgramContractViolation}!u32 {
                    return std.mem.readInt(u32, (try self.readBytes(4))[0..4], .little);
                }

                fn readU64(self: *@This()) error{ProgramContractViolation}!u64 {
                    return std.mem.readInt(u64, (try self.readBytes(8))[0..8], .little);
                }

                fn readUsize(self: *@This()) error{ProgramContractViolation}!usize {
                    const value = try self.readU64();
                    if (value > std.math.maxInt(usize)) return error.ProgramContractViolation;
                    return @intCast(value);
                }
            };

            fn journalFingerprintBytes(bytes: []const u8) u64 {
                var hasher = std.hash.Wyhash.init(0);
                hashBytes(&hasher, "ability.program.session.journal");
                hashU32(&hasher, session_journal_fingerprint_version);
                hashBytes(&hasher, bytes);
                return hasher.final();
            }

            fn requestTraceFromAny(trace: anytype) Journal.RequestTrace {
                if (@TypeOf(trace) == Trace.OperationRequest) return .{ .operation = trace };
                if (@TypeOf(trace) == Trace.AfterRequest) return .{ .after = trace };
                @compileError("Journal recorder expected a Program.Session request or after trace");
            }

            fn cloneOptionalJournalLabel(allocator: std.mem.Allocator, label_value: ?[]const u8) std.mem.Allocator.Error!?[]u8 {
                if (label_value) |value| return try allocator.dupe(u8, value);
                return null;
            }

            fn cloneJournalRequestTrace(allocator: std.mem.Allocator, trace: Journal.RequestTrace) std.mem.Allocator.Error!Journal.RequestTrace {
                return switch (trace) {
                    .operation => |operation| blk: {
                        var owned = operation;
                        owned.semantic_label = try cloneOptionalJournalLabel(allocator, operation.semantic_label);
                        errdefer if (owned.semantic_label) |semantic_label| allocator.free(semantic_label);
                        owned.requirement_label = try allocator.dupe(u8, operation.requirement_label);
                        errdefer allocator.free(owned.requirement_label);
                        owned.op_name = try allocator.dupe(u8, operation.op_name);
                        break :blk .{ .operation = owned };
                    },
                    .after => |after| blk: {
                        var owned = after;
                        owned.semantic_label = try cloneOptionalJournalLabel(allocator, after.semantic_label);
                        errdefer if (owned.semantic_label) |semantic_label| allocator.free(semantic_label);
                        owned.original_requirement_label = try allocator.dupe(u8, after.original_requirement_label);
                        errdefer allocator.free(owned.original_requirement_label);
                        owned.original_op_name = try allocator.dupe(u8, after.original_op_name);
                        break :blk .{ .after = owned };
                    },
                };
            }

            fn deinitJournalRequestTrace(allocator: std.mem.Allocator, trace: *Journal.RequestTrace) void {
                switch (trace.*) {
                    .operation => |*operation| {
                        if (operation.semantic_label) |semantic_label| allocator.free(semantic_label);
                        allocator.free(operation.requirement_label);
                        allocator.free(operation.op_name);
                    },
                    .after => |*after| {
                        if (after.semantic_label) |semantic_label| allocator.free(semantic_label);
                        allocator.free(after.original_requirement_label);
                        allocator.free(after.original_op_name);
                    },
                }
            }

            fn deinitJournalEntry(allocator: std.mem.Allocator, entry: *Journal.Entry) void {
                switch (entry.*) {
                    .request => |*trace| deinitJournalRequestTrace(allocator, trace),
                    .response => |*response| if (response.value_image) |value_image| allocator.free(value_image),
                    .capsule_image => |*image| allocator.free(image.bytes),
                    .exchange_event => |*event| if (event.blocker_tag) |tag| allocator.free(tag),
                    else => {},
                }
            }

            fn encodeJournalResponseValue(
                allocator: std.mem.Allocator,
                response_trace: Trace.Response,
                value: anytype,
            ) anyerror![]u8 {
                const ValueType = @TypeOf(value);
                return switch (response_trace.response_ref.codec) {
                    .unit => encodeJournalResponseValueAs(allocator, response_trace, .{ .codec = .unit }, value),
                    .bool => encodeJournalResponseValueAs(allocator, response_trace, .{ .codec = .bool }, value),
                    .i32 => encodeJournalResponseValueAs(allocator, response_trace, .{ .codec = .i32 }, value),
                    .usize => encodeJournalResponseValueAs(allocator, response_trace, .{ .codec = .usize }, value),
                    .string => encodeJournalResponseValueAs(allocator, response_trace, .{ .codec = .string }, value),
                    .string_list => encodeJournalResponseValueAs(allocator, response_trace, .{ .codec = .string_list }, value),
                    .product, .sum => blk: {
                        const schema_index = response_trace.response_ref.schema_index orelse return error.ProgramContractViolation;
                        inline for (body_value_schema_types, 0..) |SchemaType, index| {
                            if (schema_index == index) {
                                if (ValueType != SchemaType) return error.ProgramContractViolation;
                                const expected_ref: lowering_api.ValueRef = comptime .{
                                    .codec = compiled_plan.value_schemas[index].codec,
                                    .schema_index = @intCast(index),
                                };
                                break :blk encodeJournalResponseValueAs(allocator, response_trace, expected_ref, value);
                            }
                        }
                        return error.ProgramContractViolation;
                    },
                };
            }

            fn encodeJournalResponseValueAs(
                allocator: std.mem.Allocator,
                response_trace: Trace.Response,
                comptime expected_ref: lowering_api.ValueRef,
                value: anytype,
            ) anyerror![]u8 {
                if (!response_trace.response_ref.eql(expected_ref)) return error.ProgramContractViolation;
                if (try fingerprintTypedValueImage(expected_ref, value) != response_trace.response_value_fingerprint) return error.ProgramContractViolation;
                var writer = ExchangeByteWriter.init(allocator);
                errdefer writer.deinit();
                var context = ValueImageContext.init(allocator);
                defer context.deinit();
                try writeExchangeValueRef(&writer, expected_ref);
                try writeTypedValueImage(&writer, &context, expected_ref, value);
                return writer.toOwnedSlice();
            }

            fn decodeJournalResponseValue(
                replayer: *Journal.Replayer,
                comptime ValueType: type,
                response_trace: Trace.Response,
                value_image: []const u8,
            ) anyerror!ValueType {
                return switch (response_trace.response_ref.codec) {
                    .unit => decodeJournalResponseValueAs(replayer, ValueType, response_trace, value_image, .{ .codec = .unit }),
                    .bool => decodeJournalResponseValueAs(replayer, ValueType, response_trace, value_image, .{ .codec = .bool }),
                    .i32 => decodeJournalResponseValueAs(replayer, ValueType, response_trace, value_image, .{ .codec = .i32 }),
                    .usize => decodeJournalResponseValueAs(replayer, ValueType, response_trace, value_image, .{ .codec = .usize }),
                    .string => decodeJournalResponseValueAs(replayer, ValueType, response_trace, value_image, .{ .codec = .string }),
                    .string_list => decodeJournalResponseValueAs(replayer, ValueType, response_trace, value_image, .{ .codec = .string_list }),
                    .product, .sum => blk: {
                        const schema_index = response_trace.response_ref.schema_index orelse return error.ProgramContractViolation;
                        inline for (body_value_schema_types, 0..) |SchemaType, index| {
                            if (schema_index == index) {
                                if (ValueType != SchemaType) return error.ProgramContractViolation;
                                const expected_ref: lowering_api.ValueRef = comptime .{
                                    .codec = compiled_plan.value_schemas[index].codec,
                                    .schema_index = @intCast(index),
                                };
                                break :blk decodeJournalResponseValueAs(replayer, ValueType, response_trace, value_image, expected_ref);
                            }
                        }
                        return error.ProgramContractViolation;
                    },
                };
            }

            fn decodeJournalResponseValueAs(
                replayer: *Journal.Replayer,
                comptime ValueType: type,
                response_trace: Trace.Response,
                value_image: []const u8,
                comptime expected_ref: lowering_api.ValueRef,
            ) anyerror!ValueType {
                if (!response_trace.response_ref.eql(expected_ref)) return error.ProgramContractViolation;
                var reader = ExchangeByteReader.init(value_image);
                const encoded_ref = try readExchangeValueRef(&reader);
                if (!encoded_ref.eql(expected_ref)) return error.ProgramContractViolation;
                var context = ValueImageContext.init(replayer.journal.allocator);
                defer context.deinit();
                const value = try readTypedValueImage(&reader, replayer, &context, expected_ref, ValueType);
                if (!reader.eof()) return error.ProgramContractViolation;
                if (try fingerprintTypedValueImage(expected_ref, value) != response_trace.response_value_fingerprint) return error.ProgramContractViolation;
                return value;
            }

            fn validateJournalResponseValueImage(
                allocator: std.mem.Allocator,
                response_trace: Trace.Response,
                value_image: []const u8,
            ) anyerror!void {
                var validation_journal = Journal.init(allocator);
                defer validation_journal.deinit();
                var replayer = validation_journal.replayer();
                defer replayer.deinit();

                var reader = ExchangeByteReader.init(value_image);
                const encoded_ref = try readExchangeValueRef(&reader);
                if (!encoded_ref.eql(response_trace.response_ref)) return error.ProgramContractViolation;
                return switch (response_trace.response_ref.codec) {
                    .unit => validateJournalResponseValueImageAs(&reader, &replayer, response_trace, .{ .codec = .unit }, void),
                    .bool => validateJournalResponseValueImageAs(&reader, &replayer, response_trace, .{ .codec = .bool }, bool),
                    .i32 => validateJournalResponseValueImageAs(&reader, &replayer, response_trace, .{ .codec = .i32 }, i32),
                    .usize => validateJournalResponseValueImageAs(&reader, &replayer, response_trace, .{ .codec = .usize }, usize),
                    .string => validateJournalResponseValueImageAs(&reader, &replayer, response_trace, .{ .codec = .string }, []const u8),
                    .string_list => validateJournalResponseValueImageAs(&reader, &replayer, response_trace, .{ .codec = .string_list }, []const []const u8),
                    .product, .sum => blk: {
                        const schema_index = response_trace.response_ref.schema_index orelse return error.ProgramContractViolation;
                        inline for (body_value_schema_types, 0..) |SchemaType, index| {
                            if (schema_index == index) {
                                const expected_ref: lowering_api.ValueRef = comptime .{
                                    .codec = compiled_plan.value_schemas[index].codec,
                                    .schema_index = @intCast(index),
                                };
                                if (!response_trace.response_ref.eql(expected_ref)) return error.ProgramContractViolation;
                                break :blk validateJournalResponseValueImageAs(&reader, &replayer, response_trace, expected_ref, SchemaType);
                            }
                        }
                        return error.ProgramContractViolation;
                    },
                };
            }

            fn validateJournalResponseValueImageAs(
                reader: *ExchangeByteReader,
                replayer: *Journal.Replayer,
                response_trace: Trace.Response,
                comptime expected_ref: lowering_api.ValueRef,
                comptime ValueType: type,
            ) anyerror!void {
                var context = ValueImageContext.init(replayer.journal.allocator);
                defer context.deinit();
                const value = try readTypedValueImage(reader, replayer, &context, expected_ref, ValueType);
                if (!reader.eof()) return error.ProgramContractViolation;
                if (try fingerprintTypedValueImage(expected_ref, value) != response_trace.response_value_fingerprint) {
                    return error.ProgramContractViolation;
                }
            }

            fn fingerprintJournalResponseTrace(trace: Trace.Response) u64 {
                var hasher = std.hash.Wyhash.init(0);
                hashBytes(&hasher, "ability.session.response");
                hashU32(&hasher, Trace.fingerprint_version);
                hashU64(&hasher, trace.request_fingerprint);
                hashBytes(&hasher, @tagName(trace.kind));
                hashJournalTraceValueRef(&hasher, trace.response_ref);
                hashU64(&hasher, trace.response_value_fingerprint);
                return hasher.final();
            }

            fn hashJournalRequestPrefix(hasher: *std.hash.Wyhash, turn_index: usize, kind: Trace.RequestKind) void {
                hashBytes(hasher, "ability.session.request");
                hashU32(hasher, Trace.fingerprint_version);
                hashBytes(hasher, label);
                hashBytes(hasher, body_compiled_plan.label);
                hashU64(hasher, body_compiled_plan_hash);
                hashUsize(hasher, turn_index);
                hashBytes(hasher, @tagName(kind));
            }

            fn fingerprintJournalOperationRequestTrace(trace: Trace.OperationRequest) u64 {
                var hasher = std.hash.Wyhash.init(0);
                hashJournalRequestPrefix(&hasher, trace.turn_index, .operation);
                hashUsize(&hasher, trace.operation_site_index);
                hashU64(&hasher, trace.operation_site_fingerprint);
                hashUsize(&hasher, trace.function_index);
                hashUsize(&hasher, trace.block_index);
                hashUsize(&hasher, trace.instruction_index);
                hashU16(&hasher, trace.requirement_index);
                hashBytes(&hasher, trace.requirement_label);
                hashU16(&hasher, trace.op_index);
                hashBytes(&hasher, trace.op_name);
                hashBytes(&hasher, @tagName(trace.mode));
                hashJournalTraceValueRef(&hasher, trace.payload_ref);
                hashU64(&hasher, trace.payload_value_fingerprint);
                hashJournalTraceValueRef(&hasher, trace.resume_ref);
                hashJournalTraceValueRef(&hasher, trace.result_ref);
                hashBool(&hasher, trace.has_after);
                return hasher.final();
            }

            fn fingerprintJournalAfterRequestTrace(trace: Trace.AfterRequest) u64 {
                var hasher = std.hash.Wyhash.init(0);
                hashJournalRequestPrefix(&hasher, trace.turn_index, .after);
                hashUsize(&hasher, trace.after_site_index);
                hashU64(&hasher, trace.after_site_fingerprint);
                hashUsize(&hasher, trace.source_operation_site_index);
                hashU64(&hasher, trace.source_operation_site_fingerprint);
                hashUsize(&hasher, trace.function_index);
                hashUsize(&hasher, trace.block_index);
                hashUsize(&hasher, trace.instruction_index);
                hashU16(&hasher, trace.original_requirement_index);
                hashBytes(&hasher, trace.original_requirement_label);
                hashU16(&hasher, trace.original_op_index);
                hashBytes(&hasher, trace.original_op_name);
                hashJournalTraceValueRef(&hasher, trace.current_value_ref);
                hashU64(&hasher, trace.current_value_fingerprint);
                hashJournalTraceValueRef(&hasher, trace.expected_output_ref);
                hashJournalTraceValueRef(&hasher, trace.result_ref);
                return hasher.final();
            }

            fn hashJournalTraceValueRef(hasher: *std.hash.Wyhash, ref: lowering_api.ValueRef) void {
                hasher.update(&[_]u8{@intFromEnum(ref.codec)});
                hashBool(hasher, ref.schema_index != null);
                if (ref.schema_index) |schema_index| hashU16(hasher, schema_index);
            }

            fn hashJournalCodec(hasher: *std.hash.Wyhash, codec: lowering_api.ValueCodec) void {
                hasher.update(&[_]u8{@intFromEnum(codec)});
            }

            fn fingerprintTypedValueImage(comptime ref: lowering_api.ValueRef, value: anytype) Error!u64 {
                const ValueType = @TypeOf(value);
                if (comptime !ProgramValueRefMatchesType(body_value_schema_types, ref, ValueType)) return error.ProgramContractViolation;
                var hasher = std.hash.Wyhash.init(0);
                hashBytes(&hasher, "ability.session.value");
                hashU32(&hasher, Trace.fingerprint_version);
                hashJournalTraceValueRef(&hasher, ref);
                try hashTypedValueImagePayload(&hasher, ref, value);
                return hasher.final();
            }

            fn hashTypedValueImagePayload(hasher: *std.hash.Wyhash, comptime ref: lowering_api.ValueRef, value: anytype) Error!void {
                const ValueType = @TypeOf(value);
                if (comptime !ProgramValueRefMatchesType(body_value_schema_types, ref, ValueType)) return error.ProgramContractViolation;
                switch (comptime ref.codec) {
                    .unit => {},
                    .bool => hashBool(hasher, value),
                    .i32 => hashI32(hasher, value),
                    .usize => hashUsize(hasher, value),
                    .string => hashBytes(hasher, value),
                    .string_list => {
                        hashUsize(hasher, value.len);
                        for (value) |item| hashBytes(hasher, item);
                    },
                    .product => try hashProductValueImagePayload(hasher, ref, ValueType, value),
                    .sum => try hashSumValueImagePayload(hasher, ref, ValueType, value),
                }
            }

            fn hashJournalStructuredSchemaPrefix(
                hasher: *std.hash.Wyhash,
                comptime ref: lowering_api.ValueRef,
                comptime ValueType: type,
                comptime schema_index: usize,
            ) Error!void {
                inline for (body_value_schema_types, 0..) |SchemaType, index| {
                    if (schema_index == index) {
                        if (SchemaType != ValueType) return error.ProgramContractViolation;
                        const schema = compiled_plan.value_schemas[index];
                        if (schema.codec != ref.codec) return error.ProgramContractViolation;
                        hashU16(hasher, @intCast(index));
                        hashBytes(hasher, schema.label);
                        hashJournalCodec(hasher, schema.codec);
                        return;
                    }
                }
                return error.ProgramContractViolation;
            }

            fn hashProductValueImagePayload(
                hasher: *std.hash.Wyhash,
                comptime ref: lowering_api.ValueRef,
                comptime ValueType: type,
                value: ValueType,
            ) Error!void {
                const schema_index = comptime ref.schema_index orelse return error.ProgramContractViolation;
                try hashJournalStructuredSchemaPrefix(hasher, ref, ValueType, schema_index);
                const schema = compiled_plan.value_schemas[schema_index];
                if (schema.codec != .product) return error.ProgramContractViolation;
                const fields = std.meta.fields(ValueType);
                if (fields.len != schema.field_count) return error.ProgramContractViolation;
                hashU16(hasher, schema.first_field);
                hashU16(hasher, schema.field_count);
                inline for (0..schema.field_count) |field_offset| {
                    const field = compiled_plan.value_fields[@as(usize, schema.first_field) + field_offset];
                    const field_ref: lowering_api.ValueRef = .{
                        .codec = field.codec,
                        .schema_index = field.schema_index,
                    };
                    hashU16(hasher, @intCast(field_offset));
                    hashBytes(hasher, field.name);
                    hashJournalTraceValueRef(hasher, field_ref);
                    const field_fingerprint = try fingerprintTypedValueImage(field_ref, @field(value, field.name));
                    hashU64(hasher, field_fingerprint);
                }
            }

            fn activeValueImageVariantOrdinal(comptime ValueType: type, value: ValueType) Error!u16 {
                return switch (@typeInfo(ValueType)) {
                    .@"enum" => |enum_info| {
                        inline for (enum_info.fields, 0..) |field, field_index| {
                            if (value == @field(ValueType, field.name)) return @intCast(field_index);
                        }
                        return error.ProgramContractViolation;
                    },
                    .@"union" => |union_info| {
                        const Tag = union_info.tag_type orelse return error.ProgramContractViolation;
                        const active = std.meta.activeTag(value);
                        inline for (union_info.fields, 0..) |field, field_index| {
                            if (active == @field(Tag, field.name)) return @intCast(field_index);
                        }
                        return error.ProgramContractViolation;
                    },
                    .optional => if (value == null) 0 else 1,
                    else => error.ProgramContractViolation,
                };
            }

            fn hashSumValueImagePayload(
                hasher: *std.hash.Wyhash,
                comptime ref: lowering_api.ValueRef,
                comptime ValueType: type,
                value: ValueType,
            ) Error!void {
                const schema_index = comptime ref.schema_index orelse return error.ProgramContractViolation;
                try hashJournalStructuredSchemaPrefix(hasher, ref, ValueType, schema_index);
                const schema = compiled_plan.value_schemas[schema_index];
                if (schema.codec != .sum) return error.ProgramContractViolation;
                const active = try activeValueImageVariantOrdinal(ValueType, value);
                if (active >= schema.variant_count) return error.ProgramContractViolation;
                hashU16(hasher, schema.first_variant);
                hashU16(hasher, schema.variant_count);
                hashU16(hasher, active);
                inline for (0..schema.variant_count) |variant_offset| {
                    if (active == variant_offset) {
                        const variant = compiled_plan.value_variants[@as(usize, schema.first_variant) + variant_offset];
                        const variant_ref: lowering_api.ValueRef = .{
                            .codec = variant.codec,
                            .schema_index = variant.schema_index,
                        };
                        hashBytes(hasher, variant.name);
                        hashJournalTraceValueRef(hasher, variant_ref);
                        const payload_fingerprint = try sumVariantPayloadValueImageFingerprint(variant_offset, variant_ref, ValueType, value);
                        hashU64(hasher, payload_fingerprint);
                        return;
                    }
                }
                return error.ProgramContractViolation;
            }

            fn sumVariantPayloadValueImageFingerprint(
                comptime variant_offset: usize,
                comptime variant_ref: lowering_api.ValueRef,
                comptime ValueType: type,
                value: ValueType,
            ) Error!u64 {
                return switch (@typeInfo(ValueType)) {
                    .@"enum" => fingerprintTypedValueImage(variant_ref, {}),
                    .optional => if (variant_offset == 0)
                        fingerprintTypedValueImage(variant_ref, {})
                    else
                        fingerprintTypedValueImage(variant_ref, value.?),
                    .@"union" => |union_info| blk: {
                        inline for (union_info.fields, 0..) |field, field_index| {
                            if (variant_offset == field_index) {
                                if (field.type == void) break :blk fingerprintTypedValueImage(variant_ref, {});
                                break :blk fingerprintTypedValueImage(variant_ref, @field(value, field.name));
                            }
                        }
                        return error.ProgramContractViolation;
                    },
                    else => error.ProgramContractViolation,
                };
            }

            fn writeExchangeValueRef(writer: *ExchangeByteWriter, ref: lowering_api.ValueRef) std.mem.Allocator.Error!void {
                try writer.writeU8(@intFromEnum(ref.codec));
                try writer.writeBool(ref.schema_index != null);
                if (ref.schema_index) |schema_index| try writer.writeU16(schema_index);
            }

            fn readExchangeCodec(reader: *ExchangeByteReader) error{ProgramContractViolation}!lowering_api.ValueCodec {
                return switch (try reader.readU8()) {
                    @intFromEnum(lowering_api.ValueCodec.unit) => .unit,
                    @intFromEnum(lowering_api.ValueCodec.bool) => .bool,
                    @intFromEnum(lowering_api.ValueCodec.i32) => .i32,
                    @intFromEnum(lowering_api.ValueCodec.product) => .product,
                    @intFromEnum(lowering_api.ValueCodec.usize) => .usize,
                    @intFromEnum(lowering_api.ValueCodec.string) => .string,
                    @intFromEnum(lowering_api.ValueCodec.string_list) => .string_list,
                    @intFromEnum(lowering_api.ValueCodec.sum) => .sum,
                    else => error.ProgramContractViolation,
                };
            }

            fn readExchangeValueRef(reader: *ExchangeByteReader) error{ProgramContractViolation}!lowering_api.ValueRef {
                return .{
                    .codec = try readExchangeCodec(reader),
                    .schema_index = if (try reader.readBool()) try reader.readU16() else null,
                };
            }

            fn writeJournalResponseKind(writer: *ExchangeByteWriter, kind: Trace.ResponseKind) std.mem.Allocator.Error!void {
                try writer.writeU8(switch (kind) {
                    .@"resume" => 0,
                    .return_now => 1,
                    .resume_after => 2,
                });
            }

            fn readJournalResponseKind(reader: *ExchangeByteReader) error{ProgramContractViolation}!Trace.ResponseKind {
                return switch (try reader.readU8()) {
                    0 => .@"resume",
                    1 => .return_now,
                    2 => .resume_after,
                    else => error.ProgramContractViolation,
                };
            }

            fn writeJournalControlMode(writer: *ExchangeByteWriter, mode: plan_types.ControlMode) std.mem.Allocator.Error!void {
                try writer.writeU8(switch (mode) {
                    .abort => 0,
                    .choice => 1,
                    .transform => 2,
                });
            }

            fn readJournalControlMode(reader: *ExchangeByteReader) error{ProgramContractViolation}!plan_types.ControlMode {
                return switch (try reader.readU8()) {
                    0 => .abort,
                    1 => .choice,
                    2 => .transform,
                    else => error.ProgramContractViolation,
                };
            }

            fn writeValueImageString(
                writer: *ExchangeByteWriter,
                context: *ValueImageContext,
                value: []const u8,
            ) std.mem.Allocator.Error!void {
                if (context.stringIndex(value)) |index| {
                    try writer.writeU8(1);
                    try writer.writeUsize(index);
                    return;
                }
                try writer.writeU8(0);
                try context.strings.append(context.allocator, value);
                try writer.writeLenBytes(value);
            }

            fn readValueImageString(
                reader: *ExchangeByteReader,
                context: *ValueImageContext,
            ) anyerror![]const u8 {
                return switch (try reader.readU8()) {
                    0 => blk: {
                        const value = try reader.readLenBytes();
                        try context.strings.append(context.allocator, value);
                        break :blk value;
                    },
                    1 => blk: {
                        const index = try reader.readUsize();
                        if (index >= context.strings.items.len) return error.ProgramContractViolation;
                        break :blk context.strings.items[index];
                    },
                    else => error.ProgramContractViolation,
                };
            }

            fn writeValueImageStringList(
                writer: *ExchangeByteWriter,
                context: *ValueImageContext,
                value: []const []const u8,
            ) anyerror!void {
                if (context.stringListIndex(value)) |index| {
                    try writer.writeU8(1);
                    try writer.writeUsize(index);
                    return;
                }
                try writer.writeU8(0);
                try context.string_lists.append(context.allocator, value);
                try writer.writeUsize(value.len);
                for (value) |item| try writeValueImageString(writer, context, item);
            }

            fn writeTypedValueImage(
                writer: *ExchangeByteWriter,
                context: *ValueImageContext,
                comptime ref: lowering_api.ValueRef,
                value: anytype,
            ) anyerror!void {
                const ValueType = @TypeOf(value);
                if (comptime !ProgramValueRefMatchesType(body_value_schema_types, ref, ValueType)) return error.ProgramContractViolation;
                switch (comptime ref.codec) {
                    .unit => {},
                    .bool => try writer.writeBool(value),
                    .i32 => try writer.writeU32(@bitCast(value)),
                    .usize => try writer.writeUsize(value),
                    .string => try writeValueImageString(writer, context, value),
                    .string_list => try writeValueImageStringList(writer, context, value),
                    .product => {
                        const schema_index = comptime ref.schema_index orelse return error.ProgramContractViolation;
                        const schema = compiled_plan.value_schemas[schema_index];
                        if (schema.codec != .product) return error.ProgramContractViolation;
                        const info = @typeInfo(ValueType).@"struct";
                        if (info.fields.len != schema.field_count) return error.ProgramContractViolation;
                        inline for (0..schema.field_count) |field_offset| {
                            const field = compiled_plan.value_fields[@as(usize, schema.first_field) + field_offset];
                            try writer.writeLenBytes(field.name);
                            const field_ref: lowering_api.ValueRef = comptime .{ .codec = field.codec, .schema_index = field.schema_index };
                            try writeExchangeValueRef(writer, field_ref);
                            const FieldType = @TypeOf(@field(value, field.name));
                            try writeTypedValueImage(writer, context, field_ref, @as(FieldType, @field(value, field.name)));
                        }
                    },
                    .sum => switch (@typeInfo(ValueType)) {
                        .@"enum" => try writer.writeLenBytes(@tagName(value)),
                        .optional => {
                            const schema_index = comptime ref.schema_index orelse return error.ProgramContractViolation;
                            const schema = compiled_plan.value_schemas[schema_index];
                            if (schema.codec != .sum or schema.variant_count != 2) return error.ProgramContractViolation;
                            if (value) |payload| {
                                const variant = compiled_plan.value_variants[@as(usize, schema.first_variant) + 1];
                                try writer.writeLenBytes(variant.name);
                                const payload_ref: lowering_api.ValueRef = comptime .{ .codec = variant.codec, .schema_index = variant.schema_index };
                                try writeExchangeValueRef(writer, payload_ref);
                                try writeTypedValueImage(writer, context, payload_ref, payload);
                            } else {
                                const variant = compiled_plan.value_variants[schema.first_variant];
                                try writer.writeLenBytes(variant.name);
                            }
                        },
                        .@"union" => |union_info| {
                            const schema_index = comptime ref.schema_index orelse return error.ProgramContractViolation;
                            const schema = compiled_plan.value_schemas[schema_index];
                            if (schema.codec != .sum) return error.ProgramContractViolation;
                            const tag = std.meta.activeTag(value);
                            inline for (union_info.fields, 0..) |field, field_index| {
                                if (tag == @field(union_info.tag_type.?, field.name)) {
                                    const variant = compiled_plan.value_variants[@as(usize, schema.first_variant) + field_index];
                                    try writer.writeLenBytes(variant.name);
                                    if (field.type == void) return;
                                    const payload_ref: lowering_api.ValueRef = comptime .{ .codec = variant.codec, .schema_index = variant.schema_index };
                                    try writeExchangeValueRef(writer, payload_ref);
                                    try writeTypedValueImage(writer, context, payload_ref, @field(value, field.name));
                                    return;
                                }
                            }
                            return error.ProgramContractViolation;
                        },
                        else => return error.ProgramContractViolation,
                    },
                }
            }

            fn readTypedValueImage(
                reader: *ExchangeByteReader,
                replayer: *Journal.Replayer,
                context: *ValueImageContext,
                comptime ref: lowering_api.ValueRef,
                comptime ValueType: type,
            ) anyerror!ValueType {
                if (comptime !ProgramValueRefMatchesType(body_value_schema_types, ref, ValueType)) return error.ProgramContractViolation;
                return switch (comptime ref.codec) {
                    .unit => {},
                    .bool => try reader.readBool(),
                    .i32 => @as(i32, @bitCast(try reader.readU32())),
                    .usize => try reader.readUsize(),
                    .string => try readValueImageString(reader, context),
                    .string_list => blk: {
                        const items = try readValueImageStringList(reader, replayer, context);
                        if (ValueType == []const []const u8) break :blk items;
                        if (ValueType == [][]const u8) break :blk @constCast(items);
                        return error.ProgramContractViolation;
                    },
                    .product => blk: {
                        var value: ValueType = undefined;
                        const schema_index = comptime ref.schema_index orelse return error.ProgramContractViolation;
                        const schema = compiled_plan.value_schemas[schema_index];
                        if (schema.codec != .product) return error.ProgramContractViolation;
                        const info = @typeInfo(ValueType).@"struct";
                        if (info.fields.len != schema.field_count) return error.ProgramContractViolation;
                        inline for (0..schema.field_count) |field_offset| {
                            const field = compiled_plan.value_fields[@as(usize, schema.first_field) + field_offset];
                            if (!std.mem.eql(u8, try reader.readLenBytes(), field.name)) return error.ProgramContractViolation;
                            const field_ref: lowering_api.ValueRef = comptime .{ .codec = field.codec, .schema_index = field.schema_index };
                            const encoded_ref = try readExchangeValueRef(reader);
                            if (!encoded_ref.eql(field_ref)) return error.ProgramContractViolation;
                            const struct_field = std.meta.fields(ValueType)[field_offset];
                            const decoded_field = try readTypedValueImage(reader, replayer, context, field_ref, struct_field.type);
                            if (comptime field.codec == .string_list and struct_field.type == [][]const u8) {
                                @field(value, field.name) = @constCast(decoded_field);
                            } else {
                                @field(value, field.name) = decoded_field;
                            }
                        }
                        break :blk value;
                    },
                    .sum => switch (@typeInfo(ValueType)) {
                        .@"enum" => blk: {
                            const tag_name = try reader.readLenBytes();
                            inline for (@typeInfo(ValueType).@"enum".fields) |field| {
                                if (std.mem.eql(u8, tag_name, field.name)) break :blk @field(ValueType, field.name);
                            }
                            return error.ProgramContractViolation;
                        },
                        .optional => |optional| blk: {
                            const schema_index = comptime ref.schema_index orelse return error.ProgramContractViolation;
                            const schema = compiled_plan.value_schemas[schema_index];
                            if (schema.codec != .sum or schema.variant_count != 2) return error.ProgramContractViolation;
                            const tag_name = try reader.readLenBytes();
                            const none_variant = compiled_plan.value_variants[schema.first_variant];
                            const some_variant = compiled_plan.value_variants[@as(usize, schema.first_variant) + 1];
                            if (std.mem.eql(u8, tag_name, none_variant.name)) break :blk null;
                            if (!std.mem.eql(u8, tag_name, some_variant.name)) return error.ProgramContractViolation;
                            const variant = compiled_plan.value_variants[@as(usize, schema.first_variant) + 1];
                            const payload_ref: lowering_api.ValueRef = comptime .{ .codec = variant.codec, .schema_index = variant.schema_index };
                            const encoded_ref = try readExchangeValueRef(reader);
                            if (!encoded_ref.eql(payload_ref)) return error.ProgramContractViolation;
                            break :blk try readTypedValueImage(reader, replayer, context, payload_ref, optional.child);
                        },
                        .@"union" => |union_info| blk: {
                            const schema_index = comptime ref.schema_index orelse return error.ProgramContractViolation;
                            const schema = compiled_plan.value_schemas[schema_index];
                            if (schema.codec != .sum) return error.ProgramContractViolation;
                            const tag_name = try reader.readLenBytes();
                            inline for (union_info.fields, 0..) |field, field_index| {
                                if (std.mem.eql(u8, tag_name, field.name)) {
                                    if (field.type == void) break :blk @unionInit(ValueType, field.name, {});
                                    const variant = compiled_plan.value_variants[@as(usize, schema.first_variant) + field_index];
                                    const payload_ref: lowering_api.ValueRef = comptime .{ .codec = variant.codec, .schema_index = variant.schema_index };
                                    const encoded_ref = try readExchangeValueRef(reader);
                                    if (!encoded_ref.eql(payload_ref)) return error.ProgramContractViolation;
                                    break :blk @unionInit(ValueType, field.name, try readTypedValueImage(reader, replayer, context, payload_ref, field.type));
                                }
                            }
                            return error.ProgramContractViolation;
                        },
                        else => return error.ProgramContractViolation,
                    },
                };
            }

            fn readValueImageStringList(
                reader: *ExchangeByteReader,
                replayer: *Journal.Replayer,
                context: *ValueImageContext,
            ) anyerror![]const []const u8 {
                return switch (try reader.readU8()) {
                    0 => blk: {
                        const count = try reader.readUsize();
                        if (count > reader.remaining() / 8) return error.ProgramContractViolation;
                        const items = try replayer.journal.allocator.alloc([]const u8, count);
                        var items_owned = false;
                        errdefer if (!items_owned) replayer.journal.allocator.free(items);
                        for (items) |*item| item.* = try readValueImageString(reader, context);
                        try context.string_lists.append(context.allocator, items);
                        try replayer.string_lists.append(replayer.journal.allocator, items);
                        items_owned = true;
                        break :blk items;
                    },
                    1 => blk: {
                        const index = try reader.readUsize();
                        if (index >= context.string_lists.items.len) return error.ProgramContractViolation;
                        break :blk context.string_lists.items[index];
                    },
                    else => error.ProgramContractViolation,
                };
            }

            fn writeJournalRequestTrace(writer: *ExchangeByteWriter, trace: Journal.RequestTrace) anyerror!void {
                try Journal.validateJournalRequestTrace(trace);
                switch (trace) {
                    .operation => |operation| {
                        try writer.writeU8(0);
                        try writer.writeU64(operation.fingerprint);
                        try writer.writeUsize(operation.turn_index);
                        try writer.writeUsize(operation.operation_site_index);
                        try writer.writeU64(operation.operation_site_fingerprint);
                        try writer.writeBool(operation.semantic_label != null);
                        if (operation.semantic_label) |semantic_label| try writer.writeLenBytes(semantic_label);
                        try writer.writeUsize(operation.function_index);
                        try writer.writeUsize(operation.block_index);
                        try writer.writeUsize(operation.instruction_index);
                        try writer.writeU16(operation.requirement_index);
                        try writer.writeLenBytes(operation.requirement_label);
                        try writer.writeU16(operation.op_index);
                        try writer.writeLenBytes(operation.op_name);
                        try writeJournalControlMode(writer, operation.mode);
                        try writeExchangeValueRef(writer, operation.payload_ref);
                        try writer.writeBool(operation.has_payload);
                        try writer.writeU64(operation.payload_value_fingerprint);
                        try writeExchangeValueRef(writer, operation.resume_ref);
                        try writeExchangeValueRef(writer, operation.result_ref);
                        try writer.writeBool(operation.has_after);
                    },
                    .after => |after| {
                        try writer.writeU8(1);
                        try writer.writeU64(after.fingerprint);
                        try writer.writeUsize(after.turn_index);
                        try writer.writeUsize(after.after_site_index);
                        try writer.writeU64(after.after_site_fingerprint);
                        try writer.writeUsize(after.source_operation_site_index);
                        try writer.writeU64(after.source_operation_site_fingerprint);
                        try writer.writeBool(after.semantic_label != null);
                        if (after.semantic_label) |semantic_label| try writer.writeLenBytes(semantic_label);
                        try writer.writeUsize(after.function_index);
                        try writer.writeUsize(after.block_index);
                        try writer.writeUsize(after.instruction_index);
                        try writer.writeU16(after.original_requirement_index);
                        try writer.writeLenBytes(after.original_requirement_label);
                        try writer.writeU16(after.original_op_index);
                        try writer.writeLenBytes(after.original_op_name);
                        try writeExchangeValueRef(writer, after.current_value_ref);
                        try writer.writeU64(after.current_value_fingerprint);
                        try writeExchangeValueRef(writer, after.expected_output_ref);
                        try writeExchangeValueRef(writer, after.result_ref);
                    },
                }
            }

            fn readJournalRequestTrace(reader: *ExchangeByteReader, allocator: std.mem.Allocator) anyerror!Journal.RequestTrace {
                return switch (try reader.readU8()) {
                    0 => blk: {
                        const fingerprint = try reader.readU64();
                        const turn_index = try reader.readUsize();
                        const operation_site_index = try reader.readUsize();
                        const operation_site_fingerprint = try reader.readU64();
                        const semantic_label = if (try reader.readBool()) try allocator.dupe(u8, try reader.readLenBytes()) else null;
                        errdefer if (semantic_label) |label_bytes| allocator.free(label_bytes);
                        const function_index = try reader.readUsize();
                        const block_index = try reader.readUsize();
                        const instruction_index = try reader.readUsize();
                        const requirement_index = try reader.readU16();
                        const requirement_label = try allocator.dupe(u8, try reader.readLenBytes());
                        errdefer allocator.free(requirement_label);
                        const op_index = try reader.readU16();
                        const op_name = try allocator.dupe(u8, try reader.readLenBytes());
                        errdefer allocator.free(op_name);
                        const mode = try readJournalControlMode(reader);
                        const trace: Trace.OperationRequest = .{
                            .program_label = label,
                            .plan_label = body_compiled_plan.label,
                            .plan_hash = body_compiled_plan_hash,
                            .fingerprint = fingerprint,
                            .turn_index = turn_index,
                            .operation_site_index = operation_site_index,
                            .operation_site_fingerprint = operation_site_fingerprint,
                            .semantic_label = semantic_label,
                            .function_index = function_index,
                            .block_index = block_index,
                            .instruction_index = instruction_index,
                            .requirement_index = requirement_index,
                            .requirement_label = requirement_label,
                            .op_index = op_index,
                            .op_name = op_name,
                            .mode = mode,
                            .payload_ref = try readExchangeValueRef(reader),
                            .has_payload = try reader.readBool(),
                            .payload_value_fingerprint = try reader.readU64(),
                            .resume_ref = try readExchangeValueRef(reader),
                            .result_ref = try readExchangeValueRef(reader),
                            .has_after = try reader.readBool(),
                        };
                        try Journal.validateJournalRequestTrace(.{ .operation = trace });
                        if (trace.fingerprint != fingerprintJournalOperationRequestTrace(trace)) return error.ProgramContractViolation;
                        break :blk .{ .operation = trace };
                    },
                    1 => blk: {
                        const fingerprint = try reader.readU64();
                        const turn_index = try reader.readUsize();
                        const after_site_index = try reader.readUsize();
                        const after_site_fingerprint = try reader.readU64();
                        const source_operation_site_index = try reader.readUsize();
                        const source_operation_site_fingerprint = try reader.readU64();
                        const semantic_label = if (try reader.readBool()) try allocator.dupe(u8, try reader.readLenBytes()) else null;
                        errdefer if (semantic_label) |label_bytes| allocator.free(label_bytes);
                        const function_index = try reader.readUsize();
                        const block_index = try reader.readUsize();
                        const instruction_index = try reader.readUsize();
                        const original_requirement_index = try reader.readU16();
                        const original_requirement_label = try allocator.dupe(u8, try reader.readLenBytes());
                        errdefer allocator.free(original_requirement_label);
                        const original_op_index = try reader.readU16();
                        const original_op_name = try allocator.dupe(u8, try reader.readLenBytes());
                        errdefer allocator.free(original_op_name);
                        const trace: Trace.AfterRequest = .{
                            .program_label = label,
                            .plan_label = body_compiled_plan.label,
                            .plan_hash = body_compiled_plan_hash,
                            .fingerprint = fingerprint,
                            .turn_index = turn_index,
                            .after_site_index = after_site_index,
                            .after_site_fingerprint = after_site_fingerprint,
                            .source_operation_site_index = source_operation_site_index,
                            .source_operation_site_fingerprint = source_operation_site_fingerprint,
                            .semantic_label = semantic_label,
                            .function_index = function_index,
                            .block_index = block_index,
                            .instruction_index = instruction_index,
                            .original_requirement_index = original_requirement_index,
                            .original_requirement_label = original_requirement_label,
                            .original_op_index = original_op_index,
                            .original_op_name = original_op_name,
                            .current_value_ref = try readExchangeValueRef(reader),
                            .current_value_fingerprint = try reader.readU64(),
                            .expected_output_ref = try readExchangeValueRef(reader),
                            .result_ref = try readExchangeValueRef(reader),
                        };
                        if (trace.fingerprint != fingerprintJournalAfterRequestTrace(trace)) return error.ProgramContractViolation;
                        break :blk .{ .after = trace };
                    },
                    else => error.ProgramContractViolation,
                };
            }

            fn writeJournalEntry(writer: *ExchangeByteWriter, entry: Journal.Entry) anyerror!void {
                switch (entry) {
                    .request => |trace| {
                        try writer.writeU8(0);
                        try writeJournalRequestTrace(writer, trace);
                    },
                    .response => |response| {
                        try writer.writeU8(1);
                        try writer.writeU64(response.trace.request_fingerprint);
                        try writeJournalResponseKind(writer, response.trace.kind);
                        try writeExchangeValueRef(writer, response.trace.response_ref);
                        try writer.writeU64(response.trace.response_value_fingerprint);
                        try writer.writeU64(response.trace.fingerprint);
                        try writer.writeBool(response.value_image != null);
                        if (response.value_image) |value_image| try writer.writeLenBytes(value_image);
                    },
                    .capsule_image => |image| {
                        try writer.writeU8(2);
                        try writer.writeU64(image.image_fingerprint);
                        try writer.writeU64(image.capsule_fingerprint);
                        try writer.writeU64(image.current_request_fingerprint);
                        try writer.writeLenBytes(image.bytes);
                    },
                    .done => |fingerprint| {
                        try writer.writeU8(3);
                        try writer.writeU64(fingerprint);
                    },
                    .exchange_event => |event| {
                        try writer.writeU8(4);
                        try writeJournalExchangeEvent(writer, event);
                    },
                }
            }

            fn readJournalEntry(reader: *ExchangeByteReader, allocator: std.mem.Allocator, format_version: u32) anyerror!Journal.Entry {
                return switch (try reader.readU8()) {
                    0 => .{ .request = try readJournalRequestTrace(reader, allocator) },
                    1 => blk: {
                        const trace: Trace.Response = .{
                            .request_fingerprint = try reader.readU64(),
                            .kind = try readJournalResponseKind(reader),
                            .response_ref = try readExchangeValueRef(reader),
                            .response_value_fingerprint = try reader.readU64(),
                            .fingerprint = try reader.readU64(),
                        };
                        if (trace.fingerprint != fingerprintJournalResponseTrace(trace)) return error.ProgramContractViolation;
                        const value_image = if (try reader.readBool()) blk_value: {
                            const image = try allocator.dupe(u8, try reader.readLenBytes());
                            errdefer allocator.free(image);
                            try validateJournalResponseValueImage(allocator, trace, image);
                            break :blk_value image;
                        } else null;
                        break :blk .{ .response = .{
                            .trace = trace,
                            .value_image = value_image,
                        } };
                    },
                    2 => blk: {
                        const image_fingerprint = try reader.readU64();
                        const capsule_fingerprint = try reader.readU64();
                        const current_request_fingerprint = try reader.readU64();
                        const source = try reader.readLenBytes();
                        const bytes = try allocator.dupe(u8, source);
                        errdefer allocator.free(bytes);
                        if (image_fingerprint != capsuleImageFingerprint(bytes)) return error.ProgramContractViolation;
                        var decoded = Core.Capsule.decode(allocator, bytes) catch |err| return mapProgramRunError(Error, err);
                        defer decoded.deinit();
                        const metadata = decoded.metadata();
                        if (capsule_fingerprint != decoded.fingerprint() or
                            current_request_fingerprint != metadata.current_request_fingerprint)
                        {
                            return error.ProgramContractViolation;
                        }
                        break :blk .{ .capsule_image = .{
                            .image_fingerprint = image_fingerprint,
                            .capsule_fingerprint = capsule_fingerprint,
                            .current_request_fingerprint = current_request_fingerprint,
                            .bytes = bytes,
                        } };
                    },
                    3 => .{ .done = try reader.readU64() },
                    4 => if (format_version >= 2)
                        .{ .exchange_event = try readJournalExchangeEvent(reader, allocator) }
                    else
                        error.ProgramContractViolation,
                    else => error.ProgramContractViolation,
                };
            }

            fn writeOptionalJournalU64(writer: *ExchangeByteWriter, value: ?u64) std.mem.Allocator.Error!void {
                try writer.writeBool(value != null);
                if (value) |actual| try writer.writeU64(actual);
            }

            fn readOptionalJournalU64(reader: *ExchangeByteReader) error{ProgramContractViolation}!?u64 {
                if (!try reader.readBool()) return null;
                return try reader.readU64();
            }

            fn writeJournalExchangeEventKind(writer: *ExchangeByteWriter, kind: Journal.ExchangeEvent.Kind) std.mem.Allocator.Error!void {
                try writer.writeU8(switch (kind) {
                    .provider_manifest_recorded => 0,
                    .capability_granted => 1,
                    .capability_attenuated => 2,
                    .route_selected => 3,
                    .route_blocked => 4,
                    .response_authorized => 5,
                    .response_rejected => 6,
                });
            }

            fn readJournalExchangeEventKind(reader: *ExchangeByteReader) error{ProgramContractViolation}!Journal.ExchangeEvent.Kind {
                return switch (try reader.readU8()) {
                    0 => .provider_manifest_recorded,
                    1 => .capability_granted,
                    2 => .capability_attenuated,
                    3 => .route_selected,
                    4 => .route_blocked,
                    5 => .response_authorized,
                    6 => .response_rejected,
                    else => error.ProgramContractViolation,
                };
            }

            fn writeJournalExchangeEvent(writer: *ExchangeByteWriter, event: Journal.ExchangeEvent) anyerror!void {
                try writeJournalExchangeEventKind(writer, event.kind);
                try writeOptionalJournalU64(writer, event.provider_fingerprint);
                try writeOptionalJournalU64(writer, event.capability_fingerprint);
                try writeOptionalJournalU64(writer, event.route_fingerprint);
                try writeOptionalJournalU64(writer, event.authorization_fingerprint);
                try writeOptionalJournalU64(writer, event.request_envelope_fingerprint);
                try writeOptionalJournalU64(writer, event.response_envelope_fingerprint);
                try writer.writeBool(event.blocker_tag != null);
                if (event.blocker_tag) |tag| try writer.writeLenBytes(tag);
            }

            fn readJournalExchangeEvent(reader: *ExchangeByteReader, allocator: std.mem.Allocator) anyerror!Journal.ExchangeEvent {
                const kind = try readJournalExchangeEventKind(reader);
                const provider_fingerprint = try readOptionalJournalU64(reader);
                const capability_fingerprint = try readOptionalJournalU64(reader);
                const route_fingerprint = try readOptionalJournalU64(reader);
                const authorization_fingerprint = try readOptionalJournalU64(reader);
                const request_envelope_fingerprint = try readOptionalJournalU64(reader);
                const response_envelope_fingerprint = try readOptionalJournalU64(reader);
                const blocker_tag = if (try reader.readBool()) blk: {
                    const tag = try allocator.dupe(u8, try reader.readLenBytes());
                    break :blk tag;
                } else null;
                return .{
                    .kind = kind,
                    .provider_fingerprint = provider_fingerprint,
                    .capability_fingerprint = capability_fingerprint,
                    .route_fingerprint = route_fingerprint,
                    .authorization_fingerprint = authorization_fingerprint,
                    .request_envelope_fingerprint = request_envelope_fingerprint,
                    .response_envelope_fingerprint = response_envelope_fingerprint,
                    .blocker_tag = blocker_tag,
                };
            }

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
                        var exchange_storage = self.takeExchangeResponseStorage();
                        errdefer deinitExchangeResponseStorage(allocator, &exchange_storage);
                        const exchange_cleanup_allocator = if (exchange_storage) |exchange| exchange.tracker.allocator() else null;
                        const result = if (comptime @typeInfo(HandlersType) == .pointer)
                            finishSessionResult(allocator, self.handlers, &raw, exchange_cleanup_allocator)
                        else
                            finishSessionResult(allocator, &self.handlers, &raw, exchange_cleanup_allocator);
                        var finished = result catch |err| {
                            raw.deinit();
                            self.closeAs(.deinitialized);
                            return err;
                        };
                        if (exchange_storage) |exchange| armExchangeResponseCleanupAllocator(&finished, exchange);
                        errdefer finished.deinit();
                        try attachExchangeResponseStorageToResult(allocator, &finished, &exchange_storage);
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
                const allocator = lowered_machine.runtimeAllocator(self.runtime);
                var exchange_storage = self.takeExchangeResponseStorage();
                defer deinitExchangeResponseStorage(allocator, &exchange_storage);
                const completed = self.core.takeCompleted() catch |err|
                    std.debug.panic("completed session result decode failed during deinit: {s}", .{@errorName(err)});
                if (completed) |raw_result| {
                    var raw = raw_result;
                    defer raw.deinit();
                    const result_cleanup = comptime bodyDeinitResultMode(Body, Value, ProgramOutputs);
                    if (result_cleanup == .none) return;
                    var storage = raw.takeStorage();
                    defer if (storage) |*owned| owned.deinit();
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
                    if (exchange_storage) |exchange| {
                        deinitBodyResult(Body, Value, ProgramOutputs, .{
                            .allocator = exchange.tracker.allocator(),
                            .value = raw.value,
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

        /// Transport-neutral typed envelopes for exchanging yielded effects across host boundaries.
        pub const Exchange = struct {
            const manifest_magic = "ABL_EXM1";
            const request_magic = "ABL_EXQ1";
            const response_magic = "ABL_EXR1";
            const provider_magic = "ABL_EXP1";
            const capability_magic = "ABL_EXC1";
            const authorization_magic = "ABL_EXA1";

            /// Current encoded manifest image format version.
            pub const manifest_format_version = exchange_manifest_format_version;
            /// Current manifest image fingerprint domain version.
            pub const manifest_fingerprint_version = exchange_manifest_fingerprint_version;
            /// Current encoded request envelope format version.
            pub const request_format_version = exchange_request_format_version;
            /// Current request envelope fingerprint domain version.
            pub const request_fingerprint_version = exchange_request_fingerprint_version;
            /// Current encoded response envelope format version.
            pub const response_format_version = exchange_response_format_version;
            /// Current response envelope fingerprint domain version.
            pub const response_fingerprint_version = exchange_response_fingerprint_version;
            /// Current provider manifest image format version.
            pub const provider_format_version = exchange_provider_format_version;
            /// Current provider manifest image fingerprint domain version.
            pub const provider_fingerprint_version = exchange_provider_fingerprint_version;
            /// Current capability grant image format version.
            pub const capability_format_version = exchange_capability_format_version;
            /// Current capability grant image fingerprint domain version.
            pub const capability_fingerprint_version = exchange_capability_fingerprint_version;
            /// Current authorization witness fingerprint domain version.
            pub const authorization_fingerprint_version = exchange_authorization_fingerprint_version;
            /// Current route witness fingerprint domain version.
            pub const route_fingerprint_version = exchange_route_fingerprint_version;

            /// Stable fingerprint for scoping capability grants to a journal branch id.
            pub fn journalPolicyFingerprint(journal_branch_id: []const u8) u64 {
                return journalBranchPolicyFingerprint(journal_branch_id);
            }

            /// Dynamic exchange request kind yielded by a parked session.
            pub const RequestKind = enum {
                operation,
                after,
            };

            /// Dynamic exchange response kind accepted by a parked session.
            pub const ResponseKind = Session.Trace.ResponseKind;

            /// Canonical image of the Program exchange surface.
            pub const Manifest = struct {
                allocator: std.mem.Allocator,
                bytes: []u8,
                fingerprint: u64,
                program_label: []const u8 = label,
                plan_label: []const u8 = body_compiled_plan.label,
                plan_hash: u64 = body_compiled_plan_hash,
                operation_site_count: usize = protocol.operation_site_count,
                after_site_count: usize = protocol.after_site_count,
                value_schema_count: usize = compiled_plan.value_schemas.len,
                value_field_count: usize = compiled_plan.value_fields.len,
                value_variant_count: usize = compiled_plan.value_variants.len,

                /// Encode the current Program exchange manifest.
                pub fn encode(allocator: std.mem.Allocator) Error!@This() {
                    var writer = Writer.init(allocator);
                    errdefer writer.deinit();
                    writeManifestPayload(&writer) catch |err| return mapProgramRunError(Error, err);
                    const payload = writer.bytes.items;
                    const fingerprint = exchangeFingerprint("ability.exchange.manifest", exchange_manifest_fingerprint_version, payload);
                    try writer.writeU64(fingerprint);
                    return .{
                        .allocator = allocator,
                        .bytes = try writer.toOwnedSlice(),
                        .fingerprint = fingerprint,
                    };
                }

                /// Decode and validate a Program exchange manifest image.
                pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) Error!@This() {
                    const payload = try checkedPayload(bytes, "ability.exchange.manifest", exchange_manifest_fingerprint_version);
                    var reader = Reader.init(payload);
                    try reader.expectBytes(manifest_magic);
                    if (try reader.readU32() != exchange_manifest_format_version) return error.ProgramContractViolation;
                    if (try reader.readU32() != exchange_manifest_fingerprint_version) return error.ProgramContractViolation;
                    if (try reader.readU32() != exchange_request_format_version) return error.ProgramContractViolation;
                    if (try reader.readU32() != exchange_request_fingerprint_version) return error.ProgramContractViolation;
                    if (try reader.readU32() != exchange_response_format_version) return error.ProgramContractViolation;
                    if (try reader.readU32() != exchange_response_fingerprint_version) return error.ProgramContractViolation;
                    if (!std.mem.eql(u8, try reader.readLenBytes(), label)) return error.ProgramContractViolation;
                    if (!std.mem.eql(u8, try reader.readLenBytes(), body_compiled_plan.label)) return error.ProgramContractViolation;
                    if (try reader.readU64() != body_compiled_plan_hash) return error.ProgramContractViolation;
                    if (try reader.readU32() != lowering_api.trace_fingerprint_version) return error.ProgramContractViolation;
                    if (try reader.readU32() != capsule_image_format_version) return error.ProgramContractViolation;
                    if (try reader.readU32() != capsule_image_fingerprint_version) return error.ProgramContractViolation;
                    const manifest_journal_format = try reader.readU32();
                    if (manifest_journal_format != 1 and manifest_journal_format != journal_format_version) return error.ProgramContractViolation;
                    if (try reader.readU32() != journal_fingerprint_version) return error.ProgramContractViolation;
                    try readManifestValueSchemas(&reader);
                    try readManifestOperationSites(&reader);
                    try readManifestAfterSites(&reader);
                    if (!reader.eof()) return error.ProgramContractViolation;
                    const owned = allocator.dupe(u8, bytes) catch |err| return mapProgramRunError(Error, err);
                    return .{
                        .allocator = allocator,
                        .bytes = owned,
                        .fingerprint = try checkedBytesFingerprint(bytes, "ability.exchange.manifest", exchange_manifest_fingerprint_version),
                    };
                }

                /// Release manifest image storage.
                pub fn deinit(self: *@This()) void {
                    self.allocator.free(self.bytes);
                    self.bytes = &.{};
                }
            };

            /// Local guardrails for envelope size, capsule, site, and response-kind acceptance.
            pub const Policy = struct {
                allow_capsules: bool = true,
                allow_response_value_images: bool = true,
                max_envelope_bytes: usize = std.math.maxInt(usize),
                max_payload_bytes: usize = std.math.maxInt(usize),
                max_capsule_image_bytes: ?usize = null,
                allowed_response_kinds: ResponseKindSet = .{},
                allowed_operation_sites: ?[]const usize = null,
                allowed_after_sites: ?[]const usize = null,
                require_route: bool = false,
                reject_ambiguous_routes: bool = true,
                require_response_capability: bool = false,
                allowed_provider_fingerprints: ?[]const u64 = null,
                allowed_capability_fingerprints: ?[]const u64 = null,
                allow_capsule_restore: bool = true,

                /// Response-kind allow list used by Policy.
                pub const ResponseKindSet = struct {
                    @"resume": bool = true,
                    return_now: bool = true,
                    resume_after: bool = true,

                    /// Return true when this set allows the response kind.
                    pub fn allows(self: @This(), kind_value: ResponseKind) bool {
                        return switch (kind_value) {
                            .@"resume" => self.@"resume",
                            .return_now => self.return_now,
                            .resume_after => self.resume_after,
                        };
                    }
                };

                /// Validate a request envelope against this policy.
                pub fn validateRequest(self: @This(), envelope: RequestEnvelope) Error!void {
                    if (envelope.bytes.len > self.max_envelope_bytes) return error.ProgramContractViolation;
                    if (envelope.value_image.len > self.max_payload_bytes) return error.ProgramContractViolation;
                    if (!self.allow_capsules and envelope.capsule_image != null) return error.ProgramContractViolation;
                    if (envelope.capsule_image) |image| {
                        if (image.len > (self.max_capsule_image_bytes orelse self.max_payload_bytes)) return error.ProgramContractViolation;
                    }
                    switch (envelope.kind) {
                        .operation => if (!policyAllowsSite(self.allowed_operation_sites, envelope.site_index)) return error.ProgramContractViolation,
                        .after => if (!policyAllowsSite(self.allowed_after_sites, envelope.site_index)) return error.ProgramContractViolation,
                    }
                }

                /// Validate a response envelope against this policy.
                pub fn validateResponse(self: @This(), envelope: ResponseEnvelope) Error!void {
                    if (envelope.bytes.len > self.max_envelope_bytes) return error.ProgramContractViolation;
                    if (envelope.value_image.len > self.max_payload_bytes) return error.ProgramContractViolation;
                    if (!self.allow_response_value_images and envelope.value_image.len != 0) return error.ProgramContractViolation;
                    if (!self.allowed_response_kinds.allows(envelope.kind)) return error.ProgramContractViolation;
                }

                fn policyAllowsSite(allowed: ?[]const usize, site_index: usize) bool {
                    const list = allowed orelse return true;
                    for (list) |allowed_index| if (allowed_index == site_index) return true;
                    return false;
                }
            };

            /// Structured capability/routing validation blockers.
            pub const BlockerTag = enum {
                wrong_provider,
                wrong_manifest,
                wrong_program_label,
                wrong_plan_hash,
                wrong_journal_policy,
                request_kind,
                operation_site,
                after_site,
                protocol_operation,
                response_kind,
                response_ref,
                embedded_capsule,
                capsule_restore,
                request_too_large,
                response_too_large,
                payload_too_large,
                capsule_too_large,
                missing_capability_fingerprint,
                wrong_capability,
                wrong_capability_path,
                wrong_route,
                wrong_request,
                invalid_envelope,
                provider_not_allowed,
                capability_not_allowed,
                ambiguous_route,
                no_route,
                broadened_authority,
                expired_capability,
            };

            /// Fixed-capacity structured validation report. Extra blockers are saturated, not allocated.
            pub const ValidationReport = struct {
                blockers: [16]BlockerTag = undefined,
                count: usize = 0,

                /// Return true when the report contains no blockers.
                pub fn allowed(self: @This()) bool {
                    return self.count == 0;
                }

                /// Add a blocker tag if it is not already present.
                pub fn add(self: *@This(), tag: BlockerTag) void {
                    if (self.has(tag)) return;
                    if (self.count < self.blockers.len) {
                        self.blockers[self.count] = tag;
                        self.count += 1;
                    }
                }

                /// Add all blockers from another validation report.
                pub fn merge(self: *@This(), other: @This()) void {
                    for (other.blockers[0..other.count]) |tag| self.add(tag);
                }

                /// Return true when the report contains the blocker tag.
                pub fn has(self: @This(), tag: BlockerTag) bool {
                    for (self.blockers[0..self.count]) |existing| if (existing == tag) return true;
                    return false;
                }

                /// Return the first blocker tag name, if present.
                pub fn firstTagName(self: @This()) ?[]const u8 {
                    if (self.count == 0) return null;
                    return @tagName(self.blockers[0]);
                }
            };

            /// Request-kind allow set used by capability grants.
            pub const RequestKindSet = struct {
                operation: bool = true,
                after: bool = true,

                fn allows(self: @This(), kind_value: RequestKind) bool {
                    return switch (kind_value) {
                        .operation => self.operation,
                        .after => self.after,
                    };
                }

                fn subsetOf(self: @This(), parent: @This()) bool {
                    return (!self.operation or parent.operation) and (!self.after or parent.after);
                }
            };

            /// Host-side claim describing what a provider says it can handle.
            pub const ProviderManifest = struct {
                allocator: std.mem.Allocator,
                bytes: []u8,
                fingerprint: u64,
                label: []u8,
                provider_fingerprint: u64,
                supported_program_manifest_fingerprints: []const u64,
                supported_protocol_labels: []const []const u8,
                supported_operation_sites: []const usize,
                supported_after_sites: []const usize,
                supported_protocol_op_fingerprints: []const u64,
                allowed_response_kinds: Policy.ResponseKindSet,
                max_request_envelope_bytes: usize,
                max_response_envelope_bytes: usize,
                accepts_embedded_capsules: bool,
                accepts_capsule_restore: bool,
                semantic_tags: []const []const u8,
                metadata: []u8,

                /// Options used to encode a provider manifest.
                pub const Options = struct {
                    label: []const u8,
                    provider_fingerprint: ?u64 = null,
                    supported_program_manifest_fingerprints: []const u64 = &.{},
                    supported_protocol_labels: []const []const u8 = &.{},
                    supported_operation_sites: []const usize = &.{},
                    supported_after_sites: []const usize = &.{},
                    supported_protocol_op_fingerprints: []const u64 = &.{},
                    allowed_response_kinds: Policy.ResponseKindSet = .{},
                    max_request_envelope_bytes: usize = std.math.maxInt(usize),
                    max_response_envelope_bytes: usize = std.math.maxInt(usize),
                    accepts_embedded_capsules: bool = true,
                    accepts_capsule_restore: bool = true,
                    semantic_tags: []const []const u8 = &.{},
                    metadata: []const u8 = &.{},
                };

                /// Encode a provider manifest into deterministic owned bytes.
                pub fn encode(allocator: std.mem.Allocator, options: Options) Error!@This() {
                    const provider_fp = options.provider_fingerprint orelse providerIdentityFingerprint(options.label, options.metadata);
                    var writer = Writer.init(allocator);
                    errdefer writer.deinit();
                    try writeProviderPayload(&writer, provider_fp, options);
                    const payload = writer.bytes.items;
                    const fingerprint = exchangeFingerprint("ability.exchange.provider", exchange_provider_fingerprint_version, payload);
                    try writer.writeU64(fingerprint);
                    const owned_bytes = try writer.toOwnedSlice();
                    errdefer allocator.free(owned_bytes);
                    const label_value = try allocator.dupe(u8, options.label);
                    errdefer allocator.free(label_value);
                    const manifests = try cloneU64s(allocator, options.supported_program_manifest_fingerprints);
                    errdefer allocator.free(manifests);
                    const protocol_labels = try cloneStringList(allocator, options.supported_protocol_labels);
                    errdefer freeStringList(allocator, protocol_labels);
                    const operation_sites = try cloneUsizes(allocator, options.supported_operation_sites);
                    errdefer allocator.free(operation_sites);
                    const after_sites = try cloneUsizes(allocator, options.supported_after_sites);
                    errdefer allocator.free(after_sites);
                    const protocol_ops = try cloneU64s(allocator, options.supported_protocol_op_fingerprints);
                    errdefer allocator.free(protocol_ops);
                    const tags = try cloneStringList(allocator, options.semantic_tags);
                    errdefer freeStringList(allocator, tags);
                    const metadata = try allocator.dupe(u8, options.metadata);
                    errdefer allocator.free(metadata);
                    return .{
                        .allocator = allocator,
                        .bytes = owned_bytes,
                        .fingerprint = fingerprint,
                        .label = label_value,
                        .provider_fingerprint = provider_fp,
                        .supported_program_manifest_fingerprints = manifests,
                        .supported_protocol_labels = protocol_labels,
                        .supported_operation_sites = operation_sites,
                        .supported_after_sites = after_sites,
                        .supported_protocol_op_fingerprints = protocol_ops,
                        .allowed_response_kinds = options.allowed_response_kinds,
                        .max_request_envelope_bytes = options.max_request_envelope_bytes,
                        .max_response_envelope_bytes = options.max_response_envelope_bytes,
                        .accepts_embedded_capsules = options.accepts_embedded_capsules,
                        .accepts_capsule_restore = options.accepts_capsule_restore,
                        .semantic_tags = tags,
                        .metadata = metadata,
                    };
                }

                /// Decode and validate a provider manifest image.
                pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) Error!@This() {
                    const payload = try checkedPayload(bytes, "ability.exchange.provider", exchange_provider_fingerprint_version);
                    var reader = Reader.init(payload);
                    try reader.expectBytes(provider_magic);
                    if (try reader.readU32() != exchange_provider_format_version) return error.ProgramContractViolation;
                    if (try reader.readU32() != exchange_provider_fingerprint_version) return error.ProgramContractViolation;
                    const provider_fp = try reader.readU64();
                    const label_value = try allocator.dupe(u8, try reader.readLenBytes());
                    errdefer allocator.free(label_value);
                    const manifests = try readU64List(allocator, &reader);
                    errdefer allocator.free(manifests);
                    const protocol_labels = try readStringList(allocator, &reader);
                    errdefer freeStringList(allocator, protocol_labels);
                    const operation_sites = try readUsizeList(allocator, &reader);
                    errdefer allocator.free(operation_sites);
                    const after_sites = try readUsizeList(allocator, &reader);
                    errdefer allocator.free(after_sites);
                    const protocol_ops = try readU64List(allocator, &reader);
                    errdefer allocator.free(protocol_ops);
                    const response_kinds = try readResponseKindSet(&reader);
                    const max_request = try reader.readUsize();
                    const max_response = try reader.readUsize();
                    const accepts_capsules = try reader.readBool();
                    const accepts_restore = try reader.readBool();
                    const tags = try readStringList(allocator, &reader);
                    errdefer freeStringList(allocator, tags);
                    const metadata = try allocator.dupe(u8, try reader.readLenBytes());
                    errdefer allocator.free(metadata);
                    if (!reader.eof()) return error.ProgramContractViolation;
                    const owned = try allocator.dupe(u8, bytes);
                    errdefer allocator.free(owned);
                    return .{
                        .allocator = allocator,
                        .bytes = owned,
                        .fingerprint = try checkedBytesFingerprint(bytes, "ability.exchange.provider", exchange_provider_fingerprint_version),
                        .label = label_value,
                        .provider_fingerprint = provider_fp,
                        .supported_program_manifest_fingerprints = manifests,
                        .supported_protocol_labels = protocol_labels,
                        .supported_operation_sites = operation_sites,
                        .supported_after_sites = after_sites,
                        .supported_protocol_op_fingerprints = protocol_ops,
                        .allowed_response_kinds = response_kinds,
                        .max_request_envelope_bytes = max_request,
                        .max_response_envelope_bytes = max_response,
                        .accepts_embedded_capsules = accepts_capsules,
                        .accepts_capsule_restore = accepts_restore,
                        .semantic_tags = tags,
                        .metadata = metadata,
                    };
                }

                /// Release provider manifest owned storage.
                pub fn deinit(self: *@This()) void {
                    self.allocator.free(self.bytes);
                    self.allocator.free(self.label);
                    self.allocator.free(self.supported_program_manifest_fingerprints);
                    freeStringList(self.allocator, self.supported_protocol_labels);
                    self.allocator.free(self.supported_operation_sites);
                    self.allocator.free(self.supported_after_sites);
                    self.allocator.free(self.supported_protocol_op_fingerprints);
                    freeStringList(self.allocator, self.semantic_tags);
                    self.allocator.free(self.metadata);
                    self.bytes = &.{};
                }

                /// Return true when the provider claim covers the request envelope.
                pub fn supportsRequest(self: @This(), request: RequestEnvelope) bool {
                    if (!providerFieldsBoundToBytes(self)) return false;
                    request.validate() catch return false;
                    const requirement_label = requestRequirementLabel(request) orelse return false;
                    const protocol_op_fingerprint = requestProtocolOperationFingerprint(request) orelse return false;
                    if (!listAllowsString(self.supported_protocol_labels, requirement_label)) return false;
                    if (!listAllowsU64(self.supported_program_manifest_fingerprints, request.manifest_fingerprint)) return false;
                    if (request.bytes.len > self.max_request_envelope_bytes) return false;
                    if (request.capsule_image != null and !self.accepts_embedded_capsules) return false;
                    if (self.supported_protocol_op_fingerprints.len != 0 and !listAllowsU64(self.supported_protocol_op_fingerprints, protocol_op_fingerprint)) return false;
                    const operation_sites_constrained = self.supported_operation_sites.len != 0;
                    const after_sites_constrained = self.supported_after_sites.len != 0;
                    switch (request.kind) {
                        .operation => {
                            if (!operation_sites_constrained and after_sites_constrained) return false;
                            if (operation_sites_constrained and !listAllowsUsize(self.supported_operation_sites, request.site_index)) return false;
                            return true;
                        },
                        .after => {
                            if (!after_sites_constrained and operation_sites_constrained) return false;
                            if (after_sites_constrained and !listAllowsUsize(self.supported_after_sites, request.site_index)) return false;
                            return true;
                        },
                    }
                }
            };

            /// Deterministic capability grant authorizing a provider to answer request subsets.
            pub const Capability = struct {
                allocator: std.mem.Allocator,
                bytes: []u8,
                version: u32,
                fingerprint: u64,
                issuer_label: []u8,
                provider_fingerprint: u64,
                manifest_fingerprint: u64,
                allowed_request_kinds: RequestKindSet,
                allowed_program_labels: []const []const u8,
                allowed_plan_hashes: []const u64,
                allowed_operation_sites: []const usize,
                allowed_after_sites: []const usize,
                allowed_protocol_op_fingerprints: []const u64,
                allowed_requirement_labels: []const []const u8,
                allowed_op_names: []const []const u8,
                allowed_response_kinds: Policy.ResponseKindSet,
                allowed_response_refs: []lowering_api.ValueRef,
                allow_embedded_capsule_response_handling: bool,
                allow_capsule_restore: bool,
                max_request_bytes: usize,
                max_response_bytes: usize,
                max_payload_bytes: usize,
                max_capsule_image_bytes: usize,
                journal_policy_fingerprint: ?u64,
                expires_at_generation: ?u64,
                parent_capability_fingerprint: ?u64,
                attenuation_path_fingerprint: u64,

                /// Options used to encode a capability grant.
                pub const Options = struct {
                    issuer_label: []const u8,
                    provider_fingerprint: u64,
                    manifest_fingerprint: u64,
                    allowed_request_kinds: ?RequestKindSet = null,
                    allowed_program_labels: []const []const u8 = &.{},
                    allowed_plan_hashes: []const u64 = &.{},
                    allowed_operation_sites: []const usize = &.{},
                    allowed_after_sites: []const usize = &.{},
                    allowed_protocol_op_fingerprints: []const u64 = &.{},
                    allowed_requirement_labels: []const []const u8 = &.{},
                    allowed_op_names: []const []const u8 = &.{},
                    allowed_response_kinds: Policy.ResponseKindSet = .{},
                    allowed_response_refs: []const lowering_api.ValueRef = &.{},
                    allow_embedded_capsule_response_handling: bool = true,
                    allow_capsule_restore: bool = true,
                    max_request_bytes: usize = std.math.maxInt(usize),
                    max_response_bytes: usize = std.math.maxInt(usize),
                    max_payload_bytes: usize = std.math.maxInt(usize),
                    max_capsule_image_bytes: usize = std.math.maxInt(usize),
                    journal_policy_fingerprint: ?u64 = null,
                    expires_at_generation: ?u64 = null,
                    parent_capability_fingerprint: ?u64 = null,
                    attenuation_path_fingerprint: ?u64 = null,
                };

                /// Optional narrowing arguments for deterministic attenuation.
                pub const Attenuation = struct {
                    allowed_request_kinds: ?RequestKindSet = null,
                    allowed_program_labels: ?[]const []const u8 = null,
                    allowed_plan_hashes: ?[]const u64 = null,
                    allowed_operation_sites: ?[]const usize = null,
                    allowed_after_sites: ?[]const usize = null,
                    allowed_protocol_op_fingerprints: ?[]const u64 = null,
                    allowed_requirement_labels: ?[]const []const u8 = null,
                    allowed_op_names: ?[]const []const u8 = null,
                    allowed_response_kinds: ?Policy.ResponseKindSet = null,
                    allowed_response_refs: ?[]const lowering_api.ValueRef = null,
                    allow_embedded_capsule_response_handling: ?bool = null,
                    allow_capsule_restore: ?bool = null,
                    max_request_bytes: ?usize = null,
                    max_response_bytes: ?usize = null,
                    max_payload_bytes: ?usize = null,
                    max_capsule_image_bytes: ?usize = null,
                    expires_at_generation: ?u64 = null,
                };

                /// Encode a capability grant into deterministic owned bytes.
                pub fn encode(allocator: std.mem.Allocator, options: Options) Error!@This() {
                    const grant = capabilityGrantFingerprint(options);
                    const path = options.attenuation_path_fingerprint orelse capabilityPathFingerprint(options.parent_capability_fingerprint, options.provider_fingerprint, 0, grant);
                    var writer = Writer.init(allocator);
                    errdefer writer.deinit();
                    try writeCapabilityPayload(&writer, options, path);
                    const payload = writer.bytes.items;
                    const fingerprint = exchangeFingerprint("ability.exchange.capability", exchange_capability_fingerprint_version, payload);
                    try writer.writeU64(fingerprint);
                    return capabilityFromOptions(allocator, try writer.toOwnedSlice(), fingerprint, options, path);
                }

                /// Decode and validate a capability grant image.
                pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) Error!@This() {
                    const payload = try checkedPayload(bytes, "ability.exchange.capability", exchange_capability_fingerprint_version);
                    var reader = Reader.init(payload);
                    try reader.expectBytes(capability_magic);
                    const format = try reader.readU32();
                    if (format != exchange_capability_format_version) return error.ProgramContractViolation;
                    if (try reader.readU32() != exchange_capability_fingerprint_version) return error.ProgramContractViolation;
                    const version = try reader.readU32();
                    if (version != 1) return error.ProgramContractViolation;
                    const issuer = try allocator.dupe(u8, try reader.readLenBytes());
                    errdefer allocator.free(issuer);
                    const provider_fp = try reader.readU64();
                    const manifest_fp = try reader.readU64();
                    const request_kinds = try readRequestKindSet(&reader);
                    const program_labels = try readStringList(allocator, &reader);
                    errdefer freeStringList(allocator, program_labels);
                    const plan_hashes = try readU64List(allocator, &reader);
                    errdefer allocator.free(plan_hashes);
                    const operation_sites = try readUsizeList(allocator, &reader);
                    errdefer allocator.free(operation_sites);
                    const after_sites = try readUsizeList(allocator, &reader);
                    errdefer allocator.free(after_sites);
                    const protocol_ops = try readU64List(allocator, &reader);
                    errdefer allocator.free(protocol_ops);
                    const requirement_labels = try readStringList(allocator, &reader);
                    errdefer freeStringList(allocator, requirement_labels);
                    const op_names = try readStringList(allocator, &reader);
                    errdefer freeStringList(allocator, op_names);
                    const response_kinds = try readResponseKindSet(&reader);
                    const response_refs = try readValueRefList(allocator, &reader);
                    errdefer allocator.free(response_refs);
                    const allow_capsule_response = try reader.readBool();
                    const allow_restore = try reader.readBool();
                    const max_request = try reader.readUsize();
                    const max_response = try reader.readUsize();
                    const max_payload = try reader.readUsize();
                    const max_capsule = try reader.readUsize();
                    const journal_policy = try readOptionalU64(&reader);
                    const expires_at = try readOptionalU64(&reader);
                    const parent = try readOptionalU64(&reader);
                    const path = try reader.readU64();
                    if (!reader.eof()) return error.ProgramContractViolation;
                    const owned = try allocator.dupe(u8, bytes);
                    errdefer allocator.free(owned);
                    return .{
                        .allocator = allocator,
                        .bytes = owned,
                        .version = version,
                        .fingerprint = try checkedBytesFingerprint(bytes, "ability.exchange.capability", exchange_capability_fingerprint_version),
                        .issuer_label = issuer,
                        .provider_fingerprint = provider_fp,
                        .manifest_fingerprint = manifest_fp,
                        .allowed_request_kinds = request_kinds,
                        .allowed_program_labels = program_labels,
                        .allowed_plan_hashes = plan_hashes,
                        .allowed_operation_sites = operation_sites,
                        .allowed_after_sites = after_sites,
                        .allowed_protocol_op_fingerprints = protocol_ops,
                        .allowed_requirement_labels = requirement_labels,
                        .allowed_op_names = op_names,
                        .allowed_response_kinds = response_kinds,
                        .allowed_response_refs = response_refs,
                        .allow_embedded_capsule_response_handling = allow_capsule_response,
                        .allow_capsule_restore = allow_restore,
                        .max_request_bytes = max_request,
                        .max_response_bytes = max_response,
                        .max_payload_bytes = max_payload,
                        .max_capsule_image_bytes = max_capsule,
                        .journal_policy_fingerprint = journal_policy,
                        .expires_at_generation = expires_at,
                        .parent_capability_fingerprint = parent,
                        .attenuation_path_fingerprint = path,
                    };
                }

                /// Release capability-owned storage.
                pub fn deinit(self: *@This()) void {
                    self.allocator.free(self.bytes);
                    self.allocator.free(self.issuer_label);
                    freeStringList(self.allocator, self.allowed_program_labels);
                    self.allocator.free(self.allowed_plan_hashes);
                    self.allocator.free(self.allowed_operation_sites);
                    self.allocator.free(self.allowed_after_sites);
                    self.allocator.free(self.allowed_protocol_op_fingerprints);
                    freeStringList(self.allocator, self.allowed_requirement_labels);
                    freeStringList(self.allocator, self.allowed_op_names);
                    self.allocator.free(self.allowed_response_refs);
                    self.bytes = &.{};
                }

                /// Return a child capability whose authority is a subset of this capability.
                pub fn attenuate(self: @This(), allocator: std.mem.Allocator, args: Attenuation) Error!@This() {
                    if (!capabilityFieldsBoundToBytes(self)) return error.ProgramContractViolation;
                    const request_kinds = args.allowed_request_kinds orelse if (args.allowed_operation_sites != null or args.allowed_after_sites != null) RequestKindSet{
                        .operation = args.allowed_operation_sites != null,
                        .after = args.allowed_after_sites != null,
                    } else self.allowed_request_kinds;
                    if (!request_kinds.subsetOf(self.allowed_request_kinds)) return error.ProgramContractViolation;
                    if (args.allowed_response_kinds) |value| if (!responseKindSetSubset(value, self.allowed_response_kinds)) return error.ProgramContractViolation;
                    if (args.allowed_program_labels) |value| if (!stringListSubset(value, self.allowed_program_labels)) return error.ProgramContractViolation;
                    if (args.allowed_plan_hashes) |value| if (!u64ListSubset(value, self.allowed_plan_hashes)) return error.ProgramContractViolation;
                    if (args.allowed_operation_sites) |value| if (!usizeListSubset(value, self.allowed_operation_sites)) return error.ProgramContractViolation;
                    if (args.allowed_after_sites) |value| if (!usizeListSubset(value, self.allowed_after_sites)) return error.ProgramContractViolation;
                    if (args.allowed_protocol_op_fingerprints) |value| if (!u64ListSubset(value, self.allowed_protocol_op_fingerprints)) return error.ProgramContractViolation;
                    if (args.allowed_requirement_labels) |value| if (!stringListSubset(value, self.allowed_requirement_labels)) return error.ProgramContractViolation;
                    if (args.allowed_op_names) |value| if (!stringListSubset(value, self.allowed_op_names)) return error.ProgramContractViolation;
                    if (args.allowed_response_refs) |value| if (!valueRefListSubset(value, self.allowed_response_refs)) return error.ProgramContractViolation;
                    if ((args.allow_embedded_capsule_response_handling orelse self.allow_embedded_capsule_response_handling) and !self.allow_embedded_capsule_response_handling) return error.ProgramContractViolation;
                    if ((args.allow_capsule_restore orelse self.allow_capsule_restore) and !self.allow_capsule_restore) return error.ProgramContractViolation;
                    if (args.expires_at_generation) |child_expiry| {
                        if (self.expires_at_generation) |parent_expiry| {
                            if (child_expiry > parent_expiry) return error.ProgramContractViolation;
                        }
                    }
                    const max_request = args.max_request_bytes orelse self.max_request_bytes;
                    const max_response = args.max_response_bytes orelse self.max_response_bytes;
                    const max_payload = args.max_payload_bytes orelse self.max_payload_bytes;
                    const max_capsule = args.max_capsule_image_bytes orelse self.max_capsule_image_bytes;
                    if (max_request > self.max_request_bytes or max_response > self.max_response_bytes or max_payload > self.max_payload_bytes or max_capsule > self.max_capsule_image_bytes) return error.ProgramContractViolation;
                    var options: Options = .{
                        .issuer_label = self.issuer_label,
                        .provider_fingerprint = self.provider_fingerprint,
                        .manifest_fingerprint = self.manifest_fingerprint,
                        .allowed_request_kinds = request_kinds,
                        .allowed_program_labels = args.allowed_program_labels orelse self.allowed_program_labels,
                        .allowed_plan_hashes = args.allowed_plan_hashes orelse self.allowed_plan_hashes,
                        .allowed_operation_sites = args.allowed_operation_sites orelse self.allowed_operation_sites,
                        .allowed_after_sites = args.allowed_after_sites orelse self.allowed_after_sites,
                        .allowed_protocol_op_fingerprints = args.allowed_protocol_op_fingerprints orelse self.allowed_protocol_op_fingerprints,
                        .allowed_requirement_labels = args.allowed_requirement_labels orelse self.allowed_requirement_labels,
                        .allowed_op_names = args.allowed_op_names orelse self.allowed_op_names,
                        .allowed_response_kinds = args.allowed_response_kinds orelse self.allowed_response_kinds,
                        .allowed_response_refs = args.allowed_response_refs orelse self.allowed_response_refs,
                        .allow_embedded_capsule_response_handling = args.allow_embedded_capsule_response_handling orelse self.allow_embedded_capsule_response_handling,
                        .allow_capsule_restore = args.allow_capsule_restore orelse self.allow_capsule_restore,
                        .max_request_bytes = max_request,
                        .max_response_bytes = max_response,
                        .max_payload_bytes = max_payload,
                        .max_capsule_image_bytes = max_capsule,
                        .journal_policy_fingerprint = self.journal_policy_fingerprint,
                        .expires_at_generation = args.expires_at_generation orelse self.expires_at_generation,
                        .parent_capability_fingerprint = self.fingerprint,
                    };
                    options.attenuation_path_fingerprint = capabilityPathFingerprint(
                        self.fingerprint,
                        self.provider_fingerprint,
                        self.attenuation_path_fingerprint,
                        capabilityGrantFingerprint(options),
                    );
                    return Capability.encode(allocator, options);
                }

                /// Validate this capability against a request/provider pair.
                pub fn allowsRequest(self: @This(), request: RequestEnvelope, provider: ProviderManifest) ValidationReport {
                    return validateRequestCapability(self, provider, request);
                }
            };

            /// Capability authorization sidecar. It is deliberately outside response bytes/fingerprints.
            pub const Authorization = struct {
                provider_fingerprint: u64,
                capability_fingerprint: u64,
                capability_path_fingerprint: u64,
                route_fingerprint: u64,
                request_envelope_fingerprint: u64,
                response_envelope_fingerprint: u64,
                authorization_fingerprint: u64,

                /// Construct an authorization witness for a routed response.
                pub fn forResponse(route: Route, response: ResponseEnvelope) Error!@This() {
                    if (route.request_envelope_fingerprint != response.request_envelope_fingerprint) return error.ProgramContractViolation;
                    var value = Authorization{
                        .provider_fingerprint = route.provider_fingerprint,
                        .capability_fingerprint = route.capability_fingerprint,
                        .capability_path_fingerprint = route.capability_path_fingerprint,
                        .route_fingerprint = route.fingerprint,
                        .request_envelope_fingerprint = route.request_envelope_fingerprint,
                        .response_envelope_fingerprint = response.fingerprint,
                        .authorization_fingerprint = 0,
                    };
                    value.authorization_fingerprint = fingerprintAuthorization(value);
                    return value;
                }

                /// Encode this authorization witness into deterministic bytes.
                pub fn encode(self: @This(), allocator: std.mem.Allocator) Error![]u8 {
                    var writer = Writer.init(allocator);
                    errdefer writer.deinit();
                    try writer.writeBytes(authorization_magic);
                    try writer.writeU32(exchange_authorization_fingerprint_version);
                    try writer.writeU64(self.provider_fingerprint);
                    try writer.writeU64(self.capability_fingerprint);
                    try writer.writeU64(self.capability_path_fingerprint);
                    try writer.writeU64(self.route_fingerprint);
                    try writer.writeU64(self.request_envelope_fingerprint);
                    try writer.writeU64(self.response_envelope_fingerprint);
                    try writer.writeU64(fingerprintAuthorization(self));
                    return writer.toOwnedSlice();
                }

                /// Decode and validate deterministic authorization bytes.
                pub fn decode(bytes: []const u8) Error!@This() {
                    var reader = Reader.init(bytes);
                    try reader.expectBytes(authorization_magic);
                    if (try reader.readU32() != exchange_authorization_fingerprint_version) return error.ProgramContractViolation;
                    const value = Authorization{
                        .provider_fingerprint = try reader.readU64(),
                        .capability_fingerprint = try reader.readU64(),
                        .capability_path_fingerprint = try reader.readU64(),
                        .route_fingerprint = try reader.readU64(),
                        .request_envelope_fingerprint = try reader.readU64(),
                        .response_envelope_fingerprint = try reader.readU64(),
                        .authorization_fingerprint = try reader.readU64(),
                    };
                    if (!reader.eof()) return error.ProgramContractViolation;
                    if (value.authorization_fingerprint != fingerprintAuthorization(value)) return error.ProgramContractViolation;
                    return value;
                }
            };

            /// Deterministic result of matching a request to provider plus capability.
            pub const Route = struct {
                fingerprint: u64,
                request_envelope_fingerprint: u64,
                provider_fingerprint: u64,
                capability_fingerprint: u64,
                capability_path_fingerprint: u64,
                manifest_fingerprint: u64,
                request_kind: RequestKind,
                site_index: usize,
                site_fingerprint: u64,
                allowed_response_kinds: Policy.ResponseKindSet,
                max_response_bytes: usize,
                max_payload_bytes: usize,
                capsule_restore_allowed: bool,
                blockers: ValidationReport,

                /// Build a route witness from request, provider, capability, and policy.
                pub fn from(request: RequestEnvelope, provider: ProviderManifest, capability: Capability, policy: Policy) @This() {
                    var blockers = validateRequestCapability(capability, provider, request);
                    blockers.merge(validatePolicyRequestScope(policy, request));
                    const allowed_response_kinds = responseKindSetRestrictRefs(request, responseKindSetIntersection(
                        responseKindSetIntersection(provider.allowed_response_kinds, capability.allowed_response_kinds),
                        policy.allowed_response_kinds,
                    ), capability.allowed_response_refs);
                    if (!requestAcceptsAnyResponseKind(request, allowed_response_kinds)) blockers.add(.response_kind);
                    if (!requestAcceptsAnyResponseRef(request, allowed_response_kinds, capability.allowed_response_refs)) blockers.add(.response_ref);
                    if (!policyProviderAllowed(policy, provider.provider_fingerprint)) blockers.add(.provider_not_allowed);
                    if (!policyCapabilityAllowed(policy, capability.fingerprint)) blockers.add(.capability_not_allowed);
                    var route = Route{
                        .fingerprint = 0,
                        .request_envelope_fingerprint = request.fingerprint,
                        .provider_fingerprint = provider.provider_fingerprint,
                        .capability_fingerprint = capability.fingerprint,
                        .capability_path_fingerprint = capability.attenuation_path_fingerprint,
                        .manifest_fingerprint = request.manifest_fingerprint,
                        .request_kind = request.kind,
                        .site_index = request.site_index,
                        .site_fingerprint = request.site_fingerprint,
                        .allowed_response_kinds = allowed_response_kinds,
                        .max_response_bytes = @min(@min(provider.max_response_envelope_bytes, capability.max_response_bytes), policy.max_envelope_bytes),
                        .max_payload_bytes = if (policy.allow_response_value_images) @min(capability.max_payload_bytes, policy.max_payload_bytes) else 0,
                        .capsule_restore_allowed = capability.allow_capsule_restore and provider.accepts_capsule_restore and policy.allow_capsule_restore,
                        .blockers = blockers,
                    };
                    route.fingerprint = fingerprintRoute(route);
                    return route;
                }

                /// Return true when this route has no blockers.
                pub fn valid(self: @This()) bool {
                    return self.blockers.allowed();
                }
            };

            /// Host-owned deterministic route planner over provider/capability catalogs.
            pub const Router = struct {
                providers: []const ProviderManifest,
                capabilities: []const Capability,
                policy: Policy = .{},

                /// Router planning outcome.
                pub const Status = enum {
                    no_route,
                    one_route,
                    ambiguous_routes,
                    blocked_routes,
                };

                /// Route planning report.
                pub const Plan = struct {
                    status: Status,
                    route: ?Route = null,
                    blocked: ValidationReport = .{},
                    candidate_count: usize = 0,
                    blocked_count: usize = 0,
                };

                /// Plan a deterministic route for the request.
                pub fn plan(self: @This(), request: RequestEnvelope) Plan {
                    return self.planWithPolicy(request, self.policy);
                }

                /// Plan a deterministic route while also applying caller-supplied policy restrictions.
                pub fn planWithPolicy(self: @This(), request: RequestEnvelope, policy: Policy) Plan {
                    var first_valid: ?Route = null;
                    var first_blocked: ?Route = null;
                    var blocked_report: ValidationReport = .{};
                    var valid_count: usize = 0;
                    var blocked_count: usize = 0;
                    for (self.providers) |provider| {
                        capabilities_loop: for (self.capabilities) |capability| {
                            if (capability.provider_fingerprint != provider.provider_fingerprint) continue :capabilities_loop;
                            var route = Route.from(request, provider, capability, self.policy);
                            const caller_route = Route.from(request, provider, capability, policy);
                            route.blockers.merge(caller_route.blockers);
                            route.allowed_response_kinds = responseKindSetIntersection(route.allowed_response_kinds, caller_route.allowed_response_kinds);
                            route.max_response_bytes = @min(route.max_response_bytes, caller_route.max_response_bytes);
                            route.max_payload_bytes = @min(route.max_payload_bytes, caller_route.max_payload_bytes);
                            route.capsule_restore_allowed = route.capsule_restore_allowed and caller_route.capsule_restore_allowed;
                            if (!requestAcceptsAnyResponseKind(request, route.allowed_response_kinds)) route.blockers.add(.response_kind);
                            route.fingerprint = fingerprintRoute(route);
                            if (route.valid()) {
                                valid_count += 1;
                                if (first_valid == null) first_valid = route;
                            } else {
                                blocked_count += 1;
                                blocked_report.merge(route.blockers);
                                if (first_blocked == null) first_blocked = route;
                            }
                        }
                    }
                    if (valid_count == 1) return .{ .status = .one_route, .route = first_valid, .candidate_count = valid_count, .blocked_count = blocked_count };
                    if (valid_count > 1) {
                        var blocked: ValidationReport = .{};
                        blocked.add(.ambiguous_route);
                        return .{ .status = .ambiguous_routes, .route = first_valid, .blocked = blocked, .candidate_count = valid_count, .blocked_count = blocked_count };
                    }
                    if (blocked_count > 0) return .{ .status = .blocked_routes, .route = first_blocked, .blocked = blocked_report, .blocked_count = blocked_count };
                    var blocked: ValidationReport = .{};
                    blocked.add(.no_route);
                    return .{ .status = .no_route, .blocked = blocked };
                }

                /// Look up a capability by fingerprint.
                pub fn capabilityByFingerprint(self: @This(), fingerprint: u64) ?*const Capability {
                    for (self.capabilities) |*capability| if (capability.fingerprint == fingerprint) return capability;
                    return null;
                }
            };

            /// Options used while producing request envelopes.
            pub const RequestOptions = struct {
                capsule: ?Session.Capsule.Image = null,
                journal: ?*Session.Journal = null,
                journal_branch_id: ?[]const u8 = null,
            };

            /// Canonical typed request envelope for a yielded operation or after hook.
            pub const RequestEnvelope = struct {
                allocator: std.mem.Allocator,
                bytes: []u8,
                fingerprint: u64,
                manifest_fingerprint: u64,
                program_label: []const u8,
                plan_label: []const u8,
                plan_hash: u64,
                kind: RequestKind,
                request_fingerprint: u64,
                trace_fingerprint: u64,
                turn_index: usize,
                site_index: usize,
                site_fingerprint: u64,
                semantic_label: ?[]const u8,
                name: []const u8,
                mode: plan_types.ControlMode,
                value_ref: lowering_api.ValueRef,
                value_image: []u8,
                value_fingerprint: u64,
                expected_resume_ref: ?lowering_api.ValueRef,
                expected_return_ref: ?lowering_api.ValueRef,
                expected_after_ref: ?lowering_api.ValueRef,
                result_ref: lowering_api.ValueRef,
                capsule_image: ?[]u8 = null,
                capsule_image_fingerprint: ?u64 = null,
                journal_branch_id: ?[]const u8 = null,

                /// Encode an operation request yielded by Program.Session.
                pub fn fromRequest(allocator: std.mem.Allocator, request: Session.Request, options: RequestOptions) Error!@This() {
                    const trace = request.trace();
                    const value_image = try encodeRequestValueImage(allocator, request);
                    defer allocator.free(value_image);
                    const manifest_image = try manifestFingerprintForCurrentProgram(allocator);
                    var envelope = try encodeRequestEnvelope(allocator, .{
                        .kind = .operation,
                        .manifest_fingerprint = manifest_image,
                        .request_fingerprint = trace.fingerprint,
                        .trace_fingerprint = trace.fingerprint,
                        .turn_index = trace.turn_index,
                        .site_index = trace.operation_site_index,
                        .site_fingerprint = trace.operation_site_fingerprint,
                        .semantic_label = trace.semantic_label,
                        .name = trace.op_name,
                        .mode = trace.mode,
                        .value_ref = trace.payload_ref,
                        .value_image = value_image,
                        .value_fingerprint = trace.payload_value_fingerprint,
                        .expected_resume_ref = if (trace.mode == .abort) null else trace.resume_ref,
                        .expected_return_ref = if (trace.mode == .transform) null else trace.result_ref,
                        .expected_after_ref = null,
                        .result_ref = trace.result_ref,
                        .capsule = options.capsule,
                        .journal_branch_id = options.journal_branch_id,
                    });
                    errdefer envelope.deinit();
                    try envelope.validate();
                    if (options.journal) |journal| {
                        const start_len = journal.entries.items.len;
                        errdefer journal.truncateEntries(start_len);
                        try journal.appendRequest(.{ .operation = trace });
                        if (options.capsule) |capsule| try journal.appendCapsuleImage(capsule);
                    }
                    return envelope;
                }

                /// Encode an after-continuation request yielded by Program.Session.
                pub fn fromAfter(allocator: std.mem.Allocator, request: Session.AfterRequest, options: RequestOptions) Error!@This() {
                    const trace = request.trace();
                    const value_image = try encodeAfterValueImage(allocator, request);
                    defer allocator.free(value_image);
                    const manifest_image = try manifestFingerprintForCurrentProgram(allocator);
                    var envelope = try encodeRequestEnvelope(allocator, .{
                        .kind = .after,
                        .manifest_fingerprint = manifest_image,
                        .request_fingerprint = trace.fingerprint,
                        .trace_fingerprint = trace.fingerprint,
                        .turn_index = trace.turn_index,
                        .site_index = trace.after_site_index,
                        .site_fingerprint = trace.after_site_fingerprint,
                        .semantic_label = trace.semantic_label,
                        .name = trace.original_op_name,
                        .mode = .transform,
                        .value_ref = trace.current_value_ref,
                        .value_image = value_image,
                        .value_fingerprint = trace.current_value_fingerprint,
                        .expected_resume_ref = null,
                        .expected_return_ref = null,
                        .expected_after_ref = trace.expected_output_ref,
                        .result_ref = trace.result_ref,
                        .capsule = options.capsule,
                        .journal_branch_id = options.journal_branch_id,
                    });
                    errdefer envelope.deinit();
                    try envelope.validate();
                    if (options.journal) |journal| {
                        const start_len = journal.entries.items.len;
                        errdefer journal.truncateEntries(start_len);
                        try journal.appendRequest(.{ .after = trace });
                        if (options.capsule) |capsule| try journal.appendCapsuleImage(capsule);
                    }
                    return envelope;
                }

                /// Decode and validate a request envelope for this Program.
                pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) Error!@This() {
                    return decodeWithPolicy(allocator, bytes, .{});
                }

                /// Decode and validate a request envelope after applying policy limits before payload copies.
                pub fn decodeWithPolicy(allocator: std.mem.Allocator, bytes: []const u8, policy: Policy) Error!@This() {
                    if (bytes.len > policy.max_envelope_bytes) return error.ProgramContractViolation;
                    const payload = try checkedPayload(bytes, "ability.exchange.request", exchange_request_fingerprint_version);
                    var reader = Reader.init(payload);
                    try reader.expectBytes(request_magic);
                    if (try reader.readU32() != exchange_request_format_version) return error.ProgramContractViolation;
                    if (try reader.readU32() != exchange_request_fingerprint_version) return error.ProgramContractViolation;
                    const manifest_fingerprint = try reader.readU64();
                    var envelope_owned = false;
                    const program_label_owned = try dupeExpectedString(allocator, &reader, label);
                    errdefer if (!envelope_owned) allocator.free(program_label_owned);
                    const plan = try dupeExpectedString(allocator, &reader, body_compiled_plan.label);
                    errdefer if (!envelope_owned) allocator.free(plan);
                    const decoded_plan_hash = try reader.readU64();
                    if (decoded_plan_hash != body_compiled_plan_hash) return error.ProgramContractViolation;
                    const kind_value = try readRequestKind(&reader);
                    const request_fingerprint = try reader.readU64();
                    const trace_fingerprint = try reader.readU64();
                    const turn_index = try reader.readUsize();
                    const site_index = try reader.readUsize();
                    const site_fingerprint = try reader.readU64();
                    switch (kind_value) {
                        .operation => if (!Policy.policyAllowsSite(policy.allowed_operation_sites, site_index)) return error.ProgramContractViolation,
                        .after => if (!Policy.policyAllowsSite(policy.allowed_after_sites, site_index)) return error.ProgramContractViolation,
                    }
                    const semantic_label = try readOptionalOwnedBytes(allocator, &reader);
                    errdefer if (!envelope_owned) if (semantic_label) |value| allocator.free(value);
                    const name_value = try allocator.dupe(u8, try reader.readLenBytes());
                    errdefer if (!envelope_owned) allocator.free(name_value);
                    const mode = try readExchangeControlMode(&reader);
                    const value_ref = try readExchangeValueRef(&reader);
                    const value_fingerprint = try reader.readU64();
                    const value_image_slice = try reader.readLenBytes();
                    if (value_image_slice.len > policy.max_payload_bytes) return error.ProgramContractViolation;
                    const value_image = try allocator.dupe(u8, value_image_slice);
                    errdefer if (!envelope_owned) allocator.free(value_image);
                    const expected_resume_ref = try readOptionalValueRef(&reader);
                    const expected_return_ref = try readOptionalValueRef(&reader);
                    const expected_after_ref = try readOptionalValueRef(&reader);
                    const result_ref = try readExchangeValueRef(&reader);
                    const capsule_image = if (try reader.readBool()) blk: {
                        if (!policy.allow_capsules) return error.ProgramContractViolation;
                        const capsule_slice = try reader.readLenBytes();
                        const capsule_limit = policy.max_capsule_image_bytes orelse policy.max_payload_bytes;
                        if (capsule_slice.len > capsule_limit) return error.ProgramContractViolation;
                        const capsule_bytes = try allocator.dupe(u8, capsule_slice);
                        errdefer if (!envelope_owned) allocator.free(capsule_bytes);
                        const fingerprint = Session.capsuleImageFingerprint(capsule_bytes);
                        const encoded_fingerprint = try reader.readU64();
                        if (fingerprint != encoded_fingerprint) return error.ProgramContractViolation;
                        break :blk capsule_bytes;
                    } else null;
                    errdefer if (!envelope_owned) if (capsule_image) |image| allocator.free(image);
                    const capsule_fingerprint = if (capsule_image != null) Session.capsuleImageFingerprint(capsule_image.?) else null;
                    const branch_id = try readOptionalOwnedBytes(allocator, &reader);
                    errdefer if (!envelope_owned) if (branch_id) |value| allocator.free(value);
                    if (!reader.eof()) return error.ProgramContractViolation;
                    const owned = allocator.dupe(u8, bytes) catch |err| return mapProgramRunError(Error, err);
                    errdefer if (!envelope_owned) allocator.free(owned);
                    var envelope = RequestEnvelope{
                        .allocator = allocator,
                        .bytes = owned,
                        .fingerprint = try checkedBytesFingerprint(bytes, "ability.exchange.request", exchange_request_fingerprint_version),
                        .manifest_fingerprint = manifest_fingerprint,
                        .program_label = program_label_owned,
                        .plan_label = plan,
                        .plan_hash = decoded_plan_hash,
                        .kind = kind_value,
                        .request_fingerprint = request_fingerprint,
                        .trace_fingerprint = trace_fingerprint,
                        .turn_index = turn_index,
                        .site_index = site_index,
                        .site_fingerprint = site_fingerprint,
                        .semantic_label = semantic_label,
                        .name = name_value,
                        .mode = mode,
                        .value_ref = value_ref,
                        .value_image = value_image,
                        .value_fingerprint = value_fingerprint,
                        .expected_resume_ref = expected_resume_ref,
                        .expected_return_ref = expected_return_ref,
                        .expected_after_ref = expected_after_ref,
                        .result_ref = result_ref,
                        .capsule_image = capsule_image,
                        .capsule_image_fingerprint = capsule_fingerprint,
                        .journal_branch_id = branch_id,
                    };
                    envelope_owned = true;
                    validateRequestEnvelopeFields(envelope) catch |err| {
                        envelope.deinit();
                        return err;
                    };
                    return envelope;
                }

                /// Validate manifest, plan, site, value image, and capsule compatibility.
                pub fn validate(self: @This()) Error!void {
                    try validateRequestEnvelopeFields(self);
                    try validateRequestEnvelopeFieldsBoundToBytes(self);
                }

                /// Release request envelope storage.
                pub fn deinit(self: *@This()) void {
                    self.allocator.free(self.bytes);
                    self.allocator.free(self.program_label);
                    self.allocator.free(self.plan_label);
                    if (self.semantic_label) |value| self.allocator.free(value);
                    self.allocator.free(self.name);
                    self.allocator.free(self.value_image);
                    if (self.capsule_image) |image| self.allocator.free(image);
                    if (self.journal_branch_id) |branch| self.allocator.free(branch);
                    self.bytes = &.{};
                }
            };

            /// Options used while applying response envelopes.
            pub const ResponseOptions = struct {
                journal: ?*Session.Journal = null,
                request_envelope_fingerprint: ?u64 = null,
            };

            /// Canonical typed response envelope for host-supplied answers.
            pub const ResponseEnvelope = struct {
                allocator: std.mem.Allocator,
                bytes: []u8,
                fingerprint: u64,
                manifest_fingerprint: u64,
                request_envelope_fingerprint: u64,
                request_fingerprint: u64,
                kind: ResponseKind,
                response_ref: lowering_api.ValueRef,
                value_image: []u8,
                response_value_fingerprint: u64,
                response_trace_fingerprint: u64,
                authorization: ?Authorization = null,

                /// Encode a resume response for an operation request envelope.
                pub fn @"resume"(allocator: std.mem.Allocator, request: RequestEnvelope, value: anytype) Error!@This() {
                    return encodeResponseEnvelope(allocator, request, .@"resume", value);
                }

                /// Encode a return-now response for an operation request envelope.
                pub fn returnNow(allocator: std.mem.Allocator, request: RequestEnvelope, value: anytype) Error!@This() {
                    return encodeResponseEnvelope(allocator, request, .return_now, value);
                }

                /// Encode a resume-after response for an after request envelope.
                pub fn resumeAfter(allocator: std.mem.Allocator, request: RequestEnvelope, value: anytype) Error!@This() {
                    return encodeResponseEnvelope(allocator, request, .resume_after, value);
                }

                /// Decode and validate response bytes that are self-contained in the envelope.
                pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) Error!@This() {
                    return decodeWithPolicy(allocator, bytes, .{});
                }

                /// Decode and validate response bytes after applying policy limits before payload copies.
                pub fn decodeWithPolicy(allocator: std.mem.Allocator, bytes: []const u8, policy: Policy) Error!@This() {
                    if (bytes.len > policy.max_envelope_bytes) return error.ProgramContractViolation;
                    const payload = try checkedPayload(bytes, "ability.exchange.response", exchange_response_fingerprint_version);
                    var reader = Reader.init(payload);
                    try reader.expectBytes(response_magic);
                    if (try reader.readU32() != exchange_response_format_version) return error.ProgramContractViolation;
                    if (try reader.readU32() != exchange_response_fingerprint_version) return error.ProgramContractViolation;
                    const manifest_fingerprint = try reader.readU64();
                    const request_envelope_fingerprint = try reader.readU64();
                    const request_fingerprint = try reader.readU64();
                    const kind_value = try readExchangeResponseKind(&reader);
                    if (!policy.allowed_response_kinds.allows(kind_value)) return error.ProgramContractViolation;
                    const response_ref = try readExchangeValueRef(&reader);
                    const value_fingerprint = try reader.readU64();
                    const response_trace_fingerprint = try reader.readU64();
                    const value_image_slice = try reader.readLenBytes();
                    if (value_image_slice.len > policy.max_payload_bytes) return error.ProgramContractViolation;
                    if (!policy.allow_response_value_images and value_image_slice.len != 0) return error.ProgramContractViolation;
                    const value_image = try allocator.dupe(u8, value_image_slice);
                    errdefer allocator.free(value_image);
                    if (!reader.eof()) return error.ProgramContractViolation;
                    if (manifest_fingerprint != try manifestFingerprintForCurrentProgram(allocator)) return error.ProgramContractViolation;
                    const trace = responseTraceFromEnvelope(request_fingerprint, kind_value, response_ref, value_fingerprint);
                    if (trace.fingerprint != response_trace_fingerprint) return error.ProgramContractViolation;
                    try validateExchangeValueImage(allocator, response_ref, value_fingerprint, value_image);
                    const owned = allocator.dupe(u8, bytes) catch |err| return mapProgramRunError(Error, err);
                    errdefer allocator.free(owned);
                    return .{
                        .allocator = allocator,
                        .bytes = owned,
                        .fingerprint = try checkedBytesFingerprint(bytes, "ability.exchange.response", exchange_response_fingerprint_version),
                        .manifest_fingerprint = manifest_fingerprint,
                        .request_envelope_fingerprint = request_envelope_fingerprint,
                        .request_fingerprint = request_fingerprint,
                        .kind = kind_value,
                        .response_ref = response_ref,
                        .value_image = value_image,
                        .response_value_fingerprint = value_fingerprint,
                        .response_trace_fingerprint = response_trace_fingerprint,
                    };
                }

                /// Validate this response against the exact request envelope it answers.
                pub fn validateForRequest(self: @This(), request: RequestEnvelope) Error!void {
                    try request.validate();
                    if (self.manifest_fingerprint != request.manifest_fingerprint) return error.ProgramContractViolation;
                    if (self.request_envelope_fingerprint != request.fingerprint) return error.ProgramContractViolation;
                    if (self.request_fingerprint != request.request_fingerprint) return error.ProgramContractViolation;
                    try validateResponseEnvelopeFieldsBoundToBytes(self);
                    const expected_ref = try expectedResponseRef(request, self.kind);
                    if (!self.response_ref.eql(expected_ref)) return error.ProgramContractViolation;
                    const trace = responseTraceFromEnvelope(request.request_fingerprint, self.kind, self.response_ref, self.response_value_fingerprint);
                    if (trace.fingerprint != self.response_trace_fingerprint) return error.ProgramContractViolation;
                    try validateExchangeValueImage(self.allocator, self.response_ref, self.response_value_fingerprint, self.value_image);
                }

                /// Attach a deterministic authorization witness without changing response bytes.
                pub fn authorize(self: *@This(), route: Route) Error!void {
                    self.authorization = try Authorization.forResponse(route, self.*);
                }

                /// Release response envelope storage.
                pub fn deinit(self: *@This()) void {
                    self.allocator.free(self.bytes);
                    self.allocator.free(self.value_image);
                    self.bytes = &.{};
                }
            };

            /// Nonblocking transport-neutral runner over host-owned inbox/outbox storage.
            pub const MailboxRunner = struct {
                last_request_fingerprint: ?u64 = null,
                last_request_envelope_fingerprint: ?u64 = null,
                last_request_included_capsule: ?bool = null,
                last_request_journal_branch_id: ?[]u8 = null,
                last_request_journal_branch_allocator: ?std.mem.Allocator = null,
                last_route: ?Route = null,
                last_response_capability_required: bool = false,

                /// One nonblocking mailbox runner outcome.
                pub const Step = union(enum) {
                    parked: RequestEnvelope,
                    done: Result,
                    running,
                };

                /// Release runner-owned pending request state.
                pub fn deinit(self: *@This()) void {
                    self.clearLastRequestJournalBranch();
                }

                fn clearLastRequestJournalBranch(self: *@This()) void {
                    if (self.last_request_journal_branch_id) |branch| {
                        self.last_request_journal_branch_allocator.?.free(branch);
                    }
                    self.last_request_journal_branch_id = null;
                    self.last_request_journal_branch_allocator = null;
                }

                fn cloneJournalBranch(allocator: std.mem.Allocator, branch: ?[]const u8) Error!?[]u8 {
                    const value = branch orelse return null;
                    return allocator.dupe(u8, value) catch |err| return mapProgramRunError(Error, err);
                }

                fn adoptLastRequestJournalBranch(self: *@This(), allocator: std.mem.Allocator, branch: ?[]u8) void {
                    self.clearLastRequestJournalBranch();
                    self.last_request_journal_branch_id = branch;
                    self.last_request_journal_branch_allocator = if (branch != null) allocator else null;
                }

                fn appendOutboxEnvelope(allocator: std.mem.Allocator, outbox: anytype, envelope: RequestEnvelope) Error!void {
                    var outbox_envelope = RequestEnvelope.decode(allocator, envelope.bytes) catch |err| return mapProgramRunError(Error, err);
                    errdefer outbox_envelope.deinit();
                    outbox.append(outbox_envelope) catch |err| return mapProgramRunError(Error, err);
                }

                fn appendRoutedOutboxEnvelope(allocator: std.mem.Allocator, outbox: anytype, envelope: RequestEnvelope, route: Route) Error!void {
                    var outbox_envelope = RequestEnvelope.decode(allocator, envelope.bytes) catch |err| return mapProgramRunError(Error, err);
                    errdefer outbox_envelope.deinit();
                    const OutboxType = @TypeOf(outbox.*);
                    if (comptime @hasDecl(OutboxType, "appendRouted")) {
                        // appendRouted mirrors append: it takes envelope ownership only
                        // after success, so failures leave cleanup with the runner.
                        outbox.appendRouted(outbox_envelope, route) catch |err| return mapProgramRunError(Error, err);
                    } else {
                        outbox.append(outbox_envelope) catch |err| return mapProgramRunError(Error, err);
                    }
                }

                const JournalCheckpoint = struct {
                    ledger: *Session.Journal,
                    start_len: usize,
                };

                fn appendRouteSelectedJournal(journal: ?*Session.Journal, route: Route) Error!?JournalCheckpoint {
                    const ledger = journal orelse return null;
                    const start_len = ledger.entries.items.len;
                    try ledger.appendExchangeEvent(.{
                        .kind = .route_selected,
                        .provider_fingerprint = route.provider_fingerprint,
                        .capability_fingerprint = route.capability_fingerprint,
                        .route_fingerprint = route.fingerprint,
                        .request_envelope_fingerprint = route.request_envelope_fingerprint,
                    });
                    return .{ .ledger = ledger, .start_len = start_len };
                }

                fn appendRouteAwareOutboxEnvelope(
                    allocator: std.mem.Allocator,
                    outbox: anytype,
                    envelope: RequestEnvelope,
                    router: ?Router,
                    policy: Policy,
                    journal: ?*Session.Journal,
                ) Error!?Route {
                    if (router) |catalog| {
                        const route_plan = catalog.planWithPolicy(envelope, policy);
                        const route_required = policyRequiresRoute(policy) or policyRequiresRoute(catalog.policy);
                        const reject_ambiguous_routes = policy.reject_ambiguous_routes or catalog.policy.reject_ambiguous_routes;
                        const router_request_policy = validatePolicyRequestScope(catalog.policy, envelope);
                        if (!router_request_policy.allowed()) {
                            if (journal) |ledger| try ledger.appendExchangeEvent(.{
                                .kind = .route_blocked,
                                .request_envelope_fingerprint = envelope.fingerprint,
                                .blocker_tag = router_request_policy.firstTagName(),
                            });
                            return error.ProgramContractViolation;
                        }
                        switch (route_plan.status) {
                            .one_route => {
                                const route = route_plan.route.?;
                                const journal_checkpoint = try appendRouteSelectedJournal(journal, route);
                                errdefer if (journal_checkpoint) |checkpoint| checkpoint.ledger.truncateEntries(checkpoint.start_len);
                                try appendRoutedOutboxEnvelope(allocator, outbox, envelope, route);
                                return route;
                            },
                            .ambiguous_routes => {
                                if (!reject_ambiguous_routes and route_plan.route != null) {
                                    const route = route_plan.route.?;
                                    const journal_checkpoint = try appendRouteSelectedJournal(journal, route);
                                    errdefer if (journal_checkpoint) |checkpoint| checkpoint.ledger.truncateEntries(checkpoint.start_len);
                                    try appendRoutedOutboxEnvelope(allocator, outbox, envelope, route);
                                    return route;
                                }
                                if (journal) |ledger| try ledger.appendExchangeEvent(.{
                                    .kind = .route_blocked,
                                    .request_envelope_fingerprint = envelope.fingerprint,
                                    .blocker_tag = route_plan.blocked.firstTagName(),
                                });
                                return error.ProgramContractViolation;
                            },
                            .blocked_routes => {
                                if (!route_required and blockedRoutesAllowOptionalFallback(route_plan.blocked)) {} else {
                                    if (journal) |ledger| try ledger.appendExchangeEvent(.{
                                        .kind = .route_blocked,
                                        .request_envelope_fingerprint = envelope.fingerprint,
                                        .blocker_tag = route_plan.blocked.firstTagName(),
                                    });
                                    return error.ProgramContractViolation;
                                }
                            },
                            .no_route => {},
                        }
                        if (route_required) {
                            if (journal) |ledger| try ledger.appendExchangeEvent(.{
                                .kind = .route_blocked,
                                .request_envelope_fingerprint = envelope.fingerprint,
                                .blocker_tag = route_plan.blocked.firstTagName(),
                            });
                            return error.ProgramContractViolation;
                        }
                    } else if (policyRequiresRoute(policy)) return error.ProgramContractViolation;
                    try appendOutboxEnvelope(allocator, outbox, envelope);
                    return null;
                }

                fn validateCurrentRequestPolicy(
                    allocator: std.mem.Allocator,
                    session: *Session,
                    current_value: Session.Current,
                    policy: Policy,
                    include_capsule: bool,
                    journal_branch_id: ?[]const u8,
                ) Error!void {
                    switch (current_value) {
                        .request => |request| {
                            var envelope = try requestEnvelopeForCurrent(allocator, session, .{ .request = request }, include_capsule, journal_branch_id);
                            defer envelope.deinit();
                            try policy.validateRequest(envelope);
                        },
                        .after => |after| {
                            var envelope = try requestEnvelopeForCurrent(allocator, session, .{ .after = after }, include_capsule, journal_branch_id);
                            defer envelope.deinit();
                            try policy.validateRequest(envelope);
                        },
                        .none => {},
                    }
                }

                /// Advance one host turn, appending yielded requests and consuming one response if present.
                pub fn runStep(
                    self: *@This(),
                    session: *Session,
                    outbox: anytype,
                    inbox: anytype,
                    options: struct {
                        allocator: std.mem.Allocator,
                        policy: Policy = .{},
                        capsule: bool = false,
                        journal_branch_id: ?[]const u8 = null,
                        router: ?Router = null,
                        journal: ?*Session.Journal = null,
                    },
                ) Error!Step {
                    const current_value = try session.current();
                    if (try inbox.nextResponse()) |response_value| {
                        var response = response_value;
                        defer response.deinit();
                        const request_included_capsule = self.last_request_included_capsule orelse options.capsule;
                        const request_journal_branch_id = if (self.last_request_envelope_fingerprint != null) self.last_request_journal_branch_id else options.journal_branch_id;
                        try validateCurrentRequestPolicy(options.allocator, session, current_value, options.policy, request_included_capsule, request_journal_branch_id);
                        if (options.router) |router| try validateCurrentRequestPolicy(options.allocator, session, current_value, router.policy, request_included_capsule, request_journal_branch_id);
                        try options.policy.validateResponse(response);
                        if (options.router) |router| try router.policy.validateResponse(response);
                        var response_authorized_checkpoint: ?JournalCheckpoint = null;
                        errdefer if (response_authorized_checkpoint) |checkpoint| checkpoint.ledger.truncateEntries(checkpoint.start_len);
                        if (self.last_route) |route| {
                            var route_policy_report = validateRouteResponse(route, response);
                            route_policy_report.merge(validateRoutePolicies(route, options.router, options.policy));
                            var owned_current = try requestEnvelopeForCurrent(options.allocator, session, current_value, request_included_capsule, request_journal_branch_id);
                            defer owned_current.deinit();
                            route_policy_report.merge(validateRouteCurrentPlan(route, options.router, options.policy, owned_current));
                            if (!route_policy_report.allowed()) {
                                if (options.journal) |ledger| try ledger.appendExchangeEvent(.{
                                    .kind = .response_rejected,
                                    .provider_fingerprint = route.provider_fingerprint,
                                    .capability_fingerprint = route.capability_fingerprint,
                                    .route_fingerprint = route.fingerprint,
                                    .request_envelope_fingerprint = route.request_envelope_fingerprint,
                                    .response_envelope_fingerprint = response.fingerprint,
                                    .blocker_tag = route_policy_report.firstTagName(),
                                });
                                return error.ProgramContractViolation;
                            }
                        } else {
                            var owned_current = try requestEnvelopeForCurrent(options.allocator, session, current_value, request_included_capsule, request_journal_branch_id);
                            defer owned_current.deinit();
                            const unrouted_report = validateUnroutedResponsePlan(options.router, options.policy, owned_current);
                            if (!unrouted_report.allowed()) {
                                if (options.journal) |ledger| try ledger.appendExchangeEvent(.{
                                    .kind = .response_rejected,
                                    .request_envelope_fingerprint = owned_current.fingerprint,
                                    .response_envelope_fingerprint = response.fingerprint,
                                    .blocker_tag = unrouted_report.firstTagName(),
                                });
                                return error.ProgramContractViolation;
                            }
                        }
                        if (self.last_response_capability_required or responseCapabilityRequiredFor(options.router, options.policy)) {
                            const route = self.last_route orelse return error.ProgramContractViolation;
                            const router = options.router orelse return error.ProgramContractViolation;
                            const capability = router.capabilityByFingerprint(route.capability_fingerprint) orelse return error.ProgramContractViolation;
                            var owned_current = try requestEnvelopeForCurrent(options.allocator, session, current_value, request_included_capsule, request_journal_branch_id);
                            defer owned_current.deinit();
                            var report = validateRoutedResponseCapability(route, capability.*, owned_current, response);
                            report.merge(validateRoutePolicies(route, options.router, options.policy));
                            if (!report.allowed()) {
                                if (options.journal) |ledger| try ledger.appendExchangeEvent(.{
                                    .kind = .response_rejected,
                                    .provider_fingerprint = route.provider_fingerprint,
                                    .capability_fingerprint = route.capability_fingerprint,
                                    .route_fingerprint = route.fingerprint,
                                    .request_envelope_fingerprint = route.request_envelope_fingerprint,
                                    .response_envelope_fingerprint = response.fingerprint,
                                    .blocker_tag = report.firstTagName(),
                                });
                                return error.ProgramContractViolation;
                            }
                            if (options.journal) |ledger| {
                                const start_len = ledger.entries.items.len;
                                try ledger.appendExchangeEvent(.{
                                    .kind = .response_authorized,
                                    .provider_fingerprint = route.provider_fingerprint,
                                    .capability_fingerprint = route.capability_fingerprint,
                                    .route_fingerprint = route.fingerprint,
                                    .authorization_fingerprint = response.authorization.?.authorization_fingerprint,
                                    .request_envelope_fingerprint = route.request_envelope_fingerprint,
                                    .response_envelope_fingerprint = response.fingerprint,
                                });
                                response_authorized_checkpoint = .{ .ledger = ledger, .start_len = start_len };
                            }
                        }
                        try applyResponse(session, response, .{ .request_envelope_fingerprint = self.last_request_envelope_fingerprint });
                        self.last_request_fingerprint = null;
                        self.last_request_envelope_fingerprint = null;
                        self.last_request_included_capsule = null;
                        self.clearLastRequestJournalBranch();
                        self.last_route = null;
                        self.last_response_capability_required = false;
                        return .running;
                    }
                    return switch (current_value) {
                        .request => |request| blk: {
                            var envelope = try requestEnvelopeForCurrent(options.allocator, session, .{ .request = request }, options.capsule, options.journal_branch_id);
                            errdefer envelope.deinit();
                            try options.policy.validateRequest(envelope);
                            const response_capability_required = responseCapabilityRequiredFor(options.router, options.policy);
                            const route_refresh_required = routeRefreshRequiredFor(self.last_route, options.router, options.policy, envelope, self.last_response_capability_required, response_capability_required);
                            if (self.last_request_envelope_fingerprint != envelope.fingerprint or route_refresh_required) {
                                var owned_branch = try cloneJournalBranch(options.allocator, options.journal_branch_id);
                                errdefer if (owned_branch) |branch| options.allocator.free(branch);
                                self.last_route = try appendRouteAwareOutboxEnvelope(options.allocator, outbox, envelope, options.router, options.policy, options.journal);
                                self.last_request_fingerprint = envelope.request_fingerprint;
                                self.last_request_envelope_fingerprint = envelope.fingerprint;
                                self.last_request_included_capsule = options.capsule;
                                self.adoptLastRequestJournalBranch(options.allocator, owned_branch);
                                owned_branch = null;
                                self.last_response_capability_required = response_capability_required;
                            } else {
                                self.last_response_capability_required = response_capability_required;
                            }
                            break :blk .{ .parked = envelope };
                        },
                        .after => |after| blk: {
                            var envelope = try requestEnvelopeForCurrent(options.allocator, session, .{ .after = after }, options.capsule, options.journal_branch_id);
                            errdefer envelope.deinit();
                            try options.policy.validateRequest(envelope);
                            const response_capability_required = responseCapabilityRequiredFor(options.router, options.policy);
                            const route_refresh_required = routeRefreshRequiredFor(self.last_route, options.router, options.policy, envelope, self.last_response_capability_required, response_capability_required);
                            if (self.last_request_envelope_fingerprint != envelope.fingerprint or route_refresh_required) {
                                var owned_branch = try cloneJournalBranch(options.allocator, options.journal_branch_id);
                                errdefer if (owned_branch) |branch| options.allocator.free(branch);
                                self.last_route = try appendRouteAwareOutboxEnvelope(options.allocator, outbox, envelope, options.router, options.policy, options.journal);
                                self.last_request_fingerprint = envelope.request_fingerprint;
                                self.last_request_envelope_fingerprint = envelope.fingerprint;
                                self.last_request_included_capsule = options.capsule;
                                self.adoptLastRequestJournalBranch(options.allocator, owned_branch);
                                owned_branch = null;
                                self.last_response_capability_required = response_capability_required;
                            } else {
                                self.last_response_capability_required = response_capability_required;
                            }
                            break :blk .{ .parked = envelope };
                        },
                        .none => switch (try session.next()) {
                            .request => |request| blk: {
                                var envelope = try requestEnvelopeForCurrent(options.allocator, session, .{ .request = request }, options.capsule, options.journal_branch_id);
                                errdefer envelope.deinit();
                                try options.policy.validateRequest(envelope);
                                var owned_branch = try cloneJournalBranch(options.allocator, options.journal_branch_id);
                                errdefer if (owned_branch) |branch| options.allocator.free(branch);
                                self.last_route = try appendRouteAwareOutboxEnvelope(options.allocator, outbox, envelope, options.router, options.policy, options.journal);
                                self.last_request_fingerprint = envelope.request_fingerprint;
                                self.last_request_envelope_fingerprint = envelope.fingerprint;
                                self.last_request_included_capsule = options.capsule;
                                self.adoptLastRequestJournalBranch(options.allocator, owned_branch);
                                owned_branch = null;
                                self.last_response_capability_required = responseCapabilityRequiredFor(options.router, options.policy);
                                break :blk .{ .parked = envelope };
                            },
                            .after => |after| blk: {
                                var envelope = try requestEnvelopeForCurrent(options.allocator, session, .{ .after = after }, options.capsule, options.journal_branch_id);
                                errdefer envelope.deinit();
                                try options.policy.validateRequest(envelope);
                                var owned_branch = try cloneJournalBranch(options.allocator, options.journal_branch_id);
                                errdefer if (owned_branch) |branch| options.allocator.free(branch);
                                self.last_route = try appendRouteAwareOutboxEnvelope(options.allocator, outbox, envelope, options.router, options.policy, options.journal);
                                self.last_request_fingerprint = envelope.request_fingerprint;
                                self.last_request_envelope_fingerprint = envelope.fingerprint;
                                self.last_request_included_capsule = options.capsule;
                                self.adoptLastRequestJournalBranch(options.allocator, owned_branch);
                                owned_branch = null;
                                self.last_response_capability_required = responseCapabilityRequiredFor(options.router, options.policy);
                                break :blk .{ .parked = envelope };
                            },
                            .done => |result| .{ .done = result },
                        },
                    };
                }
            };

            /// Apply a validated response envelope to the current parked session request.
            pub fn applyResponse(session: *Session, response: ResponseEnvelope, options: ResponseOptions) Error!void {
                const current_value = try session.current();
                const request_envelope = switch (current_value) {
                    .request => |request| try RequestEnvelope.fromRequest(response.allocator, request, .{}),
                    .after => |after| try RequestEnvelope.fromAfter(response.allocator, after, .{}),
                    .none => return error.ProgramContractViolation,
                };
                var owned_request = request_envelope;
                defer owned_request.deinit();
                try validateResponseForCurrentRequest(response, owned_request, options.request_envelope_fingerprint);
                const response_trace: Session.Trace.Response = .{
                    .request_fingerprint = response.request_fingerprint,
                    .kind = response.kind,
                    .response_ref = response.response_ref,
                    .response_value_fingerprint = response.response_value_fingerprint,
                    .fingerprint = response.response_trace_fingerprint,
                };
                const journal_checkpoint = if (options.journal) |journal| checkpoint: {
                    const start_len = journal.entries.items.len;
                    try journal.appendValidatedResponseValueImage(response_trace, response.value_image);
                    break :checkpoint .{ .journal = journal, .start_len = start_len };
                } else null;
                errdefer if (journal_checkpoint) |checkpoint| checkpoint.journal.truncateEntries(checkpoint.start_len);
                try applyResponseValue(session, current_value, response);
            }

            fn validateResponseForCurrentRequest(response: ResponseEnvelope, request: RequestEnvelope, request_envelope_fingerprint: ?u64) Error!void {
                try request.validate();
                if (response.manifest_fingerprint != request.manifest_fingerprint) return error.ProgramContractViolation;
                if (response.request_envelope_fingerprint != (request_envelope_fingerprint orelse request.fingerprint)) return error.ProgramContractViolation;
                if (response.request_fingerprint != request.request_fingerprint) return error.ProgramContractViolation;
                try validateResponseEnvelopeFieldsBoundToBytes(response);
                const expected_ref = try expectedResponseRef(request, response.kind);
                if (!response.response_ref.eql(expected_ref)) return error.ProgramContractViolation;
                const trace = responseTraceFromEnvelope(request.request_fingerprint, response.kind, response.response_ref, response.response_value_fingerprint);
                if (trace.fingerprint != response.response_trace_fingerprint) return error.ProgramContractViolation;
                try validateExchangeValueImage(response.allocator, response.response_ref, response.response_value_fingerprint, response.value_image);
            }

            /// Validate a capability grant against a request envelope and provider manifest.
            pub fn validateRequestCapability(capability: Capability, provider: ProviderManifest, request: RequestEnvelope) ValidationReport {
                request.validate() catch {
                    var invalid: ValidationReport = .{};
                    invalid.add(.invalid_envelope);
                    return invalid;
                };
                var report = validateCapabilityRequestScope(capability, request);
                if (!providerFieldsBoundToBytes(provider)) report.add(.wrong_provider);
                if (provider.provider_fingerprint != capability.provider_fingerprint) report.add(.wrong_provider);
                if (!provider.supportsRequest(request)) report.add(switch (request.kind) {
                    .operation => .operation_site,
                    .after => .after_site,
                });
                if (request.bytes.len > provider.max_request_envelope_bytes) report.add(.request_too_large);
                if (request.capsule_image != null and !provider.accepts_embedded_capsules) report.add(.embedded_capsule);
                return report;
            }

            fn validateCapabilityRequestScope(capability: Capability, request: RequestEnvelope) ValidationReport {
                var report: ValidationReport = .{};
                request.validate() catch {
                    report.add(.invalid_envelope);
                    return report;
                };
                if (!capabilityFieldsBoundToBytes(capability)) report.add(.wrong_capability);
                const requirement_label = requestRequirementLabel(request) orelse {
                    report.add(.invalid_envelope);
                    return report;
                };
                const protocol_op_fingerprint = requestProtocolOperationFingerprint(request) orelse {
                    report.add(.invalid_envelope);
                    return report;
                };
                if (request.manifest_fingerprint != capability.manifest_fingerprint) report.add(.wrong_manifest);
                if (!capability.allowed_request_kinds.allows(request.kind)) report.add(.request_kind);
                if (capability.expires_at_generation) |expires_at| {
                    if (request.turn_index >= expires_at) report.add(.expired_capability);
                }
                if (!listAllowsString(capability.allowed_program_labels, request.program_label)) report.add(.wrong_program_label);
                if (!listAllowsU64(capability.allowed_plan_hashes, request.plan_hash)) report.add(.wrong_plan_hash);
                if (capability.journal_policy_fingerprint) |expected_policy| {
                    const branch_id = request.journal_branch_id orelse {
                        report.add(.wrong_journal_policy);
                        return report;
                    };
                    if (journalBranchPolicyFingerprint(branch_id) != expected_policy) report.add(.wrong_journal_policy);
                }
                switch (request.kind) {
                    .operation => if (!listAllowsUsize(capability.allowed_operation_sites, request.site_index)) report.add(.operation_site),
                    .after => if (!listAllowsUsize(capability.allowed_after_sites, request.site_index)) report.add(.after_site),
                }
                if (!listAllowsU64(capability.allowed_protocol_op_fingerprints, protocol_op_fingerprint)) report.add(.protocol_operation);
                if (!listAllowsString(capability.allowed_requirement_labels, requirement_label)) report.add(.protocol_operation);
                if (!listAllowsString(capability.allowed_op_names, request.name)) report.add(.protocol_operation);
                if (request.bytes.len > capability.max_request_bytes) report.add(.request_too_large);
                if (request.value_image.len > capability.max_payload_bytes) report.add(.payload_too_large);
                if (request.capsule_image) |image| {
                    if (!capability.allow_embedded_capsule_response_handling) report.add(.embedded_capsule);
                    if (image.len > capability.max_capsule_image_bytes) report.add(.capsule_too_large);
                }
                return report;
            }

            fn validatePolicyRequestScope(policy: Policy, request: RequestEnvelope) ValidationReport {
                var report: ValidationReport = .{};
                if (request.bytes.len > policy.max_envelope_bytes) report.add(.request_too_large);
                if (request.value_image.len > policy.max_payload_bytes) report.add(.payload_too_large);
                if (request.capsule_image != null and !policy.allow_capsules) report.add(.embedded_capsule);
                if (request.capsule_image) |image| {
                    if (image.len > (policy.max_capsule_image_bytes orelse policy.max_payload_bytes)) report.add(.capsule_too_large);
                }
                switch (request.kind) {
                    .operation => if (!Policy.policyAllowsSite(policy.allowed_operation_sites, request.site_index)) report.add(.operation_site),
                    .after => if (!Policy.policyAllowsSite(policy.allowed_after_sites, request.site_index)) report.add(.after_site),
                }
                return report;
            }

            /// Validate a response envelope's sidecar authorization against a capability and request.
            pub fn validateResponseCapability(capability: Capability, request: RequestEnvelope, response: ResponseEnvelope) ValidationReport {
                var report = validateCapabilityRequestScope(capability, request);
                request.validate() catch {
                    report.add(.invalid_envelope);
                    return report;
                };
                response.validateForRequest(request) catch {
                    report.add(.invalid_envelope);
                    return report;
                };
                const authorization = response.authorization orelse {
                    report.add(.missing_capability_fingerprint);
                    return report;
                };
                if (authorization.capability_fingerprint != capability.fingerprint) report.add(.wrong_capability);
                if (authorization.provider_fingerprint != capability.provider_fingerprint) report.add(.wrong_provider);
                if (authorization.capability_path_fingerprint != capability.attenuation_path_fingerprint) report.add(.wrong_capability_path);
                if (authorization.request_envelope_fingerprint != request.fingerprint) report.add(.wrong_request);
                if (authorization.response_envelope_fingerprint != response.fingerprint) report.add(.wrong_request);
                if (authorization.authorization_fingerprint != fingerprintAuthorization(authorization)) report.add(.wrong_capability);
                if (response.manifest_fingerprint != capability.manifest_fingerprint) report.add(.wrong_manifest);
                if (!capability.allowed_response_kinds.allows(response.kind)) report.add(.response_kind);
                if (!listAllowsValueRef(capability.allowed_response_refs, response.response_ref)) report.add(.response_ref);
                if (response.bytes.len > capability.max_response_bytes) report.add(.response_too_large);
                if (response.value_image.len > capability.max_payload_bytes) report.add(.payload_too_large);
                return report;
            }

            /// Validate a response sidecar against the exact selected route and request authority.
            pub fn validateRoutedResponseCapability(route: Route, capability: Capability, request: RequestEnvelope, response: ResponseEnvelope) ValidationReport {
                var report = validateResponseCapability(capability, request, response);
                if (route.fingerprint != fingerprintRoute(route)) report.add(.wrong_route);
                for (route.blockers.blockers[0..route.blockers.count]) |blocker| report.add(blocker);
                const authorization = response.authorization orelse return report;
                if (route.capability_fingerprint != capability.fingerprint) report.add(.wrong_capability);
                if (route.request_envelope_fingerprint != request.fingerprint) report.add(.wrong_request);
                if (authorization.route_fingerprint != route.fingerprint) report.add(.wrong_route);
                if (!route.allowed_response_kinds.allows(response.kind)) report.add(.response_kind);
                if (response.bytes.len > route.max_response_bytes) report.add(.response_too_large);
                if (response.value_image.len > route.max_payload_bytes) report.add(.payload_too_large);
                return report;
            }

            /// Restore from a request capsule only when the route/capability permits restoration.
            pub fn restoreFromRequestEnvelopeWithCapability(
                runtime: *lowered_machine.Runtime,
                handlers: HandlersType,
                request: RequestEnvelope,
                route: Route,
                provider: ProviderManifest,
                capability: Capability,
                policy: Policy,
            ) Error!Session {
                if (route.fingerprint != fingerprintRoute(route)) return error.ProgramContractViolation;
                const expected_route = Route.from(request, provider, capability, policy);
                if (expected_route.fingerprint != route.fingerprint) return error.ProgramContractViolation;
                if (!expected_route.valid()) return error.ProgramContractViolation;
                if (!expected_route.capsule_restore_allowed) return error.ProgramContractViolation;
                if (route.request_envelope_fingerprint != request.fingerprint) return error.ProgramContractViolation;
                if (route.capability_fingerprint != capability.fingerprint) return error.ProgramContractViolation;
                if (!capability.allow_capsule_restore) return error.ProgramContractViolation;
                try request.validate();
                const report = validateCapabilityRequestScope(capability, request);
                if (!report.allowed()) return error.ProgramContractViolation;
                if (request.capsule_image) |image| {
                    if (image.len > capability.max_capsule_image_bytes) return error.ProgramContractViolation;
                }
                return restoreFromRequestEnvelope(runtime, handlers, request);
            }

            fn validateRequestEnvelopeFields(envelope: RequestEnvelope) Error!void {
                if (envelope.manifest_fingerprint != try manifestFingerprintForCurrentProgram(envelope.allocator)) return error.ProgramContractViolation;
                if (!std.mem.eql(u8, envelope.program_label, label)) return error.ProgramContractViolation;
                if (!std.mem.eql(u8, envelope.plan_label, body_compiled_plan.label)) return error.ProgramContractViolation;
                if (envelope.plan_hash != body_compiled_plan_hash) return error.ProgramContractViolation;
                if (envelope.fingerprint != try checkedBytesFingerprint(envelope.bytes, "ability.exchange.request", exchange_request_fingerprint_version)) return error.ProgramContractViolation;
                switch (envelope.kind) {
                    .operation => try validateOperationEnvelopeSite(envelope),
                    .after => try validateAfterEnvelopeSite(envelope),
                }
                try validateExchangeValueImage(envelope.allocator, envelope.value_ref, envelope.value_fingerprint, envelope.value_image);
                try validateCapsuleImageForEnvelope(envelope);
            }

            fn validateRequestEnvelopeFieldsBoundToBytes(envelope: RequestEnvelope) Error!void {
                var decoded = try RequestEnvelope.decode(envelope.allocator, envelope.bytes);
                defer decoded.deinit();
                if (envelope.fingerprint != decoded.fingerprint) return error.ProgramContractViolation;
                if (envelope.manifest_fingerprint != decoded.manifest_fingerprint) return error.ProgramContractViolation;
                if (!std.mem.eql(u8, envelope.program_label, decoded.program_label)) return error.ProgramContractViolation;
                if (!std.mem.eql(u8, envelope.plan_label, decoded.plan_label)) return error.ProgramContractViolation;
                if (envelope.plan_hash != decoded.plan_hash) return error.ProgramContractViolation;
                if (envelope.kind != decoded.kind) return error.ProgramContractViolation;
                if (envelope.request_fingerprint != decoded.request_fingerprint) return error.ProgramContractViolation;
                if (envelope.trace_fingerprint != decoded.trace_fingerprint) return error.ProgramContractViolation;
                if (envelope.turn_index != decoded.turn_index) return error.ProgramContractViolation;
                if (envelope.site_index != decoded.site_index) return error.ProgramContractViolation;
                if (envelope.site_fingerprint != decoded.site_fingerprint) return error.ProgramContractViolation;
                if (!optionalBytesEql(envelope.semantic_label, decoded.semantic_label)) return error.ProgramContractViolation;
                if (!std.mem.eql(u8, envelope.name, decoded.name)) return error.ProgramContractViolation;
                if (envelope.mode != decoded.mode) return error.ProgramContractViolation;
                if (!envelope.value_ref.eql(decoded.value_ref)) return error.ProgramContractViolation;
                if (envelope.value_fingerprint != decoded.value_fingerprint) return error.ProgramContractViolation;
                if (!std.mem.eql(u8, envelope.value_image, decoded.value_image)) return error.ProgramContractViolation;
                if (!optionalValueRefEql(envelope.expected_resume_ref, decoded.expected_resume_ref)) return error.ProgramContractViolation;
                if (!optionalValueRefEql(envelope.expected_return_ref, decoded.expected_return_ref)) return error.ProgramContractViolation;
                if (!optionalValueRefEql(envelope.expected_after_ref, decoded.expected_after_ref)) return error.ProgramContractViolation;
                if (!envelope.result_ref.eql(decoded.result_ref)) return error.ProgramContractViolation;
                if (!optionalBytesEql(envelope.capsule_image, decoded.capsule_image)) return error.ProgramContractViolation;
                if (envelope.capsule_image_fingerprint != decoded.capsule_image_fingerprint) return error.ProgramContractViolation;
                if (!optionalBytesEql(envelope.journal_branch_id, decoded.journal_branch_id)) return error.ProgramContractViolation;
            }

            fn validateResponseEnvelopeFieldsBoundToBytes(response: ResponseEnvelope) Error!void {
                var decoded = try ResponseEnvelope.decode(response.allocator, response.bytes);
                defer decoded.deinit();
                if (response.fingerprint != decoded.fingerprint) return error.ProgramContractViolation;
                if (response.manifest_fingerprint != decoded.manifest_fingerprint) return error.ProgramContractViolation;
                if (response.request_envelope_fingerprint != decoded.request_envelope_fingerprint) return error.ProgramContractViolation;
                if (response.request_fingerprint != decoded.request_fingerprint) return error.ProgramContractViolation;
                if (response.kind != decoded.kind) return error.ProgramContractViolation;
                if (!response.response_ref.eql(decoded.response_ref)) return error.ProgramContractViolation;
                if (response.response_value_fingerprint != decoded.response_value_fingerprint) return error.ProgramContractViolation;
                if (response.response_trace_fingerprint != decoded.response_trace_fingerprint) return error.ProgramContractViolation;
                if (!std.mem.eql(u8, response.value_image, decoded.value_image)) return error.ProgramContractViolation;
            }

            /// Restore a session from an embedded request capsule image.
            pub fn restoreFromRequestEnvelope(
                runtime: *lowered_machine.Runtime,
                handlers: HandlersType,
                request: RequestEnvelope,
            ) Error!Session {
                try request.validate();
                const image_bytes = request.capsule_image orelse return error.ProgramContractViolation;
                var capsule = try Session.Capsule.decode(request.allocator, image_bytes);
                defer capsule.deinit();
                var session = try Session.restore(runtime, handlers, &capsule);
                errdefer session.deinit();
                const current_value = try session.current();
                const current_fingerprint = switch (current_value) {
                    .request => |current_request| current_request.fingerprint(),
                    .after => |after_request| after_request.fingerprint(),
                    .none => return error.ProgramContractViolation,
                };
                if (current_fingerprint != request.request_fingerprint) return error.ProgramContractViolation;
                return session;
            }

            fn requestEnvelopeForCurrent(
                allocator: std.mem.Allocator,
                session: *Session,
                current_value: Session.Current,
                include_capsule: bool,
                journal_branch_id: ?[]const u8,
            ) Error!RequestEnvelope {
                var capsule_image: ?Session.Capsule.Image = null;
                if (include_capsule) {
                    var capsule = try session.capture(allocator);
                    defer capsule.deinit();
                    capsule_image = try capsule.encode(allocator);
                }
                defer if (capsule_image) |*image| image.deinit();
                return switch (current_value) {
                    .request => |request| RequestEnvelope.fromRequest(allocator, request, .{ .capsule = capsule_image, .journal_branch_id = journal_branch_id }),
                    .after => |after| RequestEnvelope.fromAfter(allocator, after, .{ .capsule = capsule_image, .journal_branch_id = journal_branch_id }),
                    .none => error.ProgramContractViolation,
                };
            }

            const Writer = Session.ExchangeByteWriter;
            const Reader = Session.ExchangeByteReader;

            fn writeManifestPayload(writer: *Writer) anyerror!void {
                try writer.writeBytes(manifest_magic);
                try writer.writeU32(exchange_manifest_format_version);
                try writer.writeU32(exchange_manifest_fingerprint_version);
                try writer.writeU32(exchange_request_format_version);
                try writer.writeU32(exchange_request_fingerprint_version);
                try writer.writeU32(exchange_response_format_version);
                try writer.writeU32(exchange_response_fingerprint_version);
                try writer.writeLenBytes(label);
                try writer.writeLenBytes(body_compiled_plan.label);
                try writer.writeU64(body_compiled_plan_hash);
                try writer.writeU32(lowering_api.trace_fingerprint_version);
                try writer.writeU32(capsule_image_format_version);
                try writer.writeU32(capsule_image_fingerprint_version);
                try writer.writeU32(journal_format_version);
                try writer.writeU32(journal_fingerprint_version);
                try writer.writeUsize(compiled_plan.value_schemas.len);
                for (compiled_plan.value_schemas) |schema| {
                    try writer.writeLenBytes(schema.label);
                    try writeExchangeValueRef(writer, .{ .codec = schema.codec, .schema_index = schema.index });
                    try writer.writeU16(schema.first_field);
                    try writer.writeU16(schema.field_count);
                    try writer.writeU16(schema.first_variant);
                    try writer.writeU16(schema.variant_count);
                }
                try writer.writeUsize(compiled_plan.value_fields.len);
                for (compiled_plan.value_fields) |field| {
                    try writer.writeLenBytes(field.name);
                    try writeExchangeValueRef(writer, .{ .codec = field.codec, .schema_index = field.schema_index });
                }
                try writer.writeUsize(compiled_plan.value_variants.len);
                for (compiled_plan.value_variants) |variant| {
                    try writer.writeLenBytes(variant.name);
                    try writeExchangeValueRef(writer, .{ .codec = variant.codec, .schema_index = variant.schema_index });
                }
                try writer.writeUsize(protocol.operation_site_count);
                inline for (protocol.operation_site_metadata) |site| {
                    try writer.writeUsize(site.index);
                    try writer.writeU64(site.fingerprint);
                    try writeOptionalBytes(writer, site.semantic_label);
                    try writer.writeLenBytes(site.requirement_label);
                    try writer.writeLenBytes(site.op_name);
                    try writeExchangeControlMode(writer, site.op_mode);
                    try writeExchangeValueRef(writer, site.payload_ref);
                    try writeExchangeValueRef(writer, site.resume_ref);
                    try writeExchangeValueRef(writer, site.result_ref);
                    try writer.writeBool(site.has_after);
                }
                try writer.writeUsize(protocol.after_site_count);
                inline for (protocol.after_site_metadata) |site| {
                    try writer.writeUsize(site.index);
                    try writer.writeU64(site.fingerprint);
                    try writeOptionalBytes(writer, site.semantic_label);
                    try writer.writeUsize(site.source_operation_site_index);
                    try writer.writeU64(site.source_operation_site_fingerprint);
                    try writer.writeLenBytes(site.original_requirement_label);
                    try writer.writeLenBytes(site.original_op_name);
                    try writeExchangeValueRef(writer, site.result_ref);
                }
            }

            fn readManifestValueSchemas(reader: *Reader) Error!void {
                const count = try reader.readUsize();
                if (count != compiled_plan.value_schemas.len) return error.ProgramContractViolation;
                for (compiled_plan.value_schemas) |schema| {
                    if (!std.mem.eql(u8, try reader.readLenBytes(), schema.label)) return error.ProgramContractViolation;
                    const ref = try readExchangeValueRef(reader);
                    if (!ref.eql(.{ .codec = schema.codec, .schema_index = schema.index })) return error.ProgramContractViolation;
                    if (try reader.readU16() != schema.first_field) return error.ProgramContractViolation;
                    if (try reader.readU16() != schema.field_count) return error.ProgramContractViolation;
                    if (try reader.readU16() != schema.first_variant) return error.ProgramContractViolation;
                    if (try reader.readU16() != schema.variant_count) return error.ProgramContractViolation;
                }
                const field_count = try reader.readUsize();
                if (field_count != compiled_plan.value_fields.len) return error.ProgramContractViolation;
                for (compiled_plan.value_fields) |field| {
                    if (!std.mem.eql(u8, try reader.readLenBytes(), field.name)) return error.ProgramContractViolation;
                    const ref = try readExchangeValueRef(reader);
                    if (!ref.eql(.{ .codec = field.codec, .schema_index = field.schema_index })) return error.ProgramContractViolation;
                }
                const variant_count = try reader.readUsize();
                if (variant_count != compiled_plan.value_variants.len) return error.ProgramContractViolation;
                for (compiled_plan.value_variants) |variant| {
                    if (!std.mem.eql(u8, try reader.readLenBytes(), variant.name)) return error.ProgramContractViolation;
                    const ref = try readExchangeValueRef(reader);
                    if (!ref.eql(.{ .codec = variant.codec, .schema_index = variant.schema_index })) return error.ProgramContractViolation;
                }
            }

            fn readManifestOperationSites(reader: *Reader) Error!void {
                const count = try reader.readUsize();
                if (count != protocol.operation_site_count) return error.ProgramContractViolation;
                inline for (protocol.operation_site_metadata) |site| {
                    if (try reader.readUsize() != site.index) return error.ProgramContractViolation;
                    if (try reader.readU64() != site.fingerprint) return error.ProgramContractViolation;
                    try expectOptionalBytes(reader, site.semantic_label);
                    if (!std.mem.eql(u8, try reader.readLenBytes(), site.requirement_label)) return error.ProgramContractViolation;
                    if (!std.mem.eql(u8, try reader.readLenBytes(), site.op_name)) return error.ProgramContractViolation;
                    if (try readExchangeControlMode(reader) != site.op_mode) return error.ProgramContractViolation;
                    if (!(try readExchangeValueRef(reader)).eql(site.payload_ref)) return error.ProgramContractViolation;
                    if (!(try readExchangeValueRef(reader)).eql(site.resume_ref)) return error.ProgramContractViolation;
                    if (!(try readExchangeValueRef(reader)).eql(site.result_ref)) return error.ProgramContractViolation;
                    if (try reader.readBool() != site.has_after) return error.ProgramContractViolation;
                }
            }

            fn readManifestAfterSites(reader: *Reader) Error!void {
                const count = try reader.readUsize();
                if (count != protocol.after_site_count) return error.ProgramContractViolation;
                inline for (protocol.after_site_metadata) |site| {
                    if (try reader.readUsize() != site.index) return error.ProgramContractViolation;
                    if (try reader.readU64() != site.fingerprint) return error.ProgramContractViolation;
                    try expectOptionalBytes(reader, site.semantic_label);
                    if (try reader.readUsize() != site.source_operation_site_index) return error.ProgramContractViolation;
                    if (try reader.readU64() != site.source_operation_site_fingerprint) return error.ProgramContractViolation;
                    if (!std.mem.eql(u8, try reader.readLenBytes(), site.original_requirement_label)) return error.ProgramContractViolation;
                    if (!std.mem.eql(u8, try reader.readLenBytes(), site.original_op_name)) return error.ProgramContractViolation;
                    if (!(try readExchangeValueRef(reader)).eql(site.result_ref)) return error.ProgramContractViolation;
                }
            }

            fn manifestFingerprintForCurrentProgram(allocator: std.mem.Allocator) Error!u64 {
                var manifest = try Manifest.encode(allocator);
                defer manifest.deinit();
                return manifest.fingerprint;
            }

            fn encodeRequestEnvelope(allocator: std.mem.Allocator, args: anytype) Error!RequestEnvelope {
                var writer = Writer.init(allocator);
                errdefer writer.deinit();
                try writer.writeBytes(request_magic);
                try writer.writeU32(exchange_request_format_version);
                try writer.writeU32(exchange_request_fingerprint_version);
                try writer.writeU64(args.manifest_fingerprint);
                try writer.writeLenBytes(label);
                try writer.writeLenBytes(body_compiled_plan.label);
                try writer.writeU64(body_compiled_plan_hash);
                try writeRequestKind(&writer, args.kind);
                try writer.writeU64(args.request_fingerprint);
                try writer.writeU64(args.trace_fingerprint);
                try writer.writeUsize(args.turn_index);
                try writer.writeUsize(args.site_index);
                try writer.writeU64(args.site_fingerprint);
                try writeOptionalBytes(&writer, args.semantic_label);
                try writer.writeLenBytes(args.name);
                try writeExchangeControlMode(&writer, args.mode);
                try writeExchangeValueRef(&writer, args.value_ref);
                try writer.writeU64(args.value_fingerprint);
                try writer.writeLenBytes(args.value_image);
                try writeOptionalValueRef(&writer, args.expected_resume_ref);
                try writeOptionalValueRef(&writer, args.expected_return_ref);
                try writeOptionalValueRef(&writer, args.expected_after_ref);
                try writeExchangeValueRef(&writer, args.result_ref);
                try writer.writeBool(args.capsule != null);
                if (args.capsule) |capsule| {
                    try writer.writeLenBytes(capsule.bytes);
                    try writer.writeU64(capsule.image_fingerprint);
                }
                try writeOptionalBytes(&writer, args.journal_branch_id);
                const payload = writer.bytes.items;
                const fingerprint = exchangeFingerprint("ability.exchange.request", exchange_request_fingerprint_version, payload);
                try writer.writeU64(fingerprint);
                const owned = try writer.toOwnedSlice();
                errdefer allocator.free(owned);
                const value_image = try allocator.dupe(u8, args.value_image);
                errdefer allocator.free(value_image);
                const capsule_image = if (args.capsule) |capsule| try allocator.dupe(u8, capsule.bytes) else null;
                errdefer if (capsule_image) |image| allocator.free(image);
                const branch_id = if (args.journal_branch_id) |branch| try allocator.dupe(u8, branch) else null;
                errdefer if (branch_id) |branch| allocator.free(branch);
                const name_value = try allocator.dupe(u8, args.name);
                errdefer allocator.free(name_value);
                const semantic_label = if (args.semantic_label) |semantic| try allocator.dupe(u8, semantic) else null;
                errdefer if (semantic_label) |semantic| allocator.free(semantic);
                const program_label = try allocator.dupe(u8, label);
                errdefer allocator.free(program_label);
                const plan_label = try allocator.dupe(u8, body_compiled_plan.label);
                errdefer allocator.free(plan_label);
                return .{
                    .allocator = allocator,
                    .bytes = owned,
                    .fingerprint = fingerprint,
                    .manifest_fingerprint = args.manifest_fingerprint,
                    .program_label = program_label,
                    .plan_label = plan_label,
                    .plan_hash = body_compiled_plan_hash,
                    .kind = args.kind,
                    .request_fingerprint = args.request_fingerprint,
                    .trace_fingerprint = args.trace_fingerprint,
                    .turn_index = args.turn_index,
                    .site_index = args.site_index,
                    .site_fingerprint = args.site_fingerprint,
                    .semantic_label = semantic_label,
                    .name = name_value,
                    .mode = args.mode,
                    .value_ref = args.value_ref,
                    .value_image = value_image,
                    .value_fingerprint = args.value_fingerprint,
                    .expected_resume_ref = args.expected_resume_ref,
                    .expected_return_ref = args.expected_return_ref,
                    .expected_after_ref = args.expected_after_ref,
                    .result_ref = args.result_ref,
                    .capsule_image = capsule_image,
                    .capsule_image_fingerprint = if (args.capsule) |capsule| capsule.image_fingerprint else null,
                    .journal_branch_id = branch_id,
                };
            }

            fn encodeResponseEnvelope(allocator: std.mem.Allocator, request: RequestEnvelope, kind_value: ResponseKind, value: anytype) Error!ResponseEnvelope {
                try request.validate();
                const response_ref = try expectedResponseRef(request, kind_value);
                const expected_ref = comptime ProgramValueRefForType(body_value_schema_types, @TypeOf(value));
                if (!response_ref.eql(expected_ref)) return error.ProgramContractViolation;
                const response_value_fingerprint = try Session.fingerprintTypedValueImage(expected_ref, value);
                const response_trace = responseTraceFromEnvelope(request.request_fingerprint, kind_value, response_ref, response_value_fingerprint);
                const value_image = try encodeExchangeValueImage(allocator, response_ref, response_value_fingerprint, value);
                errdefer allocator.free(value_image);
                var writer = Writer.init(allocator);
                errdefer writer.deinit();
                try writer.writeBytes(response_magic);
                try writer.writeU32(exchange_response_format_version);
                try writer.writeU32(exchange_response_fingerprint_version);
                try writer.writeU64(request.manifest_fingerprint);
                try writer.writeU64(request.fingerprint);
                try writer.writeU64(request.request_fingerprint);
                try writeExchangeResponseKind(&writer, kind_value);
                try writeExchangeValueRef(&writer, response_ref);
                try writer.writeU64(response_value_fingerprint);
                try writer.writeU64(response_trace.fingerprint);
                try writer.writeLenBytes(value_image);
                const payload = writer.bytes.items;
                const fingerprint = exchangeFingerprint("ability.exchange.response", exchange_response_fingerprint_version, payload);
                try writer.writeU64(fingerprint);
                return .{
                    .allocator = allocator,
                    .bytes = try writer.toOwnedSlice(),
                    .fingerprint = fingerprint,
                    .manifest_fingerprint = request.manifest_fingerprint,
                    .request_envelope_fingerprint = request.fingerprint,
                    .request_fingerprint = request.request_fingerprint,
                    .kind = kind_value,
                    .response_ref = response_ref,
                    .value_image = value_image,
                    .response_value_fingerprint = response_value_fingerprint,
                    .response_trace_fingerprint = response_trace.fingerprint,
                };
            }

            fn applyResponseValue(session: *Session, current_value: Session.Current, response: ResponseEnvelope) Error!void {
                return switch (response.response_ref.codec) {
                    .unit => try applyDecodedExchangeValueImage(session, current_value, response, void),
                    .bool => try applyDecodedExchangeValueImage(session, current_value, response, bool),
                    .i32 => try applyDecodedExchangeValueImage(session, current_value, response, i32),
                    .usize => try applyDecodedExchangeValueImage(session, current_value, response, usize),
                    .string => try applyDecodedExchangeValueImage(session, current_value, response, []const u8),
                    .string_list => try applyDecodedExchangeValueImage(session, current_value, response, []const []const u8),
                    .product, .sum => blk: {
                        const schema_index = response.response_ref.schema_index orelse return error.ProgramContractViolation;
                        inline for (body_value_schema_types, 0..) |SchemaType, index| {
                            if (schema_index == index) {
                                break :blk try applyDecodedExchangeValueImage(session, current_value, response, SchemaType);
                            }
                        }
                        return error.ProgramContractViolation;
                    },
                };
            }

            fn applyDecodedExchangeValueImage(
                session: *Session,
                current_value: Session.Current,
                response: ResponseEnvelope,
                comptime ValueType: type,
            ) Error!void {
                const expected_ref = comptime ProgramValueRefForType(body_value_schema_types, ValueType);
                if (!response.response_ref.eql(expected_ref)) return error.ProgramContractViolation;
                var journal = Session.Journal.init(response.allocator);
                defer journal.deinit();
                var replayer = journal.replayer();
                defer replayer.deinit();
                var reader = Reader.init(response.value_image);
                const encoded_ref = try readExchangeValueRef(&reader);
                if (!encoded_ref.eql(expected_ref)) return error.ProgramContractViolation;
                var context = Session.ValueImageContext.init(response.allocator);
                defer context.deinit();
                const value = Session.readTypedValueImage(&reader, &replayer, &context, expected_ref, ValueType) catch |err| return mapProgramRunError(Error, err);
                if (!reader.eof()) return error.ProgramContractViolation;
                if (try Session.fingerprintTypedValueImage(expected_ref, value) != response.response_value_fingerprint) return error.ProgramContractViolation;
                const canonical = try encodeExchangeValueImage(response.allocator, response.response_ref, response.response_value_fingerprint, value);
                defer response.allocator.free(canonical);
                if (!std.mem.eql(u8, response.value_image, canonical)) return error.ProgramContractViolation;
                try applyTypedResponse(session, current_value, response, value);
            }

            fn applyTypedResponse(session: *Session, current_value: Session.Current, response: ResponseEnvelope, value: anytype) Error!void {
                const stable_value = try session.storeExchangeResponseValue(value);
                return switch (current_value) {
                    .request => |request| switch (response.kind) {
                        .@"resume" => try session.@"resume"(request, stable_value),
                        .return_now => try session.returnNow(request, stable_value),
                        .resume_after => error.ProgramContractViolation,
                    },
                    .after => |after| switch (response.kind) {
                        .resume_after => try session.resumeAfter(after, stable_value),
                        else => error.ProgramContractViolation,
                    },
                    .none => error.ProgramContractViolation,
                };
            }

            fn encodeRequestValueImage(allocator: std.mem.Allocator, request: Session.Request) Error![]u8 {
                return switch (request.payload_ref.codec) {
                    .unit => encodeExchangeValueImage(allocator, request.payload_ref, request.trace().payload_value_fingerprint, try request.payload(void)),
                    .bool => encodeExchangeValueImage(allocator, request.payload_ref, request.trace().payload_value_fingerprint, try request.payload(bool)),
                    .i32 => encodeExchangeValueImage(allocator, request.payload_ref, request.trace().payload_value_fingerprint, try request.payload(i32)),
                    .usize => encodeExchangeValueImage(allocator, request.payload_ref, request.trace().payload_value_fingerprint, try request.payload(usize)),
                    .string => encodeExchangeValueImage(allocator, request.payload_ref, request.trace().payload_value_fingerprint, try request.payload([]const u8)),
                    .string_list => encodeExchangeValueImage(allocator, request.payload_ref, request.trace().payload_value_fingerprint, try request.payload([]const []const u8)),
                    .product, .sum => blk: {
                        const schema_index = request.payload_ref.schema_index orelse return error.ProgramContractViolation;
                        inline for (body_value_schema_types, 0..) |SchemaType, index| {
                            if (schema_index == index) break :blk encodeExchangeValueImage(allocator, request.payload_ref, request.trace().payload_value_fingerprint, try request.payload(SchemaType));
                        }
                        return error.ProgramContractViolation;
                    },
                };
            }

            fn encodeAfterValueImage(allocator: std.mem.Allocator, request: Session.AfterRequest) Error![]u8 {
                return switch (request.value_ref.codec) {
                    .unit => encodeExchangeValueImage(allocator, request.value_ref, request.trace().current_value_fingerprint, try request.value(void)),
                    .bool => encodeExchangeValueImage(allocator, request.value_ref, request.trace().current_value_fingerprint, try request.value(bool)),
                    .i32 => encodeExchangeValueImage(allocator, request.value_ref, request.trace().current_value_fingerprint, try request.value(i32)),
                    .usize => encodeExchangeValueImage(allocator, request.value_ref, request.trace().current_value_fingerprint, try request.value(usize)),
                    .string => encodeExchangeValueImage(allocator, request.value_ref, request.trace().current_value_fingerprint, try request.value([]const u8)),
                    .string_list => encodeExchangeValueImage(allocator, request.value_ref, request.trace().current_value_fingerprint, try request.value([]const []const u8)),
                    .product, .sum => blk: {
                        const schema_index = request.value_ref.schema_index orelse return error.ProgramContractViolation;
                        inline for (body_value_schema_types, 0..) |SchemaType, index| {
                            if (schema_index == index) break :blk encodeExchangeValueImage(allocator, request.value_ref, request.trace().current_value_fingerprint, try request.value(SchemaType));
                        }
                        return error.ProgramContractViolation;
                    },
                };
            }

            fn encodeExchangeValueImage(allocator: std.mem.Allocator, ref: lowering_api.ValueRef, expected_fingerprint: u64, value: anytype) Error![]u8 {
                const expected_ref = comptime ProgramValueRefForType(body_value_schema_types, @TypeOf(value));
                if (!ref.eql(expected_ref)) return error.ProgramContractViolation;
                if (try Session.fingerprintTypedValueImage(expected_ref, value) != expected_fingerprint) return error.ProgramContractViolation;
                var writer = Writer.init(allocator);
                errdefer writer.deinit();
                var context = Session.ValueImageContext.initCanonical(allocator);
                defer context.deinit();
                try writeExchangeValueRef(&writer, expected_ref);
                Session.writeTypedValueImage(&writer, &context, expected_ref, value) catch |err| return mapProgramRunError(Error, err);
                return writer.toOwnedSlice() catch |err| return mapProgramRunError(Error, err);
            }

            fn decodeExchangeValueImage(
                allocator: std.mem.Allocator,
                ref: lowering_api.ValueRef,
                expected_fingerprint: u64,
                image: []const u8,
                comptime ValueType: type,
            ) Error!void {
                const expected_ref = comptime ProgramValueRefForType(body_value_schema_types, ValueType);
                if (!ref.eql(expected_ref)) return error.ProgramContractViolation;
                var journal = Session.Journal.init(allocator);
                defer journal.deinit();
                var replayer = journal.replayer();
                defer replayer.deinit();
                var reader = Reader.init(image);
                const encoded_ref = try readExchangeValueRef(&reader);
                if (!encoded_ref.eql(expected_ref)) return error.ProgramContractViolation;
                var context = Session.ValueImageContext.init(allocator);
                defer context.deinit();
                const value = Session.readTypedValueImage(&reader, &replayer, &context, expected_ref, ValueType) catch |err| return mapProgramRunError(Error, err);
                if (!reader.eof()) return error.ProgramContractViolation;
                if (try Session.fingerprintTypedValueImage(expected_ref, value) != expected_fingerprint) return error.ProgramContractViolation;
                const canonical = try encodeExchangeValueImage(allocator, ref, expected_fingerprint, value);
                defer allocator.free(canonical);
                if (!std.mem.eql(u8, image, canonical)) return error.ProgramContractViolation;
            }

            fn validateExchangeValueImage(allocator: std.mem.Allocator, ref: lowering_api.ValueRef, expected_fingerprint: u64, image: []const u8) Error!void {
                switch (ref.codec) {
                    .unit => try decodeExchangeValueImage(allocator, ref, expected_fingerprint, image, void),
                    .bool => try decodeExchangeValueImage(allocator, ref, expected_fingerprint, image, bool),
                    .i32 => try decodeExchangeValueImage(allocator, ref, expected_fingerprint, image, i32),
                    .usize => try decodeExchangeValueImage(allocator, ref, expected_fingerprint, image, usize),
                    .string => try decodeExchangeValueImage(allocator, ref, expected_fingerprint, image, []const u8),
                    .string_list => try decodeExchangeValueImage(allocator, ref, expected_fingerprint, image, []const []const u8),
                    .product, .sum => {
                        const schema_index = ref.schema_index orelse return error.ProgramContractViolation;
                        inline for (body_value_schema_types, 0..) |SchemaType, index| {
                            if (schema_index == index) {
                                try decodeExchangeValueImage(allocator, ref, expected_fingerprint, image, SchemaType);
                                return;
                            }
                        }
                        return error.ProgramContractViolation;
                    },
                }
            }

            fn expectedResponseRef(request: RequestEnvelope, kind_value: ResponseKind) Error!lowering_api.ValueRef {
                return switch (kind_value) {
                    .@"resume" => request.expected_resume_ref orelse error.ProgramContractViolation,
                    .return_now => request.expected_return_ref orelse error.ProgramContractViolation,
                    .resume_after => request.expected_after_ref orelse error.ProgramContractViolation,
                };
            }

            fn responseTraceFromEnvelope(request_fingerprint: u64, kind_value: ResponseKind, ref: lowering_api.ValueRef, value_fingerprint: u64) Session.Trace.Response {
                var hasher = std.hash.Wyhash.init(0);
                hashBytes(&hasher, "ability.session.response");
                hashU32(&hasher, Session.Trace.fingerprint_version);
                hashU64(&hasher, request_fingerprint);
                hashBytes(&hasher, @tagName(kind_value));
                Session.hashJournalTraceValueRef(&hasher, ref);
                hashU64(&hasher, value_fingerprint);
                return .{
                    .request_fingerprint = request_fingerprint,
                    .kind = kind_value,
                    .response_ref = ref,
                    .response_value_fingerprint = value_fingerprint,
                    .fingerprint = hasher.final(),
                };
            }

            fn validateOperationEnvelopeSite(envelope: RequestEnvelope) Error!void {
                inline for (protocol.operation_site_metadata) |site| {
                    if (site.index == envelope.site_index) {
                        if (site.fingerprint != envelope.site_fingerprint) return error.ProgramContractViolation;
                        if (!optionalBytesEql(envelope.semantic_label, site.semantic_label)) return error.ProgramContractViolation;
                        if (!std.mem.eql(u8, envelope.name, site.op_name)) return error.ProgramContractViolation;
                        if (envelope.mode != site.op_mode) return error.ProgramContractViolation;
                        if (!site.payload_ref.eql(envelope.value_ref)) return error.ProgramContractViolation;
                        if (!site.result_ref.eql(envelope.result_ref)) return error.ProgramContractViolation;
                        if (!optionalValueRefEql(envelope.expected_resume_ref, if (site.op_mode == .abort) null else site.resume_ref)) return error.ProgramContractViolation;
                        if (!optionalValueRefEql(envelope.expected_return_ref, if (site.op_mode == .transform) null else site.result_ref)) return error.ProgramContractViolation;
                        if (envelope.expected_after_ref != null) return error.ProgramContractViolation;
                        const trace: Session.Trace.OperationRequest = .{
                            .program_label = label,
                            .plan_label = body_compiled_plan.label,
                            .plan_hash = body_compiled_plan_hash,
                            .turn_index = envelope.turn_index,
                            .operation_site_index = site.index,
                            .operation_site_fingerprint = site.fingerprint,
                            .semantic_label = site.semantic_label,
                            .function_index = site.function_index,
                            .block_index = site.block_index,
                            .instruction_index = site.instruction_index,
                            .requirement_index = site.requirement_index,
                            .requirement_label = site.requirement_label,
                            .op_index = site.op_index,
                            .op_name = site.op_name,
                            .mode = site.op_mode,
                            .payload_ref = site.payload_ref,
                            .has_payload = site.payload_ref.codec != .unit,
                            .payload_value_fingerprint = envelope.value_fingerprint,
                            .resume_ref = site.resume_ref,
                            .result_ref = site.result_ref,
                            .has_after = site.has_after,
                            .fingerprint = 0,
                        };
                        const expected_fingerprint = Session.fingerprintJournalOperationRequestTrace(trace);
                        if (envelope.request_fingerprint != expected_fingerprint or envelope.trace_fingerprint != expected_fingerprint) return error.ProgramContractViolation;
                        return;
                    }
                }
                return error.ProgramContractViolation;
            }

            fn validateAfterEnvelopeSite(envelope: RequestEnvelope) Error!void {
                inline for (protocol.after_site_metadata) |site| {
                    if (site.index == envelope.site_index) {
                        if (site.fingerprint != envelope.site_fingerprint) return error.ProgramContractViolation;
                        if (!optionalBytesEql(envelope.semantic_label, site.semantic_label)) return error.ProgramContractViolation;
                        if (!std.mem.eql(u8, envelope.name, site.original_op_name)) return error.ProgramContractViolation;
                        if (envelope.mode != .transform) return error.ProgramContractViolation;
                        if (!site.result_ref.eql(envelope.result_ref)) return error.ProgramContractViolation;
                        if (envelope.expected_resume_ref != null or envelope.expected_return_ref != null) return error.ProgramContractViolation;
                        if (envelope.expected_after_ref == null) return error.ProgramContractViolation;
                        inline for (protocol.operation_site_metadata) |operation_site| {
                            if (operation_site.index == site.source_operation_site_index) {
                                if (operation_site.fingerprint != site.source_operation_site_fingerprint) return error.ProgramContractViolation;
                                const expected_input_ref = comptime lowering_api.sessionAfterProtocolInputRefForOperationSite(body_compiled_plan, body_value_schema_types, HandlersType, operation_site);
                                if (expected_input_ref) |input_ref| {
                                    if (!envelope.value_ref.eql(input_ref)) return error.ProgramContractViolation;
                                }
                                const expected_output_ref = comptime lowering_api.sessionAfterProtocolOutputRefForOperationSite(body_compiled_plan, body_value_schema_types, HandlersType, operation_site);
                                if (!envelope.expected_after_ref.?.eql(expected_output_ref)) return error.ProgramContractViolation;
                                const trace: Session.Trace.AfterRequest = .{
                                    .program_label = label,
                                    .plan_label = body_compiled_plan.label,
                                    .plan_hash = body_compiled_plan_hash,
                                    .turn_index = envelope.turn_index,
                                    .after_site_index = site.index,
                                    .after_site_fingerprint = site.fingerprint,
                                    .semantic_label = site.semantic_label,
                                    .source_operation_site_index = site.source_operation_site_index,
                                    .source_operation_site_fingerprint = site.source_operation_site_fingerprint,
                                    .function_index = site.source_function_index,
                                    .block_index = site.source_block_index,
                                    .instruction_index = site.source_instruction_index,
                                    .original_requirement_index = site.original_requirement_index,
                                    .original_requirement_label = site.original_requirement_label,
                                    .original_op_index = site.original_op_index,
                                    .original_op_name = site.original_op_name,
                                    .current_value_ref = envelope.value_ref,
                                    .current_value_fingerprint = envelope.value_fingerprint,
                                    .expected_output_ref = expected_output_ref,
                                    .result_ref = site.result_ref,
                                    .fingerprint = 0,
                                };
                                const expected_fingerprint = Session.fingerprintJournalAfterRequestTrace(trace);
                                if (envelope.request_fingerprint != expected_fingerprint or envelope.trace_fingerprint != expected_fingerprint) return error.ProgramContractViolation;
                                return;
                            }
                        }
                        return error.ProgramContractViolation;
                    }
                }
                return error.ProgramContractViolation;
            }

            fn requestRequirementLabel(request: RequestEnvelope) ?[]const u8 {
                return switch (request.kind) {
                    .operation => blk: {
                        inline for (protocol.operation_site_metadata) |site| {
                            if (site.index == request.site_index and site.fingerprint == request.site_fingerprint) break :blk site.requirement_label;
                        }
                        break :blk null;
                    },
                    .after => blk: {
                        inline for (protocol.after_site_metadata) |site| {
                            if (site.index == request.site_index and site.fingerprint == request.site_fingerprint) break :blk site.original_requirement_label;
                        }
                        break :blk null;
                    },
                };
            }

            fn requestProtocolOperationFingerprint(request: RequestEnvelope) ?u64 {
                return switch (request.kind) {
                    .operation => request.site_fingerprint,
                    .after => blk: {
                        inline for (protocol.after_site_metadata) |site| {
                            if (site.index == request.site_index and site.fingerprint == request.site_fingerprint) break :blk site.source_operation_site_fingerprint;
                        }
                        break :blk null;
                    },
                };
            }

            fn optionalValueRefEql(actual: ?lowering_api.ValueRef, expected: ?lowering_api.ValueRef) bool {
                if (actual == null and expected == null) return true;
                if (actual == null or expected == null) return false;
                return actual.?.eql(expected.?);
            }

            fn optionalBytesEql(actual: ?[]const u8, expected: ?[]const u8) bool {
                if (actual == null and expected == null) return true;
                if (actual == null or expected == null) return false;
                return std.mem.eql(u8, actual.?, expected.?);
            }

            fn validateCapsuleImageForEnvelope(envelope: RequestEnvelope) Error!void {
                const image_bytes = envelope.capsule_image orelse return;
                const image_fingerprint = envelope.capsule_image_fingerprint orelse return error.ProgramContractViolation;
                if (image_fingerprint != Session.capsuleImageFingerprint(image_bytes)) return error.ProgramContractViolation;
                var capsule = try Session.Capsule.decode(envelope.allocator, image_bytes);
                defer capsule.deinit();
                const metadata = capsule.metadata();
                if (metadata.current_request_fingerprint != envelope.request_fingerprint) return error.ProgramContractViolation;
                switch (envelope.kind) {
                    .operation => {
                        if (metadata.parked_kind != .operation) return error.ProgramContractViolation;
                        if (metadata.current_operation_site_index == null or metadata.current_operation_site_index.? != envelope.site_index) return error.ProgramContractViolation;
                    },
                    .after => {
                        if (metadata.parked_kind != .after) return error.ProgramContractViolation;
                        if (metadata.current_after_site_index == null or metadata.current_after_site_index.? != envelope.site_index) return error.ProgramContractViolation;
                    },
                }
            }

            fn exchangeFingerprint(domain: []const u8, version: u32, bytes: []const u8) u64 {
                var hasher = std.hash.Wyhash.init(0);
                hashBytes(&hasher, domain);
                hashU32(&hasher, version);
                hashBytes(&hasher, bytes);
                return hasher.final();
            }

            fn journalBranchPolicyFingerprint(journal_branch_id: []const u8) u64 {
                return exchangeFingerprint("ability.exchange.journal.policy", exchange_capability_fingerprint_version, journal_branch_id);
            }

            fn checkedPayload(bytes: []const u8, domain: []const u8, version: u32) Error![]const u8 {
                if (bytes.len < 8) return error.ProgramContractViolation;
                const payload = bytes[0 .. bytes.len - 8];
                const actual = std.mem.readInt(u64, bytes[bytes.len - 8 ..][0..8], .little);
                if (actual != exchangeFingerprint(domain, version, payload)) return error.ProgramContractViolation;
                return payload;
            }

            fn checkedBytesFingerprint(bytes: []const u8, domain: []const u8, version: u32) Error!u64 {
                const payload = try checkedPayload(bytes, domain, version);
                return exchangeFingerprint(domain, version, payload);
            }

            fn writeExchangeValueRef(writer: *Writer, ref: lowering_api.ValueRef) std.mem.Allocator.Error!void {
                try writer.writeU8(@intFromEnum(ref.codec));
                try writer.writeBool(ref.schema_index != null);
                if (ref.schema_index) |schema_index| try writer.writeU16(schema_index);
            }

            fn readExchangeValueRef(reader: *Reader) Error!lowering_api.ValueRef {
                return Session.readExchangeValueRef(reader);
            }

            fn writeOptionalValueRef(writer: *Writer, ref: ?lowering_api.ValueRef) std.mem.Allocator.Error!void {
                try writer.writeBool(ref != null);
                if (ref) |actual| try writeExchangeValueRef(writer, actual);
            }

            fn readOptionalValueRef(reader: *Reader) Error!?lowering_api.ValueRef {
                if (!try reader.readBool()) return null;
                return try readExchangeValueRef(reader);
            }

            fn writeOptionalBytes(writer: *Writer, value: ?[]const u8) std.mem.Allocator.Error!void {
                try writer.writeBool(value != null);
                if (value) |actual| try writer.writeLenBytes(actual);
            }

            fn readOptionalOwnedBytes(allocator: std.mem.Allocator, reader: *Reader) Error!?[]u8 {
                if (!try reader.readBool()) return null;
                return allocator.dupe(u8, try reader.readLenBytes()) catch |err| return mapProgramRunError(Error, err);
            }

            fn expectOptionalBytes(reader: *Reader, expected: ?[]const u8) Error!void {
                if (try reader.readBool()) {
                    const actual = try reader.readLenBytes();
                    if (expected == null or !std.mem.eql(u8, actual, expected.?)) return error.ProgramContractViolation;
                } else if (expected != null) return error.ProgramContractViolation;
            }

            fn dupeExpectedString(allocator: std.mem.Allocator, reader: *Reader, expected: []const u8) Error![]u8 {
                const actual = try reader.readLenBytes();
                if (!std.mem.eql(u8, actual, expected)) return error.ProgramContractViolation;
                return allocator.dupe(u8, actual) catch |err| return mapProgramRunError(Error, err);
            }

            fn cloneU64s(allocator: std.mem.Allocator, values: []const u64) Error![]u64 {
                return allocator.dupe(u64, values) catch |err| return mapProgramRunError(Error, err);
            }

            fn cloneUsizes(allocator: std.mem.Allocator, values: []const usize) Error![]usize {
                return allocator.dupe(usize, values) catch |err| return mapProgramRunError(Error, err);
            }

            fn cloneValueRefs(allocator: std.mem.Allocator, values: []const lowering_api.ValueRef) Error![]lowering_api.ValueRef {
                return allocator.dupe(lowering_api.ValueRef, values) catch |err| return mapProgramRunError(Error, err);
            }

            fn cloneStringList(allocator: std.mem.Allocator, values: []const []const u8) Error![]const []const u8 {
                const owned = allocator.alloc([]u8, values.len) catch |err| return mapProgramRunError(Error, err);
                var filled: usize = 0;
                errdefer {
                    for (owned[0..filled]) |item| allocator.free(item);
                    allocator.free(owned);
                }
                for (values, 0..) |value, index| {
                    owned[index] = allocator.dupe(u8, value) catch |err| return mapProgramRunError(Error, err);
                    filled += 1;
                }
                return owned;
            }

            fn freeStringList(allocator: std.mem.Allocator, values: []const []const u8) void {
                for (values) |value| allocator.free(value);
                allocator.free(values);
            }

            fn writeStringList(writer: *Writer, values: []const []const u8) std.mem.Allocator.Error!void {
                try writer.writeUsize(values.len);
                for (values) |value| try writer.writeLenBytes(value);
            }

            fn readStringList(allocator: std.mem.Allocator, reader: *Reader) Error![]const []const u8 {
                const count = try reader.readUsize();
                if (count > reader.remaining() / 8) return error.ProgramContractViolation;
                const values = allocator.alloc([]u8, count) catch |err| return mapProgramRunError(Error, err);
                var filled: usize = 0;
                errdefer {
                    for (values[0..filled]) |item| allocator.free(item);
                    allocator.free(values);
                }
                for (0..count) |index| {
                    values[index] = allocator.dupe(u8, try reader.readLenBytes()) catch |err| return mapProgramRunError(Error, err);
                    filled += 1;
                }
                return values;
            }

            fn writeU64List(writer: *Writer, values: []const u64) std.mem.Allocator.Error!void {
                try writer.writeUsize(values.len);
                for (values) |value| try writer.writeU64(value);
            }

            fn readU64List(allocator: std.mem.Allocator, reader: *Reader) Error![]u64 {
                const count = try reader.readUsize();
                if (count > reader.remaining() / 8) return error.ProgramContractViolation;
                const values = allocator.alloc(u64, count) catch |err| return mapProgramRunError(Error, err);
                errdefer allocator.free(values);
                for (values) |*value| value.* = try reader.readU64();
                return values;
            }

            fn writeUsizeList(writer: *Writer, values: []const usize) std.mem.Allocator.Error!void {
                try writer.writeUsize(values.len);
                for (values) |value| try writer.writeUsize(value);
            }

            fn readUsizeList(allocator: std.mem.Allocator, reader: *Reader) Error![]usize {
                const count = try reader.readUsize();
                if (count > reader.remaining() / 8) return error.ProgramContractViolation;
                const values = allocator.alloc(usize, count) catch |err| return mapProgramRunError(Error, err);
                errdefer allocator.free(values);
                for (values) |*value| value.* = try reader.readUsize();
                return values;
            }

            fn writeValueRefList(writer: *Writer, values: []const lowering_api.ValueRef) std.mem.Allocator.Error!void {
                try writer.writeUsize(values.len);
                for (values) |value| try writeExchangeValueRef(writer, value);
            }

            fn readValueRefList(allocator: std.mem.Allocator, reader: *Reader) Error![]lowering_api.ValueRef {
                const count = try reader.readUsize();
                if (count > reader.remaining() / 2) return error.ProgramContractViolation;
                const values = allocator.alloc(lowering_api.ValueRef, count) catch |err| return mapProgramRunError(Error, err);
                errdefer allocator.free(values);
                for (values) |*value| value.* = try readExchangeValueRef(reader);
                return values;
            }

            fn expectStringList(reader: *Reader, expected: []const []const u8) Error!void {
                const count = try reader.readUsize();
                if (count != expected.len) return error.ProgramContractViolation;
                for (expected) |value| {
                    if (!std.mem.eql(u8, try reader.readLenBytes(), value)) return error.ProgramContractViolation;
                }
            }

            fn expectU64List(reader: *Reader, expected: []const u64) Error!void {
                const count = try reader.readUsize();
                if (count != expected.len) return error.ProgramContractViolation;
                for (expected) |value| {
                    if (try reader.readU64() != value) return error.ProgramContractViolation;
                }
            }

            fn expectUsizeList(reader: *Reader, expected: []const usize) Error!void {
                const count = try reader.readUsize();
                if (count != expected.len) return error.ProgramContractViolation;
                for (expected) |value| {
                    if (try reader.readUsize() != value) return error.ProgramContractViolation;
                }
            }

            fn expectValueRefList(reader: *Reader, expected: []const lowering_api.ValueRef) Error!void {
                const count = try reader.readUsize();
                if (count != expected.len) return error.ProgramContractViolation;
                for (expected) |value| {
                    const actual = try readExchangeValueRef(reader);
                    if (!actual.eql(value)) return error.ProgramContractViolation;
                }
            }

            fn writeOptionalU64(writer: *Writer, value: ?u64) std.mem.Allocator.Error!void {
                try writer.writeBool(value != null);
                if (value) |actual| try writer.writeU64(actual);
            }

            fn readOptionalU64(reader: *Reader) Error!?u64 {
                if (!try reader.readBool()) return null;
                return try reader.readU64();
            }

            fn writeResponseKindSet(writer: *Writer, set: Policy.ResponseKindSet) std.mem.Allocator.Error!void {
                try writer.writeBool(set.@"resume");
                try writer.writeBool(set.return_now);
                try writer.writeBool(set.resume_after);
            }

            fn readResponseKindSet(reader: *Reader) Error!Policy.ResponseKindSet {
                return .{
                    .@"resume" = try reader.readBool(),
                    .return_now = try reader.readBool(),
                    .resume_after = try reader.readBool(),
                };
            }

            fn responseKindSetsEqual(left: Policy.ResponseKindSet, right: Policy.ResponseKindSet) bool {
                return left.@"resume" == right.@"resume" and
                    left.return_now == right.return_now and
                    left.resume_after == right.resume_after;
            }

            fn writeRequestKindSet(writer: *Writer, set: RequestKindSet) std.mem.Allocator.Error!void {
                try writer.writeBool(set.operation);
                try writer.writeBool(set.after);
            }

            fn readRequestKindSet(reader: *Reader) Error!RequestKindSet {
                return .{
                    .operation = try reader.readBool(),
                    .after = try reader.readBool(),
                };
            }

            fn providerIdentityFingerprint(provider_label: []const u8, metadata: []const u8) u64 {
                var hasher = std.hash.Wyhash.init(0);
                hashBytes(&hasher, "ability.exchange.provider.identity");
                hashU32(&hasher, exchange_provider_fingerprint_version);
                hashBytes(&hasher, provider_label);
                hashBytes(&hasher, metadata);
                return hasher.final();
            }

            fn writeProviderPayload(writer: *Writer, provider_fp: u64, options: ProviderManifest.Options) std.mem.Allocator.Error!void {
                try writer.writeBytes(provider_magic);
                try writer.writeU32(exchange_provider_format_version);
                try writer.writeU32(exchange_provider_fingerprint_version);
                try writer.writeU64(provider_fp);
                try writer.writeLenBytes(options.label);
                try writeU64List(writer, options.supported_program_manifest_fingerprints);
                try writeStringList(writer, options.supported_protocol_labels);
                try writeUsizeList(writer, options.supported_operation_sites);
                try writeUsizeList(writer, options.supported_after_sites);
                try writeU64List(writer, options.supported_protocol_op_fingerprints);
                try writeResponseKindSet(writer, options.allowed_response_kinds);
                try writer.writeUsize(options.max_request_envelope_bytes);
                try writer.writeUsize(options.max_response_envelope_bytes);
                try writer.writeBool(options.accepts_embedded_capsules);
                try writer.writeBool(options.accepts_capsule_restore);
                try writeStringList(writer, options.semantic_tags);
                try writer.writeLenBytes(options.metadata);
            }

            fn capabilityRequestKinds(options: Capability.Options) RequestKindSet {
                if (options.allowed_request_kinds) |request_kinds| return request_kinds;
                const restricts_operation_sites = options.allowed_operation_sites.len != 0;
                const restricts_after_sites = options.allowed_after_sites.len != 0;
                if (restricts_operation_sites or restricts_after_sites) {
                    return .{
                        .operation = restricts_operation_sites,
                        .after = restricts_after_sites,
                    };
                }
                return .{};
            }

            fn writeCapabilityPayload(writer: *Writer, options: Capability.Options, path: u64) std.mem.Allocator.Error!void {
                try writer.writeBytes(capability_magic);
                try writer.writeU32(exchange_capability_format_version);
                try writer.writeU32(exchange_capability_fingerprint_version);
                try writer.writeU32(1);
                try writer.writeLenBytes(options.issuer_label);
                try writer.writeU64(options.provider_fingerprint);
                try writer.writeU64(options.manifest_fingerprint);
                try writeRequestKindSet(writer, capabilityRequestKinds(options));
                try writeStringList(writer, options.allowed_program_labels);
                try writeU64List(writer, options.allowed_plan_hashes);
                try writeUsizeList(writer, options.allowed_operation_sites);
                try writeUsizeList(writer, options.allowed_after_sites);
                try writeU64List(writer, options.allowed_protocol_op_fingerprints);
                try writeStringList(writer, options.allowed_requirement_labels);
                try writeStringList(writer, options.allowed_op_names);
                try writeResponseKindSet(writer, options.allowed_response_kinds);
                try writeValueRefList(writer, options.allowed_response_refs);
                try writer.writeBool(options.allow_embedded_capsule_response_handling);
                try writer.writeBool(options.allow_capsule_restore);
                try writer.writeUsize(options.max_request_bytes);
                try writer.writeUsize(options.max_response_bytes);
                try writer.writeUsize(options.max_payload_bytes);
                try writer.writeUsize(options.max_capsule_image_bytes);
                try writeOptionalU64(writer, options.journal_policy_fingerprint);
                try writeOptionalU64(writer, options.expires_at_generation);
                try writeOptionalU64(writer, options.parent_capability_fingerprint);
                try writer.writeU64(path);
            }

            fn capabilityFromOptions(
                allocator: std.mem.Allocator,
                bytes: []u8,
                fingerprint: u64,
                options: Capability.Options,
                path: u64,
            ) Error!Capability {
                errdefer allocator.free(bytes);
                const issuer = try allocator.dupe(u8, options.issuer_label);
                errdefer allocator.free(issuer);
                const program_labels = try cloneStringList(allocator, options.allowed_program_labels);
                errdefer freeStringList(allocator, program_labels);
                const plan_hashes = try cloneU64s(allocator, options.allowed_plan_hashes);
                errdefer allocator.free(plan_hashes);
                const operation_sites = try cloneUsizes(allocator, options.allowed_operation_sites);
                errdefer allocator.free(operation_sites);
                const after_sites = try cloneUsizes(allocator, options.allowed_after_sites);
                errdefer allocator.free(after_sites);
                const protocol_ops = try cloneU64s(allocator, options.allowed_protocol_op_fingerprints);
                errdefer allocator.free(protocol_ops);
                const requirement_labels = try cloneStringList(allocator, options.allowed_requirement_labels);
                errdefer freeStringList(allocator, requirement_labels);
                const op_names = try cloneStringList(allocator, options.allowed_op_names);
                errdefer freeStringList(allocator, op_names);
                const response_refs = try cloneValueRefs(allocator, options.allowed_response_refs);
                errdefer allocator.free(response_refs);
                return .{
                    .allocator = allocator,
                    .bytes = bytes,
                    .version = 1,
                    .fingerprint = fingerprint,
                    .issuer_label = issuer,
                    .provider_fingerprint = options.provider_fingerprint,
                    .manifest_fingerprint = options.manifest_fingerprint,
                    .allowed_request_kinds = capabilityRequestKinds(options),
                    .allowed_program_labels = program_labels,
                    .allowed_plan_hashes = plan_hashes,
                    .allowed_operation_sites = operation_sites,
                    .allowed_after_sites = after_sites,
                    .allowed_protocol_op_fingerprints = protocol_ops,
                    .allowed_requirement_labels = requirement_labels,
                    .allowed_op_names = op_names,
                    .allowed_response_kinds = options.allowed_response_kinds,
                    .allowed_response_refs = response_refs,
                    .allow_embedded_capsule_response_handling = options.allow_embedded_capsule_response_handling,
                    .allow_capsule_restore = options.allow_capsule_restore,
                    .max_request_bytes = options.max_request_bytes,
                    .max_response_bytes = options.max_response_bytes,
                    .max_payload_bytes = options.max_payload_bytes,
                    .max_capsule_image_bytes = options.max_capsule_image_bytes,
                    .journal_policy_fingerprint = options.journal_policy_fingerprint,
                    .expires_at_generation = options.expires_at_generation,
                    .parent_capability_fingerprint = options.parent_capability_fingerprint,
                    .attenuation_path_fingerprint = path,
                };
            }

            fn capabilityGrantFingerprint(options: Capability.Options) u64 {
                var hasher = std.hash.Wyhash.init(0);
                hashBytes(&hasher, "ability.exchange.capability.grant");
                hashU32(&hasher, exchange_capability_fingerprint_version);
                hashBytes(&hasher, options.issuer_label);
                hashU64(&hasher, options.provider_fingerprint);
                hashU64(&hasher, options.manifest_fingerprint);
                const request_kinds = capabilityRequestKinds(options);
                hashBool(&hasher, request_kinds.operation);
                hashBool(&hasher, request_kinds.after);
                hashStringList(&hasher, options.allowed_program_labels);
                hashU64List(&hasher, options.allowed_plan_hashes);
                hashUsizeList(&hasher, options.allowed_operation_sites);
                hashUsizeList(&hasher, options.allowed_after_sites);
                hashU64List(&hasher, options.allowed_protocol_op_fingerprints);
                hashStringList(&hasher, options.allowed_requirement_labels);
                hashStringList(&hasher, options.allowed_op_names);
                hashBool(&hasher, options.allowed_response_kinds.@"resume");
                hashBool(&hasher, options.allowed_response_kinds.return_now);
                hashBool(&hasher, options.allowed_response_kinds.resume_after);
                hashValueRefList(&hasher, options.allowed_response_refs);
                hashBool(&hasher, options.allow_embedded_capsule_response_handling);
                hashBool(&hasher, options.allow_capsule_restore);
                hashUsize(&hasher, options.max_request_bytes);
                hashUsize(&hasher, options.max_response_bytes);
                hashUsize(&hasher, options.max_payload_bytes);
                hashUsize(&hasher, options.max_capsule_image_bytes);
                hashOptionalU64(&hasher, options.journal_policy_fingerprint);
                hashOptionalU64(&hasher, options.expires_at_generation);
                hashOptionalU64(&hasher, options.parent_capability_fingerprint);
                return hasher.final();
            }

            fn providerFieldsBoundToBytes(provider: ProviderManifest) bool {
                const payload = checkedPayload(provider.bytes, "ability.exchange.provider", exchange_provider_fingerprint_version) catch return false;
                const fingerprint = checkedBytesFingerprint(provider.bytes, "ability.exchange.provider", exchange_provider_fingerprint_version) catch return false;
                if (fingerprint != provider.fingerprint) return false;
                var reader = Reader.init(payload);
                reader.expectBytes(provider_magic) catch return false;
                if ((reader.readU32() catch return false) != exchange_provider_format_version) return false;
                if ((reader.readU32() catch return false) != exchange_provider_fingerprint_version) return false;
                if ((reader.readU64() catch return false) != provider.provider_fingerprint) return false;
                if (!std.mem.eql(u8, reader.readLenBytes() catch return false, provider.label)) return false;
                expectU64List(&reader, provider.supported_program_manifest_fingerprints) catch return false;
                expectStringList(&reader, provider.supported_protocol_labels) catch return false;
                expectUsizeList(&reader, provider.supported_operation_sites) catch return false;
                expectUsizeList(&reader, provider.supported_after_sites) catch return false;
                expectU64List(&reader, provider.supported_protocol_op_fingerprints) catch return false;
                const response_kinds = readResponseKindSet(&reader) catch return false;
                if (!responseKindSetsEqual(response_kinds, provider.allowed_response_kinds)) return false;
                if ((reader.readUsize() catch return false) != provider.max_request_envelope_bytes) return false;
                if ((reader.readUsize() catch return false) != provider.max_response_envelope_bytes) return false;
                if ((reader.readBool() catch return false) != provider.accepts_embedded_capsules) return false;
                if ((reader.readBool() catch return false) != provider.accepts_capsule_restore) return false;
                expectStringList(&reader, provider.semantic_tags) catch return false;
                if (!std.mem.eql(u8, reader.readLenBytes() catch return false, provider.metadata)) return false;
                return reader.eof();
            }

            fn capabilityFieldsBoundToBytes(capability: Capability) bool {
                const payload = checkedPayload(capability.bytes, "ability.exchange.capability", exchange_capability_fingerprint_version) catch return false;
                const fingerprint = checkedBytesFingerprint(capability.bytes, "ability.exchange.capability", exchange_capability_fingerprint_version) catch return false;
                if (fingerprint != capability.fingerprint) return false;
                var reader = Reader.init(payload);
                reader.expectBytes(capability_magic) catch return false;
                if ((reader.readU32() catch return false) != exchange_capability_format_version) return false;
                if ((reader.readU32() catch return false) != exchange_capability_fingerprint_version) return false;
                if ((reader.readU32() catch return false) != capability.version) return false;
                if (!std.mem.eql(u8, reader.readLenBytes() catch return false, capability.issuer_label)) return false;
                if ((reader.readU64() catch return false) != capability.provider_fingerprint) return false;
                if ((reader.readU64() catch return false) != capability.manifest_fingerprint) return false;
                const request_kinds = readRequestKindSet(&reader) catch return false;
                if (request_kinds.operation != capability.allowed_request_kinds.operation or
                    request_kinds.after != capability.allowed_request_kinds.after) return false;
                expectStringList(&reader, capability.allowed_program_labels) catch return false;
                expectU64List(&reader, capability.allowed_plan_hashes) catch return false;
                expectUsizeList(&reader, capability.allowed_operation_sites) catch return false;
                expectUsizeList(&reader, capability.allowed_after_sites) catch return false;
                expectU64List(&reader, capability.allowed_protocol_op_fingerprints) catch return false;
                expectStringList(&reader, capability.allowed_requirement_labels) catch return false;
                expectStringList(&reader, capability.allowed_op_names) catch return false;
                const response_kinds = readResponseKindSet(&reader) catch return false;
                if (response_kinds.@"resume" != capability.allowed_response_kinds.@"resume" or
                    response_kinds.return_now != capability.allowed_response_kinds.return_now or
                    response_kinds.resume_after != capability.allowed_response_kinds.resume_after) return false;
                expectValueRefList(&reader, capability.allowed_response_refs) catch return false;
                if ((reader.readBool() catch return false) != capability.allow_embedded_capsule_response_handling) return false;
                if ((reader.readBool() catch return false) != capability.allow_capsule_restore) return false;
                if ((reader.readUsize() catch return false) != capability.max_request_bytes) return false;
                if ((reader.readUsize() catch return false) != capability.max_response_bytes) return false;
                if ((reader.readUsize() catch return false) != capability.max_payload_bytes) return false;
                if ((reader.readUsize() catch return false) != capability.max_capsule_image_bytes) return false;
                if ((readOptionalU64(&reader) catch return false) != capability.journal_policy_fingerprint) return false;
                if ((readOptionalU64(&reader) catch return false) != capability.expires_at_generation) return false;
                if ((readOptionalU64(&reader) catch return false) != capability.parent_capability_fingerprint) return false;
                if ((reader.readU64() catch return false) != capability.attenuation_path_fingerprint) return false;
                return reader.eof();
            }

            fn capabilityPathFingerprint(parent: ?u64, provider_fp: u64, prior_path: u64, grant_fp: u64) u64 {
                var hasher = std.hash.Wyhash.init(0);
                hashBytes(&hasher, "ability.exchange.capability.path");
                hashU32(&hasher, exchange_capability_fingerprint_version);
                hashBool(&hasher, parent != null);
                if (parent) |value| hashU64(&hasher, value);
                hashU64(&hasher, provider_fp);
                hashU64(&hasher, prior_path);
                hashU64(&hasher, grant_fp);
                return hasher.final();
            }

            fn fingerprintAuthorization(value: Authorization) u64 {
                var hasher = std.hash.Wyhash.init(0);
                hashBytes(&hasher, "ability.exchange.authorization");
                hashU32(&hasher, exchange_authorization_fingerprint_version);
                hashU64(&hasher, value.provider_fingerprint);
                hashU64(&hasher, value.capability_fingerprint);
                hashU64(&hasher, value.capability_path_fingerprint);
                hashU64(&hasher, value.route_fingerprint);
                hashU64(&hasher, value.request_envelope_fingerprint);
                hashU64(&hasher, value.response_envelope_fingerprint);
                return hasher.final();
            }

            fn fingerprintRoute(route: Route) u64 {
                var hasher = std.hash.Wyhash.init(0);
                hashBytes(&hasher, "ability.exchange.route");
                hashU32(&hasher, exchange_route_fingerprint_version);
                hashU64(&hasher, route.request_envelope_fingerprint);
                hashU64(&hasher, route.provider_fingerprint);
                hashU64(&hasher, route.capability_fingerprint);
                hashU64(&hasher, route.capability_path_fingerprint);
                hashU64(&hasher, route.manifest_fingerprint);
                hashBytes(&hasher, @tagName(route.request_kind));
                hashUsize(&hasher, route.site_index);
                hashU64(&hasher, route.site_fingerprint);
                hashBool(&hasher, route.allowed_response_kinds.@"resume");
                hashBool(&hasher, route.allowed_response_kinds.return_now);
                hashBool(&hasher, route.allowed_response_kinds.resume_after);
                hashUsize(&hasher, route.max_response_bytes);
                hashUsize(&hasher, route.max_payload_bytes);
                hashBool(&hasher, route.capsule_restore_allowed);
                for (route.blockers.blockers[0..route.blockers.count]) |blocker| hashBytes(&hasher, @tagName(blocker));
                return hasher.final();
            }

            fn listAllowsU64(list: []const u64, value: u64) bool {
                if (list.len == 0) return true;
                for (list) |item| if (item == value) return true;
                return false;
            }

            fn listAllowsUsize(list: []const usize, value: usize) bool {
                if (list.len == 0) return true;
                for (list) |item| if (item == value) return true;
                return false;
            }

            fn listAllowsString(list: []const []const u8, value: []const u8) bool {
                if (list.len == 0) return true;
                for (list) |item| if (std.mem.eql(u8, item, value)) return true;
                return false;
            }

            fn listAllowsValueRef(list: []const lowering_api.ValueRef, value: lowering_api.ValueRef) bool {
                if (list.len == 0) return true;
                for (list) |item| if (item.eql(value)) return true;
                return false;
            }

            fn u64ListSubset(child: []const u64, parent: []const u64) bool {
                if (child.len == 0) return parent.len == 0;
                if (parent.len == 0) return true;
                for (child) |item| if (!listAllowsU64(parent, item)) return false;
                return true;
            }

            fn usizeListSubset(child: []const usize, parent: []const usize) bool {
                if (child.len == 0) return parent.len == 0;
                if (parent.len == 0) return true;
                for (child) |item| if (!listAllowsUsize(parent, item)) return false;
                return true;
            }

            fn stringListSubset(child: []const []const u8, parent: []const []const u8) bool {
                if (child.len == 0) return parent.len == 0;
                if (parent.len == 0) return true;
                for (child) |item| if (!listAllowsString(parent, item)) return false;
                return true;
            }

            fn valueRefListSubset(child: []const lowering_api.ValueRef, parent: []const lowering_api.ValueRef) bool {
                if (child.len == 0) return parent.len == 0;
                if (parent.len == 0) return true;
                for (child) |item| if (!listAllowsValueRef(parent, item)) return false;
                return true;
            }

            fn responseKindSetSubset(child: Policy.ResponseKindSet, parent: Policy.ResponseKindSet) bool {
                return (!child.@"resume" or parent.@"resume") and
                    (!child.return_now or parent.return_now) and
                    (!child.resume_after or parent.resume_after);
            }

            fn responseKindSetIntersection(left: Policy.ResponseKindSet, right: Policy.ResponseKindSet) Policy.ResponseKindSet {
                return .{
                    .@"resume" = left.@"resume" and right.@"resume",
                    .return_now = left.return_now and right.return_now,
                    .resume_after = left.resume_after and right.resume_after,
                };
            }

            fn requestAcceptsAnyResponseKind(request: RequestEnvelope, set: Policy.ResponseKindSet) bool {
                return (request.expected_resume_ref != null and set.@"resume") or
                    (request.expected_return_ref != null and set.return_now) or
                    (request.expected_after_ref != null and set.resume_after);
            }

            fn requestAcceptsAnyResponseRef(request: RequestEnvelope, set: Policy.ResponseKindSet, refs: []const lowering_api.ValueRef) bool {
                if (refs.len == 0) return true;
                if (request.expected_resume_ref) |ref| {
                    if (set.@"resume" and listAllowsValueRef(refs, ref)) return true;
                }
                if (request.expected_return_ref) |ref| {
                    if (set.return_now and listAllowsValueRef(refs, ref)) return true;
                }
                if (request.expected_after_ref) |ref| {
                    if (set.resume_after and listAllowsValueRef(refs, ref)) return true;
                }
                return false;
            }

            fn responseKindSetRestrictRefs(request: RequestEnvelope, set: Policy.ResponseKindSet, refs: []const lowering_api.ValueRef) Policy.ResponseKindSet {
                return .{
                    .@"resume" = set.@"resume" and request.expected_resume_ref != null and (refs.len == 0 or listAllowsValueRef(refs, request.expected_resume_ref.?)),
                    .return_now = set.return_now and request.expected_return_ref != null and (refs.len == 0 or listAllowsValueRef(refs, request.expected_return_ref.?)),
                    .resume_after = set.resume_after and request.expected_after_ref != null and (refs.len == 0 or listAllowsValueRef(refs, request.expected_after_ref.?)),
                };
            }

            fn policyRequiresRoute(policy: Policy) bool {
                return policy.require_route or policy.require_response_capability;
            }

            fn routeRequiredFor(router: ?Router, policy: Policy) bool {
                if (policyRequiresRoute(policy)) return true;
                const catalog = router orelse return false;
                return policyRequiresRoute(catalog.policy);
            }

            fn routeMatchesCurrentPlan(route: Route, router: ?Router, policy: Policy, request: RequestEnvelope) bool {
                return validateRouteCurrentPlan(route, router, policy, request).allowed();
            }

            fn validateRouteCurrentPlan(route: Route, router: ?Router, policy: Policy, request: RequestEnvelope) ValidationReport {
                var report: ValidationReport = .{};
                const catalog = router orelse {
                    report.add(.no_route);
                    return report;
                };
                const route_plan = catalog.planWithPolicy(request, policy);
                const reject_ambiguous_routes = policy.reject_ambiguous_routes or catalog.policy.reject_ambiguous_routes;
                switch (route_plan.status) {
                    .one_route => {
                        if (route_plan.route != null and route_plan.route.?.fingerprint == route.fingerprint) return report;
                        report.add(.wrong_route);
                    },
                    .ambiguous_routes => {
                        if (!reject_ambiguous_routes and route_plan.route != null and route_plan.route.?.fingerprint == route.fingerprint) return report;
                        report.merge(route_plan.blocked);
                    },
                    .blocked_routes, .no_route => report.merge(route_plan.blocked),
                }
                if (report.allowed()) report.add(.wrong_route);
                return report;
            }

            fn validateUnroutedResponsePlan(router: ?Router, policy: Policy, request: RequestEnvelope) ValidationReport {
                var report: ValidationReport = .{};
                const catalog = router orelse {
                    if (policyRequiresRoute(policy)) report.add(.no_route);
                    return report;
                };
                const route_plan = catalog.planWithPolicy(request, policy);
                const reject_ambiguous_routes = policy.reject_ambiguous_routes or catalog.policy.reject_ambiguous_routes;
                switch (route_plan.status) {
                    .one_route => report.add(.wrong_route),
                    .ambiguous_routes => {
                        if (reject_ambiguous_routes or route_plan.route != null) report.merge(route_plan.blocked);
                    },
                    .blocked_routes => if (routeRequiredFor(router, policy) or !blockedRoutesAllowOptionalFallback(route_plan.blocked)) report.merge(route_plan.blocked),
                    .no_route => if (routeRequiredFor(router, policy)) report.merge(route_plan.blocked),
                }
                if (!report.allowed()) return report;
                if (routeRequiredFor(router, policy)) report.add(.no_route);
                return report;
            }

            fn blockedRoutesAllowOptionalFallback(report: ValidationReport) bool {
                if (report.allowed()) return true;
                for (report.blockers[0..report.count]) |tag| switch (tag) {
                    .wrong_provider,
                    .wrong_manifest,
                    .wrong_program_label,
                    .wrong_plan_hash,
                    .request_kind,
                    .operation_site,
                    .after_site,
                    .protocol_operation,
                    .response_kind,
                    .response_ref,
                    .embedded_capsule,
                    .capsule_restore,
                    .request_too_large,
                    .response_too_large,
                    .payload_too_large,
                    .capsule_too_large,
                    .missing_capability_fingerprint,
                    .wrong_capability_path,
                    .wrong_route,
                    .wrong_request,
                    => {},
                    .provider_not_allowed,
                    .capability_not_allowed,
                    .wrong_journal_policy,
                    .wrong_capability,
                    .invalid_envelope,
                    .expired_capability,
                    .broadened_authority,
                    .ambiguous_route,
                    .no_route,
                    => return false,
                };
                return true;
            }

            fn routeRefreshRequiredFor(
                last_route: ?Route,
                router: ?Router,
                policy: Policy,
                request: RequestEnvelope,
                last_response_capability_required: bool,
                response_capability_required: bool,
            ) bool {
                if (last_route) |route| {
                    return !validateRoutePolicies(route, router, policy).allowed() or
                        !routeMatchesCurrentPlan(route, router, policy, request) or
                        last_response_capability_required != response_capability_required;
                }
                if (routeRequiredFor(router, policy)) return true;
                const catalog = router orelse return false;
                if (!validatePolicyRequestScope(catalog.policy, request).allowed()) return true;
                const route_plan = catalog.planWithPolicy(request, policy);
                const reject_ambiguous_routes = policy.reject_ambiguous_routes or catalog.policy.reject_ambiguous_routes;
                return switch (route_plan.status) {
                    .one_route => true,
                    .blocked_routes => routeRequiredFor(router, policy) or !blockedRoutesAllowOptionalFallback(route_plan.blocked),
                    .ambiguous_routes => reject_ambiguous_routes or route_plan.route != null,
                    .no_route => false,
                };
            }

            fn responseCapabilityRequiredFor(router: ?Router, policy: Policy) bool {
                if (policy.require_response_capability) return true;
                const catalog = router orelse return false;
                return catalog.policy.require_response_capability;
            }

            fn policyProviderAllowed(policy: Policy, provider_fp: u64) bool {
                const list = policy.allowed_provider_fingerprints orelse return true;
                for (list) |item| if (item == provider_fp) return true;
                return false;
            }

            fn policyCapabilityAllowed(policy: Policy, capability_fp: u64) bool {
                const list = policy.allowed_capability_fingerprints orelse return true;
                for (list) |item| if (item == capability_fp) return true;
                return false;
            }

            fn validateRoutePolicy(route: Route, policy: Policy) ValidationReport {
                var report: ValidationReport = .{};
                if (!policyProviderAllowed(policy, route.provider_fingerprint)) report.add(.provider_not_allowed);
                if (!policyCapabilityAllowed(policy, route.capability_fingerprint)) report.add(.capability_not_allowed);
                if (!responseKindSetSubset(route.allowed_response_kinds, policy.allowed_response_kinds)) report.add(.response_kind);
                if (route.max_response_bytes > policy.max_envelope_bytes) report.add(.response_too_large);
                if (route.max_payload_bytes > policy.max_payload_bytes) report.add(.payload_too_large);
                return report;
            }

            fn validateRoutePolicies(route: Route, router: ?Router, policy: Policy) ValidationReport {
                var report = validateRoutePolicy(route, policy);
                if (router) |catalog| report.merge(validateRoutePolicy(route, catalog.policy));
                return report;
            }

            fn validateRouteResponse(route: Route, response: ResponseEnvelope) ValidationReport {
                var report: ValidationReport = .{};
                if (!route.valid()) report.merge(route.blockers);
                if (route.request_envelope_fingerprint != response.request_envelope_fingerprint) report.add(.wrong_request);
                if (!route.allowed_response_kinds.allows(response.kind)) report.add(.response_kind);
                if (response.bytes.len > route.max_response_bytes) report.add(.response_too_large);
                if (response.value_image.len > route.max_payload_bytes) report.add(.payload_too_large);
                return report;
            }

            fn writeRequestKind(writer: *Writer, kind_value: RequestKind) std.mem.Allocator.Error!void {
                try writer.writeU8(switch (kind_value) {
                    .operation => 0,
                    .after => 1,
                });
            }

            fn readRequestKind(reader: *Reader) Error!RequestKind {
                return switch (try reader.readU8()) {
                    0 => .operation,
                    1 => .after,
                    else => error.ProgramContractViolation,
                };
            }

            fn writeExchangeResponseKind(writer: *Writer, kind_value: ResponseKind) std.mem.Allocator.Error!void {
                try Session.writeJournalResponseKind(writer, kind_value);
            }

            fn readExchangeResponseKind(reader: *Reader) Error!ResponseKind {
                return try Session.readJournalResponseKind(reader);
            }

            fn writeExchangeControlMode(writer: *Writer, mode: plan_types.ControlMode) std.mem.Allocator.Error!void {
                try Session.writeJournalControlMode(writer, mode);
            }

            fn readExchangeControlMode(reader: *Reader) Error!plan_types.ControlMode {
                return try Session.readJournalControlMode(reader);
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

        fn hashOptionalU64(hasher: *std.hash.Wyhash, value: ?u64) void {
            hashBool(hasher, value != null);
            if (value) |actual| hashU64(hasher, actual);
        }

        fn hashU64List(hasher: *std.hash.Wyhash, values: []const u64) void {
            hashUsize(hasher, values.len);
            for (values) |value| hashU64(hasher, value);
        }

        fn hashUsizeList(hasher: *std.hash.Wyhash, values: []const usize) void {
            hashUsize(hasher, values.len);
            for (values) |value| hashUsize(hasher, value);
        }

        fn hashStringList(hasher: *std.hash.Wyhash, values: []const []const u8) void {
            hashUsize(hasher, values.len);
            for (values) |value| hashBytes(hasher, value);
        }

        fn hashValueRefList(hasher: *std.hash.Wyhash, values: []const lowering_api.ValueRef) void {
            hashUsize(hasher, values.len);
            for (values) |value| hashValueRef(hasher, value);
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
                if (self.residualized_sites.len != self.target_effect_row.residualized_sites or
                    self.dynamically_interpreted_sites.len != self.target_effect_row.dynamically_interpreted_sites or
                    self.reinterpreted_sites.len != self.target_effect_row.dynamically_reinterpreted_sites or
                    self.emitted_protocol_operations.len != self.target_effect_row.emitted_protocol_operations or
                    self.exposed_residual_operations != self.target_effect_row.exposed_residual_operations)
                {
                    return error.InvalidPipelineCertificate;
                }
                if (self.residualized_sites.len != self.source_effect_row.residualized_sites or
                    self.emitted_protocol_operations.len != self.source_effect_row.emitted_protocol_operations or
                    self.source_effect_row.residualized_sites > self.source_effect_row.source_operation_sites or
                    self.source_effect_row.residualized_sites + self.source_effect_row.exposed_residual_operations != self.source_effect_row.source_operation_sites or
                    self.source_effect_row.dynamically_interpreted_sites != 0 or
                    self.source_effect_row.dynamically_reinterpreted_sites != 0 or
                    self.source_effect_row.handled_protocol_operations != 0 or
                    self.source_effect_row.handled_after_sites != 0 or
                    self.source_effect_row.residual_after_sites != self.source_effect_row.source_after_sites or
                    self.source_effect_row.blockers != self.blockers.len)
                {
                    return error.InvalidPipelineCertificate;
                }
                if (self.target_effect_row.handled_after_sites > self.target_effect_row.source_after_sites or
                    self.target_effect_row.residual_after_sites > self.target_effect_row.source_after_sites or
                    self.target_effect_row.handled_after_sites + self.target_effect_row.residual_after_sites != self.target_effect_row.source_after_sites)
                {
                    return error.InvalidPipelineCertificate;
                }
                if (self.source_to_residual_site_map.len != self.residualized_sites.len or
                    self.residual_to_source_site_map.len != self.residualized_sites.len)
                {
                    return error.InvalidPipelineCertificate;
                }
                for (self.residualized_sites) |route| {
                    const source_map_entry = residualMapEntryForRoute(self.source_to_residual_site_map, route) orelse
                        return error.InvalidPipelineCertificate;
                    const residual_map_entry = residualMapEntryForRoute(self.residual_to_source_site_map, route) orelse
                        return error.InvalidPipelineCertificate;
                    if (!residualMapEntriesAgree(source_map_entry, residual_map_entry)) {
                        return error.InvalidPipelineCertificate;
                    }
                }
                for (self.source_to_residual_site_map, 0..) |entry, index| {
                    if (entry.source_site_fingerprint == 0 or entry.residual_site_fingerprint == null) return error.InvalidPipelineCertificate;
                    var duplicate_source = false;
                    var duplicate_residual = false;
                    for (self.source_to_residual_site_map, 0..) |other, other_index| {
                        if (other_index < index and other.source_site_fingerprint == entry.source_site_fingerprint) duplicate_source = true;
                        if (other_index < index and other.residual_site_fingerprint != null and other.residual_site_fingerprint.? == entry.residual_site_fingerprint.?) duplicate_residual = true;
                    }
                    if (duplicate_source or duplicate_residual) return error.InvalidPipelineCertificate;
                }
            }

            fn residualMapEntryForRoute(entries: []const ResidualSourceMapEntry, route: PipelineRouteWitness) ?ResidualSourceMapEntry {
                if (route.source_site_fingerprint == null or
                    route.target_protocol_op_fingerprint == null or
                    route.morphism_fingerprint == null)
                {
                    return null;
                }
                for (entries) |entry| {
                    if (entry.residual_site_fingerprint != null and
                        entry.source_site_fingerprint == route.source_site_fingerprint.? and
                        entry.target_protocol_op_fingerprint == route.target_protocol_op_fingerprint.?)
                    {
                        return entry;
                    }
                }
                return null;
            }

            fn residualMapEntriesAgree(left: ResidualSourceMapEntry, right: ResidualSourceMapEntry) bool {
                return left.source_site_index == right.source_site_index and
                    left.source_site_fingerprint == right.source_site_fingerprint and
                    left.residual_site_index == right.residual_site_index and
                    left.residual_site_fingerprint == right.residual_site_fingerprint and
                    left.target_protocol_op_fingerprint == right.target_protocol_op_fingerprint;
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

        fn routeKindInSet(comptime route_kind: PipelineRouteKind, comptime route_kinds: anytype) bool {
            inline for (route_kinds) |candidate| {
                if (route_kind == candidate) return true;
            }
            return false;
        }

        fn pipelineRoutesWithKind(comptime routes: []const PipelineRouteWitness, comptime route_kind: PipelineRouteKind) type {
            return pipelineRoutesWithKinds(routes, .{route_kind});
        }

        fn pipelineRoutesWithKinds(comptime routes: []const PipelineRouteWitness, comptime route_kinds: anytype) type {
            comptime var count: usize = 0;
            inline for (routes) |route| {
                if (routeKindInSet(route.kind, route_kinds)) count += 1;
            }
            var table: [count]PipelineRouteWitness = undefined;
            comptime var index: usize = 0;
            inline for (routes) |route| {
                if (routeKindInSet(route.kind, route_kinds)) {
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
            const DynamicInterpretedRoutes = pipelineRoutesWithKinds(Report.routes, .{
                .source_site_handled,
                .source_site_reinterpreted_dynamic,
            });
            const AfterRoutes = pipelineRoutesWithKind(Report.routes, .after_site_handled);
            const residual_effect_row = PipelineEffectRow{
                .source_program_label = label,
                .source_plan_hash = body_compiled_plan_hash,
                .residual_program_label = ResidualProgram.contract.label,
                .residual_plan_hash = ResidualProgram.compiled_plan.hash(),
                .source_operation_sites = protocol.operation_site_count,
                .source_after_sites = protocol.after_site_count,
                .residualized_sites = ResidualizedRoutes.values.len,
                .dynamically_interpreted_sites = DynamicInterpretedRoutes.values.len,
                .dynamically_reinterpreted_sites = DynamicRoutes.values.len,
                .handled_protocol_operations = 0,
                .emitted_protocol_operations = ResidualizedRoutes.values.len,
                .exposed_residual_operations = ResidualProgram.effect_row.residual_operation_sites,
                .handled_after_sites = AfterRoutes.values.len,
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
                .dynamically_interpreted_sites = &DynamicInterpretedRoutes.values,
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
                    if (!traceBelongsToProgram(trace, ResidualProgram.contract.label, ResidualProgram.compiled_plan.hash())) return null;
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
                            if (dynamicRouteForResidualEntry(entry, request)) |route| return route;
                            inline for (Report.routes) |route| {
                                if (routeMatchesTargetFingerprint(route, request) and
                                    route.source_site_fingerprint != null and
                                    route.source_site_fingerprint.? == entry.source_site_fingerprint)
                                {
                                    return route;
                                }
                            }
                            return null;
                        }
                        if (routeForSourceTrace(request.source_trace, request)) |route| return route;
                        return null;
                    }
                    if (@hasField(@TypeOf(request), "source_site_fingerprint")) {
                        if (dynamicRouteForResidualOwnedValue(request)) |route| return route;
                        inline for (Report.routes) |route| {
                            if (routeMatchesTargetFingerprint(route, request) and
                                routeMatchesRequestSource(route, request))
                            {
                                return route;
                            }
                        }
                        return null;
                    }
                    return null;
                }

                /// Map target request traces by the same deterministic protocol-operation fingerprint.
                pub fn mapTargetTrace(trace: anytype) ?PipelineRouteWitness {
                    if (@hasField(@TypeOf(trace), "source_trace")) {
                        if (mapResidualTrace(trace.source_trace)) |entry| {
                            if (dynamicRouteForResidualEntry(entry, trace)) |route| return route;
                            inline for (Report.routes) |route| {
                                if (routeMatchesTargetFingerprint(route, trace) and
                                    route.source_site_fingerprint != null and
                                    route.source_site_fingerprint.? == entry.source_site_fingerprint)
                                {
                                    return route;
                                }
                            }
                            return null;
                        }
                        if (routeForSourceTrace(trace.source_trace, trace)) |route| return route;
                        return null;
                    }
                    if (@hasField(@TypeOf(trace), "source_site_fingerprint")) {
                        if (dynamicRouteForResidualOwnedValue(trace)) |route| return route;
                        inline for (Report.routes) |route| {
                            if (routeMatchesTargetFingerprint(route, trace) and
                                routeMatchesRequestSource(route, trace))
                            {
                                return route;
                            }
                        }
                        return null;
                    }
                    return null;
                }

                fn routeMatchesTargetFingerprint(route: PipelineRouteWitness, value: anytype) bool {
                    const target_protocol_op_fingerprint = targetProtocolFingerprintForValue(value) orelse return false;
                    return route.target_protocol_op_fingerprint != null and
                        route.target_protocol_op_fingerprint.? == target_protocol_op_fingerprint;
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
                        return dynamicRouteForResidualEntry(entry, value);
                    }
                    return null;
                }

                fn dynamicRouteForResidualEntry(entry: ResidualSourceMapEntry, value: anytype) ?PipelineRouteWitness {
                    const target_protocol_op_fingerprint = targetProtocolFingerprintForValue(value) orelse return null;
                    return .{
                        .kind = .source_site_reinterpreted_dynamic,
                        .source_site_index = entry.source_site_index,
                        .source_site_fingerprint = entry.source_site_fingerprint,
                        .target_protocol_label = if (@hasField(@TypeOf(value), "target_protocol_label")) value.target_protocol_label else null,
                        .target_op_name = if (@hasField(@TypeOf(value), "target_op_name")) value.target_op_name else null,
                        .target_protocol_op_fingerprint = target_protocol_op_fingerprint,
                        .morphism_fingerprint = morphismFingerprintForValue(value),
                    };
                }

                fn morphismFingerprintForValue(value: anytype) ?u64 {
                    if (!@hasField(@TypeOf(value), "morphism_fingerprint")) return null;
                    const morphism_fingerprint = value.morphism_fingerprint;
                    return switch (@typeInfo(@TypeOf(morphism_fingerprint))) {
                        .optional => morphism_fingerprint,
                        else => morphism_fingerprint,
                    };
                }

                fn targetProtocolFingerprintForValue(value: anytype) ?u64 {
                    if (!@hasField(@TypeOf(value), "target_protocol_op_fingerprint")) return null;
                    const target_fingerprint = value.target_protocol_op_fingerprint;
                    return switch (@typeInfo(@TypeOf(target_fingerprint))) {
                        .optional => target_fingerprint,
                        else => target_fingerprint,
                    };
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
                    return forwardedResidualSourceEntryForFingerprint(value.source_site_fingerprint);
                }

                fn forwardedResidualSourceEntryForFingerprint(residual_site_fingerprint: u64) ?ResidualSourceMapEntry {
                    inline for (protocol.operation_site_metadata) |site| {
                        if (comptime !routeResidualizesSource(site.fingerprint)) {
                            inline for (ResidualProgram.protocol.operation_site_metadata) |residual_site| {
                                if (residual_site.fingerprint == residual_site_fingerprint and
                                    residual_site.function_index == site.function_index and
                                    residual_site.block_index == site.block_index and
                                    residual_site.instruction_index == site.instruction_index)
                                {
                                    return .{
                                        .source_site_index = site.index,
                                        .source_site_fingerprint = site.fingerprint,
                                        .residual_site_index = residual_site.index,
                                        .residual_site_fingerprint = residual_site.fingerprint,
                                        .disposition = .forwarded,
                                        .target_protocol_label = residual_site.requirement_label,
                                        .target_op_name = residual_site.op_name,
                                        .target_protocol_op_fingerprint = residual_site.fingerprint,
                                        .mapping_label = residual_site.semantic_label,
                                    };
                                }
                            }
                        }
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
                    return false;
                }

                fn traceMatchesProgramSite(trace: anytype, comptime site: anytype, comptime expected_label: []const u8, comptime expected_plan_hash: u64) bool {
                    if (@hasField(@TypeOf(trace), "operation_site_fingerprint") and trace.operation_site_fingerprint == site.fingerprint) {
                        return traceBelongsToProgram(trace, expected_label, expected_plan_hash);
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
                            try recordTraceValue(options, (try traceFor(current)).operation, response_trace, value);
                            try session.resumeTyped(typed, value);
                            break :resume_branch null;
                        },
                        .return_now => |value| return_now: {
                            if (!Site.may_return_now) return error.ProgramContractViolation;
                            const response_trace = typed.responseTrace(.return_now, value) catch |err| return mapProgramRunError(Error, err);
                            try recordTraceValue(options, (try traceFor(current)).operation, response_trace, value);
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
                            try recordTraceValue(options, (try traceFor(current)).operation, response_trace, value);
                            try session.resumeTyped(typed, value);
                            break :resume_branch null;
                        },
                        .return_now => |value| return_now: {
                            if (!Site.may_return_now) return error.ProgramContractViolation;
                            const response_trace = typed.responseTrace(.return_now, value) catch |err| return mapProgramRunError(Error, err);
                            try recordTraceValue(options, (try traceFor(current)).operation, response_trace, value);
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
                            try recordTraceDynamicValue(options, (try traceFor(current)).after, response_trace, value);
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
                    if (comptime @typeInfo(@TypeOf(options)) == .@"struct" and @hasField(@TypeOf(options), "journal_recorder")) {
                        var journal_recorder = options.journal_recorder;
                        if (comptime @typeInfo(@TypeOf(journal_recorder.record(request_trace, response_trace))) == .error_union) {
                            journal_recorder.record(request_trace, response_trace) catch |err| return mapProgramRunError(Error, err);
                        } else {
                            _ = journal_recorder.record(request_trace, response_trace);
                        }
                    }
                }

                fn recordTraceValue(options: anytype, request_trace: anytype, response_trace: Session.Trace.Response, value: anytype) Error!void {
                    if (comptime @typeInfo(@TypeOf(options)) == .@"struct" and @hasField(@TypeOf(options), "trace_recorder")) {
                        if (comptime @typeInfo(@TypeOf(options.trace_recorder.record(request_trace, response_trace))) == .error_union) {
                            options.trace_recorder.record(request_trace, response_trace) catch |err| return mapProgramRunError(Error, err);
                        } else {
                            _ = options.trace_recorder.record(request_trace, response_trace);
                        }
                    }
                    if (comptime @typeInfo(@TypeOf(options)) == .@"struct" and @hasField(@TypeOf(options), "journal_recorder")) {
                        var journal_recorder = options.journal_recorder;
                        const JournalRecorderType = @TypeOf(journal_recorder);
                        const JournalRecorderDeclType = switch (@typeInfo(JournalRecorderType)) {
                            .pointer => |pointer| pointer.child,
                            else => JournalRecorderType,
                        };
                        if (comptime @hasDecl(JournalRecorderDeclType, "recordValue")) {
                            if (comptime @typeInfo(@TypeOf(journal_recorder.recordValue(request_trace, response_trace, value))) == .error_union) {
                                journal_recorder.recordValue(request_trace, response_trace, value) catch |err| return mapProgramRunError(Error, err);
                            } else {
                                _ = journal_recorder.recordValue(request_trace, response_trace, value);
                            }
                        } else if (comptime @typeInfo(@TypeOf(journal_recorder.record(request_trace, response_trace))) == .error_union) {
                            journal_recorder.record(request_trace, response_trace) catch |err| return mapProgramRunError(Error, err);
                        } else {
                            _ = journal_recorder.record(request_trace, response_trace);
                        }
                    }
                }

                fn recordTraceDynamicValue(options: anytype, request_trace: anytype, response_trace: Session.Trace.Response, value: Handler.DynamicValue) Error!void {
                    return switch (value.ref.codec) {
                        .unit => try recordTraceValue(options, request_trace, response_trace, try value.as(void)),
                        .bool => try recordTraceValue(options, request_trace, response_trace, try value.as(bool)),
                        .i32 => try recordTraceValue(options, request_trace, response_trace, try value.as(i32)),
                        .usize => try recordTraceValue(options, request_trace, response_trace, try value.as(usize)),
                        .string => try recordTraceValue(options, request_trace, response_trace, try value.as([]const u8)),
                        .string_list => try recordTraceValue(options, request_trace, response_trace, try value.as([]const []const u8)),
                        .product, .sum => {
                            const schema_index = value.ref.schema_index orelse return error.ProgramContractViolation;
                            inline for (body_value_schema_types, 0..) |SchemaType, index| {
                                if (schema_index == index) return try recordTraceValue(options, request_trace, response_trace, try value.as(SchemaType));
                            }
                            return error.ProgramContractViolation;
                        },
                    };
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
