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
        .label = "effect-treaty-replayable",
        .ir_hash = 0x74726561747903,
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
    @compileError("invalid treaty replayable example: " ++ @errorName(err));

const Body = struct {
    pub const site_metadata = compiled.site_metadata;
    pub const compiled_plan = compiled.plan;
};

const Program = boundary.program("effect-treaty-replayable", Handlers, Body);
const ApprovalRequest = Program.protocol.operationSite("approval", "request", 0);

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

    var manifest = try Program.Exchange.Manifest.encode(allocator);
    defer manifest.deinit();
    var provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "replayable-provider",
        .provider_fingerprint = 0x7303,
        .supported_program_manifest_fingerprints = &.{manifest.fingerprint},
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{ApprovalRequest.index},
        .supported_protocol_op_fingerprints = &.{ApprovalRequest.fingerprint},
    });
    defer provider.deinit();
    var offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "replayable-offer",
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

    var first = try nextEnvelope(allocator, &runtime);
    defer first.session.deinit();
    defer first.envelope.deinit();
    var first_request = Program.Exchange.TreatyRequest.fromRequest(first.envelope);
    first_request.requested_usage_mode = .replayable;
    first_request.requested_response_use = .fresh;
    first_request.requested_replay_policy = .fresh;
    var first_result = try Program.Exchange.TreatyResolver.resolve(.{
        .allocator = allocator,
        .request = first.envelope,
        .manifest = manifest,
        .provider_manifests = providers[0..],
        .provider_offers = offers[0..],
        .capabilities = capabilities[0..],
        .treaty_request = first_request,
    });
    defer first_result.deinit();
    var first_response = try Program.Exchange.ResponseEnvelope.@"resume"(allocator, first.envelope, @as(i32, 7));
    defer first_response.deinit();
    try first_response.authorizeTreaty(first_result.treaty.?, .fresh);
    const first_accepted = Program.Exchange.validateTreatyResponse(first_result.treaty.?, first.envelope, first_response).allowed();
    var journal = Program.Session.Journal.init(allocator);
    defer journal.deinit();
    const first_current = try first.session.current();
    const first_typed_request = try first_current.request.as(ApprovalRequest);
    const recorded_response_trace = try first_typed_request.responseTrace(.@"resume", @as(i32, 7));
    try journal.appendRequest(.{ .operation = first_current.request.trace() });
    try journal.appendResponseValue(recorded_response_trace, @as(i32, 7));
    try journal.appendDone(recorded_response_trace.response_value_fingerprint);

    var second = try nextEnvelope(allocator, &runtime);
    defer second.session.deinit();
    defer second.envelope.deinit();
    var replay_request = Program.Exchange.TreatyRequest.fromRequest(second.envelope);
    replay_request.requested_usage_mode = .replayable;
    replay_request.requested_response_use = .replayed;
    replay_request.requested_replay_policy = .replayed;
    var replay_result = try Program.Exchange.TreatyResolver.resolve(.{
        .allocator = allocator,
        .request = second.envelope,
        .manifest = manifest,
        .provider_manifests = providers[0..],
        .provider_offers = offers[0..],
        .capabilities = capabilities[0..],
        .treaty_request = replay_request,
        .treaty_policy = .{ .require_replay_only_response = true },
    });
    defer replay_result.deinit();

    var fresh_second = try Program.Exchange.ResponseEnvelope.@"resume"(allocator, second.envelope, @as(i32, 9));
    defer fresh_second.deinit();
    try fresh_second.authorizeTreaty(replay_result.treaty.?, .fresh);
    const fresh_second_accepted = Program.Exchange.validateTreatyResponse(replay_result.treaty.?, second.envelope, fresh_second).allowed();

    var replayer = journal.replayer();
    defer replayer.deinit();
    const replayed = try replayer.expectCurrentResponseValue(try second.session.current(), i32);
    var replayed_second = try Program.Exchange.ResponseEnvelope.@"resume"(allocator, second.envelope, replayed.value);
    defer replayed_second.deinit();
    try replayed_second.authorizeTreatyWithReplaySource(replay_result.treaty.?, .replayed, replayed.trace.fingerprint, replayed.trace.response_value_fingerprint);
    const replayed_accepted = Program.Exchange.validateTreatyResponse(replay_result.treaty.?, second.envelope, replayed_second).allowed();
    try Program.Exchange.applyResponse(&second.session, replayed_second, .{});
    var final = switch (try second.session.next()) {
        .done => |done| done,
        else => return error.ExpectedDone,
    };
    defer final.deinit();
    try replayer.expectDone(replayed.trace.response_value_fingerprint);

    try writer.print("replay_policy={s}\n", .{@tagName(replay_result.treaty.?.replay_policy)});
    try writer.print("obligation_fingerprint=none\n", .{});
    try writer.print("treaty_fingerprint={x}\n", .{replay_result.treaty.?.fingerprint});
    try writer.print("journal_fingerprint={x}\n", .{try journal.fingerprint()});
    try writer.print("first_fresh_accepted={}\n", .{first_accepted});
    try writer.print("fresh_second_accepted={}\n", .{fresh_second_accepted});
    try writer.print("replayed_second_accepted={}\n", .{replayed_accepted});
    try writer.print("final_result={d}\n", .{final.value});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
