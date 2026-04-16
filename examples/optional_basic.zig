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
    /// Choose the direct-return branch for the front-door optional example.
    pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
        transcript.note("policy-return-now");
        return shift.effect.choice.Decision(i32, []const u8).returnNow("result=early");
    }

    /// Preserve the early answer unchanged in the return-now branch.
    pub fn afterResume(answer: []const u8) []const u8 {
        return answer;
    }
};

const resume_policy = struct {
    /// Resume the front-door optional request with the canonical value.
    pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
        transcript.note("policy-resume");
        return shift.effect.choice.Decision(i32, []const u8).resumeWith(41);
    }

    /// Finalize the resumed front-door optional answer.
    pub fn afterResume(answer: []const u8) []const u8 {
        transcript.note("body-after-request");
        transcript.note("policy-after-resume");
        return answer;
    }
};

fn optionalReturnNowBody(eff: anytype) anyerror![]const u8 {
    return try eff.optional.request(struct {
        /// Apply this continuation hook.
        pub fn apply(_: i32, _: anytype) anyerror![]const u8 {
            return "unused";
        }
    });
}

fn optionalResumeBody(eff: anytype) anyerror![]const u8 {
    return try eff.optional.request(struct {
        /// Apply this continuation hook.
        pub fn apply(_: i32, _: anytype) anyerror![]const u8 {
            return "answer=42";
        }
    });
}

/// Write the optional-family transcript through the lexical front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    try writer.writeAll("branch=return_now\n");
    transcript.len = 0;
    const early_result = try shift.with(@src(), &runtime, .{
        .optional = shift.effect.optional.use(i32, return_now_policy),
    }, shift.NamedBody("examples/optional_basic.zig", "optionalReturnNowBody", anyerror![]const u8, optionalReturnNowBody));
    for (transcript.items[0..transcript.len]) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("final={s}\n", .{early_result.value});

    try writer.writeAll("branch=resume_with\n");
    transcript.len = 0;
    const resumed = try shift.with(@src(), &runtime, .{
        .optional = shift.effect.optional.use(i32, resume_policy),
    }, shift.NamedBody("examples/optional_basic.zig", "optionalResumeBody", anyerror![]const u8, optionalResumeBody));
    for (transcript.items[0..transcript.len]) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("final={s}\n", .{resumed.value});
}

/// Run the optional family example.
pub fn main() anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
