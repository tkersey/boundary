const parity_kernel = @import("parity_kernel");
const parity_scenarios = @import("parity_scenarios");

/// Hard witness ids supported by the executable reference machine.
pub const WitnessId = enum {
    atm_resume_transform,
    direct_return,
    multi_prompt,
    resume_or_return_resume,
    resume_or_return_return_now,
    static_redelim,
};

/// Run the reference machine for one hard semantic witness.
pub fn runWitness(writer: anytype, id: []const u8) anyerror!void {
    const scenario = parity_scenarios.findWitness(id) orelse return error.UnknownWitness;
    const state = parity_kernel.runScenario(scenario.scenario_id);
    try parity_kernel.writeTranscript(writer, &state);
}

/// Execute the reference machine for the ATM resume-then-transform witness.
pub fn runAtmResumeTransform(writer: anytype) anyerror!void {
    try runWitness(writer, "atm_resume_transform");
}

/// Execute the reference machine for the direct-return witness.
pub fn runDirectReturn(writer: anytype) anyerror!void {
    try runWitness(writer, "direct_return");
}

/// Execute the reference machine for the static re-delimitation witness.
pub fn runStaticRedelim(writer: anytype) anyerror!void {
    try runWitness(writer, "static_redelim");
}

/// Execute the reference machine for the prompt-value separation witness.
pub fn runMultiPrompt(writer: anytype) anyerror!void {
    try runWitness(writer, "multi_prompt");
}

/// Execute the reference machine for the optional-resumption direct-return witness.
pub fn runResumeOrReturnReturnNow(writer: anytype) anyerror!void {
    try runWitness(writer, "resume_or_return_return_now");
}

/// Execute the reference machine for the optional-resumption single-resume witness.
pub fn runResumeOrReturnResume(writer: anytype) anyerror!void {
    try runWitness(writer, "resume_or_return_resume");
}
