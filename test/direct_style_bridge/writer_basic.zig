const example = @import("example_writer_basic");

/// Stable internal proof case id; the legacy `bridge_case_id` name stays for the private seam.
pub const bridge_case_id = "writer_basic";
/// Canonical path for this internal proof fixture wrapper.
pub const source_path = "test/direct_style_bridge/writer_basic.zig";
/// Embedded fixture source consumed by fail-closed internal proof admission.
pub const source = @embedFile("writer_basic.zig");

/// Replay the canonical writer example through the internal proof fixture seam.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
