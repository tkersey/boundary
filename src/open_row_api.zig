const effect_ir = @import("effect_ir");
const open_row_descriptor_adapter = @import("internal/open_row_descriptor_adapter.zig");
const std = @import("std");
const with_api = @import("with_api.zig");

/// Re-export one transform leaf descriptor for the open-row surface.
pub const Transform = effect_ir.Transform;
/// Re-export one choice leaf descriptor for the open-row surface.
pub const Choice = effect_ir.Choice;
/// Re-export one abort leaf descriptor for the open-row surface.
pub const Abort = effect_ir.Abort;

/// One closed-root run result: explicit handled outputs plus answer value.
pub fn RunResult(comptime Outputs: type, comptime Answer: type) type {
    return struct {
        outputs: Outputs,
        value: Answer,
    };
}

/// Resolve one canonical row value from a nested row literal.
pub fn Row(comptime Spec: anytype) effect_ir.Row {
    return effect_ir.rowFromSpec(Spec);
}

/// Resolve one merged canonical row value from multiple row fragments.
pub fn mergeRows(comptime Specs: anytype) effect_ir.Row {
    return effect_ir.mergeRows(Specs);
}

/// Minimal capability-bundle carrier for the future direct-call surface.
pub fn Uses(comptime RowValue: effect_ir.Row) type {
    return struct {
        /// The normalized row carried by this capability bundle.
        pub const Row = RowValue;
    };
}

fn BodyTypeForTargetType(comptime TargetType: type) type {
    if (@hasDecl(TargetType, "Body")) return TargetType.Body;
    @compileError(@typeName(TargetType) ++ " must be a handled target returned from shift.handle(...)");
}

fn MaybeBodyTypeForTargetValue(comptime target: anytype) ?type {
    if (@TypeOf(target) == type) return target;
    if (@hasDecl(@TypeOf(target), "Body")) return @TypeOf(target).Body;
    return null;
}

fn assertStructHandlers(comptime HandlersType: type) void {
    if (@typeInfo(HandlersType) != .@"struct") {
        @compileError("closed-root handlers must be a struct literal or struct value");
    }
}

fn hasStructField(comptime StructType: type, comptime name: []const u8) bool {
    if (@typeInfo(StructType) != .@"struct") return false;
    inline for (@typeInfo(StructType).@"struct".fields) |field| {
        if (comptime std.mem.eql(u8, field.name, name)) return true;
    }
    return false;
}

fn sentinelName(comptime name: []const u8) [:0]const u8 {
    const owned = std.fmt.comptimePrint("{s}\x00", .{name});
    return owned[0..name.len :0];
}

