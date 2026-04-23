const common = @import("common.zig");
const lexical_runtime = common.lexical_runtime;
const std = common.std;
pub const ResumeWitness = common.ResumeWitness;

pub const transcript = struct {
    threadlocal var items = [_][]const u8{ "", "", "", "", "", "" };
    threadlocal var len: usize = 0;
    threadlocal var runtime_ptr: ?*lexical_runtime.Runtime = null;
    threadlocal var outer_value: i32 = 0;

    fn note(message: []const u8) void {
        items[len] = message;
        len += 1;
    }

    pub const OuterHandler = struct {
        state: void = {},

        pub fn step(_: *@This()) i32 {
            transcript.note("outer-handler-enter");
            transcript.note("after-outer-shift");
            return 1;
        }

        pub fn afterStep(_: *@This(), answer: i32) i32 {
            transcript.note("outer-handler-exit");
            return answer + transcript.outer_value;
        }
    };

    pub const InnerHandler = struct {
        state: void = {},

        pub fn step(_: *@This()) i32 {
            transcript.note("inner-handler-enter");
            return 2;
        }

        pub fn afterStep(_: *@This(), answer: i32) i32 {
            transcript.note("after-inner-shift");
            transcript.note("inner-handler-exit");
            return answer + 9;
        }
    };
};

pub fn staticRedelimInnerBody(inner_eff: anytype) anyerror!i32 {
    const inner_value = try inner_eff.inner.step.perform();
    return inner_value;
}

fn runStaticRedelim(writer: anytype) anyerror!void {
    var runtime = lexical_runtime.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.len = 0;
    transcript.runtime_ptr = &runtime;
    const result = try lexical_runtime.with(&runtime, .{
        .outer = ResumeWitness.use(.{ .handler = transcript.OuterHandler{} }),
    }, struct {
        pub fn body(outer_eff: anytype) anyerror!i32 {
            _ = try outer_eff.outer.step.perform();
            const nested = (try lexical_runtime.with(transcript.runtime_ptr.?, .{
                .inner = NestedResumeWitness.use(.{ .handler = Nested.InnerHandler{} }),
            }, struct {
                pub fn body(inner_eff: anytype) anyerror!i32 {
                    return staticRedelimInnerBody(inner_eff);
                }
            })).value;
            return nested;
        }

        pub const NestedResumeWitness = common.ResumeWitness;
        pub const Nested = struct {
            pub const InnerHandler = transcript.InnerHandler;
        };
    });
    try common.printTranscript(writer, transcript.items[0..transcript.len]);
    try writer.print("final={d}\n", .{result.value});
}

test "lexical witness static_redelim transcripts stay aligned" {
    try common.expectLexicalWitness("static_redelim", runStaticRedelim);
}
