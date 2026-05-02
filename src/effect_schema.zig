// zlinter-disable declaration_naming - this internal schema DSL keeps semantic names aligned with lifecycle/output vocabulary rather than style-driven aliases.
// zlinter-disable field_ordering - enum and schema field order stay semantically grouped for effect-family readability.
// zlinter-disable function_naming - lower-case schema constructors intentionally read like a DSL even when they return comptime types.
// zlinter-disable import_ordering - keeping `std` before `effect_ir` matches the rest of the local schema helpers.
// zlinter-disable max_positional_args - the family schema constructor keeps the lifecycle/output axes explicit instead of hiding them in an extra config struct.
// zlinter-disable require_doc_comment - this internal schema DSL uses public declarations for comptime reflection rather than human-facing API docs.
const std = @import("std");
const effect_ir = @import("effect_ir");

pub const ControlMode = enum {
    transform,
    choice,
    abort,
};

pub const AfterStrategy = enum {
    none,
    binding_optional,
};

pub const LifecycleTag = enum {
    plain_transform,
    reader_environment,
    state_cell,
    choice_policy,
    abort_catch,
    writer_accumulator,
    resource_bracket,
    generated_family,
};

pub const OutputTag = enum {
    none,
    final_state,
    accumulator,
    custom_finalizer,
};

pub fn op(
    comptime logical_name: [:0]const u8,
    comptime mode: ControlMode,
    comptime PayloadType: type,
    comptime ResumeType: type,
    comptime after_strategy: AfterStrategy,
) type {
    return struct {
        pub const name: [:0]const u8 = logical_name;
        pub const control_mode = mode;
        pub const Payload = PayloadType;
        pub const Resume = ResumeType;
        pub const after = after_strategy;
    };
}

pub fn transform(
    comptime logical_name: [:0]const u8,
    comptime PayloadType: type,
    comptime ResumeType: type,
) type {
    return op(logical_name, .transform, PayloadType, ResumeType, .none);
}

pub fn choice(
    comptime logical_name: [:0]const u8,
    comptime PayloadType: type,
    comptime ResumeType: type,
) type {
    return op(logical_name, .choice, PayloadType, ResumeType, .none);
}

pub fn abort(
    comptime logical_name: [:0]const u8,
    comptime PayloadType: type,
) type {
    return op(logical_name, .abort, PayloadType, noreturn, .none);
}

fn familySchema(
    comptime logical_name: [:0]const u8,
    comptime lifecycle: LifecycleTag,
    comptime ErrorSetType: type,
    comptime StateType: type,
    comptime ItemType: type,
    comptime OutputType: type,
    comptime output_tag: OutputTag,
    comptime OutputFinalizer: type,
    comptime PolicyType: type,
    comptime CatchType: type,
    comptime ManagerType: type,
    comptime Ops: anytype,
) type {
    return struct {
        pub const logical_family_name: [:0]const u8 = logical_name;
        pub const lifecycle_tag = lifecycle;
        pub const ErrorSet = ErrorSetType;
        pub const State = StateType;
        pub const Item = ItemType;
        pub const Output = OutputType;
        pub const output = output_tag;
        pub const OutputFinalizerType = OutputFinalizer;
        pub const Policy = PolicyType;
        pub const Catch = CatchType;
        pub const Manager = ManagerType;
        pub const ops = Ops;
        pub const op_count = Ops.len;
    };
}

pub fn state_cell(comptime StateType: type, comptime ErrorSetType: type) type {
    return familySchema(
        "state",
        .state_cell,
        ErrorSetType,
        StateType,
        void,
        StateType,
        .final_state,
        void,
        void,
        void,
        void,
        .{
            transform("get", void, StateType),
            transform("set", StateType, void),
        },
    );
}

pub fn reader_environment(comptime EnvType: type, comptime ErrorSetType: type) type {
    return familySchema(
        "reader",
        .reader_environment,
        ErrorSetType,
        EnvType,
        void,
        void,
        .none,
        void,
        void,
        void,
        void,
        .{
            transform("ask", void, EnvType),
        },
    );
}

