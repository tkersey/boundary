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
        boundary_effect_shape,
        boundary_static_treaty_plan,
        boundary_closure_policy,
        boundary_closure_graph,
        boundary_closure_report,
        boundary_closure_certificate,
        boundary_world_port,
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
        boundary_closure,
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
    pub const boundary_effect_shape = Domain{ .id = .boundary_effect_shape, .name = "boundary.evidence.closure.effect_shape", .fingerprint_version = 1, .owner = .boundary_closure, .kind = .derived_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "effect shape" };
    pub const boundary_static_treaty_plan = Domain{ .id = .boundary_static_treaty_plan, .name = "boundary.evidence.closure.static_treaty_plan", .fingerprint_version = 1, .owner = .boundary_closure, .kind = .report, .journal_referenced = true, .certificate_referenced = true, .tests = "static treaty" };
    pub const boundary_closure_policy = Domain{ .id = .boundary_closure_policy, .name = "boundary.evidence.closure.policy", .fingerprint_version = 1, .owner = .boundary_closure, .kind = .fingerprint, .journal_referenced = true, .certificate_referenced = true, .tests = "boundary closure policy" };
    pub const boundary_closure_graph = Domain{ .id = .boundary_closure_graph, .name = "boundary.evidence.closure.graph", .fingerprint_version = 1, .owner = .boundary_closure, .kind = .derived_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "closure graph" };
    pub const boundary_closure_report = Domain{ .id = .boundary_closure_report, .name = "boundary.evidence.closure.report", .fingerprint_version = 1, .owner = .boundary_closure, .kind = .report, .journal_referenced = true, .certificate_referenced = true, .tests = "boundary closure" };
    pub const boundary_closure_certificate = Domain{ .id = .boundary_closure_certificate, .name = "boundary.evidence.closure.certificate", .format_version = 1, .fingerprint_version = 1, .owner = .boundary_closure, .kind = .certificate, .journal_referenced = true, .certificate_referenced = true, .tests = "closure certificate" };
    pub const boundary_world_port = Domain{ .id = .boundary_world_port, .name = "boundary.evidence.closure.world_port", .format_version = 1, .fingerprint_version = 1, .owner = .boundary_closure, .kind = .derived_metadata, .stability = .host_owned_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "world port" };
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
    domains.boundary_effect_shape,
    domains.boundary_static_treaty_plan,
    domains.boundary_closure_policy,
    domains.boundary_closure_graph,
    domains.boundary_closure_report,
    domains.boundary_closure_certificate,
    domains.boundary_world_port,
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

pub fn refForBoundaryStaticTreatyPlan(plan: anytype) Ref {
    return refFor(domains.boundary_static_treaty_plan, plan.fingerprint, .{ .label = optionalLabel(plan, "label") });
}

pub fn refForBoundaryClosureGraph(graph: anytype) Ref {
    return refFor(domains.boundary_closure_graph, graph.fingerprint, .{ .label = optionalLabel(graph, "label") });
}

pub fn refForBoundaryClosureReport(report: anytype) Ref {
    return refFor(domains.boundary_closure_report, report.report_fingerprint, .{ .label = optionalLabel(report, "summary") });
}

pub fn refForBoundaryClosureCertificate(certificate: anytype) Ref {
    return refFor(domains.boundary_closure_certificate, certificate.certificate_fingerprint, .{
        .format_version = domains.boundary_closure_certificate.format_version,
        .label = optionalLabel(certificate, "label"),
    });
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
    root_program,
    provider_program,
    effect_shape,
    static_treaty_plan,
    closure_graph,
    closure_policy,
    closure_report,
    closure_certificate,
    world_port,
    blocker,
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

    pub fn fieldValueRef(self: *@This(), field_label: []const u8, ref: BoundaryValueRef) void {
        self.writeLabel(field_label);
        self.rawBytes(ref.codec);
        self.fieldOptionalU64("value_ref.schema_index", if (ref.schema_index) |value| @as(u64, value) else null);
    }

    pub fn fieldOptionalValueRef(self: *@This(), field_label: []const u8, maybe_ref: ?BoundaryValueRef) void {
        self.writeLabel(field_label);
        self.hasher.update(&[_]u8{@intFromBool(maybe_ref != null)});
        if (maybe_ref) |ref| self.fieldValueRef("value_ref", ref);
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
    boundary_closure,
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

pub const BoundaryClosureBlockerTag = enum {
    root_program_missing,
    provider_catalog_empty,
    effect_shape_unhandled,
    nested_provider_effect_unhandled,
    no_static_treaty_plan,
    no_provider_offer_for_shape,
    no_capability_for_shape,
    ambiguous_static_treaty_plan,
    intrinsic_route_rejected,
    unallowlisted_intrinsic,
    unknown_semantic_body,
    dynamic_mapper_rejected,
    provider_program_contract_missing,
    provider_program_nested_unknown,
    world_port_missing,
    world_port_shape_mismatch,
    capability_shape_mismatch,
    treaty_policy_incompatible,
    defunctionalization_policy_incompatible,
    runtime_guard_required,
    unsupported_shape_planning,
    residualization_shape_unsupported,
    pipeline_shape_unsupported,
    depth_limit_exceeded,
    cycle_detected,
};

pub const BoundaryValueRef = struct {
    codec: []const u8,
    schema_index: ?u16 = null,

    pub fn init(codec: []const u8, schema_index: ?u16) @This() {
        return .{ .codec = codec, .schema_index = schema_index };
    }

    pub fn fromValueRef(ref: anytype) @This() {
        return .{
            .codec = @tagName(ref.codec),
            .schema_index = if (ref.schema_index) |index| @as(u16, @intCast(index)) else null,
        };
    }

    pub fn eql(self: @This(), other: @This()) bool {
        return std.mem.eql(u8, self.codec, other.codec) and self.schema_index == other.schema_index;
    }
};

pub const BoundaryClosurePolicy = struct {
    label: []const u8 = "strict_static",
    defunctionalization_policy: DefunctionalizationPolicy = DefunctionalizationPolicy.strict(),
    require_all_effect_shapes_closed: bool = true,
    allow_host_intrinsics: bool = false,
    allow_world_ports: bool = false,
    allowed_host_intrinsic_fingerprints: []const u64 = &.{},
    allowed_host_intrinsic_kinds: []const HostIntrinsic.Kind = &.{},
    allowed_host_intrinsic_labels: []const []const u8 = &.{},
    allowed_world_port_fingerprints: []const u64 = &.{},
    allowed_world_port_kinds: []const WorldPort.Kind = &.{},
    allowed_world_port_labels: []const []const u8 = &.{},
    allow_runtime_guards: bool = false,
    require_static_treaty_plans: bool = true,
    reject_unknown_semantic_bodies: bool = true,
    reject_host_intrinsics: bool = true,
    require_program_backed_providers: bool = false,
    require_declarative_morphisms: bool = false,
    prefer_boundary_native: bool = true,
    reject_ambiguous_routes: bool = true,
    reject_unknown_effect_shapes: bool = true,
    reject_request_value_dependence: bool = true,
    reject_runtime_guards: bool = true,
    allow_test_world_ports: bool = false,
    allow_intrinsic_test_fixtures: bool = false,
    allow_kernel_primitives: bool = true,
    max_morphism_hops: usize = 1,
    max_depth: usize = 64,
    max_nested_provider_depth: usize = 64,
    max_nodes: usize = 4096,

    pub fn strictStatic() @This() {
        return .{};
    }

    pub fn strict() @This() {
        return strictStatic();
    }

    pub fn strictClosed() @This() {
        return strictStatic();
    }

    pub fn worldBoundary() @This() {
        return .{
            .label = "world_boundary",
            .defunctionalization_policy = DefunctionalizationPolicy.worldBoundary(),
            .allow_host_intrinsics = true,
            .allow_world_ports = true,
            .reject_unknown_effect_shapes = true,
            .reject_host_intrinsics = false,
            .reject_request_value_dependence = true,
            .reject_runtime_guards = true,
        };
    }

    pub fn testFixture() @This() {
        return .{
            .label = "test_fixture",
            .defunctionalization_policy = DefunctionalizationPolicy.testFixture(),
            .allow_host_intrinsics = true,
            .allow_world_ports = true,
            .allowed_world_port_kinds = &.{.test_fixture},
            .allow_test_world_ports = true,
            .allow_intrinsic_test_fixtures = true,
            .reject_host_intrinsics = false,
            .reject_unknown_effect_shapes = true,
        };
    }

    pub fn auditOnly() @This() {
        return .{
            .label = "audit_only",
            .defunctionalization_policy = DefunctionalizationPolicy.permissive(),
            .require_all_effect_shapes_closed = false,
            .allow_host_intrinsics = true,
            .allow_world_ports = true,
            .allow_runtime_guards = true,
            .reject_unknown_semantic_bodies = false,
            .reject_host_intrinsics = false,
            .reject_ambiguous_routes = false,
            .reject_unknown_effect_shapes = false,
            .reject_request_value_dependence = false,
            .reject_runtime_guards = false,
        };
    }

    pub fn fingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_closure_policy);
        builder.fieldBytes("label", self.label);
        builder.fieldU64("defunctionalization_policy", self.defunctionalization_policy.fingerprint());
        builder.fieldBool("require_all_effect_shapes_closed", self.require_all_effect_shapes_closed);
        builder.fieldBool("allow_host_intrinsics", self.allow_host_intrinsics);
        builder.fieldBool("allow_world_ports", self.allow_world_ports);
        for (self.allowed_host_intrinsic_fingerprints) |value| builder.fieldU64("allowed_host_intrinsic", value);
        for (self.allowed_host_intrinsic_kinds) |kind| builder.fieldBytes("allowed_host_intrinsic_kind", @tagName(kind));
        for (self.allowed_host_intrinsic_labels) |label_value| builder.fieldBytes("allowed_host_intrinsic_label", label_value);
        for (self.allowed_world_port_fingerprints) |value| builder.fieldU64("allowed_world_port", value);
        for (self.allowed_world_port_kinds) |kind| builder.fieldBytes("allowed_world_port_kind", @tagName(kind));
        for (self.allowed_world_port_labels) |label_value| builder.fieldBytes("allowed_world_port_label", label_value);
        builder.fieldBool("allow_runtime_guards", self.allow_runtime_guards);
        builder.fieldBool("require_static_treaty_plans", self.require_static_treaty_plans);
        builder.fieldBool("reject_unknown_semantic_bodies", self.reject_unknown_semantic_bodies);
        builder.fieldBool("reject_host_intrinsics", self.reject_host_intrinsics);
        builder.fieldBool("require_program_backed_providers", self.require_program_backed_providers);
        builder.fieldBool("require_declarative_morphisms", self.require_declarative_morphisms);
        builder.fieldBool("prefer_boundary_native", self.prefer_boundary_native);
        builder.fieldBool("reject_ambiguous_routes", self.reject_ambiguous_routes);
        builder.fieldBool("reject_unknown_effect_shapes", self.reject_unknown_effect_shapes);
        builder.fieldBool("reject_request_value_dependence", self.reject_request_value_dependence);
        builder.fieldBool("reject_runtime_guards", self.reject_runtime_guards);
        builder.fieldBool("allow_test_world_ports", self.allow_test_world_ports);
        builder.fieldBool("allow_intrinsic_test_fixtures", self.allow_intrinsic_test_fixtures);
        builder.fieldBool("allow_kernel_primitives", self.allow_kernel_primitives);
        builder.fieldUsize("max_morphism_hops", self.max_morphism_hops);
        builder.fieldUsize("max_depth", self.max_depth);
        builder.fieldUsize("max_nested_provider_depth", self.max_nested_provider_depth);
        builder.fieldUsize("max_nodes", self.max_nodes);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refFor(domains.boundary_closure_policy, self.fingerprint(), .{ .label = self.label });
    }

    pub fn policySummary(self: @This()) PolicySummary {
        return .{
            .policy_domain = domains.boundary_closure_policy.id,
            .policy_fingerprint = self.fingerprint(),
            .policy_label = self.label,
        };
    }

    pub fn allowsWorldPortRef(self: @This(), world_port_ref: Ref) bool {
        return worldPortRefAllowedByPolicy(world_port_ref, self);
    }

    pub fn allowsHostIntrinsicRef(self: @This(), intrinsic_ref: Ref) bool {
        if (intrinsic_ref.domain_id != domains.host_intrinsic.id) return false;
        if (!self.allow_host_intrinsics or self.reject_host_intrinsics) return false;
        if (self.allow_intrinsic_test_fixtures) {
            if (intrinsic_ref.kind_tag) |kind_tag| {
                if (std.mem.eql(u8, kind_tag, @tagName(HostIntrinsic.Kind.test_fixture))) return true;
            }
        }
        for (self.allowed_host_intrinsic_fingerprints) |allowed| {
            if (allowed == intrinsic_ref.fingerprint) return true;
        }
        if (intrinsic_ref.kind_tag) |kind_tag| {
            for (self.allowed_host_intrinsic_kinds) |allowed| {
                if (std.mem.eql(u8, @tagName(allowed), kind_tag)) return true;
            }
        }
        if (intrinsic_ref.label) |label_value| {
            for (self.allowed_host_intrinsic_labels) |allowed| {
                if (std.mem.eql(u8, allowed, label_value)) return true;
            }
        }
        return self.allowed_host_intrinsic_fingerprints.len == 0 and
            self.allowed_host_intrinsic_kinds.len == 0 and
            self.allowed_host_intrinsic_labels.len == 0;
    }
};

