const lexical_runtime = @import("lexical_runtime_internal");
const std = @import("std");
const ResumeWitness = lexical_runtime.effect.Define(.{
    .state_type = void,
    .ops = .{
        lexical_runtime.effect.ops.Transform("step", void, i32),
    },
});

fn printTranscript(writer: anytype, lines: []const []const u8) anyerror!void {
    for (lines) |line| try writer.print("{s}\n", .{line});
}

/// Run the lexical direct-return witness transcript.
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
    const result = try lexical_runtime.with(&runtime, .{
        .exception = lexical_runtime.effect.exception.use([]const u8, catch_policy),
    }, struct {
        /// Abort immediately through the lexical exception surface.
        pub fn body(eff: anytype) anyerror![]const u8 {
            try eff.exception.throw("result=early");
        }
    });
    try writer.print("{s}\n", .{transcript.handler_line});
    try writer.print("final={s}\n", .{result.value});
}

/// Run the lexical optional return-now witness transcript.
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
        /// Choose the direct-return branch for the lexical optional witness.
        pub fn resumeOrReturn() lexical_runtime.effect.choice.Decision(i32, []const u8) {
            transcript.note("handler-return-now");
            return lexical_runtime.effect.choice.Decision(i32, []const u8).returnNow("result=early");
        }

        /// Preserve the returned answer if this branch is ever resumed.
        pub fn afterResume(answer: []const u8) []const u8 {
            return answer;
        }
    };

    var runtime = lexical_runtime.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.len = 0;
    const result = try lexical_runtime.with(&runtime, .{
        .optional = lexical_runtime.effect.optional.use(i32, policy),
    }, struct {
        /// Trigger the lexical choice point and confirm the continuation is skipped.
        pub fn body(eff: anytype) anyerror![]const u8 {
            return try eff.optional.request(struct {
                /// This continuation must never run in the return-now witness.
                pub fn apply(_: i32, _: anytype) anyerror![]const u8 {
                    unreachable;
                }
            });
        }
    });
    try printTranscript(writer, transcript.items[0..transcript.len]);
    try writer.print("final={s}\n", .{result.value});
}

/// Run the lexical optional single-resume witness transcript.
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
        /// Choose the resume branch for the lexical optional witness.
        pub fn resumeOrReturn() lexical_runtime.effect.choice.Decision(i32, []const u8) {
            transcript.note("handler-decide-resume");
            return lexical_runtime.effect.choice.Decision(i32, []const u8).resumeWith(41);
        }

        /// Preserve the resumed answer after the witness continuation returns.
        pub fn afterResume(answer: []const u8) []const u8 {
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
        /// Trigger the lexical choice point and finish the resumed continuation.
        pub fn body(eff: anytype) anyerror![]const u8 {
            return try eff.optional.request(struct {
                /// Resume the lexical witness continuation with the canonical answer.
                pub fn apply(value: i32, _: anytype) anyerror![]const u8 {
                    if (value != 41) unreachable;
                    transcript.note("body-after-shift");
                    return "answer=42";
                }
            });
        }
    });
    try printTranscript(writer, transcript.items[0..transcript.len]);
    try writer.print("final={s}\n", .{result.value});
}

/// Run the lexical generator witness transcript.
pub fn runGenerator(writer: anytype) anyerror!void {
    var runtime = lexical_runtime.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    var output_buffer: [256]u8 = undefined;
    var output_fba = std.heap.FixedBufferAllocator.init(&output_buffer);
    const result = try lexical_runtime.with(&runtime, .{
        .writer = lexical_runtime.effect.writer.use([]const u8, output_fba.allocator()),
        .state = lexical_runtime.effect.state.use(@as(i32, 0)),
    }, struct {
        /// Emit three yielded values and return the final generator count.
        pub fn body(eff: anytype) anyerror!i32 {
            while (true) {
                const current = try eff.state.get();
                if (current == 3) return current;
                const next = current + 1;
                try eff.state.set(next);
                try eff.writer.tell(switch (next) {
                    1 => "yield=1",
                    2 => "yield=2",
                    3 => "yield=3",
                    else => unreachable,
                });
            }
        }
    });
    defer output_fba.allocator().free(result.outputs.writer);
    for (result.outputs.writer) |item| try writer.print("{s}\n", .{item});
    try writer.print("done={d}\n", .{result.value});
}

