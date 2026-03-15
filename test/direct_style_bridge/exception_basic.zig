const example = @import("example_exception_basic");

/// Stable bridge case id for the exception example.
pub const bridge_case_id = "exception_basic";

/// Run the canonical exception example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
