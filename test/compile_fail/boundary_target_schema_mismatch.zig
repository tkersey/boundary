// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

const semantic = boundary.ir.builder.semantic;
const Handlers = struct {};

fn compiled(comptime label: []const u8, comptime Payload: type) boundary.ir.ProgramPlan {
    const Protocol = boundary.ir.schema.Protocol(.{
        .label = "approval",
        .ops = .{boundary.ir.schema.transform("request", Payload, i32)},
    });
    const rows = Protocol.Rows(Handlers, .{ .requirement_index = 0, .first_op = 0 });
    const request = rows.op("request");
    const result = semantic.finish(.{
        .label = label,
        .ir_hash = 0xC781_F00D,
        .entry = "run",
        .requirements = &.{rows.requirement},
        .ops = &rows.ops,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = semantic.span(0, 1),
            .params = .{},
            .locals = .{
                semantic.local("payload", Payload),
                semantic.local("decision", i32),
            },
            .result = i32,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    if (Payload == []const u8)
                        semantic.constString("payload", "deploy")
                    else
                        semantic.constI32("payload", 1),
                    semantic.call(request, .{ .dst = "decision", .payload = "payload", .label = "approval.request" }),
                },
                .terminator = semantic.returnValue("decision"),
            }},
        }},
    }) catch |err| @compileError("invalid fixture: " ++ @errorName(err));
    return result.plan;
}

const SourceProgram = boundary.program("target-schema-source", Handlers, struct {
    pub const compiled_plan = compiled("target-schema-source", []const u8);
});
const DriftedProgram = boundary.program("target-schema-drifted", Handlers, struct {
    pub const compiled_plan = compiled("target-schema-drifted", i32);
});

const Evidence = SourceProgram.Evidence;
const Closure = SourceProgram.BoundaryClosure;
const Elaboration = Closure.Elaboration;
const source_site = SourceProgram.protocol.operationSite("approval", "request", 0);
const drifted_site = DriftedProgram.protocol.operationSite("approval", "request", 0);

comptime {
    @setEvalBranchQuota(200_000);
    const source_ref = Evidence.refFor(Evidence.domains.program_plan, SourceProgram.compiled_plan.hash(), .{ .label = SourceProgram.contract.label });
    const intrinsic_ref = Evidence.refFor(Evidence.domains.host_intrinsic, 0xC781_F002, .{ .label = "intrinsic" });
    const source_shape = Closure.EffectShape.init(.{
        .program_label = "target-schema-source",
        .kind = .operation,
        .site_index = source_site.index,
        .protocol_label = "approval",
        .protocol_op_fingerprint = source_site.fingerprint,
        .value_ref = Evidence.BoundaryValueRef.init("target-schema-stale-payload", null),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(source_site.resume_ref),
        .result_ref = Evidence.BoundaryValueRef.fromValueRef(source_site.resume_ref),
    });
    const plan = Closure.StaticTreatyPlan.init(.{
        .label = "target-schema-plan",
        .source_shape = source_shape,
        .selected_semantic_body = .host_intrinsic,
        .selected_intrinsic_ref = intrinsic_ref,
        .host_intrinsic = true,
    });
    const world_port = Closure.WorldPort.init(.{
        .label = "target-schema-world-port",
        .kind = .test_fixture,
        .effect_shape_ref = source_shape.evidenceRef(),
        .exposed_intrinsic_ref = intrinsic_ref,
        .supported_protocol_labels = &.{"approval"},
        .supported_site_indexes = &.{ source_site.index, drifted_site.index },
        .supported_protocol_op_fingerprints = &.{ source_site.fingerprint, drifted_site.fingerprint },
    });
    const graph = Closure.Graph.init("target-schema-graph", &.{}, &.{}, &.{});
    const report = Closure.Report.init(.{
        .graph_fingerprint = graph.fingerprint,
        .root_program_refs = &.{source_ref},
        .effect_shape_count = 1,
        .world_port_refs = &.{world_port.evidenceRef()},
        .open_world_port_count = 1,
    });
    const certificate = Closure.Certificate.init(report, graph, Closure.Policy.auditOnly(), &.{plan.evidenceRef()});
    const input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = report,
        .closure_certificate = certificate,
        .static_treaty_plans = &.{plan},
        .source_program_ref = source_ref,
        .world_ports = &.{world_port},
        .policy = Elaboration.Policy.auditOnly(),
    };
    var target_policy = Elaboration.Target.Policy.auditOnly();
    target_policy.fail_on_schema_mismatch = true;
    _ = Elaboration.Target.compileComptime(.{
        .label = "target-schema-mismatch",
        .input = input,
        .residual_program = DriftedProgram,
        .policy = target_policy,
    });
}