pub const BoundaryEffectShape = struct {
    fingerprint: u64,
    program_label: []const u8,
    plan_label: []const u8 = "",
    plan_hash: u64 = 0,
    kind: Kind,
    site_index: ?usize = null,
    site_fingerprint: ?u64 = null,
    semantic_label: ?[]const u8 = null,
    name: []const u8 = "",
    mode: []const u8 = "",
    value_ref: ?BoundaryValueRef = null,
    expected_resume_ref: ?BoundaryValueRef = null,
    result_ref: ?BoundaryValueRef = null,
    protocol_label: []const u8 = "",
    protocol_op_fingerprint: ?u64 = null,
    desired_response_refs: []const BoundaryValueRef = &.{},
    usage_summary: []const u8 = "",
    branch_policy_summary: []const u8 = "",
    replay_policy_summary: []const u8 = "",
    max_request_bytes: usize = 0,
    max_response_bytes: usize = 0,
    max_payload_bytes: usize = 0,
    max_capsule_image_bytes: usize = 0,

    pub const Kind = enum {
        root_program,
        provider_program,
        operation,
        after,
        intrinsic,
        world_port,
        unknown,
    };

    pub const Options = struct {
        program_label: []const u8,
        plan_label: []const u8 = "",
        plan_hash: u64 = 0,
        kind: Kind,
        site_index: ?usize = null,
        site_fingerprint: ?u64 = null,
        semantic_label: ?[]const u8 = null,
        name: []const u8 = "",
        mode: []const u8 = "",
        value_ref: ?BoundaryValueRef = null,
        expected_resume_ref: ?BoundaryValueRef = null,
        result_ref: ?BoundaryValueRef = null,
        protocol_label: []const u8 = "",
        protocol_op_fingerprint: ?u64 = null,
        desired_response_refs: []const BoundaryValueRef = &.{},
        usage_summary: []const u8 = "",
        branch_policy_summary: []const u8 = "",
        replay_policy_summary: []const u8 = "",
        max_request_bytes: usize = 0,
        max_response_bytes: usize = 0,
        max_payload_bytes: usize = 0,
        max_capsule_image_bytes: usize = 0,
    };

    pub fn init(options: Options) @This() {
        var value = @This(){
            .fingerprint = 0,
            .program_label = options.program_label,
            .plan_label = options.plan_label,
            .plan_hash = options.plan_hash,
            .kind = options.kind,
            .site_index = options.site_index,
            .site_fingerprint = options.site_fingerprint,
            .semantic_label = options.semantic_label,
            .name = options.name,
            .mode = options.mode,
            .value_ref = options.value_ref,
            .expected_resume_ref = options.expected_resume_ref,
            .result_ref = options.result_ref,
            .protocol_label = options.protocol_label,
            .protocol_op_fingerprint = options.protocol_op_fingerprint,
            .desired_response_refs = options.desired_response_refs,
            .usage_summary = options.usage_summary,
            .branch_policy_summary = options.branch_policy_summary,
            .replay_policy_summary = options.replay_policy_summary,
            .max_request_bytes = options.max_request_bytes,
            .max_response_bytes = options.max_response_bytes,
            .max_payload_bytes = options.max_payload_bytes,
            .max_capsule_image_bytes = options.max_capsule_image_bytes,
        };
        value.fingerprint = value.computeFingerprint();
        return value;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        @setEvalBranchQuota(10_000);
        var builder = FingerprintBuilder.init(domains.boundary_effect_shape);
        builder.fieldBytes("program_label", self.program_label);
        builder.fieldBytes("plan_label", self.plan_label);
        builder.fieldU64("plan_hash", self.plan_hash);
        builder.fieldBytes("kind", @tagName(self.kind));
        builder.fieldOptionalU64("site_index", if (self.site_index) |value| @as(u64, @intCast(value)) else null);
        builder.fieldOptionalU64("site_fingerprint", self.site_fingerprint);
        builder.fieldOptionalBytes("semantic_label", self.semantic_label);
        builder.fieldBytes("name", self.name);
        builder.fieldBytes("mode", self.mode);
        builder.fieldOptionalValueRef("value_ref", self.value_ref);
        builder.fieldOptionalValueRef("expected_resume_ref", self.expected_resume_ref);
        builder.fieldOptionalValueRef("result_ref", self.result_ref);
        builder.fieldBytes("protocol_label", self.protocol_label);
        builder.fieldOptionalU64("protocol_op_fingerprint", self.protocol_op_fingerprint);
        for (self.desired_response_refs) |ref| builder.fieldValueRef("desired_response_ref", ref);
        builder.fieldBytes("usage_summary", self.usage_summary);
        builder.fieldBytes("branch_policy_summary", self.branch_policy_summary);
        builder.fieldBytes("replay_policy_summary", self.replay_policy_summary);
        builder.fieldUsize("max_request_bytes", self.max_request_bytes);
        builder.fieldUsize("max_response_bytes", self.max_response_bytes);
        builder.fieldUsize("max_payload_bytes", self.max_payload_bytes);
        builder.fieldUsize("max_capsule_image_bytes", self.max_capsule_image_bytes);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refFor(domains.boundary_effect_shape, self.fingerprint, .{
            .label = self.program_label,
            .site_index = self.site_index,
            .kind_tag = @tagName(self.kind),
        });
    }
};

pub const BoundaryWorldPort = struct {
    fingerprint: u64,
    label: []const u8,
    kind: Kind,
    effect_shape_ref: ?Ref = null,
    supported_protocol_labels: []const []const u8 = &.{},
    supported_site_indexes: []const usize = &.{},
    supported_protocol_op_fingerprints: []const u64 = &.{},
    contract_summary: []const u8 = "",
    tags: []const []const u8 = &.{},
    metadata: []const u8 = &.{},

    pub const Kind = WorldPort.Kind;

    pub const Options = struct {
        label: []const u8,
        kind: Kind,
        effect_shape_ref: ?Ref = null,
        supported_protocol_labels: []const []const u8 = &.{},
        supported_site_indexes: []const usize = &.{},
        supported_protocol_op_fingerprints: []const u64 = &.{},
        contract_summary: []const u8 = "",
        tags: []const []const u8 = &.{},
        metadata: []const u8 = &.{},
    };

    pub fn init(options: Options) @This() {
        var value = @This(){
            .fingerprint = 0,
            .label = options.label,
            .kind = options.kind,
            .effect_shape_ref = options.effect_shape_ref,
            .supported_protocol_labels = options.supported_protocol_labels,
            .supported_site_indexes = options.supported_site_indexes,
            .supported_protocol_op_fingerprints = options.supported_protocol_op_fingerprints,
            .contract_summary = options.contract_summary,
            .tags = options.tags,
            .metadata = options.metadata,
        };
        value.fingerprint = value.computeFingerprint();
        return value;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_world_port);
        builder.fieldU32("format_version", domains.boundary_world_port.format_version.?);
        builder.fieldU32("fingerprint_version", domains.boundary_world_port.fingerprint_version);
        builder.fieldBytes("label", self.label);
        builder.fieldBytes("kind", @tagName(self.kind));
        builder.fieldOptionalRef("effect_shape", self.effect_shape_ref);
        for (self.supported_protocol_labels) |protocol_label| builder.fieldBytes("supported_protocol", protocol_label);
        for (self.supported_site_indexes) |site| builder.fieldUsize("supported_site", site);
        for (self.supported_protocol_op_fingerprints) |fingerprint| builder.fieldU64("supported_protocol_op", fingerprint);
        builder.fieldBytes("contract_summary", self.contract_summary);
        for (self.tags) |tag| builder.fieldBytes("tag", tag);
        builder.fieldBytes("metadata", self.metadata);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refFor(domains.boundary_world_port, self.fingerprint, .{
            .format_version = domains.boundary_world_port.format_version,
            .label = self.label,
            .kind_tag = @tagName(self.kind),
        });
    }
};

