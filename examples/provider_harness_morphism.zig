// zlinter-disable declaration_naming field_ordering require_doc_comment no_inferred_error_unions
const boundary = @import("boundary");
const std = @import("std");

const Handlers = struct {};
const ApprovalProtocol = boundary.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{boundary.ir.schema.transform("request", []const u8, i32)},
});
const Rows = ApprovalProtocol.Rows(Handlers, .{ .requirement_index = 0, .first_op = 0 });
const PolicyProtocol = boundary.ir.schema.Protocol(.{
    .label = "policy",
    .ops = .{boundary.ir.schema.transform("check", []const u8, i32)},
});
const PolicyCheck = PolicyProtocol.operation("check", .{});
const semantic = boundary.ir.builder.semantic;
const Request = Rows.op("request");
const compiled = boundary.ir.builder.semantic.finish(.{
    .label = "provider-harness-morphism",
    .ir_hash = 0x70726f76696402,
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
                semantic.call(Request, .{ .dst = "decision", .payload = "payload", .label = "approval.request" }),
            },
            .terminator = semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid provider harness morphism example: " ++ @errorName(err));

const Body = struct {
    pub const site_metadata = compiled.site_metadata;
    pub const compiled_plan = compiled.plan;
};
const Program = boundary.program("provider-harness-morphism", Handlers, Body);
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
    policy_checks: usize = 0,
};

fn handlePolicy(ctx: *ProviderCtx, request: anytype) !Outcome {
    try std.testing.expectEqual(PolicyCheck.fingerprint, request.target_protocol_op_fingerprint);
    const payload = try request.payload(ctx.allocator);
    defer ctx.allocator.free(payload);
    if (!std.mem.eql(u8, payload, "deploy-prod")) return .{ .reject = "policy denied unknown payload" };
    ctx.policy_checks += 1;
    return .{ .@"resume" = 1 };
}

const PolicyDecl = Program.Exchange.ProviderHandler.operation(ApprovalRequest, handlePolicy, .{
    .label = "policy-check",
    .protocol_label = "policy",
    .protocol_op_fingerprint = PolicyCheck.fingerprint,
    .supported_usage_modes = .{ .copyable = false },
    .supported_response_uses = .{ .replayed = false, .deterministic_replay = false, .override = false },
});
const Harness = Program.Exchange.ProviderHarness(.{
    .label = "policy-provider",
    .provider_fingerprint = @as(?u64, 0x7202),
    .entries = .{PolicyDecl},
});

const Outbox = struct {
    allocator: std.mem.Allocator,
    requests: std.ArrayList(Program.Exchange.RequestEnvelope) = .empty,
    certificates: std.ArrayList(Program.Exchange.Treaty.Certificate) = .empty,

    fn deinit(self: *@This()) void {
        for (self.requests.items) |*request| request.deinit();
        for (self.certificates.items) |*certificate| certificate.deinit(self.allocator);
        self.requests.deinit(self.allocator);
        self.certificates.deinit(self.allocator);
    }

    pub fn appendTreaty(self: *@This(), request: Program.Exchange.RequestEnvelope, certificate: Program.Exchange.Treaty.Certificate) !void {
        var owned_request = request;
        var owned_certificate = certificate;
        var request_owned = true;
        var certificate_owned = true;
        errdefer if (request_owned) owned_request.deinit();
        errdefer if (certificate_owned) owned_certificate.deinit(self.allocator);
        try self.requests.append(self.allocator, owned_request);
        request_owned = false;
        errdefer {
            var appended_request = self.requests.pop().?;
            appended_request.deinit();
        }
        try self.certificates.append(self.allocator, owned_certificate);
        certificate_owned = false;
    }
};

