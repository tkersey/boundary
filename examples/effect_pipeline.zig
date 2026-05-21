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

const RulesProtocol = boundary.ir.schema.Protocol(.{
    .label = "rules",
    .ops = .{
        boundary.ir.schema.transform("lookup", []const u8, i32),
    },
});

const LookupRules = RulesProtocol.operation("lookup", .{});

const approval_semantic_spec = blk: {
    const semantic = boundary.ir.builder.semantic;
    const RequestApproval = ApprovalRows.op("request");

    break :blk .{
        .label = "effect-pipeline-source",
        .ir_hash = 0x706970656c696e65,
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
    @compileError("invalid effect pipeline semantic plan: " ++ @errorName(err));

const ApprovalBody = struct {
    pub const site_metadata = approval_compiled.site_metadata;
    pub const compiled_plan = approval_compiled.plan;
};

const ApprovalProgram = boundary.program("effect-pipeline-source", ApprovalHandlers, ApprovalBody);
const ApprovalRequest = ApprovalProgram.protocol.operationSite("approval", "request", 0);

const ApprovalPolicyMapper = struct {
    pub fn @"resume"(decision: i32) ApprovalProgram.Handler.SourceOutcome(ApprovalRequest) {
        return ApprovalProgram.Handler.@"resume"(ApprovalRequest, decision);
    }
};

const ApprovalViaPolicy = ApprovalProgram.Morphism(.{
    .source = ApprovalRequest,
    .target = CheckPolicy,
    .Mapper = ApprovalPolicyMapper,
});

const ResidualApprovalViaPolicy = ApprovalProgram.ResidualMorphism(.{
    .source = ApprovalRequest,
    .target = CheckPolicy,
    .payload = boundary.ir.expr.identity(),
    .response = ApprovalProgram.ResidualResponse.resumeIdentity(),
    .label = "approval.request-as-policy.check",
});

const Pipeline = ApprovalProgram.Pipeline(.{
    .label = "approval-policy-pipeline",
    .residualize = .{ResidualApprovalViaPolicy},
    .goal = ApprovalProgram.pipeline.Goal.allowResiduals(),
    .strategy = .prefer_residualization,
});

const ResidualPolicySite = Pipeline.Residual.protocol.operationSite("policy", "check", 0);

const PolicyRulesMapper = struct {
    pub fn @"resume"(decision: i32) Pipeline.Residual.Handler.SourceOutcome(ResidualPolicySite) {
        return Pipeline.Residual.Handler.@"resume"(ResidualPolicySite, decision);
    }
};

const PolicyViaRules = Pipeline.Residual.Morphism(.{
    .source = ResidualPolicySite,
    .target = LookupRules,
    .Mapper = PolicyRulesMapper,
});

const Host = struct {
    allow: bool,
};

const SourceApprovalHandler = struct {
    pub fn handle(_: *Host, request: anytype, _: ApprovalProgram.Handler.Control) !ApprovalProgram.Handler.MorphismOutcome(ApprovalViaPolicy) {
        return ApprovalProgram.Handler.reinterpret(ApprovalViaPolicy, try request.payload());
    }
};

const SourcePolicyHandler = struct {
    pub fn handle(host: *Host, request: anytype) !ApprovalProgram.Handler.TargetResponse(CheckPolicy) {
        _ = try request.payload();
        return .{ .@"resume" = if (host.allow) 1 else 0 };
    }
};

const ResidualPolicyHandler = struct {
    pub fn handle(_: *Host, request: anytype, _: Pipeline.Residual.Handler.Control) !Pipeline.Residual.Handler.MorphismOutcome(PolicyViaRules) {
        return Pipeline.Residual.Handler.reinterpret(PolicyViaRules, try request.payload());
    }
};

const RulesHandler = struct {
    pub fn handle(host: *Host, request: anytype) !Pipeline.Residual.Handler.TargetResponse(LookupRules) {
        _ = try request.payload();
        return .{ .@"resume" = if (host.allow) 1 else 0 };
    }
};

const SourceDynamic = ApprovalProgram.Interpreter(.{
    ApprovalProgram.Handler.morphism(ApprovalViaPolicy, SourceApprovalHandler.handle),
    ApprovalProgram.Handler.protocolOperation(CheckPolicy, SourcePolicyHandler.handle),
});

const PipelineFull = Pipeline.Interpreter(.{
    Pipeline.Residual.Handler.morphism(PolicyViaRules, ResidualPolicyHandler.handle),
    Pipeline.Residual.Handler.protocolOperation(LookupRules, RulesHandler.handle),
});

const PipelinePartial = Pipeline.Interpreter(.{
    Pipeline.Residual.Handler.morphism(PolicyViaRules, ResidualPolicyHandler.handle),
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

fn sourceDynamicValue(runtime: *boundary.Runtime, allow: bool) !i32 {
    var host = Host{ .allow = allow };
    return expectDoneValue(try SourceDynamic.run(runtime, .{}, &host, .{}));
}

fn pipelineValue(runtime: *boundary.Runtime, allow: bool) !i32 {
    var host = Host{ .allow = allow };
    return expectDoneValue(try PipelineFull.run(runtime, .{}, &host, .{}));
}

fn partialPipelineValue(runtime: *boundary.Runtime, writer: anytype) !i32 {
    var host = Host{ .allow = true };
    var partial = try PipelinePartial.run(runtime, .{}, &host, .{});
    switch (partial) {
        .reinterpreted => |*request| {
            defer request.deinit();
            const route = Pipeline.sourceForTargetProtocolRequest(request.*) orelse return error.ExpectedTargetMap;
            try writer.print("partial_target_protocol_op={x}\n", .{request.target_protocol_op_fingerprint});
            try writer.print("partial_source_site={x}\n", .{route.source_site_fingerprint.?});
            try writer.print("partial_capsule={x}\n", .{request.source_capsule_fingerprint});

            var restored = try Pipeline.Residual.Session.restore(runtime, .{}, &request.capsule);
            defer restored.deinit();
            const current = switch (try restored.current()) {
                .request => |value| value,
                .after => return error.UnexpectedAfter,
                .none => return error.ExpectedResidualRequest,
            };
            try restored.@"resume"(current, @as(i32, 1));
            var done = switch (try restored.next()) {
                .done => |value| value,
                .request => return error.UnexpectedRequest,
                .after => return error.UnexpectedAfter,
            };
            defer done.deinit();
            return done.value;
        },
        else => return error.ExpectedReinterpreted,
    }
}

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();

    Pipeline.assertValid();
    try Pipeline.certificate.check();
    SourceDynamic.assertEliminates(ApprovalProgram);
    PipelineFull.assertEliminates(Pipeline.Residual);

    const allow = true;
    const deny = false;
    const allow_dynamic = try sourceDynamicValue(&runtime, allow);
    const allow_pipeline = try pipelineValue(&runtime, allow);
    const deny_dynamic = try sourceDynamicValue(&runtime, deny);
    const deny_pipeline = try pipelineValue(&runtime, deny);
    if (allow_dynamic != allow_pipeline or deny_dynamic != deny_pipeline) return error.PipelineMismatch;

    var residual_session = try Pipeline.Residual.Session.start(&runtime, .{});
    defer residual_session.deinit();
    const residual_request = switch (try residual_session.next()) {
        .request => |request| request,
        .done => return error.ExpectedResidualRequest,
        .after => return error.UnexpectedAfter,
    };
    const mapped = Pipeline.mapResidualTrace(residual_request.trace()) orelse return error.ExpectedResidualMap;
    try residual_session.@"resume"(residual_request, @as(i32, 1));
    var session_result = switch (try residual_session.next()) {
        .done => |done| done,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer session_result.deinit();

    const partial_value = try partialPipelineValue(&runtime, writer);

    try writer.print("pipeline_fingerprint={x}\n", .{Pipeline.fingerprint});
    try writer.print("pipeline_fingerprint_version={d}\n", .{Pipeline.fingerprint_version});
    try writer.print("source_sites={d}\n", .{Pipeline.effect_row.source_operation_sites});
    try writer.print("residualized_sites={d}\n", .{Pipeline.effect_row.residualized_sites});
    try writer.print("emitted_protocol_ops={d}\n", .{Pipeline.effect_row.emitted_protocol_operations});
    try writer.print("residual_effects={d}\n", .{Pipeline.effect_row.exposed_residual_operations});
    try writer.print("source_site_fingerprint={x}\n", .{ApprovalRequest.fingerprint});
    try writer.print("residual_site_fingerprint={x}\n", .{ResidualPolicySite.fingerprint});
    try writer.print("mapped_source_site_fingerprint={x}\n", .{mapped.source_site_fingerprint});
    try writer.print("rules_protocol_op_fingerprint={x}\n", .{LookupRules.fingerprint});
    try writer.print("allow_dynamic={d}\n", .{allow_dynamic});
    try writer.print("allow_pipeline={d}\n", .{allow_pipeline});
    try writer.print("deny_dynamic={d}\n", .{deny_dynamic});
    try writer.print("deny_pipeline={d}\n", .{deny_pipeline});
    try writer.print("session_result={d}\n", .{session_result.value});
    try writer.print("partial_result={d}\n", .{partial_value});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
