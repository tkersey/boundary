const raw = @import("raw.zig");
const std = @import("std");

fn hasDeclSafe(comptime T: type, comptime name: []const u8) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, name),
        else => false,
    };
}

fn assertTaggedUnion(comptime T: type, comptime label: []const u8) void {
    switch (@typeInfo(T)) {
        .@"union" => |info| {
            if (info.tag_type == null) {
                @compileError(label ++ " must be a tagged union");
            }
        },
        else => @compileError(label ++ " must be a tagged union"),
    }
}

fn validateSpec(comptime Spec: type) void {
    if (!hasDeclSafe(Spec, "TagType")) @compileError("ControlSpec requires Spec.TagType");
    if (!hasDeclSafe(Spec, "ResumeValue")) @compileError("ControlSpec requires Spec.ResumeValue");
    if (!hasDeclSafe(Spec, "AnswerValue")) @compileError("ControlSpec requires Spec.AnswerValue");
    if (!hasDeclSafe(Spec, "OperationValue")) @compileError("ControlSpec requires Spec.OperationValue");
    assertTaggedUnion(Spec.OperationValue, "Spec.OperationValue");
}

fn StartOrResume(comptime Resume: type) type {
    return union(enum) {
        start: void,
        value: Resume,
    };
}

fn StepResult(comptime Operation: type, comptime Answer: type) type {
    return union(enum) {
        done: Answer,
        suspended: Operation,
    };
}

