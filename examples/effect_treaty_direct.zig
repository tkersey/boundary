// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions
const boundary = @import("boundary");
const std = @import("std");

const Handlers = struct {};

const ApprovalProtocol = boundary.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{
        boundary.ir.schema.transform("request", []const u8, i32),
    },
});

const Rows = ApprovalProtocol.Rows(Handlers, .{
    .requirement_index = 0,
    .first_op = 0,
});

const semantic_spec = blk: {
    const semantic = boundary.ir.builder.semantic;
    const Request = Rows.op("request");

    break :blk .{
        .label = "effect-treaty-direct",
        .ir_hash = 0x74726561747901,
        .entry = "run",
        .requirements = &.{Rows.requirement},
        .ops = &Rows.ops,
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
                    semantic.call(Request, .{ .dst = "decision", .payload = "payload", .label = "approval.request" }),
                },
                .terminator = semantic.returnValue("decision"),
            }},
        }},
    };
};

const compiled = boundary.ir.builder.semantic.finish(semantic_spec) catch |err|
    @compileError("invalid treaty direct example: " ++ @errorName(err));

const Body = struct {
    pub const site_metadata = compiled.site_metadata;
    pub const compiled_plan = compiled.plan;
};

const Program = boundary.program("effect-treaty-direct", Handlers, Body);
const ApprovalRequest = Program.protocol.operationSite("approval", "request", 0);

const Outbox = struct {
    allocator: std.mem.Allocator,
    requests: std.ArrayList(Program.Exchange.RequestEnvelope) = .empty,
    treaty_fingerprint: u64 = 0,
    certificate_fingerprint: u64 = 0,

    fn deinit(self: *@This()) void {
        for (self.requests.items) |*request| request.deinit();
        self.requests.deinit(self.allocator);
    }

    pub fn appendTreaty(self: *@This(), request: Program.Exchange.RequestEnvelope, certificate: Program.Exchange.Treaty.Certificate) !void {
        try self.requests.append(self.allocator, request);
        var owned_certificate = certificate;
        defer owned_certificate.deinit(self.allocator);
        self.treaty_fingerprint = owned_certificate.treaty_fingerprint;
        self.certificate_fingerprint = owned_certificate.certificate_fingerprint;
    }
};

const Inbox = struct {
    response: ?Program.Exchange.ResponseEnvelope = null,

    fn deinit(self: *@This()) void {
        if (self.response) |*response| response.deinit();
        self.response = null;
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

    var manifest = try Program.Exchange.Manifest.encode(allocator);
    defer manifest.deinit();
    var provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "approval-provider",
        .provider_fingerprint = 0x7101,
        .supported_program_manifest_fingerprints = &.{manifest.fingerprint},
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{ApprovalRequest.index},
        .supported_protocol_op_fingerprints = &.{ApprovalRequest.fingerprint},
    });
    defer provider.deinit();
    var offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "approval-direct-offer",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{ApprovalRequest.index},
        .supported_protocol_op_fingerprints = &.{ApprovalRequest.fingerprint},
        .produced_response_refs = &.{ApprovalRequest.resume_ref},
    });
    defer offer.deinit();
    var capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "host",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
    });
    defer capability.deinit();

    const providers = [_]Program.Exchange.ProviderManifest{provider};
    const offers = [_]Program.Exchange.ProviderOffer{offer};
    const capabilities = [_]Program.Exchange.Capability{capability};

    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();
    var outbox = Outbox{ .allocator = allocator };
    defer outbox.deinit();
    var inbox = Inbox{};
    defer inbox.deinit();
    var runner = Program.Exchange.MailboxRunner{};
    defer runner.deinit();
    var journal = Program.Session.Journal.init(allocator);
    defer journal.deinit();

    var parked = try runner.runTreatyStep(&session, &outbox, &inbox, .{
        .allocator = allocator,
        .manifest = manifest,
        .provider_manifests = providers[0..],
        .provider_offers = offers[0..],
        .capabilities = capabilities[0..],
        .treaty_policy = .{ .require_capability_attenuation = true },
        .journal = &journal,
    });
    switch (parked) {
        .parked => |*request| request.deinit(),
        else => return error.ExpectedRequest,
    }

    const treaty = runner.last_treaty.?;
    const treaty_fingerprint = treaty.fingerprint;
    const attenuated_capability_fingerprint = treaty.certificate.attenuated_capability_fingerprint.?;
    const route_fingerprint = treaty.route.fingerprint;
    inbox.response = try Program.Exchange.ResponseEnvelope.@"resume"(allocator, outbox.requests.items[0], @as(i32, 1));
    try inbox.response.?.authorizeTreaty(treaty, .fresh);
    _ = try runner.runTreatyStep(&session, &outbox, &inbox, .{
        .allocator = allocator,
        .manifest = manifest,
        .provider_manifests = providers[0..],
        .provider_offers = offers[0..],
        .capabilities = capabilities[0..],
        .treaty_policy = .{ .require_capability_attenuation = true },
    });
    var final = switch (try runner.runTreatyStep(&session, &outbox, &inbox, .{ .allocator = allocator, .manifest = manifest })) {
        .done => |done| done,
        else => return error.ExpectedDone,
    };
    defer final.deinit();

    try writer.print("treaty_fingerprint={x}\n", .{treaty_fingerprint});
    try writer.print("provider_offer_fingerprint={x}\n", .{offer.fingerprint});
    try writer.print("attenuated_capability_fingerprint={x}\n", .{attenuated_capability_fingerprint});
    try writer.print("route_fingerprint={x}\n", .{route_fingerprint});
    try writer.print("obligation_fingerprint=none\n", .{});
    try writer.print("final_result={d}\n", .{final.value});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
