const effect_ir = @import("effect_ir");
const generated_family = @import("../effect/generated_family.zig");
const shift = @import("../root.zig");
const std = @import("std");
const with_api = @import("../with_api.zig");

fn hasDeclSafe(comptime T: type, comptime name: []const u8) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, name),
        else => false,
    };
}

/// Return whether a handler already matches the descriptor contract.
pub fn isDescriptorLike(comptime T: type) bool {
    return hasDeclSafe(T, "ErrorSet") and
        hasDeclSafe(T, "Output") and
        hasDeclSafe(T, "HandleType") and
        hasDeclSafe(T, "bindLexical") and
        hasDeclSafe(T, "run");
}

fn singleMode(comptime requirement: effect_ir.Requirement) effect_ir.ControlMode {
    if (requirement.ops.len == 0) {
        @compileError(std.fmt.comptimePrint("open-row requirement '{s}' must declare at least one op", .{requirement.label}));
    }
    const mode = requirement.ops[0].mode;
    inline for (requirement.ops[1..]) |op| {
        if (op.mode != mode) {
            @compileError(std.fmt.comptimePrint(
                "open-row requirement '{s}' must use a single control mode when adapting plain handlers",
                .{requirement.label},
            ));
        }
    }
    return mode;
}

fn requirementForLabel(comptime row: effect_ir.Row, comptime label: []const u8) effect_ir.Requirement {
    inline for (row.requirements) |requirement| {
        if (comptime std.mem.eql(u8, requirement.label, label)) return requirement;
    }
    @compileError(std.fmt.comptimePrint("row does not contain requirement '{s}'", .{label}));
}

fn rowForBody(comptime Body: type) effect_ir.Row {
    const uses_type = if (@hasDecl(Body, "Uses"))
        Body.Uses
    else if (@hasDecl(Body, "uses"))
        Body.uses
    else
        @compileError(@typeName(Body) ++ " must declare Uses = shift.Uses(...)");
    if (!@hasDecl(uses_type, "Row")) {
        @compileError(@typeName(Body) ++ ".Uses must expose Row");
    }
    return uses_type.Row;
}

fn StateTypeForPlainHandler(comptime requirement: effect_ir.Requirement, comptime PlainHandler: type) type {
    return switch (singleMode(requirement)) {
        .transform => if (@hasField(PlainHandler, "state"))
            @FieldType(PlainHandler, "state")
        else
            struct {},
        .choice, .abort => if (@hasField(PlainHandler, "state"))
            @FieldType(PlainHandler, "state")
        else
            struct {},
    };
}

fn opNameSentinel(comptime name: []const u8) [:0]const u8 {
    return name[0..name.len :0];
}

fn GeneratedOpType(comptime op: effect_ir.OpSpec) type {
    return switch (op.mode) {
        .transform => generated_family.ops.Transform(opNameSentinel(op.op_name), op.PayloadType, op.ResumeType),
        .choice => generated_family.ops.Choice(opNameSentinel(op.op_name), op.PayloadType, op.ResumeType),
        .abort => generated_family.ops.Abort(opNameSentinel(op.op_name), op.PayloadType),
    };
}

fn FamilyTypeForRequirement(comptime requirement: effect_ir.Requirement, comptime PlainHandler: type, comptime AnswerType: type) type {
    _ = AnswerType;
    return switch (requirement.ops.len) {
        1 => generated_family.Build(.{
            .state_type = StateTypeForPlainHandler(requirement, PlainHandler),
            .ops = .{GeneratedOpType(requirement.ops[0])},
        }),
        2 => generated_family.Build(.{
            .state_type = StateTypeForPlainHandler(requirement, PlainHandler),
            .ops = .{
                GeneratedOpType(requirement.ops[0]),
                GeneratedOpType(requirement.ops[1]),
            },
        }),
        3 => generated_family.Build(.{
            .state_type = StateTypeForPlainHandler(requirement, PlainHandler),
            .ops = .{
                GeneratedOpType(requirement.ops[0]),
                GeneratedOpType(requirement.ops[1]),
                GeneratedOpType(requirement.ops[2]),
            },
        }),
        4 => generated_family.Build(.{
            .state_type = StateTypeForPlainHandler(requirement, PlainHandler),
            .ops = .{
                GeneratedOpType(requirement.ops[0]),
                GeneratedOpType(requirement.ops[1]),
                GeneratedOpType(requirement.ops[2]),
                GeneratedOpType(requirement.ops[3]),
            },
        }),
        else => @compileError("plain user-defined open-row adapter currently supports between 1 and 4 ops"),
    };
}

fn AdaptedDescriptorType(comptime requirement: effect_ir.Requirement, comptime PlainHandler: type, comptime AnswerType: type) type {
    const Family = FamilyTypeForRequirement(requirement, PlainHandler, AnswerType);
    return @TypeOf(Family.use(.{
        .handler = std.mem.zeroInit(PlainHandler, .{}),
    }));
}

/// Adapt one plain handler value into a descriptor-compatible value.
pub fn adaptedHandlerValue(comptime requirement: effect_ir.Requirement, comptime PlainHandler: type, comptime AnswerType: type, handler: PlainHandler) AdaptedDescriptorType(requirement, PlainHandler, AnswerType) {
    const Family = FamilyTypeForRequirement(requirement, PlainHandler, AnswerType);
    return Family.use(.{
        .handler = handler,
    });
}

