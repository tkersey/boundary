// zlinter-disable require_doc_comment - lexical witness helpers are test-only support surfaces.
const common = @import("common.zig");
const lexical_runtime = common.lexical_runtime;
const std = common.std;
const ResumeWitness = common.ResumeWitness;

const transcript = struct {
    threadlocal var items = [_][]const u8{ "", "", "" };
    threadlocal var len: usize = 0;

    fn note(message: []const u8) void {
        items[len] = message;
        len += 1;
    }
};

const Handler = struct {
    state: void = {},

    pub fn step(_: *@This()) i32 {
        transcript.note("handler-enter");
        return 41;
    }

    pub fn afterStep(_: *@This(), answer: []const u8) []const u8 {
        transcript.note("body-after-shift");
        transcript.note("handler-after-resume");
        return answer;
    }
};

fn atmBody(eff: anytype) anyerror![]const u8 {
    _ = try eff.atm.step.perform();
    return "answer=42";
}

fn runAtmResumeTransform(writer: anytype) anyerror!void {
    var runtime = lexical_runtime.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.len = 0;
    const result = try lexical_runtime.with(&runtime, .{
        .atm = ResumeWitness.use(.{ .handler = Handler{} }),
    }, struct {
        pub fn body(eff: anytype) anyerror![]const u8 {
            return atmBody(eff);
        }
    });
    try common.printTranscript(writer, transcript.items[0..transcript.len]);
    try writer.print("final={s}\n", .{result.value});
}

test "lexical witness atm_resume_transform transcripts stay aligned" {
    try common.expectLexicalWitness("atm_resume_transform", runAtmResumeTransform);
}