pub const BoundaryClosureBlocker = struct {
    tag: BoundaryClosureBlockerTag,
    subject: ?Ref = null,
    primary: ?Ref = null,
    summary: []const u8,
    severity: Severity = .@"error",

    pub fn toEvidenceBlocker(self: @This()) Blocker {
        return boundaryClosureBlocker(.{
            .tag = self.tag,
            .subject = self.subject,
            .primary = self.primary,
            .summary = self.summary,
            .severity = self.severity,
        });
    }
};

pub const WorldPort = struct {
    format_version: u32 = 1,
    fingerprint_version: u32 = 1,
    fingerprint: u64,
    label: []const u8,
    kind: Kind,
    owner_subsystem: SourceSubsystem = .boundary_closure,
    associated_program_ref: ?Ref = null,
    associated_provider_ref: ?Ref = null,
    associated_treaty_ref: ?Ref = null,
    associated_capability_ref: ?Ref = null,
    reason: []const u8 = "",
    stability: Stability = .host_owned,
    replay_policy_summary: []const u8 = "",
    usage_mode_summary: []const u8 = "",
    evidence_dependencies: []const Dependency = &.{},
    tags: []const []const u8 = &.{},
    metadata: []const u8 = &.{},

    pub const Kind = enum {
        host_tool,
        host_model,
        host_file,
        host_network,
        host_human,
        host_randomness,
        host_clock,
        host_storage,
        foreign_system,
        test_fixture,
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
        owner_subsystem: SourceSubsystem = .boundary_closure,
        associated_program_ref: ?Ref = null,
        associated_provider_ref: ?Ref = null,
        associated_treaty_ref: ?Ref = null,
        associated_capability_ref: ?Ref = null,
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
            .associated_program_ref = options.associated_program_ref,
            .associated_provider_ref = options.associated_provider_ref,
            .associated_treaty_ref = options.associated_treaty_ref,
            .associated_capability_ref = options.associated_capability_ref,
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
        var builder = FingerprintBuilder.init(domains.boundary_world_port);
        builder.fieldU32("format_version", self.format_version);
        builder.fieldU32("fingerprint_version", self.fingerprint_version);
        builder.fieldBytes("label", self.label);
        builder.fieldBytes("kind", @tagName(self.kind));
        builder.fieldBytes("owner", @tagName(self.owner_subsystem));
        builder.fieldOptionalRef("program", self.associated_program_ref);
        builder.fieldOptionalRef("provider", self.associated_provider_ref);
        builder.fieldOptionalRef("treaty", self.associated_treaty_ref);
        builder.fieldOptionalRef("capability", self.associated_capability_ref);
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
        return refFor(domains.boundary_world_port, self.fingerprint, .{
            .format_version = self.format_version,
            .label = self.label,
            .kind_tag = @tagName(self.kind),
        });
    }

    pub fn toEvidenceBlocker(self: @This(), tag: BoundaryClosureBlockerTag, summary: []const u8) Blocker {
        return boundaryClosureBlocker(.{
            .tag = tag,
            .subject = self.evidenceRef(),
            .primary = self.associated_program_ref orelse self.associated_provider_ref orelse self.associated_treaty_ref,
            .summary = summary,
        });
    }
};

pub const EffectShape = struct {
    fingerprint: u64,
    label: []const u8,
    root_program_ref: ?Ref = null,
    program_plan_ref: ?Ref = null,
    operation_sites: []const OperationSite = &.{},
    after_sites: []const AfterSite = &.{},
    static_treaty_plan_refs: []const Ref = &.{},
    semantic_body_refs: []const Ref = &.{},
    host_intrinsic_refs: []const Ref = &.{},
    world_port_refs: []const Ref = &.{},
    dependencies: []const Dependency = &.{},
    requires_runtime_guard: bool = false,
    request_value_dependent: bool = false,

    pub const OperationSite = struct {
        index: usize,
        fingerprint: u64,
        requirement_label: []const u8 = "",
        op_name: []const u8 = "",
        payload_ref: ?BoundaryValueRef = null,
        resume_ref: ?BoundaryValueRef = null,
        has_after: bool = false,
    };

    pub const AfterSite = struct {
        index: usize,
        fingerprint: u64,
        source_operation_site_index: usize,
        source_operation_site_fingerprint: u64,
        result_ref: ?BoundaryValueRef = null,
    };

    pub const Options = struct {
        label: []const u8,
        root_program_ref: ?Ref = null,
        program_plan_ref: ?Ref = null,
        operation_sites: []const OperationSite = &.{},
        after_sites: []const AfterSite = &.{},
        static_treaty_plan_refs: []const Ref = &.{},
        semantic_body_refs: []const Ref = &.{},
        host_intrinsic_refs: []const Ref = &.{},
        world_port_refs: []const Ref = &.{},
        dependencies: []const Dependency = &.{},
        requires_runtime_guard: bool = false,
        request_value_dependent: bool = false,
    };

    pub fn init(options: Options) @This() {
        var value = @This(){
            .fingerprint = 0,
            .label = options.label,
            .root_program_ref = options.root_program_ref,
            .program_plan_ref = options.program_plan_ref,
            .operation_sites = options.operation_sites,
            .after_sites = options.after_sites,
            .static_treaty_plan_refs = options.static_treaty_plan_refs,
            .semantic_body_refs = options.semantic_body_refs,
            .host_intrinsic_refs = options.host_intrinsic_refs,
            .world_port_refs = options.world_port_refs,
            .dependencies = options.dependencies,
            .requires_runtime_guard = options.requires_runtime_guard,
            .request_value_dependent = options.request_value_dependent,
        };
        value.fingerprint = value.computeFingerprint();
        return value;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_effect_shape);
        builder.fieldBytes("label", self.label);
        builder.fieldOptionalRef("root_program", self.root_program_ref);
        builder.fieldOptionalRef("program_plan", self.program_plan_ref);
        for (self.operation_sites) |site| {
            builder.fieldUsize("operation.index", site.index);
            builder.fieldU64("operation.fingerprint", site.fingerprint);
            builder.fieldBytes("operation.requirement", site.requirement_label);
            builder.fieldBytes("operation.name", site.op_name);
            builder.fieldOptionalValueRef("operation.payload", site.payload_ref);
            builder.fieldOptionalValueRef("operation.resume", site.resume_ref);
            builder.fieldBool("operation.has_after", site.has_after);
        }
        for (self.after_sites) |site| {
            builder.fieldUsize("after.index", site.index);
            builder.fieldU64("after.fingerprint", site.fingerprint);
            builder.fieldUsize("after.source.index", site.source_operation_site_index);
            builder.fieldU64("after.source.fingerprint", site.source_operation_site_fingerprint);
            builder.fieldOptionalValueRef("after.result", site.result_ref);
        }
        for (self.static_treaty_plan_refs) |ref| builder.fieldRef("static_treaty_plan", ref);
        for (self.semantic_body_refs) |ref| builder.fieldRef("semantic_body", ref);
        for (self.host_intrinsic_refs) |ref| builder.fieldRef("host_intrinsic", ref);
        for (self.world_port_refs) |ref| builder.fieldRef("world_port", ref);
        writeCanonicalDependencies(&builder, self.dependencies);
        builder.fieldBool("requires_runtime_guard", self.requires_runtime_guard);
        builder.fieldBool("request_value_dependent", self.request_value_dependent);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refFor(domains.boundary_effect_shape, self.fingerprint, .{ .label = self.label });
    }
};

pub const BoundaryClosureBlockerOptions = struct {
    tag: BoundaryClosureBlockerTag,
    subject: ?Ref = null,
    primary: ?Ref = null,
    related_refs: []const Ref = &.{},
    branch_id: ?u64 = null,
    site_index: ?usize = null,
    source_site_fingerprint: ?u64 = null,
    target_protocol_op_fingerprint: ?u64 = null,
    morphism_fingerprint: ?u64 = null,
    summary: []const u8,
    severity: Severity = .@"error",
};

pub fn boundaryClosureBlocker(options: BoundaryClosureBlockerOptions) Blocker {
    return .{
        .domain = domains.boundary_closure_report.id,
        .tag = @tagName(options.tag),
        .severity = options.severity,
        .subject = options.subject,
        .primary = options.primary,
        .related_refs = options.related_refs,
        .branch_id = options.branch_id,
        .site_index = options.site_index,
        .source_site_fingerprint = options.source_site_fingerprint,
        .target_protocol_op_fingerprint = options.target_protocol_op_fingerprint,
        .morphism_fingerprint = options.morphism_fingerprint,
        .short_code = @tagName(options.tag),
        .summary = options.summary,
        .source = .boundary_closure,
    };
}

pub fn refForBoundaryEffectShape(shape: EffectShape) Ref {
    return shape.evidenceRef();
}

pub fn refForBoundaryWorldPort(port: WorldPort) Ref {
    return port.evidenceRef();
}

pub fn refForBoundaryClosurePolicy(policy: BoundaryClosurePolicy) Ref {
    return policy.evidenceRef();
}

