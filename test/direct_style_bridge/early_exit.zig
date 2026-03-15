const example = @import("example_early_exit");

/// Stable bridge case id for the early-exit example.
pub const bridge_case_id = "early_exit";

/// Run the canonical early-exit example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
