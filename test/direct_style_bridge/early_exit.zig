const example = @import("example_early_exit");

/// Stable internal proof case id; the legacy `bridge_case_id` name stays for the private seam.
pub const bridge_case_id = "early_exit";
/// Canonical path for this internal proof fixture wrapper.
pub const source_path = "test/direct_style_bridge/early_exit.zig";
/// Embedded fixture source consumed by fail-closed internal proof admission.
pub const source = @embedFile("early_exit.zig");

/// Replay the canonical early-exit example through the internal proof fixture seam.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
