const example = @import("example_writer_basic");

/// Stable bridge case id for the writer example.
pub const bridge_case_id = "writer_basic";

/// Run the canonical writer example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
