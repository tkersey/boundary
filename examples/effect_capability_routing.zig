// zlinter-disable declaration_naming require_doc_comment no_hidden_allocations no_inferred_error_unions
const ability = @import("ability");
const std = @import("std");

const Handlers = struct {};

const ApprovalProtocol = ability.ir.schema.Protocol(.{
    .label = "capability",
    .ops = .{
        ability.ir.schema.transform("check", []const u8, i32),
        ability.ir.schema.transform("call", []const u8, i32),
    },
});

const Rows = ApprovalProtocol.Rows(Handlers, .{
    .requirement_index = 0,
    .first_op = 0,
});

const semantic_spec = blk: {
    const semantic = ability.ir.builder.semantic;
    const Check = Rows.op("check");
    const Call = Rows.op("call");

    break :blk .{
        .label = "effect-capability-routing",
        .ir_hash = 0x636170726f757465,
        .entry = "run",
        .requirements = &.{Rows.requirement},
        .ops = &Rows.ops,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = semantic.span(0, 1),
            .params = .{},
            .locals = .{
                semantic.local("policy_payload", []const u8),
                semantic.local("tool_payload", []const u8),
                semantic.local("policy_score", i32),
                semantic.local("denied", bool),
                semantic.local("result", i32),
            },
            .result = i32,
            .blocks = .{
                .{
                    .name = "entry",
                    .instructions = .{
                        semantic.constString("policy_payload", "deploy-tool"),
                        semantic.call(Check, .{ .dst = "policy_score", .payload = "policy_payload", .label = "policy.check" }),
                        semantic.compareEqZero("denied", "policy_score"),
                    },
                    .terminator = semantic.branchIf("denied", .{ .then = "denied", .@"else" = "tool" }),
                },
                .{
                    .name = "tool",
                    .instructions = .{
                        semantic.constString("tool_payload", "deploy-tool"),
                        semantic.call(Call, .{ .dst = "result", .payload = "tool_payload", .label = "tool.call" }),
                    },
                    .terminator = semantic.returnValue("result"),
                },
                .{
                    .name = "denied",
                    .instructions = .{
                        semantic.constI32("result", 0),
                    },
                    .terminator = semantic.returnValue("result"),
                },
            },
        }},
    };
};

const compiled = ability.ir.builder.semantic.finish(semantic_spec) catch |err|
    @compileError("invalid effect capability routing example: " ++ @errorName(err));

const Body = struct {
    pub const site_metadata = compiled.site_metadata;
    pub const compiled_plan = compiled.plan;
};

const Program = ability.program("effect-capability-routing", Handlers, Body);
const PolicySite = Program.protocol.operationSite("capability", "check", 0);
const ToolSite = Program.protocol.operationSite("capability", "call", 0);

const Outbox = struct {
    allocator: std.mem.Allocator,
    requests: std.ArrayList(Program.Exchange.RequestEnvelope) = .empty,
    routes: std.ArrayList(Program.Exchange.Route) = .empty,

    fn deinit(self: *@This()) void {
        for (self.requests.items) |*request| request.deinit();
        self.requests.deinit(self.allocator);
        self.routes.deinit(self.allocator);
    }

    pub fn append(self: *@This(), request: Program.Exchange.RequestEnvelope) !void {
        try self.requests.append(self.allocator, request);
    }

    pub fn appendRouted(self: *@This(), request: Program.Exchange.RequestEnvelope, route: Program.Exchange.Route) !void {
        try self.requests.append(self.allocator, request);
        try self.routes.append(self.allocator, route);
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

fn answerNext(allocator: std.mem.Allocator, outbox: *Outbox, inbox: *Inbox) !void {
    const index = outbox.requests.items.len - 1;
    const request = outbox.requests.items[index];
    const route = outbox.routes.items[index];
    inbox.response = if (request.site_index == PolicySite.index)
        try Program.Exchange.ResponseEnvelope.@"resume"(allocator, request, @as(i32, 1))
    else
        try Program.Exchange.ResponseEnvelope.@"resume"(allocator, request, @as(i32, 42));
    try inbox.response.?.authorize(route);
}

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    var runtime = ability.Runtime.init(allocator);
    defer runtime.deinit();

    var manifest = try Program.Exchange.Manifest.encode(allocator);
    defer manifest.deinit();
    var policy_provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "policy-provider",
        .supported_program_manifest_fingerprints = &[_]u64{manifest.fingerprint},
        .supported_protocol_labels = &[_][]const u8{"capability"},
        .supported_operation_sites = &[_]usize{PolicySite.index},
        .supported_protocol_op_fingerprints = &[_]u64{PolicySite.fingerprint},
    });
    defer policy_provider.deinit();
    var tool_provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "tool-provider",
        .supported_program_manifest_fingerprints = &[_]u64{manifest.fingerprint},
        .supported_protocol_labels = &[_][]const u8{"capability"},
        .supported_operation_sites = &[_]usize{ToolSite.index},
        .supported_protocol_op_fingerprints = &[_]u64{ToolSite.fingerprint},
    });
    defer tool_provider.deinit();
    var policy_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "host",
        .provider_fingerprint = policy_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &[_]usize{PolicySite.index},
        .allowed_protocol_op_fingerprints = &[_]u64{PolicySite.fingerprint},
        .allowed_response_kinds = .{ .return_now = false, .resume_after = false },
    });
    defer policy_capability.deinit();
    var tool_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "host",
        .provider_fingerprint = tool_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &[_]usize{ToolSite.index},
        .allowed_protocol_op_fingerprints = &[_]u64{ToolSite.fingerprint},
        .allowed_response_kinds = .{ .return_now = false, .resume_after = false },
    });
    defer tool_capability.deinit();
    const providers = [_]Program.Exchange.ProviderManifest{ policy_provider, tool_provider };
    const capabilities = [_]Program.Exchange.Capability{ policy_capability, tool_capability };
    const router = Program.Exchange.Router{ .providers = providers[0..], .capabilities = capabilities[0..] };

    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();
    var outbox = Outbox{ .allocator = allocator };
    defer outbox.deinit();
    var inbox = Inbox{};
    defer inbox.deinit();
    var runner = Program.Exchange.MailboxRunner{};
    var journal = Program.Session.Journal.init(allocator);
    defer journal.deinit();

    while (true) {
        var step = try runner.runStep(&session, &outbox, &inbox, .{
            .allocator = allocator,
            .router = router,
            .journal = &journal,
            .policy = .{ .require_route = true, .require_response_capability = true },
        });
        switch (step) {
            .parked => |*request| {
                request.deinit();
                try answerNext(allocator, &outbox, &inbox);
            },
            .running => {},
            .done => |*done| {
                defer done.deinit();
                try writer.print("policy_provider_fingerprint={x}\n", .{policy_provider.provider_fingerprint});
                try writer.print("tool_provider_fingerprint={x}\n", .{tool_provider.provider_fingerprint});
                try writer.print("policy_capability_fingerprint={x}\n", .{policy_capability.fingerprint});
                try writer.print("tool_capability_fingerprint={x}\n", .{tool_capability.fingerprint});
                try writer.print("route_fingerprint={x}\n", .{outbox.routes.items[outbox.routes.items.len - 1].fingerprint});
                try writer.print("response_authorization_fingerprint={x}\n", .{journal.entries.items[journal.entries.items.len - 1].exchange_event.authorization_fingerprint.?});
                try writer.print("final_result={d}\n", .{done.value});
                return;
            },
        }
    }
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
