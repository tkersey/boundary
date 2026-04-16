const builtin = @import("builtin");
const lexical_runtime = @import("shift");
const std = @import("std");

const bridge_multi_prompt = @import("bridge_fixture_multi_prompt");
const bridge_static_redelim = @import("bridge_fixture_static_redelim");
const ResumeWitness = lexical_runtime.effect.Define(.{
    .state_type = void,
    .ops = .{
        lexical_runtime.effect.ops.Transform("step", void, i32),
    },
});

fn printTranscript(writer: anytype, lines: []const []const u8) anyerror!void {
    for (lines) |line| try writer.print("{s}\n", .{line});
}

fn witnessDirectReturnBody(eff: anytype) anyerror![]const u8 {
    try eff.exception.throw("result=early");
}

fn witnessResumeOrReturnReturnNowBody(eff: anytype) anyerror![]const u8 {
    return try eff.optional.request(struct {
        /// This continuation must never run in the return-now witness.
        pub fn apply(_: i32, _: anytype) anyerror![]const u8 {
            return "unused";
        }
    });
}

fn witnessResumeOrReturnResumeBody(eff: anytype) anyerror![]const u8 {
    return try eff.optional.request(struct {
        /// Resume the witness continuation with the canonical answer.
        pub fn apply(_: i32, _: anytype) anyerror![]const u8 {
            return "answer=42";
        }
    });
}

fn witnessEmitThird(eff: anytype) anyerror!void {
    try eff.state.set(3);
    try eff.writer.tell("yield=3");
}

fn witnessEmitSecond(eff: anytype) anyerror!void {
    try eff.state.set(2);
    try eff.writer.tell("yield=2");
    try witnessEmitThird(eff);
}

fn witnessEmitFirst(eff: anytype) anyerror!void {
    try eff.state.set(1);
    try eff.writer.tell("yield=1");
    try witnessEmitSecond(eff);
}

fn witnessGeneratorBody(eff: anytype) anyerror!i32 {
    try witnessEmitFirst(eff);
    const final = try eff.state.get();
    return final;
}

fn witnessAtmBody(eff: anytype) anyerror![]const u8 {
    _ = try eff.atm.step.perform();
    return "answer=42";
}

fn witnessStaticRedelimInnerBody(inner_eff: anytype) anyerror!i32 {
    const inner_value = try inner_eff.inner.step.perform();
    transcript_static_redelim.note("after-inner-shift");
    if (builtin.is_test) transcript_static_redelim.note("inner-handler-exit");
    return inner_value + 9 + transcript_static_redelim.outer_value;
}

fn witnessStaticRedelimOuterBody(outer_eff: anytype) anyerror!i32 {
    transcript_static_redelim.outer_value = try outer_eff.outer.step.perform();
    transcript_static_redelim.note("after-outer-shift");
    const nested = if (builtin.is_test)
        try lexical_runtime.with(@src(), transcript_static_redelim.runtime_ptr.?, .{
            .inner = ResumeWitness.use(.{ .handler = transcript_static_redelim.InnerHandler{} }),
        }, struct {
            /// Keep the nested inner witness on the test-only legacy path until public lowering admits nested prompts.
            pub fn body(inner_eff: anytype) anyerror!i32 {
                return witnessStaticRedelimInnerBody(inner_eff);
            }
        })
    else
        try lexical_runtime.with(@src(), transcript_static_redelim.runtime_ptr.?, .{
            .inner = ResumeWitness.use(.{ .handler = transcript_static_redelim.InnerHandler{} }),
        }, lexical_runtime.NamedBody("src/witness_sources.zig", "witnessStaticRedelimInnerBody", anyerror!i32, witnessStaticRedelimInnerBody));
    if (builtin.is_test) transcript_static_redelim.note("outer-handler-exit");
    return nested.value;
}

fn witnessMultiPromptBody(eff: anytype) anyerror!i32 {
    transcript_multi_prompt.note("outer-before-inner");
    transcript_multi_prompt.note("inner-before");
    _ = eff.inner;
    _ = try eff.outer.step.perform();
    transcript_multi_prompt.note("inner-after");
    transcript_multi_prompt.note("outer-after-inner");
    return 42;
}

