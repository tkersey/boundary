const shift = @import("shift");
const std = @import("std");

const NoError = error{};

fn runReturnNow(writer: anytype) anyerror!void {
    const DemoPrompt = shift.Prompt(.resume_or_return, []const u8, []const u8, NoError);
    const Decision = shift.ResumeOrReturn(void, []const u8);

    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;
        var transcript = [_][]const u8{ "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        const handle = struct {
            /// Choose the immediate-return branch for this transcript.
            pub fn resumeOrReturn() Decision {
                note("handler-return-now");
                return Decision.returnNow("result=early");
            }

            /// Preserve the resumed answer if this branch ever resumes.
            pub fn afterResume(value: []const u8) []const u8 {
                return value;
            }
        };

        fn body() shift.ResetError(NoError)![]const u8 {
            _ = try shift.shift(void, prompt_ptr.?, handle);
            return "result=late";
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var prompt = DemoPrompt.init();
    demo.prompt_ptr = &prompt;
    demo.transcript_len = 0;

    const answer = try shift.reset(&runtime, &prompt, demo.body);
    for (demo.transcript[0..demo.transcript_len]) |line| try writer.print("{s}\n", .{line});
    try writer.print("final={s}\n", .{answer});
}

fn runResumeWith(writer: anytype) anyerror!void {
    const DemoPrompt = shift.Prompt(.resume_or_return, i32, []const u8, NoError);
    const Decision = shift.ResumeOrReturn(i32, []const u8);

    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;
        var transcript = [_][]const u8{ "", "", "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        const handle = struct {
            /// Choose the resumptive branch for this transcript.
            pub fn resumeOrReturn() Decision {
                note("handler-decide-resume");
                return Decision.resumeWith(41);
            }

            /// Convert the resumed answer into the enclosing output.
            pub fn afterResume(value: i32) []const u8 {
                _ = value;
                note("handler-after-resume");
                return "answer=42";
            }
        };

        fn body() shift.ResetError(NoError)!i32 {
            const current = try shift.shift(i32, prompt_ptr.?, handle);
            note("body-after-shift");
            return current + 1;
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var prompt = DemoPrompt.init();
    demo.prompt_ptr = &prompt;
    demo.transcript_len = 0;

    const answer = try shift.reset(&runtime, &prompt, demo.body);
    for (demo.transcript[0..demo.transcript_len]) |line| try writer.print("{s}\n", .{line});
    try writer.print("final={s}\n", .{answer});
}

/// Write both optional-resumption branches in one example transcript.
pub fn run(writer: anytype) anyerror!void {
    try writer.writeAll("branch=return_now\n");
    try runReturnNow(writer);
    try writer.writeAll("branch=resume_with\n");
    try runResumeWith(writer);
}

/// Run the optional-resumption example with both supported branches in one execution.
pub fn main() anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
