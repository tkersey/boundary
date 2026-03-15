const example = @import("example_reader_basic");

/// Stable bridge case id for the reader example.
pub const bridge_case_id = "reader_basic";

/// Run the canonical reader example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
