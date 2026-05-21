// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions
const boundary = @import("boundary");
const std = @import("std");

const ApprovalHandlers = struct {};

const ApprovalProtocol = boundary.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{
        boundary.ir.schema.choice("request", []const u8, i32),
    },
});

const ApprovalRows = ApprovalProtocol.Rows(ApprovalHandlers, .{
    .requirement_index = 0,
    .first_op = 0,
});

const approval_semantic_spec = blk: {
    const semantic = boundary.ir.builder.semantic;
    const RequestOp = ApprovalRows.op("request");

    break :blk .{
        .label = "continuation-branching",
        .ir_hash = 0x63617073756c6501,
        .entry = "run",
        .requirements = &.{ApprovalRows.requirement},
        .ops = &ApprovalRows.ops,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = semantic.span(0, 1),
            .params = .{},
            .locals = .{
                semantic.local("request_payload", []const u8),
                semantic.local("approval_resume", i32),
                semantic.local("approved_result", []const u8),
            },
            .result = []const u8,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    semantic.constString("request_payload", "publish-request"),
                    semantic.call(RequestOp, .{
                        .dst = "approval_resume",
                        .payload = "request_payload",
                        .label = "approval.request",
                    }),
                    semantic.constString("approved_result", "approved"),
                },
                .terminator = semantic.returnValue("approved_result"),
            }},
        }},
    };
};

const approval_compiled = boundary.ir.builder.semantic.finish(approval_semantic_spec) catch |err|
    @compileError("invalid continuation-branching semantic plan: " ++ @errorName(err));

const ApprovalBody = struct {
    pub const site_metadata = approval_compiled.site_metadata;
    pub const compiled_plan = approval_compiled.plan;
};

const ApprovalProgram = boundary.program("continuation-branching", ApprovalHandlers, ApprovalBody);
const RequestSite = ApprovalProgram.protocol.operationSite("approval", "request", 0);

fn doneResult(session: *ApprovalProgram.Session) !ApprovalProgram.Result {
    return switch (try session.next()) {
        .done => |done| done,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
}

fn currentRequest(session: *ApprovalProgram.Session) !ApprovalProgram.Session.Request {
    return switch (try session.current()) {
        .request => |request| request,
        .after => error.UnexpectedAfter,
        .none => error.ExpectedRequest,
    };
}

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();

    var seed = try ApprovalProgram.Session.start(&runtime, .{});
    defer seed.deinit();

    const request = switch (try seed.next()) {
        .request => |yielded| yielded,
        .after => return error.UnexpectedAfter,
        .done => return error.UnexpectedDone,
    };
    const typed_request = try request.as(RequestSite);
    const payload = try typed_request.payload();

    var capsule = try seed.capture(allocator);
    defer capsule.deinit();

    var approved_branch = try ApprovalProgram.Session.restore(&runtime, .{}, &capsule);
    defer approved_branch.deinit();
    const approved_request = try currentRequest(&approved_branch);
    try approved_branch.resumeTyped(try approved_request.as(RequestSite), @as(RequestSite.Resume, 1));
    var approved_result = try doneResult(&approved_branch);
    defer approved_result.deinit();

    var denied_branch = try ApprovalProgram.Session.restore(&runtime, .{}, &capsule);
    defer denied_branch.deinit();
    const denied_request = try currentRequest(&denied_branch);
    try denied_branch.returnNowTyped(try denied_request.as(RequestSite), @as(RequestSite.Result, "denied"));
    var denied_result = try doneResult(&denied_branch);
    defer denied_result.deinit();

    var proof_branch = try ApprovalProgram.Session.restore(&runtime, .{}, &capsule);
    defer proof_branch.deinit();
    const proof_request = try currentRequest(&proof_branch);
    const reused = approved_request.fingerprint() == request.fingerprint() and
        denied_request.fingerprint() == request.fingerprint() and
        proof_request.fingerprint() == request.fingerprint();

    try writer.print("capsule_fingerprint={x}\n", .{capsule.fingerprint()});
    try writer.print("request_fingerprint={x}\n", .{request.fingerprint()});
    try writer.print("payload={s}\n", .{payload});
    try writer.print("approved_result={s}\n", .{approved_result.value});
    try writer.print("denied_result={s}\n", .{denied_result.value});
    try writer.print("capsule_reused={any}\n", .{reused});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
