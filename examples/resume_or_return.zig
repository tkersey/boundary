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

const return_now_policy = struct {
    /// Choose the return-now branch for the front-door resume-or-return example.
    pub fn resumeOrReturn() ability.effect.choice.Decision(i32, []const u8) {
        transcript.note("handler-return-now");
        return ability.effect.choice.Decision(i32, []const u8).returnNow("result=early");
    }

    /// Preserve the early answer unchanged.
    pub fn afterResume(answer: []const u8) []const u8 {
        return answer;
    }
};

const resume_policy = struct {
    /// Choose the resume branch for the front-door resume-or-return example.
    pub fn resumeOrReturn() ability.effect.choice.Decision(i32, []const u8) {
        transcript.note("handler-decide-resume");
        return ability.effect.choice.Decision(i32, []const u8).resumeWith(41);
    }

    /// Finalize the resumed front-door answer.
    pub fn afterResume(answer: []const u8) []const u8 {
        transcript.note("body-after-shift");
        transcript.note("handler-after-resume");
        return answer;
    }
};

fn resumeOrReturnEarlyBody(eff: anytype) anyerror![]const u8 {
    return try eff.optional.request(struct {
        /// Apply this continuation hook.
        pub fn apply(_: i32, _: anytype) anyerror![]const u8 {
            return "unused";
        }
    });
}

fn resumeOrReturnResumedBody(eff: anytype) anyerror![]const u8 {
    return try eff.optional.request(struct {
        /// Apply this continuation hook.
        pub fn apply(_: i32, _: anytype) anyerror![]const u8 {
            return "answer=42";
        }
    });
}

fn runReturnNow(runtime: *ability.Runtime) ![]const u8 {
    const early = try ability.with(runtime, .{
        .optional = ability.effect.optional.use(i32, return_now_policy),
    }, struct {
        /// Run the return-now resume-or-return example body.
        pub fn body(eff: anytype) @TypeOf(resumeOrReturnEarlyBody(eff)) {
            return resumeOrReturnEarlyBody(eff);
        }
    });
    return early.value;
}

fn runResume(runtime: *ability.Runtime) ![]const u8 {
    const resumed = try ability.with(runtime, .{
        .optional = ability.effect.optional.use(i32, resume_policy),
    }, struct {
        /// Run the resumed resume-or-return example body.
        pub fn body(eff: anytype) @TypeOf(resumeOrReturnResumedBody(eff)) {
            return resumeOrReturnResumedBody(eff);
        }
    });
    return resumed.value;
}

/// Write the optional-resumption transcript through the lexical front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = ability.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    try writer.writeAll("branch=return_now\n");
    transcript.len = 0;
    const early = try runReturnNow(&runtime);
    for (transcript.items[0..transcript.len]) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("final={s}\n", .{early});

    try writer.writeAll("branch=resume_with\n");
    transcript.len = 0;
    const resumed = try runResume(&runtime);
    for (transcript.items[0..transcript.len]) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("final={s}\n", .{resumed});
}

/// Run the optional-resumption example.
pub fn main(init: std.process.Init) anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