const Inbox = struct {
    response: ?Program.Exchange.ResponseEnvelope = null,

    fn deinit(self: *@This()) void {
        if (self.response) |*response| response.deinit();
    }

    pub fn nextResponse(self: *@This()) !?Program.Exchange.ResponseEnvelope {
        const response = self.response orelse return null;
        self.response = null;
        return response;
    }
};

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var catalog = try Harness.buildCatalog(allocator);
    defer catalog.deinit();
    var capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "host",
        .provider_fingerprint = Harness.provider_fingerprint,
        .manifest_fingerprint = catalog.manifest.fingerprint,
    });
    defer capability.deinit();
    const morphism = Program.Exchange.MorphismOffer{
        .label = "approval.request-as-policy.check",
        .source_site_fingerprint = ApprovalRequest.fingerprint,
        .source_protocol_op_fingerprint = ApprovalRequest.fingerprint,
        .target_protocol_op_fingerprint = PolicyCheck.fingerprint,
        .dynamic_morphism_fingerprint = 0x7702,
        .target_usage = .linear,
        .source_response_refs = &.{ApprovalRequest.resume_ref},
        .target_response_refs = &.{ApprovalRequest.resume_ref},
    };
    const providers = [_]Program.Exchange.ProviderManifest{catalog.provider_manifest};
    const offers = [_]Program.Exchange.ProviderOffer{catalog.provider_offers[0]};
    const capabilities = [_]Program.Exchange.Capability{capability};
    const morphisms = [_]Program.Exchange.MorphismOffer{morphism};

    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();
    var outbox = Outbox{ .allocator = allocator };
    defer outbox.deinit();
    var inbox = Inbox{};
    defer inbox.deinit();
    var runner = Program.Exchange.MailboxRunner{};
    defer runner.deinit();

    var parked = try runner.runTreatyStep(&session, &outbox, &inbox, .{
        .allocator = allocator,
        .manifest = catalog.manifest,
        .provider_manifests = providers[0..],
        .provider_offers = offers[0..],
        .capabilities = capabilities[0..],
        .morphism_offers = morphisms[0..],
    });
    const source_request_fingerprint = switch (parked) {
        .parked => |*request| blk: {
            const fp = request.request_fingerprint;
            request.deinit();
            break :blk fp;
        },
        else => return error.ExpectedRequest,
    };
    const treaty = runner.last_treaty.?;
    if (treaty.handling != .dynamic_morphism) return error.ExpectedMorphismTreaty;
    const treaty_fingerprint = treaty.fingerprint;
    const morphism_fingerprint = morphism.fingerprint();

    var ctx = ProviderCtx{ .allocator = allocator };
    const provider_result = try Harness.handle(&ctx, allocator, outbox.requests.items[0], outbox.certificates.items[0], .{ .treaty = treaty });
    const authorization_fingerprint = switch (provider_result) {
        .response => |packet| blk: {
            inbox.response = packet.response;
            break :blk packet.treaty_authorization.authorization_fingerprint;
        },
        else => return error.ExpectedProviderResponse,
    };
    _ = try runner.runTreatyStep(&session, &outbox, &inbox, .{
        .allocator = allocator,
        .manifest = catalog.manifest,
        .provider_manifests = providers[0..],
        .provider_offers = offers[0..],
        .capabilities = capabilities[0..],
        .morphism_offers = morphisms[0..],
    });
    var final = switch (try runner.runTreatyStep(&session, &outbox, &inbox, .{ .allocator = allocator, .manifest = catalog.manifest })) {
        .done => |done| done,
        else => return error.ExpectedDone,
    };
    defer final.deinit();

    try writer.print("source_request_fingerprint={x}\n", .{source_request_fingerprint});
    try writer.print("target_protocol_op_fingerprint={x}\n", .{PolicyCheck.fingerprint});
    try writer.print("morphism_fingerprint={x}\n", .{morphism_fingerprint});
    try writer.print("treaty_fingerprint={x}\n", .{treaty_fingerprint});
    try writer.print("response_authorization_fingerprint={x}\n", .{authorization_fingerprint});
    try writer.print("policy_checks={d}\n", .{ctx.policy_checks});
    try writer.print("handling={s}\n", .{@tagName(treaty.handling)});
    try writer.print("provider_usage={s}\n", .{@tagName(treaty.provider_usage)});
    try writer.print("final_result={d}\n", .{final.value});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
