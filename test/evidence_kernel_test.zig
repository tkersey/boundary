// zlinter-disable no_inferred_error_unions no_swallow_error require_doc_comment
const boundary = @import("boundary");
const std = @import("std");

fn unitPlan() boundary.ir.ProgramPlan {
    const root = boundary.ir.builder.function(0);
    const functions = [_]boundary.ir.plan.Function{.{
        .symbol_name = "run",
        .value_codec = .unit,
        .result_codec = .unit,
        .parameter_count = 0,
        .first_requirement = 0,
        .requirement_count = 0,
        .first_output = 0,
        .output_count = 0,
        .first_local = 0,
        .local_count = 0,
        .first_block = 0,
        .entry_block = 0,
        .block_count = 1,
        .first_instruction = 0,
        .instruction_count = 0,
    }};
    const blocks = [_]boundary.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }};
    const terminators = [_]boundary.ir.plan.Terminator{.{ .kind = .return_unit }};
    return boundary.ir.builder.finish(.{
        .label = "evidence-test-plan",
        .ir_hash = 1,
        .entry = root,
        .functions = &functions,
        .requirements = &.{},
        .ops = &.{},
        .outputs = &.{},
        .locals = &.{},
        .blocks = &blocks,
        .terminators = &terminators,
        .instructions = &.{},
    }) catch unreachable;
}

const Program = boundary.program("evidence-test", struct {}, struct {
    pub const compiled_plan = unitPlan();
});

const Evidence = Program.Evidence;

fn hashU32(hasher: *std.hash.Wyhash, value: u32) void {
    var bytes = [_]u8{0} ** 4;
    std.mem.writeInt(u32, &bytes, value, .little);
    hasher.update(&bytes);
}

fn hashU64(hasher: *std.hash.Wyhash, value: u64) void {
    var bytes = [_]u8{0} ** 8;
    std.mem.writeInt(u64, &bytes, value, .little);
    hasher.update(&bytes);
}

fn hashUsize(hasher: *std.hash.Wyhash, value: usize) void {
    hashU64(hasher, @intCast(value));
}

fn hashBytes(hasher: *std.hash.Wyhash, bytes: []const u8) void {
    hashUsize(hasher, bytes.len);
    hasher.update(bytes);
}

fn exchangeFingerprint(domain: Evidence.Domain, bytes: []const u8) u64 {
    const payload = bytes[0 .. bytes.len - 8];
    var hasher = std.hash.Wyhash.init(0);
    hashBytes(&hasher, domain.name);
    hashU32(&hasher, domain.fingerprint_version);
    hashBytes(&hasher, payload);
    return hasher.final();
}

test "evidence domain registry is unique and mirrors public version constants" {
    try Evidence.validateRegistry();

    try std.testing.expectEqual(Program.capsule_image_format_version, Evidence.domains.capsule_image.format_version.?);
    try std.testing.expectEqual(Program.capsule_image_fingerprint_version, Evidence.domains.capsule_image.fingerprint_version);
    try std.testing.expectEqual(Program.journal_format_version, Evidence.domains.journal.format_version.?);
    try std.testing.expectEqual(@as(u32, 4), Evidence.domains.journal_legacy_v4.format_version.?);
    try std.testing.expectEqual(Program.journal_fingerprint_version, Evidence.domains.journal.fingerprint_version);
    try std.testing.expectEqual(Program.exchange_request_format_version, Evidence.domains.exchange_request_envelope.format_version.?);
    try std.testing.expectEqual(Program.exchange_request_fingerprint_version, Evidence.domains.exchange_request_envelope.fingerprint_version);
    try std.testing.expectEqual(Program.exchange_provider_identity_fingerprint_version, Evidence.domains.provider_identity.fingerprint_version);
    try std.testing.expectEqual(Program.exchange_provider_harness_fingerprint_version, Evidence.domains.provider_harness.fingerprint_version);
    try std.testing.expectEqual(@as(u32, 1), Evidence.domains.authorization.format_version.?);
    try std.testing.expectEqual(Program.exchange_treaty_fingerprint_version, Evidence.domains.treaty.fingerprint_version);
    try std.testing.expectEqual(Program.Exchange.treaty_certificate_fingerprint_version, Evidence.domains.treaty_certificate.fingerprint_version);
    try std.testing.expectEqual(Program.exchange_treaty_authorization_fingerprint_version, Evidence.domains.treaty_authorization.fingerprint_version);
    try std.testing.expectEqual(Program.exchange_treaty_authorization_fingerprint_version, Evidence.domains.treaty_authorization.format_version.?);
    try std.testing.expectEqual(Program.evidence_host_intrinsic_format_version, Evidence.domains.host_intrinsic.format_version.?);
    try std.testing.expectEqual(Program.evidence_host_intrinsic_fingerprint_version, Evidence.domains.host_intrinsic.fingerprint_version);
    try std.testing.expectEqual(Program.evidence_semantic_body_fingerprint_version, Evidence.domains.semantic_body.fingerprint_version);
    try std.testing.expectEqual(Program.evidence_defunctionalization_policy_fingerprint_version, Evidence.domains.defunctionalization_policy.fingerprint_version);
    try std.testing.expectEqual(Program.evidence_defunctionalization_report_fingerprint_version, Evidence.domains.defunctionalization_report.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_effect_shape_fingerprint_version, Evidence.domains.boundary_effect_shape.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_static_treaty_plan_fingerprint_version, Evidence.domains.boundary_static_treaty_plan.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_closure_policy_fingerprint_version, Evidence.domains.boundary_closure_policy.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_closure_graph_fingerprint_version, Evidence.domains.boundary_closure_graph.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_closure_report_fingerprint_version, Evidence.domains.boundary_closure_report.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_closure_certificate_format_version, Evidence.domains.boundary_closure_certificate.format_version.?);
    try std.testing.expectEqual(Program.boundary_closure_certificate_fingerprint_version, Evidence.domains.boundary_closure_certificate.fingerprint_version);
    try std.testing.expectEqual(Program.boundary_world_port_format_version, Evidence.domains.boundary_world_port.format_version.?);
    try std.testing.expectEqual(Program.boundary_world_port_fingerprint_version, Evidence.domains.boundary_world_port.fingerprint_version);
    try std.testing.expectEqual(@as(u32, 3), Evidence.domains.treaty_authorization_legacy_v3.format_version.?);
    try std.testing.expectEqual(@as(u32, 2), Evidence.domains.treaty_authorization_legacy_v2.format_version.?);
    try std.testing.expectEqual(Program.pipeline_fingerprint_version, Evidence.domains.pipeline.fingerprint_version);

    try std.testing.expectEqualStrings("boundary.program.capsule.image", Evidence.domains.capsule_image.name);
    try std.testing.expectEqualStrings("boundary.program.session.journal", Evidence.domains.journal.name);
    try std.testing.expectEqualStrings("boundary.exchange.provider_offer", Evidence.domains.provider_offer.name);
    try std.testing.expectEqualStrings("boundary.exchange.morphism_offer", Evidence.domains.morphism_offer.name);
    try std.testing.expectEqualStrings("boundary.exchange.capability.path", Evidence.domains.capability_attenuation_path.name);
    try std.testing.expectEqualStrings("boundary.exchange.authorization.result", Evidence.domains.authorization_result.name);
    try std.testing.expectEqualStrings("boundary.session.reinterpret", Evidence.domains.reinterpretation.name);
    try std.testing.expectEqualStrings("boundary.evidence.semantic_body", Evidence.domains.semantic_body.name);
    try std.testing.expectEqualStrings("boundary.evidence.host_intrinsic", Evidence.domains.host_intrinsic.name);
    try std.testing.expectEqualStrings("boundary.evidence.closure.effect_shape", Evidence.domains.boundary_effect_shape.name);
    try std.testing.expectEqualStrings("boundary.evidence.closure.world_port", Evidence.domains.boundary_world_port.name);
    try std.testing.expectEqualStrings("boundary.evidence.closure.policy", Evidence.domains.boundary_closure_policy.name);

    for (Evidence.all_domains) |domain| {
        try std.testing.expect(domain.request_tokens_excluded);
        try std.testing.expect(domain.runtime_identity_excluded);
        if (domain.bytes_encoded) try std.testing.expect(domain.format_version != null);
        try std.testing.expect(domain.fingerprint_version != 0);
    }
}

test "boundary closure foundational refs use static shape metadata" {
    const unit_ref = Evidence.BoundaryValueRef{ .codec = "unit" };
    const bool_ref = Evidence.BoundaryValueRef{ .codec = "bool" };
    const root_ref = Evidence.refFor(Evidence.domains.program_plan, 0x1111, .{ .label = "root" });
    const treaty_plan_ref = Evidence.refFor(Evidence.domains.boundary_static_treaty_plan, 0x4444, .{ .label = "approval-plan" });
    const operation_sites = [_]Evidence.EffectShape.OperationSite{.{
        .index = 3,
        .fingerprint = 0x2222,
        .requirement_label = "approval",
        .op_name = "ask",
        .payload_ref = unit_ref,
        .resume_ref = bool_ref,
        .has_after = true,
    }};
    const same_operation_sites = [_]Evidence.EffectShape.OperationSite{operation_sites[0]};
    const changed_operation_sites = [_]Evidence.EffectShape.OperationSite{.{
        .index = 3,
        .fingerprint = 0x2223,
        .requirement_label = "approval",
        .op_name = "ask",
        .payload_ref = unit_ref,
        .resume_ref = bool_ref,
        .has_after = true,
    }};
    const shape = Evidence.EffectShape.init(.{
        .label = "root-shape",
        .root_program_ref = root_ref,
        .program_plan_ref = root_ref,
        .operation_sites = operation_sites[0..],
        .static_treaty_plan_refs = &.{treaty_plan_ref},
        .semantic_body_refs = &.{Evidence.SemanticBody.boundary_program.evidenceRef()},
    });
    const same_shape = Evidence.EffectShape.init(.{
        .label = "root-shape",
        .root_program_ref = root_ref,
        .program_plan_ref = root_ref,
        .operation_sites = same_operation_sites[0..],
        .static_treaty_plan_refs = &.{treaty_plan_ref},
        .semantic_body_refs = &.{Evidence.SemanticBody.boundary_program.evidenceRef()},
    });
    const changed_shape = Evidence.EffectShape.init(.{
        .label = "root-shape",
        .root_program_ref = root_ref,
        .program_plan_ref = root_ref,
        .operation_sites = changed_operation_sites[0..],
        .static_treaty_plan_refs = &.{treaty_plan_ref},
        .semantic_body_refs = &.{Evidence.SemanticBody.boundary_program.evidenceRef()},
    });

    try std.testing.expectEqual(shape.fingerprint, same_shape.fingerprint);
    try std.testing.expect(shape.fingerprint != changed_shape.fingerprint);
    try std.testing.expectEqual(Evidence.domains.boundary_effect_shape.id, shape.evidenceRef().domain_id);
    try std.testing.expectEqualStrings("root-shape", shape.evidenceRef().label.?);
    try std.testing.expect(Evidence.refForBoundaryEffectShape(shape).eql(shape.evidenceRef()));
    const closure_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "closure-root",
        .kind = .operation,
        .site_index = 3,
        .site_fingerprint = 0x2222,
        .protocol_label = "approval",
        .protocol_op_fingerprint = 0x2222,
    });
    try std.testing.expect(Evidence.refForBoundaryEffectShape(closure_shape).eql(closure_shape.evidenceRef()));

    const strict = Evidence.BoundaryClosurePolicy.strictStatic();
    const world_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    try std.testing.expect(strict.fingerprint() != world_policy.fingerprint());
    try std.testing.expectEqual(Evidence.domains.boundary_closure_policy.id, strict.evidenceRef().domain_id);
    const intrinsic_ref = Evidence.refFor(Evidence.domains.host_intrinsic, 0xBEEF, .{ .label = "approval-host" });
    try std.testing.expect(!world_policy.allowsHostIntrinsicRef(intrinsic_ref));
    var allowlisted_world_policy = world_policy;
    allowlisted_world_policy.allowed_host_intrinsic_fingerprints = &.{intrinsic_ref.fingerprint};
    try std.testing.expect(allowlisted_world_policy.allowsHostIntrinsicRef(intrinsic_ref));

    const port = Evidence.WorldPort.init(.{
        .label = "approval-world",
        .kind = .host_tool,
        .associated_program_ref = root_ref,
        .reason = "host approval boundary",
        .tags = &.{"approval"},
    });
    try std.testing.expectEqual(Evidence.domains.boundary_world_port.id, port.evidenceRef().domain_id);
    try std.testing.expectEqualStrings("host_tool", port.evidenceRef().kind_tag.?);
    try std.testing.expect(Evidence.refForBoundaryWorldPort(port).eql(port.evidenceRef()));
    const closure_port = Evidence.BoundaryWorldPort.init(.{
        .label = "approval-closure-world",
        .kind = .host_tool,
        .effect_shape_ref = closure_shape.evidenceRef(),
        .exposed_intrinsic_ref = intrinsic_ref,
        .supported_protocol_labels = &.{"approval"},
        .supported_site_indexes = &.{3},
        .supported_protocol_op_fingerprints = &.{0x2222},
    });
    try std.testing.expect(Evidence.refForBoundaryWorldPort(closure_port).eql(closure_port.evidenceRef()));

    const blocker = Evidence.boundaryClosureBlocker(.{
        .tag = .runtime_guard_required,
        .subject = shape.evidenceRef(),
        .primary = port.evidenceRef(),
        .summary = "runtime guard is not a static closure proof",
    });
    try std.testing.expect(blocker.valid());
    try std.testing.expectEqual(Evidence.domains.boundary_closure_report.id, blocker.domain);
    try std.testing.expectEqual(shape.fingerprint, blocker.subject.?.fingerprint);
}

