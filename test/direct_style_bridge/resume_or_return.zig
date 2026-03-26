const example = @import("example_resume_or_return");

/// Stable bridge case id for the combined optional example.
pub const bridge_case_id = "resume_or_return";
/// Canonical path for this bridge fixture wrapper.
pub const source_path = "test/direct_style_bridge/resume_or_return.zig";
/// Embedded source text consumed by fail-closed bridge fixture admission.
pub const source = @embedFile("resume_or_return.zig");

/// Run the canonical optional-resumption example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
