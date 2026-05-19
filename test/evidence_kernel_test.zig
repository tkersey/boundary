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

test "evidence domain registry is unique and mirrors public version constants" {
    try Evidence.validateRegistry();

    try std.testing.expectEqual(Program.capsule_image_format_version, Evidence.domains.capsule_image.format_version.?);
    try std.testing.expectEqual(Program.capsule_image_fingerprint_version, Evidence.domains.capsule_image.fingerprint_version);
    try std.testing.expectEqual(Program.journal_format_version, Evidence.domains.journal.format_version.?);
    try std.testing.expectEqual(@as(u32, 4), Evidence.domains.journal_legacy_v4.format_version.?);
    try std.testing.expectEqual(Program.journal_fingerprint_version, Evidence.domains.journal.fingerprint_version);
    try std.testing.expectEqual(Program.exchange_request_format_version, Evidence.domains.exchange_request_envelope.format_version.?);
    try std.testing.expectEqual(Program.exchange_request_fingerprint_version, Evidence.domains.exchange_request_envelope.fingerprint_version);
    try std.testing.expectEqual(Program.exchange_provider_harness_fingerprint_version, Evidence.domains.provider_harness.fingerprint_version);
    try std.testing.expectEqual(Program.exchange_treaty_authorization_fingerprint_version, Evidence.domains.treaty_authorization.fingerprint_version);
    try std.testing.expectEqual(Program.pipeline_fingerprint_version, Evidence.domains.pipeline.fingerprint_version);

    for (Evidence.all_domains) |domain| {
        try std.testing.expect(domain.request_tokens_excluded);
        try std.testing.expect(domain.runtime_identity_excluded);
        if (domain.bytes_encoded) try std.testing.expect(domain.format_version != null);
        try std.testing.expect(domain.fingerprint_version != 0);
    }
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
    const deps_unsorted = [_]Evidence.Dependency{
        .{ .role = .route, .ref = route },
        .{ .role = .provider, .ref = provider },
        .{ .role = .subject, .ref = subject },
    };
    const deps_sorted = [_]Evidence.Dependency{
        .{ .role = .subject, .ref = subject },
        .{ .role = .provider, .ref = provider },
        .{ .role = .route, .ref = route },
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

    const treaty_blocker = Program.Exchange.Treaty.Blocker{
        .tag = .no_provider_offer,
        .request_fingerprint = request_ref.fingerprint,
        .provider_fingerprint = 200,
        .offer_fingerprint = 201,
        .summary = "no provider supports request",
    };
    var related_storage: [6]Evidence.Ref = undefined;
    const evidence_blocker = treaty_blocker.toEvidenceBlockerWithRelated(&related_storage);
    try std.testing.expectEqual(Evidence.domains.treaty_resolver.id, evidence_blocker.domain);
    try std.testing.expectEqualStrings("no_provider_offer", evidence_blocker.tag);
    try std.testing.expectEqual(@as(usize, 2), evidence_blocker.related_refs.len);
    try std.testing.expect(evidence_blocker.summary.len != 0);

    var treaty_list = Program.Exchange.Treaty.BlockerList{};
    treaty_list.add(treaty_blocker);
    var treaty_report_storage: [4]Evidence.Blocker = undefined;
    const treaty_report = treaty_list.toEvidenceReport(request_ref, &deps, &treaty_report_storage);
    try std.testing.expect(treaty_report.hasErrors());
    try std.testing.expectEqual(Evidence.domains.treaty_resolver.id, treaty_report.report_domain);
}

test "certificate authorization and journal projection views expose common refs" {
    const certificate = .{
        .certificate_fingerprint = @as(u64, 10),
        .treaty_fingerprint = @as(u64, 11),
        .request_envelope_fingerprint = @as(u64, 12),
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
    try Evidence.expectDependencyContains(view.dependencies, .provider, Evidence.refFor(Evidence.domains.provider_manifest, certificate.provider_fingerprint, .{}));

    const authorization = .{
        .authorization_fingerprint = @as(u64, 20),
        .treaty_fingerprint = @as(u64, 21),
        .request_envelope_fingerprint = @as(u64, 22),
        .response_envelope_fingerprint = @as(u64, 23),
        .provider_fingerprint = @as(u64, 24),
        .capability_fingerprint = @as(u64, 25),
        .route_fingerprint = @as(u64, 26),
        .obligation_fingerprint = @as(?u64, 27),
    };
    const authorization_view = Evidence.authorizationViewForTreatyAuthorization(authorization);
    try std.testing.expectEqual(Evidence.domains.treaty_authorization.id, authorization_view.authorization_ref.domain_id);
    try std.testing.expectEqual(authorization.response_envelope_fingerprint, authorization_view.response_ref.?.fingerprint);

    const projection = Evidence.journalProjection(authorization_view.authorization_ref, "treaty_authorization_recorded", &.{authorization_view.response_ref.?}, "authorization recorded");
    try std.testing.expectEqualStrings("treaty_authorization_recorded", projection.suggested_event_kind);
    try std.testing.expectEqual(authorization.authorization_fingerprint, projection.evidence_ref.fingerprint);
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