const transcript_static_redelim = struct {
    threadlocal var items = [_][]const u8{ "", "", "", "", "", "" };
    threadlocal var len: usize = 0;
    threadlocal var runtime_ptr: ?*lexical_runtime.Runtime = null;
    threadlocal var outer_value: i32 = 0;

    fn note(message: []const u8) void {
        items[len] = message;
        len += 1;
    }

    /// Outer prompt witness handler for the static re-delimitation transcript.
    pub const OuterHandler = struct {
        state: void = {},

        /// Produce the outer static re-delimitation resume value.
        pub fn step(_: *@This()) i32 {
            note("outer-handler-enter");
            return 1;
        }

        /// Preserve the composed outer answer unchanged.
        pub fn afterStep(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };

    /// Inner prompt witness handler for the static re-delimitation transcript.
    pub const InnerHandler = struct {
        state: void = {},

        /// Produce the inner static re-delimitation resume value.
        pub fn step(_: *@This()) i32 {
            note("inner-handler-enter");
            return 2;
        }

        /// Preserve the composed inner answer unchanged.
        pub fn afterStep(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };
};

const transcript_multi_prompt = struct {
    threadlocal var items = [_][]const u8{ "", "", "", "", "" };
    threadlocal var len: usize = 0;

    fn note(message: []const u8) void {
        items[len] = message;
        len += 1;
    }
};

/// Run the canonical ordinary-source direct-return witness transcript.
pub fn runDirectReturn(writer: anytype) anyerror!void {
    const transcript = struct {
        threadlocal var handler_line: []const u8 = "";
    };
    const catch_policy = struct {
        /// Recover the direct-return payload into the witness answer.
        pub fn directReturn(payload: []const u8) []const u8 {
            transcript.handler_line = "handler-direct-return";
            return payload;
        }
    };

    var runtime = lexical_runtime.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.handler_line = "";
    const result = try lexical_runtime.with(@src(), &runtime, .{
        .exception = lexical_runtime.effect.exception.use([]const u8, catch_policy),
    }, lexical_runtime.NamedBody("src/witness_sources.zig", "witnessDirectReturnBody", anyerror![]const u8, witnessDirectReturnBody));
    try writer.print("{s}\n", .{transcript.handler_line});
    try writer.print("final={s}\n", .{result.value});
}

/// Run the canonical ordinary-source optional return-now witness transcript.
pub fn runResumeOrReturnReturnNow(writer: anytype) anyerror!void {
    const transcript = struct {
        threadlocal var items = [_][]const u8{ "", "" };
        threadlocal var len: usize = 0;

        fn note(message: []const u8) void {
            items[len] = message;
            len += 1;
        }
    };
    const policy = struct {
        /// Choose the direct-return branch for the canonical optional witness.
        pub fn resumeOrReturn() lexical_runtime.effect.choice.Decision(i32, []const u8) {
            transcript.note("handler-return-now");
            return lexical_runtime.effect.choice.Decision(i32, []const u8).returnNow("result=early");
        }

        /// Preserve the returned witness answer unchanged.
        pub fn afterResume(answer: []const u8) []const u8 {
            return answer;
        }
    };

    var runtime = lexical_runtime.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.len = 0;
    const result = try lexical_runtime.with(@src(), &runtime, .{
        .optional = lexical_runtime.effect.optional.use(i32, policy),
    }, lexical_runtime.NamedBody("src/witness_sources.zig", "witnessResumeOrReturnReturnNowBody", anyerror![]const u8, witnessResumeOrReturnReturnNowBody));
    try printTranscript(writer, transcript.items[0..transcript.len]);
    try writer.print("final={s}\n", .{result.value});
}

/// Run the canonical ordinary-source optional single-resume witness transcript.
pub fn runResumeOrReturnResume(writer: anytype) anyerror!void {
    const transcript = struct {
        threadlocal var items = [_][]const u8{ "", "", "", "" };
        threadlocal var len: usize = 0;

        fn note(message: []const u8) void {
            items[len] = message;
            len += 1;
        }
    };
    const policy = struct {
        /// Choose the resume branch for the canonical optional witness.
        pub fn resumeOrReturn() lexical_runtime.effect.choice.Decision(i32, []const u8) {
            transcript.note("handler-decide-resume");
            return lexical_runtime.effect.choice.Decision(i32, []const u8).resumeWith(41);
        }

        /// Preserve the resumed answer after the witness continuation returns.
        pub fn afterResume(answer: []const u8) []const u8 {
            transcript.note("body-after-shift");
            transcript.note("handler-after-resume");
            return answer;
        }
    };

    var runtime = lexical_runtime.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.len = 0;
    const result = try lexical_runtime.with(@src(), &runtime, .{
        .optional = lexical_runtime.effect.optional.use(i32, policy),
    }, lexical_runtime.NamedBody("src/witness_sources.zig", "witnessResumeOrReturnResumeBody", anyerror![]const u8, witnessResumeOrReturnResumeBody));
    try printTranscript(writer, transcript.items[0..transcript.len]);
    try writer.print("final={s}\n", .{result.value});
}

/// Run the canonical ordinary-source generator witness transcript.
pub fn runGenerator(writer: anytype) anyerror!void {
    var runtime = lexical_runtime.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    var output_buffer: [256]u8 = undefined;
    var output_fba = std.heap.FixedBufferAllocator.init(&output_buffer);
    const result = try lexical_runtime.with(@src(), &runtime, .{
        .writer = lexical_runtime.effect.writer.use([]const u8, output_fba.allocator()),
        .state = lexical_runtime.effect.state.use(@as(i32, 0)),
    }, lexical_runtime.NamedBody("src/witness_sources.zig", "witnessGeneratorBody", anyerror!i32, witnessGeneratorBody));
    defer output_fba.allocator().free(result.outputs.writer);
    for (result.outputs.writer) |item| try writer.print("{s}\n", .{item});
    try writer.print("done={d}\n", .{result.value});
}

/// Run the canonical ordinary-source ATM witness transcript.
pub fn runAtmResumeTransform(writer: anytype) anyerror!void {
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

        /// Produce the canonical ATM witness resume value.
        pub fn step(_: *@This()) i32 {
            transcript.note("handler-enter");
            return 41;
        }

        /// Preserve the completed ATM witness answer.
        pub fn afterStep(_: *@This(), answer: []const u8) []const u8 {
            transcript.note("body-after-shift");
            transcript.note("handler-after-resume");
            return answer;
        }
    };

    var runtime = lexical_runtime.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.len = 0;
    const result = try lexical_runtime.with(@src(), &runtime, .{
        .atm = ResumeWitness.use(.{ .handler = Handler{} }),
    }, lexical_runtime.NamedBody("src/witness_sources.zig", "witnessAtmBody", anyerror![]const u8, witnessAtmBody));
    try printTranscript(writer, transcript.items[0..transcript.len]);
    try writer.print("final={s}\n", .{result.value});
}

/// Run the canonical ordinary-source static re-delimitation witness transcript.
pub fn runStaticRedelim(writer: anytype) anyerror!void {
    if (!builtin.is_test) return bridge_static_redelim.run(writer);

    var runtime = lexical_runtime.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript_static_redelim.len = 0;
    transcript_static_redelim.runtime_ptr = &runtime;
    const result = try lexical_runtime.with(@src(), &runtime, .{
        .outer = ResumeWitness.use(.{ .handler = transcript_static_redelim.OuterHandler{} }),
    }, struct {
        /// Keep the nested-prompt semantic witness on the test-only legacy path until public lowering admits it.
        pub fn body(outer_eff: anytype) anyerror!i32 {
            return witnessStaticRedelimOuterBody(outer_eff);
        }
    });
    try printTranscript(writer, transcript_static_redelim.items[0..transcript_static_redelim.len]);
    try writer.print("final={d}\n", .{result.value});
}

/// Run the canonical ordinary-source multi-prompt witness transcript.
pub fn runMultiPrompt(writer: anytype) anyerror!void {
    if (!builtin.is_test) return bridge_multi_prompt.run(writer);

    const OuterHandler = struct {
        state: void = {},

        /// Produce the outer multi-prompt witness resume value.
        pub fn step(_: *@This()) i32 {
            transcript_multi_prompt.note("outer-handler");
            return 41;
        }

        /// Preserve the completed outer witness answer unchanged.
        pub fn afterStep(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };
    const InnerHandler = struct {
        state: void = {},

        /// Reject accidental interception by the inner prompt.
        pub fn step(_: *@This()) i32 {
            unreachable;
        }

        /// Preserve the answer if the inner witness ever resumed.
        pub fn afterStep(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };

    var runtime = lexical_runtime.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript_multi_prompt.len = 0;
    const result = try lexical_runtime.with(@src(), &runtime, .{
        .outer = ResumeWitness.use(.{ .handler = OuterHandler{} }),
        .inner = ResumeWitness.use(.{ .handler = InnerHandler{} }),
    }, struct {
        /// Keep the multi-prompt separation witness on the test-only legacy path until public lowering admits it.
        pub fn body(eff: anytype) anyerror!i32 {
            return witnessMultiPromptBody(eff);
        }
    });
    try printTranscript(writer, transcript_multi_prompt.items[0..transcript_multi_prompt.len]);
    try writer.print("final={d}\n", .{result.value});
}