/// Build a typed one-shot effect interface from one comptime specification.
pub fn ControlSpec(comptime Spec: type) type {
    validateSpec(Spec);

    const ResumeValueType = Spec.ResumeValue;
    const AnswerValueType = Spec.AnswerValue;
    const OperationValueType = Spec.OperationValue;
    const TagMarkerType = Spec.TagType;
    const ResumeInputType = StartOrResume(ResumeValueType);
    const StepResultType = StepResult(OperationValueType, AnswerValueType);
    const prompt_token_t = struct {};

    comptime {
        if (@sizeOf(prompt_token_t) != 0) {
            @compileError("prompt tokens must stay zero-sized");
        }
    }

    return struct {
        /// Zero-sized prompt marker for this control family.
        pub const prompt_token = prompt_token_t;
        /// Resume payload type for suspended continuations.
        pub const ResumeValue = ResumeValueType;
        /// Final answer type for the delimited computation.
        pub const AnswerValue = AnswerValueType;
        /// Tagged-union operation surface handled by this family.
        pub const OperationValue = OperationValueType;
        /// Input passed to a machine step on first entry or resumption.
        pub const ResumeInput = ResumeInputType;
        /// Step result returned by a machine implementation.
        pub const StepResult = StepResultType;
        /// Unique prompt marker type for this family.
        pub const TagType = TagMarkerType;

        /// Construct the zero-sized prompt token.
        pub fn prompt() prompt_token {
            return .{};
        }

        /// Release-only alias to an owned suspended continuation.
        pub fn ContinuationAlias(comptime Machine: type) type {
            validateMachine(Machine);
            return struct {
                control: ?*raw.ContinuationControl,

                /// Release one alias reference.
                pub fn release(self: *@This()) anyerror!void {
                    const control = try requireLiveControl(self.control);
                    try control.release();
                    self.control = null;
                }
            };
        }

        /// Typed one-shot continuation for one computation type.
        pub fn Continuation(comptime Machine: type) type {
            validateMachine(Machine);
            return struct {
                control: ?*raw.ContinuationControl,

                /// Create a release-only alias to the same continuation.
                pub fn alias(self: *@This()) anyerror!ContinuationAlias(Machine) {
                    const control = try requireLiveControl(self.control);
                    try control.retain();
                    return .{ .control = control };
                }

                /// Release an owner wrapper only after the continuation is no longer active.
                pub fn release(self: *@This()) anyerror!void {
                    const control = try requireLiveControl(self.control);
                    if (control.box_ptr != null and control.state == .fresh and control.owner_state == .alive) {
                        return error.SessionBusy;
                    }
                    try control.release();
                    self.control = null;
                }

                /// Resume a suspended machine with a typed value.
                pub fn resumeWith(self: *@This(), value: ResumeValueType) anyerror!RunState(Machine) {
                    const control = try requireLiveControl(self.control);
                    try control.consume(.resumed);
                    const next_state = try advanceBox(Machine, control, .{ .value = value });
                    self.control = null;
                    return next_state;
                }

                /// Discard a suspended machine exactly once.
                pub fn discard(self: *@This()) anyerror!void {
                    const control = try requireLiveControl(self.control);
                    try control.consume(.discarded);
                    control.discardFn(control);
                    try retireControl(Machine, control);
                    self.control = null;
                }
            };
        }

        /// Suspended effect plus its typed continuation.
        pub fn Suspension(comptime Machine: type) type {
            validateMachine(Machine);
            return struct {
                operation: OperationValueType,
                continuation: Continuation(Machine),
            };
        }

        /// Either a completed answer or a typed suspension.
        pub fn RunState(comptime Machine: type) type {
            validateMachine(Machine);
            return union(enum) {
                done: AnswerValueType,
                suspended: Suspension(Machine),
            };
        }

        /// Start an effectful computation, boxing it only if the first step suspends.
        pub fn start(
            comptime Machine: type,
            session: *raw.Session,
            machine: Machine,
        ) anyerror!RunState(Machine) {
            validateMachine(Machine);
            try session.ensureCanStart();

            var local = machine;
            return switch (local.step(.{ .start = {} })) {
                .done => |answer| .{ .done = answer },
                .suspended => |operation| blk: {
                    const machine_box = try session.allocator.create(MachineBox(Machine));
                    errdefer session.allocator.destroy(machine_box);
                    machine_box.* = .{ .machine = local };

                    const control = try createControl(Machine, session, machine_box);
                    break :blk .{
                        .suspended = .{
                            .operation = operation,
                            .continuation = .{ .control = control },
                        },
                    };
                },
            };
        }

        /// Drive a computation to completion with a synchronous typed interpreter.
        pub fn handle(
            comptime Machine: type,
            comptime Handler: type,
            session: *raw.Session,
            machine: Machine,
            handler: *Handler,
        ) anyerror!AnswerValueType {
            var state = try start(Machine, session, machine);
            while (true) {
                switch (state) {
                    .done => |answer| return answer,
                    .suspended => |*suspension| {
                        state = handler.handle(suspension.operation, &suspension.continuation) catch |err| {
                            if (suspension.continuation.control != null) {
                                suspension.continuation.discard() catch |cleanup_err| switch (cleanup_err) {
                                    error.AlreadyResolved, error.SessionClosed, error.SessionDestroyed => {},
                                    else => unreachable,
                                };
                            }
                            return err;
                        };
                    },
                }
            }
        }

        fn requireLiveControl(control: ?*raw.ContinuationControl) raw.Error!*raw.ContinuationControl {
            return control orelse error.AlreadyResolved;
        }

        fn validateMachine(comptime Machine: type) void {
            if (!std.meta.hasMethod(Machine, "step")) {
                @compileError(@typeName(Machine) ++ " must declare step(self, input)");
            }

            const step_fn_info = @typeInfo(@TypeOf(Machine.step)).@"fn";
            if (step_fn_info.params.len != 2) {
                @compileError(@typeName(Machine) ++ ".step must accept self and one input");
            }

            const InputType = step_fn_info.params[1].type orelse
                @compileError(@typeName(Machine) ++ ".step input type must be known");
            if (InputType != ResumeInputType) {
                @compileError(@typeName(Machine) ++ ".step input must be " ++ @typeName(ResumeInputType));
            }

            const ReturnType = step_fn_info.return_type orelse
                @compileError(@typeName(Machine) ++ ".step must declare a return type");
            if (ReturnType != StepResultType) {
                @compileError(@typeName(Machine) ++ ".step must return " ++ @typeName(StepResultType));
            }
        }

        fn MachineBox(comptime Machine: type) type {
            return struct {
                machine: Machine,
            };
        }

        fn boxFromControl(comptime Machine: type, control: *raw.ContinuationControl) *MachineBox(Machine) {
            return @ptrCast(@alignCast(control.box_ptr.?));
        }

        fn createControl(
            comptime Machine: type,
            session: *raw.Session,
            box: *MachineBox(Machine),
        ) anyerror!*raw.ContinuationControl {
            const control = try session.allocator.create(raw.ContinuationControl);
            control.* = .{
                .allocator = session.allocator,
                .thread_id = std.Thread.getCurrentId(),
                .owner_session = session,
                .box_ptr = @ptrCast(box),
                .discardFn = discardFn(Machine),
                .destroyBoxFn = destroyBoxFn(Machine),
                .destroySelfFn = destroySelfFn(),
            };
            session.retainActive(control);
            return control;
        }

        fn discardFn(comptime Machine: type) *const fn (*raw.ContinuationControl) void {
            return struct {
                fn call(control: *raw.ContinuationControl) void {
                    if (control.box_ptr == null) return;
                    const box = boxFromControl(Machine, control);
                    if (comptime hasDeclSafe(Machine, "onDiscard")) box.machine.onDiscard();
                }
            }.call;
        }

        fn destroyBoxFn(comptime Machine: type) *const fn (*raw.ContinuationControl) void {
            return struct {
                fn call(control: *raw.ContinuationControl) void {
                    if (control.box_ptr == null) return;
                    const box = boxFromControl(Machine, control);
                    if (comptime hasDeclSafe(Machine, "onDestroy")) box.machine.onDestroy();
                    control.allocator.destroy(box);
                    control.box_ptr = null;
                }
            }.call;
        }

        fn destroySelfFn() *const fn (*raw.ContinuationControl) void {
            return struct {
                fn call(control: *raw.ContinuationControl) void {
                    control.allocator.destroy(control);
                }
            }.call;
        }

        fn retireControl(_: type, control: *raw.ContinuationControl) anyerror!void {
            if (control.box_ptr != null) {
                control.destroyBoxFn(control);
            }
            if (control.owner_session) |session| {
                session.retire(control);
            }
            try control.release();
        }

        fn advanceBox(
            comptime Machine: type,
            current_control: *raw.ContinuationControl,
            input: ResumeInputType,
        ) anyerror!RunState(Machine) {
            const box = boxFromControl(Machine, current_control);
            return switch (box.machine.step(input)) {
                .done => |answer| blk: {
                    try retireControl(Machine, current_control);
                    break :blk .{ .done = answer };
                },
                .suspended => |operation| blk: {
                    const session = current_control.owner_session.?;
                    const next_control = try createControl(Machine, session, box);
                    current_control.box_ptr = null;
                    if (session.active_count > 0) {
                        // current_control is still active at the list head until retired below
                    }
                    session.retire(current_control);
                    try current_control.release();
                    break :blk .{
                        .suspended = .{
                            .operation = operation,
                            .continuation = .{ .control = next_control },
                        },
                    };
                },
            };
        }
    };
}