pub fn choice_policy(comptime ResumeType: type, comptime ErrorSetType: type, comptime PolicyType: type) type {
    return familySchema(
        "optional",
        .choice_policy,
        ErrorSetType,
        ResumeType,
        void,
        void,
        .none,
        void,
        PolicyType,
        void,
        void,
        .{
            op("request", .choice, void, ResumeType, .binding_optional),
        },
    );
}

pub fn abort_catch(comptime PayloadType: type, comptime ErrorSetType: type, comptime CatchType: type) type {
    return familySchema(
        "exception",
        .abort_catch,
        ErrorSetType,
        PayloadType,
        void,
        void,
        .none,
        void,
        void,
        CatchType,
        void,
        .{
            abort("throw", PayloadType),
        },
    );
}

pub fn writer_accumulator(comptime ItemType: type, comptime ErrorSetType: type) type {
    return familySchema(
        "writer",
        .writer_accumulator,
        ErrorSetType,
        void,
        ItemType,
        []ItemType,
        .accumulator,
        void,
        void,
        void,
        void,
        .{
            transform("tell", ItemType, void),
        },
    );
}

pub fn resource_bracket(comptime ResourceType: type, comptime ErrorSetType: type, comptime ManagerType: type) type {
    return familySchema(
        "resource",
        .resource_bracket,
        ErrorSetType,
        ResourceType,
        void,
        void,
        .none,
        void,
        void,
        void,
        ManagerType,
        .{
            transform("acquire", void, ResourceType),
        },
    );
}

fn generatedControlMode(mode: anytype) ControlMode {
    return switch (mode) {
        .resume_then_transform => .transform,
        .resume_or_return => .choice,
        .direct_return => .abort,
    };
}

fn generatedAfterStrategy(mode: anytype) AfterStrategy {
    return switch (generatedControlMode(mode)) {
        .transform, .choice => .binding_optional,
        .abort => .none,
    };
}

fn generatedOutputTag(comptime mode: anytype, comptime StateType: type) OutputTag {
    if (generatedControlMode(mode) != .transform) return .none;
    return if (stateTypeProducesOutput(StateType)) .final_state else .none;
}

fn generatedOutputType(comptime mode: anytype, comptime StateType: type) type {
    if (generatedOutputTag(mode, StateType) == .final_state) return StateType;
    return void;
}

fn stateTypeProducesOutput(comptime T: type) bool {
    return T != void and !isEmptyStructType(T);
}

fn isEmptyStructType(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => |info| info.fields.len == 0,
        else => false,
    };
}

fn hasDeclSafe(comptime T: type, comptime name: []const u8) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, name),
        else => false,
    };
}

fn assertOpSchema(comptime OpSchema: type) void {
    if (!hasDeclSafe(OpSchema, "name") or OpSchema.name.len == 0) {
        @compileError("effect op schema must declare a non-empty name");
    }
    if (!hasDeclSafe(OpSchema, "control_mode")) {
        @compileError("effect op schema must declare control_mode");
    }
    if (!hasDeclSafe(OpSchema, "Payload")) {
        @compileError("effect op schema must declare Payload");
    }
    if (!hasDeclSafe(OpSchema, "Resume")) {
        @compileError("effect op schema must declare Resume");
    }
    if (!hasDeclSafe(OpSchema, "after")) {
        @compileError("effect op schema must declare after strategy");
    }
    if (OpSchema.control_mode == .abort and OpSchema.after != .none) {
        @compileError("abort op schemas cannot declare after hooks");
    }
}

