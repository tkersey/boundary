// zlinter-disable no_inferred_error_unions no_swallow_error require_doc_comment
const ability = @import("ability");
const std = @import("std");

fn unitPlan() ability.ir.ProgramPlan {
    const root = ability.ir.builder.function(0);
    const functions = [_]ability.ir.plan.Function{.{
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
    const blocks = [_]ability.ir.plan.Block{.{ .first_instruction = 0, .instruction_count = 0, .terminator_index = 0 }};
    const terminators = [_]ability.ir.plan.Terminator{.{ .kind = .return_unit }};
    return ability.ir.builder.finish(.{
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

const Program = ability.program("evidence-test", struct {}, struct {
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
    try std.testing.expectEqual(@as(u32, 3), Evidence.domains.treaty_authorization_legacy_v3.format_version.?);
    try std.testing.expectEqual(@as(u32, 2), Evidence.domains.treaty_authorization_legacy_v2.format_version.?);
    try std.testing.expectEqual(Program.pipeline_fingerprint_version, Evidence.domains.pipeline.fingerprint_version);

    try std.testing.expectEqualStrings("ability.program.capsule.image", Evidence.domains.capsule_image.name);
    try std.testing.expectEqualStrings("ability.program.session.journal", Evidence.domains.journal.name);
    try std.testing.expectEqualStrings("ability.exchange.provider_offer", Evidence.domains.provider_offer.name);
    try std.testing.expectEqualStrings("ability.exchange.morphism_offer", Evidence.domains.morphism_offer.name);
    try std.testing.expectEqualStrings("ability.exchange.capability.path", Evidence.domains.capability_attenuation_path.name);
    try std.testing.expectEqualStrings("ability.exchange.authorization.result", Evidence.domains.authorization_result.name);
    try std.testing.expectEqualStrings("ability.session.reinterpret", Evidence.domains.reinterpretation.name);
    try std.testing.expectEqualStrings("ability.evidence.semantic_body", Evidence.domains.semantic_body.name);
    try std.testing.expectEqualStrings("ability.evidence.host_intrinsic", Evidence.domains.host_intrinsic.name);

    for (Evidence.all_domains) |domain| {
        try std.testing.expect(domain.request_tokens_excluded);
        try std.testing.expect(domain.runtime_identity_excluded);
        if (domain.bytes_encoded) try std.testing.expect(domain.format_version != null);
        try std.testing.expect(domain.fingerprint_version != 0);
    }
}

test "semantic body classifications expose stable evidence refs" {
    try std.testing.expect(Evidence.SemanticBody.ability_program.isNonIntrinsic());
    try std.testing.expect(Evidence.SemanticBody.declarative.isNonIntrinsic());
    try std.testing.expect(Evidence.SemanticBody.residualized_program.isNonIntrinsic());
    try std.testing.expect(Evidence.SemanticBody.pipeline.isNonIntrinsic());
    try std.testing.expect(Evidence.SemanticBody.kernel_primitive.isNonIntrinsic());
    try std.testing.expect(Evidence.SemanticBody.host_intrinsic.isHostIntrinsic());
    try std.testing.expect(Evidence.SemanticBody.unknown.isUnknown());
    try std.testing.expect(!Evidence.SemanticBody.kernel_primitive.isHostIntrinsic());

    const program_ref = Evidence.SemanticBody.ability_program.evidenceRef();
    const intrinsic_ref = Evidence.SemanticBody.host_intrinsic.evidenceRef();
    try std.testing.expectEqual(Evidence.domains.semantic_body.id, program_ref.domain_id);
    try std.testing.expectEqualStrings("ability_program", program_ref.kind_tag.?);
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

    try std.testing.expectEqual(intrinsic.fingerprint, same.fingerprint);
    try std.testing.expect(intrinsic.fingerprint != relabeled.fingerprint);
    try std.testing.expect(intrinsic.fingerprint != rekind.fingerprint);
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
            .ability_program = 1,
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
    try std.testing.expectEqual(@as(usize, 1), report.ability_program_count);
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