test "static treaty planner matches provider shape without request bytes" {
    const allocator = std.testing.allocator;
    var manifest = try Program.Exchange.Manifest.encode(allocator);
    defer manifest.deinit();

    const payload_ref = boundary.ir.ValueRef{ .codec = .unit };
    const response_ref = boundary.ir.ValueRef{ .codec = .bool };
    const site_index: usize = 4;
    const protocol_op_fingerprint: u64 = 0xCAFE;

    var provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "approval-provider",
        .supported_program_manifest_fingerprints = &.{manifest.fingerprint},
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
    });
    defer provider.deinit();
    var offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "approval-offer",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{response_ref},
    });
    defer offer.deinit();
    const offer_intrinsic_ref = offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    const allowed_intrinsics = [_]u64{offer_intrinsic_ref.fingerprint};
    var world_plan_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    world_plan_policy.allowed_host_intrinsic_fingerprints = allowed_intrinsics[0..];
    var capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "host",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_refs = &.{response_ref},
    });
    defer capability.deinit();

    const shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan",
        .plan_hash = 1,
        .kind = .operation,
        .site_index = site_index,
        .site_fingerprint = protocol_op_fingerprint,
        .name = "approve",
        .mode = "transform",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = protocol_op_fingerprint,
    });

    const plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = world_plan_policy,
    });
    defer allocator.free(plan.blockers);
    defer allocator.free(plan.dependencies);

    try std.testing.expect(plan.closed());
    try std.testing.expectEqual(@as(usize, 1), plan.direct_candidate_count);
    try std.testing.expectEqual(Evidence.domains.boundary_static_treaty_plan.id, plan.evidenceRef().domain_id);
    try std.testing.expectEqual(offer.evidenceRef().fingerprint, plan.selected_provider_offer_ref.?.fingerprint);
    try std.testing.expectEqual(capability.evidenceRef().fingerprint, plan.selected_capability_ref.?.fingerprint);
    try std.testing.expect(!plan.runtime_request_value_validation_required);
    try std.testing.expect(!plan.byte_size_runtime_guard_required);

    var max_zero_closure_policy = world_plan_policy;
    max_zero_closure_policy.defunctionalization_policy.maximum_intrinsic_count = 0;
    const max_zero_closure_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = max_zero_closure_policy,
    });
    defer allocator.free(max_zero_closure_plan.blockers);
    defer allocator.free(max_zero_closure_plan.dependencies);
    try std.testing.expect(!max_zero_closure_plan.closed());
    try std.testing.expectEqual(Evidence.BoundaryClosureBlockerTag.defunctionalization_policy_incompatible, max_zero_closure_plan.blockers[0].tag);

    const max_zero_treaty_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = world_plan_policy,
        .treaty_policy = .{
            .defunctionalization_policy = .{
                .maximum_intrinsic_count = 0,
            },
        },
    });
    defer allocator.free(max_zero_treaty_plan.blockers);
    defer allocator.free(max_zero_treaty_plan.dependencies);
    try std.testing.expect(!max_zero_treaty_plan.closed());
    try std.testing.expectEqual(Evidence.BoundaryClosureBlockerTag.treaty_policy_incompatible, max_zero_treaty_plan.blockers[0].tag);

    var deterministic_replay_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "approval-deterministic-replay-offer",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{response_ref},
        .supported_response_uses = .{ .fresh = false, .replayed = false, .deterministic_replay = true },
    });
    defer deterministic_replay_offer.deinit();
    const deterministic_replay_intrinsic = deterministic_replay_offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    const replay_intrinsics = [_]u64{deterministic_replay_intrinsic.fingerprint};
    var deterministic_replay_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    deterministic_replay_policy.allowed_host_intrinsic_fingerprints = replay_intrinsics[0..];
    const deterministic_replay_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{deterministic_replay_offer},
        .capabilities = &.{capability},
        .treaty_policy = .{ .require_replay_only_response = true },
        .policy = deterministic_replay_policy,
    });
    defer allocator.free(deterministic_replay_plan.blockers);
    defer allocator.free(deterministic_replay_plan.dependencies);
    try std.testing.expect(deterministic_replay_plan.closed());
    var deterministic_replay_result = try Program.BoundaryClosure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_manifests = &.{provider},
        .provider_offers = &.{deterministic_replay_offer},
        .capabilities = &.{capability},
        .treaty_policy = .{ .require_replay_only_response = true },
        .policy = deterministic_replay_policy,
    });
    defer deterministic_replay_result.deinit();
    try deterministic_replay_result.assertClosed();

    var capsule_required_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "approval-capsule-required-offer",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{response_ref},
        .capsule_policy = .required,
    });
    defer capsule_required_offer.deinit();
    const capsule_required_intrinsic = capsule_required_offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    const cap_req_intrinsics = [_]u64{capsule_required_intrinsic.fingerprint};
    var capsule_required_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    capsule_required_policy.allowed_host_intrinsic_fingerprints = cap_req_intrinsics[0..];
    const capsule_required_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{capsule_required_offer},
        .capabilities = &.{capability},
        .policy = capsule_required_policy,
    });
    defer allocator.free(capsule_required_plan.blockers);
    defer allocator.free(capsule_required_plan.dependencies);
    try std.testing.expect(!capsule_required_plan.closed());
    try std.testing.expect(capsule_required_plan.selected_provider_offer_ref == null);

    var capsule_treaty_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    capsule_treaty_policy.allowed_host_intrinsic_fingerprints = allowed_intrinsics[0..];
    const capsule_treaty_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .treaty_policy = .{ .require_capsule_embedding = true },
        .policy = capsule_treaty_policy,
    });
    defer allocator.free(capsule_treaty_plan.blockers);
    defer allocator.free(capsule_treaty_plan.dependencies);
    try std.testing.expect(!capsule_treaty_plan.closed());
    try std.testing.expect(capsule_treaty_plan.selected_provider_offer_ref == null);

    const missing_value_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan",
        .plan_hash = 1,
        .kind = .operation,
        .site_index = site_index,
        .site_fingerprint = protocol_op_fingerprint,
        .name = "approve",
        .mode = "transform",
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = protocol_op_fingerprint,
    });
    const missing_value_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = missing_value_shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = world_plan_policy,
    });
    defer allocator.free(missing_value_plan.blockers);
    defer allocator.free(missing_value_plan.dependencies);
    try std.testing.expect(!missing_value_plan.closed());
    var saw_missing_value_guard = false;
    for (missing_value_plan.blockers) |blocker| {
        if (blocker.tag == .runtime_guard_required) saw_missing_value_guard = true;
    }
    try std.testing.expect(saw_missing_value_guard);
    try std.testing.expect(missing_value_plan.runtime_request_value_validation_required);

    const audit_plan_policy = Evidence.BoundaryClosurePolicy.auditOnly();
    const audit_missing_value_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = missing_value_shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = audit_plan_policy,
    });
    defer allocator.free(audit_missing_value_plan.blockers);
    defer allocator.free(audit_missing_value_plan.dependencies);
    try std.testing.expect(audit_missing_value_plan.closed());
    try std.testing.expect(audit_missing_value_plan.selected_provider_offer_ref != null);
    try std.testing.expect(audit_missing_value_plan.runtime_request_value_validation_required);
    try std.testing.expect(audit_missing_value_plan.byte_size_runtime_guard_required);

    var runtime_guard_reject_policy = audit_plan_policy;
    runtime_guard_reject_policy.allow_runtime_guards = false;
    runtime_guard_reject_policy.reject_runtime_guards = true;
    const rejected_runtime_guard_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = missing_value_shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = runtime_guard_reject_policy,
    });
    defer allocator.free(rejected_runtime_guard_plan.blockers);
    defer allocator.free(rejected_runtime_guard_plan.dependencies);
    try std.testing.expect(!rejected_runtime_guard_plan.closed());
    try std.testing.expect(rejected_runtime_guard_plan.runtime_request_value_validation_required);
    try std.testing.expectEqual(Evidence.BoundaryClosureBlockerTag.runtime_guard_required, rejected_runtime_guard_plan.blockers[0].tag);

    const unknown_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan",
        .plan_hash = 1,
        .kind = .unknown,
        .site_index = site_index,
        .site_fingerprint = protocol_op_fingerprint,
        .name = "approve",
        .mode = "transform",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = protocol_op_fingerprint,
    });
    const unknown_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = unknown_shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = world_plan_policy,
    });
    defer allocator.free(unknown_plan.blockers);
    defer allocator.free(unknown_plan.dependencies);
    try std.testing.expect(!unknown_plan.closed());
    var saw_unhandled_shape = false;
    for (unknown_plan.blockers) |blocker| {
        if (blocker.tag == .effect_shape_unhandled) saw_unhandled_shape = true;
    }
    try std.testing.expect(saw_unhandled_shape);

    var return_only_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "return-only-offer",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{response_ref},
        .allowed_response_kinds = .{ .@"resume" = false, .return_now = true, .resume_after = false },
    });
    defer return_only_offer.deinit();
    var return_only_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "return-only-capability",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_kinds = .{ .@"resume" = false, .return_now = true, .resume_after = false },
        .allowed_response_refs = &.{response_ref},
    });
    defer return_only_capability.deinit();
    const transform_with_return_ref = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan",
        .plan_hash = 1,
        .kind = .operation,
        .site_index = site_index,
        .site_fingerprint = protocol_op_fingerprint,
        .name = "approve",
        .mode = "transform",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .result_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = protocol_op_fingerprint,
    });
    var mode_policy = world_plan_policy;
    const return_intrinsic = return_only_offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    mode_policy.allowed_host_intrinsic_fingerprints = &.{return_intrinsic.fingerprint};
    const impossible_return_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = transform_with_return_ref,
        .provider_manifests = &.{provider},
        .provider_offers = &.{return_only_offer},
        .capabilities = &.{return_only_capability},
        .policy = mode_policy,
    });
    defer allocator.free(impossible_return_plan.blockers);
    defer allocator.free(impossible_return_plan.dependencies);
    try std.testing.expect(!impossible_return_plan.closed());

    var resume_only_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "resume-only-offer",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{response_ref},
        .allowed_response_kinds = .{ .@"resume" = true, .return_now = false, .resume_after = false },
    });
    defer resume_only_offer.deinit();
    var resume_only_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "resume-only-capability",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_kinds = .{ .@"resume" = true, .return_now = false, .resume_after = false },
        .allowed_response_refs = &.{response_ref},
    });
    defer resume_only_capability.deinit();
    const abort_with_resume_ref = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan",
        .plan_hash = 1,
        .kind = .operation,
        .site_index = site_index,
        .site_fingerprint = protocol_op_fingerprint,
        .name = "approve",
        .mode = "abort",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .result_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = protocol_op_fingerprint,
    });
    const resume_intrinsic = resume_only_offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    mode_policy.allowed_host_intrinsic_fingerprints = &.{resume_intrinsic.fingerprint};
    const impossible_resume_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = abort_with_resume_ref,
        .provider_manifests = &.{provider},
        .provider_offers = &.{resume_only_offer},
        .capabilities = &.{resume_only_capability},
        .policy = mode_policy,
    });
    defer allocator.free(impossible_resume_plan.blockers);
    defer allocator.free(impossible_resume_plan.dependencies);
    try std.testing.expect(!impossible_resume_plan.closed());

    var preferred_provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "preferred-approval-provider",
        .provider_fingerprint = 0xA770,
        .supported_program_manifest_fingerprints = &.{manifest.fingerprint},
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
    });
    defer preferred_provider.deinit();
    var preferred_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "preferred-approval-offer",
        .provider_fingerprint = preferred_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{response_ref},
    });
    defer preferred_offer.deinit();
    var preferred_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "preferred-host",
        .provider_fingerprint = preferred_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_refs = &.{response_ref},
    });
    defer preferred_capability.deinit();
    const preferred_intrinsic_ref = preferred_offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    const priority_intrinsics = [_]u64{ offer_intrinsic_ref.fingerprint, preferred_intrinsic_ref.fingerprint };
    var priority_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    priority_policy.allowed_host_intrinsic_fingerprints = priority_intrinsics[0..];
    const priority_order = [_]u64{ preferred_provider.provider_fingerprint, provider.provider_fingerprint };
    const priority_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{ provider, preferred_provider },
        .provider_offers = &.{ offer, preferred_offer },
        .capabilities = &.{ capability, preferred_capability },
        .treaty_policy = .{
            .ambiguity_policy = .host_ordered,
            .provider_priority = priority_order[0..],
        },
        .policy = priority_policy,
    });
    defer allocator.free(priority_plan.blockers);
    defer allocator.free(priority_plan.dependencies);
    try std.testing.expect(priority_plan.closed());
    try std.testing.expectEqual(preferred_offer.evidenceRef().fingerprint, priority_plan.selected_provider_offer_ref.?.fingerprint);

    const static_fresh_disallowed_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .treaty_policy = .{ .disallow_fresh_response = true },
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.blocked, static_fresh_disallowed_plan.status);
    const unnamed_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan",
        .plan_hash = 1,
        .kind = .operation,
        .site_index = site_index,
        .site_fingerprint = protocol_op_fingerprint,
        .mode = "transform",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = protocol_op_fingerprint,
    });
    const unnamed_op_scoped_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = unnamed_shape,
        .manifest = manifest,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.blocked, unnamed_op_scoped_static_plan.status);
    const fresh_disallowed_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .treaty_policy = .{ .disallow_fresh_response = true },
        .policy = world_plan_policy,
    });
    defer allocator.free(fresh_disallowed_plan.blockers);
    defer allocator.free(fresh_disallowed_plan.dependencies);
    try std.testing.expect(!fresh_disallowed_plan.closed());
    try std.testing.expect(fresh_disallowed_plan.selected_provider_offer_ref == null);

    const tag_required_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .treaty_policy = .{ .required_provider_tags = &.{"trusted"} },
    });
    try std.testing.expect(tag_required_static_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);
    const tag_required_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .treaty_policy = .{ .required_provider_tags = &.{"trusted"} },
        .policy = world_plan_policy,
    });
    defer allocator.free(tag_required_plan.blockers);
    defer allocator.free(tag_required_plan.dependencies);
    try std.testing.expect(!tag_required_plan.closed());
    try std.testing.expect(tag_required_plan.selected_provider_offer_ref == null);

    const direct_disabled_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .treaty_policy = .{ .allow_direct_handling = false },
        .policy = world_plan_policy,
    });
    defer allocator.free(direct_disabled_plan.blockers);
    defer allocator.free(direct_disabled_plan.dependencies);
    try std.testing.expect(!direct_disabled_plan.closed());
    try std.testing.expectEqual(@as(usize, 0), direct_disabled_plan.direct_candidate_count);
    try std.testing.expect(direct_disabled_plan.selected_provider_offer_ref == null);

    const missing_provider_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = world_plan_policy,
    });
    defer allocator.free(missing_provider_plan.blockers);
    defer allocator.free(missing_provider_plan.dependencies);
    try std.testing.expect(!missing_provider_plan.closed());
    try std.testing.expect(missing_provider_plan.selected_provider_ref == null);
    try std.testing.expect(missing_provider_plan.selected_provider_offer_ref == null);

    var malformed_offer_base = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "malformed-approval-offer",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"other"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{response_ref},
    });
    defer malformed_offer_base.deinit();
    var forged_offer = malformed_offer_base;
    forged_offer.supported_protocol_labels = &.{"approval"};
    const unbound_offer_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{forged_offer},
        .capabilities = &.{capability},
        .policy = world_plan_policy,
    });
    defer allocator.free(unbound_offer_plan.blockers);
    defer allocator.free(unbound_offer_plan.dependencies);
    try std.testing.expect(!unbound_offer_plan.closed());
    try std.testing.expect(unbound_offer_plan.selected_provider_offer_ref == null);

    var stale_provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "stale-approval-provider",
        .provider_fingerprint = provider.provider_fingerprint,
        .supported_program_manifest_fingerprints = &.{manifest.fingerprint},
        .supported_protocol_labels = &.{"other"},
        .supported_operation_sites = &.{site_index + 1},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint + 1},
    });
    defer stale_provider.deinit();
    const stale_provider_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{stale_provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = world_plan_policy,
    });
    defer allocator.free(stale_provider_plan.blockers);
    defer allocator.free(stale_provider_plan.dependencies);
    try std.testing.expect(!stale_provider_plan.closed());
    try std.testing.expect(stale_provider_plan.selected_provider_ref == null);
    try std.testing.expect(stale_provider_plan.selected_provider_offer_ref == null);

    var forged_provider = stale_provider;
    forged_provider.supported_protocol_labels = &.{"approval"};
    forged_provider.supported_operation_sites = &.{site_index};
    forged_provider.supported_protocol_op_fingerprints = &.{protocol_op_fingerprint};
    const unbound_provider_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{forged_provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = world_plan_policy,
    });
    defer allocator.free(unbound_provider_plan.blockers);
    defer allocator.free(unbound_provider_plan.dependencies);
    try std.testing.expect(!unbound_provider_plan.closed());
    try std.testing.expect(unbound_provider_plan.selected_provider_ref == null);

    const byte_bounded_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan",
        .plan_hash = 1,
        .kind = .operation,
        .site_index = site_index,
        .site_fingerprint = protocol_op_fingerprint,
        .name = "approve",
        .mode = "transform",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = protocol_op_fingerprint,
        .max_request_bytes = 64,
        .max_payload_bytes = 32,
        .max_response_bytes = 16,
        .max_capsule_image_bytes = 8,
    });
    var narrow_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "narrow-byte-capability",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_refs = &.{response_ref},
        .max_request_bytes = 63,
        .max_payload_bytes = 32,
        .max_response_bytes = 16,
        .max_capsule_image_bytes = 8,
    });
    defer narrow_capability.deinit();
    const narrow_capability_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = byte_bounded_shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{narrow_capability},
        .policy = world_plan_policy,
    });
    defer allocator.free(narrow_capability_plan.blockers);
    defer allocator.free(narrow_capability_plan.dependencies);
    try std.testing.expect(!narrow_capability_plan.closed());
    try std.testing.expect(narrow_capability_plan.selected_provider_offer_ref == null);

    var forged_capability = narrow_capability;
    forged_capability.max_request_bytes = 64;
    const unbound_capability_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = byte_bounded_shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{forged_capability},
        .policy = world_plan_policy,
    });
    defer allocator.free(unbound_capability_plan.blockers);
    defer allocator.free(unbound_capability_plan.dependencies);
    try std.testing.expect(!unbound_capability_plan.closed());
    try std.testing.expect(unbound_capability_plan.selected_capability_ref == null);

    var unrelated_static_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "unrelated-static-offer",
        .provider_fingerprint = 0xBADC0DE,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"unrelated"},
        .supported_operation_sites = &.{site_index + 99},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint + 99},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{response_ref},
    });
    defer unrelated_static_offer.deinit();
    const static_plan_with_unrelated_offer = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{provider},
        .provider_offers = &.{ unrelated_static_offer, offer },
        .capabilities = &.{capability},
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.static_treaty, static_plan_with_unrelated_offer.status);
    try std.testing.expect(!static_plan_with_unrelated_offer.blockers.hasErrors());

    var priority_provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "priority-approval-provider",
        .provider_fingerprint = 0xBEEFBEEF,
        .supported_program_manifest_fingerprints = &.{manifest.fingerprint},
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
    });
    defer priority_provider.deinit();
    var priority_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "priority-approval-offer",
        .provider_fingerprint = priority_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{response_ref},
        .max_response_bytes = 8,
    });
    defer priority_offer.deinit();
    const priority_offer_intrinsic_ref = priority_offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    var priority_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "priority-capability",
        .provider_fingerprint = priority_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_refs = &.{response_ref},
        .max_response_bytes = 8,
    });
    defer priority_capability.deinit();
    const provider_priority = [_]u64{priority_provider.provider_fingerprint};
    const host_ordered_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{ provider, priority_provider },
        .provider_offers = &.{ offer, priority_offer },
        .capabilities = &.{ capability, priority_capability },
        .treaty_policy = .{
            .ambiguity_policy = .host_ordered,
            .provider_priority = provider_priority[0..],
        },
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.static_treaty, host_ordered_static_plan.status);
    try std.testing.expectEqual(priority_provider.provider_fingerprint, host_ordered_static_plan.provider_fingerprint);
    try std.testing.expect(!host_ordered_static_plan.blockers.hasErrors());

    const broad_provider_priority = [_]u64{provider.provider_fingerprint};
    const least_authority_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{ provider, priority_provider },
        .provider_offers = &.{ offer, priority_offer },
        .capabilities = &.{ capability, priority_capability },
        .treaty_policy = .{
            .ambiguity_policy = .prefer_least_authority,
            .provider_priority = broad_provider_priority[0..],
        },
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.static_treaty, least_authority_static_plan.status);
    try std.testing.expectEqual(priority_provider.provider_fingerprint, least_authority_static_plan.provider_fingerprint);
    try std.testing.expect(!least_authority_static_plan.blockers.hasErrors());

    var least_authority_closure_policy = world_plan_policy;
    const least_allowed_intrinsics = [_]u64{ offer_intrinsic_ref.fingerprint, priority_offer_intrinsic_ref.fingerprint };
    least_authority_closure_policy.allowed_host_intrinsic_fingerprints = least_allowed_intrinsics[0..];
    const least_authority_closure_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{ provider, priority_provider },
        .provider_offers = &.{ offer, priority_offer },
        .capabilities = &.{ capability, priority_capability },
        .treaty_policy = .{
            .ambiguity_policy = .prefer_least_authority,
            .provider_priority = broad_provider_priority[0..],
        },
        .policy = least_authority_closure_policy,
    });
    defer allocator.free(least_authority_closure_plan.blockers);
    defer allocator.free(least_authority_closure_plan.dependencies);
    try std.testing.expect(least_authority_closure_plan.closed());
    try std.testing.expectEqual(priority_offer.evidenceRef().fingerprint, least_authority_closure_plan.selected_provider_offer_ref.?.fingerprint);

    var least_broad_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "broad-host",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_refs = &.{response_ref},
        .max_response_bytes = 1024,
        .max_payload_bytes = 1024,
    });
    defer least_broad_capability.deinit();
    var least_narrow_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "narrow-host",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_refs = &.{response_ref},
        .max_response_bytes = 8,
        .max_payload_bytes = 8,
    });
    defer least_narrow_capability.deinit();
    const least_authority_capability_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{ least_broad_capability, least_narrow_capability },
        .treaty_policy = .{ .ambiguity_policy = .prefer_least_authority },
        .policy = world_plan_policy,
    });
    defer allocator.free(least_authority_capability_plan.blockers);
    defer allocator.free(least_authority_capability_plan.dependencies);
    try std.testing.expect(least_authority_capability_plan.closed());
    try std.testing.expectEqual(least_narrow_capability.evidenceRef().fingerprint, least_authority_capability_plan.selected_capability_ref.?.fingerprint);

    const static_plan_with_rejected_candidate = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{ provider, priority_provider },
        .provider_offers = &.{ priority_offer, offer },
        .capabilities = &.{capability},
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.static_treaty, static_plan_with_rejected_candidate.status);
    try std.testing.expect(!static_plan_with_rejected_candidate.blockers.hasErrors());
    const static_plan_report = static_plan_with_rejected_candidate.toEvidenceReport(&.{});
    try std.testing.expect(static_plan_report.success);
    try std.testing.expect(static_plan_report.subject.eql(static_plan_with_rejected_candidate.evidenceRef()));

    const bounded_authority_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .treaty_policy = .{ .max_envelope_bytes = 64 },
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.static_treaty, bounded_authority_static_plan.status);
    try std.testing.expect(static_plan_with_rejected_candidate.fingerprint != bounded_authority_static_plan.fingerprint);

    var program_required_policy = world_plan_policy;
    program_required_policy.require_program_backed_providers = true;
    const program_required_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = program_required_policy,
    });
    defer allocator.free(program_required_plan.blockers);
    defer allocator.free(program_required_plan.dependencies);
    try std.testing.expect(!program_required_plan.closed());
    try std.testing.expect(program_required_plan.selected_provider_offer_ref == null);

    var defunc_program_required_policy = world_plan_policy;
    defunc_program_required_policy.defunctionalization_policy.require_program_backed_providers = true;
    const defunc_program_required_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = defunc_program_required_policy,
    });
    defer allocator.free(defunc_program_required_plan.blockers);
    defer allocator.free(defunc_program_required_plan.dependencies);
    try std.testing.expect(!defunc_program_required_plan.closed());
    try std.testing.expect(defunc_program_required_plan.selected_provider_offer_ref == null);

    var wrong_response_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "wrong-response-approval-offer",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{boundary.ir.ValueRef{ .codec = .i32 }},
    });
    defer wrong_response_offer.deinit();
    const wrong_response_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{wrong_response_offer},
        .capabilities = &.{capability},
        .policy = world_plan_policy,
    });
    defer allocator.free(wrong_response_plan.blockers);
    defer allocator.free(wrong_response_plan.dependencies);
    try std.testing.expect(!wrong_response_plan.closed());
    try std.testing.expect(wrong_response_plan.selected_provider_offer_ref == null);

    const static_return_ref = boundary.ir.ValueRef{ .codec = .i32 };
    const multi_response_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan",
        .plan_hash = 1,
        .kind = .operation,
        .site_index = site_index,
        .site_fingerprint = protocol_op_fingerprint,
        .name = "approve",
        .mode = "transform",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .result_ref = Evidence.BoundaryValueRef.fromValueRef(static_return_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = protocol_op_fingerprint,
    });
    var wrong_kind_static_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "wrong-response-kind-static-offer",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{response_ref},
        .allowed_response_kinds = .{ .@"resume" = false, .return_now = true, .resume_after = false },
    });
    defer wrong_kind_static_offer.deinit();
    var multi_response_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "multi-response-capability",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_kinds = .{ .@"resume" = false, .return_now = true, .resume_after = false },
        .allowed_response_refs = &.{static_return_ref},
    });
    defer multi_response_capability.deinit();
    const wrong_kind_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = multi_response_shape,
        .manifest = manifest,
        .provider_manifests = &.{provider},
        .provider_offers = &.{wrong_kind_static_offer},
        .capabilities = &.{multi_response_capability},
    });
    try std.testing.expect(wrong_kind_static_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);

    var no_resume_provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "no-resume-provider",
        .supported_program_manifest_fingerprints = &.{manifest.fingerprint},
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .allowed_response_kinds = .{ .@"resume" = false, .return_now = true, .resume_after = false },
    });
    defer no_resume_provider.deinit();
    const no_resume_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{no_resume_provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = world_plan_policy,
    });
    defer allocator.free(no_resume_plan.blockers);
    defer allocator.free(no_resume_plan.dependencies);
    try std.testing.expect(!no_resume_plan.closed());
    try std.testing.expect(no_resume_plan.selected_provider_offer_ref == null);
    const no_resume_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{no_resume_provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
    });
    try std.testing.expect(no_resume_static_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);

    const no_resume_route_policy = Program.Exchange.Policy{
        .allowed_response_kinds = .{ .@"resume" = false, .return_now = true, .resume_after = false },
    };
    const no_resume_policy_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .route_policy = no_resume_route_policy,
    });
    try std.testing.expect(no_resume_policy_static_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);
    const no_resume_policy_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .route_policy = no_resume_route_policy,
        .policy = world_plan_policy,
    });
    defer allocator.free(no_resume_policy_plan.blockers);
    defer allocator.free(no_resume_policy_plan.dependencies);
    try std.testing.expect(!no_resume_policy_plan.closed());
    try std.testing.expect(no_resume_policy_plan.selected_provider_offer_ref == null);

    const denied_provider_fingerprints = [_]u64{provider.provider_fingerprint +% 1};
    const denied_provider_route_policy = Program.Exchange.Policy{ .allowed_provider_fingerprints = denied_provider_fingerprints[0..] };
    const denied_provider_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .route_policy = denied_provider_route_policy,
    });
    try std.testing.expect(denied_provider_static_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);
    const denied_provider_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .route_policy = denied_provider_route_policy,
        .policy = world_plan_policy,
    });
    defer allocator.free(denied_provider_plan.blockers);
    defer allocator.free(denied_provider_plan.dependencies);
    try std.testing.expect(!denied_provider_plan.closed());

    const denied_capability_fingerprints = [_]u64{capability.fingerprint +% 1};
    const denied_capability_route_policy = Program.Exchange.Policy{ .allowed_capability_fingerprints = denied_capability_fingerprints[0..] };
    const denied_capability_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .route_policy = denied_capability_route_policy,
    });
    try std.testing.expect(denied_capability_static_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);

    const byte_bound_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan",
        .plan_hash = 1,
        .kind = .operation,
        .site_index = site_index,
        .site_fingerprint = protocol_op_fingerprint,
        .name = "approve",
        .mode = "transform",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = protocol_op_fingerprint,
        .max_request_bytes = 64,
    });
    var narrow_provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "narrow-provider",
        .supported_program_manifest_fingerprints = &.{manifest.fingerprint},
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .max_request_envelope_bytes = 32,
    });
    defer narrow_provider.deinit();
    const narrow_provider_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = byte_bound_shape,
        .manifest = manifest,
        .provider_manifests = &.{narrow_provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
    });
    try std.testing.expect(narrow_provider_static_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);
    var narrow_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "narrow-offer",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{response_ref},
        .max_request_bytes = 32,
    });
    defer narrow_offer.deinit();
    const narrow_offer_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = byte_bound_shape,
        .manifest = manifest,
        .provider_manifests = &.{provider},
        .provider_offers = &.{narrow_offer},
        .capabilities = &.{capability},
    });
    try std.testing.expect(narrow_offer_static_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);

    var wrong_response_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "wrong-response-capability",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_refs = &.{boundary.ir.ValueRef{ .codec = .i32 }},
    });
    defer wrong_response_capability.deinit();
    const wrong_capability_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{wrong_response_capability},
        .policy = world_plan_policy,
    });
    defer allocator.free(wrong_capability_plan.blockers);
    defer allocator.free(wrong_capability_plan.dependencies);
    try std.testing.expect(!wrong_capability_plan.closed());
    try std.testing.expect(wrong_capability_plan.selected_provider_offer_ref == null);

    var after_only_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "after-only-capability",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_request_kinds = .{ .operation = false, .after = true },
        .allowed_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_refs = &.{response_ref},
    });
    defer after_only_capability.deinit();
    const wrong_kind_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{after_only_capability},
        .policy = world_plan_policy,
    });
    defer allocator.free(wrong_kind_plan.blockers);
    defer allocator.free(wrong_kind_plan.dependencies);
    try std.testing.expect(!wrong_kind_plan.closed());
    try std.testing.expect(wrong_kind_plan.selected_provider_offer_ref == null);

    const return_ref = boundary.ir.ValueRef{ .codec = .i32 };
    var return_now_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "return-now-approval-offer",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{return_ref},
        .allowed_response_kinds = .{ .@"resume" = false, .return_now = true, .resume_after = false },
    });
    defer return_now_offer.deinit();
    const return_now_intrinsic_ref = return_now_offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    const allowed_return_now_intrinsics = [_]u64{return_now_intrinsic_ref.fingerprint};
    var return_now_policy = world_plan_policy;
    return_now_policy.allowed_host_intrinsic_fingerprints = allowed_return_now_intrinsics[0..];
    var return_now_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "return-now-capability",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_kinds = .{ .@"resume" = false, .return_now = true, .resume_after = false },
        .allowed_response_refs = &.{return_ref},
    });
    defer return_now_capability.deinit();
    const return_now_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan",
        .plan_hash = 1,
        .kind = .operation,
        .site_index = site_index,
        .site_fingerprint = protocol_op_fingerprint,
        .name = "approve",
        .mode = "abort",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .result_ref = Evidence.BoundaryValueRef.fromValueRef(return_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = protocol_op_fingerprint,
    });
    const return_now_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = return_now_shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{return_now_offer},
        .capabilities = &.{return_now_capability},
        .policy = return_now_policy,
    });
    defer allocator.free(return_now_plan.blockers);
    defer allocator.free(return_now_plan.dependencies);
    try std.testing.expect(return_now_plan.closed());
    try std.testing.expectEqual(return_now_offer.evidenceRef().fingerprint, return_now_plan.selected_provider_offer_ref.?.fingerprint);
    const desired_return_refs = [_]Evidence.BoundaryValueRef{Evidence.BoundaryValueRef.fromValueRef(return_ref)};
    const desired_return_now_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan",
        .plan_hash = 1,
        .kind = .operation,
        .site_index = site_index,
        .site_fingerprint = protocol_op_fingerprint,
        .name = "approve",
        .mode = "abort",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .result_ref = Evidence.BoundaryValueRef.fromValueRef(return_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = protocol_op_fingerprint,
        .desired_response_refs = desired_return_refs[0..],
    });
    const desired_return_now_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = desired_return_now_shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{return_now_offer},
        .capabilities = &.{return_now_capability},
        .policy = return_now_policy,
    });
    defer allocator.free(desired_return_now_plan.blockers);
    defer allocator.free(desired_return_now_plan.dependencies);
    try std.testing.expect(desired_return_now_plan.closed());
    try std.testing.expectEqual(return_now_offer.evidenceRef().fingerprint, desired_return_now_plan.selected_provider_offer_ref.?.fingerprint);

    const desired_return_only_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan",
        .plan_hash = 1,
        .kind = .operation,
        .site_index = site_index,
        .site_fingerprint = protocol_op_fingerprint,
        .name = "approve",
        .mode = "abort",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .result_ref = Evidence.BoundaryValueRef.fromValueRef(return_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = protocol_op_fingerprint,
        .desired_response_refs = desired_return_refs[0..],
    });
    var resume_only_return_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "resume-only-return-offer",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{return_ref},
        .allowed_response_kinds = .{ .@"resume" = true, .return_now = false, .resume_after = false },
    });
    defer resume_only_return_offer.deinit();
    var resume_only_return_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "resume-only-return-capability",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_kinds = .{ .@"resume" = true, .return_now = false, .resume_after = false },
        .allowed_response_refs = &.{return_ref},
    });
    defer resume_only_return_capability.deinit();
    const resume_only_return_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = desired_return_only_shape,
        .manifest = manifest,
        .provider_manifests = &.{provider},
        .provider_offers = &.{resume_only_return_offer},
        .capabilities = &.{resume_only_return_capability},
    });
    try std.testing.expect(resume_only_return_static_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);
    const resume_only_return_intrinsic_ref = resume_only_return_offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    const resume_only_intrinsics = [_]u64{resume_only_return_intrinsic_ref.fingerprint};
    var resume_only_policy = world_plan_policy;
    resume_only_policy.allowed_host_intrinsic_fingerprints = resume_only_intrinsics[0..];
    const resume_only_return_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = desired_return_only_shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{resume_only_return_offer},
        .capabilities = &.{resume_only_return_capability},
        .policy = resume_only_policy,
    });
    defer allocator.free(resume_only_return_plan.blockers);
    defer allocator.free(resume_only_return_plan.dependencies);
    try std.testing.expect(!resume_only_return_plan.closed());
    try std.testing.expect(resume_only_return_plan.selected_provider_offer_ref == null);

    const no_response_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan",
        .plan_hash = 1,
        .kind = .operation,
        .site_index = site_index,
        .site_fingerprint = protocol_op_fingerprint,
        .name = "approve",
        .mode = "transform",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = protocol_op_fingerprint,
    });
    const no_response_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = no_response_shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = world_plan_policy,
    });
    defer allocator.free(no_response_plan.blockers);
    defer allocator.free(no_response_plan.dependencies);
    try std.testing.expect(!no_response_plan.closed());
    try std.testing.expect(no_response_plan.selected_provider_offer_ref == null);

    const impossible_desired_refs = [_]Evidence.BoundaryValueRef{Evidence.BoundaryValueRef.fromValueRef(return_ref)};
    const impossible_desired_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan",
        .plan_hash = 1,
        .kind = .operation,
        .site_index = site_index,
        .site_fingerprint = protocol_op_fingerprint,
        .name = "approve",
        .mode = "transform",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = protocol_op_fingerprint,
        .desired_response_refs = impossible_desired_refs[0..],
    });
    const impossible_desired_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = impossible_desired_shape,
        .manifest = manifest,
        .provider_manifests = &.{provider},
        .provider_offers = &.{resume_only_return_offer},
        .capabilities = &.{resume_only_return_capability},
    });
    try std.testing.expect(impossible_desired_static_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);
    const impossible_desired_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = impossible_desired_shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{resume_only_return_offer},
        .capabilities = &.{resume_only_return_capability},
        .policy = resume_only_policy,
    });
    defer allocator.free(impossible_desired_plan.blockers);
    defer allocator.free(impossible_desired_plan.dependencies);
    try std.testing.expect(!impossible_desired_plan.closed());
    try std.testing.expect(impossible_desired_plan.selected_provider_offer_ref == null);

    var unauthorized_provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "unauthorized-approval-provider",
        .supported_program_manifest_fingerprints = &.{manifest.fingerprint},
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
    });
    defer unauthorized_provider.deinit();
    var unauthorized_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "unauthorized-approval-offer",
        .provider_fingerprint = unauthorized_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{response_ref},
    });
    defer unauthorized_offer.deinit();
    const plan_with_unusable_offer = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{ unauthorized_provider, provider },
        .provider_offers = &.{ unauthorized_offer, offer },
        .capabilities = &.{capability},
        .policy = world_plan_policy,
    });
    defer allocator.free(plan_with_unusable_offer.blockers);
    defer allocator.free(plan_with_unusable_offer.dependencies);
    try std.testing.expect(plan_with_unusable_offer.closed());
    try std.testing.expectEqual(@as(usize, 0), plan_with_unusable_offer.blockers.len);
    try std.testing.expectEqual(offer.evidenceRef().fingerprint, plan_with_unusable_offer.selected_provider_offer_ref.?.fingerprint);

    const after_site_index: usize = 9;
    const after_current_ref = boundary.ir.ValueRef{ .codec = .i32 };
    const after_output_ref = boundary.ir.ValueRef{ .codec = .bool };
    var after_provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "approval-after-provider",
        .supported_program_manifest_fingerprints = &.{manifest.fingerprint},
        .supported_protocol_labels = &.{"approval"},
        .supported_after_sites = &.{after_site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .allowed_response_kinds = .{ .@"resume" = false, .return_now = false, .resume_after = true },
    });
    defer after_provider.deinit();
    var after_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "approval-after-offer",
        .provider_fingerprint = after_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_after_sites = &.{after_site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .accepted_current_value_refs = &.{after_current_ref},
        .produced_response_refs = &.{after_output_ref},
        .allowed_response_kinds = .{ .@"resume" = false, .return_now = false, .resume_after = true },
    });
    defer after_offer.deinit();
    const after_offer_intrinsic_ref = after_offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    const allowed_after_intrinsics = [_]u64{after_offer_intrinsic_ref.fingerprint};
    var world_after_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    world_after_policy.allowed_host_intrinsic_fingerprints = allowed_after_intrinsics[0..];
    var after_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "after-test",
        .provider_fingerprint = after_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_request_kinds = .{ .operation = false, .after = true },
        .allowed_after_sites = &.{after_site_index},
        .allowed_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_kinds = .{ .@"resume" = false, .return_now = false, .resume_after = true },
        .allowed_response_refs = &.{after_output_ref},
    });
    defer after_capability.deinit();
    const after_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan",
        .plan_hash = 1,
        .kind = .after,
        .site_index = after_site_index,
        .site_fingerprint = 0xF00D,
        .name = "approve",
        .mode = "after",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(after_current_ref),
        .expected_after_ref = Evidence.BoundaryValueRef.fromValueRef(after_output_ref),
        .result_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = protocol_op_fingerprint,
    });
    const after_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = after_shape,
        .provider_manifests = &.{after_provider},
        .provider_offers = &.{after_offer},
        .capabilities = &.{after_capability},
        .policy = world_after_policy,
    });
    defer allocator.free(after_plan.blockers);
    defer allocator.free(after_plan.dependencies);
    try std.testing.expect(after_plan.closed());
    try std.testing.expectEqual(after_offer.evidenceRef().fingerprint, after_plan.selected_provider_offer_ref.?.fingerprint);

    const target_protocol_op_fingerprint: u64 = 0xFACE;
    const morphism_target_response_ref = boundary.ir.ValueRef{ .codec = .i32 };
    var morphism_target_provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "approval-morphism-target-provider",
        .supported_program_manifest_fingerprints = &.{manifest.fingerprint},
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{target_protocol_op_fingerprint},
    });
    defer morphism_target_provider.deinit();
    var morphism_target_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "approval-morphism-target-offer",
        .provider_fingerprint = morphism_target_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{target_protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{morphism_target_response_ref},
    });
    defer morphism_target_offer.deinit();
    const morphism_target_intrinsic_ref = morphism_target_offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    const allowed_morphism_intrinsics = [_]u64{morphism_target_intrinsic_ref.fingerprint};
    var morphism_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    morphism_policy.allowed_host_intrinsic_fingerprints = allowed_morphism_intrinsics[0..];
    var morphism_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "morphism-capability",
        .provider_fingerprint = morphism_target_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{target_protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_refs = &.{morphism_target_response_ref},
    });
    defer morphism_capability.deinit();
    var source_only_morphism_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "source-only-morphism-capability",
        .provider_fingerprint = morphism_target_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_refs = &.{response_ref},
    });
    defer source_only_morphism_capability.deinit();
    const morphism_offer = Program.Exchange.MorphismOffer{
        .label = "approval-static-morphism",
        .source_site_fingerprint = protocol_op_fingerprint,
        .source_protocol_op_fingerprint = protocol_op_fingerprint,
        .target_protocol_op_fingerprint = target_protocol_op_fingerprint,
        .pipeline_fingerprint = 0x515151,
        .source_response_refs = &.{response_ref},
        .target_response_refs = &.{morphism_target_response_ref},
    };
    var multi_target_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "approval-multi-target-offer",
        .provider_fingerprint = morphism_target_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{target_protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{ morphism_target_response_ref, response_ref },
    });
    defer multi_target_offer.deinit();
    const multi_target_intrinsic_ref = multi_target_offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    const wildcard_morphism_intrinsics = [_]u64{ morphism_target_intrinsic_ref.fingerprint, multi_target_intrinsic_ref.fingerprint };
    var wildcard_morphism_policy = morphism_policy;
    wildcard_morphism_policy.allowed_host_intrinsic_fingerprints = wildcard_morphism_intrinsics[0..];
    var multi_target_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "multi-target-capability",
        .provider_fingerprint = morphism_target_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{target_protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_refs = &.{ morphism_target_response_ref, response_ref },
    });
    defer multi_target_capability.deinit();
    const source_subset_multi_target_morphism = Program.Exchange.MorphismOffer{
        .label = "approval-source-subset-multi-target-morphism",
        .source_site_fingerprint = protocol_op_fingerprint,
        .source_protocol_op_fingerprint = protocol_op_fingerprint,
        .target_protocol_op_fingerprint = target_protocol_op_fingerprint,
        .pipeline_fingerprint = 0x515154,
        .source_response_refs = &.{response_ref},
        .target_response_refs = &.{ morphism_target_response_ref, response_ref },
    };
    const source_subset_multi_target_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{multi_target_offer},
        .morphism_offers = &.{source_subset_multi_target_morphism},
        .capabilities = &.{multi_target_capability},
        .treaty_policy = .{ .allow_direct_handling = false },
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.static_treaty, source_subset_multi_target_static_plan.status);
    const wildcard_source_target_morphism = Program.Exchange.MorphismOffer{
        .label = "approval-wildcard-source-target-morphism",
        .source_site_fingerprint = protocol_op_fingerprint,
        .source_protocol_op_fingerprint = protocol_op_fingerprint,
        .target_protocol_op_fingerprint = target_protocol_op_fingerprint,
        .pipeline_fingerprint = 0x515157,
        .target_response_refs = &.{morphism_target_response_ref},
    };
    const wildcard_source_target_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{multi_target_offer},
        .morphism_offers = &.{wildcard_source_target_morphism},
        .capabilities = &.{multi_target_capability},
        .treaty_policy = .{ .allow_direct_handling = false },
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.static_treaty, wildcard_source_target_static_plan.status);
    const wildcard_source_target_closure_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{multi_target_offer},
        .morphism_offers = &.{wildcard_source_target_morphism},
        .capabilities = &.{multi_target_capability},
        .treaty_policy = .{ .allow_direct_handling = false },
        .policy = wildcard_morphism_policy,
    });
    defer allocator.free(wildcard_source_target_closure_plan.blockers);
    defer allocator.free(wildcard_source_target_closure_plan.dependencies);
    try std.testing.expect(wildcard_source_target_closure_plan.closed());
    var wildcard_source_target_closure = try Program.BoundaryClosure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{multi_target_offer},
        .morphism_offers = &.{wildcard_source_target_morphism},
        .capabilities = &.{multi_target_capability},
        .treaty_policy = .{ .allow_direct_handling = false },
        .policy = wildcard_morphism_policy,
    });
    defer wildcard_source_target_closure.deinit();
    try wildcard_source_target_closure.assertClosedExceptWorldPorts();
    try std.testing.expectEqual(@as(usize, 1), wildcard_source_target_closure.report.residualized_pipeline_route_count);
    try std.testing.expectEqual(@as(usize, 0), wildcard_source_target_closure.report.declarative_route_count);
    const partial_offer_multi_target_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{source_subset_multi_target_morphism},
        .capabilities = &.{multi_target_capability},
        .treaty_policy = .{ .allow_direct_handling = false },
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.blocked, partial_offer_multi_target_static_plan.status);
    try std.testing.expectEqual(@as(usize, 0), partial_offer_multi_target_static_plan.candidate_count);
    const partial_capability_multi_target_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{multi_target_offer},
        .morphism_offers = &.{source_subset_multi_target_morphism},
        .capabilities = &.{morphism_capability},
        .treaty_policy = .{ .allow_direct_handling = false },
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.no_static_treaty, partial_capability_multi_target_static_plan.status);
    try std.testing.expectEqual(@as(usize, 0), partial_capability_multi_target_static_plan.candidate_count);
    const extra_target_response_ref = boundary.ir.ValueRef{ .codec = .usize };
    const omitted_target_response_ref = boundary.ir.ValueRef{ .codec = .string };
    var capped_target_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "approval-capped-target-offer",
        .provider_fingerprint = morphism_target_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{target_protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{ morphism_target_response_ref, response_ref, extra_target_response_ref },
    });
    defer capped_target_offer.deinit();
    var capped_target_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "capped-target-capability",
        .provider_fingerprint = morphism_target_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{target_protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_refs = &.{ morphism_target_response_ref, response_ref, extra_target_response_ref },
    });
    defer capped_target_capability.deinit();
    const over_capacity_target_morphism = Program.Exchange.MorphismOffer{
        .label = "approval-over-capacity-target-morphism",
        .source_site_fingerprint = protocol_op_fingerprint,
        .source_protocol_op_fingerprint = protocol_op_fingerprint,
        .target_protocol_op_fingerprint = target_protocol_op_fingerprint,
        .pipeline_fingerprint = 0x515155,
        .source_response_refs = &.{response_ref},
        .target_response_refs = &.{ morphism_target_response_ref, response_ref, extra_target_response_ref, omitted_target_response_ref },
    };
    const over_capacity_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{capped_target_offer},
        .morphism_offers = &.{over_capacity_target_morphism},
        .capabilities = &.{capped_target_capability},
        .treaty_policy = .{ .allow_direct_handling = false },
    });
    try std.testing.expect(over_capacity_static_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);
    const over_capacity_closure_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{capped_target_offer},
        .morphism_offers = &.{over_capacity_target_morphism},
        .capabilities = &.{capped_target_capability},
        .policy = morphism_policy,
    });
    defer allocator.free(over_capacity_closure_plan.blockers);
    defer allocator.free(over_capacity_closure_plan.dependencies);
    try std.testing.expect(!over_capacity_closure_plan.closed());
    try std.testing.expect(over_capacity_closure_plan.selected_morphism_ref == null);
    const multi_target_intrinsics = [_]u64{multi_target_intrinsic_ref.fingerprint};
    var multi_target_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    multi_target_policy.allowed_host_intrinsic_fingerprints = multi_target_intrinsics[0..];
    const partial_target_closure_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{multi_target_offer},
        .morphism_offers = &.{source_subset_multi_target_morphism},
        .capabilities = &.{morphism_capability},
        .treaty_policy = .{ .allow_direct_handling = false },
        .policy = multi_target_policy,
    });
    defer allocator.free(partial_target_closure_plan.blockers);
    defer allocator.free(partial_target_closure_plan.dependencies);
    try std.testing.expect(!partial_target_closure_plan.closed());
    try std.testing.expect(partial_target_closure_plan.selected_morphism_ref == null);
    var label_scoped_target_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "label-scoped-target-capability",
        .provider_fingerprint = morphism_target_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_refs = &.{morphism_target_response_ref},
    });
    defer label_scoped_target_capability.deinit();
    const label_scoped_target_static_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{label_scoped_target_capability},
        .treaty_policy = .{ .allow_direct_handling = false },
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.no_static_treaty, label_scoped_target_static_plan.status);
    const dynamic_morphism_offer = Program.Exchange.MorphismOffer{
        .label = "approval-dynamic-morphism",
        .source_site_fingerprint = protocol_op_fingerprint,
        .source_protocol_op_fingerprint = protocol_op_fingerprint,
        .target_protocol_op_fingerprint = target_protocol_op_fingerprint,
        .dynamic_morphism_fingerprint = 0xD1A,
        .source_response_refs = &.{response_ref},
        .target_response_refs = &.{morphism_target_response_ref},
    };
    const dynamic_morphism_intrinsic_ref = dynamic_morphism_offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    const dynamic_morphism_intrinsics = [_]u64{ morphism_target_intrinsic_ref.fingerprint, dynamic_morphism_intrinsic_ref.fingerprint };
    var dynamic_morphism_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    dynamic_morphism_policy.allowed_host_intrinsic_fingerprints = dynamic_morphism_intrinsics[0..];
    const dynamic_morphism_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{dynamic_morphism_offer},
        .capabilities = &.{morphism_capability},
        .policy = dynamic_morphism_policy,
    });
    defer allocator.free(dynamic_morphism_plan.blockers);
    defer allocator.free(dynamic_morphism_plan.dependencies);
    try std.testing.expect(dynamic_morphism_plan.closed());
    try std.testing.expectEqual(dynamic_morphism_offer.evidenceRef().fingerprint, dynamic_morphism_plan.selected_morphism_ref.?.fingerprint);
    try Evidence.expectDependencyContains(dynamic_morphism_plan.dependencies, .offer, morphism_target_offer.evidenceRef());
    try Evidence.expectDependencyContains(dynamic_morphism_plan.dependencies, .capability, morphism_capability.evidenceRef());
    const mixed_morphism_offer = Program.Exchange.MorphismOffer{
        .label = "approval-mixed-morphism",
        .source_site_fingerprint = protocol_op_fingerprint,
        .source_protocol_op_fingerprint = protocol_op_fingerprint,
        .target_protocol_op_fingerprint = target_protocol_op_fingerprint,
        .dynamic_morphism_fingerprint = 0xD1A,
        .pipeline_fingerprint = 0x515152,
        .source_response_refs = &.{response_ref},
        .target_response_refs = &.{morphism_target_response_ref},
    };
    const mixed_morphism_intrinsic_ref = mixed_morphism_offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    const mixed_morphism_intrinsics = [_]u64{ morphism_target_intrinsic_ref.fingerprint, mixed_morphism_intrinsic_ref.fingerprint };
    var mixed_morphism_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    mixed_morphism_policy.allowed_host_intrinsic_fingerprints = mixed_morphism_intrinsics[0..];
    const mixed_morphism_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{mixed_morphism_offer},
        .capabilities = &.{morphism_capability},
        .policy = mixed_morphism_policy,
    });
    defer allocator.free(mixed_morphism_plan.blockers);
    defer allocator.free(mixed_morphism_plan.dependencies);
    try std.testing.expect(!mixed_morphism_plan.closed());
    try std.testing.expect(mixed_morphism_plan.selected_morphism_ref == null);
    const dynamic_morphism_disabled_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{dynamic_morphism_offer},
        .capabilities = &.{morphism_capability},
        .treaty_policy = .{ .allow_dynamic_interpretation = false },
        .policy = dynamic_morphism_policy,
    });
    defer allocator.free(dynamic_morphism_disabled_plan.blockers);
    defer allocator.free(dynamic_morphism_disabled_plan.dependencies);
    try std.testing.expect(!dynamic_morphism_disabled_plan.closed());
    var dynamic_morphism_result = try Program.BoundaryClosure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{dynamic_morphism_offer},
        .capabilities = &.{morphism_capability},
        .policy = dynamic_morphism_policy,
    });
    defer dynamic_morphism_result.deinit();
    try dynamic_morphism_result.assertClosed();
    try std.testing.expectEqual(@as(usize, 2), dynamic_morphism_result.report.host_intrinsic_count);
    var saw_dynamic_morphism_intrinsic = false;
    for (dynamic_morphism_result.report.host_intrinsic_refs) |ref| {
        if (ref.eql(dynamic_morphism_intrinsic_ref)) saw_dynamic_morphism_intrinsic = true;
    }
    try std.testing.expect(saw_dynamic_morphism_intrinsic);
    const source_capability_morphism_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{source_only_morphism_capability},
        .policy = morphism_policy,
    });
    defer allocator.free(source_capability_morphism_plan.blockers);
    defer allocator.free(source_capability_morphism_plan.dependencies);
    try std.testing.expect(!source_capability_morphism_plan.closed());
    try std.testing.expect(source_capability_morphism_plan.selected_morphism_ref == null);
    var label_scoped_target_result = try Program.BoundaryClosure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{label_scoped_target_capability},
        .policy = morphism_policy,
    });
    defer label_scoped_target_result.deinit();
    try std.testing.expect(!label_scoped_target_result.report.closed());
    const choice_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan",
        .plan_hash = 1,
        .kind = .operation,
        .site_index = site_index,
        .site_fingerprint = protocol_op_fingerprint,
        .name = "approve",
        .mode = "choice",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .result_ref = Evidence.BoundaryValueRef.fromValueRef(morphism_target_response_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = protocol_op_fingerprint,
    });
    var return_kind_resume_ref_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "return-kind-resume-ref-offer",
        .provider_fingerprint = morphism_target_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{target_protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{response_ref},
        .allowed_response_kinds = .{ .@"resume" = false, .return_now = true, .resume_after = false },
    });
    defer return_kind_resume_ref_offer.deinit();
    var return_kind_resume_ref_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "return-kind-resume-ref-capability",
        .provider_fingerprint = morphism_target_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{target_protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_kinds = .{ .@"resume" = false, .return_now = true, .resume_after = false },
        .allowed_response_refs = &.{response_ref},
    });
    defer return_kind_resume_ref_capability.deinit();
    const return_kind_resume_ref_intrinsic = return_kind_resume_ref_offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    const return_kind_intrinsics = [_]u64{return_kind_resume_ref_intrinsic.fingerprint};
    var return_kind_morphism_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    return_kind_morphism_policy.allowed_host_intrinsic_fingerprints = return_kind_intrinsics[0..];
    const return_kind_morphism = Program.Exchange.MorphismOffer{
        .label = "return-kind-static-morphism",
        .source_site_fingerprint = protocol_op_fingerprint,
        .source_protocol_op_fingerprint = protocol_op_fingerprint,
        .target_protocol_op_fingerprint = target_protocol_op_fingerprint,
        .pipeline_fingerprint = 0x515153,
    };
    const kind_ref_mismatch_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = choice_shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{return_kind_resume_ref_offer},
        .morphism_offers = &.{return_kind_morphism},
        .capabilities = &.{return_kind_resume_ref_capability},
        .treaty_policy = .{ .allow_direct_handling = false },
        .policy = return_kind_morphism_policy,
    });
    defer allocator.free(kind_ref_mismatch_plan.blockers);
    defer allocator.free(kind_ref_mismatch_plan.dependencies);
    try std.testing.expect(!kind_ref_mismatch_plan.closed());
    try std.testing.expect(kind_ref_mismatch_plan.selected_morphism_ref == null);
    const return_kind_target_morphism = Program.Exchange.MorphismOffer{
        .label = "return-kind-target-static-morphism",
        .source_site_fingerprint = protocol_op_fingerprint,
        .source_protocol_op_fingerprint = protocol_op_fingerprint,
        .target_protocol_op_fingerprint = target_protocol_op_fingerprint,
        .pipeline_fingerprint = 0x515156,
        .source_response_refs = &.{morphism_target_response_ref},
        .target_response_refs = &.{response_ref},
    };
    const return_kind_target_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = choice_shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{return_kind_resume_ref_offer},
        .morphism_offers = &.{return_kind_target_morphism},
        .capabilities = &.{return_kind_resume_ref_capability},
        .treaty_policy = .{ .allow_direct_handling = false },
        .policy = return_kind_morphism_policy,
    });
    defer allocator.free(return_kind_target_plan.blockers);
    defer allocator.free(return_kind_target_plan.dependencies);
    try std.testing.expect(return_kind_target_plan.closed());
    try std.testing.expectEqual(return_kind_target_morphism.evidenceRef().fingerprint, return_kind_target_plan.selected_morphism_ref.?.fingerprint);
    var resume_only_target_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "resume-only-target-offer",
        .provider_fingerprint = morphism_target_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{target_protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{response_ref},
        .allowed_response_kinds = .{ .@"resume" = true, .return_now = false, .resume_after = false },
    });
    defer resume_only_target_offer.deinit();
    var resume_only_target_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "resume-only-target-capability",
        .provider_fingerprint = morphism_target_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{target_protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_kinds = .{ .@"resume" = true, .return_now = false, .resume_after = false },
        .allowed_response_refs = &.{response_ref},
    });
    defer resume_only_target_capability.deinit();
    const resume_only_target_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = choice_shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{resume_only_target_offer},
        .morphism_offers = &.{return_kind_target_morphism},
        .capabilities = &.{resume_only_target_capability},
        .treaty_policy = .{ .allow_direct_handling = false },
        .policy = return_kind_morphism_policy,
    });
    defer allocator.free(resume_only_target_plan.blockers);
    defer allocator.free(resume_only_target_plan.dependencies);
    try std.testing.expect(!resume_only_target_plan.closed());
    try std.testing.expect(resume_only_target_plan.selected_morphism_ref == null);
    const unallowlisted_morphism_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{morphism_capability},
        .policy = Evidence.BoundaryClosurePolicy.worldBoundary(),
    });
    defer allocator.free(unallowlisted_morphism_plan.blockers);
    defer allocator.free(unallowlisted_morphism_plan.dependencies);
    try std.testing.expect(!unallowlisted_morphism_plan.closed());
    try std.testing.expect(unallowlisted_morphism_plan.selected_morphism_ref == null);
    const target_shape_response_refs = [_]Evidence.BoundaryValueRef{Evidence.BoundaryValueRef.fromValueRef(morphism_target_response_ref)};
    const morphism_target_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan",
        .plan_hash = 1,
        .kind = .operation,
        .site_index = site_index,
        .site_fingerprint = protocol_op_fingerprint,
        .name = "approve",
        .mode = "transform",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = target_protocol_op_fingerprint,
        .usage_summary = "copyable",
        .desired_response_refs = target_shape_response_refs[0..],
    });
    const morphism_target_world_port = Program.BoundaryClosure.WorldPort.init(.{
        .label = "approval-morphism-target-world-port",
        .kind = .host_tool,
        .effect_shape_ref = morphism_target_shape.evidenceRef(),
        .exposed_intrinsic_ref = morphism_target_intrinsic_ref,
        .supported_protocol_labels = &.{"approval"},
        .supported_site_indexes = &.{site_index},
        .supported_protocol_op_fingerprints = &.{target_protocol_op_fingerprint},
    });
    var morphism_target_world_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    const morphism_target_world_ports = [_]Program.BoundaryClosure.WorldPort{morphism_target_world_port};
    const allowed_target_ports = [_]u64{morphism_target_world_port.fingerprint};
    morphism_target_world_policy.allowed_world_port_fingerprints = allowed_target_ports[0..];
    const target_world_port_morphism_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{morphism_capability},
        .policy = morphism_target_world_policy,
        .world_ports = morphism_target_world_ports[0..],
    });
    defer allocator.free(target_world_port_morphism_plan.blockers);
    defer allocator.free(target_world_port_morphism_plan.dependencies);
    try std.testing.expect(target_world_port_morphism_plan.closed());
    try std.testing.expectEqual(morphism_offer.evidenceRef().fingerprint, target_world_port_morphism_plan.selected_morphism_ref.?.fingerprint);
    var target_world_port_result = try Program.BoundaryClosure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{morphism_capability},
        .policy = morphism_target_world_policy,
        .world_ports = morphism_target_world_ports[0..],
    });
    defer target_world_port_result.deinit();
    try std.testing.expect(target_world_port_result.report.closedExceptWorldPorts());
    try std.testing.expectEqual(@as(usize, 1), target_world_port_result.report.open_world_port_count);
    try std.testing.expectEqual(morphism_target_world_port.evidenceRef().fingerprint, target_world_port_result.report.world_port_refs[0].fingerprint);
    try target_world_port_result.certificate.check(target_world_port_result.graph, target_world_port_result.report, morphism_target_world_policy);
    const dynamic_mapper_world_port = Program.BoundaryClosure.WorldPort.init(.{
        .label = "approval-dynamic-mapper-world-port",
        .kind = .host_tool,
        .effect_shape_ref = shape.evidenceRef(),
        .exposed_intrinsic_ref = dynamic_morphism_intrinsic_ref,
        .supported_protocol_labels = &.{"approval"},
        .supported_site_indexes = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
    });
    const dynamic_target_world_port = Program.BoundaryClosure.WorldPort.init(.{
        .label = "approval-dynamic-target-world-port",
        .kind = .host_tool,
        .effect_shape_ref = morphism_target_shape.evidenceRef(),
        .exposed_intrinsic_ref = morphism_target_intrinsic_ref,
        .supported_protocol_labels = &.{"approval"},
        .supported_site_indexes = &.{site_index},
        .supported_protocol_op_fingerprints = &.{target_protocol_op_fingerprint},
    });
    const dynamic_world_ports = [_]Program.BoundaryClosure.WorldPort{ dynamic_mapper_world_port, dynamic_target_world_port };
    const dynamic_allowed_ports = [_]u64{ dynamic_mapper_world_port.fingerprint, dynamic_target_world_port.fingerprint };
    var dynamic_multi_port_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    dynamic_multi_port_policy.allowed_world_port_fingerprints = dynamic_allowed_ports[0..];
    var dynamic_multi_port_result = try Program.BoundaryClosure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{dynamic_morphism_offer},
        .capabilities = &.{morphism_capability},
        .policy = dynamic_multi_port_policy,
        .world_ports = dynamic_world_ports[0..],
    });
    defer dynamic_multi_port_result.deinit();
    try std.testing.expect(dynamic_multi_port_result.report.closedExceptWorldPorts());
    try std.testing.expect(!dynamic_multi_port_result.report.closed());
    try std.testing.expectEqual(@as(usize, 1), dynamic_multi_port_result.report.open_world_port_count);
    try std.testing.expectEqual(@as(usize, 2), dynamic_multi_port_result.report.world_port_refs.len);
    try dynamic_multi_port_result.certificate.check(dynamic_multi_port_result.graph, dynamic_multi_port_result.report, dynamic_multi_port_policy);
    const wrong_source_morphism_offer = Program.Exchange.MorphismOffer{
        .label = "approval-wrong-source-response-morphism",
        .source_site_fingerprint = protocol_op_fingerprint,
        .source_protocol_op_fingerprint = protocol_op_fingerprint,
        .target_protocol_op_fingerprint = target_protocol_op_fingerprint,
        .pipeline_fingerprint = 0x515152,
        .source_response_refs = &.{morphism_target_response_ref},
        .target_response_refs = &.{morphism_target_response_ref},
    };
    const wrong_source_morphism_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{wrong_source_morphism_offer},
        .capabilities = &.{morphism_capability},
        .policy = morphism_policy,
    });
    defer allocator.free(wrong_source_morphism_plan.blockers);
    defer allocator.free(wrong_source_morphism_plan.dependencies);
    try std.testing.expect(!wrong_source_morphism_plan.closed());
    try std.testing.expectEqual(@as(usize, 0), wrong_source_morphism_plan.morphism_candidate_count);
    try std.testing.expect(wrong_source_morphism_plan.selected_morphism_ref == null);
    var wrong_payload_morphism_target_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "approval-morphism-wrong-payload-target-offer",
        .provider_fingerprint = morphism_target_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{target_protocol_op_fingerprint},
        .accepted_payload_refs = &.{response_ref},
        .produced_response_refs = &.{morphism_target_response_ref},
    });
    defer wrong_payload_morphism_target_offer.deinit();
    const wrong_payload_target_intrinsic_ref = wrong_payload_morphism_target_offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    const wrong_payload_intrinsics = [_]u64{wrong_payload_target_intrinsic_ref.fingerprint};
    var wrong_payload_morphism_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    wrong_payload_morphism_policy.allowed_host_intrinsic_fingerprints = wrong_payload_intrinsics[0..];
    const wrong_payload_morphism_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{wrong_payload_morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{morphism_capability},
        .policy = wrong_payload_morphism_policy,
    });
    defer allocator.free(wrong_payload_morphism_plan.blockers);
    defer allocator.free(wrong_payload_morphism_plan.dependencies);
    try std.testing.expect(!wrong_payload_morphism_plan.closed());
    try std.testing.expect(wrong_payload_morphism_plan.selected_morphism_ref == null);
    var label_only_morphism_target_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "approval-morphism-label-only-target-offer",
        .provider_fingerprint = morphism_target_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{morphism_target_response_ref},
    });
    defer label_only_morphism_target_offer.deinit();
    const label_only_offer_static_morphism_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{label_only_morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{morphism_capability},
    });
    try std.testing.expect(label_only_offer_static_morphism_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);
    const label_only_offer_morphism_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{label_only_morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{morphism_capability},
        .policy = morphism_policy,
    });
    defer allocator.free(label_only_offer_morphism_plan.blockers);
    defer allocator.free(label_only_offer_morphism_plan.dependencies);
    try std.testing.expect(!label_only_offer_morphism_plan.closed());
    var label_only_morphism_target_provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "approval-morphism-label-only-target-provider",
        .provider_fingerprint = morphism_target_provider.provider_fingerprint,
        .supported_program_manifest_fingerprints = &.{manifest.fingerprint},
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
    });
    defer label_only_morphism_target_provider.deinit();
    const label_only_provider_static_morphism_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{label_only_morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{morphism_capability},
    });
    try std.testing.expect(label_only_provider_static_morphism_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);
    const label_only_provider_morphism_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{label_only_morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{morphism_capability},
        .policy = morphism_policy,
    });
    defer allocator.free(label_only_provider_morphism_plan.blockers);
    defer allocator.free(label_only_provider_morphism_plan.dependencies);
    try std.testing.expect(!label_only_provider_morphism_plan.closed());
    var alternate_label_morphism_target_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "approval-morphism-alternate-label-target-offer",
        .provider_fingerprint = morphism_target_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"other"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{target_protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{morphism_target_response_ref},
    });
    defer alternate_label_morphism_target_offer.deinit();
    const alternate_label_static_morphism_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{alternate_label_morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{morphism_capability},
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.static_treaty, alternate_label_static_morphism_plan.status);
    var stale_morphism_target_provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "stale-approval-morphism-target-provider",
        .provider_fingerprint = morphism_target_provider.provider_fingerprint,
        .supported_program_manifest_fingerprints = &.{manifest.fingerprint},
        .supported_protocol_labels = &.{"other"},
        .supported_operation_sites = &.{site_index + 1},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
    });
    defer stale_morphism_target_provider.deinit();
    var forged_morphism_target_provider = stale_morphism_target_provider;
    forged_morphism_target_provider.supported_protocol_labels = &.{"approval"};
    forged_morphism_target_provider.supported_operation_sites = &.{site_index};
    forged_morphism_target_provider.supported_protocol_op_fingerprints = &.{target_protocol_op_fingerprint};
    const forged_provider_static_morphism_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{forged_morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{morphism_capability},
    });
    try std.testing.expect(forged_provider_static_morphism_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);
    var copyable_only_morphism_target_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "approval-morphism-copyable-only-target-offer",
        .provider_fingerprint = morphism_target_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{target_protocol_op_fingerprint},
        .supported_usage_modes = .{ .linear = false },
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{morphism_target_response_ref},
    });
    defer copyable_only_morphism_target_offer.deinit();
    const linear_target_morphism = Program.Exchange.MorphismOffer{
        .label = "approval-linear-target-morphism",
        .source_site_fingerprint = protocol_op_fingerprint,
        .source_protocol_op_fingerprint = protocol_op_fingerprint,
        .target_protocol_op_fingerprint = target_protocol_op_fingerprint,
        .pipeline_fingerprint = 0x515154,
        .target_usage = .linear,
        .source_response_refs = &.{response_ref},
        .target_response_refs = &.{morphism_target_response_ref},
    };
    const unsupported_usage_static_morphism_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{copyable_only_morphism_target_offer},
        .morphism_offers = &.{linear_target_morphism},
        .capabilities = &.{morphism_capability},
    });
    try std.testing.expect(unsupported_usage_static_morphism_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);
    const copyable_only_intrinsic_ref = copyable_only_morphism_target_offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    const copyable_only_intrinsics = [_]u64{copyable_only_intrinsic_ref.fingerprint};
    var copyable_only_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    copyable_only_policy.allowed_host_intrinsic_fingerprints = copyable_only_intrinsics[0..];
    const unsupported_usage_morphism_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{copyable_only_morphism_target_offer},
        .morphism_offers = &.{linear_target_morphism},
        .capabilities = &.{morphism_capability},
        .policy = copyable_only_policy,
    });
    defer allocator.free(unsupported_usage_morphism_plan.blockers);
    defer allocator.free(unsupported_usage_morphism_plan.dependencies);
    try std.testing.expect(!unsupported_usage_morphism_plan.closed());
    try std.testing.expect(unsupported_usage_morphism_plan.selected_morphism_ref == null);
    var target_op_scoped_morphism_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "target-op-scoped-morphism-capability",
        .provider_fingerprint = morphism_target_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{target_protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"other"},
        .allowed_op_names = &.{"other"},
        .allowed_response_refs = &.{morphism_target_response_ref},
    });
    defer target_op_scoped_morphism_capability.deinit();
    const target_op_scoped_static_morphism_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{target_op_scoped_morphism_capability},
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.static_treaty, target_op_scoped_static_morphism_plan.status);
    const morphism_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{morphism_capability},
        .policy = morphism_policy,
    });
    defer allocator.free(morphism_plan.blockers);
    defer allocator.free(morphism_plan.dependencies);
    try std.testing.expect(morphism_plan.closed());
    try std.testing.expectEqual(@as(usize, 0), morphism_plan.direct_candidate_count);
    try std.testing.expectEqual(@as(usize, 1), morphism_plan.morphism_candidate_count);
    try std.testing.expectEqual(morphism_offer.evidenceRef().fingerprint, morphism_plan.selected_morphism_ref.?.fingerprint);

    var cross_protocol_provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "policy-morphism-target-provider",
        .supported_program_manifest_fingerprints = &.{manifest.fingerprint},
        .supported_protocol_labels = &.{"policy"},
        .supported_protocol_op_fingerprints = &.{target_protocol_op_fingerprint},
    });
    defer cross_protocol_provider.deinit();
    var cross_protocol_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "policy-morphism-target-offer",
        .provider_fingerprint = cross_protocol_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"policy"},
        .supported_protocol_op_fingerprints = &.{target_protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{morphism_target_response_ref},
    });
    defer cross_protocol_offer.deinit();
    const cross_protocol_intrinsic_ref = cross_protocol_offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    const cross_protocol_intrinsics = [_]u64{cross_protocol_intrinsic_ref.fingerprint};
    var cross_protocol_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    cross_protocol_policy.allowed_host_intrinsic_fingerprints = cross_protocol_intrinsics[0..];
    var cross_protocol_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "policy-morphism-capability",
        .provider_fingerprint = cross_protocol_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_protocol_op_fingerprints = &.{target_protocol_op_fingerprint},
        .allowed_response_refs = &.{morphism_target_response_ref},
    });
    defer cross_protocol_capability.deinit();
    const cross_protocol_morphism_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{cross_protocol_provider},
        .provider_offers = &.{cross_protocol_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{cross_protocol_capability},
        .policy = cross_protocol_policy,
    });
    defer allocator.free(cross_protocol_morphism_plan.blockers);
    defer allocator.free(cross_protocol_morphism_plan.dependencies);
    try std.testing.expect(cross_protocol_morphism_plan.closed());
    try std.testing.expectEqual(morphism_offer.evidenceRef().fingerprint, cross_protocol_morphism_plan.selected_morphism_ref.?.fingerprint);

    const target_op_scoped_morphism_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{target_op_scoped_morphism_capability},
        .policy = morphism_policy,
    });
    defer allocator.free(target_op_scoped_morphism_plan.blockers);
    defer allocator.free(target_op_scoped_morphism_plan.dependencies);
    try std.testing.expect(target_op_scoped_morphism_plan.closed());

    const residualization_disabled_morphism_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{morphism_capability},
        .treaty_policy = .{ .allow_residualization = false },
        .policy = morphism_policy,
    });
    defer allocator.free(residualization_disabled_morphism_plan.blockers);
    defer allocator.free(residualization_disabled_morphism_plan.dependencies);
    try std.testing.expect(!residualization_disabled_morphism_plan.closed());
    try std.testing.expect(residualization_disabled_morphism_plan.selected_morphism_ref == null);

    const static_source_capability_morphism_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{source_only_morphism_capability},
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.no_static_treaty, static_source_capability_morphism_plan.status);
    const blocked_static_report = static_source_capability_morphism_plan.toEvidenceReport(&.{});
    try std.testing.expect(!blocked_static_report.success);
    const static_morphism_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{morphism_capability},
    });
    try std.testing.expectEqual(Program.Exchange.TreatyResolver.StaticStatus.static_treaty, static_morphism_plan.status);
    try std.testing.expectEqual(morphism_offer.evidenceRef().fingerprint, static_morphism_plan.morphism_offer_ref.?.fingerprint);
    const static_tag_required_morphism_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{morphism_capability},
        .treaty_policy = .{ .required_provider_tags = &.{"trusted"} },
    });
    try std.testing.expect(static_tag_required_morphism_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);
    const static_residualization_disabled_morphism_plan = Program.Exchange.TreatyResolver.planStatic(.{
        .shape = shape,
        .manifest = manifest,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{morphism_capability},
        .treaty_policy = .{ .allow_residualization = false },
    });
    try std.testing.expect(static_residualization_disabled_morphism_plan.status != Program.Exchange.TreatyResolver.StaticStatus.static_treaty);

    var zero_hop_policy = morphism_policy;
    zero_hop_policy.max_morphism_hops = 0;
    const zero_hop_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{morphism_capability},
        .policy = zero_hop_policy,
    });
    defer allocator.free(zero_hop_plan.blockers);
    defer allocator.free(zero_hop_plan.dependencies);
    try std.testing.expect(!zero_hop_plan.closed());
    try std.testing.expectEqual(@as(usize, 0), zero_hop_plan.morphism_candidate_count);
    try std.testing.expect(zero_hop_plan.selected_morphism_ref == null);

    const zero_treaty_hop_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{morphism_target_provider},
        .provider_offers = &.{morphism_target_offer},
        .morphism_offers = &.{morphism_offer},
        .capabilities = &.{morphism_capability},
        .treaty_policy = .{ .max_morphism_hops = 0 },
        .policy = morphism_policy,
    });
    defer allocator.free(zero_treaty_hop_plan.blockers);
    defer allocator.free(zero_treaty_hop_plan.dependencies);
    try std.testing.expect(!zero_treaty_hop_plan.closed());
    try std.testing.expectEqual(@as(usize, 0), zero_treaty_hop_plan.morphism_candidate_count);
    try std.testing.expect(zero_treaty_hop_plan.selected_morphism_ref == null);

    const strict_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = Evidence.BoundaryClosurePolicy.strict(),
    });
    defer allocator.free(strict_plan.blockers);
    defer allocator.free(strict_plan.dependencies);
    try std.testing.expect(!strict_plan.closed());
    try std.testing.expect(strict_plan.blockers.len != 0);

    var second_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "approval-offer-2",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{response_ref},
    });
    defer second_offer.deinit();
    const second_offer_intrinsic_ref = second_offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    var ambiguity_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    ambiguity_policy.prefer_boundary_native = false;
    const ambiguous_allowed_intrinsics = [_]u64{ offer_intrinsic_ref.fingerprint, second_offer_intrinsic_ref.fingerprint };
    ambiguity_policy.allowed_host_intrinsic_fingerprints = ambiguous_allowed_intrinsics[0..];
    const ambiguous_plan = try Program.Exchange.TreatyResolver.planShape(.{
        .allocator = allocator,
        .shape = shape,
        .provider_manifests = &.{provider},
        .provider_offers = &.{ offer, second_offer },
        .capabilities = &.{capability},
        .policy = ambiguity_policy,
    });
    defer allocator.free(ambiguous_plan.blockers);
    defer allocator.free(ambiguous_plan.dependencies);
    try std.testing.expect(!ambiguous_plan.closed());
    try std.testing.expectEqual(Evidence.BoundaryClosureBlockerTag.ambiguous_static_treaty_plan, ambiguous_plan.blockers[0].tag);
}