pub const BoundaryStaticTreatyPlan = struct {
    fingerprint: u64,
    label: []const u8,
    source_shape: BoundaryEffectShape,
    direct_candidate_count: usize = 0,
    morphism_candidate_count: usize = 0,
    selected_provider_offer_ref: ?Ref = null,
    selected_provider_ref: ?Ref = null,
    selected_capability_ref: ?Ref = null,
    selected_morphism_ref: ?Ref = null,
    selected_semantic_body: SemanticBody = .unknown,
    selected_intrinsic_ref: ?Ref = null,
    boundary_native: bool = false,
    host_intrinsic: bool = false,
    runtime_request_value_validation_required: bool = true,
    byte_size_runtime_guard_required: bool = true,
    blockers: []const BoundaryClosureBlocker = &.{},
    dependencies: []const Dependency = &.{},

    pub const Options = struct {
        label: []const u8,
        source_shape: BoundaryEffectShape,
        direct_candidate_count: usize = 0,
        morphism_candidate_count: usize = 0,
        selected_provider_offer_ref: ?Ref = null,
        selected_provider_ref: ?Ref = null,
        selected_capability_ref: ?Ref = null,
        selected_morphism_ref: ?Ref = null,
        selected_semantic_body: SemanticBody = .unknown,
        selected_intrinsic_ref: ?Ref = null,
        boundary_native: bool = false,
        host_intrinsic: bool = false,
        runtime_request_value_validation_required: bool = true,
        byte_size_runtime_guard_required: bool = true,
        blockers: []const BoundaryClosureBlocker = &.{},
        dependencies: []const Dependency = &.{},
    };

    pub fn init(options: Options) @This() {
        var plan = @This(){
            .fingerprint = 0,
            .label = options.label,
            .source_shape = options.source_shape,
            .direct_candidate_count = options.direct_candidate_count,
            .morphism_candidate_count = options.morphism_candidate_count,
            .selected_provider_offer_ref = options.selected_provider_offer_ref,
            .selected_provider_ref = options.selected_provider_ref,
            .selected_capability_ref = options.selected_capability_ref,
            .selected_morphism_ref = options.selected_morphism_ref,
            .selected_semantic_body = options.selected_semantic_body,
            .selected_intrinsic_ref = options.selected_intrinsic_ref,
            .boundary_native = options.boundary_native,
            .host_intrinsic = options.host_intrinsic,
            .runtime_request_value_validation_required = options.runtime_request_value_validation_required,
            .byte_size_runtime_guard_required = options.byte_size_runtime_guard_required,
            .blockers = options.blockers,
            .dependencies = options.dependencies,
        };
        plan.fingerprint = plan.computeFingerprint();
        return plan;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_static_treaty_plan);
        builder.fieldBytes("label", self.label);
        builder.fieldRef("source_shape", self.source_shape.evidenceRef());
        builder.fieldUsize("direct_candidates", self.direct_candidate_count);
        builder.fieldUsize("morphism_candidates", self.morphism_candidate_count);
        builder.fieldOptionalRef("provider_offer", self.selected_provider_offer_ref);
        builder.fieldOptionalRef("provider", self.selected_provider_ref);
        builder.fieldOptionalRef("capability", self.selected_capability_ref);
        builder.fieldOptionalRef("morphism", self.selected_morphism_ref);
        builder.fieldBytes("semantic_body", @tagName(self.selected_semantic_body));
        builder.fieldOptionalRef("intrinsic", self.selected_intrinsic_ref);
        builder.fieldBool("boundary_native", self.boundary_native);
        builder.fieldBool("host_intrinsic", self.host_intrinsic);
        builder.fieldBool("runtime_request_value_validation_required", self.runtime_request_value_validation_required);
        builder.fieldBool("byte_size_runtime_guard_required", self.byte_size_runtime_guard_required);
        for (self.blockers) |blocker| builder.fieldU64("blocker", blocker.toEvidenceBlocker().fingerprint());
        writeCanonicalDependencies(&builder, self.dependencies);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refFor(domains.boundary_static_treaty_plan, self.fingerprint, .{ .label = self.label });
    }

    pub fn closed(self: @This()) bool {
        return self.selected_provider_offer_ref != null and !hasErrorClosureBlockers(self.blockers);
    }
};

pub const BoundaryGraph = struct {
    label: []const u8 = "boundary-closure-graph",
    fingerprint: u64,
    nodes: []const Node = &.{},
    edges: []const Edge = &.{},
    dependencies: []const Dependency = &.{},

    pub const NodeKind = enum {
        root_program,
        provider_program,
        operation_site,
        after_site,
        protocol_operation,
        provider_harness,
        provider_offer,
        capability_grant,
        morphism_offer,
        residualization_adapter,
        pipeline_adapter,
        treaty_shape_plan,
        semantic_body,
        host_intrinsic,
        world_port,
        blocker,
    };

    pub const EdgeKind = enum {
        root_yields,
        provider_program_yields,
        handled_by_provider,
        adapted_by_morphism,
        residualized_by,
        pipeline_by,
        authorized_by_capability,
        treaty_planned,
        opens_obligation,
        classified_as,
        intrinsic_boundary,
        world_port_exposes,
        blocked_by,
    };

    pub const Node = struct {
        kind: NodeKind,
        ref: Ref,
        label: []const u8 = "",
    };

    pub const Edge = struct {
        kind: EdgeKind,
        from: Ref,
        to: Ref,
        label: []const u8 = "",
    };

    pub fn init(label: []const u8, nodes: []const Node, edges: []const Edge, dependencies: []const Dependency) @This() {
        var graph = @This(){ .label = label, .fingerprint = 0, .nodes = nodes, .edges = edges, .dependencies = dependencies };
        graph.fingerprint = graph.computeFingerprint();
        return graph;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_closure_graph);
        builder.fieldBytes("label", self.label);
        for (self.nodes) |node| {
            builder.fieldBytes("node.kind", @tagName(node.kind));
            builder.fieldRef("node.ref", node.ref);
            builder.fieldBytes("node.label", node.label);
        }
        for (self.edges) |edge| {
            builder.fieldBytes("edge.kind", @tagName(edge.kind));
            builder.fieldRef("edge.from", edge.from);
            builder.fieldRef("edge.to", edge.to);
            builder.fieldBytes("edge.label", edge.label);
        }
        writeCanonicalDependencies(&builder, self.dependencies);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refFor(domains.boundary_closure_graph, self.fingerprint, .{ .label = self.label });
    }
};

pub const BoundaryClosureReport = struct {
    summary: []const u8 = "boundary closure report",
    report_fingerprint: u64,
    graph_fingerprint: u64,
    root_program_refs: []const Ref = &.{},
    provider_harness_refs: []const Ref = &.{},
    provider_program_refs: []const Ref = &.{},
    effect_shape_count: usize = 0,
    closed_effect_shape_count: usize = 0,
    open_world_port_count: usize = 0,
    host_intrinsic_count: usize = 0,
    unknown_body_count: usize = 0,
    blocker_count: usize = 0,
    ambiguity_count: usize = 0,
    boundary_native_route_count: usize = 0,
    declarative_route_count: usize = 0,
    residualized_pipeline_route_count: usize = 0,
    intrinsic_route_count: usize = 0,
    world_port_refs: []const Ref = &.{},
    host_intrinsic_refs: []const Ref = &.{},
    unknown_refs: []const Ref = &.{},
    blockers: []const Blocker = &.{},
    dependencies: []const Dependency = &.{},
    policy_summary: ?PolicySummary = null,

    pub const Options = struct {
        graph_fingerprint: u64,
        root_program_refs: []const Ref = &.{},
        provider_harness_refs: []const Ref = &.{},
        provider_program_refs: []const Ref = &.{},
        effect_shape_count: usize = 0,
        closed_effect_shape_count: usize = 0,
        open_world_port_count: usize = 0,
        host_intrinsic_count: usize = 0,
        unknown_body_count: usize = 0,
        blocker_count: usize = 0,
        ambiguity_count: usize = 0,
        boundary_native_route_count: usize = 0,
        declarative_route_count: usize = 0,
        residualized_pipeline_route_count: usize = 0,
        intrinsic_route_count: usize = 0,
        world_port_refs: []const Ref = &.{},
        host_intrinsic_refs: []const Ref = &.{},
        unknown_refs: []const Ref = &.{},
        blockers: []const Blocker = &.{},
        dependencies: []const Dependency = &.{},
        policy_summary: ?PolicySummary = null,
        summary: []const u8 = "boundary closure report",
    };

    pub fn init(options: Options) @This() {
        var report = @This(){
            .summary = options.summary,
            .report_fingerprint = 0,
            .graph_fingerprint = options.graph_fingerprint,
            .root_program_refs = options.root_program_refs,
            .provider_harness_refs = options.provider_harness_refs,
            .provider_program_refs = options.provider_program_refs,
            .effect_shape_count = options.effect_shape_count,
            .closed_effect_shape_count = options.closed_effect_shape_count,
            .open_world_port_count = options.open_world_port_count,
            .host_intrinsic_count = options.host_intrinsic_count,
            .unknown_body_count = options.unknown_body_count,
            .blocker_count = options.blocker_count,
            .ambiguity_count = options.ambiguity_count,
            .boundary_native_route_count = options.boundary_native_route_count,
            .declarative_route_count = options.declarative_route_count,
            .residualized_pipeline_route_count = options.residualized_pipeline_route_count,
            .intrinsic_route_count = options.intrinsic_route_count,
            .world_port_refs = options.world_port_refs,
            .host_intrinsic_refs = options.host_intrinsic_refs,
            .unknown_refs = options.unknown_refs,
            .blockers = options.blockers,
            .dependencies = options.dependencies,
            .policy_summary = options.policy_summary,
        };
        report.report_fingerprint = report.computeFingerprint();
        return report;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_closure_report);
        builder.fieldU64("graph", self.graph_fingerprint);
        for (self.root_program_refs) |ref| builder.fieldRef("root", ref);
        for (self.provider_harness_refs) |ref| builder.fieldRef("provider_harness", ref);
        for (self.provider_program_refs) |ref| builder.fieldRef("provider_program", ref);
        builder.fieldUsize("effect_shape_count", self.effect_shape_count);
        builder.fieldUsize("closed_effect_shape_count", self.closed_effect_shape_count);
        builder.fieldUsize("open_world_port_count", self.open_world_port_count);
        builder.fieldUsize("host_intrinsic_count", self.host_intrinsic_count);
        builder.fieldUsize("unknown_body_count", self.unknown_body_count);
        builder.fieldUsize("blocker_count", self.blocker_count);
        builder.fieldUsize("ambiguity_count", self.ambiguity_count);
        builder.fieldUsize("boundary_native_route_count", self.boundary_native_route_count);
        builder.fieldUsize("declarative_route_count", self.declarative_route_count);
        builder.fieldUsize("residualized_pipeline_route_count", self.residualized_pipeline_route_count);
        builder.fieldUsize("intrinsic_route_count", self.intrinsic_route_count);
        for (self.world_port_refs) |ref| builder.fieldRef("world_port", ref);
        for (self.host_intrinsic_refs) |ref| builder.fieldRef("host_intrinsic", ref);
        for (self.unknown_refs) |ref| builder.fieldRef("unknown", ref);
        for (self.blockers) |blocker| builder.fieldU64("blocker", blocker.fingerprint());
        writeCanonicalDependencies(&builder, self.dependencies);
        if (self.policy_summary) |policy| builder.fieldU64("policy", policy.policy_fingerprint);
        builder.fieldBytes("summary", self.summary);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refFor(domains.boundary_closure_report, self.report_fingerprint, .{ .label = self.summary });
    }

    pub fn closed(self: @This()) bool {
        return self.blocker_count == 0 and self.effect_shape_count == self.closed_effect_shape_count;
    }

    pub fn closedExceptWorldPorts(self: @This()) bool {
        return self.blocker_count == 0 and self.closed_effect_shape_count + self.open_world_port_count >= self.effect_shape_count;
    }

    pub fn toEvidenceReport(self: @This()) Report {
        const policy_fingerprint = if (self.policy_summary) |policy| policy.policy_fingerprint else null;
        if (self.blocker_count != 0 or hasErrorBlockers(self.blockers)) {
            return Report.withFailure(self.evidenceRef(), domains.boundary_closure_report.id, self.dependencies, self.blockers, &.{}, policy_fingerprint, self.summary);
        }
        return Report.ok(self.evidenceRef(), domains.boundary_closure_report.id, self.dependencies);
    }
};

