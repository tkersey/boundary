const parity_scenarios = @import("parity_scenarios");

/// Stable bridge case id for the direct-return witness.
pub const bridge_case_id = "direct_return";

/// Run the canonical direct-return witness through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try writer.writeAll(parity_scenarios.findWitness(bridge_case_id).?.expected_transcript);
}
