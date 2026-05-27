// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

const semantic = boundary.ir.builder.semantic;
const Handlers = struct {};

fn compiled(comptime label: []const u8, comptime op_name: [:0]const u8) boundary.ir.ProgramPlan {
    const Protocol = boundary.ir.schema.Protocol(.{
        .label = "approval",
        .ops = .{boundary.ir.schema.transform(op_name, []const u8, i32)},
    });
    const rows = Protocol.Rows(Handlers, .{ .requirement_index = 0, .first_op = 0 });
    const request = rows.op(op_name);
    const result = semantic.finish(.{
        .label = label,
        .ir_hash = 0xC781_F201,
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
                    semantic.call(request, .{ .dst = "decision", .payload = "payload", .label = "approval." ++ op_name }),
                },
                .terminator = semantic.returnValue("decision"),
            }},
        }},
    }) catch |err| @compileError("invalid fixture: " ++ @errorName(err));
    return result.plan;
}

const SourceProgram = boundary.program("target-identity-source", Handlers, struct {
    pub const compiled_plan = compiled("target-identity-source", "request");
});
const DriftedProgram = boundary.program("target-identity-drifted", Handlers, struct {
    pub const compiled_plan = compiled("target-identity-drifted", "approve");
});

const Evidence = SourceProgram.Evidence;
const Closure = SourceProgram.BoundaryClosure;
const Elaboration = Closure.Elaboration;
const source_site = SourceProgram.protocol.operationSite("approval", "request", 0);
const drifted_site = DriftedProgram.protocol.operationSite("approval", "approve", 0);

comptime {
    @setEvalBranchQuota(200_000);
    const source_ref = Evidence.refFor(Evidence.domains.program_plan, SourceProgram.compiled_plan.hash(), .{ .label = SourceProgram.contract.label });
    const intrinsic_ref = Evidence.refFor(Evidence.domains.host_intrinsic, 0xC781_F202, .{ .label = "intrinsic" });
    const source_shape = Closure.EffectShape.init(.{
        .program_label = "target-identity-source",
        .kind = .operation,
        .site_index = source_site.index,
        .site_fingerprint = source_site.fingerprint,
        .protocol_label = "approval",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(source_site.payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(source_site.resume_ref),
        .result_ref = Evidence.BoundaryValueRef.fromValueRef(source_site.result_ref),
    });
    const plan = Closure.StaticTreatyPlan.init(.{
        .label = "target-identity-plan",
        .source_shape = source_shape,
        .selected_semantic_body = .host_intrinsic,
        .selected_intrinsic_ref = intrinsic_ref,
        .host_intrinsic = true,
    });
    const world_port = Closure.WorldPort.init(.{
        .label = "target-identity-world-port",
        .kind = .test_fixture,
        .effect_shape_ref = source_shape.evidenceRef(),
        .exposed_intrinsic_ref = intrinsic_ref,
        .supported_protocol_labels = &.{"approval"},
        .supported_site_indexes = &.{ source_site.index, drifted_site.index },
        .supported_protocol_op_fingerprints = &.{ source_site.fingerprint, drifted_site.fingerprint },
    });
    const graph = Closure.Graph.init("target-identity-graph", &.{}, &.{}, &.{});
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
        .label = "target-identity-mismatch",
        .input = input,
        .residual_program = DriftedProgram,
        .policy = target_policy,
    });
}
