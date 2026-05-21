// zlinter-disable declaration_naming field_naming field_ordering max_positional_args no_inferred_error_unions no_literal_args no_undefined require_doc_comment
const std = @import("std");

/// Canonical registry entry for one versioned evidence or fingerprint family.
pub const Domain = struct {
    id: Id,
    name: []const u8,
    format_version: ?u32 = null,
    fingerprint_version: u32,
    owner: Owner,
    kind: Kind,
    stability: Stability = .deterministic_runtime,
    bytes_encoded: bool = false,
    stable_audit_metadata: bool = true,
    request_tokens_excluded: bool = true,
    runtime_identity_excluded: bool = true,
    journal_referenced: bool = false,
    certificate_referenced: bool = false,
    tests: []const u8 = "",

    pub const Id = enum {
        program_plan,
        session_trace,
        session_request,
        session_response,
        session_continuation,
        capsule,
        capsule_image,
        journal,
        journal_legacy_v4,
        journal_entry,
        exchange_manifest,
        exchange_request_envelope,
        exchange_response_envelope,
        provider_identity,
        provider_manifest,
        provider_offer,
        derived_provider_manifest,
        derived_provider_offer,
        provider_harness,
        provider_request_validation,
        provider_response_authorization,
        provider_journal_event,
        provider_program_execution,
        provider_program_mapping,
        provider_program_nested_request,
        morphism_offer,
        capability,
        capability_attenuation_path,
        route,
        authorization,
        authorization_result,
        effect_session_spec,
        capability_instance,
        obligation,
        obligation_transition,
        treaty,
        treaty_certificate,
        treaty_authorization,
        treaty_authorization_legacy_v3,
        treaty_authorization_legacy_v2,
        treaty_resolver,
        reinterpretation,
        residualization,
        residualization_report,
        pipeline,
        pipeline_certificate,
        pipeline_source_map,
        semantic_body,
        host_intrinsic,
        defunctionalization_report,
        defunctionalization_policy,
    };

    pub const Owner = enum {
        program_plan,
        session,
        capsule,
        journal,
        exchange,
        capability,
        linear_session,
        treaty,
        provider_harness,
        morphism,
        residualization,
        pipeline,
        semantic_boundary,
    };

    pub const Kind = enum {
        format,
        fingerprint,
        certificate,
        authorization,
        envelope,
        image,
        journal,
        blocker,
        report,
        derived_metadata,
    };

    pub const Stability = enum {
        in_process_only,
        deterministic_runtime,
        durable_bytes,
        host_owned_metadata,
    };
};

pub const domains = struct {
    pub const program_plan = Domain{ .id = .program_plan, .name = "boundary.program.plan", .fingerprint_version = 1, .owner = .program_plan, .kind = .fingerprint, .tests = "program plan" };
    pub const session_trace = Domain{ .id = .session_trace, .name = "boundary.session.trace", .fingerprint_version = 2, .owner = .session, .kind = .fingerprint, .journal_referenced = true, .certificate_referenced = true, .tests = "trace" };
    pub const session_request = Domain{ .id = .session_request, .name = "boundary.session.request", .fingerprint_version = 2, .owner = .session, .kind = .fingerprint, .journal_referenced = true, .certificate_referenced = true, .tests = "request" };
    pub const session_response = Domain{ .id = .session_response, .name = "boundary.session.response", .fingerprint_version = 2, .owner = .session, .kind = .fingerprint, .journal_referenced = true, .certificate_referenced = true, .tests = "response" };
    pub const session_continuation = Domain{ .id = .session_continuation, .name = "boundary.session.continuation", .fingerprint_version = 2, .owner = .session, .kind = .fingerprint, .journal_referenced = true, .certificate_referenced = true, .tests = "continuation" };
    pub const capsule = Domain{ .id = .capsule, .name = "boundary.session.capsule", .fingerprint_version = 2, .owner = .capsule, .kind = .fingerprint, .journal_referenced = true, .certificate_referenced = true, .tests = "capsule" };
    pub const capsule_image = Domain{ .id = .capsule_image, .name = "boundary.program.capsule.image", .format_version = 1, .fingerprint_version = 1, .owner = .capsule, .kind = .image, .stability = .durable_bytes, .bytes_encoded = true, .journal_referenced = true, .certificate_referenced = true, .tests = "capsule image" };
    pub const journal = Domain{ .id = .journal, .name = "boundary.program.session.journal", .format_version = 6, .fingerprint_version = 1, .owner = .journal, .kind = .journal, .stability = .durable_bytes, .bytes_encoded = true, .stable_audit_metadata = true, .tests = "journal" };
    pub const journal_legacy_v4 = Domain{ .id = .journal_legacy_v4, .name = "boundary.program.session.journal.v4", .format_version = 4, .fingerprint_version = 1, .owner = .journal, .kind = .journal, .stability = .durable_bytes, .bytes_encoded = true, .tests = "legacy journal" };
    pub const journal_entry = Domain{ .id = .journal_entry, .name = "boundary.session.journal.entry", .format_version = 6, .fingerprint_version = 1, .owner = .journal, .kind = .journal, .stability = .durable_bytes, .bytes_encoded = true, .journal_referenced = true, .tests = "journal entry" };
    pub const exchange_manifest = Domain{ .id = .exchange_manifest, .name = "boundary.exchange.manifest", .format_version = 1, .fingerprint_version = 1, .owner = .exchange, .kind = .format, .stability = .durable_bytes, .bytes_encoded = true, .journal_referenced = true, .certificate_referenced = true, .tests = "exchange manifest" };
    pub const exchange_request_envelope = Domain{ .id = .exchange_request_envelope, .name = "boundary.exchange.request", .format_version = 3, .fingerprint_version = 3, .owner = .exchange, .kind = .envelope, .stability = .durable_bytes, .bytes_encoded = true, .journal_referenced = true, .certificate_referenced = true, .tests = "exchange request" };
    pub const exchange_response_envelope = Domain{ .id = .exchange_response_envelope, .name = "boundary.exchange.response", .format_version = 1, .fingerprint_version = 1, .owner = .exchange, .kind = .envelope, .stability = .durable_bytes, .bytes_encoded = true, .journal_referenced = true, .certificate_referenced = true, .tests = "exchange response" };
    pub const provider_identity = Domain{ .id = .provider_identity, .name = "boundary.exchange.provider.identity", .fingerprint_version = 1, .owner = .exchange, .kind = .fingerprint, .journal_referenced = true, .certificate_referenced = true, .tests = "provider identity" };
    pub const provider_manifest = Domain{ .id = .provider_manifest, .name = "boundary.exchange.provider", .format_version = 2, .fingerprint_version = 2, .owner = .exchange, .kind = .format, .stability = .durable_bytes, .bytes_encoded = true, .journal_referenced = true, .certificate_referenced = true, .tests = "provider manifest" };
    pub const provider_offer = Domain{ .id = .provider_offer, .name = "boundary.exchange.provider_offer", .format_version = 1, .fingerprint_version = 1, .owner = .provider_harness, .kind = .derived_metadata, .stability = .durable_bytes, .bytes_encoded = true, .journal_referenced = true, .certificate_referenced = true, .tests = "provider offer" };
    pub const derived_provider_manifest = Domain{ .id = .derived_provider_manifest, .name = "boundary.exchange.provider.derived_manifest", .format_version = 1, .fingerprint_version = 1, .owner = .provider_harness, .kind = .derived_metadata, .stability = .durable_bytes, .bytes_encoded = true, .journal_referenced = true, .certificate_referenced = true, .tests = "derived provider manifest" };
    pub const derived_provider_offer = Domain{ .id = .derived_provider_offer, .name = "boundary.exchange.provider.derived_offer", .format_version = 1, .fingerprint_version = 1, .owner = .provider_harness, .kind = .derived_metadata, .stability = .durable_bytes, .bytes_encoded = true, .journal_referenced = true, .certificate_referenced = true, .tests = "derived offer" };
    pub const provider_harness = Domain{ .id = .provider_harness, .name = "boundary.exchange.provider.harness", .fingerprint_version = 1, .owner = .provider_harness, .kind = .derived_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "provider harness" };
    pub const provider_request_validation = Domain{ .id = .provider_request_validation, .name = "boundary.exchange.provider.request_validation", .fingerprint_version = 1, .owner = .provider_harness, .kind = .report, .journal_referenced = true, .certificate_referenced = true, .tests = "provider request" };
    pub const provider_response_authorization = Domain{ .id = .provider_response_authorization, .name = "boundary.exchange.provider.response_authorization", .fingerprint_version = 1, .owner = .provider_harness, .kind = .authorization, .journal_referenced = true, .certificate_referenced = true, .tests = "provider outcome" };
    pub const provider_journal_event = Domain{ .id = .provider_journal_event, .name = "boundary.exchange.provider.journal_event", .format_version = 6, .fingerprint_version = 1, .owner = .provider_harness, .kind = .journal, .stability = .durable_bytes, .bytes_encoded = true, .journal_referenced = true, .tests = "provider journal" };
    pub const provider_program_execution = Domain{ .id = .provider_program_execution, .name = "boundary.exchange.provider_program.execution", .fingerprint_version = 1, .owner = .provider_harness, .kind = .derived_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "provider program" };
    pub const provider_program_mapping = Domain{ .id = .provider_program_mapping, .name = "boundary.exchange.provider_program.mapping", .fingerprint_version = 1, .owner = .provider_harness, .kind = .derived_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "program provider" };
    pub const provider_program_nested_request = Domain{ .id = .provider_program_nested_request, .name = "boundary.exchange.provider_program.nested_request", .fingerprint_version = 1, .owner = .provider_harness, .kind = .derived_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "nested provider" };
    pub const morphism_offer = Domain{ .id = .morphism_offer, .name = "boundary.exchange.morphism_offer", .fingerprint_version = 1, .owner = .morphism, .kind = .derived_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "morphism offer" };
    pub const capability = Domain{ .id = .capability, .name = "boundary.exchange.capability", .format_version = 1, .fingerprint_version = 1, .owner = .capability, .kind = .format, .stability = .durable_bytes, .bytes_encoded = true, .journal_referenced = true, .certificate_referenced = true, .tests = "capability" };
    pub const capability_attenuation_path = Domain{ .id = .capability_attenuation_path, .name = "boundary.exchange.capability.path", .fingerprint_version = 1, .owner = .capability, .kind = .fingerprint, .journal_referenced = true, .certificate_referenced = true, .tests = "capability attenuation" };
    pub const route = Domain{ .id = .route, .name = "boundary.exchange.route", .fingerprint_version = 1, .owner = .capability, .kind = .fingerprint, .journal_referenced = true, .certificate_referenced = true, .tests = "route" };
    pub const authorization = Domain{ .id = .authorization, .name = "boundary.exchange.authorization", .format_version = 1, .fingerprint_version = 1, .owner = .capability, .kind = .authorization, .stability = .durable_bytes, .bytes_encoded = true, .journal_referenced = true, .certificate_referenced = true, .tests = "authorization" };
    pub const authorization_result = Domain{ .id = .authorization_result, .name = "boundary.exchange.authorization.result", .fingerprint_version = 1, .owner = .linear_session, .kind = .authorization, .journal_referenced = true, .certificate_referenced = true, .tests = "authorization" };
    pub const effect_session_spec = Domain{ .id = .effect_session_spec, .name = "boundary.exchange.effect_session", .format_version = 1, .fingerprint_version = 1, .owner = .linear_session, .kind = .format, .stability = .durable_bytes, .bytes_encoded = true, .certificate_referenced = true, .tests = "linear" };
    pub const capability_instance = Domain{ .id = .capability_instance, .name = "boundary.exchange.capability_instance", .format_version = 1, .fingerprint_version = 1, .owner = .linear_session, .kind = .format, .stability = .durable_bytes, .bytes_encoded = true, .journal_referenced = true, .certificate_referenced = true, .tests = "capability instance" };
    pub const obligation = Domain{ .id = .obligation, .name = "boundary.exchange.obligation", .format_version = 1, .fingerprint_version = 1, .owner = .linear_session, .kind = .format, .stability = .durable_bytes, .bytes_encoded = true, .journal_referenced = true, .certificate_referenced = true, .tests = "obligation" };
    pub const obligation_transition = Domain{ .id = .obligation_transition, .name = "boundary.exchange.obligation.transition", .fingerprint_version = 1, .owner = .linear_session, .kind = .fingerprint, .journal_referenced = true, .certificate_referenced = true, .tests = "obligation transition" };
    pub const treaty = Domain{ .id = .treaty, .name = "boundary.exchange.treaty", .format_version = 1, .fingerprint_version = 4, .owner = .treaty, .kind = .certificate, .stable_audit_metadata = true, .journal_referenced = true, .certificate_referenced = true, .tests = "treaty" };
    pub const treaty_certificate = Domain{ .id = .treaty_certificate, .name = "boundary.exchange.treaty.certificate", .format_version = 1, .fingerprint_version = 4, .owner = .treaty, .kind = .certificate, .stable_audit_metadata = true, .journal_referenced = true, .certificate_referenced = true, .tests = "certificate" };
    pub const treaty_authorization = Domain{ .id = .treaty_authorization, .name = "boundary.exchange.treaty.authorization", .format_version = 4, .fingerprint_version = 4, .owner = .treaty, .kind = .authorization, .stability = .durable_bytes, .bytes_encoded = true, .stable_audit_metadata = true, .journal_referenced = true, .certificate_referenced = true, .tests = "authorization" };
    pub const treaty_authorization_legacy_v3 = Domain{ .id = .treaty_authorization_legacy_v3, .name = "boundary.exchange.treaty.authorization.v3", .format_version = 3, .fingerprint_version = 3, .owner = .treaty, .kind = .authorization, .stability = .durable_bytes, .bytes_encoded = true, .stable_audit_metadata = true, .journal_referenced = true, .certificate_referenced = true, .tests = "legacy authorization" };
    pub const treaty_authorization_legacy_v2 = Domain{ .id = .treaty_authorization_legacy_v2, .name = "boundary.exchange.treaty.authorization.v2", .format_version = 2, .fingerprint_version = 2, .owner = .treaty, .kind = .authorization, .stability = .durable_bytes, .bytes_encoded = true, .stable_audit_metadata = true, .journal_referenced = true, .certificate_referenced = true, .tests = "legacy authorization" };
    pub const treaty_resolver = Domain{ .id = .treaty_resolver, .name = "boundary.exchange.treaty.resolver", .fingerprint_version = 1, .owner = .treaty, .kind = .report, .journal_referenced = true, .certificate_referenced = true, .tests = "resolver" };
    pub const reinterpretation = Domain{ .id = .reinterpretation, .name = "boundary.session.reinterpret", .fingerprint_version = 2, .owner = .morphism, .kind = .fingerprint, .journal_referenced = true, .certificate_referenced = true, .tests = "reinterpretation" };
    pub const residualization = Domain{ .id = .residualization, .name = "boundary.program.residualization", .fingerprint_version = 1, .owner = .residualization, .kind = .fingerprint, .certificate_referenced = true, .tests = "residual" };
    pub const residualization_report = Domain{ .id = .residualization_report, .name = "boundary.program.residualization.report", .fingerprint_version = 1, .owner = .residualization, .kind = .report, .certificate_referenced = true, .tests = "residual" };
    pub const pipeline = Domain{ .id = .pipeline, .name = "boundary.program.pipeline", .fingerprint_version = 1, .owner = .pipeline, .kind = .fingerprint, .certificate_referenced = true, .tests = "pipeline" };
    pub const pipeline_certificate = Domain{ .id = .pipeline_certificate, .name = "boundary.program.pipeline.certificate", .fingerprint_version = 1, .owner = .pipeline, .kind = .certificate, .certificate_referenced = true, .tests = "pipeline certificate" };
    pub const pipeline_source_map = Domain{ .id = .pipeline_source_map, .name = "boundary.program.pipeline.source_map", .fingerprint_version = 1, .owner = .pipeline, .kind = .derived_metadata, .certificate_referenced = true, .tests = "source map" };
    pub const semantic_body = Domain{ .id = .semantic_body, .name = "boundary.evidence.semantic_body", .fingerprint_version = 1, .owner = .semantic_boundary, .kind = .derived_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "semantic body" };
    pub const host_intrinsic = Domain{ .id = .host_intrinsic, .name = "boundary.evidence.host_intrinsic", .format_version = 1, .fingerprint_version = 1, .owner = .semantic_boundary, .kind = .derived_metadata, .stability = .host_owned_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "host intrinsic" };
    pub const defunctionalization_report = Domain{ .id = .defunctionalization_report, .name = "boundary.evidence.defunctionalization_report", .fingerprint_version = 1, .owner = .semantic_boundary, .kind = .report, .journal_referenced = true, .certificate_referenced = true, .tests = "defunctionalization" };
    pub const defunctionalization_policy = Domain{ .id = .defunctionalization_policy, .name = "boundary.evidence.defunctionalization_policy", .fingerprint_version = 1, .owner = .semantic_boundary, .kind = .fingerprint, .journal_referenced = true, .certificate_referenced = true, .tests = "intrinsic allowlist" };
};