fn cleanupSession(session: *raw.Session, mode: raw.CloseMode) void {
    session.close(mode) catch |err| switch (err) {
        error.SessionClosed => {},
        else => unreachable,
    };
    session.destroy() catch |err| switch (err) {
        error.SessionOpen => {},
        else => unreachable,
    };
}

const ReleaseOrder = enum {
    forward,
    reverse,
};

fn LifecycleLawHarness(comptime Spec: type, comptime Machine: type, comptime max_aliases: usize) type {
    const alias_capacity = if (max_aliases == 0) 1 else max_aliases;
    return struct {
        session: *raw.Session,
        owner: Spec.Continuation(Machine),
        aliases: [alias_capacity]Spec.ContinuationAlias(Machine) = [_]Spec.ContinuationAlias(Machine){.{ .control = null }} ** alias_capacity,
        alias_count: usize = 0,
        destroyed: bool = false,

        fn init(allocator: std.mem.Allocator, machine: Machine) anyerror!@This() {
            const session = try raw.Session.create(allocator);
            const initial_state = try Spec.start(Machine, session, machine);
            return .{
                .session = session,
                .owner = switch (initial_state) {
                    .done => unreachable,
                    .suspended => |suspension| suspension.continuation,
                },
            };
        }

        fn deinit(self: *@This()) void {
            if (self.owner.control != null) {
                self.owner.release() catch |err| switch (err) {
                    error.AlreadyResolved => {},
                    error.SessionBusy => self.owner.discard() catch |discard_err| switch (discard_err) {
                        error.AlreadyResolved => {},
                        else => unreachable,
                    },
                    else => unreachable,
                };
            }
            self.releaseAliases(.reverse) catch |err| switch (err) {
                error.AlreadyResolved => {},
                else => unreachable,
            };
            if (!self.destroyed) cleanupSession(self.session, .cancel);
        }

        fn addAliases(self: *@This(), count: usize) anyerror!void {
            std.debug.assert(count <= max_aliases);
            var index: usize = 0;
            while (index < count) : (index += 1) {
                self.aliases[index] = try self.owner.alias();
            }
            self.alias_count = count;
        }

        fn releaseAliases(self: *@This(), order: ReleaseOrder) anyerror!void {
            switch (order) {
                .forward => {
                    var index: usize = 0;
                    while (index < self.alias_count) : (index += 1) {
                        try self.aliases[index].release();
                    }
                },
                .reverse => {
                    var index = self.alias_count;
                    while (index > 0) {
                        index -= 1;
                        try self.aliases[index].release();
                    }
                },
            }
            self.alias_count = 0;
        }

        fn close(self: *@This(), mode: raw.CloseMode) anyerror!void {
            try self.session.close(mode);
        }

        fn destroy(self: *@This()) anyerror!void {
            try self.session.destroy();
            self.destroyed = true;
        }

        fn assertQuiescent(self: *@This()) anyerror!void {
            if (self.destroyed) return;
            const stats = try self.session.snapshot();
            try std.testing.expectEqual(@as(usize, 0), stats.active_count);
            try std.testing.expectEqual(@as(usize, 0), stats.retired_count);
        }
    };
}

