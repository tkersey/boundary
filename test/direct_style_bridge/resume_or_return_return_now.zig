const parity_scenarios = @import("parity_scenarios");

/// Stable internal proof case id; the legacy `bridge_case_id` name stays for the private seam.
pub const bridge_case_id = "resume_or_return_return_now";
/// Canonical path for this internal proof fixture wrapper.
pub const source_path = "test/direct_style_bridge/resume_or_return_return_now.zig";
/// Embedded fixture source consumed by fail-closed internal proof admission.
pub const source = @embedFile("resume_or_return_return_now.zig");

/// Replay the canonical return-now optional witness through the internal proof fixture seam.
pub fn run(writer: anytype) anyerror!void {
    try writer.writeAll(parity_scenarios.findWitness(bridge_case_id).?.expected_transcript);
}
