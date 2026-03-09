const shift = @import("shift");
const std = @import("std");

const EffectsSpec = shift.EffectSpec(struct {
    /// Prompt marker for the typed effect-handler example.
    pub const TagType = enum { token };
    /// Resume payload for the typed effect-handler example.
    pub const ResumeValue = union(enum) {
        count: usize,
        emitted: void,
        env: []const u8,
        put_ok: void,
    };
    /// Final answer for the typed effect-handler example.
    pub const AnswerValue = struct {
        env: []const u8,
        final_count: usize,
    };
    /// Operation payload for the typed effect-handler example.
    pub const OperationValue = union(enum) {
        ask_env: void,
        emit: []const u8,
        get_count: void,
        put_count: usize,
    };
});

const Program = struct {
    phase: enum {
        complete,
        emit_count_update,
        emit_env_read,
        need_env,
        need_get_count,
        need_put_count,
    } = .need_env,
    env: []const u8 = "",
    next_count: usize = 0,

        /// Advance the effectful program by one step.
        pub fn step(self: *@This(), input: EffectsSpec.ResumeInput) EffectsSpec.StepResult {
        return switch (self.phase) {
            .need_env => switch (input) {
                .start => blk: {
                    self.phase = .emit_env_read;
                    break :blk .{ .suspended = .{ .ask_env = {} } };
                },
                .value => unreachable,
            },
            .emit_env_read => switch (input) {
                .start => unreachable,
                .value => |value| switch (value) {
                    .env => |env| blk: {
                        self.env = env;
                        self.phase = .need_get_count;
                        break :blk .{ .suspended = .{ .emit = "env-read" } };
                    },
                    else => unreachable,
                },
            },
            .need_get_count => switch (input) {
                .start => unreachable,
                .value => |value| switch (value) {
                    .emitted => blk: {
                        self.phase = .need_put_count;
                        break :blk .{ .suspended = .{ .get_count = {} } };
                    },
                    else => unreachable,
                },
            },
            .need_put_count => switch (input) {
                .start => unreachable,
                .value => |value| switch (value) {
                    .count => |count| blk: {
                        self.next_count = count + 1;
                        self.phase = .emit_count_update;
                        break :blk .{ .suspended = .{ .put_count = self.next_count } };
                    },
                    else => unreachable,
                },
            },
            .emit_count_update => switch (input) {
                .start => unreachable,
                .value => |value| switch (value) {
                    .put_ok => blk: {
                        self.phase = .complete;
                        break :blk .{ .suspended = .{ .emit = "count-updated" } };
                    },
                    else => unreachable,
                },
            },
            .complete => switch (input) {
                .start => unreachable,
                .value => |value| switch (value) {
                    .emitted => .{ .done = .{ .env = self.env, .final_count = self.next_count } },
                    else => unreachable,
                },
            },
        };
    }
};

const TraceInterpreter = struct {
    allocator: std.mem.Allocator,
    trace: std.ArrayList([]const u8) = .empty,

    /// Interpret trace effects or decline them for another interpreter.
    pub fn handle(
        self: *@This(),
        operation: EffectsSpec.OperationValue,
        continuation: *EffectsSpec.Continuation(Program),
    ) anyerror!?EffectsSpec.RunState(Program) {
        return switch (operation) {
            .emit => |message| blk: {
                try self.trace.append(self.allocator, message);
                break :blk @as(?EffectsSpec.RunState(Program), try continuation.resumeWith(.{ .emitted = {} }));
            },
            else => null,
        };
    }
};

const EnvironmentInterpreter = struct {
    env: []const u8,

    /// Interpret environment effects or decline them for another interpreter.
    pub fn handle(
        self: *@This(),
        operation: EffectsSpec.OperationValue,
        continuation: *EffectsSpec.Continuation(Program),
    ) anyerror!?EffectsSpec.RunState(Program) {
        return switch (operation) {
            .ask_env => blk: {
                break :blk @as(?EffectsSpec.RunState(Program), try continuation.resumeWith(.{ .env = self.env }));
            },
            else => null,
        };
    }
};

