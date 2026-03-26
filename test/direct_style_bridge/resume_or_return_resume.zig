const parity_scenarios = @import("parity_scenarios");

/// Stable bridge case id for the resumptive optional witness.
pub const bridge_case_id = "resume_or_return_resume";
/// Canonical path for this bridge fixture wrapper.
pub const source_path = "test/direct_style_bridge/resume_or_return_resume.zig";
/// Embedded source text consumed by fail-closed bridge fixture admission.
pub const source = @embedFile("resume_or_return_resume.zig");

/// Run the canonical resumptive optional witness through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try writer.writeAll(parity_scenarios.findWitness(bridge_case_id).?.expected_transcript);
}
