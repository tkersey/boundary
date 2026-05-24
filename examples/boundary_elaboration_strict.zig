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
    .label = "boundary-elaboration-strict-source",
    .ir_hash = 0x656c7374726301,
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
}) catch |err| @compileError("invalid strict elaboration source: " ++ @errorName(err));

const SourceBody = struct {
    pub const site_metadata = source_compiled.site_metadata;
    pub const compiled_plan = source_compiled.plan;
};
const SourceProgram = boundary.program("boundary-elaboration-strict-source", SourceHandlers, SourceBody);
const ApprovalRequest = SourceProgram.protocol.operationSite("approval", "request", 0);

const provider_compiled = semantic.finish(.{
    .label = "boundary-elaboration-strict-provider",
    .ir_hash = 0x656c7374726801,
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
}) catch |err| @compileError("invalid strict elaboration provider: " ++ @errorName(err));

const ProviderBody = struct {
    pub const compiled_plan = provider_compiled.plan;
};
const ProviderProgram = boundary.program("boundary-elaboration-strict-provider", struct {}, ProviderBody);

const ResidualBodyPlan = semantic.finish(.{
    .label = "boundary-elaboration-strict-residual",
    .ir_hash = 0x656c7374727201,
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
}) catch |err| @compileError("invalid strict elaboration residual: " ++ @errorName(err));

const ResidualProgram = boundary.program("boundary-elaboration-strict-residual", struct {}, struct {
    pub const compiled_plan = ResidualBodyPlan.plan;
});

const ApprovalDecl = SourceProgram.Exchange.ProviderHandler.program(.{
    .label = "approval-program-handler",
    .op = ApprovalRequest,
    .program = ProviderProgram,
    .map_request = .payload_to_args,
    .map_result = .result_to_resume,
});
const Harness = SourceProgram.Exchange.ProviderHarness(.{
    .label = "approval-program-provider",
    .provider_fingerprint = @as(?u64, 0xE151),
    .entries = .{ApprovalDecl},
});

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
    const allocator = std.heap.page_allocator;
    const Closure = SourceProgram.BoundaryClosure;
    const root_shapes = Closure.effectShapesForProgram(SourceProgram, .operation);
    var catalog = try Harness.buildCatalog(allocator);
    defer catalog.deinit();
    var capability = try SourceProgram.Exchange.Capability.encode(allocator, .{
        .issuer_label = "elaboration-host",
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
    const provider_programs = [_]Closure.ProviderProgram{.{
        .provider_ref = catalog.provider_manifest.evidenceRef(),
        .program_ref = SourceProgram.Evidence.refFor(SourceProgram.Evidence.domains.program_plan, ProviderProgram.compiled_plan.hash(), .{ .label = ProviderProgram.contract.label }),
        .provider_program_mapping_fingerprint = ApprovalDecl.provider_program_mapping_fingerprint,
        .effect_free = true,
    }};
    var closure_policy = Closure.Policy.strict();
    closure_policy.require_root_program_refs = true;
    var closure = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = root_shapes[0..1],
        .provider_programs = provider_programs[0..],
        .provider_manifests = &.{catalog.provider_manifest},
        .provider_offers = &.{catalog.provider_offers[0]},
        .capabilities = &.{capability},
        .policy = closure_policy,
        .root_program_refs = &.{source_ref},
        .provider_harness_refs = &.{SourceProgram.Evidence.refForProviderHarness(Harness)},
    });
    defer closure.deinit();
    try closure.assertClosed();

    var elaboration_policy = Closure.Elaboration.Policy.strict();
    elaboration_policy.closure_policy = closure_policy;
    const elaboration_input = Closure.Elaboration.Input{
        .closure_graph = closure.graph,
        .closure_report = closure.report,
        .closure_certificate = closure.certificate,
        .static_treaty_plans = closure.static_treaty_plans,
        .source_program_ref = source_ref,
        .provider_programs = provider_programs[0..],
        .provider_harness_refs = &.{SourceProgram.Evidence.refForProviderHarness(Harness)},
        .policy = elaboration_policy,
    };
    try elaboration_input.validate();
    const residual_ref = SourceProgram.Evidence.refFor(SourceProgram.Evidence.domains.program_plan, ResidualProgram.compiled_plan.hash(), .{ .label = ResidualProgram.contract.label });
    const source_entries = [_]Closure.Elaboration.SourceMap.Entry{.{
        .source_ref = root_shapes[0].evidenceRef(),
        .residual_ref = residual_ref,
        .source_site_index = root_shapes[0].site_index,
        .static_treaty_plan_ref = closure.static_treaty_plans[0].evidenceRef(),
        .provider_program_ref = provider_programs[0].program_ref,
        .disposition = .provider_program_linked,
        .label = "approval.request",
    }};
    const source_map = Closure.Elaboration.SourceMap.init("boundary-elaboration-strict-source-map", source_entries[0..], &.{});
    const trace_entries = [_]Closure.Elaboration.TraceMap.Entry{.{ .source_ref = root_shapes[0].evidenceRef(), .residual_ref = residual_ref, .trace_label = "approval.request" }};
    const trace_map = Closure.Elaboration.TraceMap.init("boundary-elaboration-strict-trace-map", trace_entries[0..]);
    const effect_row = Closure.Elaboration.EffectRow.init(.{
        .label = "boundary-elaboration-strict-effect-row",
        .source_program_ref = source_ref,
        .residual_program_ref = residual_ref,
        .normal_form = .strict_closed,
        .source_effect_shapes = closure.report.effect_shape_count,
        .closed_effect_shapes = closure.report.closed_effect_shape_count,
        .provider_program_links = closure.report.provider_program_refs.len,
    });
    const normal_form = Closure.Elaboration.NormalForm.init("boundary-elaboration-strict-normal-form", .strict_closed, closure.certificate.evidenceRef(), effect_row.evidenceRef(), 0);
    const dependencies = [_]SourceProgram.Evidence.Dependency{
        .{ .role = .closure_certificate, .ref = closure.certificate.evidenceRef() },
        .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() },
        .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() },
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
        .selected_static_treaty_plan_refs = closure.certificate.selected_static_treaty_plan_refs,
        .inlined_provider_program_refs = closure.report.provider_program_refs,
        .summary_counts = .{
            .root_effect_shapes = closure.report.effect_shape_count,
            .internal_routes_elaborated = closure.report.closed_effect_shape_count,
            .provider_programs_linked = closure.report.provider_program_refs.len,
        },
        .dependencies = dependencies[0..],
    });
    try elaboration_certificate.check(elaboration_policy, closure.graph.evidenceRef(), closure.report.evidenceRef(), closure.certificate.evidenceRef(), source_map, effect_row, trace_map, normal_form);
    const original = try originalValue(allocator);
    const residual = try residualValue(allocator);
    if (original != residual) return error.ElaborationMismatch;
    try writer.print("closure_certificate_fingerprint={x}\n", .{closure.certificate.certificate_fingerprint});
    try writer.print("elaboration_certificate_fingerprint={x}\n", .{elaboration_certificate.certificate_fingerprint});
    try writer.print("elaborated_plan_hash={x}\n", .{ResidualProgram.compiled_plan.hash()});
    try writer.print("final_result={d}\n", .{residual});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
