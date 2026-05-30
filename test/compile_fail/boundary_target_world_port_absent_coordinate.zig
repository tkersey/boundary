// zlinter-disable declaration_naming require_doc_comment no_swallow_error
const boundary = @import("boundary");

const semantic = boundary.ir.builder.semantic;
const Handlers = struct {};

fn compiled() boundary.ir.ProgramPlan {
    const Protocol = boundary.ir.schema.Protocol(.{
        .label = "approval",
        .ops = .{boundary.ir.schema.transform("request", []const u8, i32)},
    });
    const rows = Protocol.Rows(Handlers, .{ .requirement_index = 0, .first_op = 0 });
    const request = rows.op("request");
    const result = semantic.finish(.{
        .label = "world-port-absent-coordinate",
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
    return result.plan;
}

const Program = boundary.program("world-port-absent-coordinate", Handlers, struct {
    pub const compiled_plan = compiled();
});

const Evidence = Program.Evidence;
const Closure = Program.BoundaryClosure;
const Elaboration = Closure.Elaboration;
const request_site = Program.protocol.operationSite("approval", "request", 0);

comptime {
    @setEvalBranchQuota(300_000);
    const source_ref = Evidence.refFor(Evidence.domains.program_plan, Program.compiled_plan.hash(), .{ .label = Program.contract.label });
    const intrinsic_ref = Evidence.refFor(Evidence.domains.host_intrinsic, 0xC781_F402, .{ .label = "absent-coordinate-intrinsic" });
    const absent_shape = Closure.EffectShape.init(.{
        .program_label = Program.contract.label,
        .plan_hash = Program.compiled_plan.hash(),
        .kind = .operation,
        .site_index = request_site.index + 99,
        .protocol_label = "approval",
    });
    const plan = Closure.StaticTreatyPlan.init(.{
        .label = "absent-coordinate-plan",
        .source_shape = absent_shape,
        .selected_semantic_body = .host_intrinsic,
        .selected_intrinsic_ref = intrinsic_ref,
        .host_intrinsic = true,
    });
    const world_port = Closure.WorldPort.init(.{
        .label = "absent-coordinate-world-port",
        .kind = .test_fixture,
        .exposed_intrinsic_ref = intrinsic_ref,
        .supported_protocol_labels = &.{"approval"},
    });
    const graph = Closure.Graph.init("absent-coordinate-graph", &.{}, &.{}, &.{});
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
    _ = Elaboration.Target.compileComptime(.{
        .label = "absent-coordinate-target",
        .input = input,
        .residual_program = Program,
        .policy = Elaboration.Target.Policy.auditOnly(),
    });
}
