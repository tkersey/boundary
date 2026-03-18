const parity_scenarios = @import("parity_scenarios");

/// Stable bridge case id for the static re-delimitation witness.
pub const bridge_case_id = "static_redelim";

/// Run the canonical static re-delimitation witness through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try writer.writeAll(parity_scenarios.findWitness(bridge_case_id).?.expected_transcript);
}
