const parity_scenarios = @import("parity_scenarios");

/// Stable bridge case id for the resumptive optional witness.
pub const bridge_case_id = "resume_or_return_resume";

/// Run the canonical resumptive optional witness through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try writer.writeAll(parity_scenarios.findWitness(bridge_case_id).?.expected_transcript);
}
