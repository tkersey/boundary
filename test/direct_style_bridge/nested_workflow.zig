const example = @import("example_nested_workflow");

/// Stable bridge case id for the nested workflow example.
pub const bridge_case_id = "nested_workflow";

/// Run the canonical nested workflow example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
