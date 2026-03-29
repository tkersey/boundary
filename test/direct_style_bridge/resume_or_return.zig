const example = @import("example_resume_or_return");

/// Stable internal proof case id; the legacy `bridge_case_id` name stays for the private seam.
pub const bridge_case_id = "resume_or_return";
/// Canonical path for this internal proof fixture wrapper.
pub const source_path = "test/direct_style_bridge/resume_or_return.zig";
/// Embedded fixture source consumed by fail-closed internal proof admission.
pub const source = @embedFile("resume_or_return.zig");

/// Replay the canonical optional-resumption example through the internal proof fixture seam.
pub fn run(writer: anytype) anyerror!void {
    try example.run(writer);
}