const StateInterpreter = struct {
    count: usize,

    /// Interpret state effects or decline them for another interpreter.
    pub fn handle(
        self: *@This(),
        operation: EffectsSpec.OperationValue,
        continuation: *EffectsSpec.Continuation(Program),
    ) anyerror!?EffectsSpec.RunState(Program) {
        return switch (operation) {
            .get_count => blk: {
                break :blk @as(?EffectsSpec.RunState(Program), try continuation.resumeWith(.{ .count = self.count }));
            },
            .put_count => |next| blk: {
                self.count = next;
                break :blk @as(?EffectsSpec.RunState(Program), try continuation.resumeWith(.{ .put_ok = {} }));
            },
            else => null,
        };
    }
};

fn InterpreterChain(comptime Interpreters: type) type {
    return struct {
        interpreters: Interpreters,

        /// Interpret one effect by consulting each interpreter in order.
        pub fn handle(
            self: *@This(),
            operation: EffectsSpec.OperationValue,
            continuation: *EffectsSpec.Continuation(Program),
        ) anyerror!EffectsSpec.RunState(Program) {
            return dispatch(self, operation, continuation, 0);
        }

        fn dispatch(
            self: *@This(),
            operation: EffectsSpec.OperationValue,
            continuation: *EffectsSpec.Continuation(Program),
            comptime index: usize,
        ) anyerror!EffectsSpec.RunState(Program) {
            const fields = @typeInfo(Interpreters).@"struct".fields;
            if (index >= fields.len) return error.UnhandledEffect;

            const interpreter = &@field(self.interpreters, fields[index].name);
            if (try interpreter.handle(operation, continuation)) |next| return next;
            return dispatch(self, operation, continuation, index + 1);
        }
    };
}

const RunOutput = struct {
    answer: EffectsSpec.AnswerValue,
    trace: std.ArrayList([]const u8),
};

fn cleanupSession(session: *shift.raw.Session) void {
    session.close(.cancel) catch |err| switch (err) {
        error.SessionClosed => {},
        else => unreachable,
    };
    session.destroy() catch |err| switch (err) {
        error.SessionOpen => {},
        else => unreachable,
    };
}

fn runWithHandlers(allocator: std.mem.Allocator) anyerror!RunOutput {
    const session = try shift.raw.Session.create(allocator);
    var destroyed = false;
    defer if (!destroyed) cleanupSession(session);

    var interpreters = InterpreterChain(struct {
        trace: TraceInterpreter,
        state: StateInterpreter,
        environment: EnvironmentInterpreter,
    }){
        .interpreters = .{
            .trace = .{ .allocator = allocator },
            .state = .{ .count = 41 },
            .environment = .{ .env = "production" },
        },
    };
    errdefer interpreters.interpreters.trace.trace.deinit(allocator);

    var state = try EffectsSpec.start(Program, session, .{});

    while (true) {
        switch (state) {
            .done => |answer| {
                try session.close(.graceful);
                try session.destroy();
                destroyed = true;
                return .{
                    .answer = answer,
                    .trace = interpreters.interpreters.trace.trace,
                };
            },
            .suspended => |*suspension| {
                state = try interpreters.handle(suspension.operation, &suspension.continuation);
            },
        }
    }
}

/// Run the typed effect-handler example.
pub fn main() anyerror!void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    var output = try runWithHandlers(gpa.allocator());
    defer output.trace.deinit(gpa.allocator());

    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("env={s} final_count={d} trace=[", .{ output.answer.env, output.answer.final_count });
    for (output.trace.items, 0..) |entry, index| {
        if (index != 0) try stdout.print(", ", .{});
        try stdout.print("{s}", .{entry});
    }
    try stdout.print("]\n", .{});
    try stdout.flush();
}
