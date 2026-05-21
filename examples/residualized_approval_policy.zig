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

const PolicyProtocol = boundary.ir.schema.Protocol(.{
    .label = "policy",
    .ops = .{
        boundary.ir.schema.transform("check", []const u8, i32),
    },
});

const CheckPolicy = PolicyProtocol.operation("check", .{});

const approval_semantic_spec = blk: {
    const semantic = boundary.ir.builder.semantic;
    const RequestApproval = ApprovalRows.op("request");

    break :blk .{
        .label = "residualized-approval-policy",
        .ir_hash = 0x7265736170706f6c,
        .entry = "run",
        .requirements = &.{ApprovalRows.requirement},
        .ops = &ApprovalRows.ops,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = semantic.span(0, 1),
            .params = .{},
            .locals = .{
                semantic.local("request_payload", []const u8),
                semantic.local("approval_decision", i32),
            },
            .result = i32,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    semantic.constString("request_payload", "deploy-prod"),
                    semantic.call(RequestApproval, .{
                        .dst = "approval_decision",
                        .payload = "request_payload",
                        .label = "approval.request",
                    }),
                },
                .terminator = semantic.returnValue("approval_decision"),
            }},
        }},
    };
};

const approval_compiled = boundary.ir.builder.semantic.finish(approval_semantic_spec) catch |err|
    @compileError("invalid residualized approval policy semantic plan: " ++ @errorName(err));

const ApprovalBody = struct {
    pub const site_metadata = approval_compiled.site_metadata;
    pub const compiled_plan = approval_compiled.plan;
};

const ApprovalProgram = boundary.program("residualized-approval-policy", ApprovalHandlers, ApprovalBody);
const ApprovalRequest = ApprovalProgram.protocol.operationSite("approval", "request", 0);

const DynamicApprovalPolicyMapper = struct {
    pub fn @"resume"(decision: i32) ApprovalProgram.Handler.SourceOutcome(ApprovalRequest) {
        return ApprovalProgram.Handler.@"resume"(ApprovalRequest, @as(ApprovalRequest.Resume, decision));
    }
};

const DynamicApprovalViaPolicy = ApprovalProgram.Morphism(.{
    .source = ApprovalRequest,
    .target = CheckPolicy,
    .Mapper = DynamicApprovalPolicyMapper,
});

const ResidualApprovalViaPolicy = ApprovalProgram.ResidualMorphism(.{
    .source = ApprovalRequest,
    .target = CheckPolicy,
    .payload = boundary.ir.expr.identity(),
    .response = ApprovalProgram.ResidualResponse.resumeIdentity(),
    .label = "approval.request-as-policy.check",
});

const ResidualProgram = ApprovalProgram.residualize(.{
    .label = "approval-as-policy",
    .morphisms = .{ResidualApprovalViaPolicy},
});

const ResidualPolicySite = ResidualProgram.protocol.operationSite("policy", "check", 0);

const Host = struct {
    allow: bool,
};

const DynamicApprovalHandler = struct {
    pub fn handle(_: *Host, request: anytype, _: ApprovalProgram.Handler.Control) !ApprovalProgram.Handler.MorphismOutcome(DynamicApprovalViaPolicy) {
        return ApprovalProgram.Handler.reinterpret(DynamicApprovalViaPolicy, try request.payload());
    }
};

const DynamicPolicyHandler = struct {
    pub fn handle(host: *Host, request: anytype) !ApprovalProgram.Handler.TargetResponse(CheckPolicy) {
        _ = try request.payload();
        return .{ .@"resume" = if (host.allow) 1 else 0 };
    }
};

const ResidualPolicyHandler = struct {
    pub fn handle(host: *Host, request: anytype, _: ResidualProgram.Handler.Control) !ResidualProgram.Handler.Outcome(ResidualPolicySite) {
        _ = try request.payload();
        return ResidualProgram.Handler.@"resume"(ResidualPolicySite, @as(i32, if (host.allow) 1 else 0));
    }
};

const SourceOnly = ApprovalProgram.Interpreter(.{
    ApprovalProgram.Handler.morphism(DynamicApprovalViaPolicy, DynamicApprovalHandler.handle),
});

