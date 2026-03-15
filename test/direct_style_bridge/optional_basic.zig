const example = @import("example_optional_basic");

/// Stable bridge case id for the optional effect example.
pub const bridge_case_id = "optional_basic";

/// Run the canonical optional effect example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
