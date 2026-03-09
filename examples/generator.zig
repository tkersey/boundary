const shift = @import("shift");
const std = @import("std");

const GeneratorSpec = shift.EffectSpec(struct {
    /// Prompt marker for the generator example.
    pub const TagType = enum { token };
    /// Resume payload for the generator example.
    pub const ResumeValue = void;
    /// Final answer for the generator example.
    pub const AnswerValue = usize;
    /// Operation payload for the generator example.
    pub const OperationValue = union(enum) {
        yield_value: i32,
    };
});

const Machine = struct {
    next_value: i32 = 1,
    remaining: usize = 3,

    /// Advance the generator computation by one step.
    pub fn step(self: *@This(), input: GeneratorSpec.ResumeInput) GeneratorSpec.StepResult {
        switch (input) {
            .start => {},
            .value => {},
        }

        if (self.remaining == 0) return .{ .done = @intCast(self.next_value - 1) };

        const current = self.next_value;
        self.next_value += 1;
        self.remaining -= 1;
        return .{ .suspended = .{ .yield_value = current } };
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

/// Run the generator example.
pub fn main() anyerror!void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    const session = try shift.raw.Session.create(gpa.allocator());
    var destroyed = false;
    defer if (!destroyed) cleanupSession(session);

    var state = try GeneratorSpec.start(Machine, session, .{});
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    while (true) {
        switch (state) {
            .done => |answer| {
                try session.close(.graceful);
                try session.destroy();
                destroyed = true;
                try stdout.print("done={d}\n", .{answer});
                try stdout.flush();
                break;
            },
            .suspended => |*suspension| {
                try stdout.print("yield={d}\n", .{suspension.operation.yield_value});
                state = try suspension.continuation.resumeWith({});
            },
        }
    }
}
