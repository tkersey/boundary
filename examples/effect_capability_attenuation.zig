// zlinter-disable declaration_naming require_doc_comment no_hidden_allocations no_inferred_error_unions
const boundary = @import("boundary");
const std = @import("std");

const Handlers = struct {};

const ToolProtocol = boundary.ir.schema.Protocol(.{
    .label = "tool",
    .ops = .{
        boundary.ir.schema.transform("call", []const u8, i32),
    },
});

const Rows = ToolProtocol.Rows(Handlers, .{ .requirement_index = 0, .first_op = 0 });

const semantic_spec = blk: {
    const semantic = boundary.ir.builder.semantic;
    const Call = Rows.op("call");
    break :blk .{
        .label = "effect-capability-attenuation",
        .ir_hash = 0x617474656e636170,
        .entry = "run",
        .requirements = &.{Rows.requirement},
        .ops = &Rows.ops,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = semantic.span(0, 1),
            .params = .{},
            .locals = .{
                semantic.local("payload", []const u8),
                semantic.local("result", i32),
            },
            .result = i32,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    semantic.constString("payload", "safe-tool"),
                    semantic.call(Call, .{ .dst = "result", .payload = "payload", .label = "tool.call" }),
                },
                .terminator = semantic.returnValue("result"),
            }},
        }},
    };
};

const compiled = boundary.ir.builder.semantic.finish(semantic_spec) catch |err|
    @compileError("invalid effect capability attenuation example: " ++ @errorName(err));

const Body = struct {
    pub const site_metadata = compiled.site_metadata;
    pub const compiled_plan = compiled.plan;
};

const Program = boundary.program("effect-capability-attenuation", Handlers, Body);
const ToolSite = Program.protocol.operationSite("tool", "call", 0);

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    var runtime = boundary.Runtime.init(allocator);
    defer runtime.deinit();

    var manifest = try Program.Exchange.Manifest.encode(allocator);
    defer manifest.deinit();
    var provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "tool-provider",
        .supported_program_manifest_fingerprints = &[_]u64{manifest.fingerprint},
        .supported_protocol_labels = &[_][]const u8{"tool"},
        .supported_operation_sites = &[_]usize{ ToolSite.index, 999 },
        .supported_protocol_op_fingerprints = &[_]u64{ToolSite.fingerprint},
    });
    defer provider.deinit();

    var parent = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "host",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &[_]usize{ ToolSite.index, 999 },
        .allowed_protocol_op_fingerprints = &[_]u64{ToolSite.fingerprint},
        .allowed_response_kinds = .{},
        .max_payload_bytes = 4096,
    });
    defer parent.deinit();
    var child = try parent.attenuate(allocator, .{
        .allowed_operation_sites = &[_]usize{ToolSite.index},
        .allowed_response_kinds = .{ .return_now = false, .resume_after = false },
        .max_payload_bytes = 1024,
    });
    defer child.deinit();

    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();
    const request = switch (try session.next()) {
        .request => |value| value,
        .after => return error.UnexpectedAfter,
        .done => return error.UnexpectedDone,
    };
    var envelope = try Program.Exchange.RequestEnvelope.fromRequest(allocator, request, .{});
    defer envelope.deinit();
    const allowed = child.allowsRequest(envelope, provider);

    var disallowed_site = try parent.attenuate(allocator, .{
        .allowed_operation_sites = &[_]usize{999},
        .allowed_response_kinds = .{ .return_now = false, .resume_after = false },
        .max_payload_bytes = 1024,
    });
    defer disallowed_site.deinit();
    const site_block = disallowed_site.allowsRequest(envelope, provider);

    const broaden_response_rejected = if (child.attenuate(allocator, .{
        .allowed_response_kinds = .{ .return_now = true },
    })) |broadened_value| blk: {
        var broadened = broadened_value;
        broadened.deinit();
        break :blk false;
    } else |err| err == error.ProgramContractViolation;

    try writer.print("parent_capability_fingerprint={x}\n", .{parent.fingerprint});
    try writer.print("child_capability_fingerprint={x}\n", .{child.fingerprint});
    try writer.print("child_path_fingerprint={x}\n", .{child.attenuation_path_fingerprint});
    try writer.print("allowed_request={}\n", .{allowed.allowed()});
    try writer.print("disallowed_site_blocker={s}\n", .{site_block.firstTagName() orelse "none"});
    try writer.print("broaden_response_rejected={}\n", .{broaden_response_rejected});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