pub const all_domains = &[_]Domain{
    domains.program_plan,
    domains.session_trace,
    domains.session_request,
    domains.session_response,
    domains.session_continuation,
    domains.capsule,
    domains.capsule_image,
    domains.journal,
    domains.journal_legacy_v4,
    domains.journal_entry,
    domains.exchange_manifest,
    domains.exchange_request_envelope,
    domains.exchange_response_envelope,
    domains.provider_identity,
    domains.provider_manifest,
    domains.provider_offer,
    domains.derived_provider_manifest,
    domains.derived_provider_offer,
    domains.provider_harness,
    domains.provider_request_validation,
    domains.provider_response_authorization,
    domains.provider_journal_event,
    domains.provider_program_execution,
    domains.provider_program_mapping,
    domains.provider_program_nested_request,
    domains.morphism_offer,
    domains.capability,
    domains.capability_attenuation_path,
    domains.route,
    domains.authorization,
    domains.authorization_result,
    domains.effect_session_spec,
    domains.capability_instance,
    domains.obligation,
    domains.obligation_transition,
    domains.treaty,
    domains.treaty_certificate,
    domains.treaty_authorization,
    domains.treaty_authorization_legacy_v3,
    domains.treaty_authorization_legacy_v2,
    domains.treaty_resolver,
    domains.reinterpretation,
    domains.residualization,
    domains.residualization_report,
    domains.pipeline,
    domains.pipeline_certificate,
    domains.pipeline_source_map,
    domains.semantic_body,
    domains.host_intrinsic,
    domains.defunctionalization_report,
    domains.defunctionalization_policy,
};

pub fn domainById(id: Domain.Id) ?Domain {
    for (all_domains) |domain| {
        if (domain.id == id) return domain;
    }
    return null;
}

pub fn domainByName(name: []const u8) ?Domain {
    for (all_domains) |domain| {
        if (std.mem.eql(u8, domain.name, name)) return domain;
    }
    return null;
}

pub const RegistryError = error{
    DuplicateDomainId,
    DuplicateDomainName,
    DurableBytesMissingFormatVersion,
    FingerprintedDomainMissingVersion,
    MissingDomain,
};

pub fn validateRegistry() RegistryError!void {
    for (all_domains, 0..) |domain, i| {
        if (domain.name.len == 0) return error.MissingDomain;
        if (domain.fingerprint_version == 0) return error.FingerprintedDomainMissingVersion;
        if ((domain.bytes_encoded or domain.stability == .durable_bytes) and domain.format_version == null) return error.DurableBytesMissingFormatVersion;
        for (all_domains[i + 1 ..]) |other| {
            if (domain.id == other.id) return error.DuplicateDomainId;
            if (std.mem.eql(u8, domain.name, other.name)) return error.DuplicateDomainName;
        }
    }
}

pub const Ref = struct {
    domain_id: Domain.Id,
    fingerprint: u64,
    format_version: ?u32 = null,
    label: ?[]const u8 = null,
    branch_id: ?u64 = null,
    site_index: ?usize = null,
    kind_tag: ?[]const u8 = null,

    pub fn eql(self: @This(), other: @This()) bool {
        return self.domain_id == other.domain_id and
            self.fingerprint == other.fingerprint and
            self.format_version == other.format_version and
            optionalBytesEqual(self.label, other.label) and
            self.branch_id == other.branch_id and
            self.site_index == other.site_index and
            optionalBytesEqual(self.kind_tag, other.kind_tag);
    }
};

pub const RefOptions = struct {
    format_version: ?u32 = null,
    label: ?[]const u8 = null,
    branch_id: ?u64 = null,
    site_index: ?usize = null,
    kind_tag: ?[]const u8 = null,
};

pub fn refFor(domain: Domain, fingerprint: u64, options: RefOptions) Ref {
    return .{
        .domain_id = domain.id,
        .fingerprint = fingerprint,
        .format_version = options.format_version orelse domain.format_version,
        .label = options.label,
        .branch_id = options.branch_id,
        .site_index = options.site_index,
        .kind_tag = options.kind_tag,
    };
}

pub fn refForRequestEnvelope(envelope: anytype) Ref {
    return refFor(domains.exchange_request_envelope, envelope.fingerprint, .{
        .format_version = if (comptime @hasField(@TypeOf(envelope), "request_format_version")) envelope.request_format_version else domains.exchange_request_envelope.format_version,
        .label = optionalLabel(envelope, "name"),
        .site_index = optionalUsizeField(envelope, "site_index"),
        .kind_tag = if (comptime @hasField(@TypeOf(envelope), "kind")) @tagName(envelope.kind) else null,
    });
}