pub fn assertFamilySchema(comptime FamilySchema: type) void {
    inline for (.{
        "logical_family_name",
        "lifecycle_tag",
        "ErrorSet",
        "State",
        "Item",
        "Output",
        "output",
        "ops",
        "op_count",
    }) |decl_name| {
        if (!hasDeclSafe(FamilySchema, decl_name)) {
            @compileError("effect family schema is missing " ++ decl_name);
        }
    }
    if (FamilySchema.logical_family_name.len == 0) {
        @compileError("effect family schema must declare a non-empty logical_family_name");
    }
    if (FamilySchema.op_count != FamilySchema.ops.len) {
        @compileError("effect family schema op_count must match ops.len");
    }
    inline for (FamilySchema.ops) |OpSchema| {
        assertOpSchema(OpSchema);
    }
}

pub fn assertBindingSchema(comptime BindingSchema: type) void {
    if (!hasDeclSafe(BindingSchema, "requirement_label") or BindingSchema.requirement_label.len == 0) {
        @compileError("effect binding schema must declare a non-empty requirement_label");
    }
    if (!hasDeclSafe(BindingSchema, "Family") and !hasDeclSafe(BindingSchema, "family")) {
        @compileError("effect binding schema must declare Family or family");
    }
    if (!hasDeclSafe(BindingSchema, "Handler")) {
        @compileError("effect binding schema must declare Handler");
    }
    if (hasDeclSafe(BindingSchema, "Family") and hasDeclSafe(BindingSchema, "family") and BindingSchema.Family != BindingSchema.family) {
        @compileError("effect binding schema Family and family aliases must match");
    }
    assertFamilySchema(BindingSchemaFamily(BindingSchema));
}

fn BindingSchemaFamily(comptime BindingSchema: type) type {
    if (hasDeclSafe(BindingSchema, "Family")) return BindingSchema.Family;
    if (hasDeclSafe(BindingSchema, "family")) return BindingSchema.family;
    @compileError("effect binding schema must declare Family or family");
}

fn generatedSchemaOp(comptime GeneratedOp: type) type {
    return op(
        GeneratedOp.op_name,
        generatedControlMode(GeneratedOp.mode),
        GeneratedOp.Payload,
        GeneratedOp.Resume,
        generatedAfterStrategy(GeneratedOp.mode),
    );
}

fn bindingHasAfter(comptime OpSchema: type, comptime HandlerType: type) bool {
    return switch (OpSchema.after) {
        .none => false,
        .binding_optional => hasAfterMethod(HandlerType, OpSchema.name),
    };
}

fn afterMethodName(comptime op_name: []const u8) []const u8 {
    var buffer: [128]u8 = undefined;
    var len: usize = 0;
    buffer[len..][0..5].* = "after".*;
    len += 5;
    var upper_next = true;
    inline for (op_name) |byte| {
        if (byte == '_') {
            buffer[len] = byte;
            len += 1;
            upper_next = true;
            continue;
        }
        buffer[len] = if (upper_next and byte >= 'a' and byte <= 'z') byte - 32 else byte;
        len += 1;
        upper_next = false;
    }
    return buffer[0..len];
}

fn legacyAfterMethodName(comptime op_name: []const u8) []const u8 {
    var buffer: [128]u8 = undefined;
    var len: usize = 0;
    buffer[len..][0..5].* = "after".*;
    len += 5;
    var upper_next = true;
    inline for (op_name) |byte| {
        if (byte == '_') {
            upper_next = true;
            continue;
        }
        buffer[len] = if (upper_next and byte >= 'a' and byte <= 'z') byte - 32 else byte;
        len += 1;
        upper_next = false;
    }
    return buffer[0..len];
}

fn hasAfterMethod(comptime HandlerType: type, comptime op_name: []const u8) bool {
    const underscored_name = comptime afterMethodName(op_name);
    if (@hasDecl(HandlerType, underscored_name)) return true;
    const legacy_name = comptime legacyAfterMethodName(op_name);
    return !std.mem.eql(u8, legacy_name, underscored_name) and @hasDecl(HandlerType, legacy_name);
}

