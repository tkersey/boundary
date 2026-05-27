// zlinter-disable declaration_naming field_ordering require_doc_comment no_hidden_allocations no_inferred_error_unions
const boundary = @import("boundary");
const std = @import("std");

const RootHandlers = struct {};
const ProviderHandlers = struct {};
const semantic = boundary.ir.builder.semantic;

const ApprovalProtocol = boundary.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{boundary.ir.schema.transform("request", []const u8, i32)},
});
const ApprovalRows = ApprovalProtocol.Rows(RootHandlers, .{ .requirement_index = 0, .first_op = 0 });
const ApprovalRequestOp = ApprovalRows.op("request");

const root_compiled = semantic.finish(.{
    .label = "boundary-normalization-nested-root",
    .ir_hash = 0x6e6e726f6f740001,
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
}) catch |err| @compileError("invalid normalization nested root: " ++ @errorName(err));

const RootBody = struct {
    pub const site_metadata = root_compiled.site_metadata;
    pub const compiled_plan = root_compiled.plan;
};
const RootProgram = boundary.program("boundary-normalization-nested-root", RootHandlers, RootBody);
const ApprovalRequest = RootProgram.protocol.operationSite("approval", "request", 0);

const PolicyProtocol = boundary.ir.schema.Protocol(.{
    .label = "policy",
    .ops = .{boundary.ir.schema.transform("check", []const u8, i32)},
});
const PolicyRows = PolicyProtocol.Rows(ProviderHandlers, .{ .requirement_index = 0, .first_op = 0 });
const PolicyCheckOp = PolicyRows.op("check");