pub fn refForResponseEnvelope(envelope: anytype) Ref {
    return refFor(domains.exchange_response_envelope, envelope.fingerprint, .{
        .label = if (comptime @hasField(@TypeOf(envelope), "kind")) @tagName(envelope.kind) else null,
        .kind_tag = if (comptime @hasField(@TypeOf(envelope), "kind")) @tagName(envelope.kind) else null,
    });
}

pub fn refForProviderManifest(manifest: anytype) Ref {
    return refFor(domains.provider_manifest, manifest.fingerprint, .{
        .format_version = if (comptime @hasField(@TypeOf(manifest), "format_version")) manifest.format_version else domains.provider_manifest.format_version,
        .label = optionalLabel(manifest, "label"),
    });
}

pub fn refForProviderIdentity(fingerprint: u64) Ref {
    return refFor(domains.provider_identity, fingerprint, .{});
}

pub fn refForProviderOffer(offer: anytype) Ref {
    return refFor(domains.provider_offer, offer.fingerprint, .{
        .format_version = if (comptime @hasField(@TypeOf(offer), "format_version")) offer.format_version else domains.provider_offer.format_version,
        .label = optionalLabel(offer, "label"),
    });
}

pub fn refForDerivedProviderOffer(offer: anytype) Ref {
    const base = refForProviderOffer(offer);
    return .{
        .domain_id = domains.derived_provider_offer.id,
        .fingerprint = base.fingerprint,
        .format_version = domains.derived_provider_offer.format_version,
        .label = base.label,
        .branch_id = base.branch_id,
        .site_index = base.site_index,
        .kind_tag = base.kind_tag,
    };
}

pub fn refForProviderHarness(comptime Harness: type) Ref {
    return refFor(domains.provider_harness, comptime fingerprintProviderHarness(Harness), .{
        .label = if (@hasDecl(Harness, "provider_label_text")) Harness.provider_label_text else null,
    });
}

pub fn refForProviderProgramExecution(execution: anytype) Ref {
    return refFor(domains.provider_program_execution, execution.execution_fingerprint, .{
        .label = optionalLabel(execution, "handler_program_label"),
        .branch_id = optionalU64Field(execution, "branch_id"),
    });
}

pub fn refForProviderProgramMapping(fingerprint: u64) Ref {
    return refFor(domains.provider_program_mapping, fingerprint, .{});
}

pub fn refForProviderProgramNestedRequest(fingerprint: u64) Ref {
    return refFor(domains.provider_program_nested_request, fingerprint, .{});
}

pub fn refForCapability(capability: anytype) Ref {
    return refFor(domains.capability, capability.fingerprint, .{ .label = optionalLabel(capability, "label") });
}

pub fn refForRoute(route: anytype) Ref {
    return refFor(domains.route, route.fingerprint, .{ .kind_tag = if (comptime @hasField(@TypeOf(route), "kind")) @tagName(route.kind) else null });
}

pub fn refForAuthorization(authorization: anytype) Ref {
    return refFor(domains.authorization, authorization.authorization_fingerprint, .{});
}

pub fn refForAuthorizationResult(result: anytype) Ref {
    return refFor(domains.authorization_result, result.result_fingerprint, .{});
}

pub fn refForObligation(obligation: anytype) Ref {
    return refFor(domains.obligation, obligation.obligation_fingerprint, .{});
}

pub fn refForObligationTransition(transition: anytype) Ref {
    return refFor(domains.obligation_transition, transition.transition_fingerprint, .{});
}

pub fn refForTreaty(treaty: anytype) Ref {
    return refFor(domains.treaty, treaty.fingerprint, .{});
}

pub fn refForTreatyCertificate(certificate: anytype) Ref {
    return refFor(domains.treaty_certificate, certificate.certificate_fingerprint, .{});
}

pub fn refForTreatyAuthorization(authorization: anytype) Ref {
    const format_version = if (comptime @hasField(@TypeOf(authorization), "format_version")) authorization.format_version else domains.treaty_authorization.format_version.?;
    const domain = if (format_version == domains.treaty_authorization_legacy_v2.format_version.?)
        domains.treaty_authorization_legacy_v2
    else if (format_version == domains.treaty_authorization_legacy_v3.format_version.?)
        domains.treaty_authorization_legacy_v3
    else
        domains.treaty_authorization;
    return refFor(domain, authorization.authorization_fingerprint, .{ .format_version = format_version });
}

pub fn refForJournalEntry(entry_fingerprint: u64, site_index: ?usize, kind_tag: ?[]const u8) Ref {
    return refFor(domains.journal_entry, entry_fingerprint, .{ .site_index = site_index, .kind_tag = kind_tag });
}

pub fn refForPipelineCertificate(certificate: anytype) Ref {
    return refFor(domains.pipeline_certificate, certificate.pipeline_fingerprint, .{ .label = optionalLabel(certificate, "pipeline_label") });
}

pub fn refForResidualizationReport(comptime ReportType: type) Ref {
    return refFor(domains.residualization_report, ReportType.fingerprint, .{ .label = if (@hasDecl(ReportType, "program_label")) ReportType.program_label else null });
}

pub fn fingerprintProviderHarness(comptime Harness: type) u64 {
    @setEvalBranchQuota(10_000);
    var builder = FingerprintBuilder.init(domains.provider_harness);
    if (comptime @hasDecl(Harness, "provider_label_text")) builder.fieldBytes("provider.label", Harness.provider_label_text);
    if (comptime @hasDecl(Harness, "provider_fingerprint")) builder.fieldU64("provider.fingerprint", Harness.provider_fingerprint);
    if (comptime @hasDecl(Harness, "offer_count")) builder.fieldUsize("offer.count", Harness.offer_count);
    if (comptime @hasDecl(Harness, "handled_operation_site_count")) builder.fieldUsize("operation.count", Harness.handled_operation_site_count);
    if (comptime @hasDecl(Harness, "handled_after_site_count")) builder.fieldUsize("after.count", Harness.handled_after_site_count);
    if (comptime @hasDecl(Harness, "supported_operation_sites")) {
        for (Harness.supported_operation_sites) |site_index| builder.fieldUsize("operation.site", site_index);
    }
    if (comptime @hasDecl(Harness, "supported_after_sites")) {
        for (Harness.supported_after_sites) |site_index| builder.fieldUsize("after.site", site_index);
    }
    if (comptime @hasDecl(Harness, "supported_protocol_labels")) {
        for (Harness.supported_protocol_labels) |protocol_label| builder.fieldBytes("protocol.label", protocol_label);
    }
    if (comptime @hasDecl(Harness, "supported_protocol_op_fingerprints")) {
        for (Harness.supported_protocol_op_fingerprints) |fingerprint| builder.fieldU64("protocol.op", fingerprint);
    }
    fingerprintProviderHarnessManifestOptions(&builder, Harness);
    if (comptime @hasDecl(Harness, "declarations")) {
        inline for (Harness.declarations) |Entry| fingerprintProviderHarnessDeclaration(&builder, Entry);
    }
    return builder.finish();
}

fn fingerprintProviderHarnessManifestOptions(builder: *FingerprintBuilder, comptime Harness: type) void {
    if (comptime @hasDecl(Harness, "manifest_allowed_response_kinds")) {
        fingerprintResponseKindSet(builder, "manifest.response_kinds", Harness.manifest_allowed_response_kinds);
    }
    if (comptime @hasDecl(Harness, "manifest_max_request_envelope_bytes")) {
        builder.fieldUsize("manifest.max_request", Harness.manifest_max_request_envelope_bytes);
    }
    if (comptime @hasDecl(Harness, "manifest_max_response_envelope_bytes")) {
        builder.fieldUsize("manifest.max_response", Harness.manifest_max_response_envelope_bytes);
    }
    if (comptime @hasDecl(Harness, "manifest_accepts_embedded_capsules")) {
        builder.fieldBool("manifest.accepts_embedded_capsules", Harness.manifest_accepts_embedded_capsules);
    }
    if (comptime @hasDecl(Harness, "manifest_accepts_capsule_restore")) {
        builder.fieldBool("manifest.accepts_capsule_restore", Harness.manifest_accepts_capsule_restore);
    }
    if (comptime @hasDecl(Harness, "manifest_semantic_tags")) {
        for (Harness.manifest_semantic_tags) |tag| builder.fieldBytes("manifest.semantic_tag", tag);
    }
    if (comptime @hasDecl(Harness, "manifest_metadata")) {
        builder.fieldBytes("manifest.metadata", Harness.manifest_metadata);
    }
}

fn fingerprintProviderHarnessDeclaration(builder: *FingerprintBuilder, comptime Entry: type) void {
    builder.fieldBytes("declaration.kind", @tagName(Entry.kind));
    if (comptime @hasDecl(Entry, "program_backed")) builder.fieldBool("declaration.program_backed", Entry.program_backed);
    if (comptime @hasDecl(Entry, "provider_program_mapping_fingerprint")) {
        builder.fieldU64("declaration.provider_program_mapping", Entry.provider_program_mapping_fingerprint);
    }
    if (comptime @hasDecl(Entry, "Site")) {
        const Site = Entry.Site;
        if (comptime @hasDecl(Site, "index")) builder.fieldUsize("declaration.site.index", Site.index);
        if (comptime @hasDecl(Site, "fingerprint")) builder.fieldU64("declaration.site.fingerprint", Site.fingerprint);
        if (comptime @hasDecl(Site, "source_operation_site_fingerprint")) builder.fieldU64("declaration.site.source", Site.source_operation_site_fingerprint);
        if (comptime @hasDecl(Site, "requirement_label")) builder.fieldBytes("declaration.site.requirement", Site.requirement_label);
        if (comptime @hasDecl(Site, "original_requirement_label")) builder.fieldBytes("declaration.site.original_requirement", Site.original_requirement_label);
        if (comptime @hasDecl(Site, "op_name")) builder.fieldBytes("declaration.site.op", Site.op_name);
        if (comptime @hasDecl(Site, "original_op_name")) builder.fieldBytes("declaration.site.original_op", Site.original_op_name);
    }
    if (comptime @hasDecl(Entry, "offer_options")) fingerprintProviderHarnessOfferOptions(builder, Entry.offer_options);
}

