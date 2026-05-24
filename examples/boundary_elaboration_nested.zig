// zlinter-disable declaration_naming field_ordering require_doc_comment no_hidden_allocations no_inferred_error_unions
const boundary = @import("boundary");
const std = @import("std");

const RootHandlers = struct {};
const ProviderHandlers = struct {
    payload: []const u8 = "",
};
const semantic = boundary.ir.builder.semantic;

const ApprovalProtocol = boundary.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{boundary.ir.schema.transform("request", []const u8, i32)},
});
const ApprovalRows = ApprovalProtocol.Rows(RootHandlers, .{ .requirement_index = 0, .first_op = 0 });
const ApprovalRequestOp = ApprovalRows.op("request");

const root_compiled = semantic.finish(.{
    .label = "boundary-elaboration-nested-root",
    .ir_hash = 0x656c6e65737201,
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
}) catch |err| @compileError("invalid nested elaboration root: " ++ @errorName(err));

const RootBody = struct {
    pub const site_metadata = root_compiled.site_metadata;
    pub const compiled_plan = root_compiled.plan;
};
const RootProgram = boundary.program("boundary-elaboration-nested-root", RootHandlers, RootBody);
const ApprovalRequest = RootProgram.protocol.operationSite("approval", "request", 0);

const PolicyProtocol = boundary.ir.schema.Protocol(.{
    .label = "policy",
    .ops = .{boundary.ir.schema.transform("check", []const u8, i32)},
});
const PolicyRows = PolicyProtocol.Rows(ProviderHandlers, .{ .requirement_index = 0, .first_op = 0 });
const PolicyCheckOp = PolicyRows.op("check");

const approval_provider_compiled = semantic.finish(.{
    .label = "boundary-elaboration-nested-approval-provider",
    .ir_hash = 0x656c6e61707001,
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
}) catch |err| @compileError("invalid nested elaboration approval provider: " ++ @errorName(err));

const ApprovalProviderBody = struct {
    pub const site_metadata = approval_provider_compiled.site_metadata;
    pub const compiled_plan = approval_provider_compiled.plan;

    pub fn encodeArgs(handlers: ProviderHandlers) struct { []const u8 } {
        return .{handlers.payload};
    }
};
const ApprovalProviderProgram = boundary.program("boundary-elaboration-nested-approval-provider", ProviderHandlers, ApprovalProviderBody);
const PolicyCheck = ApprovalProviderProgram.protocol.operationSite("policy", "check", 0);

const policy_provider_compiled = semantic.finish(.{
    .label = "boundary-elaboration-nested-policy-provider",
    .ir_hash = 0x656c6e706f6c01,
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
}) catch |err| @compileError("invalid nested elaboration policy provider: " ++ @errorName(err));

const PolicyProviderProgram = boundary.program("boundary-elaboration-nested-policy-provider", ProviderHandlers, struct {
    pub const compiled_plan = policy_provider_compiled.plan;

    pub fn encodeArgs(handlers: ProviderHandlers) struct { []const u8 } {
        return .{handlers.payload};
    }
});

const residual_compiled = semantic.finish(.{
    .label = "boundary-elaboration-nested-residual",
    .ir_hash = 0x656c6e72657301,
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
}) catch |err| @compileError("invalid nested elaboration residual: " ++ @errorName(err));

const ResidualProgram = boundary.program("boundary-elaboration-nested-residual", struct {}, struct {
    pub const compiled_plan = residual_compiled.plan;
});

const ApprovalDecl = RootProgram.Exchange.ProviderHandler.program(.{
    .label = "approval-program-handler",
    .op = ApprovalRequest,
    .program = ApprovalProviderProgram,
    .map_request = .payload_to_args,
    .map_result = .result_to_resume,
});
const ApprovalHarness = RootProgram.Exchange.ProviderHarness(.{
    .label = "approval-program-provider",
    .provider_fingerprint = @as(?u64, 0xE161),
    .entries = .{ApprovalDecl},
});

const PolicyDecl = ApprovalProviderProgram.Exchange.ProviderHandler.program(.{
    .label = "policy-program-handler",
    .op = PolicyCheck,
    .program = PolicyProviderProgram,
    .map_request = .payload_to_args,
    .map_result = .result_to_resume,
});
const PolicyHarness = ApprovalProviderProgram.Exchange.ProviderHarness(.{
    .label = "policy-program-provider",
    .provider_fingerprint = @as(?u64, 0xE162),
    .entries = .{PolicyDecl},
});

