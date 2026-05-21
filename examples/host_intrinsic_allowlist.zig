// zlinter-disable declaration_naming field_ordering require_doc_comment no_hidden_allocations no_inferred_error_unions
const ability = @import("ability");
const std = @import("std");

const Handlers = struct {};
const semantic = ability.ir.builder.semantic;
const ApprovalProtocol = ability.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{ability.ir.schema.transform("request", []const u8, i32)},
});
const Rows = ApprovalProtocol.Rows(Handlers, .{ .requirement_index = 0, .first_op = 0 });
const RequestOp = Rows.op("request");
const compiled = semantic.finish(.{
    .label = "host-intrinsic-allowlist",
    .ir_hash = 0x686f7374696e01,
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
}) catch |err| @compileError("invalid host intrinsic allowlist example: " ++ @errorName(err));

const Body = struct {
    pub const site_metadata = compiled.site_metadata;
    pub const compiled_plan = compiled.plan;
};
const Program = ability.program("host-intrinsic-allowlist", Handlers, Body);
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

const ProviderCtx = struct {
    allocator: std.mem.Allocator,
};

fn hostToolApproval(ctx: *ProviderCtx, request: anytype) !Outcome {
    const payload = try request.payload(ctx.allocator);
    defer ctx.allocator.free(payload);
    if (!std.mem.eql(u8, payload, "deploy-prod")) return .{ .reject = "unexpected approval payload" };
    return .{ .@"resume" = 7 };
}

const ApprovalDecl = Program.Exchange.ProviderHandler.intrinsicOperation(ApprovalRequest, hostToolApproval, .{
    .label = "approval-host-tool",
    .tags = &.{"host_tool"},
    .metadata = "opaque host approval callback",
});
const Harness = Program.Exchange.ProviderHarness(.{
    .label = "approval-host-tool-provider",
    .provider_fingerprint = @as(?u64, 0x7721),
    .entries = .{ApprovalDecl},
});

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    var runtime = ability.Runtime.init(allocator);
    defer runtime.deinit();
    var catalog = try Harness.buildCatalog(allocator);
    defer catalog.deinit();

    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();
    const request = switch (try session.next()) {
        .request => |value| value,
        .after => return error.UnexpectedAfter,
        .done => return error.UnexpectedDone,
    };
    var envelope = try Program.Exchange.RequestEnvelope.fromRequest(allocator, request, .{});
    defer envelope.deinit();
    var capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "host",
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
    const intrinsic = offers[0].hostIntrinsic() orelse return error.ExpectedIntrinsic;
    var world_policy = Program.Evidence.DefunctionalizationPolicy.worldBoundary();
    const allowed_fingerprints = [_]u64{intrinsic.fingerprint};
    world_policy.allowed_intrinsic_fingerprints = allowed_fingerprints[0..];

    var strict = try Program.Exchange.TreatyResolver.resolve(.{
        .allocator = allocator,
        .request = envelope,
        .manifest = catalog.manifest,
        .provider_manifests = providers[0..],
        .provider_offers = offers[0..],
        .capabilities = capabilities[0..],
        .treaty_policy = .{ .defunctionalization_policy = Program.Evidence.DefunctionalizationPolicy.strict() },
    });
    defer strict.deinit();
    var allowed = try Program.Exchange.TreatyResolver.resolve(.{
        .allocator = allocator,
        .request = envelope,
        .manifest = catalog.manifest,
        .provider_manifests = providers[0..],
        .provider_offers = offers[0..],
        .capabilities = capabilities[0..],
        .treaty_policy = .{ .defunctionalization_policy = world_policy },
    });
    defer allowed.deinit();
    const treaty = allowed.treaty orelse return error.ExpectedTreaty;

    var ctx = ProviderCtx{ .allocator = allocator };
    const provider_result = try Harness.handle(&ctx, allocator, envelope, treaty.certificate, .{ .treaty = treaty });
    switch (provider_result) {
        .response => |packet| {
            var owned = packet;
            defer owned.deinit();
            try Program.Exchange.applyResponse(&session, owned.response, .{});
        },
        else => return error.ExpectedProviderResponse,
    }
    var final = switch (try session.next()) {
        .done => |done| done,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer final.deinit();

    try writer.print("intrinsic_label={s}\n", .{intrinsic.label});
    try writer.print("intrinsic_fingerprint={x}\n", .{intrinsic.fingerprint});
    try writer.print("strict_policy={s}\n", .{strict.blockers.firstTagName() orelse @tagName(strict.status)});
    try writer.print("allowlist_policy={s}\n", .{@tagName(allowed.status)});
    try writer.print("final_result={d}\n", .{final.value});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
