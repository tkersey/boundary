const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const Picker = shift.effect.Define(.{
    .state_type = struct {},
    .error_set_type = NoError,
    .ops = .{
        shift.effect.ops.Choice("pick", i32, i32),
    },
});

/// Render the generated lexical choice-family example transcript.
pub fn run(writer: anytype) anyerror!void {
    const transcript = struct {
        threadlocal var items = [_][]const u8{ "", "", "", "", "", "", "", "" };
        threadlocal var len: usize = 0;

        fn note(message: []const u8) void {
            items[len] = message;
            len += 1;
        }
    };

    const return_now_handler = struct {
        /// Return now for the generated lexical choice example.
        pub fn pick(_: *@This(), _: i32) shift.ResetError(NoError)!shift.ResumeOrReturn(i32, []const u8) {
            transcript.note("policy-return-now");
            return shift.ResumeOrReturn(i32, []const u8).returnNow("result=early");
        }

        /// Preserve the early answer unchanged.
        pub fn afterPick(_: *@This(), answer: []const u8) []const u8 {
            return answer;
        }
    };

    const resume_handler = struct {
        /// Resume with the canonical generated choice value.
        pub fn pick(_: *@This(), payload: i32) shift.ResetError(NoError)!shift.ResumeOrReturn(i32, []const u8) {
            transcript.note("policy-resume");
            return shift.ResumeOrReturn(i32, []const u8).resumeWith(payload);
        }

        /// Finalize the resumed generated choice answer.
        pub fn afterPick(_: *@This(), answer: []const u8) shift.ResetError(NoError)![]const u8 {
            transcript.note("policy-after-resume");
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();

    try writer.writeAll("branch=return_now\n");
    transcript.len = 0;
    const early = try shift.with(&runtime, .{
        .picker = Picker.use(.{ .handler = return_now_handler{} }),
    }, struct {
        /// Trigger the generated lexical choice point and prove the continuation is skipped.
        pub fn body(eff: anytype) shift.ResetError(NoError)![]const u8 {
            return try eff.picker.pick.perform(41, struct {
                /// This generated continuation must never run in the return-now branch.
                pub fn apply(_: i32, _: anytype) shift.ResetError(NoError)![]const u8 {
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
        .picker = Picker.use(.{ .handler = resume_handler{} }),
    }, struct {
        /// Trigger the generated lexical choice point and complete the explicit continuation.
        pub fn body(eff: anytype) shift.ResetError(NoError)![]const u8 {
            return try eff.picker.pick.perform(41, struct {
                /// Resume the generated lexical choice continuation with the canonical final answer.
                pub fn apply(value: i32, _: anytype) shift.ResetError(NoError)![]const u8 {
                    if (value != 41) unreachable;
                    transcript.note("body-after-pick");
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

/// Run the generated lexical choice-family example on stdout.
pub fn main() anyerror!void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