test "zero-sized prompt tokens stay free" {
    const spec_t = ControlSpec(struct {
        /// Prompt marker for the unit test family.
        pub const TagType = enum { token };
        /// Resume payload for the unit test family.
        pub const ResumeValue = u8;
        /// Final answer for the unit test family.
        pub const AnswerValue = u8;
        /// Operation payload for the unit test family.
        pub const OperationValue = union(enum) {
            ping: void,
        };
    });
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(spec_t.prompt_token));
}

test "start suspend resume completes once" {
    const spec_t = ControlSpec(struct {
        /// Prompt marker for the suspend-resume test.
        pub const TagType = enum { token };
        /// Resume payload for the suspend-resume test.
        pub const ResumeValue = u8;
        /// Final answer for the suspend-resume test.
        pub const AnswerValue = u8;
        /// Operation payload for the suspend-resume test.
        pub const OperationValue = union(enum) {
            ping: u8,
        };
    });

    const Machine = struct {
        phase: enum { complete, initial } = .initial,
        /// Advance the one-shot machine by one step.
        pub fn step(self: *@This(), input: spec_t.ResumeInput) spec_t.StepResult {
            return switch (self.phase) {
                .initial => switch (input) {
                    .start => blk: {
                        self.phase = .complete;
                        break :blk .{ .suspended = .{ .ping = 41 } };
                    },
                    .value => unreachable,
                },
                .complete => switch (input) {
                    .start => unreachable,
                    .value => |value| .{ .done = value + 1 },
                },
            };
        }
    };

    const session = try raw.Session.create(std.testing.allocator);
    defer cleanupSession(session, .cancel);

    var state = try spec_t.start(Machine, session, .{});
    switch (state) {
        .done => unreachable,
        .suspended => |*suspension| {
            try std.testing.expectEqual(@as(u8, 41), suspension.operation.ping);
            state = try suspension.continuation.resumeWith(41);
        },
    }

    switch (state) {
        .done => |answer| try std.testing.expectEqual(@as(u8, 42), answer),
        .suspended => unreachable,
    }
}

