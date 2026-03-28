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

const return_now_policy = struct {
    /// Choose the return-now branch for the front-door resume-or-return example.
    pub fn resumeOrReturn() shift.Decision(i32, []const u8) {
        transcript.note("handler-return-now");
        return shift.Decision(i32, []const u8).returnNow("result=early");
    }

    /// Preserve the early answer unchanged.
    pub fn afterResume(answer: []const u8) []const u8 {
        return answer;
    }
};

const resume_policy = struct {
    /// Choose the resume branch for the front-door resume-or-return example.
    pub fn resumeOrReturn() shift.Decision(i32, []const u8) {
        transcript.note("handler-decide-resume");
        return shift.Decision(i32, []const u8).resumeWith(41);
    }

    /// Finalize the resumed front-door answer.
    pub fn afterResume(answer: []const u8) []const u8 {
        transcript.note("handler-after-resume");
        return answer;
    }
};

const OptionalRow = shift.effects.optional(i32);

const return_now_workflow = struct {
    pub const Uses = shift.Uses(OptionalRow);

    /// Trigger the front-door choice point and prove the return-now branch skips the continuation.
    pub fn body(eff: anytype) ![]const u8 {
        return try eff.optional.request(struct {
            /// Apply this public continuation hook.
            pub fn apply(_: i32, _: anytype) ![]const u8 {
                unreachable;
            }
        });
    }
};

const resume_workflow = struct {
    pub const Uses = shift.Uses(OptionalRow);

    /// Trigger the front-door choice point and complete the resumed continuation.
    pub fn body(eff: anytype) ![]const u8 {
        return try eff.optional.request(struct {
            /// Apply this public continuation hook.
            pub fn apply(value: i32, _: anytype) ![]const u8 {
                if (value != 41) unreachable;
                transcript.note("body-after-shift");
                return "answer=42";
            }
        });
    }
};

/// Write the optional-resumption transcript through the root front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    try writer.writeAll("branch=return_now\n");
    transcript.len = 0;
    const return_now_closed = shift.bind(return_now_workflow, .{
        .optional = shift.handlers.optional(i32, return_now_policy),
    });
    const early = try shift.run(&runtime, return_now_closed);
    for (transcript.items[0..transcript.len]) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("final={s}\n", .{early.value});

    try writer.writeAll("branch=resume_with\n");
    transcript.len = 0;
    const resume_closed = shift.bind(resume_workflow, .{
        .optional = shift.handlers.optional(i32, resume_policy),
    });
    const resumed = try shift.run(&runtime, resume_closed);
    for (transcript.items[0..transcript.len]) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("final={s}\n", .{resumed.value});
}

/// Run the optional-resumption example.
pub fn main() anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
