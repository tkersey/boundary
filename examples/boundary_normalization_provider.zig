// zlinter-disable declaration_naming field_ordering require_doc_comment no_hidden_allocations no_inferred_error_unions
const boundary = @import("boundary");
const std = @import("std");

const SourceHandlers = struct {};
const semantic = boundary.ir.builder.semantic;

const ApprovalProtocol = boundary.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{boundary.ir.schema.transform("request", []const u8, i32)},
});
const ApprovalRows = ApprovalProtocol.Rows(SourceHandlers, .{ .requirement_index = 0, .first_op = 0 });
const ApprovalRequestOp = ApprovalRows.op("request");

const source_compiled = semantic.finish(.{
    .label = "boundary-normalization-provider-source",
    .ir_hash = 0x6e70726f76530001,
    .entry = "run",
    .requirements = &.{ApprovalRows.requirement},
    .ops = &ApprovalRows.ops,
    .functions = .{.{
        .symbol_name = "run",
        .requirements = semantic.span(0, 1),
        .params = .{},
        .locals = .{ semantic.local("payload", []const u8), semantic.local("decision", i32) },
        .result = i32,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{
                semantic.constString("payload", "deploy-prod"),
                semantic.call(ApprovalRequestOp, .{ .dst = "decision", .payload = "payload", .label = "approval.request" }),
            },
            .terminator = semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid normalization provider source: " ++ @errorName(err));

const SourceBody = struct {
    pub const site_metadata = source_compiled.site_metadata;
    pub const compiled_plan = source_compiled.plan;
};
const SourceProgram = boundary.program("boundary-normalization-provider-source", SourceHandlers, SourceBody);
const ApprovalRequest = SourceProgram.protocol.operationSite("approval", "request", 0);

const provider_compiled = semantic.finish(.{
    .label = "boundary-normalization-provider-handler",
    .ir_hash = 0x6e70726f76480001,
    .entry = "run",
    .functions = .{.{
        .symbol_name = "run",
        .params = .{semantic.param("payload", []const u8)},
        .locals = .{semantic.local("decision", i32)},
        .result = i32,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{semantic.constI32("decision", 1)},
            .terminator = semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid normalization provider handler: " ++ @errorName(err));

const ProviderProgram = boundary.program("boundary-normalization-provider-handler", struct {}, struct {
    pub const compiled_plan = provider_compiled.plan;
});

const residual_compiled = semantic.finish(.{
    .label = "boundary-normalization-provider-residual",
    .ir_hash = 0x6e70726f76696401,
    .entry = "run",
    .functions = .{.{
        .symbol_name = "run",
        .params = .{},
        .locals = .{semantic.local("decision", i32)},
        .result = i32,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{semantic.constI32("decision", 1)},
            .terminator = semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid normalization provider residual: " ++ @errorName(err));

const ResidualProgram = boundary.program("boundary-normalization-provider-residual", struct {}, struct {
    pub const compiled_plan = residual_compiled.plan;
});

const Closure = SourceProgram.BoundaryClosure;
const Elaboration = Closure.Elaboration;
const Evidence = SourceProgram.Evidence;
const source_ref = Evidence.refFor(Evidence.domains.program_plan, SourceProgram.compiled_plan.hash(), .{ .label = SourceProgram.contract.label });
const provider_ref = Evidence.refFor(Evidence.domains.provider_manifest, 0x6e70_5101, .{ .label = "normalization-approval-provider" });
const provider_offer_ref = Evidence.refFor(Evidence.domains.provider_offer, 0x6e70_5102, .{ .label = "normalization-approval-offer" });
const provider_program_ref = Evidence.refFor(Evidence.domains.program_plan, ProviderProgram.compiled_plan.hash(), .{ .label = ProviderProgram.contract.label });
const residual_ref = Evidence.refFor(Evidence.domains.program_plan, ResidualProgram.compiled_plan.hash(), .{ .label = ResidualProgram.contract.label });
const source_shape = Closure.EffectShape.init(.{
    .program_label = SourceProgram.contract.label,
    .plan_hash = SourceProgram.compiled_plan.hash(),
    .kind = .operation,
    .site_index = ApprovalRequest.index,
    .protocol_label = "approval",
    .protocol_op_fingerprint = ApprovalRequest.fingerprint,
    .expected_resume_ref = Evidence.BoundaryValueRef.init("i32", null),
});
const static_plan = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk Closure.StaticTreatyPlan.init(.{
        .label = "approval.request.provider",
        .source_shape = source_shape,
        .selected_provider_ref = provider_ref,
        .selected_provider_offer_ref = provider_offer_ref,
        .selected_capability_ref = provider_ref,
        .selected_semantic_body = .boundary_program,
        .selected_provider_program_ref = provider_program_ref,
        .selected_provider_program_mapping_fingerprint = 0x6e70_5201,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = 0,
        .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{}),
    });
};
const provider_programs = [_]Closure.ProviderProgram{.{
    .provider_ref = provider_ref,
    .program_ref = provider_program_ref,
    .provider_program_mapping_fingerprint = static_plan.selected_provider_program_mapping_fingerprint,
    .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForPlan(static_plan, .payload_to_args, .result_to_resume),
    .request_mapping = .payload_to_args,
    .result_mapping = .result_to_resume,
    .effect_free = true,
}};
const provider_program_links = [_]Elaboration.ProviderProgramLink{.{
    .provider_ref = provider_ref,
    .program_ref = provider_program_ref,
    .residual_program_ref = residual_ref,
    .mapping_fingerprint = static_plan.selected_provider_program_mapping_fingerprint,
    .mapping_support_fingerprint = static_plan.selected_provider_program_mapping_support_fingerprint,
    .effect_shape_ref = source_shape.evidenceRef(),
}};
const closure_graph = Closure.Graph.init("boundary-normalization-provider-graph", &.{}, &.{}, &.{});
const closure_report = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk Closure.Report.init(.{
        .graph_fingerprint = closure_graph.fingerprint,
        .root_program_refs = &.{source_ref},
        .provider_program_refs = &.{provider_program_ref},
        .effect_shape_count = 1,
        .closed_effect_shape_count = 1,
    });
};
const closure_policy = Closure.Policy.auditOnly();
const closure_certificate = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk Closure.Certificate.init(closure_report, closure_graph, closure_policy, &.{static_plan.evidenceRef()});
};
const elaboration_policy = blk: {
    var policy = Elaboration.Policy.auditOnly();
    policy.closure_policy = closure_policy;
    break :blk policy;
};
const elaboration_input = Elaboration.Input{
    .closure_graph = closure_graph,
    .closure_report = closure_report,
    .closure_certificate = closure_certificate,
    .static_treaty_plans = &.{static_plan},
    .source_program_ref = source_ref,
    .residual_program_ref = residual_ref,
    .provider_programs = provider_programs[0..],
    .provider_program_links = provider_program_links[0..],
    .policy = elaboration_policy,
};
const Target = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk Elaboration.Target.compileComptime(.{
        .label = "boundary-normalization-provider-target",
        .input = elaboration_input,
        .residual_program = ResidualProgram,
        .policy = Elaboration.Target.Policy.auditOnly(),
    });
};

fn originalValue(allocator: std.mem.Allocator) !i32 {
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var session = try SourceProgram.Session.start(&runtime, .{});
    defer session.deinit();
    const request = switch (try session.next()) {
        .request => |value| value,
        .after => return error.UnexpectedAfter,
        .done => return error.UnexpectedDone,
    };
    try session.@"resume"(request, @as(i32, 1));
    var done = switch (try session.next()) {
        .done => |value| value,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer done.deinit();
    return done.value;
}

fn residualValue(allocator: std.mem.Allocator) !i32 {
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var result = try ResidualProgram.run(&runtime, ResidualProgram.Handlers{});
    defer result.deinit();
    return result.value;
}

pub fn run(writer: anytype) !void {
    Target.assertNormalForm(.strict_closed);
    Target.assertWorldSurfaceReady();
    Target.assertNoSearchHotPath();

    const original = try originalValue(std.heap.page_allocator);
    const residual = try residualValue(std.heap.page_allocator);
    if (original != residual) return error.NormalizationAgreementMismatch;

    try writer.print("normalization_certificate_fingerprint={x}\n", .{Target.NormalizationCertificate.certificate_fingerprint});
    try writer.print("rewrite_step_fingerprint={x}\n", .{Target.NormalizationTrace.rewrite_steps[0].fingerprint});
    try writer.print("linked_provider_route_count={d}\n", .{Target.EffectRow.linked_provider_programs});
    try writer.print("generated_program_plan_hash={x}\n", .{Target.Program.compiled_plan.hash()});
    try writer.print("final_result={d}\n", .{residual});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
