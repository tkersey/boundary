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
        .label = "target-direct-world-port-source",
        .ir_hash = 0xC781_F101,
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

const SourceProgram = boundary.program("target-direct-world-port-source", Handlers, struct {
    pub const compiled_plan = compiled();
});

const Evidence = SourceProgram.Evidence;
const Closure = SourceProgram.BoundaryClosure;
const Elaboration = Closure.Elaboration;
const source_site = SourceProgram.protocol.operationSite("approval", "request", 0);

comptime {
    @setEvalBranchQuota(200_000);
    const source_ref = Evidence.refFor(Evidence.domains.program_plan, SourceProgram.compiled_plan.hash(), .{ .label = SourceProgram.contract.label });
    const source_shape = Closure.EffectShape.init(.{
        .program_label = "target-direct-world-port-source",
        .kind = .operation,
        .site_index = source_site.index,
        .protocol_label = "approval",
        .protocol_op_fingerprint = source_site.fingerprint,
    });
    _ = source_shape;
    const world_port = Closure.WorldPort.init(.{
        .label = "target-direct-world-port",
        .kind = .test_fixture,
        .supported_protocol_labels = &.{"approval"},
        .supported_site_indexes = &.{source_site.index},
        .supported_protocol_op_fingerprints = &.{source_site.fingerprint},
    });
    const graph = Closure.Graph.init("target-direct-world-port-graph", &.{}, &.{}, &.{});
    const report = Closure.Report.init(.{
        .graph_fingerprint = graph.fingerprint,
        .root_program_refs = &.{source_ref},
        .effect_shape_count = 1,
        .world_port_refs = &.{world_port.evidenceRef()},
        .open_world_port_count = 1,
    });
    const certificate = Closure.Certificate.init(report, graph, Closure.Policy.auditOnly(), &.{});
    const input = Elaboration.Input{
        .closure_graph = graph,
        .closure_report = report,
        .closure_certificate = certificate,
        .source_program_ref = source_ref,
        .world_ports = &.{world_port},
        .policy = Elaboration.Policy.auditOnly(),
    };
    var target_policy = Elaboration.Target.Policy.auditOnly();
    target_policy.fail_on_schema_mismatch = true;
    _ = Elaboration.Target.compileComptime(.{
        .label = "target-direct-world-port-schema-witness",
        .input = input,
        .residual_program = SourceProgram,
        .policy = target_policy,
    });
}