test "boundary closure optional static treaty plans do not block closure" {
    const allocator = std.testing.allocator;
    var manifest = try Program.Exchange.Manifest.encode(allocator);
    defer manifest.deinit();

    const payload_ref = boundary.ir.ValueRef{ .codec = .unit };
    const response_ref = boundary.ir.ValueRef{ .codec = .bool };
    const site_index: usize = 5;
    const protocol_op_fingerprint: u64 = 0xACE;
    const shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "optional-static-test",
        .plan_label = "optional-static-test-plan",
        .plan_hash = 0xABCD,
        .manifest_fingerprint = manifest.fingerprint,
        .kind = .operation,
        .site_index = site_index,
        .site_fingerprint = protocol_op_fingerprint,
        .name = "approve",
        .mode = "transform",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = protocol_op_fingerprint,
    });
    const Closure = Evidence.BoundaryClosure(Program);

    var strict_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
    });
    defer strict_result.deinit();
    try std.testing.expect(!strict_result.report.closed());
    try std.testing.expectEqual(@as(usize, 1), strict_result.report.effect_shape_count);
    try std.testing.expectEqual(@as(usize, 0), strict_result.report.closed_effect_shape_count);
    try std.testing.expectEqual(@as(usize, 1), strict_result.report.blocker_count);
    try std.testing.expectEqual(
        error.BoundaryClosureNotClosed,
        strict_result.certificate.check(strict_result.graph, strict_result.report, Evidence.BoundaryClosurePolicy.strictStatic()),
    );
    var saw_no_provider = false;
    for (strict_result.report.blockers) |blocker| {
        if (std.mem.eql(u8, blocker.tag, "no_provider_offer_for_shape")) saw_no_provider = true;
    }
    try std.testing.expect(saw_no_provider);

    const shape_only_port = Closure.WorldPort.init(.{
        .label = "shape-only-world-port",
        .kind = .host_tool,
        .effect_shape_ref = shape.evidenceRef(),
        .supported_protocol_labels = &.{"approval"},
        .supported_site_indexes = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .contract_summary = "world owns this open approval effect",
    });
    const shape_only_ports = [_]Closure.WorldPort{shape_only_port};
    var shape_only_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    const allowed_shape_only_ports = [_]u64{shape_only_port.fingerprint};
    shape_only_policy.allowed_world_port_fingerprints = allowed_shape_only_ports[0..];
    var shape_only_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .policy = shape_only_policy,
        .world_ports = shape_only_ports[0..],
    });
    defer shape_only_result.deinit();
    try shape_only_result.assertClosedExceptWorldPorts();
    try std.testing.expectEqual(@as(usize, 1), shape_only_result.report.effect_shape_count);
    try std.testing.expectEqual(@as(usize, 0), shape_only_result.report.closed_effect_shape_count);
    try std.testing.expectEqual(@as(usize, 1), shape_only_result.report.open_world_port_count);
    try std.testing.expectEqual(@as(usize, 0), shape_only_result.report.blocker_count);
    try std.testing.expectEqual(Evidence.domains.boundary_effect_shape.id, shape_only_result.report.world_port_intrinsic_refs[0].domain_id);
    try std.testing.expect(shape_only_result.report.world_port_intrinsic_refs[0].eql(shape.evidenceRef()));
    try shape_only_result.certificate.check(shape_only_result.graph, shape_only_result.report, shape_only_policy);

    var optional_policy = Evidence.BoundaryClosurePolicy.strictStatic();
    optional_policy.label = "optional_static";
    optional_policy.require_static_treaty_plans = false;
    var optional_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .policy = optional_policy,
    });
    defer optional_result.deinit();
    try optional_result.assertClosed();
    try std.testing.expectEqual(@as(usize, 1), optional_result.report.effect_shape_count);
    try std.testing.expectEqual(@as(usize, 1), optional_result.report.closed_effect_shape_count);
    try std.testing.expectEqual(@as(usize, 0), optional_result.report.blocker_count);
    try std.testing.expectEqual(@as(usize, 0), optional_result.report.unknown_body_count);
    try std.testing.expectEqual(@as(usize, 1), optional_result.static_treaty_plans.len);
    try std.testing.expect(optional_result.static_treaty_plans[0].selected_provider_offer_ref == null);
    try optional_result.certificate.check(optional_result.graph, optional_result.report, optional_policy);
}

