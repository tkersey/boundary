// zlinter-disable declaration_naming field_ordering require_doc_comment no_hidden_allocations no_inferred_error_unions
const boundary = @import("boundary");
const std = @import("std");

const Handlers = struct {};
const semantic = boundary.ir.builder.semantic;

const ApprovalProtocol = boundary.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{boundary.ir.schema.transform("request", []const u8, i32)},
});
const Rows = ApprovalProtocol.Rows(Handlers, .{ .requirement_index = 0, .first_op = 0 });
const RequestOp = Rows.op("request");

const source_compiled = semantic.finish(.{
    .label = "boundary-elaboration-world-port-source",
    .ir_hash = 0x656c776f726c6401,
    .entry = "run",
    .requirements = &.{Rows.requirement},
    .ops = &Rows.ops,
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
                semantic.call(RequestOp, .{ .dst = "decision", .payload = "payload", .label = "approval.request" }),
            },
            .terminator = semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid world-port elaboration source: " ++ @errorName(err));

const SourceBody = struct {
    pub const site_metadata = source_compiled.site_metadata;
    pub const compiled_plan = source_compiled.plan;
};
const SourceProgram = boundary.program("boundary-elaboration-world-port-source", Handlers, SourceBody);
const ApprovalRequest = SourceProgram.protocol.operationSite("approval", "request", 0);

const residual_compiled = semantic.finish(.{
    .label = "boundary-elaboration-world-port-residual",
    .ir_hash = 0x656c776f726c6402,
    .entry = "run",
    .requirements = &.{Rows.requirement},
    .ops = &Rows.ops,
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
                semantic.call(RequestOp, .{ .dst = "decision", .payload = "payload", .label = "approval.request.world" }),
            },
            .terminator = semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid world-port elaboration residual: " ++ @errorName(err));

const ResidualProgram = boundary.program("boundary-elaboration-world-port-residual", Handlers, struct {
    pub const site_metadata = residual_compiled.site_metadata;
    pub const compiled_plan = residual_compiled.plan;
});

const Outcome = union(enum) {
    forward,
    pending,
    reject: []const u8,
    replay: i32,
    @"resume": i32,
    resume_after: void,
    return_now: i32,
};

fn hostApproval(_: void, _: anytype) !Outcome {
    return .{ .@"resume" = 7 };
}

const ApprovalDecl = SourceProgram.Exchange.ProviderHandler.intrinsicOperation(ApprovalRequest, hostApproval, .{
    .label = "approval-host-human",
    .tags = &.{"host_human"},
    .metadata = "host human approval boundary",
});
const Harness = SourceProgram.Exchange.ProviderHarness(.{
    .label = "approval-host-human-provider",
    .provider_fingerprint = @as(?u64, 0xE153),
    .entries = .{ApprovalDecl},
});

fn residualWorldValue(allocator: std.mem.Allocator) !i32 {
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var session = try ResidualProgram.Session.start(&runtime, .{});
    defer session.deinit();
    const request = switch (try session.next()) {
        .request => |value| value,
        .after => return error.UnexpectedAfter,
        .done => return error.UnexpectedDone,
    };
    if (request.operation_site_index != ApprovalRequest.index) return error.UnexpectedWorldPortSite;
    try session.@"resume"(request, @as(i32, 7));
    var done = switch (try session.next()) {
        .done => |value| value,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer done.deinit();
    return done.value;
}

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    const Closure = SourceProgram.BoundaryClosure;
    const root_shapes = Closure.effectShapesForProgram(SourceProgram, .operation);
    var catalog = try Harness.buildCatalog(allocator);
    defer catalog.deinit();
    var capability = try SourceProgram.Exchange.Capability.encode(allocator, .{
        .issuer_label = "elaboration-world-host",
        .provider_fingerprint = Harness.provider_fingerprint,
        .manifest_fingerprint = catalog.manifest.fingerprint,
        .allowed_request_kinds = .{ .operation = true },
        .allowed_operation_sites = &.{ApprovalRequest.index},
        .allowed_protocol_op_fingerprints = &.{ApprovalRequest.fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"request"},
    });
    defer capability.deinit();
    const source_ref = SourceProgram.Evidence.refFor(SourceProgram.Evidence.domains.program_plan, SourceProgram.compiled_plan.hash(), .{ .label = SourceProgram.contract.label });
    const intrinsic_ref = catalog.provider_offers[0].hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    const port = Closure.WorldPort.init(.{
        .label = "human-approval-port",
        .kind = .host_human,
        .effect_shape_ref = root_shapes[0].evidenceRef(),
        .exposed_intrinsic_ref = intrinsic_ref,
        .supported_protocol_labels = &.{"approval"},
        .supported_site_indexes = &.{ApprovalRequest.index},
        .supported_protocol_op_fingerprints = &.{ApprovalRequest.fingerprint},
        .contract_summary = "world must provide the human approval decision",
    });
    const ports = [_]Closure.WorldPort{port};
    var closure_policy = Closure.Policy.worldBoundary();
    closure_policy.require_root_program_refs = true;
    const allowed_ports = [_]u64{port.fingerprint};
    closure_policy.allowed_world_port_fingerprints = allowed_ports[0..];
    var closure = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = root_shapes[0..1],
        .root_program_refs = &.{source_ref},
        .provider_manifests = &.{catalog.provider_manifest},
        .provider_offers = &.{catalog.provider_offers[0]},
        .capabilities = &.{capability},
        .policy = closure_policy,
        .world_ports = ports[0..],
    });
    defer closure.deinit();
    try closure.assertClosedExceptWorldPorts();

    var elaboration_policy = Closure.Elaboration.Policy.worldBoundary();
    elaboration_policy.closure_policy = closure_policy;
    const elaboration_input = Closure.Elaboration.Input{
        .closure_graph = closure.graph,
        .closure_report = closure.report,
        .closure_certificate = closure.certificate,
        .static_treaty_plans = closure.static_treaty_plans,
        .source_program_ref = source_ref,
        .world_ports = ports[0..],
        .policy = elaboration_policy,
    };
    try elaboration_input.validate();
    const residual_ref = SourceProgram.Evidence.refFor(SourceProgram.Evidence.domains.program_plan, ResidualProgram.compiled_plan.hash(), .{ .label = ResidualProgram.contract.label });
    const source_entries = [_]Closure.Elaboration.SourceMap.Entry{.{
        .source_ref = root_shapes[0].evidenceRef(),
        .residual_ref = residual_ref,
        .source_site_index = root_shapes[0].site_index,
        .residual_site_index = ApprovalRequest.index,
        .static_treaty_plan_ref = closure.static_treaty_plans[0].evidenceRef(),
        .world_port_ref = port.evidenceRef(),
        .disposition = .world_port_lowered,
        .label = "approval.request.world",
    }};
    const source_map = Closure.Elaboration.SourceMap.init("boundary-elaboration-world-port-source-map", source_entries[0..], &.{});
    const trace_entries = [_]Closure.Elaboration.TraceMap.Entry{.{ .source_ref = root_shapes[0].evidenceRef(), .residual_ref = port.evidenceRef(), .trace_label = "approval.request.world" }};
    const trace_map = Closure.Elaboration.TraceMap.init("boundary-elaboration-world-port-trace-map", trace_entries[0..]);
    const effect_row = Closure.Elaboration.EffectRow.init(.{
        .label = "boundary-elaboration-world-port-effect-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .world_ports_only,
        .source_effect_shapes = closure.report.effect_shape_count,
        .closed_effect_shapes = closure.report.closed_effect_shape_count,
        .world_ports = closure.report.open_world_port_count,
    });
    const normal_form = Closure.Elaboration.NormalForm.init("boundary-elaboration-world-port-normal-form", .world_ports_only, closure.certificate.evidenceRef(), effect_row.evidenceRef(), 0);
    const dependencies = [_]SourceProgram.Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure.certificate.evidenceRef() },
        .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() },
        .{ .role = .elaboration_trace_map, .ref = trace_map.evidenceRef() },
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
        .normal_form = .world_ports_only,
        .elaborated_program_plan_hash = ResidualProgram.compiled_plan.hash(),
        .selected_static_treaty_plan_refs = closure.certificate.selected_static_treaty_plan_refs,
        .world_port_refs = closure.report.world_port_refs,
        .residual_world_port_refs = &.{port.evidenceRef()},
        .summary_counts = .{
            .root_effect_shapes = closure.report.effect_shape_count,
            .world_ports_emitted = closure.report.open_world_port_count,
        },
        .dependencies = dependencies[0..],
    });
    try elaboration_certificate.check(elaboration_policy, closure.graph.evidenceRef(), closure.report.evidenceRef(), closure.certificate.evidenceRef(), source_map, effect_row, trace_map, normal_form);
    if (!source_map.sourceForResidualSite(ApprovalRequest.index).?.eql(root_shapes[0].evidenceRef())) return error.SourceMapMismatch;
    if (!source_map.worldPortForResidualSite(ApprovalRequest.index).?.eql(port.evidenceRef())) return error.SourceMapMismatch;
    const final = try residualWorldValue(allocator);
    try writer.print("world_port_fingerprint={x}\n", .{port.fingerprint});
    try writer.print("residual_world_port_site_index={d}\n", .{ApprovalRequest.index});
    try writer.print("residual_world_port_site_fingerprint={x}\n", .{ApprovalRequest.fingerprint});
    try writer.print("source_effect_shape_fingerprint={x}\n", .{root_shapes[0].fingerprint});
    try writer.print("elaboration_certificate_fingerprint={x}\n", .{elaboration_certificate.certificate_fingerprint});
    try writer.print("final_result={d}\n", .{final});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
