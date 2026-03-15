const example = @import("example_state_basic");

/// Stable bridge case id for the state example.
pub const bridge_case_id = "state_basic";

/// Run the canonical state example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
