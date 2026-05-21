// zlinter-disable declaration_naming field_ordering require_doc_comment no_inferred_error_unions
const boundary = @import("boundary");
const std = @import("std");

const Handlers = struct {};
const ApprovalProtocol = boundary.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{boundary.ir.schema.transform("request", []const u8, i32)},
});
const Rows = ApprovalProtocol.Rows(Handlers, .{ .requirement_index = 0, .first_op = 0 });
const semantic = boundary.ir.builder.semantic;
const Request = Rows.op("request");
const compiled = boundary.ir.builder.semantic.finish(.{
    .label = "provider-harness-replayable",
    .ir_hash = 0x70726f76696403,
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
}) catch |err| @compileError("invalid provider harness replayable example: " ++ @errorName(err));

const Body = struct {
    pub const site_metadata = compiled.site_metadata;
    pub const compiled_plan = compiled.plan;
};
const Program = boundary.program("provider-harness-replayable", Handlers, Body);
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
    replayed: usize = 0,
};

fn handleApproval(ctx: *ProviderCtx, request: anytype) !Outcome {
    const payload = try request.payload(ctx.allocator);
    defer ctx.allocator.free(payload);
    if (!std.mem.eql(u8, payload, "deploy-prod")) return .{ .reject = "unknown approval payload" };
    ctx.replayed += 1;
    return .{ .replay = 7 };
}

const ApprovalDecl = Program.Exchange.ProviderHandler.operation(ApprovalRequest, handleApproval, .{
    .label = "approval-replay",
    .supported_usage_modes = .{ .copyable = false, .replayable = true },
    .supported_response_uses = .{ .fresh = false, .replayed = true, .deterministic_replay = false, .override = false },
    .supported_replay_policies = .{ .fresh = false, .replayed = true, .deterministic_replay = false, .override = false },
});
const Harness = Program.Exchange.ProviderHarness(.{
    .label = "approval-replay-provider",
    .provider_fingerprint = @as(?u64, 0x7103),
    .entries = .{ApprovalDecl},
});

fn nextEnvelope(allocator: std.mem.Allocator, runtime: *boundary.Runtime) !struct {
    session: Program.Session,
    envelope: Program.Exchange.RequestEnvelope,
} {
    var session = try Program.Session.start(runtime, .{});
    errdefer session.deinit();
    const request = switch (try session.next()) {
        .request => |value| value,
        .after => return error.UnexpectedAfter,
        .done => return error.UnexpectedDone,
    };
    var envelope = try Program.Exchange.RequestEnvelope.fromRequest(allocator, request, .{});
    errdefer envelope.deinit();
    return .{ .session = session, .envelope = envelope };
}

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

    var first = try nextEnvelope(allocator, &runtime);
    defer first.session.deinit();
    defer first.envelope.deinit();
    var journal = Program.Session.Journal.init(allocator);
    defer journal.deinit();
    const first_current = try first.session.current();
    const first_typed_request = try first_current.request.as(ApprovalRequest);
    const recorded_response_trace = try first_typed_request.responseTrace(.@"resume", @as(i32, 7));
    try journal.appendRequest(.{ .operation = first_current.request.trace() });
    try journal.appendResponseValue(recorded_response_trace, @as(i32, 7));
    try journal.appendDone(recorded_response_trace.response_value_fingerprint);
    var replay_source_envelope = try Program.Exchange.RequestEnvelope.fromRequest(allocator, first_current.request, .{
        .usage_metadata = .{ .usage = .replayable, .branch_id = 7, .replay_policy = .replayed },
    });
    defer replay_source_envelope.deinit();
    var replay_source_response = try Program.Exchange.ResponseEnvelope.@"resume"(allocator, replay_source_envelope, @as(i32, 7));
    defer replay_source_response.deinit();

    var second = try nextEnvelope(allocator, &runtime);
    defer second.session.deinit();
    defer second.envelope.deinit();
    var treaty_request = Program.Exchange.TreatyRequest.fromRequest(second.envelope);
    treaty_request.requested_usage_mode = .replayable;
    treaty_request.requested_response_use = .replayed;
    treaty_request.requested_replay_policy = .replayed;
    treaty_request.require_least_authority = false;
    var resolved = try Program.Exchange.TreatyResolver.resolve(.{
        .allocator = allocator,
        .request = second.envelope,
        .manifest = catalog.manifest,
        .provider_manifests = providers[0..],
        .provider_offers = offers[0..],
        .capabilities = capabilities[0..],
        .treaty_request = treaty_request,
        .treaty_policy = .{ .require_least_authority = false, .require_replay_only_response = true },
    });
    defer resolved.deinit();
    const treaty = resolved.treaty orelse return error.ExpectedTreaty;

    var replayer = journal.replayer();
    defer replayer.deinit();
    const replayed = try replayer.expectCurrentResponseValue(try second.session.current(), i32);
    var ctx = ProviderCtx{ .allocator = allocator };
    var handled = try Harness.handle(&ctx, allocator, second.envelope, treaty.certificate, .{
        .treaty = treaty,
        .replay_source_journal = &journal,
        .replay_source_response_trace = replayed.trace,
        .replay_source_response = replay_source_response,
        .replay_source_response_fingerprint = replay_source_response.fingerprint,
        .replay_source_response_value_fingerprint = replayed.trace.response_value_fingerprint,
    });
    const authorization_fingerprint = switch (handled) {
        .response => |*packet| blk: {
            defer packet.deinit();
            try Program.Exchange.applyResponse(&second.session, packet.response, .{});
            break :blk packet.treaty_authorization.authorization_fingerprint;
        },
        else => return error.ExpectedProviderResponse,
    };
    var final = switch (try second.session.next()) {
        .done => |done| done,
        else => return error.ExpectedDone,
    };
    defer final.deinit();
    try replayer.expectDone(replayed.trace.response_value_fingerprint);

    try writer.print("replay_policy={s}\n", .{@tagName(treaty.replay_policy)});
    try writer.print("source_response_fingerprint={x}\n", .{replay_source_response.fingerprint});
    try writer.print("response_authorization_fingerprint={x}\n", .{authorization_fingerprint});
    try writer.print("provider_replays={d}\n", .{ctx.replayed});
    try writer.print("final_result={d}\n", .{final.value});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