fn resolveApprovalTreaty(
    allocator: std.mem.Allocator,
    catalog: anytype,
    request: RootProgram.Exchange.RequestEnvelope,
) !RootProgram.Exchange.TreatyResolver.Result {
    var capability = try RootProgram.Exchange.Capability.encode(allocator, .{
        .issuer_label = "nested-elaboration-root-runtime",
        .provider_fingerprint = ApprovalHarness.provider_fingerprint,
        .manifest_fingerprint = catalog.manifest.fingerprint,
        .allowed_request_kinds = .{ .operation = true },
        .allowed_operation_sites = &.{ApprovalRequest.index},
        .allowed_protocol_op_fingerprints = &.{ApprovalRequest.fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"request"},
    });
    defer capability.deinit();
    const providers = [_]RootProgram.Exchange.ProviderManifest{catalog.provider_manifest};
    const offers = [_]RootProgram.Exchange.ProviderOffer{catalog.provider_offers[0]};
    const capabilities = [_]RootProgram.Exchange.Capability{capability};
    return RootProgram.Exchange.TreatyResolver.resolve(.{
        .allocator = allocator,
        .request = request,
        .manifest = catalog.manifest,
        .provider_manifests = providers[0..],
        .provider_offers = offers[0..],
        .capabilities = capabilities[0..],
    });
}

fn resolvePolicyTreaty(
    allocator: std.mem.Allocator,
    catalog: anytype,
    request: ApprovalProviderProgram.Exchange.RequestEnvelope,
) !ApprovalProviderProgram.Exchange.TreatyResolver.Result {
    var capability = try ApprovalProviderProgram.Exchange.Capability.encode(allocator, .{
        .issuer_label = "nested-elaboration-policy-runtime",
        .provider_fingerprint = PolicyHarness.provider_fingerprint,
        .manifest_fingerprint = catalog.manifest.fingerprint,
        .allowed_request_kinds = .{ .operation = true },
        .allowed_operation_sites = &.{PolicyCheck.index},
        .allowed_protocol_op_fingerprints = &.{PolicyCheck.fingerprint},
        .allowed_requirement_labels = &.{"policy"},
        .allowed_op_names = &.{"check"},
    });
    defer capability.deinit();
    const providers = [_]ApprovalProviderProgram.Exchange.ProviderManifest{catalog.provider_manifest};
    const offers = [_]ApprovalProviderProgram.Exchange.ProviderOffer{catalog.provider_offers[0]};
    const capabilities = [_]ApprovalProviderProgram.Exchange.Capability{capability};
    return ApprovalProviderProgram.Exchange.TreatyResolver.resolve(.{
        .allocator = allocator,
        .request = request,
        .manifest = catalog.manifest,
        .provider_manifests = providers[0..],
        .provider_offers = offers[0..],
        .capabilities = capabilities[0..],
    });
}

