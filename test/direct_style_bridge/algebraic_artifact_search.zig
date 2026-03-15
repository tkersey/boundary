const example = @import("example_algebraic_artifact_search");

/// Stable bridge case id for the algebraic artifact search example.
pub const bridge_case_id = "algebraic_artifact_search";

/// Run the canonical algebraic artifact search example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