fn AppendedHandlersType(comptime PrefixType: type, comptime label: []const u8, comptime HandlerType: type) type {
    assertStructHandlers(PrefixType);
    if (hasStructField(PrefixType, label)) {
        @compileError(std.fmt.comptimePrint("closed-root handlers already include handled label '{s}'", .{label}));
    }

    const prefix_fields = @typeInfo(PrefixType).@"struct".fields;
    var fields = [_]std.builtin.Type.StructField{.{
        .name = "",
        .type = void,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = @alignOf(void),
    }} ** (prefix_fields.len + 1);

    inline for (prefix_fields, 0..) |field, index| {
        fields[index] = .{
            .name = field.name,
            .type = field.type,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(field.type),
        };
    }
    fields[prefix_fields.len] = .{
        .name = sentinelName(label),
        .type = HandlerType,
        .default_value_ptr = null,
        .is_comptime = false,
        .alignment = @alignOf(HandlerType),
    };

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

fn ClosedHandlersType(comptime TargetType: type, comptime OuterHandlersType: type) type {
    assertStructHandlers(OuterHandlersType);
    if (TargetType == type) return OuterHandlersType;
    if (!@hasDecl(TargetType, "handled_label")) return OuterHandlersType;
    return ClosedHandlersType(
        TargetType.Target,
        AppendedHandlersType(OuterHandlersType, TargetType.handled_label, TargetType.Handler),
    );
}

fn copyHandlerFields(dest_ptr: anytype, value: anytype) void {
    inline for (@typeInfo(@TypeOf(value)).@"struct".fields) |field| {
        @field(dest_ptr.*, field.name) = @field(value, field.name);
    }
}

fn installHandledFields(dest_ptr: anytype, target: anytype) void {
    const TargetType = @TypeOf(target);
    if (!@hasDecl(TargetType, "handled_label")) return;
    @field(dest_ptr.*, TargetType.handled_label) = target.handler;
    if (@hasField(TargetType, "target") and @TypeOf(target.target) != type) installHandledFields(dest_ptr, target.target);
}

fn closeHandlersForTarget(target: anytype, handlers: anytype) ClosedHandlersType(@TypeOf(target), @TypeOf(handlers)) {
    const Closed = ClosedHandlersType(@TypeOf(target), @TypeOf(handlers));
    var storage: [@sizeOf(Closed)]u8 align(@alignOf(Closed)) = [_]u8{0} ** @sizeOf(Closed);
    const closed_ptr: *Closed = @ptrCast(&storage);
    copyHandlerFields(closed_ptr, handlers);
    installHandledFields(closed_ptr, target);
    return closed_ptr.*;
}

fn BoundBodyType(comptime BoundType: type) type {
    if (@hasDecl(BoundType, "Body")) return BoundType.Body;
    if (@hasDecl(BoundType, "body")) return BoundType.body;
    @compileError("runBound expects a value returned from bind(BodyOrHandledTarget, handlers)");
}

fn BoundHandlersType(comptime BoundType: type) type {
    return if (@hasField(BoundType, "target"))
        ClosedHandlersType(BoundType.Target, BoundType.Handlers)
    else
        BoundType.Handlers;
}

fn HandledWithBody(comptime label_name: []const u8, comptime TargetType: type, comptime HandlerType: type, comptime BodyType: type) type {
    return if (TargetType == type) struct {
        /// The handled label for this partial discharge wrapper.
        pub const handled_label = label_name;
        /// The target type wrapped by this handled value.
        pub const Target = TargetType;
        /// The handler type installed for the handled label.
        pub const Handler = HandlerType;
        /// The root body type enclosed by this handled target.
        pub const Body = BodyType;

        handler: HandlerType,
    } else struct {
        /// The handled label for this partial discharge wrapper.
        pub const handled_label = label_name;
        /// The target type wrapped by this handled value.
        pub const Target = TargetType;
        /// The handler type installed for the handled label.
        pub const Handler = HandlerType;
        /// The root body type enclosed by this handled target.
        pub const Body = BodyType;

        target: TargetType,
        handler: HandlerType,
    };
}

fn HandledWithoutBody(comptime label_name: []const u8, comptime TargetType: type, comptime HandlerType: type) type {
    return struct {
        /// The handled label for this partial discharge wrapper.
        pub const handled_label = label_name;
        /// The target type wrapped by this handled value.
        pub const Target = TargetType;
        /// The handler type installed for the handled label.
        pub const Handler = HandlerType;

        target: TargetType,
        handler: HandlerType,
    };
}

fn BoundBody(comptime BodyType: type, comptime HandlersType: type) type {
    return struct {
        /// The body type closed by this bind call.
        pub const body = BodyType;
        /// The body type closed by this bind call.
        pub const Body = BodyType;
        /// The handler bundle type closed by this bind call.
        pub const Handlers = HandlersType;

        handlers: HandlersType,
    };
}

fn BoundTarget(comptime TargetType: type, comptime HandlersType: type) type {
    return if (@hasDecl(TargetType, "Body"))
        struct {
            /// The target value type wrapped by this bind call.
            pub const Target = TargetType;
            /// The body type enclosed by the staged target.
            pub const Body = BodyTypeForTargetType(Target);
            /// The handler bundle type wrapped by this bind call.
            pub const Handlers = HandlersType;

            target: TargetType,
            handlers: HandlersType,
        }
    else
        struct {
            /// The target value type wrapped by this bind call.
            pub const Target = TargetType;
            /// The handler bundle type wrapped by this bind call.
            pub const Handlers = HandlersType;

            target: TargetType,
            handlers: HandlersType,
        };
}

/// Partially discharge one handled label around a target value.
pub fn handle(comptime label: []const u8, handler: anytype, target: anytype) if (MaybeBodyTypeForTargetValue(target)) |BodyType|
    HandledWithBody(label, @TypeOf(target), @TypeOf(handler), BodyType)
else
    HandledWithoutBody(label, @TypeOf(target), @TypeOf(handler)) {
    if (@TypeOf(target) == type) return .{ .handler = handler };
    return .{ .target = target, .handler = handler };
}

/// Bind a complete handler bundle around a body or handled target.
pub fn bind(target: anytype, handlers: anytype) if (@TypeOf(target) == type)
    BoundBody(target, @TypeOf(handlers))
else
    BoundTarget(@TypeOf(target), @TypeOf(handlers)) {
    if (@TypeOf(target) == type) {
        return .{ .handlers = handlers };
    }
    return .{
        .target = target,
        .handlers = handlers,
    };
}

/// Execute one closed root built by `bind`.
pub fn runBound(runtime: anytype, bound: anytype) with_api.WithFnReturnType(
    open_row_descriptor_adapter.AdaptedHandlersType(BoundBodyType(@TypeOf(bound)), BoundHandlersType(@TypeOf(bound))),
    BoundBodyType(@TypeOf(bound)),
) {
    const BoundType = @TypeOf(bound);
    const Body = BoundBodyType(BoundType);
    const closed_handlers = if (@hasField(BoundType, "target"))
        closeHandlersForTarget(bound.target, bound.handlers)
    else
        bound.handlers;
    const adapted = open_row_descriptor_adapter.adaptHandlersForBody(Body, closed_handlers);
    return with_api.with(runtime, adapted, Body);
}

/// Built-in row fragment constructors on top of the open-row core.
pub const effects = struct {
    /// Build the canonical state row fragment.
    pub fn state(comptime T: type) effect_ir.Row {
        return Row(.{
            .state = .{
                .get = Transform(void, T),
                .set = Transform(T, void),
            },
        });
    }

    /// Build the canonical reader row fragment.
    pub fn reader(comptime T: type) effect_ir.Row {
        return Row(.{
            .reader = .{
                .ask = Transform(void, T),
            },
        });
    }

    /// Build the canonical writer row fragment.
    pub fn writer(comptime T: type) effect_ir.Row {
        return Row(.{
            .writer = .{
                .tell = Transform(T, void),
            },
        });
    }

    /// Build the canonical optional row fragment.
    pub fn optional(comptime T: type) effect_ir.Row {
        return Row(.{
            .optional = .{
                .request = Choice(T, T),
            },
        });
    }

    /// Build the canonical exception row fragment.
    pub fn exception(comptime T: type) effect_ir.Row {
        return Row(.{
            .exception = .{
                .throw = Abort(T),
            },
        });
    }

    /// Build the canonical resource row fragment.
    pub fn resource(comptime T: type) effect_ir.Row {
        return Row(.{
            .resource = .{
                .acquire = Transform(void, T),
            },
        });
    }
};

test "RunResult keeps outputs and value fields" {
    const Result = RunResult(struct { state: i32 }, []const u8);
    const value: Result = .{
        .outputs = .{ .state = 7 },
        .value = "done",
    };
    try @import("std").testing.expectEqual(@as(i32, 7), value.outputs.state);
    try @import("std").testing.expectEqualStrings("done", value.value);
}

test "Uses carries the normalized row type" {
    const WorkflowRow = mergeRows(.{
        .{
            .writer = .{
                .tell = Transform([]const u8, void),
            },
        },
        .{
            .guard = .{
                .fail = Abort([]const u8),
            },
        },
    });
    const eff = Uses(WorkflowRow);
    const digest = try effect_ir.rowDigest(eff.Row, &.{});
    try @import("std").testing.expectEqual(@as(usize, 2), digest.requirement_count);
}

test "bind and handle preserve target and handler payloads" {
    const staged = handle("state", .{ .value = 1 }, .{ .name = "workflow" });
    const closed = bind(staged, .{ .writer = .{} });

    try @import("std").testing.expectEqualStrings("workflow", closed.target.target.name);
    try @import("std").testing.expectEqual(@as(i32, 1), closed.target.handler.value);
}

test "runBound executes handled targets bound with remaining handlers" {
    const WorkflowRow = mergeRows(.{
        effects.state(i32),
        effects.writer([]const u8),
    });
    const workflow_type = struct {
        /// Capability bundle for the handled-root execution test.
        pub const uses = Uses(WorkflowRow);

        /// Execute the handled-root test workflow through state and writer handlers.
        pub fn body(eff: anytype) anyerror![]const u8 {
            const before = try eff.state.get();
            try eff.state.set(before + 1);
            try eff.writer.tell("queued");
            return "done";
        }
    };

    var runtime = @import("root.zig").Runtime.init(@import("std").testing.allocator);
    defer runtime.deinit();

    const staged = handle("state", @import("open_row_handlers.zig").state(@as(i32, 5)), workflow_type);
    const closed = bind(staged, .{
        .writer = @import("open_row_handlers.zig").writer([]const u8, @import("std").testing.allocator),
    });
    const result = try runBound(&runtime, closed);
    defer @import("std").testing.allocator.free(result.outputs.writer);

    try @import("std").testing.expectEqual(@as(i32, 6), result.outputs.state);
    try @import("std").testing.expectEqual(@as(usize, 1), result.outputs.writer.len);
    try @import("std").testing.expectEqualStrings("queued", result.outputs.writer[0]);
    try @import("std").testing.expectEqualStrings("done", result.value);
}

test "builtin row fragments normalize to one requirement each" {
    const workflow = mergeRows(.{
        effects.state(i32),
        effects.writer([]const u8),
        effects.exception([]const u8),
    });
    const digest = try effect_ir.rowDigest(workflow, &.{});
    try @import("std").testing.expectEqual(@as(usize, 3), digest.requirement_count);
    try @import("std").testing.expectEqual(@as(usize, 4), digest.op_count);
}

test "builtin resource row fragment normalizes to one requirement" {
    const workflow = effects.resource([]const u8);
    const digest = try effect_ir.rowDigest(workflow, &.{});
    try @import("std").testing.expectEqual(@as(usize, 1), digest.requirement_count);
    try @import("std").testing.expectEqual(@as(usize, 1), digest.op_count);
}
