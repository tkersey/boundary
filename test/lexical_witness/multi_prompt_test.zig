const common = @import("common.zig");
const lexical_runtime = common.lexical_runtime;
const std = common.std;
const ResumeWitness = common.ResumeWitness;

const transcript = struct {
    threadlocal var items = [_][]const u8{ "", "", "", "", "" };
    threadlocal var len: usize = 0;

    fn note(message: []const u8) void {
        items[len] = message;
        len += 1;
    }

    const OuterHandler = struct {
        state: void = {},

        pub fn step(_: *@This()) i32 {
            transcript.note("outer-handler");
            return 41;
        }

        pub fn afterStep(_: *@This(), answer: i32) i32 {
            noteInnerAfter();
            noteOuterAfterInner();
            return answer;
        }
    };

    const InnerHandler = struct {
        state: void = {},

        pub fn step(_: *@This()) i32 {
            unreachable;
        }

        pub fn afterStep(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };
};

fn noteOuterBeforeInner() void {
    transcript.note("outer-before-inner");
}

fn noteInnerBefore() void {
    transcript.note("inner-before");
}

fn noteInnerAfter() void {
    transcript.note("inner-after");
}

fn noteOuterAfterInner() void {
    transcript.note("outer-after-inner");
}

fn multiPromptBody(eff: anytype) anyerror!i32 {
    _ = eff.inner;
    _ = try eff.outer.step.perform();
    return 42;
}

fn runMultiPrompt(writer: anytype) anyerror!void {
    var runtime = lexical_runtime.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.len = 0;
    noteOuterBeforeInner();
    noteInnerBefore();
    const result = try lexical_runtime.with(&runtime, .{
        .outer = ResumeWitness.use(.{ .handler = transcript.OuterHandler{} }),
        .inner = ResumeWitness.use(.{ .handler = transcript.InnerHandler{} }),
    }, struct {
        pub fn body(eff: anytype) anyerror!i32 {
            return multiPromptBody(eff);
        }
    });
    try common.printTranscript(writer, transcript.items[0..transcript.len]);
    try writer.print("final={d}\n", .{result.value});
}

test "lexical witness multi_prompt transcripts stay aligned" {
    try common.expectLexicalWitness("multi_prompt", runMultiPrompt);
}
