const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const Approval = shift.effect.Define(.{
    .state_type = struct {},
    .error_set_type = NoError,
    .ops = .{
        shift.effect.ops.Choice("publish", void, []const u8),
    },
});

/// Write the nested workflow transcript through the lexical front door.
pub fn run(writer: anytype) anyerror!void {
    const transcript = struct {
        threadlocal var items = [_][]const u8{ "", "", "", "", "", "" };
        threadlocal var len: usize = 0;

        fn note(message: []const u8) void {
            items[len] = message;
            len += 1;
        }
    };

    const approval_handler = struct {
        /// Approve publication through the lexical generated choice surface.
        pub fn publish(_: *@This()) shift.effect.choice.Decision([]const u8, []const u8) {
            transcript.note("approval=publish");
            return shift.effect.choice.Decision([]const u8, []const u8).returnNow("completed");
        }

        /// Preserve the resumed workflow answer unchanged.
        pub fn afterPublish(_: *@This(), answer: []const u8) []const u8 {
            return answer;
        }
    };

    transcript.len = 0;

    const result = try shift.with(.{
        .approval = Approval.use(.{ .handler = approval_handler{} }),
    }, struct {
        /// Queue the workflow, request approval, and finish on the resumed branch.
        pub fn body(eff: anytype) shift.ResetError(NoError)![]const u8 {
            transcript.note("workflow=queued");
            transcript.note("audit=entered");
            transcript.note("audit=after");
            const approved = try eff.approval.publish.perform(struct {
                /// This continuation must never run in the return-now approval branch.
                pub fn apply(_: []const u8, _: anytype) shift.ResetError(NoError)![]const u8 {
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