pub const BoundaryClosureCertificate = struct {
    certificate_format_version: u32 = 1,
    certificate_fingerprint: u64,
    closure_report_fingerprint: u64,
    closure_graph_fingerprint: u64,
    policy_ref: Ref,
    policy_fingerprint: u64,
    root_refs: []const Ref = &.{},
    provider_refs: []const Ref = &.{},
    provider_program_refs: []const Ref = &.{},
    policy_refs: []const Ref = &.{},
    world_port_refs: []const Ref = &.{},
    intrinsic_refs: []const Ref = &.{},
    selected_static_treaty_plan_refs: []const Ref = &.{},
    blocker_refs: []const Ref = &.{},
    effect_shape_count: usize = 0,
    closed_effect_shape_count: usize = 0,
    world_port_count: usize = 0,
    blocker_count: usize = 0,
    summary: []const u8 = "boundary closure certificate",

    pub fn init(report: BoundaryClosureReport, graph: BoundaryGraph, policy: BoundaryClosurePolicy, plan_refs: []const Ref) @This() {
        var certificate = @This(){
            .certificate_fingerprint = 0,
            .closure_report_fingerprint = report.report_fingerprint,
            .closure_graph_fingerprint = graph.fingerprint,
            .policy_ref = policy.evidenceRef(),
            .policy_fingerprint = policy.fingerprint(),
            .root_refs = report.root_program_refs,
            .provider_refs = report.provider_harness_refs,
            .provider_program_refs = report.provider_program_refs,
            .policy_refs = &.{},
            .world_port_refs = report.world_port_refs,
            .intrinsic_refs = report.host_intrinsic_refs,
            .selected_static_treaty_plan_refs = plan_refs,
            .effect_shape_count = report.effect_shape_count,
            .closed_effect_shape_count = report.closed_effect_shape_count,
            .world_port_count = report.open_world_port_count,
            .blocker_count = report.blocker_count,
        };
        certificate.certificate_fingerprint = certificate.computeFingerprint();
        return certificate;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_closure_certificate);
        builder.fieldU32("format_version", self.certificate_format_version);
        builder.fieldU64("report", self.closure_report_fingerprint);
        builder.fieldU64("graph", self.closure_graph_fingerprint);
        builder.fieldRef("policy_ref", self.policy_ref);
        builder.fieldU64("policy_fingerprint", self.policy_fingerprint);
        for (self.root_refs) |ref| builder.fieldRef("root", ref);
        for (self.provider_refs) |ref| builder.fieldRef("provider", ref);
        for (self.provider_program_refs) |ref| builder.fieldRef("provider_program", ref);
        for (self.policy_refs) |ref| builder.fieldRef("policy", ref);
        for (self.world_port_refs) |ref| builder.fieldRef("world_port", ref);
        for (self.intrinsic_refs) |ref| builder.fieldRef("intrinsic", ref);
        for (self.selected_static_treaty_plan_refs) |ref| builder.fieldRef("static_treaty_plan", ref);
        for (self.blocker_refs) |ref| builder.fieldRef("blocker", ref);
        builder.fieldUsize("effect_shape_count", self.effect_shape_count);
        builder.fieldUsize("closed_effect_shape_count", self.closed_effect_shape_count);
        builder.fieldUsize("world_port_count", self.world_port_count);
        builder.fieldUsize("blocker_count", self.blocker_count);
        builder.fieldBytes("summary", self.summary);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refFor(domains.boundary_closure_certificate, self.certificate_fingerprint, .{
            .format_version = domains.boundary_closure_certificate.format_version,
            .label = self.summary,
        });
    }

    pub fn check(self: @This(), graph: BoundaryGraph, report: BoundaryClosureReport, policy: BoundaryClosurePolicy) error{
        BoundaryClosureGraphMismatch,
        BoundaryClosureReportMismatch,
        BoundaryClosureCertificateMismatch,
        BoundaryClosurePolicyMismatch,
        BoundaryClosureNotClosed,
        BoundaryClosureWorldPortsRejected,
        BoundaryClosureUnknownBodies,
        BoundaryClosureIntrinsicRejected,
        BoundaryClosureAmbiguous,
    }!void {
        if (self.closure_graph_fingerprint != graph.fingerprint) return error.BoundaryClosureGraphMismatch;
        if (self.closure_report_fingerprint != report.report_fingerprint) return error.BoundaryClosureReportMismatch;
        if (self.certificate_fingerprint != self.computeFingerprint()) return error.BoundaryClosureCertificateMismatch;
        if (!self.policy_ref.eql(policy.evidenceRef()) or self.policy_fingerprint != policy.fingerprint()) return error.BoundaryClosurePolicyMismatch;
        if (policy.require_all_effect_shapes_closed) {
            if (policy.allow_world_ports) {
                if (!report.closedExceptWorldPorts()) return error.BoundaryClosureNotClosed;
            } else {
                if (!report.closed()) return error.BoundaryClosureNotClosed;
            }
        }
        if (!policy.allow_world_ports and report.open_world_port_count != 0) return error.BoundaryClosureWorldPortsRejected;
        if (policy.reject_unknown_semantic_bodies and report.unknown_body_count != 0) return error.BoundaryClosureUnknownBodies;
        if (policy.reject_host_intrinsics and report.host_intrinsic_count != 0) return error.BoundaryClosureIntrinsicRejected;
        if (policy.reject_ambiguous_routes and report.ambiguity_count != 0) return error.BoundaryClosureAmbiguous;
    }

    pub fn evidenceView(self: @This(), dependencies: []const Dependency, report: BoundaryClosureReport, _: BoundaryClosurePolicy) CertificateView {
        return .{
            .certificate_ref = self.evidenceRef(),
            .subject_ref = report.evidenceRef(),
            .domain = domains.boundary_closure_certificate.id,
            .dependencies = dependencies,
            .report_fingerprint = report.report_fingerprint,
            .policy_ref = self.policy_ref,
            .policy_fingerprint = self.policy_fingerprint,
            .certificate_fingerprint = self.certificate_fingerprint,
            .summary = self.summary,
        };
    }
};

