// zlinter-disable declaration_naming field_ordering require_doc_comment no_hidden_allocations no_inferred_error_unions
const ability = @import("ability");
const std = @import("std");

const SourceHandlers = struct {};
const semantic = ability.ir.builder.semantic;

const ApprovalProtocol = ability.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{ability.ir.schema.transform("request", []const u8, i32)},
});
const ApprovalRows = ApprovalProtocol.Rows(SourceHandlers, .{ .requirement_index = 0, .first_op = 0 });
const ApprovalRequestOp = ApprovalRows.op("request");

const source_compiled = semantic.finish(.{
    .label = "defunctionalization-boundary-source",
    .ir_hash = 0x646566756e6301,
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
}) catch |err| @compileError("invalid defunctionalization boundary source: " ++ @errorName(err));

const SourceBody = struct {
    pub const site_metadata = source_compiled.site_metadata;
    pub const compiled_plan = source_compiled.plan;
};
const SourceProgram = ability.program("defunctionalization-boundary-source", SourceHandlers, SourceBody);
const ApprovalRequest = SourceProgram.protocol.operationSite("approval", "request", 0);

const handler_compiled = semantic.finish(.{
    .label = "defunctionalization-boundary-program-provider",
    .ir_hash = 0x64656670726f6701,
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
}) catch |err| @compileError("invalid defunctionalization boundary provider: " ++ @errorName(err));

const HandlerBody = struct {
    pub const compiled_plan = handler_compiled.plan;
};
const HandlerProgram = ability.program("defunctionalization-boundary-program-provider", struct {}, HandlerBody);

const ProgramDecl = SourceProgram.Exchange.ProviderHandler.program(.{
    .label = "program-backed-approval",
    .op = ApprovalRequest,
    .program = HandlerProgram,
    .map_request = .payload_to_args,
    .map_result = .result_to_resume,
});
const ProgramHarness = SourceProgram.Exchange.ProviderHarness(.{
    .label = "program-backed-provider",
    .provider_fingerprint = @as(?u64, 0x7711),
    .entries = .{ProgramDecl},
});

const Outcome = union(enum) {
    forward,
    pending,
    reject: []const u8,
    replay: i32,
    @"resume": i32,
    resume_after: void,
    return_now: i32,
};

const IntrinsicCtx = struct {};

fn intrinsicApproval(_: *IntrinsicCtx, request: anytype) !Outcome {
    const payload = try request.payload();
    if (!std.mem.eql(u8, payload, "deploy-prod")) return .{ .reject = "unexpected payload" };
    return .{ .@"resume" = 2 };
}

const IntrinsicDecl = SourceProgram.Exchange.ProviderHandler.intrinsicOperation(ApprovalRequest, intrinsicApproval, .{
    .label = "intrinsic-approval",
});
const IntrinsicHarness = SourceProgram.Exchange.ProviderHarness(.{
    .label = "intrinsic-provider",
    .provider_fingerprint = @as(?u64, 0x7712),
    .entries = .{IntrinsicDecl},
});

fn capabilityFor(allocator: std.mem.Allocator, catalog: anytype, provider_fingerprint: u64) !SourceProgram.Exchange.Capability {
    return SourceProgram.Exchange.Capability.encode(allocator, .{
        .issuer_label = "host",
        .provider_fingerprint = provider_fingerprint,
        .manifest_fingerprint = catalog.manifest.fingerprint,
        .allowed_request_kinds = .{ .operation = true },
        .allowed_operation_sites = &.{ApprovalRequest.index},
        .allowed_protocol_op_fingerprints = &.{ApprovalRequest.fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"request"},
    });
}

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    var runtime = ability.Runtime.init(allocator);
    defer runtime.deinit();

    var session = try SourceProgram.Session.start(&runtime, .{});
    defer session.deinit();
    const request = switch (try session.next()) {
        .request => |value| value,
        .after => return error.UnexpectedAfter,
        .done => return error.UnexpectedDone,
    };
    var envelope = try SourceProgram.Exchange.RequestEnvelope.fromRequest(allocator, request, .{});
    defer envelope.deinit();

    var program_catalog = try ProgramHarness.buildCatalog(allocator);
    defer program_catalog.deinit();
    var intrinsic_catalog = try IntrinsicHarness.buildCatalog(allocator);
    defer intrinsic_catalog.deinit();
    var program_capability = try capabilityFor(allocator, program_catalog, ProgramHarness.provider_fingerprint);
    defer program_capability.deinit();
    var intrinsic_capability = try capabilityFor(allocator, intrinsic_catalog, IntrinsicHarness.provider_fingerprint);
    defer intrinsic_capability.deinit();

    const providers = [_]SourceProgram.Exchange.ProviderManifest{ program_catalog.provider_manifest, intrinsic_catalog.provider_manifest };
    const offers = [_]SourceProgram.Exchange.ProviderOffer{ program_catalog.provider_offers[0], intrinsic_catalog.provider_offers[0] };
    const capabilities = [_]SourceProgram.Exchange.Capability{ program_capability, intrinsic_capability };
    const intrinsic = offers[1].hostIntrinsic() orelse return error.ExpectedIntrinsic;

    var permissive = try SourceProgram.Exchange.TreatyResolver.resolve(.{
        .allocator = allocator,
        .request = envelope,
        .manifest = program_catalog.manifest,
        .provider_manifests = providers[0..],
        .provider_offers = offers[0..],
        .capabilities = capabilities[0..],
    });
    defer permissive.deinit();
    var preferred = try SourceProgram.Exchange.TreatyResolver.resolve(.{
        .allocator = allocator,
        .request = envelope,
        .manifest = program_catalog.manifest,
        .provider_manifests = providers[0..],
        .provider_offers = offers[0..],
        .capabilities = capabilities[0..],
        .treaty_policy = .{ .ambiguity_policy = .host_ordered, .prefer_program_backed_provider = true },
    });
    defer preferred.deinit();
    var strict_intrinsic = try SourceProgram.Exchange.TreatyResolver.resolve(.{
        .allocator = allocator,
        .request = envelope,
        .manifest = intrinsic_catalog.manifest,
        .provider_manifests = providers[1..],
        .provider_offers = offers[1..],
        .capabilities = capabilities[1..],
        .treaty_policy = .{ .defunctionalization_policy = SourceProgram.Evidence.DefunctionalizationPolicy.strict() },
    });
    defer strict_intrinsic.deinit();

    try writer.print("program_body={s}\n", .{offers[0].semanticBodyWithProvider(providers[0]).name()});
    try writer.print("intrinsic_body={s}\n", .{offers[1].semanticBody().name()});
    try writer.print("intrinsic_fingerprint={x}\n", .{intrinsic.fingerprint});
    try writer.print("permissive_status={s} candidates={d}\n", .{ @tagName(permissive.status), permissive.candidate_count });
    try writer.print("preferred_treaty_fingerprint={x}\n", .{preferred.treaty.?.fingerprint});
    try writer.print("preferred_provider_body={s}\n", .{preferred.treaty.?.provider_semantic_body.name()});
    try writer.print("strict_intrinsic_blocker={s}\n", .{strict_intrinsic.blockers.firstTagName() orelse "none"});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
