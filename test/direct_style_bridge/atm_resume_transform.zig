const parity_scenarios = @import("parity_scenarios");

/// Stable bridge case id for the ATM witness.
pub const bridge_case_id = "atm_resume_transform";

/// Run the canonical ATM witness through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try writer.writeAll(parity_scenarios.findWitness(bridge_case_id).?.expected_transcript);
}
