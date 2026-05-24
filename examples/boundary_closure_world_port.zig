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
    .label = "boundary-closure-world-port",
    .ir_hash = 0x776f726c647001,
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
}) catch |err| @compileError("invalid world-port closure source: " ++ @errorName(err));

const Body = struct {
    pub const site_metadata = compiled.site_metadata;
    pub const compiled_plan = compiled.plan;
};
const Program = boundary.program("boundary-closure-world-port", Handlers, Body);
const ApprovalRequest = Program.protocol.operationSite("approval", "request", 0);

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

const ApprovalDecl = Program.Exchange.ProviderHandler.intrinsicOperation(ApprovalRequest, hostApproval, .{
    .label = "approval-host-human",
    .tags = &.{"host_human"},
    .metadata = "host human approval boundary",
});
const Harness = Program.Exchange.ProviderHarness(.{
    .label = "approval-host-human-provider",
    .provider_fingerprint = @as(?u64, 0x8821),
    .entries = .{ApprovalDecl},
});

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    const Closure = Program.BoundaryClosure;
    const root_shapes = Closure.effectShapesForProgram(Program, .operation);
    var catalog = try Harness.buildCatalog(allocator);
    defer catalog.deinit();
    var capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "world-host",
        .provider_fingerprint = Harness.provider_fingerprint,
        .manifest_fingerprint = catalog.manifest.fingerprint,
        .allowed_request_kinds = .{ .operation = true },
        .allowed_operation_sites = &.{ApprovalRequest.index},
        .allowed_protocol_op_fingerprints = &.{ApprovalRequest.fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"request"},
    });
    defer capability.deinit();
    const providers = [_]Program.Exchange.ProviderManifest{catalog.provider_manifest};
    const offers = [_]Program.Exchange.ProviderOffer{catalog.provider_offers[0]};
    const capabilities = [_]Program.Exchange.Capability{capability};
    const root_ref = Program.Evidence.refFor(Program.Evidence.domains.program_plan, Program.compiled_plan.hash(), .{ .label = Program.contract.label });
    const intrinsic_ref = offers[0].hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
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

    var strict_policy = Closure.Policy.strict();
    strict_policy.require_root_program_refs = true;
    var strict = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = root_shapes[0..1],
        .root_program_refs = &.{root_ref},
        .provider_manifests = providers[0..],
        .provider_offers = offers[0..],
        .capabilities = capabilities[0..],
        .policy = strict_policy,
    });
    defer strict.deinit();

    var policy = Closure.Policy.worldBoundary();
    policy.require_root_program_refs = true;
    const allowed_ports = [_]u64{port.fingerprint};
    policy.allowed_world_port_fingerprints = allowed_ports[0..];
    var world = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = root_shapes[0..1],
        .root_program_refs = &.{root_ref},
        .provider_manifests = providers[0..],
        .provider_offers = offers[0..],
        .capabilities = capabilities[0..],
        .policy = policy,
        .world_ports = ports[0..],
    });
    defer world.deinit();
    try world.assertClosedExceptWorldPorts();
    try writer.print("intrinsic_fingerprint={x}\n", .{intrinsic_ref.fingerprint});
    try writer.print("world_port_fingerprint={x}\n", .{port.fingerprint});
    try writer.print("strict_blocker_count={}\n", .{strict.report.blocker_count});
    try writer.print("world_boundary_certificate_fingerprint={x}\n", .{world.certificate.certificate_fingerprint});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
