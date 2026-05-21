// zlinter-disable declaration_naming field_ordering require_doc_comment no_hidden_allocations no_inferred_error_unions
const boundary = @import("boundary");
const std = @import("std");

const SourceHandlers = struct {};
const HandlerHandlers = struct {};
const semantic = boundary.ir.builder.semantic;

const ApprovalProtocol = boundary.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{boundary.ir.schema.transform("request", []const u8, i32)},
});
const ApprovalRows = ApprovalProtocol.Rows(SourceHandlers, .{ .requirement_index = 0, .first_op = 0 });
const ApprovalRequestOp = ApprovalRows.op("request");

const source_compiled = semantic.finish(.{
    .label = "program-provider-nested-source",
    .ir_hash = 0x7070676e73726301,
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
                semantic.call(ApprovalRequestOp, .{
                    .dst = "decision",
                    .payload = "payload",
                    .label = "approval.request",
                }),
            },
            .terminator = semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid program-provider nested source: " ++ @errorName(err));

const SourceBody = struct {
    pub const site_metadata = source_compiled.site_metadata;
    pub const compiled_plan = source_compiled.plan;
};
const SourceProgram = boundary.program("program-provider-nested-source", SourceHandlers, SourceBody);
const ApprovalRequest = SourceProgram.protocol.operationSite("approval", "request", 0);

const PolicyProtocol = boundary.ir.schema.Protocol(.{
    .label = "policy",
    .ops = .{boundary.ir.schema.transform("check", []const u8, i32)},
});
const PolicyRows = PolicyProtocol.Rows(HandlerHandlers, .{ .requirement_index = 0, .first_op = 0 });
const PolicyCheckOp = PolicyRows.op("check");

const handler_compiled = semantic.finish(.{
    .label = "program-provider-nested-handler",
    .ir_hash = 0x7070676e68646c01,
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
            .instructions = .{
                semantic.call(PolicyCheckOp, .{
                    .dst = "decision",
                    .payload = "payload",
                    .label = "policy.check",
                }),
            },
            .terminator = semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid program-provider nested handler: " ++ @errorName(err));

const HandlerBody = struct {
    pub const site_metadata = handler_compiled.site_metadata;
    pub const compiled_plan = handler_compiled.plan;
};
const HandlerProgram = boundary.program("program-provider-nested-handler", HandlerHandlers, HandlerBody);
const PolicyCheck = HandlerProgram.protocol.operationSite("policy", "check", 0);

const ApprovalDecl = SourceProgram.Exchange.ProviderHandler.program(.{
    .label = "approval-program-handler",
    .op = ApprovalRequest,
    .program = HandlerProgram,
    .map_request = .payload_to_args,
    .map_result = .result_to_resume,
});
const ApprovalHarness = SourceProgram.Exchange.ProviderHarness(.{
    .label = "approval-program-provider",
    .provider_fingerprint = @as(?u64, 0x7702),
    .entries = .{ApprovalDecl},
});

const PolicyOutcome = union(enum) {
    forward,
    pending,
    reject: []const u8,
    replay: i32,
    @"resume": i32,
    resume_after: void,
    return_now: i32,
};

fn handlePolicy(_: void, request: anytype) !PolicyOutcome {
    const payload = try request.payload(std.heap.page_allocator);
    defer std.heap.page_allocator.free(payload);
    return .{ .@"resume" = 7 };
}

const PolicyDecl = HandlerProgram.Exchange.ProviderHandler.operation(PolicyCheck, handlePolicy, .{
    .label = "policy-check",
});
const PolicyHarness = HandlerProgram.Exchange.ProviderHarness(.{
    .label = "policy-provider",
    .provider_fingerprint = @as(?u64, 0x7703),
    .entries = .{PolicyDecl},
});

fn resolveApprovalTreaty(
    allocator: std.mem.Allocator,
    catalog: anytype,
    request: SourceProgram.Exchange.RequestEnvelope,
) !SourceProgram.Exchange.TreatyResolver.Result {
    var capability = try SourceProgram.Exchange.Capability.encode(allocator, .{
        .issuer_label = "nested-host",
        .provider_fingerprint = ApprovalHarness.provider_fingerprint,
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
    return SourceProgram.Exchange.TreatyResolver.resolve(.{
        .allocator = allocator,
        .request = request,
        .manifest = catalog.manifest,
        .provider_manifests = providers[0..],
        .provider_offers = offers[0..],
        .capabilities = capabilities[0..],
    });
}

fn resolvePolicyTreaty(
    allocator: std.mem.Allocator,
    catalog: anytype,
    request: HandlerProgram.Exchange.RequestEnvelope,
) !HandlerProgram.Exchange.TreatyResolver.Result {
    var capability = try HandlerProgram.Exchange.Capability.encode(allocator, .{
        .issuer_label = "policy-host",
        .provider_fingerprint = PolicyHarness.provider_fingerprint,
        .manifest_fingerprint = catalog.manifest.fingerprint,
        .allowed_request_kinds = .{ .operation = true },
        .allowed_operation_sites = &.{PolicyCheck.index},
        .allowed_protocol_op_fingerprints = &.{PolicyCheck.fingerprint},
        .allowed_requirement_labels = &.{"policy"},
        .allowed_op_names = &.{"check"},
    });
    defer capability.deinit();
    const providers = [_]HandlerProgram.Exchange.ProviderManifest{catalog.provider_manifest};
    const offers = [_]HandlerProgram.Exchange.ProviderOffer{catalog.provider_offers[0]};
    const capabilities = [_]HandlerProgram.Exchange.Capability{capability};
    return HandlerProgram.Exchange.TreatyResolver.resolve(.{
        .allocator = allocator,
        .request = request,
        .manifest = catalog.manifest,
        .provider_manifests = providers[0..],
        .provider_offers = offers[0..],
        .capabilities = capabilities[0..],
    });
}

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var session = try SourceProgram.Session.start(&runtime, .{});
    defer session.deinit();
    const parent_request = switch (try session.next()) {
        .request => |value| value,
        .after => return error.UnexpectedAfter,
        .done => return error.UnexpectedDone,
    };
    var parent_envelope = try SourceProgram.Exchange.RequestEnvelope.fromRequest(allocator, parent_request, .{});
    defer parent_envelope.deinit();

    var approval_catalog = try ApprovalHarness.buildCatalog(allocator);
    defer approval_catalog.deinit();
    var approval_resolved = try resolveApprovalTreaty(allocator, approval_catalog, parent_envelope);
    defer approval_resolved.deinit();
    const approval_treaty = approval_resolved.treaty orelse return error.ExpectedTreaty;

    var handler_runtime = boundary.Runtime.init(allocator);
    defer handler_runtime.deinit();
    var started = try ApprovalHarness.startProgramExecution(0, &handler_runtime, HandlerProgram.Handlers{}, allocator, parent_envelope, approval_treaty.certificate, approval_catalog.provider_offers[0], .{ .treaty = approval_treaty });
    var execution = switch (started) {
        .provider_suspended => |*value| moved: {
            const moved_value = value.*;
            value.session = null;
            value.nested_request_envelope = null;
            break :moved moved_value;
        },
        .response => |*packet| {
            packet.deinit();
            return error.ExpectedProviderSuspension;
        },
        .rejected => return error.ExpectedProviderSuspension,
    };
    defer execution.deinit();
    const nested_envelope = execution.nested_request_envelope.?;

    var policy_catalog = try PolicyHarness.buildCatalog(allocator);
    defer policy_catalog.deinit();
    var policy_resolved = try resolvePolicyTreaty(allocator, policy_catalog, nested_envelope);
    defer policy_resolved.deinit();
    const policy_treaty = policy_resolved.treaty orelse return error.ExpectedTreaty;
    var policy_result = try PolicyHarness.handle({}, allocator, nested_envelope, policy_treaty.certificate, .{ .treaty = policy_treaty });
    var nested_response = switch (policy_result) {
        .response => |*packet| moved: {
            var response = try HandlerProgram.Exchange.ResponseEnvelope.decode(allocator, packet.response.bytes);
            errdefer response.deinit();
            packet.deinit();
            break :moved response;
        },
        else => return error.ExpectedProviderResponse,
    };
    defer nested_response.deinit();

    var continued = try ApprovalHarness.continueProgramExecution(0, &execution, &handler_runtime, HandlerProgram.Handlers{}, allocator, parent_envelope, approval_treaty.certificate, approval_catalog.provider_offers[0], nested_response, .{ .treaty = approval_treaty });
    const execution_fingerprint = switch (continued) {
        .response => |*packet| blk: {
            defer packet.deinit();
            try SourceProgram.Exchange.applyResponse(&session, packet.response, .{});
            break :blk packet.provider_program_execution_fingerprint.?;
        },
        .provider_suspended => |*parked| {
            parked.deinit();
            return error.ExpectedProviderResponse;
        },
        .rejected => return error.ExpectedProviderResponse,
    };
    var final = switch (try session.next()) {
        .done => |done| done,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer final.deinit();

    try writer.print("parent_request_fingerprint={x}\n", .{parent_envelope.request_fingerprint});
    try writer.print("nested_request_fingerprint={x}\n", .{nested_envelope.request_fingerprint});
    try writer.print("provider_program_execution_fingerprint={x}\n", .{execution_fingerprint});
    try writer.print("policy_provider_fingerprint={x}\n", .{PolicyHarness.provider_fingerprint});
    try writer.print("final_result={d}\n", .{final.value});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
