const witnesses = @import("witnesses_src");

/// Stable bridge case id for the static re-delimitation witness.
pub const bridge_case_id = "static_redelim";

/// Run the canonical static re-delimitation witness through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try witnesses.runWitness(writer, bridge_case_id);
}
