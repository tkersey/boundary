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
    const Value = ProgramValueTypeForRef(body_compiled_plan, body_value_schema_types, lowering_api.executableResultRefForPlan(body_compiled_plan));
    const Outputs = ProgramOutputsType(Body);

    return struct {
        /// Runtime-owned executable plan for this public program.
        pub const compiled_plan = body_compiled_plan;
        /// Read-only projection of the compiled ProgramPlan contract.
        pub const contract = ProgramContractFor(label, body_compiled_plan, Value, Outputs, body_value_schema_types, body_nested_with_targets);
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

        /// Host-driven session execution for plans without after hooks.
        pub const Session = struct {
            const Core = lowering_api.ExecutableSessionForPlan(
                BodyErrorSet(Body),
                body_compiled_plan,
                body_value_schema_types,
                body_nested_with_targets,
            );

            runtime: *lowered_machine.Runtime,
            handlers: HandlersType,
            core: Core,
            active: bool = true,

            /// Defunctionalized effect operation request yielded by `next`.
            pub const Request = Core.Request;
            /// One session step: either a terminal result or a yielded request.
            pub const Step = union(enum) {
                done: Result,
                request: Request,
            };

            /// Start a host-driven execution session and enter runtime ownership.
            pub fn start(runtime: *lowered_machine.Runtime, handlers: HandlersType) Error!Session {
                const mutable_handlers = handlers;
                lowered_machine.beginExecution(runtime) catch |err| return mapProgramRunError(Error, err);
                var runtime_active = true;
                errdefer if (runtime_active) lowered_machine.endExecution(runtime);

                const args = if (comptime hasDeclSafe(Body, "encodeArgs"))
                    Body.encodeArgs(mutable_handlers)
                else
                    @as([]const lowered_machine.ProgramValue, &.{});
                const core = Core.start(lowered_machine.runtimeAllocator(runtime), args) catch |err| return mapProgramRunError(Error, err);
                runtime_active = false;
                return .{
                    .runtime = runtime,
                    .handlers = mutable_handlers,
                    .core = core,
                };
            }

            /// Close an unfinished session and release runtime ownership.
            pub fn deinit(self: *Session) void {
                self.close();
            }

            /// Advance until the next yielded request or terminal result.
            pub fn next(self: *Session) Error!Step {
                try self.ensureActiveThread();
                const core_step = self.core.next() catch |err| {
                    self.close();
                    return mapProgramRunError(Error, err);
                };
                return switch (core_step) {
                    .request => |request| .{ .request = request },
                    .done => |raw| done: {
                        const allocator = lowered_machine.runtimeAllocator(self.runtime);
                        const result = if (comptime @typeInfo(HandlersType) == .pointer)
                            finishResult(allocator, self.handlers, raw.value)
                        else
                            finishResult(allocator, &self.handlers, raw.value);
                        const finished = result catch |err| {
                            self.close();
                            return err;
                        };
                        self.close();
                        break :done .{ .done = finished };
                    },
                };
            }

            /// Resume a yielded transform or choice request with a typed value.
            pub fn @"resume"(self: *Session, request: Request, value: anytype) Error!void {
                try self.ensureActiveThread();
                self.core.@"resume"(request, value) catch |err| return mapProgramRunError(Error, err);
            }

            /// Complete a yielded choice or abort request with a terminal value.
            pub fn returnNow(self: *Session, request: Request, value: anytype) Error!void {
                try self.ensureActiveThread();
                self.core.returnNow(request, value) catch |err| return mapProgramRunError(Error, err);
            }

            fn ensureActiveThread(self: *Session) Error!void {
                if (!self.active) return error.ProgramContractViolation;
                self.runtime.ensureThread() catch |err| return mapProgramRunError(Error, err);
            }

            fn close(self: *Session) void {
                if (!self.active) return;
                self.core.deinit();
                lowered_machine.endExecution(self.runtime);
                self.active = false;
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

    const contract = ProgramContractFor("contract-session-executable-blocked", plan, void, void, &.{}, &.{});
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