/// Run the lexical ATM resume-then-transform witness transcript.
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

        /// Produce the canonical ATM resume value.
        pub fn step(_: *@This()) i32 {
            transcript.note("handler-enter");
            return 41;
        }

        /// Preserve the completed ATM witness answer.
        pub fn afterStep(_: *@This(), answer: []const u8) []const u8 {
            return answer;
        }
    };

    var runtime = lexical_runtime.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.len = 0;
    const result = try lexical_runtime.with(&runtime, .{
        .atm = ResumeWitness.use(.{ .handler = Handler{} }),
    }, struct {
        /// Resume once through the lexical ATM witness and return the final answer.
        pub fn body(eff: anytype) anyerror![]const u8 {
            _ = try eff.atm.step.perform();
            transcript.note("body-after-shift");
            transcript.note("handler-after-resume");
            return "answer=42";
        }
    });
    try printTranscript(writer, transcript.items[0..transcript.len]);
    try writer.print("final={s}\n", .{result.value});
}

/// Run the lexical static re-delimitation witness transcript.
pub fn runStaticRedelim(writer: anytype) anyerror!void {
    const transcript = struct {
        threadlocal var items = [_][]const u8{ "", "", "", "", "", "" };
        threadlocal var len: usize = 0;
        threadlocal var runtime_ptr: ?*lexical_runtime.Runtime = null;
        threadlocal var outer_value: i32 = 0;

        fn note(message: []const u8) void {
            items[len] = message;
            len += 1;
        }
    };
    const OuterHandler = struct {
        state: void = {},

        /// Produce the outer static re-delimitation resume value.
        pub fn step(_: *@This()) i32 {
            transcript.note("outer-handler-enter");
            return 1;
        }

        /// Preserve the composed outer witness answer.
        pub fn afterStep(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };
    const InnerHandler = struct {
        state: void = {},

        /// Produce the inner static re-delimitation resume value.
        pub fn step(_: *@This()) i32 {
            transcript.note("inner-handler-enter");
            return 2;
        }

        /// Preserve the composed inner witness answer.
        pub fn afterStep(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };

    var runtime = lexical_runtime.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.len = 0;
    transcript.runtime_ptr = &runtime;
    const result = try lexical_runtime.with(&runtime, .{
        .outer = ResumeWitness.use(.{ .handler = OuterHandler{} }),
    }, struct {
        /// Resume the outer witness, then open and resolve the nested inner witness.
        pub fn body(outer_eff: anytype) anyerror!i32 {
            transcript.outer_value = try outer_eff.outer.step.perform();
            transcript.note("after-outer-shift");
            const nested = try lexical_runtime.with(transcript.runtime_ptr.?, .{
                .inner = ResumeWitness.use(.{ .handler = InnerHandler{} }),
            }, struct {
                /// Resume the nested inner witness and return the composed answer.
                pub fn body(inner_eff: anytype) anyerror!i32 {
                    const inner_value = try inner_eff.inner.step.perform();
                    transcript.note("after-inner-shift");
                    transcript.note("inner-handler-exit");
                    return inner_value + 9 + transcript.outer_value;
                }
            });
            transcript.note("outer-handler-exit");
            return nested.value;
        }
    });
    try printTranscript(writer, transcript.items[0..transcript.len]);
    try writer.print("final={d}\n", .{result.value});
}

/// Run the lexical multi-prompt separation witness transcript.
pub fn runMultiPrompt(writer: anytype) anyerror!void {
    const transcript = struct {
        threadlocal var items = [_][]const u8{ "", "", "", "", "" };
        threadlocal var len: usize = 0;

        fn note(message: []const u8) void {
            items[len] = message;
            len += 1;
        }
    };
    const OuterHandler = struct {
        state: void = {},

        /// Produce the outer multi-prompt witness resume value.
        pub fn step(_: *@This()) i32 {
            transcript.note("outer-handler");
            return 41;
        }

        /// Preserve the completed outer multi-prompt answer.
        pub fn afterStep(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };
    const InnerHandler = struct {
        state: void = {},

        /// Reject any accidental inner interception in the multi-prompt witness.
        pub fn step(_: *@This()) i32 {
            unreachable;
        }

        /// Preserve the answer if the inner witness were ever resumed.
        pub fn afterStep(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };

    var runtime = lexical_runtime.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.len = 0;
    const result = try lexical_runtime.with(&runtime, .{
        .outer = ResumeWitness.use(.{ .handler = OuterHandler{} }),
        .inner = ResumeWitness.use(.{ .handler = InnerHandler{} }),
    }, struct {
        /// Prove the outer and inner witness bindings remain distinct under one lexical scope.
        pub fn body(eff: anytype) anyerror!i32 {
            transcript.note("outer-before-inner");
            transcript.note("inner-before");
            _ = eff.inner;
            _ = try eff.outer.step.perform();
            transcript.note("inner-after");
            transcript.note("outer-after-inner");
            return 42;
        }
    });
    try printTranscript(writer, transcript.items[0..transcript.len]);
    try writer.print("final={d}\n", .{result.value});
}