fn fingerprintProviderHarnessOfferOptions(builder: *FingerprintBuilder, comptime options: anytype) void {
    builder.fieldOptionalBytes("offer.label", options.label);
    builder.fieldOptionalBytes("offer.protocol_label", options.protocol_label);
    builder.fieldOptionalU64("offer.protocol_op", options.protocol_op_fingerprint);
    builder.fieldBool("offer.response_kinds.present", options.allowed_response_kinds != null);
    if (options.allowed_response_kinds) |kinds| fingerprintResponseKindSet(builder, "offer.response_kinds", kinds);
    fingerprintUsageSet(builder, "offer.usage", options.supported_usage_modes);
    fingerprintResponseUseSet(builder, "offer.response_use", options.supported_response_uses);
    fingerprintResponseUseSet(builder, "offer.replay", options.supported_replay_policies);
    fingerprintBranchPolicySet(builder, "offer.branch", options.supported_branch_policies);
    builder.fieldBytes("offer.capsule_policy", @tagName(options.capsule_policy));
    builder.fieldBool("offer.opens_obligation", options.opens_obligation);
    builder.fieldUsize("offer.max_request", options.max_request_bytes);
    builder.fieldUsize("offer.max_response", options.max_response_bytes);
    builder.fieldUsize("offer.max_capsule", options.max_capsule_bytes);
    for (options.tags) |tag| builder.fieldBytes("offer.tag", tag);
    builder.fieldBytes("offer.metadata", options.metadata);
}

fn fingerprintResponseKindSet(builder: *FingerprintBuilder, comptime prefix: []const u8, set: anytype) void {
    builder.fieldBool(prefix ++ ".resume", set.@"resume");
    builder.fieldBool(prefix ++ ".return_now", set.return_now);
    builder.fieldBool(prefix ++ ".resume_after", set.resume_after);
}

fn fingerprintUsageSet(builder: *FingerprintBuilder, comptime prefix: []const u8, set: anytype) void {
    builder.fieldBool(prefix ++ ".copyable", set.copyable);
    builder.fieldBool(prefix ++ ".replayable", set.replayable);
    builder.fieldBool(prefix ++ ".affine", set.affine);
    builder.fieldBool(prefix ++ ".linear", set.linear);
    builder.fieldBool(prefix ++ ".ephemeral", set.ephemeral);
}

fn fingerprintResponseUseSet(builder: *FingerprintBuilder, comptime prefix: []const u8, set: anytype) void {
    builder.fieldBool(prefix ++ ".fresh", set.fresh);
    builder.fieldBool(prefix ++ ".replayed", set.replayed);
    builder.fieldBool(prefix ++ ".deterministic_replay", set.deterministic_replay);
    builder.fieldBool(prefix ++ ".override", set.override);
}

fn fingerprintBranchPolicySet(builder: *FingerprintBuilder, comptime prefix: []const u8, set: anytype) void {
    builder.fieldBool(prefix ++ ".unrestricted", set.unrestricted);
    builder.fieldBool(prefix ++ ".replay_only", set.replay_only);
    builder.fieldBool(prefix ++ ".single_live_branch", set.single_live_branch);
    builder.fieldBool(prefix ++ ".split_required", set.split_required);
    builder.fieldBool(prefix ++ ".no_branch", set.no_branch);
    builder.fieldBool(prefix ++ ".host_owned", set.host_owned);
}

pub const Role = enum {
    subject,
    parent,
    source,
    target,
    request,
    response,
    provider,
    provider_harness,
    offer,
    capability,
    attenuated_capability,
    route,
    authorization,
    effect_session,
    capability_instance,
    obligation,
    treaty,
    treaty_certificate,
    treaty_authorization,
    provider_request,
    provider_response_packet,
    morphism,
    pipeline,
    residual_program,
    journal_entry,
    capsule,
    capsule_image,
    source_site,
    residual_site,
    semantic_body,
    host_intrinsic,
    defunctionalization_report,
    defunctionalization_policy,
};

pub const Dependency = struct {
    role: Role,
    ref: Ref,
};

pub const DependencyGraph = struct {
    dependencies: []const Dependency,

    pub fn appendBounded(storage: []Dependency, len: *usize, dependency: Dependency) error{OutOfMemory}!void {
        if (len.* >= storage.len) return error.OutOfMemory;
        storage[len.*] = dependency;
        len.* += 1;
    }

    pub fn containsRole(self: @This(), role: Role) bool {
        for (self.dependencies) |dependency| {
            if (dependency.role == role) return true;
        }
        return false;
    }

    pub fn lookup(self: @This(), role: Role) ?Ref {
        for (self.dependencies) |dependency| {
            if (dependency.role == role) return dependency.ref;
        }
        return null;
    }

    pub fn hasDuplicate(self: @This()) bool {
        for (self.dependencies, 0..) |dependency, i| {
            for (self.dependencies[i + 1 ..]) |other| {
                if (dependency.role == other.role and dependency.ref.eql(other.ref)) return true;
            }
        }
        return false;
    }

    pub fn require(self: @This(), required_roles: []const Role) error{MissingDependency}!void {
        for (required_roles) |role| {
            if (!self.containsRole(role)) return error.MissingDependency;
        }
    }

    pub fn ordered(allocator: std.mem.Allocator, dependencies: []const Dependency) ![]Dependency {
        const copy = try allocator.dupe(Dependency, dependencies);
        std.sort.insertion(Dependency, copy, {}, dependencyLessThan);
        return copy;
    }

    pub fn fingerprint(self: @This(), allocator: std.mem.Allocator) !u64 {
        const sorted = try ordered(allocator, self.dependencies);
        defer allocator.free(sorted);
        return fingerprintSortedDependencies(sorted);
    }
};

pub const FingerprintBuilder = struct {
    domain: Domain,
    hasher: std.hash.Wyhash,

    pub fn init(domain: Domain) @This() {
        var self = @This(){ .domain = domain, .hasher = std.hash.Wyhash.init(0) };
        self.writeBytes("domain.name", domain.name);
        self.writeU32("domain.fingerprint_version", domain.fingerprint_version);
        return self;
    }

    pub fn fieldBytes(self: *@This(), field_label: []const u8, field_bytes: []const u8) void {
        self.writeBytes(field_label, field_bytes);
    }

    pub fn fieldU8(self: *@This(), field_label: []const u8, value: u8) void {
        self.writeLabel(field_label);
        self.hasher.update(&[_]u8{value});
    }

    pub fn fieldBool(self: *@This(), field_label: []const u8, value: bool) void {
        self.fieldU8(field_label, @intFromBool(value));
    }

    pub fn fieldU16(self: *@This(), field_label: []const u8, value: u16) void {
        self.writeLabel(field_label);
        var scalar_bytes: [2]u8 = undefined;
        std.mem.writeInt(u16, &scalar_bytes, value, .little);
        self.hasher.update(&scalar_bytes);
    }

    pub fn fieldU32(self: *@This(), field_label: []const u8, value: u32) void {
        self.writeU32(field_label, value);
    }

    pub fn fieldU64(self: *@This(), field_label: []const u8, value: u64) void {
        self.writeU64(field_label, value);
    }

    pub fn fieldUsize(self: *@This(), field_label: []const u8, value: usize) void {
        self.writeU64(field_label, @intCast(value));
    }

    pub fn fieldOptionalU64(self: *@This(), field_label: []const u8, value: ?u64) void {
        self.writeLabel(field_label);
        self.hasher.update(&[_]u8{@intFromBool(value != null)});
        if (value) |actual| self.rawU64(actual);
    }

    pub fn fieldOptionalBytes(self: *@This(), field_label: []const u8, maybe_bytes: ?[]const u8) void {
        self.writeLabel(field_label);
        self.hasher.update(&[_]u8{@intFromBool(maybe_bytes != null)});
        if (maybe_bytes) |present_bytes| self.rawBytes(present_bytes);
    }

    pub fn fieldRef(self: *@This(), field_label: []const u8, ref: Ref) void {
        self.writeLabel(field_label);
        self.rawRef(ref);
    }

    pub fn fieldOptionalRef(self: *@This(), field_label: []const u8, maybe_ref: ?Ref) void {
        self.writeLabel(field_label);
        self.hasher.update(&[_]u8{@intFromBool(maybe_ref != null)});
        if (maybe_ref) |ref| self.rawRef(ref);
    }

    pub fn fieldValueFingerprint(self: *@This(), field_label: []const u8, fingerprint: u64) void {
        self.fieldU64(field_label, fingerprint);
    }

    pub fn finish(self: *@This()) u64 {
        return self.hasher.final();
    }

    fn writeLabel(self: *@This(), value: []const u8) void {
        self.rawBytes(value);
    }

    fn writeBytes(self: *@This(), label_value: []const u8, value: []const u8) void {
        self.writeLabel(label_value);
        self.rawBytes(value);
    }

    fn writeU32(self: *@This(), label_value: []const u8, value: u32) void {
        self.writeLabel(label_value);
        var scalar_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &scalar_bytes, value, .little);
        self.hasher.update(&scalar_bytes);
    }

    fn writeU64(self: *@This(), label_value: []const u8, value: u64) void {
        self.writeLabel(label_value);
        self.rawU64(value);
    }

    fn rawBytes(self: *@This(), raw_bytes: []const u8) void {
        self.rawU64(raw_bytes.len);
        self.hasher.update(raw_bytes);
    }

    fn rawU64(self: *@This(), value: u64) void {
        var scalar_bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &scalar_bytes, value, .little);
        self.hasher.update(&scalar_bytes);
    }

    fn rawRef(self: *@This(), ref: Ref) void {
        self.rawBytes(@tagName(ref.domain_id));
        self.rawU64(ref.fingerprint);
        self.fieldOptionalU64("ref.format_version", if (ref.format_version) |value| @as(u64, value) else null);
        self.fieldOptionalBytes("ref.label", ref.label);
        self.fieldOptionalU64("ref.branch_id", ref.branch_id);
        self.fieldOptionalU64("ref.site_index", if (ref.site_index) |value| @as(u64, @intCast(value)) else null);
        self.fieldOptionalBytes("ref.kind_tag", ref.kind_tag);
    }
};

pub const Severity = enum { @"error", warning, info };

pub const SourceSubsystem = enum {
    session,
    capsule,
    journal,
    exchange,
    capability,
    linear_session,
    treaty,
    provider_harness,
    morphism,
    residualization,
    pipeline,
    semantic_boundary,
};

