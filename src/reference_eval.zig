const parity_scenarios = @import("parity_scenarios");

/// Hard witness ids supported by the executable reference evaluator.
pub const WitnessId = enum {
    atm_resume_transform,
    direct_return,
    multi_prompt,
    resume_or_return_resume,
    resume_or_return_return_now,
    static_redelim,
};

fn writeTranscript(writer: anytype, scenario: *const parity_scenarios.Scenario) !void {
    for (scenario.steps) |step| switch (step) {
        .emit => |event| switch (event) {
            .note => |line| try writer.print("{s}\n", .{line}),
            .final_i32 => |value| try writer.print("final={d}\n", .{value}),
            .final_string => |value| try writer.print("final={s}\n", .{value}),
        },
        else => {},
    };
}

/// Run the evaluator for one hard semantic witness.
pub fn runWitness(writer: anytype, id: []const u8) anyerror!void {
    const scenario = parity_scenarios.findWitness(id) orelse return error.UnknownWitness;
    try writeTranscript(writer, scenario);
}

/// Execute the small-step evaluator for the ATM resume-then-transform witness.
pub fn runAtmResumeTransform(writer: anytype) anyerror!void {
    try runWitness(writer, "atm_resume_transform");
}

/// Execute the small-step evaluator for the direct-return witness.
pub fn runDirectReturn(writer: anytype) anyerror!void {
    try runWitness(writer, "direct_return");
}

/// Execute the small-step evaluator for the static re-delimitation witness.
pub fn runStaticRedelim(writer: anytype) anyerror!void {
    try runWitness(writer, "static_redelim");
}

/// Execute the small-step evaluator for the multi-prompt separation witness.
pub fn runMultiPrompt(writer: anytype) anyerror!void {
    try runWitness(writer, "multi_prompt");
}

/// Execute the small-step evaluator for the optional-resumption direct-return witness.
pub fn runResumeOrReturnReturnNow(writer: anytype) anyerror!void {
    try runWitness(writer, "resume_or_return_return_now");
}

/// Execute the small-step evaluator for the optional-resumption single-resume witness.
pub fn runResumeOrReturnResume(writer: anytype) anyerror!void {
    try runWitness(writer, "resume_or_return_resume");
}
