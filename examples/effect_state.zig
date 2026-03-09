const shift = @import("shift");
const std = @import("std");

const StateSpec = shift.EffectSpec(struct {
    /// Prompt marker for the effect-state example.
    pub const TagType = enum { token };
    /// Resume payload for the effect-state example.
    pub const ResumeValue = union(enum) {
        got: i32,
        put_ok: void,
    };
    /// Final answer for the effect-state example.
    pub const AnswerValue = i32;
    /// Operation payload for the effect-state example.
    pub const OperationValue = union(enum) {
        get: void,
        put: i32,
    };
});

const Machine = struct {
    phase: enum {
        complete,
        need_get,
        need_put,
    } = .need_get,
    cached: i32 = 0,

    /// Advance the stateful computation by one step.
    pub fn step(self: *@This(), input: StateSpec.ResumeInput) StateSpec.StepResult {
        return switch (self.phase) {
            .need_get => switch (input) {
                .start => blk: {
                    self.phase = .need_put;
                    break :blk .{ .suspended = .{ .get = {} } };
                },
                .value => unreachable,
            },
            .need_put => switch (input) {
                .start => unreachable,
                .value => |value| switch (value) {
                    .got => |got| blk: {
                        self.cached = got + 1;
                        self.phase = .complete;
                        break :blk .{ .suspended = .{ .put = self.cached } };
                    },
                    .put_ok => unreachable,
                },
            },
            .complete => switch (input) {
                .start => unreachable,
                .value => |value| switch (value) {
                    .put_ok => .{ .done = self.cached },
                    .got => unreachable,
                },
            },
        };
    }
};

const Handler = struct {
    state: i32,

    /// Resolve one effect operation and resume the computation.
    pub fn handle(
        self: *@This(),
        operation: StateSpec.OperationValue,
        continuation: *StateSpec.Continuation(Machine),
    ) anyerror!StateSpec.RunState(Machine) {
        return switch (operation) {
            .get => continuation.resumeWith(.{ .got = self.state }),
            .put => |next| blk: {
                self.state = next;
                break :blk continuation.resumeWith(.{ .put_ok = {} });
            },
        };
    }
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

/// Run the effect-state example.
pub fn main() anyerror!void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    const session = try shift.raw.Session.create(gpa.allocator());
    var destroyed = false;
    defer if (!destroyed) cleanupSession(session);

    var handler = Handler{ .state = 41 };
    const answer = try StateSpec.handle(Machine, Handler, session, .{}, &handler);
    try session.close(.graceful);
    try session.destroy();
    destroyed = true;
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("answer={d} final_state={d}\n", .{ answer, handler.state });
    try stdout.flush();
}
