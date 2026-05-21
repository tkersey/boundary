// zlinter-disable declaration_naming field_ordering require_doc_comment no_hidden_allocations no_inferred_error_unions
const boundary = @import("boundary");
const std = @import("std");

const RootHandlers = struct {};
const ProviderHandlers = struct {};
const semantic = boundary.ir.builder.semantic;

const ApprovalProtocol = boundary.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{boundary.ir.schema.transform("request", []const u8, i32)},
});
const ApprovalRows = ApprovalProtocol.Rows(RootHandlers, .{ .requirement_index = 0, .first_op = 0 });
const ApprovalRequestOp = ApprovalRows.op("request");

const root_compiled = semantic.finish(.{
    .label = "boundary-closure-nested-root",
    .ir_hash = 0x6e657374726f01,
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
}) catch |err| @compileError("invalid nested closure root: " ++ @errorName(err));

const RootBody = struct {
    pub const site_metadata = root_compiled.site_metadata;
    pub const compiled_plan = root_compiled.plan;
};
const RootProgram = boundary.program("boundary-closure-nested-root", RootHandlers, RootBody);
const ApprovalRequest = RootProgram.protocol.operationSite("approval", "request", 0);

const PolicyProtocol = boundary.ir.schema.Protocol(.{
    .label = "policy",
    .ops = .{boundary.ir.schema.transform("check", []const u8, i32)},
});
const PolicyRows = PolicyProtocol.Rows(ProviderHandlers, .{ .requirement_index = 0, .first_op = 0 });
const PolicyCheckOp = PolicyRows.op("check");

