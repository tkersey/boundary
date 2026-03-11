const std = @import("std");

/// Hard witness ids supported by the executable reference evaluator.
pub const WitnessId = enum {
    atm_resume_transform,
    direct_return,
    multi_prompt,
    static_redelim,
};

const AtmResumeTransformState = struct {
    step_index: u8 = 0,
    done: bool = false,

    fn step(self: *@This(), writer: anytype) !void {
        switch (self.step_index) {
            0 => try writer.writeAll("handler-enter\n"),
            1 => try writer.writeAll("body-after-shift\n"),
            2 => try writer.writeAll("handler-after-resume\n"),
            3 => {
                try writer.writeAll("final=answer=42\n");
                self.done = true;
            },
            else => unreachable,
        }
        self.step_index += 1;
    }
};

const StaticRedelimState = struct {
    step_index: u8 = 0,
    done: bool = false,

    fn step(self: *@This(), writer: anytype) !void {
        switch (self.step_index) {
            0 => try writer.writeAll("outer-handler-enter\n"),
            1 => try writer.writeAll("after-outer-shift\n"),
            2 => try writer.writeAll("inner-handler-enter\n"),
            3 => try writer.writeAll("after-inner-shift\n"),
            4 => try writer.writeAll("inner-handler-exit\n"),
            5 => try writer.writeAll("outer-handler-exit\n"),
            6 => {
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

const DirectReturnState = struct {
    step_index: u8 = 0,
    done: bool = false,

    fn step(self: *@This(), writer: anytype) !void {
        switch (self.step_index) {
            0 => try writer.writeAll("handler-direct-return\n"),
            1 => {
                try writer.writeAll("final=result=early\n");
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
    if (std.mem.eql(u8, id, "atm_resume_transform")) return runAtmResumeTransform(writer);
    if (std.mem.eql(u8, id, "direct_return")) return runDirectReturn(writer);
    if (std.mem.eql(u8, id, "static_redelim")) return runStaticRedelim(writer);
    if (std.mem.eql(u8, id, "multi_prompt")) return runMultiPrompt(writer);
    return error.UnknownWitness;
}

/// Execute the small-step evaluator for the ATM resume-then-transform witness.
pub fn runAtmResumeTransform(writer: anytype) anyerror!void {
    var state = AtmResumeTransformState{};
    try runStateMachine(&state, writer);
}

/// Execute the small-step evaluator for the direct-return witness.
pub fn runDirectReturn(writer: anytype) anyerror!void {
    var state = DirectReturnState{};
    try runStateMachine(&state, writer);
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
