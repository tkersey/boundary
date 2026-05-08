// zlinter-disable function_naming no_empty_block no_undefined no_swallow_error
const lowered_machine = @import("lowered_machine");
const lowering_api = @import("lowering_api");
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
        validateBodyValueSchemaTypes(plan, Body);
        const schema_types = BodyValueSchemaTypes(Body).values;
        lowering_api.validateTypedExecutablePlanSupportWithNestedTargets(plan, schema_types, nested_with_targets) catch |err| {
            @compileError("Body.compiled_plan is not supported by ability.program: " ++ @errorName(err) ++ "\n" ++
                lowering_api.executableCapabilitySummary(plan, schema_types, nested_with_targets));
        };
        validatePlanReturnErrors(plan, BodyErrorSet(Body));
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

fn valueFieldPlansEqual(comptime actual: anytype, comptime expected: anytype) bool {
    return std.mem.eql(u8, actual.name, expected.name) and
        actual.codec == expected.codec and
        actual.schema_index == expected.schema_index;
}

fn valueVariantPlansEqual(comptime actual: anytype, comptime expected: anytype) bool {
    return std.mem.eql(u8, actual.name, expected.name) and
        actual.codec == expected.codec and
        actual.schema_index == expected.schema_index;
}

fn validateBodyValueSchemaTypes(comptime plan: lowering_api.ProgramPlan, comptime Body: type) void {
    const plan_schema_count = plan.value_schemas.len;
    if (comptime !hasDeclSafe(Body, "value_schema_types")) {
        if (plan_schema_count != 0) {
            @compileError("Body.value_schema_types is required when Body.compiled_plan contains product or sum value schemas");
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
        if (!valueFieldPlansEqual(plan.value_fields[index], expected)) {
            @compileError("Body.value_schema_types does not match Body.compiled_plan.value_fields[" ++ schemaIndexLabel(index) ++ "]");
        }
    }
    inline for (registry.value_variants, 0..) |expected, index| {
        if (!valueVariantPlansEqual(plan.value_variants[index], expected)) {
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

fn validatePlanReturnErrors(comptime plan: lowering_api.ProgramPlan, comptime ErrorSet: type) void {
    for (plan.instructions) |instruction| {
        if (instruction.kind == .return_error and !errorSetContains(ErrorSet, instruction.string_literal)) {
            @compileError("Body.compiled_plan return_error is not declared in Body.Error: " ++ instruction.string_literal);
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
            const outputs = if (comptime @typeInfo(HandlersType) == .pointer)
                collectBodyOutputs(Body, Outputs, allocator, mutable_handlers) catch |err| {
                    deinitBodyResult(Body, Value, Outputs, .{
                        .allocator = allocator,
                        .value = raw.value,
                        .outputs = null,
                    });
                    return mapProgramRunError(Error, err);
                }
            else
                collectBodyOutputs(Body, Outputs, allocator, &mutable_handlers) catch |err| {
                    deinitBodyResult(Body, Value, Outputs, .{
                        .allocator = allocator,
                        .value = raw.value,
                        .outputs = null,
                    });
                    return mapProgramRunError(Error, err);
                };
            return .{
                .allocator = allocator,
                .value = raw.value,
                .outputs = outputs,
            };
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