test "boundary closure traversal closes a provider-backed shape" {
    const allocator = std.testing.allocator;
    var manifest = try Program.Exchange.Manifest.encode(allocator);
    defer manifest.deinit();

    const payload_ref = boundary.ir.ValueRef{ .codec = .unit };
    const response_ref = boundary.ir.ValueRef{ .codec = .bool };
    const site_index: usize = 6;
    const protocol_op_fingerprint: u64 = 0xBEEF;

    var provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "closure-provider",
        .supported_program_manifest_fingerprints = &.{manifest.fingerprint},
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
    });
    defer provider.deinit();
    var offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "closure-offer",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{response_ref},
    });
    defer offer.deinit();
    const offer_intrinsic_ref = offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    const allowed_intrinsics = [_]u64{offer_intrinsic_ref.fingerprint};
    var closure_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    closure_policy.allowed_host_intrinsic_fingerprints = allowed_intrinsics[0..];
    var capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "host",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_refs = &.{response_ref},
    });
    defer capability.deinit();

    const shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan",
        .plan_hash = 1,
        .manifest_fingerprint = manifest.fingerprint,
        .kind = .operation,
        .site_index = site_index,
        .site_fingerprint = protocol_op_fingerprint,
        .name = "approve",
        .mode = "transform",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = protocol_op_fingerprint,
    });
    const Closure = Evidence.BoundaryClosure(Program);
    var result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = closure_policy,
    });
    defer result.deinit();

    try result.assertClosed();
    try std.testing.expectEqual(@as(usize, 1), result.report.effect_shape_count);
    try std.testing.expectEqual(@as(usize, 1), result.report.closed_effect_shape_count);
    try std.testing.expectEqual(@as(usize, 1), result.static_treaty_plans.len);
    try std.testing.expectEqual(offer.evidenceRef().fingerprint, result.static_treaty_plans[0].selected_provider_offer_ref.?.fingerprint);
    try result.certificate.check(result.graph, result.report, closure_policy);
    try std.testing.expect(Evidence.refForBoundaryClosureCertificate(result.certificate).eql(result.certificate.evidenceRef()));

    const treaty_only_intrinsics = [_]u64{offer_intrinsic_ref.fingerprint +% 1};
    var treaty_allowlist_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = closure_policy,
        .treaty_policy = .{ .allowed_intrinsic_fingerprints = treaty_only_intrinsics[0..] },
    });
    defer treaty_allowlist_result.deinit();
    try std.testing.expect(!treaty_allowlist_result.report.closed());
    var saw_treaty_unallow = false;
    for (treaty_allowlist_result.report.blockers) |blocker| {
        if (std.mem.eql(u8, blocker.tag, "unallowlisted_intrinsic")) saw_treaty_unallow = true;
    }
    try std.testing.expect(saw_treaty_unallow);
    var saw_treaty_blocker_edge = false;
    for (treaty_allowlist_result.graph.edges) |edge| {
        if (edge.kind == .blocked_by and edge.from.eql(shape.evidenceRef())) saw_treaty_blocker_edge = true;
    }
    try std.testing.expect(saw_treaty_blocker_edge);
    var explicit_defunc_treaty_allowlist_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = closure_policy,
        .treaty_policy = .{
            .allowed_intrinsic_fingerprints = treaty_only_intrinsics[0..],
            .defunctionalization_policy = .{
                .allowed_intrinsic_fingerprints = &.{offer_intrinsic_ref.fingerprint},
            },
        },
    });
    defer explicit_defunc_treaty_allowlist_result.deinit();
    try std.testing.expect(!explicit_defunc_treaty_allowlist_result.report.closed());

    var after_only_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "after-only-closure-offer",
        .provider_fingerprint = provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_after_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .accepted_current_value_refs = &.{payload_ref},
        .produced_response_refs = &.{response_ref},
    });
    defer after_only_offer.deinit();
    const after_only_intrinsic_ref = after_only_offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    const after_only_allowed_intrinsics = [_]u64{after_only_intrinsic_ref.fingerprint};
    var after_only_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    after_only_policy.allowed_host_intrinsic_fingerprints = after_only_allowed_intrinsics[0..];
    var after_only_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_manifests = &.{provider},
        .provider_offers = &.{after_only_offer},
        .capabilities = &.{capability},
        .policy = after_only_policy,
    });
    defer after_only_result.deinit();
    try std.testing.expect(!after_only_result.report.closed());
    try std.testing.expectEqual(@as(usize, 0), after_only_result.report.closed_effect_shape_count);
    try std.testing.expect(after_only_result.static_treaty_plans[0].selected_provider_offer_ref == null);

    var root_ref_inputs = [_]Evidence.Ref{Evidence.refFor(Evidence.domains.program_plan, shape.plan_hash, .{ .label = shape.program_label })};
    var provider_harness_ref_inputs = [_]Evidence.Ref{provider.evidenceRef()};
    const original_root_ref = root_ref_inputs[0];
    const original_provider_harness_ref = provider_harness_ref_inputs[0];
    var owned_ref_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .root_program_refs = root_ref_inputs[0..],
        .provider_harness_refs = provider_harness_ref_inputs[0..],
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = closure_policy,
    });
    defer owned_ref_result.deinit();
    root_ref_inputs[0] = Evidence.refFor(Evidence.domains.program_plan, 0xBADBEEF, .{ .label = "mutated-root-program" });
    provider_harness_ref_inputs[0] = Evidence.refFor(Evidence.domains.provider_identity, 0xBADCAFE, .{ .label = "mutated-provider-harness" });
    try std.testing.expect(owned_ref_result.report.root_program_refs[0].eql(original_root_ref));
    try std.testing.expect(owned_ref_result.report.provider_harness_refs[0].eql(original_provider_harness_ref));
    try std.testing.expect(owned_ref_result.certificate.root_refs[0].eql(original_root_ref));
    try std.testing.expect(owned_ref_result.certificate.provider_refs[0].eql(original_provider_harness_ref));
    var saw_root_yields_edge = false;
    for (owned_ref_result.graph.edges) |edge| {
        if (edge.kind == .root_yields and edge.from.eql(original_root_ref) and edge.to.eql(shape.evidenceRef())) {
            saw_root_yields_edge = true;
        }
    }
    try std.testing.expect(saw_root_yields_edge);
    try owned_ref_result.certificate.check(owned_ref_result.graph, owned_ref_result.report, closure_policy);

    const effect_free_root_ref = Evidence.refFor(Evidence.domains.program_plan, 0xEFFEC7F2EE, .{ .label = "effect-free-root" });
    var missing_root_shape_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_program_refs = &.{effect_free_root_ref},
        .policy = closure_policy,
    });
    defer missing_root_shape_result.deinit();
    try std.testing.expectEqual(@as(usize, 1), missing_root_shape_result.report.blocker_count);
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        missing_root_shape_result.certificate.check(missing_root_shape_result.graph, missing_root_shape_result.report, closure_policy),
    );

    const unrooted_effect_free_ref = Evidence.refFor(Evidence.domains.program_plan, 0xEFFEC7F2EF, .{ .label = "unrooted-effect-free-root" });
    var unrooted_effect_free_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_program_refs = &.{effect_free_root_ref},
        .effect_free_root_refs = &.{unrooted_effect_free_ref},
        .policy = closure_policy,
    });
    defer unrooted_effect_free_result.deinit();
    try std.testing.expectEqual(@as(usize, 2), unrooted_effect_free_result.report.blocker_count);
    try std.testing.expect(!unrooted_effect_free_result.report.closed());

    var effect_free_root_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_program_refs = &.{effect_free_root_ref},
        .effect_free_root_refs = &.{effect_free_root_ref},
        .policy = closure_policy,
    });
    defer effect_free_root_result.deinit();
    try effect_free_root_result.assertClosed();
    try std.testing.expectEqual(@as(usize, 0), effect_free_root_result.report.effect_shape_count);
    try std.testing.expectEqual(@as(usize, 0), effect_free_root_result.report.blocker_count);
    try std.testing.expectEqual(@as(usize, 1), effect_free_root_result.report.effect_free_root_refs.len);
    try effect_free_root_result.certificate.check(effect_free_root_result.graph, effect_free_root_result.report, closure_policy);

    const unwitnessed_root_ref = Evidence.refFor(Evidence.domains.program_plan, 0xEFFEC7BAD, .{ .label = "unwitnessed-root" });
    var partial_root_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_program_refs = &.{ effect_free_root_ref, unwitnessed_root_ref },
        .effect_free_root_refs = &.{effect_free_root_ref},
        .policy = closure_policy,
    });
    defer partial_root_result.deinit();
    try std.testing.expectEqual(@as(usize, 1), partial_root_result.report.blocker_count);
    try std.testing.expect(!partial_root_result.report.closed());

    const unmatched_root_refs = [_]Evidence.Ref{
        Evidence.refFor(Evidence.domains.program_plan, 0x123400, .{ .label = "other-root-a" }),
        Evidence.refFor(Evidence.domains.program_plan, 0x123401, .{ .label = "other-root-b" }),
    };
    var unmatched_root_shape_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .root_program_refs = unmatched_root_refs[0..],
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = closure_policy,
    });
    defer unmatched_root_shape_result.deinit();
    try std.testing.expectEqual(@as(usize, 3), unmatched_root_shape_result.report.blocker_count);
    try std.testing.expect(!unmatched_root_shape_result.report.closed());

    const unmatched_single_root_ref = Evidence.refFor(Evidence.domains.program_plan, 0x123402, .{ .label = "other-root-single" });
    var unmatched_single_root_shape_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .root_program_refs = &.{unmatched_single_root_ref},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = closure_policy,
    });
    defer unmatched_single_root_shape_result.deinit();
    try std.testing.expectEqual(@as(usize, 2), unmatched_single_root_shape_result.report.blocker_count);
    try std.testing.expect(!unmatched_single_root_shape_result.report.closed());

    const foreign_manifest_fingerprint = manifest.fingerprint +% 1;
    var foreign_provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "foreign-closure-provider",
        .supported_program_manifest_fingerprints = &.{foreign_manifest_fingerprint},
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
    });
    defer foreign_provider.deinit();
    var foreign_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "foreign-closure-offer",
        .provider_fingerprint = foreign_provider.provider_fingerprint,
        .manifest_fingerprint = foreign_manifest_fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{response_ref},
    });
    defer foreign_offer.deinit();
    const foreign_intrinsic_ref = foreign_offer.hostIntrinsicRef() orelse return error.ExpectedIntrinsic;
    const allowed_foreign_intrinsics = [_]u64{foreign_intrinsic_ref.fingerprint};
    var foreign_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    foreign_policy.allowed_host_intrinsic_fingerprints = allowed_foreign_intrinsics[0..];
    var foreign_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "foreign-host",
        .provider_fingerprint = foreign_provider.provider_fingerprint,
        .manifest_fingerprint = foreign_manifest_fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_refs = &.{response_ref},
    });
    defer foreign_capability.deinit();
    var foreign_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_manifests = &.{foreign_provider},
        .provider_offers = &.{foreign_offer},
        .capabilities = &.{foreign_capability},
        .policy = foreign_policy,
    });
    defer foreign_result.deinit();
    try std.testing.expect(!foreign_result.report.closed());
    try std.testing.expectEqual(@as(usize, 0), foreign_result.report.closed_effect_shape_count);

    const world_port = Closure.WorldPort.init(.{
        .label = "approval-world-port",
        .kind = .host_tool,
        .effect_shape_ref = shape.evidenceRef(),
        .exposed_intrinsic_ref = offer_intrinsic_ref,
        .supported_protocol_labels = &.{"approval"},
        .supported_site_indexes = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
    });
    const world_ports = [_]Closure.WorldPort{world_port};
    var world_port_only_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    const world_port_only_allowed = [_]u64{world_port.fingerprint};
    world_port_only_policy.allowed_world_port_fingerprints = world_port_only_allowed[0..];
    world_port_only_policy.reject_host_intrinsics = true;
    var world_port_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = world_port_only_policy,
        .world_ports = world_ports[0..],
    });
    defer world_port_result.deinit();
    try world_port_result.assertClosedExceptWorldPorts();
    try std.testing.expect(!world_port_result.report.closed());
    try std.testing.expectEqual(@as(usize, 1), world_port_result.report.open_world_port_count);
    try world_port_result.certificate.check(world_port_result.graph, world_port_result.report, world_port_only_policy);

    const second_shape = Evidence.BoundaryEffectShape.init(.{
        .program_label = "evidence-test",
        .plan_label = "evidence-test-plan-2",
        .plan_hash = 2,
        .manifest_fingerprint = manifest.fingerprint,
        .kind = .operation,
        .site_index = site_index,
        .site_fingerprint = protocol_op_fingerprint,
        .name = "approve",
        .mode = "transform",
        .value_ref = Evidence.BoundaryValueRef.fromValueRef(payload_ref),
        .expected_resume_ref = Evidence.BoundaryValueRef.fromValueRef(response_ref),
        .protocol_label = "approval",
        .protocol_op_fingerprint = protocol_op_fingerprint,
    });
    var mixed_world_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    mixed_world_policy.allowed_world_port_fingerprints = world_port_only_allowed[0..];
    mixed_world_policy.allowed_host_intrinsic_fingerprints = allowed_intrinsics[0..];
    var mixed_world_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{ shape, second_shape },
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = mixed_world_policy,
        .world_ports = world_ports[0..],
    });
    defer mixed_world_result.deinit();
    try mixed_world_result.assertClosedExceptWorldPorts();
    try std.testing.expectEqual(@as(usize, 2), mixed_world_result.report.effect_shape_count);
    try std.testing.expectEqual(@as(usize, 1), mixed_world_result.report.closed_effect_shape_count);
    try std.testing.expectEqual(@as(usize, 1), mixed_world_result.report.open_world_port_count);
    try mixed_world_result.certificate.check(mixed_world_result.graph, mixed_world_result.report, mixed_world_policy);

    var overcounted_world_report = world_port_result.report;
    overcounted_world_report.closed_effect_shape_count = 2;
    overcounted_world_report.report_fingerprint = overcounted_world_report.computeFingerprint();
    const overcounted_world_cert = Evidence.BoundaryClosureCertificate.init(
        overcounted_world_report,
        world_port_result.graph,
        world_port_only_policy,
        world_port_result.plan_refs,
    );
    try std.testing.expectError(
        error.BoundaryClosureNotClosed,
        overcounted_world_cert.check(world_port_result.graph, overcounted_world_report, world_port_only_policy),
    );
    var disallowed_world_policy = world_port_only_policy;
    const disallowed_world_ports = [_]u64{world_port.fingerprint +% 1};
    disallowed_world_policy.allowed_world_port_fingerprints = disallowed_world_ports[0..];
    var disallowed_world_report = world_port_result.report;
    disallowed_world_report.policy_summary = disallowed_world_policy.policySummary();
    disallowed_world_report.report_fingerprint = disallowed_world_report.computeFingerprint();
    const disallowed_world_certificate = Evidence.BoundaryClosureCertificate.init(
        disallowed_world_report,
        world_port_result.graph,
        disallowed_world_policy,
        world_port_result.plan_refs,
    );
    try std.testing.expectError(
        error.BoundaryClosureWorldPortsRejected,
        disallowed_world_certificate.check(world_port_result.graph, disallowed_world_report, disallowed_world_policy),
    );
    const unallowlisted_world_policy = Evidence.BoundaryClosurePolicy.worldBoundary();
    var unallowlisted_world_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = unallowlisted_world_policy,
        .world_ports = world_ports[0..],
    });
    defer unallowlisted_world_result.deinit();
    try std.testing.expect(!unallowlisted_world_result.report.closedExceptWorldPorts());
    try std.testing.expectEqual(@as(usize, 0), unallowlisted_world_result.report.open_world_port_count);

    var impostor_provider = try Program.Exchange.ProviderManifest.encode(allocator, .{
        .label = "impostor-closure-provider",
        .supported_program_manifest_fingerprints = &.{manifest.fingerprint},
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
    });
    defer impostor_provider.deinit();
    var impostor_offer = try Program.Exchange.ProviderOffer.encode(allocator, .{
        .label = "impostor-closure-offer",
        .provider_fingerprint = impostor_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .supported_protocol_labels = &.{"approval"},
        .supported_operation_sites = &.{site_index},
        .supported_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .accepted_payload_refs = &.{payload_ref},
        .produced_response_refs = &.{response_ref},
    });
    defer impostor_offer.deinit();
    var impostor_capability = try Program.Exchange.Capability.encode(allocator, .{
        .issuer_label = "impostor-host",
        .provider_fingerprint = impostor_provider.provider_fingerprint,
        .manifest_fingerprint = manifest.fingerprint,
        .allowed_operation_sites = &.{site_index},
        .allowed_protocol_op_fingerprints = &.{protocol_op_fingerprint},
        .allowed_requirement_labels = &.{"approval"},
        .allowed_op_names = &.{"approve"},
        .allowed_response_refs = &.{response_ref},
    });
    defer impostor_capability.deinit();
    var impostor_world_port_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_manifests = &.{impostor_provider},
        .provider_offers = &.{impostor_offer},
        .capabilities = &.{impostor_capability},
        .policy = world_port_only_policy,
        .world_ports = world_ports[0..],
    });
    defer impostor_world_port_result.deinit();
    try std.testing.expect(!impostor_world_port_result.report.closedExceptWorldPorts());
    try std.testing.expectEqual(@as(usize, 0), impostor_world_port_result.report.open_world_port_count);

    const report_view = result.report.toEvidenceReport();
    try std.testing.expect(report_view.success);
    try std.testing.expectEqual(Evidence.domains.boundary_closure_report.id, report_view.report_domain);

    var summary_buffer: [192]u8 = undefined;
    var summary_stream = std.Io.Writer.fixed(&summary_buffer);
    try result.writeSummary(&summary_stream);
    const summary = summary_stream.buffered();
    try std.testing.expect(std.mem.find(u8, summary, "closure=closed") != null);
    try std.testing.expect(std.mem.find(u8, summary, "certificate=") != null);

    var same_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = closure_policy,
    });
    defer same_result.deinit();
    try std.testing.expectEqual(result.graph.fingerprint, same_result.graph.fingerprint);
    try std.testing.expectEqual(result.report.report_fingerprint, same_result.report.report_fingerprint);
    try std.testing.expectEqual(result.certificate.certificate_fingerprint, same_result.certificate.certificate_fingerprint);
    var stale_graph = result.graph;
    stale_graph.label = "stale-graph";
    try std.testing.expectError(
        error.BoundaryClosureGraphMismatch,
        result.certificate.check(stale_graph, result.report, closure_policy),
    );
    var stale_report = result.report;
    stale_report.closed_effect_shape_count = 0;
    try std.testing.expectError(
        error.BoundaryClosureReportMismatch,
        result.certificate.check(result.graph, stale_report, closure_policy),
    );
    try std.testing.expectError(
        error.BoundaryClosurePolicyMismatch,
        result.certificate.check(result.graph, result.report, Evidence.BoundaryClosurePolicy.strict()),
    );
    var stale_policy_report = result.report;
    stale_policy_report.policy_summary = Evidence.BoundaryClosurePolicy.strict().policySummary();
    stale_policy_report.report_fingerprint = stale_policy_report.computeFingerprint();
    const stale_policy_certificate = Evidence.BoundaryClosureCertificate.init(
        stale_policy_report,
        result.graph,
        closure_policy,
        result.plan_refs,
    );
    try std.testing.expectError(
        error.BoundaryClosurePolicyMismatch,
        stale_policy_certificate.check(result.graph, stale_policy_report, closure_policy),
    );
    var missing_plan_ref_certificate = result.certificate;
    missing_plan_ref_certificate.selected_static_treaty_plan_refs = &.{};
    missing_plan_ref_certificate.certificate_fingerprint = missing_plan_ref_certificate.computeFingerprint();
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        missing_plan_ref_certificate.check(result.graph, result.report, closure_policy),
    );
    var forged_plan_ref_certificate = result.certificate;
    forged_plan_ref_certificate.selected_static_treaty_plan_refs = &.{Evidence.refFor(Evidence.domains.boundary_static_treaty_plan, 0xDEADBEEF, .{ .label = "forged-plan" })};
    forged_plan_ref_certificate.certificate_fingerprint = forged_plan_ref_certificate.computeFingerprint();
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        forged_plan_ref_certificate.check(result.graph, result.report, closure_policy),
    );
    const forged_plan_edges = try allocator.dupe(Closure.Graph.Edge, result.graph.edges);
    defer allocator.free(forged_plan_edges);
    for (forged_plan_edges) |*edge| {
        if (edge.kind == .treaty_planned) {
            edge.from = offer.evidenceRef();
            break;
        }
    }
    const forged_plan_edge_graph = Closure.Graph.init(result.graph.label, result.graph.nodes, forged_plan_edges, result.graph.dependencies);
    var forged_plan_edge_report = result.report;
    forged_plan_edge_report.graph_fingerprint = forged_plan_edge_graph.fingerprint;
    forged_plan_edge_report.report_fingerprint = forged_plan_edge_report.computeFingerprint();
    const forged_plan_edge_certificate = Evidence.BoundaryClosureCertificate.init(
        forged_plan_edge_report,
        forged_plan_edge_graph,
        closure_policy,
        result.plan_refs,
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        forged_plan_edge_certificate.check(forged_plan_edge_graph, forged_plan_edge_report, closure_policy),
    );
    var stale_count_certificate = result.certificate;
    stale_count_certificate.closed_effect_shape_count = 0;
    stale_count_certificate.certificate_fingerprint = stale_count_certificate.computeFingerprint();
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        stale_count_certificate.check(result.graph, result.report, closure_policy),
    );
    const forged_plan_refs = [_]Evidence.Ref{result.static_treaty_plans[0].evidenceRef()};
    const forged_world_port_ref = Evidence.refFor(Evidence.domains.boundary_world_port, 0xBEEF, .{
        .label = "forged-world-port",
        .kind_tag = @tagName(Evidence.WorldPort.Kind.host_tool),
    });
    const forged_world_port_refs = [_]Evidence.Ref{forged_world_port_ref};
    var restricted_world_policy = closure_policy;
    const allowed_world_ports = [_]u64{0xCAFE};
    restricted_world_policy.allowed_world_port_fingerprints = allowed_world_ports[0..];
    const forged_intrinsic_ref = Evidence.refFor(Evidence.domains.host_intrinsic, 0xD00D, .{
        .label = "forged-host-intrinsic",
        .kind_tag = @tagName(Evidence.HostIntrinsic.Kind.host_tool),
    });
    const forged_intrinsic_refs = [_]Evidence.Ref{forged_intrinsic_ref};
    const forged_world_report = Evidence.BoundaryClosureReport.init(.{
        .graph_fingerprint = result.graph.fingerprint,
        .effect_shape_count = 1,
        .closed_effect_shape_count = 0,
        .open_world_port_count = 1,
        .host_intrinsic_count = 1,
        .world_port_refs = forged_world_port_refs[0..],
        .world_port_intrinsic_refs = forged_intrinsic_refs[0..],
        .host_intrinsic_refs = forged_intrinsic_refs[0..],
        .policy_summary = restricted_world_policy.policySummary(),
    });
    const forged_world_certificate = Evidence.BoundaryClosureCertificate.init(
        forged_world_report,
        result.graph,
        restricted_world_policy,
        forged_plan_refs[0..],
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        forged_world_certificate.check(result.graph, forged_world_report, restricted_world_policy),
    );
    const forged_program_ref = Evidence.refFor(Evidence.domains.program_plan, 0xF00D, .{ .label = "forged-provider-program" });
    const forged_provider_program_refs = [_]Evidence.Ref{forged_program_ref};
    const forged_provider_program_report = Evidence.BoundaryClosureReport.init(.{
        .graph_fingerprint = result.graph.fingerprint,
        .effect_shape_count = 1,
        .closed_effect_shape_count = 1,
        .provider_program_refs = forged_provider_program_refs[0..],
        .policy_summary = closure_policy.policySummary(),
    });
    const forged_program_cert = Evidence.BoundaryClosureCertificate.init(
        forged_provider_program_report,
        result.graph,
        closure_policy,
        forged_plan_refs[0..],
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        forged_program_cert.check(result.graph, forged_provider_program_report, closure_policy),
    );
    const mispaired_world_report = Evidence.BoundaryClosureReport.init(.{
        .graph_fingerprint = world_port_result.graph.fingerprint,
        .effect_shape_count = 1,
        .closed_effect_shape_count = 0,
        .open_world_port_count = 1,
        .host_intrinsic_count = 1,
        .world_port_refs = world_port_result.report.world_port_refs,
        .world_port_intrinsic_refs = forged_intrinsic_refs[0..],
        .host_intrinsic_refs = forged_intrinsic_refs[0..],
        .policy_summary = world_port_only_policy.policySummary(),
    });
    const mispaired_world_certificate = Evidence.BoundaryClosureCertificate.init(
        mispaired_world_report,
        world_port_result.graph,
        world_port_only_policy,
        world_port_result.plan_refs,
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        mispaired_world_certificate.check(world_port_result.graph, mispaired_world_report, world_port_only_policy),
    );
    const omitted_intrinsic_report = Evidence.BoundaryClosureReport.init(.{
        .graph_fingerprint = world_port_result.graph.fingerprint,
        .effect_shape_count = 1,
        .closed_effect_shape_count = 1,
        .policy_summary = world_port_only_policy.policySummary(),
    });
    const omitted_intrinsic_certificate = Evidence.BoundaryClosureCertificate.init(
        omitted_intrinsic_report,
        world_port_result.graph,
        world_port_only_policy,
        world_port_result.plan_refs,
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        omitted_intrinsic_certificate.check(world_port_result.graph, omitted_intrinsic_report, world_port_only_policy),
    );
    const forged_intrinsic_report = Evidence.BoundaryClosureReport.init(.{
        .graph_fingerprint = result.graph.fingerprint,
        .effect_shape_count = 1,
        .closed_effect_shape_count = 1,
        .host_intrinsic_count = 1,
        .host_intrinsic_refs = forged_intrinsic_refs[0..],
        .policy_summary = closure_policy.policySummary(),
    });
    const forged_intrinsic_certificate = Evidence.BoundaryClosureCertificate.init(
        forged_intrinsic_report,
        result.graph,
        closure_policy,
        forged_plan_refs[0..],
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        forged_intrinsic_certificate.check(result.graph, forged_intrinsic_report, closure_policy),
    );

    var not_closed_report = result.report;
    not_closed_report.closed_effect_shape_count = 0;
    not_closed_report.report_fingerprint = not_closed_report.computeFingerprint();
    const not_closed_certificate = Evidence.BoundaryClosureCertificate.init(
        not_closed_report,
        result.graph,
        closure_policy,
        forged_plan_refs[0..],
    );
    try std.testing.expectError(
        error.BoundaryClosureNotClosed,
        not_closed_certificate.check(result.graph, not_closed_report, closure_policy),
    );

    const forged_blocker = Evidence.boundaryClosureBlocker(.{
        .tag = .runtime_guard_required,
        .subject = result.static_treaty_plans[0].source_shape.evidenceRef(),
        .summary = "forged blocker must prevent closure",
    });
    const forged_blockers = [_]Evidence.Blocker{forged_blocker};
    var blocked_but_count_default_report = result.report;
    blocked_but_count_default_report.blockers = forged_blockers[0..];
    blocked_but_count_default_report.blocker_count = forged_blockers.len;
    blocked_but_count_default_report.report_fingerprint = blocked_but_count_default_report.computeFingerprint();
    try std.testing.expect(!blocked_but_count_default_report.closed());
    const missing_blocker_ref_certificate = Evidence.BoundaryClosureCertificate.init(
        blocked_but_count_default_report,
        result.graph,
        closure_policy,
        forged_plan_refs[0..],
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        missing_blocker_ref_certificate.check(result.graph, blocked_but_count_default_report, closure_policy),
    );
    const forged_blocker_refs = [_]Evidence.Ref{Evidence.refForBoundaryClosureBlocker(forged_blocker)};
    const blocked_but_count_default_certificate = Evidence.BoundaryClosureCertificate.initWithBlockerRefs(
        blocked_but_count_default_report,
        result.graph,
        closure_policy,
        forged_plan_refs[0..],
        forged_blocker_refs[0..],
    );
    try std.testing.expectError(
        error.BoundaryClosureCertificateMismatch,
        blocked_but_count_default_certificate.check(result.graph, blocked_but_count_default_report, closure_policy),
    );

    var empty_audit_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .policy = Evidence.BoundaryClosurePolicy.auditOnly(),
    });
    defer empty_audit_result.deinit();
    try std.testing.expectEqual(@as(usize, 1), empty_audit_result.report.blocker_count);
    try std.testing.expectEqual(empty_audit_result.report.blockers.len, empty_audit_result.certificate.blocker_refs.len);
    var saw_empty_audit_blocker_node = false;
    for (empty_audit_result.graph.nodes) |node| {
        if (node.kind == .blocker and node.ref.eql(empty_audit_result.certificate.blocker_refs[0])) {
            saw_empty_audit_blocker_node = true;
        }
    }
    try std.testing.expect(saw_empty_audit_blocker_node);
    try empty_audit_result.certificate.check(
        empty_audit_result.graph,
        empty_audit_result.report,
        Evidence.BoundaryClosurePolicy.auditOnly(),
    );

    const provider_program_ref = Evidence.refFor(Evidence.domains.program_plan, 0xABCDEF, .{ .label = "provider-program" });
    const stale_provider_ref = Evidence.refFor(Evidence.domains.provider_identity, 0xBAD5EED, .{ .label = "stale-provider" });
    const stale_provider_program_ref = Evidence.refFor(Evidence.domains.program_plan, 0xBADCAFE, .{ .label = "stale-provider-program" });
    var omitted_provider_shapes_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_programs = &.{.{
            .provider_ref = provider.evidenceRef(),
            .program_ref = provider_program_ref,
            .shapes = &.{},
        }},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = closure_policy,
    });
    defer omitted_provider_shapes_result.deinit();
    try std.testing.expectEqual(@as(usize, 0), omitted_provider_shapes_result.report.provider_program_refs.len);
    try std.testing.expectEqual(@as(usize, 0), omitted_provider_shapes_result.report.blocker_count);
    try omitted_provider_shapes_result.certificate.check(omitted_provider_shapes_result.graph, omitted_provider_shapes_result.report, closure_policy);

    var provider_program_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_programs = &.{
            .{
                .provider_ref = provider.evidenceRef(),
                .program_ref = provider_program_ref,
                .shapes = &.{},
                .effect_free = true,
            },
            .{
                .provider_ref = stale_provider_ref,
                .program_ref = stale_provider_program_ref,
                .shapes = &.{shape},
            },
        },
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = closure_policy,
    });
    defer provider_program_result.deinit();
    try std.testing.expectEqual(@as(usize, 1), provider_program_result.report.effect_shape_count);
    try std.testing.expectEqual(@as(usize, 0), provider_program_result.report.provider_program_refs.len);
    try std.testing.expectEqual(@as(usize, 0), provider_program_result.certificate.provider_program_refs.len);
    try provider_program_result.certificate.check(provider_program_result.graph, provider_program_result.report, closure_policy);

    var recursive_provider_program_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_programs = &.{.{
            .provider_ref = provider.evidenceRef(),
            .program_ref = provider_program_ref,
            .shapes = &.{shape},
        }},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = closure_policy,
    });
    defer recursive_provider_program_result.deinit();
    try std.testing.expectEqual(@as(usize, 1), recursive_provider_program_result.report.effect_shape_count);
    try std.testing.expectEqual(@as(usize, 0), recursive_provider_program_result.report.provider_program_refs.len);
    try std.testing.expectEqual(@as(usize, 0), recursive_provider_program_result.report.blocker_count);
    try std.testing.expectEqual(recursive_provider_program_result.report.blockers.len, recursive_provider_program_result.certificate.blocker_refs.len);
    try recursive_provider_program_result.certificate.check(recursive_provider_program_result.graph, recursive_provider_program_result.report, closure_policy);

    var depth_policy = closure_policy;
    depth_policy.max_nested_provider_depth = 0;
    var depth_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_programs = &.{.{
            .provider_ref = provider.evidenceRef(),
            .program_ref = provider_program_ref,
            .shapes = &.{shape},
        }},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = depth_policy,
    });
    defer depth_result.deinit();
    try std.testing.expectEqual(@as(usize, 0), depth_result.report.provider_program_refs.len);
    try std.testing.expectEqual(@as(usize, 0), depth_result.report.blocker_count);
    try std.testing.expectEqual(depth_result.report.blockers.len, depth_result.certificate.blocker_refs.len);
    try depth_result.certificate.check(depth_result.graph, depth_result.report, depth_policy);

    var node_bound_policy = closure_policy;
    node_bound_policy.max_nodes = 0;
    var node_bound_result = try Closure.analyze(allocator, .{
        .allocator = allocator,
        .root_shapes = &.{shape},
        .provider_manifests = &.{provider},
        .provider_offers = &.{offer},
        .capabilities = &.{capability},
        .policy = node_bound_policy,
    });
    defer node_bound_result.deinit();
    try std.testing.expect(node_bound_result.report.blocker_count != 0);
    try std.testing.expectEqual(node_bound_result.report.blockers.len, node_bound_result.certificate.blocker_refs.len);
    try std.testing.expectError(
        error.BoundaryClosureNotClosed,
        node_bound_result.certificate.check(node_bound_result.graph, node_bound_result.report, node_bound_policy),
    );
}

