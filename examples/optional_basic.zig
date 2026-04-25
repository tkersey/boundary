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
    /// Choose the direct-return branch for the front-door optional example.
    pub fn resumeOrReturn() ability.effect.choice.Decision(i32, []const u8) {
        transcript.note("policy-return-now");
        return ability.effect.choice.Decision(i32, []const u8).returnNow("result=early");
    }

    /// Preserve the early answer unchanged in the return-now branch.
    pub fn afterResume(answer: []const u8) []const u8 {
        return answer;
    }
};

const resume_policy = struct {
    /// Resume the front-door optional request with the canonical value.
    pub fn resumeOrReturn() ability.effect.choice.Decision(i32, []const u8) {
        transcript.note("policy-resume");
        return ability.effect.choice.Decision(i32, []const u8).resumeWith(41);
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

fn runReturnNow(runtime: *ability.Runtime) ![]const u8 {
    const early_result = try ability.with(runtime, .{
        .optional = ability.effect.optional.use(i32, return_now_policy),
    }, struct {
        /// Run the return-now optional example body.
        pub fn body(eff: anytype) @TypeOf(optionalReturnNowBody(eff)) {
            return optionalReturnNowBody(eff);
        }
    });
    return early_result.value;
}

fn runResume(runtime: *ability.Runtime) ![]const u8 {
    const resumed = try ability.with(runtime, .{
        .optional = ability.effect.optional.use(i32, resume_policy),
    }, struct {
        /// Run the resumed optional example body.
        pub fn body(eff: anytype) @TypeOf(optionalResumeBody(eff)) {
            return optionalResumeBody(eff);
        }
    });
    return resumed.value;
}

/// Write the optional-family transcript through the lexical front door.
pub fn run(writer: anytype) anyerror!void {
    var runtime = ability.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    try writer.writeAll("branch=return_now\n");
    transcript.len = 0;
    const early_result = try runReturnNow(&runtime);
    for (transcript.items[0..transcript.len]) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("final={s}\n", .{early_result});

    try writer.writeAll("branch=resume_with\n");
    transcript.len = 0;
    const resumed = try runResume(&runtime);
    for (transcript.items[0..transcript.len]) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("final={s}\n", .{resumed});
}

/// Run the optional family example.
pub fn main(init: std.process.Init) anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
