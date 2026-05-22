// zlinter-disable declaration_naming field_naming field_ordering max_positional_args no_inferred_error_unions no_literal_args no_undefined require_doc_comment
const lowering_api = @import("lowering_api");
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
        .label = optionalLabel(certificate, "summary"),
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
    stale_effect_shape,
    stale_world_port,
    duplicate_effect_shape,
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
        if (std.mem.eql(u8, self.label, "audit_only") and
            self.allowed_host_intrinsic_fingerprints.len == 0 and
            self.allowed_host_intrinsic_kinds.len == 0 and
            self.allowed_host_intrinsic_labels.len == 0)
        {
            return self.defunctionalization_policy.allowsIntrinsicRef(intrinsic_ref);
        }
        return false;
    }
};

pub const BoundaryEffectShape = struct {
    fingerprint: u64,
    program_label: []const u8,
    plan_label: []const u8 = "",
    plan_hash: u64 = 0,
    manifest_fingerprint: ?u64 = null,
    kind: Kind,
    site_index: ?usize = null,
    site_fingerprint: ?u64 = null,
    semantic_label: ?[]const u8 = null,
    name: []const u8 = "",
    mode: []const u8 = "",
    value_ref: ?BoundaryValueRef = null,
    expected_resume_ref: ?BoundaryValueRef = null,
    expected_after_ref: ?BoundaryValueRef = null,
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
        manifest_fingerprint: ?u64 = null,
        kind: Kind,
        site_index: ?usize = null,
        site_fingerprint: ?u64 = null,
        semantic_label: ?[]const u8 = null,
        name: []const u8 = "",
        mode: []const u8 = "",
        value_ref: ?BoundaryValueRef = null,
        expected_resume_ref: ?BoundaryValueRef = null,
        expected_after_ref: ?BoundaryValueRef = null,
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
            .manifest_fingerprint = options.manifest_fingerprint,
            .kind = options.kind,
            .site_index = options.site_index,
            .site_fingerprint = options.site_fingerprint,
            .semantic_label = options.semantic_label,
            .name = options.name,
            .mode = options.mode,
            .value_ref = options.value_ref,
            .expected_resume_ref = options.expected_resume_ref,
            .expected_after_ref = options.expected_after_ref,
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
        builder.fieldOptionalU64("manifest", self.manifest_fingerprint);
        builder.fieldBytes("kind", @tagName(self.kind));
        builder.fieldOptionalU64("site_index", if (self.site_index) |value| @as(u64, @intCast(value)) else null);
        builder.fieldOptionalU64("site_fingerprint", self.site_fingerprint);
        builder.fieldOptionalBytes("semantic_label", self.semantic_label);
        builder.fieldBytes("name", self.name);
        builder.fieldBytes("mode", self.mode);
        builder.fieldOptionalValueRef("value_ref", self.value_ref);
        builder.fieldOptionalValueRef("expected_resume_ref", self.expected_resume_ref);
        builder.fieldOptionalValueRef("expected_after_ref", self.expected_after_ref);
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
    exposed_intrinsic_ref: ?Ref = null,
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
        exposed_intrinsic_ref: ?Ref = null,
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
            .exposed_intrinsic_ref = options.exposed_intrinsic_ref,
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
        builder.fieldOptionalRef("exposed_intrinsic", self.exposed_intrinsic_ref);
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

pub fn refForBoundaryEffectShape(shape: anytype) Ref {
    return shape.evidenceRef();
}

pub fn fingerprintBoundaryEffectShapeSet(shapes: []const BoundaryEffectShape) u64 {
    var builder = FingerprintBuilder.init(domains.boundary_effect_shape);
    builder.fieldUsize("shape_count", shapes.len);
    for (shapes) |shape| builder.fieldRef("shape", shape.evidenceRef());
    return builder.finish();
}

pub fn refForBoundaryWorldPort(port: anytype) Ref {
    return port.evidenceRef();
}

pub fn refForBoundaryClosureBlocker(blocker: Blocker) Ref {
    return refFor(domains.boundary_closure_report, blocker.fingerprint(), .{ .kind_tag = blocker.short_code });
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
    selected_morphism_semantic_body: ?SemanticBody = null,
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
        selected_morphism_semantic_body: ?SemanticBody = null,
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
            .selected_morphism_semantic_body = options.selected_morphism_semantic_body,
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
        if (self.selected_morphism_semantic_body) |body| builder.fieldBytes("morphism_semantic_body", @tagName(body));
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

    pub fn closedUnderPolicy(self: @This(), policy: BoundaryClosurePolicy) bool {
        _ = policy;
        return self.closed();
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
    effect_free_root_refs: []const Ref = &.{},
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
    world_port_intrinsic_refs: []const Ref = &.{},
    host_intrinsic_refs: []const Ref = &.{},
    unknown_refs: []const Ref = &.{},
    blockers: []const Blocker = &.{},
    dependencies: []const Dependency = &.{},
    policy_summary: ?PolicySummary = null,

    pub const Options = struct {
        graph_fingerprint: u64,
        root_program_refs: []const Ref = &.{},
        effect_free_root_refs: []const Ref = &.{},
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
        world_port_intrinsic_refs: []const Ref = &.{},
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
            .effect_free_root_refs = options.effect_free_root_refs,
            .provider_harness_refs = options.provider_harness_refs,
            .provider_program_refs = options.provider_program_refs,
            .effect_shape_count = options.effect_shape_count,
            .closed_effect_shape_count = options.closed_effect_shape_count,
            .open_world_port_count = options.open_world_port_count,
            .host_intrinsic_count = options.host_intrinsic_count,
            .unknown_body_count = options.unknown_body_count,
            .blocker_count = if (options.blockers.len != 0) options.blockers.len else options.blocker_count,
            .ambiguity_count = options.ambiguity_count,
            .boundary_native_route_count = options.boundary_native_route_count,
            .declarative_route_count = options.declarative_route_count,
            .residualized_pipeline_route_count = options.residualized_pipeline_route_count,
            .intrinsic_route_count = options.intrinsic_route_count,
            .world_port_refs = options.world_port_refs,
            .world_port_intrinsic_refs = options.world_port_intrinsic_refs,
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
        for (self.effect_free_root_refs) |ref| builder.fieldRef("effect_free_root", ref);
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
        for (self.world_port_intrinsic_refs) |ref| builder.fieldRef("world_port_intrinsic", ref);
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
        return self.blocker_count == 0 and !hasErrorBlockers(self.blockers) and self.open_world_port_count == 0 and self.effect_shape_count == self.closed_effect_shape_count;
    }

    pub fn closedExceptWorldPorts(self: @This()) bool {
        return self.blocker_count == 0 and
            !hasErrorBlockers(self.blockers) and
            self.closed_effect_shape_count <= self.effect_shape_count and
            self.open_world_port_count <= self.effect_shape_count and
            self.closed_effect_shape_count + self.open_world_port_count == self.effect_shape_count;
    }

    pub fn toEvidenceReport(self: @This()) Report {
        const policy_fingerprint = if (self.policy_summary) |policy| policy.policy_fingerprint else null;
        if (self.blocker_count != 0 or hasErrorBlockers(self.blockers) or !self.closedExceptWorldPorts()) {
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
    effect_free_root_refs: []const Ref = &.{},
    provider_refs: []const Ref = &.{},
    provider_program_refs: []const Ref = &.{},
    policy_refs: []const Ref = &.{},
    world_port_refs: []const Ref = &.{},
    world_port_intrinsic_refs: []const Ref = &.{},
    intrinsic_refs: []const Ref = &.{},
    selected_static_treaty_plan_refs: []const Ref = &.{},
    blocker_refs: []const Ref = &.{},
    effect_shape_count: usize = 0,
    closed_effect_shape_count: usize = 0,
    world_port_count: usize = 0,
    blocker_count: usize = 0,
    summary: []const u8 = "boundary closure certificate",

    pub fn init(report: BoundaryClosureReport, graph: BoundaryGraph, policy: BoundaryClosurePolicy, plan_refs: []const Ref) @This() {
        return initWithBlockerRefs(report, graph, policy, plan_refs, &.{});
    }

    pub fn initWithBlockerRefs(report: BoundaryClosureReport, graph: BoundaryGraph, policy: BoundaryClosurePolicy, plan_refs: []const Ref, blocker_refs: []const Ref) @This() {
        var certificate = @This(){
            .certificate_fingerprint = 0,
            .closure_report_fingerprint = report.report_fingerprint,
            .closure_graph_fingerprint = graph.fingerprint,
            .policy_ref = policy.evidenceRef(),
            .policy_fingerprint = policy.fingerprint(),
            .root_refs = report.root_program_refs,
            .effect_free_root_refs = report.effect_free_root_refs,
            .provider_refs = report.provider_harness_refs,
            .provider_program_refs = report.provider_program_refs,
            .policy_refs = &.{},
            .world_port_refs = report.world_port_refs,
            .world_port_intrinsic_refs = report.world_port_intrinsic_refs,
            .intrinsic_refs = report.host_intrinsic_refs,
            .selected_static_treaty_plan_refs = plan_refs,
            .blocker_refs = blocker_refs,
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
        for (self.effect_free_root_refs) |ref| builder.fieldRef("effect_free_root", ref);
        for (self.provider_refs) |ref| builder.fieldRef("provider", ref);
        for (self.provider_program_refs) |ref| builder.fieldRef("provider_program", ref);
        for (self.policy_refs) |ref| builder.fieldRef("policy", ref);
        for (self.world_port_refs) |ref| builder.fieldRef("world_port", ref);
        for (self.world_port_intrinsic_refs) |ref| builder.fieldRef("world_port_intrinsic", ref);
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

    pub fn check(
        self: @This(),
        graph: BoundaryGraph,
        report: BoundaryClosureReport,
        policy: BoundaryClosurePolicy,
        static_treaty_plans: []const BoundaryStaticTreatyPlan,
    ) error{
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
        if (graph.fingerprint != graph.computeFingerprint()) return error.BoundaryClosureGraphMismatch;
        if (report.graph_fingerprint != graph.fingerprint) return error.BoundaryClosureGraphMismatch;
        if (report.report_fingerprint != report.computeFingerprint()) return error.BoundaryClosureReportMismatch;
        if (self.closure_graph_fingerprint != graph.fingerprint) return error.BoundaryClosureGraphMismatch;
        if (self.closure_report_fingerprint != report.report_fingerprint) return error.BoundaryClosureReportMismatch;
        if (self.certificate_fingerprint != self.computeFingerprint()) return error.BoundaryClosureCertificateMismatch;
        if (!self.policy_ref.eql(policy.evidenceRef()) or self.policy_fingerprint != policy.fingerprint()) return error.BoundaryClosurePolicyMismatch;
        if (!policySummaryMatches(report.policy_summary, policy)) return error.BoundaryClosurePolicyMismatch;
        if (!refsEqual(self.root_refs, report.root_program_refs)) return error.BoundaryClosureCertificateMismatch;
        if (!refsEqual(self.effect_free_root_refs, report.effect_free_root_refs)) return error.BoundaryClosureCertificateMismatch;
        if (!graphNodeRefsMatchReport(graph, .root_program, report.root_program_refs)) return error.BoundaryClosureCertificateMismatch;
        if (!graphRootYieldEdgesMatchReport(graph, report)) return error.BoundaryClosureCertificateMismatch;
        if (!refsEqual(self.provider_refs, report.provider_harness_refs)) return error.BoundaryClosureCertificateMismatch;
        if (!graphNodeRefsMatchReport(graph, .provider_harness, report.provider_harness_refs)) return error.BoundaryClosureCertificateMismatch;
        if (!refsEqual(self.provider_program_refs, report.provider_program_refs)) return error.BoundaryClosureCertificateMismatch;
        if (!graphNodeRefsMatchReport(graph, .provider_program, report.provider_program_refs)) return error.BoundaryClosureCertificateMismatch;
        if (!refsEqual(self.world_port_refs, report.world_port_refs)) return error.BoundaryClosureCertificateMismatch;
        if (!refsEqual(self.world_port_intrinsic_refs, report.world_port_intrinsic_refs)) return error.BoundaryClosureCertificateMismatch;
        if (!refsEqual(self.intrinsic_refs, report.host_intrinsic_refs)) return error.BoundaryClosureCertificateMismatch;
        if (self.effect_shape_count != report.effect_shape_count) return error.BoundaryClosureCertificateMismatch;
        if (self.closed_effect_shape_count != report.closed_effect_shape_count) return error.BoundaryClosureCertificateMismatch;
        if (self.world_port_count != report.open_world_port_count) return error.BoundaryClosureCertificateMismatch;
        if (self.blocker_count != report.blocker_count) return error.BoundaryClosureCertificateMismatch;
        if (report.blocker_count != report.blockers.len) return error.BoundaryClosureCertificateMismatch;
        if (!blockerRefsMatchBlockers(self.blocker_refs, report.blockers)) return error.BoundaryClosureCertificateMismatch;
        if (!graphBlockerRefsMatchCertificate(graph, self.blocker_refs, report.blockers)) return error.BoundaryClosureCertificateMismatch;
        if (report.open_world_port_count != graphWorldPortShapeCount(graph, report)) return error.BoundaryClosureCertificateMismatch;
        if ((report.open_world_port_count == 0) != (report.world_port_refs.len == 0)) return error.BoundaryClosureCertificateMismatch;
        if (report.host_intrinsic_count != report.host_intrinsic_refs.len) return error.BoundaryClosureCertificateMismatch;
        if (report.unknown_body_count != report.unknown_refs.len) return error.BoundaryClosureCertificateMismatch;
        if (report.world_port_refs.len != report.world_port_intrinsic_refs.len) return error.BoundaryClosureCertificateMismatch;
        if (!graphNodeRefsMatchReport(graph, .host_intrinsic, report.host_intrinsic_refs)) return error.BoundaryClosureCertificateMismatch;
        if (!graphNodeRefsMatchReport(graph, .world_port, report.world_port_refs)) return error.BoundaryClosureCertificateMismatch;
        if (!graphWorldPortEdgesMatchReport(graph, report)) return error.BoundaryClosureCertificateMismatch;
        for (report.world_port_intrinsic_refs) |paired_ref| {
            if (paired_ref.domain_id == domains.host_intrinsic.id) {
                if (!refsContain(report.host_intrinsic_refs, paired_ref)) return error.BoundaryClosureCertificateMismatch;
            } else if (paired_ref.domain_id == domains.boundary_effect_shape.id) {
                if (!graphHasNode(graph, .operation_site, paired_ref) and !graphHasNode(graph, .after_site, paired_ref)) return error.BoundaryClosureCertificateMismatch;
            } else {
                return error.BoundaryClosureCertificateMismatch;
            }
        }
        if (self.selected_static_treaty_plan_refs.len != report.effect_shape_count) return error.BoundaryClosureCertificateMismatch;
        if (!graphPlanRefsMatchCertificate(graph, self.selected_static_treaty_plan_refs)) return error.BoundaryClosureCertificateMismatch;
        if (!staticTreatyPlansMatchCertificate(
            graph,
            report,
            policy,
            self.blocker_refs,
            self.selected_static_treaty_plan_refs,
            static_treaty_plans,
        )) return error.BoundaryClosureCertificateMismatch;
        if (policy.require_all_effect_shapes_closed) {
            if (policy.allow_world_ports) {
                if (!report.closedExceptWorldPorts()) return error.BoundaryClosureNotClosed;
            } else {
                if (!report.closed()) return error.BoundaryClosureNotClosed;
            }
        }
        for (report.world_port_refs, report.world_port_intrinsic_refs) |world_port_ref, paired_ref| {
            if (!policy.allowsWorldPortRef(world_port_ref)) return error.BoundaryClosureWorldPortsRejected;
            if (paired_ref.domain_id == domains.host_intrinsic.id) {
                if (!graphHasEdge(graph, .world_port_exposes, paired_ref, world_port_ref)) return error.BoundaryClosureWorldPortsRejected;
            } else if (paired_ref.domain_id == domains.boundary_effect_shape.id) {
                if (!graphHasEdge(graph, .opens_obligation, paired_ref, world_port_ref)) return error.BoundaryClosureWorldPortsRejected;
            } else {
                return error.BoundaryClosureWorldPortsRejected;
            }
        }
        for (report.host_intrinsic_refs) |host_intrinsic_ref| {
            if (!policy.allowsHostIntrinsicRef(host_intrinsic_ref) and !reportHasAllowedWorldPortForIntrinsic(report, graph, policy, host_intrinsic_ref)) return error.BoundaryClosureIntrinsicRejected;
        }
        if (!policy.allow_world_ports and report.open_world_port_count != 0) return error.BoundaryClosureWorldPortsRejected;
        if (policy.reject_unknown_semantic_bodies and report.unknown_body_count != 0) return error.BoundaryClosureUnknownBodies;
        if (policy.reject_host_intrinsics) {
            for (report.host_intrinsic_refs) |host_intrinsic_ref| {
                if (!reportHasAllowedWorldPortForIntrinsic(report, graph, policy, host_intrinsic_ref)) return error.BoundaryClosureIntrinsicRejected;
            }
        }
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
        const maxStaticResponseRefs = 3;

        pub const ProviderProgram = struct {
            provider_ref: Ref,
            program_ref: Ref,
            provider_program_mapping_fingerprint: ?u64 = null,
            shapes: []const Closure.EffectShape = &.{},
            effect_free: bool = false,
        };

        const SelectedProviderProgram = struct {
            mapping_fingerprint: u64,
            program_ref: Ref,
            effect_shape_count: usize,
            effect_shape_fingerprint: u64,
        };

        const SelectedProviderProgramKey = struct {
            provider_ref: Ref,
            program_ref: Ref,
            mapping_fingerprint: ?u64,
            effect_shape_fingerprint: u64,

            fn eql(self: @This(), other: @This()) bool {
                return self.provider_ref.eql(other.provider_ref) and
                    self.program_ref.eql(other.program_ref) and
                    self.mapping_fingerprint == other.mapping_fingerprint and
                    self.effect_shape_fingerprint == other.effect_shape_fingerprint;
            }
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
            route_policy: ProgramType.Exchange.Policy = .{},
            policy: Policy = Policy.strict(),
            world_ports: []const Closure.WorldPort = &.{},
            root_program_refs: []const Ref = &.{},
            effect_free_root_refs: []const Ref = &.{},
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
            route_policy: ProgramType.Exchange.Policy = .{},
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
            world_port_intrinsic_refs: []Ref = &.{},
            host_intrinsic_refs: []Ref = &.{},
            unknown_refs: []Ref = &.{},

            pub fn deinit(self: *@This()) void {
                for (self.static_treaty_plans) |plan| {
                    self.allocator.free(plan.blockers);
                    self.allocator.free(plan.dependencies);
                }
                self.allocator.free(self.static_treaty_plans);
                self.allocator.free(self.report.root_program_refs);
                self.allocator.free(self.report.effect_free_root_refs);
                self.allocator.free(self.report.provider_harness_refs);
                self.allocator.free(self.blockers);
                self.allocator.free(self.plan_refs);
                self.allocator.free(self.certificate.blocker_refs);
                self.allocator.free(self.provider_program_refs);
                self.allocator.free(self.world_port_refs);
                self.allocator.free(self.world_port_intrinsic_refs);
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
                shapes[index] = afterShape(RootProgram, site);
                index += 1;
            }
            return shapes;
        }

        pub fn operationShape(comptime RootProgram: type, comptime site: anytype, comptime kind: Closure.EffectShape.Kind) Closure.EffectShape {
            return Closure.EffectShape.init(.{
                .program_label = RootProgram.contract.label,
                .plan_label = RootProgram.compiled_plan.label,
                .plan_hash = RootProgram.compiled_plan.hash(),
                .manifest_fingerprint = RootProgram.Exchange.exchange_manifest_fingerprint_value,
                .kind = kind,
                .site_index = site.index,
                .site_fingerprint = site.fingerprint,
                .semantic_label = site.semantic_label,
                .name = site.op_name,
                .mode = @tagName(site.op_mode),
                .value_ref = BoundaryValueRef.fromValueRef(site.payload_ref),
                .expected_resume_ref = operationResumeRef(site),
                .result_ref = operationReturnRef(site),
                .protocol_label = site.requirement_label,
                .protocol_op_fingerprint = site.fingerprint,
            });
        }

        fn operationResumeRef(comptime site: anytype) ?BoundaryValueRef {
            return switch (site.op_mode) {
                .transform, .choice => BoundaryValueRef.fromValueRef(site.resume_ref),
                .abort => null,
            };
        }

        fn operationReturnRef(comptime site: anytype) ?BoundaryValueRef {
            return switch (site.op_mode) {
                .transform => null,
                .choice, .abort => BoundaryValueRef.fromValueRef(site.result_ref),
            };
        }

        pub fn afterShape(comptime RootProgram: type, comptime site: anytype) Closure.EffectShape {
            const operation_site = comptime afterSourceOperationSite(RootProgram, site);
            const current_ref = lowering_api.sessionAfterProtocolInputRefForOperationSite(RootProgram.compiled_plan, RootProgram.value_schema_types, RootProgram.Handlers, operation_site) orelse lowering_api.ValueRef{ .codec = .unit };
            const output_ref = lowering_api.sessionAfterProtocolOutputRefForOperationSite(RootProgram.compiled_plan, RootProgram.value_schema_types, RootProgram.Handlers, operation_site);
            return Closure.EffectShape.init(.{
                .program_label = RootProgram.contract.label,
                .plan_label = RootProgram.compiled_plan.label,
                .plan_hash = RootProgram.compiled_plan.hash(),
                .manifest_fingerprint = RootProgram.Exchange.exchange_manifest_fingerprint_value,
                .kind = .after,
                .site_index = site.index,
                .site_fingerprint = site.fingerprint,
                .semantic_label = site.semantic_label,
                .name = site.original_op_name,
                .mode = "after",
                .value_ref = BoundaryValueRef.fromValueRef(current_ref),
                .expected_after_ref = BoundaryValueRef.fromValueRef(output_ref),
                .result_ref = BoundaryValueRef.fromValueRef(site.result_ref),
                .protocol_label = site.original_requirement_label,
                .protocol_op_fingerprint = site.source_operation_site_fingerprint,
            });
        }

        fn afterSourceOperationSite(comptime RootProgram: type, comptime after_site: anytype) lowering_api.SessionOperationYieldSite {
            inline for (RootProgram.contract.session.yield_sites) |site| {
                if (site.index == after_site.source_operation_site_index and site.fingerprint == after_site.source_operation_site_fingerprint) return site;
            }
            @compileError("BoundaryClosure after site has no matching source operation site");
        }

        pub fn planTreatyForShape(inputs: PlanInputs) !StaticTreatyPlan {
            var blockers = std.ArrayList(BoundaryClosureBlocker).empty;
            defer blockers.deinit(inputs.allocator);
            var dependencies = std.ArrayList(Dependency).empty;
            defer dependencies.deinit(inputs.allocator);

            try dependencies.append(inputs.allocator, .{ .role = .effect_shape, .ref = inputs.shape.evidenceRef() });
            const shape_stale = inputs.shape.fingerprint != inputs.shape.computeFingerprint();
            if (shape_stale) {
                try blockers.append(inputs.allocator, .{
                    .tag = .stale_effect_shape,
                    .subject = inputs.shape.evidenceRef(),
                    .summary = "effect shape fields do not match its evidence fingerprint",
                });
            }
            const runtime_request_value_guard_required = !shape_stale and shapeRequiresValueRef(inputs.shape) and inputs.shape.value_ref == null;
            if (runtime_request_value_guard_required and inputs.policy.reject_request_value_dependence) {
                try blockers.append(inputs.allocator, .{
                    .tag = .runtime_guard_required,
                    .subject = inputs.shape.evidenceRef(),
                    .summary = "effect shape is missing request value ref",
                });
            }
            var selected: CandidateSelection = .{};
            if (shape_stale) {
                // Stale public fields are not allowed to drive provider selection.
            } else if (shapeSupportedForPlanning(inputs.shape)) {
                selected = try selectShapeCandidate(inputs, &blockers, &dependencies);
            } else if (inputs.policy.reject_unknown_effect_shapes) {
                try blockers.append(inputs.allocator, .{
                    .tag = .effect_shape_unhandled,
                    .subject = inputs.shape.evidenceRef(),
                    .summary = "effect shape kind cannot be statically planned",
                });
            }
            if (selectedIntrinsicCountBlocker(inputs.policy, inputs.treaty_policy, selected)) |tag| {
                try blockers.append(inputs.allocator, .{
                    .tag = tag,
                    .subject = inputs.shape.evidenceRef(),
                    .primary = selected.intrinsic_ref orelse selected.morphism_ref orelse selected.offer_ref,
                    .summary = "selected static treaty route exceeds defunctionalization intrinsic count policy",
                });
            }
            const real_runtime_guard_required = runtime_request_value_guard_required or hasClosureBlockerTag(blockers.items, .runtime_guard_required);
            if (real_runtime_guard_required and !hasClosureBlockerTag(blockers.items, .runtime_guard_required) and
                (inputs.policy.reject_runtime_guards or !inputs.policy.allow_runtime_guards))
            {
                try blockers.append(inputs.allocator, .{
                    .tag = .runtime_guard_required,
                    .subject = inputs.shape.evidenceRef(),
                    .summary = "runtime guard required by static plan but rejected by closure policy",
                });
            }

            const owned_blockers = try blockers.toOwnedSlice(inputs.allocator);
            errdefer inputs.allocator.free(owned_blockers);
            const owned_dependencies = try dependencies.toOwnedSlice(inputs.allocator);
            errdefer inputs.allocator.free(owned_dependencies);
            const runtime_guard_required = runtime_request_value_guard_required or selected.offer_ref == null or hasClosureBlockerTag(owned_blockers, .runtime_guard_required);
            return StaticTreatyPlan.init(.{
                .label = inputs.shape.name,
                .source_shape = inputs.shape,
                .direct_candidate_count = selected.direct_count,
                .morphism_candidate_count = selected.morphism_count,
                .selected_provider_offer_ref = selected.offer_ref,
                .selected_provider_ref = selected.provider_ref,
                .selected_capability_ref = selected.capability_ref,
                .selected_morphism_ref = selected.morphism_ref,
                .selected_morphism_semantic_body = selected.morphism_body,
                .selected_semantic_body = selected.body,
                .selected_intrinsic_ref = selected.intrinsic_ref,
                .boundary_native = selected.body.isNonIntrinsic() and (if (selected.morphism_body) |body| body.isNonIntrinsic() else true),
                .host_intrinsic = selected.body == .host_intrinsic or (if (selected.morphism_body) |body| body == .host_intrinsic else false),
                .runtime_request_value_validation_required = runtime_guard_required,
                .byte_size_runtime_guard_required = runtime_guard_required,
                .blockers = owned_blockers,
                .dependencies = owned_dependencies,
            });
        }

        pub fn analyze(result_allocator: std.mem.Allocator, input: Input) !Result {
            const allocator = result_allocator;
            var analysis_input = input;
            analysis_input.allocator = allocator;
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
            var provider_program_keys = std.ArrayList(SelectedProviderProgramKey).empty;
            defer provider_program_keys.deinit(allocator);
            var world_port_refs = std.ArrayList(Ref).empty;
            errdefer world_port_refs.deinit(allocator);
            var world_port_intrinsic_refs = std.ArrayList(Ref).empty;
            errdefer world_port_intrinsic_refs.deinit(allocator);
            var host_intrinsic_refs = std.ArrayList(Ref).empty;
            errdefer host_intrinsic_refs.deinit(allocator);
            var unknown_refs = std.ArrayList(Ref).empty;
            errdefer unknown_refs.deinit(allocator);
            var nodes = std.ArrayList(Graph.Node).empty;
            errdefer nodes.deinit(allocator);
            var edges = std.ArrayList(Graph.Edge).empty;
            errdefer edges.deinit(allocator);
            var active_provider_program_refs = std.ArrayList(Ref).empty;
            defer active_provider_program_refs.deinit(allocator);
            var active_provider_program_keys = std.ArrayList(SelectedProviderProgramKey).empty;
            defer active_provider_program_keys.deinit(allocator);
            var seen_shape_refs = std.ArrayList(Ref).empty;
            defer seen_shape_refs.deinit(allocator);

            if (analysis_input.root_shapes.len == 0 and analysis_input.root_program_refs.len == 0) {
                const evidence_blocker = boundaryClosureBlocker(.{
                    .tag = .root_program_missing,
                    .summary = "closure input contains no root effect shapes",
                });
                try blockers.append(allocator, evidence_blocker);
                try appendBlockerGraph(allocator, &nodes, &edges, evidence_blocker);
            }
            for (analysis_input.effect_free_root_refs) |effect_free_root_ref| {
                if (refsContain(analysis_input.root_program_refs, effect_free_root_ref)) continue;
                const evidence_blocker = boundaryClosureBlocker(.{
                    .tag = .root_program_missing,
                    .subject = effect_free_root_ref,
                    .summary = "effect-free root witness is not a declared root program",
                });
                try blockers.append(allocator, evidence_blocker);
                try appendBlockerGraph(allocator, &nodes, &edges, evidence_blocker);
            }
            for (analysis_input.root_program_refs) |root_ref| {
                if (refsContain(analysis_input.effect_free_root_refs, root_ref)) continue;
                var witnessed = false;
                for (analysis_input.root_shapes) |shape| {
                    if (rootRefMatchesShape(root_ref, shape)) {
                        witnessed = true;
                        break;
                    }
                }
                if (witnessed) continue;
                const evidence_blocker = boundaryClosureBlocker(.{
                    .tag = .root_program_missing,
                    .subject = root_ref,
                    .summary = "declared root program has no effect shape or effect-free witness",
                });
                try blockers.append(allocator, evidence_blocker);
                try appendBlockerGraph(allocator, &nodes, &edges, evidence_blocker);
            }
            for (analysis_input.root_program_refs) |root_ref| {
                try nodes.append(allocator, .{ .kind = .root_program, .ref = root_ref, .label = root_ref.label orelse "root program" });
            }
            for (analysis_input.provider_harness_refs) |provider_ref| {
                try nodes.append(allocator, .{ .kind = .provider_harness, .ref = provider_ref, .label = provider_ref.label orelse "provider harness" });
            }
            for (analysis_input.world_ports) |port| {
                if (port.fingerprint == port.computeFingerprint()) continue;
                const evidence_blocker = boundaryClosureBlocker(.{
                    .tag = .stale_world_port,
                    .subject = port.evidenceRef(),
                    .summary = "world-port fields do not match its evidence fingerprint",
                });
                try blockers.append(allocator, evidence_blocker);
                try appendBlockerGraph(allocator, &nodes, &edges, evidence_blocker);
            }

            var closed_count: usize = 0;
            var world_port_shape_count: usize = 0;
            var boundary_native_count: usize = 0;
            var declarative_count: usize = 0;
            var residualized_pipeline_count: usize = 0;
            var intrinsic_count: usize = 0;
            var ambiguity_count: usize = 0;

            try analyzeShapes(allocator, analysis_input, analysis_input.root_shapes, &all_plans, &blockers, &plan_refs, &seen_shape_refs, &world_port_refs, &world_port_intrinsic_refs, &host_intrinsic_refs, &unknown_refs, &nodes, &edges, &closed_count, &world_port_shape_count, &boundary_native_count, &declarative_count, &residualized_pipeline_count, &intrinsic_count, &ambiguity_count, analysis_input.root_program_refs, null);
            try analyzeSelectedProviderPrograms(allocator, analysis_input, &all_plans, &blockers, &plan_refs, &seen_shape_refs, &provider_program_refs, &provider_program_keys, &active_provider_program_refs, &active_provider_program_keys, &world_port_refs, &world_port_intrinsic_refs, &host_intrinsic_refs, &unknown_refs, &nodes, &edges, &closed_count, &world_port_shape_count, &boundary_native_count, &declarative_count, &residualized_pipeline_count, &intrinsic_count, &ambiguity_count, 0, all_plans.items.len, 0);
            for (all_plans.items) |plan| {
                if (plan.selected_semantic_body != .boundary_program) continue;
                const provider_ref = plan.selected_provider_ref orelse continue;
                const selected_program = selectedPlanProviderProgram(analysis_input, plan) orelse {
                    const evidence_blocker = boundaryClosureBlocker(.{
                        .tag = .provider_program_contract_missing,
                        .subject = plan.source_shape.evidenceRef(),
                        .primary = provider_ref,
                        .summary = "selected program-backed provider is missing provider program closure metadata",
                    });
                    try blockers.append(allocator, evidence_blocker);
                    try appendBlockerGraph(allocator, &nodes, &edges, evidence_blocker);
                    continue;
                };
                if (providerProgramForSelectedOffer(analysis_input.provider_programs, provider_ref, selected_program) == null) {
                    const evidence_blocker = boundaryClosureBlocker(.{
                        .tag = .provider_program_contract_missing,
                        .subject = plan.source_shape.evidenceRef(),
                        .primary = provider_ref,
                        .summary = "selected program-backed provider has no provider program closure entry",
                    });
                    try blockers.append(allocator, evidence_blocker);
                    try appendBlockerGraph(allocator, &nodes, &edges, evidence_blocker);
                }
            }

            if (nodes.items.len > analysis_input.policy.max_nodes or edges.items.len > analysis_input.policy.max_nodes) {
                const evidence_blocker = boundaryClosureBlocker(.{
                    .tag = .depth_limit_exceeded,
                    .summary = "closure graph exceeds policy max_nodes bound",
                });
                try blockers.append(allocator, evidence_blocker);
                try appendBlockerGraph(allocator, &nodes, &edges, evidence_blocker);
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
            const owned_root_program_refs = try allocator.dupe(Ref, analysis_input.root_program_refs);
            errdefer allocator.free(owned_root_program_refs);
            const owned_effect_free_root_refs = try allocator.dupe(Ref, analysis_input.effect_free_root_refs);
            errdefer allocator.free(owned_effect_free_root_refs);
            const owned_provider_harness_refs = try allocator.dupe(Ref, analysis_input.provider_harness_refs);
            errdefer allocator.free(owned_provider_harness_refs);
            const owned_blocker_refs = try allocator.alloc(Ref, owned_blockers.len);
            errdefer allocator.free(owned_blocker_refs);
            for (owned_blockers, owned_blocker_refs) |blocker, *blocker_ref| {
                blocker_ref.* = refForBoundaryClosureBlocker(blocker);
            }
            const owned_plan_refs = try plan_refs.toOwnedSlice(allocator);
            errdefer allocator.free(owned_plan_refs);
            const owned_provider_program_refs = try provider_program_refs.toOwnedSlice(allocator);
            errdefer allocator.free(owned_provider_program_refs);
            const owned_world_port_refs = try world_port_refs.toOwnedSlice(allocator);
            errdefer allocator.free(owned_world_port_refs);
            const owned_world_port_intrinsic_refs = try world_port_intrinsic_refs.toOwnedSlice(allocator);
            errdefer allocator.free(owned_world_port_intrinsic_refs);
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
                .root_program_refs = owned_root_program_refs,
                .effect_free_root_refs = owned_effect_free_root_refs,
                .provider_harness_refs = owned_provider_harness_refs,
                .provider_program_refs = owned_provider_program_refs,
                .effect_shape_count = owned_plan_refs.len,
                .closed_effect_shape_count = closed_count,
                .open_world_port_count = world_port_shape_count,
                .host_intrinsic_count = intrinsic_count,
                .unknown_body_count = owned_unknown_refs.len,
                .blocker_count = owned_blockers.len,
                .ambiguity_count = ambiguity_count,
                .boundary_native_route_count = boundary_native_count,
                .declarative_route_count = declarative_count,
                .residualized_pipeline_route_count = residualized_pipeline_count,
                .intrinsic_route_count = intrinsic_count,
                .world_port_refs = owned_world_port_refs,
                .world_port_intrinsic_refs = owned_world_port_intrinsic_refs,
                .host_intrinsic_refs = owned_host_intrinsic_refs,
                .unknown_refs = owned_unknown_refs,
                .blockers = owned_blockers,
                .policy_summary = analysis_input.policy.policySummary(),
            });
            const certificate = Certificate.initWithBlockerRefs(report, graph, analysis_input.policy, owned_plan_refs, owned_blocker_refs);
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
                .world_port_intrinsic_refs = owned_world_port_intrinsic_refs,
                .host_intrinsic_refs = owned_host_intrinsic_refs,
                .unknown_refs = owned_unknown_refs,
            };
        }

        const CandidateSelection = struct {
            direct_count: usize = 0,
            morphism_count: usize = 0,
            offer_ref: ?Ref = null,
            provider_ref: ?Ref = null,
            provider_fingerprint: u64 = 0,
            capability_ref: ?Ref = null,
            morphism_ref: ?Ref = null,
            morphism_body: ?SemanticBody = null,
            intrinsic_ref: ?Ref = null,
            body: SemanticBody = .unknown,
            selected_rank: u8 = std.math.maxInt(u8),
            selected_rank_count: usize = 0,
            selected_authority: CandidateAuthority = .{},
        };

        const CandidateAuthority = struct {
            max_response_bytes: usize = std.math.maxInt(usize),
            max_payload_bytes: usize = std.math.maxInt(usize),
            capsule_restore_allowed: bool = true,
            response_kind_count: u8 = 3,
            attenuated: bool = false,
        };

        fn selectShapeCandidate(inputs: PlanInputs, blockers: *std.ArrayList(BoundaryClosureBlocker), dependencies: *std.ArrayList(Dependency)) !CandidateSelection {
            var selection: CandidateSelection = .{};
            var rejected_candidates = std.ArrayList(BoundaryClosureBlocker).empty;
            defer rejected_candidates.deinit(inputs.allocator);
            if (inputs.treaty_policy.require_capsule_embedding) {
                try blockers.append(inputs.allocator, .{ .tag = .treaty_policy_incompatible, .subject = inputs.shape.evidenceRef(), .summary = "closure planning has no embedded capsule evidence for a capsule-required treaty policy" });
                return selection;
            }
            if (inputs.treaty_policy.allow_direct_handling) {
                for (inputs.provider_offers) |offer| {
                    offer.validate() catch {
                        try rejected_candidates.append(inputs.allocator, .{ .tag = .no_provider_offer_for_shape, .subject = inputs.shape.evidenceRef(), .primary = offer.evidenceRef(), .summary = "provider offer fields are not bound to provider offer bytes" });
                        continue;
                    };
                    if (!offerMatchesShape(offer, inputs.shape)) continue;
                    const provider = providerManifestForOffer(inputs.provider_manifests, offer) orelse {
                        try rejected_candidates.append(inputs.allocator, .{ .tag = .no_provider_offer_for_shape, .subject = inputs.shape.evidenceRef(), .primary = offer.evidenceRef(), .summary = "provider offer is not backed by a provider manifest" });
                        continue;
                    };
                    if (!providerManifestSupportsShape(provider, inputs.shape)) {
                        try rejected_candidates.append(inputs.allocator, .{ .tag = .no_provider_offer_for_shape, .subject = inputs.shape.evidenceRef(), .primary = provider.evidenceRef(), .summary = "provider manifest does not support this effect shape" });
                        continue;
                    }
                    const body = offer.semanticBodyWithProvider(provider);
                    const intrinsic_ref = offer.hostIntrinsicRef();
                    if (providerBodyRejectedByPolicy(inputs.policy, inputs.treaty_policy, body, intrinsic_ref)) |tag| {
                        try rejected_candidates.append(inputs.allocator, .{ .tag = tag, .subject = inputs.shape.evidenceRef(), .primary = offer.evidenceRef(), .summary = "provider offer semantic body is rejected by closure policy" });
                        continue;
                    }
                    if (body == .host_intrinsic) {
                        if (intrinsic_ref) |ref| {
                            if (!inputAllowsIntrinsicOrWorldPort(inputs, ref, inputs.shape)) {
                                try rejected_candidates.append(inputs.allocator, .{ .tag = .unallowlisted_intrinsic, .subject = inputs.shape.evidenceRef(), .primary = ref, .summary = "host-intrinsic provider is not allowlisted or exposed as a world port" });
                                continue;
                            }
                        } else if (inputs.policy.reject_host_intrinsics) {
                            try rejected_candidates.append(inputs.allocator, .{ .tag = .intrinsic_route_rejected, .subject = inputs.shape.evidenceRef(), .primary = offer.evidenceRef(), .summary = "host-intrinsic provider route lacks an intrinsic evidence ref" });
                            continue;
                        }
                    }
                    if (!providerOfferTagsAllowTreatyPolicy(inputs.treaty_policy, offer.tags)) {
                        try rejected_candidates.append(inputs.allocator, .{ .tag = .treaty_policy_incompatible, .subject = inputs.shape.evidenceRef(), .primary = offer.evidenceRef(), .summary = "provider offer tags are incompatible with treaty policy" });
                        continue;
                    }
                    if (!treatyUsagePolicyAllowsShapeOffer(offer, inputs.shape, inputs.treaty_policy)) {
                        try rejected_candidates.append(inputs.allocator, .{ .tag = .treaty_policy_incompatible, .subject = inputs.shape.evidenceRef(), .primary = offer.evidenceRef(), .summary = "provider offer usage or replay policy is incompatible with treaty policy" });
                        continue;
                    }
                    var matched_capability = false;
                    direct_capabilities: for (inputs.capabilities) |capability| {
                        if (!capabilityMatchesShape(capability, offer, inputs.shape)) continue :direct_capabilities;
                        if (!directCandidateResponseShapeAllowed(inputs.route_policy, provider, offer, capability, inputs.shape)) continue :direct_capabilities;
                        if (closureCapabilityBlockedByTreatyPolicy(capability, inputs.treaty_policy)) continue :direct_capabilities;
                        matched_capability = true;
                        selection.direct_count += 1;
                        try dependencies.append(inputs.allocator, .{ .role = .offer, .ref = offer.evidenceRef() });
                        try dependencies.append(inputs.allocator, .{ .role = .capability, .ref = capability.evidenceRef() });
                        selectCandidate(inputs.policy, inputs.treaty_policy, inputs.route_policy, &selection, inputs.shape, provider, offer, capability, null, body, intrinsic_ref);
                    }
                    if (!matched_capability) {
                        try rejected_candidates.append(inputs.allocator, .{ .tag = .no_capability_for_shape, .subject = inputs.shape.evidenceRef(), .primary = offer.evidenceRef(), .summary = "provider offer has no static capability grant for this effect shape" });
                    }
                }
            }

            const morphism_policy_blocker = morphismPlanningBlocker(inputs);
            for (inputs.morphism_offers) |morphism| {
                if (!morphismMatchesShape(morphism, inputs.shape)) continue;
                if (morphism.hasMixedAdapterBody()) {
                    try rejected_candidates.append(inputs.allocator, .{ .tag = .unsupported_shape_planning, .subject = inputs.shape.evidenceRef(), .primary = morphism.evidenceRef(), .summary = "morphism offer cites both dynamic and static adapter bodies" });
                    continue;
                }
                if (morphism_policy_blocker) |tag| {
                    try rejected_candidates.append(inputs.allocator, .{ .tag = tag, .subject = inputs.shape.evidenceRef(), .primary = morphism.evidenceRef(), .summary = "morphism adaptation is rejected by closure policy" });
                    continue;
                }
                selection.morphism_count += 1;
                try dependencies.append(inputs.allocator, .{ .role = .morphism, .ref = morphism.evidenceRef() });
                const body = morphism.semanticBody();
                if (morphismBodyRejectedByPolicy(inputs.policy, inputs.treaty_policy, body, morphism.hostIntrinsicRef())) |tag| {
                    try rejected_candidates.append(inputs.allocator, .{ .tag = tag, .subject = inputs.shape.evidenceRef(), .primary = morphism.evidenceRef(), .summary = "morphism semantic body is rejected by closure policy" });
                    continue;
                }
                const static_adapter = body == .residualized_program or body == .pipeline;
                const dynamic_adapter = body == .host_intrinsic;
                if (!static_adapter and !dynamic_adapter) {
                    try rejected_candidates.append(inputs.allocator, .{ .tag = .dynamic_mapper_rejected, .subject = inputs.shape.evidenceRef(), .primary = morphism.evidenceRef(), .summary = "morphism offer lacks static or dynamic adapter evidence" });
                    continue;
                }
                if (dynamic_adapter) {
                    if (!inputs.treaty_policy.allow_dynamic_interpretation) {
                        try rejected_candidates.append(inputs.allocator, .{ .tag = .dynamic_mapper_rejected, .subject = inputs.shape.evidenceRef(), .primary = morphism.evidenceRef(), .summary = "treaty policy disallows dynamic morphism adapters" });
                        continue;
                    }
                    if (morphism.hostIntrinsicRef()) |ref| {
                        if (!inputAllowsIntrinsicOrWorldPort(inputs, ref, inputs.shape)) {
                            try rejected_candidates.append(inputs.allocator, .{ .tag = .unallowlisted_intrinsic, .subject = inputs.shape.evidenceRef(), .primary = ref, .summary = "dynamic morphism mapper is not allowlisted or exposed as a world port" });
                            continue;
                        }
                    } else {
                        try rejected_candidates.append(inputs.allocator, .{ .tag = .dynamic_mapper_rejected, .subject = inputs.shape.evidenceRef(), .primary = morphism.evidenceRef(), .summary = "dynamic morphism adapter lacks an intrinsic evidence ref" });
                        continue;
                    }
                }
                if (static_adapter) {
                    if (!inputs.treaty_policy.allow_residualization) {
                        try rejected_candidates.append(inputs.allocator, .{ .tag = .treaty_policy_incompatible, .subject = inputs.shape.evidenceRef(), .primary = morphism.evidenceRef(), .summary = "treaty policy disallows residualized or pipeline morphism adapters" });
                        continue;
                    }
                }
                if (static_adapter or dynamic_adapter) {
                    var target_response_refs_buffer: [3]BoundaryValueRef = undefined;
                    const target_shape = morphismTargetShape(inputs.shape, morphism, &target_response_refs_buffer);
                    morphism_provider_offers: for (inputs.provider_offers) |offer| {
                        offer.validate() catch {
                            try rejected_candidates.append(inputs.allocator, .{ .tag = .no_provider_offer_for_shape, .subject = inputs.shape.evidenceRef(), .primary = offer.evidenceRef(), .summary = "morphism provider offer fields are not bound to provider offer bytes" });
                            continue :morphism_provider_offers;
                        };
                        if (!offerMatchesMorphismTarget(offer, inputs.shape, morphism, target_shape)) continue :morphism_provider_offers;
                        const provider = providerManifestForOffer(inputs.provider_manifests, offer) orelse {
                            try rejected_candidates.append(inputs.allocator, .{ .tag = .no_provider_offer_for_shape, .subject = inputs.shape.evidenceRef(), .primary = offer.evidenceRef(), .summary = "morphism provider offer is not backed by a provider manifest" });
                            continue :morphism_provider_offers;
                        };
                        if (!providerManifestSupportsMorphismTarget(provider, target_shape)) {
                            try rejected_candidates.append(inputs.allocator, .{ .tag = .no_provider_offer_for_shape, .subject = inputs.shape.evidenceRef(), .primary = provider.evidenceRef(), .summary = "provider manifest does not support the morphism target shape" });
                            continue :morphism_provider_offers;
                        }
                        const provider_body = offer.semanticBodyWithProvider(provider);
                        if (providerBodyRejectedByPolicy(inputs.policy, inputs.treaty_policy, provider_body, offer.hostIntrinsicRef())) |tag| {
                            try rejected_candidates.append(inputs.allocator, .{ .tag = tag, .subject = inputs.shape.evidenceRef(), .primary = offer.evidenceRef(), .summary = "morphism provider semantic body is rejected by closure policy" });
                            continue :morphism_provider_offers;
                        }
                        if (provider_body == .host_intrinsic) {
                            if (offer.hostIntrinsicRef()) |ref| {
                                if (!inputAllowsIntrinsicOrWorldPort(inputs, ref, target_shape)) {
                                    try rejected_candidates.append(inputs.allocator, .{ .tag = .unallowlisted_intrinsic, .subject = inputs.shape.evidenceRef(), .primary = ref, .summary = "morphism target provider intrinsic is not allowlisted or exposed as a world port" });
                                    continue :morphism_provider_offers;
                                }
                            } else if (inputs.policy.reject_host_intrinsics) {
                                try rejected_candidates.append(inputs.allocator, .{ .tag = .intrinsic_route_rejected, .subject = inputs.shape.evidenceRef(), .primary = offer.evidenceRef(), .summary = "morphism target host-intrinsic provider lacks an intrinsic evidence ref" });
                                continue :morphism_provider_offers;
                            }
                        }
                        if (!providerOfferTagsAllowTreatyPolicy(inputs.treaty_policy, offer.tags)) {
                            try rejected_candidates.append(inputs.allocator, .{ .tag = .treaty_policy_incompatible, .subject = inputs.shape.evidenceRef(), .primary = offer.evidenceRef(), .summary = "morphism provider offer tags are incompatible with treaty policy" });
                            continue :morphism_provider_offers;
                        }
                        if (!treatyUsagePolicyAllowsMorphismTargetOffer(offer, inputs.shape, target_shape, inputs.treaty_policy)) {
                            try rejected_candidates.append(inputs.allocator, .{ .tag = .treaty_policy_incompatible, .subject = inputs.shape.evidenceRef(), .primary = offer.evidenceRef(), .summary = "morphism provider offer usage or replay policy is incompatible with treaty policy" });
                            continue :morphism_provider_offers;
                        }
                        var matched_capability = false;
                        morphism_capabilities: for (inputs.capabilities) |capability| {
                            if (!capabilityMatchesMorphismTarget(capability, offer, inputs.shape, morphism, target_shape)) continue :morphism_capabilities;
                            if (!targetCandidateResponseShapeAllowed(inputs.route_policy, provider, offer, capability, inputs.shape, morphism, target_shape)) continue :morphism_capabilities;
                            if (closureCapabilityBlockedByTreatyPolicy(capability, inputs.treaty_policy)) continue :morphism_capabilities;
                            matched_capability = true;
                            try dependencies.append(inputs.allocator, .{ .role = .offer, .ref = offer.evidenceRef() });
                            try dependencies.append(inputs.allocator, .{ .role = .capability, .ref = capability.evidenceRef() });
                            selectCandidate(inputs.policy, inputs.treaty_policy, inputs.route_policy, &selection, target_shape, provider, offer, capability, morphism, provider_body, offer.hostIntrinsicRef());
                        }
                        if (!matched_capability) {
                            try rejected_candidates.append(inputs.allocator, .{ .tag = .no_capability_for_shape, .subject = inputs.shape.evidenceRef(), .primary = offer.evidenceRef(), .summary = "morphism provider offer has no static capability grant for the target shape" });
                        }
                    }
                }
            }

            if (selection.offer_ref == null) {
                for (rejected_candidates.items) |candidate_blocker| {
                    if (!inputs.policy.require_static_treaty_plans and staticTreatyRequirementBlocker(candidate_blocker.tag)) continue;
                    try blockers.append(inputs.allocator, candidate_blocker);
                }
                if (selection.direct_count == 0 and selection.morphism_count == 0) {
                    if (inputs.policy.require_static_treaty_plans) {
                        try blockers.append(inputs.allocator, .{ .tag = .no_provider_offer_for_shape, .subject = inputs.shape.evidenceRef(), .summary = "no provider offer can handle this effect shape" });
                    }
                } else {
                    if (inputs.policy.require_static_treaty_plans) {
                        try blockers.append(inputs.allocator, .{ .tag = .no_static_treaty_plan, .subject = inputs.shape.evidenceRef(), .summary = "candidate offers exist but no static route satisfies policy and capability constraints" });
                    }
                }
            } else if (inputs.policy.reject_ambiguous_routes and selection.selected_rank_count > 1) {
                try blockers.append(inputs.allocator, .{ .tag = .ambiguous_static_treaty_plan, .subject = inputs.shape.evidenceRef(), .primary = selection.offer_ref, .summary = "multiple static treaty routes remain unresolved" });
            }
            return selection;
        }

        fn staticTreatyRequirementBlocker(tag: BoundaryClosureBlockerTag) bool {
            return boundaryStaticTreatyRequirementBlocker(tag);
        }

        fn analyzeShapes(
            allocator: std.mem.Allocator,
            input: Input,
            shapes: []const Closure.EffectShape,
            all_plans: *std.ArrayList(StaticTreatyPlan),
            blockers: *std.ArrayList(Blocker),
            plan_refs: *std.ArrayList(Ref),
            seen_shape_refs: *std.ArrayList(Ref),
            world_port_refs: *std.ArrayList(Ref),
            world_port_intrinsic_refs: *std.ArrayList(Ref),
            host_intrinsic_refs: *std.ArrayList(Ref),
            unknown_refs: *std.ArrayList(Ref),
            nodes: *std.ArrayList(Graph.Node),
            edges: *std.ArrayList(Graph.Edge),
            closed_count: *usize,
            world_port_shape_count: *usize,
            boundary_native_count: *usize,
            declarative_count: *usize,
            residualized_pipeline_count: *usize,
            intrinsic_count: *usize,
            ambiguity_count: *usize,
            root_program_refs: []const Ref,
            parent_provider_program_ref: ?Ref,
        ) !void {
            for (shapes) |shape| {
                const shape_ref = shape.evidenceRef();
                if (shape.fingerprint != shape.computeFingerprint()) {
                    const evidence_blocker = boundaryClosureBlocker(.{
                        .tag = .stale_effect_shape,
                        .subject = shape_ref,
                        .summary = "effect shape fields do not match its evidence fingerprint",
                    });
                    try blockers.append(allocator, evidence_blocker);
                    try appendBlockerGraph(allocator, nodes, edges, evidence_blocker);
                    continue;
                }
                if (refsContain(seen_shape_refs.items, shape_ref)) {
                    const evidence_blocker = boundaryClosureBlocker(.{
                        .tag = .duplicate_effect_shape,
                        .subject = shape_ref,
                        .summary = "duplicate effect shape is not certified twice",
                    });
                    try blockers.append(allocator, evidence_blocker);
                    try appendBlockerGraph(allocator, nodes, edges, evidence_blocker);
                    continue;
                }
                try seen_shape_refs.append(allocator, shape_ref);
                try nodes.append(allocator, .{ .kind = if (shape.kind == .after) .after_site else .operation_site, .ref = shape_ref, .label = shape.name });
                if (parent_provider_program_ref) |program_ref| {
                    try edges.append(allocator, .{ .kind = .provider_program_yields, .from = program_ref, .to = shape_ref });
                } else {
                    if (!try appendRootYieldEdges(allocator, edges, root_program_refs, shape_ref, shape)) {
                        const evidence_blocker = boundaryClosureBlocker(.{
                            .tag = .root_program_missing,
                            .subject = shape_ref,
                            .summary = "root effect shape does not match any declared root program",
                        });
                        try blockers.append(allocator, evidence_blocker);
                        try appendBlockerGraph(allocator, nodes, edges, evidence_blocker);
                    }
                }
                const plan = try planTreatyForShape(.{
                    .allocator = allocator,
                    .shape = shape,
                    .provider_manifests = input.provider_manifests,
                    .provider_offers = input.provider_offers,
                    .morphism_offers = input.morphism_offers,
                    .capabilities = input.capabilities,
                    .treaty_policy = input.treaty_policy,
                    .route_policy = input.route_policy,
                    .policy = input.policy,
                    .world_ports = input.world_ports,
                });
                var plan_appended = false;
                errdefer if (!plan_appended) {
                    allocator.free(plan.blockers);
                    allocator.free(plan.dependencies);
                };
                try all_plans.append(allocator, plan);
                plan_appended = true;
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
                const world_port_count_before_shape = world_port_refs.items.len;
                var selected_morphism_body: ?SemanticBody = null;
                if (plan.selected_morphism_ref) |morphism_ref| {
                    try nodes.append(allocator, .{ .kind = .morphism_offer, .ref = morphism_ref, .label = "morphism" });
                    try edges.append(allocator, .{ .kind = .adapted_by_morphism, .from = shape_ref, .to = morphism_ref });
                    if (morphismOfferForRef(input.morphism_offers, morphism_ref)) |morphism| {
                        selected_morphism_body = morphism.semanticBody();
                        if (morphism.hostIntrinsicRef()) |intrinsic_ref| {
                            try host_intrinsic_refs.append(allocator, intrinsic_ref);
                            intrinsic_count.* += 1;
                            try nodes.append(allocator, .{ .kind = .host_intrinsic, .ref = intrinsic_ref, .label = "dynamic morphism mapper" });
                            try edges.append(allocator, .{ .kind = .intrinsic_boundary, .from = shape_ref, .to = intrinsic_ref });
                            if (worldPortForShape(input.policy, input.world_ports, shape, intrinsic_ref)) |port| {
                                try world_port_refs.append(allocator, port.evidenceRef());
                                try world_port_intrinsic_refs.append(allocator, intrinsic_ref);
                                try nodes.append(allocator, .{ .kind = .world_port, .ref = port.evidenceRef(), .label = port.label });
                                try edges.append(allocator, .{ .kind = .opens_obligation, .from = shape_ref, .to = port.evidenceRef() });
                                try edges.append(allocator, .{ .kind = .world_port_exposes, .from = intrinsic_ref, .to = port.evidenceRef() });
                            }
                        }
                    }
                }
                if (plan.selected_intrinsic_ref) |intrinsic_ref| {
                    try host_intrinsic_refs.append(allocator, intrinsic_ref);
                    intrinsic_count.* += 1;
                    try nodes.append(allocator, .{ .kind = .host_intrinsic, .ref = intrinsic_ref, .label = "host intrinsic" });
                    try edges.append(allocator, .{ .kind = .intrinsic_boundary, .from = shape_ref, .to = intrinsic_ref });
                    if (worldPortForPlanIntrinsic(input, shape, plan, intrinsic_ref)) |port| {
                        try world_port_refs.append(allocator, port.evidenceRef());
                        try world_port_intrinsic_refs.append(allocator, intrinsic_ref);
                        try nodes.append(allocator, .{ .kind = .world_port, .ref = port.evidenceRef(), .label = port.label });
                        try edges.append(allocator, .{ .kind = .opens_obligation, .from = shape_ref, .to = port.evidenceRef() });
                        try edges.append(allocator, .{ .kind = .world_port_exposes, .from = intrinsic_ref, .to = port.evidenceRef() });
                    }
                }
                const closed_under_policy = plan.closedUnderPolicy(input.policy);
                const shape_world_port = if (!closed_under_policy) shapeOnlyWorldPortForShape(input.policy, input.world_ports, shape) else null;
                if (shape_world_port) |port| {
                    try world_port_refs.append(allocator, port.evidenceRef());
                    try world_port_intrinsic_refs.append(allocator, shape_ref);
                    try nodes.append(allocator, .{ .kind = .world_port, .ref = port.evidenceRef(), .label = port.label });
                    try edges.append(allocator, .{ .kind = .opens_obligation, .from = shape_ref, .to = port.evidenceRef() });
                }
                if (plan.selected_provider_offer_ref != null and plan.selected_semantic_body == .unknown) try unknown_refs.append(allocator, shape_ref);
                if (closed_under_policy) {
                    if (world_port_refs.items.len == world_port_count_before_shape) {
                        closed_count.* += 1;
                    } else {
                        world_port_shape_count.* += 1;
                    }
                    if (plan.boundary_native) boundary_native_count.* += 1;
                    switch (selected_morphism_body orelse plan.selected_semantic_body) {
                        .boundary_program, .kernel_primitive => {},
                        .declarative => declarative_count.* += 1,
                        .residualized_program, .pipeline => residualized_pipeline_count.* += 1,
                        .host_intrinsic, .unknown => {},
                    }
                } else if (shape_world_port != null) {
                    world_port_shape_count.* += 1;
                }
                plan_blockers: for (plan.blockers) |closure_blocker| {
                    if (shape_world_port != null and staticTreatyRequirementBlocker(closure_blocker.tag)) continue :plan_blockers;
                    const evidence_blocker = closure_blocker.toEvidenceBlocker();
                    try blockers.append(allocator, evidence_blocker);
                    try appendBlockerGraph(allocator, nodes, edges, evidence_blocker);
                    if (closure_blocker.tag == .ambiguous_static_treaty_plan) ambiguity_count.* += 1;
                }
            }
        }

        fn appendBlockerGraph(
            allocator: std.mem.Allocator,
            nodes: *std.ArrayList(Graph.Node),
            edges: *std.ArrayList(Graph.Edge),
            blocker: Blocker,
        ) !void {
            const blocker_ref = refForBoundaryClosureBlocker(blocker);
            try nodes.append(allocator, .{ .kind = .blocker, .ref = blocker_ref, .label = blocker.summary });
            if (blocker.subject) |subject_ref| {
                try edges.append(allocator, .{ .kind = .blocked_by, .from = subject_ref, .to = blocker_ref });
            }
        }

        fn appendRootYieldEdges(
            allocator: std.mem.Allocator,
            edges: *std.ArrayList(Graph.Edge),
            root_refs: []const Ref,
            shape_ref: Ref,
            shape: Closure.EffectShape,
        ) !bool {
            if (root_refs.len == 0) return true;
            var matched = false;
            for (root_refs) |root_ref| {
                if (!rootRefMatchesShape(root_ref, shape)) continue;
                try edges.append(allocator, .{ .kind = .root_yields, .from = root_ref, .to = shape_ref });
                matched = true;
            }
            return matched;
        }

        fn rootRefMatchesShape(root_ref: Ref, shape: Closure.EffectShape) bool {
            if (root_ref.domain_id != domains.program_plan.id) return false;
            if (shape.plan_hash != 0) return root_ref.fingerprint == shape.plan_hash;
            if (root_ref.label) |label| {
                if (std.mem.eql(u8, label, shape.program_label)) return true;
                if (shape.plan_label.len != 0 and std.mem.eql(u8, label, shape.plan_label)) return true;
            }
            return false;
        }

        fn providerShapeCountForKeys(programs: []const ProviderProgram, program_keys: []const SelectedProviderProgramKey) usize {
            var count: usize = 0;
            for (program_keys) |program_key| {
                for (programs) |program| {
                    if (providerProgramKey(program).eql(program_key)) {
                        count += program.shapes.len;
                        break;
                    }
                }
            }
            return count;
        }

        fn analyzeSelectedProviderPrograms(
            allocator: std.mem.Allocator,
            input: Input,
            all_plans: *std.ArrayList(StaticTreatyPlan),
            blockers: *std.ArrayList(Blocker),
            plan_refs: *std.ArrayList(Ref),
            seen_shape_refs: *std.ArrayList(Ref),
            provider_program_refs: *std.ArrayList(Ref),
            provider_program_keys: *std.ArrayList(SelectedProviderProgramKey),
            active_provider_program_refs: *std.ArrayList(Ref),
            active_provider_program_keys: *std.ArrayList(SelectedProviderProgramKey),
            world_port_refs: *std.ArrayList(Ref),
            world_port_intrinsic_refs: *std.ArrayList(Ref),
            host_intrinsic_refs: *std.ArrayList(Ref),
            unknown_refs: *std.ArrayList(Ref),
            nodes: *std.ArrayList(Graph.Node),
            edges: *std.ArrayList(Graph.Edge),
            closed_count: *usize,
            world_port_shape_count: *usize,
            boundary_native_count: *usize,
            declarative_count: *usize,
            residualized_pipeline_count: *usize,
            intrinsic_count: *usize,
            ambiguity_count: *usize,
            selected_plan_start: usize,
            selected_plan_end: usize,
            depth: usize,
        ) !void {
            provider_programs: for (input.provider_programs) |provider_program| {
                if (!providerProgramSelected(input, all_plans.items[selected_plan_start..selected_plan_end], provider_program)) continue :provider_programs;
                const selected_key = providerProgramKey(provider_program);
                if (providerProgramKeysContain(active_provider_program_keys.items, selected_key)) {
                    const evidence_blocker = boundaryClosureBlocker(.{
                        .tag = .cycle_detected,
                        .subject = provider_program.program_ref,
                        .primary = provider_program.provider_ref,
                        .summary = "selected provider program recurs through its own closure graph",
                    });
                    try blockers.append(allocator, evidence_blocker);
                    try appendBlockerGraph(allocator, nodes, edges, evidence_blocker);
                    continue :provider_programs;
                }
                if (providerProgramKeysContain(provider_program_keys.items, selected_key)) continue :provider_programs;
                if (depth >= input.policy.max_nested_provider_depth or depth >= input.policy.max_depth) {
                    const evidence_blocker = boundaryClosureBlocker(.{
                        .tag = .depth_limit_exceeded,
                        .subject = provider_program.program_ref,
                        .primary = provider_program.provider_ref,
                        .summary = "provider program nesting exceeds closure policy depth bound",
                    });
                    try blockers.append(allocator, evidence_blocker);
                    try appendBlockerGraph(allocator, nodes, edges, evidence_blocker);
                    continue :provider_programs;
                }

                try provider_program_refs.append(allocator, provider_program.program_ref);
                try provider_program_keys.append(allocator, selected_key);
                try active_provider_program_refs.append(allocator, provider_program.program_ref);
                try active_provider_program_keys.append(allocator, selected_key);
                try nodes.append(allocator, .{ .kind = .provider_program, .ref = provider_program.program_ref, .label = "provider program" });

                if (provider_program.shapes.len == 0 and !provider_program.effect_free) {
                    const evidence_blocker = boundaryClosureBlocker(.{
                        .tag = .provider_program_nested_unknown,
                        .subject = provider_program.program_ref,
                        .primary = provider_program.provider_ref,
                        .summary = "selected provider program has no nested effect-shape proof",
                    });
                    try blockers.append(allocator, evidence_blocker);
                    try appendBlockerGraph(allocator, nodes, edges, evidence_blocker);
                    _ = active_provider_program_refs.pop();
                    _ = active_provider_program_keys.pop();
                    continue :provider_programs;
                }

                const nested_plan_start = all_plans.items.len;
                try analyzeShapes(allocator, input, provider_program.shapes, all_plans, blockers, plan_refs, seen_shape_refs, world_port_refs, world_port_intrinsic_refs, host_intrinsic_refs, unknown_refs, nodes, edges, closed_count, world_port_shape_count, boundary_native_count, declarative_count, residualized_pipeline_count, intrinsic_count, ambiguity_count, &.{}, provider_program.program_ref);
                try analyzeSelectedProviderPrograms(allocator, input, all_plans, blockers, plan_refs, seen_shape_refs, provider_program_refs, provider_program_keys, active_provider_program_refs, active_provider_program_keys, world_port_refs, world_port_intrinsic_refs, host_intrinsic_refs, unknown_refs, nodes, edges, closed_count, world_port_shape_count, boundary_native_count, declarative_count, residualized_pipeline_count, intrinsic_count, ambiguity_count, nested_plan_start, all_plans.items.len, depth + 1);
                _ = active_provider_program_refs.pop();
                _ = active_provider_program_keys.pop();
            }
        }

        fn providerProgramKey(provider_program: ProviderProgram) SelectedProviderProgramKey {
            return .{
                .provider_ref = provider_program.provider_ref,
                .program_ref = provider_program.program_ref,
                .mapping_fingerprint = provider_program.provider_program_mapping_fingerprint,
                .effect_shape_fingerprint = fingerprintBoundaryEffectShapeSet(provider_program.shapes),
            };
        }

        fn providerProgramKeysContain(keys: []const SelectedProviderProgramKey, needle: SelectedProviderProgramKey) bool {
            for (keys) |key| {
                if (key.eql(needle)) return true;
            }
            return false;
        }

        fn providerProgramSelected(input: Input, plans: []const StaticTreatyPlan, provider_program: ProviderProgram) bool {
            for (plans) |plan| {
                const selected_program = selectedPlanProviderProgram(input, plan) orelse continue;
                const selected_provider_ref = plan.selected_provider_ref orelse continue;
                if (!selected_provider_ref.eql(provider_program.provider_ref)) continue;
                if (provider_program.provider_program_mapping_fingerprint) |program_mapping| {
                    if (program_mapping == selected_program.mapping_fingerprint and
                        provider_program.program_ref.eql(selected_program.program_ref) and
                        providerProgramShapesMatchSelected(provider_program, selected_program))
                    {
                        return true;
                    }
                }
            }
            return false;
        }

        fn providerProgramShapesMatchSelected(provider_program: ProviderProgram, selected_program: SelectedProviderProgram) bool {
            if (provider_program.effect_free) {
                if (selected_program.effect_shape_count != 0 or provider_program.shapes.len != 0) return false;
            } else if (provider_program.shapes.len != selected_program.effect_shape_count) return false;
            return fingerprintBoundaryEffectShapeSet(provider_program.shapes) == selected_program.effect_shape_fingerprint;
        }

        fn selectedPlanProviderProgram(input: Input, plan: StaticTreatyPlan) ?SelectedProviderProgram {
            if (plan.selected_semantic_body != .boundary_program) return null;
            const selected_offer_ref = plan.selected_provider_offer_ref orelse return null;
            for (input.provider_offers) |offer| {
                if (!offer.evidenceRef().eql(selected_offer_ref)) continue;
                const mapping_fingerprint = offer.provider_program_mapping_fingerprint orelse return null;
                const program_ref = offer.provider_program_ref orelse return null;
                const effect_shape_count = offer.provider_program_effect_shape_count orelse return null;
                const effect_shape_fingerprint = offer.provider_program_effect_shape_fingerprint orelse return null;
                return .{
                    .mapping_fingerprint = mapping_fingerprint,
                    .program_ref = program_ref,
                    .effect_shape_count = effect_shape_count,
                    .effect_shape_fingerprint = effect_shape_fingerprint,
                };
            }
            return null;
        }

        fn providerProgramForSelectedOffer(programs: []const ProviderProgram, provider_ref: Ref, selected_program: SelectedProviderProgram) ?ProviderProgram {
            for (programs) |program| {
                if (!program.provider_ref.eql(provider_ref)) continue;
                if (!program.program_ref.eql(selected_program.program_ref)) continue;
                if (!providerProgramShapesMatchSelected(program, selected_program)) continue;
                if (program.provider_program_mapping_fingerprint) |program_mapping| {
                    if (program_mapping == selected_program.mapping_fingerprint) return program;
                }
            }
            return null;
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

        fn shapeRequiresValueRef(shape: Closure.EffectShape) bool {
            return shape.kind == .operation or shape.kind == .after;
        }

        fn shapeSupportedForPlanning(shape: Closure.EffectShape) bool {
            if (shape.kind != .operation and shape.kind != .after) return false;
            return shape.site_index != null and
                shape.site_fingerprint != null and
                shape.protocol_label.len != 0 and
                shape.protocol_op_fingerprint != null;
        }

        fn hasClosureBlockerTag(blockers: []const BoundaryClosureBlocker, tag: BoundaryClosureBlockerTag) bool {
            for (blockers) |blocker| {
                if (blocker.tag == tag) return true;
            }
            return false;
        }

        fn selectedHostIntrinsicCount(selection: CandidateSelection) usize {
            if (selection.offer_ref == null) return 0;
            var count: usize = 0;
            if (selection.body == .host_intrinsic) count += 1;
            if (selection.morphism_body) |body| {
                if (body == .host_intrinsic) count += 1;
            }
            return count;
        }

        fn selectedIntrinsicCountBlocker(
            policy: Policy,
            treaty_policy: ProgramType.Exchange.Treaty.Policy,
            selection: CandidateSelection,
        ) ?BoundaryClosureBlockerTag {
            const count = selectedHostIntrinsicCount(selection);
            if (policy.defunctionalization_policy.maximum_intrinsic_count) |maximum| {
                if (count > maximum) return .defunctionalization_policy_incompatible;
            }
            if (closureDefunctionalizationPolicy(treaty_policy)) |defunc| {
                if (defunc.maximum_intrinsic_count) |maximum| {
                    if (count > maximum) return .treaty_policy_incompatible;
                }
            }
            return null;
        }

        fn selectCandidate(
            closure_policy: Policy,
            policy: ProgramType.Exchange.Treaty.Policy,
            route_policy: ProgramType.Exchange.Policy,
            selection: *CandidateSelection,
            shape: Closure.EffectShape,
            provider: ProgramType.Exchange.ProviderManifest,
            offer: ProgramType.Exchange.ProviderOffer,
            capability: ProgramType.Exchange.Capability,
            morphism: ?ProgramType.Exchange.MorphismOffer,
            body: SemanticBody,
            intrinsic_ref: ?Ref,
        ) void {
            const candidate_authority = closureCandidateAuthority(policy, route_policy, provider, offer, capability, shape);
            if (selection.offer_ref != null) {
                const candidate_preferred = closureCandidatePreferred(closure_policy, policy, selection.*, candidate_authority, provider, morphism, body);
                const selected_preferred = closureSelectedPreferred(closure_policy, policy, selection.*, candidate_authority, provider, morphism, body);
                if (candidate_preferred and !selected_preferred) {
                    selection.selected_rank_count = 0;
                } else {
                    if (!selected_preferred and closureTieIsAmbiguous(policy)) selection.selected_rank_count += 1;
                    return;
                }
            }
            selection.offer_ref = offer.evidenceRef();
            selection.provider_ref = provider.evidenceRef();
            selection.provider_fingerprint = provider.provider_fingerprint;
            selection.capability_ref = capability.evidenceRef();
            selection.morphism_ref = if (morphism) |morphism_offer| morphism_offer.evidenceRef() else null;
            selection.morphism_body = if (morphism) |morphism_offer| morphism_offer.semanticBody() else null;
            selection.body = body;
            selection.intrinsic_ref = intrinsic_ref;
            selection.selected_rank = closureCandidateRank(closure_policy, policy, body);
            selection.selected_rank_count = 1;
            selection.selected_authority = candidate_authority;
        }

        fn closureCandidatePreferred(
            closure_policy: Policy,
            policy: ProgramType.Exchange.Treaty.Policy,
            selected: CandidateSelection,
            candidate_authority: CandidateAuthority,
            provider: ProgramType.Exchange.ProviderManifest,
            morphism: ?ProgramType.Exchange.MorphismOffer,
            body: SemanticBody,
        ) bool {
            const candidate_closure_rank = closureCandidateRank(closure_policy, policy, body);
            if (candidate_closure_rank != selected.selected_rank) return candidate_closure_rank < selected.selected_rank;
            if (closureDefunctionalizationPreferenceEnabled(policy)) {
                const candidate_provider_rank = closureProviderSemanticBodyRank(body);
                const selected_provider_rank = closureProviderSemanticBodyRank(selected.body);
                if (closureDefunctionalizationProviderPreferenceEnabled(policy) and candidate_provider_rank != selected_provider_rank) return candidate_provider_rank < selected_provider_rank;
                const candidate_morphism_rank = if (morphism) |morphism_offer| closureMorphismSemanticBodyRank(policy, morphism_offer.semanticBody()) else 0;
                const selected_morphism_rank = if (selected.morphism_body) |selected_body| closureMorphismSemanticBodyRank(policy, selected_body) else 0;
                if (closureDefunctionalizationMorphismPreferenceEnabled(policy) and candidate_morphism_rank != selected_morphism_rank) return candidate_morphism_rank < selected_morphism_rank;
            }
            return switch (policy.ambiguity_policy) {
                .reject_ambiguous => false,
                .prefer_direct => closureHandlingRank(morphism, .prefer_direct) < closureSelectedHandlingRank(selected, .prefer_direct),
                .prefer_residualized => closureHandlingRank(morphism, .prefer_residualized) < closureSelectedHandlingRank(selected, .prefer_residualized),
                .prefer_dynamic => closureHandlingRank(morphism, .prefer_dynamic) < closureSelectedHandlingRank(selected, .prefer_dynamic),
                .prefer_least_authority => closureAuthorityLess(candidate_authority, selected.selected_authority) or (!closureAuthorityLess(selected.selected_authority, candidate_authority) and closureProviderPriorityLess(policy.provider_priority, provider.provider_fingerprint, selected.provider_fingerprint)),
                .host_ordered => closureProviderPriorityLess(policy.provider_priority, provider.provider_fingerprint, selected.provider_fingerprint),
            };
        }

        fn closureSelectedPreferred(
            closure_policy: Policy,
            policy: ProgramType.Exchange.Treaty.Policy,
            selected: CandidateSelection,
            candidate_authority: CandidateAuthority,
            provider: ProgramType.Exchange.ProviderManifest,
            morphism: ?ProgramType.Exchange.MorphismOffer,
            body: SemanticBody,
        ) bool {
            const selected_closure_rank = selected.selected_rank;
            const candidate_closure_rank = closureCandidateRank(closure_policy, policy, body);
            if (selected_closure_rank != candidate_closure_rank) return selected_closure_rank < candidate_closure_rank;
            if (closureDefunctionalizationPreferenceEnabled(policy)) {
                const selected_provider_rank = closureProviderSemanticBodyRank(selected.body);
                const candidate_provider_rank = closureProviderSemanticBodyRank(body);
                if (closureDefunctionalizationProviderPreferenceEnabled(policy) and selected_provider_rank != candidate_provider_rank) return selected_provider_rank < candidate_provider_rank;
                const selected_morphism_rank = if (selected.morphism_body) |selected_body| closureMorphismSemanticBodyRank(policy, selected_body) else 0;
                const candidate_morphism_rank = if (morphism) |morphism_offer| closureMorphismSemanticBodyRank(policy, morphism_offer.semanticBody()) else 0;
                if (closureDefunctionalizationMorphismPreferenceEnabled(policy) and selected_morphism_rank != candidate_morphism_rank) return selected_morphism_rank < candidate_morphism_rank;
            }
            return switch (policy.ambiguity_policy) {
                .reject_ambiguous => false,
                .prefer_direct => closureSelectedHandlingRank(selected, .prefer_direct) < closureHandlingRank(morphism, .prefer_direct),
                .prefer_residualized => closureSelectedHandlingRank(selected, .prefer_residualized) < closureHandlingRank(morphism, .prefer_residualized),
                .prefer_dynamic => closureSelectedHandlingRank(selected, .prefer_dynamic) < closureHandlingRank(morphism, .prefer_dynamic),
                .prefer_least_authority => closureAuthorityLess(selected.selected_authority, candidate_authority) or (!closureAuthorityLess(candidate_authority, selected.selected_authority) and closureProviderPriorityLess(policy.provider_priority, selected.provider_fingerprint, provider.provider_fingerprint)),
                .host_ordered => closureProviderPriorityLess(policy.provider_priority, selected.provider_fingerprint, provider.provider_fingerprint),
            };
        }

        fn closureCandidateAuthority(
            policy: ProgramType.Exchange.Treaty.Policy,
            route_policy: ProgramType.Exchange.Policy,
            provider: ProgramType.Exchange.ProviderManifest,
            offer: ProgramType.Exchange.ProviderOffer,
            capability: ProgramType.Exchange.Capability,
            shape: Closure.EffectShape,
        ) CandidateAuthority {
            var response_kinds = closureResponseKindIntersection(provider.allowed_response_kinds, capability.allowed_response_kinds);
            response_kinds = closureResponseKindIntersection(response_kinds, offer.allowed_response_kinds);
            response_kinds = closureResponseKindIntersection(response_kinds, route_policy.allowed_response_kinds);
            return .{
                .max_response_bytes = closureMinNonZero(.{
                    provider.max_response_envelope_bytes,
                    capability.max_response_bytes,
                    offer.max_response_bytes,
                    if (shape.max_response_bytes == 0) std.math.maxInt(usize) else shape.max_response_bytes,
                    policy.max_envelope_bytes,
                    route_policy.max_envelope_bytes,
                }),
                .max_payload_bytes = if (route_policy.allow_response_value_images) closureMinNonZero(.{
                    capability.max_payload_bytes,
                    if (shape.max_payload_bytes == 0) std.math.maxInt(usize) else shape.max_payload_bytes,
                    route_policy.max_payload_bytes,
                }) else 0,
                .capsule_restore_allowed = capability.allow_capsule_restore and provider.accepts_capsule_restore and route_policy.allow_capsule_restore,
                .response_kind_count = closureResponseKindCount(response_kinds),
                .attenuated = capability.parent_capability_fingerprint != null or policy.require_least_authority or policy.require_capability_attenuation,
            };
        }

        fn closureAuthorityLess(candidate: CandidateAuthority, selected: CandidateAuthority) bool {
            if (candidate.max_response_bytes != selected.max_response_bytes) return candidate.max_response_bytes < selected.max_response_bytes;
            if (candidate.max_payload_bytes != selected.max_payload_bytes) return candidate.max_payload_bytes < selected.max_payload_bytes;
            if (candidate.capsule_restore_allowed != selected.capsule_restore_allowed) return !candidate.capsule_restore_allowed;
            if (candidate.response_kind_count != selected.response_kind_count) return candidate.response_kind_count < selected.response_kind_count;
            if (candidate.attenuated != selected.attenuated) return candidate.attenuated;
            return false;
        }

        fn closureResponseKindIntersection(left: ProgramType.Exchange.Policy.ResponseKindSet, right: ProgramType.Exchange.Policy.ResponseKindSet) ProgramType.Exchange.Policy.ResponseKindSet {
            return .{
                .@"resume" = left.@"resume" and right.@"resume",
                .return_now = left.return_now and right.return_now,
                .resume_after = left.resume_after and right.resume_after,
            };
        }

        fn closureResponseKindCount(kinds: ProgramType.Exchange.Policy.ResponseKindSet) u8 {
            var count: u8 = 0;
            if (kinds.@"resume") count += 1;
            if (kinds.return_now) count += 1;
            if (kinds.resume_after) count += 1;
            return count;
        }

        fn closureMinNonZero(values: anytype) usize {
            var result: usize = std.math.maxInt(usize);
            inline for (values) |value| {
                if (value != 0) result = @min(result, value);
            }
            return result;
        }

        fn closureTieIsAmbiguous(policy: ProgramType.Exchange.Treaty.Policy) bool {
            return policy.ambiguity_policy != .host_ordered;
        }

        fn closureCandidateRank(closure_policy: Policy, policy: ProgramType.Exchange.Treaty.Policy, body: SemanticBody) u8 {
            const closure_rank = candidateRank(closure_policy, body);
            if (closure_rank != 0) return closure_rank;
            if (closureDefunctionalizationProviderPreferenceEnabled(policy)) return closureProviderSemanticBodyRank(body);
            return closure_rank;
        }

        fn closureHandlingRank(morphism: ?ProgramType.Exchange.MorphismOffer, policy: ProgramType.Exchange.Treaty.AmbiguityPolicy) u8 {
            const handling: ProgramType.Exchange.Treaty.HandlingKind = if (morphism) |morphism_offer| blk: {
                if (morphism_offer.dynamic_morphism_fingerprint != null) break :blk .dynamic_morphism;
                if (morphism_offer.residual_morphism_fingerprint != null or morphism_offer.pipeline_fingerprint != null) break :blk .residualized;
                break :blk .direct;
            } else .direct;
            return closureTreatyHandlingRank(handling, policy);
        }

        fn closureSelectedHandlingRank(selected: CandidateSelection, policy: ProgramType.Exchange.Treaty.AmbiguityPolicy) u8 {
            const handling: ProgramType.Exchange.Treaty.HandlingKind = if (selected.morphism_ref == null) .direct else switch (selected.morphism_body orelse .unknown) {
                .host_intrinsic => .dynamic_morphism,
                .residualized_program, .pipeline, .declarative => .residualized,
                .boundary_program, .kernel_primitive, .unknown => .direct,
            };
            return closureTreatyHandlingRank(handling, policy);
        }

        fn closureTreatyHandlingRank(handling: ProgramType.Exchange.Treaty.HandlingKind, policy: ProgramType.Exchange.Treaty.AmbiguityPolicy) u8 {
            return switch (policy) {
                .prefer_direct => switch (handling) {
                    .direct => 0,
                    .residualized, .pipeline_adapted => 1,
                    .dynamic_morphism => 2,
                },
                .prefer_residualized => switch (handling) {
                    .residualized, .pipeline_adapted => 0,
                    .direct => 1,
                    .dynamic_morphism => 2,
                },
                .prefer_dynamic => switch (handling) {
                    .dynamic_morphism => 0,
                    .residualized, .pipeline_adapted => 1,
                    .direct => 2,
                },
                .reject_ambiguous,
                .prefer_least_authority,
                .host_ordered,
                => 0,
            };
        }

        fn closureDefunctionalizationPreferenceEnabled(policy: ProgramType.Exchange.Treaty.Policy) bool {
            return closureDefunctionalizationProviderPreferenceEnabled(policy) or
                closureDefunctionalizationMorphismPreferenceEnabled(policy);
        }

        fn closureDefunctionalizationProviderPreferenceEnabled(policy: ProgramType.Exchange.Treaty.Policy) bool {
            const defunc = closureDefunctionalizationPolicy(policy) orelse return false;
            return defunc.prefer_boundary_program;
        }

        fn closureDefunctionalizationMorphismPreferenceEnabled(policy: ProgramType.Exchange.Treaty.Policy) bool {
            const defunc = closureDefunctionalizationPolicy(policy) orelse return false;
            return defunc.prefer_declarative or defunc.prefer_residualized;
        }

        fn closureDefunctionalizationPolicy(policy: ProgramType.Exchange.Treaty.Policy) ?DefunctionalizationPolicy {
            const configured =
                policy.prefer_program_backed_provider or
                policy.reject_intrinsic_provider or
                policy.reject_intrinsic_morphism or
                policy.allowed_intrinsic_kinds.len != 0 or
                policy.allowed_intrinsic_fingerprints.len != 0;
            if (policy.defunctionalization_policy == null and !configured) return null;
            var defunc = policy.defunctionalization_policy orelse DefunctionalizationPolicy{
                .label = "treaty",
                .allow_host_intrinsics = true,
                .allowed_intrinsic_kinds = policy.allowed_intrinsic_kinds,
                .allowed_intrinsic_fingerprints = policy.allowed_intrinsic_fingerprints,
                .reject_unknown = policy.reject_intrinsic_provider or
                    policy.reject_intrinsic_morphism or
                    policy.allowed_intrinsic_kinds.len != 0 or
                    policy.allowed_intrinsic_fingerprints.len != 0,
                .reject_dynamic_mappers = policy.reject_intrinsic_morphism,
                .require_program_backed_providers = policy.reject_intrinsic_provider,
                .require_declarative_morphisms = policy.reject_intrinsic_morphism,
                .prefer_boundary_program = policy.prefer_program_backed_provider,
                .prefer_declarative = policy.reject_intrinsic_morphism,
                .prefer_residualized = policy.reject_intrinsic_morphism,
            };
            defunc.reject_unknown = defunc.reject_unknown or
                policy.reject_intrinsic_provider or
                policy.reject_intrinsic_morphism or
                policy.allowed_intrinsic_kinds.len != 0 or
                policy.allowed_intrinsic_fingerprints.len != 0;
            defunc.reject_dynamic_mappers = defunc.reject_dynamic_mappers or policy.reject_intrinsic_morphism;
            defunc.require_program_backed_providers = defunc.require_program_backed_providers or policy.reject_intrinsic_provider;
            defunc.require_declarative_morphisms = defunc.require_declarative_morphisms or policy.reject_intrinsic_morphism;
            defunc.prefer_boundary_program = defunc.prefer_boundary_program or policy.prefer_program_backed_provider;
            defunc.prefer_declarative = defunc.prefer_declarative or policy.reject_intrinsic_morphism;
            defunc.prefer_residualized = defunc.prefer_residualized or policy.reject_intrinsic_morphism;
            return defunc;
        }

        fn closureProviderSemanticBodyRank(body: SemanticBody) u8 {
            return switch (body) {
                .boundary_program => 0,
                .declarative, .residualized_program, .pipeline => 1,
                .kernel_primitive => 2,
                .host_intrinsic => 3,
                .unknown => 4,
            };
        }

        fn closureMorphismSemanticBodyRank(policy: ProgramType.Exchange.Treaty.Policy, body: SemanticBody) u8 {
            const defunc = closureDefunctionalizationPolicy(policy) orelse return closureProviderSemanticBodyRank(body);
            if (defunc.prefer_declarative and !defunc.prefer_residualized) {
                return switch (body) {
                    .declarative => 0,
                    .residualized_program => 1,
                    .pipeline => 2,
                    .boundary_program, .kernel_primitive => 3,
                    .host_intrinsic => 4,
                    .unknown => 5,
                };
            }
            if (defunc.prefer_residualized and !defunc.prefer_declarative) {
                return switch (body) {
                    .residualized_program => 0,
                    .pipeline => 1,
                    .declarative => 2,
                    .boundary_program, .kernel_primitive => 3,
                    .host_intrinsic => 4,
                    .unknown => 5,
                };
            }
            return closureProviderSemanticBodyRank(body);
        }

        fn closureProviderPriorityLess(priority: ?[]const u64, candidate: u64, selected: u64) bool {
            const values = priority orelse return false;
            const candidate_index = closureProviderPriorityIndex(values, candidate) orelse return false;
            const selected_index = closureProviderPriorityIndex(values, selected) orelse return true;
            return candidate_index < selected_index;
        }

        fn closureProviderPriorityIndex(priority: []const u64, provider_fingerprint: u64) ?usize {
            for (priority, 0..) |value, index| {
                if (value == provider_fingerprint) return index;
            }
            return null;
        }

        fn providerBodyRejectedByPolicy(policy: Policy, treaty_policy: ProgramType.Exchange.Treaty.Policy, body: SemanticBody, intrinsic_ref: ?Ref) ?BoundaryClosureBlockerTag {
            const treaty_defunc = closureDefunctionalizationPolicy(treaty_policy);
            if (body == .unknown and (policy.reject_unknown_semantic_bodies or policy.defunctionalization_policy.reject_unknown)) return .unknown_semantic_body;
            if (treaty_defunc) |defunc| {
                if (body == .unknown and defunc.reject_unknown) return .unknown_semantic_body;
            }
            if (body == .kernel_primitive and !policy.allow_kernel_primitives) return .defunctionalization_policy_incompatible;
            if (body == .kernel_primitive and !policy.defunctionalization_policy.allow_kernel_primitives) return .defunctionalization_policy_incompatible;
            if (treaty_defunc) |defunc| {
                if (body == .kernel_primitive and !defunc.allow_kernel_primitives) return .defunctionalization_policy_incompatible;
            }
            if (policy.require_program_backed_providers or policy.defunctionalization_policy.require_program_backed_providers) {
                if (body != .boundary_program) return .defunctionalization_policy_incompatible;
            }
            if (treaty_defunc) |defunc| {
                if (defunc.require_program_backed_providers and body != .boundary_program) return .defunctionalization_policy_incompatible;
            }
            if (body == .host_intrinsic) {
                if (policy.defunctionalization_policy.require_no_intrinsics_in_treaties or !policy.defunctionalization_policy.allow_host_intrinsics) return .intrinsic_route_rejected;
                if (treaty_policy.reject_intrinsic_provider) return .intrinsic_route_rejected;
                if (treaty_defunc) |defunc| {
                    if (defunc.require_no_intrinsics_in_treaties or !defunc.allow_host_intrinsics) return .intrinsic_route_rejected;
                    if (intrinsic_ref) |ref| {
                        if (!defunc.allowsIntrinsicRef(ref)) return .unallowlisted_intrinsic;
                        if (!closureIntrinsicRefAllowedByTreatyPolicy(ref, treaty_policy)) return .unallowlisted_intrinsic;
                    }
                }
                if (intrinsic_ref) |ref| {
                    if (!policy.defunctionalization_policy.allowsIntrinsicRef(ref)) return .unallowlisted_intrinsic;
                    if (!closureIntrinsicRefAllowedByTreatyPolicy(ref, treaty_policy)) return .unallowlisted_intrinsic;
                }
            }
            return null;
        }

        fn morphismPlanningBlocker(inputs: PlanInputs) ?BoundaryClosureBlockerTag {
            if (!inputs.treaty_policy.allow_morphism_adaptation) return .treaty_policy_incompatible;
            if (inputs.policy.max_morphism_hops == 0 or inputs.treaty_policy.max_morphism_hops == 0) return .treaty_policy_incompatible;
            return null;
        }

        fn morphismTargetShape(shape: Closure.EffectShape, morphism: ProgramType.Exchange.MorphismOffer, target_response_refs_buffer: *[3]BoundaryValueRef) Closure.EffectShape {
            var target = shape;
            target.protocol_op_fingerprint = morphism.target_protocol_op_fingerprint;
            target.usage_summary = @tagName(morphism.target_usage);
            if (morphism.target_response_refs.len != 0) {
                var count: usize = 0;
                for (morphism.target_response_refs) |ref| {
                    if (count == target_response_refs_buffer.len) break;
                    target_response_refs_buffer[count] = BoundaryValueRef.fromValueRef(ref);
                    count += 1;
                }
                target.desired_response_refs = target_response_refs_buffer[0..count];
            }
            target.fingerprint = target.computeFingerprint();
            return target;
        }

        fn worldPortForPlanIntrinsic(input: Input, shape: Closure.EffectShape, plan: StaticTreatyPlan, intrinsic_ref: Ref) ?Closure.WorldPort {
            if (plan.selected_morphism_ref) |morphism_ref| {
                if (morphismOfferForRef(input.morphism_offers, morphism_ref)) |morphism| {
                    var target_response_refs_buffer: [3]BoundaryValueRef = undefined;
                    const target_shape = morphismTargetShape(shape, morphism, &target_response_refs_buffer);
                    return worldPortForShape(input.policy, input.world_ports, target_shape, intrinsic_ref);
                }
            }
            return worldPortForShape(input.policy, input.world_ports, shape, intrinsic_ref);
        }

        fn morphismOfferForRef(morphisms: []const ProgramType.Exchange.MorphismOffer, ref: Ref) ?ProgramType.Exchange.MorphismOffer {
            for (morphisms) |morphism| {
                if (morphism.evidenceRef().eql(ref)) return morphism;
            }
            return null;
        }

        fn morphismBodyRejectedByPolicy(policy: Policy, treaty_policy: ProgramType.Exchange.Treaty.Policy, body: SemanticBody, intrinsic_ref: ?Ref) ?BoundaryClosureBlockerTag {
            const treaty_defunc = closureDefunctionalizationPolicy(treaty_policy);
            if (body == .unknown and (policy.reject_unknown_semantic_bodies or policy.defunctionalization_policy.reject_unknown)) return .unknown_semantic_body;
            if (treaty_defunc) |defunc| {
                if (body == .unknown and defunc.reject_unknown) return .unknown_semantic_body;
            }
            if (body == .host_intrinsic) {
                if (policy.require_declarative_morphisms or policy.defunctionalization_policy.require_declarative_morphisms) return .dynamic_mapper_rejected;
                if (policy.defunctionalization_policy.reject_dynamic_mappers or policy.defunctionalization_policy.require_no_intrinsics_in_treaties or !policy.defunctionalization_policy.allow_host_intrinsics) return .dynamic_mapper_rejected;
                if (treaty_policy.reject_intrinsic_morphism) return .dynamic_mapper_rejected;
                if (treaty_defunc) |defunc| {
                    if (defunc.reject_dynamic_mappers or defunc.require_declarative_morphisms or defunc.require_no_intrinsics_in_treaties or !defunc.allow_host_intrinsics) return .dynamic_mapper_rejected;
                    if (intrinsic_ref) |ref| {
                        if (!defunc.allowsIntrinsicRef(ref)) return .unallowlisted_intrinsic;
                        if (!closureIntrinsicRefAllowedByTreatyPolicy(ref, treaty_policy)) return .unallowlisted_intrinsic;
                    }
                }
                if (intrinsic_ref) |ref| {
                    if (!policy.defunctionalization_policy.allowsIntrinsicRef(ref)) return .unallowlisted_intrinsic;
                    if (!closureIntrinsicRefAllowedByTreatyPolicy(ref, treaty_policy)) return .unallowlisted_intrinsic;
                }
            }
            if (policy.require_declarative_morphisms or policy.defunctionalization_policy.require_declarative_morphisms) {
                if (body != .declarative and body != .residualized_program and body != .pipeline) return .defunctionalization_policy_incompatible;
            }
            if (treaty_defunc) |defunc| {
                if (defunc.require_declarative_morphisms and body != .declarative and body != .residualized_program and body != .pipeline) return .defunctionalization_policy_incompatible;
            }
            return null;
        }

        fn closureRoutePolicyAllowsProvider(policy: ProgramType.Exchange.Policy, provider_fingerprint: u64) bool {
            const allowed = policy.allowed_provider_fingerprints orelse return true;
            for (allowed) |fingerprint| if (fingerprint == provider_fingerprint) return true;
            return false;
        }

        fn closureRoutePolicyAllowsCapability(policy: ProgramType.Exchange.Policy, capability_fingerprint: u64) bool {
            const allowed = policy.allowed_capability_fingerprints orelse return true;
            for (allowed) |fingerprint| if (fingerprint == capability_fingerprint) return true;
            return false;
        }

        fn closureRoutePolicyAllowsShape(policy: ProgramType.Exchange.Policy, shape: Closure.EffectShape) bool {
            if (shape.max_request_bytes != 0 and shape.max_request_bytes > policy.max_envelope_bytes) return false;
            if (shape.max_response_bytes != 0 and shape.max_response_bytes > policy.max_envelope_bytes) return false;
            if (!closureRoutePolicyAllowsShapeSite(policy, shape)) return false;
            if (!policy.allow_response_value_images and shape.max_payload_bytes != 0) return false;
            if (shape.max_payload_bytes != 0 and shape.max_payload_bytes > policy.max_payload_bytes) return false;
            if (shape.max_capsule_image_bytes != 0) {
                if (!policy.allow_capsules) return false;
                const capsule_limit = policy.max_capsule_image_bytes orelse policy.max_payload_bytes;
                if (shape.max_capsule_image_bytes > capsule_limit) return false;
            }
            return true;
        }

        fn closureRoutePolicyAllowsShapeSite(policy: ProgramType.Exchange.Policy, shape: Closure.EffectShape) bool {
            const allowed = if (shape.kind == .after) policy.allowed_after_sites else policy.allowed_operation_sites;
            const list = allowed orelse return true;
            const site_index = shape.site_index orelse return false;
            return listAllowsUsizeClosure(list, site_index);
        }

        fn closureCapabilityBlockedByTreatyPolicy(capability: ProgramType.Exchange.Capability, policy: ProgramType.Exchange.Treaty.Policy) bool {
            return policy.require_capability_attenuation and
                capability.parent_capability_fingerprint == null;
        }

        fn closureIntrinsicRefAllowedByTreatyPolicy(intrinsic_ref: Ref, policy: ProgramType.Exchange.Treaty.Policy) bool {
            if (policy.allowed_intrinsic_fingerprints.len == 0 and policy.allowed_intrinsic_kinds.len == 0) return true;
            if (intrinsic_ref.domain_id != domains.host_intrinsic.id) return false;
            for (policy.allowed_intrinsic_fingerprints) |allowed| if (allowed == intrinsic_ref.fingerprint) return true;
            if (intrinsic_ref.kind_tag) |kind_tag| {
                for (policy.allowed_intrinsic_kinds) |allowed| {
                    if (std.mem.eql(u8, @tagName(allowed), kind_tag)) return true;
                }
            }
            return false;
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

        fn providerManifestSupportsShape(provider: ProgramType.Exchange.ProviderManifest, shape: Closure.EffectShape) bool {
            if (!provider.fieldsBoundToBytes()) return false;
            if (shape.manifest_fingerprint) |manifest_fingerprint| {
                if (!listAllowsU64Closure(provider.supported_program_manifest_fingerprints, manifest_fingerprint)) return false;
            }
            if (!listAllowsStringClosure(provider.supported_protocol_labels, shape.protocol_label)) return false;
            if (!constrainedOptionalU64AllowsClosure(provider.supported_protocol_op_fingerprints, shape.protocol_op_fingerprint, false)) return false;
            if (shape.max_request_bytes != 0 and shape.max_request_bytes > provider.max_request_envelope_bytes) return false;
            if (shape.max_response_bytes != 0 and shape.max_response_bytes > provider.max_response_envelope_bytes) return false;
            if (shape.max_capsule_image_bytes != 0 and !provider.accepts_embedded_capsules) return false;
            const operation_sites_constrained = provider.supported_operation_sites.len != 0;
            const after_sites_constrained = provider.supported_after_sites.len != 0;
            if (shape.kind == .after) {
                if (!after_sites_constrained and operation_sites_constrained) return false;
                if (!constrainedOptionalUsizeAllowsClosure(provider.supported_after_sites, shape.site_index, false)) return false;
            } else {
                if (!operation_sites_constrained and after_sites_constrained) return false;
                if (!constrainedOptionalUsizeAllowsClosure(provider.supported_operation_sites, shape.site_index, false)) return false;
            }
            return true;
        }

        fn providerManifestSupportsMorphismTarget(provider: ProgramType.Exchange.ProviderManifest, shape: Closure.EffectShape) bool {
            if (!provider.fieldsBoundToBytes()) return false;
            if (shape.manifest_fingerprint) |manifest_fingerprint| {
                if (!listAllowsU64Closure(provider.supported_program_manifest_fingerprints, manifest_fingerprint)) return false;
            }
            if (shape.protocol_op_fingerprint) |protocol_op| {
                if (provider.supported_protocol_op_fingerprints.len == 0 and provider.supported_protocol_labels.len != 0) return false;
                if (!listAllowsU64Closure(provider.supported_protocol_op_fingerprints, protocol_op)) return false;
            } else if (provider.supported_protocol_op_fingerprints.len != 0 or provider.supported_protocol_labels.len != 0) {
                return false;
            }
            if (shape.max_request_bytes != 0 and shape.max_request_bytes > provider.max_request_envelope_bytes) return false;
            if (shape.max_response_bytes != 0 and shape.max_response_bytes > provider.max_response_envelope_bytes) return false;
            if (shape.max_capsule_image_bytes != 0 and !provider.accepts_embedded_capsules) return false;
            const operation_sites_constrained = provider.supported_operation_sites.len != 0;
            const after_sites_constrained = provider.supported_after_sites.len != 0;
            if (shape.kind == .after) {
                if (!after_sites_constrained and operation_sites_constrained) return false;
                if (!constrainedOptionalUsizeAllowsClosure(provider.supported_after_sites, shape.site_index, false)) return false;
            } else {
                if (!operation_sites_constrained and after_sites_constrained) return false;
                if (!constrainedOptionalUsizeAllowsClosure(provider.supported_operation_sites, shape.site_index, false)) return false;
            }
            return true;
        }

        fn capabilityMatchesShape(capability: ProgramType.Exchange.Capability, offer: ProgramType.Exchange.ProviderOffer, shape: Closure.EffectShape) bool {
            if (!capability.fieldsBoundToBytes()) return false;
            if (capability.provider_fingerprint != offer.provider_fingerprint) return false;
            if (capability.manifest_fingerprint != offer.manifest_fingerprint) return false;
            if (shape.manifest_fingerprint) |manifest_fingerprint| {
                if (capability.manifest_fingerprint != manifest_fingerprint) return false;
            }
            if (!listAllowsStringClosure(capability.allowed_program_labels, shape.program_label)) return false;
            if (!listAllowsU64Closure(capability.allowed_plan_hashes, shape.plan_hash)) return false;
            if (shape.kind == .after) {
                if (!constrainedOptionalUsizeAllowsClosure(capability.allowed_after_sites, shape.site_index, false)) return false;
            } else {
                if (!constrainedOptionalUsizeAllowsClosure(capability.allowed_operation_sites, shape.site_index, false)) return false;
            }
            if (!constrainedOptionalU64AllowsClosure(capability.allowed_protocol_op_fingerprints, shape.protocol_op_fingerprint, false)) return false;
            if (!listAllowsStringClosure(capability.allowed_requirement_labels, shape.protocol_label)) return false;
            if (!listAllowsStringClosure(capability.allowed_op_names, shape.name)) return false;
            if (!capabilityAllowsShapeRequestKind(capability, shape)) return false;
            if (shape.max_request_bytes != 0 and shape.max_request_bytes > capability.max_request_bytes) return false;
            if (shape.max_payload_bytes != 0 and shape.max_payload_bytes > capability.max_payload_bytes) return false;
            if (shape.max_response_bytes != 0 and shape.max_response_bytes > capability.max_response_bytes) return false;
            if (shape.max_capsule_image_bytes != 0) {
                if (!capability.allow_embedded_capsule_response_handling) return false;
                if (shape.max_capsule_image_bytes > capability.max_capsule_image_bytes) return false;
            }
            if (!directResponseShapeAllowed(capability.allowed_response_kinds, capability.allowed_response_refs, shape)) return false;
            return true;
        }

        fn capabilityMatchesMorphismTarget(
            capability: ProgramType.Exchange.Capability,
            offer: ProgramType.Exchange.ProviderOffer,
            source_shape: Closure.EffectShape,
            morphism: ProgramType.Exchange.MorphismOffer,
            shape: Closure.EffectShape,
        ) bool {
            if (!capability.fieldsBoundToBytes()) return false;
            if (capability.provider_fingerprint != offer.provider_fingerprint) return false;
            if (capability.manifest_fingerprint != offer.manifest_fingerprint) return false;
            if (shape.manifest_fingerprint) |manifest_fingerprint| {
                if (capability.manifest_fingerprint != manifest_fingerprint) return false;
            }
            if (!listAllowsStringClosure(capability.allowed_program_labels, shape.program_label)) return false;
            if (!listAllowsU64Closure(capability.allowed_plan_hashes, shape.plan_hash)) return false;
            if (shape.kind == .after) {
                if (!constrainedOptionalUsizeAllowsClosure(capability.allowed_after_sites, shape.site_index, false)) return false;
            } else {
                if (!constrainedOptionalUsizeAllowsClosure(capability.allowed_operation_sites, shape.site_index, false)) return false;
            }
            if (!constrainedOptionalU64AllowsClosure(capability.allowed_protocol_op_fingerprints, shape.protocol_op_fingerprint, false)) return false;
            if (capability.allowed_protocol_op_fingerprints.len == 0 and
                (capability.allowed_requirement_labels.len != 0 or capability.allowed_op_names.len != 0))
            {
                return false;
            }
            if (!capabilityAllowsShapeRequestKind(capability, shape)) return false;
            if (shape.max_request_bytes != 0 and shape.max_request_bytes > capability.max_request_bytes) return false;
            if (shape.max_payload_bytes != 0 and shape.max_payload_bytes > capability.max_payload_bytes) return false;
            if (shape.max_response_bytes != 0 and shape.max_response_bytes > capability.max_response_bytes) return false;
            if (shape.max_capsule_image_bytes != 0) {
                if (!capability.allow_embedded_capsule_response_handling) return false;
                if (shape.max_capsule_image_bytes > capability.max_capsule_image_bytes) return false;
            }
            if (!targetResponseShapeAllowed(capability.allowed_response_kinds, capability.allowed_response_refs, source_shape, morphism, shape)) return false;
            return true;
        }

        fn directCandidateResponseShapeAllowed(
            policy: ProgramType.Exchange.Policy,
            provider: ProgramType.Exchange.ProviderManifest,
            offer: ProgramType.Exchange.ProviderOffer,
            capability: ProgramType.Exchange.Capability,
            shape: Closure.EffectShape,
        ) bool {
            if (!closureRoutePolicyAllowsProvider(policy, provider.provider_fingerprint)) return false;
            if (!closureRoutePolicyAllowsCapability(policy, capability.fingerprint)) return false;
            if (!closureRoutePolicyAllowsShape(policy, shape)) return false;
            var kinds = closureResponseKindIntersection(provider.allowed_response_kinds, capability.allowed_response_kinds);
            kinds = closureResponseKindIntersection(kinds, offer.allowed_response_kinds);
            kinds = closureResponseKindIntersection(kinds, policy.allowed_response_kinds);
            return directResponseShapeAllowedByRefs(kinds, offer.produced_response_refs, capability.allowed_response_refs, shape);
        }

        fn targetCandidateResponseShapeAllowed(
            policy: ProgramType.Exchange.Policy,
            provider: ProgramType.Exchange.ProviderManifest,
            offer: ProgramType.Exchange.ProviderOffer,
            capability: ProgramType.Exchange.Capability,
            source_shape: Closure.EffectShape,
            morphism: ProgramType.Exchange.MorphismOffer,
            shape: Closure.EffectShape,
        ) bool {
            if (!closureRoutePolicyAllowsProvider(policy, provider.provider_fingerprint)) return false;
            if (!closureRoutePolicyAllowsCapability(policy, capability.fingerprint)) return false;
            if (!closureRoutePolicyAllowsShape(policy, shape)) return false;
            var kinds = closureResponseKindIntersection(provider.allowed_response_kinds, capability.allowed_response_kinds);
            kinds = closureResponseKindIntersection(kinds, offer.allowed_response_kinds);
            kinds = closureResponseKindIntersection(kinds, policy.allowed_response_kinds);
            return targetResponseShapeAllowedByRefs(kinds, offer.produced_response_refs, capability.allowed_response_refs, source_shape, morphism, shape);
        }

        fn offerMatchesShape(offer: ProgramType.Exchange.ProviderOffer, shape: Closure.EffectShape) bool {
            offer.validate() catch return false;
            if (!offer.capsule_policy.allows(shapeCarriesCapsule(shape))) return false;
            if (shape.manifest_fingerprint) |manifest_fingerprint| {
                if (offer.manifest_fingerprint != manifest_fingerprint) return false;
            }
            if (!listAllowsStringClosure(offer.supported_protocol_labels, shape.protocol_label)) return false;
            if (!constrainedOptionalU64AllowsClosure(offer.supported_protocol_op_fingerprints, shape.protocol_op_fingerprint, false)) return false;
            if (shape.max_request_bytes != 0 and shape.max_request_bytes > offer.max_request_bytes) return false;
            if (shape.max_response_bytes != 0 and shape.max_response_bytes > offer.max_response_bytes) return false;
            if (shape.max_capsule_image_bytes != 0 and shape.max_capsule_image_bytes > offer.max_capsule_bytes) return false;
            if (!directResponseShapeAllowed(offer.allowed_response_kinds, offer.produced_response_refs, shape)) return false;
            const operation_sites_constrained = offer.supported_operation_sites.len != 0;
            const after_sites_constrained = offer.supported_after_sites.len != 0;
            if (shape.kind == .after) {
                if (!after_sites_constrained and operation_sites_constrained) return false;
                if (!constrainedOptionalUsizeAllowsClosure(offer.supported_after_sites, shape.site_index, false)) return false;
                if (shape.value_ref) |ref| if (!listAllowsBoundaryValueRef(offer.accepted_current_value_refs, ref)) return false;
            } else {
                if (!operation_sites_constrained and after_sites_constrained) return false;
                if (!constrainedOptionalUsizeAllowsClosure(offer.supported_operation_sites, shape.site_index, false)) return false;
                if (shape.value_ref) |ref| if (!listAllowsBoundaryValueRef(offer.accepted_payload_refs, ref)) return false;
            }
            return true;
        }

        fn offerMatchesMorphismTarget(
            offer: ProgramType.Exchange.ProviderOffer,
            source_shape: Closure.EffectShape,
            morphism: ProgramType.Exchange.MorphismOffer,
            shape: Closure.EffectShape,
        ) bool {
            offer.validate() catch return false;
            if (!offer.capsule_policy.allows(shapeCarriesCapsule(shape))) return false;
            if (shape.manifest_fingerprint) |manifest_fingerprint| {
                if (offer.manifest_fingerprint != manifest_fingerprint) return false;
            }
            if (shape.protocol_op_fingerprint) |protocol_op| {
                if (offer.supported_protocol_op_fingerprints.len == 0 and offer.supported_protocol_labels.len != 0) return false;
                if (!listAllowsU64Closure(offer.supported_protocol_op_fingerprints, protocol_op)) return false;
            } else if (offer.supported_protocol_op_fingerprints.len != 0 or offer.supported_protocol_labels.len != 0) {
                return false;
            }
            if (shape.max_request_bytes != 0 and shape.max_request_bytes > offer.max_request_bytes) return false;
            if (shape.max_response_bytes != 0 and shape.max_response_bytes > offer.max_response_bytes) return false;
            if (shape.max_capsule_image_bytes != 0 and shape.max_capsule_image_bytes > offer.max_capsule_bytes) return false;
            if (!targetResponseShapeAllowed(offer.allowed_response_kinds, offer.produced_response_refs, source_shape, morphism, shape)) return false;
            const operation_sites_constrained = offer.supported_operation_sites.len != 0;
            const after_sites_constrained = offer.supported_after_sites.len != 0;
            if (shape.kind == .after) {
                if (!after_sites_constrained and operation_sites_constrained) return false;
                if (!constrainedOptionalUsizeAllowsClosure(offer.supported_after_sites, shape.site_index, false)) return false;
                if (shape.value_ref) |ref| if (!listAllowsBoundaryValueRef(offer.accepted_current_value_refs, ref)) return false;
            } else {
                if (!operation_sites_constrained and after_sites_constrained) return false;
                if (!constrainedOptionalUsizeAllowsClosure(offer.supported_operation_sites, shape.site_index, false)) return false;
                if (shape.value_ref) |ref| if (!listAllowsBoundaryValueRef(offer.accepted_payload_refs, ref)) return false;
            }
            return true;
        }

        fn shapeCarriesCapsule(shape: Closure.EffectShape) bool {
            return shape.max_capsule_image_bytes != 0;
        }

        fn treatyUsagePolicyAllowsShapeOffer(offer: ProgramType.Exchange.ProviderOffer, shape: Closure.EffectShape, policy: ProgramType.Exchange.Treaty.Policy) bool {
            const usage = closureShapeUsage(shape.usage_summary);
            const response_use = closureShapeResponseUseForOffer(offer, shape.replay_policy_summary, policy);
            const replay_policy = closureShapeResponseUse(shape.replay_policy_summary, .fresh);
            const branch_policy = closureShapeBranchPolicy(shape.branch_policy_summary);
            if (policy.disallow_fresh_response and response_use == .fresh) return false;
            if (policy.require_replay_only_response and response_use != .replayed and response_use != .deterministic_replay) return false;
            if (policy.require_obligation_opening and !offer.opens_obligation) return false;
            return policy.allowed_usage_modes.allows(usage) and
                offer.supported_usage_modes.allows(usage) and
                policy.allowed_response_uses.allows(response_use) and
                offer.supported_response_uses.allows(response_use) and
                offer.supported_replay_policies.allows(replay_policy) and
                policy.allowed_branch_policies.allows(branch_policy) and
                offer.supported_branch_policies.allows(branch_policy);
        }

        fn providerOfferTagsAllowTreatyPolicy(policy: ProgramType.Exchange.Treaty.Policy, tags: []const []const u8) bool {
            for (policy.required_provider_tags) |tag| if (!stringListContainsClosure(tags, tag)) return false;
            for (policy.disallowed_provider_tags) |tag| if (stringListContainsClosure(tags, tag)) return false;
            return true;
        }

        fn treatyUsagePolicyAllowsMorphismTargetOffer(
            offer: ProgramType.Exchange.ProviderOffer,
            source_shape: Closure.EffectShape,
            target_shape: Closure.EffectShape,
            policy: ProgramType.Exchange.Treaty.Policy,
        ) bool {
            const source_usage = closureShapeUsage(source_shape.usage_summary);
            const target_usage = closureShapeUsage(target_shape.usage_summary);
            const response_use = closureShapeResponseUseForOffer(offer, source_shape.replay_policy_summary, policy);
            const replay_policy = closureShapeResponseUse(source_shape.replay_policy_summary, .fresh);
            const branch_policy = closureShapeBranchPolicy(source_shape.branch_policy_summary);
            if (policy.disallow_fresh_response and response_use == .fresh) return false;
            if (policy.require_replay_only_response and response_use != .replayed and response_use != .deterministic_replay) return false;
            if (policy.require_obligation_opening and !offer.opens_obligation) return false;
            return policy.allowed_usage_modes.allows(source_usage) and
                offer.supported_usage_modes.allows(target_usage) and
                policy.allowed_response_uses.allows(response_use) and
                offer.supported_response_uses.allows(response_use) and
                offer.supported_replay_policies.allows(replay_policy) and
                policy.allowed_branch_policies.allows(branch_policy) and
                offer.supported_branch_policies.allows(branch_policy);
        }

        fn closureTreatyResponseUseAllowed(policy: ProgramType.Exchange.Treaty.Policy, offer: ProgramType.Exchange.ProviderOffer, response_use: ProgramType.Exchange.ResponseUse) bool {
            return policy.allowed_response_uses.allows(response_use) and offer.supported_response_uses.allows(response_use);
        }

        fn closureShapeResponseUseForOffer(
            offer: ProgramType.Exchange.ProviderOffer,
            replay_policy_summary: []const u8,
            policy: ProgramType.Exchange.Treaty.Policy,
        ) ProgramType.Exchange.ResponseUse {
            if (replay_policy_summary.len != 0) return closureShapeResponseUse(replay_policy_summary, .fresh);
            if (policy.require_replay_only_response) {
                if (closureTreatyResponseUseAllowed(policy, offer, .replayed)) return .replayed;
                if (closureTreatyResponseUseAllowed(policy, offer, .deterministic_replay)) return .deterministic_replay;
                return .replayed;
            }
            return .fresh;
        }

        fn closureShapeUsage(value: []const u8) ProgramType.Exchange.Usage {
            if (std.mem.eql(u8, value, "replayable")) return .replayable;
            if (std.mem.eql(u8, value, "affine")) return .affine;
            if (std.mem.eql(u8, value, "linear")) return .linear;
            if (std.mem.eql(u8, value, "ephemeral")) return .ephemeral;
            return .copyable;
        }

        fn closureShapeResponseUse(value: []const u8, default_value: ProgramType.Exchange.ResponseUse) ProgramType.Exchange.ResponseUse {
            if (std.mem.eql(u8, value, "replayed")) return .replayed;
            if (std.mem.eql(u8, value, "deterministic_replay")) return .deterministic_replay;
            if (std.mem.eql(u8, value, "override")) return .override;
            if (std.mem.eql(u8, value, "fresh")) return .fresh;
            return default_value;
        }

        fn closureShapeBranchPolicy(value: []const u8) ProgramType.Exchange.BranchPolicy {
            if (std.mem.eql(u8, value, "replay_only")) return .replay_only;
            if (std.mem.eql(u8, value, "single_live_branch")) return .single_live_branch;
            if (std.mem.eql(u8, value, "split_required")) return .split_required;
            if (std.mem.eql(u8, value, "no_branch")) return .no_branch;
            if (std.mem.eql(u8, value, "host_owned")) return .host_owned;
            return .unrestricted;
        }

        fn capabilityAllowsShapeRequestKind(capability: ProgramType.Exchange.Capability, shape: Closure.EffectShape) bool {
            return if (shape.kind == .after) capability.allowed_request_kinds.after else capability.allowed_request_kinds.operation;
        }

        fn directResponseShapeAllowed(kinds: ProgramType.Exchange.Policy.ResponseKindSet, refs: anytype, shape: Closure.EffectShape) bool {
            if (shape.kind == .after) {
                const expected = shape.expected_after_ref orelse return false;
                return kinds.resume_after and shapeDesiredResponseAllows(shape, expected) and listAllowsBoundaryValueRef(refs, expected);
            }
            if (shape.expected_resume_ref) |ref| {
                if (shapeMayResume(shape) and kinds.@"resume" and shapeDesiredResponseAllows(shape, ref) and listAllowsBoundaryValueRef(refs, ref)) return true;
            }
            if (shape.result_ref) |ref| {
                if (shapeMayReturnNow(shape) and kinds.return_now and shapeDesiredResponseAllows(shape, ref) and listAllowsBoundaryValueRef(refs, ref)) return true;
            }
            return false;
        }

        fn directResponseShapeAllowedByRefs(
            kinds: ProgramType.Exchange.Policy.ResponseKindSet,
            offer_refs: []const lowering_api.ValueRef,
            capability_refs: []const lowering_api.ValueRef,
            shape: Closure.EffectShape,
        ) bool {
            if (shape.kind == .after) {
                const expected = shape.expected_after_ref orelse return false;
                return kinds.resume_after and shapeDesiredResponseAllows(shape, expected) and responseRefAllowedByBoth(offer_refs, capability_refs, expected);
            }
            if (shape.expected_resume_ref) |ref| {
                if (shapeMayResume(shape) and kinds.@"resume" and shapeDesiredResponseAllows(shape, ref) and responseRefAllowedByBoth(offer_refs, capability_refs, ref)) return true;
            }
            if (shape.result_ref) |ref| {
                if (shapeMayReturnNow(shape) and kinds.return_now and shapeDesiredResponseAllows(shape, ref) and responseRefAllowedByBoth(offer_refs, capability_refs, ref)) return true;
            }
            return false;
        }

        fn targetResponseShapeAllowed(
            kinds: ProgramType.Exchange.Policy.ResponseKindSet,
            refs: anytype,
            source_shape: Closure.EffectShape,
            morphism: ProgramType.Exchange.MorphismOffer,
            shape: Closure.EffectShape,
        ) bool {
            const source_filtered_kinds = morphismSourceResponseKindsForTarget(kinds, source_shape, morphism);
            if (shape.desired_response_refs.len != 0) {
                if (!closureResponseKindSetAny(source_filtered_kinds)) return false;
                for (shape.desired_response_refs) |ref| {
                    if (!listAllowsBoundaryValueRef(refs, ref)) return false;
                }
                return true;
            }
            return directResponseShapeAllowed(source_filtered_kinds, refs, shape);
        }

        fn targetResponseShapeAllowedByRefs(
            kinds: ProgramType.Exchange.Policy.ResponseKindSet,
            offer_refs: []const lowering_api.ValueRef,
            capability_refs: []const lowering_api.ValueRef,
            source_shape: Closure.EffectShape,
            morphism: ProgramType.Exchange.MorphismOffer,
            shape: Closure.EffectShape,
        ) bool {
            const source_filtered_kinds = morphismSourceResponseKindsForTarget(kinds, source_shape, morphism);
            if (shape.desired_response_refs.len != 0) {
                if (!closureResponseKindSetAny(source_filtered_kinds)) return false;
                for (shape.desired_response_refs) |ref| {
                    if (!responseRefAllowedByBoth(offer_refs, capability_refs, ref)) return false;
                }
                return true;
            }
            return directResponseShapeAllowedByRefs(source_filtered_kinds, offer_refs, capability_refs, shape);
        }

        fn morphismSourceResponseKindsForTarget(
            kinds: ProgramType.Exchange.Policy.ResponseKindSet,
            shape: Closure.EffectShape,
            morphism: ProgramType.Exchange.MorphismOffer,
        ) ProgramType.Exchange.Policy.ResponseKindSet {
            var result: ProgramType.Exchange.Policy.ResponseKindSet = .{
                .@"resume" = false,
                .return_now = false,
                .resume_after = false,
            };
            if (shape.kind == .after) {
                if (shape.expected_after_ref) |ref| {
                    result.resume_after = kinds.resume_after and shapeDesiredResponseAllows(shape, ref) and morphismSourceAllowsResponseRef(morphism, ref);
                }
                return result;
            }
            if (shape.expected_resume_ref) |ref| {
                result.@"resume" = shapeMayResume(shape) and kinds.@"resume" and shapeDesiredResponseAllows(shape, ref) and morphismSourceAllowsResponseRef(morphism, ref);
            }
            if (shape.result_ref) |ref| {
                result.return_now = shapeMayReturnNow(shape) and kinds.return_now and shapeDesiredResponseAllows(shape, ref) and morphismSourceAllowsResponseRef(morphism, ref);
            }
            return result;
        }

        fn morphismSourceAllowsResponseRef(morphism: ProgramType.Exchange.MorphismOffer, ref: BoundaryValueRef) bool {
            if (morphism.source_response_refs.len == 0) return true;
            return listAllowsBoundaryValueRef(morphism.source_response_refs, ref);
        }

        fn closureResponseKindSetAny(kinds: ProgramType.Exchange.Policy.ResponseKindSet) bool {
            return kinds.@"resume" or kinds.return_now or kinds.resume_after;
        }

        fn responseRefAllowedByBoth(
            offer_refs: []const lowering_api.ValueRef,
            capability_refs: []const lowering_api.ValueRef,
            ref: BoundaryValueRef,
        ) bool {
            return listAllowsBoundaryValueRef(offer_refs, ref) and listAllowsBoundaryValueRef(capability_refs, ref);
        }

        fn shapeDesiredResponseAllows(shape: Closure.EffectShape, ref: BoundaryValueRef) bool {
            if (shape.desired_response_refs.len == 0) return true;
            for (shape.desired_response_refs) |desired| {
                if (desired.eql(ref)) return true;
            }
            return false;
        }

        fn morphismMatchesShape(morphism: ProgramType.Exchange.MorphismOffer, shape: Closure.EffectShape) bool {
            if (morphism.blockers.len != 0) return false;
            if (morphism.source_usage != closureShapeUsage(shape.usage_summary)) return false;
            if (morphism.target_response_refs.len > maxStaticResponseRefs) return false;
            if (morphism.target_response_refs.len != 0 and morphism.source_response_refs.len == 0) return false;
            if (morphism.source_site_fingerprint) |fingerprint| {
                if (shape.site_fingerprint == null or shape.site_fingerprint.? != fingerprint) return false;
            }
            if (morphism.source_protocol_op_fingerprint) |fingerprint| {
                if (shape.protocol_op_fingerprint == null or shape.protocol_op_fingerprint.? != fingerprint) return false;
            }
            if (morphism.source_response_refs.len != 0) {
                var source_response_refs_buffer: [3]BoundaryValueRef = undefined;
                const source_response_refs = shapeResponseRefs(shape, &source_response_refs_buffer);
                for (source_response_refs) |source_ref| {
                    if (listAllowsBoundaryValueRef(morphism.source_response_refs, source_ref)) return true;
                }
                return false;
            }
            return true;
        }

        fn shapeResponseRefs(shape: Closure.EffectShape, buffer: *[3]BoundaryValueRef) []const BoundaryValueRef {
            if (shape.kind == .after) {
                if (shape.expected_after_ref) |ref| {
                    if (!shapeDesiredResponseAllows(shape, ref)) return buffer[0..0];
                    buffer[0] = ref;
                    return buffer[0..1];
                }
                return buffer[0..0];
            }
            var count: usize = 0;
            if (shapeMayResume(shape)) {
                if (shape.expected_resume_ref) |ref| {
                    if (shapeDesiredResponseAllows(shape, ref)) {
                        buffer[count] = ref;
                        count += 1;
                    }
                }
            }
            if (shapeMayReturnNow(shape)) {
                if (shape.result_ref) |ref| {
                    if (shapeDesiredResponseAllows(shape, ref)) {
                        buffer[count] = ref;
                        count += 1;
                    }
                }
            }
            return buffer[0..count];
        }

        fn shapeMayResume(shape: Closure.EffectShape) bool {
            return !std.mem.eql(u8, shape.mode, "abort");
        }

        fn shapeMayReturnNow(shape: Closure.EffectShape) bool {
            return !std.mem.eql(u8, shape.mode, "transform");
        }

        fn inputAllowsIntrinsicOrWorldPort(inputs: PlanInputs, intrinsic_ref: Ref, shape: Closure.EffectShape) bool {
            if (inputs.policy.allowsHostIntrinsicRef(intrinsic_ref)) return true;
            if (!inputs.policy.allow_world_ports) return false;
            return worldPortForShape(inputs.policy, inputs.world_ports, shape, intrinsic_ref) != null;
        }

        fn worldPortForShape(policy: Policy, world_ports: []const Closure.WorldPort, shape: Closure.EffectShape, intrinsic_ref: Ref) ?Closure.WorldPort {
            for (world_ports) |port| {
                if (port.fingerprint != port.computeFingerprint()) continue;
                if (!policy.allowsWorldPortRef(port.evidenceRef())) continue;
                if (!worldPortMatchesShape(port, shape)) continue;
                if (port.exposed_intrinsic_ref) |exposed_ref| {
                    if (!exposed_ref.eql(intrinsic_ref)) continue;
                } else continue;
                return port;
            }
            return null;
        }

        fn shapeOnlyWorldPortForShape(policy: Policy, world_ports: []const Closure.WorldPort, shape: Closure.EffectShape) ?Closure.WorldPort {
            for (world_ports) |port| {
                if (port.fingerprint != port.computeFingerprint()) continue;
                if (!policy.allowsWorldPortRef(port.evidenceRef())) continue;
                if (port.exposed_intrinsic_ref != null) continue;
                if (port.effect_shape_ref == null) continue;
                if (!worldPortMatchesShape(port, shape)) continue;
                return port;
            }
            return null;
        }

        fn worldPortMatchesShape(port: Closure.WorldPort, shape: Closure.EffectShape) bool {
            var exact_shape_ref = false;
            if (port.effect_shape_ref) |shape_ref| {
                if (!shape_ref.eql(shape.evidenceRef())) return false;
                exact_shape_ref = true;
            }
            if (!listAllowsStringClosure(port.supported_protocol_labels, shape.protocol_label)) return false;
            if (!constrainedOptionalUsizeAllowsClosure(port.supported_site_indexes, shape.site_index, exact_shape_ref)) return false;
            if (!constrainedOptionalU64AllowsClosure(port.supported_protocol_op_fingerprints, shape.protocol_op_fingerprint, exact_shape_ref)) return false;
            return true;
        }
    };
}

fn hasErrorClosureBlockers(blockers: []const BoundaryClosureBlocker) bool {
    for (blockers) |blocker| if (blocker.severity == .@"error") return true;
    return false;
}

fn boundaryStaticTreatyRequirementBlocker(tag: BoundaryClosureBlockerTag) bool {
    return switch (tag) {
        .no_static_treaty_plan,
        .no_provider_offer_for_shape,
        .no_capability_for_shape,
        => true,
        .root_program_missing,
        .provider_catalog_empty,
        .effect_shape_unhandled,
        .nested_provider_effect_unhandled,
        .stale_effect_shape,
        .stale_world_port,
        .duplicate_effect_shape,
        .ambiguous_static_treaty_plan,
        .intrinsic_route_rejected,
        .unallowlisted_intrinsic,
        .unknown_semantic_body,
        .dynamic_mapper_rejected,
        .provider_program_contract_missing,
        .provider_program_nested_unknown,
        .world_port_missing,
        .world_port_shape_mismatch,
        .capability_shape_mismatch,
        .treaty_policy_incompatible,
        .defunctionalization_policy_incompatible,
        .runtime_guard_required,
        .unsupported_shape_planning,
        .residualization_shape_unsupported,
        .pipeline_shape_unsupported,
        .depth_limit_exceeded,
        .cycle_detected,
        => false,
    };
}

fn refsEqual(lhs: []const Ref, rhs: []const Ref) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |left, right| {
        if (!left.eql(right)) return false;
    }
    return true;
}

fn refsContain(refs: []const Ref, needle: Ref) bool {
    for (refs) |ref| {
        if (ref.eql(needle)) return true;
    }
    return false;
}

fn blockerRefsMatchBlockers(refs: []const Ref, blockers: []const Blocker) bool {
    if (refs.len != blockers.len) return false;
    for (refs, blockers) |ref, blocker| {
        if (!ref.eql(refForBoundaryClosureBlocker(blocker))) return false;
    }
    return true;
}

fn blockersContain(blockers: []const Blocker, needle: Blocker) bool {
    const needle_fingerprint = needle.fingerprint();
    for (blockers) |blocker| {
        if (blocker.fingerprint() == needle_fingerprint) return true;
    }
    return false;
}

fn policySummaryMatches(summary: ?PolicySummary, policy: BoundaryClosurePolicy) bool {
    const actual = summary orelse return false;
    const expected = policy.policySummary();
    return actual.policy_domain == expected.policy_domain and
        actual.policy_fingerprint == expected.policy_fingerprint and
        std.mem.eql(u8, actual.policy_label, expected.policy_label);
}

fn reportHasAllowedWorldPortForIntrinsic(report: BoundaryClosureReport, graph: BoundaryGraph, policy: BoundaryClosurePolicy, intrinsic_ref: Ref) bool {
    if (!policy.allow_world_ports or report.open_world_port_count == 0) return false;
    for (report.world_port_refs, report.world_port_intrinsic_refs) |world_port_ref, paired_intrinsic_ref| {
        if (paired_intrinsic_ref.domain_id != domains.host_intrinsic.id) continue;
        if (!paired_intrinsic_ref.eql(intrinsic_ref)) continue;
        if (!policy.allowsWorldPortRef(world_port_ref)) continue;
        if (!graphHasEdge(graph, .world_port_exposes, intrinsic_ref, world_port_ref)) continue;
        return true;
    }
    return false;
}

fn graphPlanRefsMatchCertificate(graph: BoundaryGraph, plan_refs: []const Ref) bool {
    var graph_plan_count: usize = 0;
    var graph_shape_count: usize = 0;
    var graph_shape_plan_edge_count: usize = 0;
    for (graph.nodes) |node| {
        switch (node.kind) {
            .treaty_shape_plan => {
                graph_plan_count += 1;
                if (!refsContain(plan_refs, node.ref)) return false;
            },
            .operation_site, .after_site => {
                graph_shape_count += 1;
                if (!graphHasOutgoingTreatyPlanFromShape(graph, node.ref)) return false;
            },
            .root_program,
            .provider_program,
            .protocol_operation,
            .provider_harness,
            .provider_offer,
            .capability_grant,
            .morphism_offer,
            .residualization_adapter,
            .pipeline_adapter,
            .semantic_body,
            .host_intrinsic,
            .world_port,
            .blocker,
            => {},
        }
    }
    if (graph_plan_count != plan_refs.len) return false;
    if (graph_shape_count != plan_refs.len) return false;
    for (graph.edges) |edge| {
        if (edge.kind != .treaty_planned) continue;
        if (!graphHasNode(graph, .operation_site, edge.from) and !graphHasNode(graph, .after_site, edge.from)) return false;
        if (!graphHasNode(graph, .treaty_shape_plan, edge.to)) return false;
        graph_shape_plan_edge_count += 1;
    }
    if (graph_shape_plan_edge_count != plan_refs.len) return false;
    for (plan_refs) |plan_ref| {
        if (plan_ref.domain_id != domains.boundary_static_treaty_plan.id) return false;
        if (!graphHasNode(graph, .treaty_shape_plan, plan_ref)) return false;
        if (!graphHasIncomingTreatyPlanFromShape(graph, plan_ref)) return false;
    }
    return true;
}

fn staticTreatyPlansMatchCertificate(
    graph: BoundaryGraph,
    report: BoundaryClosureReport,
    policy: BoundaryClosurePolicy,
    blocker_refs: []const Ref,
    plan_refs: []const Ref,
    plans: []const BoundaryStaticTreatyPlan,
) bool {
    if (plans.len != plan_refs.len) return false;

    var closed_shape_count: usize = 0;
    var world_port_shape_count: usize = 0;
    var unknown_body_count: usize = 0;
    var boundary_native_route_count: usize = 0;
    var declarative_route_count: usize = 0;
    var residualized_pipeline_route_count: usize = 0;
    var intrinsic_route_count: usize = 0;
    for (plan_refs) |plan_ref| {
        if (plan_ref.domain_id != domains.boundary_static_treaty_plan.id) return false;
        var match_count: usize = 0;
        var matched_plan: ?BoundaryStaticTreatyPlan = null;
        find_matching_plan: for (plans) |plan| {
            if (!plan.evidenceRef().eql(plan_ref)) continue :find_matching_plan;
            match_count += 1;
            matched_plan = plan;
        }
        if (match_count != 1) return false;
        const plan = matched_plan.?;
        if (plan.fingerprint != plan.computeFingerprint()) return false;
        if (!plan.evidenceRef().eql(plan_ref)) return false;
        if (!staticTreatyPlanBlockersMatchReport(graph, report, blocker_refs, plan)) return false;

        const shape_ref = plan.source_shape.evidenceRef();
        if (!graphHasNode(graph, .operation_site, shape_ref) and !graphHasNode(graph, .after_site, shape_ref)) return false;
        if (!graphHasEdge(graph, .treaty_planned, shape_ref, plan_ref)) return false;
        if (plan.selected_provider_offer_ref) |offer_ref| {
            if (!graphHasNode(graph, .provider_offer, offer_ref)) return false;
            if (!graphHasEdge(graph, .handled_by_provider, shape_ref, offer_ref)) return false;
        }
        if (plan.selected_capability_ref) |capability_ref| {
            if (!graphHasNode(graph, .capability_grant, capability_ref)) return false;
            if (!graphHasEdge(graph, .authorized_by_capability, shape_ref, capability_ref)) return false;
        }
        if (plan.selected_morphism_ref) |morphism_ref| {
            if (!graphHasNode(graph, .morphism_offer, morphism_ref)) return false;
            if (!graphHasEdge(graph, .adapted_by_morphism, shape_ref, morphism_ref)) return false;
        }
        if (plan.selected_intrinsic_ref) |intrinsic_ref| {
            if (!graphHasNode(graph, .host_intrinsic, intrinsic_ref)) return false;
            if (!graphHasEdge(graph, .intrinsic_boundary, shape_ref, intrinsic_ref)) return false;
        }
        if (plan.selected_provider_offer_ref != null and plan.selected_semantic_body == .unknown) unknown_body_count += 1;

        const has_world_port = graphShapeHasWorldPort(graph, report, shape_ref);
        if (plan.closedUnderPolicy(policy)) {
            if (has_world_port) {
                world_port_shape_count += 1;
            } else {
                closed_shape_count += 1;
            }
            if (plan.boundary_native) boundary_native_route_count += 1;
            if (plan.host_intrinsic) intrinsic_route_count += selectedPlanHostIntrinsicCount(plan);
            switch (plan.selected_morphism_semantic_body orelse plan.selected_semantic_body) {
                .boundary_program, .kernel_primitive, .host_intrinsic, .unknown => {},
                .declarative => declarative_route_count += 1,
                .residualized_program, .pipeline => residualized_pipeline_route_count += 1,
            }
        } else if (has_world_port) {
            world_port_shape_count += 1;
        }
    }

    return closed_shape_count == report.closed_effect_shape_count and
        world_port_shape_count == report.open_world_port_count and
        unknown_body_count == report.unknown_body_count and
        boundary_native_route_count == report.boundary_native_route_count and
        declarative_route_count == report.declarative_route_count and
        residualized_pipeline_route_count == report.residualized_pipeline_route_count and
        intrinsic_route_count == report.intrinsic_route_count;
}

fn staticTreatyPlanBlockersMatchReport(graph: BoundaryGraph, report: BoundaryClosureReport, blocker_refs: []const Ref, plan: BoundaryStaticTreatyPlan) bool {
    const shape_ref = plan.source_shape.evidenceRef();
    const has_world_port = graphShapeHasWorldPort(graph, report, shape_ref);
    for (plan.blockers) |closure_blocker| {
        if (has_world_port and boundaryStaticTreatyRequirementBlocker(closure_blocker.tag)) continue;
        const blocker = closure_blocker.toEvidenceBlocker();
        const blocker_ref = refForBoundaryClosureBlocker(blocker);
        if (!refsContain(blocker_refs, blocker_ref)) return false;
        if (!blockersContain(report.blockers, blocker)) return false;
        if (!graphHasNode(graph, .blocker, blocker_ref)) return false;
        if (blocker.subject) |subject_ref| {
            if (!graphHasEdge(graph, .blocked_by, subject_ref, blocker_ref)) return false;
        }
    }
    return true;
}

fn selectedPlanHostIntrinsicCount(plan: BoundaryStaticTreatyPlan) usize {
    if (plan.selected_provider_offer_ref == null) return 0;
    var count: usize = 0;
    if (plan.selected_semantic_body == .host_intrinsic) count += 1;
    if (plan.selected_morphism_semantic_body) |body| {
        if (body == .host_intrinsic) count += 1;
    }
    return count;
}

fn graphBlockerRefsMatchCertificate(graph: BoundaryGraph, blocker_refs: []const Ref, blockers: []const Blocker) bool {
    if (blocker_refs.len != blockers.len) return false;
    var graph_blocker_count: usize = 0;
    for (graph.nodes) |node| {
        if (node.kind != .blocker) continue;
        graph_blocker_count += 1;
        if (!refsContain(blocker_refs, node.ref)) return false;
    }
    if (graph_blocker_count != blocker_refs.len) return false;
    for (blocker_refs, blockers) |blocker_ref, blocker| {
        if (blocker_ref.domain_id != domains.boundary_closure_report.id) return false;
        if (!graphHasNode(graph, .blocker, blocker_ref)) return false;
        if (blocker.subject) |subject_ref| {
            if (!graphHasEdge(graph, .blocked_by, subject_ref, blocker_ref)) return false;
        }
    }
    return true;
}

fn graphNodeRefsMatchReport(graph: BoundaryGraph, kind: BoundaryGraph.NodeKind, report_refs: []const Ref) bool {
    var graph_count: usize = 0;
    for (graph.nodes) |node| {
        if (node.kind != kind) continue;
        graph_count += 1;
        if (!refsContain(report_refs, node.ref)) return false;
    }
    if (graph_count != report_refs.len) return false;
    for (report_refs) |report_ref| {
        if (!graphHasNode(graph, kind, report_ref)) return false;
    }
    return true;
}

fn graphRootYieldEdgesMatchReport(graph: BoundaryGraph, report: BoundaryClosureReport) bool {
    for (report.effect_free_root_refs) |effect_free_root_ref| {
        if (!refsContain(report.root_program_refs, effect_free_root_ref)) return false;
    }
    if (report.root_program_refs.len == 0) return true;
    for (report.root_program_refs) |root_ref| {
        if (refsContain(report.effect_free_root_refs, root_ref)) continue;
        if (!graphHasOutgoingEdge(graph, .root_yields, root_ref)) return false;
    }
    for (graph.edges) |edge| {
        if (edge.kind != .root_yields) continue;
        if (!refsContain(report.root_program_refs, edge.from)) return false;
        if (!graphHasNode(graph, .operation_site, edge.to) and !graphHasNode(graph, .after_site, edge.to)) return false;
    }
    for (graph.nodes) |node| {
        if (node.kind != .operation_site and node.kind != .after_site) continue;
        if (graphHasIncomingEdge(graph, .provider_program_yields, node.ref)) continue;
        if (!graphHasIncomingEdge(graph, .root_yields, node.ref)) return false;
    }
    return true;
}

fn graphWorldPortEdgesMatchReport(graph: BoundaryGraph, report: BoundaryClosureReport) bool {
    for (report.world_port_refs, report.world_port_intrinsic_refs) |world_port_ref, paired_ref| {
        if (paired_ref.domain_id == domains.host_intrinsic.id) {
            if (!graphHasEdge(graph, .world_port_exposes, paired_ref, world_port_ref)) return false;
        } else if (paired_ref.domain_id == domains.boundary_effect_shape.id) {
            if (!graphHasEdge(graph, .opens_obligation, paired_ref, world_port_ref)) return false;
        } else {
            return false;
        }
    }
    for (graph.edges) |edge| {
        if (edge.kind == .world_port_exposes and !reportHasWorldPortPair(report, edge.from, edge.to)) return false;
        if (edge.kind == .opens_obligation and !reportHasWorldPortObligation(graph, report, edge.from, edge.to)) return false;
    }
    return true;
}

fn graphWorldPortShapeCount(graph: BoundaryGraph, report: BoundaryClosureReport) usize {
    var count: usize = 0;
    for (graph.nodes) |node| {
        if (node.kind != .operation_site and node.kind != .after_site) continue;
        if (graphShapeHasWorldPort(graph, report, node.ref)) count += 1;
    }
    return count;
}

fn graphShapeHasWorldPort(graph: BoundaryGraph, report: BoundaryClosureReport, shape_ref: Ref) bool {
    for (report.world_port_refs, report.world_port_intrinsic_refs) |world_port_ref, paired_ref| {
        if (paired_ref.domain_id == domains.host_intrinsic.id) {
            if (!graphHasEdge(graph, .intrinsic_boundary, shape_ref, paired_ref)) continue;
            if (!graphHasEdge(graph, .opens_obligation, shape_ref, world_port_ref)) continue;
            if (graphHasEdge(graph, .world_port_exposes, paired_ref, world_port_ref)) return true;
        } else if (paired_ref.domain_id == domains.boundary_effect_shape.id) {
            if (!paired_ref.eql(shape_ref)) continue;
            if (graphHasEdge(graph, .opens_obligation, shape_ref, world_port_ref)) return true;
        }
    }
    return false;
}

fn reportHasWorldPortPair(report: BoundaryClosureReport, intrinsic_ref: Ref, world_port_ref: Ref) bool {
    for (report.world_port_refs, report.world_port_intrinsic_refs) |report_world_port_ref, report_intrinsic_ref| {
        if (report_intrinsic_ref.eql(intrinsic_ref) and report_world_port_ref.eql(world_port_ref)) return true;
    }
    return false;
}

fn reportHasWorldPortObligation(graph: BoundaryGraph, report: BoundaryClosureReport, shape_ref: Ref, world_port_ref: Ref) bool {
    for (report.world_port_refs, report.world_port_intrinsic_refs) |report_world_port_ref, paired_ref| {
        if (!report_world_port_ref.eql(world_port_ref)) continue;
        if (paired_ref.domain_id == domains.boundary_effect_shape.id) {
            if (paired_ref.eql(shape_ref)) return true;
        } else if (paired_ref.domain_id == domains.host_intrinsic.id) {
            if (!graphHasEdge(graph, .intrinsic_boundary, shape_ref, paired_ref)) continue;
            if (graphHasEdge(graph, .world_port_exposes, paired_ref, world_port_ref)) return true;
        }
    }
    return false;
}

fn graphHasNode(graph: BoundaryGraph, kind: BoundaryGraph.NodeKind, ref: Ref) bool {
    for (graph.nodes) |node| {
        if (node.kind == kind and node.ref.eql(ref)) return true;
    }
    return false;
}

fn graphHasIncomingEdge(graph: BoundaryGraph, kind: BoundaryGraph.EdgeKind, to: Ref) bool {
    for (graph.edges) |edge| {
        if (edge.kind == kind and edge.to.eql(to)) return true;
    }
    return false;
}

fn graphHasIncomingTreatyPlanFromShape(graph: BoundaryGraph, to: Ref) bool {
    for (graph.edges) |edge| {
        if (edge.kind != .treaty_planned or !edge.to.eql(to)) continue;
        if (graphHasNode(graph, .operation_site, edge.from) or graphHasNode(graph, .after_site, edge.from)) return true;
    }
    return false;
}

fn graphHasOutgoingEdge(graph: BoundaryGraph, kind: BoundaryGraph.EdgeKind, from: Ref) bool {
    for (graph.edges) |edge| {
        if (edge.kind == kind and edge.from.eql(from)) return true;
    }
    return false;
}

fn graphHasOutgoingTreatyPlanFromShape(graph: BoundaryGraph, from: Ref) bool {
    for (graph.edges) |edge| {
        if (edge.kind != .treaty_planned or !edge.from.eql(from)) continue;
        if (graphHasNode(graph, .treaty_shape_plan, edge.to)) return true;
    }
    return false;
}

fn graphHasEdge(graph: BoundaryGraph, kind: BoundaryGraph.EdgeKind, from: Ref, to: Ref) bool {
    for (graph.edges) |edge| {
        if (edge.kind == kind and edge.from.eql(from) and edge.to.eql(to)) return true;
    }
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

fn constrainedOptionalU64AllowsClosure(list: []const u64, value: ?u64, exact_ref_match: bool) bool {
    if (list.len == 0) return true;
    if (value) |present| return listAllowsU64Closure(list, present);
    return exact_ref_match;
}

fn constrainedOptionalUsizeAllowsClosure(list: []const usize, value: ?usize, exact_ref_match: bool) bool {
    if (list.len == 0) return true;
    if (value) |present| return listAllowsUsizeClosure(list, present);
    return exact_ref_match;
}

fn listAllowsStringClosure(list: []const []const u8, value: []const u8) bool {
    if (list.len == 0) return true;
    for (list) |candidate| if (std.mem.eql(u8, candidate, value)) return true;
    return false;
}

fn stringListContainsClosure(list: []const []const u8, value: []const u8) bool {
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
    return false;
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
