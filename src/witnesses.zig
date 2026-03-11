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
    .{ .witness_id = "multi_prompt", .title = "Multi-prompt separation" },
    .{ .witness_id = "generator", .title = "Generator" },
    .{ .witness_id = "early_exit", .title = "Early exit" },
    .{ .witness_id = "nested_workflow", .title = "Nested workflow" },
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
    if (std.mem.eql(u8, id, "early_exit")) return runEarlyExit(writer);
    if (std.mem.eql(u8, id, "nested_workflow")) return runNestedWorkflow(writer);
    return error.UnknownWitness;
}

/// Run the generator witness.
pub fn runGenerator(writer: anytype) anyerror!void {
    const tag = struct {};
    const NoError = error{};

    const demo = struct {
        var yielded = [_]i32{ 0, 0, 0 };
        var yield_count: usize = 0;
        var pending_value: i32 = 0;

        fn yieldValue(value: i32) shift.ResetError(NoError)!void {
            pending_value = value;
            _ = try shift.shift(void, tag, void, NoError, handleYield);
        }

        fn handleYield(k: *shift.Continuation(void, tag, void, NoError)) shift.ResetError(NoError)!void {
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
    try shift.reset(tag, void, NoError, &runtime, demo.body);

    var i: usize = 0;
    while (i < demo.yield_count) : (i += 1) try writer.print("yield={d}\n", .{demo.yielded[i]});
    try writer.print("done={d}\n", .{demo.yield_count});
}

/// Run the early-exit witness.
pub fn runEarlyExit(writer: anytype) anyerror!void {
    const tag = struct {};
    const NoError = error{};

    const demo = struct {
        fn handle(_: *shift.Continuation(void, tag, []const u8, NoError)) shift.ResetError(NoError)![]const u8 {
            return "result=early";
        }

        fn body() shift.ResetError(NoError)![]const u8 {
            _ = try shift.shift(void, tag, []const u8, NoError, handle);
            return "result=late";
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    const answer = try shift.reset(tag, []const u8, NoError, &runtime, demo.body);
    try writer.print("{s}\n", .{answer});
}

/// Run the re-delimitation witness that separates static `shift/reset` from `control/prompt`.
pub fn runStaticRedelim(writer: anytype) anyerror!void {
    const tag = struct {};
    const NoError = error{};

    const demo = struct {
        var transcript = [_][]const u8{ "", "", "", "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        fn innerHandle(_: *shift.Continuation(i32, tag, i32, NoError)) shift.ResetError(NoError)!i32 {
            note("inner-handler");
            return 2;
        }

        fn outerHandle(k: *shift.Continuation(i32, tag, i32, NoError)) shift.ResetError(NoError)!i32 {
            note("outer-handler-enter");
            const answer = try k.resumeWith(1);
            note("outer-handler-exit");
            return answer + 10;
        }

        fn body() shift.ResetError(NoError)!i32 {
            const current = try shift.shift(i32, tag, i32, NoError, outerHandle);
            note("after-outer-shift");
            _ = current;
            _ = try shift.shift(i32, tag, i32, NoError, innerHandle);
            note("after-inner-shift");
            return 99;
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    demo.transcript_len = 0;

    const answer = try shift.reset(tag, i32, NoError, &runtime, demo.body);
    for (demo.transcript[0..demo.transcript_len]) |line| try writer.print("{s}\n", .{line});
    try writer.print("final={d}\n", .{answer});
}

/// Run the multi-prompt separation witness.
pub fn runMultiPrompt(writer: anytype) anyerror!void {
    const outer_tag = struct {};
    const inner_tag = struct {};
    const NoError = error{};

    const demo = struct {
        var runtime_ptr: ?*shift.Runtime = null;
        var transcript = [_][]const u8{ "", "", "", "", "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        fn innerHandle(k: *shift.Continuation(i32, outer_tag, i32, NoError)) shift.ResetError(NoError)!i32 {
            note("outer-handler");
            return try k.resumeWith(41);
        }

        fn innerBody() shift.ResetError(NoError)!i32 {
            note("inner-before");
            const current = try shift.shift(i32, outer_tag, i32, NoError, innerHandle);
            note("inner-after");
            return current + 1;
        }

        fn outerBody() shift.ResetError(NoError)!i32 {
            note("outer-before-inner");
            const answer = try shift.reset(inner_tag, i32, NoError, runtime_ptr.?, innerBody);
            note("outer-after-inner");
            return answer;
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    demo.runtime_ptr = &runtime;
    demo.transcript_len = 0;

    const answer = try shift.reset(outer_tag, i32, NoError, &runtime, demo.outerBody);
    for (demo.transcript[0..demo.transcript_len]) |line| try writer.print("{s}\n", .{line});
    try writer.print("final={d}\n", .{answer});
}

/// Run the nested-workflow witness.
pub fn runNestedWorkflow(writer: anytype) anyerror!void {
    const approval_tag = struct {};
    const audit_tag = struct {};
    const NoError = error{};

    const demo = struct {
        var runtime_ptr: ?*shift.Runtime = null;
        var transcript = [_][]const u8{ "", "", "", "", "", "" };
        var transcript_len: usize = 0;

        fn note(message: []const u8) void {
            transcript[transcript_len] = message;
            transcript_len += 1;
        }

        fn handleApproval(k: *shift.Continuation(bool, approval_tag, []const u8, NoError)) shift.ResetError(NoError)![]const u8 {
            note("approval=publish");
            const approved = true;
            return try k.resumeWith(approved);
        }

        fn handleAudit(k: *shift.Continuation(void, audit_tag, void, NoError)) shift.ResetError(NoError)!void {
            note("audit=entered");
            return try k.resumeWith({});
        }

        fn auditBody() shift.ResetError(NoError)!void {
            _ = try shift.shift(void, audit_tag, void, NoError, handleAudit);
            note("audit=after");
            const approved = try shift.shift(bool, approval_tag, []const u8, NoError, handleApproval);
            if (!approved) return;
        }

        fn body() shift.ResetError(NoError)![]const u8 {
            note("workflow=queued");
            try shift.reset(audit_tag, void, NoError, runtime_ptr.?, auditBody);
            note("workflow=done");
            return "result=completed";
        }
    };

    var runtime = shift.Runtime.init(std.heap.page_allocator, .{});
    defer runtime.deinit();
    demo.runtime_ptr = &runtime;
    demo.transcript_len = 0;

    const answer = try shift.reset(approval_tag, []const u8, NoError, &runtime, demo.body);
    for (demo.transcript[0..demo.transcript_len]) |line| try writer.print("{s}\n", .{line});
    try writer.print("{s}\n", .{answer});
}
