const shift = @import("root.zig");
const std = @import("std");

/// Stable witness metadata for the tests-only corpus.
pub const Witness = struct {
    witness_id: []const u8,
    title: []const u8,
};

/// Stable witness registry used by transcript-locked tests.
pub const witnesses = [_]Witness{
    .{ .witness_id = "atm_resume_transform", .title = "ATM resume-then-transform" },
    .{ .witness_id = "direct_return", .title = "Direct return without continuation exposure" },
    .{ .witness_id = "resume_or_return_return_now", .title = "Optional resumption chooses direct return" },
    .{ .witness_id = "resume_or_return_resume", .title = "Optional resumption chooses single resume" },
    .{ .witness_id = "static_redelim", .title = "Static re-delimitation against control/prompt" },
    .{ .witness_id = "multi_prompt", .title = "Prompt-value separation" },
    .{ .witness_id = "generator", .title = "Generator" },
};

/// Print the stable witness registry.
pub fn listWitnesses(writer: anytype) anyerror!void {
    for (witnesses) |witness| try writer.print("{s}\t{s}\n", .{ witness.witness_id, witness.title });
}

/// Run one witness by stable id.
pub fn runWitness(writer: anytype, id: []const u8) anyerror!void {
    if (std.mem.eql(u8, id, "atm_resume_transform")) return runAtmResumeTransform(writer);
    if (std.mem.eql(u8, id, "direct_return")) return runDirectReturn(writer);
    if (std.mem.eql(u8, id, "resume_or_return_return_now")) return runResumeOrReturnReturnNow(writer);
    if (std.mem.eql(u8, id, "resume_or_return_resume")) return runResumeOrReturnResume(writer);
    if (std.mem.eql(u8, id, "static_redelim")) return runStaticRedelim(writer);
    if (std.mem.eql(u8, id, "multi_prompt")) return runMultiPrompt(writer);
    if (std.mem.eql(u8, id, "generator")) return runGenerator(writer);
    return error.UnknownWitness;
}

