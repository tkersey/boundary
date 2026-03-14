const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const OptionalInstance = shift.effect.optional.Instance(i32, NoError);

fn runReturnNow(writer: anytype) anyerror!void {
    const policy = struct {
        var transcript = [_][]const u8{ "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        /// Choose the direct-return branch for this optional family example.
        pub fn resumeOrReturn() shift.ResumeOrReturn(i32, []const u8) {
            note("policy-return-now");
            return shift.ResumeOrReturn(i32, []const u8).returnNow("result=early");
        }

        /// Preserve the resumed answer if this branch ever resumes.
        pub fn afterResume(value: i32) []const u8 {
            _ = value;
            return "result=late";
        }
    };
    const demo = struct {
        /// Exercise the direct-return branch through the public optional helper.
        pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)!i32 {
            _ = try shift.effect.optional.request(Cap, ctx);
            return 0;
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var instance = OptionalInstance.init();
    policy.transcript_len = 0;

    const answer = try shift.effect.optional.handle([]const u8, &runtime, &instance, policy, demo);
    for (policy.transcript[0..policy.transcript_len]) |line| try writer.print("{s}\n", .{line});
    try writer.print("final={s}\n", .{answer});
}

fn runResumeWith(writer: anytype) anyerror!void {
    const policy = struct {
        var transcript = [_][]const u8{ "", "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        /// Choose the resumptive branch for this optional family example.
        pub fn resumeOrReturn() shift.ResumeOrReturn(i32, []const u8) {
            note("policy-resume");
            return shift.ResumeOrReturn(i32, []const u8).resumeWith(41);
        }

        /// Convert the resumed answer into the enclosing output.
        pub fn afterResume(value: i32) []const u8 {
            _ = value;
            note("policy-after-resume");
            return "answer=42";
        }
    };
    const demo = struct {
        fn note(message: []const u8) void {
            policy.note(message);
        }

        /// Resume once through the optional family request point.
        pub fn body(comptime Cap: type, ctx: anytype) shift.ResetError(NoError)!i32 {
            const current = try shift.effect.optional.request(Cap, ctx);
            note("body-after-request");
            return current + 1;
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var instance = OptionalInstance.init();
    policy.transcript_len = 0;

    const answer = try shift.effect.optional.handle([]const u8, &runtime, &instance, policy, demo);
    for (policy.transcript[0..policy.transcript_len]) |line| try writer.print("{s}\n", .{line});
    try writer.print("final={s}\n", .{answer});
}

/// Write both optional-family branches in one example transcript.
pub fn run(writer: anytype) anyerror!void {
    try writer.writeAll("branch=return_now\n");
    try runReturnNow(writer);
    try writer.writeAll("branch=resume_with\n");
    try runResumeWith(writer);
}

/// Run the optional family example using only the public effect surface.
pub fn main() anyerror!void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
