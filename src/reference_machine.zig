const std = @import("std");

/// Hard witness ids supported by the executable reference machine.
pub const WitnessId = enum {
    multi_prompt,
    static_redelim,
};

const StaticRedelimState = union(enum) {
    after_outer_shift,
    complete,
    inner_handler,
    outer_handler_enter,
    outer_handler_exit,
    start,

    fn step(self: *@This(), writer: anytype) !void {
        switch (self.*) {
            .start => self.* = .outer_handler_enter,
            .outer_handler_enter => {
                try writer.writeAll("outer-handler-enter\n");
                self.* = .after_outer_shift;
            },
            .after_outer_shift => {
                try writer.writeAll("after-outer-shift\n");
                self.* = .inner_handler;
            },
            .inner_handler => {
                try writer.writeAll("inner-handler\n");
                self.* = .outer_handler_exit;
            },
            .outer_handler_exit => {
                try writer.writeAll("outer-handler-exit\n");
                self.* = .complete;
            },
            .complete => {
                try writer.writeAll("final=12\n");
                self.* = .start;
            },
        }
    }
};

const MultiPromptState = union(enum) {
    complete,
    inner_after,
    inner_before,
    outer_after_inner,
    outer_before_inner,
    outer_handler,
    start,

    fn step(self: *@This(), writer: anytype) !void {
        switch (self.*) {
            .start => self.* = .outer_before_inner,
            .outer_before_inner => {
                try writer.writeAll("outer-before-inner\n");
                self.* = .inner_before;
            },
            .inner_before => {
                try writer.writeAll("inner-before\n");
                self.* = .outer_handler;
            },
            .outer_handler => {
                try writer.writeAll("outer-handler\n");
                self.* = .inner_after;
            },
            .inner_after => {
                try writer.writeAll("inner-after\n");
                self.* = .outer_after_inner;
            },
            .outer_after_inner => {
                try writer.writeAll("outer-after-inner\n");
                self.* = .complete;
            },
            .complete => {
                try writer.writeAll("final=42\n");
                self.* = .start;
            },
        }
    }
};

fn runStateMachine(state: anytype, writer: anytype) !void {
    while (true) {
        switch (state.*) {
            .complete => {
                try state.step(writer);
                break;
            },
            else => try state.step(writer),
        }
    }
}

/// Run the reference machine for one hard semantic witness.
pub fn runWitness(writer: anytype, id: []const u8) anyerror!void {
    if (std.mem.eql(u8, id, "static_redelim")) return runStaticRedelim(writer);
    if (std.mem.eql(u8, id, "multi_prompt")) return runMultiPrompt(writer);
    return error.UnknownWitness;
}

/// Execute the reference machine for the static re-delimitation witness.
pub fn runStaticRedelim(writer: anytype) anyerror!void {
    var state: StaticRedelimState = .start;
    try runStateMachine(&state, writer);
}

/// Execute the reference machine for the prompt-value separation witness.
pub fn runMultiPrompt(writer: anytype) anyerror!void {
    var state: MultiPromptState = .start;
    try runStateMachine(&state, writer);
}