fn providerPathValue(allocator: std.mem.Allocator) !i32 {
    var root_runtime = boundary.Runtime.init(allocator);
    defer root_runtime.deinit();
    var root_session = try RootProgram.Session.start(&root_runtime, .{});
    defer root_session.deinit();
    const approval_request = switch (try root_session.next()) {
        .request => |value| value,
        .after => return error.UnexpectedAfter,
        .done => return error.UnexpectedDone,
    };
    var approval_envelope = try RootProgram.Exchange.RequestEnvelope.fromRequest(allocator, approval_request, .{});
    defer approval_envelope.deinit();
    var approval_catalog = try ApprovalHarness.buildCatalog(allocator);
    defer approval_catalog.deinit();
    var approval_resolved = try resolveApprovalTreaty(allocator, approval_catalog, approval_envelope);
    defer approval_resolved.deinit();
    const approval_treaty = approval_resolved.treaty orelse return error.ExpectedTreaty;
    var approval_runtime = boundary.Runtime.init(allocator);
    defer approval_runtime.deinit();
    var approval_started = try ApprovalHarness.startProgramExecution(0, &approval_runtime, ApprovalProviderProgram.Handlers{}, allocator, approval_envelope, approval_treaty.certificate, approval_catalog.provider_offers[0], .{ .treaty = approval_treaty });
    var approval_execution = switch (approval_started) {
        .provider_suspended => |*value| moved: {
            const moved_value = value.*;
            value.session = null;
            value.nested_request_envelope = null;
            break :moved moved_value;
        },
        .response => |*packet| {
            packet.deinit();
            return error.ExpectedProviderSuspension;
        },
        .rejected => return error.ExpectedProviderSuspension,
    };
    defer approval_execution.deinit();
    const policy_envelope = approval_execution.nested_request_envelope.?;
    var policy_catalog = try PolicyHarness.buildCatalog(allocator);
    defer policy_catalog.deinit();
    var policy_resolved = try resolvePolicyTreaty(allocator, policy_catalog, policy_envelope);
    defer policy_resolved.deinit();
    const policy_treaty = policy_resolved.treaty orelse return error.ExpectedTreaty;
    var policy_runtime = boundary.Runtime.init(allocator);
    defer policy_runtime.deinit();
    var policy_started = try PolicyHarness.startProgramExecution(0, &policy_runtime, PolicyProviderProgram.Handlers{}, allocator, policy_envelope, policy_treaty.certificate, policy_catalog.provider_offers[0], .{ .treaty = policy_treaty });
    var policy_response = switch (policy_started) {
        .response => |*packet| moved: {
            var response = try ApprovalProviderProgram.Exchange.ResponseEnvelope.decode(allocator, packet.response.bytes);
            errdefer response.deinit();
            packet.deinit();
            break :moved response;
        },
        .provider_suspended => |*parked| {
            parked.deinit();
            return error.ExpectedProviderResponse;
        },
        .rejected => return error.ExpectedProviderResponse,
    };
    defer policy_response.deinit();
    var approval_continued = try ApprovalHarness.continueProgramExecution(0, &approval_execution, &approval_runtime, ApprovalProviderProgram.Handlers{}, allocator, approval_envelope, approval_treaty.certificate, approval_catalog.provider_offers[0], policy_response, .{ .treaty = approval_treaty });
    switch (approval_continued) {
        .response => |*packet| {
            defer packet.deinit();
            try RootProgram.Exchange.applyResponse(&root_session, packet.response, .{});
        },
        .provider_suspended => |*parked| {
            parked.deinit();
            return error.ExpectedProviderResponse;
        },
        .rejected => return error.ExpectedProviderResponse,
    }
    var done = switch (try root_session.next()) {
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

const NestedAnalysis = struct {
    certificate_ref: RootProgram.Evidence.Ref,
    shape_ref: RootProgram.Evidence.Ref,
    shape_fingerprint: u64,
    provider_program_ref: RootProgram.Evidence.Ref,
    static_treaty_plan_ref: RootProgram.Evidence.Ref,
    provider_binding_ref: RootProgram.Evidence.Ref,
    static_treaty_plan: RootProgram.Evidence.BoundaryStaticTreatyPlan,

    fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.static_treaty_plan.blockers);
        allocator.free(self.static_treaty_plan.dependencies);
    }
};

