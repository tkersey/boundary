// zlinter-disable require_doc_comment - these fixture witnesses expose public nested policies and continuations only because the lexical API binds comptime-visible structs.
const shift = @import("shift");
const std = @import("std");

fn ExecResult(comptime T: type) type {
    return (shift.RuntimeError || error{ OutOfMemory, BodyOops, ContinueOops, HandlerOops, AfterOops })!T;
}

fn expectFixtureTranscript(comptime fixture_path: []const u8, writer_fn: anytype) anyerror!void {
    var buffer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buffer.deinit();
    try writer_fn(&buffer.writer);
    try std.testing.expectEqualStrings(@embedFile(fixture_path), buffer.written());
}

test "shift.with matches the optional fixture transcript through lexical handles" {
    try expectFixtureTranscript("example_proof/fixtures/optional_basic.txt", struct {
        fn run(writer: anytype) anyerror!void {
            const transcript = struct {
                threadlocal var active_writer: ?@TypeOf(writer) = null;

                fn note(message: []const u8) void {
                    active_writer.?.writeAll(message) catch unreachable;
                }
            };

            const return_now_policy = struct {
                pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
                    transcript.note("policy-return-now\n");
                    return shift.effect.choice.Decision(i32, []const u8).returnNow("result=early");
                }

                pub fn afterResume(answer: []const u8) []const u8 {
                    return answer;
                }
            };

            const resume_policy = struct {
                pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
                    transcript.note("policy-resume\n");
                    return shift.effect.choice.Decision(i32, []const u8).resumeWith(41);
                }

                pub fn afterResume(answer: []const u8) []const u8 {
                    transcript.note("policy-after-resume\n");
                    return answer;
                }
            };

            var runtime = shift.Runtime.init(std.testing.allocator);
            defer runtime.deinit();

            const previous_writer = transcript.active_writer;
            transcript.active_writer = writer;
            defer transcript.active_writer = previous_writer;

            try writer.writeAll("branch=return_now\n");
            const early = try shift.with(&runtime, .{
                .optional = shift.effect.optional.use(i32, return_now_policy),
            }, struct {
                pub fn body(eff: anytype) ExecResult([]const u8) {
                    return try eff.optional.request(struct {
                        pub fn apply(_: i32, _: anytype) ExecResult([]const u8) {
                            unreachable;
                        }
                    });
                }
            });
            try writer.print("final={s}\n", .{early.value});

            try writer.writeAll("branch=resume_with\n");
            const resumed = try shift.with(&runtime, .{
                .optional = shift.effect.optional.use(i32, resume_policy),
            }, struct {
                pub fn body(eff: anytype) ExecResult([]const u8) {
                    return try eff.optional.request(struct {
                        pub fn apply(value: i32, _: anytype) ExecResult([]const u8) {
                            if (value != 41) unreachable;
                            transcript.note("body-after-request\n");
                            return "answer=42";
                        }
                    });
                }
            });
            try writer.print("final={s}\n", .{resumed.value});
        }
    }.run);
}
