const parity_scenarios = @import("parity_scenarios");
const shift = @import("shift");
const std = @import("std");

const NoError = error{};

fn printTranscript(writer: anytype, lines: []const []const u8) !void {
    for (lines) |line| try writer.print("{s}\n", .{line});
}

fn expectLexicalWitness(comptime witness_id: []const u8, runner: anytype) !void {
    const expected = parity_scenarios.findWitness(witness_id).?.expected_transcript;
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try runner(&writer);
    try std.testing.expectEqualStrings(expected, writer.buffered());
}

fn runDirectReturn(writer: anytype) !void {
    const transcript = struct {
        threadlocal var handler_line: []const u8 = "";
    };
    const catch_policy = struct {
        /// Recover the direct-return payload into the final witness answer.
        pub fn directReturn(payload: []const u8) []const u8 {
            transcript.handler_line = "handler-direct-return";
            return payload;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    transcript.handler_line = "";
    const result = try shift.with(&runtime, .{
        .exception = shift.effect.exception.use([]const u8, NoError, catch_policy),
    }, struct {
        /// Abort immediately through the lexical exception surface.
        pub fn body(eff: anytype) shift.ResetError(NoError)![]const u8 {
            try eff.exception.throw("result=early");
        }
    });
    try writer.print("{s}\n", .{transcript.handler_line});
    try writer.print("final={s}\n", .{result.value});
}

fn runResumeOrReturnReturnNow(writer: anytype) !void {
    const transcript = struct {
        threadlocal var items = [_][]const u8{ "", "" };
        threadlocal var len: usize = 0;

        fn note(message: []const u8) void {
            items[len] = message;
            len += 1;
        }
    };
    const policy = struct {
        /// Choose the direct-return branch for the return-now witness.
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
            transcript.note("handler-return-now");
            return shift.effect.choice.Decision(i32, []const u8).returnNow("result=early");
        }

        /// Preserve the early answer unchanged.
        pub fn afterResume(answer: []const u8) []const u8 {
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    transcript.len = 0;
    const result = try shift.with(&runtime, .{
        .optional = shift.effect.optional.use(i32, NoError, policy),
    }, struct {
        /// Trigger the lexical choice point and prove the continuation is skipped.
        pub fn body(eff: anytype) shift.ResetError(NoError)![]const u8 {
            return try eff.optional.request(struct {
                /// This continuation must never run in the return-now witness.
                pub fn apply(_: i32, _: anytype) shift.ResetError(NoError)![]const u8 {
                    unreachable;
                }
            });
        }
    });
    try printTranscript(writer, transcript.items[0..transcript.len]);
    try writer.print("final={s}\n", .{result.value});
}

fn runResumeOrReturnResume(writer: anytype) !void {
    const transcript = struct {
        threadlocal var items = [_][]const u8{ "", "", "", "" };
        threadlocal var len: usize = 0;

        fn note(message: []const u8) void {
            items[len] = message;
            len += 1;
        }
    };
    const policy = struct {
        /// Choose the resume branch for the single-resume witness.
        pub fn resumeOrReturn() shift.effect.choice.Decision(i32, []const u8) {
            transcript.note("handler-decide-resume");
            return shift.effect.choice.Decision(i32, []const u8).resumeWith(41);
        }

        /// Finalize the resumed answer after the continuation returns.
        pub fn afterResume(answer: []const u8) []const u8 {
            transcript.note("handler-after-resume");
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    transcript.len = 0;
    const result = try shift.with(&runtime, .{
        .optional = shift.effect.optional.use(i32, NoError, policy),
    }, struct {
        /// Trigger the lexical choice point and complete the resumed continuation.
        pub fn body(eff: anytype) shift.ResetError(NoError)![]const u8 {
            return try eff.optional.request(struct {
                /// Resume the lexical continuation with the canonical witness answer.
                pub fn apply(value: i32, _: anytype) shift.ResetError(NoError)![]const u8 {
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

fn runGenerator(writer: anytype) !void {
    var runtime = shift.Runtime.init(std.testing.allocator);
    defer runtime.deinit();
    var output_buffer: [256]u8 = undefined;
    var output_fba = std.heap.FixedBufferAllocator.init(&output_buffer);
    const result = try shift.with(&runtime, .{
        .writer = shift.effect.writer.use([]const u8, NoError, output_fba.allocator()),
        .state = shift.effect.state.use(NoError, @as(i32, 0)),
    }, struct {
        /// Emit three yielded values and return the final generator count.
        pub fn body(eff: anytype) shift.ResetError(NoError)!i32 {
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

test "lexical witness transcripts stay aligned with the admitted parity subset" {
    try expectLexicalWitness("direct_return", runDirectReturn);
    try expectLexicalWitness("resume_or_return_return_now", runResumeOrReturnReturnNow);
    try expectLexicalWitness("resume_or_return_resume", runResumeOrReturnResume);
    try expectLexicalWitness("generator", runGenerator);
}
