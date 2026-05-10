// zlinter-disable function_naming no_empty_block no_undefined no_swallow_error
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
) type {
    const operation_sites = lowering_api.sessionOperationYieldSitesForPlanWithMetadata(plan, nested_targets, site_metadata);
    const after_sites = lowering_api.sessionAfterYieldSitesForPlanWithMetadata(plan, nested_targets, site_metadata);
    const plan_hash = plan.hash();

    return struct {
        pub const label = program_label;
        pub const hash = plan_hash;
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
    const Value = ProgramValueTypeForRef(body_compiled_plan, body_value_schema_types, lowering_api.executableResultRefForPlan(body_compiled_plan));
    const Outputs = ProgramOutputsType(Body);

    return struct {
        /// Runtime-owned executable plan for this public program.
        pub const compiled_plan = body_compiled_plan;
        /// Read-only projection of the compiled ProgramPlan contract.
        pub const contract = ProgramContractFor(label, body_compiled_plan, Value, Outputs, body_value_schema_types, body_nested_with_targets, body_site_metadata);
        /// Typed defunctionalized protocol descriptors derived from Program.Session static sites.
        pub const protocol = ProgramProtocolFor(label, body_compiled_plan, body_value_schema_types, body_nested_with_targets, HandlersType, Body, body_site_metadata);
        /// Public execution error for this program.
        pub const Error = ProgramErrorSet(Body);

        /// Public result value plus outputs. Cleanup is uniform even for void outputs.
        pub const Result = struct {
            allocator: std.mem.Allocator,
            value: Value,
            outputs: Outputs,

            /// Release owned result resources declared by the program body.
            pub fn deinit(self: *@This()) void {
                deinitBodyResult(Body, Value, Outputs, .{
                    .allocator = self.allocator,
                    .value = self.value,
                    .outputs = self.outputs,
                });
                if (comptime hasDeclSafe(Body, "deinitOutputs")) {
                    const DeinitOutputsFn = @TypeOf(Body.deinitOutputs);
                    if (DeinitOutputsFn != fn (std.mem.Allocator, Outputs) void) {
                        @compileError("Body.deinitOutputs must have type fn (std.mem.Allocator, outputs) void");
                    }
                    Body.deinitOutputs(self.allocator, self.outputs);
                }
            }
        };

        fn finishResult(allocator: std.mem.Allocator, handlers: anytype, value: Value) Error!Result {
            const outputs = collectBodyOutputs(Body, Outputs, allocator, handlers) catch |err| {
                deinitBodyResult(Body, Value, Outputs, .{
                    .allocator = allocator,
                    .value = value,
                    .outputs = null,
                });
                return mapProgramRunError(Error, err);
            };
            return .{
                .allocator = allocator,
                .value = value,
                .outputs = outputs,
            };
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
                    .done => |raw| done: {
                        const allocator = lowered_machine.runtimeAllocator(self.runtime);
                        const result = if (comptime @typeInfo(HandlersType) == .pointer)
                            finishResult(allocator, self.handlers, raw.value)
                        else
                            finishResult(allocator, &self.handlers, raw.value);
                        const finished = result catch |err| {
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
                if (completed) |raw| {
                    deinitBodyResult(Body, Value, Outputs, .{
                        .allocator = lowered_machine.runtimeAllocator(self.runtime),
                        .value = raw.value,
                        .outputs = null,
                    });
                }
            }
        };
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
