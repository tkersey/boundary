const witnesses = @import("witnesses_src");

/// Stable bridge case id for the ATM witness.
pub const bridge_case_id = "atm_resume_transform";

/// Run the canonical ATM witness through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try witnesses.runWitness(writer, bridge_case_id);
}
