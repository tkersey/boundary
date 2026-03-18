const parity_scenarios = @import("parity_scenarios");

/// Stable bridge case id for the return-now optional witness.
pub const bridge_case_id = "resume_or_return_return_now";

/// Run the canonical return-now optional witness through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try writer.writeAll(parity_scenarios.findWitness(bridge_case_id).?.expected_transcript);
}
