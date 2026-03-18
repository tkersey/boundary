const shift = @import("shift");
const std = @import("std");

const NoError = error{};
const ResumeWitness = shift.effect.Define(.{
    .state_type = void,
    .ops = .{
        shift.effect.ops.Transform("step", void, i32),
    },
});

fn printTranscript(writer: anytype, lines: []const []const u8) !void {
    for (lines) |line| try writer.print("{s}\n", .{line});
}

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

    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.handler_line = "";
    const result = try shift.with(&runtime, .{
        .exception = shift.effect.exception.use([]const u8, catch_policy),
    }, struct {
        /// Abort immediately through the canonical ordinary witness source.
        pub fn body(eff: anytype) ![]const u8 {
            try eff.exception.throw("result=early");
        }
    });
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
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
            transcript.note("handler-return-now");
            return shift.effect.choice.Decision(i32, []const u8).returnNow("result=early");
        }

        /// Preserve the returned witness answer unchanged.
        pub fn afterResume(answer: []const u8) []const u8 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.len = 0;
    const result = try shift.with(&runtime, .{
        .optional = shift.effect.optional.use(i32, policy),
    }, struct {
        /// Trigger the canonical witness choice point and prove the continuation is skipped.
        pub fn body(eff: anytype) ![]const u8 {
            return try eff.optional.request(struct {
                /// This continuation must never run in the return-now witness.
                pub fn apply(_: i32, _: anytype) ![]const u8 {
                    unreachable;
                }
            });
        }
    });
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
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
            transcript.note("handler-decide-resume");
            return shift.effect.choice.Decision(i32, []const u8).resumeWith(41);
        }

        /// Preserve the resumed answer after the witness continuation returns.
        pub fn afterResume(answer: []const u8) []const u8 {
            transcript.note("handler-after-resume");
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.len = 0;
    const result = try shift.with(&runtime, .{
        .optional = shift.effect.optional.use(i32, policy),
    }, struct {
        /// Trigger the canonical witness choice point and finish the resumed continuation.
        pub fn body(eff: anytype) ![]const u8 {
            return try eff.optional.request(struct {
                /// Resume the witness continuation with the canonical answer.
                pub fn apply(value: i32, _: anytype) ![]const u8 {
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

/// Run the canonical ordinary-source generator witness transcript.
pub fn runGenerator(writer: anytype) anyerror!void {
    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    var output_buffer: [256]u8 = undefined;
    var output_fba = std.heap.FixedBufferAllocator.init(&output_buffer);
    const result = try shift.with(&runtime, .{
        .writer = shift.effect.writer.use([]const u8, output_fba.allocator()),
        .state = shift.effect.state.use(@as(i32, 0)),
    }, struct {
        /// Emit the canonical yielded values and return the final generator count.
        pub fn body(eff: anytype) !i32 {
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
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.len = 0;
    const result = try shift.with(&runtime, .{
        .atm = ResumeWitness.use(.{ .handler = Handler{} }),
    }, struct {
        /// Resume once through the ATM witness and return the canonical answer.
        pub fn body(eff: anytype) ![]const u8 {
            _ = try eff.atm.step.perform();
            transcript.note("body-after-shift");
            transcript.note("handler-after-resume");
            return "answer=42";
        }
    });
    try printTranscript(writer, transcript.items[0..transcript.len]);
    try writer.print("final={s}\n", .{result.value});
}

/// Run the canonical ordinary-source static re-delimitation witness transcript.
pub fn runStaticRedelim(writer: anytype) anyerror!void {
    const transcript = struct {
        threadlocal var items = [_][]const u8{ "", "", "", "", "", "" };
        threadlocal var len: usize = 0;
        threadlocal var runtime_ptr: ?*shift.Runtime = null;
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

        /// Preserve the composed outer answer unchanged.
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

        /// Preserve the composed inner answer unchanged.
        pub fn afterStep(_: *@This(), answer: i32) i32 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.len = 0;
    transcript.runtime_ptr = &runtime;
    const result = try shift.with(&runtime, .{
        .outer = ResumeWitness.use(.{ .handler = OuterHandler{} }),
    }, struct {
        /// Resume the outer witness, then resolve the nested inner witness.
        pub fn body(outer_eff: anytype) !i32 {
            transcript.outer_value = try outer_eff.outer.step.perform();
            transcript.note("after-outer-shift");
            const nested = try shift.with(transcript.runtime_ptr.?, .{
                .inner = ResumeWitness.use(.{ .handler = InnerHandler{} }),
            }, struct {
                /// Resume the nested inner witness and return the composed answer.
                pub fn body(inner_eff: anytype) !i32 {
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

/// Run the canonical ordinary-source multi-prompt witness transcript.
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

    var runtime = shift.Runtime.init(std.heap.page_allocator);
    defer runtime.deinit();
    transcript.len = 0;
    const result = try shift.with(&runtime, .{
        .outer = ResumeWitness.use(.{ .handler = OuterHandler{} }),
        .inner = ResumeWitness.use(.{ .handler = InnerHandler{} }),
    }, struct {
        /// Prove the outer and inner witness bindings remain distinct under one lexical scope.
        pub fn body(eff: anytype) !i32 {
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