test "semantic body classifications expose stable evidence refs" {
    try std.testing.expect(Evidence.SemanticBody.boundary_program.isNonIntrinsic());
    try std.testing.expect(Evidence.SemanticBody.declarative.isNonIntrinsic());
    try std.testing.expect(Evidence.SemanticBody.residualized_program.isNonIntrinsic());
    try std.testing.expect(Evidence.SemanticBody.pipeline.isNonIntrinsic());
    try std.testing.expect(Evidence.SemanticBody.kernel_primitive.isNonIntrinsic());
    try std.testing.expect(Evidence.SemanticBody.host_intrinsic.isHostIntrinsic());
    try std.testing.expect(Evidence.SemanticBody.unknown.isUnknown());
    try std.testing.expect(!Evidence.SemanticBody.kernel_primitive.isHostIntrinsic());

    const program_ref = Evidence.SemanticBody.boundary_program.evidenceRef();
    const intrinsic_ref = Evidence.SemanticBody.host_intrinsic.evidenceRef();
    try std.testing.expectEqual(Evidence.domains.semantic_body.id, program_ref.domain_id);
    try std.testing.expectEqualStrings("boundary_program", program_ref.kind_tag.?);
    try std.testing.expect(program_ref.fingerprint != intrinsic_ref.fingerprint);
}

