const shift = @import("shift");
const std = @import("std");

const NoError = error{};

/// Write the optional-resumption transcript through the lexical front door.
pub fn run(writer: anytype) anyerror!void {
    const transcript = struct {
        threadlocal var items = [_][]const u8{ "", "", "", "", "", "" };
        threadlocal var len: usize = 0;

        fn note(message: []const u8) void {
            items[len] = message;
            len += 1;
        }
    };

    const return_now_policy = struct {
        /// Choose the return-now branch for the lexical resume-or-return example.
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
            transcript.note("handler-return-now");
            return shift.effect.choice.Decision(i32, []const u8).returnNow("result=early");
        }

        /// Preserve the early answer unchanged.
        pub fn afterResume(answer: []const u8) []const u8 {
            return answer;
        }
    };

    const resume_policy = struct {
        /// Choose the resume branch for the lexical resume-or-return example.
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
            transcript.note("handler-decide-resume");
            return shift.effect.choice.Decision(i32, []const u8).resumeWith(41);
        }

        /// Finalize the resumed lexical answer.
        pub fn afterResume(answer: []const u8) []const u8 {
            transcript.note("handler-after-resume");
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    try writer.writeAll("branch=return_now\n");
    transcript.len = 0;
    const early = try shift.with(&runtime, .{
        .optional = shift.effect.optional.use(i32, return_now_policy),
    }, struct {
        /// Trigger the lexical choice point and prove the return-now branch skips the continuation.
        pub fn body(eff: anytype) ![]const u8 {
            return try eff.optional.request(struct {
                /// This continuation must never run in the return-now branch.
                pub fn apply(_: i32, _: anytype) ![]const u8 {
                    unreachable;
                }
            });
        }
    });
    for (transcript.items[0..transcript.len]) |item| {
        try writer.print("{s}\n", .{item});
    }
    try writer.print("final={s}\n", .{early.value});

    try writer.writeAll("branch=resume_with\n");
    transcript.len = 0;
    const resumed = try shift.with(&runtime, .{
        .optional = shift.effect.optional.use(i32, resume_policy),
    }, struct {
        /// Trigger the lexical choice point and complete the resumed continuation.
        pub fn body(eff: anytype) ![]const u8 {
            return try eff.optional.request(struct {
                /// Resume the lexical continuation with the canonical final answer.
                pub fn apply(value: i32, _: anytype) ![]const u8 {
                    if (value != 41) unreachable;
                    transcript.note("body-after-shift");
                    return "answer=42";
                }
            });
        }
    });
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
