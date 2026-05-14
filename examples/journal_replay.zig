// zlinter-disable declaration_naming require_doc_comment no_hidden_allocations no_inferred_error_unions
const ability = @import("ability");
const std = @import("std");

const ApprovalHandlers = struct {};

const ApprovalProtocol = ability.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{
        ability.ir.schema.transform("score", []const u8, i32),
    },
});

const ApprovalRows = ApprovalProtocol.Rows(ApprovalHandlers, .{
    .requirement_index = 0,
    .first_op = 0,
});

const approval_semantic_spec = blk: {
    const semantic = ability.ir.builder.semantic;
    const ScoreOp = ApprovalRows.op("score");

    break :blk .{
        .label = "journal-replay",
        .ir_hash = 0x6a6f75726e616c01,
        .entry = "run",
        .requirements = &.{ApprovalRows.requirement},
        .ops = &ApprovalRows.ops,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = semantic.span(0, 1),
            .params = .{},
            .locals = .{
                semantic.local("payload", []const u8),
                semantic.local("score", i32),
            },
            .result = i32,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    semantic.constString("payload", "policy-input"),
                    semantic.call(ScoreOp, .{
                        .dst = "score",
                        .payload = "payload",
                        .label = "approval.score",
                    }),
                },
                .terminator = semantic.returnValue("score"),
            }},
        }},
    };
};

const approval_compiled = ability.ir.builder.semantic.finish(approval_semantic_spec) catch |err|
    @compileError("invalid journal-replay semantic plan: " ++ @errorName(err));

const ApprovalBody = struct {
    pub const site_metadata = approval_compiled.site_metadata;
    pub const compiled_plan = approval_compiled.plan;
};

const ApprovalProgram = ability.program("journal-replay", ApprovalHandlers, ApprovalBody);
const ScoreSite = ApprovalProgram.protocol.operationSite("approval", "score", 0);

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    var runtime = ability.Runtime.init(allocator);
    defer runtime.deinit();

    var session = try ApprovalProgram.Session.start(&runtime, .{});
    defer session.deinit();
    var journal = ApprovalProgram.Session.Journal.init(allocator);
    defer journal.deinit();

    const request = switch (try session.next()) {
        .request => |yielded| yielded,
        .after => return error.UnexpectedAfter,
        .done => return error.UnexpectedDone,
    };
    const typed = try request.as(ScoreSite);
    const response_trace = try typed.responseTrace(.@"resume", @as(i32, 42));
    try journal.appendRequest(.{ .operation = request.trace() });
    try journal.appendResponseValue(response_trace, @as(i32, 42));
    try session.resumeTyped(typed, @as(i32, 42));
    var result = switch (try session.next()) {
        .done => |done| done,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try journal.appendDone(response_trace.response_value_fingerprint);

    const journal_bytes = try journal.encode(allocator);
    defer allocator.free(journal_bytes);
    var decoded = try ApprovalProgram.Session.Journal.decode(allocator, journal_bytes);
    defer decoded.deinit();

    var replay_session = try ApprovalProgram.Session.start(&runtime, .{});
    defer replay_session.deinit();
    _ = try replay_session.next();
    var replayer = decoded.replayer();
    defer replayer.deinit();
    const replay_value = try replayer.expectCurrentValue(try replay_session.current(), i32);
    try replay_session.resumeTyped(try (try replay_session.current()).request.as(ScoreSite), replay_value);
    var replay_result = switch (try replay_session.next()) {
        .done => |done| done,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer replay_result.deinit();
    try replayer.expectDone(response_trace.response_value_fingerprint);

    try writer.print("journal_fingerprint={x}\n", .{try decoded.fingerprint()});
    try writer.print("recorded_result={d}\n", .{result.value});
    try writer.print("replayed_result={d}\n", .{replay_result.value});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
