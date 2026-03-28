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

fn dummyPointer(comptime PtrType: type) PtrType {
    const pointer = @typeInfo(PtrType).pointer;
    const Child = std.meta.Child(PtrType);
    return switch (pointer.size) {
        .slice => blk: {
            const base = std.mem.alignForward(usize, 1, @alignOf(Child));
            const many = @as([*]Child, @ptrFromInt(base));
            const slice = many[0..1];
            if (pointer.is_const) break :blk @as(PtrType, slice);
            break :blk @as(PtrType, @constCast(slice));
        },
        else => @as(PtrType, @ptrFromInt(std.mem.alignForward(usize, 1, @alignOf(Child)))),
    };
}

fn dummyValue(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .pointer => dummyPointer(T),
        .optional => |optional| dummyValue(optional.child),
        .@"struct" => |info| blk: {
            var value_buffer: T = undefined;
            inline for (info.fields) |field| {
                @field(value_buffer, field.name) = dummyValue(field.type);
            }
            break :blk value_buffer;
        },
        .void => {},
        else => dummyPointer(*T).*,
    };
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
        5 => generated_family.Build(.{
            .state_type = StateTypeForPlainHandler(requirement, PlainHandler),
            .ops = .{
                GeneratedOpType(requirement.ops[0]),
                GeneratedOpType(requirement.ops[1]),
                GeneratedOpType(requirement.ops[2]),
                GeneratedOpType(requirement.ops[3]),
                GeneratedOpType(requirement.ops[4]),
            },
        }),
        6 => generated_family.Build(.{
            .state_type = StateTypeForPlainHandler(requirement, PlainHandler),
            .ops = .{
                GeneratedOpType(requirement.ops[0]),
                GeneratedOpType(requirement.ops[1]),
                GeneratedOpType(requirement.ops[2]),
                GeneratedOpType(requirement.ops[3]),
                GeneratedOpType(requirement.ops[4]),
                GeneratedOpType(requirement.ops[5]),
            },
        }),
        7 => generated_family.Build(.{
            .state_type = StateTypeForPlainHandler(requirement, PlainHandler),
            .ops = .{
                GeneratedOpType(requirement.ops[0]),
                GeneratedOpType(requirement.ops[1]),
                GeneratedOpType(requirement.ops[2]),
                GeneratedOpType(requirement.ops[3]),
                GeneratedOpType(requirement.ops[4]),
                GeneratedOpType(requirement.ops[5]),
                GeneratedOpType(requirement.ops[6]),
            },
        }),
        8 => generated_family.Build(.{
            .state_type = StateTypeForPlainHandler(requirement, PlainHandler),
            .ops = .{
                GeneratedOpType(requirement.ops[0]),
                GeneratedOpType(requirement.ops[1]),
                GeneratedOpType(requirement.ops[2]),
                GeneratedOpType(requirement.ops[3]),
                GeneratedOpType(requirement.ops[4]),
                GeneratedOpType(requirement.ops[5]),
                GeneratedOpType(requirement.ops[6]),
                GeneratedOpType(requirement.ops[7]),
            },
        }),
        else => @compileError("plain user-defined open-row adapter currently supports between 1 and 8 ops"),
    };
}

