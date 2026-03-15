const example = @import("example_generator");

/// Stable bridge case id for the generator example.
pub const bridge_case_id = "generator";

/// Run the canonical generator example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
