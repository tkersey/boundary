const witnesses = @import("witnesses_src");

/// Stable bridge case id for the prompt-separation witness.
pub const bridge_case_id = "multi_prompt";

/// Run the canonical prompt-separation witness through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try witnesses.runWitness(writer, bridge_case_id);
}
