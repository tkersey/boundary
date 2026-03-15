const example = @import("example_resource_basic");

/// Stable bridge case id for the resource example.
pub const bridge_case_id = "resource_basic";

/// Run the canonical resource example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