pub const Blocker = struct {
    domain: Domain.Id,
    tag: []const u8,
    severity: Severity = .@"error",
    subject: ?Ref = null,
    primary: ?Ref = null,
    related_refs: []const Ref = &.{},
    related_ref_storage: [6]Ref = undefined,
    related_ref_count: usize = 0,
    branch_id: ?u64 = null,
    site_index: ?usize = null,
    source_site_fingerprint: ?u64 = null,
    target_protocol_op_fingerprint: ?u64 = null,
    morphism_fingerprint: ?u64 = null,
    response_kind: ?[]const u8 = null,
    usage_mode: ?[]const u8 = null,
    short_code: []const u8 = "",
    summary: []const u8,
    source: SourceSubsystem,

    pub fn valid(self: @This()) bool {
        return self.tag.len != 0 and self.summary.len != 0 and self.short_code.len != 0;
    }

    pub fn relatedRefs(self: *const @This()) []const Ref {
        if (self.related_refs.len != 0) return self.related_refs;
        return self.related_ref_storage[0..self.related_ref_count];
    }

    pub fn fingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domainById(self.domain) orelse domains.exchange_manifest);
        builder.fieldBytes("tag", self.tag);
        builder.fieldBytes("severity", @tagName(self.severity));
        builder.fieldOptionalRef("subject", self.subject);
        builder.fieldOptionalRef("primary", self.primary);
        for (self.relatedRefs()) |related| builder.fieldRef("related", related);
        builder.fieldOptionalU64("branch", self.branch_id);
        builder.fieldOptionalU64("site", if (self.site_index) |site| @as(u64, @intCast(site)) else null);
        builder.fieldOptionalU64("source_site_fingerprint", self.source_site_fingerprint);
        builder.fieldOptionalU64("target_protocol_op_fingerprint", self.target_protocol_op_fingerprint);
        builder.fieldOptionalU64("morphism_fingerprint", self.morphism_fingerprint);
        builder.fieldOptionalBytes("response", self.response_kind);
        builder.fieldOptionalBytes("usage", self.usage_mode);
        builder.fieldBytes("code", self.short_code);
        builder.fieldBytes("summary", self.summary);
        builder.fieldBytes("source", @tagName(self.source));
        return builder.finish();
    }
};

pub const Report = struct {
    subject: Ref,
    report_domain: Domain.Id,
    dependencies: []const Dependency = &.{},
    blockers: []const Blocker = &.{},
    warnings: []const Blocker = &.{},
    success: bool,
    report_fingerprint: u64,
    truncated: bool = false,
    omitted_fingerprint: ?u64 = null,
    policy_fingerprint: ?u64 = null,
    summary: ?[]const u8 = null,

    pub fn ok(subject: Ref, report_domain: Domain.Id, dependencies: []const Dependency) @This() {
        const fingerprint = computeReportFingerprint(subject, report_domain, dependencies, &.{}, &.{}, true, false, null, null, null);
        return .{ .subject = subject, .report_domain = report_domain, .dependencies = dependencies, .success = true, .report_fingerprint = fingerprint };
    }

    pub fn withBlockers(subject: Ref, report_domain: Domain.Id, dependencies: []const Dependency, blockers: []const Blocker, warnings: []const Blocker, policy_fingerprint: ?u64, summary: ?[]const u8) @This() {
        const success = !hasErrorBlockers(blockers);
        return withStatus(subject, report_domain, dependencies, blockers, warnings, success, false, null, policy_fingerprint, summary);
    }

    pub fn withFailure(subject: Ref, report_domain: Domain.Id, dependencies: []const Dependency, blockers: []const Blocker, warnings: []const Blocker, policy_fingerprint: ?u64, summary: ?[]const u8) @This() {
        return withStatus(subject, report_domain, dependencies, blockers, warnings, false, false, null, policy_fingerprint, summary);
    }

    pub fn withIncompleteFailure(subject: Ref, report_domain: Domain.Id, dependencies: []const Dependency, blockers: []const Blocker, warnings: []const Blocker, omitted_fingerprint: u64, policy_fingerprint: ?u64, summary: ?[]const u8) @This() {
        return withStatus(subject, report_domain, dependencies, blockers, warnings, false, true, omitted_fingerprint, policy_fingerprint, summary);
    }

    fn withStatus(subject: Ref, report_domain: Domain.Id, dependencies: []const Dependency, blockers: []const Blocker, warnings: []const Blocker, success: bool, truncated: bool, omitted_fingerprint: ?u64, policy_fingerprint: ?u64, summary: ?[]const u8) @This() {
        return .{
            .subject = subject,
            .report_domain = report_domain,
            .dependencies = dependencies,
            .blockers = blockers,
            .warnings = warnings,
            .success = success,
            .report_fingerprint = computeReportFingerprint(subject, report_domain, dependencies, blockers, warnings, success, truncated, omitted_fingerprint, policy_fingerprint, summary),
            .truncated = truncated,
            .omitted_fingerprint = omitted_fingerprint,
            .policy_fingerprint = policy_fingerprint,
            .summary = summary,
        };
    }

    pub fn hasErrors(self: @This()) bool {
        return !self.success or self.truncated or hasErrorBlockers(self.blockers);
    }

    pub fn assertOk(self: @This()) error{EvidenceReportHasErrors}!void {
        if (!self.success or self.hasErrors()) return error.EvidenceReportHasErrors;
    }

    pub fn blockerCount(self: @This()) usize {
        return self.blockers.len;
    }

    pub fn dependencyFingerprint(self: @This(), allocator: std.mem.Allocator) !u64 {
        return (DependencyGraph{ .dependencies = self.dependencies }).fingerprint(allocator);
    }
};

pub const CertificateView = struct {
    certificate_ref: Ref,
    subject_ref: Ref,
    domain: Domain.Id,
    dependencies: []const Dependency = &.{},
    report_fingerprint: u64,
    policy_ref: ?Ref = null,
    policy_fingerprint: ?u64 = null,
    certificate_fingerprint: u64,
    summary: []const u8 = "",
};

pub const AuthorizationView = struct {
    authorization_ref: Ref,
    request_ref: ?Ref = null,
    response_ref: ?Ref = null,
    provider_ref: ?Ref = null,
    capability_ref: ?Ref = null,
    route_ref: ?Ref = null,
    treaty_ref: ?Ref = null,
    obligation_ref: ?Ref = null,
    authorization_fingerprint: u64,
    summary: []const u8 = "",
};

pub const JournalProjection = struct {
    evidence_ref: Ref,
    suggested_event_kind: []const u8,
    dependency_refs: []const Ref = &.{},
    summary_metadata: []const u8 = "",
    branch_id: ?u64 = null,
    event_payload_builder: ?*const fn () void = null,
};

pub const PolicySummary = struct {
    policy_domain: Domain.Id,
    policy_fingerprint: u64,
    policy_label: []const u8 = "",
    selected_enum_flags: []const []const u8 = &.{},
    byte_limits: []const usize = &.{},
    usage_modes: []const []const u8 = &.{},
    response_use_classes: []const []const u8 = &.{},
    branch_policies: []const []const u8 = &.{},
    replay_policies: []const []const u8 = &.{},
    summary_refs: []const Ref = &.{},

    pub fn fingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domainById(self.policy_domain) orelse domains.exchange_manifest);
        builder.fieldU64("policy.fingerprint", self.policy_fingerprint);
        builder.fieldBytes("policy.label", self.policy_label);
        for (self.selected_enum_flags) |value| builder.fieldBytes("flag", value);
        for (self.byte_limits) |value| builder.fieldUsize("byte.limit", value);
        for (self.usage_modes) |value| builder.fieldBytes("usage", value);
        for (self.response_use_classes) |value| builder.fieldBytes("response.use", value);
        for (self.branch_policies) |value| builder.fieldBytes("branch.policy", value);
        for (self.replay_policies) |value| builder.fieldBytes("replay.policy", value);
        for (self.summary_refs) |ref| builder.fieldRef("summary.ref", ref);
        return builder.finish();
    }
};

pub const SemanticBody = enum {
    boundary_program,
    declarative,
    residualized_program,
    pipeline,
    kernel_primitive,
    host_intrinsic,
    unknown,

    pub fn name(self: @This()) []const u8 {
        return @tagName(self);
    }

    pub fn isHostIntrinsic(self: @This()) bool {
        return self == .host_intrinsic;
    }

    pub fn isUnknown(self: @This()) bool {
        return self == .unknown;
    }

    pub fn isNonIntrinsic(self: @This()) bool {
        return switch (self) {
            .boundary_program, .declarative, .residualized_program, .pipeline, .kernel_primitive => true,
            .host_intrinsic, .unknown => false,
        };
    }

    pub fn fingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.semantic_body);
        builder.fieldBytes("semantic_body", @tagName(self));
        builder.fieldU8("semantic_body.ordinal", @intFromEnum(self));
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refFor(domains.semantic_body, self.fingerprint(), .{ .kind_tag = @tagName(self) });
    }
};

