const std = @import("std");

/// Hard witness ids supported by the executable reference machine.
pub const WitnessId = enum {
    atm_resume_transform,
    direct_return,
    multi_prompt,
    resume_or_return_resume,
    resume_or_return_return_now,
    static_redelim,
};

const AtmResumeTransformState = union(enum) {
    body_after_shift,
    complete,
    handler_after_resume,
    handler_enter,
    start,

    fn step(self: *@This(), writer: anytype) !void {
        switch (self.*) {
            .start => self.* = .handler_enter,
            .handler_enter => {
                try writer.writeAll("handler-enter\n");
                self.* = .body_after_shift;
            },
            .body_after_shift => {
                try writer.writeAll("body-after-shift\n");
                self.* = .handler_after_resume;
            },
            .handler_after_resume => {
                try writer.writeAll("handler-after-resume\n");
                self.* = .complete;
            },
            .complete => {
                try writer.writeAll("final=answer=42\n");
                self.* = .start;
            },
        }
    }
};

const StaticRedelimState = union(enum) {
    after_inner_shift,
    after_outer_shift,
    complete,
    inner_handler_enter,
    inner_handler_exit,
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
                self.* = .inner_handler_enter;
            },
            .inner_handler_enter => {
                try writer.writeAll("inner-handler-enter\n");
                self.* = .after_inner_shift;
            },
            .after_inner_shift => {
                try writer.writeAll("after-inner-shift\n");
                self.* = .inner_handler_exit;
            },
            .inner_handler_exit => {
                try writer.writeAll("inner-handler-exit\n");
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

const DirectReturnState = union(enum) {
    complete,
    handler_direct_return,
    start,

    fn step(self: *@This(), writer: anytype) !void {
        switch (self.*) {
            .start => self.* = .handler_direct_return,
            .handler_direct_return => {
                try writer.writeAll("handler-direct-return\n");
                self.* = .complete;
            },
            .complete => {
                try writer.writeAll("final=result=early\n");
                self.* = .start;
            },
        }
    }
};

const ResumeOrReturnReturnNowState = union(enum) {
    complete,
    handler_return_now,
    start,

    fn step(self: *@This(), writer: anytype) !void {
        switch (self.*) {
            .start => self.* = .handler_return_now,
            .handler_return_now => {
                try writer.writeAll("handler-return-now\n");
                self.* = .complete;
            },
            .complete => {
                try writer.writeAll("final=result=early\n");
                self.* = .start;
            },
        }
    }
};

const ResumeOrReturnResumeState = union(enum) {
    body_after_shift,
    complete,
    handler_after_resume,
    handler_decide_resume,
    start,

    fn step(self: *@This(), writer: anytype) !void {
        switch (self.*) {
            .start => self.* = .handler_decide_resume,
            .handler_decide_resume => {
                try writer.writeAll("handler-decide-resume\n");
                self.* = .body_after_shift;
            },
            .body_after_shift => {
                try writer.writeAll("body-after-shift\n");
                self.* = .handler_after_resume;
            },
            .handler_after_resume => {
                try writer.writeAll("handler-after-resume\n");
                self.* = .complete;
            },
            .complete => {
                try writer.writeAll("final=answer=42\n");
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
    if (std.mem.eql(u8, id, "atm_resume_transform")) return runAtmResumeTransform(writer);
    if (std.mem.eql(u8, id, "direct_return")) return runDirectReturn(writer);
    if (std.mem.eql(u8, id, "static_redelim")) return runStaticRedelim(writer);
    if (std.mem.eql(u8, id, "multi_prompt")) return runMultiPrompt(writer);
    if (std.mem.eql(u8, id, "resume_or_return_return_now")) return runResumeOrReturnReturnNow(writer);
    if (std.mem.eql(u8, id, "resume_or_return_resume")) return runResumeOrReturnResume(writer);
    return error.UnknownWitness;
}

/// Execute the reference machine for the ATM resume-then-transform witness.
pub fn runAtmResumeTransform(writer: anytype) anyerror!void {
    var state: AtmResumeTransformState = .start;
    try runStateMachine(&state, writer);
}

/// Execute the reference machine for the direct-return witness.
pub fn runDirectReturn(writer: anytype) anyerror!void {
    var state: DirectReturnState = .start;
    try runStateMachine(&state, writer);
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

/// Execute the reference machine for the optional-resumption direct-return witness.
pub fn runResumeOrReturnReturnNow(writer: anytype) anyerror!void {
    var state: ResumeOrReturnReturnNowState = .start;
    try runStateMachine(&state, writer);
}

/// Execute the reference machine for the optional-resumption single-resume witness.
pub fn runResumeOrReturnResume(writer: anytype) anyerror!void {
    var state: ResumeOrReturnResumeState = .start;
    try runStateMachine(&state, writer);
}
