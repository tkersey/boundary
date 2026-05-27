// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

const semantic = boundary.ir.builder.semantic;
const Handlers = struct {};

const Protocol = boundary.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{boundary.ir.schema.transform("request", []const u8, i32)},
});
const rows = Protocol.Rows(Handlers, .{ .requirement_index = 0, .first_op = 0 });
const request = rows.op("request");
const compiled = semantic.finish(.{
    .label = "target-program-backed-source",
    .ir_hash = 0xC781_F401,
    .entry = "run",
    .requirements = &.{rows.requirement},
    .ops = &rows.ops,
    .functions = .{.{
        .symbol_name = "run",
        .requirements = semantic.span(0, 1),
        .params = .{},
        .locals = .{
            semantic.local("payload", []const u8),
            semantic.local("decision", i32),
        },
        .result = i32,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{
                semantic.constString("payload", "deploy"),
                semantic.call(request, .{ .dst = "decision", .payload = "payload", .label = "approval.request" }),
            },
            .terminator = semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid fixture: " ++ @errorName(err));

const Program = boundary.program("target-program-backed-source", Handlers, struct {
    pub const site_metadata = compiled.site_metadata;
    pub const compiled_plan = compiled.plan;
});

const Evidence = Program.Evidence;
const Closure = Program.BoundaryClosure;
const Elaboration = Closure.Elaboration;
const source_site = Program.protocol.operationSite("approval", "request", 0);

comptime {
    @setEvalBranchQuota(300_000);
    const source_ref = Evidence.refFor(Evidence.domains.program_plan, Program.compiled_plan.hash(), .{ .label = Program.contract.label });
    const morphism_ref = Evidence.refFor(Evidence.domains.morphism_offer, 0xC781_F402, .{ .label = "pipeline-morphism" });
    const pipeline_ref = Evidence.refFor(Evidence.domains.pipeline, 0xC781_F403, .{ .label = "pipeline-proof" });
    const source_shape = Closure.EffectShape.init(.{
        .program_label = Program.contract.label,
        .kind = .operation,
        .site_index = source_site.index,
        .protocol_label = "approval",
        .protocol_op_fingerprint = source_site.fingerprint,
    });
    const dependencies = [_]Evidence.Dependency{
        .{ .role = .morphism, .ref = morphism_ref },
        .{ .role = .pipeline, .ref = pipeline_ref },
        .{ .role = .residual_program, .ref = source_ref },
    };
    const plan = Closure.StaticTreatyPlan.init(.{
        .label = "pipeline-route",
        .source_shape = source_shape,
        .selected_semantic_body = .pipeline,
        .selected_morphism_ref = morphism_ref,
        .selected_morphism_semantic_body = .pipeline,
        .selected_provider_ref = source_ref,
        .selected_provider_offer_ref = source_ref,
        .selected_capability_ref = source_ref,
        .dependencies = dependencies[0..],
    });
    const graph = Closure.Graph.init("target-program-backed-graph", &.{}, &.{}, &.{});
    const report = Closure.Report.init(.{
        .graph_fingerprint = graph.fingerprint,
        .root_program_refs = &.{source_ref},
        .effect_shape_count = 1,
        .closed_effect_shape_count = 1,
        .residualized_pipeline_route_count = 1,
    });
    const certificate = Closure.Certificate.init(report, graph, Closure.Policy.auditOnly(), &.{plan.evidenceRef()});
    const input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = report,
        .closure_certificate = certificate,
        .static_treaty_plans = &.{plan},
        .source_program_ref = source_ref,
        .morphism_offer_refs = &.{morphism_ref},
        .pipeline_adapter_refs = &.{pipeline_ref},
        .policy = Elaboration.Policy.auditOnly(),
    };
    var target_policy = Elaboration.Target.Policy.auditOnly();
    target_policy.elaboration_policy.require_program_backed_providers_for_internal_routes = true;
    _ = Elaboration.Target.compileComptime(.{
        .label = "target-program-backed-requirement",
        .input = input,
        .residual_program = Program,
        .policy = target_policy,
    });
}