pub fn BoundaryClosure(comptime ProgramType: type) type {
    return struct {
        pub const Policy = BoundaryClosurePolicy;
        pub const EffectShape = BoundaryEffectShape;
        pub const WorldPort = BoundaryWorldPort;
        pub const StaticTreatyPlan = BoundaryStaticTreatyPlan;
        pub const Graph = BoundaryGraph;
        pub const Report = BoundaryClosureReport;
        pub const Certificate = BoundaryClosureCertificate;
        const Closure = @This();

        pub const ProviderProgram = struct {
            provider_ref: Ref,
            program_ref: Ref,
            shapes: []const Closure.EffectShape = &.{},
        };

        pub const Input = struct {
            allocator: std.mem.Allocator,
            root_shapes: []const Closure.EffectShape = &.{},
            provider_programs: []const ProviderProgram = &.{},
            provider_manifests: []const ProgramType.Exchange.ProviderManifest = &.{},
            provider_offers: []const ProgramType.Exchange.ProviderOffer = &.{},
            morphism_offers: []const ProgramType.Exchange.MorphismOffer = &.{},
            capabilities: []const ProgramType.Exchange.Capability = &.{},
            treaty_policy: ProgramType.Exchange.Treaty.Policy = .{},
            policy: Policy = Policy.strict(),
            world_ports: []const Closure.WorldPort = &.{},
            root_program_refs: []const Ref = &.{},
            provider_harness_refs: []const Ref = &.{},
        };

        pub const PlanInputs = struct {
            allocator: std.mem.Allocator,
            shape: Closure.EffectShape,
            provider_manifests: []const ProgramType.Exchange.ProviderManifest = &.{},
            provider_offers: []const ProgramType.Exchange.ProviderOffer = &.{},
            morphism_offers: []const ProgramType.Exchange.MorphismOffer = &.{},
            capabilities: []const ProgramType.Exchange.Capability = &.{},
            treaty_policy: ProgramType.Exchange.Treaty.Policy = .{},
            policy: Policy = Policy.strict(),
            world_ports: []const Closure.WorldPort = &.{},
        };

        pub const Result = struct {
            allocator: std.mem.Allocator,
            graph: Graph,
            report: Closure.Report,
            certificate: Certificate,
            static_treaty_plans: []StaticTreatyPlan = &.{},
            blockers: []Blocker = &.{},
            plan_refs: []Ref = &.{},
            provider_program_refs: []Ref = &.{},
            world_port_refs: []Ref = &.{},
            host_intrinsic_refs: []Ref = &.{},
            unknown_refs: []Ref = &.{},

            pub fn deinit(self: *@This()) void {
                for (self.static_treaty_plans) |plan| {
                    self.allocator.free(plan.blockers);
                    self.allocator.free(plan.dependencies);
                }
                self.allocator.free(self.static_treaty_plans);
                self.allocator.free(self.blockers);
                self.allocator.free(self.plan_refs);
                self.allocator.free(self.provider_program_refs);
                self.allocator.free(self.world_port_refs);
                self.allocator.free(self.host_intrinsic_refs);
                self.allocator.free(self.unknown_refs);
                self.allocator.free(self.graph.nodes);
                self.allocator.free(self.graph.edges);
            }

            pub fn assertClosed(self: @This()) error{BoundaryClosureNotClosed}!void {
                if (!self.report.closed()) return error.BoundaryClosureNotClosed;
            }

            pub fn assertClosedExceptWorldPorts(self: @This()) error{BoundaryClosureNotClosed}!void {
                if (!self.report.closedExceptWorldPorts()) return error.BoundaryClosureNotClosed;
            }

            pub fn writeSummary(self: @This(), writer: anytype) !void {
                try writer.print("closure={s} effect_shapes={} closed={} world_ports={} host_intrinsics={} blockers={} certificate={x}\n", .{
                    if (self.report.closedExceptWorldPorts()) "closed" else "blocked",
                    self.report.effect_shape_count,
                    self.report.closed_effect_shape_count,
                    self.report.open_world_port_count,
                    self.report.host_intrinsic_count,
                    self.report.blocker_count,
                    self.certificate.certificate_fingerprint,
                });
            }
        };

        pub fn effectShapesForProgram(comptime RootProgram: type, comptime kind: Closure.EffectShape.Kind) [RootProgram.contract.session.yield_sites.len + RootProgram.contract.session.after_sites.len]Closure.EffectShape {
            @setEvalBranchQuota(20_000);
            var shapes: [RootProgram.contract.session.yield_sites.len + RootProgram.contract.session.after_sites.len]Closure.EffectShape = undefined;
            var index: usize = 0;
            inline for (RootProgram.contract.session.yield_sites) |site| {
                shapes[index] = operationShape(RootProgram, site, kind);
                index += 1;
            }
            inline for (RootProgram.contract.session.after_sites) |site| {
                shapes[index] = afterShape(RootProgram, site, kind);
                index += 1;
            }
            return shapes;
        }

        pub fn operationShape(comptime RootProgram: type, comptime site: anytype, comptime kind: Closure.EffectShape.Kind) Closure.EffectShape {
            return Closure.EffectShape.init(.{
                .program_label = RootProgram.contract.label,
                .plan_label = RootProgram.compiled_plan.label,
                .plan_hash = RootProgram.compiled_plan.hash(),
                .kind = kind,
                .site_index = site.index,
                .site_fingerprint = site.fingerprint,
                .semantic_label = site.semantic_label,
                .name = site.op_name,
                .mode = @tagName(site.op_mode),
                .value_ref = BoundaryValueRef.fromValueRef(site.payload_ref),
                .expected_resume_ref = BoundaryValueRef.fromValueRef(site.resume_ref),
                .result_ref = BoundaryValueRef.fromValueRef(site.result_ref),
                .protocol_label = site.requirement_label,
                .protocol_op_fingerprint = site.fingerprint,
            });
        }

        pub fn afterShape(comptime RootProgram: type, comptime site: anytype, comptime kind: Closure.EffectShape.Kind) Closure.EffectShape {
            return Closure.EffectShape.init(.{
                .program_label = RootProgram.contract.label,
                .plan_label = RootProgram.compiled_plan.label,
                .plan_hash = RootProgram.compiled_plan.hash(),
                .kind = kind,
                .site_index = site.index,
                .site_fingerprint = site.fingerprint,
                .semantic_label = site.semantic_label,
                .name = site.original_op_name,
                .mode = "after",
                .result_ref = BoundaryValueRef.fromValueRef(site.result_ref),
                .protocol_label = site.original_requirement_label,
                .protocol_op_fingerprint = site.source_operation_site_fingerprint,
            });
        }

        pub fn planTreatyForShape(inputs: PlanInputs) !StaticTreatyPlan {
            var blockers = std.ArrayList(BoundaryClosureBlocker).empty;
            defer blockers.deinit(inputs.allocator);
            var dependencies = std.ArrayList(Dependency).empty;
            defer dependencies.deinit(inputs.allocator);

            try dependencies.append(inputs.allocator, .{ .role = .effect_shape, .ref = inputs.shape.evidenceRef() });
            const selected = try selectShapeCandidate(inputs, &blockers, &dependencies);
            const owned_blockers = try blockers.toOwnedSlice(inputs.allocator);
            errdefer inputs.allocator.free(owned_blockers);
            const owned_dependencies = try dependencies.toOwnedSlice(inputs.allocator);
            errdefer inputs.allocator.free(owned_dependencies);
            return StaticTreatyPlan.init(.{
                .label = inputs.shape.name,
                .source_shape = inputs.shape,
                .direct_candidate_count = selected.direct_count,
                .morphism_candidate_count = selected.morphism_count,
                .selected_provider_offer_ref = selected.offer_ref,
                .selected_provider_ref = selected.provider_ref,
                .selected_capability_ref = selected.capability_ref,
                .selected_morphism_ref = selected.morphism_ref,
                .selected_semantic_body = selected.body,
                .selected_intrinsic_ref = selected.intrinsic_ref,
                .boundary_native = selected.body == .boundary_program or selected.body == .declarative or selected.body == .residualized_program or selected.body == .pipeline or selected.body == .kernel_primitive,
                .host_intrinsic = selected.body == .host_intrinsic,
                .runtime_request_value_validation_required = true,
                .byte_size_runtime_guard_required = true,
                .blockers = owned_blockers,
                .dependencies = owned_dependencies,
            });
        }

        pub fn analyze(allocator: std.mem.Allocator, input: Input) !Result {
            var all_plans = std.ArrayList(StaticTreatyPlan).empty;
            errdefer {
                for (all_plans.items) |plan| {
                    allocator.free(plan.blockers);
                    allocator.free(plan.dependencies);
                }
                all_plans.deinit(allocator);
            }
            var blockers = std.ArrayList(Blocker).empty;
            errdefer blockers.deinit(allocator);
            var plan_refs = std.ArrayList(Ref).empty;
            errdefer plan_refs.deinit(allocator);
            var provider_program_refs = std.ArrayList(Ref).empty;
            errdefer provider_program_refs.deinit(allocator);
            var world_port_refs = std.ArrayList(Ref).empty;
            errdefer world_port_refs.deinit(allocator);
            var host_intrinsic_refs = std.ArrayList(Ref).empty;
            errdefer host_intrinsic_refs.deinit(allocator);
            var unknown_refs = std.ArrayList(Ref).empty;
            errdefer unknown_refs.deinit(allocator);
            var nodes = std.ArrayList(Graph.Node).empty;
            errdefer nodes.deinit(allocator);
            var edges = std.ArrayList(Graph.Edge).empty;
            errdefer edges.deinit(allocator);

            if (input.root_shapes.len == 0) {
                try blockers.append(allocator, boundaryClosureBlocker(.{
                    .tag = .root_program_missing,
                    .summary = "closure input contains no root effect shapes",
                }));
            }

            var closed_count: usize = 0;
            var boundary_native_count: usize = 0;
            var intrinsic_count: usize = 0;
            var ambiguity_count: usize = 0;

            if (input.provider_programs.len > input.policy.max_nested_provider_depth) {
                try blockers.append(allocator, boundaryClosureBlocker(.{
                    .tag = .depth_limit_exceeded,
                    .summary = "provider program nesting exceeds closure policy depth bound",
                }));
            }
            try analyzeShapes(allocator, input, input.root_shapes, &all_plans, &blockers, &plan_refs, &world_port_refs, &host_intrinsic_refs, &unknown_refs, &nodes, &edges, &closed_count, &boundary_native_count, &intrinsic_count, &ambiguity_count, true);
            for (input.provider_programs, 0..) |provider_program, index| {
                for (input.provider_programs[0..index]) |previous| {
                    if (previous.program_ref.eql(provider_program.program_ref)) {
                        try blockers.append(allocator, boundaryClosureBlocker(.{
                            .tag = .cycle_detected,
                            .subject = provider_program.program_ref,
                            .primary = previous.program_ref,
                            .summary = "provider program closure input repeats a provider program ref",
                        }));
                        break;
                    }
                }
                try provider_program_refs.append(allocator, provider_program.program_ref);
                try nodes.append(allocator, .{ .kind = .provider_program, .ref = provider_program.program_ref, .label = "provider program" });
                try analyzeShapes(allocator, input, provider_program.shapes, &all_plans, &blockers, &plan_refs, &world_port_refs, &host_intrinsic_refs, &unknown_refs, &nodes, &edges, &closed_count, &boundary_native_count, &intrinsic_count, &ambiguity_count, false);
            }

            std.sort.insertion(Graph.Node, nodes.items, {}, graphNodeLessThan);
            std.sort.insertion(Graph.Edge, edges.items, {}, graphEdgeLessThan);
            const owned_plans = try all_plans.toOwnedSlice(allocator);
            errdefer {
                for (owned_plans) |plan| {
                    allocator.free(plan.blockers);
                    allocator.free(plan.dependencies);
                }
                allocator.free(owned_plans);
            }
            const owned_blockers = try blockers.toOwnedSlice(allocator);
            errdefer allocator.free(owned_blockers);
            const owned_plan_refs = try plan_refs.toOwnedSlice(allocator);
            errdefer allocator.free(owned_plan_refs);
            const owned_provider_program_refs = try provider_program_refs.toOwnedSlice(allocator);
            errdefer allocator.free(owned_provider_program_refs);
            const owned_world_port_refs = try world_port_refs.toOwnedSlice(allocator);
            errdefer allocator.free(owned_world_port_refs);
            const owned_host_intrinsic_refs = try host_intrinsic_refs.toOwnedSlice(allocator);
            errdefer allocator.free(owned_host_intrinsic_refs);
            const owned_unknown_refs = try unknown_refs.toOwnedSlice(allocator);
            errdefer allocator.free(owned_unknown_refs);
            const owned_nodes = try nodes.toOwnedSlice(allocator);
            errdefer allocator.free(owned_nodes);
            const owned_edges = try edges.toOwnedSlice(allocator);
            errdefer allocator.free(owned_edges);

            const graph = Graph.init("boundary-closure-graph", owned_nodes, owned_edges, &.{});
            const report = Closure.Report.init(.{
                .graph_fingerprint = graph.fingerprint,
                .root_program_refs = input.root_program_refs,
                .provider_harness_refs = input.provider_harness_refs,
                .provider_program_refs = owned_provider_program_refs,
                .effect_shape_count = input.root_shapes.len + providerShapeCount(input.provider_programs),
                .closed_effect_shape_count = closed_count,
                .open_world_port_count = owned_world_port_refs.len,
                .host_intrinsic_count = intrinsic_count,
                .unknown_body_count = owned_unknown_refs.len,
                .blocker_count = owned_blockers.len,
                .ambiguity_count = ambiguity_count,
                .boundary_native_route_count = boundary_native_count,
                .intrinsic_route_count = intrinsic_count,
                .world_port_refs = owned_world_port_refs,
                .host_intrinsic_refs = owned_host_intrinsic_refs,
                .unknown_refs = owned_unknown_refs,
                .blockers = owned_blockers,
                .policy_summary = input.policy.policySummary(),
            });
            const certificate = Certificate.init(report, graph, input.policy, owned_plan_refs);
            return .{
                .allocator = allocator,
                .graph = graph,
                .report = report,
                .certificate = certificate,
                .static_treaty_plans = owned_plans,
                .blockers = owned_blockers,
                .plan_refs = owned_plan_refs,
                .provider_program_refs = owned_provider_program_refs,
                .world_port_refs = owned_world_port_refs,
                .host_intrinsic_refs = owned_host_intrinsic_refs,
                .unknown_refs = owned_unknown_refs,
            };
        }

        const CandidateSelection = struct {
            direct_count: usize = 0,
            morphism_count: usize = 0,
            offer_ref: ?Ref = null,
            provider_ref: ?Ref = null,
            capability_ref: ?Ref = null,
            morphism_ref: ?Ref = null,
            intrinsic_ref: ?Ref = null,
            body: SemanticBody = .unknown,
            selected_rank: u8 = std.math.maxInt(u8),
            selected_rank_count: usize = 0,
        };

        fn selectShapeCandidate(inputs: PlanInputs, blockers: *std.ArrayList(BoundaryClosureBlocker), dependencies: *std.ArrayList(Dependency)) !CandidateSelection {
            var selection: CandidateSelection = .{};
            for (inputs.provider_offers) |offer| {
                if (!offerMatchesShape(offer, inputs.shape)) continue;
                const capability = capabilityForShape(inputs.capabilities, offer, inputs.shape) orelse {
                    try blockers.append(inputs.allocator, .{ .tag = .no_capability_for_shape, .subject = inputs.shape.evidenceRef(), .primary = offer.evidenceRef(), .summary = "provider offer has no static capability grant for this effect shape" });
                    continue;
                };
                const provider = providerManifestForOffer(inputs.provider_manifests, offer);
                const body = if (offer.providerProgramMappingAttested()) SemanticBody.boundary_program else if (provider) |manifest| offer.semanticBodyWithProvider(manifest) else offer.semanticBody();
                if (body == .unknown and inputs.policy.reject_unknown_semantic_bodies) {
                    try blockers.append(inputs.allocator, .{ .tag = .unknown_semantic_body, .subject = inputs.shape.evidenceRef(), .primary = offer.evidenceRef(), .summary = "provider offer semantic body is unknown" });
                    continue;
                }
                const intrinsic_ref = offer.hostIntrinsicRef();
                if (body == .host_intrinsic) {
                    if (intrinsic_ref) |ref| {
                        if (!inputAllowsIntrinsicOrWorldPort(inputs, ref, inputs.shape)) {
                            try blockers.append(inputs.allocator, .{ .tag = .unallowlisted_intrinsic, .subject = inputs.shape.evidenceRef(), .primary = ref, .summary = "host-intrinsic provider is not allowlisted or exposed as a world port" });
                            continue;
                        }
                    } else if (inputs.policy.reject_host_intrinsics) {
                        try blockers.append(inputs.allocator, .{ .tag = .intrinsic_route_rejected, .subject = inputs.shape.evidenceRef(), .primary = offer.evidenceRef(), .summary = "host-intrinsic provider route lacks an intrinsic evidence ref" });
                        continue;
                    }
                }
                selection.direct_count += 1;
                try dependencies.append(inputs.allocator, .{ .role = .offer, .ref = offer.evidenceRef() });
                try dependencies.append(inputs.allocator, .{ .role = .capability, .ref = capability.evidenceRef() });
                const rank = candidateRank(inputs.policy, body);
                if (betterCandidate(inputs.policy, selection, body, offer.evidenceRef())) {
                    selection.offer_ref = offer.evidenceRef();
                    selection.provider_ref = if (provider) |manifest| manifest.evidenceRef() else null;
                    selection.capability_ref = capability.evidenceRef();
                    selection.body = body;
                    selection.intrinsic_ref = intrinsic_ref;
                    selection.selected_rank = rank;
                    selection.selected_rank_count = 1;
                } else if (rank == selection.selected_rank) {
                    selection.selected_rank_count += 1;
                }
            }

            for (inputs.morphism_offers) |morphism| {
                if (!morphismMatchesShape(morphism, inputs.shape)) continue;
                selection.morphism_count += 1;
                try dependencies.append(inputs.allocator, .{ .role = .morphism, .ref = morphism.evidenceRef() });
                const body = morphism.semanticBody();
                if (body == .host_intrinsic and inputs.treaty_policy.reject_intrinsic_morphism) {
                    try blockers.append(inputs.allocator, .{ .tag = .dynamic_mapper_rejected, .subject = inputs.shape.evidenceRef(), .primary = morphism.evidenceRef(), .summary = "dynamic intrinsic morphism mapper rejected by treaty policy" });
                    continue;
                }
                if (body == .residualized_program or body == .pipeline) {
                    morphism_provider_offers: for (inputs.provider_offers) |offer| {
                        if (!offerMatchesMorphismTarget(offer, morphism)) continue :morphism_provider_offers;
                        const capability = capabilityForShape(inputs.capabilities, offer, inputs.shape) orelse continue :morphism_provider_offers;
                        const provider = providerManifestForOffer(inputs.provider_manifests, offer);
                        const provider_body = if (offer.providerProgramMappingAttested()) SemanticBody.boundary_program else if (provider) |manifest| offer.semanticBodyWithProvider(manifest) else offer.semanticBody();
                        const rank = candidateRank(inputs.policy, provider_body);
                        if (betterCandidate(inputs.policy, selection, provider_body, offer.evidenceRef())) {
                            selection.offer_ref = offer.evidenceRef();
                            selection.provider_ref = if (provider) |manifest| manifest.evidenceRef() else null;
                            selection.capability_ref = capability.evidenceRef();
                            selection.morphism_ref = morphism.evidenceRef();
                            selection.body = provider_body;
                            selection.intrinsic_ref = offer.hostIntrinsicRef();
                            selection.selected_rank = rank;
                            selection.selected_rank_count = 1;
                        } else if (rank == selection.selected_rank) {
                            selection.selected_rank_count += 1;
                        }
                    }
                }
            }

            if (selection.offer_ref == null) {
                if (selection.direct_count == 0 and selection.morphism_count == 0) {
                    try blockers.append(inputs.allocator, .{ .tag = .no_provider_offer_for_shape, .subject = inputs.shape.evidenceRef(), .summary = "no provider offer can handle this effect shape" });
                } else {
                    try blockers.append(inputs.allocator, .{ .tag = .no_static_treaty_plan, .subject = inputs.shape.evidenceRef(), .summary = "candidate offers exist but no static route satisfies policy and capability constraints" });
                }
            } else if (inputs.policy.reject_ambiguous_routes and (selection.selected_rank_count > 1 or selection.direct_count > 1)) {
                try blockers.append(inputs.allocator, .{ .tag = .ambiguous_static_treaty_plan, .subject = inputs.shape.evidenceRef(), .primary = selection.offer_ref, .summary = "multiple static treaty routes remain unresolved" });
            }
            return selection;
        }

        fn analyzeShapes(
            allocator: std.mem.Allocator,
            input: Input,
            shapes: []const Closure.EffectShape,
            all_plans: *std.ArrayList(StaticTreatyPlan),
            blockers: *std.ArrayList(Blocker),
            plan_refs: *std.ArrayList(Ref),
            world_port_refs: *std.ArrayList(Ref),
            host_intrinsic_refs: *std.ArrayList(Ref),
            unknown_refs: *std.ArrayList(Ref),
            nodes: *std.ArrayList(Graph.Node),
            edges: *std.ArrayList(Graph.Edge),
            closed_count: *usize,
            boundary_native_count: *usize,
            intrinsic_count: *usize,
            ambiguity_count: *usize,
            root: bool,
        ) !void {
            for (shapes) |shape| {
                const shape_ref = shape.evidenceRef();
                try nodes.append(allocator, .{ .kind = if (shape.kind == .after) .after_site else .operation_site, .ref = shape_ref, .label = shape.name });
                const plan = try planTreatyForShape(.{
                    .allocator = allocator,
                    .shape = shape,
                    .provider_manifests = input.provider_manifests,
                    .provider_offers = input.provider_offers,
                    .morphism_offers = input.morphism_offers,
                    .capabilities = input.capabilities,
                    .treaty_policy = input.treaty_policy,
                    .policy = input.policy,
                    .world_ports = input.world_ports,
                });
                try all_plans.append(allocator, plan);
                try plan_refs.append(allocator, plan.evidenceRef());
                try nodes.append(allocator, .{ .kind = .treaty_shape_plan, .ref = plan.evidenceRef(), .label = plan.label });
                try edges.append(allocator, .{ .kind = .treaty_planned, .from = shape_ref, .to = plan.evidenceRef() });
                if (plan.selected_provider_offer_ref) |offer_ref| {
                    try nodes.append(allocator, .{ .kind = .provider_offer, .ref = offer_ref, .label = "provider offer" });
                    try edges.append(allocator, .{ .kind = .handled_by_provider, .from = shape_ref, .to = offer_ref });
                }
                if (plan.selected_capability_ref) |cap_ref| {
                    try nodes.append(allocator, .{ .kind = .capability_grant, .ref = cap_ref, .label = "capability" });
                    try edges.append(allocator, .{ .kind = .authorized_by_capability, .from = shape_ref, .to = cap_ref });
                }
                if (plan.selected_morphism_ref) |morphism_ref| {
                    try nodes.append(allocator, .{ .kind = .morphism_offer, .ref = morphism_ref, .label = "morphism" });
                    try edges.append(allocator, .{ .kind = .adapted_by_morphism, .from = shape_ref, .to = morphism_ref });
                }
                if (plan.selected_intrinsic_ref) |intrinsic_ref| {
                    try host_intrinsic_refs.append(allocator, intrinsic_ref);
                    intrinsic_count.* += 1;
                    try nodes.append(allocator, .{ .kind = .host_intrinsic, .ref = intrinsic_ref, .label = "host intrinsic" });
                    try edges.append(allocator, .{ .kind = .intrinsic_boundary, .from = shape_ref, .to = intrinsic_ref });
                    if (worldPortForShape(input.policy, input.world_ports, shape, intrinsic_ref)) |port| {
                        try world_port_refs.append(allocator, port.evidenceRef());
                        try nodes.append(allocator, .{ .kind = .world_port, .ref = port.evidenceRef(), .label = port.label });
                        try edges.append(allocator, .{ .kind = .world_port_exposes, .from = intrinsic_ref, .to = port.evidenceRef() });
                    }
                }
                if (plan.selected_semantic_body == .unknown) try unknown_refs.append(allocator, shape_ref);
                if (plan.closed()) {
                    closed_count.* += 1;
                    if (plan.boundary_native) boundary_native_count.* += 1;
                }
                for (plan.blockers) |closure_blocker| {
                    const evidence_blocker = closure_blocker.toEvidenceBlocker();
                    try blockers.append(allocator, evidence_blocker);
                    try nodes.append(allocator, .{ .kind = .blocker, .ref = refFor(domains.boundary_closure_report, evidence_blocker.fingerprint(), .{ .kind_tag = @tagName(closure_blocker.tag) }), .label = closure_blocker.summary });
                    if (closure_blocker.tag == .ambiguous_static_treaty_plan) ambiguity_count.* += 1;
                }
                _ = root;
            }
        }

        fn providerShapeCount(programs: []const ProviderProgram) usize {
            var count: usize = 0;
            for (programs) |program| count += program.shapes.len;
            return count;
        }

        fn graphNodeLessThan(_: void, lhs: Graph.Node, rhs: Graph.Node) bool {
            if (@intFromEnum(lhs.kind) != @intFromEnum(rhs.kind)) return @intFromEnum(lhs.kind) < @intFromEnum(rhs.kind);
            if (lhs.ref.fingerprint != rhs.ref.fingerprint) return lhs.ref.fingerprint < rhs.ref.fingerprint;
            return std.mem.lessThan(u8, lhs.label, rhs.label);
        }

        fn graphEdgeLessThan(_: void, lhs: Graph.Edge, rhs: Graph.Edge) bool {
            if (@intFromEnum(lhs.kind) != @intFromEnum(rhs.kind)) return @intFromEnum(lhs.kind) < @intFromEnum(rhs.kind);
            if (lhs.from.fingerprint != rhs.from.fingerprint) return lhs.from.fingerprint < rhs.from.fingerprint;
            if (lhs.to.fingerprint != rhs.to.fingerprint) return lhs.to.fingerprint < rhs.to.fingerprint;
            return std.mem.lessThan(u8, lhs.label, rhs.label);
        }

        fn betterCandidate(policy: Policy, current: CandidateSelection, body: SemanticBody, offer_ref: Ref) bool {
            if (current.offer_ref == null) return true;
            if (policy.prefer_boundary_native) {
                const current_native = current.body.isNonIntrinsic();
                const candidate_native = body.isNonIntrinsic();
                if (candidate_native != current_native) return candidate_native;
            }
            return offer_ref.fingerprint < current.offer_ref.?.fingerprint;
        }

        fn candidateRank(policy: Policy, body: SemanticBody) u8 {
            if (policy.prefer_boundary_native and body.isNonIntrinsic()) return 0;
            if (body == .host_intrinsic) return 2;
            if (body == .unknown) return 3;
            return 1;
        }

        fn providerManifestForOffer(providers: []const ProgramType.Exchange.ProviderManifest, offer: ProgramType.Exchange.ProviderOffer) ?ProgramType.Exchange.ProviderManifest {
            for (providers) |provider| {
                if (provider.provider_fingerprint == offer.provider_fingerprint and listAllowsU64Closure(provider.supported_program_manifest_fingerprints, offer.manifest_fingerprint)) return provider;
            }
            return null;
        }

        fn capabilityForShape(capabilities: []const ProgramType.Exchange.Capability, offer: ProgramType.Exchange.ProviderOffer, shape: Closure.EffectShape) ?ProgramType.Exchange.Capability {
            for (capabilities) |capability| {
                if (capability.provider_fingerprint != offer.provider_fingerprint) continue;
                if (capability.manifest_fingerprint != offer.manifest_fingerprint) continue;
                if (!listAllowsStringClosure(capability.allowed_program_labels, shape.program_label)) continue;
                if (!listAllowsU64Closure(capability.allowed_plan_hashes, shape.plan_hash)) continue;
                if (shape.kind == .after) {
                    if (shape.site_index) |site| if (!listAllowsUsizeClosure(capability.allowed_after_sites, site)) continue;
                } else {
                    if (shape.site_index) |site| if (!listAllowsUsizeClosure(capability.allowed_operation_sites, site)) continue;
                }
                if (shape.protocol_op_fingerprint) |protocol_op| if (!listAllowsU64Closure(capability.allowed_protocol_op_fingerprints, protocol_op)) continue;
                if (!listAllowsStringClosure(capability.allowed_requirement_labels, shape.protocol_label)) continue;
                if (!listAllowsStringClosure(capability.allowed_op_names, shape.name)) continue;
                return capability;
            }
            return null;
        }

        fn offerMatchesShape(offer: ProgramType.Exchange.ProviderOffer, shape: Closure.EffectShape) bool {
            if (!listAllowsStringClosure(offer.supported_protocol_labels, shape.protocol_label)) return false;
            if (shape.protocol_op_fingerprint) |protocol_op| if (!listAllowsU64Closure(offer.supported_protocol_op_fingerprints, protocol_op)) return false;
            if (shape.kind == .after) {
                if (shape.site_index) |site| if (!listAllowsUsizeClosure(offer.supported_after_sites, site)) return false;
                if (shape.result_ref) |ref| if (!listAllowsBoundaryValueRef(offer.accepted_current_value_refs, ref)) return false;
            } else {
                if (shape.site_index) |site| if (!listAllowsUsizeClosure(offer.supported_operation_sites, site)) return false;
                if (shape.value_ref) |ref| if (!listAllowsBoundaryValueRef(offer.accepted_payload_refs, ref)) return false;
            }
            return true;
        }

        fn morphismMatchesShape(morphism: ProgramType.Exchange.MorphismOffer, shape: Closure.EffectShape) bool {
            if (morphism.source_site_fingerprint) |fingerprint| {
                if (shape.site_fingerprint == null or shape.site_fingerprint.? != fingerprint) return false;
            }
            if (morphism.source_protocol_op_fingerprint) |fingerprint| {
                if (shape.protocol_op_fingerprint == null or shape.protocol_op_fingerprint.? != fingerprint) return false;
            }
            return morphism.blockers.len == 0;
        }

        fn offerMatchesMorphismTarget(offer: ProgramType.Exchange.ProviderOffer, morphism: ProgramType.Exchange.MorphismOffer) bool {
            if (!listAllowsU64Closure(offer.supported_protocol_op_fingerprints, morphism.target_protocol_op_fingerprint)) return false;
            for (morphism.target_response_refs) |target_ref| {
                if (!listAllowsBoundaryValueRef(offer.produced_response_refs, BoundaryValueRef.fromValueRef(target_ref))) return false;
            }
            return true;
        }

        fn inputAllowsIntrinsicOrWorldPort(inputs: PlanInputs, intrinsic_ref: Ref, shape: Closure.EffectShape) bool {
            if (inputs.policy.allowsHostIntrinsicRef(intrinsic_ref)) return true;
            if (!inputs.policy.allow_world_ports) return false;
            return worldPortForShape(inputs.policy, inputs.world_ports, shape, intrinsic_ref) != null;
        }

        fn worldPortForShape(policy: Policy, world_ports: []const Closure.WorldPort, shape: Closure.EffectShape, intrinsic_ref: Ref) ?Closure.WorldPort {
            for (world_ports) |port| {
                if (!policy.allowsWorldPortRef(port.evidenceRef())) continue;
                if (port.effect_shape_ref) |shape_ref| {
                    if (!shape_ref.eql(shape.evidenceRef())) continue;
                }
                if (!listAllowsStringClosure(port.supported_protocol_labels, shape.protocol_label)) continue;
                if (shape.site_index) |site| if (!listAllowsUsizeClosure(port.supported_site_indexes, site)) continue;
                if (shape.protocol_op_fingerprint) |protocol_op| if (!listAllowsU64Closure(port.supported_protocol_op_fingerprints, protocol_op)) continue;
                _ = intrinsic_ref;
                return port;
            }
            return null;
        }
    };
}