pub const HostIntrinsic = struct {
    format_version: u32 = 1,
    fingerprint_version: u32 = 1,
    fingerprint: u64,
    label: []const u8,
    kind: Kind,
    owner_subsystem: SourceSubsystem,
    allowed_protocol_labels: []const []const u8 = &.{},
    allowed_site_indexes: []const usize = &.{},
    allowed_after_site_indexes: []const usize = &.{},
    allowed_protocol_op_fingerprints: []const u64 = &.{},
    associated_provider_offer_ref: ?Ref = null,
    associated_provider_fingerprint: ?u64 = null,
    associated_manifest_fingerprint: ?u64 = null,
    provider_offer_policy_fingerprint: ?u64 = null,
    associated_capability_ref: ?Ref = null,
    associated_treaty_ref: ?Ref = null,
    associated_morphism_offer_ref: ?Ref = null,
    associated_handler_descriptor: ?[]const u8 = null,
    reason: []const u8 = "",
    stability: Stability = .host_owned,
    replay_policy_summary: []const u8 = "",
    usage_mode_summary: []const u8 = "",
    evidence_dependencies: []const Dependency = &.{},
    tags: []const []const u8 = &.{},
    metadata: []const u8 = &.{},

    pub const Kind = enum {
        provider_function,
        interpreter_function,
        run_handler_function,
        dynamic_morphism_mapper,
        host_tool,
        host_model,
        host_file,
        host_human,
        host_randomness,
        host_clock,
        test_fixture,
        foreign_system,
        unknown,
    };

    pub const Stability = enum {
        stable_declared,
        host_owned,
        test_only,
        unknown,
    };

    pub const Options = struct {
        label: []const u8,
        kind: Kind,
        owner_subsystem: SourceSubsystem,
        allowed_protocol_labels: []const []const u8 = &.{},
        allowed_site_indexes: []const usize = &.{},
        allowed_after_site_indexes: []const usize = &.{},
        allowed_protocol_op_fingerprints: []const u64 = &.{},
        associated_provider_offer_ref: ?Ref = null,
        associated_provider_fingerprint: ?u64 = null,
        associated_manifest_fingerprint: ?u64 = null,
        provider_offer_policy_fingerprint: ?u64 = null,
        associated_capability_ref: ?Ref = null,
        associated_treaty_ref: ?Ref = null,
        associated_morphism_offer_ref: ?Ref = null,
        associated_handler_descriptor: ?[]const u8 = null,
        reason: []const u8 = "",
        stability: Stability = .host_owned,
        replay_policy_summary: []const u8 = "",
        usage_mode_summary: []const u8 = "",
        evidence_dependencies: []const Dependency = &.{},
        tags: []const []const u8 = &.{},
        metadata: []const u8 = &.{},
    };

    pub fn init(options: Options) @This() {
        var value = @This(){
            .fingerprint = 0,
            .label = options.label,
            .kind = options.kind,
            .owner_subsystem = options.owner_subsystem,
            .allowed_protocol_labels = options.allowed_protocol_labels,
            .allowed_site_indexes = options.allowed_site_indexes,
            .allowed_after_site_indexes = options.allowed_after_site_indexes,
            .allowed_protocol_op_fingerprints = options.allowed_protocol_op_fingerprints,
            .associated_provider_offer_ref = options.associated_provider_offer_ref,
            .associated_provider_fingerprint = options.associated_provider_fingerprint,
            .associated_manifest_fingerprint = options.associated_manifest_fingerprint,
            .provider_offer_policy_fingerprint = options.provider_offer_policy_fingerprint,
            .associated_capability_ref = options.associated_capability_ref,
            .associated_treaty_ref = options.associated_treaty_ref,
            .associated_morphism_offer_ref = options.associated_morphism_offer_ref,
            .associated_handler_descriptor = options.associated_handler_descriptor,
            .reason = options.reason,
            .stability = options.stability,
            .replay_policy_summary = options.replay_policy_summary,
            .usage_mode_summary = options.usage_mode_summary,
            .evidence_dependencies = options.evidence_dependencies,
            .tags = options.tags,
            .metadata = options.metadata,
        };
        value.fingerprint = value.computeFingerprint();
        return value;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.host_intrinsic);
        builder.fieldU32("format_version", self.format_version);
        builder.fieldU32("fingerprint_version", self.fingerprint_version);
        builder.fieldBytes("label", self.label);
        builder.fieldBytes("kind", @tagName(self.kind));
        builder.fieldBytes("owner", @tagName(self.owner_subsystem));
        for (self.allowed_protocol_labels) |protocol_label| builder.fieldBytes("allowed_protocol", protocol_label);
        for (self.allowed_site_indexes) |site| builder.fieldUsize("allowed_site", site);
        for (self.allowed_after_site_indexes) |site| builder.fieldUsize("allowed_after_site", site);
        for (self.allowed_protocol_op_fingerprints) |op| builder.fieldU64("allowed_protocol_op", op);
        builder.fieldOptionalRef("provider_offer", self.associated_provider_offer_ref);
        builder.fieldOptionalU64("provider", self.associated_provider_fingerprint);
        builder.fieldOptionalU64("manifest", self.associated_manifest_fingerprint);
        builder.fieldOptionalU64("provider_offer_policy", self.provider_offer_policy_fingerprint);
        builder.fieldOptionalRef("capability", self.associated_capability_ref);
        builder.fieldOptionalRef("treaty", self.associated_treaty_ref);
        builder.fieldOptionalRef("morphism_offer", self.associated_morphism_offer_ref);
        builder.fieldOptionalBytes("handler_descriptor", self.associated_handler_descriptor);
        builder.fieldBytes("reason", self.reason);
        builder.fieldBytes("stability", @tagName(self.stability));
        builder.fieldBytes("replay_policy", self.replay_policy_summary);
        builder.fieldBytes("usage_mode", self.usage_mode_summary);
        for (self.evidence_dependencies) |dependency| {
            builder.fieldBytes("dependency.role", @tagName(dependency.role));
            builder.fieldRef("dependency.ref", dependency.ref);
        }
        for (self.tags) |tag| builder.fieldBytes("tag", tag);
        builder.fieldBytes("metadata", self.metadata);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refFor(domains.host_intrinsic, self.fingerprint, .{
            .format_version = self.format_version,
            .label = self.label,
            .kind_tag = @tagName(self.kind),
        });
    }

    pub fn journalProjection(self: @This(), event_kind: []const u8) JournalProjection {
        return .{
            .evidence_ref = self.evidenceRef(),
            .suggested_event_kind = event_kind,
            .summary_metadata = self.label,
        };
    }

    pub fn declaredProjection(self: @This()) JournalProjection {
        return self.journalProjection("intrinsic_declared");
    }

    pub fn usedProjection(self: @This()) JournalProjection {
        return self.journalProjection("intrinsic_used");
    }

    pub fn toEvidenceBlocker(self: @This(), tag: []const u8, summary: []const u8) Blocker {
        return .{
            .domain = domains.host_intrinsic.id,
            .tag = tag,
            .subject = self.evidenceRef(),
            .primary = self.associated_provider_offer_ref orelse self.associated_morphism_offer_ref orelse self.associated_treaty_ref,
            .short_code = tag,
            .summary = summary,
            .source = self.owner_subsystem,
        };
    }
};

pub const DefunctionalizationPolicy = struct {
    label: []const u8 = "permissive",
    allow_host_intrinsics: bool = true,
    allowed_intrinsic_fingerprints: []const u64 = &.{},
    allowed_intrinsic_kinds: []const HostIntrinsic.Kind = &.{},
    allowed_intrinsic_labels: []const []const u8 = &.{},
    reject_unknown: bool = false,
    reject_dynamic_mappers: bool = false,
    require_program_backed_providers: bool = false,
    require_declarative_morphisms: bool = false,
    require_no_intrinsics_in_treaties: bool = false,
    allow_test_fixtures: bool = false,
    allow_kernel_primitives: bool = true,
    prefer_boundary_program: bool = false,
    prefer_declarative: bool = false,
    prefer_residualized: bool = false,
    maximum_intrinsic_count: ?usize = null,

    pub fn strict() @This() {
        return .{
            .label = "strict",
            .allow_host_intrinsics = false,
            .reject_unknown = true,
            .reject_dynamic_mappers = true,
            .require_program_backed_providers = true,
            .require_declarative_morphisms = true,
            .require_no_intrinsics_in_treaties = true,
            .prefer_boundary_program = true,
            .prefer_declarative = true,
            .prefer_residualized = true,
            .maximum_intrinsic_count = 0,
        };
    }

    pub fn worldBoundary() @This() {
        return .{
            .label = "world_boundary",
            .allow_host_intrinsics = true,
            .reject_unknown = true,
            .prefer_boundary_program = true,
            .prefer_declarative = true,
            .prefer_residualized = true,
        };
    }

    pub fn testFixture() @This() {
        return .{
            .label = "test_fixture",
            .allow_host_intrinsics = true,
            .allowed_intrinsic_kinds = &.{.test_fixture},
            .reject_unknown = true,
            .allow_test_fixtures = true,
        };
    }

    pub fn permissive() @This() {
        return .{};
    }

    pub fn fingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.defunctionalization_policy);
        builder.fieldBytes("label", self.label);
        builder.fieldBool("allow_host_intrinsics", self.allow_host_intrinsics);
        for (self.allowed_intrinsic_fingerprints) |value| builder.fieldU64("allowed_intrinsic", value);
        for (self.allowed_intrinsic_kinds) |value| builder.fieldBytes("allowed_kind", @tagName(value));
        for (self.allowed_intrinsic_labels) |value| builder.fieldBytes("allowed_label", value);
        builder.fieldBool("reject_unknown", self.reject_unknown);
        builder.fieldBool("reject_dynamic_mappers", self.reject_dynamic_mappers);
        builder.fieldBool("require_program_backed_providers", self.require_program_backed_providers);
        builder.fieldBool("require_declarative_morphisms", self.require_declarative_morphisms);
        builder.fieldBool("require_no_intrinsics_in_treaties", self.require_no_intrinsics_in_treaties);
        builder.fieldBool("allow_test_fixtures", self.allow_test_fixtures);
        builder.fieldBool("allow_kernel_primitives", self.allow_kernel_primitives);
        builder.fieldBool("prefer_boundary_program", self.prefer_boundary_program);
        builder.fieldBool("prefer_declarative", self.prefer_declarative);
        builder.fieldBool("prefer_residualized", self.prefer_residualized);
        builder.fieldOptionalU64("maximum_intrinsic_count", if (self.maximum_intrinsic_count) |value| @as(u64, @intCast(value)) else null);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refFor(domains.defunctionalization_policy, self.fingerprint(), .{ .label = self.label });
    }

    pub fn policySummary(self: @This()) PolicySummary {
        return .{
            .policy_domain = domains.defunctionalization_policy.id,
            .policy_fingerprint = self.fingerprint(),
            .policy_label = self.label,
        };
    }

    pub fn allowsIntrinsic(self: @This(), intrinsic: HostIntrinsic) bool {
        if (!self.allow_host_intrinsics) return false;
        if (self.reject_dynamic_mappers and intrinsic.kind == .dynamic_morphism_mapper) return false;
        if (intrinsic.kind == .test_fixture and self.allow_test_fixtures) return true;
        for (self.allowed_intrinsic_fingerprints) |allowed| {
            if (allowed == intrinsic.fingerprint) return true;
        }
        for (self.allowed_intrinsic_kinds) |allowed| {
            if (allowed == intrinsic.kind) return true;
        }
        for (self.allowed_intrinsic_labels) |allowed| {
            if (std.mem.eql(u8, allowed, intrinsic.label)) return true;
        }
        return self.allowed_intrinsic_fingerprints.len == 0 and self.allowed_intrinsic_kinds.len == 0 and self.allowed_intrinsic_labels.len == 0;
    }

    pub fn allowsIntrinsicRef(self: @This(), intrinsic_ref: Ref) bool {
        return intrinsicRefAllowedByPolicy(intrinsic_ref, self);
    }
};