test "continuation owner and alias surfaces stay separated" {
    const spec_t = ControlSpec(struct {
        /// Prompt marker for the ownership-surface test.
        pub const TagType = enum { token };
        /// Resume payload for the ownership-surface test.
        pub const ResumeValue = u8;
        /// Final answer for the ownership-surface test.
        pub const AnswerValue = u8;
        /// Operation payload for the ownership-surface test.
        pub const OperationValue = union(enum) {
            ping: u8,
        };
    });

    const machine_t = struct {
        /// Suspend once so the owner and alias surfaces can be inspected.
        pub fn step(_: *@This(), input: spec_t.ResumeInput) spec_t.StepResult {
            return switch (input) {
                .start => .{ .suspended = .{ .ping = 1 } },
                .value => |value| .{ .done = value },
            };
        }
    };

    try std.testing.expect(std.meta.hasMethod(spec_t.Continuation(machine_t), "alias"));
    try std.testing.expect(!std.meta.hasMethod(spec_t.Continuation(machine_t), "clone"));
    try std.testing.expect(std.meta.hasMethod(spec_t.Continuation(machine_t), "release"));
    try std.testing.expect(std.meta.hasMethod(spec_t.ContinuationAlias(machine_t), "release"));
    try std.testing.expect(!std.meta.hasMethod(spec_t.ContinuationAlias(machine_t), "alias"));
    try std.testing.expect(!std.meta.hasMethod(spec_t.ContinuationAlias(machine_t), "resumeWith"));
    try std.testing.expect(!std.meta.hasMethod(spec_t.ContinuationAlias(machine_t), "discard"));
}

test "owner lifecycle matrix covers active, closed, destroyed, and resolved states" {
    const spec_t = ControlSpec(struct {
        /// Prompt marker for the lifecycle-matrix test.
        pub const TagType = enum { token };
        /// Resume payload for the lifecycle-matrix test.
        pub const ResumeValue = u8;
        /// Final answer for the lifecycle-matrix test.
        pub const AnswerValue = u8;
        /// Operation payload for the lifecycle-matrix test.
        pub const OperationValue = union(enum) {
            ping: u8,
        };
    });

    const Action = enum {
        discard,
        release,
        resume_with,
    };
    const Preparation = enum {
        active,
        closed,
        destroyed,
        resolved,
    };
    const Case = struct {
        name: []const u8,
        preparation: Preparation,
        action: Action,
        expected_error: ?raw.Error,
        expected_answer: ?u8 = null,
    };

    const MachineT = struct {
        phase: enum { complete, initial } = .initial,

        /// Suspend once, then complete on the first resumption value.
        pub fn step(self: *@This(), input: spec_t.ResumeInput) spec_t.StepResult {
            return switch (self.phase) {
                .initial => switch (input) {
                    .start => blk: {
                        self.phase = .complete;
                        break :blk .{ .suspended = .{ .ping = 5 } };
                    },
                    .value => unreachable,
                },
                .complete => switch (input) {
                    .start => unreachable,
                    .value => |value| .{ .done = value + 1 },
                },
            };
        }
    };

    const cases = [_]Case{
        .{ .name = "active resume", .preparation = .active, .action = .resume_with, .expected_error = null, .expected_answer = 8 },
        .{ .name = "active discard", .preparation = .active, .action = .discard, .expected_error = null },
        .{ .name = "active release", .preparation = .active, .action = .release, .expected_error = error.SessionBusy },
        .{ .name = "closed resume", .preparation = .closed, .action = .resume_with, .expected_error = error.SessionClosed },
        .{ .name = "closed discard", .preparation = .closed, .action = .discard, .expected_error = error.SessionClosed },
        .{ .name = "closed release", .preparation = .closed, .action = .release, .expected_error = null },
        .{ .name = "destroyed resume", .preparation = .destroyed, .action = .resume_with, .expected_error = error.SessionDestroyed },
        .{ .name = "destroyed discard", .preparation = .destroyed, .action = .discard, .expected_error = error.SessionDestroyed },
        .{ .name = "destroyed release", .preparation = .destroyed, .action = .release, .expected_error = null },
        .{ .name = "resolved resume", .preparation = .resolved, .action = .resume_with, .expected_error = error.AlreadyResolved },
        .{ .name = "resolved discard", .preparation = .resolved, .action = .discard, .expected_error = error.AlreadyResolved },
        .{ .name = "resolved release", .preparation = .resolved, .action = .release, .expected_error = error.AlreadyResolved },
    };

    for (cases) |case| {
        var harness = try LifecycleLawHarness(spec_t, MachineT, 0).init(std.testing.allocator, .{});
        defer harness.deinit();

        switch (case.preparation) {
            .active => {},
            .closed => try harness.close(.cancel),
            .destroyed => {
                try harness.close(.graceful);
                try harness.destroy();
            },
            .resolved => try harness.owner.discard(),
        }

        switch (case.action) {
            .resume_with => {
                if (case.expected_error) |expected| {
                    try std.testing.expectError(expected, harness.owner.resumeWith(7));
                    switch (case.preparation) {
                        .closed, .destroyed => try harness.owner.release(),
                        else => {},
                    }
                } else {
                    const resumed = try harness.owner.resumeWith(7);
                    switch (resumed) {
                        .done => |answer| try std.testing.expectEqual(case.expected_answer.?, answer),
                        .suspended => unreachable,
                    }
                    try harness.assertQuiescent();
                }
            },
            .discard => {
                if (case.expected_error) |expected| {
                    try std.testing.expectError(expected, harness.owner.discard());
                    switch (case.preparation) {
                        .closed, .destroyed => try harness.owner.release(),
                        else => {},
                    }
                } else {
                    try harness.owner.discard();
                    try harness.assertQuiescent();
                }
            },
            .release => {
                if (case.expected_error) |expected| {
                    try std.testing.expectError(expected, harness.owner.release());
                    if (case.preparation == .active) {
                        try harness.owner.discard();
                        try harness.assertQuiescent();
                    }
                } else {
                    try harness.owner.release();
                    try harness.assertQuiescent();
                }
            },
        }
    }
}

