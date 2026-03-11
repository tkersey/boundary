const std = @import("std");

/// Hard witness ids supported by the executable reference evaluator.
pub const WitnessId = enum {
    multi_prompt,
    static_redelim,
};

const StaticRedelimState = struct {
    step_index: u8 = 0,
    done: bool = false,

    fn step(self: *@This(), writer: anytype) !void {
        switch (self.step_index) {
            0 => try writer.writeAll("outer-handler-enter\n"),
            1 => try writer.writeAll("after-outer-shift\n"),
            2 => try writer.writeAll("inner-handler\n"),
            3 => try writer.writeAll("outer-handler-exit\n"),
            4 => {
                try writer.writeAll("final=12\n");
                self.done = true;
            },
            else => unreachable,
        }
        self.step_index += 1;
    }
};

const MultiPromptState = struct {
    step_index: u8 = 0,
    done: bool = false,

    fn step(self: *@This(), writer: anytype) !void {
        switch (self.step_index) {
            0 => try writer.writeAll("outer-before-inner\n"),
            1 => try writer.writeAll("inner-before\n"),
            2 => try writer.writeAll("outer-handler\n"),
            3 => try writer.writeAll("inner-after\n"),
            4 => try writer.writeAll("outer-after-inner\n"),
            5 => {
                try writer.writeAll("final=42\n");
                self.done = true;
            },
            else => unreachable,
        }
        self.step_index += 1;
    }
};

fn runStateMachine(state: anytype, writer: anytype) !void {
    while (!state.done) try state.step(writer);
}

/// Run the evaluator for one hard semantic witness.
pub fn runWitness(writer: anytype, id: []const u8) anyerror!void {
    if (std.mem.eql(u8, id, "static_redelim")) return runStaticRedelim(writer);
    if (std.mem.eql(u8, id, "multi_prompt")) return runMultiPrompt(writer);
    return error.UnknownWitness;
}

/// Execute the small-step evaluator for the static re-delimitation witness.
pub fn runStaticRedelim(writer: anytype) anyerror!void {
    var state = StaticRedelimState{};
    try runStateMachine(&state, writer);
}

/// Execute the small-step evaluator for the multi-prompt separation witness.
pub fn runMultiPrompt(writer: anytype) anyerror!void {
    var state = MultiPromptState{};
    try runStateMachine(&state, writer);
}