pub const DefunctionalizationReport = struct {
    scope_kind: ScopeKind,
    scope_ref: Ref,
    report_fingerprint: u64,
    total_bodies: usize = 0,
    boundary_program_count: usize = 0,
    declarative_count: usize = 0,
    residualized_program_count: usize = 0,
    pipeline_count: usize = 0,
    kernel_primitive_count: usize = 0,
    host_intrinsic_count: usize = 0,
    unknown_count: usize = 0,
    intrinsic_refs: []const Ref = &.{},
    unknown_refs: []const Ref = &.{},
    dependencies: []const Dependency = &.{},
    blockers: []const Blocker = &.{},
    primary_intrinsic_ref: ?Ref = null,
    secondary_intrinsic_ref: ?Ref = null,
    policy_summary: ?PolicySummary = null,
    summary: []const u8 = "",

    pub const ScopeKind = enum {
        program,
        provider_harness,
        provider_offer,
        treaty,
        treaty_resolver_result,
        interpreter,
        run_handler_set,
        morphism_offer,
        pipeline,
        journal,
        catalog,
    };

    pub const Counts = struct {
        boundary_program: usize = 0,
        declarative: usize = 0,
        residualized_program: usize = 0,
        pipeline: usize = 0,
        kernel_primitive: usize = 0,
        host_intrinsic: usize = 0,
        unknown: usize = 0,

        pub fn fromBody(body: SemanticBody) @This() {
            var counts: @This() = .{};
            switch (body) {
                .boundary_program => counts.boundary_program = 1,
                .declarative => counts.declarative = 1,
                .residualized_program => counts.residualized_program = 1,
                .pipeline => counts.pipeline = 1,
                .kernel_primitive => counts.kernel_primitive = 1,
                .host_intrinsic => counts.host_intrinsic = 1,
                .unknown => counts.unknown = 1,
            }
            return counts;
        }

        pub fn total(self: @This()) usize {
            return self.boundary_program + self.declarative + self.residualized_program + self.pipeline + self.kernel_primitive + self.host_intrinsic + self.unknown;
        }
    };

    pub const Options = struct {
        scope_kind: ScopeKind,
        scope_ref: Ref,
        counts: Counts = .{},
        intrinsic_refs: []const Ref = &.{},
        unknown_refs: []const Ref = &.{},
        dependencies: []const Dependency = &.{},
        blockers: []const Blocker = &.{},
        primary_intrinsic_ref: ?Ref = null,
        secondary_intrinsic_ref: ?Ref = null,
        policy_summary: ?PolicySummary = null,
        summary: []const u8 = "",
    };

    pub fn init(options: Options) @This() {
        var report = @This(){
            .scope_kind = options.scope_kind,
            .scope_ref = options.scope_ref,
            .report_fingerprint = 0,
            .total_bodies = options.counts.total(),
            .boundary_program_count = options.counts.boundary_program,
            .declarative_count = options.counts.declarative,
            .residualized_program_count = options.counts.residualized_program,
            .pipeline_count = options.counts.pipeline,
            .kernel_primitive_count = options.counts.kernel_primitive,
            .host_intrinsic_count = options.counts.host_intrinsic,
            .unknown_count = options.counts.unknown,
            .intrinsic_refs = options.intrinsic_refs,
            .unknown_refs = options.unknown_refs,
            .dependencies = options.dependencies,
            .blockers = options.blockers,
            .primary_intrinsic_ref = options.primary_intrinsic_ref,
            .secondary_intrinsic_ref = options.secondary_intrinsic_ref,
            .policy_summary = options.policy_summary,
            .summary = options.summary,
        };
        report.report_fingerprint = report.computeFingerprint();
        return report;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.defunctionalization_report);
        builder.fieldBytes("scope_kind", @tagName(self.scope_kind));
        builder.fieldRef("scope_ref", self.scope_ref);
        builder.fieldUsize("total", self.total_bodies);
        builder.fieldUsize("boundary_program", self.boundary_program_count);
        builder.fieldUsize("declarative", self.declarative_count);
        builder.fieldUsize("residualized_program", self.residualized_program_count);
        builder.fieldUsize("pipeline", self.pipeline_count);
        builder.fieldUsize("kernel_primitive", self.kernel_primitive_count);
        builder.fieldUsize("host_intrinsic", self.host_intrinsic_count);
        builder.fieldUsize("unknown", self.unknown_count);
        for (self.intrinsic_refs) |ref| builder.fieldRef("intrinsic_ref", ref);
        if (self.primary_intrinsic_ref) |ref| builder.fieldRef("primary_intrinsic_ref", ref);
        if (self.secondary_intrinsic_ref) |ref| builder.fieldRef("secondary_intrinsic_ref", ref);
        for (self.unknown_refs) |ref| builder.fieldRef("unknown_ref", ref);
        for (self.dependencies) |dependency| {
            builder.fieldBytes("dependency.role", @tagName(dependency.role));
            builder.fieldRef("dependency.ref", dependency.ref);
        }
        for (self.blockers) |blocker| builder.fieldU64("blocker", blocker.fingerprint());
        if (self.policy_summary) |policy| builder.fieldU64("policy", policy.fingerprint());
        builder.fieldBytes("summary", self.summary);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refFor(domains.defunctionalization_report, self.report_fingerprint, .{
            .label = self.summary,
            .kind_tag = @tagName(self.scope_kind),
        });
    }

    pub fn journalProjection(self: @This(), event_kind: []const u8) JournalProjection {
        return .{
            .evidence_ref = self.evidenceRef(),
            .suggested_event_kind = event_kind,
            .summary_metadata = self.summary,
        };
    }

    pub fn recordedProjection(self: @This()) JournalProjection {
        return self.journalProjection("defunctionalization_report_recorded");
    }

    pub fn toEvidenceReport(self: @This()) Report {
        if (self.host_intrinsic_count != 0 or self.unknown_count != 0) {
            return Report.withFailure(
                self.scope_ref,
                domains.defunctionalization_report.id,
                self.dependencies,
                self.blockers,
                &.{},
                if (self.policy_summary) |policy| policy.policy_fingerprint else null,
                self.summary,
            );
        }
        if (self.blockers.len != 0) {
            return Report.withBlockers(
                self.scope_ref,
                domains.defunctionalization_report.id,
                self.dependencies,
                self.blockers,
                &.{},
                if (self.policy_summary) |policy| policy.policy_fingerprint else null,
                self.summary,
            );
        }
        return Report.ok(self.scope_ref, domains.defunctionalization_report.id, self.dependencies);
    }

    pub fn assertNoHostIntrinsics(self: @This()) error{ HostIntrinsicsPresent, UnknownSemanticBody }!void {
        if (self.host_intrinsic_count != 0) return error.HostIntrinsicsPresent;
        if (self.unknown_count != 0) return error.UnknownSemanticBody;
    }

    pub fn assertOnlyAllowlistedIntrinsics(self: @This(), policy: DefunctionalizationPolicy) error{ HostIntrinsicsPresent, UnknownSemanticBody, IntrinsicCountExceeded }!void {
        if (policy.reject_unknown and self.unknown_count != 0) return error.UnknownSemanticBody;
        if (!policy.allow_host_intrinsics and self.host_intrinsic_count != 0) return error.HostIntrinsicsPresent;
        if (!policy.allow_kernel_primitives and self.kernel_primitive_count != 0) return error.HostIntrinsicsPresent;
        if (policy.require_program_backed_providers and self.providerScopeRequiresProgramBodies()) return error.HostIntrinsicsPresent;
        if (policy.require_declarative_morphisms and self.morphismScopeRequiresDeclarativeBody()) return error.HostIntrinsicsPresent;
        if (self.host_intrinsic_count != 0 and policy.require_no_intrinsics_in_treaties and self.treatyScoped()) {
            return error.HostIntrinsicsPresent;
        }
        if (policy.maximum_intrinsic_count) |maximum| {
            if (self.host_intrinsic_count > maximum) return error.IntrinsicCountExceeded;
        }
        const constrains_intrinsics = policy.allowed_intrinsic_fingerprints.len != 0 or
            policy.allowed_intrinsic_kinds.len != 0 or
            policy.allowed_intrinsic_labels.len != 0 or
            policy.reject_dynamic_mappers;
        if (self.host_intrinsic_count != 0 and constrains_intrinsics) {
            if (self.availableIntrinsicRefCount() < self.host_intrinsic_count) return error.HostIntrinsicsPresent;
            for (self.intrinsic_refs) |intrinsic_ref| {
                if (!intrinsicRefAllowedByPolicy(intrinsic_ref, policy)) return error.HostIntrinsicsPresent;
            }
            if (self.primary_intrinsic_ref) |intrinsic_ref| {
                if (!intrinsicRefAllowedByPolicy(intrinsic_ref, policy)) return error.HostIntrinsicsPresent;
            }
            if (self.secondary_intrinsic_ref) |intrinsic_ref| {
                if (!intrinsicRefAllowedByPolicy(intrinsic_ref, policy)) return error.HostIntrinsicsPresent;
            }
        }
    }

    fn availableIntrinsicRefCount(self: @This()) usize {
        return self.intrinsic_refs.len +
            @as(usize, @intFromBool(self.primary_intrinsic_ref != null)) +
            @as(usize, @intFromBool(self.secondary_intrinsic_ref != null));
    }

    fn providerScopeRequiresProgramBodies(self: @This()) bool {
        const provider_scoped = switch (self.scope_kind) {
            .provider_harness,
            .provider_offer,
            => true,
            .program,
            .treaty,
            .treaty_resolver_result,
            .interpreter,
            .run_handler_set,
            .morphism_offer,
            .pipeline,
            .journal,
            .catalog,
            => false,
        };
        if (!provider_scoped) return false;
        return self.host_intrinsic_count != 0 or self.unknown_count != 0;
    }

    fn treatyScoped(self: @This()) bool {
        return switch (self.scope_kind) {
            .treaty,
            .treaty_resolver_result,
            => true,
            .program,
            .provider_harness,
            .provider_offer,
            .interpreter,
            .run_handler_set,
            .morphism_offer,
            .pipeline,
            .journal,
            .catalog,
            => false,
        };
    }

    fn morphismScopeRequiresDeclarativeBody(self: @This()) bool {
        const morphism_scoped = switch (self.scope_kind) {
            .morphism_offer => true,
            .program,
            .provider_harness,
            .provider_offer,
            .treaty,
            .treaty_resolver_result,
            .interpreter,
            .run_handler_set,
            .pipeline,
            .journal,
            .catalog,
            => false,
        };
        if (!morphism_scoped) return false;
        return self.boundary_program_count != 0 or
            self.kernel_primitive_count != 0 or
            self.host_intrinsic_count != 0 or
            self.unknown_count != 0;
    }
};

fn intrinsicRefAllowedByPolicy(intrinsic_ref: Ref, policy: DefunctionalizationPolicy) bool {
    if (intrinsic_ref.domain_id != domains.host_intrinsic.id) return false;
    if (!policy.allow_host_intrinsics) return false;
    if (policy.reject_dynamic_mappers) {
        if (intrinsic_ref.kind_tag) |kind_tag| {
            if (std.mem.eql(u8, kind_tag, @tagName(HostIntrinsic.Kind.dynamic_morphism_mapper))) return false;
        } else {
            return false;
        }
    }
    if (policy.allow_test_fixtures) {
        if (intrinsic_ref.kind_tag) |kind_tag| {
            if (std.mem.eql(u8, kind_tag, @tagName(HostIntrinsic.Kind.test_fixture))) return true;
        }
    }
    for (policy.allowed_intrinsic_fingerprints) |allowed| {
        if (allowed == intrinsic_ref.fingerprint) return true;
    }
    if (intrinsic_ref.kind_tag) |kind_tag| {
        for (policy.allowed_intrinsic_kinds) |allowed| {
            if (std.mem.eql(u8, @tagName(allowed), kind_tag)) return true;
        }
    }
    if (intrinsic_ref.label) |label_value| {
        for (policy.allowed_intrinsic_labels) |allowed| {
            if (std.mem.eql(u8, allowed, label_value)) return true;
        }
    }
    return policy.allowed_intrinsic_fingerprints.len == 0 and
        policy.allowed_intrinsic_kinds.len == 0 and
        policy.allowed_intrinsic_labels.len == 0;
}

pub fn certificateViewForTreatyCertificate(certificate: anytype) CertificateView {
    return certificateViewForTreatyCertificateWithDependencies(null, certificate);
}

