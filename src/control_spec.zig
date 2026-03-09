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

/// Build a typed one-shot control family from one comptime specification.
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

        /// Typed one-shot continuation wrapper for one machine type.
        pub fn Continuation(comptime Machine: type) type {
            validateMachine(Machine);
            return struct {
                control: *raw.ContinuationControl,

                /// Retain another wrapper reference to the same continuation.
                pub fn clone(self: @This()) @This() {
                    self.control.retain();
                    return self;
                }

                /// Release one wrapper reference.
                pub fn release(self: *@This()) void {
                    self.control.release();
                }

                /// Resume a suspended machine with a typed value.
                pub fn resumeWith(self: *@This(), value: ResumeValueType) anyerror!RunState(Machine) {
                    try self.control.consume(.resumed);
                    return advanceBox(Machine, self.control, .{ .value = value });
                }

                /// Discard a suspended machine exactly once.
                pub fn discard(self: *@This()) anyerror!void {
                    try self.control.consume(.discarded);
                    self.control.discardFn(self.control);
                    retireControl(Machine, self.control);
                }
            };
        }

        /// Suspended operation plus its typed continuation.
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

        /// Start a managed machine, boxing it only if the first step suspends.
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

        /// Drive a machine to completion with a synchronous typed handler.
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
                        state = try handler.handle(suspension.operation, &suspension.continuation);
                    },
                }
            }
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

        fn retireControl(_: type, control: *raw.ContinuationControl) void {
            if (control.box_ptr != null) {
                control.destroyBoxFn(control);
            }
            if (control.owner_session) |session| {
                session.retire(control);
            }
            control.release();
        }

        fn advanceBox(
            comptime Machine: type,
            current_control: *raw.ContinuationControl,
            input: ResumeInputType,
        ) anyerror!RunState(Machine) {
            const box = boxFromControl(Machine, current_control);
            return switch (box.machine.step(input)) {
                .done => |answer| blk: {
                    retireControl(Machine, current_control);
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
                    current_control.release();
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
        error.SessionBusy, error.SessionOpen => {},
        else => unreachable,
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
