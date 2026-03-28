const effect_ir = @import("effect_ir");
const open_row_descriptor_adapter = @import("internal/open_row_descriptor_adapter.zig");
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
        pub const Row = RowValue;
    };
}

fn Handled(comptime label_name: []const u8, comptime TargetType: type, comptime HandlerType: type) type {
    return struct {
        pub const handled_label = label_name;
        pub const Target = TargetType;
        pub const Handler = HandlerType;

        target: TargetType,
        handler: HandlerType,
    };
}

fn Bound(comptime TargetValue: anytype, comptime HandlersType: type) type {
    return if (@TypeOf(TargetValue) == type)
        struct {
            pub const body = TargetValue;
            pub const Handlers = HandlersType;

            handlers: HandlersType,
        }
    else
        struct {
            pub const Target = @TypeOf(TargetValue);
            pub const Handlers = HandlersType;

            target: @TypeOf(TargetValue),
            handlers: HandlersType,
        };
}

pub fn handle(comptime label: []const u8, handler: anytype, target: anytype) Handled(label, @TypeOf(target), @TypeOf(handler)) {
    return .{
        .target = target,
        .handler = handler,
    };
}

pub fn bind(target: anytype, handlers: anytype) Bound(target, @TypeOf(handlers)) {
    if (@TypeOf(target) == type) {
        return .{ .handlers = handlers };
    }
    return .{
        .target = target,
        .handlers = handlers,
    };
}

/// Execute one closed root built by `bind`.
pub fn runBound(runtime: anytype, bound: anytype) @TypeOf(with_api.with(runtime, open_row_descriptor_adapter.adaptHandlersForBody(@TypeOf(bound).body, bound.handlers), @TypeOf(bound).body)) {
    const BoundType = @TypeOf(bound);
    if (!@hasDecl(BoundType, "body")) {
        @compileError("runBound expects a value returned from bind(Body, handlers)");
    }
    const adapted = open_row_descriptor_adapter.adaptHandlersForBody(BoundType.body, bound.handlers);
    return with_api.with(runtime, adapted, BoundType.body);
}

/// Built-in row fragment constructors on top of the open-row core.
pub const effects = struct {
    pub fn state(comptime T: type) effect_ir.Row {
        return Row(.{
            .state = .{
                .get = Transform(void, T),
                .set = Transform(T, void),
            },
        });
    }

    pub fn reader(comptime T: type) effect_ir.Row {
        return Row(.{
            .reader = .{
                .ask = Transform(void, T),
            },
        });
    }

    pub fn writer(comptime T: type) effect_ir.Row {
        return Row(.{
            .writer = .{
                .tell = Transform(T, void),
            },
        });
    }

    pub fn optional(comptime T: type) effect_ir.Row {
        return Row(.{
            .optional = .{
                .request = Choice(T, T),
            },
        });
    }

    pub fn exception(comptime T: type) effect_ir.Row {
        return Row(.{
            .exception = .{
                .throw = Abort(T),
            },
        });
    }

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