const approval_provider_compiled = semantic.finish(.{
    .label = "boundary-normalization-nested-approval-provider",
    .ir_hash = 0x6e6e617070720001,
    .entry = "run",
    .requirements = &.{PolicyRows.requirement},
    .ops = &PolicyRows.ops,
    .functions = .{.{
        .symbol_name = "run",
        .requirements = semantic.span(0, 1),
        .params = .{semantic.param("payload", []const u8)},
        .locals = .{semantic.local("decision", i32)},
        .result = i32,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{semantic.call(PolicyCheckOp, .{ .dst = "decision", .payload = "payload", .label = "policy.check" })},
            .terminator = semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid normalization nested approval provider: " ++ @errorName(err));

const ApprovalProviderProgram = boundary.program("boundary-normalization-nested-approval-provider", ProviderHandlers, struct {
    pub const site_metadata = approval_provider_compiled.site_metadata;
    pub const compiled_plan = approval_provider_compiled.plan;
});
const PolicyCheck = ApprovalProviderProgram.protocol.operationSite("policy", "check", 0);

const policy_provider_compiled = semantic.finish(.{
    .label = "boundary-normalization-nested-policy-provider",
    .ir_hash = 0x6e6e706f6c790001,
    .entry = "run",
    .functions = .{.{
        .symbol_name = "run",
        .params = .{semantic.param("payload", []const u8)},
        .locals = .{semantic.local("decision", i32)},
        .result = i32,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{semantic.constI32("decision", 7)},
            .terminator = semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid normalization nested policy provider: " ++ @errorName(err));

const PolicyProviderProgram = boundary.program("boundary-normalization-nested-policy-provider", ProviderHandlers, struct {
    pub const compiled_plan = policy_provider_compiled.plan;
});

const residual_compiled = semantic.finish(.{
    .label = "boundary-normalization-nested-residual",
    .ir_hash = 0x6e6e657374656401,
    .entry = "run",
    .functions = .{.{
        .symbol_name = "run",
        .params = .{},
        .locals = .{semantic.local("decision", i32)},
        .result = i32,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{semantic.constI32("decision", 7)},
            .terminator = semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid normalization nested residual: " ++ @errorName(err));

const ResidualProgram = boundary.program("boundary-normalization-nested-residual", struct {}, struct {
    pub const compiled_plan = residual_compiled.plan;
});

const Closure = RootProgram.BoundaryClosure;
const Elaboration = Closure.Elaboration;
const Evidence = RootProgram.Evidence;
const root_ref = Evidence.refFor(Evidence.domains.program_plan, RootProgram.compiled_plan.hash(), .{ .label = RootProgram.contract.label });
const approval_provider_ref = Evidence.refFor(Evidence.domains.provider_manifest, 0x6e6e_5101, .{ .label = "normalization-approval-provider" });
const approval_offer_ref = Evidence.refFor(Evidence.domains.provider_offer, 0x6e6e_5102, .{ .label = "normalization-approval-offer" });
const approval_program_ref = Evidence.refFor(Evidence.domains.program_plan, ApprovalProviderProgram.compiled_plan.hash(), .{ .label = ApprovalProviderProgram.contract.label });
const policy_provider_ref = Evidence.refFor(Evidence.domains.provider_manifest, 0x6e6e_5201, .{ .label = "normalization-policy-provider" });
const policy_offer_ref = Evidence.refFor(Evidence.domains.provider_offer, 0x6e6e_5202, .{ .label = "normalization-policy-offer" });
const policy_program_ref = Evidence.refFor(Evidence.domains.program_plan, PolicyProviderProgram.compiled_plan.hash(), .{ .label = PolicyProviderProgram.contract.label });
const residual_ref = Evidence.refFor(Evidence.domains.program_plan, ResidualProgram.compiled_plan.hash(), .{ .label = ResidualProgram.contract.label });

const root_shape = Closure.EffectShape.init(.{
    .program_label = RootProgram.contract.label,
    .plan_hash = RootProgram.compiled_plan.hash(),
    .kind = .operation,
    .site_index = ApprovalRequest.index,
    .protocol_label = "approval",
    .protocol_op_fingerprint = ApprovalRequest.fingerprint,
    .expected_resume_ref = Evidence.BoundaryValueRef.init("i32", null),
});
const nested_shape = Closure.EffectShape.init(.{
    .program_label = ApprovalProviderProgram.contract.label,
    .plan_hash = ApprovalProviderProgram.compiled_plan.hash(),
    .kind = .operation,
    .site_index = PolicyCheck.index,
    .protocol_label = "policy",
    .protocol_op_fingerprint = PolicyCheck.fingerprint,
    .expected_resume_ref = Evidence.BoundaryValueRef.init("i32", null),
});
const root_plan = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk Closure.StaticTreatyPlan.init(.{
        .label = "approval.request.provider",
        .source_shape = root_shape,
        .selected_provider_ref = approval_provider_ref,
        .selected_provider_offer_ref = approval_offer_ref,
        .selected_capability_ref = approval_provider_ref,
        .selected_semantic_body = .boundary_program,
        .selected_provider_program_ref = approval_program_ref,
        .selected_provider_program_mapping_fingerprint = 0x6e6e_5301,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = 1,
        .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{nested_shape}),
    });
};
const nested_plan = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk Closure.StaticTreatyPlan.init(.{
        .label = "policy.check.provider",
        .source_shape = nested_shape,
        .selected_provider_ref = policy_provider_ref,
        .selected_provider_offer_ref = policy_offer_ref,
        .selected_capability_ref = policy_provider_ref,
        .selected_semantic_body = .boundary_program,
        .selected_provider_program_ref = policy_program_ref,
        .selected_provider_program_mapping_fingerprint = 0x6e6e_5302,
        .selected_provider_program_request_mapping_tag = "payload_to_args",
        .selected_provider_program_result_mapping_tag = "result_to_resume",
        .selected_provider_program_effect_shape_count = 0,
        .selected_provider_program_effect_shape_fingerprint = Evidence.fingerprintBoundaryEffectShapeSet(&.{}),
    });
};
const provider_programs = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk [_]Closure.ProviderProgram{ .{
        .provider_ref = approval_provider_ref,
        .program_ref = approval_program_ref,
        .provider_program_mapping_fingerprint = root_plan.selected_provider_program_mapping_fingerprint,
        .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForPlan(root_plan, .payload_to_args, .result_to_resume),
        .request_mapping = .payload_to_args,
        .result_mapping = .result_to_resume,
        .shapes = &.{nested_shape},
    }, .{
        .provider_ref = policy_provider_ref,
        .program_ref = policy_program_ref,
        .provider_program_mapping_fingerprint = nested_plan.selected_provider_program_mapping_fingerprint,
        .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForPlan(nested_plan, .payload_to_args, .result_to_resume),
        .request_mapping = .payload_to_args,
        .result_mapping = .result_to_resume,
        .effect_free = true,
    } };
};
const provider_program_links = [_]Elaboration.ProviderProgramLink{ .{
    .provider_ref = approval_provider_ref,
    .program_ref = approval_program_ref,
    .residual_program_ref = residual_ref,
    .mapping_fingerprint = root_plan.selected_provider_program_mapping_fingerprint,
    .mapping_support_fingerprint = root_plan.selected_provider_program_mapping_support_fingerprint,
    .effect_shape_ref = root_shape.evidenceRef(),
}, .{
    .provider_ref = policy_provider_ref,
    .program_ref = policy_program_ref,
    .residual_program_ref = residual_ref,
    .mapping_fingerprint = nested_plan.selected_provider_program_mapping_fingerprint,
    .mapping_support_fingerprint = nested_plan.selected_provider_program_mapping_support_fingerprint,
    .effect_shape_ref = nested_shape.evidenceRef(),
} };
const closure_graph = Closure.Graph.init("boundary-normalization-nested-graph", &.{}, &.{}, &.{});
const closure_report = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk Closure.Report.init(.{
        .graph_fingerprint = closure_graph.fingerprint,
        .root_program_refs = &.{root_ref},
        .provider_program_refs = &.{ approval_program_ref, policy_program_ref },
        .effect_shape_count = 2,
        .closed_effect_shape_count = 2,
    });
};
const closure_policy = Closure.Policy.auditOnly();
const closure_certificate = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk Closure.Certificate.init(closure_report, closure_graph, closure_policy, &.{ root_plan.evidenceRef(), nested_plan.evidenceRef() });
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
    .static_treaty_plans = &.{ root_plan, nested_plan },
    .source_program_ref = root_ref,
    .residual_program_ref = residual_ref,
    .provider_programs = provider_programs[0..],
    .provider_program_links = provider_program_links[0..],
    .policy = elaboration_policy,
};
const Target = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk Elaboration.Target.compileComptime(.{
        .label = "boundary-normalization-nested-target",
        .input = elaboration_input,
        .residual_program = ResidualProgram,
        .policy = Elaboration.Target.Policy.auditOnly(),
    });
};

fn originalValue(allocator: std.mem.Allocator) !i32 {
    var root_runtime = boundary.Runtime.init(allocator);
    defer root_runtime.deinit();
    var root_session = try RootProgram.Session.start(&root_runtime, .{});
    defer root_session.deinit();
    const approval_request = switch (try root_session.next()) {
        .request => |value| value,
        .after => return error.UnexpectedAfter,
        .done => return error.UnexpectedDone,
    };

    var approval_runtime = boundary.Runtime.init(allocator);
    defer approval_runtime.deinit();
    var approval_args = [_]boundary.ir.ProgramValue{.{ .string = "deploy-prod" }};
    var approval_session = try ApprovalProviderProgram.Session.startWithArgs(&approval_runtime, .{}, &approval_args);
    defer approval_session.deinit();
    const policy_request = switch (try approval_session.next()) {
        .request => |value| value,
        .after => return error.UnexpectedAfter,
        .done => return error.UnexpectedDone,
    };
    var policy_runtime = boundary.Runtime.init(allocator);
    defer policy_runtime.deinit();
    var policy_args = [_]boundary.ir.ProgramValue{.{ .string = "deploy-prod" }};
    var policy_result = try PolicyProviderProgram.runWithArgs(&policy_runtime, .{}, &policy_args);
    defer policy_result.deinit();

    try approval_session.@"resume"(policy_request, policy_result.value);
    var approval_done = switch (try approval_session.next()) {
        .done => |value| value,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer approval_done.deinit();

    try root_session.@"resume"(approval_request, approval_done.value);
    var root_done = switch (try root_session.next()) {
        .done => |value| value,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer root_done.deinit();
    return root_done.value;
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

    try writer.print("root_redex_fingerprint={x}\n", .{Target.NormalizationTrace.eliminated_redex_refs[0].fingerprint});
    try writer.print("nested_redex_fingerprint={x}\n", .{Target.NormalizationTrace.eliminated_redex_refs[1].fingerprint});
    try writer.print("rewrite_step_count={d}\n", .{Target.NormalizationTrace.rewrite_steps.len});
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
