const example = @import("example_resume_or_return");

/// Stable bridge case id for the combined optional example.
pub const bridge_case_id = "resume_or_return";

/// Run the canonical optional-resumption example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
