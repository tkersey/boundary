const example = @import("example_algebraic_abortive_validation");

/// Stable bridge case id for the algebraic abortive validation example.
pub const bridge_case_id = "algebraic_abortive_validation";

/// Run the canonical algebraic abortive validation example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
