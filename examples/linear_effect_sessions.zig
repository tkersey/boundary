// zlinter-disable declaration_naming require_doc_comment no_inferred_error_unions
const ability = @import("ability");
const std = @import("std");

const Handlers = struct {};

const Protocol = ability.ir.schema.Protocol(.{
    .label = "linear-demo",
    .ops = .{
        ability.ir.schema.transform("lookup", []const u8, i32),
        ability.ir.schema.transform("charge", []const u8, i32),
    },
});

const Rows = Protocol.Rows(Handlers, .{
    .requirement_index = 0,
    .first_op = 0,
});

const semantic_spec = blk: {
    const semantic = ability.ir.builder.semantic;
    const LookupOp = Rows.op("lookup");
    const ChargeOp = Rows.op("charge");

    break :blk .{
        .label = "linear-effect-sessions",
        .ir_hash = 0x6c696e6561720001,
        .entry = "run",
        .requirements = &.{Rows.requirement},
        .ops = &Rows.ops,
        .functions = .{.{
            .symbol_name = "run",
            .requirements = semantic.span(0, 1),
            .params = .{},
            .locals = .{
                semantic.local("lookup_key", []const u8),
                semantic.local("lookup_value", i32),
                semantic.local("charge_id", []const u8),
                semantic.local("charge_value", i32),
            },
            .result = i32,
            .blocks = .{.{
                .name = "entry",
                .instructions = .{
                    semantic.constString("lookup_key", "cache:plan"),
                    semantic.call(LookupOp, .{
                        .dst = "lookup_value",
                        .payload = "lookup_key",
                        .label = "cache.lookup",
                    }),
                    semantic.constString("charge_id", "payment:charge"),
                    semantic.call(ChargeOp, .{
                        .dst = "charge_value",
                        .payload = "charge_id",
                        .label = "payment.charge",
                    }),
                },
                .terminator = semantic.returnValue("charge_value"),
            }},
        }},
    };
};

const compiled = ability.ir.builder.semantic.finish(semantic_spec) catch |err|
    @compileError("invalid linear-effect-sessions semantic plan: " ++ @errorName(err));

const Body = struct {
    pub const site_metadata = compiled.site_metadata;
    pub const compiled_plan = compiled.plan;
};

const Program = ability.program("linear-effect-sessions", Handlers, Body);

fn nextRequest(session: *Program.Session) !Program.Session.Request {
    return switch (try session.next()) {
        .request => |request| request,
        .after => error.UnexpectedAfter,
        .done => error.UnexpectedDone,
    };
}

fn doneValue(session: *Program.Session) !i32 {
    var result = switch (try session.next()) {
        .done => |done| done,
        .request => return error.UnexpectedRequest,
        .after => return error.UnexpectedAfter,
    };
    defer result.deinit();
    return result.value;
}

