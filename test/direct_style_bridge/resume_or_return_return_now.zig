const witnesses = @import("witnesses_src");

/// Stable bridge case id for the return-now optional witness.
pub const bridge_case_id = "resume_or_return_return_now";

/// Run the canonical return-now optional witness through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try witnesses.runWitness(writer, bridge_case_id);
}