test "host intrinsic fingerprints use declared metadata not runtime identity" {
    const offer_ref = Evidence.refFor(Evidence.domains.provider_offer, 0x55, .{ .label = "offer" });
    const intrinsic = Evidence.HostIntrinsic.init(.{
        .label = "fixture-tool",
        .kind = .host_tool,
        .owner_subsystem = .provider_harness,
        .associated_provider_offer_ref = offer_ref,
        .reason = "external tool call",
        .replay_policy_summary = "host-owned",
        .usage_mode_summary = "copyable",
        .tags = &.{"world"},
        .metadata = "declared-metadata",
    });
    const same = Evidence.HostIntrinsic.init(.{
        .label = "fixture-tool",
        .kind = .host_tool,
        .owner_subsystem = .provider_harness,
        .associated_provider_offer_ref = offer_ref,
        .reason = "external tool call",
        .replay_policy_summary = "host-owned",
        .usage_mode_summary = "copyable",
        .tags = &.{"world"},
        .metadata = "declared-metadata",
    });
    const relabeled = Evidence.HostIntrinsic.init(.{
        .label = "fixture-tool-v2",
        .kind = .host_tool,
        .owner_subsystem = .provider_harness,
        .associated_provider_offer_ref = offer_ref,
        .reason = "external tool call",
        .metadata = "declared-metadata",
    });
    const rekind = Evidence.HostIntrinsic.init(.{
        .label = "fixture-tool",
        .kind = .host_model,
        .owner_subsystem = .provider_harness,
        .associated_provider_offer_ref = offer_ref,
        .reason = "external tool call",
        .metadata = "declared-metadata",
    });
    const after_scoped = Evidence.HostIntrinsic.init(.{
        .label = "fixture-tool",
        .kind = .host_tool,
        .owner_subsystem = .provider_harness,
        .associated_provider_offer_ref = offer_ref,
        .allowed_after_site_indexes = &.{1},
        .reason = "external tool call",
        .replay_policy_summary = "host-owned",
        .usage_mode_summary = "copyable",
        .tags = &.{"world"},
        .metadata = "declared-metadata",
    });

    try std.testing.expectEqual(intrinsic.fingerprint, same.fingerprint);
    try std.testing.expect(intrinsic.fingerprint != relabeled.fingerprint);
    try std.testing.expect(intrinsic.fingerprint != rekind.fingerprint);
    try std.testing.expect(intrinsic.fingerprint != after_scoped.fingerprint);
    try std.testing.expectEqual(Evidence.domains.host_intrinsic.id, intrinsic.evidenceRef().domain_id);
    try std.testing.expectEqual(Program.evidence_host_intrinsic_format_version, intrinsic.evidenceRef().format_version.?);
    try std.testing.expect(!@hasField(Evidence.HostIntrinsic, "function_pointer"));
    try std.testing.expect(!@hasField(Evidence.HostIntrinsic, "request_token"));

    const blocker = intrinsic.toEvidenceBlocker("unallowlisted_intrinsic", "tool not allowlisted");
    try std.testing.expectEqual(Evidence.domains.host_intrinsic.id, blocker.domain);
    try std.testing.expectEqual(intrinsic.fingerprint, blocker.subject.?.fingerprint);
    const projection = intrinsic.declaredProjection();
    try std.testing.expectEqualStrings("intrinsic_declared", projection.suggested_event_kind);
    try std.testing.expectEqual(intrinsic.fingerprint, projection.evidence_ref.fingerprint);
}

