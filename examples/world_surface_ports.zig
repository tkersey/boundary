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

const compiled = semantic.finish(.{
    .label = "world-surface-ports-residual",
    .ir_hash = 0x7773706f72740001,
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
}) catch |err| @compileError("invalid world surface ports residual: " ++ @errorName(err));

pub const Program = boundary.program("world-surface-ports-residual", Handlers, struct {
    pub const site_metadata = compiled.site_metadata;
    pub const compiled_plan = compiled.plan;
});
pub const ApprovalRequest = Program.protocol.operationSite("approval", "request", 0);
const Closure = Program.BoundaryClosure;
const Elaboration = Closure.Elaboration;
const program_ref = Program.Evidence.refFor(Program.Evidence.domains.program_plan, Program.compiled_plan.hash(), .{ .label = Program.contract.label });
const source_shape = Closure.EffectShape.init(.{
    .program_label = Program.contract.label,
    .plan_hash = Program.compiled_plan.hash(),
    .kind = .operation,
    .site_index = ApprovalRequest.index,
    .protocol_label = "approval",
    .protocol_op_fingerprint = ApprovalRequest.fingerprint,
});
const intrinsic_ref = Program.Evidence.refFor(Program.Evidence.domains.host_intrinsic, 0x7773_9001, .{ .label = "human-approval-host" });
const static_plan = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk Closure.StaticTreatyPlan.init(.{
        .label = "approval.request.world",
        .source_shape = source_shape,
        .selected_semantic_body = .host_intrinsic,
        .selected_intrinsic_ref = intrinsic_ref,
        .host_intrinsic = true,
    });
};
const port = Closure.WorldPort.init(.{
    .label = "human-approval-port",
    .kind = .host_human,
    .effect_shape_ref = source_shape.evidenceRef(),
    .exposed_intrinsic_ref = intrinsic_ref,
    .supported_protocol_labels = &.{"approval"},
    .supported_site_indexes = &.{ApprovalRequest.index},
    .supported_protocol_op_fingerprints = &.{ApprovalRequest.fingerprint},
});
const closure_graph = Closure.Graph.init("world-surface-ports-graph", &.{}, &.{}, &.{});
const closure_report = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk Closure.Report.init(.{
        .graph_fingerprint = closure_graph.fingerprint,
        .root_program_refs = &.{program_ref},
        .effect_shape_count = 1,
        .world_port_refs = &.{port.evidenceRef()},
        .open_world_port_count = 1,
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
    .source_program_ref = program_ref,
    .world_ports = &.{port},
    .policy = elaboration_policy,
};
pub const Target = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk Elaboration.Target.compileComptime(.{
        .label = "world-surface-ports-target",
        .input = elaboration_input,
        .residual_program = Program,
        .policy = Elaboration.Target.Policy.auditOnly(),
    });
};

fn runFixture(allocator: std.mem.Allocator) !i32 {
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();
    const request = switch (try session.next()) {
        .request => |value| value,
        .after => return error.UnexpectedAfter,
        .done => return error.UnexpectedDone,
    };
    const world_port_id = Target.WorldDispatchTable.lookup(request.operation_site_index) orelse return error.MissingWorldPort;
    if (world_port_id != 0) return error.UnexpectedWorldPort;
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
    Target.assertNormalForm(.world_ports_only);
    Target.assertWorldSurfaceReady();
    Target.assertNoSearchHotPath();
    const final = try runFixture(std.heap.page_allocator);
    try writer.print("world_surface_fingerprint={x}\n", .{Target.WorldSurface.surface_fingerprint});
    try writer.print("world_port_id={d}\n", .{Target.WorldPortTable.entries[0].world_port_id});
    try writer.print("residual_site_fingerprint={x}\n", .{Target.WorldPortTable.entries[0].residual_site_fingerprint});
    try writer.print("source_effect_shape_fingerprint={x}\n", .{source_shape.fingerprint});
    try writer.print("final_result={d}\n", .{final});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
