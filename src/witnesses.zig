const shift = @import("root.zig");
const std = @import("std");

/// Stable witness metadata for the tests-only corpus.
pub const Witness = struct {
    witness_id: []const u8,
    title: []const u8,
};

/// Stable witness registry used by transcript-locked tests.
pub const witnesses = [_]Witness{
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
    if (std.mem.eql(u8, id, "static_redelim")) return runStaticRedelim(writer);
    if (std.mem.eql(u8, id, "multi_prompt")) return runMultiPrompt(writer);
    if (std.mem.eql(u8, id, "generator")) return runGenerator(writer);
    return error.UnknownWitness;
}

/// Run the generator witness.
pub fn runGenerator(writer: anytype) anyerror!void {
    const NoError = error{};
    const DemoPrompt = shift.Prompt(void, NoError);

    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;
        var yielded = [_]i32{ 0, 0, 0 };
        var yield_count: usize = 0;
        var pending_value: i32 = 0;

        fn yieldValue(value: i32) shift.ResetError(NoError)!void {
            pending_value = value;
            _ = try shift.shift(void, prompt_ptr.?, handleYield);
        }

        fn handleYield(k: *shift.Continuation(void, DemoPrompt)) shift.ResetError(NoError)!void {
            yielded[yield_count] = pending_value;
            yield_count += 1;
            return try k.resumeWith({});
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
    const DemoPrompt = shift.Prompt([]const u8, NoError);

    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;

        fn handle(_: *shift.Continuation(void, DemoPrompt)) shift.ResetError(NoError)![]const u8 {
            return "result=early";
        }

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

/// Run the re-delimitation witness that separates static `shift/reset` from `control/prompt`.
pub fn runStaticRedelim(writer: anytype) anyerror!void {
    const NoError = error{};
    const DemoPrompt = shift.Prompt(i32, NoError);

    const demo = struct {
        var prompt_ptr: ?*const DemoPrompt = null;
        var transcript = [_][]const u8{ "", "", "", "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        fn innerHandle(_: *shift.Continuation(i32, DemoPrompt)) shift.ResetError(NoError)!i32 {
            note("inner-handler");
            return 2;
        }

        fn outerHandle(k: *shift.Continuation(i32, DemoPrompt)) shift.ResetError(NoError)!i32 {
            note("outer-handler-enter");
            const answer = try k.resumeWith(1);
            note("outer-handler-exit");
            return answer + 10;
        }

        fn body() shift.ResetError(NoError)!i32 {
            const current = try shift.shift(i32, prompt_ptr.?, outerHandle);
            note("after-outer-shift");
            _ = current;
            _ = try shift.shift(i32, prompt_ptr.?, innerHandle);
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
    const DemoPrompt = shift.Prompt(i32, NoError);

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

        fn innerHandle(k: *shift.Continuation(i32, DemoPrompt)) shift.ResetError(NoError)!i32 {
            note("outer-handler");
            return try k.resumeWith(41);
        }

        fn innerBody() shift.ResetError(NoError)!i32 {
            note("inner-before");
            const current = try shift.shift(i32, outer_prompt_ptr.?, innerHandle);
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
    const ApprovalPrompt = shift.Prompt([]const u8, NoError);
    const AuditPrompt = shift.Prompt(void, NoError);

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

        fn handleApproval(k: *shift.Continuation(bool, ApprovalPrompt)) shift.ResetError(NoError)![]const u8 {
            note("approval=publish");
            const approved = true;
            return try k.resumeWith(approved);
        }

        fn handleAudit(k: *shift.Continuation(void, AuditPrompt)) shift.ResetError(NoError)!void {
            note("audit=entered");
            return try k.resumeWith({});
        }

        fn auditBody() shift.ResetError(NoError)!void {
            _ = try shift.shift(void, audit_prompt_ptr.?, handleAudit);
            note("audit=after");
            _ = try shift.shift(bool, approval_prompt_ptr.?, handleApproval);
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
