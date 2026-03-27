const example = @import("example_resource_basic");

/// Stable bridge case id for the resource example.
pub const bridge_case_id = "resource_basic";
/// Canonical path for this bridge fixture wrapper.
pub const source_path = "test/direct_style_bridge/resource_basic.zig";
/// Embedded source text consumed by fail-closed bridge fixture admission.
pub const source = @embedFile("resource_basic.zig");

/// Run the canonical resource example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
