// zlinter-disable declaration_naming field_naming field_ordering function_naming max_positional_args no_inferred_error_unions no_literal_args no_undefined require_doc_comment
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
        boundary_elaboration_policy,
        boundary_elaboration_certificate,
        boundary_elaboration_source_map,
        boundary_elaboration_effect_row,
        boundary_elaboration_trace_map,
        boundary_normal_form,
        boundary_world_surface,
        boundary_world_port_table,
        boundary_world_value_table,
        boundary_world_dispatch_table,
        boundary_world_surface_profile,
        boundary_world_replay_key_recipe,
        boundary_target_policy,
        boundary_target_certificate,
        boundary_target_evidence_map,
        boundary_elaboration_compiler,
        boundary_elaboration_generated_plan,
        boundary_normalization_redex,
        boundary_normalization_rule,
        boundary_normalization_step,
        boundary_normalization_trace,
        boundary_normalization_certificate,
        boundary_route_lowering,
        boundary_plan_builder,
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
        boundary_elaboration,
        boundary_target,
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
    pub const boundary_static_treaty_plan = Domain{ .id = .boundary_static_treaty_plan, .name = "boundary.evidence.closure.static_treaty_plan", .fingerprint_version = 2, .owner = .boundary_closure, .kind = .report, .journal_referenced = true, .certificate_referenced = true, .tests = "static treaty" };
    pub const boundary_closure_policy = Domain{ .id = .boundary_closure_policy, .name = "boundary.evidence.closure.policy", .fingerprint_version = 1, .owner = .boundary_closure, .kind = .fingerprint, .journal_referenced = true, .certificate_referenced = true, .tests = "boundary closure policy" };
    pub const boundary_closure_graph = Domain{ .id = .boundary_closure_graph, .name = "boundary.evidence.closure.graph", .fingerprint_version = 1, .owner = .boundary_closure, .kind = .derived_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "closure graph" };
    pub const boundary_closure_report = Domain{ .id = .boundary_closure_report, .name = "boundary.evidence.closure.report", .fingerprint_version = 1, .owner = .boundary_closure, .kind = .report, .journal_referenced = true, .certificate_referenced = true, .tests = "boundary closure" };
    pub const boundary_closure_certificate = Domain{ .id = .boundary_closure_certificate, .name = "boundary.evidence.closure.certificate", .format_version = 1, .fingerprint_version = 1, .owner = .boundary_closure, .kind = .certificate, .journal_referenced = true, .certificate_referenced = true, .tests = "closure certificate" };
    pub const boundary_world_port = Domain{ .id = .boundary_world_port, .name = "boundary.evidence.closure.world_port", .format_version = 1, .fingerprint_version = 1, .owner = .boundary_closure, .kind = .derived_metadata, .stability = .host_owned_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "world port" };
    pub const boundary_elaboration_policy = Domain{ .id = .boundary_elaboration_policy, .name = "boundary.evidence.elaboration.policy", .fingerprint_version = 1, .owner = .boundary_elaboration, .kind = .fingerprint, .journal_referenced = true, .certificate_referenced = true, .tests = "boundary elaboration policy" };
    pub const boundary_elaboration_certificate = Domain{ .id = .boundary_elaboration_certificate, .name = "boundary.evidence.elaboration.certificate", .format_version = 1, .fingerprint_version = 1, .owner = .boundary_elaboration, .kind = .certificate, .journal_referenced = true, .certificate_referenced = true, .tests = "elaboration certificate" };
    pub const boundary_elaboration_source_map = Domain{ .id = .boundary_elaboration_source_map, .name = "boundary.evidence.elaboration.source_map", .fingerprint_version = 1, .owner = .boundary_elaboration, .kind = .derived_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "source map" };
    pub const boundary_elaboration_effect_row = Domain{ .id = .boundary_elaboration_effect_row, .name = "boundary.evidence.elaboration.effect_row", .fingerprint_version = 1, .owner = .boundary_elaboration, .kind = .derived_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "boundary elaboration" };
    pub const boundary_elaboration_trace_map = Domain{ .id = .boundary_elaboration_trace_map, .name = "boundary.evidence.elaboration.trace_map", .fingerprint_version = 1, .owner = .boundary_elaboration, .kind = .derived_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "runtime agreement" };
    pub const boundary_normal_form = Domain{ .id = .boundary_normal_form, .name = "boundary.evidence.elaboration.normal_form", .fingerprint_version = 1, .owner = .boundary_elaboration, .kind = .derived_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "boundary normal form" };
    pub const boundary_world_surface = Domain{ .id = .boundary_world_surface, .name = "boundary.evidence.target.world_surface", .format_version = 1, .fingerprint_version = 1, .owner = .boundary_target, .kind = .derived_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "world surface" };
    pub const boundary_world_port_table = Domain{ .id = .boundary_world_port_table, .name = "boundary.evidence.target.world_port_table", .fingerprint_version = 1, .owner = .boundary_target, .kind = .derived_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "world port table" };
    pub const boundary_world_value_table = Domain{ .id = .boundary_world_value_table, .name = "boundary.evidence.target.world_value_table", .fingerprint_version = 1, .owner = .boundary_target, .kind = .derived_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "world value table" };
    pub const boundary_world_dispatch_table = Domain{ .id = .boundary_world_dispatch_table, .name = "boundary.evidence.target.world_dispatch_table", .fingerprint_version = 1, .owner = .boundary_target, .kind = .derived_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "world dispatch" };
    pub const boundary_world_surface_profile = Domain{ .id = .boundary_world_surface_profile, .name = "boundary.evidence.target.world_surface_profile", .fingerprint_version = 1, .owner = .boundary_target, .kind = .derived_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "surface profile" };
    pub const boundary_world_replay_key_recipe = Domain{ .id = .boundary_world_replay_key_recipe, .name = "boundary.evidence.target.world_replay_key_recipe", .fingerprint_version = 1, .owner = .boundary_target, .kind = .derived_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "replay key" };
    pub const boundary_target_policy = Domain{ .id = .boundary_target_policy, .name = "boundary.evidence.target.policy", .fingerprint_version = 2, .owner = .boundary_target, .kind = .fingerprint, .journal_referenced = true, .certificate_referenced = true, .tests = "boundary target policy" };
    pub const boundary_target_certificate = Domain{ .id = .boundary_target_certificate, .name = "boundary.evidence.target.certificate", .format_version = 2, .fingerprint_version = 2, .owner = .boundary_target, .kind = .certificate, .journal_referenced = true, .certificate_referenced = true, .tests = "certified boundary target" };
    pub const boundary_target_evidence_map = Domain{ .id = .boundary_target_evidence_map, .name = "boundary.evidence.target.evidence_map", .fingerprint_version = 1, .owner = .boundary_target, .kind = .derived_metadata, .journal_referenced = true, .certificate_referenced = true, .tests = "evidence" };
    pub const boundary_elaboration_compiler = Domain{ .id = .boundary_elaboration_compiler, .name = "boundary.evidence.target.compiler", .fingerprint_version = 1, .owner = .boundary_target, .kind = .derived_metadata, .certificate_referenced = true, .tests = "elaboration compiler" };
    pub const boundary_elaboration_generated_plan = Domain{ .id = .boundary_elaboration_generated_plan, .name = "boundary.evidence.target.generated_plan", .fingerprint_version = 1, .owner = .boundary_target, .kind = .derived_metadata, .certificate_referenced = true, .tests = "automatic elaboration" };
    pub const boundary_normalization_redex = Domain{ .id = .boundary_normalization_redex, .name = "boundary.evidence.target.normalization.redex", .fingerprint_version = 1, .owner = .boundary_target, .kind = .derived_metadata, .certificate_referenced = true, .tests = "redex" };
    pub const boundary_normalization_rule = Domain{ .id = .boundary_normalization_rule, .name = "boundary.evidence.target.normalization.rule", .fingerprint_version = 1, .owner = .boundary_target, .kind = .derived_metadata, .certificate_referenced = true, .tests = "rewrite rule" };
    pub const boundary_normalization_step = Domain{ .id = .boundary_normalization_step, .name = "boundary.evidence.target.normalization.step", .fingerprint_version = 1, .owner = .boundary_target, .kind = .derived_metadata, .certificate_referenced = true, .tests = "rewrite step" };
    pub const boundary_normalization_trace = Domain{ .id = .boundary_normalization_trace, .name = "boundary.evidence.target.normalization.trace", .fingerprint_version = 1, .owner = .boundary_target, .kind = .report, .certificate_referenced = true, .tests = "normalization trace" };
    pub const boundary_normalization_certificate = Domain{ .id = .boundary_normalization_certificate, .name = "boundary.evidence.target.normalization.certificate", .format_version = 1, .fingerprint_version = 1, .owner = .boundary_target, .kind = .certificate, .certificate_referenced = true, .tests = "normalization" };
    pub const boundary_route_lowering = Domain{ .id = .boundary_route_lowering, .name = "boundary.evidence.target.normalization.route_lowering", .fingerprint_version = 1, .owner = .boundary_target, .kind = .derived_metadata, .certificate_referenced = true, .tests = "route lowering" };
    pub const boundary_plan_builder = Domain{ .id = .boundary_plan_builder, .name = "boundary.evidence.target.normalization.plan_builder", .fingerprint_version = 1, .owner = .boundary_target, .kind = .derived_metadata, .certificate_referenced = true, .tests = "plan builder" };
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
    domains.boundary_elaboration_policy,
    domains.boundary_elaboration_certificate,
    domains.boundary_elaboration_source_map,
    domains.boundary_elaboration_effect_row,
    domains.boundary_elaboration_trace_map,
    domains.boundary_normal_form,
    domains.boundary_world_surface,
    domains.boundary_world_port_table,
    domains.boundary_world_value_table,
    domains.boundary_world_dispatch_table,
    domains.boundary_world_surface_profile,
    domains.boundary_world_replay_key_recipe,
    domains.boundary_target_policy,
    domains.boundary_target_certificate,
    domains.boundary_target_evidence_map,
    domains.boundary_elaboration_compiler,
    domains.boundary_elaboration_generated_plan,
    domains.boundary_normalization_redex,
    domains.boundary_normalization_rule,
    domains.boundary_normalization_step,
    domains.boundary_normalization_trace,
    domains.boundary_normalization_certificate,
    domains.boundary_route_lowering,
    domains.boundary_plan_builder,
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

pub fn refForBoundaryElaborationCertificate(certificate: anytype) Ref {
    return refFor(domains.boundary_elaboration_certificate, certificate.certificate_fingerprint, .{
        .format_version = domains.boundary_elaboration_certificate.format_version,
        .label = optionalLabel(certificate, "elaborated_program_label"),
    });
}

pub fn refForBoundaryElaborationSourceMap(source_map: anytype) Ref {
    return refFor(domains.boundary_elaboration_source_map, source_map.fingerprint, .{ .label = optionalLabel(source_map, "label") });
}

pub fn refForBoundaryElaborationEffectRow(effect_row: anytype) Ref {
    return refFor(domains.boundary_elaboration_effect_row, effect_row.fingerprint, .{ .label = optionalLabel(effect_row, "label") });
}

pub fn refForBoundaryElaborationTraceMap(trace_map: anytype) Ref {
    return refFor(domains.boundary_elaboration_trace_map, trace_map.fingerprint, .{ .label = optionalLabel(trace_map, "label") });
}

pub fn refForBoundaryNormalForm(normal_form: anytype) Ref {
    return refFor(domains.boundary_normal_form, normal_form.fingerprint, .{
        .label = optionalLabel(normal_form, "label"),
        .kind_tag = if (comptime @hasField(@TypeOf(normal_form), "kind")) @tagName(normal_form.kind) else null,
    });
}

pub fn refForBoundaryWorldSurface(surface: anytype) Ref {
    return refFor(domains.boundary_world_surface, surface.surface_fingerprint, .{
        .format_version = domains.boundary_world_surface.format_version,
        .label = optionalLabel(surface, "label"),
    });
}

pub fn refForBoundaryWorldPortTable(table: anytype) Ref {
    return refFor(domains.boundary_world_port_table, table.fingerprint, .{ .label = optionalLabel(table, "label") });
}

pub fn refForBoundaryWorldValueTable(table: anytype) Ref {
    return refFor(domains.boundary_world_value_table, table.fingerprint, .{ .label = optionalLabel(table, "label") });
}

pub fn refForBoundaryWorldDispatchTable(table: anytype) Ref {
    return refFor(domains.boundary_world_dispatch_table, table.fingerprint, .{ .label = optionalLabel(table, "label") });
}

pub fn refForBoundaryWorldSurfaceProfile(profile: anytype) Ref {
    return refFor(domains.boundary_world_surface_profile, profile.fingerprint, .{ .label = optionalLabel(profile, "label") });
}

pub fn refForBoundaryWorldReplayKeyRecipe(recipe: anytype) Ref {
    return refFor(domains.boundary_world_replay_key_recipe, recipe.fingerprint, .{ .label = optionalLabel(recipe, "label") });
}

pub fn refForBoundaryTargetCertificate(certificate: anytype) Ref {
    return refFor(domains.boundary_target_certificate, certificate.certificate_fingerprint, .{
        .format_version = domains.boundary_target_certificate.format_version,
        .label = optionalLabel(certificate, "target_label"),
    });
}

pub fn refForBoundaryTargetEvidenceMap(map: anytype) Ref {
    return refFor(domains.boundary_target_evidence_map, map.fingerprint, .{ .label = optionalLabel(map, "label") });
}

pub fn refForBoundaryNormalizationRedex(redex: anytype) Ref {
    return refFor(domains.boundary_normalization_redex, redex.fingerprint, .{
        .label = optionalLabel(redex, "label"),
        .site_index = if (comptime @hasField(@TypeOf(redex), "coordinates")) redex.coordinates.site_index else null,
        .kind_tag = if (comptime @hasField(@TypeOf(redex), "kind")) @tagName(redex.kind) else null,
    });
}

pub fn refForBoundaryNormalizationRule(rule: anytype) Ref {
    return refFor(domains.boundary_normalization_rule, rule.fingerprint, .{
        .label = optionalLabel(rule, "label"),
        .kind_tag = if (comptime @hasField(@TypeOf(rule), "kind")) @tagName(rule.kind) else null,
    });
}

pub fn refForBoundaryNormalizationStep(step: anytype) Ref {
    return refFor(domains.boundary_normalization_step, step.fingerprint, .{
        .label = optionalLabel(step, "summary"),
        .site_index = if (comptime @hasField(@TypeOf(step), "step_index")) step.step_index else null,
    });
}

pub fn refForBoundaryNormalizationTrace(trace: anytype) Ref {
    return refFor(domains.boundary_normalization_trace, trace.trace_fingerprint, .{ .label = optionalLabel(trace, "label") });
}

pub fn refForBoundaryNormalizationCertificate(certificate: anytype) Ref {
    return refFor(domains.boundary_normalization_certificate, certificate.certificate_fingerprint, .{
        .format_version = domains.boundary_normalization_certificate.format_version,
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
    provider_program_mapping,
    effect_shape,
    static_treaty_plan,
    closure_graph,
    closure_policy,
    closure_report,
    closure_certificate,
    world_port,
    elaboration_certificate,
    elaboration_source_map,
    elaboration_effect_row,
    elaboration_trace_map,
    normal_form,
    world_surface,
    world_port_table,
    world_value_table,
    world_dispatch_table,
    surface_profile,
    replay_key_recipe,
    normalization_redex,
    normalization_rule,
    normalization_step,
    normalization_trace,
    normalization_certificate,
    route_lowering,
    plan_builder,
    target_certificate,
    target_evidence_map,
    generated_plan,
    compiler,
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
    boundary_elaboration,
    boundary_target,
    boundary_normalization,
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

fn copyBoundaryValueRefs(dest: []BoundaryValueRef, refs: []const BoundaryValueRef) u8 {
    var count: u8 = 0;
    for (refs) |ref| {
        if (count == dest.len) break;
        dest[count] = ref;
        count += 1;
    }
    return count;
}

fn providerProgramMappingSupportFingerprintForTags(
    provider_ref: Ref,
    offer_ref: Ref,
    program_ref: Ref,
    mapping_fingerprint: u64,
    shape_count: u64,
    shape_fingerprint: u64,
    request_mapping_tag: []const u8,
    result_mapping_tag: []const u8,
) u64 {
    var builder = FingerprintBuilder.init(domains.provider_program_mapping);
    builder.fieldRef("provider", provider_ref);
    builder.fieldRef("offer", offer_ref);
    builder.fieldRef("program", program_ref);
    builder.fieldU64("mapping", mapping_fingerprint);
    builder.fieldU64("effect_shape_count", shape_count);
    builder.fieldU64("effect_shape_fingerprint", shape_fingerprint);
    builder.fieldBytes("request_mapping", request_mapping_tag);
    builder.fieldBytes("result_mapping", result_mapping_tag);
    return builder.finish();
}

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
    require_root_program_refs: bool = false,
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
        builder.fieldBool("require_root_program_refs", self.require_root_program_refs);
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
        if (!self.defunctionalization_policy.allowsIntrinsicRef(intrinsic_ref)) return false;
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
        if (!self.require_all_effect_shapes_closed and
            self.allowed_host_intrinsic_fingerprints.len == 0 and
            self.allowed_host_intrinsic_kinds.len == 0 and
            self.allowed_host_intrinsic_labels.len == 0) return true;
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
    var emitted_rank: usize = 0;
    while (emitted_rank < shapes.len) : (emitted_rank += 1) {
        var selected_index: ?usize = null;
        for (shapes, 0..) |shape, index| {
            const ref = shape.evidenceRef();
            var rank: usize = 0;
            for (shapes, 0..) |other_shape, other_index| {
                const other_ref = other_shape.evidenceRef();
                if (refLessForCanonicalSet(other_ref, ref) or (other_ref.eql(ref) and other_index < index)) rank += 1;
            }
            if (rank == emitted_rank) {
                selected_index = index;
                break;
            }
        }
        builder.fieldRef("shape", shapes[selected_index.?].evidenceRef());
    }
    return builder.finish();
}

fn refLessForCanonicalSet(lhs: Ref, rhs: Ref) bool {
    if (@intFromEnum(lhs.domain_id) != @intFromEnum(rhs.domain_id)) return @intFromEnum(lhs.domain_id) < @intFromEnum(rhs.domain_id);
    if (lhs.fingerprint != rhs.fingerprint) return lhs.fingerprint < rhs.fingerprint;
    if (optionalIntLess(u32, lhs.format_version, rhs.format_version)) |less| return less;
    if (optionalBytesLess(lhs.label, rhs.label)) |less| return less;
    if (optionalIntLess(u64, lhs.branch_id, rhs.branch_id)) |less| return less;
    if (optionalIntLess(usize, lhs.site_index, rhs.site_index)) |less| return less;
    if (optionalBytesLess(lhs.kind_tag, rhs.kind_tag)) |less| return less;
    return false;
}

fn optionalIntLess(comptime T: type, lhs: ?T, rhs: ?T) ?bool {
    if (lhs) |left| {
        const right = rhs orelse return false;
        if (left != right) return left < right;
        return null;
    }
    if (rhs != null) return true;
    return null;
}

fn optionalBytesLess(lhs: ?[]const u8, rhs: ?[]const u8) ?bool {
    if (lhs) |left| {
        const right = rhs orelse return false;
        if (!std.mem.eql(u8, left, right)) return std.mem.lessThan(u8, left, right);
        return null;
    }
    if (rhs != null) return true;
    return null;
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
    const max_morphism_target_response_refs = 3;

    fingerprint: u64,
    label: []const u8,
    source_shape: BoundaryEffectShape,
    direct_candidate_count: usize = 0,
    morphism_candidate_count: usize = 0,
    selected_provider_offer_ref: ?Ref = null,
    selected_provider_ref: ?Ref = null,
    selected_capability_ref: ?Ref = null,
    selected_morphism_ref: ?Ref = null,
    selected_morphism_target_shape_ref: ?Ref = null,
    selected_morphism_target_shape: ?BoundaryEffectShape = null,
    selected_morphism_target_response_ref_count: u8 = 0,
    selected_morphism_target_response_refs: [max_morphism_target_response_refs]BoundaryValueRef = [_]BoundaryValueRef{.{ .codec = "" }} ** max_morphism_target_response_refs,
    selected_morphism_semantic_body: ?SemanticBody = null,
    selected_morphism_intrinsic_ref: ?Ref = null,
    selected_semantic_body: SemanticBody = .unknown,
    selected_intrinsic_ref: ?Ref = null,
    selected_provider_program_ref: ?Ref = null,
    selected_provider_program_mapping_fingerprint: ?u64 = null,
    selected_provider_program_request_mapping_tag: ?[]const u8 = null,
    selected_provider_program_result_mapping_tag: ?[]const u8 = null,
    selected_provider_program_mapping_support_fingerprint: ?u64 = null,
    selected_provider_program_effect_shape_count: ?u64 = null,
    selected_provider_program_effect_shape_fingerprint: ?u64 = null,
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
        selected_morphism_target_shape_ref: ?Ref = null,
        selected_morphism_target_shape: ?BoundaryEffectShape = null,
        selected_morphism_target_response_ref_count: u8 = 0,
        selected_morphism_target_response_refs: [max_morphism_target_response_refs]BoundaryValueRef = [_]BoundaryValueRef{.{ .codec = "" }} ** max_morphism_target_response_refs,
        selected_morphism_semantic_body: ?SemanticBody = null,
        selected_morphism_intrinsic_ref: ?Ref = null,
        selected_semantic_body: SemanticBody = .unknown,
        selected_intrinsic_ref: ?Ref = null,
        selected_provider_program_ref: ?Ref = null,
        selected_provider_program_mapping_fingerprint: ?u64 = null,
        selected_provider_program_request_mapping_tag: ?[]const u8 = null,
        selected_provider_program_result_mapping_tag: ?[]const u8 = null,
        selected_provider_program_mapping_support_fingerprint: ?u64 = null,
        selected_provider_program_effect_shape_count: ?u64 = null,
        selected_provider_program_effect_shape_fingerprint: ?u64 = null,
        boundary_native: bool = false,
        host_intrinsic: bool = false,
        runtime_request_value_validation_required: bool = true,
        byte_size_runtime_guard_required: bool = true,
        blockers: []const BoundaryClosureBlocker = &.{},
        dependencies: []const Dependency = &.{},
    };

    pub fn init(options: Options) @This() {
        var target_response_refs = options.selected_morphism_target_response_refs;
        var target_response_ref_count = options.selected_morphism_target_response_ref_count;
        if (options.selected_morphism_target_shape) |shape| {
            if (shape.desired_response_refs.len != 0) {
                target_response_ref_count = copyBoundaryValueRefs(&target_response_refs, shape.desired_response_refs);
            }
        }
        const provider_program_mapping_support_fingerprint = options.selected_provider_program_mapping_support_fingerprint orelse
            selectedProviderProgramMappingSupportFingerprintFromOptions(options);
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
            .selected_morphism_target_shape_ref = options.selected_morphism_target_shape_ref,
            .selected_morphism_target_shape = options.selected_morphism_target_shape,
            .selected_morphism_target_response_ref_count = target_response_ref_count,
            .selected_morphism_target_response_refs = target_response_refs,
            .selected_morphism_semantic_body = options.selected_morphism_semantic_body,
            .selected_morphism_intrinsic_ref = options.selected_morphism_intrinsic_ref,
            .selected_semantic_body = options.selected_semantic_body,
            .selected_intrinsic_ref = options.selected_intrinsic_ref,
            .selected_provider_program_ref = options.selected_provider_program_ref,
            .selected_provider_program_mapping_fingerprint = options.selected_provider_program_mapping_fingerprint,
            .selected_provider_program_request_mapping_tag = options.selected_provider_program_request_mapping_tag,
            .selected_provider_program_result_mapping_tag = options.selected_provider_program_result_mapping_tag,
            .selected_provider_program_mapping_support_fingerprint = provider_program_mapping_support_fingerprint,
            .selected_provider_program_effect_shape_count = options.selected_provider_program_effect_shape_count,
            .selected_provider_program_effect_shape_fingerprint = options.selected_provider_program_effect_shape_fingerprint,
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

    pub fn morphismTargetShapeWitness(self: *const @This()) ?BoundaryEffectShape {
        var shape = self.selected_morphism_target_shape orelse return null;
        if (self.selected_morphism_target_response_ref_count > max_morphism_target_response_refs) return null;
        shape.desired_response_refs = self.selected_morphism_target_response_refs[0..self.selected_morphism_target_response_ref_count];
        shape.fingerprint = shape.computeFingerprint();
        return shape;
    }

    fn selectedProviderProgramMappingSupportFingerprintFromOptions(options: Options) ?u64 {
        const provider_ref = options.selected_provider_ref orelse return null;
        const offer_ref = options.selected_provider_offer_ref orelse return null;
        const program_ref = options.selected_provider_program_ref orelse return null;
        const mapping_fingerprint = options.selected_provider_program_mapping_fingerprint orelse return null;
        const request_mapping_tag = options.selected_provider_program_request_mapping_tag orelse return null;
        const result_mapping_tag = options.selected_provider_program_result_mapping_tag orelse return null;
        const shape_count = options.selected_provider_program_effect_shape_count orelse return null;
        const shape_fingerprint = options.selected_provider_program_effect_shape_fingerprint orelse return null;
        return providerProgramMappingSupportFingerprintForTags(provider_ref, offer_ref, program_ref, mapping_fingerprint, shape_count, shape_fingerprint, request_mapping_tag, result_mapping_tag);
    }

    pub fn selectedProviderProgramMappingSupportFingerprint(self: @This()) ?u64 {
        const provider_ref = self.selected_provider_ref orelse return null;
        const offer_ref = self.selected_provider_offer_ref orelse return null;
        const program_ref = self.selected_provider_program_ref orelse return null;
        const mapping_fingerprint = self.selected_provider_program_mapping_fingerprint orelse return null;
        const request_mapping_tag = self.selected_provider_program_request_mapping_tag orelse return null;
        const result_mapping_tag = self.selected_provider_program_result_mapping_tag orelse return null;
        const shape_count = self.selected_provider_program_effect_shape_count orelse return null;
        const shape_fingerprint = self.selected_provider_program_effect_shape_fingerprint orelse return null;
        return providerProgramMappingSupportFingerprintForTags(provider_ref, offer_ref, program_ref, mapping_fingerprint, shape_count, shape_fingerprint, request_mapping_tag, result_mapping_tag);
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
        builder.fieldOptionalRef("morphism_target_shape", self.selected_morphism_target_shape_ref);
        if (self.morphismTargetShapeWitness()) |shape| builder.fieldRef("morphism_target_shape_witness", shape.evidenceRef());
        if (self.selected_morphism_semantic_body) |body| builder.fieldBytes("morphism_semantic_body", @tagName(body));
        builder.fieldOptionalRef("morphism_intrinsic", self.selected_morphism_intrinsic_ref);
        builder.fieldBytes("semantic_body", @tagName(self.selected_semantic_body));
        builder.fieldOptionalRef("intrinsic", self.selected_intrinsic_ref);
        builder.fieldOptionalRef("provider_program", self.selected_provider_program_ref);
        builder.fieldOptionalU64("provider_program_mapping", self.selected_provider_program_mapping_fingerprint);
        if (self.selected_provider_program_request_mapping_tag) |tag| builder.fieldBytes("provider_program_request_mapping", tag);
        if (self.selected_provider_program_result_mapping_tag) |tag| builder.fieldBytes("provider_program_result_mapping", tag);
        builder.fieldOptionalU64("provider_program_mapping_support", self.selected_provider_program_mapping_support_fingerprint);
        builder.fieldOptionalU64("provider_program_effect_shape_count", self.selected_provider_program_effect_shape_count);
        builder.fieldOptionalU64("provider_program_effect_shape_fingerprint", self.selected_provider_program_effect_shape_fingerprint);
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
        return self.selected_provider_offer_ref != null and
            self.selected_provider_ref != null and
            self.selected_capability_ref != null and
            !hasErrorClosureBlockers(self.blockers);
    }

    pub fn closedUnderPolicy(self: @This(), policy: BoundaryClosurePolicy) bool {
        if (!self.closed()) return false;
        if (self.selected_morphism_ref != null and self.selected_morphism_semantic_body == null) return false;
        if (self.selected_morphism_ref != null and policy.max_morphism_hops == 0) return false;
        if ((policy.reject_runtime_guards or !policy.allow_runtime_guards) and
            (self.runtime_request_value_validation_required or self.byte_size_runtime_guard_required)) return false;
        if (policy.reject_request_value_dependence and self.runtime_request_value_validation_required) return false;
        if (policy.reject_unknown_semantic_bodies or policy.defunctionalization_policy.reject_unknown) {
            if (self.selected_semantic_body == .unknown) return false;
            if (self.selected_morphism_semantic_body) |body| {
                if (body == .unknown) return false;
            }
        }
        if (!policy.allow_kernel_primitives or !policy.defunctionalization_policy.allow_kernel_primitives) {
            if (self.selected_semantic_body == .kernel_primitive) return false;
            if (self.selected_morphism_semantic_body) |body| {
                if (body == .kernel_primitive) return false;
            }
        }
        if (policy.defunctionalization_policy.maximum_intrinsic_count) |maximum| {
            if (selectedPlanHostIntrinsicCount(self) > maximum) return false;
        }
        if (self.selected_semantic_body == .host_intrinsic) {
            const intrinsic_ref = self.selected_intrinsic_ref orelse return false;
            if (!policy.allowsHostIntrinsicRef(intrinsic_ref)) return false;
        }
        if (self.selected_morphism_semantic_body) |body| {
            if (body == .host_intrinsic) {
                const intrinsic_ref = self.selected_morphism_intrinsic_ref orelse return false;
                if (!policy.allowsHostIntrinsicRef(intrinsic_ref)) return false;
            }
        }
        if (policy.require_program_backed_providers or policy.defunctionalization_policy.require_program_backed_providers) {
            if (self.selected_semantic_body != .boundary_program) return false;
        }
        if (self.selected_semantic_body == .boundary_program) {
            if (self.selected_provider_program_ref == null or
                self.selected_provider_program_mapping_fingerprint == null or
                self.selected_provider_program_request_mapping_tag == null or
                self.selected_provider_program_result_mapping_tag == null or
                self.selected_provider_program_mapping_support_fingerprint == null or
                self.selected_provider_program_effect_shape_count == null or
                self.selected_provider_program_effect_shape_fingerprint == null)
            {
                return false;
            }
        }
        if (policy.require_declarative_morphisms or policy.defunctionalization_policy.require_declarative_morphisms) {
            const body = self.selected_morphism_semantic_body orelse return true;
            if (body != .declarative and body != .residualized_program and body != .pipeline) return false;
        }
        return true;
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
        provider_manifest,
        provider_offer,
        provider_program_mapping,
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
        provider_program_mapped_by,
        provider_advertises_offer,
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
    derive_blocker_refs: bool = false,
    effect_shape_count: usize = 0,
    closed_effect_shape_count: usize = 0,
    world_port_count: usize = 0,
    blocker_count: usize = 0,
    summary: []const u8 = "boundary closure certificate",

    pub fn init(report: BoundaryClosureReport, graph: BoundaryGraph, policy: BoundaryClosurePolicy, plan_refs: []const Ref) @This() {
        var certificate = initWithBlockerRefs(report, graph, policy, plan_refs, &.{});
        certificate.derive_blocker_refs = report.blockers.len != 0;
        certificate.certificate_fingerprint = certificate.computeFingerprint();
        return certificate;
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
        if (self.derive_blocker_refs) builder.fieldBool("derive_blocker_refs", true);
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
        if (self.certificate_format_version != domains.boundary_closure_certificate.format_version.?) return error.BoundaryClosureCertificateMismatch;
        if (self.certificate_fingerprint != self.computeFingerprint()) return error.BoundaryClosureCertificateMismatch;
        if (!self.policy_ref.eql(policy.evidenceRef()) or self.policy_fingerprint != policy.fingerprint()) return error.BoundaryClosurePolicyMismatch;
        if (!policySummaryMatches(report.policy_summary, policy)) return error.BoundaryClosurePolicyMismatch;
        if (!refsHaveDomain(report.root_program_refs, domains.program_plan.id)) return error.BoundaryClosureCertificateMismatch;
        if (!refsHaveDomain(report.effect_free_root_refs, domains.program_plan.id)) return error.BoundaryClosureCertificateMismatch;
        if (!refsHaveDomain(report.provider_harness_refs, domains.provider_harness.id)) return error.BoundaryClosureCertificateMismatch;
        if (!refsHaveDomain(report.provider_program_refs, domains.program_plan.id)) return error.BoundaryClosureCertificateMismatch;
        if (!refsEqual(self.root_refs, report.root_program_refs)) return error.BoundaryClosureCertificateMismatch;
        if (!refsEqual(self.effect_free_root_refs, report.effect_free_root_refs)) return error.BoundaryClosureCertificateMismatch;
        if (!graphNodeRefsMatchReport(graph, .root_program, report.root_program_refs)) return error.BoundaryClosureCertificateMismatch;
        if (policy.require_root_program_refs and report.effect_shape_count != 0 and report.root_program_refs.len == 0) return error.BoundaryClosureCertificateMismatch;
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
        if (self.derive_blocker_refs) {
            if (self.blocker_refs.len != 0) return error.BoundaryClosureCertificateMismatch;
            if (!derivedBlockerRefsMatchGraph(graph, report.blockers)) return error.BoundaryClosureCertificateMismatch;
        } else {
            if (!blockerRefsMatchBlockers(self.blocker_refs, report.blockers)) return error.BoundaryClosureCertificateMismatch;
            if (!graphBlockerRefsMatchCertificate(graph, self.blocker_refs, report.blockers)) return error.BoundaryClosureCertificateMismatch;
        }
        if (report.world_port_refs.len != report.world_port_intrinsic_refs.len) return error.BoundaryClosureCertificateMismatch;
        if (report.open_world_port_count != graphWorldPortShapeCount(graph, report)) return error.BoundaryClosureCertificateMismatch;
        if ((report.open_world_port_count == 0) != (report.world_port_refs.len == 0)) return error.BoundaryClosureCertificateMismatch;
        if (report.host_intrinsic_count != report.host_intrinsic_refs.len) return error.BoundaryClosureCertificateMismatch;
        if (policy.defunctionalization_policy.maximum_intrinsic_count) |maximum| {
            if (report.host_intrinsic_count > maximum) return error.BoundaryClosureIntrinsicRejected;
        }
        if (report.unknown_body_count != report.unknown_refs.len) return error.BoundaryClosureCertificateMismatch;
        if (!graphNodeRefsMatchReport(graph, .host_intrinsic, report.host_intrinsic_refs)) return error.BoundaryClosureCertificateMismatch;
        if (!graphHostIntrinsicRefsMatchReport(graph, report, self.selected_static_treaty_plan_refs)) return error.BoundaryClosureCertificateMismatch;
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
        if (graph.nodes.len > policy.max_nodes and !reportHasClosureBlockerTag(report, .depth_limit_exceeded)) return error.BoundaryClosureCertificateMismatch;
        if (!staticTreatyPlansRespectDepthPolicy(graph, report, policy, static_treaty_plans)) return error.BoundaryClosureCertificateMismatch;
        if (!staticTreatyPlansMatchCertificate(
            graph,
            report,
            policy,
            self.blocker_refs,
            self.derive_blocker_refs,
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
        if (!graphIntrinsicBoundariesAllowedByPolicy(report, graph, policy, false)) return error.BoundaryClosureIntrinsicRejected;
        if (!policy.allow_world_ports and report.open_world_port_count != 0) return error.BoundaryClosureWorldPortsRejected;
        if (policy.reject_unknown_semantic_bodies and report.unknown_body_count != 0) return error.BoundaryClosureUnknownBodies;
        if (policy.reject_host_intrinsics) {
            if (!graphIntrinsicBoundariesAllowedByPolicy(report, graph, policy, true)) return error.BoundaryClosureIntrinsicRejected;
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

pub const BoundaryNormalFormKind = enum {
    strict_closed,
    world_ports_only,
    partial_with_blockers,
};

pub const BoundaryElaborationBlockerTag = enum {
    unchecked_closure_certificate,
    closure_ref_mismatch,
    closure_certificate_mismatch,
    closure_graph_ref_mismatch,
    root_ref_mismatch,
    provider_ref_mismatch,
    provider_program_ref_mismatch,
    static_treaty_plan_ref_mismatch,
    world_port_ref_mismatch,
    policy_ref_mismatch,
    closure_report_not_closed,
    world_ports_rejected,
    intrinsic_world_port_rejected,
    internal_route_not_program_backed,
    unsupported_request_mapping,
    unsupported_result_mapping,
    provider_arg_schema_mismatch,
    provider_result_schema_mismatch,
    provider_mapping_not_elaborable,
    unsupported_provider_mapping,
    provider_program_schema_mismatch,
    unsupported_world_port_lowering,
    morphism_not_elaborable,
    dynamic_mapper_not_elaborable,
    pipeline_adapter_missing,
    residualization_unsupported_for_shape,
    morphism_trace_map_missing,
    morphism_ref_mismatch,
    unsupported_morphism_lowering,
    unsupported_pipeline_lowering,
    schema_ref_mismatch,
    residual_plan_invalid,
    source_map_mismatch,
    evidence_map_mismatch,
    normal_form_violation,
};

pub const BoundaryElaborationPolicy = struct {
    label: []const u8 = "strict_elaboration",
    closure_policy: BoundaryClosurePolicy = BoundaryClosurePolicy.strictStatic(),
    allow_world_ports: bool = false,
    require_certificate_checked: bool = true,
    allow_intrinsic_world_ports: bool = false,
    require_program_backed_providers_for_internal_routes: bool = true,
    allow_declarative_morphisms: bool = true,
    allow_residualized_morphisms: bool = true,
    allow_pipeline_adapters: bool = true,
    reject_dynamic_intrinsic_mappers: bool = true,
    reject_unknown_semantic_bodies: bool = true,
    max_nested_provider_depth: usize = 32,
    fail_on_unsupported_shape: bool = true,
    require_checked_closure_certificate: bool = true,
    allow_partial_with_blockers: bool = false,
    allow_provider_program_linking: bool = true,
    emit_trace_map: bool = true,
    max_blockers: usize = 0,

    pub fn strictStatic() @This() {
        return strictClosed();
    }

    pub fn strict() @This() {
        return strictClosed();
    }

    pub fn strictClosed() @This() {
        var policy = @This(){};
        policy.closure_policy.allow_world_ports = false;
        policy.closure_policy.reject_host_intrinsics = true;
        policy.allow_world_ports = false;
        policy.allow_intrinsic_world_ports = false;
        return policy;
    }

    pub fn worldBoundary() @This() {
        var policy = @This(){
            .label = "world_boundary_elaboration",
            .closure_policy = BoundaryClosurePolicy.worldBoundary(),
            .allow_world_ports = true,
            .allow_intrinsic_world_ports = true,
        };
        policy.closure_policy.reject_host_intrinsics = false;
        return policy;
    }

    pub fn auditOnly() @This() {
        return .{
            .label = "audit_only_elaboration",
            .closure_policy = BoundaryClosurePolicy.auditOnly(),
            .require_certificate_checked = false,
            .require_checked_closure_certificate = false,
            .allow_world_ports = true,
            .allow_intrinsic_world_ports = true,
            .allow_partial_with_blockers = true,
            .fail_on_unsupported_shape = false,
            .reject_dynamic_intrinsic_mappers = false,
            .reject_unknown_semantic_bodies = false,
            .max_blockers = std.math.maxInt(usize),
        };
    }

    pub fn fingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_elaboration_policy);
        builder.fieldBytes("label", self.label);
        builder.fieldU64("closure_policy", self.closure_policy.fingerprint());
        builder.fieldBool("allow_world_ports", self.allow_world_ports);
        builder.fieldBool("require_certificate_checked", self.require_certificate_checked);
        builder.fieldBool("allow_intrinsic_world_ports", self.allow_intrinsic_world_ports);
        builder.fieldBool("require_program_backed_providers_for_internal_routes", self.require_program_backed_providers_for_internal_routes);
        builder.fieldBool("allow_declarative_morphisms", self.allow_declarative_morphisms);
        builder.fieldBool("allow_residualized_morphisms", self.allow_residualized_morphisms);
        builder.fieldBool("allow_pipeline_adapters", self.allow_pipeline_adapters);
        builder.fieldBool("reject_dynamic_intrinsic_mappers", self.reject_dynamic_intrinsic_mappers);
        builder.fieldBool("reject_unknown_semantic_bodies", self.reject_unknown_semantic_bodies);
        builder.fieldUsize("max_nested_provider_depth", self.max_nested_provider_depth);
        builder.fieldBool("fail_on_unsupported_shape", self.fail_on_unsupported_shape);
        builder.fieldBool("require_checked_closure_certificate", self.require_checked_closure_certificate);
        builder.fieldBool("allow_partial_with_blockers", self.allow_partial_with_blockers);
        builder.fieldBool("allow_provider_program_linking", self.allow_provider_program_linking);
        builder.fieldBool("emit_trace_map", self.emit_trace_map);
        builder.fieldUsize("max_blockers", self.max_blockers);
        return builder.finish();
    }

    pub fn policySummary(self: @This()) PolicySummary {
        return .{
            .policy_domain = domains.boundary_elaboration_policy.id,
            .policy_fingerprint = self.fingerprint(),
            .policy_label = self.label,
        };
    }
};

pub const BoundaryElaborationBlocker = struct {
    tag: BoundaryElaborationBlockerTag,
    subject: ?Ref = null,
    primary: ?Ref = null,
    related_refs: []const Ref = &.{},
    site_index: ?usize = null,
    summary: []const u8,
    severity: Severity = .@"error",

    pub fn toEvidenceBlocker(self: @This()) Blocker {
        return boundaryElaborationBlocker(.{
            .tag = self.tag,
            .subject = self.subject,
            .primary = self.primary,
            .related_refs = self.related_refs,
            .site_index = self.site_index,
            .summary = self.summary,
            .severity = self.severity,
        });
    }
};

pub const BoundaryElaborationBlockerOptions = struct {
    tag: BoundaryElaborationBlockerTag,
    subject: ?Ref = null,
    primary: ?Ref = null,
    related_refs: []const Ref = &.{},
    site_index: ?usize = null,
    summary: []const u8,
    severity: Severity = .@"error",
};

pub fn boundaryElaborationBlocker(options: BoundaryElaborationBlockerOptions) Blocker {
    return .{
        .domain = domains.boundary_elaboration_certificate.id,
        .tag = @tagName(options.tag),
        .severity = options.severity,
        .subject = options.subject,
        .primary = options.primary,
        .related_refs = options.related_refs,
        .site_index = options.site_index,
        .short_code = @tagName(options.tag),
        .summary = options.summary,
        .source = .boundary_elaboration,
    };
}

pub fn refForBoundaryElaborationBlocker(blocker: Blocker) Ref {
    return refFor(domains.boundary_elaboration_certificate, blocker.fingerprint(), .{ .kind_tag = blocker.short_code });
}

pub const BoundaryElaborationSourceMap = struct {
    label: []const u8,
    fingerprint: u64,
    entries: []const Entry = &.{},
    dependencies: []const Dependency = &.{},

    pub const Disposition = enum {
        preserved,
        provider_program_linked,
        world_port_lowered,
        residualized,
        pipeline_adapter,
        blocked,
    };

    pub const Entry = struct {
        source_ref: Ref,
        residual_ref: ?Ref = null,
        source_site_index: ?usize = null,
        residual_site_index: ?usize = null,
        provider_program_ref: ?Ref = null,
        static_treaty_plan_ref: ?Ref = null,
        world_port_ref: ?Ref = null,
        blocker_ref: ?Ref = null,
        disposition: Disposition,
        label: []const u8 = "",
    };

    pub fn init(label: []const u8, entries: []const Entry, dependencies: []const Dependency) @This() {
        var map = @This(){ .label = label, .fingerprint = 0, .entries = entries, .dependencies = dependencies };
        map.fingerprint = map.computeFingerprint();
        return map;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_elaboration_source_map);
        builder.fieldBytes("label", self.label);
        for (self.entries) |entry| {
            builder.fieldRef("entry.source", entry.source_ref);
            builder.fieldOptionalRef("entry.residual", entry.residual_ref);
            builder.fieldOptionalU64("entry.source_site", if (entry.source_site_index) |site| @as(u64, @intCast(site)) else null);
            builder.fieldOptionalU64("entry.residual_site", if (entry.residual_site_index) |site| @as(u64, @intCast(site)) else null);
            builder.fieldOptionalRef("entry.provider_program", entry.provider_program_ref);
            builder.fieldOptionalRef("entry.static_treaty_plan", entry.static_treaty_plan_ref);
            builder.fieldOptionalRef("entry.world_port", entry.world_port_ref);
            builder.fieldOptionalRef("entry.blocker", entry.blocker_ref);
            builder.fieldBytes("entry.disposition", @tagName(entry.disposition));
            builder.fieldBytes("entry.label", entry.label);
        }
        writeCanonicalDependencies(&builder, self.dependencies);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refForBoundaryElaborationSourceMap(self);
    }

    pub fn sourceForResidualSite(self: @This(), residual_site_index: usize) ?Ref {
        for (self.entries) |entry| {
            if (entry.residual_site_index == residual_site_index) return entry.source_ref;
        }
        return null;
    }

    pub fn residualForSourceShape(self: @This(), source_ref: Ref) ?Ref {
        for (self.entries) |entry| {
            if (entry.source_ref.eql(source_ref)) return entry.residual_ref;
        }
        return null;
    }

    pub fn worldPortForResidualSite(self: @This(), residual_site_index: usize) ?Ref {
        for (self.entries) |entry| {
            if (entry.residual_site_index == residual_site_index) return entry.world_port_ref;
        }
        return null;
    }

    pub fn staticPlanForElaboratedRoute(self: @This(), source_ref: Ref) ?Ref {
        for (self.entries) |entry| {
            if (entry.source_ref.eql(source_ref)) return entry.static_treaty_plan_ref;
        }
        return null;
    }
};

pub const BoundaryElaborationEffectRow = struct {
    label: []const u8,
    fingerprint: u64,
    source_program_ref: Ref,
    residual_program_ref: Ref,
    normal_form: BoundaryNormalFormKind,
    source_effect_shapes: usize = 0,
    closed_effect_shapes: usize = 0,
    eliminated_source_shapes: usize = 0,
    elaborated_provider_routes: usize = 0,
    elaborated_morphism_routes: usize = 0,
    linked_provider_programs: usize = 0,
    nested_provider_shapes_linked: usize = 0,
    nested_provider_depth: usize = 0,
    residual_world_ports: usize = 0,
    unsupported_shapes: usize = 0,
    strict_closed: bool = false,
    world_ports_only: bool = false,
    world_ports: usize = 0,
    provider_program_links: usize = 0,
    residualized_routes: usize = 0,
    pipeline_routes: usize = 0,
    blockers: usize = 0,

    pub fn init(options: struct {
        label: []const u8,
        source_program_ref: Ref,
        residual_program_ref: Ref,
        normal_form: BoundaryNormalFormKind,
        source_effect_shapes: usize = 0,
        closed_effect_shapes: usize = 0,
        eliminated_source_shapes: usize = 0,
        elaborated_provider_routes: usize = 0,
        elaborated_morphism_routes: usize = 0,
        linked_provider_programs: usize = 0,
        nested_provider_shapes_linked: usize = 0,
        nested_provider_depth: usize = 0,
        residual_world_ports: usize = 0,
        unsupported_shapes: usize = 0,
        world_ports: usize = 0,
        provider_program_links: usize = 0,
        residualized_routes: usize = 0,
        pipeline_routes: usize = 0,
        blockers: usize = 0,
    }) @This() {
        var row = @This(){
            .label = options.label,
            .fingerprint = 0,
            .source_program_ref = options.source_program_ref,
            .residual_program_ref = options.residual_program_ref,
            .normal_form = options.normal_form,
            .source_effect_shapes = options.source_effect_shapes,
            .closed_effect_shapes = options.closed_effect_shapes,
            .eliminated_source_shapes = if (options.eliminated_source_shapes != 0) options.eliminated_source_shapes else options.closed_effect_shapes,
            .elaborated_provider_routes = if (options.elaborated_provider_routes != 0) options.elaborated_provider_routes else options.provider_program_links,
            .elaborated_morphism_routes = if (options.elaborated_morphism_routes != 0) options.elaborated_morphism_routes else options.residualized_routes,
            .linked_provider_programs = if (options.linked_provider_programs != 0) options.linked_provider_programs else options.provider_program_links,
            .nested_provider_shapes_linked = options.nested_provider_shapes_linked,
            .nested_provider_depth = options.nested_provider_depth,
            .residual_world_ports = if (options.residual_world_ports != 0) options.residual_world_ports else options.world_ports,
            .unsupported_shapes = options.unsupported_shapes,
            .strict_closed = options.normal_form == .strict_closed,
            .world_ports_only = options.normal_form == .world_ports_only,
            .world_ports = options.world_ports,
            .provider_program_links = options.provider_program_links,
            .residualized_routes = options.residualized_routes,
            .pipeline_routes = options.pipeline_routes,
            .blockers = options.blockers,
        };
        row.fingerprint = row.computeFingerprint();
        return row;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_elaboration_effect_row);
        builder.fieldBytes("label", self.label);
        builder.fieldRef("source_program", self.source_program_ref);
        builder.fieldRef("residual_program", self.residual_program_ref);
        builder.fieldBytes("normal_form", @tagName(self.normal_form));
        builder.fieldUsize("source_effect_shapes", self.source_effect_shapes);
        builder.fieldUsize("closed_effect_shapes", self.closed_effect_shapes);
        builder.fieldUsize("eliminated_source_shapes", self.eliminated_source_shapes);
        builder.fieldUsize("elaborated_provider_routes", self.elaborated_provider_routes);
        builder.fieldUsize("elaborated_morphism_routes", self.elaborated_morphism_routes);
        builder.fieldUsize("linked_provider_programs", self.linked_provider_programs);
        builder.fieldUsize("nested_provider_shapes_linked", self.nested_provider_shapes_linked);
        builder.fieldUsize("nested_provider_depth", self.nested_provider_depth);
        builder.fieldUsize("residual_world_ports", self.residual_world_ports);
        builder.fieldUsize("unsupported_shapes", self.unsupported_shapes);
        builder.fieldBool("strict_closed", self.strict_closed);
        builder.fieldBool("world_ports_only", self.world_ports_only);
        builder.fieldUsize("world_ports", self.world_ports);
        builder.fieldUsize("provider_program_links", self.provider_program_links);
        builder.fieldUsize("residualized_routes", self.residualized_routes);
        builder.fieldUsize("pipeline_routes", self.pipeline_routes);
        builder.fieldUsize("blockers", self.blockers);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refForBoundaryElaborationEffectRow(self);
    }
};

pub const BoundaryElaborationTraceMap = struct {
    label: []const u8,
    fingerprint: u64,
    entries: []const Entry = &.{},

    pub const Entry = struct {
        source_ref: Ref,
        residual_ref: Ref,
        trace_label: []const u8 = "",
    };

    pub fn init(label: []const u8, entries: []const Entry) @This() {
        var map = @This(){ .label = label, .fingerprint = 0, .entries = entries };
        map.fingerprint = map.computeFingerprint();
        return map;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_elaboration_trace_map);
        builder.fieldBytes("label", self.label);
        for (self.entries) |entry| {
            builder.fieldRef("trace.source", entry.source_ref);
            builder.fieldRef("trace.residual", entry.residual_ref);
            builder.fieldBytes("trace.label", entry.trace_label);
        }
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refForBoundaryElaborationTraceMap(self);
    }
};

pub const BoundaryNormalForm = struct {
    label: []const u8,
    fingerprint: u64,
    kind: BoundaryNormalFormKind,
    closure_certificate_ref: Ref,
    effect_row_ref: Ref,
    blocker_count: usize = 0,

    pub fn init(label: []const u8, kind: BoundaryNormalFormKind, closure_certificate_ref: Ref, effect_row_ref: Ref, blocker_count: usize) @This() {
        var normal_form = @This(){
            .label = label,
            .fingerprint = 0,
            .kind = kind,
            .closure_certificate_ref = closure_certificate_ref,
            .effect_row_ref = effect_row_ref,
            .blocker_count = blocker_count,
        };
        normal_form.fingerprint = normal_form.computeFingerprint();
        return normal_form;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_normal_form);
        builder.fieldBytes("label", self.label);
        builder.fieldBytes("kind", @tagName(self.kind));
        builder.fieldRef("closure_certificate", self.closure_certificate_ref);
        builder.fieldRef("effect_row", self.effect_row_ref);
        builder.fieldUsize("blocker_count", self.blocker_count);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refForBoundaryNormalForm(self);
    }
};

pub const BoundaryElaborationCertificate = struct {
    certificate_format_version: u32 = 1,
    certificate_fingerprint: u64,
    closure_certificate_ref: Ref,
    closure_graph_ref: Ref,
    root_program_ref: Ref,
    elaborated_program_plan_hash: u64 = 0,
    elaborated_program_label: []const u8,
    source_program_ref: Ref,
    residual_program_ref: Ref,
    closure_report_ref: Ref,
    source_map_ref: Ref,
    residual_map_ref: ?Ref = null,
    evidence_map_ref: ?Ref = null,
    effect_row_ref: Ref,
    trace_map_ref: ?Ref = null,
    normal_form_ref: Ref,
    policy_summary: PolicySummary,
    elaboration_policy_fingerprint: u64,
    normal_form: BoundaryNormalFormKind,
    selected_static_treaty_plan_refs: []const Ref = &.{},
    inlined_provider_program_refs: []const Ref = &.{},
    blocker_refs: []const Ref = &.{},
    world_port_refs: []const Ref = &.{},
    residual_world_port_refs: []const Ref = &.{},
    evidence_dependency_refs: []const Ref = &.{},
    source_to_residual_site_map_fingerprint: u64 = 0,
    residual_to_source_site_map_fingerprint: u64 = 0,
    summary_counts: SummaryCounts = .{},
    dependencies: []const Dependency = &.{},
    summary: []const u8 = "boundary elaboration certificate",

    pub const SummaryCounts = struct {
        root_effect_shapes: usize = 0,
        internal_routes_elaborated: usize = 0,
        provider_programs_linked: usize = 0,
        nested_provider_shapes_linked: usize = 0,
        nested_provider_depth: usize = 0,
        morphism_routes_elaborated: usize = 0,
        pipeline_routes_elaborated: usize = 0,
        world_ports_emitted: usize = 0,
        blockers: usize = 0,
    };

    pub fn init(options: struct {
        elaborated_program_label: []const u8,
        source_program_ref: Ref,
        residual_program_ref: Ref,
        closure_certificate_ref: Ref,
        closure_graph_ref: Ref,
        closure_report_ref: Ref,
        source_map_ref: Ref,
        residual_map_ref: ?Ref = null,
        evidence_map_ref: ?Ref = null,
        effect_row_ref: Ref,
        trace_map_ref: ?Ref = null,
        normal_form_ref: Ref,
        policy: BoundaryElaborationPolicy,
        normal_form: BoundaryNormalFormKind,
        elaborated_program_plan_hash: u64 = 0,
        selected_static_treaty_plan_refs: []const Ref = &.{},
        inlined_provider_program_refs: []const Ref = &.{},
        blocker_refs: []const Ref = &.{},
        world_port_refs: []const Ref = &.{},
        residual_world_port_refs: []const Ref = &.{},
        evidence_dependency_refs: []const Ref = &.{},
        source_to_residual_site_map_fingerprint: u64 = 0,
        residual_to_source_site_map_fingerprint: u64 = 0,
        summary_counts: SummaryCounts = .{},
        dependencies: []const Dependency = &.{},
        summary: []const u8 = "boundary elaboration certificate",
    }) @This() {
        var certificate = @This(){
            .certificate_fingerprint = 0,
            .closure_certificate_ref = options.closure_certificate_ref,
            .closure_graph_ref = options.closure_graph_ref,
            .root_program_ref = options.source_program_ref,
            .elaborated_program_plan_hash = options.elaborated_program_plan_hash,
            .elaborated_program_label = options.elaborated_program_label,
            .source_program_ref = options.source_program_ref,
            .residual_program_ref = options.residual_program_ref,
            .closure_report_ref = options.closure_report_ref,
            .source_map_ref = options.source_map_ref,
            .residual_map_ref = options.residual_map_ref,
            .evidence_map_ref = options.evidence_map_ref,
            .effect_row_ref = options.effect_row_ref,
            .trace_map_ref = options.trace_map_ref,
            .normal_form_ref = options.normal_form_ref,
            .policy_summary = options.policy.policySummary(),
            .elaboration_policy_fingerprint = options.policy.fingerprint(),
            .normal_form = options.normal_form,
            .selected_static_treaty_plan_refs = options.selected_static_treaty_plan_refs,
            .inlined_provider_program_refs = options.inlined_provider_program_refs,
            .blocker_refs = options.blocker_refs,
            .world_port_refs = options.world_port_refs,
            .residual_world_port_refs = options.residual_world_port_refs,
            .evidence_dependency_refs = options.evidence_dependency_refs,
            .source_to_residual_site_map_fingerprint = if (options.source_to_residual_site_map_fingerprint != 0) options.source_to_residual_site_map_fingerprint else options.source_map_ref.fingerprint,
            .residual_to_source_site_map_fingerprint = if (options.residual_to_source_site_map_fingerprint != 0) options.residual_to_source_site_map_fingerprint else options.source_map_ref.fingerprint,
            .summary_counts = options.summary_counts,
            .dependencies = options.dependencies,
            .summary = options.summary,
        };
        certificate.certificate_fingerprint = certificate.computeFingerprint();
        return certificate;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_elaboration_certificate);
        builder.fieldU32("format_version", self.certificate_format_version);
        builder.fieldRef("closure_certificate", self.closure_certificate_ref);
        builder.fieldRef("closure_graph", self.closure_graph_ref);
        builder.fieldRef("root_program", self.root_program_ref);
        builder.fieldU64("elaborated_program_plan_hash", self.elaborated_program_plan_hash);
        builder.fieldBytes("label", self.elaborated_program_label);
        builder.fieldRef("source_program", self.source_program_ref);
        builder.fieldRef("residual_program", self.residual_program_ref);
        builder.fieldRef("closure_report", self.closure_report_ref);
        builder.fieldRef("source_map", self.source_map_ref);
        builder.fieldOptionalRef("residual_map", self.residual_map_ref);
        builder.fieldOptionalRef("evidence_map", self.evidence_map_ref);
        builder.fieldRef("effect_row", self.effect_row_ref);
        builder.fieldOptionalRef("trace_map", self.trace_map_ref);
        builder.fieldRef("normal_form_ref", self.normal_form_ref);
        builder.fieldU64("policy", self.policy_summary.policy_fingerprint);
        builder.fieldU64("elaboration_policy", self.elaboration_policy_fingerprint);
        builder.fieldBytes("normal_form", @tagName(self.normal_form));
        for (self.selected_static_treaty_plan_refs) |ref| builder.fieldRef("static_treaty_plan", ref);
        for (self.inlined_provider_program_refs) |ref| builder.fieldRef("inlined_provider_program", ref);
        for (self.blocker_refs) |ref| builder.fieldRef("blocker", ref);
        for (self.world_port_refs) |ref| builder.fieldRef("world_port", ref);
        for (self.residual_world_port_refs) |ref| builder.fieldRef("residual_world_port", ref);
        for (self.evidence_dependency_refs) |ref| builder.fieldRef("evidence_dependency", ref);
        builder.fieldU64("source_to_residual_site_map", self.source_to_residual_site_map_fingerprint);
        builder.fieldU64("residual_to_source_site_map", self.residual_to_source_site_map_fingerprint);
        builder.fieldUsize("summary.root_effect_shapes", self.summary_counts.root_effect_shapes);
        builder.fieldUsize("summary.internal_routes_elaborated", self.summary_counts.internal_routes_elaborated);
        builder.fieldUsize("summary.provider_programs_linked", self.summary_counts.provider_programs_linked);
        builder.fieldUsize("summary.nested_provider_shapes_linked", self.summary_counts.nested_provider_shapes_linked);
        builder.fieldUsize("summary.nested_provider_depth", self.summary_counts.nested_provider_depth);
        builder.fieldUsize("summary.morphism_routes_elaborated", self.summary_counts.morphism_routes_elaborated);
        builder.fieldUsize("summary.pipeline_routes_elaborated", self.summary_counts.pipeline_routes_elaborated);
        builder.fieldUsize("summary.world_ports_emitted", self.summary_counts.world_ports_emitted);
        builder.fieldUsize("summary.blockers", self.summary_counts.blockers);
        writeCanonicalDependencies(&builder, self.dependencies);
        builder.fieldBytes("summary", self.summary);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refForBoundaryElaborationCertificate(self);
    }

    pub fn check(
        self: @This(),
        policy: BoundaryElaborationPolicy,
        expected_closure_graph_ref: Ref,
        expected_closure_report_ref: Ref,
        expected_closure_certificate_ref: Ref,
        source_map: BoundaryElaborationSourceMap,
        effect_row: BoundaryElaborationEffectRow,
        trace_map: ?BoundaryElaborationTraceMap,
        normal_form: BoundaryNormalForm,
        static_treaty_plans: []const BoundaryStaticTreatyPlan,
        world_ports: []const BoundaryWorldPort,
    ) error{
        BoundaryElaborationCertificateMismatch,
        BoundaryElaborationPolicyMismatch,
        BoundaryElaborationWorldPortsRejected,
        BoundaryElaborationBlocked,
    }!void {
        if (self.certificate_format_version != domains.boundary_elaboration_certificate.format_version.?) return error.BoundaryElaborationCertificateMismatch;
        if (self.certificate_fingerprint != self.computeFingerprint()) return error.BoundaryElaborationCertificateMismatch;
        if (!policySummariesEqual(self.policy_summary, policy.policySummary())) return error.BoundaryElaborationPolicyMismatch;
        if (self.elaboration_policy_fingerprint != policy.fingerprint()) return error.BoundaryElaborationPolicyMismatch;
        if (!self.closure_graph_ref.eql(expected_closure_graph_ref)) return error.BoundaryElaborationCertificateMismatch;
        if (!self.closure_report_ref.eql(expected_closure_report_ref)) return error.BoundaryElaborationCertificateMismatch;
        if (!self.closure_certificate_ref.eql(expected_closure_certificate_ref)) return error.BoundaryElaborationCertificateMismatch;
        if (source_map.fingerprint != source_map.computeFingerprint()) return error.BoundaryElaborationCertificateMismatch;
        if (effect_row.fingerprint != effect_row.computeFingerprint()) return error.BoundaryElaborationCertificateMismatch;
        if (normal_form.fingerprint != normal_form.computeFingerprint()) return error.BoundaryElaborationCertificateMismatch;
        if (!self.source_map_ref.eql(source_map.evidenceRef())) return error.BoundaryElaborationCertificateMismatch;
        if (self.source_to_residual_site_map_fingerprint != source_map.fingerprint) return error.BoundaryElaborationCertificateMismatch;
        if (self.residual_to_source_site_map_fingerprint != source_map.fingerprint) return error.BoundaryElaborationCertificateMismatch;
        if (self.residual_map_ref) |ref| {
            if (!ref.eql(source_map.evidenceRef())) return error.BoundaryElaborationCertificateMismatch;
        }
        if (self.evidence_map_ref) |ref| {
            if (!ref.eql(source_map.evidenceRef())) return error.BoundaryElaborationCertificateMismatch;
        }
        if (!self.effect_row_ref.eql(effect_row.evidenceRef())) return error.BoundaryElaborationCertificateMismatch;
        if (policy.emit_trace_map) {
            const expected = self.trace_map_ref orelse return error.BoundaryElaborationCertificateMismatch;
            const actual = trace_map orelse return error.BoundaryElaborationCertificateMismatch;
            if (actual.fingerprint != actual.computeFingerprint()) return error.BoundaryElaborationCertificateMismatch;
            if (!expected.eql(actual.evidenceRef())) return error.BoundaryElaborationCertificateMismatch;
        } else if (self.trace_map_ref != null or trace_map != null) {
            return error.BoundaryElaborationCertificateMismatch;
        }
        if (trace_map) |actual| {
            if (!traceMapMatchesSourceMap(actual, source_map)) return error.BoundaryElaborationCertificateMismatch;
        }
        if (!self.normal_form_ref.eql(normal_form.evidenceRef())) return error.BoundaryElaborationCertificateMismatch;
        if (!normal_form.effect_row_ref.eql(effect_row.evidenceRef())) return error.BoundaryElaborationCertificateMismatch;
        if (!normal_form.closure_certificate_ref.eql(self.closure_certificate_ref)) return error.BoundaryElaborationCertificateMismatch;
        if (self.normal_form != normal_form.kind or self.normal_form != effect_row.normal_form) return error.BoundaryElaborationCertificateMismatch;
        if (!effectRowSatisfiesNormalForm(effect_row, normal_form)) return error.BoundaryElaborationCertificateMismatch;
        if (!effectRowAliasesMatchCanonicalFields(effect_row)) return error.BoundaryElaborationCertificateMismatch;
        if (self.source_program_ref.domain_id != domains.program_plan.id) return error.BoundaryElaborationCertificateMismatch;
        if (self.residual_program_ref.domain_id != domains.program_plan.id) return error.BoundaryElaborationCertificateMismatch;
        if (!self.source_program_ref.eql(effect_row.source_program_ref)) return error.BoundaryElaborationCertificateMismatch;
        if (!self.root_program_ref.eql(self.source_program_ref)) return error.BoundaryElaborationCertificateMismatch;
        if (!self.residual_program_ref.eql(effect_row.residual_program_ref)) return error.BoundaryElaborationCertificateMismatch;
        if (!sourceMapResidualRefsMatch(source_map, self.residual_program_ref)) return error.BoundaryElaborationCertificateMismatch;
        if (self.elaborated_program_plan_hash != 0 and self.elaborated_program_plan_hash != self.residual_program_ref.fingerprint) return error.BoundaryElaborationCertificateMismatch;
        if (self.evidence_dependency_refs.len != 0 and
            !dependencyRefsMatchDependencies(self.evidence_dependency_refs, self.dependencies)) return error.BoundaryElaborationCertificateMismatch;
        if (!summaryCountsMatchEffectRow(self.summary_counts, effect_row)) return error.BoundaryElaborationCertificateMismatch;
        if (effect_row.source_effect_shapes != sourceMapEffectShapeEntryCount(source_map)) return error.BoundaryElaborationCertificateMismatch;
        if (effect_row.closed_effect_shapes != sourceMapClosedEffectShapeCount(source_map)) return error.BoundaryElaborationCertificateMismatch;
        const source_map_world_ports = sourceMapWorldPortCount(source_map);
        if (effect_row.world_ports != source_map_world_ports) return error.BoundaryElaborationCertificateMismatch;
        if (effect_row.residual_world_ports != source_map_world_ports) return error.BoundaryElaborationCertificateMismatch;
        if (self.summary_counts.world_ports_emitted != source_map_world_ports) return error.BoundaryElaborationCertificateMismatch;
        if (!sourceMapWorldPortRefsMatch(source_map, self.world_port_refs)) return error.BoundaryElaborationCertificateMismatch;
        if (!sourceMapWorldPortRefsMatch(source_map, self.residual_world_port_refs)) return error.BoundaryElaborationCertificateMismatch;
        if (!sourceMapWorldPortSitesValid(source_map)) return error.BoundaryElaborationCertificateMismatch;
        const source_map_provider_programs = sourceMapProviderProgramCount(source_map);
        if (effect_row.provider_program_links != source_map_provider_programs) return error.BoundaryElaborationCertificateMismatch;
        const source_map_unique_provider_programs = sourceMapProviderProgramUniqueCount(source_map);
        if (effect_row.linked_provider_programs != source_map_unique_provider_programs) return error.BoundaryElaborationCertificateMismatch;
        if (self.summary_counts.provider_programs_linked != source_map_unique_provider_programs) return error.BoundaryElaborationCertificateMismatch;
        if (effect_row.residualized_routes != sourceMapDispositionCount(source_map, .residualized)) return error.BoundaryElaborationCertificateMismatch;
        if (effect_row.pipeline_routes != sourceMapDispositionCount(source_map, .pipeline_adapter)) return error.BoundaryElaborationCertificateMismatch;
        if (!sourceMapClosedRoutesHaveStaticPlanRefs(source_map)) return error.BoundaryElaborationCertificateMismatch;
        if (!sourceMapProviderProgramRefsMatch(source_map, self.inlined_provider_program_refs)) return error.BoundaryElaborationCertificateMismatch;
        if (effect_row.nested_provider_depth > policy.max_nested_provider_depth or
            self.summary_counts.nested_provider_depth > policy.max_nested_provider_depth)
        {
            return error.BoundaryElaborationBlocked;
        }
        if (!sourceMapStaticTreatyPlanRefsMatch(source_map, self.selected_static_treaty_plan_refs)) return error.BoundaryElaborationCertificateMismatch;
        if (!sourceMapWorldPortsMatchPorts(source_map, world_ports)) return error.BoundaryElaborationCertificateMismatch;
        if (!worldPortsAllowedByElaborationPolicy(policy, world_ports)) return error.BoundaryElaborationWorldPortsRejected;
        if (!sourceMapStaticTreatyPlanSourcesMatch(policy, self.source_program_ref, self.inlined_provider_program_refs, self.dependencies, source_map, static_treaty_plans, world_ports)) return error.BoundaryElaborationCertificateMismatch;
        if (!policy.allow_world_ports and
            (self.world_port_refs.len != 0 or
                self.residual_world_port_refs.len != 0 or
                effect_row.world_ports != 0 or
                effect_row.residual_world_ports != 0 or
                self.summary_counts.world_ports_emitted != 0 or
                self.normal_form == .world_ports_only or
                normal_form.kind == .world_ports_only))
        {
            return error.BoundaryElaborationWorldPortsRejected;
        }
        if (!policy.allow_partial_with_blockers and
            (self.blocker_refs.len != 0 or effect_row.blockers != 0 or self.summary_counts.blockers != 0 or normal_form.blocker_count != 0))
        {
            return error.BoundaryElaborationBlocked;
        }
        if (self.blocker_refs.len != effect_row.blockers) return error.BoundaryElaborationCertificateMismatch;
        const blocked_entry_count = sourceMapBlockedEntryCount(source_map);
        const blocked_unsupported_shape_count = sourceMapBlockedUnsupportedShapeCount(source_map, static_treaty_plans);
        if (blocked_entry_count > effect_row.blockers or blocked_unsupported_shape_count != effect_row.unsupported_shapes) return error.BoundaryElaborationCertificateMismatch;
        if (policy.fail_on_unsupported_shape and
            (blocked_unsupported_shape_count != 0 or effect_row.unsupported_shapes != 0))
        {
            return error.BoundaryElaborationBlocked;
        }
        if (self.blocker_refs.len > policy.max_blockers or
            effect_row.blockers > policy.max_blockers or
            self.summary_counts.blockers > policy.max_blockers or
            normal_form.blocker_count > policy.max_blockers)
        {
            return error.BoundaryElaborationBlocked;
        }
        if (self.blocker_refs.len != 0 and blocked_entry_count == 0) return error.BoundaryElaborationCertificateMismatch;
        if (blocked_entry_count != 0 and
            !sourceMapBlockerRefsMatchBlockedEntries(source_map, static_treaty_plans, self.blocker_refs))
        {
            return error.BoundaryElaborationCertificateMismatch;
        }
    }

    pub fn evidenceView(self: @This()) CertificateView {
        return .{
            .certificate_ref = self.evidenceRef(),
            .subject_ref = self.source_program_ref,
            .domain = domains.boundary_elaboration_certificate.id,
            .dependencies = self.dependencies,
            .report_fingerprint = self.effect_row_ref.fingerprint,
            .policy_fingerprint = self.policy_summary.policy_fingerprint,
            .certificate_fingerprint = self.certificate_fingerprint,
            .summary = self.summary,
        };
    }
};

pub const BoundaryTargetPolicy = struct {
    label: []const u8 = "target_fail_closed",
    elaboration_policy: BoundaryElaborationPolicy = .{ .require_program_backed_providers_for_internal_routes = false },
    require_checked_closure_certificate: bool = true,
    allow_world_ports: bool = false,
    allow_program_backed_providers: bool = true,
    allow_nested_program_backed_providers: bool = true,
    allow_declarative_morphisms: bool = true,
    allow_residualized_morphisms: bool = true,
    allow_pipeline_adapters: bool = true,
    reject_host_intrinsic_internal_routes: bool = true,
    reject_unknown_semantic_bodies: bool = true,
    max_nested_provider_depth: usize = 32,
    max_generated_functions: usize = 4096,
    max_rewrite_steps: usize = 4096,
    preserve_semantic_labels: bool = true,
    preserve_source_coordinates: bool = true,
    emit_source_map: bool = true,
    emit_trace_map: bool = true,
    emit_evidence_map: bool = true,
    emit_world_surface: bool = true,
    require_no_search_hot_path: bool = true,
    require_bounded_surface: bool = false,
    fail_on_unsupported_instruction: bool = true,
    fail_on_schema_mismatch: bool = true,
    fail_on_unbounded_world_port_when_bounded_required: bool = true,
    max_world_ports: usize = std.math.maxInt(usize),
    max_value_descriptors: usize = std.math.maxInt(usize),
    max_dispatch_entries: usize = std.math.maxInt(usize),

    pub fn strictClosed() @This() {
        return .{ .label = "strict_closed_target" };
    }

    pub fn strict_closed() @This() {
        return strictClosed();
    }

    pub fn worldBoundary() @This() {
        var policy = @This(){
            .label = "world_boundary_target",
            .elaboration_policy = BoundaryElaborationPolicy.worldBoundary(),
            .allow_world_ports = true,
            .reject_host_intrinsic_internal_routes = false,
        };
        policy.elaboration_policy.require_program_backed_providers_for_internal_routes = false;
        return policy;
    }

    pub fn world_boundary() @This() {
        return worldBoundary();
    }

    pub fn auditOnly() @This() {
        var policy = @This(){
            .label = "audit_only_target",
            .elaboration_policy = BoundaryElaborationPolicy.auditOnly(),
            .require_checked_closure_certificate = false,
            .allow_world_ports = true,
            .reject_host_intrinsic_internal_routes = false,
            .reject_unknown_semantic_bodies = false,
            .require_no_search_hot_path = false,
            .fail_on_unsupported_instruction = false,
            .fail_on_schema_mismatch = false,
            .fail_on_unbounded_world_port_when_bounded_required = false,
        };
        policy.elaboration_policy.require_program_backed_providers_for_internal_routes = false;
        return policy;
    }

    pub fn audit_only() @This() {
        return auditOnly();
    }

    pub fn toElaborationPolicy(self: @This()) BoundaryElaborationPolicy {
        return boundaryTargetElaborationPolicy(self);
    }

    pub fn fingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_target_policy);
        builder.fieldBytes("label", self.label);
        builder.fieldU64("elaboration_policy", self.elaboration_policy.fingerprint());
        builder.fieldBool("require_checked_closure_certificate", self.require_checked_closure_certificate);
        builder.fieldBool("allow_world_ports", self.allow_world_ports);
        builder.fieldBool("allow_program_backed_providers", self.allow_program_backed_providers);
        builder.fieldBool("allow_nested_program_backed_providers", self.allow_nested_program_backed_providers);
        builder.fieldBool("allow_declarative_morphisms", self.allow_declarative_morphisms);
        builder.fieldBool("allow_residualized_morphisms", self.allow_residualized_morphisms);
        builder.fieldBool("allow_pipeline_adapters", self.allow_pipeline_adapters);
        builder.fieldBool("reject_host_intrinsic_internal_routes", self.reject_host_intrinsic_internal_routes);
        builder.fieldBool("reject_unknown_semantic_bodies", self.reject_unknown_semantic_bodies);
        builder.fieldUsize("max_nested_provider_depth", self.max_nested_provider_depth);
        builder.fieldUsize("max_generated_functions", self.max_generated_functions);
        builder.fieldUsize("max_rewrite_steps", self.max_rewrite_steps);
        builder.fieldBool("preserve_semantic_labels", self.preserve_semantic_labels);
        builder.fieldBool("preserve_source_coordinates", self.preserve_source_coordinates);
        builder.fieldBool("emit_source_map", self.emit_source_map);
        builder.fieldBool("emit_trace_map", self.emit_trace_map);
        builder.fieldBool("emit_evidence_map", self.emit_evidence_map);
        builder.fieldBool("emit_world_surface", self.emit_world_surface);
        builder.fieldBool("require_no_search_hot_path", self.require_no_search_hot_path);
        builder.fieldBool("require_bounded_surface", self.require_bounded_surface);
        builder.fieldBool("fail_on_unsupported_instruction", self.fail_on_unsupported_instruction);
        builder.fieldBool("fail_on_schema_mismatch", self.fail_on_schema_mismatch);
        builder.fieldBool("fail_on_unbounded_world_port_when_bounded_required", self.fail_on_unbounded_world_port_when_bounded_required);
        builder.fieldUsize("max_world_ports", self.max_world_ports);
        builder.fieldUsize("max_value_descriptors", self.max_value_descriptors);
        builder.fieldUsize("max_dispatch_entries", self.max_dispatch_entries);
        return builder.finish();
    }
};

fn boundaryTargetElaborationPolicy(policy: BoundaryTargetPolicy) BoundaryElaborationPolicy {
    var elaboration_policy = policy.elaboration_policy;
    elaboration_policy.allow_world_ports = policy.allow_world_ports;
    elaboration_policy.allow_intrinsic_world_ports = !policy.reject_host_intrinsic_internal_routes;
    elaboration_policy.closure_policy.allow_world_ports = policy.allow_world_ports;
    if (policy.allow_world_ports) {
        elaboration_policy.closure_policy.require_all_effect_shapes_closed = false;
    }
    elaboration_policy.closure_policy.allow_host_intrinsics = !policy.reject_host_intrinsic_internal_routes;
    elaboration_policy.closure_policy.reject_host_intrinsics = policy.reject_host_intrinsic_internal_routes;
    if (!policy.reject_host_intrinsic_internal_routes) {
        elaboration_policy.closure_policy.defunctionalization_policy.allow_host_intrinsics = true;
        elaboration_policy.closure_policy.defunctionalization_policy.maximum_intrinsic_count = null;
    }
    elaboration_policy.require_certificate_checked = policy.require_checked_closure_certificate;
    elaboration_policy.require_checked_closure_certificate = policy.require_checked_closure_certificate;
    elaboration_policy.allow_provider_program_linking = policy.allow_program_backed_providers;
    elaboration_policy.allow_declarative_morphisms = policy.allow_declarative_morphisms;
    elaboration_policy.allow_residualized_morphisms = policy.allow_residualized_morphisms;
    elaboration_policy.allow_pipeline_adapters = policy.allow_pipeline_adapters;
    elaboration_policy.require_program_backed_providers_for_internal_routes =
        elaboration_policy.require_program_backed_providers_for_internal_routes or
        (!policy.allow_declarative_morphisms and !policy.allow_residualized_morphisms and !policy.allow_pipeline_adapters);
    elaboration_policy.reject_unknown_semantic_bodies = policy.reject_unknown_semantic_bodies;
    elaboration_policy.closure_policy.reject_unknown_semantic_bodies = policy.reject_unknown_semantic_bodies;
    elaboration_policy.closure_policy.defunctionalization_policy.reject_unknown = policy.reject_unknown_semantic_bodies;
    const max_nested_provider_depth = if (policy.allow_nested_program_backed_providers) policy.max_nested_provider_depth else 0;
    elaboration_policy.max_nested_provider_depth = max_nested_provider_depth;
    elaboration_policy.closure_policy.max_nested_provider_depth = max_nested_provider_depth;
    elaboration_policy.fail_on_unsupported_shape = policy.fail_on_unsupported_instruction;
    elaboration_policy.allow_partial_with_blockers = !policy.fail_on_unsupported_instruction;
    elaboration_policy.max_blockers = if (policy.fail_on_unsupported_instruction) 0 else std.math.maxInt(usize);
    elaboration_policy.emit_trace_map = policy.emit_trace_map;
    return elaboration_policy;
}

pub const BoundaryWorldPortTable = struct {
    label: []const u8,
    fingerprint: u64,
    entries: []const Entry = &.{},

    pub const Entry = struct {
        world_port_id: u32,
        residual_site_index: usize,
        residual_site_fingerprint: u64,
        world_port_ref: Ref,
        source_ref: Ref,
        payload_ref: BoundaryValueRef,
        resume_ref: BoundaryValueRef,
        result_ref: BoundaryValueRef,
        protocol_label: []const u8 = "",
        op_name: []const u8 = "",
        mode: []const u8 = "",
        semantic_label: ?[]const u8 = null,
    };

    pub fn init(label: []const u8, entries: []const Entry) @This() {
        var table = @This(){ .label = label, .fingerprint = 0, .entries = entries };
        table.fingerprint = table.computeFingerprint();
        return table;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_world_port_table);
        builder.fieldBytes("label", self.label);
        for (self.entries) |entry| {
            builder.fieldU64("entry.world_port_id", entry.world_port_id);
            builder.fieldUsize("entry.residual_site_index", entry.residual_site_index);
            builder.fieldU64("entry.residual_site_fingerprint", entry.residual_site_fingerprint);
            builder.fieldRef("entry.world_port", entry.world_port_ref);
            builder.fieldRef("entry.source", entry.source_ref);
            builder.fieldValueRef("entry.payload_ref", entry.payload_ref);
            builder.fieldValueRef("entry.resume_ref", entry.resume_ref);
            builder.fieldValueRef("entry.result_ref", entry.result_ref);
            builder.fieldBytes("entry.protocol_label", entry.protocol_label);
            builder.fieldBytes("entry.op_name", entry.op_name);
            builder.fieldBytes("entry.mode", entry.mode);
            builder.fieldOptionalBytes("entry.semantic_label", entry.semantic_label);
        }
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refForBoundaryWorldPortTable(self);
    }
};

pub const BoundaryWorldValueTable = struct {
    label: []const u8,
    fingerprint: u64,
    entries: []const Entry = &.{},

    pub const Kind = enum { payload, @"resume", result };

    pub const Entry = struct {
        value_id: u32,
        world_port_id: u32,
        kind: Kind,
        ref: BoundaryValueRef,
    };

    pub fn init(label: []const u8, entries: []const Entry) @This() {
        var table = @This(){ .label = label, .fingerprint = 0, .entries = entries };
        table.fingerprint = table.computeFingerprint();
        return table;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_world_value_table);
        builder.fieldBytes("label", self.label);
        for (self.entries) |entry| {
            builder.fieldU64("entry.value_id", entry.value_id);
            builder.fieldU64("entry.world_port_id", entry.world_port_id);
            builder.fieldBytes("entry.kind", @tagName(entry.kind));
            builder.fieldValueRef("entry.ref", entry.ref);
        }
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refForBoundaryWorldValueTable(self);
    }
};

pub const BoundaryWorldDispatchTable = struct {
    label: []const u8,
    fingerprint: u64,
    entries: []const Entry = &.{},

    pub const missing_world_port_id: u32 = std.math.maxInt(u32);

    pub const Entry = struct {
        residual_site_index: usize,
        residual_site_fingerprint: u64,
        world_port_id: u32,
    };

    pub fn init(label: []const u8, entries: []const Entry) @This() {
        var table = @This(){ .label = label, .fingerprint = 0, .entries = entries };
        table.fingerprint = table.computeFingerprint();
        return table;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_world_dispatch_table);
        builder.fieldBytes("label", self.label);
        for (self.entries) |entry| {
            builder.fieldUsize("entry.residual_site_index", entry.residual_site_index);
            builder.fieldU64("entry.residual_site_fingerprint", entry.residual_site_fingerprint);
            builder.fieldU64("entry.world_port_id", entry.world_port_id);
        }
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refForBoundaryWorldDispatchTable(self);
    }

    pub fn lookup(self: @This(), residual_site_index: usize) ?u32 {
        if (residual_site_index < self.entries.len) {
            const entry = self.entries[residual_site_index];
            if (entry.residual_site_index == residual_site_index) return worldPortIdOrNull(entry.world_port_id);
        }
        for (self.entries) |entry| {
            if (entry.residual_site_index == residual_site_index) return worldPortIdOrNull(entry.world_port_id);
        }
        return null;
    }

    fn worldPortIdOrNull(world_port_id: u32) ?u32 {
        if (world_port_id == missing_world_port_id) return null;
        return world_port_id;
    }
};

pub const BoundarySurfaceProfile = struct {
    label: []const u8,
    fingerprint: u64,
    world_port_count: usize = 0,
    value_descriptor_count: usize = 0,
    dispatch_entry_count: usize = 0,
    no_search_hot_path: bool = false,
    bounded: bool = false,

    pub fn init(options: struct {
        label: []const u8,
        world_port_count: usize = 0,
        value_descriptor_count: usize = 0,
        dispatch_entry_count: usize = 0,
        no_search_hot_path: bool = false,
        bounded: bool = false,
    }) @This() {
        var profile = @This(){
            .label = options.label,
            .fingerprint = 0,
            .world_port_count = options.world_port_count,
            .value_descriptor_count = options.value_descriptor_count,
            .dispatch_entry_count = options.dispatch_entry_count,
            .no_search_hot_path = options.no_search_hot_path,
            .bounded = options.bounded,
        };
        profile.fingerprint = profile.computeFingerprint();
        return profile;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_world_surface_profile);
        builder.fieldBytes("label", self.label);
        builder.fieldUsize("world_port_count", self.world_port_count);
        builder.fieldUsize("value_descriptor_count", self.value_descriptor_count);
        builder.fieldUsize("dispatch_entry_count", self.dispatch_entry_count);
        builder.fieldBool("no_search_hot_path", self.no_search_hot_path);
        builder.fieldBool("bounded", self.bounded);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refForBoundaryWorldSurfaceProfile(self);
    }
};

pub const BoundaryReplayKeyRecipe = struct {
    label: []const u8,
    fingerprint: u64,
    surface_ref: Ref,
    components: []const []const u8 = &.{},

    pub fn init(label: []const u8, surface_ref: Ref, components: []const []const u8) @This() {
        var recipe = @This(){ .label = label, .fingerprint = 0, .surface_ref = surface_ref, .components = components };
        recipe.fingerprint = recipe.computeFingerprint();
        return recipe;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_world_replay_key_recipe);
        builder.fieldBytes("label", self.label);
        builder.fieldRef("surface", self.surface_ref);
        for (self.components) |component| builder.fieldBytes("component", component);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refForBoundaryWorldReplayKeyRecipe(self);
    }
};

pub const BoundaryWorldSurface = struct {
    surface_format_version: u32 = 1,
    surface_fingerprint: u64,
    label: []const u8,
    residual_program_label: []const u8,
    residual_program_ref: Ref,
    elaboration_certificate_ref: Ref,
    source_map_ref: Ref,
    effect_row_ref: Ref,
    port_table_ref: Ref,
    value_table_ref: Ref,
    dispatch_table_ref: Ref,
    profile_ref: Ref,
    replay_key_recipe_ref: Ref,
    normal_form: BoundaryNormalFormKind,
    world_port_count: usize,

    pub fn init(options: struct {
        label: []const u8,
        residual_program_label: []const u8,
        residual_program_ref: Ref,
        elaboration_certificate_ref: Ref,
        source_map_ref: Ref,
        effect_row_ref: Ref,
        port_table_ref: Ref,
        value_table_ref: Ref,
        dispatch_table_ref: Ref,
        profile_ref: Ref,
        replay_key_recipe_ref: Ref,
        normal_form: BoundaryNormalFormKind,
        world_port_count: usize,
    }) @This() {
        var surface = @This(){
            .surface_fingerprint = 0,
            .label = options.label,
            .residual_program_label = options.residual_program_label,
            .residual_program_ref = options.residual_program_ref,
            .elaboration_certificate_ref = options.elaboration_certificate_ref,
            .source_map_ref = options.source_map_ref,
            .effect_row_ref = options.effect_row_ref,
            .port_table_ref = options.port_table_ref,
            .value_table_ref = options.value_table_ref,
            .dispatch_table_ref = options.dispatch_table_ref,
            .profile_ref = options.profile_ref,
            .replay_key_recipe_ref = options.replay_key_recipe_ref,
            .normal_form = options.normal_form,
            .world_port_count = options.world_port_count,
        };
        surface.surface_fingerprint = surface.computeFingerprint();
        return surface;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = self.fingerprintBuilderWithoutReplayRecipe();
        builder.fieldRef("replay_key_recipe", self.replay_key_recipe_ref);
        return builder.finish();
    }

    pub fn replayScopeRef(self: @This()) Ref {
        return refFor(domains.boundary_world_surface, self.computeReplayScopeFingerprint(), .{
            .format_version = domains.boundary_world_surface.format_version,
            .label = self.label,
        });
    }

    fn computeReplayScopeFingerprint(self: @This()) u64 {
        var builder = self.fingerprintBuilderWithoutReplayRecipe();
        return builder.finish();
    }

    fn fingerprintBuilderWithoutReplayRecipe(self: @This()) FingerprintBuilder {
        var builder = FingerprintBuilder.init(domains.boundary_world_surface);
        builder.fieldU32("format_version", self.surface_format_version);
        builder.fieldBytes("label", self.label);
        builder.fieldBytes("residual_program_label", self.residual_program_label);
        builder.fieldRef("residual_program", self.residual_program_ref);
        builder.fieldRef("elaboration_certificate", self.elaboration_certificate_ref);
        builder.fieldRef("source_map", self.source_map_ref);
        builder.fieldRef("effect_row", self.effect_row_ref);
        builder.fieldRef("port_table", self.port_table_ref);
        builder.fieldRef("value_table", self.value_table_ref);
        builder.fieldRef("dispatch_table", self.dispatch_table_ref);
        builder.fieldRef("profile", self.profile_ref);
        builder.fieldBytes("normal_form", @tagName(self.normal_form));
        builder.fieldUsize("world_port_count", self.world_port_count);
        return builder;
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refForBoundaryWorldSurface(self);
    }
};

pub const BoundaryTargetEvidenceMap = struct {
    label: []const u8,
    fingerprint: u64,
    dependencies: []const Dependency = &.{},

    pub fn init(label: []const u8, dependencies: []const Dependency) @This() {
        var map = @This(){ .label = label, .fingerprint = 0, .dependencies = dependencies };
        map.fingerprint = map.computeFingerprint();
        return map;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_target_evidence_map);
        builder.fieldBytes("label", self.label);
        writeCanonicalDependencies(&builder, self.dependencies);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refForBoundaryTargetEvidenceMap(self);
    }
};

pub const BoundaryNormalizationBlockerTag = enum {
    provider_program_missing,
    provider_mapping_unsupported,
    provider_arg_mismatch,
    provider_result_mismatch,
    provider_mode_unsupported,
    provider_schema_mismatch,
    provider_call_rewrite_failed,
    nested_provider_missing,
    nested_static_plan_missing,
    nested_provider_cycle,
    nested_depth_exceeded,
    nested_provider_mapping_unsupported,
    nested_rewrite_failed,
    world_port_missing,
    world_port_shape_mismatch,
    world_port_policy_rejected,
    world_port_lowering_failed,
    unsupported_redex,
    unsupported_operation_mode,
    unsupported_after_site,
    unsupported_control_flow,
    unsupported_mapping,
    unsupported_morphism,
    unsupported_pipeline,
    certificate_mismatch,
    policy_mismatch,
    residual_validation_failed,
};

pub const BoundaryNormalizationPolicy = struct {
    label: []const u8 = "normalization_fail_closed",
    allow_program_provider_rewrites: bool = true,
    allow_nested_provider_rewrites: bool = true,
    allow_world_port_residualization: bool = false,
    allow_declarative_morphism_rewrites: bool = true,
    allow_residualized_morphism_rewrites: bool = true,
    allow_pipeline_rewrites: bool = true,
    reject_host_intrinsic_internal_routes: bool = true,
    reject_unknown_semantic_bodies: bool = true,
    max_nested_provider_depth: usize = 32,
    max_rewrite_steps: usize = 4096,
    require_from_residual_validation: bool = true,
    require_no_internal_residual_effects: bool = true,
    require_no_search_hot_path: bool = true,
    preserve_semantic_labels: bool = true,
    preserve_source_coordinates: bool = true,
    fail_on_unsupported_redex: bool = true,
    fail_on_schema_mismatch: bool = true,

    pub fn strictClosed() @This() {
        return .{ .label = "strict_closed_normalization" };
    }

    pub fn strict_closed() @This() {
        return strictClosed();
    }

    pub fn worldBoundary() @This() {
        return .{
            .label = "world_boundary_normalization",
            .allow_world_port_residualization = true,
            .reject_host_intrinsic_internal_routes = false,
            .require_no_internal_residual_effects = true,
        };
    }

    pub fn world_boundary() @This() {
        return worldBoundary();
    }

    pub fn auditOnly() @This() {
        return .{
            .label = "audit_only_normalization",
            .allow_world_port_residualization = true,
            .reject_host_intrinsic_internal_routes = false,
            .reject_unknown_semantic_bodies = false,
            .require_from_residual_validation = false,
            .require_no_internal_residual_effects = false,
            .require_no_search_hot_path = false,
            .fail_on_unsupported_redex = false,
            .fail_on_schema_mismatch = false,
            .max_rewrite_steps = std.math.maxInt(usize),
        };
    }

    pub fn audit_only() @This() {
        return auditOnly();
    }

    pub fn fromTargetPolicy(target_policy: BoundaryTargetPolicy) @This() {
        return .{
            .label = target_policy.label,
            .allow_program_provider_rewrites = target_policy.allow_program_backed_providers,
            .allow_nested_provider_rewrites = target_policy.allow_nested_program_backed_providers,
            .allow_world_port_residualization = target_policy.allow_world_ports,
            .allow_declarative_morphism_rewrites = target_policy.allow_declarative_morphisms,
            .allow_residualized_morphism_rewrites = target_policy.allow_residualized_morphisms,
            .allow_pipeline_rewrites = target_policy.allow_pipeline_adapters,
            .reject_host_intrinsic_internal_routes = target_policy.reject_host_intrinsic_internal_routes,
            .reject_unknown_semantic_bodies = target_policy.reject_unknown_semantic_bodies,
            .max_nested_provider_depth = target_policy.max_nested_provider_depth,
            .max_rewrite_steps = target_policy.max_rewrite_steps,
            .require_from_residual_validation = true,
            .require_no_search_hot_path = target_policy.require_no_search_hot_path,
            .preserve_semantic_labels = target_policy.preserve_semantic_labels,
            .preserve_source_coordinates = target_policy.preserve_source_coordinates,
            .fail_on_unsupported_redex = target_policy.fail_on_unsupported_instruction,
            .fail_on_schema_mismatch = target_policy.fail_on_schema_mismatch,
        };
    }

    pub fn fingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_target_policy);
        builder.fieldBytes("normalization.label", self.label);
        builder.fieldBool("allow_program_provider_rewrites", self.allow_program_provider_rewrites);
        builder.fieldBool("allow_nested_provider_rewrites", self.allow_nested_provider_rewrites);
        builder.fieldBool("allow_world_port_residualization", self.allow_world_port_residualization);
        builder.fieldBool("allow_declarative_morphism_rewrites", self.allow_declarative_morphism_rewrites);
        builder.fieldBool("allow_residualized_morphism_rewrites", self.allow_residualized_morphism_rewrites);
        builder.fieldBool("allow_pipeline_rewrites", self.allow_pipeline_rewrites);
        builder.fieldBool("reject_host_intrinsic_internal_routes", self.reject_host_intrinsic_internal_routes);
        builder.fieldBool("reject_unknown_semantic_bodies", self.reject_unknown_semantic_bodies);
        builder.fieldUsize("max_nested_provider_depth", self.max_nested_provider_depth);
        builder.fieldUsize("max_rewrite_steps", self.max_rewrite_steps);
        builder.fieldBool("require_from_residual_validation", self.require_from_residual_validation);
        builder.fieldBool("require_no_internal_residual_effects", self.require_no_internal_residual_effects);
        builder.fieldBool("require_no_search_hot_path", self.require_no_search_hot_path);
        builder.fieldBool("preserve_semantic_labels", self.preserve_semantic_labels);
        builder.fieldBool("preserve_source_coordinates", self.preserve_source_coordinates);
        builder.fieldBool("fail_on_unsupported_redex", self.fail_on_unsupported_redex);
        builder.fieldBool("fail_on_schema_mismatch", self.fail_on_schema_mismatch);
        return builder.finish();
    }
};

pub const BoundaryNormalizationCoordinates = struct {
    function_index: ?usize = null,
    block_index: ?usize = null,
    instruction_index: ?usize = null,
    site_index: ?usize = null,
};

pub const BoundaryNormalizationRedex = struct {
    label: []const u8 = "",
    fingerprint: u64,
    source_effect_shape_ref: Ref,
    coordinates: BoundaryNormalizationCoordinates = .{},
    origin: Origin = .root_program,
    kind: Kind = .unsupported,
    selected_static_treaty_plan_ref: ?Ref = null,
    current_program_plan_ref: Ref,
    semantic_body: SemanticBody = .unknown,
    expected_lowering_kind: BoundaryNormalizationRewriteRule.Kind = .unsupported,
    evidence_dependencies: []const Dependency = &.{},

    pub const Origin = enum {
        root_program,
        provider_program,
        nested_provider_program,
        morphism_residual,
        pipeline_residual,
    };

    pub const Kind = enum {
        operation_site,
        after_site,
        protocol_operation_shape,
        world_port_site,
        unsupported,
    };

    pub fn init(options: struct {
        label: []const u8 = "",
        source_effect_shape_ref: Ref,
        coordinates: BoundaryNormalizationCoordinates = .{},
        origin: Origin = .root_program,
        kind: Kind = .unsupported,
        selected_static_treaty_plan_ref: ?Ref = null,
        current_program_plan_ref: Ref,
        semantic_body: SemanticBody = .unknown,
        expected_lowering_kind: BoundaryNormalizationRewriteRule.Kind = .unsupported,
        evidence_dependencies: []const Dependency = &.{},
    }) @This() {
        var redex = @This(){
            .label = options.label,
            .fingerprint = 0,
            .source_effect_shape_ref = options.source_effect_shape_ref,
            .coordinates = options.coordinates,
            .origin = options.origin,
            .kind = options.kind,
            .selected_static_treaty_plan_ref = options.selected_static_treaty_plan_ref,
            .current_program_plan_ref = options.current_program_plan_ref,
            .semantic_body = options.semantic_body,
            .expected_lowering_kind = options.expected_lowering_kind,
            .evidence_dependencies = options.evidence_dependencies,
        };
        redex.fingerprint = redex.computeFingerprint();
        return redex;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_normalization_redex);
        builder.fieldBytes("label", self.label);
        builder.fieldRef("source_effect_shape", self.source_effect_shape_ref);
        builder.fieldOptionalU64("coordinate.function", if (self.coordinates.function_index) |value| @as(u64, @intCast(value)) else null);
        builder.fieldOptionalU64("coordinate.block", if (self.coordinates.block_index) |value| @as(u64, @intCast(value)) else null);
        builder.fieldOptionalU64("coordinate.instruction", if (self.coordinates.instruction_index) |value| @as(u64, @intCast(value)) else null);
        builder.fieldOptionalU64("coordinate.site", if (self.coordinates.site_index) |value| @as(u64, @intCast(value)) else null);
        builder.fieldBytes("origin", @tagName(self.origin));
        builder.fieldBytes("kind", @tagName(self.kind));
        builder.fieldOptionalRef("static_treaty_plan", self.selected_static_treaty_plan_ref);
        builder.fieldRef("current_program_plan", self.current_program_plan_ref);
        builder.fieldBytes("semantic_body", @tagName(self.semantic_body));
        builder.fieldBytes("expected_lowering", @tagName(self.expected_lowering_kind));
        writeCanonicalDependencies(&builder, self.evidence_dependencies);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refForBoundaryNormalizationRedex(self);
    }
};

pub const BoundaryNormalizationRewriteRule = struct {
    label: []const u8 = "",
    fingerprint: u64,
    kind: Kind,
    evidence_dependencies: []const Dependency = &.{},
    produced_source_map_entries: usize = 0,
    produced_trace_map_entries: usize = 0,
    produced_effect_row_entries: usize = 0,
    blocker_refs: []const Ref = &.{},

    pub const Kind = enum {
        root_copy,
        provider_program_call,
        nested_provider_program_call,
        residual_world_port,
        residualized_morphism,
        pipeline_adapter,
        already_normal,
        unsupported,
    };

    pub fn init(options: struct {
        label: []const u8 = "",
        kind: Kind,
        evidence_dependencies: []const Dependency = &.{},
        produced_source_map_entries: usize = 0,
        produced_trace_map_entries: usize = 0,
        produced_effect_row_entries: usize = 0,
        blocker_refs: []const Ref = &.{},
    }) @This() {
        var rule = @This(){
            .label = options.label,
            .fingerprint = 0,
            .kind = options.kind,
            .evidence_dependencies = options.evidence_dependencies,
            .produced_source_map_entries = options.produced_source_map_entries,
            .produced_trace_map_entries = options.produced_trace_map_entries,
            .produced_effect_row_entries = options.produced_effect_row_entries,
            .blocker_refs = options.blocker_refs,
        };
        rule.fingerprint = rule.computeFingerprint();
        return rule;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_normalization_rule);
        builder.fieldBytes("label", self.label);
        builder.fieldBytes("kind", @tagName(self.kind));
        writeCanonicalDependencies(&builder, self.evidence_dependencies);
        builder.fieldUsize("produced_source_map_entries", self.produced_source_map_entries);
        builder.fieldUsize("produced_trace_map_entries", self.produced_trace_map_entries);
        builder.fieldUsize("produced_effect_row_entries", self.produced_effect_row_entries);
        for (self.blocker_refs) |ref| builder.fieldRef("blocker", ref);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refForBoundaryNormalizationRule(self);
    }
};

pub const BoundaryNormalizationRewriteStep = struct {
    step_index: usize,
    fingerprint: u64,
    redex_ref: Ref,
    rewrite_rule_ref: Ref,
    selected_static_treaty_plan_ref: ?Ref = null,
    source_effect_shape_ref: Ref,
    input_program_plan_hash: u64,
    output_program_plan_hash: u64,
    builder_state_fingerprint: ?u64 = null,
    provider_program_ref: ?Ref = null,
    provider_offer_ref: ?Ref = null,
    world_port_ref: ?Ref = null,
    morphism_or_pipeline_ref: ?Ref = null,
    blocker_refs: []const Ref = &.{},
    summary: []const u8 = "",

    pub fn init(options: struct {
        step_index: usize,
        redex_ref: Ref,
        rewrite_rule_ref: Ref,
        selected_static_treaty_plan_ref: ?Ref = null,
        source_effect_shape_ref: Ref,
        input_program_plan_hash: u64,
        output_program_plan_hash: u64,
        builder_state_fingerprint: ?u64 = null,
        provider_program_ref: ?Ref = null,
        provider_offer_ref: ?Ref = null,
        world_port_ref: ?Ref = null,
        morphism_or_pipeline_ref: ?Ref = null,
        blocker_refs: []const Ref = &.{},
        summary: []const u8 = "",
    }) @This() {
        var step = @This(){
            .step_index = options.step_index,
            .fingerprint = 0,
            .redex_ref = options.redex_ref,
            .rewrite_rule_ref = options.rewrite_rule_ref,
            .selected_static_treaty_plan_ref = options.selected_static_treaty_plan_ref,
            .source_effect_shape_ref = options.source_effect_shape_ref,
            .input_program_plan_hash = options.input_program_plan_hash,
            .output_program_plan_hash = options.output_program_plan_hash,
            .builder_state_fingerprint = options.builder_state_fingerprint,
            .provider_program_ref = options.provider_program_ref,
            .provider_offer_ref = options.provider_offer_ref,
            .world_port_ref = options.world_port_ref,
            .morphism_or_pipeline_ref = options.morphism_or_pipeline_ref,
            .blocker_refs = options.blocker_refs,
            .summary = options.summary,
        };
        step.fingerprint = step.computeFingerprint();
        return step;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_normalization_step);
        builder.fieldUsize("step_index", self.step_index);
        builder.fieldRef("redex", self.redex_ref);
        builder.fieldRef("rewrite_rule", self.rewrite_rule_ref);
        builder.fieldOptionalRef("static_treaty_plan", self.selected_static_treaty_plan_ref);
        builder.fieldRef("source_effect_shape", self.source_effect_shape_ref);
        builder.fieldU64("input_program_plan_hash", self.input_program_plan_hash);
        builder.fieldU64("output_program_plan_hash", self.output_program_plan_hash);
        builder.fieldOptionalU64("builder_state", self.builder_state_fingerprint);
        builder.fieldOptionalRef("provider_program", self.provider_program_ref);
        builder.fieldOptionalRef("provider_offer", self.provider_offer_ref);
        builder.fieldOptionalRef("world_port", self.world_port_ref);
        builder.fieldOptionalRef("morphism_or_pipeline", self.morphism_or_pipeline_ref);
        for (self.blocker_refs) |ref| builder.fieldRef("blocker", ref);
        builder.fieldBytes("summary", self.summary);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refForBoundaryNormalizationStep(self);
    }
};

pub const BoundaryNormalizationTrace = struct {
    label: []const u8,
    trace_fingerprint: u64,
    root_program_ref: Ref,
    closure_certificate_ref: Ref,
    rewrite_steps: []const BoundaryNormalizationRewriteStep = &.{},
    eliminated_redex_refs: []const Ref = &.{},
    residual_world_port_refs: []const Ref = &.{},
    unsupported_redex_refs: []const Ref = &.{},
    final_program_plan_hash: u64,
    final_normal_form: BoundaryNormalFormKind,
    evidence_dependencies: []const Dependency = &.{},

    pub fn init(options: struct {
        label: []const u8,
        root_program_ref: Ref,
        closure_certificate_ref: Ref,
        rewrite_steps: []const BoundaryNormalizationRewriteStep = &.{},
        eliminated_redex_refs: []const Ref = &.{},
        residual_world_port_refs: []const Ref = &.{},
        unsupported_redex_refs: []const Ref = &.{},
        final_program_plan_hash: u64,
        final_normal_form: BoundaryNormalFormKind,
        evidence_dependencies: []const Dependency = &.{},
    }) @This() {
        var trace = @This(){
            .label = options.label,
            .trace_fingerprint = 0,
            .root_program_ref = options.root_program_ref,
            .closure_certificate_ref = options.closure_certificate_ref,
            .rewrite_steps = options.rewrite_steps,
            .eliminated_redex_refs = options.eliminated_redex_refs,
            .residual_world_port_refs = options.residual_world_port_refs,
            .unsupported_redex_refs = options.unsupported_redex_refs,
            .final_program_plan_hash = options.final_program_plan_hash,
            .final_normal_form = options.final_normal_form,
            .evidence_dependencies = options.evidence_dependencies,
        };
        trace.trace_fingerprint = trace.computeFingerprint();
        return trace;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_normalization_trace);
        builder.fieldBytes("label", self.label);
        builder.fieldRef("root_program", self.root_program_ref);
        builder.fieldRef("closure_certificate", self.closure_certificate_ref);
        for (self.rewrite_steps) |step| builder.fieldRef("rewrite_step", step.evidenceRef());
        for (self.eliminated_redex_refs) |ref| builder.fieldRef("eliminated_redex", ref);
        for (self.residual_world_port_refs) |ref| builder.fieldRef("residual_world_port", ref);
        for (self.unsupported_redex_refs) |ref| builder.fieldRef("unsupported_redex", ref);
        builder.fieldU64("final_program_plan_hash", self.final_program_plan_hash);
        builder.fieldBytes("final_normal_form", @tagName(self.final_normal_form));
        writeCanonicalDependencies(&builder, self.evidence_dependencies);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refForBoundaryNormalizationTrace(self);
    }
};

pub const BoundaryNormalizationCertificate = struct {
    certificate_format_version: u32 = 1,
    label: []const u8,
    certificate_fingerprint: u64,
    closure_certificate_ref: Ref,
    target_policy_fingerprint: u64,
    normalization_trace_ref: Ref,
    final_program_plan_hash: u64,
    source_map_ref: Ref,
    trace_map_ref: Ref,
    evidence_map_ref: Ref,
    effect_row_ref: Ref,
    normal_form_ref: Ref,
    world_surface_ref: Ref,
    blocker_refs: []const Ref = &.{},
    evidence_view: CertificateView,
    dependencies: []const Dependency = &.{},

    pub fn init(options: struct {
        label: []const u8,
        closure_certificate_ref: Ref,
        target_policy_fingerprint: u64,
        normalization_trace_ref: Ref,
        final_program_plan_hash: u64,
        source_map_ref: Ref,
        trace_map_ref: Ref,
        evidence_map_ref: Ref,
        effect_row_ref: Ref,
        normal_form_ref: Ref,
        world_surface_ref: Ref,
        blocker_refs: []const Ref = &.{},
        dependencies: []const Dependency = &.{},
    }) @This() {
        var certificate = @This(){
            .label = options.label,
            .certificate_fingerprint = 0,
            .closure_certificate_ref = options.closure_certificate_ref,
            .target_policy_fingerprint = options.target_policy_fingerprint,
            .normalization_trace_ref = options.normalization_trace_ref,
            .final_program_plan_hash = options.final_program_plan_hash,
            .source_map_ref = options.source_map_ref,
            .trace_map_ref = options.trace_map_ref,
            .evidence_map_ref = options.evidence_map_ref,
            .effect_row_ref = options.effect_row_ref,
            .normal_form_ref = options.normal_form_ref,
            .world_surface_ref = options.world_surface_ref,
            .blocker_refs = options.blocker_refs,
            .evidence_view = .{
                .certificate_ref = Ref{ .domain_id = domains.boundary_normalization_certificate.id, .fingerprint = 0 },
                .subject_ref = options.normalization_trace_ref,
                .domain = domains.boundary_normalization_certificate.id,
                .dependencies = options.dependencies,
                .report_fingerprint = options.normalization_trace_ref.fingerprint,
                .policy_fingerprint = options.target_policy_fingerprint,
                .certificate_fingerprint = 0,
                .summary = options.label,
            },
            .dependencies = options.dependencies,
        };
        certificate.certificate_fingerprint = certificate.computeFingerprint();
        certificate.evidence_view.certificate_ref = certificate.evidenceRef();
        certificate.evidence_view.certificate_fingerprint = certificate.certificate_fingerprint;
        return certificate;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_normalization_certificate);
        builder.fieldU32("format_version", self.certificate_format_version);
        builder.fieldBytes("label", self.label);
        builder.fieldRef("closure_certificate", self.closure_certificate_ref);
        builder.fieldU64("target_policy", self.target_policy_fingerprint);
        builder.fieldRef("normalization_trace", self.normalization_trace_ref);
        builder.fieldU64("final_program_plan_hash", self.final_program_plan_hash);
        builder.fieldRef("source_map", self.source_map_ref);
        builder.fieldRef("trace_map", self.trace_map_ref);
        builder.fieldRef("evidence_map", self.evidence_map_ref);
        builder.fieldRef("effect_row", self.effect_row_ref);
        builder.fieldRef("normal_form", self.normal_form_ref);
        builder.fieldRef("world_surface", self.world_surface_ref);
        for (self.blocker_refs) |ref| builder.fieldRef("blocker", ref);
        writeCanonicalDependencies(&builder, self.dependencies);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refForBoundaryNormalizationCertificate(self);
    }

    pub fn check(
        self: @This(),
        policy: BoundaryTargetPolicy,
        trace: BoundaryNormalizationTrace,
        redexes: []const BoundaryNormalizationRedex,
        rules: []const BoundaryNormalizationRewriteRule,
        static_treaty_plans: []const BoundaryStaticTreatyPlan,
        source_map: BoundaryElaborationSourceMap,
        trace_map: BoundaryElaborationTraceMap,
        evidence_map: BoundaryTargetEvidenceMap,
        effect_row: BoundaryElaborationEffectRow,
        normal_form: BoundaryNormalForm,
        world_surface: BoundaryWorldSurface,
        world_ports: []const BoundaryWorldPort,
    ) error{ BoundaryNormalizationCertificateMismatch, BoundaryNormalizationPolicyMismatch, BoundaryNormalizationBlocked }!void {
        if (self.certificate_format_version != domains.boundary_normalization_certificate.format_version.?) return error.BoundaryNormalizationCertificateMismatch;
        if (self.certificate_fingerprint != self.computeFingerprint()) return error.BoundaryNormalizationCertificateMismatch;
        if (!certificateViewsEqual(self.evidence_view, self.evidenceView())) return error.BoundaryNormalizationCertificateMismatch;
        if (self.target_policy_fingerprint != policy.fingerprint()) return error.BoundaryNormalizationPolicyMismatch;
        const normalization_policy = BoundaryNormalizationPolicy.fromTargetPolicy(policy);
        if (!self.normalization_trace_ref.eql(trace.evidenceRef())) return error.BoundaryNormalizationCertificateMismatch;
        if (!normalizationCertificateDependenciesMatch(self.dependencies, trace, source_map, trace_map, evidence_map, effect_row, normal_form, world_surface)) return error.BoundaryNormalizationCertificateMismatch;
        if (!self.closure_certificate_ref.eql(trace.closure_certificate_ref)) return error.BoundaryNormalizationCertificateMismatch;
        if (trace.trace_fingerprint != trace.computeFingerprint()) return error.BoundaryNormalizationCertificateMismatch;
        if (!normalizationTraceDependenciesMatch(trace, source_map, effect_row, normal_form)) return error.BoundaryNormalizationCertificateMismatch;
        for (trace.rewrite_steps) |step| {
            if (step.fingerprint != step.computeFingerprint()) return error.BoundaryNormalizationCertificateMismatch;
        }
        if (redexes.len != trace.rewrite_steps.len) return error.BoundaryNormalizationCertificateMismatch;
        if (rules.len != trace.rewrite_steps.len) return error.BoundaryNormalizationCertificateMismatch;
        if (trace.rewrite_steps.len != source_map.entries.len) return error.BoundaryNormalizationCertificateMismatch;
        if (trace.rewrite_steps.len > normalization_policy.max_rewrite_steps) return error.BoundaryNormalizationPolicyMismatch;
        if (effect_row.nested_provider_depth > normalization_policy.max_nested_provider_depth) return error.BoundaryNormalizationPolicyMismatch;
        for (source_map.entries, trace.rewrite_steps, redexes, rules, 0..) |entry, step, redex, rule, index| {
            if (redex.fingerprint != redex.computeFingerprint()) return error.BoundaryNormalizationCertificateMismatch;
            if (rule.fingerprint != rule.computeFingerprint()) return error.BoundaryNormalizationCertificateMismatch;
            if (step.step_index != index) return error.BoundaryNormalizationCertificateMismatch;
            if (!step.redex_ref.eql(redex.evidenceRef())) return error.BoundaryNormalizationCertificateMismatch;
            if (!step.rewrite_rule_ref.eql(rule.evidenceRef())) return error.BoundaryNormalizationCertificateMismatch;
            if (!normalizationRedexMatchesSourceEntry(redex, entry, static_treaty_plans, trace.root_program_ref, trace.final_program_plan_hash)) return error.BoundaryNormalizationCertificateMismatch;
            if (!normalizationRuleMatchesSourceEntry(rule, entry, static_treaty_plans, trace.root_program_ref)) return error.BoundaryNormalizationCertificateMismatch;
            const semantic_body = normalizationRedexSemanticBodyForSourceEntry(entry, static_treaty_plans) orelse return error.BoundaryNormalizationCertificateMismatch;
            if (!normalizationRouteProofMatchesSourceEntry(entry, semantic_body, static_treaty_plans, world_ports)) return error.BoundaryNormalizationCertificateMismatch;
            if (!normalizationPolicyAllowsRewrite(normalization_policy, rule.kind, semantic_body)) return error.BoundaryNormalizationPolicyMismatch;
            if (!normalizationStepRouteRefsMatch(step, entry, static_treaty_plans)) return error.BoundaryNormalizationCertificateMismatch;
            const expected_builder_fingerprint = boundaryNormalizationRouteLoweringFingerprint(entry, trace.final_program_plan_hash);
            if (step.builder_state_fingerprint == null or step.builder_state_fingerprint.? != expected_builder_fingerprint) return error.BoundaryNormalizationCertificateMismatch;
            if (!std.mem.eql(u8, step.summary, @tagName(rule.kind))) return error.BoundaryNormalizationCertificateMismatch;
            if (!step.source_effect_shape_ref.eql(entry.source_ref)) return error.BoundaryNormalizationCertificateMismatch;
            if (step.input_program_plan_hash != redex.current_program_plan_ref.fingerprint) return error.BoundaryNormalizationCertificateMismatch;
            if (step.output_program_plan_hash != trace.final_program_plan_hash) return error.BoundaryNormalizationCertificateMismatch;
            if (entry.static_treaty_plan_ref) |plan_ref| {
                if (step.selected_static_treaty_plan_ref == null or !step.selected_static_treaty_plan_ref.?.eql(plan_ref)) return error.BoundaryNormalizationCertificateMismatch;
            } else if (step.selected_static_treaty_plan_ref != null) return error.BoundaryNormalizationCertificateMismatch;
            if (entry.provider_program_ref) |program_ref| {
                if (step.provider_program_ref == null or !step.provider_program_ref.?.eql(program_ref)) return error.BoundaryNormalizationCertificateMismatch;
            } else if (step.provider_program_ref != null) return error.BoundaryNormalizationCertificateMismatch;
            if (entry.world_port_ref) |world_port_ref| {
                if (step.world_port_ref == null or !step.world_port_ref.?.eql(world_port_ref)) return error.BoundaryNormalizationCertificateMismatch;
            } else if (step.world_port_ref != null) return error.BoundaryNormalizationCertificateMismatch;
            if (!normalizationBlockerRefsMatchSourceEntry(step.blocker_refs, entry, static_treaty_plans)) return error.BoundaryNormalizationCertificateMismatch;
        }
        if (trace.residual_world_port_refs.len != world_surface.world_port_count) return error.BoundaryNormalizationCertificateMismatch;
        if (trace.residual_world_port_refs.len != effect_row.residual_world_ports) return error.BoundaryNormalizationCertificateMismatch;
        var eliminated_redex_index: usize = 0;
        var unsupported_redex_index: usize = 0;
        for (source_map.entries, trace.rewrite_steps) |entry, step| {
            if (entry.world_port_ref != null) continue;
            if (entry.disposition == .blocked) {
                if (unsupported_redex_index >= trace.unsupported_redex_refs.len) return error.BoundaryNormalizationCertificateMismatch;
                if (!trace.unsupported_redex_refs[unsupported_redex_index].eql(step.redex_ref)) return error.BoundaryNormalizationCertificateMismatch;
                unsupported_redex_index += 1;
                continue;
            }
            if (eliminated_redex_index >= trace.eliminated_redex_refs.len) return error.BoundaryNormalizationCertificateMismatch;
            if (!trace.eliminated_redex_refs[eliminated_redex_index].eql(step.redex_ref)) return error.BoundaryNormalizationCertificateMismatch;
            eliminated_redex_index += 1;
        }
        if (eliminated_redex_index != trace.eliminated_redex_refs.len) return error.BoundaryNormalizationCertificateMismatch;
        if (unsupported_redex_index != trace.unsupported_redex_refs.len) return error.BoundaryNormalizationCertificateMismatch;
        var residual_world_port_index: usize = 0;
        for (source_map.entries) |entry| {
            const world_port_ref = entry.world_port_ref orelse continue;
            if (residual_world_port_index >= trace.residual_world_port_refs.len) return error.BoundaryNormalizationCertificateMismatch;
            if (!trace.residual_world_port_refs[residual_world_port_index].eql(world_port_ref)) return error.BoundaryNormalizationCertificateMismatch;
            residual_world_port_index += 1;
        }
        if (residual_world_port_index != trace.residual_world_port_refs.len) return error.BoundaryNormalizationCertificateMismatch;
        if (source_map.fingerprint != source_map.computeFingerprint()) return error.BoundaryNormalizationCertificateMismatch;
        if (trace_map.fingerprint != trace_map.computeFingerprint()) return error.BoundaryNormalizationCertificateMismatch;
        if (!traceMapMatchesSourceMap(trace_map, source_map)) return error.BoundaryNormalizationCertificateMismatch;
        if (evidence_map.fingerprint != evidence_map.computeFingerprint()) return error.BoundaryNormalizationCertificateMismatch;
        if (effect_row.fingerprint != effect_row.computeFingerprint()) return error.BoundaryNormalizationCertificateMismatch;
        if (!effectRowAliasesMatchCanonicalFields(effect_row)) return error.BoundaryNormalizationCertificateMismatch;
        if (!sourceMapEffectRowCountsMatch(source_map, effect_row)) return error.BoundaryNormalizationCertificateMismatch;
        if (sourceMapBlockedUnsupportedShapeCount(source_map, static_treaty_plans) != effect_row.unsupported_shapes) return error.BoundaryNormalizationCertificateMismatch;
        if (normal_form.fingerprint != normal_form.computeFingerprint()) return error.BoundaryNormalizationCertificateMismatch;
        if (world_surface.surface_fingerprint != world_surface.computeFingerprint()) return error.BoundaryNormalizationCertificateMismatch;
        if (!trace.root_program_ref.eql(effect_row.source_program_ref)) return error.BoundaryNormalizationCertificateMismatch;
        if (!normal_form.closure_certificate_ref.eql(trace.closure_certificate_ref)) return error.BoundaryNormalizationCertificateMismatch;
        if (!normal_form.effect_row_ref.eql(effect_row.evidenceRef())) return error.BoundaryNormalizationCertificateMismatch;
        if (!world_surface.source_map_ref.eql(source_map.evidenceRef())) return error.BoundaryNormalizationCertificateMismatch;
        if (!world_surface.effect_row_ref.eql(effect_row.evidenceRef())) return error.BoundaryNormalizationCertificateMismatch;
        if (!world_surface.residual_program_ref.eql(effect_row.residual_program_ref)) return error.BoundaryNormalizationCertificateMismatch;
        if (!sourceMapResidualRefsMatch(source_map, world_surface.residual_program_ref)) return error.BoundaryNormalizationCertificateMismatch;
        if (self.final_program_plan_hash != trace.final_program_plan_hash) return error.BoundaryNormalizationCertificateMismatch;
        if (self.final_program_plan_hash != world_surface.residual_program_ref.fingerprint) return error.BoundaryNormalizationCertificateMismatch;
        if (self.final_program_plan_hash != effect_row.residual_program_ref.fingerprint) return error.BoundaryNormalizationCertificateMismatch;
        if (!self.source_map_ref.eql(source_map.evidenceRef())) return error.BoundaryNormalizationCertificateMismatch;
        if (!self.trace_map_ref.eql(trace_map.evidenceRef())) return error.BoundaryNormalizationCertificateMismatch;
        if (!self.evidence_map_ref.eql(evidence_map.evidenceRef())) return error.BoundaryNormalizationCertificateMismatch;
        if (!self.effect_row_ref.eql(effect_row.evidenceRef())) return error.BoundaryNormalizationCertificateMismatch;
        if (!self.normal_form_ref.eql(normal_form.evidenceRef())) return error.BoundaryNormalizationCertificateMismatch;
        if (!self.world_surface_ref.eql(world_surface.evidenceRef())) return error.BoundaryNormalizationCertificateMismatch;
        if (trace.final_normal_form != normal_form.kind or normal_form.kind != effect_row.normal_form) return error.BoundaryNormalizationCertificateMismatch;
        if (world_surface.normal_form != normal_form.kind) return error.BoundaryNormalizationCertificateMismatch;
        if (!effectRowSatisfiesNormalForm(effect_row, normal_form)) return error.BoundaryNormalizationCertificateMismatch;
        if (!targetEffectRowMatchesSurfaceNormalForm(effect_row, world_surface.normal_form)) return error.BoundaryNormalizationCertificateMismatch;
        if (world_surface.world_port_count != effect_row.residual_world_ports) return error.BoundaryNormalizationCertificateMismatch;
        if (sourceMapWorldPortCount(source_map) != world_surface.world_port_count) return error.BoundaryNormalizationCertificateMismatch;
        if (world_surface.world_port_count == 0 and world_surface.normal_form == .world_ports_only) return error.BoundaryNormalizationCertificateMismatch;
        if (normal_form.kind == .strict_closed and world_surface.world_port_count != 0) return error.BoundaryNormalizationCertificateMismatch;
        if (!sourceMapBlockerRefsMatchBlockedEntries(source_map, static_treaty_plans, self.blocker_refs)) return error.BoundaryNormalizationCertificateMismatch;
        if (self.blocker_refs.len != effect_row.blockers or self.blocker_refs.len != normal_form.blocker_count) return error.BoundaryNormalizationCertificateMismatch;
        var source_map_blocked = false;
        for (source_map.entries) |entry| {
            if (entry.disposition == .blocked or entry.blocker_ref != null) {
                source_map_blocked = true;
                break;
            }
        }
        if (policy.fail_on_unsupported_instruction and
            (self.blocker_refs.len != 0 or
                trace.unsupported_redex_refs.len != 0 or
                source_map_blocked or
                effect_row.blockers != 0 or
                effect_row.unsupported_shapes != 0 or
                normal_form.blocker_count != 0))
            return error.BoundaryNormalizationBlocked;
    }

    pub fn evidenceView(self: @This()) CertificateView {
        return .{
            .certificate_ref = self.evidenceRef(),
            .subject_ref = self.normalization_trace_ref,
            .domain = domains.boundary_normalization_certificate.id,
            .dependencies = self.dependencies,
            .report_fingerprint = self.normalization_trace_ref.fingerprint,
            .policy_fingerprint = self.target_policy_fingerprint,
            .certificate_fingerprint = self.certificate_fingerprint,
            .summary = self.label,
        };
    }
};

pub const BoundaryTargetCertificate = struct {
    certificate_format_version: u32 = domains.boundary_target_certificate.format_version.?,
    certificate_fingerprint: u64,
    target_label: []const u8,
    elaboration_certificate_ref: Ref,
    residual_program_ref: Ref,
    world_surface_ref: Ref,
    port_table_ref: Ref,
    value_table_ref: Ref,
    dispatch_table_ref: Ref,
    profile_ref: Ref,
    replay_key_recipe_ref: Ref,
    evidence_map_ref: Ref,
    trace_map_ref: ?Ref = null,
    normalization_certificate_ref: ?Ref = null,
    policy_fingerprint: u64,
    dependencies: []const Dependency = &.{},
    summary: []const u8 = "certified boundary target",

    pub fn init(options: struct {
        target_label: []const u8,
        policy: BoundaryTargetPolicy,
        elaboration_certificate_ref: Ref,
        residual_program_ref: Ref,
        world_surface_ref: Ref,
        port_table_ref: Ref,
        value_table_ref: Ref,
        dispatch_table_ref: Ref,
        profile_ref: Ref,
        replay_key_recipe_ref: Ref,
        evidence_map_ref: Ref,
        trace_map_ref: ?Ref = null,
        normalization_certificate_ref: ?Ref = null,
        dependencies: []const Dependency = &.{},
        summary: []const u8 = "certified boundary target",
    }) @This() {
        var certificate = @This(){
            .certificate_fingerprint = 0,
            .target_label = options.target_label,
            .elaboration_certificate_ref = options.elaboration_certificate_ref,
            .residual_program_ref = options.residual_program_ref,
            .world_surface_ref = options.world_surface_ref,
            .port_table_ref = options.port_table_ref,
            .value_table_ref = options.value_table_ref,
            .dispatch_table_ref = options.dispatch_table_ref,
            .profile_ref = options.profile_ref,
            .replay_key_recipe_ref = options.replay_key_recipe_ref,
            .evidence_map_ref = options.evidence_map_ref,
            .trace_map_ref = options.trace_map_ref,
            .normalization_certificate_ref = options.normalization_certificate_ref,
            .policy_fingerprint = options.policy.fingerprint(),
            .dependencies = options.dependencies,
            .summary = options.summary,
        };
        certificate.certificate_fingerprint = certificate.computeFingerprint();
        return certificate;
    }

    pub fn computeFingerprint(self: @This()) u64 {
        var builder = FingerprintBuilder.init(domains.boundary_target_certificate);
        builder.fieldU32("format_version", self.certificate_format_version);
        builder.fieldBytes("target_label", self.target_label);
        builder.fieldRef("elaboration_certificate", self.elaboration_certificate_ref);
        builder.fieldRef("residual_program", self.residual_program_ref);
        builder.fieldRef("world_surface", self.world_surface_ref);
        builder.fieldRef("port_table", self.port_table_ref);
        builder.fieldRef("value_table", self.value_table_ref);
        builder.fieldRef("dispatch_table", self.dispatch_table_ref);
        builder.fieldRef("profile", self.profile_ref);
        builder.fieldRef("replay_key_recipe", self.replay_key_recipe_ref);
        builder.fieldRef("evidence_map", self.evidence_map_ref);
        builder.fieldOptionalRef("trace_map", self.trace_map_ref);
        builder.fieldOptionalRef("normalization_certificate", self.normalization_certificate_ref);
        builder.fieldU64("policy", self.policy_fingerprint);
        writeCanonicalDependencies(&builder, self.dependencies);
        builder.fieldBytes("summary", self.summary);
        return builder.finish();
    }

    pub fn evidenceRef(self: @This()) Ref {
        return refForBoundaryTargetCertificate(self);
    }

    pub fn check(
        self: @This(),
        policy: BoundaryTargetPolicy,
        elaboration_certificate: BoundaryElaborationCertificate,
        world_surface: BoundaryWorldSurface,
        source_map: BoundaryElaborationSourceMap,
        effect_row: BoundaryElaborationEffectRow,
        trace_map: BoundaryElaborationTraceMap,
        normal_form: BoundaryNormalForm,
        world_ports: []const BoundaryWorldPort,
        port_table: BoundaryWorldPortTable,
        value_table: BoundaryWorldValueTable,
        dispatch_table: BoundaryWorldDispatchTable,
        profile: BoundarySurfaceProfile,
        replay_key_recipe: BoundaryReplayKeyRecipe,
        evidence_map: BoundaryTargetEvidenceMap,
        normalization_certificate: BoundaryNormalizationCertificate,
        normalization_trace: BoundaryNormalizationTrace,
        normalization_redexes: []const BoundaryNormalizationRedex,
        normalization_rules: []const BoundaryNormalizationRewriteRule,
        static_treaty_plans: []const BoundaryStaticTreatyPlan,
    ) error{ BoundaryTargetCertificateMismatch, BoundaryTargetPolicyMismatch, BoundaryTargetSurfaceRejected }!void {
        if (self.certificate_format_version != domains.boundary_target_certificate.format_version.?) return error.BoundaryTargetCertificateMismatch;
        if (self.certificate_fingerprint != self.computeFingerprint()) return error.BoundaryTargetCertificateMismatch;
        if (self.policy_fingerprint != policy.fingerprint()) return error.BoundaryTargetPolicyMismatch;
        if (!targetPolicyEmitsRequiredArtifacts(policy)) return error.BoundaryTargetPolicyMismatch;
        if (self.elaboration_certificate_ref.domain_id != domains.boundary_elaboration_certificate.id) return error.BoundaryTargetCertificateMismatch;
        const expected_elaboration_policy = boundaryTargetElaborationPolicy(policy);
        if (elaboration_certificate.certificate_format_version != domains.boundary_elaboration_certificate.format_version.?) return error.BoundaryTargetCertificateMismatch;
        if (elaboration_certificate.certificate_fingerprint != elaboration_certificate.computeFingerprint()) return error.BoundaryTargetCertificateMismatch;
        if (!policySummariesEqual(elaboration_certificate.policy_summary, expected_elaboration_policy.policySummary())) return error.BoundaryTargetPolicyMismatch;
        if (elaboration_certificate.elaboration_policy_fingerprint != expected_elaboration_policy.fingerprint()) return error.BoundaryTargetPolicyMismatch;
        elaboration_certificate.check(
            expected_elaboration_policy,
            elaboration_certificate.closure_graph_ref,
            elaboration_certificate.closure_report_ref,
            elaboration_certificate.closure_certificate_ref,
            source_map,
            effect_row,
            trace_map,
            normal_form,
            static_treaty_plans,
            world_ports,
        ) catch |err| switch (err) {
            error.BoundaryElaborationPolicyMismatch => return error.BoundaryTargetPolicyMismatch,
            else => return error.BoundaryTargetCertificateMismatch,
        };
        if (!self.elaboration_certificate_ref.eql(elaboration_certificate.evidenceRef())) return error.BoundaryTargetCertificateMismatch;
        if (!elaboration_certificate.residual_program_ref.eql(self.residual_program_ref)) return error.BoundaryTargetCertificateMismatch;
        if (!elaboration_certificate.source_map_ref.eql(source_map.evidenceRef())) return error.BoundaryTargetCertificateMismatch;
        if (!elaboration_certificate.effect_row_ref.eql(effect_row.evidenceRef())) return error.BoundaryTargetCertificateMismatch;
        if (elaboration_certificate.normal_form_ref.domain_id != domains.boundary_normal_form.id) return error.BoundaryTargetCertificateMismatch;
        if (!elaboration_certificate.normal_form_ref.eql(normal_form.evidenceRef())) return error.BoundaryTargetCertificateMismatch;
        if (elaboration_certificate.normal_form != world_surface.normal_form) return error.BoundaryTargetCertificateMismatch;
        if (elaboration_certificate.normal_form != effect_row.normal_form) return error.BoundaryTargetCertificateMismatch;
        if (self.residual_program_ref.domain_id != domains.program_plan.id) return error.BoundaryTargetCertificateMismatch;
        if (world_surface.surface_format_version != domains.boundary_world_surface.format_version.?) return error.BoundaryTargetCertificateMismatch;
        if (world_surface.surface_fingerprint != world_surface.computeFingerprint()) return error.BoundaryTargetCertificateMismatch;
        if (source_map.fingerprint != source_map.computeFingerprint()) return error.BoundaryTargetCertificateMismatch;
        if (effect_row.fingerprint != effect_row.computeFingerprint()) return error.BoundaryTargetCertificateMismatch;
        if (trace_map.fingerprint != trace_map.computeFingerprint()) return error.BoundaryTargetCertificateMismatch;
        if (port_table.fingerprint != port_table.computeFingerprint()) return error.BoundaryTargetCertificateMismatch;
        if (value_table.fingerprint != value_table.computeFingerprint()) return error.BoundaryTargetCertificateMismatch;
        if (dispatch_table.fingerprint != dispatch_table.computeFingerprint()) return error.BoundaryTargetCertificateMismatch;
        if (profile.fingerprint != profile.computeFingerprint()) return error.BoundaryTargetCertificateMismatch;
        if (replay_key_recipe.fingerprint != replay_key_recipe.computeFingerprint()) return error.BoundaryTargetCertificateMismatch;
        if (evidence_map.fingerprint != evidence_map.computeFingerprint()) return error.BoundaryTargetCertificateMismatch;
        const trace_map_ref = self.trace_map_ref orelse return error.BoundaryTargetCertificateMismatch;
        if (trace_map_ref.domain_id != domains.boundary_elaboration_trace_map.id) return error.BoundaryTargetCertificateMismatch;
        if (!trace_map_ref.eql(trace_map.evidenceRef())) return error.BoundaryTargetCertificateMismatch;
        if (!trace_map_ref.eql(elaboration_certificate.trace_map_ref orelse return error.BoundaryTargetCertificateMismatch)) return error.BoundaryTargetCertificateMismatch;
        if (!traceMapMatchesSourceMap(trace_map, source_map)) return error.BoundaryTargetCertificateMismatch;
        const normalization_ref = self.normalization_certificate_ref orelse return error.BoundaryTargetCertificateMismatch;
        if (!targetCertificateDependenciesMatch(self.dependencies, world_surface, port_table, value_table, dispatch_table, profile, replay_key_recipe, self.residual_program_ref, self.elaboration_certificate_ref, trace_map_ref, normalization_ref)) return error.BoundaryTargetCertificateMismatch;
        if (!targetEvidenceMapDependenciesMatch(evidence_map.dependencies, world_surface, port_table, value_table, dispatch_table, profile, replay_key_recipe, self.residual_program_ref, self.elaboration_certificate_ref, trace_map_ref)) return error.BoundaryTargetCertificateMismatch;
        if (!self.world_surface_ref.eql(world_surface.evidenceRef())) return error.BoundaryTargetCertificateMismatch;
        if (!self.port_table_ref.eql(port_table.evidenceRef())) return error.BoundaryTargetCertificateMismatch;
        if (!self.value_table_ref.eql(value_table.evidenceRef())) return error.BoundaryTargetCertificateMismatch;
        if (!self.dispatch_table_ref.eql(dispatch_table.evidenceRef())) return error.BoundaryTargetCertificateMismatch;
        if (!self.profile_ref.eql(profile.evidenceRef())) return error.BoundaryTargetCertificateMismatch;
        if (!self.replay_key_recipe_ref.eql(replay_key_recipe.evidenceRef())) return error.BoundaryTargetCertificateMismatch;
        if (!self.evidence_map_ref.eql(evidence_map.evidenceRef())) return error.BoundaryTargetCertificateMismatch;
        if (normalization_ref.domain_id != domains.boundary_normalization_certificate.id) return error.BoundaryTargetCertificateMismatch;
        if (!normalization_ref.eql(normalization_certificate.evidenceRef())) return error.BoundaryTargetCertificateMismatch;
        if (normalization_certificate.certificate_format_version != domains.boundary_normalization_certificate.format_version.?) return error.BoundaryTargetCertificateMismatch;
        if (normalization_certificate.certificate_fingerprint != normalization_certificate.computeFingerprint()) return error.BoundaryTargetCertificateMismatch;
        if (normalization_certificate.target_policy_fingerprint != policy.fingerprint()) return error.BoundaryTargetPolicyMismatch;
        if (!normalization_certificate.closure_certificate_ref.eql(elaboration_certificate.closure_certificate_ref)) return error.BoundaryTargetCertificateMismatch;
        if (!normalization_trace.closure_certificate_ref.eql(elaboration_certificate.closure_certificate_ref)) return error.BoundaryTargetCertificateMismatch;
        if (!normalization_trace.root_program_ref.eql(elaboration_certificate.source_program_ref)) return error.BoundaryTargetCertificateMismatch;
        normalization_certificate.check(policy, normalization_trace, normalization_redexes, normalization_rules, static_treaty_plans, source_map, trace_map, evidence_map, effect_row, normal_form, world_surface, world_ports) catch |err| switch (err) {
            error.BoundaryNormalizationPolicyMismatch => return error.BoundaryTargetPolicyMismatch,
            error.BoundaryNormalizationBlocked => return error.BoundaryTargetSurfaceRejected,
            else => return error.BoundaryTargetCertificateMismatch,
        };
        if (!self.elaboration_certificate_ref.eql(world_surface.elaboration_certificate_ref)) return error.BoundaryTargetCertificateMismatch;
        if (!self.residual_program_ref.eql(world_surface.residual_program_ref)) return error.BoundaryTargetCertificateMismatch;
        if (world_surface.elaboration_certificate_ref.domain_id != domains.boundary_elaboration_certificate.id) return error.BoundaryTargetCertificateMismatch;
        if (world_surface.residual_program_ref.domain_id != domains.program_plan.id) return error.BoundaryTargetCertificateMismatch;
        if (world_surface.source_map_ref.domain_id != domains.boundary_elaboration_source_map.id) return error.BoundaryTargetCertificateMismatch;
        if (world_surface.effect_row_ref.domain_id != domains.boundary_elaboration_effect_row.id) return error.BoundaryTargetCertificateMismatch;
        if (!world_surface.source_map_ref.eql(source_map.evidenceRef())) return error.BoundaryTargetCertificateMismatch;
        if (!world_surface.effect_row_ref.eql(effect_row.evidenceRef())) return error.BoundaryTargetCertificateMismatch;
        if (!effect_row.residual_program_ref.eql(world_surface.residual_program_ref)) return error.BoundaryTargetCertificateMismatch;
        if (!sourceMapResidualRefsMatch(source_map, world_surface.residual_program_ref)) return error.BoundaryTargetCertificateMismatch;
        if (!targetEffectRowMatchesSurfaceNormalForm(effect_row, world_surface.normal_form)) return error.BoundaryTargetCertificateMismatch;
        if (!targetPortTableMatchesSourceMap(policy, source_map, effect_row, port_table, static_treaty_plans)) return error.BoundaryTargetCertificateMismatch;
        if (!world_surface.port_table_ref.eql(port_table.evidenceRef())) return error.BoundaryTargetCertificateMismatch;
        if (!world_surface.value_table_ref.eql(value_table.evidenceRef())) return error.BoundaryTargetCertificateMismatch;
        if (!world_surface.dispatch_table_ref.eql(dispatch_table.evidenceRef())) return error.BoundaryTargetCertificateMismatch;
        if (!world_surface.profile_ref.eql(profile.evidenceRef())) return error.BoundaryTargetCertificateMismatch;
        if (!world_surface.replay_key_recipe_ref.eql(replay_key_recipe.evidenceRef())) return error.BoundaryTargetCertificateMismatch;
        if (!replay_key_recipe.surface_ref.eql(world_surface.replayScopeRef())) return error.BoundaryTargetCertificateMismatch;
        if (!targetReplayKeyRecipeConforms(replay_key_recipe)) return error.BoundaryTargetCertificateMismatch;
        if (!targetTablesConform(port_table, value_table, dispatch_table, profile)) return error.BoundaryTargetCertificateMismatch;
        if (world_surface.world_port_count != profile.world_port_count) return error.BoundaryTargetCertificateMismatch;
        if (world_surface.world_port_count != port_table.entries.len) return error.BoundaryTargetCertificateMismatch;
        if (world_surface.world_port_count == 0 and world_surface.normal_form == .world_ports_only) return error.BoundaryTargetCertificateMismatch;
        if (world_surface.world_port_count != 0 and world_surface.normal_form == .strict_closed) return error.BoundaryTargetCertificateMismatch;
        if (world_surface.normal_form == .partial_with_blockers and policy.fail_on_unsupported_instruction) return error.BoundaryTargetSurfaceRejected;
        if (!policy.allow_world_ports and profile.world_port_count != 0) return error.BoundaryTargetSurfaceRejected;
        if (policy.require_no_search_hot_path and !profile.no_search_hot_path) return error.BoundaryTargetSurfaceRejected;
        const surface_bounded = boundaryTargetSurfaceBounded(policy, profile.world_port_count, profile.value_descriptor_count, profile.dispatch_entry_count);
        if (profile.bounded != surface_bounded) return error.BoundaryTargetCertificateMismatch;
        if (policy.require_bounded_surface and !profile.bounded and policy.fail_on_unbounded_world_port_when_bounded_required) return error.BoundaryTargetSurfaceRejected;
    }

    pub fn evidenceView(self: @This()) CertificateView {
        return .{
            .certificate_ref = self.evidenceRef(),
            .subject_ref = self.world_surface_ref,
            .domain = domains.boundary_target_certificate.id,
            .dependencies = self.dependencies,
            .report_fingerprint = self.world_surface_ref.fingerprint,
            .policy_fingerprint = self.policy_fingerprint,
            .certificate_fingerprint = self.certificate_fingerprint,
            .summary = self.summary,
        };
    }
};

fn normalizationRedexMatchesSourceEntry(
    redex: BoundaryNormalizationRedex,
    entry: BoundaryElaborationSourceMap.Entry,
    static_treaty_plans: []const BoundaryStaticTreatyPlan,
    root_program_ref: Ref,
    final_program_plan_hash: u64,
) bool {
    const residual_program_ref = refFor(domains.program_plan, final_program_plan_hash, .{});
    const current_program_ref = normalizationRedexCurrentProgramRefForSourceEntry(entry, static_treaty_plans, root_program_ref);
    const semantic_body = normalizationRedexSemanticBodyForSourceEntry(entry, static_treaty_plans) orelse return false;
    return std.mem.eql(u8, redex.label, entry.label) and
        redex.source_effect_shape_ref.eql(entry.source_ref) and
        redex.origin == normalizationRedexOriginForProgramRef(current_program_ref, root_program_ref) and
        redex.current_program_plan_ref.eql(current_program_ref) and
        redex.kind == normalizationRedexKindForSourceEntry(entry, static_treaty_plans) and
        redex.semantic_body == semantic_body and
        redex.expected_lowering_kind == normalizationRewriteRuleKindForSourceEntry(entry, static_treaty_plans, root_program_ref) and
        optionalRefValuesEqual(redex.selected_static_treaty_plan_ref, entry.static_treaty_plan_ref) and
        normalizationRedexCoordinatesMatchSourceEntry(redex.coordinates, entry) and
        dependenciesContainRef(redex.evidence_dependencies, .source, entry.source_ref) and
        dependenciesContainSubjectRef(redex.evidence_dependencies, .residual_program, residual_program_ref);
}

fn normalizationRedexSemanticBodyForSourceEntry(entry: BoundaryElaborationSourceMap.Entry, static_treaty_plans: []const BoundaryStaticTreatyPlan) ?SemanticBody {
    const plan_ref = entry.static_treaty_plan_ref orelse return .unknown;
    const plan = staticTreatyPlanForRef(static_treaty_plans, plan_ref) orelse return null;
    return boundaryStaticTreatyPlanRouteSemanticBody(plan);
}

fn normalizationRouteProofMatchesSourceEntry(entry: BoundaryElaborationSourceMap.Entry, semantic_body: SemanticBody, static_treaty_plans: []const BoundaryStaticTreatyPlan, world_ports: []const BoundaryWorldPort) bool {
    const expected_disposition: ?BoundaryElaborationSourceMap.Disposition = switch (semantic_body) {
        .boundary_program => .provider_program_linked,
        .declarative => .preserved,
        .residualized_program => .residualized,
        .pipeline => .pipeline_adapter,
        .host_intrinsic,
        .unknown,
        .kernel_primitive,
        => null,
    };
    if (entry.disposition == .world_port_lowered) {
        return normalizationWorldPortRouteProofMatchesSourceEntry(entry, semantic_body, static_treaty_plans, world_ports);
    }
    if (expected_disposition == null or entry.disposition != expected_disposition.?) {
        return entry.disposition == .blocked;
    }
    const plan_ref = entry.static_treaty_plan_ref orelse return false;
    const plan = staticTreatyPlanForRef(static_treaty_plans, plan_ref) orelse return false;
    if (!staticTreatyPlanIntegrityMatches(plan)) return false;
    if (boundaryStaticTreatyPlanRouteSemanticBody(plan) != semantic_body) return false;
    if (!staticTreatyPlanHasElaborationRouteProof(plan, semantic_body)) return false;
    if (entry.residual_ref) |residual_ref| {
        if (staticTreatyPlanNeedsResidualDependencyInCertificate(plan) and !staticTreatyPlanHasDependencyRef(plan, .residual_program, residual_ref)) return false;
        if (!staticTreatyPlanResidualDependenciesMatch(plan, residual_ref)) return false;
    }
    if (entry.disposition == .provider_program_linked) {
        const provider_program_ref = entry.provider_program_ref orelse return false;
        return optionalRefValuesEqual(plan.selected_provider_program_ref, provider_program_ref);
    }
    return entry.provider_program_ref == null;
}

fn normalizationWorldPortRouteProofMatchesSourceEntry(entry: BoundaryElaborationSourceMap.Entry, semantic_body: SemanticBody, static_treaty_plans: []const BoundaryStaticTreatyPlan, world_ports: []const BoundaryWorldPort) bool {
    const world_port_ref = entry.world_port_ref orelse return false;
    const world_port = worldPortForRef(world_ports, world_port_ref) orelse return false;
    if (entry.provider_program_ref != null) return false;
    const plan_ref = entry.static_treaty_plan_ref orelse return false;
    const plan = staticTreatyPlanForRef(static_treaty_plans, plan_ref) orelse return false;
    if (!staticTreatyPlanIntegrityMatches(plan)) return false;
    if (boundaryStaticTreatyPlanRouteSemanticBody(plan) != semantic_body) return false;
    return switch (semantic_body) {
        .declarative,
        .residualized_program,
        .pipeline,
        => staticTreatyPlanHasElaborationRouteProof(plan, semantic_body) and boundaryWorldPortMatchesShapeOnlyPlan(world_port, plan),
        .host_intrinsic => staticTreatyPlanCanLowerToWorldPort(plan) and boundaryWorldPortMatchesIntrinsicPlan(world_port, plan),
        .boundary_program,
        .unknown,
        .kernel_primitive,
        => false,
    };
}

fn boundaryWorldPortMatchesShapeOnlyPlan(port: BoundaryWorldPort, plan: BoundaryStaticTreatyPlan) bool {
    if (port.exposed_intrinsic_ref != null) return false;
    const shape = boundaryStaticTreatyPlanWorldPortShape(plan) orelse return false;
    if (shape.kind != .operation) return false;
    return boundaryWorldPortMatchesShape(port, shape);
}

fn boundaryWorldPortMatchesIntrinsicPlan(port: BoundaryWorldPort, plan: BoundaryStaticTreatyPlan) bool {
    const intrinsic_ref = staticTreatyPlanWorldPortIntrinsicRef(plan) orelse return false;
    const exposed_ref = port.exposed_intrinsic_ref orelse return false;
    if (!refSubjectsEqual(exposed_ref, intrinsic_ref)) return false;
    const shape = boundaryStaticTreatyPlanWorldPortShape(plan) orelse return false;
    if (shape.kind != .operation) return false;
    return boundaryWorldPortMatchesShape(port, shape);
}

fn boundaryStaticTreatyPlanWorldPortShape(plan: BoundaryStaticTreatyPlan) ?BoundaryEffectShape {
    if (plan.selected_morphism_ref != null) return plan.morphismTargetShapeWitness();
    return plan.source_shape;
}

pub fn boundaryNormalizationRouteLoweringFingerprint(entry: BoundaryElaborationSourceMap.Entry, output_hash: u64) u64 {
    var builder = FingerprintBuilder.init(domains.boundary_route_lowering);
    builder.fieldRef("source", entry.source_ref);
    builder.fieldOptionalRef("static_treaty_plan", entry.static_treaty_plan_ref);
    builder.fieldOptionalRef("provider_program", entry.provider_program_ref);
    builder.fieldOptionalRef("world_port", entry.world_port_ref);
    builder.fieldBytes("disposition", @tagName(entry.disposition));
    builder.fieldU64("output_program_plan_hash", output_hash);
    return builder.finish();
}

fn normalizationRuleMatchesSourceEntry(
    rule: BoundaryNormalizationRewriteRule,
    entry: BoundaryElaborationSourceMap.Entry,
    static_treaty_plans: []const BoundaryStaticTreatyPlan,
    root_program_ref: Ref,
) bool {
    if (!std.mem.eql(u8, rule.label, entry.label)) return false;
    if (rule.kind != normalizationRewriteRuleKindForSourceEntry(entry, static_treaty_plans, root_program_ref)) return false;
    if (rule.produced_source_map_entries != 1) return false;
    if (rule.produced_trace_map_entries != 1) return false;
    if (rule.produced_effect_row_entries != 1) return false;
    if (!dependenciesContainRef(rule.evidence_dependencies, .source, entry.source_ref)) return false;
    return normalizationBlockerRefsMatchSourceEntry(rule.blocker_refs, entry, static_treaty_plans);
}

fn normalizationPolicyAllowsRewrite(policy: BoundaryNormalizationPolicy, kind: BoundaryNormalizationRewriteRule.Kind, semantic_body: SemanticBody) bool {
    return switch (kind) {
        .root_copy => true,
        .already_normal => normalizationPolicyAllowsSemanticBody(policy, semantic_body),
        .provider_program_call => policy.allow_program_provider_rewrites,
        .nested_provider_program_call => policy.allow_program_provider_rewrites and policy.allow_nested_provider_rewrites,
        .residual_world_port => policy.allow_world_port_residualization and normalizationPolicyAllowsSemanticBody(policy, semantic_body),
        .residualized_morphism => policy.allow_residualized_morphism_rewrites,
        .pipeline_adapter => policy.allow_pipeline_rewrites,
        .unsupported => true,
    };
}

fn normalizationPolicyAllowsSemanticBody(policy: BoundaryNormalizationPolicy, semantic_body: SemanticBody) bool {
    return switch (semantic_body) {
        .boundary_program => policy.allow_program_provider_rewrites,
        .declarative => policy.allow_declarative_morphism_rewrites,
        .residualized_program => policy.allow_residualized_morphism_rewrites,
        .pipeline => policy.allow_pipeline_rewrites,
        .host_intrinsic => !policy.reject_host_intrinsic_internal_routes,
        .unknown => !policy.reject_unknown_semantic_bodies,
        .kernel_primitive => true,
    };
}

fn normalizationStepRouteRefsMatch(
    step: BoundaryNormalizationRewriteStep,
    entry: BoundaryElaborationSourceMap.Entry,
    static_treaty_plans: []const BoundaryStaticTreatyPlan,
) bool {
    const plan_ref = entry.static_treaty_plan_ref orelse {
        return step.provider_offer_ref == null and step.morphism_or_pipeline_ref == null;
    };
    const plan = staticTreatyPlanForRef(static_treaty_plans, plan_ref) orelse return false;
    return optionalRefValuesEqual(step.provider_offer_ref, plan.selected_provider_offer_ref) and
        optionalRefValuesEqual(step.morphism_or_pipeline_ref, plan.selected_morphism_ref);
}

fn normalizationTraceDependenciesMatch(
    trace: BoundaryNormalizationTrace,
    source_map: BoundaryElaborationSourceMap,
    effect_row: BoundaryElaborationEffectRow,
    normal_form: BoundaryNormalForm,
) bool {
    const residual_program_ref = refFor(domains.program_plan, trace.final_program_plan_hash, .{});
    return trace.evidence_dependencies.len == 5 and
        dependenciesContainRef(trace.evidence_dependencies, .closure_certificate, trace.closure_certificate_ref) and
        dependenciesContainSubjectRef(trace.evidence_dependencies, .residual_program, residual_program_ref) and
        dependenciesContainRef(trace.evidence_dependencies, .elaboration_source_map, source_map.evidenceRef()) and
        dependenciesContainRef(trace.evidence_dependencies, .elaboration_effect_row, effect_row.evidenceRef()) and
        dependenciesContainRef(trace.evidence_dependencies, .normal_form, normal_form.evidenceRef());
}

fn normalizationRedexCoordinatesMatchSourceEntry(coordinates: BoundaryNormalizationCoordinates, entry: BoundaryElaborationSourceMap.Entry) bool {
    return coordinates.function_index == 0 and
        coordinates.block_index == 0 and
        coordinates.instruction_index == entry.source_site_index and
        coordinates.site_index == entry.source_site_index;
}

fn normalizationBlockerRefsMatchSourceEntry(refs: []const Ref, entry: BoundaryElaborationSourceMap.Entry, static_treaty_plans: []const BoundaryStaticTreatyPlan) bool {
    if (entry.disposition != .blocked) return refs.len == 0;
    if (entry.blocker_ref) |blocker_ref| {
        if (entry.static_treaty_plan_ref != null) return false;
        return refs.len == 1 and refs[0].eql(blocker_ref);
    }
    const plan_ref = entry.static_treaty_plan_ref orelse return false;
    const plan = staticTreatyPlanForRef(static_treaty_plans, plan_ref) orelse return false;
    if (refs.len != plan.blockers.len) return false;
    for (refs, plan.blockers) |ref, blocker| {
        if (!ref.eql(refForBoundaryClosureBlocker(blocker.toEvidenceBlocker()))) return false;
    }
    return true;
}

fn normalizationCertificateDependenciesMatch(
    dependencies: []const Dependency,
    trace: BoundaryNormalizationTrace,
    source_map: BoundaryElaborationSourceMap,
    trace_map: BoundaryElaborationTraceMap,
    evidence_map: BoundaryTargetEvidenceMap,
    effect_row: BoundaryElaborationEffectRow,
    normal_form: BoundaryNormalForm,
    world_surface: BoundaryWorldSurface,
) bool {
    return dependencies.len == 7 and
        dependenciesContainRef(dependencies, .normalization_trace, trace.evidenceRef()) and
        dependenciesContainRef(dependencies, .elaboration_source_map, source_map.evidenceRef()) and
        dependenciesContainRef(dependencies, .elaboration_trace_map, trace_map.evidenceRef()) and
        dependenciesContainRef(dependencies, .target_evidence_map, evidence_map.evidenceRef()) and
        dependenciesContainRef(dependencies, .elaboration_effect_row, effect_row.evidenceRef()) and
        dependenciesContainRef(dependencies, .normal_form, normal_form.evidenceRef()) and
        dependenciesContainRef(dependencies, .world_surface, world_surface.evidenceRef());
}

fn normalizationRedexKindForSourceEntry(entry: BoundaryElaborationSourceMap.Entry, static_treaty_plans: []const BoundaryStaticTreatyPlan) BoundaryNormalizationRedex.Kind {
    if (entry.world_port_ref != null) return .world_port_site;
    if (entry.static_treaty_plan_ref) |plan_ref| {
        if (staticTreatyPlanForRef(static_treaty_plans, plan_ref)) |plan| return switch (plan.source_shape.kind) {
            .after => .after_site,
            .operation => .operation_site,
            .world_port => .world_port_site,
            .root_program,
            .provider_program,
            .intrinsic,
            .unknown,
            => .protocol_operation_shape,
        };
    }
    if (entry.disposition == .blocked) return .unsupported;
    if (entry.source_ref.kind_tag) |kind_tag| {
        if (std.mem.eql(u8, kind_tag, "after")) return .after_site;
        if (std.mem.eql(u8, kind_tag, "world_port")) return .world_port_site;
        if (std.mem.eql(u8, kind_tag, "operation")) return .operation_site;
    }
    return .operation_site;
}

fn normalizationRewriteRuleKindForSourceEntry(
    entry: BoundaryElaborationSourceMap.Entry,
    static_treaty_plans: []const BoundaryStaticTreatyPlan,
    root_program_ref: Ref,
) BoundaryNormalizationRewriteRule.Kind {
    return switch (entry.disposition) {
        .preserved => .already_normal,
        .provider_program_linked => if (normalizationRedexOriginForSourceEntry(entry, static_treaty_plans, root_program_ref) == .nested_provider_program) .nested_provider_program_call else .provider_program_call,
        .world_port_lowered => .residual_world_port,
        .residualized => .residualized_morphism,
        .pipeline_adapter => .pipeline_adapter,
        .blocked => .unsupported,
    };
}

fn normalizationRedexOriginForProgramRef(current_program_ref: Ref, root_program_ref: Ref) BoundaryNormalizationRedex.Origin {
    if (!current_program_ref.eql(root_program_ref)) return .nested_provider_program;
    return .root_program;
}

fn normalizationRedexOriginForSourceEntry(entry: BoundaryElaborationSourceMap.Entry, static_treaty_plans: []const BoundaryStaticTreatyPlan, root_program_ref: Ref) BoundaryNormalizationRedex.Origin {
    return normalizationRedexOriginForProgramRef(
        normalizationRedexCurrentProgramRefForSourceEntry(entry, static_treaty_plans, root_program_ref),
        root_program_ref,
    );
}

fn normalizationRedexCurrentProgramRefForSourceEntry(entry: BoundaryElaborationSourceMap.Entry, static_treaty_plans: []const BoundaryStaticTreatyPlan, root_program_ref: Ref) Ref {
    if (entry.static_treaty_plan_ref) |plan_ref| {
        if (staticTreatyPlanForRef(static_treaty_plans, plan_ref)) |plan| {
            if (plan.source_shape.plan_hash != 0) {
                return refFor(domains.program_plan, plan.source_shape.plan_hash, .{ .label = plan.source_shape.program_label });
            }
        }
    }
    return root_program_ref;
}

fn targetEvidenceMapDependenciesMatch(
    dependencies: []const Dependency,
    world_surface: BoundaryWorldSurface,
    port_table: BoundaryWorldPortTable,
    value_table: BoundaryWorldValueTable,
    dispatch_table: BoundaryWorldDispatchTable,
    profile: BoundarySurfaceProfile,
    replay_key_recipe: BoundaryReplayKeyRecipe,
    residual_program_ref: Ref,
    elaboration_certificate_ref: Ref,
    trace_map_ref: Ref,
) bool {
    return dependencies.len == 11 and
        targetBaseDependenciesContain(dependencies, world_surface, port_table, value_table, dispatch_table, profile, replay_key_recipe, residual_program_ref, elaboration_certificate_ref, trace_map_ref);
}

fn targetBaseDependenciesContain(
    dependencies: []const Dependency,
    world_surface: BoundaryWorldSurface,
    port_table: BoundaryWorldPortTable,
    value_table: BoundaryWorldValueTable,
    dispatch_table: BoundaryWorldDispatchTable,
    profile: BoundarySurfaceProfile,
    replay_key_recipe: BoundaryReplayKeyRecipe,
    residual_program_ref: Ref,
    elaboration_certificate_ref: Ref,
    trace_map_ref: Ref,
) bool {
    return dependenciesContainRef(dependencies, .elaboration_certificate, elaboration_certificate_ref) and
        dependenciesContainRef(dependencies, .elaboration_source_map, world_surface.source_map_ref) and
        dependenciesContainRef(dependencies, .elaboration_effect_row, world_surface.effect_row_ref) and
        dependenciesContainRef(dependencies, .elaboration_trace_map, trace_map_ref) and
        dependenciesContainRef(dependencies, .world_surface, world_surface.evidenceRef()) and
        dependenciesContainRef(dependencies, .world_port_table, port_table.evidenceRef()) and
        dependenciesContainRef(dependencies, .world_value_table, value_table.evidenceRef()) and
        dependenciesContainRef(dependencies, .world_dispatch_table, dispatch_table.evidenceRef()) and
        dependenciesContainRef(dependencies, .surface_profile, profile.evidenceRef()) and
        dependenciesContainRef(dependencies, .replay_key_recipe, replay_key_recipe.evidenceRef()) and
        dependenciesContainRef(dependencies, .residual_program, residual_program_ref);
}

fn targetCertificateDependenciesMatch(
    dependencies: []const Dependency,
    world_surface: BoundaryWorldSurface,
    port_table: BoundaryWorldPortTable,
    value_table: BoundaryWorldValueTable,
    dispatch_table: BoundaryWorldDispatchTable,
    profile: BoundarySurfaceProfile,
    replay_key_recipe: BoundaryReplayKeyRecipe,
    residual_program_ref: Ref,
    elaboration_certificate_ref: Ref,
    trace_map_ref: Ref,
    normalization_certificate_ref: Ref,
) bool {
    return dependencies.len == 12 and
        targetBaseDependenciesContain(dependencies, world_surface, port_table, value_table, dispatch_table, profile, replay_key_recipe, residual_program_ref, elaboration_certificate_ref, trace_map_ref) and
        dependenciesContainRef(dependencies, .normalization_certificate, normalization_certificate_ref);
}

fn targetPolicyEmitsRequiredArtifacts(policy: BoundaryTargetPolicy) bool {
    return policy.emit_source_map and
        policy.emit_trace_map and
        policy.emit_evidence_map and
        policy.emit_world_surface;
}

fn boundaryTargetSurfaceBounded(policy: BoundaryTargetPolicy, world_port_count: usize, value_descriptor_count: usize, dispatch_entry_count: usize) bool {
    return world_port_count <= policy.max_world_ports and
        value_descriptor_count <= policy.max_value_descriptors and
        dispatch_entry_count <= policy.max_dispatch_entries;
}

fn targetReplayKeyRecipeConforms(recipe: BoundaryReplayKeyRecipe) bool {
    const expected = [_][]const u8{
        "world_surface_scope_fingerprint",
        "world_port_id",
        "request_fingerprint",
        "response_fingerprint",
    };
    if (recipe.components.len != expected.len) return false;
    for (recipe.components, expected) |actual, required| {
        if (!std.mem.eql(u8, actual, required)) return false;
    }
    return true;
}

fn targetEffectRowMatchesSurfaceNormalForm(effect_row: BoundaryElaborationEffectRow, normal_form: BoundaryNormalFormKind) bool {
    if (effect_row.normal_form != normal_form) return false;
    if (!effectRowAliasesMatchCanonicalFields(effect_row)) return false;
    if (effect_row.closed_effect_shapes > effect_row.source_effect_shapes) return false;
    if (effect_row.world_ports > effect_row.source_effect_shapes - effect_row.closed_effect_shapes) return false;
    if (effect_row.residual_world_ports != effect_row.world_ports) return false;
    return switch (normal_form) {
        .strict_closed => effect_row.source_effect_shapes == effect_row.closed_effect_shapes and
            effect_row.world_ports == 0 and
            effect_row.unsupported_shapes == 0 and
            effect_row.blockers == 0,
        .world_ports_only => effect_row.world_ports != 0 and
            effect_row.source_effect_shapes == effect_row.closed_effect_shapes + effect_row.world_ports and
            effect_row.unsupported_shapes == 0 and
            effect_row.blockers == 0,
        .partial_with_blockers => effect_row.closed_effect_shapes + effect_row.world_ports <= effect_row.source_effect_shapes and
            effect_row.blockers != 0,
    };
}

fn targetPortTableMatchesSourceMap(
    policy: BoundaryTargetPolicy,
    source_map: BoundaryElaborationSourceMap,
    effect_row: BoundaryElaborationEffectRow,
    port_table: BoundaryWorldPortTable,
    static_treaty_plans: []const BoundaryStaticTreatyPlan,
) bool {
    const world_port_entries = sourceMapWorldPortCount(source_map);
    if (effect_row.world_ports != world_port_entries) return false;
    if (effect_row.residual_world_ports != world_port_entries) return false;
    if (port_table.entries.len != world_port_entries) return false;
    for (port_table.entries) |entry| {
        if (sourceMapPortTableEntryCount(policy, source_map, entry, static_treaty_plans) != 1) return false;
    }
    for (source_map.entries) |entry| {
        if (entry.world_port_ref == null) continue;
        if (sourceMapPortTableEntryCovered(policy, port_table, entry, static_treaty_plans) != 1) return false;
    }
    return true;
}

fn sourceMapPortTableEntryCount(
    policy: BoundaryTargetPolicy,
    source_map: BoundaryElaborationSourceMap,
    port_entry: BoundaryWorldPortTable.Entry,
    static_treaty_plans: []const BoundaryStaticTreatyPlan,
) usize {
    var count: usize = 0;
    for (source_map.entries) |entry| {
        if (sourceMapEntryMatchesPortTableEntry(policy, entry, port_entry, static_treaty_plans)) count += 1;
    }
    return count;
}

fn sourceMapPortTableEntryCovered(
    policy: BoundaryTargetPolicy,
    port_table: BoundaryWorldPortTable,
    source_entry: BoundaryElaborationSourceMap.Entry,
    static_treaty_plans: []const BoundaryStaticTreatyPlan,
) usize {
    var count: usize = 0;
    for (port_table.entries) |entry| {
        if (sourceMapEntryMatchesPortTableEntry(policy, source_entry, entry, static_treaty_plans)) count += 1;
    }
    return count;
}

fn sourceMapEntryMatchesPortTableEntry(
    policy: BoundaryTargetPolicy,
    source_entry: BoundaryElaborationSourceMap.Entry,
    port_entry: BoundaryWorldPortTable.Entry,
    static_treaty_plans: []const BoundaryStaticTreatyPlan,
) bool {
    if (source_entry.disposition != .world_port_lowered) return false;
    const world_port_ref = source_entry.world_port_ref orelse return false;
    const residual_site_index = source_entry.residual_site_index orelse return false;
    return world_port_ref.eql(port_entry.world_port_ref) and
        source_entry.source_ref.eql(port_entry.source_ref) and
        residual_site_index == port_entry.residual_site_index and
        targetPortTableEntryMatchesSchemaWitness(policy, source_entry, port_entry, static_treaty_plans);
}

fn targetPortTableEntryMatchesSchemaWitness(
    policy: BoundaryTargetPolicy,
    source_entry: BoundaryElaborationSourceMap.Entry,
    port_entry: BoundaryWorldPortTable.Entry,
    static_treaty_plans: []const BoundaryStaticTreatyPlan,
) bool {
    if (!policy.fail_on_schema_mismatch) return true;
    const plan_ref = source_entry.static_treaty_plan_ref orelse return false;
    const plan = staticTreatyPlanForRef(static_treaty_plans, plan_ref) orelse return false;
    if (!staticTreatyPlanIntegrityMatches(plan)) return false;
    const shape = if (plan.selected_morphism_ref != null)
        plan.morphismTargetShapeWitness() orelse return false
    else
        plan.source_shape;
    if (shape.kind != .operation) return false;
    if (policy.preserve_source_coordinates) {
        const expected_site_index = shape.site_index orelse return false;
        if (plan.selected_morphism_ref != null) {
            if (expected_site_index != port_entry.residual_site_index) return false;
        } else if (source_entry.source_site_index != expected_site_index) return false;
    }
    if (shape.protocol_label.len == 0 or !std.mem.eql(u8, shape.protocol_label, port_entry.protocol_label)) return false;
    if (shape.name.len != 0 and !std.mem.eql(u8, shape.name, port_entry.op_name)) return false;
    if (shape.mode.len == 0 or !std.mem.eql(u8, shape.mode, port_entry.mode)) return false;
    if (policy.preserve_semantic_labels) {
        const expected_semantic_label = shape.semantic_label orelse return false;
        const actual_semantic_label = port_entry.semantic_label orelse return false;
        if (!std.mem.eql(u8, expected_semantic_label, actual_semantic_label)) return false;
    } else if (port_entry.semantic_label != null) {
        return false;
    }
    if (shape.protocol_op_fingerprint) |protocol_op_fingerprint| {
        if (protocol_op_fingerprint != port_entry.residual_site_fingerprint) return false;
    } else if (shape.site_fingerprint == null) return false;
    if (shape.site_fingerprint) |site_fingerprint| {
        if (site_fingerprint != port_entry.residual_site_fingerprint) return false;
    }
    const expected_payload_ref = shape.value_ref orelse return false;
    if (!expected_payload_ref.eql(port_entry.payload_ref)) return false;
    if (shape.expected_resume_ref) |expected_resume_ref| {
        if (!expected_resume_ref.eql(port_entry.resume_ref)) return false;
    } else if (!std.mem.eql(u8, shape.mode, "abort")) {
        return false;
    }
    if (shape.result_ref) |expected_result_ref| {
        if (!expected_result_ref.eql(port_entry.result_ref)) return false;
    } else if (!std.mem.eql(u8, shape.mode, "transform")) {
        return false;
    }
    return true;
}

fn staticTreatyPlanIntegrityMatches(plan: BoundaryStaticTreatyPlan) bool {
    if (plan.source_shape.fingerprint != plan.source_shape.computeFingerprint()) return false;
    if (plan.selected_morphism_target_shape) |shape| {
        if (plan.selected_morphism_target_response_ref_count > plan.selected_morphism_target_response_refs.len) return false;
        var target_shape = shape;
        target_shape.desired_response_refs = plan.selected_morphism_target_response_refs[0..plan.selected_morphism_target_response_ref_count];
        if (target_shape.fingerprint != target_shape.computeFingerprint()) return false;
        if (plan.selected_morphism_target_shape_ref) |target_ref| {
            if (!target_ref.eql(target_shape.evidenceRef())) return false;
        }
    } else if (plan.selected_morphism_target_shape_ref != null) {
        return false;
    }
    return plan.fingerprint == plan.computeFingerprint();
}

fn targetTablesConform(
    port_table: BoundaryWorldPortTable,
    value_table: BoundaryWorldValueTable,
    dispatch_table: BoundaryWorldDispatchTable,
    profile: BoundarySurfaceProfile,
) bool {
    if (profile.world_port_count != port_table.entries.len) return false;
    if (profile.value_descriptor_count != value_table.entries.len) return false;
    if (profile.dispatch_entry_count != dispatch_table.entries.len) return false;
    if (dispatch_table.entries.len < port_table.entries.len) return false;
    for (value_table.entries, 0..) |value, value_index| {
        if (value_index > std.math.maxInt(u32)) return false;
        if (value.value_id != @as(u32, @intCast(value_index))) return false;
        if (@as(usize, @intCast(value.world_port_id)) >= port_table.entries.len) return false;
    }
    if (profile.no_search_hot_path and !targetDispatchTableDense(dispatch_table)) return false;
    for (dispatch_table.entries, 0..) |dispatch, index| {
        if (profile.no_search_hot_path and dispatch.residual_site_index != index) return false;
        if (dispatch.world_port_id == BoundaryWorldDispatchTable.missing_world_port_id) {
            if (dispatch.residual_site_fingerprint != 0) return false;
            for (port_table.entries) |port| {
                if (port.residual_site_index == dispatch.residual_site_index) return false;
            }
            continue;
        }
        const port_index: usize = @intCast(dispatch.world_port_id);
        if (port_index >= port_table.entries.len) return false;
        const port = port_table.entries[port_index];
        if (dispatch.residual_site_index != port.residual_site_index) return false;
        if (dispatch.residual_site_fingerprint != port.residual_site_fingerprint) return false;
    }
    for (port_table.entries, 0..) |port, index| {
        if (index >= BoundaryWorldDispatchTable.missing_world_port_id) return false;
        if (port.world_port_id != @as(u32, @intCast(index))) return false;
        if (port.world_port_ref.domain_id != domains.boundary_world_port.id) return false;
        var dispatch_count: usize = 0;
        dispatch_loop: for (dispatch_table.entries) |dispatch| {
            if (dispatch.residual_site_index != port.residual_site_index) continue :dispatch_loop;
            if (dispatch.residual_site_fingerprint != port.residual_site_fingerprint) return false;
            if (dispatch.world_port_id != port.world_port_id) return false;
            dispatch_count += 1;
        }
        if (dispatch_count != 1) return false;
        var has_payload = false;
        var has_resume = false;
        var has_result = false;
        value_loop: for (value_table.entries, 0..) |value, value_index| {
            if (value_index > std.math.maxInt(u32)) return false;
            if (value.value_id != @as(u32, @intCast(value_index))) return false;
            const value_port_index: usize = @intCast(value.world_port_id);
            if (value_port_index >= port_table.entries.len) return false;
            if (value.world_port_id != port.world_port_id) continue :value_loop;
            switch (value.kind) {
                .payload => {
                    if (has_payload) return false;
                    if (!value.ref.eql(port.payload_ref)) return false;
                    has_payload = true;
                },
                .@"resume" => {
                    if (has_resume) return false;
                    if (!value.ref.eql(port.resume_ref)) return false;
                    has_resume = true;
                },
                .result => {
                    if (has_result) return false;
                    if (!value.ref.eql(port.result_ref)) return false;
                    has_result = true;
                },
            }
        }
        if (!has_payload or !has_resume or !has_result) return false;
    }
    return true;
}

fn targetDispatchTableDense(dispatch_table: BoundaryWorldDispatchTable) bool {
    for (dispatch_table.entries, 0..) |entry, index| {
        if (entry.residual_site_index != index) return false;
    }
    return true;
}

fn traceMapMatchesSourceMap(trace_map: BoundaryElaborationTraceMap, source_map: BoundaryElaborationSourceMap) bool {
    if (trace_map.entries.len != source_map.entries.len) return false;
    for (source_map.entries) |source_entry| {
        const expected_residual_ref = source_entry.world_port_ref orelse (source_entry.residual_ref orelse source_entry.source_ref);
        if (traceEntryCount(trace_map, source_entry.source_ref, expected_residual_ref, source_entry.label) != sourceMapTraceTargetCount(source_map, source_entry.source_ref, expected_residual_ref, source_entry.label)) return false;
    }
    return true;
}

fn traceEntryCount(trace_map: BoundaryElaborationTraceMap, source_ref: Ref, residual_ref: Ref, trace_label: []const u8) usize {
    var count: usize = 0;
    for (trace_map.entries) |entry| {
        if (entry.source_ref.eql(source_ref) and
            entry.residual_ref.eql(residual_ref) and
            std.mem.eql(u8, entry.trace_label, trace_label))
        {
            count += 1;
        }
    }
    return count;
}

fn sourceMapTraceTargetCount(source_map: BoundaryElaborationSourceMap, source_ref: Ref, residual_ref: Ref, trace_label: []const u8) usize {
    var count: usize = 0;
    for (source_map.entries) |entry| {
        const expected_residual_ref = entry.world_port_ref orelse (entry.residual_ref orelse entry.source_ref);
        if (entry.source_ref.eql(source_ref) and
            expected_residual_ref.eql(residual_ref) and
            std.mem.eql(u8, entry.label, trace_label))
        {
            count += 1;
        }
    }
    return count;
}

fn summaryCountsMatchEffectRow(summary: BoundaryElaborationCertificate.SummaryCounts, effect_row: BoundaryElaborationEffectRow) bool {
    return summary.root_effect_shapes == effect_row.source_effect_shapes and
        summary.internal_routes_elaborated == effect_row.closed_effect_shapes and
        summary.provider_programs_linked == effect_row.linked_provider_programs and
        summary.nested_provider_shapes_linked == effect_row.nested_provider_shapes_linked and
        summary.nested_provider_depth == effect_row.nested_provider_depth and
        summary.morphism_routes_elaborated == effect_row.residualized_routes and
        summary.pipeline_routes_elaborated == effect_row.pipeline_routes and
        summary.world_ports_emitted == effect_row.world_ports and
        summary.blockers == effect_row.blockers;
}

fn effectRowAliasesMatchCanonicalFields(effect_row: BoundaryElaborationEffectRow) bool {
    return effect_row.eliminated_source_shapes == effect_row.closed_effect_shapes and
        effect_row.elaborated_provider_routes == effect_row.provider_program_links and
        effect_row.elaborated_morphism_routes == effect_row.residualized_routes and
        effect_row.strict_closed == (effect_row.normal_form == .strict_closed) and
        effect_row.world_ports_only == (effect_row.normal_form == .world_ports_only);
}

fn sourceMapEffectRowCountsMatch(source_map: BoundaryElaborationSourceMap, effect_row: BoundaryElaborationEffectRow) bool {
    return effect_row.source_effect_shapes == sourceMapEffectShapeEntryCount(source_map) and
        effect_row.closed_effect_shapes == sourceMapClosedEffectShapeCount(source_map) and
        effect_row.world_ports == sourceMapWorldPortCount(source_map) and
        effect_row.residual_world_ports == sourceMapWorldPortCount(source_map) and
        effect_row.provider_program_links == sourceMapProviderProgramCount(source_map) and
        effect_row.linked_provider_programs == sourceMapProviderProgramUniqueCount(source_map) and
        effect_row.residualized_routes == sourceMapDispositionCount(source_map, .residualized) and
        effect_row.pipeline_routes == sourceMapDispositionCount(source_map, .pipeline_adapter);
}

fn certificateViewsEqual(left: CertificateView, right: CertificateView) bool {
    return left.certificate_ref.eql(right.certificate_ref) and
        left.subject_ref.eql(right.subject_ref) and
        left.domain == right.domain and
        dependenciesEqual(left.dependencies, right.dependencies) and
        left.report_fingerprint == right.report_fingerprint and
        optionalRefValuesEqual(left.policy_ref, right.policy_ref) and
        left.policy_fingerprint == right.policy_fingerprint and
        left.certificate_fingerprint == right.certificate_fingerprint and
        std.mem.eql(u8, left.summary, right.summary);
}

fn dependenciesEqual(left: []const Dependency, right: []const Dependency) bool {
    if (left.len != right.len) return false;
    for (left, right) |left_dependency, right_dependency| {
        if (left_dependency.role != right_dependency.role or !left_dependency.ref.eql(right_dependency.ref)) return false;
    }
    return true;
}

fn dependencyRefsMatchDependencies(refs: []const Ref, dependencies: []const Dependency) bool {
    if (refs.len != dependencies.len) return false;
    for (dependencies, 0..) |dependency, index| {
        if (!refs[index].eql(dependency.ref)) return false;
    }
    return true;
}

fn dependenciesContainRef(dependencies: []const Dependency, role: Role, ref: Ref) bool {
    for (dependencies) |dependency| {
        if (dependency.role == role and dependency.ref.eql(ref)) return true;
    }
    return false;
}

fn dependenciesContainSubjectRef(dependencies: []const Dependency, role: Role, ref: Ref) bool {
    for (dependencies) |dependency| {
        if (dependency.role == role and refSubjectsEqual(dependency.ref, ref)) return true;
    }
    return false;
}

fn effectRowSatisfiesNormalForm(effect_row: BoundaryElaborationEffectRow, normal_form: BoundaryNormalForm) bool {
    if (effect_row.closed_effect_shapes > effect_row.source_effect_shapes) return false;
    if (effect_row.world_ports > effect_row.source_effect_shapes - effect_row.closed_effect_shapes) return false;
    if (effect_row.residual_world_ports != effect_row.world_ports) return false;
    if (effect_row.blockers != normal_form.blocker_count) return false;
    return switch (normal_form.kind) {
        .strict_closed => effect_row.source_effect_shapes == effect_row.closed_effect_shapes and
            effect_row.world_ports == 0 and
            effect_row.unsupported_shapes == 0 and
            effect_row.blockers == 0 and
            normal_form.blocker_count == 0,
        .world_ports_only => effect_row.world_ports != 0 and
            effect_row.source_effect_shapes == effect_row.closed_effect_shapes + effect_row.world_ports and
            effect_row.unsupported_shapes == 0 and
            effect_row.blockers == 0 and
            normal_form.blocker_count == 0,
        .partial_with_blockers => effect_row.closed_effect_shapes + effect_row.world_ports <= effect_row.source_effect_shapes and
            effect_row.blockers != 0 and
            normal_form.blocker_count != 0,
    };
}

fn sourceMapWorldPortCount(source_map: BoundaryElaborationSourceMap) usize {
    var count: usize = 0;
    for (source_map.entries) |entry| {
        if (entry.world_port_ref != null) count += 1;
    }
    return count;
}

fn sourceMapClosedEffectShapeCount(source_map: BoundaryElaborationSourceMap) usize {
    if (source_map.fingerprint != source_map.computeFingerprint()) return std.math.maxInt(usize);
    var count: usize = 0;
    for (source_map.entries) |entry| {
        switch (entry.disposition) {
            .preserved,
            .provider_program_linked,
            .residualized,
            .pipeline_adapter,
            => count += 1,
            .world_port_lowered,
            .blocked,
            => {},
        }
    }
    return count;
}

fn sourceMapResidualRefsMatch(source_map: BoundaryElaborationSourceMap, residual_ref: Ref) bool {
    for (source_map.entries) |entry| {
        const entry_residual_ref = entry.residual_ref orelse {
            switch (entry.disposition) {
                .preserved,
                .provider_program_linked,
                .residualized,
                .pipeline_adapter,
                .world_port_lowered,
                => return false,
                .blocked,
                => continue,
            }
        };
        if (!entry_residual_ref.eql(residual_ref)) return false;
    }
    return true;
}

fn sourceMapWorldPortRefsMatch(source_map: BoundaryElaborationSourceMap, refs: []const Ref) bool {
    if (sourceMapWorldPortCount(source_map) != refs.len) return false;
    for (source_map.entries) |entry| {
        const world_port_ref = entry.world_port_ref orelse continue;
        if (sourceMapWorldPortRefCount(source_map, world_port_ref) != refSliceCount(refs, world_port_ref)) return false;
    }
    for (refs) |ref| {
        if (sourceMapWorldPortRefCount(source_map, ref) == 0) return false;
    }
    return true;
}

fn sourceMapWorldPortRefCount(source_map: BoundaryElaborationSourceMap, needle: Ref) usize {
    var count: usize = 0;
    for (source_map.entries) |entry| {
        if (entry.world_port_ref) |world_port_ref| {
            if (world_port_ref.eql(needle)) count += 1;
        }
    }
    return count;
}

fn sourceMapWorldPortSitesValid(source_map: BoundaryElaborationSourceMap) bool {
    for (source_map.entries) |entry| {
        switch (entry.disposition) {
            .world_port_lowered => {
                if (entry.world_port_ref == null) return false;
                const residual_site_index = entry.residual_site_index orelse return false;
                if (sourceMapResidualSiteIndexCount(source_map, residual_site_index) != 1) return false;
            },
            .preserved,
            .provider_program_linked,
            .residualized,
            .pipeline_adapter,
            .blocked,
            => {
                if (entry.world_port_ref != null) return false;
                if (entry.residual_site_index != null) return false;
            },
        }
    }
    return true;
}

fn sourceMapResidualSiteIndexCount(source_map: BoundaryElaborationSourceMap, needle: usize) usize {
    var count: usize = 0;
    for (source_map.entries) |entry| {
        if (entry.residual_site_index) |residual_site_index| {
            if (residual_site_index == needle) count += 1;
        }
    }
    return count;
}

fn sourceMapDispositionCount(source_map: BoundaryElaborationSourceMap, disposition: BoundaryElaborationSourceMap.Disposition) usize {
    var count: usize = 0;
    for (source_map.entries) |entry| {
        if (entry.disposition == disposition) count += 1;
    }
    return count;
}

fn sourceMapClosedRoutesHaveStaticPlanRefs(source_map: BoundaryElaborationSourceMap) bool {
    for (source_map.entries) |entry| {
        switch (entry.disposition) {
            .preserved,
            .provider_program_linked,
            .residualized,
            .pipeline_adapter,
            => if (entry.static_treaty_plan_ref == null) return false,
            .world_port_lowered,
            .blocked,
            => {},
        }
    }
    return true;
}

fn sourceMapProviderProgramCount(source_map: BoundaryElaborationSourceMap) usize {
    var count: usize = 0;
    for (source_map.entries) |entry| {
        if (entry.provider_program_ref != null) count += 1;
    }
    return count;
}

fn sourceMapProviderProgramUniqueCount(source_map: BoundaryElaborationSourceMap) usize {
    var count: usize = 0;
    for (source_map.entries, 0..) |entry, index| {
        const provider_program_ref = entry.provider_program_ref orelse continue;
        var first = true;
        for (source_map.entries[0..index]) |prior| {
            if (prior.provider_program_ref) |prior_ref| {
                if (prior_ref.eql(provider_program_ref)) {
                    first = false;
                    break;
                }
            }
        }
        if (first) count += 1;
    }
    return count;
}

fn sourceMapProviderProgramRefsMatch(source_map: BoundaryElaborationSourceMap, refs: []const Ref) bool {
    if (!refSliceUnique(refs)) return false;
    if (sourceMapProviderProgramUniqueCount(source_map) != refs.len) return false;
    for (source_map.entries) |entry| {
        const provider_program_ref = entry.provider_program_ref orelse continue;
        if (refSliceCount(refs, provider_program_ref) == 0) return false;
    }
    for (refs) |ref| {
        if (sourceMapProviderProgramRefCount(source_map, ref) == 0) return false;
    }
    return true;
}

fn sourceMapProviderProgramRefCount(source_map: BoundaryElaborationSourceMap, needle: Ref) usize {
    var count: usize = 0;
    for (source_map.entries) |entry| {
        if (entry.provider_program_ref) |provider_program_ref| {
            if (provider_program_ref.eql(needle)) count += 1;
        }
    }
    return count;
}

fn sourceMapStaticTreatyPlanCount(source_map: BoundaryElaborationSourceMap) usize {
    var count: usize = 0;
    for (source_map.entries) |entry| {
        if (entry.static_treaty_plan_ref != null) count += 1;
    }
    return count;
}

fn sourceMapStaticTreatyPlanRefsMatch(source_map: BoundaryElaborationSourceMap, refs: []const Ref) bool {
    if (sourceMapStaticTreatyPlanCount(source_map) != refs.len) return false;
    for (source_map.entries) |entry| {
        const static_treaty_plan_ref = entry.static_treaty_plan_ref orelse continue;
        if (sourceMapStaticTreatyPlanRefCount(source_map, static_treaty_plan_ref) != refSliceCount(refs, static_treaty_plan_ref)) return false;
    }
    for (refs) |ref| {
        if (sourceMapStaticTreatyPlanRefCount(source_map, ref) == 0) return false;
    }
    return true;
}

fn sourceMapStaticTreatyPlanSourcesMatch(policy: BoundaryElaborationPolicy, source_program_ref: Ref, inlined_provider_program_refs: []const Ref, dependencies: []const Dependency, source_map: BoundaryElaborationSourceMap, plans: []const BoundaryStaticTreatyPlan, world_ports: []const BoundaryWorldPort) bool {
    if (sourceMapStaticTreatyPlanCount(source_map) != plans.len) return false;
    for (plans) |plan| {
        if (plan.fingerprint != plan.computeFingerprint()) return false;
        if (sourceMapStaticTreatyPlanRefCount(source_map, plan.evidenceRef()) != 1) return false;
    }
    for (source_map.entries) |entry| {
        const static_treaty_plan_ref = entry.static_treaty_plan_ref orelse continue;
        const plan = staticTreatyPlanForRef(plans, static_treaty_plan_ref) orelse return false;
        if (plan.source_shape.fingerprint != plan.source_shape.computeFingerprint()) return false;
        if (!staticTreatyPlanSourceMatchesEntry(source_program_ref, inlined_provider_program_refs, entry, plan)) return false;
        const expected_source_ref = staticTreatyPlanSourceMapEntrySourceRef(entry, plan) orelse return false;
        if (!entry.source_ref.eql(expected_source_ref)) return false;
        if (entry.source_site_index != plan.source_shape.site_index) return false;
        if (!sourceMapEntryMatchesStaticTreatyPlan(policy, dependencies, entry, plan, world_ports)) return false;
    }
    return true;
}

fn staticTreatyPlanSourceMatchesEntry(source_program_ref: Ref, inlined_provider_program_refs: []const Ref, entry: BoundaryElaborationSourceMap.Entry, plan: BoundaryStaticTreatyPlan) bool {
    _ = entry;
    if (plan.source_shape.plan_hash == 0) return true;
    if (effectShapeMatchesProgramRef(source_program_ref, plan.source_shape)) return true;
    for (inlined_provider_program_refs) |provider_program_ref| {
        if (effectShapeMatchesProgramRef(provider_program_ref, plan.source_shape)) return true;
    }
    return false;
}

fn effectShapeMatchesProgramRef(program_ref: Ref, shape: BoundaryEffectShape) bool {
    if (program_ref.domain_id != domains.program_plan.id) return false;
    const program_label = program_ref.label orelse return false;
    if (!std.mem.eql(u8, program_label, shape.program_label)) return false;
    return shape.plan_hash == 0 or program_ref.fingerprint == shape.plan_hash;
}

fn staticTreatyPlanSourceMapEntrySourceRef(entry: BoundaryElaborationSourceMap.Entry, plan: BoundaryStaticTreatyPlan) ?Ref {
    if (entry.disposition == .world_port_lowered and plan.selected_morphism_ref != null) {
        return plan.selected_morphism_target_shape_ref;
    }
    return plan.source_shape.evidenceRef();
}

fn sourceMapBlockerRefsMatchBlockedEntries(source_map: BoundaryElaborationSourceMap, plans: []const BoundaryStaticTreatyPlan, refs: []const Ref) bool {
    if (sourceMapBlockedEntryBlockerRefCount(source_map, plans) != refs.len) return false;
    for (source_map.entries) |entry| {
        if (entry.disposition != .blocked) continue;
        const static_treaty_plan_ref = entry.static_treaty_plan_ref orelse {
            const blocker_ref = entry.blocker_ref orelse return false;
            if (sourceMapDirectBlockerRefCountFor(source_map, blocker_ref) != refSliceCount(refs, blocker_ref)) return false;
            continue;
        };
        if (entry.blocker_ref != null) return false;
        const plan = staticTreatyPlanForRef(plans, static_treaty_plan_ref) orelse return false;
        for (plan.blockers) |blocker| {
            const blocker_ref = refForBoundaryClosureBlocker(blocker.toEvidenceBlocker());
            if (sourceMapStaticTreatyPlanBlockerRefCountFor(source_map, plans, blocker_ref) != refSliceCount(refs, blocker_ref)) return false;
        }
    }
    for (refs) |ref| {
        if (sourceMapBlockedEntryBlockerRefCountFor(source_map, plans, ref) == 0) return false;
    }
    return true;
}

fn sourceMapBlockedEntryCount(source_map: BoundaryElaborationSourceMap) usize {
    var count: usize = 0;
    for (source_map.entries) |entry| {
        if (entry.disposition == .blocked) count += 1;
    }
    return count;
}

fn sourceMapEffectShapeEntryCount(source_map: BoundaryElaborationSourceMap) usize {
    var count: usize = 0;
    for (source_map.entries, 0..) |entry, index| {
        if (!sourceMapEntryRepresentsEffectShape(entry)) continue;
        if (sourceMapEntryIsDirectBlocker(entry)) {
            if (sourceMapHasPlannedSourceRef(source_map, entry.source_ref)) continue;
            if (sourceMapPriorDirectBlockerHasSourceRef(source_map.entries[0..index], entry.source_ref)) continue;
        }
        count += 1;
    }
    return count;
}

fn sourceMapEntryIsDirectBlocker(entry: BoundaryElaborationSourceMap.Entry) bool {
    return entry.disposition == .blocked and entry.static_treaty_plan_ref == null;
}

fn sourceMapHasPlannedSourceRef(source_map: BoundaryElaborationSourceMap, source_ref: Ref) bool {
    for (source_map.entries) |entry| {
        if (sourceMapEntryIsDirectBlocker(entry)) continue;
        if (sourceMapEntryRepresentsEffectShape(entry) and entry.source_ref.eql(source_ref)) return true;
    }
    return false;
}

fn sourceMapPriorDirectBlockerHasSourceRef(entries: []const BoundaryElaborationSourceMap.Entry, source_ref: Ref) bool {
    for (entries) |entry| {
        if (sourceMapEntryIsDirectBlocker(entry) and entry.source_ref.eql(source_ref)) return true;
    }
    return false;
}

fn sourceMapBlockedUnsupportedShapeCount(source_map: BoundaryElaborationSourceMap, plans: []const BoundaryStaticTreatyPlan) usize {
    var count: usize = 0;
    for (source_map.entries) |entry| {
        if (sourceMapEntryIsUnsupportedShapeBlocker(entry, plans)) count += 1;
    }
    return count;
}

fn sourceMapEntryIsUnsupportedShapeBlocker(entry: BoundaryElaborationSourceMap.Entry, plans: []const BoundaryStaticTreatyPlan) bool {
    if (entry.disposition != .blocked) return false;
    if (!sourceMapEntryRepresentsEffectShape(entry)) return false;
    if (entry.static_treaty_plan_ref) |plan_ref| {
        const plan = staticTreatyPlanForRef(plans, plan_ref) orelse return false;
        return staticTreatyPlanHasUnsupportedShapeBlocker(plan);
    }
    if (entry.blocker_ref) |blocker_ref| return blockerRefCountsUnsupported(blocker_ref);
    return blockerNameCountsUnsupported(entry.label);
}

fn sourceMapEntryRepresentsEffectShape(entry: BoundaryElaborationSourceMap.Entry) bool {
    if (entry.disposition != .blocked) return true;
    if (entry.static_treaty_plan_ref != null) return true;
    return entry.source_ref.domain_id == domains.boundary_effect_shape.id;
}

fn sourceMapStaticTreatyPlanBlockerRefCount(source_map: BoundaryElaborationSourceMap, plans: []const BoundaryStaticTreatyPlan) usize {
    var count: usize = 0;
    for (source_map.entries) |entry| {
        if (entry.disposition != .blocked) continue;
        const static_treaty_plan_ref = entry.static_treaty_plan_ref orelse continue;
        const plan = staticTreatyPlanForRef(plans, static_treaty_plan_ref) orelse continue;
        count += plan.blockers.len;
    }
    return count;
}

fn sourceMapDirectBlockerRefCount(source_map: BoundaryElaborationSourceMap) usize {
    var count: usize = 0;
    for (source_map.entries) |entry| {
        if (entry.disposition == .blocked and entry.static_treaty_plan_ref == null and entry.blocker_ref != null) count += 1;
    }
    return count;
}

fn sourceMapBlockedEntryBlockerRefCount(source_map: BoundaryElaborationSourceMap, plans: []const BoundaryStaticTreatyPlan) usize {
    return sourceMapStaticTreatyPlanBlockerRefCount(source_map, plans) + sourceMapDirectBlockerRefCount(source_map);
}

fn sourceMapStaticTreatyPlanBlockerRefCountFor(source_map: BoundaryElaborationSourceMap, plans: []const BoundaryStaticTreatyPlan, ref: Ref) usize {
    var count: usize = 0;
    for (source_map.entries) |entry| {
        if (entry.disposition != .blocked) continue;
        const static_treaty_plan_ref = entry.static_treaty_plan_ref orelse continue;
        const plan = staticTreatyPlanForRef(plans, static_treaty_plan_ref) orelse continue;
        for (plan.blockers) |blocker| {
            const blocker_ref = refForBoundaryClosureBlocker(blocker.toEvidenceBlocker());
            if (blocker_ref.eql(ref)) count += 1;
        }
    }
    return count;
}

fn sourceMapDirectBlockerRefCountFor(source_map: BoundaryElaborationSourceMap, ref: Ref) usize {
    var count: usize = 0;
    for (source_map.entries) |entry| {
        if (entry.disposition != .blocked or entry.static_treaty_plan_ref != null) continue;
        const blocker_ref = entry.blocker_ref orelse continue;
        if (blocker_ref.eql(ref)) count += 1;
    }
    return count;
}

fn sourceMapBlockedEntryBlockerRefCountFor(source_map: BoundaryElaborationSourceMap, plans: []const BoundaryStaticTreatyPlan, ref: Ref) usize {
    return sourceMapStaticTreatyPlanBlockerRefCountFor(source_map, plans, ref) + sourceMapDirectBlockerRefCountFor(source_map, ref);
}

fn sourceMapEntryMatchesStaticTreatyPlan(policy: BoundaryElaborationPolicy, dependencies: []const Dependency, entry: BoundaryElaborationSourceMap.Entry, plan: BoundaryStaticTreatyPlan, world_ports: []const BoundaryWorldPort) bool {
    switch (entry.disposition) {
        .world_port_lowered => {
            const world_port_ref = entry.world_port_ref orelse return false;
            if (entry.provider_program_ref != null) return false;
            const world_port = worldPortForRef(world_ports, world_port_ref) orelse return false;
            if (world_port.exposed_intrinsic_ref == null) {
                const body = boundaryStaticTreatyPlanRouteSemanticBody(plan);
                switch (body) {
                    .declarative,
                    .residualized_program,
                    .pipeline,
                    => {},
                    .boundary_program,
                    .host_intrinsic,
                    .unknown,
                    .kernel_primitive,
                    => return false,
                }
                if (!staticTreatyPlanHasElaborationRouteProof(plan, body)) return false;
                if (plan.selected_morphism_ref != null) {
                    return boundaryWorldPortMatchesMorphismTarget(world_port, plan);
                }
                return boundaryWorldPortMatchesShape(world_port, plan.source_shape);
            }
            if (!staticTreatyPlanCanLowerToWorldPort(plan)) return false;
            const intrinsic_ref = staticTreatyPlanWorldPortIntrinsicRef(plan) orelse return false;
            if (!elaborationPolicyAllowsWorldPortIntrinsic(policy, intrinsic_ref)) return false;
            if (plan.selected_morphism_semantic_body == .host_intrinsic) {
                if (!optionalRefSubjectsEqual(world_port.exposed_intrinsic_ref, intrinsic_ref)) return false;
                if (plan.selected_morphism_ref != null) {
                    return boundaryWorldPortMatchesMorphismTarget(world_port, plan);
                }
                return boundaryWorldPortMatchesShape(world_port, plan.source_shape);
            }
            if (!optionalRefSubjectsEqual(world_port.exposed_intrinsic_ref, intrinsic_ref)) return false;
            return boundaryWorldPortMatchesShape(world_port, plan.source_shape);
        },
        .blocked => return entry.world_port_ref == null and
            entry.provider_program_ref == null and
            staticTreatyPlanBlockedUnderElaborationPolicy(policy, plan),
        .preserved,
        .provider_program_linked,
        .residualized,
        .pipeline_adapter,
        => {
            if (entry.world_port_ref != null) return false;
            const body = boundaryStaticTreatyPlanRouteSemanticBody(plan);
            if (!staticTreatyPlanRouteAllowedByElaborationPolicy(policy, plan, body)) return false;
            const expected_disposition: BoundaryElaborationSourceMap.Disposition = switch (body) {
                .boundary_program => .provider_program_linked,
                .pipeline => .pipeline_adapter,
                .residualized_program => .residualized,
                .declarative => .preserved,
                .host_intrinsic,
                .unknown,
                .kernel_primitive,
                => return false,
            };
            if (entry.disposition != expected_disposition) return false;
            if (!staticTreatyPlanHasElaborationRouteProof(plan, body)) return false;
            if (!optionalRefValuesEqual(entry.provider_program_ref, plan.selected_provider_program_ref)) return false;
            if (entry.disposition == .provider_program_linked and entry.provider_program_ref == null) return false;
            if (entry.residual_ref) |residual_ref| {
                if (staticTreatyPlanNeedsResidualDependencyInCertificate(plan) and
                    !staticTreatyPlanHasDependencyRef(plan, .residual_program, residual_ref)) return false;
                if (entry.disposition == .provider_program_linked and
                    !staticTreatyPlanHasDependencyRef(plan, .residual_program, residual_ref))
                {
                    const binding_ref = refForProviderProgramResidualBinding(plan, residual_ref) orelse return false;
                    if (!dependenciesContainRef(dependencies, .provider_program_mapping, binding_ref)) return false;
                }
                if (!staticTreatyPlanResidualDependenciesMatch(plan, residual_ref)) return false;
            }
            return true;
        },
    }
}

fn staticTreatyPlanRouteAllowedByElaborationPolicy(policy: BoundaryElaborationPolicy, plan: BoundaryStaticTreatyPlan, body: SemanticBody) bool {
    return switch (body) {
        .boundary_program => policy.allow_provider_program_linking and plan.selected_provider_program_ref != null,
        .declarative => !policy.require_program_backed_providers_for_internal_routes and policy.allow_declarative_morphisms,
        .residualized_program => !policy.require_program_backed_providers_for_internal_routes and policy.allow_residualized_morphisms,
        .pipeline => !policy.require_program_backed_providers_for_internal_routes and policy.allow_pipeline_adapters,
        .host_intrinsic,
        .unknown,
        .kernel_primitive,
        => false,
    };
}

fn staticTreatyPlanHasElaborationRouteProof(plan: BoundaryStaticTreatyPlan, body: SemanticBody) bool {
    return switch (body) {
        .boundary_program => plan.selected_provider_program_ref != null and
            plan.selected_provider_program_mapping_fingerprint != null and
            plan.selected_provider_program_request_mapping_tag != null and
            plan.selected_provider_program_result_mapping_tag != null and
            staticTreatyPlanHasProviderProgramMappingSupportProof(plan) and
            plan.selected_provider_program_effect_shape_count != null and
            plan.selected_provider_program_effect_shape_fingerprint != null and
            staticTreatyPlanHasProviderProgramMorphismProof(plan),
        .declarative => plan.selected_morphism_ref == null or staticTreatyPlanHasMorphismProof(plan, .declarative),
        .residualized_program => staticTreatyPlanHasMorphismProof(plan, .residualized_program) and
            staticTreatyPlanHasDependencyRole(plan, .residual_program),
        .pipeline => staticTreatyPlanHasMorphismProof(plan, .pipeline) and
            staticTreatyPlanHasDependencyRole(plan, .pipeline),
        .host_intrinsic,
        .unknown,
        .kernel_primitive,
        => false,
    };
}

fn staticTreatyPlanHasProviderProgramMappingSupportProof(plan: BoundaryStaticTreatyPlan) bool {
    const expected = plan.selectedProviderProgramMappingSupportFingerprint() orelse return false;
    return plan.selected_provider_program_mapping_support_fingerprint == expected and
        staticTreatyPlanProviderProgramMappingTagsMatchShape(plan);
}

fn staticTreatyPlanProviderProgramMappingTagsMatchShape(plan: BoundaryStaticTreatyPlan) bool {
    const request_mapping_tag = plan.selected_provider_program_request_mapping_tag orelse return false;
    const result_mapping_tag = plan.selected_provider_program_result_mapping_tag orelse return false;
    const mapping_shape = providerProgramMappingShapeForPlan(plan) orelse return false;
    return providerProgramMappingRequestTagMatchesShape(mapping_shape, request_mapping_tag) and
        providerProgramMappingResultTagMatchesShape(mapping_shape, result_mapping_tag);
}

fn providerProgramMappingRequestTagMatchesShape(shape: BoundaryEffectShape, tag: []const u8) bool {
    if (std.mem.eql(u8, tag, "payload_to_args")) return true;
    if (std.mem.eql(u8, tag, "unit_args")) {
        const ref = shape.value_ref orelse return false;
        return boundaryValueRefIsUnit(ref);
    }
    return false;
}

fn providerProgramMappingResultTagMatchesShape(shape: BoundaryEffectShape, tag: []const u8) bool {
    if (std.mem.eql(u8, tag, "result_to_resume")) return shape.kind == .operation and shape.expected_resume_ref != null;
    if (std.mem.eql(u8, tag, "result_to_return_now")) return shape.kind == .operation and shape.result_ref != null;
    if (std.mem.eql(u8, tag, "result_to_resume_after")) return shape.kind == .after and shape.expected_after_ref != null;
    return false;
}

fn staticTreatyPlanHasProviderProgramMorphismProof(plan: BoundaryStaticTreatyPlan) bool {
    if (plan.selected_morphism_ref == null) return true;
    const body = plan.selected_morphism_semantic_body orelse return false;
    if (!staticTreatyPlanHasMorphismProof(plan, body)) return false;
    return switch (body) {
        .boundary_program,
        .declarative,
        => true,
        .residualized_program => staticTreatyPlanHasDependencyRole(plan, .residual_program),
        .pipeline => staticTreatyPlanHasDependencyRole(plan, .pipeline),
        .host_intrinsic,
        .unknown,
        .kernel_primitive,
        => false,
    };
}

fn staticTreatyPlanHasUnsupportedShapeBlocker(plan: BoundaryStaticTreatyPlan) bool {
    for (plan.blockers) |blocker| {
        if (closureBlockerTagIsUnsupportedShape(blocker.tag)) return true;
    }
    return false;
}

fn staticTreatyPlanHasMorphismProof(plan: BoundaryStaticTreatyPlan, body: SemanticBody) bool {
    const morphism_ref = plan.selected_morphism_ref orelse return false;
    return plan.selected_morphism_semantic_body != null and
        plan.selected_morphism_semantic_body.? == body and
        staticTreatyPlanHasDependencyRef(plan, .morphism, morphism_ref);
}

fn staticTreatyPlanHasDependencyRole(plan: BoundaryStaticTreatyPlan, role: Role) bool {
    for (plan.dependencies) |dependency| {
        if (dependency.role == role) return true;
    }
    return false;
}

fn staticTreatyPlanNeedsResidualDependencyInCertificate(plan: BoundaryStaticTreatyPlan) bool {
    return switch (boundaryStaticTreatyPlanRouteSemanticBody(plan)) {
        .declarative,
        .residualized_program,
        .pipeline,
        => true,
        .boundary_program,
        .host_intrinsic,
        .unknown,
        .kernel_primitive,
        => false,
    };
}

fn staticTreatyPlanHasDependencyRef(plan: BoundaryStaticTreatyPlan, role: Role, ref: Ref) bool {
    for (plan.dependencies) |dependency| {
        if (dependency.role == role and dependency.ref.eql(ref)) return true;
    }
    return false;
}

fn staticTreatyPlanResidualDependenciesMatch(plan: BoundaryStaticTreatyPlan, residual_ref: Ref) bool {
    for (plan.dependencies) |dependency| {
        if (dependency.role != .residual_program) continue;
        if (!dependency.ref.eql(residual_ref)) return false;
    }
    return true;
}

pub fn refForProviderProgramResidualBinding(plan: BoundaryStaticTreatyPlan, residual_ref: Ref) ?Ref {
    const provider_ref = plan.selected_provider_ref orelse return null;
    const program_ref = plan.selected_provider_program_ref orelse return null;
    const mapping_fingerprint = plan.selected_provider_program_mapping_fingerprint orelse return null;
    const mapping_support_fingerprint = plan.selected_provider_program_mapping_support_fingerprint orelse return null;
    const mapping_shape = providerProgramMappingShapeForPlan(plan) orelse return null;
    var builder = FingerprintBuilder.init(domains.provider_program_mapping);
    builder.fieldRef("provider", provider_ref);
    builder.fieldRef("program", program_ref);
    builder.fieldRef("residual", residual_ref);
    builder.fieldU64("mapping", mapping_fingerprint);
    builder.fieldU64("mapping_support", mapping_support_fingerprint);
    builder.fieldRef("effect_shape", mapping_shape.evidenceRef());
    return refForProviderProgramMapping(builder.finish());
}

fn staticTreatyPlanBlockedUnderElaborationPolicy(policy: BoundaryElaborationPolicy, plan: BoundaryStaticTreatyPlan) bool {
    return plan.blockers.len != 0 and !plan.closedUnderPolicy(policy.closure_policy);
}

fn staticTreatyPlanCanLowerToWorldPort(plan: BoundaryStaticTreatyPlan) bool {
    return boundaryStaticTreatyPlanRouteSemanticBody(plan) == .host_intrinsic;
}

fn staticTreatyPlanWorldPortIntrinsicRef(plan: BoundaryStaticTreatyPlan) ?Ref {
    if (plan.selected_morphism_semantic_body == .host_intrinsic) return plan.selected_morphism_intrinsic_ref;
    if (boundaryStaticTreatyPlanRouteSemanticBody(plan) == .host_intrinsic) return plan.selected_intrinsic_ref;
    return null;
}

fn elaborationPolicyAllowsWorldPortIntrinsic(policy: BoundaryElaborationPolicy, intrinsic_ref: Ref) bool {
    if (!policy.allow_intrinsic_world_ports) return false;
    if (intrinsic_ref.domain_id != domains.host_intrinsic.id) return false;
    if (policy.reject_dynamic_intrinsic_mappers) {
        const kind_tag = intrinsic_ref.kind_tag orelse return false;
        if (std.mem.eql(u8, kind_tag, @tagName(HostIntrinsic.Kind.dynamic_morphism_mapper))) return false;
    }
    return true;
}

fn optionalRefSubjectsEqual(lhs: ?Ref, rhs: ?Ref) bool {
    if (lhs) |lhs_ref| {
        const rhs_ref = rhs orelse return false;
        return refSubjectsEqual(lhs_ref, rhs_ref);
    }
    return rhs == null;
}

fn optionalRefValuesEqual(lhs: ?Ref, rhs: ?Ref) bool {
    if (lhs) |lhs_ref| {
        const rhs_ref = rhs orelse return false;
        return refValuesEqual(lhs_ref, rhs_ref);
    }
    return rhs == null;
}

fn refValuesEqual(lhs: Ref, rhs: Ref) bool {
    return lhs.domain_id == rhs.domain_id and
        lhs.fingerprint == rhs.fingerprint and
        lhs.format_version == rhs.format_version and
        optionalBytesEqual(lhs.label, rhs.label) and
        lhs.branch_id == rhs.branch_id and
        lhs.site_index == rhs.site_index and
        optionalBytesEqual(lhs.kind_tag, rhs.kind_tag);
}

fn refSubjectsEqual(lhs: Ref, rhs: Ref) bool {
    return lhs.domain_id == rhs.domain_id and
        lhs.fingerprint == rhs.fingerprint and
        lhs.format_version == rhs.format_version and
        lhs.branch_id == rhs.branch_id and
        lhs.site_index == rhs.site_index;
}

fn boundaryStaticTreatyPlanRouteSemanticBody(plan: BoundaryStaticTreatyPlan) SemanticBody {
    if (plan.selected_semantic_body == .boundary_program) return .boundary_program;
    return plan.selected_morphism_semantic_body orelse plan.selected_semantic_body;
}

fn providerProgramMappingShapeForPlan(plan: BoundaryStaticTreatyPlan) ?BoundaryEffectShape {
    if (plan.selected_morphism_ref != null) return plan.morphismTargetShapeWitness();
    return plan.source_shape;
}

fn providerProgramMappingTagsCompatibleWithShape(shape: BoundaryEffectShape, request_mapping: anytype, result_mapping: anytype) bool {
    switch (request_mapping) {
        .payload_to_args => {},
        .unit_args => {
            const ref = shape.value_ref orelse return false;
            if (!boundaryValueRefIsUnit(ref)) return false;
        },
        .payload_and_metadata_to_args,
        .custom_comptime_mapper,
        => return false,
    }
    switch (result_mapping) {
        .result_to_resume => if (shape.kind != .operation or shape.expected_resume_ref == null) return false,
        .result_to_return_now => if (shape.kind != .operation or shape.result_ref == null) return false,
        .result_to_resume_after => if (shape.kind != .after or shape.expected_after_ref == null) return false,
        .result_to_outcome_union => return false,
    }
    return true;
}

fn boundaryValueRefIsUnit(ref: BoundaryValueRef) bool {
    return std.mem.eql(u8, ref.codec, "unit") and ref.schema_index == null;
}

fn sourceMapWorldPortsMatchPorts(source_map: BoundaryElaborationSourceMap, ports: []const BoundaryWorldPort) bool {
    for (source_map.entries) |entry| {
        const world_port_ref = entry.world_port_ref orelse continue;
        const port = worldPortForRef(ports, world_port_ref) orelse return false;
        if (worldPortDescriptorCount(ports, world_port_ref) != 1) return false;
        if (!sourceMapWorldPortEntryMatchesPort(entry, port)) return false;
    }
    for (ports) |port| {
        if (port.fingerprint != port.computeFingerprint()) return false;
        if (sourceMapWorldPortRefCount(source_map, port.evidenceRef()) == 0) return false;
    }
    return true;
}

fn worldPortDescriptorCount(ports: []const BoundaryWorldPort, needle: Ref) usize {
    var count: usize = 0;
    for (ports) |port| {
        if (port.fingerprint != port.computeFingerprint()) continue;
        if (port.evidenceRef().eql(needle)) count += 1;
    }
    return count;
}

fn sourceMapWorldPortEntryMatchesPort(entry: BoundaryElaborationSourceMap.Entry, port: BoundaryWorldPort) bool {
    if (port.effect_shape_ref) |shape_ref| {
        if (!entry.source_ref.eql(shape_ref)) return false;
    } else if (entry.static_treaty_plan_ref == null and !entry.source_ref.eql(port.evidenceRef())) {
        return false;
    }
    if (entry.source_site_index) |site_index| {
        if (!boundaryWorldPortSupportsSiteIndex(port, site_index)) return false;
    }
    if (entry.residual_site_index) |site_index| {
        if (!boundaryWorldPortSupportsSiteIndex(port, site_index)) return false;
    }
    return true;
}

fn worldPortsAllowedByElaborationPolicy(policy: BoundaryElaborationPolicy, ports: []const BoundaryWorldPort) bool {
    for (ports) |port| {
        if (!policy.closure_policy.allowsWorldPortRef(port.evidenceRef())) return false;
        if (port.exposed_intrinsic_ref) |intrinsic_ref| {
            if (!elaborationPolicyAllowsWorldPortIntrinsic(policy, intrinsic_ref)) return false;
        }
    }
    return true;
}

fn worldPortForRef(ports: []const BoundaryWorldPort, ref: Ref) ?BoundaryWorldPort {
    for (ports) |port| {
        if (port.evidenceRef().eql(ref)) return port;
    }
    return null;
}

fn boundaryWorldPortMatchesShape(port: BoundaryWorldPort, shape: BoundaryEffectShape) bool {
    if (port.effect_shape_ref) |shape_ref| {
        if (!refSubjectsEqual(shape_ref, shape.evidenceRef())) return false;
    }
    if (shape.site_index) |site_index| {
        if (!boundaryWorldPortSupportsSiteIndex(port, site_index)) return false;
    }
    if (!boundaryWorldPortSupportsRequirement(port, shape.protocol_label)) return false;
    if (shape.protocol_op_fingerprint) |fingerprint| {
        if (!boundaryWorldPortSupportsOperationFingerprint(port, fingerprint)) return false;
    }
    return true;
}

fn boundaryWorldPortMatchesMorphismTarget(port: BoundaryWorldPort, plan: BoundaryStaticTreatyPlan) bool {
    const target_shape_ref = plan.selected_morphism_target_shape_ref orelse return false;
    const target_shape = plan.morphismTargetShapeWitness() orelse return false;
    if (target_shape.fingerprint != target_shape.computeFingerprint()) return false;
    if (!refSubjectsEqual(target_shape.evidenceRef(), target_shape_ref)) return false;
    return boundaryWorldPortMatchesShape(port, target_shape);
}

fn boundaryWorldPortSupportsSiteIndex(port: BoundaryWorldPort, site_index: usize) bool {
    if (port.supported_site_indexes.len == 0) return true;
    for (port.supported_site_indexes) |supported| {
        if (supported == site_index) return true;
    }
    return false;
}

fn boundaryWorldPortSupportsRequirement(port: BoundaryWorldPort, requirement_label: []const u8) bool {
    if (port.supported_protocol_labels.len == 0) return true;
    for (port.supported_protocol_labels) |label| {
        if (std.mem.eql(u8, label, requirement_label)) return true;
    }
    return false;
}

fn boundaryWorldPortSupportsOperationFingerprint(port: BoundaryWorldPort, fingerprint: u64) bool {
    if (port.supported_protocol_op_fingerprints.len == 0) return true;
    for (port.supported_protocol_op_fingerprints) |supported| {
        if (supported == fingerprint) return true;
    }
    return false;
}

fn staticTreatyPlanForRef(plans: []const BoundaryStaticTreatyPlan, ref: Ref) ?BoundaryStaticTreatyPlan {
    for (plans) |plan| {
        if (plan.evidenceRef().eql(ref)) return plan;
    }
    return null;
}

fn sourceMapStaticTreatyPlanRefCount(source_map: BoundaryElaborationSourceMap, needle: Ref) usize {
    var count: usize = 0;
    for (source_map.entries) |entry| {
        if (entry.static_treaty_plan_ref) |static_treaty_plan_ref| {
            if (static_treaty_plan_ref.eql(needle)) count += 1;
        }
    }
    return count;
}

fn refSliceCount(refs: []const Ref, needle: Ref) usize {
    var count: usize = 0;
    for (refs) |ref| {
        if (ref.eql(needle)) count += 1;
    }
    return count;
}

fn refSliceUnique(refs: []const Ref) bool {
    for (refs, 0..) |ref, index| {
        if (refSliceCount(refs[0..index], ref) != 0) return false;
    }
    return true;
}

const ProgramBodySiteMetadata = struct {
    instruction_index: usize,
    label: []const u8,
};

fn residualProgramNestedWithTargetCount(comptime ResidualProgram: type) usize {
    if (comptime @hasDecl(ResidualProgram, "contract")) return ResidualProgram.contract.nested_with_targets.len;
    return 0;
}

fn residualProgramNestedWithTargets(comptime ResidualProgram: type) [residualProgramNestedWithTargetCount(ResidualProgram)]lowering_api.NestedWithTarget {
    var targets: [residualProgramNestedWithTargetCount(ResidualProgram)]lowering_api.NestedWithTarget = undefined;
    if (comptime @hasDecl(ResidualProgram, "contract")) {
        inline for (ResidualProgram.contract.nested_with_targets, 0..) |target, index| {
            targets[index] = .{
                .metadata = target.metadata,
                .function_index = target.function_index,
            };
        }
    }
    return targets;
}

fn residualProgramSiteMetadataCount(comptime ResidualProgram: type) usize {
    if (comptime !@hasDecl(ResidualProgram, "protocol")) return 0;
    comptime var count: usize = 0;
    inline for (ResidualProgram.protocol.operation_site_metadata) |site| {
        if (site.semantic_label != null) count += 1;
    }
    return count;
}

fn residualProgramSiteMetadata(comptime ResidualProgram: type) [residualProgramSiteMetadataCount(ResidualProgram)]ProgramBodySiteMetadata {
    var metadata: [residualProgramSiteMetadataCount(ResidualProgram)]ProgramBodySiteMetadata = undefined;
    if (comptime @hasDecl(ResidualProgram, "protocol")) {
        comptime var index: usize = 0;
        inline for (ResidualProgram.protocol.operation_site_metadata) |site| {
            if (site.semantic_label) |label| {
                metadata[index] = .{
                    .instruction_index = site.instruction_index,
                    .label = label,
                };
                index += 1;
            }
        }
    }
    return metadata;
}

pub fn BoundaryElaboration(comptime ProgramType: type, comptime Closure: type) type {
    return struct {
        pub const Policy = BoundaryElaborationPolicy;
        pub const ValidationError = error{
            BoundaryElaborationCertificateMismatch,
            BoundaryElaborationRootRefMismatch,
            BoundaryElaborationProviderProgramRefMismatch,
            BoundaryElaborationStaticTreatyPlanRefMismatch,
            BoundaryElaborationWorldPortRefMismatch,
            BoundaryElaborationWorldPortsRejected,
            BoundaryElaborationResidualProgramMismatch,
            BoundaryElaborationPolicyMismatch,
            BoundaryElaborationBlocked,
        };

        pub const ProviderProgramLink = struct {
            provider_ref: Ref,
            program_ref: Ref,
            residual_program_ref: Ref,
            mapping_fingerprint: ?u64 = null,
            mapping_support_fingerprint: ?u64 = null,
            effect_shape_ref: ?Ref = null,
        };

        pub const Input = struct {
            closure_graph: Closure.Graph,
            closure_report: Closure.Report,
            closure_certificate: Closure.Certificate,
            static_treaty_plans: []const Closure.StaticTreatyPlan = &.{},
            source_program_ref: Ref,
            residual_program_ref: ?Ref = null,
            provider_programs: []const Closure.ProviderProgram = &.{},
            provider_program_links: []const ProviderProgramLink = &.{},
            provider_harness_refs: []const Ref = &.{},
            morphism_offers: []const ProgramType.Exchange.MorphismOffer = &.{},
            morphism_offer_refs: []const Ref = &.{},
            residualization_adapter_refs: []const Ref = &.{},
            pipeline_adapter_refs: []const Ref = &.{},
            world_ports: []const Closure.WorldPort = &.{},
            policy: Policy = Policy.strictStatic(),
            label: []const u8 = ProgramType.contract.label,
            ir_hash_override: ?u64 = null,

            pub fn validate(self: @This()) ValidationError!void {
                if (!self.source_program_ref.eql(owningProgramRef())) return error.BoundaryElaborationRootRefMismatch;
                if (self.policy.require_certificate_checked or self.policy.require_checked_closure_certificate) {
                    self.closure_certificate.check(
                        self.closure_graph,
                        self.closure_report,
                        self.policy.closure_policy,
                        self.static_treaty_plans,
                    ) catch return error.BoundaryElaborationCertificateMismatch;
                }
                if (!refsContain(self.closure_report.root_program_refs, self.source_program_ref) and
                    !refsContain(self.closure_report.effect_free_root_refs, self.source_program_ref))
                {
                    return error.BoundaryElaborationRootRefMismatch;
                }
                if (!refsEqual(self.closure_certificate.root_refs, self.closure_report.root_program_refs)) {
                    return error.BoundaryElaborationCertificateMismatch;
                }
                if (!refsEqual(self.closure_certificate.provider_refs, self.closure_report.provider_harness_refs)) {
                    return error.BoundaryElaborationCertificateMismatch;
                }
                if (self.provider_harness_refs.len != 0 and !refsEqual(self.provider_harness_refs, self.closure_report.provider_harness_refs)) {
                    return error.BoundaryElaborationCertificateMismatch;
                }
                if (!providerProgramRefsMatch(self.provider_programs, self.closure_report.provider_program_refs)) {
                    return error.BoundaryElaborationProviderProgramRefMismatch;
                }
                if (!self.policy.allow_provider_program_linking and self.closure_report.provider_program_refs.len != 0) {
                    return error.BoundaryElaborationBlocked;
                }
                if (providerProgramNestedDepth(self) > self.policy.max_nested_provider_depth) {
                    return error.BoundaryElaborationBlocked;
                }
                if (!staticPlanRefsMatch(self.static_treaty_plans, self.closure_certificate.selected_static_treaty_plan_refs)) {
                    return error.BoundaryElaborationStaticTreatyPlanRefMismatch;
                }
                if (!providerProgramProofsMatchStaticPlans(self)) {
                    return error.BoundaryElaborationProviderProgramRefMismatch;
                }
                if (!staticTreatyPlansAllowedByElaborationPolicy(self)) {
                    return error.BoundaryElaborationBlocked;
                }
                if (!worldPortRefsMatch(self.world_ports, self.closure_report.world_port_refs)) {
                    return error.BoundaryElaborationWorldPortRefMismatch;
                }
                if (!hostIntrinsicPlansHaveWorldPorts(self)) {
                    return error.BoundaryElaborationWorldPortRefMismatch;
                }
                if (!self.policy.allow_world_ports and self.closure_report.open_world_port_count != 0) {
                    return error.BoundaryElaborationWorldPortsRejected;
                }
                if (!self.policy.allow_partial_with_blockers and self.closure_report.blocker_count != 0) {
                    return error.BoundaryElaborationBlocked;
                }
                if (self.policy.fail_on_unsupported_shape and closureReportHasUnsupportedShapeBlocker(self.closure_report)) {
                    return error.BoundaryElaborationBlocked;
                }
                if (self.closure_report.blocker_count > self.policy.max_blockers) {
                    return error.BoundaryElaborationBlocked;
                }
            }

            pub fn validateResidualProgram(comptime self: @This(), comptime ResidualProgram: type) ValidationError!void {
                try self.validate();
                if (!fromResidualSupportsRoutes(self)) return error.BoundaryElaborationResidualProgramMismatch;
                if (self.ir_hash_override) |override_hash| {
                    if (override_hash != ResidualProgram.compiled_plan.hash()) return error.BoundaryElaborationResidualProgramMismatch;
                }
                const residual_ref = residualProgramRef(self, ResidualProgram);
                if (self.residual_program_ref) |expected| {
                    if (!expected.eql(residual_ref)) return error.BoundaryElaborationResidualProgramMismatch;
                }
                if (!staticTreatyPlansDoNotForgeResidualProgram(self, residual_ref)) return error.BoundaryElaborationResidualProgramMismatch;
                const residual_nested_with_targets = if (@hasDecl(ResidualProgram, "nested_with_targets")) ResidualProgram.nested_with_targets else residualProgramNestedWithTargets(ResidualProgram);
                ResidualProgram.compiled_plan.validateWithNestedTargets(residual_nested_with_targets) catch return error.BoundaryElaborationResidualProgramMismatch;
                inline for (self.world_ports) |port| {
                    if (residualWorldPortSiteCount(ResidualProgram, port) != refCount(self.closure_report.world_port_refs, port.evidenceRef())) return error.BoundaryElaborationResidualProgramMismatch;
                }
                inline for (ResidualProgram.contract.session.yield_sites) |site| {
                    if (residualYieldSiteWorldPortCoverageCount(site, self.world_ports) != 1) return error.BoundaryElaborationResidualProgramMismatch;
                }
                if (ResidualProgram.contract.session.after_sites.len != 0) return error.BoundaryElaborationResidualProgramMismatch;
            }
        };

        fn owningProgramRef() Ref {
            return refFor(domains.program_plan, ProgramType.compiled_plan.hash(), .{ .label = ProgramType.contract.label });
        }

        fn residualProgramHash(comptime input: Input, comptime ResidualProgram: type) u64 {
            _ = input;
            return ResidualProgram.compiled_plan.hash();
        }

        fn residualProgramRef(comptime input: Input, comptime ResidualProgram: type) Ref {
            return refFor(domains.program_plan, residualProgramHash(input, ResidualProgram), .{ .label = ResidualProgram.contract.label });
        }

        fn fromResidualSupportsRoutes(comptime input: Input) bool {
            if (input.static_treaty_plans.len == 0) {
                if (input.closure_report.provider_program_refs.len != 0) return false;
                if (input.closure_report.closed_effect_shape_count != 0) return false;
                return true;
            }
            inline for (input.static_treaty_plans) |plan| {
                if (planBlockedForElaboration(input, plan)) continue;
                switch (routeSemanticBody(plan)) {
                    .boundary_program => if (plan.selected_provider_program_ref == null) return false,
                    .declarative => if (!input.policy.allow_declarative_morphisms) return false,
                    .residualized_program => if (!input.policy.allow_residualized_morphisms) return false,
                    .pipeline => if (!input.policy.allow_pipeline_adapters) return false,
                    .host_intrinsic,
                    => if (!input.policy.allow_world_ports or
                        input.closure_report.open_world_port_count == 0 or
                        worldPortForPlan(input, ProgramType, plan) == null) return false,
                    .unknown => return false,
                    .kernel_primitive => return false,
                }
            }
            return true;
        }

        fn staticTreatyPlansDoNotForgeResidualProgram(comptime input: Input, comptime residual_ref: Ref) bool {
            inline for (input.static_treaty_plans) |plan| {
                if (comptime planBlockedForElaboration(input, plan)) continue;
                if (comptime staticTreatyPlanRequiresResidualProgramBinding(input, plan)) {
                    if (!planHasDependencyRef(plan, .residual_program, residual_ref)) return false;
                    continue;
                }
                if (routeSemanticBody(plan) == .boundary_program and
                    !planHasDependencyRef(plan, .residual_program, residual_ref) and
                    !providerProgramResidualBindingSupported(input, plan, residual_ref)) return false;
                if (!planResidualProgramDependenciesMatch(plan, residual_ref)) return false;
            }
            return true;
        }

        fn staticTreatyPlanRequiresResidualProgramBinding(comptime input: Input, comptime plan: Closure.StaticTreatyPlan) bool {
            if (worldPortForPlan(input, ProgramType, plan) != null) return false;
            return switch (routeSemanticBody(plan)) {
                .declarative,
                .residualized_program,
                .pipeline,
                => true,
                .boundary_program,
                .host_intrinsic,
                .unknown,
                .kernel_primitive,
                => false,
            };
        }

        fn planResidualProgramDependenciesMatch(plan: Closure.StaticTreatyPlan, residual_ref: Ref) bool {
            for (plan.dependencies) |dependency| {
                if (dependency.role != .residual_program) continue;
                if (!dependency.ref.eql(residual_ref)) return false;
            }
            return true;
        }

        fn providerProgramResidualBindingSupported(comptime input: Input, comptime plan: Closure.StaticTreatyPlan, comptime residual_ref: Ref) bool {
            if (providerProgramResidualBindingExists(input.provider_program_links, plan, residual_ref)) return true;
            return residual_ref.eql(owningProgramRef()) and providerProgramSelectedByPlan(input, plan) != null;
        }

        fn providerProgramResidualBindingExists(links: []const ProviderProgramLink, plan: Closure.StaticTreatyPlan, residual_ref: Ref) bool {
            const provider_ref = plan.selected_provider_ref orelse return false;
            const program_ref = plan.selected_provider_program_ref orelse return false;
            const mapping_fingerprint = plan.selected_provider_program_mapping_fingerprint orelse return false;
            const mapping_support_fingerprint = plan.selected_provider_program_mapping_support_fingerprint orelse return false;
            const mapping_shape = providerProgramMappingShapeForPlan(plan) orelse return false;
            for (links) |link| {
                if (!link.provider_ref.eql(provider_ref)) continue;
                if (!link.program_ref.eql(program_ref)) continue;
                if (!link.residual_program_ref.eql(residual_ref)) continue;
                const expected_mapping = link.mapping_fingerprint orelse continue;
                if (expected_mapping != mapping_fingerprint) continue;
                const expected_mapping_support = link.mapping_support_fingerprint orelse continue;
                if (expected_mapping_support != mapping_support_fingerprint) continue;
                const expected_shape = link.effect_shape_ref orelse continue;
                if (!expected_shape.eql(mapping_shape.evidenceRef())) continue;
                return true;
            }
            return false;
        }

        pub const Result = struct {
            certificate: Certificate,
            source_map: SourceMap,
            effect_row: EffectRow,
            trace_map: TraceMap,
            normal_form: NormalForm,
            blockers: []const BoundaryElaborationBlocker = &.{},
        };
        pub const Certificate = BoundaryElaborationCertificate;
        pub const SourceMap = BoundaryElaborationSourceMap;
        pub const EffectRow = BoundaryElaborationEffectRow;
        pub const TraceMap = BoundaryElaborationTraceMap;
        pub const NormalForm = BoundaryNormalForm;
        pub const NormalFormKind = BoundaryNormalFormKind;
        pub const BlockerTag = BoundaryElaborationBlockerTag;
        pub const Blocker = BoundaryElaborationBlocker;
        pub const TargetPolicy = BoundaryTargetPolicy;
        pub const WorldSurface = BoundaryWorldSurface;
        pub const WorldPortTable = BoundaryWorldPortTable;
        pub const WorldValueTable = BoundaryWorldValueTable;
        pub const WorldDispatchTable = BoundaryWorldDispatchTable;
        pub const SurfaceProfile = BoundarySurfaceProfile;
        pub const ReplayKeyRecipe = BoundaryReplayKeyRecipe;
        pub const TargetCertificate = BoundaryTargetCertificate;
        pub const TargetEvidenceMap = BoundaryTargetEvidenceMap;

        pub fn FromResidual(comptime input: Input, comptime ResidualProgram: type, comptime options: anytype) type {
            @setEvalBranchQuota(2_000_000);
            const residual_hash = comptime residualProgramHash(input, ResidualProgram);
            const residual_ref = comptime refFor(domains.program_plan, residual_hash, .{ .label = ResidualProgram.contract.label });
            const bound_input = comptime blk: {
                var copy = input;
                if (copy.residual_program_ref == null) copy.residual_program_ref = residual_ref;
                break :blk copy;
            };
            comptime bound_input.validateResidualProgram(ResidualProgram) catch |err|
                @compileError("BoundaryClosure.Elaboration input rejected residual Program: " ++ @errorName(err));
            const normal_kind = comptime normalFormKindFor(bound_input);
            const source_entries = comptime sourceEntriesFor(bound_input, residual_ref, ResidualProgram, options);
            const SourceMapValue = comptime SourceMap.init(elaborationOption(options, "source_map_label", bound_input.label ++ ".source_map"), source_entries[0..], &.{});
            const TraceMapValue = comptime if (bound_input.policy.emit_trace_map) blk: {
                const trace_entries = traceEntriesForSourceEntries(source_entries);
                break :blk TraceMap.init(elaborationOption(options, "trace_map_label", bound_input.label ++ ".trace_map"), trace_entries[0..]);
            } else null;
            const source_shapes = comptime sourceEntriesEffectShapeCount(source_entries);
            const unsupported_shapes = comptime sourceEntriesBlockedUnsupportedShapeCount(bound_input, source_entries);
            const residualized_routes = comptime residualizedRouteCount(bound_input);
            const pipeline_routes = comptime pipelineRouteCount(bound_input);
            const provider_program_routes = comptime providerProgramRouteCount(bound_input);
            const linked_provider_programs = comptime linkedProviderProgramCount(bound_input);
            const nested_provider_shapes = comptime providerProgramNestedShapeCount(bound_input);
            const nested_provider_depth = comptime providerProgramNestedDepth(bound_input);
            const InlinedProviderProgramRefsValue = comptime linkedProviderProgramRefs(bound_input);
            const EffectRowValue = comptime EffectRow.init(.{
                .label = elaborationOption(options, "effect_row_label", bound_input.label ++ ".effect_row"),
                .source_program_ref = bound_input.source_program_ref,
                .residual_program_ref = residual_ref,
                .normal_form = normal_kind,
                .source_effect_shapes = source_shapes,
                .closed_effect_shapes = bound_input.closure_report.closed_effect_shape_count,
                .world_ports = bound_input.closure_report.open_world_port_count,
                .provider_program_links = provider_program_routes,
                .linked_provider_programs = linked_provider_programs,
                .nested_provider_shapes_linked = nested_provider_shapes,
                .nested_provider_depth = nested_provider_depth,
                .residualized_routes = residualized_routes,
                .pipeline_routes = pipeline_routes,
                .blockers = bound_input.closure_report.blocker_count,
                .unsupported_shapes = unsupported_shapes,
            });
            const NormalFormValue = comptime NormalForm.init(
                elaborationOption(options, "normal_form_label", bound_input.label ++ ".normal_form"),
                normal_kind,
                bound_input.closure_certificate.evidenceRef(),
                EffectRowValue.evidenceRef(),
                bound_input.closure_report.blocker_count,
            );
            const DependenciesValue = comptime dependenciesFor(bound_input, SourceMapValue, EffectRowValue, TraceMapValue, NormalFormValue);
            const ResidualWorldPortRefsValue = comptime residualWorldPortRefs(bound_input);
            const EvidenceDependencyRefsValue = comptime evidenceDependencyRefs(DependenciesValue);
            const BlockerRefsValue = comptime blockerRefsFor(bound_input);
            const CertificateValue = comptime Certificate.init(.{
                .elaborated_program_label = ResidualProgram.contract.label,
                .source_program_ref = bound_input.source_program_ref,
                .residual_program_ref = residual_ref,
                .closure_certificate_ref = bound_input.closure_certificate.evidenceRef(),
                .closure_graph_ref = bound_input.closure_graph.evidenceRef(),
                .closure_report_ref = bound_input.closure_report.evidenceRef(),
                .source_map_ref = SourceMapValue.evidenceRef(),
                .effect_row_ref = EffectRowValue.evidenceRef(),
                .trace_map_ref = if (bound_input.policy.emit_trace_map) TraceMapValue.evidenceRef() else null,
                .normal_form_ref = NormalFormValue.evidenceRef(),
                .policy = bound_input.policy,
                .normal_form = normal_kind,
                .elaborated_program_plan_hash = residual_hash,
                .selected_static_treaty_plan_refs = bound_input.closure_certificate.selected_static_treaty_plan_refs,
                .inlined_provider_program_refs = InlinedProviderProgramRefsValue[0..],
                .world_port_refs = bound_input.closure_report.world_port_refs,
                .residual_world_port_refs = ResidualWorldPortRefsValue[0..],
                .evidence_dependency_refs = EvidenceDependencyRefsValue[0..],
                .blocker_refs = BlockerRefsValue[0..],
                .summary_counts = .{
                    .root_effect_shapes = bound_input.closure_report.effect_shape_count,
                    .internal_routes_elaborated = bound_input.closure_report.closed_effect_shape_count,
                    .provider_programs_linked = linked_provider_programs,
                    .nested_provider_shapes_linked = nested_provider_shapes,
                    .nested_provider_depth = nested_provider_depth,
                    .morphism_routes_elaborated = residualized_routes,
                    .pipeline_routes_elaborated = pipeline_routes,
                    .world_ports_emitted = bound_input.closure_report.open_world_port_count,
                    .blockers = bound_input.closure_report.blocker_count,
                },
                .dependencies = DependenciesValue[0..],
            });
            comptime CertificateValue.check(bound_input.policy, bound_input.closure_graph.evidenceRef(), bound_input.closure_report.evidenceRef(), bound_input.closure_certificate.evidenceRef(), SourceMapValue, EffectRowValue, TraceMapValue, NormalFormValue, bound_input.static_treaty_plans, bound_input.world_ports) catch |err|
                @compileError("BoundaryClosure.Elaboration certificate self-check failed: " ++ @errorName(err));

            return struct {
                pub const compiled_plan = ResidualProgram.compiled_plan;
                pub const value_schema_types = ResidualProgram.value_schema_types;
                pub const nested_with_targets = if (@hasDecl(ResidualProgram, "nested_with_targets")) ResidualProgram.nested_with_targets else residualProgramNestedWithTargets(ResidualProgram);
                pub const site_metadata = if (@hasDecl(ResidualProgram, "site_metadata")) ResidualProgram.site_metadata else residualProgramSiteMetadata(ResidualProgram);
                pub const source_map = SourceMapValue;
                pub const residual_map = SourceMapValue;
                pub const evidence_map = SourceMapValue;
                pub const trace_map = TraceMapValue;
                pub const effect_row = EffectRowValue;
                pub const normal_form = NormalFormValue;
                pub const certificate = CertificateValue;
                pub const residual_world_port_refs = bound_input.closure_report.world_port_refs;
                pub const Body = @This();
            };
        }

        pub const Target = struct {
            pub const Policy = TargetPolicy;
            pub const Certificate = TargetCertificate;
            pub const EvidenceMap = TargetEvidenceMap;
            const TargetElaborationInput = Input;
            pub const PlanBuilder = struct {
                pub fn synthesizeResidualProgram(comptime options: anytype) type {
                    return targetResidualProgramOption(options);
                }

                pub fn residualProgramRef(comptime input: Input, comptime ResidualProgram: type) Ref {
                    return ProgramType.Evidence.refFor(
                        ProgramType.Evidence.domains.program_plan,
                        residualProgramHash(input, ResidualProgram),
                        .{ .label = ResidualProgram.contract.label },
                    );
                }

                pub fn generatedPlanRef(comptime input: Input, comptime ResidualProgram: type) Ref {
                    return ProgramType.Evidence.refFor(
                        ProgramType.Evidence.domains.boundary_elaboration_generated_plan,
                        residualProgramHash(input, ResidualProgram),
                        .{ .label = ResidualProgram.contract.label },
                    );
                }
            };
            pub const Normalization = struct {
                pub const Policy = BoundaryNormalizationPolicy;
                pub const Redex = BoundaryNormalizationRedex;
                pub const RewriteRule = BoundaryNormalizationRewriteRule;
                pub const RewriteStep = BoundaryNormalizationRewriteStep;
                pub const Trace = BoundaryNormalizationTrace;
                pub const Certificate = BoundaryNormalizationCertificate;
                pub const BlockerTag = BoundaryNormalizationBlockerTag;
                pub const Input = struct {
                    closure_certificate: Closure.Certificate,
                    closure_graph: Closure.Graph,
                    root_program_ref: Ref,
                    provider_harness_refs: []const Ref = &.{},
                    provider_programs: []const Closure.ProviderProgram = &.{},
                    provider_program_refs: []const Ref = &.{},
                    static_treaty_plans: []const Closure.StaticTreatyPlan = &.{},
                    morphism_offers: []const ProgramType.Exchange.MorphismOffer = &.{},
                    morphism_offer_refs: []const Ref = &.{},
                    residualization_adapter_refs: []const Ref = &.{},
                    pipeline_adapter_refs: []const Ref = &.{},
                    world_ports: []const Closure.WorldPort = &.{},
                    target_policy: TargetPolicy = .{},
                    max_nested_provider_depth: usize = 32,
                    label: []const u8 = ProgramType.contract.label,
                    ir_hash_override: ?u64 = null,

                    pub fn fromElaboration(comptime elaboration_input: TargetElaborationInput, comptime target_policy: TargetPolicy) @This() {
                        return .{
                            .closure_certificate = elaboration_input.closure_certificate,
                            .closure_graph = elaboration_input.closure_graph,
                            .root_program_ref = elaboration_input.source_program_ref,
                            .provider_harness_refs = elaboration_input.provider_harness_refs,
                            .provider_programs = elaboration_input.provider_programs,
                            .provider_program_refs = elaboration_input.closure_report.provider_program_refs,
                            .static_treaty_plans = elaboration_input.static_treaty_plans,
                            .morphism_offers = elaboration_input.morphism_offers,
                            .morphism_offer_refs = elaboration_input.morphism_offer_refs,
                            .residualization_adapter_refs = elaboration_input.residualization_adapter_refs,
                            .pipeline_adapter_refs = elaboration_input.pipeline_adapter_refs,
                            .world_ports = elaboration_input.world_ports,
                            .target_policy = target_policy,
                            .max_nested_provider_depth = target_policy.max_nested_provider_depth,
                            .label = elaboration_input.label,
                            .ir_hash_override = elaboration_input.ir_hash_override,
                        };
                    }

                    pub fn validate(comptime self: @This(), comptime elaboration_input: TargetElaborationInput) ValidationError!void {
                        try elaboration_input.validate();
                        const expected_elaboration_policy = boundaryTargetElaborationPolicy(self.target_policy);
                        if (expected_elaboration_policy.fingerprint() != elaboration_input.policy.fingerprint()) return error.BoundaryElaborationPolicyMismatch;
                        if (!self.root_program_ref.eql(elaboration_input.source_program_ref)) return error.BoundaryElaborationRootRefMismatch;
                        if (!self.closure_certificate.evidenceRef().eql(elaboration_input.closure_certificate.evidenceRef())) return error.BoundaryElaborationCertificateMismatch;
                        if (!self.closure_graph.evidenceRef().eql(elaboration_input.closure_graph.evidenceRef())) return error.BoundaryElaborationCertificateMismatch;
                        if (!refsEqual(self.provider_harness_refs, elaboration_input.provider_harness_refs)) return error.BoundaryElaborationCertificateMismatch;
                        if (!providerProgramProofSlicesEqual(self.provider_programs, elaboration_input.provider_programs)) return error.BoundaryElaborationProviderProgramRefMismatch;
                        if (!refsEqual(self.provider_program_refs, elaboration_input.closure_report.provider_program_refs)) return error.BoundaryElaborationProviderProgramRefMismatch;
                        if (!staticTreatyPlanSlicesEqual(self.static_treaty_plans, elaboration_input.static_treaty_plans)) return error.BoundaryElaborationStaticTreatyPlanRefMismatch;
                        if (!staticPlanRefsMatch(self.static_treaty_plans, elaboration_input.closure_certificate.selected_static_treaty_plan_refs)) return error.BoundaryElaborationStaticTreatyPlanRefMismatch;
                        if (!morphismOfferSlicesEqual(self.morphism_offers, elaboration_input.morphism_offers)) return error.BoundaryElaborationCertificateMismatch;
                        if (!refsEqual(self.morphism_offer_refs, elaboration_input.morphism_offer_refs)) return error.BoundaryElaborationCertificateMismatch;
                        if (!refsEqual(self.residualization_adapter_refs, elaboration_input.residualization_adapter_refs)) return error.BoundaryElaborationCertificateMismatch;
                        if (!refsEqual(self.pipeline_adapter_refs, elaboration_input.pipeline_adapter_refs)) return error.BoundaryElaborationCertificateMismatch;
                        if (!worldPortSlicesEqual(self.world_ports, elaboration_input.world_ports)) return error.BoundaryElaborationWorldPortRefMismatch;
                        if (!worldPortRefsMatch(self.world_ports, elaboration_input.closure_report.world_port_refs)) return error.BoundaryElaborationWorldPortRefMismatch;
                        if (self.max_nested_provider_depth != self.target_policy.max_nested_provider_depth) return error.BoundaryElaborationBlocked;
                    }
                };

                pub const RouteKind = enum {
                    provider_program,
                    world_port,
                    preserved,
                    residualized,
                    pipeline_adapter,
                    blocked,
                    unsupported,
                };

                pub const FallbackReason = enum {
                    none,
                    provider_program_proof_missing,
                    provider_program_policy_rejected,
                    route_policy_rejected,
                    world_port_selected,
                    internal_route_preserved,
                    residualized_route,
                    pipeline_route,
                    blocked_by_static_plan,
                    unsupported_semantic_body,
                };

                pub const ProviderProgramSelection = struct {
                    provider_ref: Ref,
                    provider_offer_ref: Ref,
                    program_ref: Ref,
                    mapping_ref: Ref,
                    mapping_fingerprint: u64,
                    mapping_support_fingerprint: u64,
                    request_mapping_tag: []const u8,
                    result_mapping_tag: []const u8,
                    effect_shape_count: u64,
                    effect_shape_fingerprint: u64,
                    effect_shape_ref: Ref,
                };

                pub const WorldPortSelection = struct {
                    world_port_ref: Ref,
                    effect_shape_ref: Ref,
                };

                pub const Route = struct {
                    kind: RouteKind,
                    fallback_reason: FallbackReason,
                    source_ref: Ref,
                    static_treaty_plan_ref: Ref,
                    route_semantic_body: SemanticBody,
                    provider_program: ?ProviderProgramSelection = null,
                    world_port: ?WorldPortSelection = null,
                };

                pub fn routeForPlan(input: anytype, plan: Closure.StaticTreatyPlan) Route {
                    const source_ref = plan.source_shape.evidenceRef();
                    const plan_ref = plan.evidenceRef();
                    if (planBlockedForElaboration(input, plan)) {
                        return .{
                            .kind = .blocked,
                            .fallback_reason = .blocked_by_static_plan,
                            .source_ref = source_ref,
                            .static_treaty_plan_ref = plan_ref,
                            .route_semantic_body = routeSemanticBody(plan),
                        };
                    }
                    if (routeSemanticBody(plan) == .boundary_program) {
                        if (!inputAllowsProviderProgramLinking(input) or !inputAllowsProviderProgramRoute(input, plan)) {
                            return .{
                                .kind = .unsupported,
                                .fallback_reason = .provider_program_policy_rejected,
                                .source_ref = source_ref,
                                .static_treaty_plan_ref = plan_ref,
                                .route_semantic_body = .boundary_program,
                            };
                        }
                        if (providerProgramSelectionForPlan(input, plan)) |selection| {
                            return .{
                                .kind = .provider_program,
                                .fallback_reason = .none,
                                .source_ref = source_ref,
                                .static_treaty_plan_ref = plan_ref,
                                .route_semantic_body = .boundary_program,
                                .provider_program = selection,
                            };
                        }
                    }
                    if (inputAllowsWorldPorts(input) and inputAllowsWorldPortRoute(input, plan)) {
                        if (worldPortSelectionForPlan(input, plan)) |selection| {
                            return .{
                                .kind = .world_port,
                                .fallback_reason = .world_port_selected,
                                .source_ref = source_ref,
                                .static_treaty_plan_ref = plan_ref,
                                .route_semantic_body = routeSemanticBody(plan),
                                .world_port = selection,
                            };
                        }
                    }
                    return switch (routeSemanticBody(plan)) {
                        .boundary_program => .{
                            .kind = .unsupported,
                            .fallback_reason = .provider_program_proof_missing,
                            .source_ref = source_ref,
                            .static_treaty_plan_ref = plan_ref,
                            .route_semantic_body = .boundary_program,
                        },
                        .declarative => if (inputAllowsRouteForSemanticBody(input, plan, .declarative)) .{
                            .kind = .preserved,
                            .fallback_reason = .internal_route_preserved,
                            .source_ref = source_ref,
                            .static_treaty_plan_ref = plan_ref,
                            .route_semantic_body = .declarative,
                        } else .{
                            .kind = .unsupported,
                            .fallback_reason = .route_policy_rejected,
                            .source_ref = source_ref,
                            .static_treaty_plan_ref = plan_ref,
                            .route_semantic_body = .declarative,
                        },
                        .residualized_program => if (inputAllowsRouteForSemanticBody(input, plan, .residualized_program)) .{
                            .kind = .residualized,
                            .fallback_reason = .residualized_route,
                            .source_ref = source_ref,
                            .static_treaty_plan_ref = plan_ref,
                            .route_semantic_body = .residualized_program,
                        } else .{
                            .kind = .unsupported,
                            .fallback_reason = .route_policy_rejected,
                            .source_ref = source_ref,
                            .static_treaty_plan_ref = plan_ref,
                            .route_semantic_body = .residualized_program,
                        },
                        .pipeline => if (inputAllowsRouteForSemanticBody(input, plan, .pipeline)) .{
                            .kind = .pipeline_adapter,
                            .fallback_reason = .pipeline_route,
                            .source_ref = source_ref,
                            .static_treaty_plan_ref = plan_ref,
                            .route_semantic_body = .pipeline,
                        } else .{
                            .kind = .unsupported,
                            .fallback_reason = .route_policy_rejected,
                            .source_ref = source_ref,
                            .static_treaty_plan_ref = plan_ref,
                            .route_semantic_body = .pipeline,
                        },
                        .host_intrinsic,
                        .unknown,
                        .kernel_primitive,
                        => .{
                            .kind = .unsupported,
                            .fallback_reason = .unsupported_semantic_body,
                            .source_ref = source_ref,
                            .static_treaty_plan_ref = plan_ref,
                            .route_semantic_body = routeSemanticBody(plan),
                        },
                    };
                }

                pub fn routesFor(comptime input: anytype) [input.static_treaty_plans.len]Route {
                    var routes: [input.static_treaty_plans.len]Route = undefined;
                    for (input.static_treaty_plans, 0..) |plan, index| {
                        routes[index] = routeForPlan(input, plan);
                    }
                    return routes;
                }

                pub fn providerProgramSelectionForPlan(input: anytype, plan: Closure.StaticTreatyPlan) ?ProviderProgramSelection {
                    _ = providerProgramSelectedByPlan(input, plan) orelse return null;
                    const provider_ref = plan.selected_provider_ref orelse return null;
                    const provider_offer_ref = plan.selected_provider_offer_ref orelse return null;
                    const program_ref = plan.selected_provider_program_ref orelse return null;
                    const mapping_fingerprint = plan.selected_provider_program_mapping_fingerprint orelse return null;
                    const mapping_support_fingerprint = plan.selected_provider_program_mapping_support_fingerprint orelse return null;
                    const request_mapping_tag = plan.selected_provider_program_request_mapping_tag orelse return null;
                    const result_mapping_tag = plan.selected_provider_program_result_mapping_tag orelse return null;
                    const effect_shape_count = plan.selected_provider_program_effect_shape_count orelse return null;
                    const effect_shape_fingerprint = plan.selected_provider_program_effect_shape_fingerprint orelse return null;
                    const mapping_shape = providerProgramMappingShapeForPlan(plan) orelse return null;
                    return .{
                        .provider_ref = provider_ref,
                        .provider_offer_ref = provider_offer_ref,
                        .program_ref = program_ref,
                        .mapping_ref = refForProviderProgramMapping(mapping_support_fingerprint),
                        .mapping_fingerprint = mapping_fingerprint,
                        .mapping_support_fingerprint = mapping_support_fingerprint,
                        .request_mapping_tag = request_mapping_tag,
                        .result_mapping_tag = result_mapping_tag,
                        .effect_shape_count = effect_shape_count,
                        .effect_shape_fingerprint = effect_shape_fingerprint,
                        .effect_shape_ref = mapping_shape.evidenceRef(),
                    };
                }

                pub fn worldPortSelectionForPlan(input: anytype, plan: Closure.StaticTreatyPlan) ?WorldPortSelection {
                    var target_response_refs_buffer: [3]BoundaryValueRef = undefined;
                    const shape = worldPortShapeForPlan(input, plan, &target_response_refs_buffer) orelse return null;
                    if (shape.kind != .operation) return null;
                    for (input.world_ports) |port| {
                        if (staticTreatyPlanCanLowerToWorldPort(plan)) {
                            const intrinsic_ref = staticTreatyPlanWorldPortIntrinsicRef(plan) orelse continue;
                            const exposed_ref = port.exposed_intrinsic_ref orelse continue;
                            if (!refSubjectsEqual(exposed_ref, intrinsic_ref)) continue;
                        } else if (staticTreatyPlanShapeOnlyWorldPortAllowed(plan)) {
                            if (port.exposed_intrinsic_ref != null) continue;
                        } else {
                            continue;
                        }
                        if (!worldPortMatchesSourceShape(port, shape)) continue;
                        return .{
                            .world_port_ref = port.evidenceRef(),
                            .effect_shape_ref = shape.evidenceRef(),
                        };
                    }
                    return null;
                }

                fn inputAllowsWorldPorts(input: anytype) bool {
                    if (comptime @hasField(@TypeOf(input), "target_policy")) return input.target_policy.allow_world_ports;
                    if (comptime @hasField(@TypeOf(input), "policy")) return input.policy.allow_world_ports;
                    return false;
                }

                fn inputAllowsProviderProgramLinking(input: anytype) bool {
                    if (comptime @hasField(@TypeOf(input), "target_policy")) return input.target_policy.allow_program_backed_providers;
                    if (comptime @hasField(@TypeOf(input), "policy")) return input.policy.allow_provider_program_linking;
                    return false;
                }

                fn inputAllowsProviderProgramRoute(input: anytype, plan: Closure.StaticTreatyPlan) bool {
                    if (!staticTreatyPlanSourceIsNested(input, plan)) return true;
                    if (comptime @hasField(@TypeOf(input), "target_policy")) {
                        return input.target_policy.allow_nested_program_backed_providers and input.target_policy.max_nested_provider_depth > 0;
                    }
                    if (comptime @hasField(@TypeOf(input), "policy")) return input.policy.max_nested_provider_depth > 0;
                    if (comptime @hasField(@TypeOf(input), "max_nested_provider_depth")) return input.max_nested_provider_depth > 0;
                    return false;
                }

                fn staticTreatyPlanSourceIsNested(input: anytype, plan: Closure.StaticTreatyPlan) bool {
                    if (plan.source_shape.plan_hash == 0) return false;
                    const root_program_ref = inputRootProgramRef(input) orelse return true;
                    const source_program_ref = refFor(domains.program_plan, plan.source_shape.plan_hash, .{ .label = plan.source_shape.program_label });
                    return !source_program_ref.eql(root_program_ref);
                }

                fn inputRootProgramRef(input: anytype) ?Ref {
                    if (comptime @hasField(@TypeOf(input), "root_program_ref")) return input.root_program_ref;
                    if (comptime @hasField(@TypeOf(input), "source_program_ref")) return input.source_program_ref;
                    return null;
                }

                fn inputAllowsRouteForSemanticBody(input: anytype, plan: Closure.StaticTreatyPlan, body: SemanticBody) bool {
                    if (comptime @hasField(@TypeOf(input), "target_policy")) {
                        return staticTreatyPlanRouteAllowedByElaborationPolicy(boundaryTargetElaborationPolicy(input.target_policy), plan, body);
                    }
                    if (comptime @hasField(@TypeOf(input), "policy")) return staticTreatyPlanRouteAllowedByElaborationPolicy(input.policy, plan, body);
                    return false;
                }

                fn inputAllowsWorldPortRoute(input: anytype, plan: Closure.StaticTreatyPlan) bool {
                    if (staticTreatyPlanCanLowerToWorldPort(plan)) {
                        const intrinsic_ref = staticTreatyPlanWorldPortIntrinsicRef(plan) orelse return false;
                        return inputAllowsWorldPortIntrinsic(input, intrinsic_ref);
                    }
                    return inputAllowsRouteForSemanticBody(input, plan, routeSemanticBody(plan));
                }

                fn inputAllowsWorldPortIntrinsic(input: anytype, intrinsic_ref: Ref) bool {
                    if (comptime @hasField(@TypeOf(input), "target_policy")) {
                        return elaborationPolicyAllowsWorldPortIntrinsic(boundaryTargetElaborationPolicy(input.target_policy), intrinsic_ref);
                    }
                    if (comptime @hasField(@TypeOf(input), "policy")) return elaborationPolicyAllowsWorldPortIntrinsic(input.policy, intrinsic_ref);
                    return false;
                }

                pub fn redexesFor(comptime SourceBody: type, comptime ResidualProgram: type, comptime input: TargetElaborationInput, comptime target_policy: TargetPolicy) [SourceBody.source_map.entries.len]Redex {
                    _ = target_policy;
                    var redexes: [SourceBody.source_map.entries.len]Redex = undefined;
                    inline for (SourceBody.source_map.entries, 0..) |entry, index| {
                        const plan = if (entry.static_treaty_plan_ref) |plan_ref| staticTreatyPlanForRef(input.static_treaty_plans, plan_ref) else null;
                        redexes[index] = Redex.init(.{
                            .label = entry.label,
                            .source_effect_shape_ref = entry.source_ref,
                            .coordinates = .{
                                .function_index = 0,
                                .block_index = 0,
                                .instruction_index = entry.source_site_index,
                                .site_index = entry.source_site_index,
                            },
                            .origin = normalizationRedexOriginForSourceEntry(entry, input.static_treaty_plans, SourceBody.certificate.source_program_ref),
                            .kind = redexKindForSourceEntry(entry, input.static_treaty_plans),
                            .selected_static_treaty_plan_ref = entry.static_treaty_plan_ref,
                            .current_program_plan_ref = normalizationRedexCurrentProgramRefForSourceEntry(entry, input.static_treaty_plans, SourceBody.certificate.source_program_ref),
                            .semantic_body = if (plan) |value| routeSemanticBody(value) else .unknown,
                            .expected_lowering_kind = rewriteRuleKindForSourceEntry(entry, input.static_treaty_plans, SourceBody.certificate.source_program_ref),
                            .evidence_dependencies = &.{
                                .{ .role = .source, .ref = entry.source_ref },
                                .{ .role = .residual_program, .ref = refFor(domains.program_plan, ResidualProgram.compiled_plan.hash(), .{ .label = ResidualProgram.contract.label }) },
                            },
                        });
                    }
                    return redexes;
                }

                pub fn rulesFor(comptime SourceBody: type, comptime input: TargetElaborationInput) [SourceBody.source_map.entries.len]RewriteRule {
                    var rules: [SourceBody.source_map.entries.len]RewriteRule = undefined;
                    inline for (SourceBody.source_map.entries, 0..) |entry, index| {
                        rules[index] = RewriteRule.init(.{
                            .label = entry.label,
                            .kind = rewriteRuleKindForSourceEntry(entry, input.static_treaty_plans, SourceBody.certificate.source_program_ref),
                            .evidence_dependencies = &.{.{ .role = .source, .ref = entry.source_ref }},
                            .produced_source_map_entries = 1,
                            .produced_trace_map_entries = 1,
                            .produced_effect_row_entries = 1,
                            .blocker_refs = sourceEntryBlockerRefs(entry, input.static_treaty_plans),
                        });
                    }
                    return rules;
                }

                pub fn stepsFor(comptime SourceBody: type, comptime ResidualProgram: type, comptime input: TargetElaborationInput, comptime redexes: anytype, comptime rules: anytype) [SourceBody.source_map.entries.len]RewriteStep {
                    var steps: [SourceBody.source_map.entries.len]RewriteStep = undefined;
                    inline for (SourceBody.source_map.entries, 0..) |entry, index| {
                        const plan = if (entry.static_treaty_plan_ref) |plan_ref| staticTreatyPlanForRef(input.static_treaty_plans, plan_ref) else null;
                        steps[index] = RewriteStep.init(.{
                            .step_index = index,
                            .redex_ref = redexes[index].evidenceRef(),
                            .rewrite_rule_ref = rules[index].evidenceRef(),
                            .selected_static_treaty_plan_ref = entry.static_treaty_plan_ref,
                            .source_effect_shape_ref = entry.source_ref,
                            .input_program_plan_hash = redexes[index].current_program_plan_ref.fingerprint,
                            .output_program_plan_hash = ResidualProgram.compiled_plan.hash(),
                            .builder_state_fingerprint = routeLoweringFingerprint(entry, ResidualProgram.compiled_plan.hash()),
                            .provider_program_ref = entry.provider_program_ref,
                            .provider_offer_ref = if (plan) |value| value.selected_provider_offer_ref else null,
                            .world_port_ref = entry.world_port_ref,
                            .morphism_or_pipeline_ref = if (plan) |value| value.selected_morphism_ref else null,
                            .blocker_refs = sourceEntryBlockerRefs(entry, input.static_treaty_plans),
                            .summary = @tagName(rules[index].kind),
                        });
                    }
                    return steps;
                }

                fn sourceEntryBlockerRefs(comptime entry: SourceMap.Entry, comptime static_treaty_plans: []const Closure.StaticTreatyPlan) []const Ref {
                    if (entry.disposition != .blocked) return &.{};
                    if (entry.blocker_ref) |blocker_ref| return &.{blocker_ref};
                    const plan_ref = entry.static_treaty_plan_ref orelse return &.{};
                    const plan = staticTreatyPlanForRef(static_treaty_plans, plan_ref) orelse return &.{};
                    var refs: [plan.blockers.len]Ref = undefined;
                    inline for (plan.blockers, 0..) |blocker, blocker_index| {
                        refs[blocker_index] = refForBoundaryClosureBlocker(blocker.toEvidenceBlocker());
                    }
                    const final_refs = refs;
                    return final_refs[0..];
                }

                pub fn traceFor(comptime SourceBody: type, comptime ResidualProgram: type, comptime input: TargetElaborationInput, comptime target_policy: TargetPolicy, comptime label: []const u8) Trace {
                    comptime input.validate() catch |err|
                        @compileError("Boundary Target Normalization input rejected: " ++ @errorName(err));
                    const RedexesValue = comptime redexesFor(SourceBody, ResidualProgram, input, target_policy);
                    const RulesValue = comptime rulesFor(SourceBody, input);
                    const StepsValue = comptime stepsFor(SourceBody, ResidualProgram, input, RedexesValue, RulesValue);
                    const eliminated = comptime eliminatedRedexRefs(SourceBody, RedexesValue);
                    const unsupported = comptime unsupportedRedexRefs(SourceBody, RedexesValue);
                    const residual_world_ports = comptime residualWorldPortRefsForTrace(SourceBody);
                    const dependencies = comptime traceDependencies(SourceBody);
                    return Trace.init(.{
                        .label = label,
                        .root_program_ref = SourceBody.certificate.source_program_ref,
                        .closure_certificate_ref = SourceBody.certificate.closure_certificate_ref,
                        .rewrite_steps = StepsValue[0..],
                        .eliminated_redex_refs = eliminated[0..],
                        .residual_world_port_refs = residual_world_ports[0..],
                        .unsupported_redex_refs = unsupported[0..],
                        .final_program_plan_hash = ResidualProgram.compiled_plan.hash(),
                        .final_normal_form = SourceBody.normal_form.kind,
                        .evidence_dependencies = dependencies[0..],
                    });
                }

                fn redexKindForSourceEntry(comptime entry: SourceMap.Entry, comptime static_treaty_plans: []const Closure.StaticTreatyPlan) Redex.Kind {
                    return normalizationRedexKindForSourceEntry(entry, static_treaty_plans);
                }

                fn rewriteRuleKindForSourceEntry(comptime entry: SourceMap.Entry, comptime static_treaty_plans: []const Closure.StaticTreatyPlan, comptime root_program_ref: Ref) RewriteRule.Kind {
                    return switch (entry.disposition) {
                        .preserved => .already_normal,
                        .provider_program_linked => if (normalizationRedexOriginForSourceEntry(entry, static_treaty_plans, root_program_ref) == .nested_provider_program) .nested_provider_program_call else .provider_program_call,
                        .world_port_lowered => .residual_world_port,
                        .residualized => .residualized_morphism,
                        .pipeline_adapter => .pipeline_adapter,
                        .blocked => .unsupported,
                    };
                }

                fn routeLoweringFingerprint(comptime entry: SourceMap.Entry, comptime output_hash: u64) u64 {
                    return boundaryNormalizationRouteLoweringFingerprint(entry, output_hash);
                }

                fn eliminatedRedexRefs(comptime SourceBody: type, comptime redexes: anytype) [eliminatedRedexCount(SourceBody)]Ref {
                    var refs: [eliminatedRedexCount(SourceBody)]Ref = undefined;
                    var count: usize = 0;
                    inline for (SourceBody.source_map.entries, 0..) |entry, index| {
                        if (entry.world_port_ref != null or entry.disposition == .blocked) continue;
                        refs[count] = redexes[index].evidenceRef();
                        count += 1;
                    }
                    return refs;
                }

                fn eliminatedRedexCount(comptime SourceBody: type) usize {
                    var count: usize = 0;
                    inline for (SourceBody.source_map.entries) |entry| {
                        if (entry.world_port_ref != null or entry.disposition == .blocked) continue;
                        count += 1;
                    }
                    return count;
                }

                fn unsupportedRedexRefs(comptime SourceBody: type, comptime redexes: anytype) [unsupportedRedexCount(SourceBody)]Ref {
                    var refs: [unsupportedRedexCount(SourceBody)]Ref = undefined;
                    var count: usize = 0;
                    inline for (SourceBody.source_map.entries, 0..) |entry, index| {
                        if (entry.disposition != .blocked) continue;
                        refs[count] = redexes[index].evidenceRef();
                        count += 1;
                    }
                    return refs;
                }

                fn unsupportedRedexCount(comptime SourceBody: type) usize {
                    var count: usize = 0;
                    inline for (SourceBody.source_map.entries) |entry| {
                        if (entry.disposition == .blocked) count += 1;
                    }
                    return count;
                }

                fn residualWorldPortRefsForTrace(comptime SourceBody: type) [residualWorldPortRefCount(SourceBody)]Ref {
                    var refs: [residualWorldPortRefCount(SourceBody)]Ref = undefined;
                    var count: usize = 0;
                    inline for (SourceBody.source_map.entries) |entry| {
                        if (entry.world_port_ref) |world_port_ref| {
                            refs[count] = world_port_ref;
                            count += 1;
                        }
                    }
                    return refs;
                }

                fn residualWorldPortRefCount(comptime SourceBody: type) usize {
                    var count: usize = 0;
                    inline for (SourceBody.source_map.entries) |entry| {
                        if (entry.world_port_ref != null) count += 1;
                    }
                    return count;
                }

                fn traceDependencies(comptime SourceBody: type) [5]Dependency {
                    return .{
                        .{ .role = .closure_certificate, .ref = SourceBody.certificate.closure_certificate_ref },
                        .{ .role = .residual_program, .ref = SourceBody.certificate.residual_program_ref },
                        .{ .role = .elaboration_source_map, .ref = SourceBody.source_map.evidenceRef() },
                        .{ .role = .elaboration_effect_row, .ref = SourceBody.effect_row.evidenceRef() },
                        .{ .role = .normal_form, .ref = SourceBody.normal_form.evidenceRef() },
                    };
                }
            };
            pub const Conformance = struct {
                pub fn check(
                    world_surface: WorldSurface,
                    port_table: WorldPortTable,
                    value_table: WorldValueTable,
                    dispatch_table: WorldDispatchTable,
                    profile: SurfaceProfile,
                    replay_key_recipe: ReplayKeyRecipe,
                ) error{BoundaryTargetConformanceMismatch}!void {
                    if (world_surface.surface_format_version != domains.boundary_world_surface.format_version.?) return error.BoundaryTargetConformanceMismatch;
                    if (world_surface.surface_fingerprint != world_surface.computeFingerprint()) return error.BoundaryTargetConformanceMismatch;
                    if (port_table.fingerprint != port_table.computeFingerprint()) return error.BoundaryTargetConformanceMismatch;
                    if (value_table.fingerprint != value_table.computeFingerprint()) return error.BoundaryTargetConformanceMismatch;
                    if (dispatch_table.fingerprint != dispatch_table.computeFingerprint()) return error.BoundaryTargetConformanceMismatch;
                    if (profile.fingerprint != profile.computeFingerprint()) return error.BoundaryTargetConformanceMismatch;
                    if (replay_key_recipe.fingerprint != replay_key_recipe.computeFingerprint()) return error.BoundaryTargetConformanceMismatch;
                    if (!world_surface.port_table_ref.eql(port_table.evidenceRef())) return error.BoundaryTargetConformanceMismatch;
                    if (!world_surface.value_table_ref.eql(value_table.evidenceRef())) return error.BoundaryTargetConformanceMismatch;
                    if (!world_surface.dispatch_table_ref.eql(dispatch_table.evidenceRef())) return error.BoundaryTargetConformanceMismatch;
                    if (!world_surface.profile_ref.eql(profile.evidenceRef())) return error.BoundaryTargetConformanceMismatch;
                    if (!world_surface.replay_key_recipe_ref.eql(replay_key_recipe.evidenceRef())) return error.BoundaryTargetConformanceMismatch;
                    if (!replay_key_recipe.surface_ref.eql(world_surface.replayScopeRef())) return error.BoundaryTargetConformanceMismatch;
                    if (!targetReplayKeyRecipeConforms(replay_key_recipe)) return error.BoundaryTargetConformanceMismatch;
                    if (!targetTablesConform(port_table, value_table, dispatch_table, profile)) return error.BoundaryTargetConformanceMismatch;
                    if (world_surface.world_port_count != profile.world_port_count) return error.BoundaryTargetConformanceMismatch;
                    if (world_surface.world_port_count != port_table.entries.len) return error.BoundaryTargetConformanceMismatch;
                    if (world_surface.world_port_count == 0 and world_surface.normal_form == .world_ports_only) return error.BoundaryTargetConformanceMismatch;
                    if (world_surface.world_port_count != 0 and world_surface.normal_form == .strict_closed) return error.BoundaryTargetConformanceMismatch;
                }
            };

            pub fn compileComptime(comptime options: anytype) type {
                const input = options.input;
                const policy = comptime targetPolicyOption(options);
                const ResidualProgram = PlanBuilder.synthesizeResidualProgram(options);
                const target_input = comptime blk: {
                    var copy = input;
                    copy.policy = boundaryTargetElaborationPolicy(policy);
                    break :blk copy;
                };
                const Body = FromResidual(target_input, ResidualProgram, options);
                return FromBodyWithProgram(Body, ResidualProgram, options);
            }

            pub fn FromBodyWithProgram(comptime SourceBody: type, comptime ResidualProgram: type, comptime options: anytype) type {
                const policy = comptime targetPolicyOption(options);
                comptime assertTargetPolicySupported(policy, ResidualProgram);
                const residual_ref = comptime residualProgramRef(options.input, ResidualProgram);
                if (comptime !SourceBody.certificate.residual_program_ref.eql(residual_ref)) {
                    @compileError("Boundary Target residual Program does not match elaborated body certificate");
                }
                const expected_elaboration_policy = comptime boundaryTargetElaborationPolicy(policy);
                if (comptime SourceBody.certificate.elaboration_policy_fingerprint != expected_elaboration_policy.fingerprint() or
                    !policySummariesEqual(SourceBody.certificate.policy_summary, expected_elaboration_policy.policySummary()))
                {
                    @compileError("Boundary Target body policy does not match target policy");
                }
                const normalization_input = comptime blk: {
                    var copy = options.input;
                    copy.policy = expected_elaboration_policy;
                    break :blk copy;
                };
                const port_entries = comptime targetWorldPortEntries(SourceBody, ResidualProgram, options.input.static_treaty_plans, policy);
                const value_entries = comptime targetWorldValueEntries(port_entries);
                const dispatch_entry_count = comptime targetWorldDispatchEntryCount(port_entries);
                if (comptime policy.require_bounded_surface and policy.fail_on_unbounded_world_port_when_bounded_required and !boundaryTargetSurfaceBounded(policy, port_entries.len, value_entries.len, dispatch_entry_count)) {
                    @compileError("Boundary Target surface exceeds target policy bounds");
                }
                const target_label = comptime targetLabelOption(options, SourceBody.certificate.elaborated_program_label ++ ".target");
                const dispatch_entries = comptime targetWorldDispatchEntries(port_entries);
                const PortTableValue = comptime WorldPortTable.init(targetOption(options, "world_port_table_label", target_label ++ ".world_port_table"), port_entries[0..]);
                const ValueTableValue = comptime WorldValueTable.init(targetOption(options, "world_value_table_label", target_label ++ ".world_value_table"), value_entries[0..]);
                const DispatchTableValue = comptime WorldDispatchTable.init(targetOption(options, "world_dispatch_table_label", target_label ++ ".world_dispatch_table"), dispatch_entries[0..]);
                const bounded = comptime boundaryTargetSurfaceBounded(policy, port_entries.len, value_entries.len, dispatch_entries.len);
                const ProfileValue = comptime SurfaceProfile.init(.{
                    .label = targetOption(options, "surface_profile_label", target_label ++ ".surface_profile"),
                    .world_port_count = port_entries.len,
                    .value_descriptor_count = value_entries.len,
                    .dispatch_entry_count = dispatch_entries.len,
                    .no_search_hot_path = targetDispatchEntriesDense(dispatch_entries[0..]),
                    .bounded = bounded,
                });
                const SurfaceScopeValue = comptime WorldSurface.init(.{
                    .label = targetOption(options, "world_surface_label", target_label ++ ".world_surface"),
                    .residual_program_label = ResidualProgram.contract.label,
                    .residual_program_ref = residual_ref,
                    .elaboration_certificate_ref = SourceBody.certificate.evidenceRef(),
                    .source_map_ref = SourceBody.source_map.evidenceRef(),
                    .effect_row_ref = SourceBody.effect_row.evidenceRef(),
                    .port_table_ref = PortTableValue.evidenceRef(),
                    .value_table_ref = ValueTableValue.evidenceRef(),
                    .dispatch_table_ref = DispatchTableValue.evidenceRef(),
                    .profile_ref = ProfileValue.evidenceRef(),
                    .replay_key_recipe_ref = SourceBody.certificate.evidenceRef(),
                    .normal_form = SourceBody.normal_form.kind,
                    .world_port_count = port_entries.len,
                });
                const ReplayComponentsValue = [_][]const u8{ "world_surface_scope_fingerprint", "world_port_id", "request_fingerprint", "response_fingerprint" };
                const ReplayKeyRecipeValue = comptime ReplayKeyRecipe.init(
                    targetOption(options, "replay_key_recipe_label", target_label ++ ".replay_key_recipe"),
                    SurfaceScopeValue.replayScopeRef(),
                    ReplayComponentsValue[0..],
                );
                const SurfaceValue = comptime WorldSurface.init(.{
                    .label = SurfaceScopeValue.label,
                    .residual_program_label = SurfaceScopeValue.residual_program_label,
                    .residual_program_ref = SurfaceScopeValue.residual_program_ref,
                    .elaboration_certificate_ref = SurfaceScopeValue.elaboration_certificate_ref,
                    .source_map_ref = SurfaceScopeValue.source_map_ref,
                    .effect_row_ref = SurfaceScopeValue.effect_row_ref,
                    .port_table_ref = SurfaceScopeValue.port_table_ref,
                    .value_table_ref = SurfaceScopeValue.value_table_ref,
                    .dispatch_table_ref = SurfaceScopeValue.dispatch_table_ref,
                    .profile_ref = SurfaceScopeValue.profile_ref,
                    .replay_key_recipe_ref = ReplayKeyRecipeValue.evidenceRef(),
                    .normal_form = SurfaceScopeValue.normal_form,
                    .world_port_count = SurfaceScopeValue.world_port_count,
                });
                const EvidenceMapDependenciesValue = comptime targetDependencies(SourceBody, SurfaceValue, PortTableValue, ValueTableValue, DispatchTableValue, ProfileValue, ReplayKeyRecipeValue);
                const EvidenceMapValue = comptime EvidenceMap.init(
                    targetOption(options, "evidence_map_label", target_label ++ ".target_evidence_map"),
                    EvidenceMapDependenciesValue[0..],
                );
                const NormalizationRedexesValue = comptime Normalization.redexesFor(
                    SourceBody,
                    ResidualProgram,
                    normalization_input,
                    policy,
                );
                const NormalizationRulesValue = comptime Normalization.rulesFor(SourceBody, normalization_input);
                const NormalizationTraceValue = comptime Normalization.traceFor(
                    SourceBody,
                    ResidualProgram,
                    normalization_input,
                    policy,
                    targetOption(options, "normalization_trace_label", target_label ++ ".normalization_trace"),
                );
                const NormalizationCertificateDependenciesValue = [_]Dependency{
                    .{ .role = .normalization_trace, .ref = NormalizationTraceValue.evidenceRef() },
                    .{ .role = .elaboration_source_map, .ref = SourceBody.source_map.evidenceRef() },
                    .{ .role = .elaboration_trace_map, .ref = SourceBody.trace_map.evidenceRef() },
                    .{ .role = .target_evidence_map, .ref = EvidenceMapValue.evidenceRef() },
                    .{ .role = .elaboration_effect_row, .ref = SourceBody.effect_row.evidenceRef() },
                    .{ .role = .normal_form, .ref = SourceBody.normal_form.evidenceRef() },
                    .{ .role = .world_surface, .ref = SurfaceValue.evidenceRef() },
                };
                const NormalizationCertificateValue = comptime Normalization.Certificate.init(.{
                    .label = targetOption(options, "normalization_certificate_label", target_label ++ ".normalization_certificate"),
                    .closure_certificate_ref = SourceBody.certificate.closure_certificate_ref,
                    .target_policy_fingerprint = policy.fingerprint(),
                    .normalization_trace_ref = NormalizationTraceValue.evidenceRef(),
                    .final_program_plan_hash = ResidualProgram.compiled_plan.hash(),
                    .source_map_ref = SourceBody.source_map.evidenceRef(),
                    .trace_map_ref = SourceBody.trace_map.evidenceRef(),
                    .evidence_map_ref = EvidenceMapValue.evidenceRef(),
                    .effect_row_ref = SourceBody.effect_row.evidenceRef(),
                    .normal_form_ref = SourceBody.normal_form.evidenceRef(),
                    .world_surface_ref = SurfaceValue.evidenceRef(),
                    .blocker_refs = SourceBody.certificate.blocker_refs,
                    .dependencies = NormalizationCertificateDependenciesValue[0..],
                });
                comptime NormalizationCertificateValue.check(policy, NormalizationTraceValue, NormalizationRedexesValue[0..], NormalizationRulesValue[0..], options.input.static_treaty_plans, SourceBody.source_map, SourceBody.trace_map, EvidenceMapValue, SourceBody.effect_row, SourceBody.normal_form, SurfaceValue, options.input.world_ports) catch |err|
                    @compileError("BoundaryClosure.Elaboration.Target normalization certificate self-check failed: " ++ @errorName(err));
                const TargetCertificateDependenciesValue = EvidenceMapDependenciesValue ++ [_]Dependency{
                    .{ .role = .normalization_certificate, .ref = NormalizationCertificateValue.evidenceRef() },
                };
                const CertificateValue = comptime TargetCertificate.init(.{
                    .target_label = target_label,
                    .policy = policy,
                    .elaboration_certificate_ref = SourceBody.certificate.evidenceRef(),
                    .residual_program_ref = residual_ref,
                    .world_surface_ref = SurfaceValue.evidenceRef(),
                    .port_table_ref = PortTableValue.evidenceRef(),
                    .value_table_ref = ValueTableValue.evidenceRef(),
                    .dispatch_table_ref = DispatchTableValue.evidenceRef(),
                    .profile_ref = ProfileValue.evidenceRef(),
                    .replay_key_recipe_ref = ReplayKeyRecipeValue.evidenceRef(),
                    .evidence_map_ref = EvidenceMapValue.evidenceRef(),
                    .trace_map_ref = SourceBody.trace_map.evidenceRef(),
                    .normalization_certificate_ref = NormalizationCertificateValue.evidenceRef(),
                    .dependencies = TargetCertificateDependenciesValue[0..],
                });
                comptime CertificateValue.check(policy, SourceBody.certificate, SurfaceValue, SourceBody.source_map, SourceBody.effect_row, SourceBody.trace_map, SourceBody.normal_form, options.input.world_ports, PortTableValue, ValueTableValue, DispatchTableValue, ProfileValue, ReplayKeyRecipeValue, EvidenceMapValue, NormalizationCertificateValue, NormalizationTraceValue, NormalizationRedexesValue[0..], NormalizationRulesValue[0..], options.input.static_treaty_plans) catch |err|
                    @compileError("BoundaryClosure.Elaboration.Target certificate self-check failed: " ++ @errorName(err));
                comptime Conformance.check(SurfaceValue, PortTableValue, ValueTableValue, DispatchTableValue, ProfileValue, ReplayKeyRecipeValue) catch |err|
                    @compileError("BoundaryClosure.Elaboration.Target conformance failed: " ++ @errorName(err));

                return struct {
                    pub const Body = SourceBody;
                    pub const Program = ResidualProgram;
                    pub const WorldSurface = SurfaceValue;
                    pub const WorldPortTable = PortTableValue;
                    pub const WorldValueTable = ValueTableValue;
                    pub const WorldDispatchTable = DispatchTableValue;
                    pub const SourceMap = SourceBody.source_map;
                    pub const TraceMap = SourceBody.trace_map;
                    pub const EvidenceMap = EvidenceMapValue;
                    pub const EffectRow = SourceBody.effect_row;
                    pub const NormalForm = SourceBody.normal_form;
                    pub const NormalizationTrace = NormalizationTraceValue;
                    pub const NormalizationCertificate = NormalizationCertificateValue;
                    pub const RewriteSteps = NormalizationTraceValue.rewrite_steps;
                    pub const Redexes = NormalizationRedexesValue;
                    pub const Rules = NormalizationRulesValue;
                    pub const EliminatedRedexRefs = NormalizationTraceValue.eliminated_redex_refs;
                    pub const Certificate = CertificateValue;
                    pub const world_surface = SurfaceValue;
                    pub const world_port_table = PortTableValue;
                    pub const world_value_table = ValueTableValue;
                    pub const world_dispatch_table = DispatchTableValue;
                    pub const surface_profile = ProfileValue;
                    pub const replay_key_recipe = ReplayKeyRecipeValue;
                    pub const evidence_map = EvidenceMapValue;
                    pub const normalization_trace = NormalizationTraceValue;
                    pub const normalization_certificate = NormalizationCertificateValue;
                    pub const certificate = CertificateValue;
                    pub const effect_row = SourceBody.effect_row;
                    pub const normal_form = SourceBody.normal_form;

                    pub fn assertNormalForm(comptime expected: NormalFormKind) void {
                        if (SourceBody.normal_form.kind != expected) @compileError("Boundary Target normal form assertion failed");
                    }

                    pub fn assertWorldSurfaceReady() void {
                        @setEvalBranchQuota(2_000_000);
                        comptime Conformance.check(world_surface, world_port_table, world_value_table, world_dispatch_table, surface_profile, replay_key_recipe) catch |err|
                            @compileError("Boundary Target world surface is not ready: " ++ @errorName(err));
                    }

                    pub fn assertNoSearchHotPath() void {
                        if (!surface_profile.no_search_hot_path) @compileError("Boundary Target dispatch table is not dense");
                        if (effect_row.blockers != 0 or effect_row.unsupported_shapes != 0) @compileError("Boundary Target has unsupported residual internal redexes");
                        if (effect_row.world_ports != world_port_table.entries.len or effect_row.residual_world_ports != world_port_table.entries.len) @compileError("Boundary Target world-port counts do not match the dense table");
                        if (normal_form.kind == .strict_closed and world_port_table.entries.len != 0) @compileError("Boundary Target strict_closed surface cannot contain world ports");
                        if (normal_form.kind == .world_ports_only and effect_row.closed_effect_shapes + effect_row.world_ports != effect_row.source_effect_shapes) @compileError("Boundary Target world_ports_only has non-world residual effects");
                        inline for (world_port_table.entries, 0..) |port, index| {
                            if (port.world_port_id != @as(u32, @intCast(index))) @compileError("Boundary Target world ports are not densely numbered");
                            comptime var found_dispatch = false;
                            inline for (world_dispatch_table.entries) |dispatch| {
                                if (dispatch.world_port_id == port.world_port_id) {
                                    found_dispatch = true;
                                }
                            }
                            if (!found_dispatch) @compileError("Boundary Target residual world-port site is missing from dispatch table");
                        }
                    }

                    pub fn assertBoundedSurface() void {
                        if (!surface_profile.bounded) @compileError("Boundary Target surface is not bounded by policy");
                    }
                };
            }
        };

        fn targetOption(comptime options: anytype, comptime name: []const u8, comptime default: []const u8) []const u8 {
            return if (comptime @hasField(@TypeOf(options), name)) @field(options, name) else default;
        }

        fn targetLabelOption(comptime options: anytype, comptime default: []const u8) []const u8 {
            return if (comptime @hasField(@TypeOf(options), "target_label"))
                options.target_label
            else if (comptime @hasField(@TypeOf(options), "label"))
                options.label
            else
                default;
        }

        fn targetPolicyOption(comptime options: anytype) TargetPolicy {
            return if (comptime @hasField(@TypeOf(options), "target_policy"))
                options.target_policy
            else if (comptime @hasField(@TypeOf(options), "policy"))
                options.policy
            else
                .{};
        }

        fn assertTargetPolicySupported(comptime policy: TargetPolicy, comptime ResidualProgram: type) void {
            if (!targetPolicyEmitsRequiredArtifacts(policy)) {
                @compileError("Boundary Target requires source, trace, evidence, and world-surface artifact emission");
            }
            if (ResidualProgram.compiled_plan.functions.len > policy.max_generated_functions) {
                @compileError("Boundary Target residual program exceeds max_generated_functions");
            }
        }

        fn targetResidualProgramOption(comptime options: anytype) type {
            return if (comptime @hasField(@TypeOf(options), "residual_program"))
                options.residual_program
            else if (comptime @hasField(@TypeOf(options), "root"))
                options.root
            else
                @compileError("Boundary Target requires .residual_program or .root; no residual target generation path is implemented");
        }

        fn targetWorldPortEntryCount(comptime Body: type) usize {
            var count: usize = 0;
            inline for (Body.source_map.entries) |entry| {
                if (entry.world_port_ref != null) count += 1;
            }
            return count;
        }

        fn targetWorldPortEntries(
            comptime Body: type,
            comptime ResidualProgram: type,
            comptime static_treaty_plans: []const BoundaryStaticTreatyPlan,
            comptime policy: TargetPolicy,
        ) [targetWorldPortEntryCount(Body)]WorldPortTable.Entry {
            var entries: [targetWorldPortEntryCount(Body)]WorldPortTable.Entry = undefined;
            var index: usize = 0;
            inline for (Body.source_map.entries) |entry| {
                const world_port_ref = entry.world_port_ref orelse continue;
                const residual_site_index = entry.residual_site_index orelse
                    @compileError("Boundary Target world-port source-map entry is missing residual_site_index");
                const site = targetResidualSiteForIndex(ResidualProgram, residual_site_index) orelse
                    @compileError("Boundary Target world-port source-map entry points at a missing residual site");
                if (policy.fail_on_schema_mismatch and entry.static_treaty_plan_ref == null) {
                    @compileError("Boundary Target world-port source-map entry is missing schema witness");
                }
                if (!targetWorldPortEntrySchemaMatches(entry, site, static_treaty_plans, policy)) {
                    @compileError("Boundary Target world-port schema mismatch");
                }
                if (index >= WorldDispatchTable.missing_world_port_id) @compileError("Boundary Target supports at most 4294967295 world ports in one surface");
                entries[index] = .{
                    .world_port_id = @intCast(index),
                    .residual_site_index = residual_site_index,
                    .residual_site_fingerprint = site.fingerprint,
                    .world_port_ref = world_port_ref,
                    .source_ref = entry.source_ref,
                    .payload_ref = BoundaryValueRef.fromValueRef(site.payload_ref),
                    .resume_ref = BoundaryValueRef.fromValueRef(site.resume_ref),
                    .result_ref = BoundaryValueRef.fromValueRef(site.result_ref),
                    .protocol_label = site.requirement_label,
                    .op_name = site.op_name,
                    .mode = @tagName(site.op_mode),
                    .semantic_label = if (policy.preserve_semantic_labels) site.semantic_label else null,
                };
                index += 1;
            }
            return entries;
        }

        fn targetWorldPortEntrySchemaMatches(
            comptime entry: SourceMap.Entry,
            comptime site: lowering_api.SessionOperationYieldSite,
            comptime static_treaty_plans: []const BoundaryStaticTreatyPlan,
            comptime policy: TargetPolicy,
        ) bool {
            if (!policy.fail_on_schema_mismatch) return true;
            const plan_ref = entry.static_treaty_plan_ref orelse return true;
            const plan = staticTreatyPlanForRef(static_treaty_plans, plan_ref) orelse return false;
            const shape = if (plan.selected_morphism_ref != null)
                plan.morphismTargetShapeWitness() orelse return false
            else
                plan.source_shape;
            if (shape.kind != .operation) return false;
            if (policy.preserve_source_coordinates) {
                const expected_site_index = shape.site_index orelse return false;
                if (plan.selected_morphism_ref != null) {
                    if (expected_site_index != site.index) return false;
                } else if (entry.source_site_index != expected_site_index) return false;
            }
            if (shape.protocol_label.len == 0 or !std.mem.eql(u8, shape.protocol_label, site.requirement_label)) return false;
            if (shape.protocol_op_fingerprint) |protocol_op_fingerprint| {
                if (protocol_op_fingerprint != site.fingerprint) return false;
            } else if (shape.site_fingerprint == null) return false;
            if (shape.site_fingerprint) |site_fingerprint| {
                if (site_fingerprint != site.fingerprint) return false;
            }
            const expected_payload_ref = shape.value_ref orelse return false;
            if (!expected_payload_ref.eql(BoundaryValueRef.fromValueRef(site.payload_ref))) return false;
            if (shape.mode.len != 0 and !std.mem.eql(u8, shape.mode, @tagName(site.op_mode))) return false;
            if (shape.expected_resume_ref) |expected_resume_ref| {
                if (!expected_resume_ref.eql(BoundaryValueRef.fromValueRef(site.resume_ref))) return false;
            } else if (site.op_mode != .abort) {
                return false;
            }
            if (shape.result_ref) |expected_result_ref| {
                if (!expected_result_ref.eql(BoundaryValueRef.fromValueRef(site.result_ref))) return false;
            } else if (site.op_mode != .transform) {
                return false;
            }
            return true;
        }

        fn targetResidualSiteForIndex(comptime ResidualProgram: type, comptime residual_site_index: usize) ?lowering_api.SessionOperationYieldSite {
            inline for (ResidualProgram.contract.session.yield_sites) |site| {
                if (site.index == residual_site_index) return site;
            }
            return null;
        }

        fn targetWorldValueEntries(comptime port_entries: anytype) [port_entries.len * 3]WorldValueTable.Entry {
            var entries: [port_entries.len * 3]WorldValueTable.Entry = undefined;
            inline for (port_entries, 0..) |port, index| {
                const base = index * 3;
                entries[base] = .{ .value_id = @intCast(base), .world_port_id = port.world_port_id, .kind = .payload, .ref = port.payload_ref };
                entries[base + 1] = .{ .value_id = @intCast(base + 1), .world_port_id = port.world_port_id, .kind = .@"resume", .ref = port.resume_ref };
                entries[base + 2] = .{ .value_id = @intCast(base + 2), .world_port_id = port.world_port_id, .kind = .result, .ref = port.result_ref };
            }
            return entries;
        }

        fn targetWorldDispatchEntryCount(comptime port_entries: anytype) usize {
            var count: usize = 0;
            inline for (port_entries) |port| {
                if (port.residual_site_index == std.math.maxInt(usize)) @compileError("Boundary Target residual site index is too large for dense dispatch");
                const needed = port.residual_site_index + 1;
                if (needed > count) count = needed;
            }
            return count;
        }

        fn targetWorldDispatchEntries(comptime port_entries: anytype) [targetWorldDispatchEntryCount(port_entries)]WorldDispatchTable.Entry {
            var entries: [targetWorldDispatchEntryCount(port_entries)]WorldDispatchTable.Entry = undefined;
            inline for (0..entries.len) |index| {
                entries[index] = .{
                    .residual_site_index = index,
                    .residual_site_fingerprint = 0,
                    .world_port_id = WorldDispatchTable.missing_world_port_id,
                };
            }
            inline for (port_entries) |port| {
                entries[port.residual_site_index] = .{
                    .residual_site_index = port.residual_site_index,
                    .residual_site_fingerprint = port.residual_site_fingerprint,
                    .world_port_id = port.world_port_id,
                };
            }
            return entries;
        }

        fn targetDispatchEntriesDense(comptime dispatch_entries: []const WorldDispatchTable.Entry) bool {
            inline for (dispatch_entries, 0..) |entry, index| {
                if (entry.residual_site_index != index) return false;
            }
            return true;
        }

        fn targetDependencies(
            comptime Body: type,
            comptime surface: WorldSurface,
            comptime port_table: WorldPortTable,
            comptime value_table: WorldValueTable,
            comptime dispatch_table: WorldDispatchTable,
            comptime profile: SurfaceProfile,
            comptime replay_key_recipe: ReplayKeyRecipe,
        ) [11]Dependency {
            return .{
                .{ .role = .elaboration_certificate, .ref = Body.certificate.evidenceRef() },
                .{ .role = .elaboration_source_map, .ref = Body.source_map.evidenceRef() },
                .{ .role = .elaboration_effect_row, .ref = Body.effect_row.evidenceRef() },
                .{ .role = .elaboration_trace_map, .ref = Body.trace_map.evidenceRef() },
                .{ .role = .world_surface, .ref = surface.evidenceRef() },
                .{ .role = .world_port_table, .ref = port_table.evidenceRef() },
                .{ .role = .world_value_table, .ref = value_table.evidenceRef() },
                .{ .role = .world_dispatch_table, .ref = dispatch_table.evidenceRef() },
                .{ .role = .surface_profile, .ref = profile.evidenceRef() },
                .{ .role = .replay_key_recipe, .ref = replay_key_recipe.evidenceRef() },
                .{ .role = .residual_program, .ref = Body.certificate.residual_program_ref },
            };
        }

        fn normalFormKindFor(comptime input: Input) NormalFormKind {
            if (input.closure_report.blocker_count != 0) return .partial_with_blockers;
            if (input.closure_report.open_world_port_count != 0) return .world_ports_only;
            return .strict_closed;
        }

        fn elaborationOption(comptime options: anytype, comptime name: []const u8, comptime default: []const u8) []const u8 {
            return if (comptime @hasField(@TypeOf(options), name)) @field(options, name) else default;
        }

        fn sourceEntryCount(comptime input: Input) usize {
            return if (input.static_treaty_plans.len != 0)
                input.static_treaty_plans.len + directClosureBlockerCount(input)
            else if (input.world_ports.len != 0)
                input.closure_report.world_port_refs.len + input.closure_report.blockers.len
            else if (input.closure_report.blockers.len != 0)
                input.closure_report.blockers.len
            else
                0;
        }

        fn directClosureBlockerCount(comptime input: Input) usize {
            var count: usize = 0;
            inline for (input.closure_report.blockers) |blocker| {
                if (!staticTreatyPlansContainBlocker(input.static_treaty_plans, blocker)) count += 1;
            }
            return count;
        }

        fn staticTreatyPlansContainBlocker(comptime plans: []const Closure.StaticTreatyPlan, comptime blocker: anytype) bool {
            const blocker_ref = refForBoundaryClosureBlocker(blocker);
            inline for (plans) |plan| {
                inline for (plan.blockers) |plan_blocker| {
                    if (refForBoundaryClosureBlocker(plan_blocker.toEvidenceBlocker()).eql(blocker_ref)) return true;
                }
            }
            return false;
        }

        fn sourceEntriesFor(comptime input: Input, comptime residual_ref: Ref, comptime ResidualProgram: type, comptime options: anytype) [sourceEntryCount(input)]SourceMap.Entry {
            _ = options;
            var entries: [sourceEntryCount(input)]SourceMap.Entry = undefined;
            var index: usize = 0;
            if (input.static_treaty_plans.len != 0) {
                inline for (input.static_treaty_plans, 0..) |plan, plan_index| {
                    if (comptime worldPortForPlan(input, ResidualProgram, plan)) |port| {
                        const residual_site_index = comptime residualWorldPortSiteIndexForOccurrence(
                            ResidualProgram,
                            port,
                            worldPortPlanOccurrenceRank(input, ResidualProgram, port.evidenceRef(), plan_index),
                        ) orelse
                            @compileError("BoundaryClosure.Elaboration world port is not exposed by the residual Program");
                        entries[index] = .{
                            .source_ref = if (plan.selected_morphism_ref != null) plan.selected_morphism_target_shape_ref.? else plan.source_shape.evidenceRef(),
                            .residual_ref = residual_ref,
                            .source_site_index = plan.source_shape.site_index,
                            .residual_site_index = residual_site_index,
                            .static_treaty_plan_ref = plan.evidenceRef(),
                            .world_port_ref = port.evidenceRef(),
                            .disposition = .world_port_lowered,
                            .label = plan.label,
                        };
                    } else if (comptime planBlockedForElaboration(input, plan)) {
                        entries[index] = .{
                            .source_ref = plan.source_shape.evidenceRef(),
                            .residual_ref = residual_ref,
                            .source_site_index = plan.source_shape.site_index,
                            .static_treaty_plan_ref = plan.evidenceRef(),
                            .disposition = .blocked,
                            .label = plan.label,
                        };
                    } else {
                        const body = comptime routeSemanticBody(plan);
                        entries[index] = .{
                            .source_ref = plan.source_shape.evidenceRef(),
                            .residual_ref = residual_ref,
                            .source_site_index = plan.source_shape.site_index,
                            .static_treaty_plan_ref = plan.evidenceRef(),
                            .provider_program_ref = plan.selected_provider_program_ref,
                            .disposition = if (body == .boundary_program) .provider_program_linked else if (body == .pipeline) .pipeline_adapter else if (body == .residualized_program) .residualized else .preserved,
                            .label = plan.label,
                        };
                    }
                    index += 1;
                }
                inline for (input.closure_report.blockers) |blocker| {
                    if (!comptime staticTreatyPlansContainBlocker(input.static_treaty_plans, blocker)) {
                        entries[index] = blockerSourceEntry(blocker, residual_ref);
                        index += 1;
                    }
                }
            } else if (input.world_ports.len != 0) {
                inline for (input.closure_report.world_port_refs, 0..) |world_port_ref, occurrence_index| {
                    const port = comptime worldPortForOccurrenceRef(input.world_ports, world_port_ref) orelse
                        @compileError("BoundaryClosure.Elaboration world port ref is not provided by the input descriptors");
                    const residual_site_index = comptime residualWorldPortSiteIndexForOccurrence(
                        ResidualProgram,
                        port,
                        worldPortOccurrenceRank(input.closure_report.world_port_refs, world_port_ref, occurrence_index),
                    ) orelse
                        @compileError("BoundaryClosure.Elaboration world port is not exposed by the residual Program");
                    const source_site_index = if (port.effect_shape_ref) |shape_ref| shape_ref.site_index orelse residual_site_index else residual_site_index;
                    entries[index] = .{
                        .source_ref = port.effect_shape_ref orelse port.evidenceRef(),
                        .residual_ref = residual_ref,
                        .source_site_index = source_site_index,
                        .residual_site_index = residual_site_index,
                        .world_port_ref = port.evidenceRef(),
                        .disposition = .world_port_lowered,
                        .label = port.label,
                    };
                    index += 1;
                }
                inline for (input.closure_report.blockers) |blocker| {
                    entries[index] = blockerSourceEntry(blocker, residual_ref);
                    index += 1;
                }
            } else if (input.closure_report.blockers.len != 0) {
                inline for (input.closure_report.blockers) |blocker| {
                    entries[index] = blockerSourceEntry(blocker, residual_ref);
                    index += 1;
                }
            }
            return entries;
        }

        fn sourceEntriesEffectShapeCount(comptime entries: anytype) usize {
            var count: usize = 0;
            inline for (entries, 0..) |entry, index| {
                if (!sourceEntryRepresentsEffectShape(entry)) continue;
                if (sourceEntryIsDirectBlocker(entry)) {
                    if (sourceEntriesHavePlannedSourceRef(entries, entry.source_ref)) continue;
                    if (sourceEntriesPriorDirectBlockerHasSourceRef(entries[0..index], entry.source_ref)) continue;
                }
                count += 1;
            }
            return count;
        }

        fn sourceEntryIsDirectBlocker(comptime entry: SourceMap.Entry) bool {
            return entry.disposition == .blocked and entry.static_treaty_plan_ref == null;
        }

        fn sourceEntriesHavePlannedSourceRef(comptime entries: anytype, comptime source_ref: Ref) bool {
            inline for (entries) |entry| {
                if (sourceEntryIsDirectBlocker(entry)) continue;
                if (sourceEntryRepresentsEffectShape(entry) and entry.source_ref.eql(source_ref)) return true;
            }
            return false;
        }

        fn sourceEntriesPriorDirectBlockerHasSourceRef(comptime entries: anytype, comptime source_ref: Ref) bool {
            inline for (entries) |entry| {
                if (sourceEntryIsDirectBlocker(entry) and entry.source_ref.eql(source_ref)) return true;
            }
            return false;
        }

        fn sourceEntryRepresentsEffectShape(comptime entry: SourceMap.Entry) bool {
            if (entry.disposition != .blocked) return true;
            if (entry.static_treaty_plan_ref != null) return true;
            return entry.source_ref.domain_id == domains.boundary_effect_shape.id;
        }

        fn sourceEntriesBlockedUnsupportedShapeCount(comptime input: Input, comptime entries: anytype) usize {
            var count: usize = 0;
            inline for (entries) |entry| {
                if (sourceEntryIsUnsupportedShapeBlocker(input, entry)) count += 1;
            }
            return count;
        }

        fn sourceEntryIsUnsupportedShapeBlocker(comptime input: Input, comptime entry: SourceMap.Entry) bool {
            if (entry.disposition != .blocked) return false;
            if (!sourceEntryRepresentsEffectShape(entry)) return false;
            if (entry.static_treaty_plan_ref) |plan_ref| {
                const plan = staticTreatyPlanForRef(input.static_treaty_plans, plan_ref) orelse return false;
                return staticTreatyPlanHasUnsupportedShapeBlocker(plan);
            }
            if (entry.blocker_ref) |blocker_ref| return blockerRefCountsUnsupported(blocker_ref);
            return blockerNameCountsUnsupported(entry.label);
        }

        fn blockerSourceEntry(comptime blocker: anytype, comptime residual_ref: Ref) SourceMap.Entry {
            return .{
                .source_ref = blocker.subject orelse refForBoundaryClosureBlocker(blocker),
                .residual_ref = residual_ref,
                .source_site_index = blocker.site_index,
                .blocker_ref = refForBoundaryClosureBlocker(blocker),
                .disposition = .blocked,
                .label = if (blocker.short_code.len != 0) blocker.short_code else blocker.summary,
            };
        }

        fn planBlockedForElaboration(input: anytype, plan: Closure.StaticTreatyPlan) bool {
            return plan.blockers.len != 0 and !plan.closedUnderPolicy(inputClosurePolicy(input));
        }

        fn inputClosurePolicy(input: anytype) Closure.Policy {
            if (comptime @hasField(@TypeOf(input), "target_policy")) return boundaryTargetElaborationPolicy(input.target_policy).closure_policy;
            if (comptime @hasField(@TypeOf(input), "policy")) return input.policy.closure_policy;
            @compileError("Boundary normalization route input must expose target_policy or policy");
        }

        fn routeSemanticBody(plan: Closure.StaticTreatyPlan) SemanticBody {
            if (plan.selected_semantic_body == .boundary_program) return .boundary_program;
            return plan.selected_morphism_semantic_body orelse plan.selected_semantic_body;
        }

        fn residualizedRouteCount(comptime input: Input) usize {
            var count: usize = 0;
            inline for (input.static_treaty_plans) |plan| {
                if (planBlockedForElaboration(input, plan)) continue;
                if (staticTreatyPlanHasShapeOnlyWorldPort(input, plan)) continue;
                if (routeSemanticBody(plan) == .residualized_program) count += 1;
            }
            return count;
        }

        fn pipelineRouteCount(comptime input: Input) usize {
            var count: usize = 0;
            inline for (input.static_treaty_plans) |plan| {
                if (planBlockedForElaboration(input, plan)) continue;
                if (staticTreatyPlanHasShapeOnlyWorldPort(input, plan)) continue;
                if (routeSemanticBody(plan) == .pipeline) count += 1;
            }
            return count;
        }

        fn providerProgramRouteCount(comptime input: Input) usize {
            var count: usize = 0;
            inline for (input.static_treaty_plans) |plan| {
                if (planBlockedForElaboration(input, plan)) continue;
                if (staticTreatyPlanHasShapeOnlyWorldPort(input, plan)) continue;
                if (plan.selected_provider_program_ref != null) count += 1;
            }
            return count;
        }

        fn linkedProviderProgramCount(comptime input: Input) usize {
            var refs: [input.static_treaty_plans.len]Ref = undefined;
            var count: usize = 0;
            inline for (input.static_treaty_plans) |plan| {
                if (planBlockedForElaboration(input, plan)) continue;
                if (staticTreatyPlanHasShapeOnlyWorldPort(input, plan)) continue;
                const program_ref = plan.selected_provider_program_ref orelse continue;
                var seen = false;
                for (refs[0..count]) |ref| {
                    if (ref.eql(program_ref)) {
                        seen = true;
                        break;
                    }
                }
                if (!seen) {
                    refs[count] = program_ref;
                    count += 1;
                }
            }
            return count;
        }

        fn linkedProviderProgramRefs(comptime input: Input) [linkedProviderProgramCount(input)]Ref {
            var refs: [linkedProviderProgramCount(input)]Ref = undefined;
            var count: usize = 0;
            inline for (input.static_treaty_plans) |plan| {
                if (planBlockedForElaboration(input, plan)) continue;
                if (staticTreatyPlanHasShapeOnlyWorldPort(input, plan)) continue;
                const program_ref = plan.selected_provider_program_ref orelse continue;
                var seen = false;
                for (refs[0..count]) |ref| {
                    if (ref.eql(program_ref)) {
                        seen = true;
                        break;
                    }
                }
                if (!seen) {
                    refs[count] = program_ref;
                    count += 1;
                }
            }
            return refs;
        }

        fn providerProgramNestedShapeCount(input: Input) usize {
            var count: usize = 0;
            for (input.provider_programs) |program| {
                if (providerProgramSelectedByStaticPlans(input, program)) {
                    count += program.shapes.len;
                }
            }
            return count;
        }

        fn providerProgramNestedDepth(input: Input) usize {
            var depth: usize = 0;
            for (input.provider_programs) |program| {
                if (providerProgramSelectedByStaticPlans(input, program)) {
                    depth = @max(depth, providerProgramNestedDepthFrom(input, program, 0));
                }
            }
            return depth;
        }

        fn providerProgramNestedDepthFrom(input: Input, program: Closure.ProviderProgram, seen_count: usize) usize {
            if (program.shapes.len == 0) return 0;
            if (seen_count >= input.provider_programs.len) return seen_count + 1;
            var child_depth: usize = 0;
            for (program.shapes) |shape| {
                const plan = staticTreatyPlanForShape(input.static_treaty_plans, shape) orelse continue;
                const child_program = providerProgramSelectedByPlan(input, plan) orelse continue;
                child_depth = @max(child_depth, providerProgramNestedDepthFrom(input, child_program, seen_count + 1));
            }
            return 1 + child_depth;
        }

        fn staticTreatyPlanForShape(plans: []const Closure.StaticTreatyPlan, shape: Closure.EffectShape) ?Closure.StaticTreatyPlan {
            const shape_ref = shape.evidenceRef();
            for (plans) |plan| {
                if (plan.source_shape.evidenceRef().eql(shape_ref)) return plan;
            }
            return null;
        }

        fn providerProgramSelectedByPlan(input: anytype, plan: Closure.StaticTreatyPlan) ?Closure.ProviderProgram {
            if (planBlockedForElaboration(input, plan)) return null;
            if (staticTreatyPlanHasShapeOnlyWorldPort(input, plan)) return null;
            const provider_ref = plan.selected_provider_ref orelse return null;
            const program_ref = plan.selected_provider_program_ref orelse return null;
            const mapping_fingerprint = plan.selected_provider_program_mapping_fingerprint orelse return null;
            const shape_count = plan.selected_provider_program_effect_shape_count orelse return null;
            const shape_fingerprint = plan.selected_provider_program_effect_shape_fingerprint orelse return null;
            for (input.provider_programs) |program| {
                if (!provider_ref.eql(program.provider_ref)) continue;
                if (!program_ref.eql(program.program_ref)) continue;
                if (program.provider_program_mapping_fingerprint == null or
                    program.provider_program_mapping_fingerprint.? != mapping_fingerprint) continue;
                if (!providerProgramMappingSupportedForPlan(program, plan)) continue;
                if (providerProgramShapesMatchPlan(program, program_ref, @intCast(shape_count), shape_fingerprint)) return program;
            }
            return null;
        }

        fn providerProgramSelectedByStaticPlans(input: Input, program: Closure.ProviderProgram) bool {
            for (input.static_treaty_plans) |plan| {
                if (planBlockedForElaboration(input, plan)) continue;
                if (staticTreatyPlanHasShapeOnlyWorldPort(input, plan)) continue;
                const provider_ref = plan.selected_provider_ref orelse continue;
                if (!provider_ref.eql(program.provider_ref)) continue;
                const program_ref = plan.selected_provider_program_ref orelse continue;
                if (!program_ref.eql(program.program_ref)) continue;
                const mapping_fingerprint = plan.selected_provider_program_mapping_fingerprint orelse continue;
                if (program.provider_program_mapping_fingerprint == null or
                    program.provider_program_mapping_fingerprint.? != mapping_fingerprint) continue;
                if (!providerProgramMappingSupportedForPlan(program, plan)) continue;
                const shape_count = plan.selected_provider_program_effect_shape_count orelse continue;
                const shape_fingerprint = plan.selected_provider_program_effect_shape_fingerprint orelse continue;
                if (providerProgramShapesMatchPlan(program, program_ref, @intCast(shape_count), shape_fingerprint)) return true;
            }
            return false;
        }

        fn worldPortForPlan(comptime input: Input, comptime ResidualProgram: type, comptime plan: Closure.StaticTreatyPlan) ?Closure.WorldPort {
            _ = ResidualProgram;
            if (plan.selected_morphism_ref != null and plan.selected_morphism_target_shape_ref == null) return null;
            var target_response_refs_buffer: [3]BoundaryValueRef = undefined;
            const shape = worldPortShapeForPlan(input, plan, &target_response_refs_buffer) orelse return null;
            if (staticTreatyPlanCanLowerToWorldPort(plan)) {
                if (plan.selected_morphism_semantic_body == .host_intrinsic) {
                    const intrinsic_ref = plan.selected_morphism_intrinsic_ref orelse return null;
                    return worldPortForIntrinsic(input, intrinsic_ref, shape);
                }
                const intrinsic_ref = plan.selected_intrinsic_ref orelse return null;
                return worldPortForIntrinsic(input, intrinsic_ref, shape);
            }
            if (staticTreatyPlanShapeOnlyWorldPortAllowed(plan)) {
                if (worldPortForShapeOnly(input, shape)) |port| return port;
            }
            return null;
        }

        fn worldPortShapeForPlan(input: anytype, plan: Closure.StaticTreatyPlan, target_response_refs_buffer: *[3]BoundaryValueRef) ?Closure.EffectShape {
            if (plan.selected_morphism_ref) |morphism_ref| {
                if (morphismOfferForRef(input.morphism_offers, morphism_ref)) |morphism| {
                    const offer_shape = morphismTargetShape(plan.source_shape, morphism, target_response_refs_buffer);
                    if (selectedMorphismTargetShape(plan)) |target_shape| {
                        if (!refSubjectsEqual(target_shape.evidenceRef(), offer_shape.evidenceRef())) return null;
                        return target_shape;
                    }
                    return offer_shape;
                }
                return null;
            }
            return plan.source_shape;
        }

        fn selectedMorphismTargetShape(plan: Closure.StaticTreatyPlan) ?Closure.EffectShape {
            const target_shape = plan.morphismTargetShapeWitness() orelse return null;
            const target_shape_ref = plan.selected_morphism_target_shape_ref orelse return null;
            if (target_shape.fingerprint != target_shape.computeFingerprint()) return null;
            if (!refSubjectsEqual(target_shape.evidenceRef(), target_shape_ref)) return null;
            return target_shape;
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

        fn morphismOfferForRef(morphisms: []const ProgramType.Exchange.MorphismOffer, ref: Ref) ?ProgramType.Exchange.MorphismOffer {
            for (morphisms) |morphism| {
                if (morphism.evidenceRef().eql(ref)) return morphism;
            }
            return null;
        }

        fn worldPortForIntrinsic(comptime input: Input, comptime intrinsic_ref: Ref, comptime shape: Closure.EffectShape) ?Closure.WorldPort {
            inline for (input.world_ports) |port| {
                const exposed_ref = port.exposed_intrinsic_ref orelse continue;
                if (!refSubjectsEqual(exposed_ref, intrinsic_ref)) continue;
                if (!worldPortMatchesSourceShape(port, shape)) continue;
                return port;
            }
            return null;
        }

        fn worldPortForShapeOnly(comptime input: Input, comptime shape: Closure.EffectShape) ?Closure.WorldPort {
            inline for (input.world_ports) |port| {
                if (port.exposed_intrinsic_ref != null) continue;
                if (port.effect_shape_ref) |shape_ref| {
                    if (!refSubjectsEqual(shape_ref, shape.evidenceRef())) continue;
                }
                if (!worldPortMatchesSourceShape(port, shape)) continue;
                return port;
            }
            return null;
        }

        fn residualWorldPortSiteIndex(comptime ResidualProgram: type, comptime port: Closure.WorldPort) ?usize {
            inline for (ResidualProgram.contract.session.yield_sites) |site| {
                if (!residualWorldPortSupportsSite(port, site)) continue;
                return site.index;
            }
            return null;
        }

        fn residualWorldPortSiteIndexForOccurrence(comptime ResidualProgram: type, comptime port: Closure.WorldPort, comptime occurrence_rank: usize) ?usize {
            var rank: usize = 0;
            inline for (ResidualProgram.contract.session.yield_sites) |site| {
                if (!residualWorldPortSupportsSite(port, site)) continue;
                if (rank == occurrence_rank) return site.index;
                rank += 1;
            }
            return null;
        }

        fn worldPortForOccurrenceRef(comptime ports: []const Closure.WorldPort, comptime ref: Ref) ?Closure.WorldPort {
            inline for (ports) |port| {
                if (port.evidenceRef().eql(ref)) return port;
            }
            return null;
        }

        fn worldPortOccurrenceRank(comptime refs: []const Ref, comptime ref: Ref, comptime occurrence_index: usize) usize {
            var rank: usize = 0;
            inline for (refs[0..occurrence_index]) |prior_ref| {
                if (prior_ref.eql(ref)) rank += 1;
            }
            return rank;
        }

        fn worldPortPlanOccurrenceRank(comptime input: Input, comptime ResidualProgram: type, comptime ref: Ref, comptime plan_index: usize) usize {
            var rank: usize = 0;
            inline for (input.static_treaty_plans[0..plan_index]) |prior_plan| {
                if (comptime worldPortForPlan(input, ResidualProgram, prior_plan)) |prior_port| {
                    if (prior_port.evidenceRef().eql(ref)) rank += 1;
                }
            }
            return rank;
        }

        fn residualWorldPortSiteCount(comptime ResidualProgram: type, comptime port: Closure.WorldPort) usize {
            var count: usize = 0;
            inline for (ResidualProgram.contract.session.yield_sites) |site| {
                if (!residualWorldPortSupportsSite(port, site)) continue;
                count += 1;
            }
            return count;
        }

        fn residualYieldSiteWorldPortCoverageCount(comptime site: anytype, comptime ports: []const Closure.WorldPort) usize {
            var count: usize = 0;
            inline for (ports) |port| {
                if (!residualWorldPortSupportsSite(port, site)) continue;
                count += 1;
            }
            return count;
        }

        fn residualWorldPortSupportsSite(comptime port: Closure.WorldPort, comptime site: anytype) bool {
            return worldPortSupportsRequirement(port, site.requirement_label) and
                worldPortSupportsSiteIndex(port, site.index) and
                worldPortSupportsOperationFingerprint(port, site.fingerprint);
        }

        fn worldPortMatchesSourceShape(port: Closure.WorldPort, shape: Closure.EffectShape) bool {
            if (port.effect_shape_ref) |shape_ref| {
                if (!refSubjectsEqual(shape_ref, shape.evidenceRef())) return false;
            }
            if (shape.site_index) |site_index| {
                if (!worldPortSupportsSiteIndex(port, site_index)) return false;
            }
            if (!worldPortSupportsRequirement(port, shape.protocol_label)) return false;
            if (shape.protocol_op_fingerprint) |fingerprint| {
                if (!worldPortSupportsOperationFingerprint(port, fingerprint)) return false;
            }
            return true;
        }

        fn worldPortSupportsSiteIndex(port: Closure.WorldPort, site_index: usize) bool {
            if (port.supported_site_indexes.len == 0) return true;
            for (port.supported_site_indexes) |supported| {
                if (supported == site_index) return true;
            }
            return false;
        }

        fn worldPortSupportsRequirement(port: Closure.WorldPort, requirement_label: []const u8) bool {
            if (port.supported_protocol_labels.len == 0) return true;
            for (port.supported_protocol_labels) |label| {
                if (std.mem.eql(u8, label, requirement_label)) return true;
            }
            return false;
        }

        fn worldPortSupportsOperationFingerprint(port: Closure.WorldPort, fingerprint: u64) bool {
            if (port.supported_protocol_op_fingerprints.len == 0) return true;
            for (port.supported_protocol_op_fingerprints) |supported| {
                if (supported == fingerprint) return true;
            }
            return false;
        }

        fn traceEntriesForSourceEntries(comptime entries: anytype) [entries.len]TraceMap.Entry {
            var trace_entries: [entries.len]TraceMap.Entry = undefined;
            inline for (entries, 0..) |entry, index| {
                trace_entries[index] = .{
                    .source_ref = entry.source_ref,
                    .residual_ref = entry.world_port_ref orelse (entry.residual_ref orelse entry.source_ref),
                    .trace_label = entry.label,
                };
            }
            return trace_entries;
        }

        fn dependencyCount(comptime input: Input) usize {
            const base: usize = if (input.policy.emit_trace_map) 6 else 5;
            return base + providerProgramResidualBindingDependencyCount(input, input.residual_program_ref.?);
        }

        fn dependenciesFor(comptime input: Input, comptime source_map: SourceMap, comptime effect_row: EffectRow, comptime trace_map: anytype, comptime normal_form: NormalForm) [dependencyCount(input)]Dependency {
            var dependencies: [dependencyCount(input)]Dependency = undefined;
            const residual_ref = input.residual_program_ref.?;
            dependencies[0] = .{ .role = .closure_certificate, .ref = input.closure_certificate.evidenceRef() };
            dependencies[1] = .{ .role = .residual_program, .ref = residual_ref };
            dependencies[2] = .{ .role = .elaboration_source_map, .ref = source_map.evidenceRef() };
            dependencies[3] = .{ .role = .elaboration_effect_row, .ref = effect_row.evidenceRef() };
            var index: usize = 0;
            if (input.policy.emit_trace_map) {
                dependencies[4] = .{ .role = .elaboration_trace_map, .ref = trace_map.evidenceRef() };
                dependencies[5] = .{ .role = .normal_form, .ref = normal_form.evidenceRef() };
                index = 6;
            } else {
                dependencies[4] = .{ .role = .normal_form, .ref = normal_form.evidenceRef() };
                index = 5;
            }
            inline for (input.static_treaty_plans) |plan| {
                if (providerProgramResidualBindingDependencyRef(input, plan, residual_ref)) |ref| {
                    dependencies[index] = .{ .role = .provider_program_mapping, .ref = ref };
                    index += 1;
                }
            }
            return dependencies;
        }

        fn providerProgramResidualBindingDependencyCount(comptime input: Input, comptime residual_ref: Ref) usize {
            var count: usize = 0;
            inline for (input.static_treaty_plans) |plan| {
                if (providerProgramResidualBindingDependencyRef(input, plan, residual_ref) != null) count += 1;
            }
            return count;
        }

        fn providerProgramResidualBindingDependencyRef(comptime input: Input, comptime plan: Closure.StaticTreatyPlan, comptime residual_ref: Ref) ?Ref {
            if (routeSemanticBody(plan) != .boundary_program) return null;
            if (planHasDependencyRef(plan, .residual_program, residual_ref)) return null;
            if (!providerProgramResidualBindingSupported(input, plan, residual_ref)) return null;
            return refForProviderProgramResidualBinding(plan, residual_ref);
        }

        fn evidenceDependencyRefs(comptime dependencies: anytype) [dependencies.len]Ref {
            var refs: [dependencies.len]Ref = undefined;
            inline for (dependencies, 0..) |dependency, index| refs[index] = dependency.ref;
            return refs;
        }

        fn residualWorldPortRefs(comptime input: Input) [input.closure_report.world_port_refs.len]Ref {
            var refs: [input.closure_report.world_port_refs.len]Ref = undefined;
            inline for (input.closure_report.world_port_refs, 0..) |ref, index| refs[index] = ref;
            return refs;
        }

        fn blockerRefCount(comptime input: Input) usize {
            return if (input.closure_certificate.blocker_refs.len != 0) input.closure_certificate.blocker_refs.len else input.closure_report.blockers.len;
        }

        fn blockerRefsFor(comptime input: Input) [blockerRefCount(input)]Ref {
            var refs: [blockerRefCount(input)]Ref = undefined;
            if (input.closure_certificate.blocker_refs.len != 0) {
                inline for (input.closure_certificate.blocker_refs, 0..) |ref, index| refs[index] = ref;
            } else {
                inline for (input.closure_report.blockers, 0..) |blocker, index| refs[index] = refForBoundaryClosureBlocker(blocker);
            }
            return refs;
        }

        fn providerProgramRefsMatch(programs: []const Closure.ProviderProgram, refs: []const Ref) bool {
            if (!refsUnique(refs)) return false;
            if (!providerProgramProofsUnique(programs)) return false;
            for (refs) |expected_ref| {
                if (providerProgramRefCount(programs, expected_ref) == 0) return false;
            }
            for (programs) |program| {
                if (refCount(refs, program.program_ref) == 0) return false;
            }
            return true;
        }

        fn providerProgramProofSlicesEqual(lhs: []const Closure.ProviderProgram, rhs: []const Closure.ProviderProgram) bool {
            if (lhs.len != rhs.len) return false;
            for (lhs, rhs) |left, right| {
                if (!providerProgramProofsEqual(left, right)) return false;
            }
            return true;
        }

        fn staticTreatyPlanSlicesEqual(lhs: []const Closure.StaticTreatyPlan, rhs: []const Closure.StaticTreatyPlan) bool {
            if (lhs.len != rhs.len) return false;
            for (lhs, rhs) |left, right| {
                if (left.fingerprint != right.fingerprint or !left.evidenceRef().eql(right.evidenceRef())) return false;
            }
            return true;
        }

        fn morphismOfferSlicesEqual(lhs: []const ProgramType.Exchange.MorphismOffer, rhs: []const ProgramType.Exchange.MorphismOffer) bool {
            if (lhs.len != rhs.len) return false;
            for (lhs, rhs) |left, right| {
                if (!left.evidenceRef().eql(right.evidenceRef())) return false;
            }
            return true;
        }

        fn worldPortSlicesEqual(lhs: []const Closure.WorldPort, rhs: []const Closure.WorldPort) bool {
            if (lhs.len != rhs.len) return false;
            for (lhs, rhs) |left, right| {
                if (left.fingerprint != right.fingerprint or !left.evidenceRef().eql(right.evidenceRef())) return false;
            }
            return true;
        }

        fn providerProgramProofsUnique(programs: []const Closure.ProviderProgram) bool {
            for (programs, 0..) |program, index| {
                for (programs[index + 1 ..]) |other| {
                    if (providerProgramProofsEqual(program, other)) return false;
                }
            }
            return true;
        }

        fn providerProgramProofsEqual(lhs: Closure.ProviderProgram, rhs: Closure.ProviderProgram) bool {
            return lhs.provider_ref.eql(rhs.provider_ref) and
                lhs.program_ref.eql(rhs.program_ref) and
                lhs.provider_program_mapping_fingerprint == rhs.provider_program_mapping_fingerprint and
                lhs.provider_program_mapping_support_fingerprint == rhs.provider_program_mapping_support_fingerprint and
                lhs.effect_free == rhs.effect_free and
                lhs.shapes.len == rhs.shapes.len and
                fingerprintBoundaryEffectShapeSet(lhs.shapes) == fingerprintBoundaryEffectShapeSet(rhs.shapes);
        }

        fn refsUnique(refs: []const Ref) bool {
            for (refs, 0..) |ref, index| {
                for (refs[index + 1 ..]) |other| {
                    if (ref.eql(other)) return false;
                }
            }
            return true;
        }

        fn staticTreatyPlansAllowedByElaborationPolicy(input: Input) bool {
            for (input.static_treaty_plans) |plan| {
                if (planBlockedForElaboration(input, plan)) continue;
                if (staticTreatyPlanHasShapeOnlyWorldPort(input, plan)) {
                    if (!shapeOnlyWorldPortPlanHasMorphismProof(input, plan)) return false;
                    continue;
                }
                switch (routeSemanticBody(plan)) {
                    .boundary_program => {
                        if (!input.policy.allow_provider_program_linking) return false;
                        if (plan.selected_provider_program_ref == null) return false;
                    },
                    .declarative => {
                        if (input.policy.require_program_backed_providers_for_internal_routes) return false;
                        if (!input.policy.allow_declarative_morphisms) return false;
                        if (!planHasMorphismProof(plan, .declarative, input.morphism_offer_refs)) return false;
                    },
                    .residualized_program => {
                        if (input.policy.require_program_backed_providers_for_internal_routes) return false;
                        if (!input.policy.allow_residualized_morphisms) return false;
                        if (!planHasMorphismProof(plan, .residualized_program, input.morphism_offer_refs)) return false;
                        if (!planHasBoundDependency(plan, .residual_program, input.residualization_adapter_refs)) return false;
                    },
                    .pipeline => {
                        if (input.policy.require_program_backed_providers_for_internal_routes) return false;
                        if (!input.policy.allow_pipeline_adapters) return false;
                        if (!planHasMorphismProof(plan, .pipeline, input.morphism_offer_refs)) return false;
                        if (!planHasBoundDependency(plan, .pipeline, input.pipeline_adapter_refs)) return false;
                    },
                    .host_intrinsic => {
                        const intrinsic_ref = staticTreatyPlanWorldPortIntrinsicRef(plan) orelse return false;
                        if (!elaborationPolicyAllowsWorldPortIntrinsic(input.policy, intrinsic_ref)) return false;
                        if (plan.selected_morphism_ref != null and
                            !planHasMorphismProof(plan, .host_intrinsic, input.morphism_offer_refs)) return false;
                    },
                    .unknown => return false,
                    .kernel_primitive => return false,
                }
            }
            if (!inputRefsBoundToPlanDependencies(input.static_treaty_plans, .morphism, input.morphism_offer_refs)) return false;
            if (!inputRefsBoundToPlanDependencies(input.static_treaty_plans, .residual_program, input.residualization_adapter_refs)) return false;
            if (!inputRefsBoundToPlanDependencies(input.static_treaty_plans, .pipeline, input.pipeline_adapter_refs)) return false;
            return true;
        }

        fn shapeOnlyWorldPortPlanHasMorphismProof(input: Input, plan: Closure.StaticTreatyPlan) bool {
            if (plan.selected_morphism_ref == null) return true;
            return switch (routeSemanticBody(plan)) {
                .declarative => input.policy.allow_declarative_morphisms and
                    planHasMorphismProof(plan, .declarative, input.morphism_offer_refs),
                .residualized_program => input.policy.allow_residualized_morphisms and
                    planHasMorphismProof(plan, .residualized_program, input.morphism_offer_refs) and
                    planHasBoundDependency(plan, .residual_program, input.residualization_adapter_refs),
                .pipeline => input.policy.allow_pipeline_adapters and
                    planHasMorphismProof(plan, .pipeline, input.morphism_offer_refs) and
                    planHasBoundDependency(plan, .pipeline, input.pipeline_adapter_refs),
                .boundary_program,
                .host_intrinsic,
                .unknown,
                .kernel_primitive,
                => false,
            };
        }

        fn staticTreatyPlanHasShapeOnlyWorldPort(input: anytype, plan: Closure.StaticTreatyPlan) bool {
            if (!staticTreatyPlanShapeOnlyWorldPortAllowed(plan)) return false;
            if (plan.selected_morphism_ref != null and plan.selected_morphism_target_shape_ref == null) return false;
            var target_response_refs_buffer: [3]BoundaryValueRef = undefined;
            const shape = worldPortShapeForPlan(input, plan, &target_response_refs_buffer) orelse return false;
            for (input.world_ports) |port| {
                if (port.exposed_intrinsic_ref != null) continue;
                if (worldPortMatchesSourceShape(port, shape)) return true;
            }
            return false;
        }

        fn staticTreatyPlanShapeOnlyWorldPortAllowed(plan: Closure.StaticTreatyPlan) bool {
            return switch (routeSemanticBody(plan)) {
                .declarative,
                .residualized_program,
                .pipeline,
                => true,
                .boundary_program,
                .host_intrinsic,
                .unknown,
                .kernel_primitive,
                => false,
            };
        }

        fn hostIntrinsicPlansHaveWorldPorts(input: Input) bool {
            for (input.static_treaty_plans) |plan| {
                if (planBlockedForElaboration(input, plan)) continue;
                if (routeSemanticBody(plan) != .host_intrinsic) continue;
                if (plan.selected_morphism_ref != null and plan.selected_morphism_target_shape_ref == null) return false;
                const intrinsic_ref = staticTreatyPlanWorldPortIntrinsicRef(plan) orelse return false;
                var target_response_refs_buffer: [3]BoundaryValueRef = undefined;
                const shape = worldPortShapeForPlan(input, plan, &target_response_refs_buffer) orelse return false;
                if (!worldPortForIntrinsicPlanExists(shape, intrinsic_ref, input.world_ports)) return false;
            }
            return true;
        }

        fn worldPortForIntrinsicPlanExists(shape: Closure.EffectShape, intrinsic_ref: Ref, ports: []const Closure.WorldPort) bool {
            for (ports) |port| {
                if (!worldPortMatchesSourceShape(port, shape)) continue;
                const port_intrinsic_ref = port.exposed_intrinsic_ref orelse continue;
                if (!refSubjectsEqual(port_intrinsic_ref, intrinsic_ref)) continue;
                return true;
            }
            return false;
        }

        fn planHasMorphismProof(plan: Closure.StaticTreatyPlan, body: SemanticBody, refs: []const Ref) bool {
            const morphism_ref = plan.selected_morphism_ref orelse return false;
            return (refs.len == 0 or refsContain(refs, morphism_ref)) and
                plan.selected_morphism_semantic_body != null and
                plan.selected_morphism_semantic_body.? == body and
                planHasDependencyRef(plan, .morphism, morphism_ref);
        }

        fn planHasBoundDependency(plan: Closure.StaticTreatyPlan, role: Role, refs: []const Ref) bool {
            for (plan.dependencies) |dependency| {
                if (dependency.role != role) continue;
                if (refs.len == 0 or refsContain(refs, dependency.ref)) return true;
            }
            return false;
        }

        fn planHasDependencyRef(plan: Closure.StaticTreatyPlan, role: Role, ref: Ref) bool {
            for (plan.dependencies) |dependency| {
                if (dependency.role == role and dependency.ref.eql(ref)) return true;
            }
            return false;
        }

        fn inputRefsBoundToPlanDependencies(plans: []const Closure.StaticTreatyPlan, role: Role, refs: []const Ref) bool {
            for (refs) |ref| {
                var found = false;
                for (plans) |plan| {
                    if (planHasDependencyRef(plan, role, ref)) {
                        found = true;
                        break;
                    }
                }
                if (!found) return false;
            }
            return true;
        }

        fn providerProgramProofsMatchStaticPlans(input: Input) bool {
            for (input.static_treaty_plans) |plan| {
                if (planBlockedForElaboration(input, plan)) continue;
                if (plan.selected_semantic_body != .boundary_program) continue;
                const provider_ref = plan.selected_provider_ref orelse return false;
                const program_ref = plan.selected_provider_program_ref orelse return false;
                const mapping_fingerprint = plan.selected_provider_program_mapping_fingerprint orelse return false;
                const shape_count = plan.selected_provider_program_effect_shape_count orelse return false;
                const shape_fingerprint = plan.selected_provider_program_effect_shape_fingerprint orelse return false;
                if (!providerProgramProofExists(input.provider_programs, plan, provider_ref, program_ref, mapping_fingerprint, @intCast(shape_count), shape_fingerprint)) return false;
            }
            return true;
        }

        fn providerProgramProofExists(programs: []const Closure.ProviderProgram, plan: Closure.StaticTreatyPlan, provider_ref: Ref, program_ref: Ref, mapping_fingerprint: u64, shape_count: usize, shape_fingerprint: u64) bool {
            for (programs) |program| {
                if (!program.provider_ref.eql(provider_ref)) continue;
                if (!program.program_ref.eql(program_ref)) continue;
                if (program.provider_program_mapping_fingerprint == null) continue;
                if (program.provider_program_mapping_fingerprint.? != mapping_fingerprint) continue;
                if (!providerProgramMappingSupportedForPlan(program, plan)) continue;
                if (!providerProgramShapesMatchPlan(program, program_ref, shape_count, shape_fingerprint)) continue;
                return true;
            }
            return false;
        }

        fn providerProgramMappingSupportedForPlan(program: Closure.ProviderProgram, plan: Closure.StaticTreatyPlan) bool {
            _ = program.provider_program_mapping_fingerprint orelse return false;
            const request_mapping = program.request_mapping orelse return false;
            const result_mapping = program.result_mapping orelse return false;
            if (!Closure.providerProgramMappingSupportMatchesPlan(plan, program)) return false;
            const mapping_shape = providerProgramMappingShapeForPlan(plan) orelse return false;
            if (!providerProgramMappingTagsCompatibleWithShape(mapping_shape, request_mapping, result_mapping)) return false;
            switch (request_mapping) {
                .payload_to_args, .unit_args => {},
                .payload_and_metadata_to_args, .custom_comptime_mapper => return false,
            }
            switch (result_mapping) {
                .result_to_resume, .result_to_return_now, .result_to_resume_after => return true,
                .result_to_outcome_union => return false,
            }
        }

        fn providerProgramShapesMatchPlan(program: Closure.ProviderProgram, program_ref: Ref, shape_count: usize, shape_fingerprint: u64) bool {
            if (program.effect_free) {
                if (shape_count != 0 or program.shapes.len != 0) return false;
            } else {
                if (shape_count == 0) return false;
                if (program.shapes.len != shape_count) return false;
            }
            for (program.shapes) |shape| {
                if (shape.fingerprint != shape.computeFingerprint()) return false;
                if (!programRefMatchesProviderShape(program_ref, shape)) return false;
            }
            return fingerprintBoundaryEffectShapeSet(program.shapes) == shape_fingerprint;
        }

        fn programRefMatchesProviderShape(program_ref: Ref, shape: Closure.EffectShape) bool {
            if (program_ref.domain_id != domains.program_plan.id) return false;
            if (shape.plan_hash == 0 or program_ref.fingerprint != shape.plan_hash) return false;
            const program_label = program_ref.label orelse return false;
            return std.mem.eql(u8, program_label, shape.program_label);
        }

        fn staticPlanRefsMatch(plans: []const Closure.StaticTreatyPlan, refs: []const Ref) bool {
            if (plans.len != refs.len) return false;
            for (refs) |expected_ref| {
                if (staticPlanRefCount(plans, expected_ref) != refCount(refs, expected_ref)) return false;
            }
            for (plans) |plan| {
                if (refCount(refs, plan.evidenceRef()) == 0) return false;
            }
            return true;
        }

        fn worldPortRefsMatch(ports: []const Closure.WorldPort, refs: []const Ref) bool {
            for (refs) |expected_ref| {
                if (worldPortRefCount(ports, expected_ref) != 1) return false;
            }
            for (ports) |port| {
                if (port.fingerprint != port.computeFingerprint()) return false;
                if (refCount(refs, port.evidenceRef()) == 0) return false;
            }
            return true;
        }

        fn refCount(refs: []const Ref, needle: Ref) usize {
            var count: usize = 0;
            for (refs) |ref| {
                if (ref.eql(needle)) count += 1;
            }
            return count;
        }

        fn providerProgramRefCount(programs: []const Closure.ProviderProgram, needle: Ref) usize {
            var count: usize = 0;
            for (programs) |program| {
                if (program.program_ref.eql(needle)) count += 1;
            }
            return count;
        }

        fn staticPlanRefCount(plans: []const Closure.StaticTreatyPlan, needle: Ref) usize {
            var count: usize = 0;
            for (plans) |plan| {
                if (plan.evidenceRef().eql(needle)) count += 1;
            }
            return count;
        }

        fn worldPortRefCount(ports: []const Closure.WorldPort, needle: Ref) usize {
            var count: usize = 0;
            for (ports) |port| {
                if (port.fingerprint != port.computeFingerprint()) continue;
                if (port.evidenceRef().eql(needle)) count += 1;
            }
            return count;
        }
    };
}

pub fn BoundaryClosure(comptime ProgramType: type) type {
    return struct {
        pub const Policy = BoundaryClosurePolicy;
        pub const EffectShape = BoundaryEffectShape;
        pub const WorldPort = BoundaryWorldPort;
        pub const StaticTreatyPlan = BoundaryStaticTreatyPlan;
        pub const Graph = BoundaryGraph;
        pub const Report = BoundaryClosureReport;
        pub const Certificate = BoundaryClosureCertificate;
        pub const Elaboration = BoundaryElaboration(ProgramType, @This());
        const Closure = @This();
        const maxStaticResponseRefs = 3;

        pub const ProviderProgram = struct {
            provider_ref: Ref,
            program_ref: Ref,
            provider_program_mapping_fingerprint: ?u64 = null,
            provider_program_mapping_support_fingerprint: ?u64 = null,
            request_mapping: ?ProgramType.Exchange.RequestToProgramArgs = null,
            result_mapping: ?ProgramType.Exchange.ProgramResultToProviderOutcome = null,
            shapes: []const Closure.EffectShape = &.{},
            effect_free: bool = false,
        };

        pub fn providerProgramMappingSupportFingerprintForPlan(
            plan: StaticTreatyPlan,
            request_mapping: ProgramType.Exchange.RequestToProgramArgs,
            result_mapping: ProgramType.Exchange.ProgramResultToProviderOutcome,
        ) ?u64 {
            const provider_ref = plan.selected_provider_ref orelse return null;
            const offer_ref = plan.selected_provider_offer_ref orelse return null;
            const program_ref = plan.selected_provider_program_ref orelse return null;
            const mapping_fingerprint = plan.selected_provider_program_mapping_fingerprint orelse return null;
            const shape_count = plan.selected_provider_program_effect_shape_count orelse return null;
            const shape_fingerprint = plan.selected_provider_program_effect_shape_fingerprint orelse return null;
            return providerProgramMappingSupportFingerprintForSelection(provider_ref, offer_ref, program_ref, mapping_fingerprint, shape_count, shape_fingerprint, request_mapping, result_mapping);
        }

        pub fn providerProgramMappingSupportFingerprintForSelection(
            provider_ref: Ref,
            offer_ref: Ref,
            program_ref: Ref,
            mapping_fingerprint: u64,
            shape_count: u64,
            shape_fingerprint: u64,
            request_mapping: ProgramType.Exchange.RequestToProgramArgs,
            result_mapping: ProgramType.Exchange.ProgramResultToProviderOutcome,
        ) u64 {
            return providerProgramMappingSupportFingerprintForTags(provider_ref, offer_ref, program_ref, mapping_fingerprint, shape_count, shape_fingerprint, @tagName(request_mapping), @tagName(result_mapping));
        }

        pub fn providerProgramMappingSupportMatchesPlan(plan: StaticTreatyPlan, program: ProviderProgram) bool {
            const request_mapping = program.request_mapping orelse return false;
            const result_mapping = program.result_mapping orelse return false;
            if (!providerProgramMappingTagsMatchPlan(plan, request_mapping, result_mapping)) return false;
            const expected = providerProgramMappingSupportFingerprintForPlan(plan, request_mapping, result_mapping) orelse return false;
            if (plan.selected_provider_program_mapping_support_fingerprint != expected) return false;
            return program.provider_program_mapping_support_fingerprint == expected;
        }

        fn providerProgramMappingTagsMatchPlan(
            plan: StaticTreatyPlan,
            request_mapping: ProgramType.Exchange.RequestToProgramArgs,
            result_mapping: ProgramType.Exchange.ProgramResultToProviderOutcome,
        ) bool {
            const selected_request = plan.selected_provider_program_request_mapping_tag orelse return false;
            const selected_result = plan.selected_provider_program_result_mapping_tag orelse return false;
            return std.mem.eql(u8, selected_request, @tagName(request_mapping)) and
                std.mem.eql(u8, selected_result, @tagName(result_mapping));
        }

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
            mapping_support_fingerprint: ?u64,
            effect_shape_fingerprint: u64,
            effect_free: bool,

            fn eql(self: @This(), other: @This()) bool {
                return self.sameSelection(other) and self.effect_free == other.effect_free;
            }

            fn sameSelection(self: @This(), other: @This()) bool {
                return self.provider_ref.eql(other.provider_ref) and
                    self.program_ref.eql(other.program_ref) and
                    self.mapping_fingerprint == other.mapping_fingerprint and
                    self.mapping_support_fingerprint == other.mapping_support_fingerprint and
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
                clearSelectedRoute(&selected);
            }
            const real_runtime_guard_required = runtime_request_value_guard_required or
                selected.byte_size_runtime_guard_required or
                hasClosureBlockerTag(blockers.items, .runtime_guard_required);
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
            const byte_size_runtime_guard_required = selected.byte_size_runtime_guard_required or selected.offer_ref == null or hasClosureBlockerTag(owned_blockers, .runtime_guard_required);
            return StaticTreatyPlan.init(.{
                .label = inputs.shape.name,
                .source_shape = inputs.shape,
                .direct_candidate_count = selected.direct_count,
                .morphism_candidate_count = selected.morphism_count,
                .selected_provider_offer_ref = selected.offer_ref,
                .selected_provider_ref = selected.provider_ref,
                .selected_capability_ref = selected.capability_ref,
                .selected_morphism_ref = selected.morphism_ref,
                .selected_morphism_target_shape_ref = selected.morphism_target_shape_ref,
                .selected_morphism_target_shape = selected.morphism_target_shape,
                .selected_morphism_target_response_ref_count = selected.morphism_target_response_ref_count,
                .selected_morphism_target_response_refs = selected.morphism_target_response_refs,
                .selected_morphism_semantic_body = selected.morphism_body,
                .selected_morphism_intrinsic_ref = selected.morphism_intrinsic_ref,
                .selected_semantic_body = selected.body,
                .selected_intrinsic_ref = selected.intrinsic_ref,
                .selected_provider_program_ref = selected.provider_program_ref,
                .selected_provider_program_mapping_fingerprint = selected.provider_program_mapping_fingerprint,
                .selected_provider_program_request_mapping_tag = selected.provider_program_request_mapping_tag,
                .selected_provider_program_result_mapping_tag = selected.provider_program_result_mapping_tag,
                .selected_provider_program_effect_shape_count = selected.provider_program_effect_shape_count,
                .selected_provider_program_effect_shape_fingerprint = selected.provider_program_effect_shape_fingerprint,
                .boundary_native = selected.body.isNonIntrinsic() and (if (selected.morphism_body) |body| body.isNonIntrinsic() else true),
                .host_intrinsic = selected.body == .host_intrinsic or (if (selected.morphism_body) |body| body == .host_intrinsic else false),
                .runtime_request_value_validation_required = runtime_guard_required,
                .byte_size_runtime_guard_required = byte_size_runtime_guard_required,
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
                root_shapes: for (analysis_input.root_shapes) |shape| {
                    if (!effectShapeFresh(shape)) continue :root_shapes;
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
            var intrinsic_route_count: usize = 0;
            var ambiguity_count: usize = 0;

            try analyzeShapes(allocator, analysis_input, analysis_input.root_shapes, &all_plans, &blockers, &plan_refs, &seen_shape_refs, &world_port_refs, &world_port_intrinsic_refs, &host_intrinsic_refs, &unknown_refs, &nodes, &edges, &closed_count, &world_port_shape_count, &boundary_native_count, &declarative_count, &residualized_pipeline_count, &intrinsic_count, &intrinsic_route_count, &ambiguity_count, analysis_input.root_program_refs, null);
            try analyzeSelectedProviderPrograms(allocator, analysis_input, &all_plans, &blockers, &plan_refs, &seen_shape_refs, &provider_program_refs, &provider_program_keys, &active_provider_program_refs, &active_provider_program_keys, &world_port_refs, &world_port_intrinsic_refs, &host_intrinsic_refs, &unknown_refs, &nodes, &edges, &closed_count, &world_port_shape_count, &boundary_native_count, &declarative_count, &residualized_pipeline_count, &intrinsic_count, &intrinsic_route_count, &ambiguity_count, 0, all_plans.items.len, 0);
            for (all_plans.items) |plan| {
                if (plan.selected_semantic_body != .boundary_program) continue;
                const provider_ref = plan.selected_provider_ref orelse continue;
                const selected_program = selectedPlanProviderProgram(plan) orelse {
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
                if (providerProgramForSelectedOffer(analysis_input.provider_programs, plan, provider_ref, selected_program) == null) {
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

            if (analysis_input.policy.defunctionalization_policy.maximum_intrinsic_count) |maximum| {
                if (intrinsic_count > maximum) {
                    const evidence_blocker = boundaryClosureBlocker(.{
                        .tag = .defunctionalization_policy_incompatible,
                        .summary = "closure host intrinsic count exceeds defunctionalization policy maximum",
                    });
                    try blockers.append(allocator, evidence_blocker);
                    try appendBlockerGraph(allocator, &nodes, &edges, evidence_blocker);
                }
            }

            if (nodes.items.len > analysis_input.policy.max_nodes) {
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
                .intrinsic_route_count = intrinsic_route_count,
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
            direct_offer_count: usize = 0,
            morphism_count: usize = 0,
            offer_ref: ?Ref = null,
            provider_ref: ?Ref = null,
            provider_fingerprint: u64 = 0,
            capability_ref: ?Ref = null,
            morphism_ref: ?Ref = null,
            morphism_target_shape_ref: ?Ref = null,
            morphism_target_shape: ?Closure.EffectShape = null,
            morphism_target_response_ref_count: u8 = 0,
            morphism_target_response_refs: [StaticTreatyPlan.max_morphism_target_response_refs]BoundaryValueRef = [_]BoundaryValueRef{.{ .codec = "" }} ** StaticTreatyPlan.max_morphism_target_response_refs,
            morphism_body: ?SemanticBody = null,
            morphism_intrinsic_ref: ?Ref = null,
            intrinsic_ref: ?Ref = null,
            body: SemanticBody = .unknown,
            provider_program_ref: ?Ref = null,
            provider_program_mapping_fingerprint: ?u64 = null,
            provider_program_request_mapping_tag: ?[]const u8 = null,
            provider_program_result_mapping_tag: ?[]const u8 = null,
            provider_program_effect_shape_count: ?u64 = null,
            provider_program_effect_shape_fingerprint: ?u64 = null,
            selected_rank: u8 = std.math.maxInt(u8),
            selected_rank_count: usize = 0,
            selected_authority: CandidateAuthority = .{},
            byte_size_runtime_guard_required: bool = false,
        };

        const CandidateAuthority = struct {
            max_request_bytes: usize = std.math.maxInt(usize),
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
            if (inputs.treaty_policy.require_capsule_embedding and !shapeCarriesCapsule(inputs.shape)) {
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
                    selection.direct_offer_count += 1;
                    var matched_capability = false;
                    direct_capabilities: for (inputs.capabilities) |capability| {
                        if (!capabilityMatchesShape(capability, offer, inputs.shape)) continue :direct_capabilities;
                        if (!directCandidateResponseShapeAllowed(inputs.route_policy, provider, offer, capability, inputs.shape)) continue :direct_capabilities;
                        if (closureCapabilityBlockedByTreatyPolicy(capability, inputs.treaty_policy)) continue :direct_capabilities;
                        matched_capability = true;
                        selection.direct_count += 1;
                        try dependencies.append(inputs.allocator, .{ .role = .offer, .ref = offer.evidenceRef() });
                        try dependencies.append(inputs.allocator, .{ .role = .capability, .ref = capability.evidenceRef() });
                        selectCandidate(inputs.policy, inputs.treaty_policy, inputs.route_policy, &selection, inputs.shape, null, provider, offer, capability, null, body, intrinsic_ref);
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
                    var dynamic_target_response_refs_buffer: [3]BoundaryValueRef = undefined;
                    const dynamic_target_shape = morphismTargetShape(inputs.shape, morphism, &dynamic_target_response_refs_buffer);
                    if (!inputs.treaty_policy.allow_dynamic_interpretation) {
                        try rejected_candidates.append(inputs.allocator, .{ .tag = .dynamic_mapper_rejected, .subject = inputs.shape.evidenceRef(), .primary = morphism.evidenceRef(), .summary = "treaty policy disallows dynamic morphism adapters" });
                        continue;
                    }
                    if (morphism.hostIntrinsicRef()) |ref| {
                        if (!inputAllowsIntrinsicOrWorldPort(inputs, ref, dynamic_target_shape)) {
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
                            selectCandidate(inputs.policy, inputs.treaty_policy, inputs.route_policy, &selection, target_shape, target_shape.evidenceRef(), provider, offer, capability, morphism, provider_body, offer.hostIntrinsicRef());
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
                if (selection.direct_offer_count == 0 and selection.morphism_count == 0) {
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
            intrinsic_route_count: *usize,
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
                if (parent_provider_program_ref == null) {
                    if (effectFreeRootMatchingShape(input.effect_free_root_refs, shape)) |effect_free_root_ref| {
                        const evidence_blocker = boundaryClosureBlocker(.{
                            .tag = .root_program_missing,
                            .subject = effect_free_root_ref,
                            .summary = "effect-free root witness conflicts with a yielding root effect shape",
                        });
                        try blockers.append(allocator, evidence_blocker);
                        try appendBlockerGraph(allocator, nodes, edges, evidence_blocker);
                        continue;
                    }
                }
                try seen_shape_refs.append(allocator, shape_ref);
                try nodes.append(allocator, .{ .kind = if (shape.kind == .after) .after_site else .operation_site, .ref = shape_ref, .label = shape.name });
                if (parent_provider_program_ref) |program_ref| {
                    try edges.append(allocator, .{ .kind = .provider_program_yields, .from = program_ref, .to = shape_ref });
                } else {
                    if ((root_program_refs.len == 0 and input.policy.require_root_program_refs) or
                        !try appendRootYieldEdges(allocator, edges, root_program_refs, shape_ref, shape))
                    {
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
                    if (plan.selected_provider_ref) |provider_ref| {
                        if (!graphNodeItemsContain(nodes.items, .provider_manifest, provider_ref)) {
                            try nodes.append(allocator, .{ .kind = .provider_manifest, .ref = provider_ref, .label = provider_ref.label orelse "provider manifest" });
                        }
                        if (!graphEdgeItemsContain(edges.items, .provider_advertises_offer, provider_ref, offer_ref)) {
                            try edges.append(allocator, .{ .kind = .provider_advertises_offer, .from = provider_ref, .to = offer_ref });
                        }
                    }
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
                            if (!input.policy.allowsHostIntrinsicRef(intrinsic_ref)) {
                                var target_response_refs_buffer: [3]BoundaryValueRef = undefined;
                                const target_shape = morphismTargetShape(shape, morphism, &target_response_refs_buffer);
                                if (worldPortForShape(input.policy, input.world_ports, target_shape, intrinsic_ref)) |port| {
                                    try world_port_refs.append(allocator, port.evidenceRef());
                                    try world_port_intrinsic_refs.append(allocator, intrinsic_ref);
                                    try nodes.append(allocator, .{ .kind = .world_port, .ref = port.evidenceRef(), .label = port.label });
                                    try edges.append(allocator, .{ .kind = .opens_obligation, .from = shape_ref, .to = port.evidenceRef() });
                                    try edges.append(allocator, .{ .kind = .world_port_exposes, .from = intrinsic_ref, .to = port.evidenceRef() });
                                }
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
                const shape_world_port = if (!closed_under_policy) blk: {
                    var target_response_refs_buffer: [3]BoundaryValueRef = undefined;
                    var world_port_shape = shape;
                    if (plan.selected_morphism_ref) |morphism_ref| {
                        if (morphismOfferForRef(input.morphism_offers, morphism_ref)) |morphism| {
                            world_port_shape = morphismTargetShape(shape, morphism, &target_response_refs_buffer);
                        }
                    }
                    break :blk shapeOnlyWorldPortForShape(input.policy, input.world_ports, world_port_shape);
                } else null;
                if (shape_world_port) |port| {
                    try world_port_refs.append(allocator, port.evidenceRef());
                    try world_port_intrinsic_refs.append(allocator, shape_ref);
                    try nodes.append(allocator, .{ .kind = .world_port, .ref = port.evidenceRef(), .label = port.label });
                    try edges.append(allocator, .{ .kind = .opens_obligation, .from = shape_ref, .to = port.evidenceRef() });
                }
                const selected_unknown_body_count = selectedPlanUnknownBodyCount(plan);
                var selected_unknown_body_index: usize = 0;
                while (selected_unknown_body_index < selected_unknown_body_count) : (selected_unknown_body_index += 1) {
                    try unknown_refs.append(allocator, shape_ref);
                }
                if (closed_under_policy) {
                    if (world_port_refs.items.len == world_port_count_before_shape) {
                        closed_count.* += 1;
                    } else {
                        world_port_shape_count.* += 1;
                    }
                    if (plan.boundary_native) boundary_native_count.* += 1;
                    if (plan.host_intrinsic) intrinsic_route_count.* += selectedPlanHostIntrinsicCount(plan);
                    switch (selected_morphism_body orelse plan.selected_semantic_body) {
                        .boundary_program, .kernel_primitive => {},
                        .declarative => declarative_count.* += 1,
                        .residualized_program, .pipeline => residualized_pipeline_count.* += 1,
                        .host_intrinsic, .unknown => {},
                    }
                } else if (world_port_refs.items.len != world_port_count_before_shape or shape_world_port != null) {
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

        fn effectFreeRootMatchingShape(effect_free_root_refs: []const Ref, shape: Closure.EffectShape) ?Ref {
            for (effect_free_root_refs) |root_ref| {
                if (rootRefMatchesShape(root_ref, shape)) return root_ref;
            }
            return null;
        }

        fn rootRefMatchesShape(root_ref: Ref, shape: Closure.EffectShape) bool {
            return programRefMatchesShape(root_ref, shape);
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
            intrinsic_route_count: *usize,
            ambiguity_count: *usize,
            selected_plan_start: usize,
            selected_plan_end: usize,
            depth: usize,
        ) !void {
            provider_programs: for (input.provider_programs) |provider_program| {
                const selected_plans = all_plans.items[selected_plan_start..selected_plan_end];
                if (!providerProgramSelected(selected_plans, provider_program)) {
                    if (providerProgramHasStaleShape(provider_program) and providerProgramTargetsSelectedPlan(selected_plans, provider_program)) {
                        const evidence_blocker = boundaryClosureBlocker(.{
                            .tag = .provider_program_contract_missing,
                            .subject = provider_program.program_ref,
                            .primary = provider_program.provider_ref,
                            .summary = "selected provider program has stale nested effect-shape proof",
                        });
                        try blockers.append(allocator, evidence_blocker);
                        try appendBlockerGraph(allocator, nodes, edges, evidence_blocker);
                    }
                    continue :provider_programs;
                }
                const selected_key = providerProgramKey(provider_program);
                if (refsContain(active_provider_program_refs.items, provider_program.program_ref) or
                    providerProgramKeysContain(active_provider_program_keys.items, selected_key))
                {
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
                if (refsContain(provider_program_refs.items, provider_program.program_ref)) {
                    if (providerProgramKeysContainConflictingProof(provider_program_keys.items, selected_key)) {
                        const evidence_blocker = boundaryClosureBlocker(.{
                            .tag = .provider_program_contract_missing,
                            .subject = provider_program.program_ref,
                            .primary = provider_program.provider_ref,
                            .summary = "selected provider program has conflicting closure proof metadata",
                        });
                        try blockers.append(allocator, evidence_blocker);
                        try appendBlockerGraph(allocator, nodes, edges, evidence_blocker);
                    } else {
                        try provider_program_keys.append(allocator, selected_key);
                        try appendProviderProgramMappingGraph(allocator, nodes, edges, provider_program);
                    }
                    continue :provider_programs;
                }
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

                if (provider_program.shapes.len == 0 and !provider_program.effect_free) {
                    if (selectedProviderProgramHasProofAlternative(
                        all_plans.items[selected_plan_start..selected_plan_end],
                        input.provider_programs,
                        selected_key,
                    )) continue :provider_programs;

                    try provider_program_keys.append(allocator, selected_key);
                    const evidence_blocker = boundaryClosureBlocker(.{
                        .tag = .provider_program_nested_unknown,
                        .subject = provider_program.program_ref,
                        .primary = provider_program.provider_ref,
                        .summary = "selected provider program has no nested effect-shape proof",
                    });
                    try blockers.append(allocator, evidence_blocker);
                    try appendBlockerGraph(allocator, nodes, edges, evidence_blocker);
                    continue :provider_programs;
                }

                try provider_program_keys.append(allocator, selected_key);
                try provider_program_refs.append(allocator, provider_program.program_ref);
                try active_provider_program_refs.append(allocator, provider_program.program_ref);
                try active_provider_program_keys.append(allocator, selected_key);
                try nodes.append(allocator, .{ .kind = .provider_program, .ref = provider_program.program_ref, .label = "provider program" });
                try appendProviderProgramMappingGraph(allocator, nodes, edges, provider_program);

                const nested_plan_start = all_plans.items.len;
                try analyzeShapes(allocator, input, provider_program.shapes, all_plans, blockers, plan_refs, seen_shape_refs, world_port_refs, world_port_intrinsic_refs, host_intrinsic_refs, unknown_refs, nodes, edges, closed_count, world_port_shape_count, boundary_native_count, declarative_count, residualized_pipeline_count, intrinsic_count, intrinsic_route_count, ambiguity_count, &.{}, provider_program.program_ref);
                try analyzeSelectedProviderPrograms(allocator, input, all_plans, blockers, plan_refs, seen_shape_refs, provider_program_refs, provider_program_keys, active_provider_program_refs, active_provider_program_keys, world_port_refs, world_port_intrinsic_refs, host_intrinsic_refs, unknown_refs, nodes, edges, closed_count, world_port_shape_count, boundary_native_count, declarative_count, residualized_pipeline_count, intrinsic_count, intrinsic_route_count, ambiguity_count, nested_plan_start, all_plans.items.len, depth + 1);
                _ = active_provider_program_refs.pop();
                _ = active_provider_program_keys.pop();
            }
        }

        fn appendProviderProgramMappingGraph(
            allocator: std.mem.Allocator,
            nodes: *std.ArrayList(Graph.Node),
            edges: *std.ArrayList(Graph.Edge),
            provider_program: ProviderProgram,
        ) !void {
            _ = provider_program.provider_program_mapping_fingerprint orelse return;
            const mapping_support_fingerprint = provider_program.provider_program_mapping_support_fingerprint orelse return;
            const mapping_support_ref = refForProviderProgramMapping(mapping_support_fingerprint);
            if (!graphNodeItemsContain(nodes.items, .provider_program_mapping, mapping_support_ref)) {
                try nodes.append(allocator, .{ .kind = .provider_program_mapping, .ref = mapping_support_ref, .label = "provider program mapping support" });
            }
            if (!graphEdgeItemsContain(edges.items, .provider_program_mapped_by, provider_program.program_ref, mapping_support_ref)) {
                try edges.append(allocator, .{ .kind = .provider_program_mapped_by, .from = provider_program.program_ref, .to = mapping_support_ref });
            }
        }

        fn graphNodeItemsContain(nodes: []const Graph.Node, kind: Graph.NodeKind, ref: Ref) bool {
            for (nodes) |node| {
                if (node.kind == kind and node.ref.eql(ref)) return true;
            }
            return false;
        }

        fn graphEdgeItemsContain(edges: []const Graph.Edge, kind: Graph.EdgeKind, from: Ref, to: Ref) bool {
            for (edges) |edge| {
                if (edge.kind == kind and edge.from.eql(from) and edge.to.eql(to)) return true;
            }
            return false;
        }

        fn providerProgramKey(provider_program: ProviderProgram) SelectedProviderProgramKey {
            return .{
                .provider_ref = provider_program.provider_ref,
                .program_ref = provider_program.program_ref,
                .mapping_fingerprint = provider_program.provider_program_mapping_fingerprint,
                .mapping_support_fingerprint = provider_program.provider_program_mapping_support_fingerprint,
                .effect_shape_fingerprint = fingerprintBoundaryEffectShapeSet(provider_program.shapes),
                .effect_free = provider_program.effect_free,
            };
        }

        fn providerProgramKeysContain(keys: []const SelectedProviderProgramKey, needle: SelectedProviderProgramKey) bool {
            for (keys) |key| {
                if (key.eql(needle)) return true;
            }
            return false;
        }

        fn providerProgramKeysContainConflictingProof(keys: []const SelectedProviderProgramKey, needle: SelectedProviderProgramKey) bool {
            for (keys) |key| {
                if (!key.program_ref.eql(needle.program_ref)) continue;
                if (key.effect_shape_fingerprint != needle.effect_shape_fingerprint or key.effect_free != needle.effect_free) return true;
            }
            return false;
        }

        fn selectedProviderProgramHasProofAlternative(plans: []const StaticTreatyPlan, programs: []const ProviderProgram, selected_key: SelectedProviderProgramKey) bool {
            for (programs) |program| {
                if (program.shapes.len == 0 and !program.effect_free) continue;
                if (!providerProgramSelected(plans, program)) continue;
                if (providerProgramKey(program).sameSelection(selected_key)) return true;
            }
            return false;
        }

        fn providerProgramSelected(plans: []const StaticTreatyPlan, provider_program: ProviderProgram) bool {
            for (plans) |plan| {
                const selected_program = selectedPlanProviderProgram(plan) orelse continue;
                const selected_provider_ref = plan.selected_provider_ref orelse continue;
                if (!selected_provider_ref.eql(provider_program.provider_ref)) continue;
                if (provider_program.provider_program_mapping_fingerprint) |program_mapping| {
                    if (providerProgramMappingSupportedForPlan(provider_program, plan) and
                        program_mapping == selected_program.mapping_fingerprint and
                        provider_program.program_ref.eql(selected_program.program_ref) and
                        providerProgramShapesMatchSelected(provider_program, selected_program))
                    {
                        return true;
                    }
                }
            }
            return false;
        }

        fn providerProgramTargetsSelectedPlan(plans: []const StaticTreatyPlan, provider_program: ProviderProgram) bool {
            for (plans) |plan| {
                const selected_program = selectedPlanProviderProgram(plan) orelse continue;
                const selected_provider_ref = plan.selected_provider_ref orelse continue;
                if (!selected_provider_ref.eql(provider_program.provider_ref)) continue;
                if (!provider_program.program_ref.eql(selected_program.program_ref)) continue;
                if (provider_program.provider_program_mapping_fingerprint) |program_mapping| {
                    if (providerProgramMappingSupportedForPlan(provider_program, plan) and
                        program_mapping == selected_program.mapping_fingerprint) return true;
                }
            }
            return false;
        }

        fn providerProgramShapesMatchSelected(provider_program: ProviderProgram, selected_program: SelectedProviderProgram) bool {
            if (provider_program.effect_free) {
                if (selected_program.effect_shape_count != 0 or provider_program.shapes.len != 0) return false;
            } else if (provider_program.shapes.len != selected_program.effect_shape_count) return false;
            for (provider_program.shapes) |shape| {
                if (!effectShapeFresh(shape)) return false;
                if (!programRefMatchesShape(provider_program.program_ref, shape)) return false;
            }
            return fingerprintBoundaryEffectShapeSet(provider_program.shapes) == selected_program.effect_shape_fingerprint;
        }

        fn programRefMatchesShape(program_ref: Ref, shape: Closure.EffectShape) bool {
            if (program_ref.domain_id != domains.program_plan.id) return false;
            if (shape.plan_hash == 0 or program_ref.fingerprint != shape.plan_hash) return false;
            const program_label = program_ref.label orelse return false;
            return std.mem.eql(u8, program_label, shape.program_label);
        }

        fn providerProgramHasStaleShape(provider_program: ProviderProgram) bool {
            for (provider_program.shapes) |shape| {
                if (!effectShapeFresh(shape)) return true;
            }
            return false;
        }

        fn effectShapeFresh(shape: Closure.EffectShape) bool {
            return shape.fingerprint == shape.computeFingerprint();
        }

        fn selectedPlanProviderProgram(plan: StaticTreatyPlan) ?SelectedProviderProgram {
            if (plan.selected_semantic_body != .boundary_program) return null;
            const mapping_fingerprint = plan.selected_provider_program_mapping_fingerprint orelse return null;
            const program_ref = plan.selected_provider_program_ref orelse return null;
            const effect_shape_count = plan.selected_provider_program_effect_shape_count orelse return null;
            const effect_shape_fingerprint = plan.selected_provider_program_effect_shape_fingerprint orelse return null;
            return .{
                .mapping_fingerprint = mapping_fingerprint,
                .program_ref = program_ref,
                .effect_shape_count = @intCast(effect_shape_count),
                .effect_shape_fingerprint = effect_shape_fingerprint,
            };
        }

        fn providerProgramForSelectedOffer(programs: []const ProviderProgram, plan: StaticTreatyPlan, provider_ref: Ref, selected_program: SelectedProviderProgram) ?ProviderProgram {
            for (programs) |program| {
                if (!program.provider_ref.eql(provider_ref)) continue;
                if (!program.program_ref.eql(selected_program.program_ref)) continue;
                if (!providerProgramShapesMatchSelected(program, selected_program)) continue;
                if (program.provider_program_mapping_fingerprint) |program_mapping| {
                    if (providerProgramMappingSupportedForPlan(program, plan) and
                        program_mapping == selected_program.mapping_fingerprint) return program;
                }
            }
            return null;
        }

        fn providerProgramMappingSupportedForPlan(provider_program: ProviderProgram, plan: StaticTreatyPlan) bool {
            _ = provider_program.provider_program_mapping_fingerprint orelse return false;
            const request_mapping = provider_program.request_mapping orelse return false;
            const result_mapping = provider_program.result_mapping orelse return false;
            if (!Closure.providerProgramMappingSupportMatchesPlan(plan, provider_program)) return false;
            const mapping_shape = providerProgramMappingShapeForPlan(plan) orelse return false;
            if (!providerProgramMappingTagsCompatibleWithShape(mapping_shape, request_mapping, result_mapping)) return false;
            switch (request_mapping) {
                .payload_to_args, .unit_args => {},
                .payload_and_metadata_to_args, .custom_comptime_mapper => return false,
            }
            switch (result_mapping) {
                .result_to_resume, .result_to_return_now, .result_to_resume_after => return true,
                .result_to_outcome_union => return false,
            }
        }

        fn graphNodeLessThan(_: void, lhs: Graph.Node, rhs: Graph.Node) bool {
            if (@intFromEnum(lhs.kind) != @intFromEnum(rhs.kind)) return @intFromEnum(lhs.kind) < @intFromEnum(rhs.kind);
            if (refLessForCanonicalSet(lhs.ref, rhs.ref)) return true;
            if (refLessForCanonicalSet(rhs.ref, lhs.ref)) return false;
            return std.mem.lessThan(u8, lhs.label, rhs.label);
        }

        fn graphEdgeLessThan(_: void, lhs: Graph.Edge, rhs: Graph.Edge) bool {
            if (@intFromEnum(lhs.kind) != @intFromEnum(rhs.kind)) return @intFromEnum(lhs.kind) < @intFromEnum(rhs.kind);
            if (refLessForCanonicalSet(lhs.from, rhs.from)) return true;
            if (refLessForCanonicalSet(rhs.from, lhs.from)) return false;
            if (refLessForCanonicalSet(lhs.to, rhs.to)) return true;
            if (refLessForCanonicalSet(rhs.to, lhs.to)) return false;
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

        fn clearSelectedRoute(selection: *CandidateSelection) void {
            selection.offer_ref = null;
            selection.provider_ref = null;
            selection.provider_fingerprint = 0;
            selection.capability_ref = null;
            selection.morphism_ref = null;
            selection.morphism_target_shape_ref = null;
            selection.morphism_target_shape = null;
            selection.morphism_target_response_ref_count = 0;
            selection.morphism_body = null;
            selection.morphism_intrinsic_ref = null;
            selection.intrinsic_ref = null;
            selection.body = .unknown;
            selection.provider_program_ref = null;
            selection.provider_program_mapping_fingerprint = null;
            selection.provider_program_request_mapping_tag = null;
            selection.provider_program_result_mapping_tag = null;
            selection.provider_program_effect_shape_count = null;
            selection.provider_program_effect_shape_fingerprint = null;
            selection.selected_rank = std.math.maxInt(u8);
            selection.selected_rank_count = 0;
            selection.selected_authority = .{};
            selection.byte_size_runtime_guard_required = false;
        }

        fn selectCandidate(
            closure_policy: Policy,
            policy: ProgramType.Exchange.Treaty.Policy,
            route_policy: ProgramType.Exchange.Policy,
            selection: *CandidateSelection,
            shape: Closure.EffectShape,
            morphism_target_shape_ref: ?Ref,
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
            selection.morphism_target_shape_ref = morphism_target_shape_ref;
            selection.morphism_target_shape = if (morphism_target_shape_ref != null) shape else null;
            selection.morphism_target_response_ref_count = 0;
            if (selection.morphism_target_shape) |*target_shape| {
                selection.morphism_target_response_ref_count = copyBoundaryValueRefs(&selection.morphism_target_response_refs, target_shape.desired_response_refs);
                target_shape.desired_response_refs = selection.morphism_target_response_refs[0..selection.morphism_target_response_ref_count];
            }
            selection.morphism_body = if (morphism) |morphism_offer| morphism_offer.semanticBody() else null;
            selection.morphism_intrinsic_ref = if (morphism) |morphism_offer| morphism_offer.hostIntrinsicRef() else null;
            selection.body = body;
            selection.intrinsic_ref = intrinsic_ref;
            if (body == .boundary_program) {
                selection.provider_program_ref = offer.provider_program_ref;
                selection.provider_program_mapping_fingerprint = offer.provider_program_mapping_fingerprint;
                selection.provider_program_request_mapping_tag = if (offer.provider_program_request_mapping) |mapping| @tagName(mapping) else null;
                selection.provider_program_result_mapping_tag = if (offer.provider_program_result_mapping) |mapping| @tagName(mapping) else null;
                selection.provider_program_effect_shape_count = if (offer.provider_program_effect_shape_count) |count| @intCast(count) else null;
                selection.provider_program_effect_shape_fingerprint = offer.provider_program_effect_shape_fingerprint;
            } else {
                selection.provider_program_ref = null;
                selection.provider_program_mapping_fingerprint = null;
                selection.provider_program_request_mapping_tag = null;
                selection.provider_program_result_mapping_tag = null;
                selection.provider_program_effect_shape_count = null;
                selection.provider_program_effect_shape_fingerprint = null;
            }
            selection.selected_rank = closureCandidateRank(closure_policy, policy, body);
            selection.selected_rank_count = 1;
            selection.selected_authority = candidate_authority;
            selection.byte_size_runtime_guard_required = closureCandidateRequiresByteGuard(shape, candidate_authority);
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
                .max_request_bytes = closureMinNonZero(.{
                    provider.max_request_envelope_bytes,
                    capability.max_request_bytes,
                    offer.max_request_bytes,
                    policy.max_envelope_bytes,
                    route_policy.max_envelope_bytes,
                }),
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

        fn closureCandidateRequiresByteGuard(shape: Closure.EffectShape, authority: CandidateAuthority) bool {
            if (shape.max_request_bytes == 0 and authority.max_request_bytes != std.math.maxInt(usize)) return true;
            if (shape.max_response_bytes == 0 and authority.max_response_bytes != std.math.maxInt(usize)) return true;
            if (shape.max_payload_bytes == 0 and authority.max_payload_bytes != 0 and authority.max_payload_bytes != std.math.maxInt(usize)) return true;
            return false;
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
            if (input.policy.allowsHostIntrinsicRef(intrinsic_ref)) return null;
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

fn reportHasClosureBlockerTag(report: BoundaryClosureReport, tag: BoundaryClosureBlockerTag) bool {
    for (report.blockers) |blocker| {
        if (std.mem.eql(u8, blocker.short_code, @tagName(tag))) return true;
    }
    return false;
}

fn closureReportHasUnsupportedShapeBlocker(report: BoundaryClosureReport) bool {
    for (report.blockers) |blocker| {
        if (closureBlockerIsUnsupportedShape(blocker)) return true;
    }
    return false;
}

fn closureBlockerIsUnsupportedShape(blocker: Blocker) bool {
    return closureBlockerNameIsUnsupportedShape(blocker.short_code) or
        closureBlockerNameIsUnsupportedShape(blocker.tag);
}

fn closureBlockerTagIsUnsupportedShape(tag: BoundaryClosureBlockerTag) bool {
    return tag == .unsupported_shape_planning or
        tag == .residualization_shape_unsupported or
        tag == .pipeline_shape_unsupported;
}

fn closureBlockerNameIsUnsupportedShape(name: []const u8) bool {
    return std.mem.eql(u8, name, @tagName(BoundaryClosureBlockerTag.unsupported_shape_planning)) or
        std.mem.eql(u8, name, @tagName(BoundaryClosureBlockerTag.residualization_shape_unsupported)) or
        std.mem.eql(u8, name, @tagName(BoundaryClosureBlockerTag.pipeline_shape_unsupported));
}

fn blockerRefCountsUnsupported(ref: Ref) bool {
    const kind_tag = ref.kind_tag orelse return true;
    return blockerNameCountsUnsupported(kind_tag);
}

fn blockerNameCountsUnsupported(name: []const u8) bool {
    const tag = std.meta.stringToEnum(BoundaryClosureBlockerTag, name) orelse return true;
    return closureBlockerTagIsUnsupportedShape(tag);
}

fn reportHasProviderProgramTraversalBlockerFor(report: BoundaryClosureReport, program_ref: Ref) bool {
    for (report.blockers) |blocker| {
        if (!std.mem.eql(u8, blocker.short_code, @tagName(BoundaryClosureBlockerTag.depth_limit_exceeded)) and
            !std.mem.eql(u8, blocker.short_code, @tagName(BoundaryClosureBlockerTag.cycle_detected)) and
            !std.mem.eql(u8, blocker.short_code, @tagName(BoundaryClosureBlockerTag.provider_program_nested_unknown)) and
            !std.mem.eql(u8, blocker.short_code, @tagName(BoundaryClosureBlockerTag.provider_program_contract_missing))) continue;
        const subject_ref = blocker.subject orelse continue;
        if (subject_ref.eql(program_ref)) return true;
    }
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

fn derivedBlockerRefsMatchGraph(graph: BoundaryGraph, blockers: []const Blocker) bool {
    var graph_blocker_count: usize = 0;
    for (graph.nodes) |node| {
        if (node.kind != .blocker) continue;
        graph_blocker_count += 1;
        var matched = false;
        for (blockers) |blocker| {
            if (node.ref.eql(refForBoundaryClosureBlocker(blocker))) {
                matched = true;
                break;
            }
        }
        if (!matched) return false;
    }
    if (graph_blocker_count != blockers.len) return false;
    for (blockers) |blocker| {
        const blocker_ref = refForBoundaryClosureBlocker(blocker);
        if (blocker_ref.domain_id != domains.boundary_closure_report.id) return false;
        if (!graphHasNode(graph, .blocker, blocker_ref)) return false;
        if (blocker.subject) |subject_ref| {
            if (blockerSubjectMustHaveGraphNode(blocker) and !graphHasAnyNode(graph, subject_ref)) return false;
            if (!graphHasEdge(graph, .blocked_by, subject_ref, blocker_ref)) return false;
        }
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
    return policySummariesEqual(actual, policy.policySummary());
}

fn policySummariesEqual(actual: PolicySummary, expected: PolicySummary) bool {
    return actual.policy_domain == expected.policy_domain and
        actual.policy_fingerprint == expected.policy_fingerprint and
        std.mem.eql(u8, actual.policy_label, expected.policy_label);
}

fn graphIntrinsicBoundariesAllowedByPolicy(report: BoundaryClosureReport, graph: BoundaryGraph, policy: BoundaryClosurePolicy, require_world_port: bool) bool {
    for (graph.edges) |edge| {
        if (edge.kind != .intrinsic_boundary) continue;
        if (!refsContain(report.host_intrinsic_refs, edge.to)) return false;
        if (!graphHasNode(graph, .host_intrinsic, edge.to)) return false;
        if (!graphHasNode(graph, .operation_site, edge.from) and !graphHasNode(graph, .after_site, edge.from)) return false;
        if (!require_world_port and policy.allowsHostIntrinsicRef(edge.to)) continue;
        if (!graphShapeHasAllowedWorldPortForIntrinsic(report, graph, policy, edge.from, edge.to)) return false;
    }
    return true;
}

fn graphShapeHasAllowedWorldPortForIntrinsic(report: BoundaryClosureReport, graph: BoundaryGraph, policy: BoundaryClosurePolicy, shape_ref: Ref, intrinsic_ref: Ref) bool {
    if (!policy.allow_world_ports or report.open_world_port_count == 0) return false;
    for (report.world_port_refs, report.world_port_intrinsic_refs) |world_port_ref, paired_intrinsic_ref| {
        if (paired_intrinsic_ref.domain_id != domains.host_intrinsic.id) continue;
        if (!paired_intrinsic_ref.eql(intrinsic_ref)) continue;
        if (!policy.allowsWorldPortRef(world_port_ref)) continue;
        if (!graphHasEdge(graph, .world_port_exposes, intrinsic_ref, world_port_ref)) continue;
        if (!graphHasEdge(graph, .opens_obligation, shape_ref, world_port_ref)) continue;
        if (!graphHasEdge(graph, .intrinsic_boundary, shape_ref, intrinsic_ref)) continue;
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
            .provider_manifest,
            .provider_offer,
            .provider_program_mapping,
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
        if (graphTreatyPlanOutgoingCountForShape(graph, edge.from) != 1) return false;
        if (graphTreatyPlanIncomingCountForPlan(graph, edge.to) != 1) return false;
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

fn graphRouteEdgesMatchSelectedRef(graph: BoundaryGraph, kind: BoundaryGraph.EdgeKind, target_kind: BoundaryGraph.NodeKind, shape_ref: Ref, selected_ref: ?Ref) bool {
    var count: usize = 0;
    for (graph.edges) |edge| {
        if (edge.kind != kind or !edge.from.eql(shape_ref)) continue;
        count += 1;
        if (!graphHasNode(graph, target_kind, edge.to)) return false;
        const expected_ref = selected_ref orelse return false;
        if (!edge.to.eql(expected_ref)) return false;
    }
    if (selected_ref) |expected_ref| {
        return count == 1 and graphHasNode(graph, target_kind, expected_ref);
    }
    return count == 0;
}

fn graphProviderOfferMatchesSelectedRoute(graph: BoundaryGraph, shape_ref: Ref, provider_ref: Ref, offer_ref: Ref) bool {
    if (provider_ref.domain_id != domains.provider_manifest.id) return false;
    if (offer_ref.domain_id != domains.provider_offer.id) return false;
    if (!graphHasNode(graph, .provider_manifest, provider_ref)) return false;
    if (!graphHasNode(graph, .provider_offer, offer_ref)) return false;
    if (!graphHasEdge(graph, .handled_by_provider, shape_ref, offer_ref)) return false;
    if (!graphHasEdge(graph, .provider_advertises_offer, provider_ref, offer_ref)) return false;
    return true;
}

fn staticTreatyPlansMatchCertificate(
    graph: BoundaryGraph,
    report: BoundaryClosureReport,
    policy: BoundaryClosurePolicy,
    blocker_refs: []const Ref,
    derive_blocker_refs: bool,
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
    var ambiguity_count: usize = 0;
    if (!providerProgramRefsAttestedByPlans(report.provider_program_refs, plans)) return false;
    if (!graphProviderProgramEdgesAttestedByPlans(graph, report, plans)) return false;
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
        if (plan.source_shape.fingerprint != plan.source_shape.computeFingerprint()) return false;
        if (!plan.evidenceRef().eql(plan_ref)) return false;
        if (!staticTreatyPlanBlockersMatchReport(graph, report, blocker_refs, derive_blocker_refs, plan)) return false;

        const shape_ref = plan.source_shape.evidenceRef();
        if (!graphHasNode(graph, .operation_site, shape_ref) and !graphHasNode(graph, .after_site, shape_ref)) return false;
        if (!graphHasEdge(graph, .treaty_planned, shape_ref, plan_ref)) return false;
        if (!graphRootYieldEdgesMatchShape(graph, shape_ref, plan.source_shape)) return false;
        if (!graphRouteEdgesMatchSelectedRef(graph, .handled_by_provider, .provider_offer, shape_ref, plan.selected_provider_offer_ref)) return false;
        if (!graphRouteEdgesMatchSelectedRef(graph, .authorized_by_capability, .capability_grant, shape_ref, plan.selected_capability_ref)) return false;
        if (!graphRouteEdgesMatchSelectedRef(graph, .adapted_by_morphism, .morphism_offer, shape_ref, plan.selected_morphism_ref)) return false;
        if (policy.require_static_treaty_plans and plan.selected_provider_offer_ref == null and !hasErrorClosureBlockers(plan.blockers)) return false;
        if (plan.selected_provider_offer_ref) |offer_ref| {
            const provider_ref = plan.selected_provider_ref orelse return false;
            if (plan.selected_capability_ref == null) return false;
            if (!graphProviderOfferMatchesSelectedRoute(graph, shape_ref, provider_ref, offer_ref)) return false;
        } else if (plan.selected_provider_ref != null) {
            return false;
        }
        if (plan.selected_provider_ref) |provider_ref| {
            if (provider_ref.domain_id != domains.provider_manifest.id) return false;
        }
        if (!staticTreatyProviderProgramProofMatches(graph, report, plan, plans)) return false;
        if (plan.selected_capability_ref) |capability_ref| {
            if (capability_ref.domain_id != domains.capability.id) return false;
            if (!graphHasNode(graph, .capability_grant, capability_ref)) return false;
        }
        if (plan.selected_morphism_ref) |morphism_ref| {
            if (morphism_ref.domain_id != domains.morphism_offer.id) return false;
            if (!graphHasNode(graph, .morphism_offer, morphism_ref)) return false;
        }
        if (plan.selected_intrinsic_ref) |intrinsic_ref| {
            if (intrinsic_ref.domain_id != domains.host_intrinsic.id) return false;
            if (!graphHasNode(graph, .host_intrinsic, intrinsic_ref)) return false;
            if (!graphHasEdge(graph, .intrinsic_boundary, shape_ref, intrinsic_ref)) return false;
        }
        if (plan.selected_morphism_intrinsic_ref) |intrinsic_ref| {
            const morphism_body = plan.selected_morphism_semantic_body orelse return false;
            if (plan.selected_morphism_ref == null or morphism_body != .host_intrinsic) return false;
            if (intrinsic_ref.domain_id != domains.host_intrinsic.id) return false;
            if (!graphHasNode(graph, .host_intrinsic, intrinsic_ref)) return false;
            if (!graphHasEdge(graph, .intrinsic_boundary, shape_ref, intrinsic_ref)) return false;
        }
        const selected_intrinsic_count = selectedPlanHostIntrinsicCount(plan);
        if (plan.selected_semantic_body == .host_intrinsic and plan.selected_intrinsic_ref == null) return false;
        if (plan.selected_morphism_semantic_body) |morphism_body| {
            if (morphism_body == .host_intrinsic and plan.selected_morphism_intrinsic_ref == null) return false;
        }
        if (graphHostIntrinsicEdgeCountForShape(graph, report, shape_ref) != selected_intrinsic_count) return false;
        const selected_unknown_body_count = selectedPlanUnknownBodyCount(plan);
        if (selected_unknown_body_count != 0) {
            if (!refsContain(report.unknown_refs, shape_ref)) return false;
            unknown_body_count += selected_unknown_body_count;
        }

        const has_world_port = graphShapeHasWorldPort(graph, report, shape_ref);
        count_ambiguity_blockers: for (plan.blockers) |closure_blocker| {
            if (has_world_port and boundaryStaticTreatyRequirementBlocker(closure_blocker.tag)) continue :count_ambiguity_blockers;
            if (closure_blocker.tag == .ambiguous_static_treaty_plan) ambiguity_count += 1;
        }
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
        ambiguity_count == report.ambiguity_count and
        boundary_native_route_count == report.boundary_native_route_count and
        declarative_route_count == report.declarative_route_count and
        residualized_pipeline_route_count == report.residualized_pipeline_route_count and
        intrinsic_route_count == report.intrinsic_route_count;
}

fn staticTreatyPlansRespectDepthPolicy(
    graph: BoundaryGraph,
    report: BoundaryClosureReport,
    policy: BoundaryClosurePolicy,
    plans: []const BoundaryStaticTreatyPlan,
) bool {
    for (plans) |plan| {
        const shape_ref = plan.source_shape.evidenceRef();
        if (graphHasAttestedProviderProgramYield(graph, report, shape_ref)) continue;
        if (!selectedProviderProgramDepthWithinPolicy(graph, report, policy, plans, plan, 0)) return false;
    }
    return true;
}

fn selectedProviderProgramDepthWithinPolicy(
    graph: BoundaryGraph,
    report: BoundaryClosureReport,
    policy: BoundaryClosurePolicy,
    plans: []const BoundaryStaticTreatyPlan,
    plan: BoundaryStaticTreatyPlan,
    depth: usize,
) bool {
    if (plan.selected_semantic_body != .boundary_program) return true;
    const program_ref = plan.selected_provider_program_ref orelse return true;
    if (depth > plans.len) return reportHasProviderProgramTraversalBlockerFor(report, program_ref);
    if (depth >= policy.max_nested_provider_depth or depth >= policy.max_depth) {
        return reportHasProviderProgramTraversalBlockerFor(report, program_ref);
    }

    for (graph.edges) |edge| {
        if (edge.kind != .provider_program_yields or !edge.from.eql(program_ref)) continue;
        const nested_plan = staticTreatyPlanForShapeRef(plans, edge.to) orelse
            return reportHasProviderProgramTraversalBlockerFor(report, program_ref);
        if (!selectedProviderProgramDepthWithinPolicy(graph, report, policy, plans, nested_plan, depth + 1)) return false;
    }
    return true;
}

fn staticTreatyPlanForShapeRef(plans: []const BoundaryStaticTreatyPlan, shape_ref: Ref) ?BoundaryStaticTreatyPlan {
    for (plans) |plan| {
        if (plan.source_shape.evidenceRef().eql(shape_ref)) return plan;
    }
    return null;
}

fn providerProgramRefsAttestedByPlans(provider_program_refs: []const Ref, plans: []const BoundaryStaticTreatyPlan) bool {
    provider_refs: for (provider_program_refs) |provider_program_ref| {
        selected_plans: for (plans) |plan| {
            if (plan.selected_semantic_body != .boundary_program) continue :selected_plans;
            const selected_ref = plan.selected_provider_program_ref orelse continue :selected_plans;
            if (selected_ref.eql(provider_program_ref)) continue :provider_refs;
        }
        return false;
    }
    return true;
}

fn staticTreatyProviderProgramProofMatches(graph: BoundaryGraph, report: BoundaryClosureReport, plan: BoundaryStaticTreatyPlan, plans: []const BoundaryStaticTreatyPlan) bool {
    if (plan.selected_semantic_body != .boundary_program) {
        return plan.selected_provider_program_ref == null and
            plan.selected_provider_program_mapping_fingerprint == null and
            plan.selected_provider_program_request_mapping_tag == null and
            plan.selected_provider_program_result_mapping_tag == null and
            plan.selected_provider_program_mapping_support_fingerprint == null and
            plan.selected_provider_program_effect_shape_count == null and
            plan.selected_provider_program_effect_shape_fingerprint == null;
    }
    const program_ref = plan.selected_provider_program_ref orelse return false;
    if (program_ref.domain_id != domains.program_plan.id) return false;
    _ = plan.selected_provider_program_mapping_fingerprint orelse return false;
    _ = plan.selected_provider_program_request_mapping_tag orelse return false;
    _ = plan.selected_provider_program_result_mapping_tag orelse return false;
    const mapping_support_fingerprint = plan.selected_provider_program_mapping_support_fingerprint orelse return false;
    if ((plan.selectedProviderProgramMappingSupportFingerprint() orelse return false) != mapping_support_fingerprint) return false;
    const effect_shape_count = plan.selected_provider_program_effect_shape_count orelse return false;
    const effect_shape_fingerprint = plan.selected_provider_program_effect_shape_fingerprint orelse return false;
    if (refsContain(report.provider_program_refs, program_ref)) {
        const mapping_support_ref = refForProviderProgramMapping(mapping_support_fingerprint);
        if (!graphHasNode(graph, .provider_program_mapping, mapping_support_ref)) return reportHasProviderProgramMissingBlocker(report, plan);
        if (!graphProviderProgramMappingEdgeMatches(graph, program_ref, mapping_support_ref)) return reportHasProviderProgramMissingBlocker(report, plan);
        if (!graphHasNode(graph, .provider_program, program_ref)) return false;
        const graph_effect_shapes = graphProviderProgramEffectShapeProof(graph, program_ref, plans) orelse return false;
        if (graph_effect_shapes.count == effect_shape_count and graph_effect_shapes.fingerprint == effect_shape_fingerprint) return true;
        return reportHasProviderProgramMissingBlocker(report, plan);
    }
    return reportHasProviderProgramMissingBlocker(report, plan);
}

fn graphProviderProgramMappingEdgeMatches(graph: BoundaryGraph, program_ref: Ref, mapping_ref: Ref) bool {
    var found = false;
    for (graph.edges) |edge| {
        if (edge.kind != .provider_program_mapped_by or !edge.from.eql(program_ref)) continue;
        if (!edge.to.eql(mapping_ref)) continue;
        if (!graphHasNode(graph, .provider_program_mapping, edge.to)) return false;
        found = true;
    }
    return found;
}

fn graphProviderProgramEdgesAttestedByPlans(graph: BoundaryGraph, report: BoundaryClosureReport, plans: []const BoundaryStaticTreatyPlan) bool {
    for (graph.edges) |edge| {
        if (edge.kind == .provider_program_mapped_by) {
            if (!refsContain(report.provider_program_refs, edge.from)) return false;
            if (!graphHasNode(graph, .provider_program, edge.from)) return false;
            if (!graphHasNode(graph, .provider_program_mapping, edge.to)) return false;
            if (!providerProgramMappingTargetMatchesPlan(edge.from, edge.to, plans)) return false;
        } else if (edge.kind == .provider_program_yields) {
            if (!refsContain(report.provider_program_refs, edge.from)) return false;
            if (!graphHasNode(graph, .provider_program, edge.from)) return false;
            if (!graphHasNode(graph, .operation_site, edge.to) and !graphHasNode(graph, .after_site, edge.to)) return false;
            if (!providerProgramYieldTargetMatchesPlan(edge.from, edge.to, plans)) return false;
        }
    }
    return true;
}

fn graphProviderProgramEffectShapeProof(graph: BoundaryGraph, program_ref: Ref, plans: []const BoundaryStaticTreatyPlan) ?struct {
    count: u64,
    fingerprint: u64,
} {
    var count: usize = 0;
    for (graph.edges, 0..) |edge, index| {
        if (edge.kind != .provider_program_yields or !edge.from.eql(program_ref)) continue;
        for (graph.edges[0..index]) |prior_edge| {
            if (prior_edge.kind == .provider_program_yields and
                prior_edge.from.eql(program_ref) and
                prior_edge.to.eql(edge.to))
            {
                return null;
            }
        }
        if (!graphHasNode(graph, .operation_site, edge.to) and !graphHasNode(graph, .after_site, edge.to)) return null;
        if (!providerProgramYieldTargetMatchesPlan(program_ref, edge.to, plans)) return null;
        count += 1;
    }

    var builder = FingerprintBuilder.init(domains.boundary_effect_shape);
    builder.fieldUsize("shape_count", count);
    var emitted_rank: usize = 0;
    while (emitted_rank < count) : (emitted_rank += 1) {
        var selected_ref: ?Ref = null;
        provider_edges: for (graph.edges, 0..) |edge, index| {
            if (edge.kind != .provider_program_yields or !edge.from.eql(program_ref)) continue :provider_edges;
            var rank: usize = 0;
            other_provider_edges: for (graph.edges, 0..) |other_edge, other_index| {
                if (other_edge.kind != .provider_program_yields or !other_edge.from.eql(program_ref)) continue :other_provider_edges;
                if (refLessForCanonicalSet(other_edge.to, edge.to) or (other_edge.to.eql(edge.to) and other_index < index)) rank += 1;
            }
            if (rank == emitted_rank) {
                selected_ref = edge.to;
                break;
            }
        }
        builder.fieldRef("shape", selected_ref.?);
    }

    return .{
        .count = @intCast(count),
        .fingerprint = builder.finish(),
    };
}

fn providerProgramMappingTargetMatchesPlan(program_ref: Ref, mapping_ref: Ref, plans: []const BoundaryStaticTreatyPlan) bool {
    for (plans) |plan| {
        if (plan.selected_semantic_body != .boundary_program) continue;
        const selected_program_ref = plan.selected_provider_program_ref orelse continue;
        if (!selected_program_ref.eql(program_ref)) continue;
        const selected_mapping_support_fingerprint = plan.selected_provider_program_mapping_support_fingerprint orelse continue;
        const selected_mapping_support_ref = refForProviderProgramMapping(selected_mapping_support_fingerprint);
        if (selected_mapping_support_ref.eql(mapping_ref)) return true;
    }
    return false;
}

fn providerProgramYieldTargetMatchesPlan(program_ref: Ref, shape_ref: Ref, plans: []const BoundaryStaticTreatyPlan) bool {
    var match_count: usize = 0;
    for (plans) |plan| {
        if (!plan.source_shape.evidenceRef().eql(shape_ref)) continue;
        if (!rootRefMatchesBoundaryShape(program_ref, plan.source_shape)) return false;
        match_count += 1;
    }
    return match_count == 1;
}

fn reportHasProviderProgramMissingBlocker(report: BoundaryClosureReport, plan: BoundaryStaticTreatyPlan) bool {
    const shape_ref = plan.source_shape.evidenceRef();
    const program_ref = plan.selected_provider_program_ref;
    for (report.blockers) |blocker| {
        if (blocker.subject) |subject| {
            if (std.mem.eql(u8, blocker.tag, @tagName(BoundaryClosureBlockerTag.provider_program_contract_missing)) and
                (subject.eql(shape_ref) or (program_ref != null and subject.eql(program_ref.?))))
            {
                return true;
            }
            if (std.mem.eql(u8, blocker.tag, @tagName(BoundaryClosureBlockerTag.provider_program_nested_unknown)) or
                std.mem.eql(u8, blocker.tag, @tagName(BoundaryClosureBlockerTag.depth_limit_exceeded)) or
                std.mem.eql(u8, blocker.tag, @tagName(BoundaryClosureBlockerTag.cycle_detected)))
            {
                if (program_ref) |ref| {
                    if (subject.eql(ref)) return true;
                }
            }
        }
    }
    return false;
}

fn staticTreatyPlanBlockersMatchReport(
    graph: BoundaryGraph,
    report: BoundaryClosureReport,
    blocker_refs: []const Ref,
    derive_blocker_refs: bool,
    plan: BoundaryStaticTreatyPlan,
) bool {
    const shape_ref = plan.source_shape.evidenceRef();
    const has_world_port = graphShapeHasWorldPort(graph, report, shape_ref);
    for (plan.blockers) |closure_blocker| {
        if (has_world_port and boundaryStaticTreatyRequirementBlocker(closure_blocker.tag)) continue;
        const blocker = closure_blocker.toEvidenceBlocker();
        const blocker_ref = refForBoundaryClosureBlocker(blocker);
        if (!derive_blocker_refs and !refsContain(blocker_refs, blocker_ref)) return false;
        if (!blockersContain(report.blockers, blocker)) return false;
        if (!graphHasNode(graph, .blocker, blocker_ref)) return false;
        if (blocker.subject) |subject_ref| {
            if (blockerSubjectMustHaveGraphNode(blocker) and !graphHasAnyNode(graph, subject_ref)) return false;
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

fn selectedPlanUnknownBodyCount(plan: BoundaryStaticTreatyPlan) usize {
    if (plan.selected_provider_offer_ref == null) return 0;
    var count: usize = 0;
    if (plan.selected_semantic_body == .unknown) count += 1;
    if (plan.selected_morphism_semantic_body) |body| {
        if (body == .unknown) count += 1;
    }
    return count;
}

fn blockerSubjectMustHaveGraphNode(blocker: Blocker) bool {
    if (std.mem.eql(u8, blocker.short_code, @tagName(BoundaryClosureBlockerTag.root_program_missing))) {
        if (blocker.subject) |subject_ref| return subject_ref.domain_id != domains.program_plan.id;
    }
    if (std.mem.eql(u8, blocker.short_code, @tagName(BoundaryClosureBlockerTag.stale_effect_shape))) return false;
    if (std.mem.eql(u8, blocker.short_code, @tagName(BoundaryClosureBlockerTag.stale_world_port))) return false;
    if (std.mem.eql(u8, blocker.short_code, @tagName(BoundaryClosureBlockerTag.provider_program_nested_unknown))) return false;
    if (std.mem.eql(u8, blocker.short_code, @tagName(BoundaryClosureBlockerTag.depth_limit_exceeded))) {
        if (blocker.subject) |subject_ref| return subject_ref.domain_id != domains.program_plan.id;
    }
    if (std.mem.eql(u8, blocker.short_code, @tagName(BoundaryClosureBlockerTag.provider_program_contract_missing))) {
        if (blocker.subject) |subject_ref| return subject_ref.domain_id != domains.program_plan.id;
    }
    return true;
}

fn reportHasRootProgramMissingBlocker(report: BoundaryClosureReport, root_ref: Ref) bool {
    for (report.blockers) |blocker| {
        if (!std.mem.eql(u8, blocker.tag, @tagName(BoundaryClosureBlockerTag.root_program_missing))) continue;
        const subject_ref = blocker.subject orelse continue;
        if (subject_ref.eql(root_ref)) return true;
    }
    return false;
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
            if (blockerSubjectMustHaveGraphNode(blocker) and !graphHasAnyNode(graph, subject_ref)) return false;
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

fn graphHostIntrinsicRefsMatchReport(graph: BoundaryGraph, report: BoundaryClosureReport, plan_refs: []const Ref) bool {
    for (report.host_intrinsic_refs) |intrinsic_ref| {
        if (intrinsic_ref.domain_id != domains.host_intrinsic.id) return false;
        if (!graphHasNode(graph, .host_intrinsic, intrinsic_ref)) return false;
        if (!graphHasSelectedPlanIntrinsicBoundary(graph, plan_refs, intrinsic_ref)) return false;
    }
    return true;
}

fn graphHasSelectedPlanIntrinsicBoundary(graph: BoundaryGraph, plan_refs: []const Ref, intrinsic_ref: Ref) bool {
    for (graph.edges) |edge| {
        if (edge.kind != .intrinsic_boundary or !edge.to.eql(intrinsic_ref)) continue;
        if (!graphHasNode(graph, .operation_site, edge.from) and !graphHasNode(graph, .after_site, edge.from)) continue;
        if (graphShapeHasSelectedPlanRef(graph, plan_refs, edge.from)) return true;
    }
    return false;
}

fn graphShapeHasSelectedPlanRef(graph: BoundaryGraph, plan_refs: []const Ref, shape_ref: Ref) bool {
    for (plan_refs) |plan_ref| {
        if (graphHasEdge(graph, .treaty_planned, shape_ref, plan_ref)) return true;
    }
    return false;
}

fn graphRootYieldEdgesMatchReport(graph: BoundaryGraph, report: BoundaryClosureReport) bool {
    for (report.effect_free_root_refs) |effect_free_root_ref| {
        if (effect_free_root_ref.domain_id != domains.program_plan.id) return false;
        if (!refsContain(report.root_program_refs, effect_free_root_ref) and
            !reportHasRootProgramMissingBlocker(report, effect_free_root_ref))
        {
            return false;
        }
    }
    for (report.root_program_refs) |root_ref| {
        if (root_ref.domain_id != domains.program_plan.id) return false;
        if (refsContain(report.effect_free_root_refs, root_ref)) {
            if (graphHasOutgoingEdge(graph, .root_yields, root_ref)) return false;
            continue;
        }
        if (!graphHasOutgoingEdge(graph, .root_yields, root_ref)) return false;
    }
    for (graph.edges) |edge| {
        if (edge.kind != .root_yields) continue;
        if (!refsContain(report.root_program_refs, edge.from)) return false;
        if (!graphHasNode(graph, .operation_site, edge.to) and !graphHasNode(graph, .after_site, edge.to)) return false;
    }
    for (graph.nodes) |node| {
        if (node.kind != .operation_site and node.kind != .after_site) continue;
        if (graphHasAttestedProviderProgramYield(graph, report, node.ref)) continue;
        if (report.root_program_refs.len == 0) continue;
        if (!graphHasIncomingEdge(graph, .root_yields, node.ref)) return false;
    }
    return true;
}

fn graphRootYieldEdgesMatchShape(graph: BoundaryGraph, shape_ref: Ref, shape: BoundaryEffectShape) bool {
    for (graph.edges) |edge| {
        if (edge.kind != .root_yields or !edge.to.eql(shape_ref)) continue;
        if (!rootRefMatchesBoundaryShape(edge.from, shape)) return false;
    }
    return true;
}

fn rootRefMatchesBoundaryShape(root_ref: Ref, shape: BoundaryEffectShape) bool {
    if (root_ref.domain_id != domains.program_plan.id) return false;
    if (shape.plan_hash == 0 or root_ref.fingerprint != shape.plan_hash) return false;
    const root_label = root_ref.label orelse return false;
    return std.mem.eql(u8, root_label, shape.program_label);
}

fn graphWorldPortEdgesMatchReport(graph: BoundaryGraph, report: BoundaryClosureReport) bool {
    for (report.world_port_refs, report.world_port_intrinsic_refs) |world_port_ref, paired_ref| {
        if (paired_ref.domain_id == domains.host_intrinsic.id) {
            if (!graphHasEdge(graph, .world_port_exposes, paired_ref, world_port_ref)) return false;
            if (!graphHasWorldPortObligationForPair(graph, paired_ref, world_port_ref)) return false;
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
    if (!graphHasNode(graph, .operation_site, shape_ref) and !graphHasNode(graph, .after_site, shape_ref)) return false;
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

fn refsHaveDomain(refs: []const Ref, domain_id: Domain.Id) bool {
    for (refs) |ref| {
        if (ref.domain_id != domain_id) return false;
    }
    return true;
}

fn graphHasAnyNode(graph: BoundaryGraph, ref: Ref) bool {
    for (graph.nodes) |node| {
        if (node.ref.eql(ref)) return true;
    }
    return false;
}

fn graphHasNode(graph: BoundaryGraph, kind: BoundaryGraph.NodeKind, ref: Ref) bool {
    for (graph.nodes) |node| {
        if (node.kind == kind and node.ref.eql(ref)) return true;
    }
    return false;
}

fn graphHostIntrinsicEdgeCountForShape(graph: BoundaryGraph, report: BoundaryClosureReport, shape_ref: Ref) usize {
    var count: usize = 0;
    for (graph.edges) |edge| {
        if (edge.kind != .intrinsic_boundary or !edge.from.eql(shape_ref)) continue;
        if (!refsContain(report.host_intrinsic_refs, edge.to)) continue;
        if (!graphHasNode(graph, .host_intrinsic, edge.to)) continue;
        count += 1;
    }
    return count;
}

fn graphHasIncomingEdge(graph: BoundaryGraph, kind: BoundaryGraph.EdgeKind, to: Ref) bool {
    for (graph.edges) |edge| {
        if (edge.kind == kind and edge.to.eql(to)) return true;
    }
    return false;
}

fn graphHasAttestedProviderProgramYield(graph: BoundaryGraph, report: BoundaryClosureReport, shape_ref: Ref) bool {
    for (graph.edges) |edge| {
        if (edge.kind != .provider_program_yields or !edge.to.eql(shape_ref)) continue;
        if (!refsContain(report.provider_program_refs, edge.from)) continue;
        if (graphHasNode(graph, .provider_program, edge.from)) return true;
    }
    return false;
}

fn graphHasWorldPortObligationForPair(graph: BoundaryGraph, intrinsic_ref: Ref, world_port_ref: Ref) bool {
    for (graph.edges) |edge| {
        if (edge.kind != .opens_obligation or !edge.to.eql(world_port_ref)) continue;
        if (!graphHasNode(graph, .operation_site, edge.from) and !graphHasNode(graph, .after_site, edge.from)) continue;
        if (graphHasEdge(graph, .intrinsic_boundary, edge.from, intrinsic_ref)) return true;
    }
    return false;
}

fn graphTreatyPlanIncomingCountForPlan(graph: BoundaryGraph, to: Ref) usize {
    var count: usize = 0;
    for (graph.edges) |edge| {
        if (edge.kind == .treaty_planned and edge.to.eql(to)) count += 1;
    }
    return count;
}

fn graphHasIncomingTreatyPlanFromShape(graph: BoundaryGraph, to: Ref) bool {
    for (graph.edges) |edge| {
        if (edge.kind != .treaty_planned or !edge.to.eql(to)) continue;
        if (graphHasNode(graph, .operation_site, edge.from) or graphHasNode(graph, .after_site, edge.from)) return true;
    }
    return false;
}

fn graphTreatyPlanOutgoingCountForShape(graph: BoundaryGraph, from: Ref) usize {
    var count: usize = 0;
    for (graph.edges) |edge| {
        if (edge.kind == .treaty_planned and edge.from.eql(from)) count += 1;
    }
    return count;
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
    if (!policy.require_all_effect_shapes_closed) {
        return policy.allowed_world_port_fingerprints.len == 0 and
            policy.allowed_world_port_kinds.len == 0 and
            policy.allowed_world_port_labels.len == 0;
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
