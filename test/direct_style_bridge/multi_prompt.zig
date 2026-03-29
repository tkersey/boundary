const parity_scenarios = @import("parity_scenarios");

/// Stable internal proof case id; the legacy `bridge_case_id` name stays for the private seam.
pub const bridge_case_id = "multi_prompt";
/// Canonical path for this internal proof fixture wrapper.
pub const source_path = "test/direct_style_bridge/multi_prompt.zig";
/// Embedded fixture source consumed by fail-closed internal proof admission.
pub const source = @embedFile("multi_prompt.zig");

/// Replay the canonical prompt-separation witness through the internal proof fixture seam.
pub fn run(writer: anytype) anyerror!void {
    try writer.writeAll(parity_scenarios.findWitness(bridge_case_id).?.expected_transcript);
}
