// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions
const boundary = @import("boundary");
const std = @import("std");

const Handlers = struct {};

const Protocol = boundary.ir.schema.Protocol(.{
    .label = "branch-safety",
    .ops = .{
        boundary.ir.schema.transform("approval", []const u8, i32),
    },
});

const Rows = Protocol.Rows(Handlers, .{
    .requirement_index = 0,
    .first_op = 0,
});

const semantic_spec = blk: {
    const semantic = boundary.ir.builder.semantic;
    const ApprovalOp = Rows.op("approval");

    break :blk .{
        .label = "linear-branch-safety",
        .ir_hash = 0x6c696e6561720002,
        .entry = "run",
        .requirements = &.{Rows.requirement},
        .ops = &Rows.ops,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = semantic.span(0, 1),
            .params = .{},
            .locals = .{
                semantic.local("payload", []const u8),
                semantic.local("answer", i32),
            },
            .result = i32,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    semantic.constString("payload", "approval"),
                    semantic.call(ApprovalOp, .{
                        .dst = "answer",
                        .payload = "payload",
                        .label = "approval.request",
                    }),
                },
                .terminator = semantic.returnValue("answer"),
            }},
        }},
    };
};

const compiled = boundary.ir.builder.semantic.finish(semantic_spec) catch |err|
    @compileError("invalid linear-branch-safety semantic plan: " ++ @errorName(err));

const Body = struct {
    pub const site_metadata = compiled.site_metadata;
    pub const compiled_plan = compiled.plan;
};

const Program = boundary.program("linear-branch-safety", Handlers, Body);

fn printPolicy(writer: anytype, policy: Program.Exchange.BranchPolicy, response_use: Program.Exchange.ResponseUse, open: bool, capsule: bool) !void {
    const report = Program.Exchange.validateBranchPolicy(policy, .linear, response_use, open, capsule);
    try writer.print("policy={s} response_use={s} open={} capsule={} accepted={}", .{
        @tagName(policy),
        @tagName(response_use),
        open,
        capsule,
        report.allowed(),
    });
    if (report.firstTagName()) |blocker| {
        try writer.print(" blocker={s}", .{blocker});
    }
    try writer.print("\n", .{});
}

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();
    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();
    _ = switch (try session.next()) {
        .request => |request| request,
        .after => return error.UnexpectedAfter,
        .done => return error.UnexpectedDone,
    };
    var capsule = try session.capture(allocator);
    defer capsule.deinit();
    var image = try capsule.encode(allocator);
    defer image.deinit();
    const has_capsule_image = image.bytes.len > 0;
    const has_open_obligation = true;

    try printPolicy(writer, .unrestricted, .fresh, has_open_obligation, has_capsule_image);
    try printPolicy(writer, .replay_only, .replayed, has_open_obligation, has_capsule_image);
    try printPolicy(writer, .replay_only, .fresh, has_open_obligation, has_capsule_image);
    try printPolicy(writer, .single_live_branch, .fresh, has_open_obligation, has_capsule_image);
    try printPolicy(writer, .no_branch, .fresh, has_open_obligation, has_capsule_image);
    try printPolicy(writer, .host_owned, .fresh, has_open_obligation, has_capsule_image);
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