test "alias counts drain after discard across a small range" {
    const spec_t = ControlSpec(struct {
        /// Prompt marker for the alias-drain property test.
        pub const TagType = enum { token };
        /// Resume payload for the alias-drain property test.
        pub const ResumeValue = void;
        /// Final answer for the alias-drain property test.
        pub const AnswerValue = void;
        /// Operation payload for the alias-drain property test.
        pub const OperationValue = union(enum) {
            ping: void,
        };
    });

    const machine_t = struct {
        /// Suspend once so the discard path can be observed.
        pub fn step(_: *@This(), input: spec_t.ResumeInput) spec_t.StepResult {
            return switch (input) {
                .start => .{ .suspended = .{ .ping = {} } },
                .value => unreachable,
            };
        }
    };

    const max_aliases = 4;
    var alias_count: usize = 0;
    while (alias_count <= max_aliases) : (alias_count += 1) {
        var harness = try LifecycleLawHarness(spec_t, machine_t, max_aliases).init(std.testing.allocator, .{});
        defer harness.deinit();

        try harness.addAliases(alias_count);
        try harness.owner.discard();
        try harness.releaseAliases(.reverse);
        try harness.assertQuiescent();
    }
}

test "alias counts drain after destroy across a small range" {
    const spec_t = ControlSpec(struct {
        /// Prompt marker for the post-destroy alias-drain test.
        pub const TagType = enum { token };
        /// Resume payload for the post-destroy alias-drain test.
        pub const ResumeValue = void;
        /// Final answer for the post-destroy alias-drain test.
        pub const AnswerValue = void;
        /// Operation payload for the post-destroy alias-drain test.
        pub const OperationValue = union(enum) {
            ping: void,
        };
    });

    const machine_t = struct {
        /// Suspend once so destroyed owners and aliases can be drained.
        pub fn step(_: *@This(), input: spec_t.ResumeInput) spec_t.StepResult {
            return switch (input) {
                .start => .{ .suspended = .{ .ping = {} } },
                .value => unreachable,
            };
        }
    };

    const max_aliases = 4;
    var alias_count: usize = 0;
    while (alias_count <= max_aliases) : (alias_count += 1) {
        var harness = try LifecycleLawHarness(spec_t, machine_t, max_aliases).init(std.testing.allocator, .{});
        defer harness.deinit();

        try harness.addAliases(alias_count);
        try harness.close(.graceful);
        try harness.destroy();
        try std.testing.expectError(error.SessionDestroyed, harness.owner.discard());
        try harness.owner.release();
        try harness.releaseAliases(.reverse);
    }
}

