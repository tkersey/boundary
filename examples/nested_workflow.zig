const shift = @import("shift");
const std = @import("std");

const transcript = struct {
    threadlocal var items = [_][]const u8{ "", "", "", "", "", "" };
    threadlocal var len: usize = 0;

    fn note(message: []const u8) void {
        items[len] = message;
        len += 1;
    }
};

const approval_policy = struct {
    /// Approve publication through the program optional surface.
    pub fn resumeOrReturn() shift.effect.choice.Decision([]const u8, []const u8) {
        transcript.note("approval=publish");
        return shift.effect.choice.Decision([]const u8, []const u8).returnNow("completed");
    }

    /// Preserve the workflow answer unchanged.
    pub fn afterResume(answer: []const u8) []const u8 {
        return answer;
    }
};

/// Write the nested workflow transcript through the lexical front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.len = 0;

    const result = try shift.with(&runtime, .{
        .optional = shift.effect.optional.use([]const u8, approval_policy),
    }, struct {
        /// Queue the workflow, request approval, and finish on the return-now branch.
        pub fn body(eff: anytype) ![]const u8 {
            transcript.note("workflow=queued");
            transcript.note("audit=entered");
            transcript.note("audit=after");
            const approved = try eff.optional.request(struct {
                /// This continuation must never run in the approval branch.
                pub fn apply(_: []const u8, _: anytype) ![]const u8 {
                    unreachable;
                }
            });
            transcript.note("workflow=done");
            return approved;
        }
    });
    for (transcript.items[0..transcript.len]) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("result={s}\n", .{result.value});
}

/// Run the nested workflow example.
pub fn main() anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