pub fn generated_family(comptime spec: anytype) type {
    const SpecType = @TypeOf(spec);
    const ErrorSetType: type = if (@hasField(SpecType, "error_set_type")) spec.error_set_type else error{};
    const StateType: type = spec.state_type;
    const mode = spec.ops[0].mode;
    const schema_ops = switch (spec.ops.len) {
        0 => .{},
        1 => .{generatedSchemaOp(spec.ops[0])},
        2 => .{ generatedSchemaOp(spec.ops[0]), generatedSchemaOp(spec.ops[1]) },
        3 => .{ generatedSchemaOp(spec.ops[0]), generatedSchemaOp(spec.ops[1]), generatedSchemaOp(spec.ops[2]) },
        4 => .{ generatedSchemaOp(spec.ops[0]), generatedSchemaOp(spec.ops[1]), generatedSchemaOp(spec.ops[2]), generatedSchemaOp(spec.ops[3]) },
        5 => .{ generatedSchemaOp(spec.ops[0]), generatedSchemaOp(spec.ops[1]), generatedSchemaOp(spec.ops[2]), generatedSchemaOp(spec.ops[3]), generatedSchemaOp(spec.ops[4]) },
        6 => .{ generatedSchemaOp(spec.ops[0]), generatedSchemaOp(spec.ops[1]), generatedSchemaOp(spec.ops[2]), generatedSchemaOp(spec.ops[3]), generatedSchemaOp(spec.ops[4]), generatedSchemaOp(spec.ops[5]) },
        7 => .{ generatedSchemaOp(spec.ops[0]), generatedSchemaOp(spec.ops[1]), generatedSchemaOp(spec.ops[2]), generatedSchemaOp(spec.ops[3]), generatedSchemaOp(spec.ops[4]), generatedSchemaOp(spec.ops[5]), generatedSchemaOp(spec.ops[6]) },
        8 => .{ generatedSchemaOp(spec.ops[0]), generatedSchemaOp(spec.ops[1]), generatedSchemaOp(spec.ops[2]), generatedSchemaOp(spec.ops[3]), generatedSchemaOp(spec.ops[4]), generatedSchemaOp(spec.ops[5]), generatedSchemaOp(spec.ops[6]), generatedSchemaOp(spec.ops[7]) },
        else => @compileError("generated family schema currently supports at most 8 ops"),
    };
    return familySchema(
        "generated_family",
        .generated_family,
        ErrorSetType,
        StateType,
        void,
        generatedOutputType(mode, StateType),
        generatedOutputTag(mode, StateType),
        void,
        void,
        void,
        void,
        schema_ops,
    );
}

pub fn Binding(
    comptime label: [:0]const u8,
    comptime FamilySchema: type,
    comptime HandlerType: type,
) type {
    return struct {
        pub const requirement_label: [:0]const u8 = label;
        pub const Family = FamilySchema;
        pub const family = FamilySchema;
        pub const Handler = HandlerType;
    };
}

pub fn row(comptime BindingSchema: type) effect_ir.Row {
    comptime assertBindingSchema(BindingSchema);
    const FamilySchema = BindingSchemaFamily(BindingSchema);
    const ops = FamilySchema.ops;
    const requirement_ops = comptime blk: {
        var buffer: [ops.len]effect_ir.OpSpec = undefined;
        for (ops, 0..) |OpSchema, index| {
            buffer[index] = .{
                .requirement_label = BindingSchema.requirement_label,
                .op_name = OpSchema.name,
                .mode = switch (OpSchema.control_mode) {
                    .transform => .transform,
                    .choice => .choice,
                    .abort => .abort,
                },
                .PayloadType = OpSchema.Payload,
                .ResumeType = OpSchema.Resume,
                .has_after = bindingHasAfter(OpSchema, BindingSchema.Handler),
            };
        }
        break :blk buffer;
    };
    const requirement = comptime effect_ir.Requirement{
        .label = BindingSchema.requirement_label,
        .ops = &requirement_ops,
    };
    return .{ .requirements = &.{requirement} };
}