fn DeclaredBodyAnswerType(comptime Body: type) type {
    const BodyFn = if (@hasDecl(Body, "body")) @TypeOf(Body.body) else @TypeOf(Body.run);
    const ReturnType = @typeInfo(BodyFn).@"fn".return_type orelse @compileError(@typeName(Body) ++ " must return a concrete answer type");
    return switch (@typeInfo(ReturnType)) {
        .error_union => |err_union| err_union.payload,
        else => ReturnType,
    };
}

fn AdaptedFieldType(comptime Body: type, comptime label: []const u8, comptime HandlerType: type) type {
    if (isDescriptorLike(HandlerType)) return HandlerType;
    const requirement = requirementForLabel(rowForBody(Body), label);
    return AdaptedDescriptorType(requirement, HandlerType, DeclaredBodyAnswerType(Body));
}

/// Resolve the descriptor-adapted handler bundle type for one open-row body.
pub fn AdaptedHandlersType(comptime Body: type, comptime HandlersType: type) type {
    const info = @typeInfo(HandlersType);
    if (info != .@"struct") @compileError("closed-root handlers must be a struct literal or struct value");

    var fields = [_]std.builtin.Type.StructField{.{
        .name = "",
        .type = void,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = @alignOf(void),
    }} ** info.@"struct".fields.len;

    inline for (info.@"struct".fields, 0..) |field, index| {
        const FieldType = AdaptedFieldType(Body, field.name, field.type);
        fields[index] = .{
            .name = field.name,
            .type = FieldType,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(FieldType),
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

/// Adapt one handler bundle for a given open-row body.
pub fn adaptHandlersForBody(comptime Body: type, handlers: anytype) AdaptedHandlersType(Body, @TypeOf(handlers)) {
    const Adapted = AdaptedHandlersType(Body, @TypeOf(handlers));
    var storage: [@sizeOf(Adapted)]u8 align(@alignOf(Adapted)) = [_]u8{0} ** @sizeOf(Adapted);
    const adapted_ptr: *Adapted = @ptrCast(&storage);
    inline for (@typeInfo(@TypeOf(handlers)).@"struct".fields) |field| {
        if (comptime isDescriptorLike(field.type)) {
            @field(adapted_ptr.*, field.name) = @field(handlers, field.name);
        } else {
            const requirement = requirementForLabel(rowForBody(Body), field.name);
            @field(adapted_ptr.*, field.name) = adaptedHandlerValue(
                requirement,
                field.type,
                DeclaredBodyAnswerType(Body),
                @field(handlers, field.name),
            );
        }
    }
    return adapted_ptr.*;
}

test "plain user-defined transform handler adapts to a descriptor" {
    const WorkflowRow = effect_ir.rowFromSpec(.{
        .counter = .{
            .get = effect_ir.Transform(void, i32),
            .set = effect_ir.Transform(i32, void),
        },
    });
    const workflow = struct {
        /// Capability bundle for the adapter test workflow.
        pub const uses = struct {
            /// The row carried by the adapter test workflow.
            pub const Row = WorkflowRow;
        };

        /// Run the adapter test workflow.
        pub fn body(eff: anytype) anyerror!i32 {
            const before = try eff.counter.get.perform();
            try eff.counter.set.perform(before + 1);
            return try eff.counter.get.perform();
        }
    };
    const Handler = struct {
        state: i32,

        /// Read the current test counter state.
        pub fn get(self: *@This()) i32 {
            return self.state;
        }

        /// Replace the current test counter state.
        pub fn set(self: *@This(), value: i32) void {
            self.state = value;
        }
    };

    const adapted = adaptHandlersForBody(workflow, .{
        .counter = Handler{ .state = 5 },
    });
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const result = try with_api.with(&runtime, adapted, workflow);
    try std.testing.expectEqual(@as(i32, 6), result.value);
}

test "plain user-defined handlers adapt arbitrary op names and payload types" {
    const WorkflowRow = effect_ir.rowFromSpec(.{
        .counter = .{
            .increment = effect_ir.Transform(u64, void),
        },
        .chooser = .{
            .choose = effect_ir.Choice(bool, bool),
        },
    });
    const workflow = struct {
        /// Capability bundle for the arbitrary-op adaptation test.
        pub const uses = shift.Uses(WorkflowRow);

        /// Execute the arbitrary-op adaptation test workflow.
        pub fn body(eff: anytype) anyerror!u64 {
            try eff.counter.increment.perform(7);
            const selected = try eff.chooser.choose.perform(true, struct {
                /// Resume the arbitrary-op adaptation test continuation.
                pub fn apply(value: bool, _: anytype) anyerror!u64 {
                    return if (value) 11 else 0;
                }
            });
            return if (selected == 11) 18 else 0;
        }
    };
    const CounterHandler = struct {
        state: u64,

        /// Increase the test counter by the supplied payload.
        pub fn increment(self: *@This(), value: u64) void {
            self.state += value;
        }
    };
    const chooser_handler = struct {
        /// Resume the test choice branch with the supplied boolean.
        pub fn choose(_: *@This(), value: bool) shift.Decision(bool, u64) {
            return shift.Decision(bool, u64).resumeWith(value);
        }
    };

    const adapted = adaptHandlersForBody(workflow, .{
        .counter = CounterHandler{ .state = 11 },
        .chooser = chooser_handler{},
    });
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const result = try with_api.with(&runtime, adapted, workflow);
    try std.testing.expectEqual(@as(u64, 18), result.outputs.counter);
    try std.testing.expectEqual(@as(u64, 18), result.value);
}