const DynamicWithPolicy = ApprovalProgram.Interpreter(.{
    ApprovalProgram.Handler.morphism(DynamicApprovalViaPolicy, DynamicApprovalHandler.handle),
    ApprovalProgram.Handler.protocolOperation(CheckPolicy, DynamicPolicyHandler.handle),
});

const ResidualWithPolicy = ResidualProgram.Interpreter(.{
    ResidualProgram.Handler.operation(ResidualPolicySite, ResidualPolicyHandler.handle),
});

fn expectDoneValue(result: anytype) !i32 {
    return switch (result) {
        .done => |done_value| value: {
            var done = done_value;
            defer done.deinit();
            break :value done.value;
        },
        .suspended => error.UnexpectedSuspend,
        .unhandled => error.UnexpectedUnhandled,
        .reinterpreted => error.UnexpectedReinterpreted,
    };
}

fn dynamicValue(runtime: *boundary.Runtime, allow: bool) !i32 {
    var host = Host{ .allow = allow };
    return expectDoneValue(try DynamicWithPolicy.run(runtime, .{}, &host, .{}));
}

fn residualValue(runtime: *boundary.Runtime, allow: bool) !i32 {
    var host = Host{ .allow = allow };
    return expectDoneValue(try ResidualWithPolicy.run(runtime, .{}, &host, .{}));
}

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();

    SourceOnly.assertReinterprets(ApprovalRequest, CheckPolicy);
    DynamicWithPolicy.assertEliminates(ApprovalProgram);
    ResidualWithPolicy.assertCoversAll();

    var inspect_host = Host{ .allow = true };
    var source_only = try SourceOnly.run(&runtime, .{}, &inspect_host, .{});
    switch (source_only) {
        .reinterpreted => |*request| {
            defer request.deinit();
            try writer.print("source_request_fingerprint={x}\n", .{request.source_request_fingerprint});
            try writer.print("target_protocol_op_fingerprint={x}\n", .{request.target_protocol_op_fingerprint});
            try writer.print("target_payload={s}\n", .{try request.payload([]const u8)});
        },
        else => return error.ExpectedReinterpreted,
    }

    const allow = true;
    const deny = false;
    const allow_dynamic = try dynamicValue(&runtime, allow);
    const allow_residual = try residualValue(&runtime, allow);
    const deny_dynamic = try dynamicValue(&runtime, deny);
    const deny_residual = try residualValue(&runtime, deny);
    if (allow_dynamic != allow_residual or deny_dynamic != deny_residual) return error.ResidualMismatch;

    var residual_session = try ResidualProgram.Session.start(&runtime, .{});
    defer residual_session.deinit();
    const residual_request = switch (try residual_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedResidualRequest,
        .after => return error.UnexpectedAfter,
    };
    const mapped = ResidualProgram.mapResidualTrace(residual_request.trace()) orelse return error.ExpectedResidualSourceMap;
    try residual_session.@"resume"(residual_request, @as(i32, 1));
    var session_result = switch (try residual_session.next()) {
        .done => |done| done,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer session_result.deinit();

    try writer.print("source_site_fingerprint={x}\n", .{ApprovalRequest.fingerprint});
    try writer.print("residual_site_fingerprint={x}\n", .{ResidualPolicySite.fingerprint});
    try writer.print("mapped_source_site_fingerprint={x}\n", .{mapped.source_site_fingerprint});
    try writer.print("residualization_fingerprint={x}\n", .{ResidualProgram.residualization_fingerprint});
    try writer.print("eliminated_source_sites={d}\n", .{ResidualProgram.effect_row.eliminated_source_sites});
    try writer.print("emitted_target_protocol_ops={d}\n", .{ResidualProgram.effect_row.emitted_target_protocol_ops});
    try writer.print("allow_dynamic={d}\n", .{allow_dynamic});
    try writer.print("allow_residual={d}\n", .{allow_residual});
    try writer.print("deny_dynamic={d}\n", .{deny_dynamic});
    try writer.print("deny_residual={d}\n", .{deny_residual});
    try writer.print("session_result={d}\n", .{session_result.value});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
