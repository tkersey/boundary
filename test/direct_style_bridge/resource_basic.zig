const example = @import("example_resource_basic");

/// Stable internal proof case id; the legacy `bridge_case_id` name stays for the private seam.
pub const bridge_case_id = "resource_basic";
/// Canonical path for this internal proof fixture wrapper.
pub const source_path = "test/direct_style_bridge/resource_basic.zig";
/// Embedded fixture source consumed by fail-closed internal proof admission.
pub const source = @embedFile("resource_basic.zig");

/// Replay the canonical resource example through the internal proof fixture seam.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