/// Run the ATM resume-then-transform witness.
pub fn runAtmResumeTransform(writer: anytype) anyerror!void {
    const NoError = error{};
    const DemoPrompt = shift.Prompt(.resume_then_transform, i32, []const u8, NoError);

    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;
        var transcript = [_][]const u8{ "", "", "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        const handle = struct {
            /// Supply the resumed hole value for this witness.
            pub fn resumeValue() i32 {
                note("handler-enter");
                return 41;
            }

            /// Transform the resumed subcontinuation answer into the enclosing answer.
            pub fn afterResume(value: i32) []const u8 {
                _ = value;
                note("handler-after-resume");
                return "answer=42";
            }
        };

        fn body() shift.ResetError(NoError)!i32 {
            const current = try shift.shift(i32, prompt_ptr.?, handle);
            note("body-after-shift");
            return current + 1;
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var prompt = DemoPrompt.init();
    demo.prompt_ptr = &prompt;
    demo.transcript_len = 0;

    const answer = try shift.reset(&runtime, &prompt, demo.body);
    for (demo.transcript[0..demo.transcript_len]) |line| try writer.print("{s}\n", .{line});
    try writer.print("final={s}\n", .{answer});
}

/// Run the generator witness.
pub fn runGenerator(writer: anytype) anyerror!void {
    const NoError = error{};
    const DemoPrompt = shift.Prompt(.resume_then_transform, void, void, NoError);

    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;
        var yielded = [_]i32{ 0, 0, 0 };
        var yield_count: usize = 0;
        var pending_value: i32 = 0;

        const handle = struct {
            /// Record the yielded value before resuming the generator body.
            pub fn resumeValue() void {
                yielded[yield_count] = pending_value;
                yield_count += 1;
            }

            /// Complete the yield protocol after the body resumes.
            pub fn afterResume(_: void) void {
                // Intentionally empty: the resumed generator body owns completion.
            }
        };

        fn yieldValue(value: i32) shift.ResetError(NoError)!void {
            pending_value = value;
            _ = try shift.shift(void, prompt_ptr.?, handle);
        }

        fn body() shift.ResetError(NoError)!void {
            yield_count = 0;
            try yieldValue(1);
            try yieldValue(2);
            try yieldValue(3);
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var prompt = DemoPrompt.init();
    demo.prompt_ptr = &prompt;
    try shift.reset(&runtime, &prompt, demo.body);

    var i: usize = 0;
    while (i < demo.yield_count) : (i += 1) try writer.print("yield={d}\n", .{demo.yielded[i]});
    try writer.print("done={d}\n", .{demo.yield_count});
}

/// Run the early-exit witness.
pub fn runEarlyExit(writer: anytype) anyerror!void {
    const NoError = error{};
    const DemoPrompt = shift.Prompt(.direct_return, []const u8, []const u8, NoError);

    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;

        const handle = struct {
            /// Return the enclosing answer directly without exposing a continuation.
            pub fn directReturn() []const u8 {
                return "result=early";
            }
        };

        fn body() shift.ResetError(NoError)![]const u8 {
            _ = try shift.shift(void, prompt_ptr.?, handle);
            return "result=late";
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var prompt = DemoPrompt.init();
    demo.prompt_ptr = &prompt;
    const answer = try shift.reset(&runtime, &prompt, demo.body);
    try writer.print("{s}\n", .{answer});
}

/// Run the semantic direct-return witness.
pub fn runDirectReturn(writer: anytype) anyerror!void {
    const NoError = error{};
    const DemoPrompt = shift.Prompt(.direct_return, []const u8, []const u8, NoError);

    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;
        var transcript = [_][]const u8{ "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        const handle = struct {
            /// Return the enclosing answer directly from the handler.
            pub fn directReturn() []const u8 {
                note("handler-direct-return");
                return "result=early";
            }
        };

        fn body() shift.ResetError(NoError)![]const u8 {
            _ = try shift.shift(void, prompt_ptr.?, handle);
            return "result=late";
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var prompt = DemoPrompt.init();
    demo.prompt_ptr = &prompt;
    demo.transcript_len = 0;

    const answer = try shift.reset(&runtime, &prompt, demo.body);
    for (demo.transcript[0..demo.transcript_len]) |line| try writer.print("{s}\n", .{line});
    try writer.print("final={s}\n", .{answer});
}

/// Run the optional-resumption direct-return witness.
pub fn runResumeOrReturnReturnNow(writer: anytype) anyerror!void {
    const NoError = error{};
    const DemoPrompt = shift.Prompt(.resume_or_return, []const u8, []const u8, NoError);
    const Decision = shift.ResumeOrReturn(void, []const u8);

    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;
        var transcript = [_][]const u8{ "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        const handle = struct {
            /// Choose the immediate return branch for this witness.
            pub fn resumeOrReturn() Decision {
                note("handler-return-now");
                return Decision.returnNow("result=early");
            }

            /// Preserve the direct-return witness answer if this branch were ever resumed.
            pub fn afterResume(value: []const u8) []const u8 {
                return value;
            }
        };

        fn body() shift.ResetError(NoError)![]const u8 {
            _ = try shift.shift(void, prompt_ptr.?, handle);
            return "result=late";
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var prompt = DemoPrompt.init();
    demo.prompt_ptr = &prompt;
    demo.transcript_len = 0;

    const answer = try shift.reset(&runtime, &prompt, demo.body);
    for (demo.transcript[0..demo.transcript_len]) |line| try writer.print("{s}\n", .{line});
    try writer.print("final={s}\n", .{answer});
}

/// Run the optional-resumption single-resume witness.
pub fn runResumeOrReturnResume(writer: anytype) anyerror!void {
    const NoError = error{};
    const DemoPrompt = shift.Prompt(.resume_or_return, i32, []const u8, NoError);
    const Decision = shift.ResumeOrReturn(i32, []const u8);

    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;
        var transcript = [_][]const u8{ "", "", "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        const handle = struct {
            /// Choose the resumptive branch for this witness.
            pub fn resumeOrReturn() Decision {
                note("handler-decide-resume");
                return Decision.resumeWith(41);
            }

            /// Convert the resumed answer into the enclosing witness answer.
            pub fn afterResume(value: i32) []const u8 {
                _ = value;
                note("handler-after-resume");
                return "answer=42";
            }
        };

        fn body() shift.ResetError(NoError)!i32 {
            const current = try shift.shift(i32, prompt_ptr.?, handle);
            note("body-after-shift");
            return current + 1;
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var prompt = DemoPrompt.init();
    demo.prompt_ptr = &prompt;
    demo.transcript_len = 0;

    const answer = try shift.reset(&runtime, &prompt, demo.body);
    for (demo.transcript[0..demo.transcript_len]) |line| try writer.print("{s}\n", .{line});
    try writer.print("final={s}\n", .{answer});
}

/// Run the re-delimitation witness that separates static `shift/reset` from `control/prompt`.
pub fn runStaticRedelim(writer: anytype) anyerror!void {
    const NoError = error{};
    const DemoPrompt = shift.Prompt(.resume_then_transform, i32, i32, NoError);

    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;
        var transcript = [_][]const u8{ "", "", "", "", "", "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        const inner_handle = struct {
            /// Resume the inner continuation with a witness payload.
            pub fn resumeValue() i32 {
                note("inner-handler-enter");
                return 2;
            }

            /// Collapse the resumed inner result back to the witness answer.
            pub fn afterResume(_: i32) i32 {
                note("inner-handler-exit");
                return 2;
            }
        };

        const outer_handle = struct {
            /// Resume the outer continuation and log the entry point.
            pub fn resumeValue() i32 {
                note("outer-handler-enter");
                return 1;
            }

            /// Observe the resumed outer answer and re-delimit it.
            pub fn afterResume(answer: i32) i32 {
                note("outer-handler-exit");
                return answer + 10;
            }
        };

        fn body() shift.ResetError(NoError)!i32 {
            const current = try shift.shift(i32, prompt_ptr.?, outer_handle);
            note("after-outer-shift");
            _ = current;
            _ = try shift.shift(i32, prompt_ptr.?, inner_handle);
            note("after-inner-shift");
            return 99;
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var prompt = DemoPrompt.init();
    demo.prompt_ptr = &prompt;
    demo.transcript_len = 0;

    const answer = try shift.reset(&runtime, &prompt, demo.body);
    for (demo.transcript[0..demo.transcript_len]) |line| try writer.print("{s}\n", .{line});
    try writer.print("final={d}\n", .{answer});
}

/// Run the prompt-value separation witness.
pub fn runMultiPrompt(writer: anytype) anyerror!void {
    const NoError = error{};
    const DemoPrompt = shift.Prompt(.resume_then_transform, i32, i32, NoError);

    const demo = struct {
        var runtime_ptr: ?*shift.Runtime = null;
        var outer_prompt_ptr: ?*const DemoPrompt = null;
        var inner_prompt_ptr: ?*const DemoPrompt = null;
        var transcript = [_][]const u8{ "", "", "", "", "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        const outer_handle = struct {
            /// Resume across the outer delimiter to prove prompt identity is by value.
            pub fn resumeValue() i32 {
                note("outer-handler");
                return 41;
            }

            /// Preserve the resumed answer unchanged for the witness.
            pub fn afterResume(value: i32) i32 {
                return value;
            }
        };

        fn innerBody() shift.ResetError(NoError)!i32 {
            note("inner-before");
            const current = try shift.shift(i32, outer_prompt_ptr.?, outer_handle);
            note("inner-after");
            return current + 1;
        }

        fn outerBody() shift.ResetError(NoError)!i32 {
            note("outer-before-inner");
            const answer = try shift.reset(runtime_ptr.?, inner_prompt_ptr.?, innerBody);
            note("outer-after-inner");
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var outer_prompt = DemoPrompt.init();
    var inner_prompt = DemoPrompt.init();
    demo.runtime_ptr = &runtime;
    demo.outer_prompt_ptr = &outer_prompt;
    demo.inner_prompt_ptr = &inner_prompt;
    demo.transcript_len = 0;

    const answer = try shift.reset(&runtime, &outer_prompt, demo.outerBody);
    for (demo.transcript[0..demo.transcript_len]) |line| try writer.print("{s}\n", .{line});
    try writer.print("final={d}\n", .{answer});
}

/// Run the nested-workflow witness.
pub fn runNestedWorkflow(writer: anytype) anyerror!void {
    const NoError = error{};
    const ApprovalPrompt = shift.Prompt(.resume_then_transform, []const u8, []const u8, NoError);
    const AuditPrompt = shift.Prompt(.resume_then_transform, void, void, NoError);

    const demo = struct {
        var runtime_ptr: ?*shift.Runtime = null;
        var approval_prompt_ptr: ?*const ApprovalPrompt = null;
        var audit_prompt_ptr: ?*const AuditPrompt = null;
        var transcript = [_][]const u8{ "", "", "", "", "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        const approval_handle = struct {
            /// Supply the approval decision into the suspended workflow.
            pub fn resumeValue() bool {
                note("approval=publish");
                return true;
            }

            /// Preserve the resumed workflow answer.
            pub fn afterResume(value: []const u8) []const u8 {
                return value;
            }
        };

        const audit_handle = struct {
            /// Mark audit entry before resuming the workflow body.
            pub fn resumeValue() void {
                note("audit=entered");
            }

            /// Complete the audit protocol after resumption.
            pub fn afterResume(_: void) void {
                // Intentionally empty: the resumed audit body owns completion.
            }
        };

        fn auditBody() shift.ResetError(NoError)!void {
            _ = try shift.shift(void, audit_prompt_ptr.?, audit_handle);
            note("audit=after");
            _ = try shift.shift(bool, approval_prompt_ptr.?, approval_handle);
        }

        fn body() shift.ResetError(NoError)![]const u8 {
            note("workflow=queued");
            try shift.reset(runtime_ptr.?, audit_prompt_ptr.?, auditBody);
            note("workflow=done");
            return "result=completed";
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    var approval_prompt = ApprovalPrompt.init();
    var audit_prompt = AuditPrompt.init();
    demo.runtime_ptr = &runtime;
    demo.approval_prompt_ptr = &approval_prompt;
    demo.audit_prompt_ptr = &audit_prompt;
    demo.transcript_len = 0;

    const answer = try shift.reset(&runtime, &approval_prompt, demo.body);
    for (demo.transcript[0..demo.transcript_len]) |line| try writer.print("{s}\n", .{line});
    try writer.print("{s}\n", .{answer});
}
