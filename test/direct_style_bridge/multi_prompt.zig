const parity_scenarios = @import("parity_scenarios");

/// Stable bridge case id for the prompt-separation witness.
pub const bridge_case_id = "multi_prompt";
/// Canonical path for this bridge fixture wrapper.
pub const source_path = "test/direct_style_bridge/multi_prompt.zig";
/// Embedded source text consumed by fail-closed bridge fixture admission.
pub const source = @embedFile("multi_prompt.zig");

/// Run the canonical prompt-separation witness through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try writer.writeAll(parity_scenarios.findWitness(bridge_case_id).?.expected_transcript);
}
