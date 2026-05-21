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
        .label = "interpreter-branching",
        .ir_hash = 0x68616e646c657201,
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
    @compileError("invalid interpreter-branching semantic plan: " ++ @errorName(err));

const ApprovalBody = struct {
    pub const site_metadata = approval_compiled.site_metadata;
    pub const compiled_plan = approval_compiled.plan;
};

const ApprovalProgram = boundary.program("interpreter-branching", ApprovalHandlers, ApprovalBody);
const RequestSite = ApprovalProgram.protocol.operationSite("approval", "request", 0);

const BranchHost = struct {
    allocator: std.mem.Allocator,
    payload: []const u8 = "",
    request_fingerprint: u64 = 0,
    captured: ?ApprovalProgram.Session.Capsule = null,
};

fn captureRequest(host: *BranchHost, request: anytype, control: ApprovalProgram.Handler.Control) !ApprovalProgram.Handler.Outcome(RequestSite) {
    host.payload = try request.payload();
    host.request_fingerprint = try control.requestFingerprint();
    host.captured = try control.capture(host.allocator);
    return ApprovalProgram.Handler.@"resume"(RequestSite, @as(RequestSite.Resume, 1));
}

fn approveRequest(_: *BranchHost, request: anytype, _: ApprovalProgram.Handler.Control) !ApprovalProgram.Handler.Outcome(RequestSite) {
    _ = try request.payload();
    return ApprovalProgram.Handler.@"resume"(RequestSite, @as(RequestSite.Resume, 1));
}

fn denyRequest(_: *BranchHost, request: anytype, _: ApprovalProgram.Handler.Control) !ApprovalProgram.Handler.Outcome(RequestSite) {
    _ = try request.payload();
    return ApprovalProgram.Handler.returnNow(RequestSite, @as(RequestSite.Result, "denied"));
}

const CaptureAndApproveInterpreter = ApprovalProgram.Interpreter(.{
    ApprovalProgram.Handler.operation(RequestSite, captureRequest),
});

const ApproveInterpreter = ApprovalProgram.Interpreter(.{
    ApprovalProgram.Handler.operation(RequestSite, approveRequest),
});

const DenyInterpreter = ApprovalProgram.Interpreter(.{
    ApprovalProgram.Handler.operation(RequestSite, denyRequest),
});

fn expectDone(result: anytype) !ApprovalProgram.Result {
    return switch (result) {
        .done => |done| done,
        .suspended => return error.UnexpectedSuspend,
        .unhandled => return error.UnexpectedUnhandled,
        .reinterpreted => return error.UnexpectedReinterpreted,
    };
}

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();

    var host = BranchHost{ .allocator = allocator };
    var approved_result = switch (try CaptureAndApproveInterpreter.run(&runtime, .{}, &host, .{})) {
        .done => |value| value,
        .suspended => return error.UnexpectedSuspend,
        .unhandled => return error.UnexpectedUnhandled,
        .reinterpreted => return error.UnexpectedReinterpreted,
    };
    defer approved_result.deinit();

    const captured = &(host.captured orelse return error.ExpectedRequest);
    defer host.captured.?.deinit();

    var approved_branch_result = try expectDone(try ApproveInterpreter.restore(&runtime, .{}, &host, captured, .{}));
    defer approved_branch_result.deinit();

    var denied_result = try expectDone(try DenyInterpreter.restore(&runtime, .{}, &host, captured, .{}));
    defer denied_result.deinit();

    try writer.print("request_payload={s}\n", .{host.payload});
    try writer.print("request_fingerprint={x}\n", .{host.request_fingerprint});
    try writer.print("captured_capsule_fingerprint={x}\n", .{captured.fingerprint()});
    try writer.print("initial_result={s}\n", .{approved_result.value});
    try writer.print("approved_branch_result={s}\n", .{approved_branch_result.value});
    try writer.print("denied_result={s}\n", .{denied_result.value});
    try writer.print("capsule_reused=true\n", .{});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
