// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions
const ability = @import("ability");
const std = @import("std");

const ApprovalHandlers = struct {};

const ApprovalProtocol = ability.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{
        ability.ir.schema.choice("request", []const u8, i32),
    },
});

const ApprovalRows = ApprovalProtocol.Rows(ApprovalHandlers, .{
    .requirement_index = 0,
    .first_op = 0,
});

const PolicyProtocol = ability.ir.schema.Protocol(.{
    .label = "policy",
    .ops = .{
        ability.ir.schema.transform("check", []const u8, bool),
    },
});

const CheckPolicy = PolicyProtocol.operation("check", .{});

const approval_semantic_spec = blk: {
    const semantic = ability.ir.builder.semantic;
    const RequestApproval = ApprovalRows.op("request");

    break :blk .{
        .label = "protocol-reinterpretation",
        .ir_hash = 0x70726f746f6d6f72,
        .entry = "run",
        .requirements = &.{ApprovalRows.requirement},
        .ops = &ApprovalRows.ops,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = semantic.span(0, 1),
            .params = .{},
            .locals = .{
                semantic.local("request_payload", []const u8),
                semantic.local("approval_decision", i32),
            },
            .result = i32,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    semantic.constString("request_payload", "deploy-prod"),
                    semantic.call(RequestApproval, .{
                        .dst = "approval_decision",
                        .payload = "request_payload",
                        .label = "approval.request",
                    }),
                },
                .terminator = semantic.returnValue("approval_decision"),
            }},
        }},
    };
};

const approval_compiled = ability.ir.builder.semantic.finish(approval_semantic_spec) catch |err|
    @compileError("invalid protocol-reinterpretation semantic plan: " ++ @errorName(err));

const ApprovalBody = struct {
    pub const site_metadata = approval_compiled.site_metadata;
    pub const compiled_plan = approval_compiled.plan;
};

const ApprovalProgram = ability.program("protocol-reinterpretation", ApprovalHandlers, ApprovalBody);
const ApprovalRequest = ApprovalProgram.protocol.operationSite("approval", "request", 0);

const ApprovalPolicyMapper = struct {
    pub fn @"resume"(decision: bool) ApprovalProgram.Handler.SourceOutcome(ApprovalRequest) {
        if (decision) {
            return ApprovalProgram.Handler.@"resume"(ApprovalRequest, @as(ApprovalRequest.Resume, 1));
        }
        return ApprovalProgram.Handler.returnNow(ApprovalRequest, @as(ApprovalRequest.Result, 0));
    }
};

const ApprovalViaPolicy = ApprovalProgram.Morphism(.{
    .source = ApprovalRequest,
    .target = CheckPolicy,
    .Mapper = ApprovalPolicyMapper,
});

const Host = struct {
    allow: bool,
};

const ApprovalHandler = struct {
    pub fn handle(_: *Host, request: anytype, _: ApprovalProgram.Handler.Control) !ApprovalProgram.Handler.MorphismOutcome(ApprovalViaPolicy) {
        return ApprovalProgram.Handler.reinterpret(ApprovalViaPolicy, try request.payload());
    }
};

const PolicyHandler = struct {
    pub fn handle(host: *Host, request: anytype) !ApprovalProgram.Handler.TargetResponse(CheckPolicy) {
        _ = try request.payload();
        return .{ .@"resume" = host.allow };
    }
};

const SourceOnly = ApprovalProgram.Interpreter(.{
    ApprovalProgram.Handler.morphism(ApprovalViaPolicy, ApprovalHandler.handle),
});

const WithPolicy = ApprovalProgram.Interpreter(.{
    ApprovalProgram.Handler.morphism(ApprovalViaPolicy, ApprovalHandler.handle),
    ApprovalProgram.Handler.protocolOperation(CheckPolicy, PolicyHandler.handle),
});

fn expectDone(result: anytype) !ApprovalProgram.Result {
    return switch (result) {
        .done => |done| done,
        .suspended => return error.UnexpectedSuspend,
        .unhandled => return error.UnexpectedUnhandled,
        .reinterpreted => return error.UnexpectedReinterpreted,
    };
}

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    var runtime = ability.Runtime.init(allocator);
    defer runtime.deinit();

    SourceOnly.assertReinterprets(ApprovalRequest, CheckPolicy);
    WithPolicy.assertHandlesProtocolOps(.{CheckPolicy});
    WithPolicy.assertEliminates(ApprovalProgram);

    var inspect_host = Host{ .allow = true };
    var source_only = try SourceOnly.run(&runtime, .{}, &inspect_host, .{});
    switch (source_only) {
        .reinterpreted => |*request| {
            defer request.deinit();
            try writer.print("source_request_fingerprint={x}\n", .{request.source_request_fingerprint});
            try writer.print("source_capsule_fingerprint={x}\n", .{request.source_capsule_fingerprint});
            try writer.print("target_protocol_op_fingerprint={x}\n", .{request.target_protocol_op_fingerprint});
            try writer.print("target_request_fingerprint={x}\n", .{request.reinterpreted_request_fingerprint});
            try writer.print("target_payload={s}\n", .{try request.payload([]const u8)});
        },
        else => return error.ExpectedReinterpreted,
    }

    var allow_host = Host{ .allow = true };
    var approved = try expectDone(try WithPolicy.run(&runtime, .{}, &allow_host, .{}));
    defer approved.deinit();

    var deny_host = Host{ .allow = false };
    var denied = try expectDone(try WithPolicy.run(&runtime, .{}, &deny_host, .{}));
    defer denied.deinit();

    try writer.print("allow_result={d}\n", .{approved.value});
    try writer.print("deny_result={d}\n", .{denied.value});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
