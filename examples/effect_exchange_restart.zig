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
        .label = "effect-exchange-restart",
        .ir_hash = 0x6578636872737474,
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
                    semantic.constString("payload", "restart-approval"),
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
    @compileError("invalid effect-exchange-restart semantic plan: " ++ @errorName(err));

const ApprovalBody = struct {
    pub const site_metadata = approval_compiled.site_metadata;
    pub const compiled_plan = approval_compiled.plan;
};

const ApprovalProgram = ability.program("effect-exchange-restart", ApprovalHandlers, ApprovalBody);

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    var journal = ApprovalProgram.Session.Journal.init(allocator);
    defer journal.deinit();

    var runtime = ability.Runtime.init(allocator);
    var session = try ApprovalProgram.Session.start(&runtime, .{});
    const request = switch (try session.next()) {
        .request => |yielded| yielded,
        .after => return error.UnexpectedAfter,
        .done => return error.UnexpectedDone,
    };
    var capsule = try session.capture(allocator);
    defer capsule.deinit();
    var image = try capsule.encode(allocator);
    defer image.deinit();
    var request_envelope = try ApprovalProgram.Exchange.RequestEnvelope.fromRequest(allocator, request, .{
        .capsule = image,
        .journal = &journal,
    });
    defer request_envelope.deinit();
    session.deinit();
    runtime.deinit();

    var decoded_request = try ApprovalProgram.Exchange.RequestEnvelope.decode(allocator, request_envelope.bytes);
    defer decoded_request.deinit();
    var restored_runtime = ability.Runtime.init(allocator);
    defer restored_runtime.deinit();
    var restored = try ApprovalProgram.Exchange.restoreFromRequestEnvelope(&restored_runtime, .{}, decoded_request);
    defer restored.deinit();
    var response = try ApprovalProgram.Exchange.ResponseEnvelope.@"resume"(allocator, decoded_request, @as(i32, 64));
    defer response.deinit();
    try journal.appendResponseValue(.{
        .request_fingerprint = response.request_fingerprint,
        .kind = response.kind,
        .response_ref = response.response_ref,
        .response_value_fingerprint = response.response_value_fingerprint,
        .fingerprint = response.response_trace_fingerprint,
    }, @as(i32, 64));
    try ApprovalProgram.Exchange.applyResponse(&restored, response, .{ .request_envelope_fingerprint = decoded_request.fingerprint });
    var result = switch (try restored.next()) {
        .done => |done| done,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    try journal.appendDone(response.response_value_fingerprint);

    const journal_bytes = try journal.encode(allocator);
    defer allocator.free(journal_bytes);
    var decoded_journal = try ApprovalProgram.Session.Journal.decode(allocator, journal_bytes);
    defer decoded_journal.deinit();
    var replay_runtime = ability.Runtime.init(allocator);
    defer replay_runtime.deinit();
    var replay_session = try ApprovalProgram.Session.start(&replay_runtime, .{});
    defer replay_session.deinit();
    _ = try replay_session.next();
    var replayer = decoded_journal.replayer();
    defer replayer.deinit();
    const replay_value = try replayer.expectCurrentValue(try replay_session.current(), i32);
    const replay_request = switch (try replay_session.current()) {
        .request => |value| value,
        .after => return error.UnexpectedAfter,
        .none => return error.ExpectedRequest,
    };
    var replay_envelope = try ApprovalProgram.Exchange.RequestEnvelope.fromRequest(allocator, replay_request, .{});
    defer replay_envelope.deinit();
    var replay_response = try ApprovalProgram.Exchange.ResponseEnvelope.@"resume"(allocator, replay_envelope, replay_value);
    defer replay_response.deinit();
    try ApprovalProgram.Exchange.applyResponse(&replay_session, replay_response, .{});
    var replay_result = switch (try replay_session.next()) {
        .done => |done| done,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer replay_result.deinit();
    try replayer.expectDone(response.response_value_fingerprint);

    try writer.print("request_envelope_fingerprint={x}\n", .{decoded_request.fingerprint});
    try writer.print("response_envelope_fingerprint={x}\n", .{response.fingerprint});
    try writer.print("final_result={d}\n", .{result.value});
    try writer.print("replayed_result={d}\n", .{replay_result.value});
    try writer.print("journal_fingerprint={x}\n", .{try decoded_journal.fingerprint()});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