test "defunctionalization reports and policies enforce strict and allowlist modes" {
    const scope = Evidence.refFor(Evidence.domains.provider_harness, 0x100, .{ .label = "provider" });
    const intrinsic = Evidence.HostIntrinsic.init(.{
        .label = "fixture-handler",
        .kind = .provider_function,
        .owner_subsystem = .provider_harness,
        .reason = "function-backed provider handler",
    });
    const intrinsic_refs = [_]Evidence.Ref{intrinsic.evidenceRef()};
    const report = Evidence.DefunctionalizationReport.init(.{
        .scope_kind = .provider_harness,
        .scope_ref = scope,
        .counts = .{
            .boundary_program = 1,
            .kernel_primitive = 1,
            .host_intrinsic = 1,
        },
        .intrinsic_refs = &intrinsic_refs,
        .dependencies = &.{.{ .role = .host_intrinsic, .ref = intrinsic.evidenceRef() }},
        .summary = "provider harness defunctionalization",
    });
    const alternate_intrinsic = Evidence.HostIntrinsic.init(.{
        .label = "alternate-fixture-handler",
        .kind = .host_tool,
        .owner_subsystem = .provider_harness,
        .reason = "alternate external handler",
    });
    const generic_intrinsic_refs = [_]Evidence.Ref{ intrinsic.evidenceRef(), alternate_intrinsic.evidenceRef() };
    const split_role_intrinsic_report = Evidence.DefunctionalizationReport.init(.{
        .scope_kind = .provider_harness,
        .scope_ref = scope,
        .counts = .{ .host_intrinsic = 2 },
        .intrinsic_refs = &.{intrinsic.evidenceRef()},
        .primary_intrinsic_ref = alternate_intrinsic.evidenceRef(),
        .summary = "intrinsic role shape",
    });
    const generic_intrinsic_report = Evidence.DefunctionalizationReport.init(.{
        .scope_kind = .provider_harness,
        .scope_ref = scope,
        .counts = .{ .host_intrinsic = 2 },
        .intrinsic_refs = &generic_intrinsic_refs,
        .summary = "intrinsic role shape",
    });

    try std.testing.expectEqual(@as(usize, 3), report.total_bodies);
    try std.testing.expectEqual(@as(usize, 1), report.boundary_program_count);
    try std.testing.expectEqual(@as(usize, 1), report.kernel_primitive_count);
    try std.testing.expectEqual(@as(usize, 1), report.host_intrinsic_count);
    try std.testing.expectEqual(Evidence.domains.defunctionalization_report.id, report.evidenceRef().domain_id);
    try std.testing.expect(split_role_intrinsic_report.report_fingerprint != generic_intrinsic_report.report_fingerprint);
    try std.testing.expectError(error.HostIntrinsicsPresent, report.assertNoHostIntrinsics());
    try std.testing.expectError(error.HostIntrinsicsPresent, report.assertOnlyAllowlistedIntrinsics(Evidence.DefunctionalizationPolicy.strict()));
    const counted_intrinsic_evidence = report.toEvidenceReport();
    try std.testing.expect(!counted_intrinsic_evidence.success);
    try std.testing.expectError(error.EvidenceReportHasErrors, counted_intrinsic_evidence.assertOk());
    try report.assertOnlyAllowlistedIntrinsics(.{
        .label = "world_boundary",
        .allow_host_intrinsics = true,
        .reject_unknown = true,
        .allowed_intrinsic_fingerprints = &.{intrinsic.fingerprint},
    });
    const treaty_only_policy = Evidence.DefunctionalizationPolicy{
        .label = "ban-treaty-intrinsics",
        .allow_host_intrinsics = true,
        .allowed_intrinsic_fingerprints = &.{intrinsic.fingerprint},
        .require_no_intrinsics_in_treaties = true,
    };
    try report.assertOnlyAllowlistedIntrinsics(treaty_only_policy);
    const treaty_intrinsic_report = Evidence.DefunctionalizationReport.init(.{
        .scope_kind = .treaty,
        .scope_ref = Evidence.refFor(Evidence.domains.treaty, 0x101, .{}),
        .counts = .{ .host_intrinsic = 1 },
        .intrinsic_refs = &intrinsic_refs,
        .summary = "treaty defunctionalization",
    });
    try std.testing.expectError(error.HostIntrinsicsPresent, treaty_intrinsic_report.assertOnlyAllowlistedIntrinsics(treaty_only_policy));
    const forged_non_intrinsic_ref = Evidence.refFor(Evidence.domains.provider_offer, intrinsic.fingerprint, .{
        .label = intrinsic.label,
        .kind_tag = @tagName(intrinsic.kind),
    });
    const forged_non_intrinsic_report = Evidence.DefunctionalizationReport.init(.{
        .scope_kind = .provider_harness,
        .scope_ref = scope,
        .counts = .{ .host_intrinsic = 1 },
        .intrinsic_refs = &.{forged_non_intrinsic_ref},
        .summary = "forged non-intrinsic ref",
    });
    try std.testing.expectError(error.HostIntrinsicsPresent, forged_non_intrinsic_report.assertOnlyAllowlistedIntrinsics(.{
        .label = "forged_non_intrinsic",
        .allow_host_intrinsics = true,
        .reject_unknown = true,
        .allowed_intrinsic_fingerprints = &.{intrinsic.fingerprint},
        .allowed_intrinsic_kinds = &.{intrinsic.kind},
        .allowed_intrinsic_labels = &.{intrinsic.label},
    }));
    try std.testing.expectError(error.HostIntrinsicsPresent, report.assertOnlyAllowlistedIntrinsics(.{
        .label = "program_backed_required",
        .allow_host_intrinsics = true,
        .reject_unknown = true,
        .allowed_intrinsic_fingerprints = &.{intrinsic.fingerprint},
        .require_program_backed_providers = true,
    }));
    try std.testing.expectError(error.HostIntrinsicsPresent, report.assertOnlyAllowlistedIntrinsics(.{
        .label = "no_kernel_primitives",
        .allow_host_intrinsics = true,
        .allow_kernel_primitives = false,
        .allowed_intrinsic_fingerprints = &.{intrinsic.fingerprint},
    }));
    try std.testing.expectError(error.HostIntrinsicsPresent, report.assertOnlyAllowlistedIntrinsics(.{
        .label = "wrong_allowlist",
        .allow_host_intrinsics = true,
        .allowed_intrinsic_fingerprints = &.{intrinsic.fingerprint + 1},
    }));
    const fixture_intrinsic = Evidence.HostIntrinsic.init(.{
        .label = "fixture-only-handler",
        .kind = .test_fixture,
        .owner_subsystem = .provider_harness,
        .reason = "test fixture provider handler",
        .stability = .test_only,
    });
    const fixture_report = Evidence.DefunctionalizationReport.init(.{
        .scope_kind = .provider_harness,
        .scope_ref = scope,
        .counts = .{ .host_intrinsic = 1 },
        .intrinsic_refs = &.{fixture_intrinsic.evidenceRef()},
        .summary = "fixture intrinsic",
    });
    try fixture_report.assertOnlyAllowlistedIntrinsics(.{
        .label = "fixture-with-constrained-policy",
        .allow_host_intrinsics = true,
        .allow_test_fixtures = true,
        .reject_dynamic_mappers = true,
        .allowed_intrinsic_fingerprints = &.{intrinsic.fingerprint + 1},
    });
    try std.testing.expect(!Evidence.DefunctionalizationPolicy.strict().allowsIntrinsicRef(fixture_intrinsic.evidenceRef()));
    try std.testing.expect(Evidence.DefunctionalizationPolicy.testFixture().allowsIntrinsicRef(fixture_intrinsic.evidenceRef()));

    const unknown_report = Evidence.DefunctionalizationReport.init(.{
        .scope_kind = .provider_offer,
        .scope_ref = Evidence.refFor(Evidence.domains.provider_offer, 0x101, .{ .label = "manual" }),
        .counts = .{ .unknown = 1 },
        .unknown_refs = &.{Evidence.SemanticBody.unknown.evidenceRef()},
        .summary = "manual offer",
    });
    try std.testing.expectError(error.UnknownSemanticBody, unknown_report.assertOnlyAllowlistedIntrinsics(Evidence.DefunctionalizationPolicy.strict()));
    const counted_unknown_evidence = unknown_report.toEvidenceReport();
    try std.testing.expect(!counted_unknown_evidence.success);
    try std.testing.expectError(error.EvidenceReportHasErrors, counted_unknown_evidence.assertOk());
    try std.testing.expect(Evidence.DefunctionalizationPolicy.worldBoundary().fingerprint() != Evidence.DefunctionalizationPolicy.permissive().fingerprint());
    try std.testing.expectEqual(Evidence.domains.defunctionalization_policy.id, Evidence.DefunctionalizationPolicy.strict().evidenceRef().domain_id);
    const projection = report.recordedProjection();
    try std.testing.expectEqualStrings("defunctionalization_report_recorded", projection.suggested_event_kind);
    try std.testing.expectEqual(report.evidenceRef().fingerprint, projection.evidence_ref.fingerprint);
}

test "evidence refs preserve domain and legacy fingerprints without request tokens" {
    const RequestKind = enum { operation };
    const request = .{
        .fingerprint = @as(u64, 0xabc),
        .request_format_version = Program.exchange_request_format_version,
        .name = "approval",
        .site_index = @as(usize, 7),
        .kind = RequestKind.operation,
    };
    const request_ref = Evidence.refForRequestEnvelope(request);
    try std.testing.expectEqual(Evidence.domains.exchange_request_envelope.id, request_ref.domain_id);
    try std.testing.expectEqual(request.fingerprint, request_ref.fingerprint);
    try std.testing.expectEqual(Program.exchange_request_format_version, request_ref.format_version.?);
    try std.testing.expect(!@hasField(Evidence.Ref, "request_token"));

    var manifest = try Program.Exchange.ProviderManifest.encode(std.testing.allocator, .{ .label = "provider" });
    defer manifest.deinit();
    const manifest_ref = manifest.evidenceRef();
    try std.testing.expectEqual(Evidence.domains.provider_manifest.id, manifest_ref.domain_id);
    try std.testing.expectEqual(manifest.fingerprint, manifest_ref.fingerprint);
    try std.testing.expectEqualStrings("provider", manifest_ref.label.?);
}

test "byte-backed provider evidence domains match encoded fingerprint domains" {
    var manifest = try Program.Exchange.ProviderManifest.encode(std.testing.allocator, .{ .label = "provider" });
    defer manifest.deinit();
    try std.testing.expectEqual(manifest.fingerprint, exchangeFingerprint(Evidence.domains.provider_manifest, manifest.bytes));

    var offer = try Program.Exchange.ProviderOffer.encode(std.testing.allocator, .{
        .label = "offer",
        .provider_fingerprint = 0x1234,
        .manifest_fingerprint = manifest.fingerprint,
    });
    defer offer.deinit();
    try std.testing.expectEqual(offer.fingerprint, exchangeFingerprint(Evidence.domains.provider_offer, offer.bytes));
    try std.testing.expectEqual(offer.fingerprint, offer.evidenceRef().fingerprint);
}

test "fingerprint builder includes domain version and distinguishes optional fields" {
    var first = Evidence.FingerprintBuilder.init(Evidence.domains.provider_harness);
    first.fieldBytes("label", "provider");
    first.fieldOptionalU64("maybe", null);

    var second = Evidence.FingerprintBuilder.init(Evidence.domains.provider_harness);
    second.fieldBytes("label", "provider");
    second.fieldOptionalU64("maybe", 0);

    var third = Evidence.FingerprintBuilder.init(Evidence.domains.provider_offer);
    third.fieldBytes("label", "provider");
    third.fieldOptionalU64("maybe", null);

    try std.testing.expect(first.finish() != second.finish());
    try std.testing.expect(first.finish() != third.finish());
    try std.testing.expect(!@hasDecl(Evidence.FingerprintBuilder, "fieldPointer"));
}