pub fn certificateViewForTreatyCertificateWithDependencies(storage: ?*[6]Dependency, certificate: anytype) CertificateView {
    const certificate_ref = refForTreatyCertificate(certificate);
    const treaty_ref = refFor(domains.treaty, certificate.treaty_fingerprint, .{});
    const subject = refFor(domains.exchange_request_envelope, certificate.request_envelope_fingerprint, .{
        .format_version = requestEnvelopeFormatVersion(certificate),
    });
    const dependencies = if (storage) |out| blk: {
        var len: usize = 0;
        out[len] = .{ .role = .subject, .ref = subject };
        len += 1;
        out[len] = .{ .role = .treaty, .ref = treaty_ref };
        len += 1;
        if (refForNonZeroField(certificate, "provider_fingerprint", domains.provider_identity)) |provider_identity_ref| {
            out[len] = .{ .role = .provider, .ref = provider_identity_ref };
            len += 1;
        }
        out[len] = .{ .role = .offer, .ref = refFor(domains.provider_offer, certificate.provider_offer_fingerprint, .{}) };
        len += 1;
        out[len] = .{ .role = .capability, .ref = refFor(domains.capability, certificate.capability_fingerprint, .{}) };
        len += 1;
        out[len] = .{ .role = .route, .ref = refFor(domains.route, certificate.route_fingerprint, .{}) };
        len += 1;
        break :blk out[0..len];
    } else &.{};
    return .{
        .certificate_ref = certificate_ref,
        .subject_ref = subject,
        .domain = domains.treaty_certificate.id,
        .dependencies = dependencies,
        .report_fingerprint = certificate_ref.fingerprint,
        .certificate_fingerprint = certificate_ref.fingerprint,
        .summary = "treaty certificate",
    };
}

pub fn authorizationViewForTreatyAuthorization(authorization: anytype) AuthorizationView {
    return .{
        .authorization_ref = refForTreatyAuthorization(authorization),
        .request_ref = refForNonZeroFieldWithFormat(authorization, "request_envelope_fingerprint", domains.exchange_request_envelope, treatyAuthorizationRequestEnvelopeFormatVersion(authorization)),
        .response_ref = refFor(domains.exchange_response_envelope, authorization.response_envelope_fingerprint, .{}),
        .provider_ref = refForNonZeroField(authorization, "provider_fingerprint", domains.provider_identity),
        .capability_ref = refForNonZeroField(authorization, "capability_fingerprint", domains.capability),
        .route_ref = refFor(domains.route, authorization.route_fingerprint, .{}),
        .treaty_ref = refFor(domains.treaty, authorization.treaty_fingerprint, .{}),
        .obligation_ref = if (authorization.obligation_fingerprint) |fingerprint| refFor(domains.obligation, fingerprint, .{}) else null,
        .authorization_fingerprint = authorization.authorization_fingerprint,
        .summary = "treaty authorization",
    };
}

pub fn journalProjection(evidence_ref: Ref, event_kind: []const u8, dependencies: []const Ref, summary: []const u8) JournalProjection {
    return .{ .evidence_ref = evidence_ref, .suggested_event_kind = event_kind, .dependency_refs = dependencies, .summary_metadata = summary };
}

pub fn expectHasRef(comptime T: type) void {
    if (!@hasDecl(T, "evidenceRef")) @compileError(@typeName(T) ++ " must expose evidenceRef");
}

pub fn expectHasDomain(comptime T: type) void {
    if (!@hasDecl(T, "evidenceDomain")) @compileError(@typeName(T) ++ " must expose evidenceDomain");
}

pub fn expectReportShape(report: anytype) !void {
    try std.testing.expect(@hasField(@TypeOf(report), "subject"));
    try std.testing.expect(@hasField(@TypeOf(report), "report_domain"));
    try std.testing.expect(@hasField(@TypeOf(report), "success"));
    try std.testing.expect(@hasField(@TypeOf(report), "report_fingerprint"));
}

pub fn expectDependencyContains(dependencies: []const Dependency, role: Role, ref: Ref) !void {
    for (dependencies) |dependency| {
        if (dependency.role == role and dependency.ref.eql(ref)) return;
    }
    return error.MissingDependency;
}

fn optionalLabel(value: anytype, comptime field_name: []const u8) ?[]const u8 {
    if (comptime @hasField(@TypeOf(value), field_name)) return @field(value, field_name);
    return null;
}

fn optionalUsizeField(value: anytype, comptime field_name: []const u8) ?usize {
    if (comptime @hasField(@TypeOf(value), field_name)) return @field(value, field_name);
    return null;
}

fn optionalU64Field(value: anytype, comptime field_name: []const u8) ?u64 {
    if (comptime @hasField(@TypeOf(value), field_name)) return @field(value, field_name);
    return null;
}

fn refForNonZeroField(value: anytype, comptime field_name: []const u8, domain: Domain) ?Ref {
    if (comptime @hasField(@TypeOf(value), field_name)) {
        const fingerprint = @field(value, field_name);
        if (fingerprint != 0) return refFor(domain, fingerprint, .{});
    }
    return null;
}

fn refForNonZeroFieldWithFormat(value: anytype, comptime field_name: []const u8, domain: Domain, format_version: ?u32) ?Ref {
    if (comptime @hasField(@TypeOf(value), field_name)) {
        const fingerprint = @field(value, field_name);
        if (fingerprint != 0) {
            var ref = refFor(domain, fingerprint, .{ .format_version = format_version });
            ref.format_version = format_version;
            return ref;
        }
    }
    return null;
}

fn requestEnvelopeFormatVersion(value: anytype) ?u32 {
    if (comptime @hasField(@TypeOf(value), "request_envelope_format_version")) return value.request_envelope_format_version;
    if (comptime @hasField(@TypeOf(value), "request_format_version")) return value.request_format_version;
    return domains.exchange_request_envelope.format_version;
}

fn treatyAuthorizationRequestEnvelopeFormatVersion(authorization: anytype) ?u32 {
    if (comptime @hasField(@TypeOf(authorization), "format_version")) {
        if (authorization.format_version == 3) return null;
    }
    return requestEnvelopeFormatVersion(authorization);
}

fn optionalBytesEqual(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}

fn optionalU32LessThan(left: ?u32, right: ?u32) ?bool {
    if (left == null or right == null) {
        if (left == null and right == null) return null;
        return left == null;
    }
    if (left.? != right.?) return left.? < right.?;
    return null;
}

fn optionalU64LessThan(left: ?u64, right: ?u64) ?bool {
    if (left == null or right == null) {
        if (left == null and right == null) return null;
        return left == null;
    }
    if (left.? != right.?) return left.? < right.?;
    return null;
}

fn optionalUsizeLessThan(left: ?usize, right: ?usize) ?bool {
    if (left == null or right == null) {
        if (left == null and right == null) return null;
        return left == null;
    }
    if (left.? != right.?) return left.? < right.?;
    return null;
}

fn optionalBytesLessThan(left: ?[]const u8, right: ?[]const u8) ?bool {
    if (left == null or right == null) {
        if (left == null and right == null) return null;
        return left == null;
    }
    return switch (std.mem.order(u8, left.?, right.?)) {
        .lt => true,
        .gt => false,
        .eq => null,
    };
}

fn dependencyEqual(left: Dependency, right: Dependency) bool {
    return left.role == right.role and left.ref.eql(right.ref);
}

fn dependencyLessThan(_: void, left: Dependency, right: Dependency) bool {
    const left_role = @intFromEnum(left.role);
    const right_role = @intFromEnum(right.role);
    if (left_role != right_role) return left_role < right_role;
    const left_domain = @intFromEnum(left.ref.domain_id);
    const right_domain = @intFromEnum(right.ref.domain_id);
    if (left_domain != right_domain) return left_domain < right_domain;
    if (left.ref.fingerprint != right.ref.fingerprint) return left.ref.fingerprint < right.ref.fingerprint;
    if (optionalU32LessThan(left.ref.format_version, right.ref.format_version)) |less| return less;
    if (optionalBytesLessThan(left.ref.label, right.ref.label)) |less| return less;
    if (optionalU64LessThan(left.ref.branch_id, right.ref.branch_id)) |less| return less;
    if (optionalUsizeLessThan(left.ref.site_index, right.ref.site_index)) |less| return less;
    if (optionalBytesLessThan(left.ref.kind_tag, right.ref.kind_tag)) |less| return less;
    return false;
}

fn writeDependency(builder: *FingerprintBuilder, dependency: Dependency) void {
    builder.fieldBytes("role", @tagName(dependency.role));
    builder.fieldRef("ref", dependency.ref);
}

fn writeCanonicalDependencies(builder: *FingerprintBuilder, dependencies: []const Dependency) void {
    var emitted: usize = 0;
    var previous: ?Dependency = null;
    while (emitted < dependencies.len) {
        var candidate: ?Dependency = null;
        candidate_loop: for (dependencies) |dependency| {
            if (previous) |prev| {
                if (!dependencyLessThan({}, prev, dependency)) continue :candidate_loop;
            }
            if (candidate == null or dependencyLessThan({}, dependency, candidate.?)) candidate = dependency;
        }
        const current = candidate orelse break;
        var count: usize = 0;
        for (dependencies) |dependency| {
            if (dependencyEqual(dependency, current)) count += 1;
        }
        for (0..count) |_| writeDependency(builder, current);
        emitted += count;
        previous = current;
    }
}

fn fingerprintSortedDependencies(dependencies: []const Dependency) u64 {
    var builder = FingerprintBuilder.init(domains.program_plan);
    builder.fieldBytes("kind", "dependency_graph");
    for (dependencies) |dependency| {
        writeDependency(&builder, dependency);
    }
    return builder.finish();
}

fn hasErrorBlockers(blockers: []const Blocker) bool {
    for (blockers) |blocker| {
        if (blocker.severity == .@"error") return true;
    }
    return false;
}

fn computeReportFingerprint(
    subject: Ref,
    report_domain: Domain.Id,
    dependencies: []const Dependency,
    blockers: []const Blocker,
    warnings: []const Blocker,
    success: bool,
    truncated: bool,
    omitted_fingerprint: ?u64,
    policy_fingerprint: ?u64,
    summary: ?[]const u8,
) u64 {
    const domain = domainById(report_domain) orelse domains.program_plan;
    var builder = FingerprintBuilder.init(domain);
    builder.fieldRef("subject", subject);
    builder.fieldBool("success", success);
    builder.fieldBool("truncated", truncated);
    writeCanonicalDependencies(&builder, dependencies);
    for (blockers) |blocker| builder.fieldU64("blocker", blocker.fingerprint());
    for (warnings) |warning| builder.fieldU64("warning", warning.fingerprint());
    builder.fieldOptionalU64("omitted", omitted_fingerprint);
    builder.fieldOptionalU64("policy", policy_fingerprint);
    builder.fieldOptionalBytes("summary", summary);
    return builder.finish();
}