fn AdaptedDescriptorType(comptime requirement: effect_ir.Requirement, comptime PlainHandler: type, comptime AnswerType: type) type {
    const Family = FamilyTypeForRequirement(requirement, PlainHandler, AnswerType);
    return @TypeOf(Family.use(.{
        .handler = dummyValue(PlainHandler),
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

fn hasHandlerField(comptime HandlersType: type, comptime label: []const u8) bool {
    inline for (@typeInfo(HandlersType).@"struct".fields) |field| {
        if (comptime std.mem.eql(u8, field.name, label)) return true;
    }
    return false;
}

fn HandlerFieldType(comptime HandlersType: type, comptime label: []const u8) type {
    inline for (@typeInfo(HandlersType).@"struct".fields) |field| {
        if (comptime std.mem.eql(u8, field.name, label)) return field.type;
    }
    @compileError(std.fmt.comptimePrint("closed-root handlers are missing required label '{s}'", .{label}));
}

fn validateHandlersForBody(comptime Body: type, comptime HandlersType: type) void {
    const row = rowForBody(Body);
    inline for (row.requirements) |requirement| {
        if (!hasHandlerField(HandlersType, requirement.label)) {
            @compileError(std.fmt.comptimePrint("closed-root handlers are missing required label '{s}'", .{requirement.label}));
        }
    }
    inline for (@typeInfo(HandlersType).@"struct".fields) |field| {
        _ = requirementForLabel(row, field.name);
    }
}

/// Resolve the descriptor-adapted handler bundle type for one open-row body.
pub fn AdaptedHandlersType(comptime Body: type, comptime HandlersType: type) type {
    const info = @typeInfo(HandlersType);
    if (info != .@"struct") @compileError("closed-root handlers must be a struct literal or struct value");
    validateHandlersForBody(Body, HandlersType);

    const row = rowForBody(Body);

    var fields = [_]std.builtin.Type.StructField{.{
        .name = "",
        .type = void,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = @alignOf(void),
    }} ** row.requirements.len;

    inline for (row.requirements, 0..) |requirement, index| {
        const RawFieldType = HandlerFieldType(HandlersType, requirement.label);
        const FieldType = AdaptedFieldType(Body, requirement.label, RawFieldType);
        fields[index] = .{
            .name = opNameSentinel(requirement.label),
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
    inline for (rowForBody(Body).requirements) |requirement| {
        const field_name = requirement.label;
        const field_value = @field(handlers, field_name);
        const FieldType = @TypeOf(field_value);
        if (comptime isDescriptorLike(FieldType)) {
            @field(adapted_ptr.*, field_name) = field_value;
        } else {
            @field(adapted_ptr.*, field_name) = adaptedHandlerValue(
                requirement,
                FieldType,
                DeclaredBodyAnswerType(Body),
                field_value,
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

test "plain user-defined handlers adapt non-zeroable stateful fields" {
    const WorkflowRow = effect_ir.rowFromSpec(.{
        .search = .{
            .query = effect_ir.Transform([]const u8, i32),
        },
    });
    const workflow = struct {
        /// Capability bundle for the non-zeroable state adaptation test.
        pub const uses = shift.Uses(WorkflowRow);

        /// Trigger the adapted search op once.
        pub fn body(eff: anytype) anyerror!i32 {
            return try eff.search.query.perform("artifact-search");
        }
    };
    const SearchHandler = struct {
        allocator: std.mem.Allocator,

        /// Return the canonical search total while proving non-zeroable state is preserved.
        pub fn query(self: *@This(), payload: []const u8) i32 {
            _ = self.allocator;
            return if (std.mem.eql(u8, payload, "artifact-search")) 3 else 0;
        }
    };

    const adapted = adaptHandlersForBody(workflow, .{
        .search = SearchHandler{ .allocator = std.testing.allocator },
    });
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const result = try with_api.with(&runtime, adapted, workflow);
    try std.testing.expectEqual(@as(i32, 3), result.value);
}

test "plain stateless transform handlers do not synthesize output fields" {
    const WorkflowRow = effect_ir.rowFromSpec(.{
        .search = .{
            .query = effect_ir.Transform([]const u8, i32),
        },
    });
    const workflow = struct {
        /// Capability bundle for the stateless-transform regression test.
        pub const uses = shift.Uses(WorkflowRow);

        /// Trigger the stateless search op once.
        pub fn body(eff: anytype) anyerror!i32 {
            return try eff.search.query.perform("artifact-search");
        }
    };
    const search_handler = struct {
        /// Return the canonical stateless search total.
        pub fn query(_: *@This(), payload: []const u8) i32 {
            return if (std.mem.eql(u8, payload, "artifact-search")) 3 else 0;
        }
    };

    const adapted = adaptHandlersForBody(workflow, .{
        .search = search_handler{},
    });
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const result = try with_api.with(&runtime, adapted, workflow);

    try std.testing.expect(!@hasField(@TypeOf(result.outputs), "search"));
    try std.testing.expectEqual(@as(i32, 3), result.value);
}

test "adapted plain handlers follow row order instead of caller field order" {
    const WorkflowRow = effect_ir.mergeRows(.{
        effect_ir.rowFromSpec(.{
            .alpha = .{
                .tick = effect_ir.Transform(void, void),
            },
        }),
        effect_ir.rowFromSpec(.{
            .beta = .{
                .tick = effect_ir.Transform(void, void),
            },
        }),
    });
    const workflow = struct {
        /// Capability bundle for the row-order adaptation test.
        pub const uses = shift.Uses(WorkflowRow);

        /// Trigger both handlers so their after hooks can prove row-order stability.
        pub fn body(eff: anytype) anyerror!i32 {
            try eff.alpha.tick.perform();
            try eff.beta.tick.perform();
            return 0;
        }
    };
    const alpha_handler = struct {
        /// Mark the alpha branch without changing control flow directly.
        pub fn tick(_: *@This()) void {
            // Intentionally empty: the after hook carries the observable effect.
        }

        /// Encode the alpha branch into the answer.
        pub fn afterTick(_: *@This(), answer: i32) i32 {
            return answer * 10 + 1;
        }
    };
    const beta_handler = struct {
        /// Mark the beta branch without changing control flow directly.
        pub fn tick(_: *@This()) void {
            // Intentionally empty: the after hook carries the observable effect.
        }

        /// Encode the beta branch into the answer.
        pub fn afterTick(_: *@This(), answer: i32) i32 {
            return answer * 10 + 2;
        }
    };

    const canonical = adaptHandlersForBody(workflow, .{
        .alpha = alpha_handler{},
        .beta = beta_handler{},
    });
    const reordered = adaptHandlersForBody(workflow, .{
        .beta = beta_handler{},
        .alpha = alpha_handler{},
    });
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const canonical_result = try with_api.with(&runtime, canonical, workflow);
    const reordered_result = try with_api.with(&runtime, reordered, workflow);
    try std.testing.expectEqual(canonical_result.value, reordered_result.value);
}

test "plain user-defined handlers adapt requirements with up to eight ops" {
    const WorkflowRow = effect_ir.rowFromSpec(.{
        .multi = .{
            .one = effect_ir.Transform(void, i32),
            .two = effect_ir.Transform(void, i32),
            .three = effect_ir.Transform(void, i32),
            .four = effect_ir.Transform(void, i32),
            .five = effect_ir.Transform(void, i32),
            .six = effect_ir.Transform(void, i32),
            .seven = effect_ir.Transform(void, i32),
            .eight = effect_ir.Transform(void, i32),
        },
    });
    const workflow = struct {
        /// Capability bundle for the eight-op adaptation test.
        pub const uses = shift.Uses(WorkflowRow);

        /// Trigger every adapted op once and sum the results.
        pub fn body(eff: anytype) anyerror!i32 {
            return (try eff.multi.one.perform()) +
                (try eff.multi.two.perform()) +
                (try eff.multi.three.perform()) +
                (try eff.multi.four.perform()) +
                (try eff.multi.five.perform()) +
                (try eff.multi.six.perform()) +
                (try eff.multi.seven.perform()) +
                (try eff.multi.eight.perform());
        }
    };
    const handler = struct {
        /// Return the first canonical test value.
        pub fn one(_: *@This()) i32 {
            return 1;
        }

        /// Return the second canonical test value.
        pub fn two(_: *@This()) i32 {
            return 2;
        }

        /// Return the third canonical test value.
        pub fn three(_: *@This()) i32 {
            return 3;
        }

        /// Return the fourth canonical test value.
        pub fn four(_: *@This()) i32 {
            return 4;
        }

        /// Return the fifth canonical test value.
        pub fn five(_: *@This()) i32 {
            return 5;
        }

        /// Return the sixth canonical test value.
        pub fn six(_: *@This()) i32 {
            return 6;
        }

        /// Return the seventh canonical test value.
        pub fn seven(_: *@This()) i32 {
            return 7;
        }

        /// Return the eighth canonical test value.
        pub fn eight(_: *@This()) i32 {
            return 8;
        }
    };

    const adapted = adaptHandlersForBody(workflow, .{
        .multi = handler{},
    });
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    const result = try with_api.with(&runtime, adapted, workflow);
    try std.testing.expectEqual(@as(i32, 36), result.value);
}