test "dependency graph order is deterministic and reports carry blockers" {
    const subject = Evidence.refFor(Evidence.domains.exchange_request_envelope, 1, .{});
    const provider = Evidence.refFor(Evidence.domains.provider_manifest, 2, .{});
    const route = Evidence.refFor(Evidence.domains.route, 3, .{});
    const route_branch_a = Evidence.refFor(Evidence.domains.route, 3, .{ .label = "route", .branch_id = 1, .site_index = 1, .kind_tag = "direct" });
    const route_branch_b = Evidence.refFor(Evidence.domains.route, 3, .{ .label = "route", .branch_id = 2, .site_index = 1, .kind_tag = "direct" });
    const deps_unsorted = [_]Evidence.Dependency{
        .{ .role = .route, .ref = route },
        .{ .role = .route, .ref = route_branch_b },
        .{ .role = .provider, .ref = provider },
        .{ .role = .route, .ref = route_branch_a },
        .{ .role = .subject, .ref = subject },
    };
    const deps_sorted = [_]Evidence.Dependency{
        .{ .role = .subject, .ref = subject },
        .{ .role = .provider, .ref = provider },
        .{ .role = .route, .ref = route },
        .{ .role = .route, .ref = route_branch_a },
        .{ .role = .route, .ref = route_branch_b },
    };

    const graph_unsorted = Evidence.DependencyGraph{ .dependencies = &deps_unsorted };
    const graph_sorted = Evidence.DependencyGraph{ .dependencies = &deps_sorted };
    try std.testing.expectEqual(try graph_sorted.fingerprint(std.testing.allocator), try graph_unsorted.fingerprint(std.testing.allocator));
    try graph_sorted.require(&.{ .subject, .provider, .route });
    try std.testing.expectError(error.MissingDependency, graph_sorted.require(&.{.response}));

    const blocker = Evidence.Blocker{
        .domain = Evidence.domains.provider_request_validation.id,
        .tag = "malformed_request",
        .subject = subject,
        .primary = provider,
        .short_code = "provider.malformed_request",
        .summary = "provider request is malformed",
        .source = .provider_harness,
    };
    try std.testing.expect(blocker.valid());

    const report = Evidence.Report.withBlockers(subject, Evidence.domains.provider_request_validation.id, &deps_sorted, &.{blocker}, &.{}, null, "provider validation");
    try std.testing.expect(report.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), report.blockerCount());
    try std.testing.expectError(error.EvidenceReportHasErrors, report.assertOk());
    try Evidence.expectReportShape(report);

    const ok = Evidence.Report.ok(subject, Evidence.domains.provider_request_validation.id, &deps_sorted);
    try ok.assertOk();
    try std.testing.expect(ok.report_fingerprint != report.report_fingerprint);

    const reversed_deps = [_]Evidence.Dependency{
        .{ .role = .route, .ref = route_branch_b },
        .{ .role = .route, .ref = route_branch_a },
        .{ .role = .provider, .ref = provider },
        .{ .role = .subject, .ref = subject },
    };
    const canonical_report = Evidence.Report.ok(subject, Evidence.domains.provider_request_validation.id, &reversed_deps);
    const canonical_report_sorted = Evidence.Report.ok(subject, Evidence.domains.provider_request_validation.id, &.{
        .{ .role = .subject, .ref = subject },
        .{ .role = .provider, .ref = provider },
        .{ .role = .route, .ref = route_branch_a },
        .{ .role = .route, .ref = route_branch_b },
    });
    try std.testing.expectEqual(canonical_report_sorted.report_fingerprint, canonical_report.report_fingerprint);
}

test "subsystem blockers lower to shared evidence blockers" {
    var capability_report = Program.Exchange.ValidationReport{};
    capability_report.add(.wrong_capability);
    capability_report.add(.duplicate_obligation_consume);

    const request_ref = Evidence.refFor(Evidence.domains.exchange_request_envelope, 100, .{});
    const capability_ref = Evidence.refFor(Evidence.domains.capability, 101, .{});
    var blocker_storage: [4]Evidence.Blocker = undefined;
    const capability_blockers = capability_report.toEvidenceBlockers(&blocker_storage, .{
        .domain = Evidence.domains.authorization_result.id,
        .subject = request_ref,
        .primary = capability_ref,
        .source = .capability,
        .summary_prefix = "capability validation",
    });
    try std.testing.expectEqual(@as(usize, 2), capability_blockers.len);
    try std.testing.expectEqual(Evidence.domains.authorization_result.id, capability_blockers[0].domain);
    try std.testing.expectEqualStrings("wrong_capability", capability_blockers[0].tag);
    try std.testing.expectEqual(capability_ref.fingerprint, capability_blockers[0].primary.?.fingerprint);
    try std.testing.expect(capability_blockers[0].summary.len != 0);

    const deps = [_]Evidence.Dependency{
        .{ .role = .request, .ref = request_ref },
        .{ .role = .capability, .ref = capability_ref },
    };
    var report_storage: [4]Evidence.Blocker = undefined;
    const capability_evidence_report = capability_report.toEvidenceReport(request_ref, Evidence.domains.authorization_result.id, &deps, &report_storage, .{
        .primary = capability_ref,
        .source = .capability,
        .summary_prefix = "capability validation",
    });
    try std.testing.expect(capability_evidence_report.hasErrors());
    try Evidence.expectDependencyContains(capability_evidence_report.dependencies, .capability, capability_ref);

    const truncated_report = capability_report.toEvidenceReport(request_ref, Evidence.domains.authorization_result.id, &deps, &.{}, .{
        .primary = capability_ref,
        .source = .capability,
        .summary_prefix = "capability validation",
    });
    try std.testing.expect(!truncated_report.success);
    try std.testing.expect(truncated_report.truncated);
    try std.testing.expect(truncated_report.omitted_fingerprint != null);
    try std.testing.expect(truncated_report.hasErrors());
    try std.testing.expectError(error.EvidenceReportHasErrors, truncated_report.assertOk());
    var partial_report_storage: [1]Evidence.Blocker = undefined;
    const partial_truncated_report = capability_report.toEvidenceReport(request_ref, Evidence.domains.authorization_result.id, &deps, &partial_report_storage, .{
        .primary = capability_ref,
        .source = .capability,
        .summary_prefix = "capability validation",
    });
    try std.testing.expect(partial_truncated_report.truncated);
    try std.testing.expect(partial_truncated_report.omitted_fingerprint != truncated_report.omitted_fingerprint);
    try std.testing.expect(partial_truncated_report.report_fingerprint != truncated_report.report_fingerprint);

    const treaty_blocker = Program.Exchange.Treaty.Blocker{
        .tag = .no_provider_offer,
        .request_fingerprint = request_ref.fingerprint,
        .request_format_version = 2,
        .provider_fingerprint = 200,
        .offer_fingerprint = 201,
        .summary = "no provider supports request",
    };
    var related_storage: [6]Evidence.Ref = undefined;
    const evidence_blocker = treaty_blocker.toEvidenceBlockerWithRelated(&related_storage);
    try std.testing.expectEqual(Evidence.domains.treaty_resolver.id, evidence_blocker.domain);
    try std.testing.expectEqualStrings("no_provider_offer", evidence_blocker.tag);
    try std.testing.expectEqual(Evidence.domains.exchange_request_envelope.id, evidence_blocker.subject.?.domain_id);
    try std.testing.expectEqual(request_ref.fingerprint, evidence_blocker.subject.?.fingerprint);
    try std.testing.expectEqual(@as(?u32, 2), evidence_blocker.subject.?.format_version);
    try std.testing.expectEqual(Evidence.domains.provider_offer.id, evidence_blocker.primary.?.domain_id);
    try std.testing.expectEqual(treaty_blocker.offer_fingerprint.?, evidence_blocker.primary.?.fingerprint);
    try std.testing.expectEqual(@as(usize, 2), evidence_blocker.related_refs.len);
    try std.testing.expect(evidence_blocker.summary.len != 0);

    const other_request_blocker = Program.Exchange.Treaty.Blocker{
        .tag = treaty_blocker.tag,
        .request_fingerprint = request_ref.fingerprint + 1,
        .provider_fingerprint = treaty_blocker.provider_fingerprint,
        .offer_fingerprint = treaty_blocker.offer_fingerprint,
        .summary = treaty_blocker.summary,
    };
    try std.testing.expect(treaty_blocker.toEvidenceBlocker().fingerprint() != other_request_blocker.toEvidenceBlocker().fingerprint());
    const other_offer_blocker = Program.Exchange.Treaty.Blocker{
        .tag = treaty_blocker.tag,
        .request_fingerprint = treaty_blocker.request_fingerprint,
        .provider_fingerprint = treaty_blocker.provider_fingerprint,
        .offer_fingerprint = treaty_blocker.offer_fingerprint.? + 1,
        .summary = treaty_blocker.summary,
    };
    try std.testing.expect(treaty_blocker.toEvidenceBlocker().fingerprint() != other_offer_blocker.toEvidenceBlocker().fingerprint());
    const default_evidence_blocker = treaty_blocker.toEvidenceBlocker();
    try std.testing.expectEqual(@as(usize, 2), default_evidence_blocker.relatedRefs().len);
    var other_capability_blocker = treaty_blocker;
    other_capability_blocker.capability_fingerprint = 301;
    try std.testing.expect(treaty_blocker.toEvidenceBlocker().fingerprint() != other_capability_blocker.toEvidenceBlocker().fingerprint());

    var treaty_list = Program.Exchange.Treaty.BlockerList{};
    treaty_list.add(treaty_blocker);
    var treaty_report_storage: [4]Evidence.Blocker = undefined;
    var treaty_related_storage: [4][6]Evidence.Ref = undefined;
    const treaty_report = treaty_list.toEvidenceReport(request_ref, &deps, &treaty_report_storage, &treaty_related_storage);
    try std.testing.expect(treaty_report.hasErrors());
    try std.testing.expectEqual(Evidence.domains.treaty_resolver.id, treaty_report.report_domain);
    try std.testing.expectEqual(@as(usize, 2), treaty_report.blockers[0].related_refs.len);

    var legacy_format_list = Program.Exchange.Treaty.BlockerList{ .request_format_version = 2 };
    legacy_format_list.addTag(.malformed_request, request_ref.fingerprint, "legacy request");
    var legacy_format_storage: [1]Evidence.Blocker = undefined;
    const legacy_format_blockers = legacy_format_list.toEvidenceBlockers(&legacy_format_storage, &.{});
    try std.testing.expectEqual(@as(?u32, 2), legacy_format_blockers[0].subject.?.format_version);

    var alternate_treaty_list = Program.Exchange.Treaty.BlockerList{};
    alternate_treaty_list.add(.{
        .tag = treaty_blocker.tag,
        .request_fingerprint = treaty_blocker.request_fingerprint,
        .provider_fingerprint = 202,
        .offer_fingerprint = 203,
        .summary = treaty_blocker.summary,
    });
    var alt_report_storage: [4]Evidence.Blocker = undefined;
    var alt_related_storage: [4][6]Evidence.Ref = undefined;
    const alt_report = alternate_treaty_list.toEvidenceReport(request_ref, &deps, &alt_report_storage, &alt_related_storage);
    try std.testing.expect(treaty_report.report_fingerprint != alt_report.report_fingerprint);

    var saturated_treaty_list = Program.Exchange.Treaty.BlockerList{};
    for (0..17) |_| saturated_treaty_list.add(treaty_blocker);
    const truncated_treaty_report = saturated_treaty_list.toEvidenceReport(request_ref, &deps, &.{}, &.{});
    try std.testing.expect(!truncated_treaty_report.success);
    try std.testing.expect(truncated_treaty_report.truncated);
    try std.testing.expect(truncated_treaty_report.omitted_fingerprint != null);
    try std.testing.expect(truncated_treaty_report.hasErrors());
    try std.testing.expectError(error.EvidenceReportHasErrors, truncated_treaty_report.assertOk());
    var partial_treaty_storage: [1]Evidence.Blocker = undefined;
    const partial_treaty_report = saturated_treaty_list.toEvidenceReport(request_ref, &deps, &partial_treaty_storage, &.{});
    try std.testing.expect(partial_treaty_report.truncated);
    try std.testing.expect(partial_treaty_report.omitted_fingerprint != truncated_treaty_report.omitted_fingerprint);
    try std.testing.expect(partial_treaty_report.report_fingerprint != truncated_treaty_report.report_fingerprint);
}

test "residual and pipeline blockers do not invent evidence refs for site fingerprints" {
    const residual_blocker = Program.ResidualBlocker{
        .tag = .unsupported_source_mode,
        .source_site_index = 3,
        .source_site_fingerprint = 100,
        .target_protocol_op_fingerprint = 200,
        .message = "unsupported residualization shape",
    };
    const residual_evidence = residual_blocker.toEvidenceBlocker();
    try std.testing.expectEqual(Evidence.domains.residualization_report.id, residual_evidence.domain);
    try std.testing.expectEqual(@as(?Evidence.Ref, null), residual_evidence.subject);
    try std.testing.expectEqual(@as(?Evidence.Ref, null), residual_evidence.primary);
    try std.testing.expectEqual(@as(?usize, 3), residual_evidence.site_index);
    try std.testing.expectEqual(@as(?u64, 100), residual_evidence.source_site_fingerprint);
    try std.testing.expectEqual(@as(?u64, 200), residual_evidence.target_protocol_op_fingerprint);
    var residual_other_target = residual_blocker;
    residual_other_target.target_protocol_op_fingerprint = 201;
    try std.testing.expect(residual_other_target.toEvidenceBlocker().fingerprint() != residual_evidence.fingerprint());

    const pipeline_blocker = Program.PipelineBlocker{
        .tag = .unsupported_residualization_shape,
        .source_site_index = 4,
        .source_site_fingerprint = 300,
        .target_protocol_op_fingerprint = 400,
        .morphism_fingerprint = 500,
        .summary = "unsupported pipeline route",
    };
    const pipeline_evidence = pipeline_blocker.toEvidenceBlocker();
    try std.testing.expectEqual(Evidence.domains.pipeline.id, pipeline_evidence.domain);
    try std.testing.expectEqual(@as(?Evidence.Ref, null), pipeline_evidence.subject);
    try std.testing.expectEqual(@as(?Evidence.Ref, null), pipeline_evidence.primary);
    try std.testing.expectEqual(@as(?usize, 4), pipeline_evidence.site_index);
    try std.testing.expectEqual(@as(?u64, 300), pipeline_evidence.source_site_fingerprint);
    try std.testing.expectEqual(@as(?u64, 400), pipeline_evidence.target_protocol_op_fingerprint);
    try std.testing.expectEqual(@as(?u64, 500), pipeline_evidence.morphism_fingerprint);
    var pipeline_other_morphism = pipeline_blocker;
    pipeline_other_morphism.morphism_fingerprint = 501;
    try std.testing.expect(pipeline_other_morphism.toEvidenceBlocker().fingerprint() != pipeline_evidence.fingerprint());
}

test "certificate authorization and journal projection views expose common refs" {
    const certificate = .{
        .certificate_fingerprint = @as(u64, 10),
        .treaty_fingerprint = @as(u64, 11),
        .request_envelope_fingerprint = @as(u64, 12),
        .request_envelope_format_version = @as(u32, 2),
        .request_fingerprint = @as(u64, 13),
        .manifest_fingerprint = @as(u64, 14),
        .provider_fingerprint = @as(u64, 15),
        .provider_offer_fingerprint = @as(u64, 16),
        .capability_fingerprint = @as(u64, 17),
        .route_fingerprint = @as(u64, 18),
    };
    var dependency_storage: [6]Evidence.Dependency = undefined;
    const view = Evidence.certificateViewForTreatyCertificateWithDependencies(&dependency_storage, certificate);
    try std.testing.expectEqual(Evidence.domains.treaty_certificate.id, view.certificate_ref.domain_id);
    try std.testing.expectEqual(certificate.certificate_fingerprint, view.certificate_fingerprint);
    try std.testing.expectEqual(@as(?u32, 2), view.subject_ref.format_version);
    try Evidence.expectDependencyContains(view.dependencies, .subject, Evidence.refFor(Evidence.domains.exchange_request_envelope, certificate.request_envelope_fingerprint, .{ .format_version = 2 }));
    try Evidence.expectDependencyContains(view.dependencies, .provider, Evidence.refForProviderIdentity(certificate.provider_fingerprint));

    const authorization = .{
        .authorization_fingerprint = @as(u64, 20),
        .treaty_fingerprint = @as(u64, 21),
        .request_envelope_fingerprint = @as(u64, 22),
        .request_envelope_format_version = @as(u32, 2),
        .response_envelope_fingerprint = @as(u64, 23),
        .provider_fingerprint = @as(u64, 24),
        .capability_fingerprint = @as(u64, 25),
        .route_fingerprint = @as(u64, 26),
        .obligation_fingerprint = @as(?u64, 27),
    };
    const authorization_view = Evidence.authorizationViewForTreatyAuthorization(authorization);
    try std.testing.expectEqual(Evidence.domains.treaty_authorization.id, authorization_view.authorization_ref.domain_id);
    try std.testing.expectEqual(@as(?u32, 2), authorization_view.request_ref.?.format_version);
    try std.testing.expectEqual(authorization.response_envelope_fingerprint, authorization_view.response_ref.?.fingerprint);
    try std.testing.expectEqual(Evidence.domains.provider_identity.id, authorization_view.provider_ref.?.domain_id);
    try std.testing.expectEqual(authorization.provider_fingerprint, authorization_view.provider_ref.?.fingerprint);

    const legacy_authorization = .{
        .authorization_fingerprint = @as(u64, 30),
        .format_version = @as(u32, 2),
        .treaty_fingerprint = @as(u64, 31),
        .request_envelope_fingerprint = @as(u64, 0),
        .response_envelope_fingerprint = @as(u64, 32),
        .provider_fingerprint = @as(u64, 0),
        .capability_fingerprint = @as(u64, 0),
        .route_fingerprint = @as(u64, 33),
        .obligation_fingerprint = @as(?u64, null),
    };
    const legacy_authorization_ref = Evidence.refForTreatyAuthorization(legacy_authorization);
    try std.testing.expectEqual(Evidence.domains.treaty_authorization_legacy_v2.id, legacy_authorization_ref.domain_id);
    try std.testing.expectEqual(@as(?u32, 2), legacy_authorization_ref.format_version);
    const legacy_authorization_view = Evidence.authorizationViewForTreatyAuthorization(legacy_authorization);
    try std.testing.expect(legacy_authorization_view.request_ref == null);
    try std.testing.expect(legacy_authorization_view.provider_ref == null);
    try std.testing.expect(legacy_authorization_view.capability_ref == null);

    const projection = Evidence.journalProjection(authorization_view.authorization_ref, "treaty_authorization_recorded", &.{authorization_view.response_ref.?}, "authorization recorded");
    try std.testing.expectEqualStrings("treaty_authorization_recorded", projection.suggested_event_kind);
    try std.testing.expectEqual(authorization.authorization_fingerprint, projection.evidence_ref.fingerprint);

    const legacy_v3_authorization = .{
        .authorization_fingerprint = @as(u64, 40),
        .format_version = @as(u32, 3),
        .treaty_fingerprint = @as(u64, 41),
        .request_envelope_fingerprint = @as(u64, 42),
        .request_envelope_format_version = @as(u32, 3),
        .response_envelope_fingerprint = @as(u64, 43),
        .provider_fingerprint = @as(u64, 44),
        .capability_fingerprint = @as(u64, 45),
        .route_fingerprint = @as(u64, 46),
        .obligation_fingerprint = @as(?u64, null),
    };
    const legacy_v3_authorization_view = Evidence.authorizationViewForTreatyAuthorization(legacy_v3_authorization);
    try std.testing.expectEqual(legacy_v3_authorization.request_envelope_fingerprint, legacy_v3_authorization_view.request_ref.?.fingerprint);
    try std.testing.expectEqual(@as(?u32, null), legacy_v3_authorization_view.request_ref.?.format_version);
}

test "evidence object shape helpers accept adapted exchange objects" {
    comptime Evidence.expectHasRef(Program.Exchange.ProviderManifest);
    comptime Evidence.expectHasRef(Program.Exchange.ProviderOffer);
    comptime Evidence.expectHasRef(Program.Exchange.RequestEnvelope);
    comptime Evidence.expectHasRef(Program.Exchange.ResponseEnvelope);
    comptime Evidence.expectHasRef(Program.Exchange.Capability);
    comptime Evidence.expectHasRef(Program.Exchange.Route);
    comptime Evidence.expectHasRef(Program.Exchange.Treaty);
    comptime Evidence.expectHasRef(Program.Exchange.Treaty.Certificate);
    comptime Evidence.expectHasRef(Program.Exchange.Treaty.Authorization);
}