const approval_handler_compiled = semantic.finish(.{
    .label = "boundary-closure-nested-approval-provider",
    .ir_hash = 0x6e657374617001,
    .entry = "run",
    .requirements = &.{PolicyRows.requirement},
    .ops = &PolicyRows.ops,
    .functions = .{.{
        .symbol_name = "run",
        .requirements = semantic.span(0, 1),
        .params = .{semantic.param("payload", []const u8)},
        .locals = .{semantic.local("decision", i32)},
        .result = i32,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{semantic.call(PolicyCheckOp, .{ .dst = "decision", .payload = "payload", .label = "policy.check" })},
            .terminator = semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid nested approval provider: " ++ @errorName(err));

const ApprovalProviderBody = struct {
    pub const site_metadata = approval_handler_compiled.site_metadata;
    pub const compiled_plan = approval_handler_compiled.plan;
};
const ApprovalProviderProgram = boundary.program("boundary-closure-nested-approval-provider", ProviderHandlers, ApprovalProviderBody);
const PolicyCheck = ApprovalProviderProgram.protocol.operationSite("policy", "check", 0);

const policy_handler_compiled = semantic.finish(.{
    .label = "boundary-closure-nested-policy-provider",
    .ir_hash = 0x6e657374706f01,
    .entry = "run",
    .functions = .{.{
        .symbol_name = "run",
        .params = .{semantic.param("payload", []const u8)},
        .locals = .{semantic.local("decision", i32)},
        .result = i32,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{semantic.constI32("decision", 7)},
            .terminator = semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid nested policy provider: " ++ @errorName(err));

const PolicyProviderBody = struct {
    pub const compiled_plan = policy_handler_compiled.plan;
};
const PolicyProviderProgram = boundary.program("boundary-closure-nested-policy-provider", struct {}, PolicyProviderBody);

const ApprovalDecl = RootProgram.Exchange.ProviderHandler.program(.{
    .label = "approval-program-handler",
    .op = ApprovalRequest,
    .program = ApprovalProviderProgram,
    .map_request = .payload_to_args,
    .map_result = .result_to_resume,
});
const ApprovalHarness = RootProgram.Exchange.ProviderHarness(.{
    .label = "approval-program-provider",
    .provider_fingerprint = @as(?u64, 0x8831),
    .entries = .{ApprovalDecl},
});

const PolicyDecl = ApprovalProviderProgram.Exchange.ProviderHandler.program(.{
    .label = "policy-program-handler",
    .op = PolicyCheck,
    .program = PolicyProviderProgram,
    .map_request = .payload_to_args,
    .map_result = .result_to_resume,
});
const PolicyHarness = ApprovalProviderProgram.Exchange.ProviderHarness(.{
    .label = "policy-program-provider",
    .provider_fingerprint = @as(?u64, 0x8832),
    .entries = .{PolicyDecl},
});

fn analyzeRoot(allocator: std.mem.Allocator, writer: anytype) !u64 {
    const Closure = RootProgram.BoundaryClosure;
    const root_shapes = Closure.effectShapesForProgram(RootProgram, .operation);
    var catalog = try ApprovalHarness.buildCatalog(allocator);
    defer catalog.deinit();
    var capability = try RootProgram.Exchange.Capability.encode(allocator, .{
        .issuer_label = "nested-root",
        .provider_fingerprint = ApprovalHarness.provider_fingerprint,
        .manifest_fingerprint = catalog.manifest.fingerprint,
        .allowed_request_kinds = .{ .operation = true },
        .allowed_operation_sites = &.{ApprovalRequest.index},
        .allowed_protocol_op_fingerprints = &.{ApprovalRequest.fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"request"},
    });
    defer capability.deinit();
    const providers = [_]RootProgram.Exchange.ProviderManifest{catalog.provider_manifest};
    const offers = [_]RootProgram.Exchange.ProviderOffer{catalog.provider_offers[0]};
    const capabilities = [_]RootProgram.Exchange.Capability{capability};
    var closure = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = root_shapes[0..1],
        .provider_manifests = providers[0..],
        .provider_offers = offers[0..],
        .capabilities = capabilities[0..],
        .policy = Closure.Policy.strict(),
    });
    defer closure.deinit();
    try closure.assertClosed();
    try writer.print("root_effect_shape_fingerprint={x}\n", .{root_shapes[0].fingerprint});
    try writer.print("root_static_treaty_plan={x}\n", .{closure.static_treaty_plans[0].fingerprint});
    return closure.certificate.certificate_fingerprint;
}

fn analyzeNested(allocator: std.mem.Allocator, writer: anytype) !u64 {
    const Closure = ApprovalProviderProgram.BoundaryClosure;
    const nested_shapes = Closure.effectShapesForProgram(ApprovalProviderProgram, .operation);
    var catalog = try PolicyHarness.buildCatalog(allocator);
    defer catalog.deinit();
    var capability = try ApprovalProviderProgram.Exchange.Capability.encode(allocator, .{
        .issuer_label = "nested-provider",
        .provider_fingerprint = PolicyHarness.provider_fingerprint,
        .manifest_fingerprint = catalog.manifest.fingerprint,
        .allowed_request_kinds = .{ .operation = true },
        .allowed_operation_sites = &.{PolicyCheck.index},
        .allowed_protocol_op_fingerprints = &.{PolicyCheck.fingerprint},
        .allowed_requirement_labels = &.{"policy"},
        .allowed_op_names = &.{"check"},
    });
    defer capability.deinit();
    const providers = [_]ApprovalProviderProgram.Exchange.ProviderManifest{catalog.provider_manifest};
    const offers = [_]ApprovalProviderProgram.Exchange.ProviderOffer{catalog.provider_offers[0]};
    const capabilities = [_]ApprovalProviderProgram.Exchange.Capability{capability};
    var closure = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = nested_shapes[0..1],
        .provider_manifests = providers[0..],
        .provider_offers = offers[0..],
        .capabilities = capabilities[0..],
        .policy = Closure.Policy.strict(),
    });
    defer closure.deinit();
    try closure.assertClosed();
    try writer.print("nested_effect_shape_fingerprint={x}\n", .{nested_shapes[0].fingerprint});
    try writer.print("nested_static_treaty_plan={x}\n", .{closure.static_treaty_plans[0].fingerprint});
    return closure.certificate.certificate_fingerprint;
}

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    const root_certificate = try analyzeRoot(allocator, writer);
    const nested_certificate = try analyzeNested(allocator, writer);
    var builder = RootProgram.Evidence.FingerprintBuilder.init(RootProgram.Evidence.domains.boundary_closure_certificate);
    builder.fieldU64("root_certificate", root_certificate);
    builder.fieldU64("nested_certificate", nested_certificate);
    try writer.print("closure_certificate_fingerprint={x}\n", .{builder.finish()});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
