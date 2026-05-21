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
    .label = "boundary-closure-strict-source",
    .ir_hash = 0x636c6f73747201,
    .entry = "run",
    .requirements = &.{ApprovalRows.requirement},
    .ops = &ApprovalRows.ops,
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
                semantic.constString("payload", "deploy-prod"),
                semantic.call(ApprovalRequestOp, .{ .dst = "decision", .payload = "payload", .label = "approval.request" }),
            },
            .terminator = semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid strict closure source: " ++ @errorName(err));

const SourceBody = struct {
    pub const site_metadata = source_compiled.site_metadata;
    pub const compiled_plan = source_compiled.plan;
};
const SourceProgram = boundary.program("boundary-closure-strict-source", SourceHandlers, SourceBody);
const ApprovalRequest = SourceProgram.protocol.operationSite("approval", "request", 0);

const handler_compiled = semantic.finish(.{
    .label = "boundary-closure-strict-handler",
    .ir_hash = 0x636c6f73746801,
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
}) catch |err| @compileError("invalid strict closure handler: " ++ @errorName(err));

const HandlerBody = struct {
    pub const compiled_plan = handler_compiled.plan;
};
const HandlerProgram = boundary.program("boundary-closure-strict-handler", struct {}, HandlerBody);

const ApprovalDecl = SourceProgram.Exchange.ProviderHandler.program(.{
    .label = "approval-program-handler",
    .op = ApprovalRequest,
    .program = HandlerProgram,
    .map_request = .payload_to_args,
    .map_result = .result_to_resume,
});
const Harness = SourceProgram.Exchange.ProviderHarness(.{
    .label = "approval-program-provider",
    .provider_fingerprint = @as(?u64, 0x8801),
    .entries = .{ApprovalDecl},
});

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    const Closure = SourceProgram.BoundaryClosure;
    const root_shapes = Closure.effectShapesForProgram(SourceProgram, .operation);
    var catalog = try Harness.buildCatalog(allocator);
    defer catalog.deinit();
    var capability = try SourceProgram.Exchange.Capability.encode(allocator, .{
        .issuer_label = "closure-host",
        .provider_fingerprint = Harness.provider_fingerprint,
        .manifest_fingerprint = catalog.manifest.fingerprint,
        .allowed_request_kinds = .{ .operation = true },
        .allowed_operation_sites = &.{ApprovalRequest.index},
        .allowed_protocol_op_fingerprints = &.{ApprovalRequest.fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"request"},
    });
    defer capability.deinit();
    const providers = [_]SourceProgram.Exchange.ProviderManifest{catalog.provider_manifest};
    const offers = [_]SourceProgram.Exchange.ProviderOffer{catalog.provider_offers[0]};
    const capabilities = [_]SourceProgram.Exchange.Capability{capability};
    var closure = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = root_shapes[0..1],
        .provider_manifests = providers[0..],
        .provider_offers = offers[0..],
        .capabilities = capabilities[0..],
        .policy = Closure.Policy.strict(),
        .root_program_refs = &.{SourceProgram.Evidence.refFor(SourceProgram.Evidence.domains.program_plan, SourceProgram.compiled_plan.hash(), .{ .label = SourceProgram.contract.label })},
        .provider_harness_refs = &.{SourceProgram.Evidence.refForProviderHarness(Harness)},
    });
    defer closure.deinit();
    try closure.assertClosed();
    try writer.print("closure_certificate_fingerprint={x}\n", .{closure.certificate.certificate_fingerprint});
    try writer.print("closed_effect_shape_count={}\n", .{closure.report.closed_effect_shape_count});
    try writer.print("provider_program_count=1\n", .{});
    try writer.print("host_intrinsic_count={}\n", .{closure.report.host_intrinsic_count});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
