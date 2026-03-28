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



fn callNoPayload(self: anytype, comptime name: []const u8) @TypeOf(@field(@TypeOf(self.inner), name)(&self.inner)) {
    return @field(@TypeOf(self.inner), name)(&self.inner);
}

fn callPayload(self: anytype, comptime name: []const u8, payload: anytype) @TypeOf(@field(@TypeOf(self.inner), name)(&self.inner, payload)) {
    return @field(@TypeOf(self.inner), name)(&self.inner, payload);
}

fn callAfter(
    self: anytype,
    comptime name: []const u8,
    answer: anytype,
) if (@hasDecl(@TypeOf(self.inner), name))
    @TypeOf(@field(@TypeOf(self.inner), name)(&self.inner, answer))
else
    @TypeOf(answer) {
    if (!@hasDecl(@TypeOf(self.inner), name)) return answer;
    return @field(@TypeOf(self.inner), name)(&self.inner, answer);
}

fn WrappedHandlerType(comptime requirement: effect_ir.Requirement, comptime AnswerType: type, comptime PlainHandler: type) type {
    const StateType = StateTypeForPlainHandler(requirement, PlainHandler);
    return struct {
        inner: PlainHandler,
        state: StateType,

        fn innerPtr(self: *@This()) *PlainHandler {
            return &self.inner;
        }

        fn syncState(self: *@This()) void {
            if (@hasField(PlainHandler, "state")) self.state = @field(self.inner, "state");
        }

        /// Initialize the wrapped plain handler state.
        pub fn init(inner: PlainHandler) @This() {
            return .{
                .inner = inner,
                .state = if (@hasField(PlainHandler, "state")) @field(inner, "state") else .{},
            };
        }

        /// Forward one payload-free operation into the wrapped handler.
        pub fn get(self: *@This()) @TypeOf(callNoPayload(self, "get")) {
            const result = callNoPayload(self, "get");
            self.syncState();
            return result;
        }

        /// Forward one post-resume hook after `get`.
        pub fn afterGet(self: *@This(), answer: AnswerType) @TypeOf(callAfter(self, "afterGet", answer)) {
            return callAfter(self, "afterGet", answer);
        }

        /// Forward one payloaded operation into the wrapped handler.
        pub fn set(self: *@This(), value: i32) @TypeOf(callPayload(self, "set", value)) {
            const result = callPayload(self, "set", value);
            self.syncState();
            return result;
        }

        /// Forward one post-resume hook after `set`.
        pub fn afterSet(self: *@This(), answer: AnswerType) @TypeOf(callAfter(self, "afterSet", answer)) {
            return callAfter(self, "afterSet", answer);
        }

        /// Forward one search operation into the wrapped handler.
        pub fn search(self: *@This(), payload: []const u8) @TypeOf(callPayload(self, "search", payload)) {
            const result = callPayload(self, "search", payload);
            self.syncState();
            return result;
        }

        /// Forward one post-resume hook after `search`.
        pub fn afterSearch(self: *@This(), answer: AnswerType) @TypeOf(callAfter(self, "afterSearch", answer)) {
            return callAfter(self, "afterSearch", answer);
        }

        /// Forward one query operation into the wrapped handler.
        pub fn query(self: *@This(), payload: []const u8) @TypeOf(callPayload(self, "query", payload)) {
            const result = callPayload(self, "query", payload);
            self.syncState();
            return result;
        }

        /// Forward one post-resume hook after `query`.
        pub fn afterQuery(self: *@This(), answer: AnswerType) @TypeOf(callAfter(self, "afterQuery", answer)) {
            return callAfter(self, "afterQuery", answer);
        }

        /// Forward one choice operation into the wrapped handler.
        pub fn pick(self: *@This(), payload: i32) @TypeOf(callPayload(self, "pick", payload)) {
            const result = callPayload(self, "pick", payload);
            self.syncState();
            return result;
        }

        /// Forward one post-resume hook after `pick`.
        pub fn afterPick(self: *@This(), answer: AnswerType) @TypeOf(callAfter(self, "afterPick", answer)) {
            return callAfter(self, "afterPick", answer);
        }

        /// Forward one payload-free choice operation into the wrapped handler.
        pub fn publish(self: *@This()) @TypeOf(callNoPayload(self, "publish")) {
            const result = callNoPayload(self, "publish");
            self.syncState();
            return result;
        }

        /// Forward one post-resume hook after `publish`.
        pub fn afterPublish(self: *@This(), answer: AnswerType) @TypeOf(callAfter(self, "afterPublish", answer)) {
            return callAfter(self, "afterPublish", answer);
        }

        /// Forward one abort operation into the wrapped handler.
        pub fn fail(self: *@This(), payload: []const u8) @TypeOf(callPayload(self, "fail", payload)) {
            const result = callPayload(self, "fail", payload);
            self.syncState();
            return result;
        }
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
    const Wrapped = WrappedHandlerType(requirement, AnswerType, PlainHandler);
    const Family = FamilyTypeForRequirement(requirement, PlainHandler, AnswerType);
    return @TypeOf(Family.use(.{
        .handler = Wrapped.init(std.mem.zeroInit(PlainHandler, .{})),
    }));
}

/// Adapt one plain handler value into a descriptor-compatible value.
pub fn adaptedHandlerValue(comptime requirement: effect_ir.Requirement, comptime PlainHandler: type, comptime AnswerType: type, handler: PlainHandler) AdaptedDescriptorType(requirement, PlainHandler, AnswerType) {
    const Wrapped = WrappedHandlerType(requirement, AnswerType, PlainHandler);
    const Family = FamilyTypeForRequirement(requirement, PlainHandler, AnswerType);
    return Family.use(.{
        .handler = Wrapped.init(handler),
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

fn AdaptedHandlersType(comptime Body: type, comptime HandlersType: type) type {
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
