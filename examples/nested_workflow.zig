const ability = @import("ability");
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
    pub fn resumeOrReturn() ability.effect.choice.Decision([]const u8, []const u8) {
        transcript.note("workflow=queued");
        transcript.note("audit=entered");
        transcript.note("audit=after");
        transcript.note("approval=publish");
        return ability.effect.choice.Decision([]const u8, []const u8).returnNow("completed");
    }

    /// Preserve the workflow answer unchanged.
    pub fn afterResume(answer: []const u8) []const u8 {
        return answer;
    }
};

fn nestedWorkflowBody(eff: anytype) anyerror![]const u8 {
    return try eff.optional.request(struct {
        /// This continuation must never run in the approval branch.
        pub fn apply(_: []const u8, _: anytype) ![]const u8 {
            return "unused";
        }
    });
}

/// Write the nested workflow transcript through the lexical front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = ability.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.len = 0;

    const result = try ability.with(&runtime, .{
        .optional = ability.effect.optional.use([]const u8, approval_policy),
    }, struct {
        /// Run the nested workflow example body through the lexical front door.
        pub fn body(eff: anytype) @TypeOf(nestedWorkflowBody(eff)) {
            return nestedWorkflowBody(eff);
        }
    });
    transcript.note("workflow=done");
    for (transcript.items[0..transcript.len]) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("result={s}\n", .{result.value});
}

/// Run the nested workflow example.
pub fn main(init: std.process.Init) anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