fn analyzeNested(allocator: std.mem.Allocator) !NestedAnalysis {
    const NestedClosure = ApprovalProviderProgram.BoundaryClosure;
    const nested_shapes = NestedClosure.effectShapesForProgram(ApprovalProviderProgram, .operation);
    var policy_catalog = try PolicyHarness.buildCatalog(allocator);
    defer policy_catalog.deinit();
    var capability = try ApprovalProviderProgram.Exchange.Capability.encode(allocator, .{
        .issuer_label = "nested-elaboration-provider",
        .provider_fingerprint = PolicyHarness.provider_fingerprint,
        .manifest_fingerprint = policy_catalog.manifest.fingerprint,
        .allowed_request_kinds = .{ .operation = true },
        .allowed_operation_sites = &.{PolicyCheck.index},
        .allowed_protocol_op_fingerprints = &.{PolicyCheck.fingerprint},
        .allowed_requirement_labels = &.{"policy"},
        .allowed_op_names = &.{"check"},
    });
    defer capability.deinit();
    const policy_provider_ref = RootProgram.Evidence.refFor(RootProgram.Evidence.domains.program_plan, PolicyProviderProgram.compiled_plan.hash(), .{ .label = PolicyProviderProgram.contract.label });
    const provider_programs = [_]NestedClosure.ProviderProgram{.{
        .provider_ref = policy_catalog.provider_manifest.evidenceRef(),
        .program_ref = policy_provider_ref,
        .provider_program_mapping_fingerprint = PolicyDecl.provider_program_mapping_fingerprint,
        .provider_program_mapping_support_fingerprint = NestedClosure.providerProgramMappingSupportFingerprintForSelection(policy_catalog.provider_manifest.evidenceRef(), policy_catalog.provider_offers[0].evidenceRef(), policy_provider_ref, PolicyDecl.provider_program_mapping_fingerprint, 0, RootProgram.Evidence.fingerprintBoundaryEffectShapeSet(&.{}), .payload_to_args, .result_to_resume),
        .request_mapping = .payload_to_args,
        .result_mapping = .result_to_resume,
        .effect_free = true,
    }};
    const source_ref = RootProgram.Evidence.refFor(RootProgram.Evidence.domains.program_plan, ApprovalProviderProgram.compiled_plan.hash(), .{ .label = ApprovalProviderProgram.contract.label });
    var policy = NestedClosure.Policy.strict();
    policy.require_root_program_refs = true;
    var closure = try NestedClosure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = nested_shapes[0..1],
        .root_program_refs = &.{source_ref},
        .provider_programs = provider_programs[0..],
        .provider_manifests = &.{policy_catalog.provider_manifest},
        .provider_offers = &.{policy_catalog.provider_offers[0]},
        .capabilities = &.{capability},
        .policy = policy,
    });
    defer closure.deinit();
    try closure.assertClosed();
    var static_treaty_plan = closure.static_treaty_plans[0];
    static_treaty_plan.blockers = try allocator.dupe(RootProgram.Evidence.BoundaryClosureBlocker, static_treaty_plan.blockers);
    errdefer allocator.free(static_treaty_plan.blockers);
    static_treaty_plan.dependencies = try allocator.dupe(RootProgram.Evidence.Dependency, static_treaty_plan.dependencies);
    errdefer allocator.free(static_treaty_plan.dependencies);
    const residual_ref = RootProgram.Evidence.refFor(RootProgram.Evidence.domains.program_plan, ResidualProgram.compiled_plan.hash(), .{ .label = ResidualProgram.contract.label });
    const provider_binding_ref = RootProgram.Evidence.refForProviderProgramResidualBinding(static_treaty_plan, residual_ref).?;
    return .{
        .certificate_ref = closure.certificate.evidenceRef(),
        .shape_ref = nested_shapes[0].evidenceRef(),
        .shape_fingerprint = nested_shapes[0].fingerprint,
        .provider_program_ref = provider_programs[0].program_ref,
        .static_treaty_plan_ref = static_treaty_plan.evidenceRef(),
        .provider_binding_ref = provider_binding_ref,
        .static_treaty_plan = static_treaty_plan,
    };
}

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    const Closure = RootProgram.BoundaryClosure;
    const root_shapes = Closure.effectShapesForProgram(RootProgram, .operation);
    const approval_provider_shapes = Closure.effectShapesForProgram(ApprovalProviderProgram, .operation);
    const nested = try analyzeNested(allocator);
    defer nested.deinit(allocator);
    var approval_catalog = try ApprovalHarness.buildCatalog(allocator);
    defer approval_catalog.deinit();
    var capability = try RootProgram.Exchange.Capability.encode(allocator, .{
        .issuer_label = "nested-elaboration-root",
        .provider_fingerprint = ApprovalHarness.provider_fingerprint,
        .manifest_fingerprint = approval_catalog.manifest.fingerprint,
        .allowed_request_kinds = .{ .operation = true },
        .allowed_operation_sites = &.{ApprovalRequest.index},
        .allowed_protocol_op_fingerprints = &.{ApprovalRequest.fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"request"},
    });
    defer capability.deinit();
    const source_ref = RootProgram.Evidence.refFor(RootProgram.Evidence.domains.program_plan, RootProgram.compiled_plan.hash(), .{ .label = RootProgram.contract.label });
    const approval_provider_ref = RootProgram.Evidence.refFor(RootProgram.Evidence.domains.program_plan, ApprovalProviderProgram.compiled_plan.hash(), .{ .label = ApprovalProviderProgram.contract.label });
    const provider_programs = [_]Closure.ProviderProgram{.{
        .provider_ref = approval_catalog.provider_manifest.evidenceRef(),
        .program_ref = approval_provider_ref,
        .provider_program_mapping_fingerprint = ApprovalDecl.provider_program_mapping_fingerprint,
        .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForSelection(approval_catalog.provider_manifest.evidenceRef(), approval_catalog.provider_offers[0].evidenceRef(), approval_provider_ref, ApprovalDecl.provider_program_mapping_fingerprint, 1, RootProgram.Evidence.fingerprintBoundaryEffectShapeSet(approval_provider_shapes[0..1]), .payload_to_args, .result_to_resume),
        .request_mapping = .payload_to_args,
        .result_mapping = .result_to_resume,
        .shapes = approval_provider_shapes[0..1],
    }};
    var closure_policy = Closure.Policy.auditOnly();
    closure_policy.require_root_program_refs = true;
    var closure = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = root_shapes[0..1],
        .root_program_refs = &.{source_ref},
        .provider_programs = provider_programs[0..],
        .provider_manifests = &.{approval_catalog.provider_manifest},
        .provider_offers = &.{approval_catalog.provider_offers[0]},
        .capabilities = &.{capability},
        .policy = closure_policy,
        .provider_harness_refs = &.{RootProgram.Evidence.refForProviderHarness(ApprovalHarness)},
    });
    defer closure.deinit();
    const elaboration_provider_programs = [_]Closure.ProviderProgram{.{
        .provider_ref = provider_programs[0].provider_ref,
        .program_ref = provider_programs[0].program_ref,
        .provider_program_mapping_fingerprint = provider_programs[0].provider_program_mapping_fingerprint,
        .provider_program_mapping_support_fingerprint = Closure.providerProgramMappingSupportFingerprintForPlan(closure.static_treaty_plans[0], .payload_to_args, .result_to_resume),
        .request_mapping = provider_programs[0].request_mapping,
        .result_mapping = provider_programs[0].result_mapping,
        .shapes = provider_programs[0].shapes,
    }};

    var elaboration_policy = Closure.Elaboration.Policy.auditOnly();
    elaboration_policy.closure_policy = closure_policy;
    const elaboration_input = Closure.Elaboration.Input{
        .closure_graph = closure.graph,
        .closure_report = closure.report,
        .closure_certificate = closure.certificate,
        .static_treaty_plans = closure.static_treaty_plans,
        .source_program_ref = source_ref,
        .provider_programs = elaboration_provider_programs[0..],
        .provider_harness_refs = &.{RootProgram.Evidence.refForProviderHarness(ApprovalHarness)},
        .policy = elaboration_policy,
    };
    try elaboration_input.validate();
    const residual_ref = RootProgram.Evidence.refFor(RootProgram.Evidence.domains.program_plan, ResidualProgram.compiled_plan.hash(), .{ .label = ResidualProgram.contract.label });
    const source_entries = [_]Closure.Elaboration.SourceMap.Entry{
        .{
            .source_ref = root_shapes[0].evidenceRef(),
            .residual_ref = residual_ref,
            .source_site_index = root_shapes[0].site_index,
            .static_treaty_plan_ref = closure.static_treaty_plans[0].evidenceRef(),
            .provider_program_ref = approval_provider_ref,
            .disposition = .provider_program_linked,
            .label = "approval.request",
        },
        .{
            .source_ref = nested.shape_ref,
            .residual_ref = residual_ref,
            .source_site_index = PolicyCheck.index,
            .provider_program_ref = nested.provider_program_ref,
            .static_treaty_plan_ref = nested.static_treaty_plan_ref,
            .disposition = .provider_program_linked,
            .label = "policy.check",
        },
    };
    const source_map = Closure.Elaboration.SourceMap.init("boundary-elaboration-nested-source-map", source_entries[0..], &.{});
    const trace_entries = [_]Closure.Elaboration.TraceMap.Entry{
        .{ .source_ref = root_shapes[0].evidenceRef(), .residual_ref = residual_ref, .trace_label = "approval.request" },
        .{ .source_ref = nested.shape_ref, .residual_ref = residual_ref, .trace_label = "policy.check" },
    };
    const trace_map = Closure.Elaboration.TraceMap.init("boundary-elaboration-nested-trace-map", trace_entries[0..]);
    const effect_row = Closure.Elaboration.EffectRow.init(.{
        .label = "boundary-elaboration-nested-effect-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .strict_closed,
        .source_effect_shapes = 2,
        .closed_effect_shapes = 2,
        .provider_program_links = 2,
        .nested_provider_shapes_linked = 1,
    });
    const normal_form = Closure.Elaboration.NormalForm.init("boundary-elaboration-nested-normal-form", .strict_closed, closure.certificate.evidenceRef(), effect_row.evidenceRef(), 0);
    const approval_provider_binding_ref = RootProgram.Evidence.refForProviderProgramResidualBinding(closure.static_treaty_plans[0], residual_ref).?;
    const policy_provider_binding_ref = nested.provider_binding_ref;
    const dependencies = [_]RootProgram.Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure.certificate.evidenceRef() },
        .{ .role = .closure_certificate, .ref = nested.certificate_ref },
        .{ .role = .residual_program, .ref = residual_ref },
        .{ .role = .provider_program_mapping, .ref = approval_provider_binding_ref },
        .{ .role = .provider_program_mapping, .ref = policy_provider_binding_ref },
        .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() },
    };
    const evidence_dependency_refs = [_]RootProgram.Evidence.Ref{
        closure.certificate.evidenceRef(),
        nested.certificate_ref,
        residual_ref,
        approval_provider_binding_ref,
        policy_provider_binding_ref,
        source_map.evidenceRef(),
        effect_row.evidenceRef(),
    };
    const inlined_provider_refs = [_]RootProgram.Evidence.Ref{ approval_provider_ref, nested.provider_program_ref };
    const selected_static_plan_refs = [_]RootProgram.Evidence.Ref{
        closure.static_treaty_plans[0].evidenceRef(),
        nested.static_treaty_plan_ref,
    };
    const elaboration_certificate = Closure.Elaboration.Certificate.init(.{
        .elaborated_program_label = ResidualProgram.contract.label,
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .closure_certificate_ref = closure.certificate.evidenceRef(),
        .closure_graph_ref = closure.graph.evidenceRef(),
        .closure_report_ref = closure.report.evidenceRef(),
        .source_map_ref = source_map.evidenceRef(),
        .effect_row_ref = effect_row.evidenceRef(),
        .trace_map_ref = trace_map.evidenceRef(),
        .normal_form_ref = normal_form.evidenceRef(),
        .policy = elaboration_policy,
        .normal_form = .strict_closed,
        .elaborated_program_plan_hash = ResidualProgram.compiled_plan.hash(),
        .selected_static_treaty_plan_refs = selected_static_plan_refs[0..],
        .inlined_provider_program_refs = inlined_provider_refs[0..],
        .evidence_dependency_refs = evidence_dependency_refs[0..],
        .summary_counts = .{
            .root_effect_shapes = 2,
            .internal_routes_elaborated = 2,
            .provider_programs_linked = 2,
            .nested_provider_shapes_linked = 1,
        },
        .dependencies = dependencies[0..],
    });
    const elaboration_static_plans = [_]Closure.StaticTreatyPlan{
        closure.static_treaty_plans[0],
        nested.static_treaty_plan,
    };
    try elaboration_certificate.check(elaboration_policy, closure.graph.evidenceRef(), closure.report.evidenceRef(), closure.certificate.evidenceRef(), source_map, effect_row, trace_map, normal_form, elaboration_static_plans[0..], &.{});
    const original = try providerPathValue(allocator);
    const residual = try residualValue(allocator);
    if (original != residual) return error.ElaborationMismatch;
    try writer.print("root_effect_shape_fingerprint={x}\n", .{root_shapes[0].fingerprint});
    try writer.print("nested_effect_shape_fingerprint={x}\n", .{nested.shape_fingerprint});
    try writer.print("approval_provider_program_ref={x}\n", .{approval_provider_ref.fingerprint});
    try writer.print("policy_provider_program_ref={x}\n", .{nested.provider_program_ref.fingerprint});
    try writer.print("elaboration_certificate_fingerprint={x}\n", .{elaboration_certificate.certificate_fingerprint});
    try writer.print("final_result={d}\n", .{residual});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