fn hasErrorClosureBlockers(blockers: []const BoundaryClosureBlocker) bool {
    for (blockers) |blocker| if (blocker.severity == .@"error") return true;
    return false;
}

fn listAllowsU64Closure(list: []const u64, value: u64) bool {
    if (list.len == 0) return true;
    for (list) |candidate| if (candidate == value) return true;
    return false;
}

fn listAllowsUsizeClosure(list: []const usize, value: usize) bool {
    if (list.len == 0) return true;
    for (list) |candidate| if (candidate == value) return true;
    return false;
}

fn listAllowsStringClosure(list: []const []const u8, value: []const u8) bool {
    if (list.len == 0) return true;
    for (list) |candidate| if (std.mem.eql(u8, candidate, value)) return true;
    return false;
}

fn listAllowsBoundaryValueRef(list: anytype, value: BoundaryValueRef) bool {
    if (list.len == 0) return true;
    for (list) |candidate| {
        if (BoundaryValueRef.fromValueRef(candidate).eql(value)) return true;
    }
    return false;
}

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

fn worldPortRefAllowedByPolicy(world_port_ref: Ref, policy: BoundaryClosurePolicy) bool {
    if (world_port_ref.domain_id != domains.boundary_world_port.id) return false;
    if (!policy.allow_world_ports) return false;
    if (policy.allow_test_world_ports) {
        if (world_port_ref.kind_tag) |kind_tag| {
            if (std.mem.eql(u8, kind_tag, @tagName(WorldPort.Kind.test_fixture))) return true;
        }
    }
    for (policy.allowed_world_port_fingerprints) |allowed| {
        if (allowed == world_port_ref.fingerprint) return true;
    }
    if (world_port_ref.kind_tag) |kind_tag| {
        for (policy.allowed_world_port_kinds) |allowed| {
            if (std.mem.eql(u8, @tagName(allowed), kind_tag)) return true;
        }
    }
    if (world_port_ref.label) |label_value| {
        for (policy.allowed_world_port_labels) |allowed| {
            if (std.mem.eql(u8, allowed, label_value)) return true;
        }
    }
    return policy.allowed_world_port_fingerprints.len == 0 and
        policy.allowed_world_port_kinds.len == 0 and
        policy.allowed_world_port_labels.len == 0;
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