pub fn run(writer: anytype) !void {
    const allocator = std.heap.page_allocator;
    var runtime = ability.Runtime.init(allocator);
    defer runtime.deinit();

    var session = try Program.Session.start(&runtime, .{});
    defer session.deinit();

    const lookup_request = try nextRequest(&session);
    var lookup_capsule = try session.capture(allocator);
    defer lookup_capsule.deinit();
    var lookup_image = try lookup_capsule.encode(allocator);
    defer lookup_image.deinit();
    var lookup_envelope = try Program.Exchange.RequestEnvelope.fromRequest(allocator, lookup_request, .{
        .capsule = lookup_image,
        .usage_metadata = .{ .usage = .replayable, .branch_id = 1, .branch_policy = .replay_only, .replay_policy = .replayed },
    });
    defer lookup_envelope.deinit();
    var lookup_response = try Program.Exchange.ResponseEnvelope.@"resume"(allocator, lookup_envelope, @as(i32, 100));
    defer lookup_response.deinit();
    try Program.Exchange.applyResponse(&session, lookup_response, .{ .request_envelope_fingerprint = lookup_envelope.fingerprint });

    var decoded_lookup = try Program.Session.Capsule.decode(allocator, lookup_image.bytes);
    defer decoded_lookup.deinit();
    var replay_branch = try Program.Session.restore(&runtime, .{}, &decoded_lookup);
    defer replay_branch.deinit();
    const replay_lookup_request = switch (try replay_branch.current()) {
        .request => |request| request,
        .after => return error.UnexpectedAfter,
        .none => return error.ExpectedRequest,
    };
    var replay_lookup_envelope = try Program.Exchange.RequestEnvelope.fromRequest(allocator, replay_lookup_request, .{
        .usage_metadata = .{ .usage = .replayable, .branch_id = 2, .branch_policy = .replay_only, .replay_policy = .replayed },
    });
    defer replay_lookup_envelope.deinit();
    var replay_response = try Program.Exchange.ResponseEnvelope.@"resume"(allocator, replay_lookup_envelope, @as(i32, 100));
    defer replay_response.deinit();
    try Program.Exchange.applyResponse(&replay_branch, replay_response, .{ .request_envelope_fingerprint = replay_lookup_envelope.fingerprint });

    const charge_request = try nextRequest(&session);
    var charge_capsule = try session.capture(allocator);
    defer charge_capsule.deinit();
    var charge_image = try charge_capsule.encode(allocator);
    defer charge_image.deinit();
    var charge_envelope = try Program.Exchange.RequestEnvelope.fromRequest(allocator, charge_request, .{
        .capsule = charge_image,
        .usage_metadata = .{ .usage = .linear, .branch_id = 10, .branch_policy = .single_live_branch, .cancelable = true },
    });
    defer charge_envelope.deinit();

    var manifest = try Program.Exchange.Manifest.encode(allocator);
    defer manifest.deinit();
    var provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "payment-provider",
        .supported_program_manifest_fingerprints = &[_]u64{manifest.fingerprint},
    });
    defer provider.deinit();
    var capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "host",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_program_labels = &[_][]const u8{Program.contract.label},
    });
    defer capability.deinit();
    const states = [_][]const u8{ "pending", "charged" };
    const spec = Program.Exchange.EffectSessionSpec{
        .label = "payment-session",
        .initial_state = "pending",
        .states = states[0..],
        .terminal_states = states[1..],
        .usage = .linear,
        .branch_policy = .single_live_branch,
    };
    var instance = try Program.Exchange.CapabilityInstance.create(capability, provider, spec, .{ .snapshot_allocator = allocator, .branch_id = 10 });
    const refs = [_]@TypeOf(charge_envelope.expected_resume_ref.?){charge_envelope.expected_resume_ref.?};
    var obligation = try Program.Exchange.Obligation.open(&instance, charge_envelope, .{}, refs[0..]);
    var charge_response = try Program.Exchange.ResponseEnvelope.@"resume"(allocator, charge_envelope, @as(i32, 7));
    defer charge_response.deinit();
    const consumed = try obligation.consume(charge_response, .fresh);
    const consumed_obligation = try obligation.applyTransition(consumed);
    obligation.deinit();
    obligation = consumed_obligation;
    const consumed_instance = try instance.consume(charge_response.fingerprint);
    instance.deinit();
    instance = consumed_instance;
    try Program.Exchange.applyResponse(&session, charge_response, .{ .request_envelope_fingerprint = charge_envelope.fingerprint });
    const final_result = try doneValue(&session);

    var decoded_charge = try Program.Session.Capsule.decode(allocator, charge_image.bytes);
    defer decoded_charge.deinit();
    var duplicate_branch = try Program.Session.restore(&runtime, .{}, &decoded_charge);
    defer duplicate_branch.deinit();
    const duplicate_request = switch (try duplicate_branch.current()) {
        .request => |request| request,
        .after => return error.UnexpectedAfter,
        .none => return error.ExpectedRequest,
    };
    var duplicate_envelope = try Program.Exchange.RequestEnvelope.fromRequest(allocator, duplicate_request, .{
        .usage_metadata = .{ .usage = .linear, .branch_id = 11, .branch_policy = .single_live_branch },
    });
    defer duplicate_envelope.deinit();
    const duplicate_rejected = if (Program.Exchange.Obligation.open(&instance, duplicate_envelope, .{}, refs[0..])) |duplicate_obligation| rejected: {
        var opened_duplicate = duplicate_obligation;
        opened_duplicate.deinit();
        break :rejected false;
    } else |err| err == error.ProgramContractViolation;

    try writer.print("lookup_obligation_usage=replayable branch=1 replay_branch=2 accepted=true\n", .{});
    try writer.print("charge_obligation_fingerprint={x}\n", .{obligation.obligation_fingerprint});
    try writer.print("capability_instance_fingerprint={x}\n", .{instance.instance_fingerprint});
    try writer.print("charge_branch_id={d} duplicate_branch_id=11 duplicate_fresh_rejected={}\n", .{ obligation.branch_id, duplicate_rejected });
    try writer.print("final_result={d}\n", .{final_result});
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try run(stdout);
    try stdout.flush();
}
