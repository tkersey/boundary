// zlinter-disable declaration_naming require_doc_comment no_hidden_allocations no_inferred_error_unions
const boundary = @import("boundary");
const std = @import("std");

const SourceHandlers = struct {};
const semantic = boundary.ir.builder.semantic;

const ApprovalProtocol = boundary.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{
        boundary.ir.schema.transform("request", []const u8, i32),
    },
});
const ApprovalRows = ApprovalProtocol.Rows(SourceHandlers, .{ .requirement_index = 0, .first_op = 0 });
const ApprovalRequestOp = ApprovalRows.op("request");

const source_compiled = semantic.finish(.{
    .label = "program-provider-direct-source",
    .ir_hash = 0x7070676469726563,
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
}) catch |err| @compileError("invalid program-provider direct source: " ++ @errorName(err));

const SourceBody = struct {
    pub const site_metadata = source_compiled.site_metadata;
    pub const compiled_plan = source_compiled.plan;
};
const SourceProgram = boundary.program("program-provider-direct-source", SourceHandlers, SourceBody);
const ApprovalRequest = SourceProgram.protocol.operationSite("approval", "request", 0);

const handler_compiled = semantic.finish(.{
    .label = "program-provider-direct-handler",
    .ir_hash = 0x7070676469726801,
    .entry = "run",
    .functions = .{.{
        .symbol_name = "run",
        .params = .{semantic.param("payload", []const u8)},
        .locals = .{semantic.local("decision", i32)},
        .result = i32,
        .blocks = .{.{
            .name = "entry",
            .instructions = .{
                semantic.constI32("decision", 1),
            },
            .terminator = semantic.returnValue("decision"),
        }},
    }},
}) catch |err| @compileError("invalid program-provider direct handler: " ++ @errorName(err));

const HandlerBody = struct {
    pub const compiled_plan = handler_compiled.plan;
};
const HandlerProgram = boundary.program("program-provider-direct-handler", struct {}, HandlerBody);

const ApprovalDecl = SourceProgram.Exchange.ProviderHandler.program(.{
    .label = "approval-program-handler",
    .op = ApprovalRequest,
    .program = HandlerProgram,
    .map_request = .payload_to_args,
    .map_result = .result_to_resume,
});
const Harness = SourceProgram.Exchange.ProviderHarness(.{
    .label = "approval-program-provider",
    .provider_fingerprint = @as(?u64, 0x7701),
    .entries = .{ApprovalDecl},
});

fn resolveTreaty(
    allocator: std.mem.Allocator,
    catalog: anytype,
    request: SourceProgram.Exchange.RequestEnvelope,
) !SourceProgram.Exchange.TreatyResolver.Result {
    var capability = try SourceProgram.Exchange.Capability.encode(allocator, .{
        .issuer_label = "direct-host",
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
    var runtime = boundary.Runtime.init(allocator);
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
    var catalog = try Harness.buildCatalog(allocator);
    defer catalog.deinit();
    var resolved = try resolveTreaty(allocator, catalog, envelope);
    defer resolved.deinit();
    const treaty = resolved.treaty orelse return error.ExpectedTreaty;

    var handler_runtime = boundary.Runtime.init(allocator);
    defer handler_runtime.deinit();
    var result = try Harness.startProgramExecution(0, &handler_runtime, HandlerProgram.Handlers{}, allocator, envelope, treaty.certificate, catalog.provider_offers[0], .{ .treaty = treaty });
    const authorization_fingerprint, const execution_fingerprint = switch (result) {
        .response => |*packet| blk: {
            defer packet.deinit();
            try SourceProgram.Exchange.applyResponse(&session, packet.response, .{});
            break :blk .{ packet.treaty_authorization.authorization_fingerprint, packet.provider_program_execution_fingerprint.? };
        },
        .provider_suspended => |*execution| {
            execution.deinit();
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

    try writer.print("parent_request_fingerprint={x}\n", .{envelope.request_fingerprint});
    try writer.print("provider_program_execution_fingerprint={x}\n", .{execution_fingerprint});
    try writer.print("treaty_fingerprint={x}\n", .{treaty.fingerprint});
    try writer.print("response_authorization_fingerprint={x}\n", .{authorization_fingerprint});
    try writer.print("final_result={d}\n", .{final.value});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
