// zlinter-disable require_doc_comment - lexical witness helpers are test-only support surfaces.
const common = @import("common.zig");
const lexical_runtime = common.lexical_runtime;
const std = common.std;

fn resumeBody(eff: anytype) anyerror![]const u8 {
    return try eff.optional.request(struct {
        pub fn apply(_: i32, _: anytype) anyerror![]const u8 {
            return "answer=42";
        }
    });
}

fn runResumeOrReturnResume(writer: anytype) anyerror!void {
    const transcript = struct {
        threadlocal var items = [_][]const u8{ "", "", "", "" };
        threadlocal var len: usize = 0;

        fn note(message: []const u8) void {
            items[len] = message;
            len += 1;
        }
    };
    const policy = struct {
        pub fn resumeOrReturn() lexical_runtime.effect.choice.Decision(i32, []const u8) {
            transcript.note("handler-decide-resume");
            return lexical_runtime.effect.choice.Decision(i32, []const u8).resumeWith(41);
        }

        pub fn afterResume(answer: []const u8) []const u8 {
            transcript.note("body-after-shift");
            transcript.note("handler-after-resume");
            return answer;
        }
    };

    var runtime = lexical_runtime.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.len = 0;
    const result = try lexical_runtime.with(&runtime, .{
        .optional = lexical_runtime.effect.optional.use(i32, policy),
    }, struct {
        pub fn body(eff: anytype) anyerror![]const u8 {
            return resumeBody(eff);
        }
    });
    try common.printTranscript(writer, transcript.items[0..transcript.len]);
    try writer.print("final={s}\n", .{result.value});
}

test "lexical witness resume_or_return_resume transcripts stay aligned" {
    try common.expectLexicalWitness("resume_or_return_resume", runResumeOrReturnResume);
}
