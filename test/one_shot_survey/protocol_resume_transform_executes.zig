const lowered_runtime = @import("private_lowered_runtime");
const std = @import("std");

/// Execute the runtime smoke-check fixture for the resume-then-transform protocol.
pub fn main() anyerror!void {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const execution = try lowered_runtime.runCaseId(&writer, "atm_resume_transform");
    try std.testing.expectEqualStrings("bridge.atm_resume_transform", execution.label);
    try std.testing.expectEqualStrings("atm_resume_transform", execution.scenario.case_id);
    try std.testing.expectEqualStrings(
        "handler-enter\nbody-after-shift\nhandler-after-resume\nfinal=answer=42\n",
        writer.buffered(),
    );
}
