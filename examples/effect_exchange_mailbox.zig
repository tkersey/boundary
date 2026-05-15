// zlinter-disable declaration_naming require_doc_comment no_hidden_allocations no_inferred_error_unions
const ability = @import("ability");
const std = @import("std");

const ApprovalHandlers = struct {};

const ApprovalProtocol = ability.ir.schema.Protocol(.{
    .label = "approval",
    .ops = .{
        ability.ir.schema.transform("score", []const u8, i32),
    },
});

const ApprovalRows = ApprovalProtocol.Rows(ApprovalHandlers, .{
    .requirement_index = 0,
    .first_op = 0,
});

const approval_semantic_spec = blk: {
    const semantic = ability.ir.builder.semantic;
    const ScoreOp = ApprovalRows.op("score");

    break :blk .{
        .label = "effect-exchange-mailbox",
        .ir_hash = 0x657863686d626f78,
        .entry = "run",
        .requirements = &.{ApprovalRows.requirement},
        .ops = &ApprovalRows.ops,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = semantic.span(0, 1),
            .params = .{},
            .locals = .{
                semantic.local("payload", []const u8),
                semantic.local("score", i32),
            },
            .result = i32,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    semantic.constString("payload", "mailbox-approval"),
                    semantic.call(ScoreOp, .{
                        .dst = "score",
                        .payload = "payload",
                        .label = "approval.score",
                    }),
                },
                .terminator = semantic.returnValue("score"),
            }},
        }},
    };
};

const approval_compiled = ability.ir.builder.semantic.finish(approval_semantic_spec) catch |err|
    @compileError("invalid effect-exchange-mailbox semantic plan: " ++ @errorName(err));

const ApprovalBody = struct {
    pub const site_metadata = approval_compiled.site_metadata;
    pub const compiled_plan = approval_compiled.plan;
};

const ApprovalProgram = ability.program("effect-exchange-mailbox", ApprovalHandlers, ApprovalBody);

const Outbox = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(ApprovalProgram.Exchange.RequestEnvelope) = .empty,

    fn deinit(self: *@This()) void {
        for (self.items.items) |*item| item.deinit();
        self.items.deinit(self.allocator);
    }

    pub fn append(self: *@This(), envelope: ApprovalProgram.Exchange.RequestEnvelope) !void {
        try self.items.append(self.allocator, try ApprovalProgram.Exchange.RequestEnvelope.decode(self.allocator, envelope.bytes));
    }
};

const Inbox = struct {
    response: ?ApprovalProgram.Exchange.ResponseEnvelope = null,

    fn deinit(self: *@This()) void {
        if (self.response) |*response| response.deinit();
        self.response = null;
    }

    pub fn nextResponse(self: *@This()) !?ApprovalProgram.Exchange.ResponseEnvelope {
        const response = self.response orelse return null;
        self.response = null;
        return response;
    }
};

fn hostHandle(allocator: std.mem.Allocator, outbox: *Outbox, inbox: *Inbox) !u64 {
    const request = outbox.items.items[0];
    var encoded_manifest = try ApprovalProgram.Exchange.Manifest.encode(allocator);
    defer encoded_manifest.deinit();
    var manifest = try ApprovalProgram.Exchange.Manifest.decode(allocator, encoded_manifest.bytes);
    defer manifest.deinit();
    if (manifest.fingerprint != request.manifest_fingerprint) return error.ManifestMismatch;
    inbox.response = try ApprovalProgram.Exchange.ResponseEnvelope.@"resume"(allocator, request, @as(i32, 42));
    return inbox.response.?.fingerprint;
}

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    var runtime = ability.Runtime.init(allocator);
    defer runtime.deinit();

    var manifest = try ApprovalProgram.Exchange.Manifest.encode(allocator);
    defer manifest.deinit();

    var session = try ApprovalProgram.Session.start(&runtime, .{});
    defer session.deinit();
    var outbox = Outbox{ .allocator = allocator };
    defer outbox.deinit();
    var inbox = Inbox{};
    defer inbox.deinit();
    var runner = ApprovalProgram.Exchange.MailboxRunner{};

    var first = try runner.runStep(&session, &outbox, &inbox, .{
        .allocator = allocator,
        .capsule = true,
    });
    const request_fingerprint = switch (first) {
        .parked => |*envelope| blk: {
            defer envelope.deinit();
            break :blk envelope.fingerprint;
        },
        else => return error.ExpectedRequest,
    };

    const response_fingerprint = try hostHandle(allocator, &outbox, &inbox);
    _ = try runner.runStep(&session, &outbox, &inbox, .{ .allocator = allocator });
    var final = switch (try runner.runStep(&session, &outbox, &inbox, .{ .allocator = allocator })) {
        .done => |done| done,
        .parked => return error.ExpectedDone,
        .running => return error.ExpectedDone,
    };
    defer final.deinit();

    try writer.print("manifest_fingerprint={x}\n", .{manifest.fingerprint});
    try writer.print("request_envelope_fingerprint={x}\n", .{request_fingerprint});
    try writer.print("response_envelope_fingerprint={x}\n", .{response_fingerprint});
    try writer.print("final_result={d}\n", .{final.value});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
