// zlinter-disable declaration_naming require_doc_comment no_hidden_allocations no_inferred_error_unions
const ability = @import("ability");
const std = @import("std");

const SourceHandlers = struct {};
const HandlerHandlers = struct {};
const semantic = ability.ir.builder.semantic;

const ApprovalProtocol = ability.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{ability.ir.schema.transform("request", []const u8, i32)},
});
const ApprovalRows = ApprovalProtocol.Rows(SourceHandlers, .{ .requirement_index = 0, .first_op = 0 });
const ApprovalRequestOp = ApprovalRows.op("request");

const source_compiled = semantic.finish(.{
    .label = "program-provider-resume-source",
    .ir_hash = 0x7070677273726301,
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
}) catch |err| @compileError("invalid program-provider resume source: " ++ @errorName(err));

const SourceBody = struct {
    pub const site_metadata = source_compiled.site_metadata;
    pub const compiled_plan = source_compiled.plan;
};
const SourceProgram = ability.program("program-provider-resume-source", SourceHandlers, SourceBody);
const ApprovalRequest = SourceProgram.protocol.operationSite("approval", "request", 0);

const PolicyProtocol = ability.ir.schema.Protocol(.{
    .label = "policy",
    .ops = .{ability.ir.schema.transform("check", []const u8, i32)},
});
const PolicyRows = PolicyProtocol.Rows(HandlerHandlers, .{ .requirement_index = 0, .first_op = 0 });
const PolicyCheckOp = PolicyRows.op("check");

const handler_compiled = semantic.finish(.{
    .label = "program-provider-resume-handler",
    .ir_hash = 0x7070677268646c01,
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
}) catch |err| @compileError("invalid program-provider resume handler: " ++ @errorName(err));

const HandlerBody = struct {
    pub const site_metadata = handler_compiled.site_metadata;
    pub const compiled_plan = handler_compiled.plan;
};
const HandlerProgram = ability.program("program-provider-resume-handler", HandlerHandlers, HandlerBody);

const ApprovalDecl = SourceProgram.Exchange.ProviderHandler.program(.{
    .label = "approval-program-handler",
    .op = ApprovalRequest,
    .program = HandlerProgram,
    .map_request = .payload_to_args,
    .map_result = .result_to_resume,
});
const ApprovalHarness = SourceProgram.Exchange.ProviderHarness(.{
    .label = "approval-program-provider",
    .provider_fingerprint = @as(?u64, 0x7704),
    .entries = .{ApprovalDecl},
});

fn resolveApprovalTreaty(
    allocator: std.mem.Allocator,
    catalog: anytype,
    request: SourceProgram.Exchange.RequestEnvelope,
) !SourceProgram.Exchange.TreatyResolver.Result {
    var capability = try SourceProgram.Exchange.Capability.encode(allocator, .{
        .issuer_label = "resume-host",
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

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    var runtime = ability.Runtime.init(allocator);
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

    var catalog = try ApprovalHarness.buildCatalog(allocator);
    defer catalog.deinit();
    var resolved = try resolveApprovalTreaty(allocator, catalog, parent_envelope);
    defer resolved.deinit();
    const treaty = resolved.treaty orelse return error.ExpectedTreaty;

    var handler_runtime = ability.Runtime.init(allocator);
    defer handler_runtime.deinit();
    var started = try ApprovalHarness.startProgramExecution(0, &handler_runtime, HandlerProgram.Handlers{}, allocator, parent_envelope, treaty.certificate, catalog.provider_offers[0], .{ .treaty = treaty });
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

    const capsule_fingerprint = execution.provider_program_capsule_image_fingerprint.?;
    const nested_request_fingerprint = execution.nested_request_fingerprint.?;
    var decoded_nested = try HandlerProgram.Exchange.RequestEnvelope.decode(allocator, execution.nested_request_envelope.?.bytes);
    var decoded_nested_owned = true;
    errdefer if (decoded_nested_owned) decoded_nested.deinit();
    execution.nested_request_envelope.?.deinit();
    execution.nested_request_envelope = decoded_nested;
    decoded_nested_owned = false;

    const nested_envelope = execution.nested_request_envelope.?;
    var nested_response = try HandlerProgram.Exchange.ResponseEnvelope.@"resume"(allocator, nested_envelope, @as(i32, 9));
    defer nested_response.deinit();
    var continued = try ApprovalHarness.continueProgramExecution(0, &execution, &handler_runtime, HandlerProgram.Handlers{}, allocator, parent_envelope, treaty.certificate, catalog.provider_offers[0], nested_response, .{ .treaty = treaty });
    switch (continued) {
        .response => |*packet| {
            defer packet.deinit();
            try SourceProgram.Exchange.applyResponse(&session, packet.response, .{});
        },
        .provider_suspended => |*parked| {
            parked.deinit();
            return error.ExpectedProviderResponse;
        },
        .rejected => return error.ExpectedProviderResponse,
    }
    var final = switch (try session.next()) {
        .done => |done| done,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer final.deinit();

    try writer.print("provider_program_capsule_fingerprint={x}\n", .{capsule_fingerprint});
    try writer.print("nested_request_fingerprint={x}\n", .{nested_request_fingerprint});
    try writer.print("final_result={d}\n", .{final.value});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
