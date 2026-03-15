const witnesses = @import("witnesses_src");

/// Stable bridge case id for the direct-return witness.
pub const bridge_case_id = "direct_return";

/// Run the canonical direct-return witness through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try witnesses.runWitness(writer, bridge_case_id);
}