test "handle discards active continuation on handler error" {
    const HandlerError = error{Boom};
    const spec_t = ControlSpec(struct {
        /// Prompt marker for the handler-error test.
        pub const TagType = enum { token };
        /// Resume payload for the handler-error test.
        pub const ResumeValue = void;
        /// Final answer for the handler-error test.
        pub const AnswerValue = void;
        /// Operation payload for the handler-error test.
        pub const OperationValue = union(enum) {
            ping: void,
        };
    });

    const machine_t = struct {
        /// Suspend once so the handler can fail before consuming the owner.
        pub fn step(_: *@This(), input: spec_t.ResumeInput) spec_t.StepResult {
            return switch (input) {
                .start => .{ .suspended = .{ .ping = {} } },
                .value => unreachable,
            };
        }
    };

    const handler_t = struct {
        /// Fail immediately so the helper must discard the active owner.
        pub fn handle(_: *@This(), _: spec_t.OperationValue, _: *spec_t.Continuation(machine_t)) HandlerError!spec_t.RunState(machine_t) {
            return error.Boom;
        }
    };

    const session = try raw.Session.create(std.testing.allocator);
    defer cleanupSession(session, .cancel);

    var handler: handler_t = .{};
    try std.testing.expectError(error.Boom, spec_t.handle(machine_t, handler_t, session, .{}, &handler));
    const stats = try session.snapshot();
    try std.testing.expectEqual(@as(usize, 0), stats.active_count);
    try std.testing.expectEqual(@as(usize, 0), stats.retired_count);
}

test "alias release rejects cross-thread use" {
    const spec_t = ControlSpec(struct {
        /// Prompt marker for the cross-thread alias test.
        pub const TagType = enum { token };
        /// Resume payload for the cross-thread alias test.
        pub const ResumeValue = void;
        /// Final answer for the cross-thread alias test.
        pub const AnswerValue = void;
        /// Operation payload for the cross-thread alias test.
        pub const OperationValue = union(enum) {
            ping: void,
        };
    });

    const machine_t = struct {
        /// Suspend once so an alias can be tested from another thread.
        pub fn step(_: *@This(), input: spec_t.ResumeInput) spec_t.StepResult {
            return switch (input) {
                .start => .{ .suspended = .{ .ping = {} } },
                .value => unreachable,
            };
        }
    };

    const AttemptT = struct {
        alias: spec_t.ContinuationAlias(machine_t),
        result: ?anyerror = null,

        /// Attempt to release the alias from the wrong thread.
        fn run(self: *@This()) void {
            self.alias.release() catch |err| {
                self.result = err;
                return;
            };
        }
    };

    const session = try raw.Session.create(std.testing.allocator);
    defer cleanupSession(session, .cancel);

    var state = try spec_t.start(machine_t, session, .{});
    switch (state) {
        .done => unreachable,
        .suspended => |*suspension| {
            var attempt = AttemptT{ .alias = try suspension.continuation.alias() };
            var thread = try std.Thread.spawn(.{}, AttemptT.run, .{&attempt});
            thread.join();
            try std.testing.expectEqual(error.CrossThread, attempt.result.?);

            try suspension.continuation.discard();
            try attempt.alias.release();
            const stats = try session.snapshot();
            try std.testing.expectEqual(@as(usize, 0), stats.active_count);
            try std.testing.expectEqual(@as(usize, 0), stats.retired_count);
        },
    }
}

test "no capture path works under failing allocator" {
    const spec_t = ControlSpec(struct {
        /// Prompt marker for the no-capture test.
        pub const TagType = enum { token };
        /// Resume payload for the no-capture test.
        pub const ResumeValue = void;
        /// Final answer for the no-capture test.
        pub const AnswerValue = usize;
        /// Operation payload for the no-capture test.
        pub const OperationValue = union(enum) {
            impossible: void,
        };
    });

    const machine_t = struct {
        /// Complete immediately without suspending.
        pub fn step(_: *@This(), input: spec_t.ResumeInput) spec_t.StepResult {
            return switch (input) {
                .start => .{ .done = 7 },
                .value => unreachable,
            };
        }
    };

    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    const session = try raw.Session.create(failing.allocator());
    defer cleanupSession(session, .cancel);

    const state = try spec_t.start(machine_t, session, .{});
    switch (state) {
        .done => |answer| try std.testing.expectEqual(@as(usize, 7), answer),
        .suspended => unreachable,
    }
}
