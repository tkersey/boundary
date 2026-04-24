// zlinter-disable require_doc_comment - lexical witness helpers are test-only support surfaces.
// zlinter-disable declaration_naming - carrier/test helper names intentionally mirror the witness they wrap.
const ability = @import("ability");
const common = @import("common.zig");
const lexical_runtime = ability;
const std = common.std;
pub const ResumeWitness = ability.effect.Define(.{
    .state_type = void,
    .ops = .{
        ability.effect.ops.Transform("step", void, i32),
    },
});

pub const transcript = struct {
    threadlocal var items = [_][]const u8{ "", "", "", "", "", "" };
    threadlocal var len: usize = 0;
    pub threadlocal var runtime_ptr: ?*lexical_runtime.Runtime = null;
    threadlocal var outer_value: i32 = 0;

    fn note(message: []const u8) void {
        items[len] = message;
        len += 1;
    }

    pub const OuterHandler = struct {
        state: void = {},

        pub fn step(_: *@This()) i32 {
            transcript.note("outer-handler-enter");
            transcript.outer_value = 1;
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

fn staticRedelimInnerHelper(inner_eff: anytype) anyerror!i32 {
    const inner_value = try inner_eff.inner.step.perform();
    return inner_value;
}

pub fn staticRedelimInnerBody(inner_eff: anytype) anyerror!i32 {
    return staticRedelimInnerHelper(inner_eff);
}

const static_redelim_inner_body_carrier = struct {
    pub const source_path = "test/lexical_witness/static_redelim_test.zig";
    pub const body_symbol = "staticRedelimInnerBody";

    pub fn body(inner_eff: anytype) anyerror!i32 {
        return staticRedelimInnerBody(inner_eff);
    }
};

fn runStaticRedelim(writer: anytype) anyerror!void {
    var runtime = lexical_runtime.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.len = 0;
    transcript.runtime_ptr = &runtime;
    transcript.outer_value = 0;
    const result = try lexical_runtime.with(&runtime, .{
        .outer = ResumeWitness.use(.{ .handler = transcript.OuterHandler{} }),
    }, struct {
        pub const runtime_transcript = transcript;

        pub fn body(outer_eff: anytype) anyerror!i32 {
            _ = try outer_eff.outer.step.perform();
            const nested_result = (try lexical_runtime.with(runtime_transcript.runtime_ptr.?, .{
                .inner = NestedResumeWitness.use(.{ .handler = nested.InnerHandler{} }),
            }, static_redelim_inner_body_carrier)).value;
            return nested_result;
        }

        pub const NestedResumeWitness = common.ResumeWitness;
        pub const nested = struct {
            pub const InnerHandler = transcript.InnerHandler;
        };
    });
    try common.printTranscript(writer, transcript.items[0..transcript.len]);
    try writer.print("final={d}\n", .{result.value});
}

test "lexical witness static_redelim transcripts stay aligned" {
    try common.expectLexicalWitness("static_redelim", runStaticRedelim);
}
