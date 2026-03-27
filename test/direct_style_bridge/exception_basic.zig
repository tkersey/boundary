const example = @import("example_exception_basic");

/// Stable bridge case id for the exception example.
pub const bridge_case_id = "exception_basic";
/// Canonical path for this bridge fixture wrapper.
pub const source_path = "test/direct_style_bridge/exception_basic.zig";
/// Embedded source text consumed by fail-closed bridge fixture admission.
pub const source = @embedFile("exception_basic.zig");

/// Run the canonical exception example through the current public surface.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