pub fn outputs(comptime BindingSchema: type) []const effect_ir.OutputSpec {
    comptime assertBindingSchema(BindingSchema);
    const FamilySchema = BindingSchemaFamily(BindingSchema);
    return switch (FamilySchema.output) {
        .none => &.{},
        .final_state, .accumulator, .custom_finalizer => &.{.{
            .label = BindingSchema.requirement_label,
            .OutputType = FamilySchema.Output,
        }},
    };
}

test "state cell schema captures final-state output" {
    const Schema = state_cell(i32, error{});
    comptime assertFamilySchema(Schema);
    try std.testing.expectEqual(LifecycleTag.state_cell, Schema.lifecycle_tag);
    try std.testing.expectEqual(OutputTag.final_state, Schema.output);
    try std.testing.expectEqualStrings("get", Schema.ops[0].name);
    try std.testing.expectEqual(ControlMode.transform, Schema.ops[0].control_mode);
}

test "generated family schema marks transform and choice ops as binding-optional after hooks" {
    const TransformSchema = generated_family(.{
        .state_type = i32,
        .ops = .{
            struct {
                pub const op_name: [:0]const u8 = "get";
                pub const mode = enum { resume_then_transform, resume_or_return, direct_return }.resume_then_transform;
                pub const Payload = void;
                pub const Resume = i32;
            },
        },
    });
    try std.testing.expectEqual(AfterStrategy.binding_optional, TransformSchema.ops[0].after);

    const AbortSchema = generated_family(.{
        .state_type = void,
        .ops = .{
            struct {
                pub const op_name: [:0]const u8 = "fail";
                pub const mode = enum { resume_then_transform, resume_or_return, direct_return }.direct_return;
                pub const Payload = []const u8;
                pub const Resume = noreturn;
            },
        },
    });
    try std.testing.expectEqual(AfterStrategy.none, AbortSchema.ops[0].after);
}

test "binding lowers schema to logical requirement and output labels" {
    const StateBinding = Binding("state", state_cell(i32, error{}), void);
    const lowered_row = row(StateBinding);
    try std.testing.expectEqual(@as(usize, 1), lowered_row.requirements.len);
    try std.testing.expectEqualStrings("state", lowered_row.requirements[0].label);
    try std.testing.expectEqualStrings("get", lowered_row.requirements[0].ops[0].op_name);
    const lowered_outputs = outputs(StateBinding);
    try std.testing.expectEqual(@as(usize, 1), lowered_outputs.len);
    try std.testing.expectEqualStrings("state", lowered_outputs[0].label);
}

test "lower-case family binding alias lowers row and outputs" {
    const StateFamily = state_cell(i32, error{});
    const StateBinding = struct {
        pub const requirement_label: [:0]const u8 = "state";
        pub const family = StateFamily;
        pub const Handler = void;
    };
    const lowered_row = row(StateBinding);
    try std.testing.expectEqualStrings("state", lowered_row.requirements[0].label);
    const lowered_outputs = outputs(StateBinding);
    try std.testing.expectEqual(@as(usize, 1), lowered_outputs.len);
    try std.testing.expectEqual(i32, lowered_outputs[0].OutputType);
}

test "generated-family binding resolves optional after hooks from the handler type" {
    const Family = generated_family(.{
        .state_type = i32,
        .ops = .{
            struct {
                pub const op_name: [:0]const u8 = "get";
                pub const mode = enum { resume_then_transform, resume_or_return, direct_return }.resume_then_transform;
                pub const Payload = void;
                pub const Resume = i32;
            },
        },
    });
    const WithAfter = Binding("counter", Family, struct {
        pub fn afterGet(_: *@This(), answer: i32) i32 {
            return answer;
        }
    });
    const NoAfter = Binding("counter", Family, struct {});
    try std.testing.expect(row(WithAfter).requirements[0].ops[0].has_after);
    try std.testing.expect(!row(NoAfter).requirements[0].ops[0].has_after);
}
